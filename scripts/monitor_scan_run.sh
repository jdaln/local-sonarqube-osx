#!/bin/zsh
set -euo pipefail

repo=""
run_id=""
interval="2"
once="false"

usage() {
  cat <<'USAGE'
Usage:
  monitor_scan_run.sh --repo PATH [--run-id ID] [--interval SEC] [--once]

Watches scan status from:
  <repo>/.sonar-local/runs/<run-id>/status.json

If --run-id is omitted, the latest run directory is used.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="$2"
      shift 2
      ;;
    --run-id)
      run_id="$2"
      shift 2
      ;;
    --interval)
      interval="$2"
      shift 2
      ;;
    --once)
      once="true"
      shift 1
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      print -u2 "unknown arg: $1"
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "$repo" ]] || { print -u2 "--repo is required"; exit 1; }
repo="$(cd "$repo" && pwd)"
[[ -d "$repo" ]] || { print -u2 "missing repo: $repo"; exit 1; }

runs_root="$repo/.sonar-local/runs"
[[ -d "$runs_root" ]] || { print -u2 "no runs directory: $runs_root"; exit 1; }

pick_latest_run() {
  local latest
  latest="$(find "$runs_root" -mindepth 1 -maxdepth 1 -type d ! -name latest -print0 2>/dev/null | xargs -0 ls -td 2>/dev/null | head -n 1 || true)"
  [[ -n "$latest" ]] && basename "$latest"
}

if [[ -z "$run_id" ]]; then
  run_id="$(pick_latest_run)"
fi
[[ -n "$run_id" ]] || { print -u2 "no run id found under $runs_root"; exit 1; }

status_file="$runs_root/$run_id/status.json"
[[ -f "$status_file" ]] || { print -u2 "missing status file: $status_file"; exit 1; }

print_snapshot() {
  local resources=""
  local pid
  pid="$(python3 - "$status_file" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get("scan_pid") or 0)
PY
)"

  if [[ "$pid" == <-> ]] && ps -p "$pid" >/dev/null 2>&1; then
    resources="$(ps -o %cpu= -o rss= -p "$pid" | awk '{printf "cpu=%s%% mem_mb=%.1f", $1, $2/1024}')"
  else
    resources="cpu=n/a mem_mb=n/a"
  fi

  python3 - "$status_file" "$resources" <<'PY'
import json
import sys

path = sys.argv[1]
resources = sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

print(f"time={data.get('updated_at','')}")
print(f"run_id={data.get('run_id','')} state={data.get('state','')} phase={data.get('phase','')} result={data.get('result','')}")
print(f"project={data.get('project_key','')} profile={data.get('profile','')} dry_run={str(data.get('dry_run', False)).lower()}")
print(f"elapsed_seconds={data.get('elapsed_seconds')} {resources}")
message = (data.get('message') or '').strip()
if message:
    print(f"message={message}")
qg = (data.get('quality_gate') or '').strip()
if qg:
    print(f"quality_gate={qg}")
analysis_id = (data.get('analysis_id') or '').strip()
if analysis_id:
    print(f"analysis_id={analysis_id}")

print("tools:")
for tool, state in sorted((data.get('tools') or {}).items()):
    print(f"  - {tool}: {state}")

artifacts = data.get("artifacts") or {}
sarif = artifacts.get("sarif_reports") or []
spotbugs = artifacts.get("spotbugs_reports") or []
print(f"artifacts: sarif={len(sarif)} spotbugs={len(spotbugs)}")
if sarif:
    print(f"sarif_paths={','.join(sarif)}")
if spotbugs:
    print(f"spotbugs_paths={','.join(spotbugs)}")
PY
}

while true; do
  print_snapshot
  state="$(python3 - "$status_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get("state", ""))
PY
)"

  if [[ "$once" == "true" || "$state" == "completed" || "$state" == "failed" ]]; then
    break
  fi

  sleep "$interval"
  print -- ""
done
