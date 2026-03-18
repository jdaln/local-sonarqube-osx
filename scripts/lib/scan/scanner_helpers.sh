collect_lcov_paths() {
  local coverage_dir="$repo/coverage"
  [[ -d "$coverage_dir" ]] || return 0
  find "$coverage_dir" -name lcov.info -type f | while read -r path; do
    normalize_report_path "$path"
  done
}

