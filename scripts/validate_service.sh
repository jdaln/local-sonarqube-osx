#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
base_dir="$(cd "$script_dir/.." && pwd)"
source "$script_dir/common.sh"
load_versions "$base_dir"

app_root=""
skip_launchd_check="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root)
      app_root="$2"
      shift 2
      ;;
    --skip-launchd-check)
      skip_launchd_check="true"
      shift 1
      ;;
    *)
      print -u2 "unknown argument: $1"
      exit 1
      ;;
  esac
done

[[ -n "$app_root" ]] || app_root="$(default_app_root)"
load_runtime_env "$app_root/config/sonarqube-serv.env"
ensure_docker_daemon

if [[ "$skip_launchd_check" != "true" ]]; then
  launchctl kickstart -k "gui/$(id -u)/${SONARQUBE_LAUNCHD_LABEL}" >/dev/null 2>&1 || true
fi

"$app_root/bin/run_sonarqube_stack.sh" --app-root "$app_root"

status_url="http://${SONARQUBE_SERVICE_HOST}:${SONARQUBE_SERVICE_PORT}/api/system/status"
auth_url="http://${SONARQUBE_SERVICE_HOST}:${SONARQUBE_SERVICE_PORT}/api/authentication/validate"

wait_for_sonarqube_up "$status_url" 180 5

status_json="$(curl -fsS "$status_url")"
auth_json="$(curl -fsS -u "${SONARQUBE_ADMIN_LOGIN}:${SONARQUBE_ADMIN_PASSWORD}" "$auth_url")"

python3 - <<'PY' "$status_json" "$auth_json"
import json
import sys

status = json.loads(sys.argv[1])
auth = json.loads(sys.argv[2])

assert status["status"] == "UP", status
assert auth["valid"] is True, auth
print("status=UP admin_login=true")
PY

if [[ "$skip_launchd_check" != "true" ]]; then
  launchctl print "gui/$(id -u)/${SONARQUBE_LAUNCHD_LABEL}" >/dev/null
fi

