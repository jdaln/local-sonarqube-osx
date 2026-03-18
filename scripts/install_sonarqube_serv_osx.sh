#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
base_dir="$(cd "$script_dir/.." && pwd)"
source "$script_dir/common.sh"
load_versions "$base_dir"

app_root=""
no_launchd="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root)
      app_root="$2"
      shift 2
      ;;
    --no-launchd)
      no_launchd="true"
      shift 1
      ;;
    *)
      print -u2 "unknown argument: $1"
      exit 1
      ;;
  esac
done

[[ -n "$app_root" ]] || app_root="$(default_app_root)"
ensure_directory_layout "$app_root"

rsync -a "$base_dir/scripts/" "$app_root/bin/"
rsync -a "$base_dir/docs/" "$app_root/docs/"
rsync -a "$base_dir/launchd/" "$app_root/launchd/"
cp "$base_dir/LICENSE" "$app_root/LICENSE"
cp "$base_dir/versions.env" "$app_root/config/versions.env"
cp "$base_dir/config/docker-compose.yml.template" "$app_root/config/docker-compose.yml.template"
cp "$base_dir/config/sonarqube-serv.env.example" "$app_root/config/sonarqube-serv.env.example"
chmod 755 "$app_root/bin/"*.sh

mkdir -p "$app_root/state/sonarqube/extensions/plugins"
if [[ -f "$base_dir/config/sonar-cxx-plugin.jar" ]]; then
  cp "$base_dir/config/sonar-cxx-plugin.jar" "$app_root/state/sonarqube/extensions/plugins/sonar-cxx-plugin.jar"
fi

env_file="$app_root/config/sonarqube-serv.env"
if [[ ! -f "$env_file" ]]; then
  write_runtime_env "$env_file" "$app_root"
fi
chmod 600 "$env_file"
load_runtime_env "$env_file"
print "Configuration loaded from: ${env_file}"
ensure_docker_daemon

"$app_root/bin/refresh_image_digests.sh" --app-root "$app_root" >/dev/null
load_resolved_images "$app_root/config/resolved-images.env"
render_compose_file \
  "$app_root/config/docker-compose.yml.template" \
  "$app_root/runtime/docker-compose.yml" \
  "$app_root" \
  "$SONARQUBE_IMAGE_REF" \
  "$POSTGRES_IMAGE_REF"

"$app_root/bin/run_sonarqube_stack.sh" --app-root "$app_root"

if [[ "$no_launchd" == "true" ]]; then
  exit 0
fi

launch_agents_dir="$HOME/Library/LaunchAgents"
mkdir -p "$launch_agents_dir"
render_launchd_template \
  "$app_root/launchd/local.sonarqube.plist" \
  "$launch_agents_dir/${SONARQUBE_LAUNCHD_LABEL}.plist" \
  "$app_root" \
  "$SONARQUBE_LAUNCHD_LABEL" \
  "$SONARQUBE_BOOTSTRAP_INTERVAL_SECONDS"

reload_launch_agent "$(id -u)" "$SONARQUBE_LAUNCHD_LABEL" "$launch_agents_dir/${SONARQUBE_LAUNCHD_LABEL}.plist"
