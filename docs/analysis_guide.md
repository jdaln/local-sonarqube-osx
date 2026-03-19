# Project Analysis Guide

`scan_project_with_sonarqube.sh` is the entrypoint for local analysis, external security tools, and SonarQube integration.

## Basic Usage

```sh
./scripts/scan_project_with_sonarqube.sh \
  --repo /absolute/path/to/repo \
  --project-key my-project
```

Fast path: omit `--prepare` to skip repo-specific prep like dependency installation, frontend test coverage, or build/test phases.

`--prepare` is optional and intended for cases where you want the wrapper to run those extra prep steps before scanning.

For Java Maven/Gradle repos, `--prepare` tries the build-integrated scanner path first. If the build fails, the wrapper retries with a generic scanner using any discovered class directories so SonarQube analysis and SARIF import can still complete on partially broken projects.

Selective skips are available when you want to keep the scan but drop specific tool families.

- `--skip-dependency-scans` skips both `trivy` and `osv-scanner`.
- `--skip-tool osv-scanner` keeps `trivy` enabled while skipping only OSV dependency checks.
- `--skip-tool gitleaks` skips secret scanning if you want to rely on the other analyzers only.

**Order of execution:**
1. Resolve SonarQube URL (defaults to local stack).
2. Validate server availability and project existence.
3. Generate temporary token (auto-auth via local admin creds).
4. Run integrated security tools.
5. Import reports (SARIF/SpotBugs) to SonarQube.
6. Run language-appropriate Sonar scanner.
7. Wait for background task and print Quality Gate status.
8. Perform API verification for SARIF engine findings.

## Security Tool Integration

The wrapper auto-runs tools based on repository contents.

- **SAST**: `opengrep` (preferred) or `semgrep` (`sonar.sarifReportPaths`)
- **Secrets**: `gitleaks` (`sonar.sarifReportPaths`)
- **IaC**: `checkov` (preferred) or `tfsec` (`sonar.sarifReportPaths`)
- **SCA (Library)**: `trivy fs` (`sonar.sarifReportPaths`)
- **SCA (Dependency)**: `osv-scanner` (`sonar.sarifReportPaths`)
- **Full Engine**: `codeql` (`sonar.sarifReportPaths`)
- **Go**: `gosec` (`sonar.sarifReportPaths`)
- **Python**: `bandit` (`sonar.sarifReportPaths`)
- **Docker**: `hadolint` (`sonar.sarifReportPaths`)
- **Java (Maven)**: FindSecBugs (`sonar.java.spotbugs.reportPaths`)

Reports are stored in `.sonar-local/security/`.

## Modes and Settings

### Security Mode (`--security-tools`)
- `auto` (default): Run available tools; continue on failure.
- `off`: Skip integrated security tools.
- `required`: Fail on missing tools or report failures. Enforces API verification.

## Local Stack Integration

Default local install:
```sh
./scripts/scan_project_with_sonarqube.sh --repo /path --project-key key
```

Custom root:
```sh
--app-root "$HOME/Library/Application Support/LocalServices/sonarqube-serv"
```

Remote SonarQube:
```sh
--host-url https://sonarqube.example.com --token YOUR_TOKEN
```

## Observability and Monitoring

Each scan generates a unique **Run ID** and stores artifacts under:
- `.sonar-local/runs/<run-id>/`

**Key Artifacts:**
- `manifest.json`: Immutable scan configuration and repo state.
- `status.json`: Live-updated run state, phase, and tool status.
- `events.jsonl`: Sequential event log.
- `scanner-command.txt`: The exact raw command sent to the Sonar scanner.

### Monitor a Scan
Use the monitoring script to watch progress in real-time. It tracks CPU/Memory usage of the scanner process and provides a summary of tool execution.

```sh
./scripts/monitor_scan_run.sh --repo /path/to/repo
```

### Run Identifiers
- `--run-id ID`: Specify a custom identifier.
- `--resume-run ID`: Resume an existing run. Manifest settings are checked for immutability to prevent incompatible scan mix-ins.

## Manual Scanning Commands

If you prefer not to use the wrapper script, use these standard commands.

### JavaScript / TypeScript
```sh
sonar-scanner \
  -Dsonar.projectKey=my-project \
  -Dsonar.sources=. \
  -Dsonar.host.url=http://127.0.0.1:9000 \
  -Dsonar.token=YOUR_TOKEN
```

### Java (Maven)
```sh
mvn clean verify sonar:sonar \
  -Dsonar.projectKey=my-project \
  -Dsonar.host.url=http://127.0.0.1:9000 \
  -Dsonar.token=YOUR_TOKEN
```

### Java (Gradle)
```sh
./gradlew build sonar \
  -Dsonar.projectKey=my-project \
  -Dsonar.host.url=http://127.0.0.1:9000 \
  -Dsonar.token=YOUR_TOKEN
```

### .NET
```sh
dotnet sonarscanner begin /k:"my-project" /d:sonar.host.url="http://127.0.0.1:9000" /d:sonar.token="YOUR_TOKEN"
dotnet build
dotnet sonarscanner end /d:sonar.token="YOUR_TOKEN"
```

### Python
```sh
sonar-scanner \
  -Dsonar.projectKey=my-project \
  -Dsonar.sources=. \
  -Dsonar.python.version=3 \
  -Dsonar.host.url=http://127.0.0.1:9000 \
  -Dsonar.token=YOUR_TOKEN
```

### Go
```sh
# Generate reports first (optional)
gosec -fmt=sonarqube -out=gosec-report.json ./...

# Scan
sonar-scanner \
  -Dsonar.projectKey=my-project \
  -Dsonar.sources=. \
  -Dsonar.externalIssuesReportPaths=gosec-report.json \
  -Dsonar.host.url=http://127.0.0.1:9000 \
  -Dsonar.token=YOUR_TOKEN
```

## Profiles

Launcher auto-detection (checks root and one level deep for monorepos):
- `java-maven`: `pom.xml` (auto-runs `clean compile`)
- `java-gradle`: `build.gradle` (auto-runs `clean compileJava`)
- `dotnet`: `*.sln` or `*.csproj`
- `js-ts`: `package.json`
- `go`: `go.mod` (auto-excludes `/vendor/`)
- `python`: `requirements.txt` (auto-excludes `venv` and `__pycache__`)
- `c-cpp`: `Makefile` or `CMakeLists.txt`
- `generic`: Fallback. `sonar-scanner` -> `npx @sonar/scan` -> Docker CLI.

Override with `--profile <name>`.

## Notes
- `dry-run`: Use `--dry-run` to print resolved commands.
- Java FindSecBugs targets Maven.
- Use repeated `--sarif PATH` or `--extra-property K=V` for custom additions.
