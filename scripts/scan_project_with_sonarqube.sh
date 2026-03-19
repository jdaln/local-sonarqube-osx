#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/common.sh"

repo=""
project_key=""
project_name=""
profile="auto"
prepare="false"
dry_run="false"
host_url="http://127.0.0.1:9000"
host_url_explicit="false"
app_root=""
token="${SONAR_TOKEN:-}"
security_tools_mode="auto"
codeql_suite="default"
build_command=""
valgrind_target=""
typeset -a skip_tools
run_id=""
resume_run_id=""
run_dir=""
run_manifest_file=""
run_status_file=""
run_events_file=""
run_result="running"
run_phase="init"
run_state="running"
run_message=""
run_started_at=""
run_completed_at=""
run_finalized="false"
run_status_initialized="false"
quality_gate_status=""
scan_pid="$$"
typeset -a extra_properties
typeset -a sarif_reports
typeset -a generated_reports
typeset -a spotbugs_reports
typeset -A expected_external_engines
typeset -A run_tool_status
temp_token_name=""
local_admin_loaded="false"
scan_started_at=""
last_analysis_id=""

usage() {
  cat <<'USAGE'
Usage:
  scan_project_with_sonarqube.sh --repo PATH --project-key KEY [options]

Options:
  --repo PATH              Project directory to scan.
  --project-key KEY        SonarQube project key.
  --project-name NAME      SonarQube project name. Defaults to repo basename.
  --profile NAME           auto | js-ts | java-maven | java-gradle | generic
  --prepare                Run supported prep before scanning (for example npm install, frontend tests/coverage, or build/test phases).
  --host-url URL           SonarQube URL. Default: local sonarqube-serv URL or http://127.0.0.1:9000.
  --token TOKEN            Use an existing Sonar token.
  --app-root PATH          Installed sonarqube-serv root for local admin creds.
  --security-tools MODE    auto | off | required (default: auto).
  --skip-security-tools    Shortcut for --security-tools off.
  --skip-tool TOOL         Skip one integrated security tool. Repeatable.
  --skip-dependency-scans  Skip dependency SCA helpers together (currently trivy and osv-scanner).
                           Use --skip-tool osv-scanner if you want to keep trivy enabled.
  --codeql-suite SUITE     default | security-extended | security-and-quality (default: default).
  --build-command CMD      Explicit build command for AST tools like CodeQL and Infer (e.g. 'make').
  --valgrind-target PATH   Path to a compiled executable to run under Valgrind (e.g. './app').
  --extra-property K=V     Extra scanner property. Repeatable.
  --sarif PATH             SARIF report to import. Repeatable.
  --dry-run                Print resolved security + scanner commands and exit.
  --run-id ID              Use a specific run id under .sonar-local/runs/.
  --resume-run ID          Resume an existing run id with immutable manifest checks.
  --help                   Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="$2"
      shift 2
      ;;
    --project-key)
      project_key="$2"
      shift 2
      ;;
    --project-name)
      project_name="$2"
      shift 2
      ;;
    --profile)
      profile="$2"
      shift 2
      ;;
    --prepare)
      prepare="true"
      shift 1
      ;;
    --host-url)
      host_url="$2"
      host_url_explicit="true"
      shift 2
      ;;
    --token)
      token="$2"
      shift 2
      ;;
    --app-root)
      app_root="$2"
      shift 2
      ;;
    --security-tools)
      security_tools_mode="$2"
      shift 2
      ;;
    --skip-security-tools)
      security_tools_mode="off"
      shift 1
      ;;
    --skip-tool)
      skip_tools+=("$2")
      shift 2
      ;;
    --skip-dependency-scans)
      skip_tools+=("trivy" "osv-scanner")
      shift 1
      ;;
    --codeql-suite)
      codeql_suite="$2"
      shift 2
      ;;
    --build-command)
      build_command="$2"
      shift 2
      ;;
    --valgrind-target)
      valgrind_target="$2"
      shift 2
      ;;
    --extra-property)
      extra_properties+=("$2")
      shift 2
      ;;
    --sarif)
      sarif_reports+=("$2")
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift 1
      ;;
    --run-id)
      run_id="$2"
      shift 2
      ;;
    --resume-run)
      resume_run_id="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      print -u2 "unknown argument: $1"
      usage >&2
      exit 1
      ;;
  esac
done

[[ "$security_tools_mode" == "auto" || "$security_tools_mode" == "off" || "$security_tools_mode" == "required" ]] || {
  print -u2 "--security-tools must be one of: auto, off, required"
  exit 1
}

typeset -A skip_tool_lookup
typeset -a allowed_skip_tools
allowed_skip_tools=(
  gitleaks
  semgrep
  iac
  trivy
  osv-scanner
  codeql
  gosec
  bandit
  hadolint
  findsecbugs
  cppcheck
  infer
  rats
  valgrind
)

if (( ${#skip_tools[@]} > 0 )); then
  typeset tool
  for tool in "${skip_tools[@]}"; do
    if (( ${allowed_skip_tools[(Ie)$tool]} == 0 )); then
      print -u2 -- "unknown tool for --skip-tool: $tool"
      print -u2 -- "supported values: ${(j:, :)allowed_skip_tools}"
      exit 1
    fi
    skip_tool_lookup[$tool]=1
  done
  skip_tools=("${(@k)skip_tool_lookup}")
fi

[[ "$codeql_suite" == "default" || "$codeql_suite" == "security-extended" || "$codeql_suite" == "security-and-quality" ]] || {
  print -u2 "--codeql-suite must be one of: default, security-extended, security-and-quality"
  exit 1
}

[[ -n "$repo" ]] || { print -u2 "--repo is required"; exit 1; }
[[ -n "$project_key" ]] || { print -u2 "--project-key is required"; exit 1; }
[[ -z "$run_id" || -z "$resume_run_id" ]] || { print -u2 "--run-id and --resume-run are mutually exclusive"; exit 1; }
[[ -z "$run_id" || "$run_id" != */* ]] || { print -u2 "--run-id must not contain '/'"; exit 1; }
[[ -z "$resume_run_id" || "$resume_run_id" != */* ]] || { print -u2 "--resume-run must not contain '/'"; exit 1; }

repo="$(cd "$repo" && pwd)"
[[ -d "$repo" ]] || { print -u2 "missing repo: $repo"; exit 1; }
[[ -n "$project_name" ]] || project_name="$(basename "$repo")"

scan_lib_dir="$script_dir/lib/scan"
source "$scan_lib_dir/core.sh"
source "$scan_lib_dir/sarif.sh"
source "$scan_lib_dir/repo_and_server.sh"
source "$scan_lib_dir/scanner_helpers.sh"
source "$scan_lib_dir/security_tools.sh"
source "$scan_lib_dir/scanner_and_wait.sh"

if [[ "$host_url_explicit" != "true" ]]; then
  load_local_admin_env >/dev/null 2>&1 || true
fi

resolved_profile="$(detect_profile)"
initialize_run_artifacts

TRAPEXIT() {
  local exit_code=$?
  if (( exit_code != 0 )) && [[ "$run_finalized" != "true" ]] && [[ "$run_status_initialized" == "true" ]]; then
    finalize_run_failure "scan failed during ${run_phase}: ${run_message}"
  fi
  return $exit_code
}

set_run_phase "preflight" "running" "resolving Sonar endpoint and credentials"
if [[ "$dry_run" != "true" ]]; then
  ensure_server_up

  if [[ -z "$token" ]]; then
    if ! generate_temp_token; then
      print -u2 "missing token; provide --token or ensure local sonarqube-serv credentials are available"
      exit 1
    fi
  fi

  if [[ "$local_admin_loaded" == "true" ]] || load_local_admin_env >/dev/null 2>&1; then
    ensure_project_exists
  fi
else
  [[ -n "$token" ]] || token="DRY_RUN_TOKEN"
fi

export SONAR_HOST_URL="$host_url"
export SONAR_TOKEN="$token"

run_security_pipeline
dedupe_sca_reports
collect_expected_external_engines

set_run_phase "scanner-build" "running" "building scanner command"
case "$resolved_profile" in
  js-ts)
    command_blob="$(build_js_ts_command)"
    ;;
  java-maven)
    command_blob="$(build_java_maven_command)"
    ;;
  java-gradle)
    command_blob="$(build_java_gradle_command)"
    ;;
  dotnet)
    command_blob="$(build_dotnet_command)"
    ;;
  python)
    command_blob="$(build_python_command)"
    ;;
  go)
    command_blob="$(build_go_command)"
    ;;
  c-cpp)
    command_blob="$(build_c_cpp_command)"
    ;;
  *)
    command_blob="$(build_generic_command)"
    ;;
esac

print -r -- "$command_blob" > "$run_dir/scanner-command.txt"

scan_started_at="$(date -u +"%Y-%m-%dT%H:%M:%S+0000")"
set_run_phase "scanner-run" "running" "running Sonar scanner"
if ! execute_scanner_with_recovery "$command_blob"; then
  finalize_run_failure "Sonar scanner failed"
  exit 1
fi

set_run_phase "background-task" "running" "waiting for Sonar compute engine task"
if ! wait_for_background_task; then
  finalize_run_failure "Sonar background task failed"
  exit 1
fi

set_run_phase "external-import-check" "running" "verifying external report imports"
if ! verify_external_issue_imports; then
  finalize_run_failure "external issue import verification failed"
  exit 1
fi

finalize_run_success
