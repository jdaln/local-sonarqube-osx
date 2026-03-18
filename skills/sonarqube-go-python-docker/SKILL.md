# SonarQube Go/Python/Docker Security Skill

Use this skill for language/container-specific tools: gosec, Bandit, and Hadolint.

## Trigger

- `strictness != off`
- Any of:
  - Go files or `go.mod`
  - Python files
  - Dockerfiles

## Output Directory

- `.sonar-local/security/`

## gosec

Trigger:

- Go detected and `gosec` installed.

Command:

```sh
gosec -no-fail -fmt sarif -out .sonar-local/security/gosec.sarif ./...
```

## Bandit

Trigger:

- Python detected and `bandit` installed.

Preferred command:

```sh
bandit -r . -f sarif -o .sonar-local/security/bandit.sarif --exit-zero
```

Fallback for Bandit builds without SARIF output:

```sh
bandit -r . -f json -o .sonar-local/security/bandit.json --exit-zero
```

If JSON fallback is used, convert JSON to SARIF before import.

## Hadolint

Trigger:

- Dockerfiles detected and `hadolint` installed.

Command:

```sh
hadolint --no-fail -f sarif Dockerfile > .sonar-local/security/hadolint.sarif
```

For multiple Dockerfiles, run once with all file paths.

## Failure Policy

- `required`: fail for missing relevant tools/report failures.
- `auto`: warn and continue.

## Return

- Produced report list and skipped-tool reasons.
