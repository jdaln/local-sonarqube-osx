# Operator Notes

## Runtime Model

Per-user `LaunchAgent` manages Docker containers. This supports systems where the Docker runtime is user-owned.

- **Bootstrap**: Launch agent starts containers (and Colima if necessary) then exits.
- **Persistence**: PostgreSQL and SonarQube data are bind-mounted under `~/Library/Application Support/LocalServices/sonarqube-serv`.
- **Lifecycle**: Containers use `restart: unless-stopped` and start automatically on user login.

## Image Management

- **Sources**: Official `sonarqube` and `postgres` images.
- **Resolution**: Install/update scripts resolve `linux/arm64` digests to `config/resolved-images.env`.
- **Integrity**: Unmodified official images only.

## Security Posture

- **Networking**: SonarQube binds to `127.0.0.1`. PostgreSQL is private to the internal Docker network.
- **Secrets**: Passwords generated at install; stored in `config/sonarqube-serv.env` (permissions: `600`).
- **Execution**: Containers run with `no-new-privileges`.

## Service Validation

`validate_service.sh` checks:
1. Docker runtime status.
2. Web UI reachability (`UP`).
3. Admin authentication with generated credentials.

## Maintenance

Update monthly to track LTS community releases:
```sh
./scripts/update_sonarqube_serv_osx.sh
```
