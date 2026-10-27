*This project has been created as part of the 42 curriculum by gabach.*

# Inception

## Description

Inception is a small containerized infrastructure running entirely inside a
virtual machine. It serves a WordPress website over HTTPS, built from three
Docker images **built by this project** (no ready-made service images are
pulled):

| Service   | Role |
|-----------|------|
| `nginx`   | The only entrypoint: terminates TLS on port 443 (TLSv1.2/1.3 only), serves static files, and forwards `.php` requests to the WordPress container over the Docker network |
| `wordpress` | WordPress + php-fpm (no web server): executes PHP, installs WordPress and its users on first boot |
| `mariadb` | MariaDB only: stores the WordPress database, initialized on first boot with the site's database and users |

Key design points:

- **One service = one container = one Dockerfile**, all called from
  `srcs/docker-compose.yml`, itself driven by the `Makefile`.
- Base images are **pinned** (`debian:bookworm`, the penultimate stable
  Debian) — `latest` is never used.
- Each container runs its real daemon (mariadbd, php-fpm, nginx) as
  **PID 1** via `exec` in its entrypoint — no `tail -f`/`sleep` hacks —
  so signals are handled cleanly and containers restart on crash
  (`restart: always`).
- A dedicated **bridge network** with Docker's embedded DNS lets services
  reach each other by name (`wordpress:9000`, `mariadb:3306`).
- Two **named volumes** (not bind mounts) hold the WordPress files and the
  MariaDB database; their data physically lives in `/home/gabach/data`
  thanks to the `local` driver's options.
- Credentials are **Docker secrets** mounted at `/run/secrets/*`; the
  `.env` file holds only non-confidential configuration. No password is
  ever committed to git.
- WordPress has **two users**: an administrator (`gabach`) and a regular
  subscriber user.

## Instructions

Requirements: a VM with Docker and the compose v2 plugin, and the domain
`gabach.42.fr` mapped to the VM's loopback in `/etc/hosts`.

```bash
git clone <repo> && cd inception

# create the gitignored secret and env files (they never travel via git)
mkdir -p secrets
printf '%s' "$(openssl rand -base64 24)"  > secrets/db_root_password.txt
printf '%s' "$(openssl rand -base64 24)"  > secrets/db_password.txt
printf '%s' 'gabach:<strong-password>'    > secrets/credentials.txt
cat > srcs/.env <<'EOF'
DOMAIN_NAME=gabach.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=gabach
MYSQL_HOST=mariadb
EOF

make            # builds the three images and starts the whole stack
```

The site is then reachable at `https://gabach.42.fr` (self-signed
certificate — accept the browser warning or use `curl -k`).

Useful targets (`make help` lists them all):

| Command | Effect |
|---------|--------|
| `make` / `make all` | build images and start the stack |
| `make up` / `make down` | start / stop (keeps volumes, images, data) |
| `make clean` | down + remove the built images |
| `make fclean` | clean + remove volumes and data directories (destroys all data) |
| `make re` | fclean + all: full rebuild from scratch |

## Resources

References used while building the project:

- [Docker documentation](https://docs.docker.com/) — images, layers,
  build cache, networks, volumes, secrets
- [docker compose documentation](https://docs.docker.com/compose/) —
  service/network/volume/secret declarations, `.env` interpolation
- [MariaDB documentation](https://mariadb.com/docs) —
  `mariadb-install-db`, unix socket, auth plugins, grant tables
- [nginx documentation](https://nginx.org/en/docs/) — FastCGI,
  `fastcgi_pass`, SSL configuration
- [php-fpm documentation](https://www.php.net/manual/en/install.fpm.php) —
  pool configuration, foreground operation
- [WordPress CLI](https://wp-cli.org/) — `wp core install`, `wp user create`
- [openssl documentation](https://docs.openssl.org/) — self-signed
  certificate generation

**How AI was used:** an AI coding assistant (Mistral Vibe) was used as a
tutor and debugging companion throughout the project: explaining Docker
concepts (layers, PID 1, networks, volumes, secrets), proposing initial
versions of configuration files and scripts that were then read, understood
and adapted by the author, and helping diagnose first-boot failures by
interpreting container logs (missing CA certificates, missing unix-socket
directory, the pre-initialized MariaDB data directory copied into fresh
volumes, the missing `mysqlcheck` binary, and a corrupted php-fpm pool
config). All code was reviewed, tested and committed by the author, who
wrote and verified every component inside the VM. The AI did not run the
infrastructure itself; the author alone validated the running stack.

## Comparisons

### Virtual Machines vs Docker

A virtual machine emulates hardware: a hypervisor runs a full guest
operating system with its own kernel, drivers and memory footprint.
Booting one takes tens of seconds to minutes and it consumes gigabytes.
Docker containers share the host kernel: a container is an isolated
*process* — the isolation comes from Linux **namespaces** (PID, network,
mount, user...) and resource limits via **cgroups**, not from hardware
emulation. Containers start in seconds and share disk through image
layers. A container is therefore **not** a lightweight VM: it does not
virtualize hardware, it constrains what a process can see and use. In
this project that distinction is the whole point: three isolated
services boot in seconds inside one small VM, while each retains its own
filesystem, network stack and process tree.

### Secrets vs Environment Variables

Both inject configuration into containers, but they differ in exposure
and lifecycle. **Environment variables** are plain strings in a process's
environment: visible in `docker inspect`, in `/proc/<pid>/environ`, in
compose-resolved output (`docker compose config`), and inherited by every
child process. **Docker secrets** are files mounted at
`/run/secrets/<name>`: they are read by the container's processes only,
never appear as values in `docker inspect` output, and do not leak into
child environments automatically. This project splits configuration
accordingly: `.env` carries names (domain, database name, user names) —
non-confidential and interpolated by compose — while passwords live in
`secrets/`, are gitignored, and are read at container start by the
entrypoint scripts. If a password sat in `.env`, a single
`docker compose config` would expose it.

### Docker Network vs Host Network

With `network: host`, a container **shares the host's entire network
stack**: no isolation, every port the container opens is a host port,
`localhost` means the host, and port conflicts are the developer's
problem. It also erases the container boundary that makes service
addressing deterministic. A user-defined **bridge network** gives each
container its own stack, connected through a private bridge, and — the
decisive feature — an **embedded DNS server** so services find each other
by name: nginx calls `fastcgi_pass wordpress:9000` and WordPress connects
to `mariadb:3306` without a single hardcoded IP. The subject forbids
`host` networking and legacy `links:` for exactly these reasons: this
project relies on the DNS of the `inception-net` bridge network, and only
one port (443) is published to the host.

### Docker Volumes vs Bind Mounts

A **bind mount** maps an arbitrary host path into a container
(`/host/path:/container/path` in a service definition): the path is the
user's responsibility, the mount bypasses Docker's volume management, and
its content is whatever the host has. A **named volume** is a
Docker-managed storage unit: created and listed by Docker
(`docker volume ls`), mountable by name, and — notably — populated from
the image's content on first use. Bind mounts are forbidden by the
subject; this project uses two named volumes (`wordpress` and `mariadb`)
whose data must physically end up under `/home/gabach/data`. That is
achieved with the `local` volume driver's options
(`type: none, o: bind, device: /home/gabach/data/...`): the option only
tells the driver where to place the backing directory; services still
reference the volume by *name*, and Docker keeps registering it as a
named volume. The result satisfies both constraints: named volumes, with
data visible at the required host location.
