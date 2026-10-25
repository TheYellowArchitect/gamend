# Database backups

The `gamend-backup` image (`ghcr.io/appsinacup/gamend-backup:18`): a Postgres
image whose entrypoint dumps one database once a day, verifies the dump, and
keeps daily, weekly and monthly copies. A `pgdata` volume on one host is a
single copy of every account; this is the second one.

## What runs

A `db_backup` service beside the database (the compose snippet is at the top
of `Dockerfile`). Its tag is the **Postgres major the database runs**, so
`pg_dump` is never older than the server: a mismatched pg_dump is the usual way
a backup job stops working silently after an upgrade.

| | |
|---|---|
| Schedule | every `BACKUP_EVERY_SECONDS` (default 24 h), catching up on start if the newest dump is stale |
| Format | `pg_dump -Fc`, compressed, so `pg_restore` can list it and restore selectively |
| Verified | every dump's table of contents is read back before the file is kept; a dump that fails is deleted, not stored |
| Retention | 14 daily · 8 weekly (Mondays) · 12 monthly (the 1st), each pruned by count |
| Location | `./backups/{daily,weekly,monthly}` on the host |

Weeklies and monthlies are **hard links** to that day's daily, so they cost no
extra disk until the daily is pruned out from under them.

## Turning it on

```bash
docker compose up -d db_backup
```

Take the first one immediately rather than waiting a day:

```bash
docker compose run --rm -e BACKUP_RUN_ONCE=1 db_backup
```

## Verifying a backup is real

An unverified backup is a belief. This restores the newest dump into a
throwaway database, counts what came back, and drops it. It never touches the
live database.

```bash
docker compose run --rm db_backup /usr/local/bin/verify_restore.sh
```

**Run it monthly, and after every Postgres upgrade** — a major-version bump is
the most likely thing to make an old dump unrestorable, and you want to find
that out on a Tuesday rather than during an outage.

## Restoring

```bash
# what have we got?
docker compose run --rm db_backup /usr/local/bin/restore.sh --list

# recover into a scratch database and look at it first (the safe default)
docker compose run --rm db_backup /usr/local/bin/restore.sh \
  /backups/daily/gamend-20260902-030000.dump --into gamend_recovered

# replace the live database (stops for confirmation, refuses if the app is up)
docker compose stop app
docker compose run --rm db_backup /usr/local/bin/restore.sh \
  /backups/daily/gamend-20260902-030000.dump --into gamend --overwrite
docker compose start app
```

Restoring into a new name is the default on purpose: it lets you inspect the
recovered data before pointing the app at it, and promoting afterwards is one
`ALTER DATABASE ... RENAME`.

## Getting them off the box — do this

**Everything above still lives on the same disk as the database.** It protects
you against a bad migration, a wrong `DELETE`, and a corrupt table. It does not
protect you against the disk, the host, or the provider.

Rather than build credentials for one storage vendor into this repo, the loop
calls `./backups/post_backup.sh` with the new dump's path if that file exists
and is executable. Anything works — `rclone`, `rsync`, `restic`, `scp`. For
example:

```bash
#!/bin/sh
# ./backups/post_backup.sh — runs inside the db_backup container.
set -eu
rclone copy "$1" remote:my-backups/ --config /backups/rclone.conf
```

A failing hook is logged and does **not** fail the backup: the dump on local
disk is already safe, and a broken upload should not stop tomorrow's dump.

The image is Postgres with these scripts, so install whatever tool you choose
in a small image built `FROM ghcr.io/appsinacup/gamend-backup:18`, or have the
hook write a marker file that a host-side cron job watches. Keep `./backups`
out of git and out of the app's Docker build context (`.gitignore`,
`.dockerignore`).

## Watching it

Every run logs one line to stdout (`docker compose logs db_backup`). Failures
are always prefixed `FAILED`; where the logs are collected (Loki, say), that is
the line to alert on:

```
{service="db_backup"} |= "FAILED"
```

A backup job nobody is told about is the same as no backup job.

## Configuration

All optional; the defaults are the table above. Set them in `.env`.

| Variable | Default | |
|---|---|---|
| `BACKUP_EVERY_SECONDS` | `86400` | interval between dumps |
| `BACKUP_KEEP_DAILY` | `14` | |
| `BACKUP_KEEP_WEEKLY` | `8` | |
| `BACKUP_KEEP_MONTHLY` | `12` | |
| `BACKUP_RUN_ONCE` | `0` | `1` dumps once and exits, for a manual run |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | `postgres` / `postgres` / `gamend` | shared with the `db` service so the two cannot drift |

Those last three are now read from one place by both services. **Changing
`POSTGRES_PASSWORD` in `.env` does not change the password of an existing
database** — `initdb` runs only on an empty volume. To actually rotate it, set
the variable *and* run `ALTER USER postgres WITH PASSWORD '…';` against the
running server, then restart the stack so the app picks up the new value.
