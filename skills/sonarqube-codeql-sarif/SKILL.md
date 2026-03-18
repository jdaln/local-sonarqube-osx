# SonarQube CodeQL SARIF Skill

Use this skill when `codeql` is installed and repository language is supported.

## Trigger

- `strictness != off`
- `codeql` binary available
- Repo contains at least one supported language.

## Supported Language Signals

- Java: `pom.xml`, `build.gradle*`, or `*.java`
- JavaScript/TypeScript: `*.js`, `*.jsx`, `*.mjs`, `*.cjs`, `*.ts`, `*.tsx`
- Python: `*.py`
- Go: `go.mod` or `*.go`

## Paths

- DB root: `.sonar-local/security/codeql/db-<lang>`
- SARIF output: `.sonar-local/security/codeql/<lang>.sarif`

## Query Packs

- Java: `codeql/java-queries`
- JavaScript/TypeScript: `codeql/javascript-queries`
- Python: `codeql/python-queries`
- Go: `codeql/go-queries`
- C#: `codeql/csharp-queries`

If a pack is missing, download it before analysis:
- `codeql pack download <pack>`

## Command Template

1. Create DB
2. Analyze with pack default suite

Example:

```sh
codeql database create ".sonar-local/security/codeql/db-python" \
  --language python \
  --source-root . \
  --overwrite \
  --threads=0

codeql database analyze ".sonar-local/security/codeql/db-python" \
  codeql/python-queries \
  --format=sarif-latest \
  --output ".sonar-local/security/codeql/python.sarif" \
  --threads=0
```

## Failure Policy

- `required`: fail on setup/analyze failure for relevant language.
- `auto`: warn and continue.

## Return

- Languages scanned
- SARIF files produced
- Any skipped language + reason
