# SonarQube Service for macOS

Local Docker-based SonarQube service with these defaults:

- Official `sonarqube:lts-community` image
- Official `postgres:17-alpine` database
- Loopback-only web UI (`127.0.0.1:9000`)
- Generated database and admin credentials
- Per-user `LaunchAgent` wrapper
- Automatic Colima bootstrap
- Monthly update workflow

## Prerequisites

- macOS (Apple Silicon recommended)
- Docker Desktop or [Colima](https://github.com/abiosoft/colima)
- `jq`, `rsync`, and `python3`

## Quick Start

### Install
```sh
./scripts/install_sonarqube_serv_osx.sh
```

### Open UI
```sh
open http://127.0.0.1:9000
```

### Verify installation:
```sh
./scripts/doctor.sh
```
This script checks Docker, the SonarQube service, and your local scanning toolset.

## Maintenance

### Update Images
```sh
./scripts/update_sonarqube_serv_osx.sh
```

### Uninstall
```sh
./scripts/uninstall_sonarqube_serv_osx.sh
```
Use `--purge` to also remove all persistent database data and Docker volumes.

### Scan a Project
```sh
./scripts/scan_project_with_sonarqube.sh \
  --repo /absolute/path/to/repo \
  --project-key my-project
```

Use `--prepare` only when you want framework-specific prep such as `npm ci`, Angular/Jest/Karma test coverage, Maven/Gradle test phases, or similar build-time setup before scanning. Omitting `--prepare` skips those test/coverage steps and is the faster default.

For Java projects, `--prepare` still attempts the build-integrated Maven/Gradle scan first. If the project build breaks, the wrapper now falls back to a generic Sonar scan using any discovered compiled classes so you still get a SonarQube project plus imported SARIF findings instead of a hard stop.

Selective skips are also supported. `--skip-dependency-scans` omits both Trivy and OSV-Scanner. If you want to keep Trivy and skip only OSV dependency checks, use `--skip-tool osv-scanner` instead. Example:

```sh
./scripts/scan_project_with_sonarqube.sh \
  --repo /absolute/path/to/repo \
  --project-key my-project-no-gitleaks-no-osv \
  --skip-tool gitleaks \
  --skip-tool osv-scanner
```

### Monitor Scan
```sh
./scripts/monitor_scan_run.sh --repo /absolute/path/to/repo
```

The scan wrapper integrates and imports findings from: Semgrep/OpenGrep, gitleaks, checkov/tfsec, Trivy, OSV-Scanner, CodeQL, gosec, Bandit, Hadolint, and FindSecBugs.

Logic: `sonar-scanner` (if present) -> `npx @sonar/scan` -> Docker scanner CLI.

> **Note on Testing:** This project has been validated against a suite of notoriously vulnerable benchmark repositories to try to attain comprehensive SAST and SCA coverage across all major language ecosystems. Tested targets include:
> - **Java/Spring:** `OWASP/wrongsecrets` (~1,400 findings)
> - **Ruby on Rails:** `OWASP/railsgoat` (~4,000 findings)
> - **Python/Django:** `adeyosemanputra/pygoat` (~390 findings)
> - **C/C++ (Embedded Linux):** `OWASP/IoTGoat` (~50 findings - most likely still weak)
> - **PHP:** `OWASP/OWASPWebGoatPHP` (~290 findings)
> - **Go:** `sonatype-nexus-community/intentionally-vulnerable-golang-project` (~100 findings)
> - and more
> If you can contribue to adding more and test it end-to-end, I very much appreciate contributions.

## Documentation

- [Operator Notes](docs/operator_notes.md) - Persistence, security, and runtime model.
- [Analysis Guide](docs/analysis_guide.md) - Scan pipeline and tool integration.
- [Local SAST Setup](docs/local_sast_tooling.md) - Install external security tools.
- [LLM Skill Index](skills/README.md) - Skills for your agents.
