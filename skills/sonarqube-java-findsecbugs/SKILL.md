# SonarQube Java FindSecBugs Skill

Use this skill for Maven-based Java repositories.

## Trigger

- `strictness != off`
- `pom.xml` exists
- `mvn` exists

## Purpose

Generate SpotBugs XML (with FindSecBugs plugin enabled in build/plugin config when applicable) and pass it to Sonar.

## Command

```sh
mvn -B com.github.spotbugs:spotbugs-maven-plugin:spotbugs
```

Expected report:

- `target/spotbugsXml.xml`

## Import Property

- `sonar.java.spotbugs.reportPaths=target/spotbugsXml.xml`

Pass this via report-import skill or `--extra-property`.

## Failure Policy

- `required`: fail if report cannot be generated.
- `auto`: warn and continue.

## Return

- Report path or skip reason.
