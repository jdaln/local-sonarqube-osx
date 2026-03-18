# Local SAST Tooling Setup

This project supports local-first security scanning through `scripts/scan_project_with_sonarqube.sh`.

## Install (macOS/Homebrew)

```sh
brew install gitleaks semgrep checkov tfsec trivy osv-scanner gosec hadolint codeql bandit
```

Notes:
- `opengrep` is optional. The wrapper prefers it if present, otherwise uses `semgrep`.
- CodeQL query packs are downloaded on first use by the wrapper (`codeql pack download ...`).

## Verify Tools

```sh
for t in gitleaks semgrep checkov tfsec trivy osv-scanner codeql gosec bandit hadolint; do
  command -v "$t" >/dev/null 2>&1 && echo "$t: ok" || echo "$t: missing"
done
```

## Verify Pipeline

Run strict mode to validate tool availability and report generation:

```sh
./scripts/scan_project_with_sonarqube.sh \
  --repo /absolute/path/to/repo \
  --project-key my-project \
  --security-tools required
```

In another terminal, watch progress:

```sh
./scripts/monitor_scan_run.sh --repo /absolute/path/to/repo
```

## Usage Notes

- **SCA Gating**: Enabled via `--sca-severity-gate` (default: `high`).
- **Monitoring**: Run artifacts are written to `.sonar-local/runs/<run-id>/` with manifest, status, and events.
- **Mixed-Language**: Automatically detected; only relevant tools are executed.
- **Deduplication**: Trivy/OSV findings are deduplicated before SonarQube import.

To enforce an SCA threshold gate (for imported Trivy/OSV findings):

```sh
./scripts/scan_project_with_sonarqube.sh \
  --repo /absolute/path/to/repo \
  --project-key my-project \
  --security-tools required \
  --sca-severity-gate high
```

Watch progress:

```sh
./scripts/monitor_scan_run.sh --repo /absolute/path/to/repo
```

## Mixed-Language Repositories

Mixed-language repos are supported. The wrapper:
- Detects relevant tools by repo contents.
- Runs only relevant scanners.
- Imports SARIF/SpotBugs reports into one Sonar analysis.
