# SonarQube Scan Core Skill

Use this skill for Sonar preflight, final scan execution, and quality gate retrieval.

## Inputs

- `repo`
- `project_key`
- `project_name` (optional)
- `prepare`: `true` | `false`
- `host_url` and `token` (optional)
- `strictness`: `auto` | `required` | `off`
- `sca_severity_gate`: `off` | `low` | `medium` | `high` | `critical` (optional, default `high`)
- `run_id` / `resume_run` (optional): persisted run tracking under `.sonar-local/runs`
- `extra_args` (optional): prebuilt report import args from report-import skill

## Preflight

1. Check server status:
   - `curl -sS -u admin:<pwd> <host_url>/api/system/status`
2. Validate scan wrapper presence:
   - `scripts/scan_project_with_sonarqube.sh`

## Recommended Final Command

```sh
./scripts/scan_project_with_sonarqube.sh \
  --repo "$repo" \
  --project-key "$project_key" \
  --project-name "$project_name" \
  --security-tools "$strictness" \
  ${run_id:+--run-id "$run_id"} \
  ${resume_run:+--resume-run "$resume_run"} \
  ${sca_severity_gate:+--sca-severity-gate "$sca_severity_gate"} \
  ${prepare:+--prepare} \
  ${extra_args}
```

For local installs, include:

```sh
--app-root "$HOME/Library/Application Support/LocalServices/sonarqube-serv"
```

By default (`--security-tools auto|required`), the wrapper runs integrated local tools
when relevant: Semgrep/OpenGrep, gitleaks, checkov/tfsec, Trivy SCA, OSV-Scanner SCA,
CodeQL, gosec, Bandit, Hadolint, and FindSecBugs (Maven).

## Import-Only Mode

When other skills generated reports explicitly, set `--security-tools off` and pass imports via `extra_args`.

## Output

- Scan command used.
- Run artifact path (`.sonar-local/runs/<run-id>/`).
- Analysis success/failure.
- Project dashboard URL.
- Quality gate status via:
  - `GET /api/qualitygates/project_status?projectKey=<key>`
- Optional live monitor:
  - `scripts/monitor_scan_run.sh --repo <repo> [--run-id <id>]`
