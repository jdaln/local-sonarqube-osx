# SonarQube SAST Pattern Skill

Use this skill to generate SARIF from OpenGrep or Semgrep.

## Trigger

Run when `strictness != off` and repository has source files.

## Tool Selection

1. Prefer `opengrep` if installed.
2. Otherwise use `semgrep`.
3. If neither exists:
   - `required`: fail.
   - `auto`: warn and continue.

## Output Path

- `.sonar-local/security/semgrep.sarif` (or equivalent pattern-scan SARIF file)

## Commands

OpenGrep:

```sh
opengrep scan --config auto --sarif --output .sonar-local/security/semgrep.sarif .
```

Semgrep:

```sh
semgrep scan --config auto --sarif --output .sonar-local/security/semgrep.sarif .
```

## Return

- Tool used (`opengrep` or `semgrep`)
- Output file path
- Finding count (if available)
