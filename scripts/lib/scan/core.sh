urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

json_get() {
  local expr="$1"
  python3 -c "import json,sys; data=json.load(sys.stdin); print($expr)"
}

join_csv() {
  local IFS=","
  print -r -- "$*"
}

run_logged() {
  if [[ "$dry_run" == "true" ]]; then
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

log_info() {
  print -- "[scan] $*"
}

log_warn() {
  print -u2 -- "[scan][warn] $*"
}

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

command_version_line() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    print -r -- "missing"
    return 0
  fi

  local out
  out="$({ "$tool" --version 2>/dev/null || true; } | head -n 1 | tr -d '\r')"
  if [[ -n "$out" ]]; then
    print -r -- "$out"
    return 0
  fi

  out="$({ "$tool" version 2>/dev/null || true; } | head -n 1 | tr -d '\r')"
  if [[ -n "$out" ]]; then
    print -r -- "$out"
    return 0
  fi

  out="$({ "$tool" -V 2>/dev/null || true; } | head -n 1 | tr -d '\r')"
  if [[ -n "$out" ]]; then
    print -r -- "$out"
    return 0
  fi

  print -r -- "available"
}

write_run_status() {
  [[ "$run_status_initialized" == "true" ]] || return 0

  local tools_blob sarif_blob spotbugs_blob generated_blob
  local name state
  tools_blob=""
  for name state in "${(@kv)run_tool_status}"; do
    tools_blob+="${name}"$'\t'"${state}"$'\n'
  done
  sarif_blob="$(printf '%s\n' "${sarif_reports[@]}")"
  spotbugs_blob="$(printf '%s\n' "${spotbugs_reports[@]}")"
  generated_blob="$(printf '%s\n' "${generated_reports[@]}")"

  RUN_STATUS_FILE="$run_status_file" \
  RUN_ID="$run_id" \
  RUN_DIR="$run_dir" \
  RUN_REPO="$repo" \
  RUN_PROJECT_KEY="$project_key" \
  RUN_PROJECT_NAME="$project_name" \
  RUN_PROFILE="$resolved_profile" \
  RUN_PHASE="$run_phase" \
  RUN_STATE="$run_state" \
  RUN_MESSAGE="$run_message" \
  RUN_STARTED_AT="$run_started_at" \
  RUN_COMPLETED_AT="$run_completed_at" \
  RUN_RESULT="$run_result" \
  RUN_QUALITY_GATE="$quality_gate_status" \
  RUN_HOST_URL="$host_url" \
  RUN_ANALYSIS_ID="$last_analysis_id" \
  RUN_SCAN_PID="$scan_pid" \
  RUN_DRY_RUN="$dry_run" \
  RUN_TOOLS_BLOB="$tools_blob" \
  RUN_SARIF_BLOB="$sarif_blob" \
  RUN_SPOTBUGS_BLOB="$spotbugs_blob" \
  RUN_GENERATED_BLOB="$generated_blob" \
  python3 - <<'PY'
import datetime as dt
import json
import os
from pathlib import Path


def lines(name):
    raw = os.environ.get(name, "")
    return [line for line in raw.splitlines() if line.strip()]


def iso_now():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_iso(raw):
    raw = (raw or "").strip()
    if not raw:
        return None
    try:
        return dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


status_file = Path(os.environ["RUN_STATUS_FILE"])
status_file.parent.mkdir(parents=True, exist_ok=True)

started = parse_iso(os.environ.get("RUN_STARTED_AT", ""))
now = dt.datetime.now(dt.timezone.utc)
elapsed = None
if started is not None:
    elapsed = int((now - started).total_seconds())

tools = {}
for line in lines("RUN_TOOLS_BLOB"):
    name, _, state = line.partition("\t")
    if name:
        tools[name] = state

payload = {
    "updated_at": iso_now(),
    "run_id": os.environ.get("RUN_ID", ""),
    "run_dir": os.environ.get("RUN_DIR", ""),
    "repo": os.environ.get("RUN_REPO", ""),
    "project_key": os.environ.get("RUN_PROJECT_KEY", ""),
    "project_name": os.environ.get("RUN_PROJECT_NAME", ""),
    "profile": os.environ.get("RUN_PROFILE", ""),
    "phase": os.environ.get("RUN_PHASE", ""),
    "state": os.environ.get("RUN_STATE", ""),
    "message": os.environ.get("RUN_MESSAGE", ""),
    "result": os.environ.get("RUN_RESULT", ""),
    "started_at": os.environ.get("RUN_STARTED_AT", ""),
    "completed_at": os.environ.get("RUN_COMPLETED_AT", ""),
    "elapsed_seconds": elapsed,
    "quality_gate": os.environ.get("RUN_QUALITY_GATE", ""),
    "host_url": os.environ.get("RUN_HOST_URL", ""),
    "analysis_id": os.environ.get("RUN_ANALYSIS_ID", ""),
    "scan_pid": int(os.environ.get("RUN_SCAN_PID", "0") or 0),
    "dry_run": os.environ.get("RUN_DRY_RUN", "false") == "true",
    "tools": tools,
    "artifacts": {
        "sarif_reports": lines("RUN_SARIF_BLOB"),
        "spotbugs_reports": lines("RUN_SPOTBUGS_BLOB"),
        "generated_reports": lines("RUN_GENERATED_BLOB"),
    },
}

with status_file.open("w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, sort_keys=True)
PY
}

record_run_event() {
  [[ "$run_status_initialized" == "true" ]] || return 0
  local level="$1"
  local message="$2"
  RUN_EVENT_LEVEL="$level" RUN_EVENT_MESSAGE="$message" RUN_EVENT_FILE="$run_events_file" python3 - <<'PY'
import datetime as dt
import json
import os
from pathlib import Path

event_file = Path(os.environ["RUN_EVENT_FILE"])
event_file.parent.mkdir(parents=True, exist_ok=True)
payload = {
    "time": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "level": os.environ.get("RUN_EVENT_LEVEL", "info"),
    "message": os.environ.get("RUN_EVENT_MESSAGE", ""),
}
with event_file.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(payload, sort_keys=True) + "\n")
PY
}

set_run_phase() {
  run_phase="$1"
  run_state="$2"
  run_message="$3"
  write_run_status
  record_run_event "info" "${run_phase}: ${run_message}"
}

set_tool_status() {
  local tool="$1"
  local state_value="$2"
  run_tool_status[$tool]="$state_value"
  write_run_status
}

initialize_run_artifacts() {
  local stamp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"

  if [[ -n "$resume_run_id" ]]; then
    run_id="$resume_run_id"
  fi
  if [[ -z "$run_id" ]]; then
    run_id="scan-${stamp}-$$"
  fi

  run_dir="$repo/.sonar-local/runs/$run_id"
  run_manifest_file="$run_dir/manifest.json"
  run_status_file="$run_dir/status.json"
  run_events_file="$run_dir/events.jsonl"
  mkdir -p "$run_dir"

  run_started_at="$(now_utc)"

  if [[ -n "$resume_run_id" && ! -f "$run_manifest_file" ]]; then
    print -u2 -- "[scan][error] --resume-run requested but manifest not found: $run_manifest_file"
    exit 1
  fi

  local tool_versions_blob input_sarif_blob extra_blob skip_blob tool
  tool_versions_blob=""
  for tool in rg opengrep semgrep gitleaks checkov tfsec trivy osv-scanner codeql gosec bandit hadolint cppcheck infer rats valgrind mvn sonar-scanner npm docker; do
    tool_versions_blob+="${tool}"$'\t'"$(command_version_line "$tool")"$'\n'
  done
  input_sarif_blob="$(printf '%s\n' "${sarif_reports[@]}")"
  extra_blob="$(printf '%s\n' "${extra_properties[@]}")"
  skip_blob="$(printf '%s\n' "${skip_tools[@]}")"

  RUN_MANIFEST_PATH="$run_manifest_file" \
  RUN_RESUME="${resume_run_id:-}" \
  RUN_REPO="$repo" \
  RUN_PROJECT_KEY="$project_key" \
  RUN_PROJECT_NAME="$project_name" \
  RUN_PROFILE_REQUESTED="$profile" \
  RUN_PROFILE_RESOLVED="$resolved_profile" \
  RUN_SECURITY_TOOLS="$security_tools_mode" \
  RUN_CODEQL_SUITE="$codeql_suite" \
  RUN_BUILD_COMMAND="$build_command" \
  RUN_VALGRIND_TARGET="$valgrind_target" \
  RUN_PREPARE="$prepare" \
  RUN_HOST_URL="$host_url" \
  RUN_DRY_RUN="$dry_run" \
  RUN_CREATED_AT="$run_started_at" \
  RUN_EXTRA_BLOB="$extra_blob" \
  RUN_SKIP_TOOLS_BLOB="$skip_blob" \
  RUN_INPUT_SARIF_BLOB="$input_sarif_blob" \
  RUN_TOOL_VERSIONS_BLOB="$tool_versions_blob" \
  python3 - <<'PY'
import json
import os
import subprocess
from pathlib import Path


def blob_to_list(name):
    raw = os.environ.get(name, "")
    return [line for line in raw.splitlines() if line.strip()]


def blob_to_map(name):
    raw = os.environ.get(name, "")
    mapping = {}
    for line in raw.splitlines():
      if not line.strip():
        continue
      key, _, value = line.partition("\t")
      if key:
        mapping[key] = value
    return mapping


def git_head(repo):
    try:
        out = subprocess.check_output(
            ["git", "-C", repo, "rev-parse", "HEAD"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        if out:
            return out
    except Exception:
        pass
    return ""


def git_dirty(repo):
    try:
        out = subprocess.check_output(
            ["git", "-C", repo, "status", "--porcelain"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return bool(out)
    except Exception:
        return False


def immutable_view(payload):
    keys = [
        "repo",
        "project_key",
        "project_name",
        "profile_requested",
        "profile_resolved",
        "security_tools_mode",
        "codeql_suite",
        "build_command",
        "valgrind_target",
        "prepare",
        "host_url",
        "dry_run",
        "skip_tools",
        "extra_properties",
        "input_sarif",
        "tool_versions",
        "repo_revision",
        "repo_dirty",
    ]
    return {key: payload.get(key) for key in keys}


manifest_path = Path(os.environ["RUN_MANIFEST_PATH"])
manifest_path.parent.mkdir(parents=True, exist_ok=True)
repo = os.environ["RUN_REPO"]

candidate = {
    "manifest_version": 1,
    "created_at": os.environ.get("RUN_CREATED_AT", ""),
    "repo": repo,
    "project_key": os.environ.get("RUN_PROJECT_KEY", ""),
    "project_name": os.environ.get("RUN_PROJECT_NAME", ""),
    "profile_requested": os.environ.get("RUN_PROFILE_REQUESTED", ""),
    "profile_resolved": os.environ.get("RUN_PROFILE_RESOLVED", ""),
    "security_tools_mode": os.environ.get("RUN_SECURITY_TOOLS", ""),
    "codeql_suite": os.environ.get("RUN_CODEQL_SUITE", "default"),
    "build_command": os.environ.get("RUN_BUILD_COMMAND", ""),
    "valgrind_target": os.environ.get("RUN_VALGRIND_TARGET", ""),
    "prepare": os.environ.get("RUN_PREPARE", "false") == "true",
    "host_url": os.environ.get("RUN_HOST_URL", ""),
    "dry_run": os.environ.get("RUN_DRY_RUN", "false") == "true",
    "skip_tools": blob_to_list("RUN_SKIP_TOOLS_BLOB"),
    "extra_properties": blob_to_list("RUN_EXTRA_BLOB"),
    "input_sarif": blob_to_list("RUN_INPUT_SARIF_BLOB"),
    "tool_versions": blob_to_map("RUN_TOOL_VERSIONS_BLOB"),
    "repo_revision": git_head(repo),
    "repo_dirty": git_dirty(repo),
}

if manifest_path.exists():
    with manifest_path.open("r", encoding="utf-8") as fh:
        existing = json.load(fh)
    if immutable_view(existing) != immutable_view(candidate):
        print("[scan][error] run manifest mismatch; refusing to mix incompatible scans", flush=True)
        print(f"[scan][error] manifest={manifest_path}", flush=True)
        raise SystemExit(2)
else:
    with manifest_path.open("w", encoding="utf-8") as fh:
        json.dump(candidate, fh, indent=2, sort_keys=True)
PY

  mkdir -p "$repo/.sonar-local/runs"
  ln -sfn "$run_dir" "$repo/.sonar-local/runs/latest" 2>/dev/null || true

  run_status_initialized="true"
  run_tool_status=(
    gitleaks pending
    semgrep pending
    iac pending
    trivy pending
    osv-scanner pending
    codeql pending
    gosec pending
    bandit pending
    hadolint pending
    findsecbugs pending
    cppcheck pending
    infer pending
    rats pending
    valgrind pending
  )
  set_run_phase "initialized" "running" "run artifacts ready"
}

finalize_run_success() {
  run_result="success"
  run_state="completed"
  run_phase="completed"
  run_message="scan completed"
  run_completed_at="$(now_utc)"
  run_finalized="true"
  write_run_status
  record_run_event "info" "scan completed successfully"
}

finalize_run_failure() {
  local message="${1:-scan failed}"
  run_result="failed"
  run_state="failed"
  run_phase="failed"
  run_message="$message"
  run_completed_at="$(now_utc)"
  run_finalized="true"
  write_run_status
  record_run_event "error" "$message"
}

handle_optional_failure() {
  local description="$1"
  if [[ "$security_tools_mode" == "required" ]]; then
    print -u2 "[scan][error] ${description} failed and --security-tools required was set"
    return 1
  fi
  log_warn "${description} failed; continuing"
  return 0
}
