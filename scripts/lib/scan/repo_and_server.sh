repo_has_files() {
  local pattern="$1"
  if command -v rg >/dev/null 2>&1; then
    rg --files \
      -g "$pattern" \
      -g '!**/node_modules/**' \
      -g '!**/.git/**' \
      -g '!**/.sonar-local/**' \
      "$repo" >/dev/null 2>&1
  else
    # Fallback for environments without ripgrep
    find "$repo" -type f -name "$pattern" \
      -not -path '*/node_modules/*' \
      -not -path '*/.git/*' \
      -not -path '*/.sonar-local/*' | grep -q .
  fi
}

repo_has_java() {
  [[ -f "$repo/pom.xml" || -f "$repo/build.gradle" || -f "$repo/build.gradle.kts" ]] && return 0
  repo_has_files '*.java' || repo_has_files '*.kt'
}

repo_has_go() {
  [[ -f "$repo/go.mod" ]] && return 0
  repo_has_files '*.go'
}

repo_has_python() {
  repo_has_files '*.py'
}

repo_has_javascript() {
  repo_has_files '*.js' && return 0
  repo_has_files '*.jsx' && return 0
  repo_has_files '*.mjs' && return 0
  repo_has_files '*.cjs' && return 0
  repo_has_files '*.ts' && return 0
  repo_has_files '*.tsx'
}

repo_has_dockerfiles() {
  find "$repo" -type f -name 'Dockerfile*' | grep -q .
}

repo_has_terraform() {
  repo_has_files '*.tf' && return 0
  repo_has_files '*.tfvars' && return 0
  repo_has_files '*.tf.json'
}

repo_has_iac() {
  repo_has_terraform && return 0
  find "$repo" -type f \( \
    -name '*.bicep' \
    -o -name 'Chart.yaml' \
    -o -name 'kustomization.yaml' \
    -o -name '*.template' \
    -o -iname '*cloudformation*.yaml' \
    -o -iname '*cloudformation*.yml' \
    -o -path '*/k8s/*.yaml' \
    -o -path '*/k8s/*.yml' \
    -o -path '*/kubernetes/*.yaml' \
    -o -path '*/kubernetes/*.yml' \
  \) | grep -q .
}

repo_has_dependency_manifests() {
  find "$repo" -type f \( \
    -name 'package-lock.json' \
    -o -name 'yarn.lock' \
    -o -name 'pnpm-lock.yaml' \
    -o -name 'npm-shrinkwrap.json' \
    -o -name 'Pipfile.lock' \
    -o -name 'poetry.lock' \
    -o -name 'requirements.txt' \
    -o -name 'requirements-*.txt' \
    -o -name 'pyproject.toml' \
    -o -name 'go.mod' \
    -o -name 'go.sum' \
    -o -name 'pom.xml' \
    -o -name 'build.gradle' \
    -o -name 'build.gradle.kts' \
    -o -name 'gradle.lockfile' \
    -o -name 'Cargo.lock' \
    -o -name 'Gemfile.lock' \
    -o -name 'composer.lock' \
    -o -name 'packages.lock.json' \
    -o -name 'paket.lock' \
    -o -name '*.csproj' \
  \) | grep -q .
}

detect_profile() {
  if [[ "$profile" != "auto" ]]; then
    print -r -- "$profile"
    return 0
  fi

  if [[ ! -f "$repo/package.json" && ! -f "$repo/pom.xml" && ! -f "$repo/build.gradle" && ! -f "$repo/build.gradle.kts" && ! -f "$repo/requirements.txt" && ! -f "$repo/go.mod" ]] && ! find "$repo" -maxdepth 1 -name "*.sln" -print -quit | grep -q . && ! find "$repo" -maxdepth 1 -name "*.csproj" -print -quit | grep -q .; then
    typeset -a sub_build_files
    while IFS= read -r file; do
      [[ -n "$file" ]] && sub_build_files+=("$file")
    done < <(find "$repo" -mindepth 2 -maxdepth 2 -name "package.json" -o -name "pom.xml" -o -name "build.gradle" -o -name "build.gradle.kts" -o -name "requirements.txt" -o -name "go.mod" -o -name "*.sln" -o -name "*.csproj")

    if [[ ${#sub_build_files[@]} -gt 0 ]]; then
      print -u2 ""
      print -u2 "================================================================================"
      print -u2 "🚨 MONOREPO DETECTED: No root build file found, but subprojects exist."
      print -u2 "Running a unified Sonar scan from the root will likely fail or skip files."
      print -u2 "Please run the scan separately for each component using the --repo flag:"
      print -u2 ""
      
      typeset -A seen_dirs
      for bf in "${sub_build_files[@]}"; do
        local sub_dir
        sub_dir="$(dirname "${bf#$repo/}")"
        if [[ -z "${seen_dirs[$sub_dir]:-}" ]]; then
          seen_dirs[$sub_dir]=1
          local safe_sub_dir="${sub_dir//[^a-zA-Z0-9_]/-}"
          local sub_key="${project_key}_${safe_sub_dir}"
          print -u2 "  scan_project_with_sonarqube.sh --repo \"$repo/$sub_dir\" --project-key \"$sub_key\" [options]"
        fi
      done
      print -u2 "================================================================================"
      print -u2 ""
      exit 1
    fi
  fi

  if [[ -f "$repo/pom.xml" ]]; then
    print -r -- "java-maven"
    return 0
  fi
  if [[ -f "$repo/build.gradle" || -f "$repo/build.gradle.kts" || -f "$repo/settings.gradle" || -f "$repo/settings.gradle.kts" ]]; then
    print -r -- "java-gradle"
    return 0
  fi
  if find "$repo" -maxdepth 1 \( -name "*.sln" -o -name "*.csproj" \) -print -quit | grep -q .; then
    print -r -- "dotnet"
    return 0
  fi
  if [[ -f "$repo/package.json" ]]; then
    print -r -- "js-ts"
    return 0
  fi
  if [[ -f "$repo/go.mod" ]]; then
    print -r -- "go"
    return 0
  fi
  if [[ -f "$repo/requirements.txt" || -f "$repo/pyproject.toml" || -f "$repo/Pipfile" ]]; then
    print -r -- "python"
    return 0
  fi
  if [[ -f "$repo/Makefile" || -f "$repo/CMakeLists.txt" ]]; then
    print -r -- "c-cpp"
    return 0
  fi
  print -r -- "generic"
}

load_local_admin_env() {
  [[ "$local_admin_loaded" == "true" ]] && return 0
  [[ -n "$app_root" ]] || app_root="$(default_app_root)"
  local env_file="$app_root/config/sonarqube-serv.env"
  [[ -f "$env_file" ]] || {
    return 1
  }
  load_runtime_env "$env_file"
  if [[ "$host_url_explicit" != "true" ]]; then
    host_url="http://${SONARQUBE_SERVICE_HOST}:${SONARQUBE_SERVICE_PORT}"
  fi
  local_admin_loaded="true"
}

revoke_temp_token() {
  [[ -n "$temp_token_name" ]] || return 0
  [[ "$local_admin_loaded" == "true" ]] || return 0
  curl -fsS -u "${SONARQUBE_ADMIN_LOGIN}:${SONARQUBE_ADMIN_PASSWORD}" \
    -X POST \
    "$host_url/api/user_tokens/revoke" \
    --data-urlencode "name=${temp_token_name}" >/dev/null 2>&1 || true
}

cleanup_on_exit() {
  local exit_code="$?"
  if [[ "$run_status_initialized" == "true" && "$run_finalized" != "true" ]]; then
    run_result="failed"
    run_state="failed"
    run_phase="failed"
    run_message="scan exited with code ${exit_code}"
    run_completed_at="$(now_utc)"
    write_run_status
    record_run_event "error" "$run_message"
  fi
  revoke_temp_token
  return "$exit_code"
}

trap cleanup_on_exit EXIT

ensure_server_up() {
  local status_json
  status_json="$(curl -fsS "$host_url/api/system/status")"
  local sonar_state
  sonar_state="$(print -r -- "$status_json" | json_get 'data["status"]')"
  [[ "$sonar_state" == "UP" ]] || {
    print -u2 "sonarqube is not ready at $host_url (status=$sonar_state)"
    exit 1
  }
}

ensure_project_exists() {
  [[ "$local_admin_loaded" == "true" ]] || return 0

  local encoded_key exists
  encoded_key="$(urlencode "$project_key")"
  exists="$(curl -fsS -u "${SONARQUBE_ADMIN_LOGIN}:${SONARQUBE_ADMIN_PASSWORD}" \
    "$host_url/api/projects/search?projects=${encoded_key}" | \
    json_get 'data["paging"]["total"]')"

  if [[ "$exists" == "0" ]]; then
    curl -fsS -u "${SONARQUBE_ADMIN_LOGIN}:${SONARQUBE_ADMIN_PASSWORD}" \
      -X POST \
      "$host_url/api/projects/create" \
      --data-urlencode "project=${project_key}" \
      --data-urlencode "name=${project_name}" >/dev/null
  fi
}

generate_temp_token() {
  load_local_admin_env || return 1
  temp_token_name="scan-$(date +%Y%m%d%H%M%S)-$$"
  token="$(curl -fsS -u "${SONARQUBE_ADMIN_LOGIN}:${SONARQUBE_ADMIN_PASSWORD}" \
    -X POST \
    "$host_url/api/user_tokens/generate" \
    --data-urlencode "name=${temp_token_name}" | \
    json_get 'data["token"]')"
}

