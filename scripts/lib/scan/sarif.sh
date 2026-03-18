convert_bandit_json_to_sarif() {
  local input_json="$1"
  local output_sarif="$2"
  python3 - "$input_json" "$output_sarif" <<'PY'
import json
import os
import re
import sys
from urllib.parse import urlparse

in_path, out_path = sys.argv[1], sys.argv[2]

with open(in_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

level_map = {"HIGH": "error", "MEDIUM": "warning", "LOW": "note"}
sev_map = {"HIGH": "8.0", "MEDIUM": "5.0", "LOW": "2.0"}

rules = {}
results = []

for finding in data.get("results", []):
    rule_id = finding.get("test_id") or "bandit-rule"
    issue_text = finding.get("issue_text") or "Bandit finding"
    issue_severity = (finding.get("issue_severity") or "LOW").upper()
    issue_confidence = (finding.get("issue_confidence") or "").lower()
    filename = finding.get("filename") or "."
    line = finding.get("line_number") or 1
    cwe = ((finding.get("issue_cwe") or {}).get("id"))

    if rule_id not in rules:
        tags = ["security", "bandit"]
        if cwe:
            tags.append(f"CWE-{cwe}")
        rules[rule_id] = {
            "id": rule_id,
            "name": finding.get("test_name") or rule_id,
            "shortDescription": {"text": issue_text},
            "properties": {"tags": tags},
        }

    result = {
        "ruleId": rule_id,
        "level": level_map.get(issue_severity, "warning"),
        "message": {"text": issue_text},
        "locations": [
            {
                "physicalLocation": {
                    "artifactLocation": {"uri": filename},
                    "region": {"startLine": int(line)},
                }
            }
        ],
        "properties": {
            "security-severity": sev_map.get(issue_severity, "5.0"),
        },
    }
    if issue_confidence:
        result["properties"]["precision"] = issue_confidence
    results.append(result)

sarif = {
    "version": "2.1.0",
    "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
    "runs": [
        {
            "tool": {
                "driver": {
                    "name": "Bandit",
                    "informationUri": "https://bandit.readthedocs.io/",
                    "rules": list(rules.values()),
                }
            },
            "results": results,
        }
    ],
}

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(sarif, fh)
PY
}

normalize_report_path() {
  local path="$1"
  if [[ "$path" == "$repo/"* ]]; then
    print -r -- "${path#$repo/}"
  else
    print -r -- "$path"
  fi
}

sarif_result_count() {
  local sarif_path="$1"
  python3 - "$sarif_path" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

total = 0
for run in data.get("runs", []):
    total += len(run.get("results") or [])
print(total)
PY
}

infer_external_engine_from_sarif() {
  local sarif_path="$1"
  local base lower
  base="$(basename "$sarif_path")"
  lower="${(L)base}"

  case "$lower" in
    *semgrep*|*opengrep*) print -r -- "Semgrep"; return 0 ;;
    *hadolint*) print -r -- "Hadolint"; return 0 ;;
    *gosec*) print -r -- "Gosec"; return 0 ;;
    *bandit*) print -r -- "Bandit"; return 0 ;;
    *codeql*) print -r -- "CodeQL"; return 0 ;;
    *gitleaks*) print -r -- "Gitleaks"; return 0 ;;
    *checkov*) print -r -- "Checkov"; return 0 ;;
    *tfsec*) print -r -- "TFSec"; return 0 ;;
    *trivy*) print -r -- "Trivy"; return 0 ;;
    *osv*scanner*|*osv*) print -r -- "OSV-Scanner"; return 0 ;;
  esac

  python3 - "$sarif_path" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

mapping = {
    "semgrep": "Semgrep",
    "opengrep": "Semgrep",
    "hadolint": "Hadolint",
    "gosec": "Gosec",
    "bandit": "Bandit",
    "codeql": "CodeQL",
    "gitleaks": "Gitleaks",
    "checkov": "Checkov",
    "tfsec": "TFSec",
    "trivy": "Trivy",
    "osv": "OSV-Scanner",
}

for run in data.get("runs", []):
    driver_name = (((run.get("tool") or {}).get("driver") or {}).get("name") or "").strip()
    if not driver_name:
        continue
    lowered = driver_name.lower()
    for needle, canonical in mapping.items():
        if needle in lowered:
            print(canonical)
            sys.exit(0)
    print(driver_name)
    sys.exit(0)
print("")
PY
}

spotbugs_result_count() {
  local report_path="$1"
  python3 - "$report_path" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
try:
    tree = ET.parse(path)
    root = tree.getroot()
    # FindBugInstance tags
    bugs = root.findall(".//BugInstance")
    print(len(bugs))
except Exception:
    print(0)
PY
}

collect_expected_external_engines() {
  expected_external_engines=()
  local report abs_path count engine

  for report in "${sarif_reports[@]}"; do
    abs_path="$report"
    [[ "$abs_path" == /* ]] || abs_path="$repo/$report"
    [[ -f "$abs_path" ]] || continue

    count="$(sarif_result_count "$abs_path" 2>/dev/null || print -r -- "0")"
    [[ "$count" == <-> ]] || count="0"
    (( count > 0 )) || continue

    engine="$(infer_external_engine_from_sarif "$abs_path" 2>/dev/null || true)"
    [[ -n "$engine" ]] || continue
    expected_external_engines[$engine]=$(( ${expected_external_engines[$engine]:-0} + count ))
  done

  for report in "${spotbugs_reports[@]}"; do
    abs_path="$report"
    [[ "$abs_path" == /* ]] || abs_path="$repo/$report"
    [[ -f "$abs_path" ]] || continue

    count="$(spotbugs_result_count "$abs_path" 2>/dev/null || print -r -- "0")"
    [[ "$count" == <-> ]] || count="0"
    (( count > 0 )) || continue

    engine="FindSecBugs"
    expected_external_engines[$engine]=$(( ${expected_external_engines[$engine]:-0} + count ))
  done
}

verify_external_issue_imports() {
  [[ "$dry_run" == "true" ]] && return 0
  (( ${#expected_external_engines[@]} > 0 )) || return 0
  [[ -n "$scan_started_at" ]] || return 0

  typeset -a expected_pairs
  local engine count
  for engine count in "${(@kv)expected_external_engines}"; do
    expected_pairs+=("${engine}:${count}")
  done

  local check_output
  if ! check_output="$(python3 - "$host_url" "$token" "$project_key" "$scan_started_at" "${expected_pairs[@]}" <<'PY'
import base64
import datetime as dt
import json
import sys
import urllib.parse
import urllib.request

host_url = sys.argv[1].rstrip("/")
token = sys.argv[2]
project_key = sys.argv[3]
scan_started_at = sys.argv[4]
expected_pairs = sys.argv[5:]

expected = {}
for pair in expected_pairs:
    engine, _, value = pair.partition(":")
    if not engine:
        continue
    try:
        expected[engine] = int(value)
    except ValueError:
        expected[engine] = 0

if not expected:
    print("external_import_check=SKIPPED expected=none")
    sys.exit(0)

auth = base64.b64encode(f"{token}:".encode("utf-8")).decode("ascii")
headers = {"Authorization": f"Basic {auth}"}

def parse_sonar_date(date_str):
    if not date_str:
        return None
    try:
        # SonarQube dates often look like 2024-03-14T15:46:25+0100
        # or with milliseconds: 2024-03-14T15:46:25.123+0100
        # Normalize: replace Z with +00:00, ensure colon in timezone offset
        import re
        normalized = date_str.replace("Z", "+00:00")
        if re.search(r"[+-]\d{4}$", normalized):
            normalized = normalized[:-2] + ":" + normalized[-2:]
        return dt.datetime.fromisoformat(normalized)
    except Exception:
        return None

try:
    threshold = parse_sonar_date(scan_started_at)
except Exception:
    threshold = None

if not threshold:
    print("external_import_check=SKIPPED threshold_parse_failed")
    sys.exit(0)

observed_total_raw = {}
observed_recent_raw = {}

page = 1
page_size = 500
total = None

while True:
    query = urllib.parse.urlencode(
        {
            "componentKeys": project_key,
            "additionalFields": "_all",
            "ps": page_size,
            "p": page,
        }
    )
    req = urllib.request.Request(f"{host_url}/api/issues/search?{query}", headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.load(resp)

    if total is None:
        total = int(payload.get("total", 0))

    for issue in payload.get("issues", []):
        engine = issue.get("externalRuleEngine")
        updated = issue.get("updateDate")
        if not engine:
            continue
        observed_total_raw[engine] = observed_total_raw.get(engine, 0) + 1
        
        updated_at = parse_sonar_date(updated)
        if updated_at and updated_at >= threshold:
            observed_recent_raw[engine] = observed_recent_raw.get(engine, 0) + 1

    if page * page_size >= total:
        break
    page += 1

aliases = {
    "Semgrep": ["Semgrep", "Semgrep OSS", "OpenGrep"],
    "CodeQL": ["CodeQL", "codeql"],
    "Gosec": ["Gosec", "gosec"],
    "Bandit": ["Bandit"],
    "Hadolint": ["Hadolint"],
    "Gitleaks": ["Gitleaks"],
    "Checkov": ["Checkov"],
    "TFSec": ["TFSec", "tfsec"],
    "Trivy": ["Trivy"],
    "OSV-Scanner": ["OSV-Scanner", "osv-scanner", "OSVScanner"],
    "FindSecBugs": ["FindSecBugs", "Find Security Bugs"],
}

def canonical_sum(name, observed):
    candidates = aliases.get(name, [name])
    total = 0
    for engine_name, count in observed.items():
        lower_engine = engine_name.lower()
        for candidate in candidates:
            lower_candidate = candidate.lower()
            if lower_engine == lower_candidate or lower_engine.startswith(lower_candidate + " "):
                total += count
                break
    return total

observed_total = {name: canonical_sum(name, observed_total_raw) for name in expected}
observed_recent = {name: canonical_sum(name, observed_recent_raw) for name in expected}

missing = [engine for engine, count in expected.items() if count > 0 and observed_total.get(engine, 0) == 0]
if missing:
    print(
        "external_import_check=FAILED "
        + "missing_engines="
        + ",".join(sorted(missing))
        + " expected="
        + json.dumps(expected, sort_keys=True)
        + " observed_total="
        + json.dumps(observed_total, sort_keys=True)
        + " observed_recent="
        + json.dumps(observed_recent, sort_keys=True)
    )
    sys.exit(3)

print(
    "external_import_check=OK "
    + "expected="
    + json.dumps(expected, sort_keys=True)
    + " observed_total="
    + json.dumps(observed_total, sort_keys=True)
    + " observed_recent="
    + json.dumps(observed_recent, sort_keys=True)
)
PY
)"; then
    if [[ "$security_tools_mode" == "required" ]]; then
      print -u2 -- "[scan][error] ${check_output}"
      return 1
    fi
    log_warn "${check_output}"
    return 0
  fi

  log_info "${check_output}"
  return 0
}

normalize_sarif_report() {
  local sarif_path="$1"
  python3 - "$sarif_path" "$repo" <<'PY'
import json
import os
import sys
from urllib.parse import urlparse

path = sys.argv[1]
repo_root = sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    raw = fh.read()

raw = raw.strip()
if not raw:
    sys.exit(1)

def try_parse(text):
    try:
        return json.loads(text)
    except Exception:
        return None

data = try_parse(raw)
if data is None:
    start = raw.find("{")
    end = raw.rfind("}")
    if start == -1 or end == -1 or end <= start:
        sys.exit(1)
    data = try_parse(raw[start : end + 1])
    if data is None:
        sys.exit(1)

if not isinstance(data, dict):
    sys.exit(1)

runs = data.get("runs")
if not isinstance(runs, list):
    runs = []
    data["runs"] = runs

line_count_cache = {}

def local_line_count(uri: str) -> int:
    if not isinstance(uri, str) or not uri.strip():
        return 0
    if uri in line_count_cache:
        return line_count_cache[uri]

    normalized = uri.strip()
    if normalized.startswith("file://"):
        normalized = urlparse(normalized).path
    elif not os.path.isabs(normalized):
        normalized = os.path.join(repo_root, normalized)

    try:
        with open(normalized, "rb") as fh:
            line_count = sum(1 for _ in fh)
    except OSError:
        line_count = 0

    line_count_cache[uri] = line_count
    return line_count

for run in runs:
    if not isinstance(run, dict):
        continue

    results = run.get("results")
    if not isinstance(results, list):
        run["results"] = []

    tool = run.get("tool")
    if not isinstance(tool, dict):
        tool = {}
        run["tool"] = tool

    driver = tool.get("driver")
    if not isinstance(driver, dict):
        driver = {}
        tool["driver"] = driver

    name = driver.get("name")
    if not isinstance(name, str) or not name.strip():
        driver["name"] = "ExternalTool"

    rules = driver.get("rules")
    if not isinstance(rules, list):
        driver["rules"] = []

    for result in run["results"]:
        if not isinstance(result, dict):
            continue
        locations = result.get("locations")
        if not isinstance(locations, list):
            continue
        for location in locations:
            if not isinstance(location, dict):
                continue
            physical = location.get("physicalLocation")
            if not isinstance(physical, dict):
                continue
            artifact = physical.get("artifactLocation")
            if not isinstance(artifact, dict):
                continue
            uri = artifact.get("uri")
            max_line = local_line_count(uri)
            if max_line <= 0:
                continue
            region = physical.get("region")
            if not isinstance(region, dict):
                region = {}
                physical["region"] = region
            start = region.get("startLine")
            try:
                start = int(start)
            except (TypeError, ValueError):
                start = 1
            if start < 1:
                start = 1
            if start > max_line:
                start = max_line
            region["startLine"] = start

            end = region.get("endLine")
            if end is not None:
                try:
                    end = int(end)
                except (TypeError, ValueError):
                    end = start
                if end < start:
                    end = start
                if end > max_line:
                    end = max_line
                region["endLine"] = end

if not isinstance(data.get("version"), str) or not data.get("version"):
    data["version"] = "2.1.0"

if "$schema" not in data:
    data["$schema"] = "https://json.schemastore.org/sarif-2.1.0.json"

with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh)
PY
}

record_sarif_report() {
  local report_path="$1"
  local normalized
  if [[ "$dry_run" != "true" && -f "$report_path" ]]; then
    if ! normalize_sarif_report "$report_path"; then
      if [[ "$security_tools_mode" == "required" ]]; then
        print -u2 -- "[scan][error] failed to normalize SARIF report: $report_path"
        exit 1
      fi
      log_warn "failed to normalize SARIF report, skipping import: $report_path"
      return 0
    fi
  fi
  normalized="$(normalize_report_path "$report_path")"
  sarif_reports+=("$normalized")
}

record_spotbugs_report() {
  local report_path="$1"
  local normalized
  normalized="$(normalize_report_path "$report_path")"
  spotbugs_reports+=("$normalized")
}
