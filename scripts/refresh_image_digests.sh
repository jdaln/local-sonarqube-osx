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
mkdir -p "$app_root/config"

sonar_digest="$(resolve_arm64_digest "${SONARQUBE_IMAGE_REPO}:${SONARQUBE_IMAGE_TAG}")"
postgres_digest="$(resolve_arm64_digest "${POSTGRES_IMAGE_REPO}:${POSTGRES_IMAGE_TAG}")"

[[ -n "$sonar_digest" ]] || { print -u2 "failed to resolve SonarQube image digest"; exit 1; }
[[ -n "$postgres_digest" ]] || { print -u2 "failed to resolve PostgreSQL image digest"; exit 1; }

write_resolved_images_env "$app_root/config/resolved-images.env" "$sonar_digest" "$postgres_digest"
print -- "SONARQUBE_IMAGE_REF=${SONARQUBE_IMAGE_REPO}:${SONARQUBE_IMAGE_TAG}@${sonar_digest}"
print -- "POSTGRES_IMAGE_REF=${POSTGRES_IMAGE_REPO}:${POSTGRES_IMAGE_TAG}@${postgres_digest}"

