#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/common.sh"

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
load_runtime_env "$app_root/config/sonarqube-serv.env"

status_url="http://${SONARQUBE_SERVICE_HOST}:${SONARQUBE_SERVICE_PORT}/api/system/status"
auth_url="http://${SONARQUBE_SERVICE_HOST}:${SONARQUBE_SERVICE_PORT}/api/authentication/validate"
change_url="http://${SONARQUBE_SERVICE_HOST}:${SONARQUBE_SERVICE_PORT}/api/users/change_password"

wait_for_sonarqube_up "$status_url" 180 5

if curl -fsS -u "${SONARQUBE_ADMIN_LOGIN}:${SONARQUBE_ADMIN_PASSWORD}" "$auth_url" | python3 -c 'import json,sys; raise SystemExit(0 if json.load(sys.stdin).get("valid") else 1)' >/dev/null 2>&1; then
  exit 0
fi

if [[ "$SONARQUBE_ADMIN_PASSWORD" == "admin" ]]; then
  exit 0
fi

if curl -fsS -u "${SONARQUBE_ADMIN_LOGIN}:admin" "$auth_url" | python3 -c 'import json,sys; raise SystemExit(0 if json.load(sys.stdin).get("valid") else 1)' >/dev/null 2>&1; then
  curl -fsS -u "${SONARQUBE_ADMIN_LOGIN}:admin" -X POST "$change_url" \
    --data-urlencode "login=${SONARQUBE_ADMIN_LOGIN}" \
    --data-urlencode "previousPassword=admin" \
    --data-urlencode "password=${SONARQUBE_ADMIN_PASSWORD}" >/dev/null
fi

