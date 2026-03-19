js_ts_prepare() {
  [[ "$prepare" == "true" ]] || return 0
  command -v npm >/dev/null 2>&1 || { print -u2 "npm is required for js-ts prepare"; exit 1; }

  local node_modules_ready="false"
  if [[ -d "$repo/node_modules" ]]; then
    node_modules_ready="true"
  fi

  if [[ "$node_modules_ready" == "false" ]]; then
    if [[ -f "$repo/package-lock.json" ]]; then
      log_info "node_modules missing; running npm ci"
      (cd "$repo" && run_logged npm ci)
    elif [[ -f "$repo/package.json" ]]; then
      log_info "node_modules missing; running npm install"
      (cd "$repo" && run_logged npm install)
    fi
  fi

  if [[ -f "$repo/angular.json" ]]; then
    typeset -a test_cmd
    # Ensure local angular-devkit is present or npx will fail to find builders
    if [[ ! -d "$repo/node_modules/@angular-devkit" ]]; then
      log_warn "@angular-devkit missing in node_modules; frontend tests might fail. Try running 'npm install' in the project root."
    fi

    # Favor npx to avoid issues with missing global 'ng'
    if [[ -f "$repo/node_modules/.bin/ng" ]]; then
      test_cmd=(npx ng test --watch=false --code-coverage)
    else
      test_cmd=(npm test -- --watch=false --code-coverage)
    fi

    if print -r -- "$(sed -n '1,220p' "$repo/package.json")" | grep -q '"karma-chrome-launcher"'; then
      test_cmd+=(--browsers=ChromeHeadless)
    fi
    (cd "$repo" && run_logged "${test_cmd[@]}")
  fi

  if [[ -f "$repo/eslint.config.js" || -f "$repo/eslint.config.mjs" || -f "$repo/eslint.config.cjs" || -f "$repo/.eslintrc" || -f "$repo/.eslintrc.js" || -f "$repo/.eslintrc.cjs" || -f "$repo/.eslintrc.json" ]]; then
    local eslint_report="$repo/.sonar-local/eslint-report.json"
    mkdir -p "$repo/.sonar-local"
    (cd "$repo" && run_logged npx eslint . -f json -o "$eslint_report")
    if [[ "$dry_run" == "true" || -f "$eslint_report" ]]; then
      generated_reports+=("eslint:$eslint_report")
    fi
  fi
}

tool_is_skipped() {
  local tool="$1"
  [[ -n "${skip_tool_lookup[$tool]:-}" ]]
}

run_semgrep_security() {
  local report="$repo/.sonar-local/security/semgrep.sarif"

  if command -v opengrep >/dev/null 2>&1; then
    log_info "running opengrep"
    if (cd "$repo" && run_logged opengrep scan --config auto --sarif --output "$report" .); then
      [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
      return 0
    fi
    if (cd "$repo" && run_logged opengrep --config auto --sarif --output "$report" .); then
      [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
      return 0
    fi
    handle_optional_failure "opengrep scan"
    return $?
  fi

  if command -v semgrep >/dev/null 2>&1; then
    log_info "running semgrep"
    if (cd "$repo" && run_logged semgrep scan --config auto --exclude-rule='generic.secrets.security.detected-facebook-oauth.detected-facebook-oauth' --exclude-rule='generic.secrets.security.detected-sonarqube-api-key.detected-sonarqube-api-key' --exclude-rule='generic.secrets.security.detected-sonarqube-docs-api-key.detected-sonarqube-docs-api-key' --sarif --output "$report" .); then
      [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
      return 0
    fi
    if (cd "$repo" && run_logged semgrep --config auto --exclude-rule='generic.secrets.security.detected-facebook-oauth.detected-facebook-oauth' --exclude-rule='generic.secrets.security.detected-sonarqube-api-key.detected-sonarqube-api-key' --exclude-rule='generic.secrets.security.detected-sonarqube-docs-api-key.detected-sonarqube-docs-api-key' --sarif --output "$report" .); then
      [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
      return 0
    fi
    handle_optional_failure "semgrep scan"
    return $?
  fi

  if [[ "$security_tools_mode" == "required" ]]; then
    print -u2 "[scan][error] --security-tools required but neither opengrep nor semgrep is installed"
    return 1
  fi
  log_warn "opengrep/semgrep not found; skipping pattern-based SAST"
  return 0
}

run_gitleaks_security() {
  local report="$repo/.sonar-local/security/gitleaks.sarif"

  if ! command -v gitleaks >/dev/null 2>&1; then
    if [[ "$security_tools_mode" == "required" ]]; then
      print -u2 "[scan][error] --security-tools required but gitleaks is not installed"
      return 1
    fi
    log_warn "gitleaks not found; skipping secret scanning"
    return 0
  fi

  log_info "running gitleaks"
  if [[ -d "$repo/.git" ]]; then
    if (cd "$repo" && run_logged gitleaks detect --source . --report-format sarif --report-path "$report" --exit-code 0 --no-banner --redact); then
      [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
      return 0
    fi
  fi

  if (cd "$repo" && run_logged gitleaks dir . --report-format sarif --report-path "$report" --exit-code 0 --no-banner --redact); then
    [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
    return 0
  fi

  handle_optional_failure "gitleaks"
  return $?
}

run_gosec_security() {
  repo_has_go || return 0
  local report="$repo/.sonar-local/security/gosec.sarif"

  if ! command -v gosec >/dev/null 2>&1; then
    if [[ "$security_tools_mode" == "required" ]]; then
      print -u2 "[scan][error] --security-tools required but gosec is not installed"
      return 1
    fi
    log_warn "gosec not found; skipping Go security scan"
    return 0
  fi

  log_info "running gosec"
  if (cd "$repo" && run_logged gosec -no-fail -fmt sarif -out "$report" ./...); then
    [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
    return 0
  fi

  handle_optional_failure "gosec"
  return $?
}

run_bandit_security() {
  repo_has_python || return 0
  local report="$repo/.sonar-local/security/bandit.sarif"
  local json_report="$repo/.sonar-local/security/bandit.json"

  if ! command -v bandit >/dev/null 2>&1; then
    if [[ "$security_tools_mode" == "required" ]]; then
      print -u2 "[scan][error] --security-tools required but bandit is not installed"
      return 1
    fi
    log_warn "bandit not found; skipping Python security scan"
    return 0
  fi

  log_info "running bandit"
  if (cd "$repo" && run_logged bandit -r . -f sarif -o "$report" --exit-zero); then
    [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
    return 0
  fi

  if [[ "$dry_run" == "true" ]]; then
    record_sarif_report "$report"
    return 0
  fi

  log_warn "bandit SARIF output failed; retrying with JSON + SARIF conversion"
  if (cd "$repo" && bandit -r . -f json -o "$json_report" --exit-zero) && convert_bandit_json_to_sarif "$json_report" "$report"; then
    [[ -f "$report" ]] && record_sarif_report "$report"
    return 0
  fi

  handle_optional_failure "bandit"
  return $?
}

run_hadolint_security() {
  repo_has_dockerfiles || return 0
  local report="$repo/.sonar-local/security/hadolint.sarif"
  typeset -a dockerfiles

  while IFS= read -r dockerfile; do
    [[ -n "$dockerfile" ]] && dockerfiles+=("${dockerfile#./}")
  done < <(cd "$repo" && find . -type f -name 'Dockerfile*' | sort)

  [[ ${#dockerfiles[@]} -gt 0 ]] || return 0

  if ! command -v hadolint >/dev/null 2>&1; then
    if [[ "$security_tools_mode" == "required" ]]; then
      print -u2 "[scan][error] --security-tools required but hadolint is not installed"
      return 1
    fi
    log_warn "hadolint not found; skipping Dockerfile linting"
    return 0
  fi

  log_info "running hadolint"
  if [[ "$dry_run" == "true" ]]; then
    printf '%q ' hadolint --no-fail -f sarif "${dockerfiles[@]}"
    printf '> %q\n' "$report"
    record_sarif_report "$report"
    return 0
  fi

  if (cd "$repo" && hadolint --no-fail -f sarif "${dockerfiles[@]}" > "$report"); then
    [[ -f "$report" ]] && record_sarif_report "$report"
    return 0
  fi

  handle_optional_failure "hadolint"
  return $?
}

run_iac_security() {
  repo_has_iac || return 0

  local checkov_dir="$repo/.sonar-local/security/checkov-output"
  local checkov_report="$checkov_dir/results_sarif.sarif"
  local tfsec_report="$repo/.sonar-local/security/tfsec.sarif"

  if command -v checkov >/dev/null 2>&1; then
    log_info "running checkov"
    if [[ "$dry_run" == "true" ]]; then
      printf '%q ' checkov -d . -o sarif --output-file-path "$checkov_dir" --soft-fail --quiet
      printf '> %q\n' /dev/null
      record_sarif_report "$checkov_report"
      return 0
    fi

    rm -rf "$checkov_dir"
    if (cd "$repo" && checkov -d . -o sarif --output-file-path "$checkov_dir" --soft-fail --quiet >/dev/null); then
      [[ -f "$checkov_report" ]] && record_sarif_report "$checkov_report"
      return 0
    fi

    handle_optional_failure "checkov"
    return $?
  fi

  if repo_has_terraform && command -v tfsec >/dev/null 2>&1; then
    log_info "running tfsec"
    if [[ "$dry_run" == "true" ]]; then
      printf '%q ' tfsec --format sarif --soft-fail .
      printf '> %q\n' "$tfsec_report"
      record_sarif_report "$tfsec_report"
      return 0
    fi

    if (cd "$repo" && tfsec --format sarif --soft-fail . > "$tfsec_report"); then
      [[ -f "$tfsec_report" ]] && record_sarif_report "$tfsec_report"
      return 0
    fi

    handle_optional_failure "tfsec"
    return $?
  fi

  if [[ "$security_tools_mode" == "required" ]]; then
    print -u2 "[scan][error] --security-tools required but neither checkov nor tfsec is installed for IaC scanning"
    return 1
  fi
  log_warn "checkov/tfsec not found; skipping IaC security scan"
  return 0
}

run_trivy_sca() {
  repo_has_dependency_manifests || return 0

  local report="$repo/.sonar-local/security/trivy.sarif"

  if ! command -v trivy >/dev/null 2>&1; then
    if [[ "$security_tools_mode" == "required" ]]; then
      print -u2 "[scan][error] --security-tools required but trivy is not installed for SCA scanning"
      return 1
    fi
    log_warn "trivy not found; skipping SCA scan"
    return 0
  fi

  log_info "running trivy (SCA)"
  if (cd "$repo" && run_logged trivy fs --scanners vuln --pkg-types library --format sarif --output "$report" .); then
    [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
    return 0
  fi

  handle_optional_failure "trivy SCA scan"
  return $?
}

run_osv_scanner_sca() {
  repo_has_dependency_manifests || return 0

  local report="$repo/.sonar-local/security/osv-scanner.sarif"

  if ! command -v osv-scanner >/dev/null 2>&1; then
    if [[ "$security_tools_mode" == "required" ]]; then
      print -u2 "[scan][error] --security-tools required but osv-scanner is not installed for SCA scanning"
      return 1
    fi
    log_warn "osv-scanner not found; skipping SCA scan"
    return 0
  fi

  log_info "running osv-scanner (SCA)"
  if (cd "$repo" && run_logged osv-scanner scan source -r . -f sarif --output "$report" --verbosity warn); then
    [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
    return 0
  fi

  if [[ "$dry_run" != "true" && -f "$report" ]]; then
    log_warn "osv-scanner returned non-zero; continuing because SARIF report was generated"
    record_sarif_report "$report"
    return 0
  fi

  handle_optional_failure "osv-scanner SCA scan"
  return $?
}

dedupe_sca_reports() {
  local trivy_report="$repo/.sonar-local/security/trivy.sarif"
  local osv_report="$repo/.sonar-local/security/osv-scanner.sarif"

  [[ "$dry_run" == "true" ]] && return 0
  [[ -f "$trivy_report" && -f "$osv_report" ]] || return 0

  local dedupe_output
  if ! dedupe_output="$(python3 - "$trivy_report" "$osv_report" <<'PY'
import json
import os
import re
import sys
from urllib.parse import urlparse

trivy_path, osv_path = sys.argv[1], sys.argv[2]

with open(trivy_path, "r", encoding="utf-8") as fh:
    trivy = json.load(fh)
with open(osv_path, "r", encoding="utf-8") as fh:
    osv = json.load(fh)

def result_key(result):
    rule_id = (result.get("ruleId") or "").strip()
    uri_key = ""
    pkg_key = ""
    locations = result.get("locations") or []
    if locations:
        physical = (locations[0] or {}).get("physicalLocation") or {}
        uri = ((physical.get("artifactLocation") or {}).get("uri") or "").strip()
        if uri.startswith("file://"):
            uri = urlparse(uri).path
        uri_key = os.path.basename(uri) or uri

    message = ((result.get("message") or {}).get("text") or "")
    m = re.search(r"Package:\s*([^\n]+)\nInstalled Version:\s*([^\n]+)", message, re.IGNORECASE)
    if m:
        pkg_key = f"{m.group(1).strip()}@{m.group(2).strip()}"
    else:
        m = re.search(r"Package '([^']+)' is vulnerable", message, re.IGNORECASE)
        if m:
            pkg_key = m.group(1).strip()
        else:
            m = re.search(r":\s*([^\s]+@[^\s]+)$", message.strip())
            if m:
                pkg_key = m.group(1).strip()

    return (rule_id, pkg_key.lower(), uri_key.lower())

trivy_keys = set()
for run in trivy.get("runs") or []:
    for result in run.get("results") or []:
        trivy_keys.add(result_key(result))

removed = 0
remaining = 0

for run in osv.get("runs") or []:
    old_results = run.get("results") or []
    new_results = []
    for result in old_results:
        if result_key(result) in trivy_keys:
            removed += 1
            continue
        new_results.append(result)
    run["results"] = new_results
    remaining += len(new_results)

    used_rule_ids = {str(r.get("ruleId", "")).strip() for r in new_results if r.get("ruleId")}
    driver = ((run.get("tool") or {}).get("driver") or {})
    rules = driver.get("rules")
    if isinstance(rules, list):
        driver["rules"] = [rule for rule in rules if str((rule or {}).get("id", "")).strip() in used_rule_ids]

with open(osv_path, "w", encoding="utf-8") as fh:
    json.dump(osv, fh)

print(f"sca_dedupe_removed={removed} osv_remaining={remaining}")
PY
)"; then
    handle_optional_failure "SCA deduplication"
    return $?
  fi

  log_info "$dedupe_output"
  return 0
}


codeql_pack_for_lang() {
  case "$1" in
    java) print -r -- 'codeql/java-queries' ;;
    javascript) print -r -- 'codeql/javascript-queries' ;;
    python) print -r -- 'codeql/python-queries' ;;
    go) print -r -- 'codeql/go-queries' ;;
    csharp) print -r -- 'codeql/csharp-queries' ;;
    cpp) print -r -- 'codeql/cpp-queries' ;;
    ruby) print -r -- 'codeql/ruby-queries' ;;
    *) return 1 ;;
  esac
}

ensure_codeql_query_pack() {
  local pack="$1"
  if codeql resolve queries --format=text -- "$pack" >/dev/null 2>&1; then
    return 0
  fi

  log_info "downloading CodeQL pack $pack"
  run_logged codeql pack download "$pack"
}

codeql_build_for_lang() {
  local lang="$1"
  case "$lang" in
    java)
      if [[ -f "$repo/pom.xml" ]]; then
        print -r -- 'mvn -B -DskipTests compile'
        return 0
      fi
      if [[ -f "$repo/gradlew" ]]; then
        print -r -- './gradlew classes -x test'
        return 0
      fi
      if [[ -f "$repo/build.gradle" || -f "$repo/build.gradle.kts" ]]; then
        print -r -- 'gradle classes -x test'
        return 0
      fi
      ;;
    go)
      print -r -- 'go build ./...'
      return 0
      ;;
    csharp)
      print -r -- 'dotnet build'
      return 0
      ;;
  esac
  print -r -- ''
}

detect_codeql_languages() {
  typeset -a langs

  repo_has_java && langs+=("java")
  if repo_has_javascript; then
    langs+=("javascript")
  fi
  repo_has_python && langs+=("python")
  repo_has_go && langs+=("go")
  if find "$repo" -type f -name '*.sln' | grep -q . || repo_has_files '*.cs'; then
    langs+=("csharp")
  fi
  if repo_has_files '*.c' || repo_has_files '*.cpp' || repo_has_files '*.h' || repo_has_files '*.hpp'; then
    langs+=("cpp")
  fi
  if repo_has_files '*.rb' || [[ -f "$repo/Gemfile" ]]; then
    langs+=("ruby")
  fi

  print -r -- "${langs[*]}"
}

run_codeql_security() {
  local detected
  detected="$(detect_codeql_languages)"
  [[ -n "$detected" ]] || return 0

  if ! command -v codeql >/dev/null 2>&1; then
    if [[ "$security_tools_mode" == "required" ]]; then
      print -u2 "[scan][error] --security-tools required but codeql is not installed"
      return 1
    fi
    log_warn "codeql not found; skipping CodeQL SARIF generation"
    return 0
  fi

  typeset -a langs
  IFS=' ' read -rA langs <<< "$detected"

  local codeql_root="$repo/.sonar-local/security/codeql"
  mkdir -p "$codeql_root"

  local lang
  for lang in "${langs[@]}"; do
    local pack db_dir report build_cmd
    pack="$(codeql_pack_for_lang "$lang" 2>/dev/null || true)"
    [[ -n "$pack" ]] || continue

    db_dir="$codeql_root/db-$lang"
    report="$codeql_root/$lang.sarif"
    build_cmd="$(codeql_build_for_lang "$lang")"

    if ! ensure_codeql_query_pack "$pack"; then
      handle_optional_failure "codeql pack download ($pack)" || return 1
      continue
    fi

    log_info "running codeql for $lang"

    typeset -a create_cmd
    create_cmd=(codeql database create "$db_dir" --source-root "$repo" --language "$lang" --overwrite --threads=0)
    [[ -n "$build_cmd" ]] && create_cmd+=(--command "$build_cmd")

    if ! (cd "$repo" && run_logged "${create_cmd[@]}"); then
      handle_optional_failure "codeql database create ($lang)" || return 1
      continue
    fi

    local query_target="$pack"
    if [[ "$codeql_suite" != "default" ]]; then
      query_target="${pack}:codeql-suites/${lang}-${codeql_suite}.qls"
    fi

    if ! (cd "$repo" && run_logged codeql database analyze "$db_dir" "$query_target" --format=sarif-latest --output "$report" --threads=0); then
      handle_optional_failure "codeql database analyze ($lang)" || return 1
      continue
    fi

    [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
  done

  return 0
}

run_findsecbugs_security() {
  repo_has_java || return 0

  if [[ ! -f "$repo/pom.xml" ]]; then
    if [[ "$security_tools_mode" == "required" ]]; then
      print -u2 "[scan][error] --security-tools required but automatic FindSecBugs currently needs a Maven project"
      return 1
    fi
    log_warn "FindSecBugs auto-run currently supports Maven projects only; skipping"
    return 0
  fi

  if ! command -v mvn >/dev/null 2>&1; then
    if [[ "$security_tools_mode" == "required" ]]; then
      print -u2 "[scan][error] --security-tools required but mvn is not installed"
      return 1
    fi
    log_warn "mvn not found; skipping FindSecBugs"
    return 0
  fi

  local report="$repo/.sonar-local/security/findsecbugs-spotbugs.xml"

  log_info "running FindSecBugs via SpotBugs Maven plugin"
  if (cd "$repo" && run_logged mvn -B -DskipTests \
      com.github.spotbugs:spotbugs-maven-plugin:spotbugs \
      -Dspotbugs.plugins=com.h3xstream.findsecbugs:findsecbugs-plugin:1.14.0 \
      -Dspotbugs.xmlOutput=true \
      -Dspotbugs.outputFile="$report" \
      -Dspotbugs.effort=Max \
      -Dspotbugs.threshold=Low); then
    [[ "$dry_run" == "true" || -f "$report" ]] && record_spotbugs_report "$report"
    return 0
  fi

  handle_optional_failure "FindSecBugs (SpotBugs Maven plugin)"
  return $?
}

run_security_step() {
  local tool="$1"
  local fn="$2"
  local before_sarif before_spotbugs
  before_sarif=${#sarif_reports[@]}
  before_spotbugs=${#spotbugs_reports[@]}

  if tool_is_skipped "$tool"; then
    log_info "skipping ${tool} by user request"
    set_tool_status "$tool" "disabled"
    record_run_event "info" "security-tools: skipped ${tool} by user request"
    return 0
  fi

  set_tool_status "$tool" "running"
  if ! "$fn"; then
    set_tool_status "$tool" "failed"
    return 1
  fi

  if (( ${#sarif_reports[@]} > before_sarif || ${#spotbugs_reports[@]} > before_spotbugs )); then
    set_tool_status "$tool" "completed"
  else
    set_tool_status "$tool" "skipped"
  fi
  return 0
}


run_cppcheck_security() {
  repo_has_files '*.c' || repo_has_files '*.cpp' || repo_has_files '*.h' || repo_has_files '*.hpp' || return 0
  local report="$repo/.sonar-local/security/cppcheck.sarif"
  local xml_out="$repo/.sonar-local/security/cppcheck.xml"

  log_info "running cppcheck via docker"
  local cmd=(docker run --rm -v "$repo:/code:ro" cxx-scanner-tools cppcheck --enable=all --xml --xml-version=2 .)
  
  if ! (run_logged "${cmd[@]}" > "$xml_out" 2>&1); then
    handle_optional_failure "cppcheck" || return 1
    return 0
  fi
  
  if [[ -f "$xml_out" && "$dry_run" != "true" ]]; then
    python3 "$script_dir/lib/scan/cppcheck_to_sarif.py" "$xml_out" "$report" 2>/dev/null || true
  fi

  [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
  return 0
}

run_infer_security() {
  repo_has_java || repo_has_files '*.c' || repo_has_files '*.cpp' || repo_has_files '*.m' || repo_has_files '*.mm' || return 0
  local report="$repo/.sonar-local/security/infer.sarif"
  local infer_out="$repo/.sonar-local/security/infer-out"
  
  typeset -a infer_cmd
  if command -v infer >/dev/null 2>&1; then
    infer_cmd=(infer)
  elif [[ -x "$HOME/.local/bin/infer" ]]; then
    infer_cmd=("$HOME/.local/bin/infer")
  else
    log_info "infer not found natively; falling back to docker"
    infer_cmd=(docker run --rm -v "$repo:/code" cxx-scanner-tools infer)
  fi

  log_info "running infer"
  local infer_exec_cmd
  if [[ -n "$build_command" ]]; then
    typeset -a bcmd
    bcmd=("${(z)build_command}")
    infer_exec_cmd=("${infer_cmd[@]}" run --sarif -- "${bcmd[@]}")
  elif repo_has_java && [[ -f "$repo/pom.xml" ]]; then
    infer_exec_cmd=("${infer_cmd[@]}" run --sarif -- mvn clean compile -DskipTests)
  else
    log_warn "infer requires a build command but --build-command was not provided and no Maven POM found. Attempting capture fallback."
    infer_exec_cmd=("${infer_cmd[@]}" capture --sarif -- gcc -c *.c)
  fi

  if ! (cd "$repo" && run_logged "${infer_exec_cmd[@]}" >/dev/null 2>&1); then
     handle_optional_failure "infer"
     return 0
  fi
  
  if [[ -f "$repo/infer-out/report.sarif" && "$dry_run" != "true" ]]; then
      mv "$repo/infer-out/report.sarif" "$report"
      rm -rf "$repo/infer-out" || true
  fi

  [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
  return 0
}

run_rats_security() {
  repo_has_files '*.c' || repo_has_files '*.cpp' || repo_has_files '*.php' || repo_has_files '*.py' || repo_has_files '*.rb' || repo_has_files '*.pl' || return 0
  local report="$repo/.sonar-local/security/rats.sarif"
  local xml_out="$repo/.sonar-local/security/rats.xml"

  if ! command -v rats >/dev/null 2>&1; then
    log_warn "rats not found; skipping"
    return 0
  fi

  log_info "running rats"
  if ! (cd "$repo" && run_logged rats --xml . > "$xml_out" 2>/dev/null); then
    handle_optional_failure "rats" || return 1
    return 0
  fi

  if [[ -f "$xml_out" && "$dry_run" != "true" ]]; then
    python3 "$script_dir/lib/scan/rats_to_sarif.py" "$xml_out" "$report" 2>/dev/null || true
  fi

  [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
  return 0
}

run_valgrind_security() {
  local report="$repo/.sonar-local/security/valgrind.sarif"
  local xml_out="$repo/.sonar-local/security/valgrind.xml"

  if [[ -z "$valgrind_target" ]]; then
    log_warn "valgrind requires a compiled target executable. Skipping automatic run (provide --valgrind-target)."
    return 0
  fi

  log_info "running valgrind via docker on target: $valgrind_target"
  local cmd=(docker run --rm -v "$repo:/code" cxx-scanner-tools valgrind --xml=yes --xml-file=valgrind.xml "$valgrind_target")

  if ! (run_logged "${cmd[@]}" >/dev/null 2>&1); then
    handle_optional_failure "valgrind" || return 1
    return 0
  fi

  if [[ -f "$repo/valgrind.xml" ]]; then
    mv "$repo/valgrind.xml" "$xml_out"
  fi

  if [[ -f "$xml_out" && "$dry_run" != "true" ]]; then
    python3 "$script_dir/lib/scan/valgrind_to_sarif.py" "$xml_out" "$report" 2>/dev/null || true
  fi

  [[ "$dry_run" == "true" || -f "$report" ]] && record_sarif_report "$report"
  return 0
}
run_security_pipeline() {
  [[ "$security_tools_mode" == "off" ]] && {
    log_info "security tool pipeline disabled"
    local tool
    for tool in "${(@k)run_tool_status}"; do
      set_tool_status "$tool" "disabled"
    done
    return 0
  }

  set_run_phase "security-tools" "running" "running integrated security tools"
  mkdir -p "$repo/.sonar-local/security"

  js_ts_prepare
  run_security_step "gitleaks" run_gitleaks_security || return 1
  run_security_step "semgrep" run_semgrep_security || return 1
  run_security_step "iac" run_iac_security || return 1
  run_security_step "trivy" run_trivy_sca || return 1
  run_security_step "osv-scanner" run_osv_scanner_sca || return 1
  run_security_step "codeql" run_codeql_security || return 1
  run_security_step "gosec" run_gosec_security || return 1
  run_security_step "bandit" run_bandit_security || return 1
  run_security_step "hadolint" run_hadolint_security || return 1
  run_security_step "findsecbugs" run_findsecbugs_security || return 1
  run_security_step "cppcheck" run_cppcheck_security || return 1
  run_security_step "infer" run_infer_security || return 1
  run_security_step "rats" run_rats_security || return 1
  run_security_step "valgrind" run_valgrind_security || return 1
}
