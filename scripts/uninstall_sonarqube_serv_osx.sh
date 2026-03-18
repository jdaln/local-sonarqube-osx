#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
base_dir="$(cd "$script_dir/.." && pwd)"
source "$script_dir/common.sh"
load_versions "$base_dir"

app_root=""
purge="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root)
      app_root="$2"
      shift 2
      ;;
    --purge)
      purge="true"
      shift 1
      ;;
    *)
      print -u2 "unknown argument: $1"
      exit 1
      ;;
  esac
done

[[ -n "$app_root" ]] || app_root="$(default_app_root)"

env_file="$app_root/config/sonarqube-serv.env"
if [[ -f "$env_file" ]]; then
  load_runtime_env "$env_file"
else
  # Fallback if env file is already gone but script is running from somewhere else
  # or if we're uninstalling from a non-standard location.
  # We still need SONARQUBE_LAUNCHD_LABEL to clean up the agent.
  : "${SONARQUBE_LAUNCHD_LABEL:=com.sonarqube.serv}"
fi

print "Stopping and removing launchd agent: $SONARQUBE_LAUNCHD_LABEL"
launch_agents_dir="$HOME/Library/LaunchAgents"
plist_path="$launch_agents_dir/${SONARQUBE_LAUNCHD_LABEL}.plist"

if [[ -f "$plist_path" ]]; then
  launchctl bootout "gui/$(id -u)/${SONARQUBE_LAUNCHD_LABEL}" >/dev/null 2>&1 || true
  rm "$plist_path"
fi

if [[ -d "$app_root" ]]; then
  print "Stopping SonarQube stack..."
  # Try to run stop script if it exists
  if [[ -f "$app_root/bin/stop_sonarqube_stack.sh" ]]; then
    "$app_root/bin/stop_sonarqube_stack.sh" --app-root "$app_root" >/dev/null 2>&1 || true
  fi

  if [[ "$purge" == "true" ]]; then
    print "Purging data and volumes..."
    if [[ -f "$app_root/runtime/docker-compose.yml" ]]; then
      (cd "$app_root/runtime" && run_compose down -v >/dev/null 2>&1 || true)
    fi
  fi

  print "Removing installation directory: $app_root"
  rm -rf "$app_root"
fi

print "Uninstallation complete."
