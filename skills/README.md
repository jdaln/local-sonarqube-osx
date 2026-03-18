# SonarQube Skill Pack

This skill pack splits scanning into a router plus focused execution skills.

## Skills

- `sonarqube-ce-security-router`: entrypoint/orchestrator.
- `sonarqube-scan-core`: Sonar preflight + final scan + quality gate checks.
- `sonarqube-sast-pattern`: OpenGrep/Semgrep SARIF generation.
- `sonarqube-codeql-sarif`: CodeQL SARIF generation.
- `sonarqube-c-cpp-hybrid`: Hybrid SARIF generation for C/C++ via cppcheck, rats, infer, and valgrind.
- `sonarqube-java-findsecbugs`: FindSecBugs/SpotBugs report generation.
- `sonarqube-go-python-docker`: gosec/Bandit/Hadolint reports.
- `sonarqube-report-import`: normalize report paths and pass import flags.

## Prerequisites

Tool installation and verification steps are documented in:
- [`docs/local_sast_tooling.md`](/Users/flow/sonarqube-serv/docs/local_sast_tooling.md)

## Recommended Order

1. `sonarqube-ce-security-router` decides plan from repo + environment.
2. Router invokes only relevant execution skills.
3. `sonarqube-report-import` assembles import arguments.
4. `sonarqube-scan-core` runs final scan and returns status + quality gate.
