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
load_runtime_env "$app_root/config/sonarqube-serv.env"
load_resolved_images "$app_root/config/resolved-images.env"
ensure_docker_daemon

run_compose \
  -f "$app_root/runtime/docker-compose.yml" \
  --project-name "$SONARQUBE_COMPOSE_PROJECT" \
  --env-file "$app_root/config/sonarqube-serv.env" \
  up -d

"$app_root/bin/bootstrap_admin.sh" --app-root "$app_root"
