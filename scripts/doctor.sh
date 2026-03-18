#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
base_dir="$(cd "$script_dir/.." && pwd)"
source "$script_dir/common.sh"
load_versions "$base_dir"

app_root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root)
      app_root="$2"
      shift 2
      ;;
    *)
      print -u2 "unknown argument: $1"
      exit 1
      ;;
  esac
done

[[ -n "$app_root" ]] || app_root="$(default_app_root)"

print "=== SonarQube Service Doctor ==="
print "App Root: ${app_root}"
print ""

# 1. Docker Check
print "[1/3] Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
  print -u2 "  ERROR: docker command not found"
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  print -u2 "  ERROR: Docker daemon is not running"
  exit 1
fi
print "  OK: Docker is running"
print ""

# 2. Service Check
print "[2/3] Checking SonarQube Service..."
if [[ -f "$app_root/config/sonarqube-serv.env" ]]; then
  load_runtime_env "$app_root/config/sonarqube-serv.env"
  status_url="http://${SONARQUBE_SERVICE_HOST}:${SONARQUBE_SERVICE_PORT}/api/system/status"
  
  if curl -fsS "$status_url" >/dev/null 2>&1; then
    status_json="$(curl -fsS "$status_url")"
    sq_status="$(print -r -- "$status_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
    print "  OK: SonarQube is ${sq_status} at ${status_url}"
  else
    print "  WARN: SonarQube is NOT reachable at ${status_url}"
    print "        Try running: ./scripts/install_sonarqube_serv_osx.sh"
  fi
else
  print "  WARN: Configuration file missing. Service might not be installed."
fi
print ""

# 3. Toolchain Check
print "[3/3] Checking Toolchain..."

typeset -a infra_tools js_tools builder_tools security_tools
infra_tools=(git rg python3 docker-compose)
js_tools=(node npm "@angular/cli")
builder_tools=(java mvn)
security_tools=(gitleaks semgrep checkov tfsec trivy osv-scanner codeql gosec bandit hadolint)

check_tools() {
  local label="$1"
  local level="$2" # "ERROR" or "INFO"
  shift 2
  local t_list=("$@")
  local t version
  local -a missing

  print -r -- "--- ${label} ---"
  for t in "${t_list[@]}"; do
    local exe="$t"
    case "$t" in
      "@angular/cli") exe="ng" ;;
    esac

    if command -v "$exe" >/dev/null 2>&1; then
      print "  OK: Found ${t} (${exe})"
    else
      if [[ "$level" == "ERROR" ]]; then
        print "  MISSING: ${t}"
        missing+=("${t}")
      else
        print "  OPTIONAL: ${t} (skipping related prep steps if project uses this)"
      fi
    fi
  done
  return ${#missing[@]}
}

check_tools "Scan Infrastructure" "ERROR" "${infra_tools[@]}"
infra_missing=$?

print ""
check_tools "JS/TS Tooling" "INFO" "${js_tools[@]}"
js_missing=$?

print ""
check_tools "Project Builders" "INFO" "${builder_tools[@]}"
builder_missing=$?

print ""
check_tools "Security Toolchain" "ERROR" "${security_tools[@]}"
security_missing=$?

# Special Check for Headless Browser
print ""
print -r -- "--- Browser Environment ---"
if command -v google-chrome >/dev/null 2>&1 || command -v chromium >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1; then
  print "  OK: Found Browser (Chrome/Chromium)"
else
  print "  INFO: No headless browser found. Optional frontend tests (Angular) will be skipped."
fi

if (( infra_missing > 0 || security_missing > 0 )); then
  print ""
  print "Action Required: Some critical tools are missing from your PATH."
  if (( infra_missing > 0 )); then
    print "  Infrastructure missing. Scanning may fail to initialize."
  fi
  if (( security_missing > 0 )); then
    print "  Security tools missing. Analysis will be restricted."
    print "  Recommendation: brew install gitleaks semgrep checkov tfsec trivy osv-scanner codeql gosec bandit hadolint"
  fi
else
  print ""
  print "Success: All core scan components are present."
fi

print ""
print "=== Doctor Finished ==="
