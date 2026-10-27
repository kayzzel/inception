# Inception — User Documentation

This document is for the **user/administrator of the running stack**:
what it provides, how to operate it, and how to check it is healthy.
For development details see `DEV_DOC.md`.

## What this stack provides

- A **WordPress website** reachable at `https://gabach.42.fr`, served over
  TLS (port 443 only — there is no HTTP listener).
- A **WordPress admin panel** at `https://gabach.42.fr/wp-admin`.
- Two WordPress accounts:
  - **`gabach`** — the site administrator (username contains no "admin",
    as required by the subject).
  - **`regular-gabach`** — a regular subscriber user, for demonstration.
- All data (site files and database) **persists** across restarts and
  rebuilds in `/home/gabach/data` on the VM.

## Starting and stopping

Run these commands from the project root inside the VM:

| Command | Effect |
|---------|--------|
| `make` | Build the images if needed and start the whole stack |
| `make up` | Start the stack (no rebuild) |
| `make down` | Stop everything, keep all data |
| `make re` | Destroy everything (including site data!) and rebuild from scratch |

> `make clean` and `make fclean` are **destructive**: `fclean` removes the
> volumes and the data directories, so the WordPress site and its database
> are deleted. The next `make` re-initializes an empty site. Use them only
> when you really want to start from zero.

## Accessing the site

1. Make sure the stack is running (`docker ps` shows `nginx`, `wordpress`
   and `mariadb`).
2. Open `https://gabach.42.fr` in the VM's browser.
3. The certificate is **self-signed** (the domain is local), so the
   browser shows a warning — accept it to proceed. The connection itself
   is encrypted (TLSv1.2 or TLSv1.3 only).

Command-line check: `curl -kI https://gabach.42.fr` should answer
`200` (or a `301` redirect).

## Logging into WordPress

1. Go to `https://gabach.42.fr/wp-admin`.
2. Log in as **`gabach`** with the WordPress admin password.
   - It is stored in `secrets/credentials.txt` on the VM, in the form
     `login:password`.
   - **Never commit this file** — it is gitignored on purpose.
3. From the admin panel you can create posts, change the theme, upload
   media (uploads up to 13 MB), and manage users.

## Where credentials live

| File | Content |
|------|---------|
| `secrets/credentials.txt` | WordPress admin login:password |
| `secrets/db_root_password.txt` | MariaDB root password |
| `secrets/db_password.txt` | MariaDB WordPress-user password |

All three are gitignored and must exist **on the machine where the stack
runs** before `make`. The stack reads them at container start as Docker
secrets (`/run/secrets/*`); editing them requires restarting the stack
(and, for database passwords, re-initializing the database —
`make re`).

## Checking the stack is healthy

```bash
docker ps                       # all three containers Up, no restart loops
docker logs --tail 20 nginx     # "ready" lines, no errors
curl -kI https://gabach.42.fr   # HTTP 200/301
```

If a container shows `Restarting` in `docker ps`, its logs
(`docker logs <name>`) explain why. Stopping with `docker stop <name>`
should take about a second (clean PID-1 shutdown), and the container will
come back automatically on the next `make up` (or never leave, thanks to
`restart: always`, unless the daemon itself was stopped).

## Data and backups

- **Website files**: `/home/gabach/data/wordpress` (WordPress install,
  themes, uploads).
- **Database files**: `/home/gabach/data/mariadb`.

To back up: stop the stack (`make down`) and copy those two directories.
To restore: put the directories back and run `make up`.
