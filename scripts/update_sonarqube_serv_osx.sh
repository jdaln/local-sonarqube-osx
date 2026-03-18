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
[[ -d "$app_root" ]] || { print -u2 "missing app root: $app_root"; exit 1; }

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

load_runtime_env "$app_root/config/sonarqube-serv.env"
print "Configuration loaded from: $(default_app_root)/config/sonarqube-serv.env"
ensure_docker_daemon

"$app_root/bin/refresh_image_digests.sh" --app-root "$app_root" >/dev/null
load_resolved_images "$app_root/config/resolved-images.env"
render_compose_file \
  "$app_root/config/docker-compose.yml.template" \
  "$app_root/runtime/docker-compose.yml" \
  "$app_root" \
  "$SONARQUBE_IMAGE_REF" \
  "$POSTGRES_IMAGE_REF"

run_compose \
  -f "$app_root/runtime/docker-compose.yml" \
  --project-name "$SONARQUBE_COMPOSE_PROJECT" \
  --env-file "$app_root/config/sonarqube-serv.env" \
  pull

"$app_root/bin/run_sonarqube_stack.sh" --app-root "$app_root"

launch_agents_dir="$HOME/Library/LaunchAgents"
if [[ -f "$launch_agents_dir/${SONARQUBE_LAUNCHD_LABEL}.plist" ]]; then
  render_launchd_template \
    "$app_root/launchd/local.sonarqube.plist" \
    "$launch_agents_dir/${SONARQUBE_LAUNCHD_LABEL}.plist" \
    "$app_root" \
    "$SONARQUBE_LAUNCHD_LABEL" \
    "$SONARQUBE_BOOTSTRAP_INTERVAL_SECONDS"
  reload_launch_agent "$(id -u)" "$SONARQUBE_LAUNCHD_LABEL" "$launch_agents_dir/${SONARQUBE_LAUNCHD_LABEL}.plist"
fi
