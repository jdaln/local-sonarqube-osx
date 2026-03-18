# scan_project_with_sonarqube modules

Entrypoint:
- `scripts/scan_project_with_sonarqube.sh`

Implementation modules:
- `core.sh`: logging, run-state manifest/status/events, common helpers.
- `sarif.sh`: SARIF normalization, conversion, external import verification, SCA dedupe/gate helpers.
- `repo_and_server.sh`: repo/language detection, local Sonar auth/project setup, token lifecycle.
- `security_tools.sh`: integrated security tool runners and pipeline orchestration.
- `scanner_helpers.sh`: scanner helper utilities shared by launcher code.
- `scanner_and_wait.sh`: scanner command builders and Sonar background-task/quality-gate wait.
