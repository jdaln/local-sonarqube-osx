# SonarQube CE Security Router Skill

Use this as the entrypoint skill. It decides which scan subskills to run and in what order.

## Purpose

Run only the tools that match the repository and Sonar edition constraints, then complete one final Sonar analysis with clear output.

## Inputs

- `repo` (absolute path)
- `project_key`
- `project_name` (optional)
- `strictness`: `auto` | `required` | `off`
- `sca_severity_gate`: `off` | `low` | `medium` | `high` | `critical` (optional, default `high`)
- `prepare`: `true` | `false`
- `host_url` and `token` (optional for local stack)

## Mandatory Preflight

1. Read Sonar runtime metadata:
   - `curl -sS -u admin:<pwd> <host_url>/api/system/info`
2. Record:
   - `System.Edition`
   - `System.Version`
3. Apply CE guardrails:
   - For CE on 9.9-style server: main branch only.
   - For Community Build behavior: if PR analysis is used, enforce target branch `main`.

## Delegation Plan

1. Always run [$sonarqube-scan-core](/Users/flow/sonarqube-serv/skills/sonarqube-scan-core/SKILL.md) preflight checks.
2. If `strictness != off`, verify local tool prerequisites from [`docs/local_sast_tooling.md`](/Users/flow/sonarqube-serv/docs/local_sast_tooling.md).
3. If `strictness != off`, run relevant report generators:
   - [$sonarqube-sast-pattern](/Users/flow/sonarqube-serv/skills/sonarqube-sast-pattern/SKILL.md)
   - secrets/IaC/SCA in wrapper (`gitleaks`, `checkov`/`tfsec`, `trivy`, `osv-scanner`) based on repo content
   - [$sonarqube-codeql-sarif](/Users/flow/sonarqube-serv/skills/sonarqube-codeql-sarif/SKILL.md) only if `codeql` installed
   - [$sonarqube-java-findsecbugs](/Users/flow/sonarqube-serv/skills/sonarqube-java-findsecbugs/SKILL.md) for Maven Java
   - [$sonarqube-go-python-docker](/Users/flow/sonarqube-serv/skills/sonarqube-go-python-docker/SKILL.md) for Go/Python/Dockerfiles
   - [$sonarqube-c-cpp-hybrid](/Users/flow/sonarqube-serv/skills/sonarqube-c-cpp-hybrid/SKILL.md) for C/C++/Obj-C and Valgrind
4. Run [$sonarqube-report-import](/Users/flow/sonarqube-serv/skills/sonarqube-report-import/SKILL.md) to build report import args.
5. Run final scan with [$sonarqube-scan-core](/Users/flow/sonarqube-serv/skills/sonarqube-scan-core/SKILL.md).

## Decision Rules

- Never run all tools by default.
- Skip irrelevant tools by language detection.
- In `required` mode, missing relevant tools are hard failures.
- In `auto` mode, missing relevant tools are warnings.
- `off` mode skips all external security tools.

## Completion Contract

Return:

- Sonar edition/version used for decisions.
- Which subskills ran and why.
- Which tools were skipped and why.
- Final analysis status + quality gate + imported report summary.
