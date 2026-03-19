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
auth_probe_url="http://${SONARQUBE_SERVICE_HOST}:${SONARQUBE_SERVICE_PORT}/api/users/search?logins=${SONARQUBE_ADMIN_LOGIN}"
change_url="http://${SONARQUBE_SERVICE_HOST}:${SONARQUBE_SERVICE_PORT}/api/users/change_password"

auth_ok() {
  local login="$1"
  local password="$2"
  curl -fsS -u "${login}:${password}" "$auth_probe_url" >/dev/null 2>&1
}

wait_for_sonarqube_up "$status_url" 180 5

if auth_ok "${SONARQUBE_ADMIN_LOGIN}" "${SONARQUBE_ADMIN_PASSWORD}"; then
  exit 0
fi

if [[ "$SONARQUBE_ADMIN_PASSWORD" == "admin" ]]; then
  print -u2 "failed to verify SonarQube admin credentials"
  exit 1
fi

if auth_ok "${SONARQUBE_ADMIN_LOGIN}" "admin"; then
  curl -fsS -u "${SONARQUBE_ADMIN_LOGIN}:admin" -X POST "$change_url" \
    --data-urlencode "login=${SONARQUBE_ADMIN_LOGIN}" \
    --data-urlencode "previousPassword=admin" \
    --data-urlencode "password=${SONARQUBE_ADMIN_PASSWORD}" >/dev/null
fi

if auth_ok "${SONARQUBE_ADMIN_LOGIN}" "${SONARQUBE_ADMIN_PASSWORD}"; then
  exit 0
fi

print -u2 "failed to verify SonarQube admin credentials after bootstrap"
exit 1
