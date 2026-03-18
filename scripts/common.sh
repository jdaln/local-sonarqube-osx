#!/bin/zsh

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

default_app_root() {
  print -- "${HOME}/Library/Application Support/LocalServices/sonarqube-serv"
}

load_versions() {
  local base_dir="$1"
  local versions_file="$base_dir/versions.env"
  if [[ ! -f "$versions_file" ]]; then
    versions_file="$base_dir/config/versions.env"
  fi
  set -a
  source "$versions_file"
  set +a
}

load_runtime_env() {
  local env_file="$1"
  set -a
  source "$env_file"
  set +a
  export APP_ROOT
  export SONARQUBE_SERVICE_HOST
  export SONARQUBE_SERVICE_PORT
  export SONARQUBE_COMPOSE_PROJECT
  export SONARQUBE_ADMIN_LOGIN
  export SONARQUBE_ADMIN_PASSWORD
  export SONARQUBE_DATABASE_NAME
  export SONARQUBE_DATABASE_USER
  export SONARQUBE_DATABASE_PASSWORD
  export SONARQUBE_USE_COLIMA
  export SONARQUBE_COLIMA_PROFILE
  export SONARQUBE_COLIMA_CPU
  export SONARQUBE_COLIMA_MEMORY_GB
  export SONARQUBE_COLIMA_DISK_GB
  export SONARQUBE_LAUNCHD_LABEL
  export SONARQUBE_ADDITIONAL_BIND_ADDRESS
}

generate_secret() {
  openssl rand -hex 24
}

write_runtime_env() {
  local env_file="$1"
  local app_root="$2"
  local database_password
  local admin_password

  database_password="$(generate_secret)"
  admin_password="$(generate_secret)"

  cat > "$env_file" <<EOF
APP_ROOT="$app_root"
SONARQUBE_SERVICE_HOST="127.0.0.1"
SONARQUBE_SERVICE_PORT="$SONARQUBE_HOST_PORT"
SONARQUBE_COMPOSE_PROJECT="local-sonarqube"
SONARQUBE_ADMIN_LOGIN="admin"
SONARQUBE_ADMIN_PASSWORD="$admin_password"
SONARQUBE_DATABASE_NAME="sonarqube"
SONARQUBE_DATABASE_USER="sonarqube"
SONARQUBE_DATABASE_PASSWORD="$database_password"
SONARQUBE_USE_COLIMA="true"
SONARQUBE_COLIMA_PROFILE="sonarqube"
SONARQUBE_COLIMA_CPU="4"
SONARQUBE_COLIMA_MEMORY_GB="8"
SONARQUBE_COLIMA_DISK_GB="60"
SONARQUBE_LAUNCHD_LABEL="$SONARQUBE_LAUNCHD_LABEL"
SONARQUBE_ADDITIONAL_BIND_ADDRESS=""
EOF
  chmod 600 "$env_file"
}

ensure_directory_layout() {
  local app_root="$1"
  mkdir -p \
    "$app_root/bin" \
    "$app_root/config" \
    "$app_root/docs" \
    "$app_root/launchd" \
    "$app_root/runtime" \
    "$app_root/state/postgres" \
    "$app_root/state/sonarqube/data" \
    "$app_root/state/sonarqube/extensions" \
    "$app_root/state/sonarqube/logs" \
    "$app_root/state/sonarqube/temp"
}

ensure_docker_daemon() {
  if docker info >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${SONARQUBE_USE_COLIMA:l}" == "true" ]] && command -v colima >/dev/null 2>&1; then
    colima start \
      --profile "$SONARQUBE_COLIMA_PROFILE" \
      --cpu "$SONARQUBE_COLIMA_CPU" \
      --memory "$SONARQUBE_COLIMA_MEMORY_GB" \
      --disk "$SONARQUBE_COLIMA_DISK_GB"
  fi

  docker info >/dev/null 2>&1 || {
    print -u2 "docker daemon is unavailable"
    return 1
  }
}

run_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
    return
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
    return
  fi

  print -u2 "no supported compose frontend found"
  return 1
}

resolve_arm64_digest() {
  local image_ref="$1"
  docker manifest inspect "$image_ref" | jq -r '
    .manifests[]
    | select(.platform.os == "linux" and .platform.architecture == "arm64")
    | .digest
    ' | head -n 1
}

write_resolved_images_env() {
  local destination="$1"
  local sonar_digest="$2"
  local postgres_digest="$3"

  cat > "$destination" <<EOF
SONARQUBE_IMAGE_REF="${SONARQUBE_IMAGE_REPO}:${SONARQUBE_IMAGE_TAG}@${sonar_digest}"
POSTGRES_IMAGE_REF="${POSTGRES_IMAGE_REPO}:${POSTGRES_IMAGE_TAG}@${postgres_digest}"
EOF
}

load_resolved_images() {
  local env_file="$1"
  set -a
  source "$env_file"
  set +a
  export SONARQUBE_IMAGE_REF
  export POSTGRES_IMAGE_REF
}

render_compose_file() {
  local template="$1"
  local destination="$2"
  local app_root="$3"
  local sonar_image_ref="$4"
  local postgres_image_ref="$5"
  local platform="${6:-linux/arm64}"
  local escaped_root="${app_root//&/\\&}"
  local escaped_sonar="${sonar_image_ref//&/\\&}"
  local escaped_postgres="${postgres_image_ref//&/\\&}"

  local bind_hosts=("${SONARQUBE_SERVICE_HOST:-127.0.0.1}")
  if [[ -n "${SONARQUBE_ADDITIONAL_BIND_ADDRESS:-}" ]]; then
    # Split by comma if multiple additional addresses are provided
    local add_hosts=("${(@s:,:)SONARQUBE_ADDITIONAL_BIND_ADDRESS}")
    bind_hosts+=("${add_hosts[@]}")
  fi

  local ports_block=""
  for host in "${bind_hosts[@]}"; do
    ports_block="${ports_block}      - \"${host}:\${SONARQUBE_SERVICE_PORT}:9000\"\\n"
  done
  # Remove the trailing newline
  ports_block="${ports_block%\\n}"

  sed \
    -e "s|__APP_ROOT__|$escaped_root|g" \
    -e "s|__SONARQUBE_IMAGE_REF__|$escaped_sonar|g" \
    -e "s|__POSTGRES_IMAGE_REF__|$escaped_postgres|g" \
    -e "s|__PLATFORM__|$platform|g" \
    -e "s|__PORTS__|$ports_block|g" \
    "$template" > "$destination"
}

render_launchd_template() {
  local template="$1"
  local destination="$2"
  local app_root="$3"
  local label="$4"
  local interval="$5"
  local escaped_root="${app_root//&/\\&}"
  local escaped_label="${label//&/\\&}"

  sed \
    -e "s|__APP_ROOT__|$escaped_root|g" \
    -e "s|__SONARQUBE_LAUNCHD_LABEL__|$escaped_label|g" \
    -e "s|<integer>300</integer>|<integer>${interval}</integer>|" \
    "$template" > "$destination"
}

wait_for_http() {
  local url="$1"
  local attempts="${2:-120}"
  local sleep_seconds="${3:-5}"
  local count=0

  until curl -fsS "$url" >/dev/null 2>&1; do
    (( count += 1 ))
    if (( count >= attempts )); then
      return 1
    fi
    sleep "$sleep_seconds"
  done
}

sonarqube_status() {
  local url="$1"
  curl -fsS "$url" | python3 - <<'PY'
import json
import sys
print(json.load(sys.stdin)["status"])
PY
}

wait_for_sonarqube_up() {
  local url="$1"
  local attempts="${2:-120}"
  local sleep_seconds="${3:-5}"
  local count=0
  local sonar_state=""

  until false; do
    sonar_state="$(curl -fsS "$url" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)"
    if [[ "$sonar_state" == "UP" ]]; then
      return 0
    fi
    (( count += 1 ))
    if (( count >= attempts )); then
      print -u2 "timed out waiting for SonarQube to reach UP; last status=${sonar_state:-unavailable}"
      return 1
    fi
    sleep "$sleep_seconds"
  done
}

reload_launch_agent() {
  local uid="$1"
  local label="$2"
  local plist_path="$3"

  launchctl bootout "gui/${uid}/${label}" >/dev/null 2>&1 || true
  if ! launchctl bootstrap "gui/${uid}" "$plist_path" >/dev/null 2>&1; then
    if ! launchctl print "gui/${uid}/${label}" >/dev/null 2>&1; then
      print -u2 "failed to bootstrap launch agent: $label"
      return 1
    fi
  fi
  launchctl kickstart -k "gui/${uid}/${label}" >/dev/null 2>&1 || true
}
