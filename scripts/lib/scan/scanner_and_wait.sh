build_js_ts_command() {
  typeset -a props
  typeset -a lcov_paths
  local eslint_report=""

  props+=("-Dsonar.projectKey=${project_key}")
  props+=("-Dsonar.projectName=${project_name}")
  props+=("-Dsonar.host.url=${host_url}")
  props+=("-Dsonar.token=${token}")
  props+=("-Dsonar.login=${token}")
  props+=("-Dsonar.sources=.")
  props+=("-Dsonar.exclusions=**/node_modules/**,**/dist/**,**/coverage/**")

  if [[ -d "$repo/src" ]] && rg -n --glob '*.spec.ts' --glob '*.test.ts' '.' "$repo/src" >/dev/null 2>&1; then
    props+=("-Dsonar.tests=src")
    props+=("-Dsonar.test.inclusions=**/*.spec.ts,**/*.test.ts")
  fi

  while read -r path; do
    [[ -n "$path" ]] && lcov_paths+=("$path")
  done < <(collect_lcov_paths)
  [[ ${#lcov_paths[@]} -gt 0 ]] && props+=("-Dsonar.javascript.lcov.reportPaths=$(join_csv "${lcov_paths[@]}")")

  for item in "${generated_reports[@]}"; do
    if [[ "$item" == eslint:* ]]; then
      eslint_report="${item#eslint:}"
    fi
  done
  [[ -n "$eslint_report" ]] && props+=("-Dsonar.eslint.reportPaths=$(normalize_report_path "$eslint_report")")

  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    props+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi

  local prop
  for prop in "${extra_properties[@]}"; do
    props+=("-D${prop}")
  done

  typeset -a cmd
  cmd=(npx -y @sonar/scan)
  cmd+=("${props[@]}")
  printf '%s\n' "${cmd[@]}"
}

build_java_maven_command() {
  typeset -a cmd
  cmd=(mvn -B)
  if [[ "$prepare" == "true" ]]; then
    cmd+=(clean verify)
  else
    cmd+=(clean compile -DskipTests)
  fi
  cmd+=(org.sonarsource.scanner.maven:sonar-maven-plugin:sonar)
  cmd+=("-Dsonar.projectKey=${project_key}")
  cmd+=("-Dsonar.projectName=${project_name}")
  cmd+=("-Dsonar.host.url=${host_url}")
  cmd+=("-Dsonar.token=${token}")
  cmd+=("-Dsonar.login=${token}")
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    cmd+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  if [[ ${#spotbugs_reports[@]} -gt 0 ]]; then
    cmd+=("-Dsonar.java.spotbugs.reportPaths=$(join_csv "${spotbugs_reports[@]}")")
  fi
  local prop
  for prop in "${extra_properties[@]}"; do
    cmd+=("-D${prop}")
  done
  printf '%s\n' "${cmd[@]}"
}

build_java_gradle_command() {
  local gradle_cmd="./gradlew"
  [[ -x "$repo/gradlew" ]] || gradle_cmd="gradle"
  typeset -a cmd
  cmd=("$gradle_cmd")
  if [[ "$prepare" == "true" ]]; then
    cmd+=(clean test jacocoTestReport sonarqube)
  else
    cmd+=(clean compileJava -x test sonarqube)
  fi
  cmd+=("-Dsonar.projectKey=${project_key}")
  cmd+=("-Dsonar.projectName=${project_name}")
  cmd+=("-Dsonar.host.url=${host_url}")
  cmd+=("-Dsonar.token=${token}")
  cmd+=("-Dsonar.login=${token}")
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    cmd+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  if [[ ${#spotbugs_reports[@]} -gt 0 ]]; then
    cmd+=("-Dsonar.java.spotbugs.reportPaths=$(join_csv "${spotbugs_reports[@]}")")
  fi
  local prop
  for prop in "${extra_properties[@]}"; do
    cmd+=("-D${prop}")
  done
  printf '%s\n' "${cmd[@]}"
}

build_generic_command() {
  typeset -a cmd
  local scanner_host_url="$host_url"

  if command -v sonar-scanner >/dev/null 2>&1; then
    cmd=(sonar-scanner)
  elif command -v npm >/dev/null 2>&1; then
    print -u2 -- "[scan] sonar-scanner not found; using npx @sonar/scan for generic profile"
    cmd=(npx -y @sonar/scan)
  elif command -v docker >/dev/null 2>&1; then
    print -u2 -- "[scan] sonar-scanner and npm not found; using sonarsource/sonar-scanner-cli container"
    scanner_host_url="${scanner_host_url/127.0.0.1/host.docker.internal}"
    scanner_host_url="${scanner_host_url/localhost/host.docker.internal}"
    cmd=(docker run --rm -v "$repo:/usr/src" -w /usr/src sonarsource/sonar-scanner-cli)
  else
    print -u2 "generic profile requires one of: sonar-scanner, npm (for npx @sonar/scan), or docker"
    return 1
  fi

  cmd+=("-Dsonar.projectKey=${project_key}")
  cmd+=("-Dsonar.projectName=${project_name}")
  cmd+=("-Dsonar.host.url=${scanner_host_url}")
  cmd+=("-Dsonar.token=${token}")
  cmd+=("-Dsonar.login=${token}")
  cmd+=("-Dsonar.sources=.")
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    cmd+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  local prop
  for prop in "${extra_properties[@]}"; do
    cmd+=("-D${prop}")
  done
  printf '%s\n' "${cmd[@]}"
}

build_java_fallback_generic_command() {
  typeset -a props
  typeset -a cmd
  typeset -a source_paths
  typeset -a test_paths
  typeset -a main_binaries
  typeset -a test_binaries
  typeset -a jacoco_paths
  local scanner_host_url="$host_url"

  props+=("-Dsonar.projectKey=${project_key}")
  props+=("-Dsonar.projectName=${project_name}")
  props+=("-Dsonar.host.url=${scanner_host_url}")
  props+=("-Dsonar.token=${token}")
  props+=("-Dsonar.login=${token}")
  props+=("-Dsonar.exclusions=**/target/**,**/build/**")

  [[ -d "$repo/src/main/java" ]] && source_paths+=(src/main/java)
  [[ -d "$repo/src/main/resources" ]] && source_paths+=(src/main/resources)
  if (( ${#source_paths[@]} > 0 )); then
    props+=("-Dsonar.sources=$(join_csv "${source_paths[@]}")")
  else
    props+=("-Dsonar.sources=.")
  fi

  [[ -d "$repo/src/test/java" ]] && test_paths+=(src/test/java)
  [[ -d "$repo/src/test/resources" ]] && test_paths+=(src/test/resources)
  if (( ${#test_paths[@]} > 0 )); then
    props+=("-Dsonar.tests=$(join_csv "${test_paths[@]}")")
  fi

  [[ -d "$repo/target/classes" ]] && main_binaries+=(target/classes)
  [[ -d "$repo/build/classes/java/main" ]] && main_binaries+=(build/classes/java/main)
  [[ -d "$repo/build/classes/kotlin/main" ]] && main_binaries+=(build/classes/kotlin/main)
  if (( ${#main_binaries[@]} > 0 )); then
    props+=("-Dsonar.java.binaries=$(join_csv "${main_binaries[@]}")")
  else
    props+=("-Dsonar.java.binaries=.")
  fi

  [[ -d "$repo/target/test-classes" ]] && test_binaries+=(target/test-classes)
  [[ -d "$repo/build/classes/java/test" ]] && test_binaries+=(build/classes/java/test)
  [[ -d "$repo/build/classes/kotlin/test" ]] && test_binaries+=(build/classes/kotlin/test)
  if (( ${#test_binaries[@]} > 0 )); then
    props+=("-Dsonar.java.test.binaries=$(join_csv "${test_binaries[@]}")")
  fi

  [[ -d "$repo/target/surefire-reports" ]] && props+=("-Dsonar.junit.reportPaths=target/surefire-reports")
  [[ -d "$repo/build/test-results/test" ]] && props+=("-Dsonar.junit.reportPaths=build/test-results/test")

  [[ -f "$repo/target/site/jacoco/jacoco.xml" ]] && jacoco_paths+=(target/site/jacoco/jacoco.xml)
  [[ -f "$repo/target/site/jacoco-it/jacoco.xml" ]] && jacoco_paths+=(target/site/jacoco-it/jacoco.xml)
  [[ -f "$repo/build/reports/jacoco/test/jacocoTestReport.xml" ]] && jacoco_paths+=(build/reports/jacoco/test/jacocoTestReport.xml)
  if (( ${#jacoco_paths[@]} > 0 )); then
    props+=("-Dsonar.coverage.jacoco.xmlReportPaths=$(join_csv "${jacoco_paths[@]}")")
  fi

  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    props+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  if [[ ${#spotbugs_reports[@]} -gt 0 ]]; then
    props+=("-Dsonar.java.spotbugs.reportPaths=$(join_csv "${spotbugs_reports[@]}")")
  fi

  local prop
  for prop in "${extra_properties[@]}"; do
    props+=("-D${prop}")
  done

  if command -v sonar-scanner >/dev/null 2>&1; then
    cmd=(sonar-scanner)
  elif command -v npm >/dev/null 2>&1; then
    cmd=(npx -y @sonar/scan)
  elif command -v docker >/dev/null 2>&1; then
    scanner_host_url="${scanner_host_url/127.0.0.1/host.docker.internal}"
    scanner_host_url="${scanner_host_url/localhost/host.docker.internal}"
    props[3]="-Dsonar.host.url=${scanner_host_url}"
    cmd=(docker run --rm -v "$repo:/usr/src" -w /usr/src sonarsource/sonar-scanner-cli)
  else
    print -u2 "generic Java fallback requires one of: sonar-scanner, npm (for npx @sonar/scan), or docker"
    return 1
  fi

  cmd+=("${props[@]}")
  printf '%s\n' "${cmd[@]}"
}

execute_scanner_with_recovery() {
  local primary_command="$1"
  if execute_multiline_command "$primary_command"; then
    return 0
  fi

  local exit_code=$?
  if [[ "$resolved_profile" != "java-maven" && "$resolved_profile" != "java-gradle" ]]; then
    return $exit_code
  fi

  log_warn "build-integrated ${resolved_profile} scan failed; retrying with generic Java fallback"
  set_run_phase "scanner-fallback" "running" "primary Java scan failed; retrying with generic scanner fallback"

  local fallback_command
  fallback_command="$(build_java_fallback_generic_command)" || return $exit_code
  print -r -- "$fallback_command" > "$run_dir/scanner-command-fallback.txt"
  execute_multiline_command "$fallback_command"
}

execute_multiline_command() {
  local multiline="$1"
  typeset -a cmd
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && cmd+=("$line")
  done <<< "$multiline"
  (cd "$repo" && run_logged "${cmd[@]}")
}

find_report_task_file() {
  typeset -a candidates
  candidates=(
    "$repo/.scannerwork/report-task.txt"
    "$repo/target/sonar/report-task.txt"
    "$repo/build/sonar/report-task.txt"
    "$repo/.sonarqube/out/.sonar/report-task.txt"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}

report_task_value() {
  local file="$1"
  local key="$2"
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1) }' "$file"
}

normalize_for_host_curl() {
  local url="$1"
  print -r -- "${url//host.docker.internal/127.0.0.1}"
}

wait_for_background_task() {
  [[ "$dry_run" == "true" ]] && return 0

  local report_task_file ce_task_url ce_task_id task_json task_status analysis_id quality_json
  last_analysis_id=""
  quality_gate_status=""
  report_task_file="$(find_report_task_file 2>/dev/null || true)"
  [[ -n "$report_task_file" ]] || return 0

  ce_task_url="$(report_task_value "$report_task_file" ceTaskUrl)"
  ce_task_id="$(report_task_value "$report_task_file" ceTaskId)"
  [[ -n "$ce_task_url" ]] || [[ -n "$ce_task_id" ]] || return 0
  [[ -n "$ce_task_url" ]] || ce_task_url="${host_url}/api/ce/task?id=${ce_task_id}"
  ce_task_url="$(normalize_for_host_curl "$ce_task_url")"

  local attempt=0
  while (( attempt < 120 )); do
    task_json="$(curl -fsS -u "${token}:" "$ce_task_url")"
    task_status="$(print -r -- "$task_json" | json_get 'data["task"]["status"]')"
    case "$task_status" in
      SUCCESS)
        analysis_id="$(print -r -- "$task_json" | json_get 'data["task"].get("analysisId", "")')"
        last_analysis_id="$analysis_id"
        if [[ -n "$analysis_id" ]]; then
          quality_json="$(curl -fsS -u "${token}:" "$(normalize_for_host_curl "${host_url}/api/qualitygates/project_status?analysisId=${analysis_id}")")"
          quality_gate_status="$(print -r -- "$quality_json" | json_get 'data["projectStatus"]["status"]')"
          print "analysis=SUCCESS quality_gate=${quality_gate_status}"
        else
          print "analysis=SUCCESS"
        fi
        return 0
        ;;
      FAILED|CANCELED)
        print -u2 "analysis task failed with status=${task_status}"
        return 1
        ;;
    esac
    attempt=$(( attempt + 1 ))
    sleep 2
  done

  print -u2 "timed out waiting for SonarQube background task"
  return 1
}
build_dotnet_command() {
  if ! command -v dotnet-sonarscanner >/dev/null 2>&1; then
    print -u2 -- "[scan][error] dotnet-sonarscanner not found; required for .NET projects."
    print -u2 -- "Install via: dotnet tool install --global dotnet-sonarscanner"
    return 1
  fi
  typeset -a props
  props+=("/k:${project_key}")
  props+=("/n:${project_name}")
  props+=("/d:sonar.host.url=${host_url}")
  props+=("/d:sonar.token=${token}")
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    props+=("/d:sonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  for prop in "${extra_properties[@]}"; do
    props+=("/d:${prop}")
  done

  typeset -a cmd
  cmd=(bash -c "dotnet sonarscanner begin ${(j: :)props} && dotnet build && dotnet sonarscanner end /d:sonar.token=\"${token}\"")
  printf '%s\n' "${cmd[@]}" 
}

build_python_command() {
  typeset -a props
  props+=("-Dsonar.projectKey=${project_key}")
  props+=("-Dsonar.projectName=${project_name}")
  props+=("-Dsonar.host.url=${host_url}")
  props+=("-Dsonar.token=${token}")
  props+=("-Dsonar.sources=.")
  props+=("-Dsonar.exclusions=**/venv/**,**/.venv/**,**/.tox/**,**/__pycache__/**")
  
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    props+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  for prop in "${extra_properties[@]}"; do
    props+=("-D${prop}")
  done

  typeset -a cmd
  if command -v sonar-scanner >/dev/null 2>&1; then
    cmd=(sonar-scanner)
  else
    cmd=(npx -y @sonar/scan)
  fi
  cmd+=("${props[@]}")
  print -r -- "${(j: :)cmd}"
}

build_go_command() {
  typeset -a props
  props+=("-Dsonar.projectKey=${project_key}")
  props+=("-Dsonar.projectName=${project_name}")
  props+=("-Dsonar.host.url=${host_url}")
  props+=("-Dsonar.token=${token}")
  props+=("-Dsonar.sources=.")
  props+=("-Dsonar.exclusions=**/vendor/**")
  
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    props+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  for prop in "${extra_properties[@]}"; do
    props+=("-D${prop}")
  done

  typeset -a cmd
  if command -v sonar-scanner >/dev/null 2>&1; then
    cmd=(sonar-scanner)
  else
    cmd=(npx -y @sonar/scan)
  fi
  cmd+=("${props[@]}")
  print -r -- "${(j: :)cmd}"
}

build_c_cpp_command() {
  typeset -a props
  props+=("-Dsonar.projectKey=${project_key}")
  props+=("-Dsonar.projectName=${project_name}")
  props+=("-Dsonar.host.url=${host_url}")
  props+=("-Dsonar.token=${token}")
  props+=("-Dsonar.sources=.")
  
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    props+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  for prop in "${extra_properties[@]}"; do
    props+=("-D${prop}")
  done

  typeset -a cmd
  if command -v sonar-scanner >/dev/null 2>&1; then
    cmd=(sonar-scanner)
  else
    cmd=(npx -y @sonar/scan)
  fi
  cmd+=("${props[@]}")
  print -u2 -- "[scan][warn] C/C++ SonarQube analysis requires Developer Edition or SonarCloud natively."
  print -u2 -- "[scan][info] Falling back to generic scanner. Third-party SARIF issues will still be imported."
  print -r -- "${(j: :)cmd}"
}
build_python_command() {
  typeset -a props
  props+=("-Dsonar.projectKey=${project_key}")
  props+=("-Dsonar.projectName=${project_name}")
  props+=("-Dsonar.host.url=${host_url}")
  props+=("-Dsonar.token=${token}")
  props+=("-Dsonar.sources=.")
  props+=("-Dsonar.exclusions=**/venv/**,**/.venv/**,**/.tox/**,**/__pycache__/**")
  
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    props+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  for prop in "${extra_properties[@]}"; do
    props+=("-D${prop}")
  done

  typeset -a cmd
  if command -v sonar-scanner >/dev/null 2>&1; then
    cmd=(sonar-scanner)
  else
    cmd=(npx -y @sonar/scan)
  fi
  cmd+=("${props[@]}")
  print -r -- "${(j: :)cmd}"
}

build_go_command() {
  typeset -a props
  props+=("-Dsonar.projectKey=${project_key}")
  props+=("-Dsonar.projectName=${project_name}")
  props+=("-Dsonar.host.url=${host_url}")
  props+=("-Dsonar.token=${token}")
  props+=("-Dsonar.sources=.")
  props+=("-Dsonar.exclusions=**/vendor/**")
  
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    props+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  for prop in "${extra_properties[@]}"; do
    props+=("-D${prop}")
  done

  typeset -a cmd
  if command -v sonar-scanner >/dev/null 2>&1; then
    cmd=(sonar-scanner)
  else
    cmd=(npx -y @sonar/scan)
  fi
  cmd+=("${props[@]}")
  print -r -- "${(j: :)cmd}"
}

build_c_cpp_command() {
  typeset -a props
  props+=("-Dsonar.projectKey=${project_key}")
  props+=("-Dsonar.projectName=${project_name}")
  props+=("-Dsonar.host.url=${host_url}")
  props+=("-Dsonar.token=${token}")
  props+=("-Dsonar.sources=.")
  
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    props+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  for prop in "${extra_properties[@]}"; do
    props+=("-D${prop}")
  done

  typeset -a cmd
  if command -v sonar-scanner >/dev/null 2>&1; then
    cmd=(sonar-scanner)
  else
    cmd=(npx -y @sonar/scan)
  fi
  cmd+=("${props[@]}")
  print -u2 -- "[scan][warn] C/C++ SonarQube analysis requires Developer Edition or SonarCloud natively."
  print -u2 -- "[scan][info] Falling back to generic scanner. Third-party SARIF issues will still be imported."
  print -r -- "${(j: :)cmd}"
}

build_dotnet_command() {
  if ! command -v dotnet-sonarscanner >/dev/null 2>&1; then
    print -u2 -- "[scan][error] dotnet-sonarscanner not found; required for .NET projects."
    print -u2 -- "Install via: dotnet tool install --global dotnet-sonarscanner"
    return 1
  fi
  typeset -a props
  props+=("/k:${project_key}")
  props+=("/n:${project_name}")
  props+=("/d:sonar.host.url=${host_url}")
  props+=("/d:sonar.token=${token}")
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    props+=("/d:sonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  for prop in "${extra_properties[@]}"; do
    props+=("/d:${prop}")
  done

  typeset -a cmd
  cmd=(bash -c "dotnet sonarscanner begin ${(j: :)props} && dotnet build && dotnet sonarscanner end /d:sonar.token=\"${token}\"")
  printf '%s\n' "${cmd[@]}" 
}

build_python_command() {
  typeset -a props
  props+=("-Dsonar.projectKey=${project_key}")
  props+=("-Dsonar.projectName=${project_name}")
  props+=("-Dsonar.host.url=${host_url}")
  props+=("-Dsonar.token=${token}")
  props+=("-Dsonar.sources=.")
  props+=("-Dsonar.exclusions=**/venv/**,**/.venv/**,**/.tox/**,**/__pycache__/**")
  
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    props+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  for prop in "${extra_properties[@]}"; do
    props+=("-D${prop}")
  done

  typeset -a cmd
  if command -v sonar-scanner >/dev/null 2>&1; then
    cmd=(sonar-scanner)
  else
    cmd=(npx -y @sonar/scan)
  fi
  cmd+=("${props[@]}")
  printf '%s\n' "${cmd[@]}"
}

build_go_command() {
  typeset -a props
  props+=("-Dsonar.projectKey=${project_key}")
  props+=("-Dsonar.projectName=${project_name}")
  props+=("-Dsonar.host.url=${host_url}")
  props+=("-Dsonar.token=${token}")
  props+=("-Dsonar.sources=.")
  props+=("-Dsonar.exclusions=**/vendor/**")
  
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    props+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  for prop in "${extra_properties[@]}"; do
    props+=("-D${prop}")
  done

  typeset -a cmd
  if command -v sonar-scanner >/dev/null 2>&1; then
    cmd=(sonar-scanner)
  else
    cmd=(npx -y @sonar/scan)
  fi
  cmd+=("${props[@]}")
  printf '%s\n' "${cmd[@]}"
}

build_c_cpp_command() {
  typeset -a props
  props+=("-Dsonar.projectKey=${project_key}")
  props+=("-Dsonar.projectName=${project_name}")
  props+=("-Dsonar.host.url=${host_url}")
  props+=("-Dsonar.token=${token}")
  props+=("-Dsonar.sources=.")
  
  if [[ ${#sarif_reports[@]} -gt 0 ]]; then
    props+=("-Dsonar.sarifReportPaths=$(join_csv "${sarif_reports[@]}")")
  fi
  for prop in "${extra_properties[@]}"; do
    props+=("-D${prop}")
  done

  typeset -a cmd
  if command -v sonar-scanner >/dev/null 2>&1; then
    cmd=(sonar-scanner)
  else
    cmd=(npx -y @sonar/scan)
  fi
  cmd+=("${props[@]}")
  print -u2 -- "[scan][warn] C/C++ SonarQube analysis requires Developer Edition or SonarCloud natively."
  print -u2 -- "[scan][info] Falling back to generic scanner. Third-party SARIF issues will still be imported."
  printf '%s\n' "${cmd[@]}"
}
