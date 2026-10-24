# Inception — Complete Build Guide

> A step-by-step guide for completing the 42 **Inception** project (Docker, docker compose, NGINX + WordPress + MariaDB).
> This is a *guide*: it explains what to do, why, and how to verify it — it does not hand you the final files.

---

## 1. What you are building

A small infrastructure, entirely inside a Virtual Machine, of three containers built **by you** (no ready-made images except the Alpine/Debian base):

```
                ┌─────────────┐
   :443 TLS ───▶│    nginx     │───▶ static/php files served via wordpress container
                └──────┬──────┘
                       │ docker network
                ┌──────┴──────┐
                │ wordpress    │  (WordPress + php-fpm, NO nginx)
                │ + php-fpm    │
                └──────┬──────┘
                       │
                ┌──────┴──────┐
                │ mariadb      │  (MariaDB only, NO nginx)
                └─────────────┘

   named volumes → /home/<login>/data  (WP website files + WP database)
```

Key constraints from the subject (all are graded):

- Each image name = its service name; each service in a dedicated container.
- Base images: **penultimate stable version of Alpine or Debian** (your choice). `latest` is forbidden.
- One **Dockerfile per service**, written by you, called from `docker-compose.yml`, which is called from the **Makefile**.
- Two **named volumes** (no bind mounts) whose data ends up in `/home/<login>/data` on the host — still named volumes, not bind mounts.
- A **docker network** connects the containers. `network: host`, `--link`, `links:` are forbidden.
- Containers must **restart on crash** and must run a real daemon as **PID 1** — no `tail -f`, `sleep infinity`, `while true`, `bash` hacks.
- NGINX is the **only entrypoint**, port **443 only**, **TLSv1.2 or TLSv1.3 only**.
- **No passwords in Dockerfiles.** Use a `.env` file; Docker **secrets** strongly recommended for confidential data. No credentials in the git repo.
- WordPress must have **two users**, one being the administrator; the admin username must not contain `admin`/`administrator` in any form.
- Domain `login.42.fr` must point to your local IP.

---

## 2. Phase 0 — Prepare the Virtual Machine

1. **Install a VM** (VirtualBox, VMware, or your 42 cluster VM) with a Debian/Ubuntu-based guest.
2. **Install Docker** inside the VM (official Docker Engine repo — not the distro's outdated package). Add your user to the `docker` group so you don't need `sudo` for every call.
3. **Install docker compose** (v2 plugin: `docker compose` with a space is fine and recommended).
4. **Point the domain to localhost**: in the VM, edit `/etc/hosts` and add a line mapping your login's domain to `127.0.0.1` (or the VM's IP — understand which one the browser will actually resolve and why):
   ```
   127.0.0.1   yourlogin.42.fr
   ```
5. Create the host data folder: `mkdir -p /home/<login>/data`.

> **Defense tip:** you will be asked why the domain resolves locally and how DNS/`/etc/hosts` work. Read about it before the eval.

---

## 3. Phase 1 — Project skeleton

Reproduce this layout at the root of your git repo (names matter, evaluators check them):

```
.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── secrets/                     # gitignored!
│   ├── credentials.txt
│   ├── db_password.txt
│   └── db_root_password.txt
└── srcs/
    ├── docker-compose.yml
    ├── .env                     # gitignored!
    └── requirements/
        ├── nginx/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   └── tools/
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   └── tools/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   └── tools/
        └── bonus/               # only if doing bonus
```

Steps:

1. Create the tree with `mkdir -p`.
2. Write a `.gitignore` **before** creating any secret file:
   ```
   srcs/.env
   secrets/
   ```
   Any password committed to git = **project failure**. Verify with `git status` that no secret ever shows up.
3. Create the three secret files with strong passwords (no trailing spaces/newline issues — know how `docker secret` reads files: it reads the *whole file*, newline included).

---

## 4. Phase 2 — Environment variables and secrets

- `srcs/.env` holds non-confidential config (and references for compose), e.g. `DOMAIN_NAME=<login>.42.fr`, `MYSQL_USER`, database and container names, `WP_*` variables, `MYSQL_HOST`, paths of secret files.
- In `docker-compose.yml`, **mount the secret files as Docker secrets** (`secrets:` top-level + per-service `secrets:` entry) and read them inside the container (e.g. a small script that `cat`s `/run/secrets/<name>`), or pass env values built from secrets. The subject says `.env` is mandatory **and** secrets are strongly recommended for confidential data — understand the difference (see README section below).

**Verification:** `docker compose config` shows the resolved values; `grep -r password srcs/` and `git log -p` should never expose a real secret.

---

## 5. Phase 3 — The docker network and volumes

In `docker-compose.yml`:

1. **Network**: declare a dedicated network (`driver: bridge`) and attach all three services to it. Give each container a fixed hostname (e.g. `container_name` + `hostname`), because WordPress and NGINX will reach MariaDB/php-fpm **by service name via Docker's internal DNS** — that's the whole point of the network.
2. **Volumes**: declare two named volumes. To make their data land in `/home/<login>/data` *while staying named volumes*, configure Docker's named-volume storage to point at that directory (read about `docker volume` driver `local` with options, or moving/changing dockerd's `data-root`/volume path) — bind mounts are explicitly forbidden. Research:
   - `docker volume create` with the `local` driver and `o=bind`-style device options (this is still a *named volume*, unlike a compose `bind` mount — know the difference and be able to justify it), **or**
   - a dedicated `volumes:` driver-options block in compose.
3. Attach: WordPress website files volume → the WP container (and the FTP container, in bonus); database volume → MariaDB's data dir (know where MariaDB stores data, e.g. `/var/lib/mysql`).
4. Add `restart: unless-stopped` (or `always`) to every service so containers restart on crash.

**Verification:** `docker volume inspect`, `docker network inspect`, `ls /home/<login>/data` after first run.

---

## 6. Phase 4 — MariaDB container

Goal: a container with **only** MariaDB, initialized with your database and users.

What your Dockerfile must do:

1. Start from the penultimate stable Debian or Alpine base image (pin an exact version tag).
2. Install MariaDB server (via `apt-get`/`apk` — mind `apt` cache cleanup in the same layer; use non-interactive install flags).
3. Copy your config (e.g. bind address `0.0.0.0` or the docker network address, port 3306, data dir) and your **init/entrypoint script** into the image.
4. The entrypoint script should: safely create the database, create the admin user + the WordPress user (from secrets/env), apply permissions, then **exec the MariaDB daemon as PID 1** (e.g. `exec mariadbd --user=mysql ...` or the proper daemon command for your version) — never a background-daemon-then-sleep hack. Handle re-initialization: if the data dir is already populated, skip user creation.

> **Key concept — PID 1:** a container runs while its PID 1 runs. The "correct" pattern is: init script does its setup, then `exec`s the daemon so the daemon *becomes* PID 1 and receives signals (clean shutdown, correct exit status). Be ready to explain why `service mysql start && tail -f /dev/null` is wrong.

**Verification:** `docker exec -it mariadb mariadb -u root -p` → `SHOW DATABASES; SELECT user, host FROM mysql.user;`.

---

## 7. Phase 5 — WordPress + php-fpm container

Goal: WordPress with php-fpm, **without** any web server.

What your Dockerfile must do:

1. Same base-image rules; install `php-fpm`, required PHP extensions (at minimum: `mysqli`/`mysqlnd`, `curl`, `gd`, `xml`, `mbstring`, `zip`, `imagick` if you want themes/plugins to work), `wget`/`curl` to fetch WordPress CLI and core.
2. Download WordPress core (and optionally `wp-cli`) at build time — no ready-made WP image allowed.
3. Configure `www.conf` (php-fpm pool): **listen on a TCP socket** (e.g. `9000`) or a socket reachable by NGINX across the network, with correct user/permissions, `listen.allowed_clients` if needed.
4. Entry script: read credentials from secrets/env, create `wp-config.php` (via wp-cli `core config` or a template), then if WP isn't installed yet, run the WP install with **two users**:
   - the **administrator** (username must NOT contain "admin"/"administrator" — e.g. your login),
   - a second regular user.
   Then `exec` php-fpm in the foreground (`php-fpm8 -F` or equivalent) so it runs as PID 1.

**Verification:** `docker exec` into it, check `php-fpm` is PID 1 (`ps -o pid,cmd -1` or `cat /proc/1/cmdline`), site DB tables exist in MariaDB, and the two WP users appear.

---

## 8. Phase 6 — NGINX container (the only entrypoint)

What your Dockerfile must do:

1. Penultimate stable Alpine or Debian base; install NGINX (+ openssl for cert generation, or generate the cert outside and copy it in — either is fine, but never commit the key).
2. Generate a **self-signed TLS certificate** for `<login>.42.fr` (know the `openssl req -x509 -nodes -days ... -newkey rsa:...` flags you use).
3. Server config must:
   - `listen 443 ssl` — **and only 443**;
   - `ssl_protocols TLSv1.2 TLSv1.3;` (nothing older);
   - `server_name <login>.42.fr;`
   - `root` pointing at the WordPress files (shared via the website volume, or forwarded to php-fpm);
   - a `location ~ \.php$` block that uses `fastcgi_pass` to the **wordpress service hostname:9000** (Docker DNS) with proper `fastcgi_param`s (`SCRIPT_FILENAME`, etc.).
4. Entry script: replace env vars in the config template if needed, then `exec nginx -g "daemon off;"` — the canonical way to run nginx as PID 1.

**Verification:** `curl -k https://<login>.42.fr` works inside the VM; `curl -kv https://<login>.42.fr` shows TLSv1.2 or 1.3; `docker port` shows only 443 published; `nmap`/`ss` shows no other exposed ports on the host.

---

## 9. Phase 7 — The Makefile

The Makefile must set up the entire application. Typical targets (design your own, but keep them meaningful and documented):

- `all` — builds the images and starts the stack (`docker compose -f srcs/docker-compose.yml up -d --build`).
- `$(NAME)`, `up`, `down`, `clean`/`fclean`, `re` — the classic 42 pattern. `clean`/`fclean` should stop and optionally remove volumes/images/network.
- Bonus: separate targets or a `bonus` target that starts the additional services.

Rules of thumb:

- Use `--build` so evaluators can see images are built from your Dockerfiles.
- Add `.PHONY` for all targets.
- Exit codes must be sane; `make` alone should do the full setup.

**Verification:** from a clean clone (`git clone` into a fresh dir in the VM): `make` → site reachable; `make down` → everything stops; `make clean && make` → works again.

---

## 10. Phase 8 — Documentation (graded files!)

Four documents at the root of the repo, in English:

1. **README.md** — first line must be *italicized*: `*This project has been created as part of the 42 curriculum by <login>.*` (exact wording). Sections required:
   - **Description** (goal + overview),
   - **Instructions** (build/install/run),
   - **Resources** (references **and** a description of how AI was used, for which tasks),
   - Plus the required comparisons:
     - Virtual Machines vs Docker
     - Secrets vs Environment Variables
     - Docker Network vs Host Network
     - Docker Volumes vs Bind Mounts
2. **USER_DOC.md** — for an end user/admin: what services the stack provides, how to start/stop, how to access the site and the WP admin panel, where credentials live, how to check services are healthy.
3. **DEV_DOC.md** — for a developer: environment setup from scratch, Makefile/compose usage, container & volume management commands, where data lives and how it persists.

---

## 11. Bonus (only if mandatory part is *perfect*)

One Dockerfile per additional service, each in its own container (and dedicated volume if useful). The list:

- **redis** cache for WordPress (a WP plugin/object-cache drop-in talks to the redis service).
- **ftp server** container pointing at the WordPress website volume (e.g. vsftpd, passive ports configured).
- **static site** in a language other than PHP (your own small showcase/resume site), served by NGINX.
- **Adminer** (web DB management) — served through NGINX too.
- **A service of your choice**, justified during the defense.

Extra ports may be opened only for bonus needs. Remember: bonus is evaluated **only** if the mandatory part is flawless.

---

## 12. Final checklist (run this before asking for an evaluation)

- [ ] Everything runs **inside a VM**.
- [ ] All config files are in `srcs/`, Makefile at the root, `make` does the full setup.
- [ ] Images built from your own Dockerfiles (penultimate stable Alpine/Debian pinned — no `latest`).
- [ ] Image names = service names; one service = one container.
- [ ] `docker compose ps` → nginx, wordpress, mariadb running; `docker inspect` → `restart: always/unless-stopped`.
- [ ] PID 1 is the daemon in every container (no `tail -f`/`sleep`/`while true`/`bash` loops — not even in entrypoints).
- [ ] Only port **443** exposed; TLS 1.2/1.3 only; `curl -kI https://<login>.42.fr` returns 200/30x.
- [ ] Two named volumes; data visible under `/home/<login>/data`; no bind mounts in compose.
- [ ] Dedicated docker network; no `host`, no `links`.
- [ ] WP has two users; admin name contains no "admin" substring.
- [ ] `.env` used; secrets used for passwords; **nothing confidential in git** (`git log -p` clean).
- [ ] README.md (exact italic first line + all sections/comparisons), USER_DOC.md, DEV_DOC.md present.
- [ ] `make clean && make` from a fresh clone works end-to-end.

---

## 13. Concepts you must be able to explain at the defense

- Docker images vs containers; layers; build cache.
- PID 1, signal handling, why daemons must run in the foreground.
- Docker networks and the embedded DNS server; why `host` networking and `links` are bad here.
- Named volumes vs bind mounts; where volume data physically lives; how you redirected it to `/home/<login>/data`.
- TLS: certificates, self-signed CAs, `curl -k`, protocol versions.
- php-fpm and FastCGI: how NGINX proxies `.php` requests to the wordpress container.
- Docker secrets vs env vars; how secrets reach the container (`/run/secrets/...`).
- Docker compose: `build` vs `image`, `depends_on` (and why it doesn't wait for readiness), env interpolation from `.env`.
- A container is **not** a VM (namespaces/cgroups vs hypervisor) — this comparison is explicitly required in the README.

Good luck — and read the official docs as you go; the defense checks understanding, not just a working stack.
