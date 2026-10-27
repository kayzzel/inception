# Inception — Developer Documentation

This document is for a **developer working on the stack**: environment
setup from scratch, how each piece works, and the day-to-day container
and volume operations. End-user usage is covered in `USER_DOC.md`.

## Environment setup from scratch

1. **VM**: any Debian- or Ubuntu-based guest with Docker installed from
   the [official Docker repository](https://docs.docker.com/engine/install/)
   (not the distro package), plus the compose v2 plugin.
2. **User group**: `sudo usermod -aG docker $USER`, then log out and back
   in — docker-group membership is read at login.
3. **Name resolution**: add to `/etc/hosts`:
   ```
   127.0.0.1   gabach.42.fr
   ```
   (Correct because you browse from inside the VM; from an external
   browser, use the VM's LAN IP instead.)
4. **Secrets and env** (gitignored — recreated on every machine):
   ```bash
   mkdir -p secrets
   printf '%s' "$(openssl rand -base64 24)"  > secrets/db_root_password.txt
   printf '%s' "$(openssl rand -base64 24)"  > secrets/db_password.txt
   printf '%s' 'gabach:<strong-password>'    > secrets/credentials.txt
   ```
   and `srcs/.env` with `DOMAIN_NAME`, `MYSQL_DATABASE`, `MYSQL_USER`,
   `MYSQL_HOST` (values are non-confidential: names, no passwords).
5. `make` — the Makefile creates the data directories, builds the three
   images and starts the stack.

## Repository layout

```
Makefile                     entry point; drives docker compose
srcs/docker-compose.yml      services, network, volumes, secrets
srcs/.env                    non-confidential env vars (interpolated by compose)
secrets/                     credentials (gitignored; mounted as Docker secrets)
srcs/requirements/nginx/     Dockerfile, conf/inception.conf, tools/init_nginx.sh
srcs/requirements/wordpress/ Dockerfile, conf/www.conf, tools/init_wordpress.sh
srcs/requirements/mariadb/   Dockerfile, conf/inception.cnf, tools/init_mariadb.sh
```

Each service follows the same pattern:

- a **Dockerfile** starting from pinned `debian:bookworm`, installing
  packages in a single `RUN` (with list cleanup in the same layer),
  copying `conf/` and `tools/`, and ending with an exec-form `ENTRYPOINT`;
- an **entrypoint script** that reads secrets (`$(cat /run/secrets/...)`
  — command substitution strips trailing newlines), performs *idempotent*
  first-boot initialization, then `exec`s the daemon so it becomes
  **PID 1**;
- a **config file** that adapts the service to the container world
  (listen on all interfaces / TCP ports, reachable across the Docker
  network).

## How first-boot initialization works (per service)

All three services write their durable state **into volumes**, so every
init script is guarded and re-runnable:

- **mariadb**: if `/var/lib/mysql/mysql` exists → skip init. Otherwise:
  `mariadb-install-db` into the volume, start a temporary daemon on the
  unix socket only, wait for it, apply the SQL (root password, database,
  `gabach@'%'` user with grants), stop it cleanly, then `exec mariadbd
  --user=mysql`. Two Dockerfile details make this correct: `/run/mysqld`
  is created in the image (needed on *every* boot), and `/var/lib/mysql`
  is *removed* from the image (the package pre-initializes it, and named
  volumes copy image content on first mount — which would fool the
  guard).
- **wordpress**: if `/var/www/html/index.php` is missing, copy the
  pristine WordPress copy from the image (`/var/www/wordpress`) into the
  volume; if `wp-config.php` is missing, `wp config create`; if not
  installed, wait for the DB (`wp db check` requires the `mysqlcheck`
  binary → `mariadb-client` is installed) then `wp core install` with the
  admin from `secrets/credentials.txt`; the second user is created behind
  its own `wp user get` guard (per-resource idempotency). Finally
  `exec php-fpm8.2 -F`.
- **nginx**: no state; `nginx -t` validates the config, then
  `exec nginx -g "daemon off;"`. The TLS certificate (key and cert) is
  generated at **build time** inside the image, so no key is ever
  committed.

## Makefile / compose usage

- `COMPOSE = docker compose -f srcs/docker-compose.yml` — everything goes
  through it.
- `make all` = `up -d --build` (rebuild images from the Dockerfiles).
- Destruction ladder: `down` (containers/network) → `clean` (+images) →
  `fclean` (+volumes and data dirs; uses `sudo` because the volume files
  are owned by the container's `www-data` UID) → `re` (fclean + all).
- `docker compose -f srcs/docker-compose.yml config` validates the file
  and prints the fully `.env`-resolved configuration — the first
  debugging step for any compose question.

## Container & volume management (day-to-day commands)

```bash
docker compose -f srcs/docker-compose.yml ps        # status
docker logs -f <container>                         # entrypoint/daemon logs
docker exec -it mariadb mariadb -u root -p         # SQL session
docker exec -it wordpress wp <command> --allow-root --path=/var/www/html
docker exec <c> cat /proc/1/cmdline                 # PID 1 check (should be the daemon)
docker network inspect inception-net                # who is on the network
docker volume ls && docker volume inspect srcs_wordpress
```

Signal sanity check: `time docker stop nginx` — about one second means
PID 1 receives SIGTERM and shuts down cleanly; a 10-second stop means a
signal-handling bug.

## Where data lives and how it persists

| Volume | Container path | Physical location (host) |
|--------|----------------|---------------------------|
| `wordpress` | `/var/www/html` (nginx **and** wordpress — same path on purpose: `SCRIPT_FILENAME` must resolve inside both) | `/home/gabach/data/wordpress` |
| `mariadb` | `/var/lib/mysql` (mariadb only) | `/home/gabach/data/mariadb` |

Both are **named volumes** whose `local` driver options point the backing
directory at the required host location (`type: none, o: bind, device:
...`). This stays a named volume (services reference it by name, Docker
registers and manages it) while making the data visible under
`/home/gabach/data` — the subject requires both properties.

Persistence rules of thumb:

- `docker stop` / `make down` / `make clean`: data untouched.
- `make fclean` / `make re`: data destroyed (volumes removed, data dirs
  erased) — the next `make` re-initializes everything.
- Containers are disposable; never store state outside the two volumes.

## Modifying the project

- **Config or entrypoint change**: edit, then `make all` — only the
  affected image rebuilds (layers after the change invalidate; earlier
  layers reuse the build cache).
- **Password change**: edit the relevant `secrets/` file, then
  `make re` (the database is initialized with those values; a mere
  restart would keep the old users).
- **Adding a service**: new directory under `srcs/requirements/`,
  one Dockerfile + conf + tools, one service block in compose (image name
  = service name, attach to `inception-net`, restart policy, PID-1
  entrypoint). Bonus services follow the same pattern.
- After any change, `make re` from a clean state is the reference test —
  it exercises exactly what an evaluator does.
