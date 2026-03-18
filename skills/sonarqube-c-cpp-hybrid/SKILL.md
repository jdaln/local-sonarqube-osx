# SonarQube C/C++ Hybrid Security Skill

Use this skill for C, C++, Objective-C, and dynamically analyzed binaries. It orchestrates `cppcheck`, `rats`, `infer`, and `valgrind` into SARIF formats.

## Trigger

- `strictness != off`
- Any of:
  - C/C++ files (`*.c`, `*.cpp`, `*.h`, `*.hpp`)
  - Objective-C files (`*.m`, `*.mm`)
  - Explicit build commands (`--build-command`)
  - Explicit dynamic targets (`--valgrind-target`)

## Output Directory

- `.sonar-local/security/`

## Cppcheck (Docker)

Trigger:
- C/C++ files detected and `cxx-scanner-tools` Docker image available.

Command:
```sh
docker run --rm -v "$PWD:/code:ro" cxx-scanner-tools cppcheck --enable=all --xml --xml-version=2 . > .sonar-local/security/cppcheck.xml
python3 scripts/lib/scan/cppcheck_to_sarif.py .sonar-local/security/cppcheck.xml .sonar-local/security/cppcheck.sarif
```

## FB Infer (Native)

Trigger:
- Java, C/C++, or Objective-C detected.
- `infer` binary available in PATH or `~/.local/bin/infer`.

Command:
```sh
# If build_command is known:
infer run --sarif -- <build_command>
# Fallback:
infer capture --sarif -- gcc -c *.c
```

## RATS (Native)

Trigger:
- C, C++, PHP, Python, Ruby, or Perl files detected.
- `rats` installed locally.

Command:
```sh
rats --xml . > .sonar-local/security/rats.xml
python3 scripts/lib/scan/rats_to_sarif.py .sonar-local/security/rats.xml .sonar-local/security/rats.sarif
```

## Valgrind (Docker DAST)

Trigger:
- `--valgrind-target` is provided by the user.

Command:
```sh
docker run --rm -v "$PWD:/code" cxx-scanner-tools valgrind --xml=yes --xml-file=valgrind.xml <valgrind_target>
python3 scripts/lib/scan/valgrind_to_sarif.py valgrind.xml .sonar-local/security/valgrind.sarif
```

## Return

- Produced SARIF report list and skipped-tool reasons.
