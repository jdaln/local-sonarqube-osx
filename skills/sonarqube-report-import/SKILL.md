# SonarQube Report Import Skill

Use this skill to translate generated tool reports into scan arguments.

## Inputs

- `repo`
- Report files that exist under `.sonar-local/security/` or build output paths.

## Supported Mappings

- SARIF files (`*.sarif`) -> repeated `--sarif <path>`
- SpotBugs XML (`target/spotbugsXml.xml`) -> `--extra-property sonar.java.spotbugs.reportPaths=target/spotbugsXml.xml`
- Checkov SARIF default path: `.sonar-local/security/checkov-output/results_sarif.sarif`
- Trivy SARIF default path: `.sonar-local/security/trivy.sarif`
- OSV-Scanner SARIF default path: `.sonar-local/security/osv-scanner.sarif`

## Output

Return a single `extra_args` string suitable for scan-core, for example:

```sh
--security-tools off \
--sarif .sonar-local/security/semgrep.sarif \
--sarif .sonar-local/security/gitleaks.sarif \
--sarif .sonar-local/security/checkov-output/results_sarif.sarif \
--sarif .sonar-local/security/trivy.sarif \
--sarif .sonar-local/security/osv-scanner.sarif \
--sarif .sonar-local/security/codeql/javascript.sarif \
--sarif .sonar-local/security/gosec.sarif \
--sarif .sonar-local/security/cppcheck.sarif \
--sarif .sonar-local/security/infer.sarif \
--sarif .sonar-local/security/rats.sarif \
--sarif .sonar-local/security/valgrind.sarif \
--extra-property sonar.java.spotbugs.reportPaths=target/spotbugsXml.xml
```

## Rules

- Include only files that actually exist.
- Normalize paths relative to repo root when possible.
- Keep argument order stable for reproducibility.
