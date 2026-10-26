# Inception — Complete Study Notes & Defense Preparation

> Personal study document for the 42 Inception project (Docker / docker compose / NGINX + WordPress + MariaDB).
> Contains: everything built, why each choice was made, key Docker concepts, and a large defense Q&A.
> (Note: this file is personal documentation — it is not one of the graded files and can be removed before final submission.)

---

## 1. What the project is

A small infrastructure inside a VM, made of **three containers built by us** (no ready-made images except the OS base):

```
                ┌─────────────┐
   :443 TLS ───▶│    nginx     │───┐
                └──────┬──────┘   │ shared wordpress volume (/var/www/html)
                       │ docker network (inception-net, bridge)
                ┌──────┴──────┐   │
                │ wordpress    │──┘  (WordPress + php-fpm, NO nginx)
                │ + php-fpm    │
                └──────┬──────┘
                       │
                ┌──────┴──────┐
                │ mariadb      │  (MariaDB only, NO nginx)
                └─────────────┘

   2 named volumes → data physically stored in /home/gabach/data
   (wordpress files + mariadb database)
```

**Hard rules from the subject (all graded):**

- Image name = service name; one service = one container.
- Base image: **penultimate stable Debian or Alpine**, pinned — `latest` forbidden.
- One **Dockerfile per service**, called by `docker-compose.yml`, called by the **Makefile**.
- Two **named volumes** (no bind mounts) with data in `/home/<login>/data`.
- A dedicated **docker network**. `network: host`, `--link`, `links:` forbidden.
- Containers **restart on crash**; a real daemon runs as **PID 1** (no `tail -f`, `sleep infinity`, `while true`, `bash`).
- **NGINX is the only entrypoint**, port **443 only**, **TLSv1.2/1.3 only**.
- **No passwords in Dockerfiles or git**: `.env` for non-confidential config, Docker **secrets** for passwords.
- WordPress has **two users**; the admin username must NOT contain `admin`/`administrator` in any form.
- Domain `<login>.42.fr` resolves to the local machine (via `/etc/hosts`).

---

## 2. Project layout

```
.
├── Makefile
├── README.md            (graded — exact italic first line + sections)
├── USER_DOC.md          (graded)
├── DEV_DOC.md           (graded)
├── .gitignore           → srcs/.env and secrets/
├── secrets/             (gitignored)
│   ├── credentials.txt        → gabach:<wp admin password>   (login:password, one line)
│   ├── db_password.txt        → mariadb wordpress-user password
│   └── db_root_password.txt   → mariadb root password
└── srcs/
    ├── .env             (gitignored — non-confidential config only)
    ├── docker-compose.yml
    └── requirements/
        ├── nginx/     → Dockerfile, .dockerignore, conf/inception.conf, tools/init_nginx.sh
        ├── wordpress/ → Dockerfile, .dockerignore, conf/www.conf, tools/init_wordpress.sh
        └── mariadb/   → Dockerfile, .dockerignore, conf/inception.cnf, tools/init_mariadb.sh
```

**Secrets vs `.env` — the distinction (defense favorite):**

| | `.env` (srcs/.env) | Docker secrets (secrets/) |
|---|---|---|
| Contains | Configuration: domain, DB name, usernames, hostnames | Credentials: passwords |
| Visibility | Interpolated into compose YAML, visible via `docker compose config`, visible in `docker inspect` | Mounted as a file at `/run/secrets/<name>` inside the container only |
| Risk if leaked | Low (no passwords!) | High — that's why they're gitignored |
| Lifecycle | Static config | Read at container start by the entrypoint script |

`DOMAIN_NAME=gabach.42.fr`, `MYSQL_DATABASE=wordpress`, `MYSQL_USER=gabach`, `MYSQL_HOST=mariadb`.

---

## 3. docker-compose.yml — piece by piece

```yaml
services:
  nginx:
    build:
      context: ./requirements/nginx
    image: nginx
    container_name: nginx
    networks:
      - inception-net
    volumes:
      - wordpress:/var/www/html
    restart: always
    depends_on:
      - wordpress
    ports:
      - "443:443"
  wordpress:
    build:
      context: ./requirements/wordpress
    image: wordpress
    container_name: wordpress
    networks:
      - inception-net
    volumes:
      - wordpress:/var/www/html
    restart: always
    depends_on:
      - mariadb
    environment:
      DOMAIN_NAME: ${DOMAIN_NAME}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_HOST: ${MYSQL_HOST}
    secrets:
      - db_password
      - credentials
  mariadb:
    build:
      context: ./requirements/mariadb
    image: mariadb
    container_name: mariadb
    networks:
      - inception-net
    volumes:
      - mariadb:/var/lib/mysql
    restart: always
    environment:
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
    secrets:
      - db_root_password
      - db_password

volumes:
  wordpress:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/gabach/data/wordpress
  mariadb:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/gabach/data/mariadb

networks:
  inception-net:
    name: inception-net
    driver: bridge

secrets:
  db_root_password:
    file: ../secrets/db_root_password.txt
  db_password:
    file: ../secrets/db_password.txt
  credentials:
    file: ../secrets/credentials.txt
```

### Concepts behind each block

- **`build.context`** — the folder containing the Dockerfile; paths in `COPY` are relative to it. `image:` names the built image (= service name, per subject). With both, compose builds instead of pulling.
- **`environment:` + `${VAR}`** — compose auto-loads `srcs/.env` and substitutes variables into the YAML; the result also becomes the container's environment, readable by entrypoint scripts (`${MYSQL_DATABASE}` in bash = same value).
- **`ports: "443:443"`** — the **publish**: HOST:CONTAINER. The only one in the stack. `EXPOSE` (in Dockerfiles) is pure documentation.
- **`depends_on`** — orders *container start*, NOT readiness. Real readiness handled by the `wp db check` retry loop in the wordpress entrypoint.
- **`restart: always`** — restart on crash, and also after daemon restart (even if manually stopped before). `unless-stopped` = restart on crash but stay stopped if you stopped it.
- **`container_name`** — fixed, predictable names for `docker exec`/`docker logs`; Docker DNS resolves *service names* regardless.
- **`networks: driver: bridge`** — user-defined bridge → **embedded DNS server** (127.0.0.11 inside containers) resolves service names (`wordpress`, `mariadb`) to current IPs. The *default* bridge has no DNS — that's why declaring our own network is the mechanism making `fastcgi_pass wordpress:9000` work.
- **Volumes with `driver_opts`** — a **named volume** (Docker-managed, listed by `docker volume ls`) whose `local` driver stores data at a chosen path instead of `/var/lib/docker/volumes/`. Still a named volume — the service references only the name; **not** a bind mount (a bind mount = host path declared *in the service's volumes*, forbidden here).

---

## 4. MariaDB container

**Dockerfile** (`srcs/requirements/mariadb/Dockerfile`): `FROM debian:bookworm` → one `RUN` apt (update + install mariadb-server/client + `rm -rf /var/lib/apt/lists/*` in the SAME layer) → `COPY` config + script → `chmod +x` → `EXPOSE 3306` → `ENTRYPOINT` in exec form.

**conf/inception.cnf:**

```ini
[mysqld]
bind-address = 0.0.0.0
port = 3306
```

Debian's default binds `127.0.0.1` — unreachable from other containers. `0.0.0.0` is safe here because the container's only networks are loopback + inception-net, and **no port is published**: nothing outside the network can reach 3306.

**tools/init_mariadb.sh** (entrypoint) does, in order:

1. Read secrets: `DB_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"` — `$(...)` **strips trailing newlines**, solving the "echo adds \n" problem.
2. **Re-init guard**: if `/var/lib/mysql/mysql` exists (i.e. the volume already holds a database) → `exec mariadbd --user=mysql` and skip everything else.
3. First run: `chown -R mysql:mysql /var/lib/mysql`, `mariadb-install-db` (writes system tables **into the volume** — the volume mounts over the image's data dir, hiding anything the package put there), start a **temporary daemon** on the unix socket only (`--skip-networking`), wait in an `until` loop until it accepts connections, then run SQL: set root password, `CREATE DATABASE`, `CREATE USER 'gabach'@'%'` (the `%` = reachable from other hosts/containers, not just localhost), `GRANT ALL PRIVILEGES ON wordpress.*`, `FLUSH PRIVILEGES`.
4. `kill` + `wait` the temp daemon (clean flush of the grant tables), then **`exec mariadbd --user=mysql`** → the daemon *becomes PID 1*.

**OS user vs DB user (classic trap):** `--user=mysql` is a **Linux account** (`/etc/passwd`) — the privilege-drop mechanism so the daemon doesn't run as root. `$DB_USER` (`gabach`) is a **MariaDB account** — a row in the grant tables used to authenticate clients. One lives in `/etc/passwd`, the other in the database. They never meet.

---

## 5. WordPress + php-fpm container

**FastCGI concept:** nginx is a static file server — it cannot execute PHP. **FastCGI** is the protocol connecting them: nginx receives `/index.php`, connects over TCP to **php-fpm** (a master process with a pool of PHP workers), passes the script path, php-fpm executes it and returns the rendered HTML. TCP 9000 across the network (not a unix socket — sockets are filesystem-local; nginx is in another container).

**Dockerfile** (`srcs/requirements/wordpress/Dockerfile`): `FROM debian:bookworm` → one `RUN` apt (php-fpm + `php-mysql` (mysqli driver — without it WP can't reach MariaDB) + php-curl/gd/xml/mbstring/zip/intl + curl + less) → download + extract WordPress to **`/var/www/wordpress`** (a pristine copy INSIDE the image — NOT `/var/www/html`, because the volume mounts over that path and an empty fresh volume *shadows* whatever the image had there) in one layer → download wp-cli phar to `/usr/local/bin/wp` → COPY `conf/www.conf` over the distro pool config → COPY + chmod entrypoint → `EXPOSE 9000` → ENTRYPOINT.

**conf/www.conf** — the real Debian php-fpm pool config with exactly two changes:

```ini
user = www-data       # Debian web user (was @php_fpm_user@ build placeholder)
group = www-data
listen = 9000         # bare port = ALL addresses, IPv6 AND IPv4 (was 127.0.0.1:9000)
```

Bare `9000` (not `0.0.0.0:9000`) because Docker DNS may resolve `wordpress` to an IPv6 address; bare-port listening covers both. Everything else (pool name `[www]`, `pm = dynamic`, `pm.max_children = 5`, `pm.start_servers = 2`, `pm.min_spare_servers = 1`, `pm.max_spare_servers = 3`) is upstream default — "adequate for a single-user demo site" is the honest defense answer.

**tools/init_wordpress.sh** (entrypoint):

1. Read secrets: `db_password`, `credentials` (parsed `login:password` via `cut -d:`). `$(cat)` strips trailing newlines.
2. **First-boot copy**: if `/var/www/html/index.php` missing → `cp -a /var/www/wordpress/. /var/www/html/` — populate the volume from the image's pristine copy (volume-shadowing fix), then `chown -R www-data:www-data`.
3. **`wp config create`** only if `wp-config.php` missing (wp-cli errors if it exists) — writes DB name/user/password/host into the volume; wp-cli generates the salt keys.
4. **`wp core is-installed`** guard → if not installed: **retry loop** (`until wp db check`) tolerating MariaDB not being ready yet (the `depends_on` doesn't-wait problem), then `wp core install --url=https://gabach.42.fr ... --admin_user=gabach --admin_password=...` and `wp user create regular-gabach` (subscriber role) → **two users**, admin name without "admin".
5. **`exec php-fpm8.2 -F`** — `-F` = foreground (php-fpm daemonizes by default), so the master becomes **PID 1**.

---

## 6. NGINX container

**Dockerfile**: `FROM debian:bookworm` → one `RUN` apt (nginx + openssl) → **generate the self-signed certificate inside the image**:

```
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
    -keyout /etc/nginx/ssl/key.pem -out /etc/nginx/ssl/cert.pem \
    -subj "/CN=gabach.42.fr"
```

The private key is generated at build time inside the image — **it never exists in git or on the host**.

Flag meanings: `req -x509` = issue a self-signed cert directly (not a CSR); `-nodes` = key stored unencrypted (else nginx prompts for a passphrase at start and containers can't type); `-newkey rsa:4096` = fresh 4096-bit RSA keypair; `-days 365` = validity; `-subj "/CN=..."` = Common Name (the domain) supplied non-interactively.

**conf/inception.conf** (dropped into `/etc/nginx/conf.d/`, which Debian's `nginx.conf` includes):

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name gabach.42.fr;

    ssl_certificate     /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root  /var/www/html;
    index index.php index.html;

    client_max_body_size 13m;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass wordpress:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
```

- **No `listen 80`** — 443 only, per subject.
- **`root /var/www/html`** — same path as the wordpress container's mount (shared volume). nginx serves static files directly; only `.php` goes to php-fpm.
- **`fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;`** — "execute this file": root + request URI. Valid inside the wordpress container **only because both containers mount the volume at the identical path**. Path mismatch = "File not found".
- **`client_max_body_size 13m`** — nginx default body cap is 1MB; without this, WordPress uploads >1MB fail with a confusing 413.
- Location selection: `location ~ \.php$` (regex) wins over `location /` (prefix) for URIs ending in `.php`.

**tools/init_nginx.sh**: `nginx -t` (validate config; fail fast with a readable error) then **`exec nginx -g "daemon off;"`** — `-g` injects a runtime global directive; nginx daemonizes by default, `daemon off` + `exec` = **nginx master is PID 1**.

---

## 7. The request path (say it out loud until it flows)

Browser → `https://gabach.42.fr` → `/etc/hosts` resolves the name to the VM's IP → Docker's published host port 443 → nginx container → TLS handshake (self-signed cert, TLSv1.2/1.3) → request `/` → nginx (static root = shared volume) → `.php` request → `location ~ \.php$` → `fastcgi_pass wordpress:9000` → Docker embedded DNS on inception-net → php-fpm worker → executes `/var/www/html/index.php` → WordPress boots → `mysqli` connects to `mariadb:3306` (same network, same DNS mechanism) → HTML rendered → back up the chain.

---

## 8. Key Docker concepts (general knowledge)

- **Image vs container**: image = frozen, read-only template (like a class); container = a running instance of it (like an object), with its own PID namespace, network stack, and a writable layer on top of the image layers.
- **Layers & cache**: every Dockerfile instruction creates a layer; Docker reuses cached layers when nothing changed. Order matters: stable steps first (apt), changing things later (COPY of your code). `apt-get update` + `install` + cleanup must share ONE `RUN` (separate layers → stale/missing package lists; deleting in a later layer doesn't shrink earlier ones — layers only accumulate).
- **PID 1**: the first process in a container; the container lives exactly as long as PID 1. A shell as PID 1 doesn't forward signals → `docker stop` hits the 10s timeout and SIGKILLs (unclean shutdown). `exec` replaces the script with the daemon **keeping the same PID** → daemon becomes PID 1, receives SIGTERM, shuts down cleanly (~1s stop = healthy signals).
- **Docker networks**: user-defined bridge networks get the embedded DNS server (127.0.0.11) that resolves container/service names. Default bridge has no DNS. `host` networking shares the host's whole stack (no isolation, port conflicts); `links` is the obsolete pre-DNS mechanism. Both forbidden by the subject.
- **Named volume vs bind mount**: bind mount = arbitrary host path declared in the service (`/host:/container`); named volume = Docker-managed storage referenced by name. `driver_opts` (`type: none, o: bind, device: ...`) on a named volume only tells the `local` driver **where to place the backing directory** — the service still references just the name, and Docker registers it in its volume store. Still a named volume.
- **Docker secrets vs env vars**: secrets are files mounted at `/run/secrets/<name>`; env vars are key-values in the process environment visible via `docker inspect` and `docker compose config`. Passwords belong in secrets; also the files are gitignored.
- **`docker compose config`**: validates + prints the fully-resolved compose file (after `.env` interpolation) — the debugging first step.
- **`EXPOSE` vs `ports`**: EXPOSE documents an internal port; `ports:` publishes it on the host. Nothing is reachable from outside without `ports:`.
- **VM vs Docker (required README comparison)**: a VM emulates hardware and runs a full guest OS with its own kernel (hypervisor; heavy, minutes to boot); Docker containers share the host kernel and isolate processes with **namespaces** (PID, network, mount, …) and **cgroups** (resource limits) — seconds to start, megabytes of overhead. A container is NOT a lightweight VM — it's an isolated process.
- **Self-signed TLS**: the server signs its own cert; browsers warn (trust can't be verified); `curl -k` skips verification. Fine here because `gabach.42.fr` is not a real domain, so no CA would sign it. TLS 1.0/1.1 are deprecated/broken → subject pins TLSv1.2/1.3.

---

## 9. Useful commands

```bash
# build & run the whole stack
docker compose -f srcs/docker-compose.yml up -d --build

# validate the compose file (first debugging step)
docker compose -f srcs/docker-compose.yml config

# status / ports / logs
docker compose -f srcs/docker-compose.yml ps
docker ps --format '{{.Names}} {{.Ports}}'
docker logs nginx            # any container name

# inspect one container's details (restart policy, mounts, network…)
docker inspect nginx

# PID 1 check
docker exec <c> cat /proc/1/cmdline
docker top <c>

# stop timing test (should be ~1s, not 10s → signals/PID1 are healthy)
time docker stop nginx

# inside mariadb
docker exec -it mariadb mariadb -u root -p
#   SHOW DATABASES;
#   SELECT user, host FROM mysql.user;
#   SHOW TABLES FROM wordpress;

# wordpress users
docker exec -it wordpress wp user list --allow-root --path=/var/www/html

# network / volume inspection
docker network inspect inception-net
docker volume ls
docker volume inspect srcs_wordpress

# TLS verification
curl -kI https://gabach.42.fr
curl -kv https://gabach.42.fr 2>&1 | grep -i protocol   # must show TLSv1.2/1.3

# full teardown (compose down keeps volumes; -v also deletes them)
docker compose -f srcs/docker-compose.yml down
docker compose -f srcs/docker-compose.yml down -v
```

---

## 10. Defense Q&A — questions an evaluator may ask

### Dockerfile & images

**Q: Why `debian:bookworm` and not `latest`?**
A: The subject requires the *penultimate* stable version of Alpine or Debian with a pinned tag. `latest` is a moving target — the image changes without my code changing, so builds aren't reproducible; the evaluator must get exactly my environment. Debian 13 (trixie) is current stable, so 12 (bookworm) is the penultimate — also more battle-tested.

**Q: Why did you choose Debian over Alpine?**
A: MariaDB's Debian package is the reference install, the documentation matches, and Alpine uses musl libc instead of glibc, which can cause subtle runtime quirks. Alpine's main advantage (tiny images) barely matters for a 3-container stack. Both are allowed by the subject.

**Q: Why are `apt-get update` and `apt-get install` in the same RUN?**
A: Each RUN is a layer. If `update` ran in its own (cached) layer, a later `install` could run with stale or missing package lists and fail or install wrong versions. Same layer = one consistent snapshot. The cleanup `rm -rf /var/lib/apt/lists/*` must also be in the same RUN: deleting files in a *later* layer doesn't shrink the image — layers only accumulate.

**Q: What does `EXPOSE` do?**
A: Nothing functional — it's documentation of which port the service listens on internally. Publishing to the host only happens with `ports:` in compose. Our stack publishes only 443.

**Q: COPY vs ADD?**
A: COPY just copies. ADD has magic behaviors (remote URLs, auto-extraction of archives) that cause surprises; you don't need them here, so use COPY.

**Q: ENTRYPOINT vs CMD?**
A: ENTRYPOINT is the fixed program the container runs; CMD supplies default arguments and is easily overridden (docker run image bash would replace a CMD entirely). A service container must always run its init script, so ENTRYPOINT (exec form), so it can't be bypassed.

**Q: Why is the entrypoint in exec (JSON) form?**
A: So PID 1 is my script itself. Shell form (`ENTRYPOINT script`) wraps it in `/bin/sh -c "script"` — the shell becomes PID 1 and breaks signal forwarding.

### PID 1 & processes

**Q: What is PID 1 and why does it matter?**
A: The first process started in a container becomes PID 1, and the container lives exactly as long as PID 1. If PID 1 is a shell or a `tail -f`, Docker's SIGTERM on `docker stop` is never forwarded → 10s timeout → SIGKILL → unclean shutdown (risk of data corruption). The daemon itself must be PID 1 to receive signals.

**Q: How do you make the daemon PID 1?**
A: The entrypoint script does its setup, then `exec`s the daemon — exec replaces the script process *keeping the same PID*, so mariadbd / php-fpm master / nginx master become PID 1. `docker stop` then completes in ~1 second.

**Q: Why is `tail -f /dev/null` / `sleep infinity` wrong?**
A: It makes a no-op process PID 1 while the daemon runs detached in the background — signals go nowhere, shutdown is unclean, and it's a fake PID 1. Forbidden explicitly by the subject.

**Q: Why does your mariadb script start a temporary daemon and then kill it?**
A: To create the database and users I need a running server to execute SQL against. So: initialize the data dir, start a temporary server bound to the unix socket only (not network-reachable), run the SQL, then kill + wait so all changes are flushed to disk in the volume, then exec the real daemon.

**Q: What does `--user=mysql` mean in `exec mariadbd --user=mysql`? Isn't your user `gabach`?**
A: `--user=mysql` is an **OS account** (`/etc/passwd`) — the classic Unix privilege drop so the daemon doesn't run as root. `gabach` is a **MariaDB account** — a row in the grant tables used to authenticate client logins. One belongs to the kernel, the other to the database. They never interact.

### Networks

**Q: Why a user-defined network?**
A: User-defined bridge networks come with Docker's embedded DNS server (127.0.0.11 inside containers) that resolves service names to their current IPs. That's how nginx reaches `wordpress:9000` and WordPress reaches `mariadb:3306` without any hardcoded IPs. The default bridge network has no DNS.

**Q: Why are `network: host` and `links:` forbidden?**
A: `host` shares the host's entire network stack — no isolation, port conflicts, defeats containerization. `links` is the obsolete pre-DNS hack (injects /etc/hosts entries); unnecessary since embedded DNS and deprecated.

**Q: What happens if I ping `wordpress` from nginx?**
A: Docker DNS resolves the name to the wordpress container's IP on inception-net; both containers share the network, so they can reach each other on any port the target listens on.

### Volumes

**Q: What is the difference between a named volume and a bind mount?**
A: A bind mount maps an arbitrary host path into the container, declared in the service (`/host:/container`). A named volume is Docker-managed storage referenced by name; Docker normally stores it under `/var/lib/docker/volumes/<name>/_data`. Bind mounts are forbidden by the subject.

**Q: Your data is in `/home/gabach/data` — isn't that a bind mount?**
A: No. The service references only the volume *name*. The location is a property of the volume itself, set via the `local` driver's `driver_opts` (`type: none, o: bind, device: /home/gabach/data/wordpress`), which just tells the driver where to place the backing directory. `docker volume ls` / `inspect` show a normal named volume. The subject requires named volumes *and* data under `/home/<login>/data`; this is the standard way to satisfy both.

**Q: Why two volumes and not one?**
A: Separation of concerns: website files (needed by wordpress AND nginx) vs database files (needed by mariadb only). Different consumers, different backup/lifecycle needs. The subject also requires exactly two.

**Q: Why does MariaDB need an init script if the package already initializes /var/lib/mysql?**
A: The package initializes at *install time* into the image's filesystem. But my volume mounts over `/var/lib/mysql`, hiding whatever the image had there. So on first boot the volume is empty and the script must initialize it *into the volume* (mariadb-install-db + SQL), guarded by a check so it never re-initializes on restart.

**Q: Why is WordPress copied into /var/www/wordpress in the image, not /var/www/html?**
A: Same shadowing reason: the volume mounts at /var/www/html. An empty fresh volume would hide the image's files at that path. The image keeps a pristine copy at /var/www/wordpress; the entrypoint copies it into the volume on first boot.

### Secrets & config

**Q: What's in `.env` and what's in secrets? Why both?**
A: `.env` holds non-confidential configuration (domain, DB name, usernames, hostnames) — compose interpolates `${VAR}` from it. Secrets hold credentials (passwords) as files, mounted at `/run/secrets/<name>` and read by the entrypoint. The subject mandates `.env` and recommends secrets for confidential data. If a password sat in `.env`, `docker compose config` or `docker inspect` would expose it.

**Q: How do secrets reach the container?**
A: The top-level `secrets:` block maps a name to a host file; the service-level `secrets:` list attaches it; Docker/compose mounts it as a plain file at `/run/secrets/<name>` inside the container. The script reads it with `$(cat ...)` — command substitution, which strips trailing newlines (so `echo`'s trailing `\n` doesn't corrupt the password).

**Q: Is there a password in your git repo?**
A: No. `secrets/` and `srcs/.env` are gitignored; `git status` never shows them. The only credential-adjacent thing in git is the nginx private key — which doesn't exist there either, because it's generated at build time inside the image.

### TLS & nginx

**Q: Why a self-signed certificate?**
A: `gabach.42.fr` isn't a real public domain, so no public CA would sign a certificate for it. Self-signed gives full TLS encryption; only the *trust* is unverified, which is why the browser warns and `curl` needs `-k`. The subject requires TLS, not public trust.

**Q: Explain your openssl command's flags.**
A: `req -x509` issues a self-signed certificate directly; `-nodes` stores the key unencrypted so nginx can start unattended (no passphrase prompt); `-newkey rsa:4096` generates a fresh 4096-bit RSA keypair; `-days 365` validity; `-subj "/CN=gabach.42.fr"` sets the Common Name non-interactively — it must match `server_name`, else the browser rejects name mismatch even beyond the trust warning.

**Q: Why only TLSv1.2/1.3?**
A: TLS 1.0 and 1.1 are cryptographically broken and officially deprecated (2018/2021). The subject pins `ssl_protocols TLSv1.2 TLSv1.3;` so the config explicitly allows only them — verifiable with `curl -kv ... | grep protocol`.

**Q: Why does nginx mount the WordPress volume too?**
A: Two reasons: it serves static files (css/js/images) directly from disk — that's nginx's core job — and it computes `SCRIPT_FILENAME` as root + URI for php-fpm. Both need the files at the *same path as the wordpress container*; if the paths differ, php-fpm gets a path that doesn't exist inside its own container ("File not found").

**Q: What does `fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;` do?**
A: It tells php-fpm which file to execute: the configured root (`/var/www/html`) concatenated with the requested URI. `$document_root` comes from the `root` directive, `$fastcgi_script_name` from the request. Without it (and only `include fastcgi_params`), php-fpm wouldn't know what to run.

**Q: Why `daemon off;`?**
A: nginx daemonizes by default (master forks to background, the starting process exits — the container would die instantly). `daemon off` keeps the master in the foreground; combined with `exec`, the master is PID 1 and handles `docker stop`'s SIGTERM.

**Q: What is `client_max_body_size 13m;` for?**
A: nginx caps request bodies at 1MB by default. WordPress media uploads bigger than that would fail with a 413 error, so the limit is raised to a sane value.

**Q: Why is there no `listen 80`?**
A: The subject: nginx is the only entrypoint, 443 only, TLS only. No HTTP listener exists in the config; `docker port nginx` shows only 443 published.

### WordPress / php-fpm

**Q: Why TCP 9000 and not a unix socket for php-fpm?**
A: php-fpm lives in a different container than nginx. Unix sockets are filesystem-local — they'd never cross containers. A TCP socket on the shared docker network, reached by service name via Docker DNS, is the container-native solution. Same reasoning as MariaDB's `bind-address = 0.0.0.0`.

**Q: Why `listen = 9000` (bare port) instead of `0.0.0.0:9000`?**
A: The pool config's own documentation: a bare port listens on *all* addresses including IPv6; `0.0.0.0` is IPv4-only. Docker's embedded DNS may resolve `wordpress` to an IPv6 address, and the bare-port form covers both, so nginx can never fail to connect.

**Q: Why php-fpm and not apache/php inside WordPress?**
A: The subject: one service = one container = one concern. nginx is the entrypoint/web server; the wordpress container only executes PHP. php-fpm is the standard way to run PHP behind a separate web server (FastCGI protocol).

**Q: How did you create the two WordPress users, and why two?**
A: In the wordpress entrypoint on first run, via wp-cli: `wp core install` creates the administrator (username `gabach` — deliberately not containing "admin", per the subject), then `wp user create` adds a regular subscriber user. The subject requires an administrator plus a second user.

**Q: What happens when the wordpress container restarts — does it reinstall?**
A: No. `wp core is-installed` (and the `wp-config.php` / `index.php` existence checks) detect the already-populated volume and skip installation; the entrypoint goes straight to `exec php-fpm`. That's the re-init guard pattern used in all three services.

### Compose & lifecycle

**Q: Does `depends_on` guarantee MariaDB is ready before WordPress starts?**
A: No — it only orders container *start*. The wordpress entrypoint handles real readiness itself: an `until wp db check` retry loop that waits until the DB actually answers.

**Q: What does `restart: always` do exactly, and `unless-stopped`?**
A: `always`: restart the container after any exit, and also restart it after the Docker daemon restarts — even if I had stopped it manually. `unless-stopped`: same, except a manually-stopped container stays stopped. Both satisfy "restart on crash".

**Q: What happens if a container crashes?**
A: The daemon (PID 1) exits, the container exits, and Docker's restart policy immediately starts a new container instance from the same image. Because state lives in the volumes, the new instance resumes with data intact — and the re-init guards make the second start skip first-boot initialization.

**Q: `image:` and `build:` are both set — which wins?**
A: `build:` builds the image from my Dockerfile and tags it with the `image:` name. The tag is required by the subject (image name = service name); `--build` on `up` forces a rebuild so evaluators see images come from my Dockerfiles.

**Q: How do I check what image a container is running?**
A: `docker ps` / `docker inspect <c>` (`.Config.Image`), `docker images` lists local ones. Each must be the one built from my `requirements/<service>/Dockerfile`, not something pulled from Docker Hub.

### General concepts

**Q: What is the difference between a container and a virtual machine?**
A: A VM emulates hardware and runs a full guest OS with its own kernel, managed by a hypervisor — heavy, slow to boot. A container shares the host kernel and isolates processes using **namespaces** (PID, network, mount, user) and **cgroups** (resource limits) — it's an isolated process, not a small VM. Boot time: seconds vs minutes; overhead: MBs vs GBs.

**Q: What is a Docker image, technically?**
A: A stack of read-only layers (one per Dockerfile instruction) plus JSON metadata (config, ENTRYPOINT, EXPOSE). Containers add a writable layer on top. Layers are cached and shared between images — that's why builds are fast and images are space-efficient.

**Q: How does `/etc/hosts` make `gabach.42.fr` work?**
A: DNS resolution on Linux consults `/etc/hosts` *before* DNS servers (per nsswitch). Adding `127.0.0.1 gabach.42.fr` (or the VM's IP) in the VM makes any request for that name resolve locally — no internet DNS needed. It's the simplest possible name resolution override.

**Q: What is `/proc/1/cmdline` telling you?**
A: The command line of PID 1 inside the container's PID namespace — `mariadbd`, `php-fpm: master process`, `nginx: master process` respectively. The one-line proof that a real daemon is PID 1.

**Q: Where is the MariaDB data physically?**
A: In the volume: physically at `/home/gabach/data/mariadb` on the VM (via driver_opts), mounted at `/var/lib/mysql` in the container. Destroying the container leaves the data; `docker compose down -v` deletes it.

**Q: How would you reset the whole project from scratch?**
A: `docker compose down -v` (stops, removes containers, networks, and volumes) then `up -d --build` — the WordPress volume is empty again so first-boot logic re-runs, and the data dir at `/home/gabach/data` can also be cleaned on the host.

**Q: Why is your admin username `gabach` and not `admin`?**
A: The subject forbids an administrator username containing "admin"/"administrator" in any form (easy-to-guess, brute-forced by default). Using my login satisfies the rule.

**Q: How do you verify the site is secure?**
A: `curl -kI https://gabach.42.fr` (reachable, cert accepted with -k), `curl -kv ... 2>&1 | grep -i protocol` (TLSv1.2/1.3 negotiated), `docker port nginx` (only 443 published), and no other container has a `ports:` mapping.

---

## 11. Final checklist (from the guide — run before asking for evaluation)

- [ ] Everything runs inside a VM.
- [ ] All config in `srcs/`, Makefile at root, `make` does the full setup.
- [ ] Images built from own Dockerfiles (penultimate stable Debian pinned — no `latest`).
- [ ] Image names = service names; one service = one container.
- [ ] `docker compose ps` → nginx, wordpress, mariadb running; `docker inspect` → restart policy set.
- [ ] PID 1 is the daemon in every container (no tail/sleep/while/bash hacks, not even in entrypoints).
- [ ] Only port 443 exposed; TLS 1.2/1.3 only; `curl -kI https://gabach.42.fr` returns 200/30x.
- [ ] Two named volumes; data visible under `/home/gabach/data`; no bind mounts in compose.
- [ ] Dedicated docker network; no `host`, no `links`.
- [ ] WP has two users; admin name contains no "admin" substring.
- [ ] `.env` used; secrets used for passwords; nothing confidential in git (`git log -p` clean).
- [ ] README.md (exact italic first line + Description/Instructions/Resources/AI usage + the four comparisons), USER_DOC.md, DEV_DOC.md present.
- [ ] `make clean && make` from a fresh clone works end-to-end.

---

## 12. What remains to build

1. **Makefile** (Phase 7): `all`, `up`, `down`, `clean`/`fclean`, `re` targets driving `docker compose -f srcs/docker-compose.yml`; `.PHONY`; a bare `make` must do the full setup.
2. **Documentation** (Phase 8): README.md with the exact italic first line `*This project has been created as part of the 42 curriculum by gabach.*` + Description, Instructions, Resources (including AI usage description), and the four comparisons (VM vs Docker, secrets vs env vars, docker network vs host network, volumes vs bind mounts); USER_DOC.md (admin/end-user view); DEV_DOC.md (developer view).
3. **Runtime verification in the VM** of everything above (all builds, first boots, PID 1 checks, end-to-end curl).
