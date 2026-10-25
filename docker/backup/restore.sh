#!/usr/bin/env bash
#
# Restore a dump. This is the script you run on the worst day, so it is
# deliberately slow to use and says exactly what it is about to do.
#
#   docker compose run --rm db_backup /usr/local/bin/restore.sh --list
#   docker compose run --rm db_backup /usr/local/bin/restore.sh <dump> --into <db>_recovered
#   docker compose run --rm db_backup /usr/local/bin/restore.sh <dump> --into <db> --overwrite
#
# <db> is the live database's name, $PGDATABASE. With a compose file of another
# name, say so: docker compose -f docker-compose.prod.yml run --rm db_backup …
#
# Restoring INTO A NEW DATABASE is the default and is almost always what you
# want: it lets you look at the recovered data before pointing the app at it,
# and it leaves the live database untouched while you do. Promoting afterwards
# is one rename.
#
# --overwrite drops and recreates the target. It requires typing the database
# name back, and it refuses to run while anything is still connected — a
# restore over a live app is how a bad hour becomes a bad week.
#
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups}"
dump=""
target=""
overwrite=0

log() { printf '%s restore %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
die() { log "FAILED $*"; exit 1; }

if [ "${1:-}" = "--list" ] || [ $# -eq 0 ]; then
  echo "Available dumps under $BACKUP_DIR (newest first):"
  { ls -1t "$BACKUP_DIR"/daily/*.dump "$BACKUP_DIR"/weekly/*.dump \
    "$BACKUP_DIR"/monthly/*.dump 2>/dev/null || true; } \
    | while read -r f; do
        printf '  %s  %7s  %s\n' \
          "$(date -u -r "$f" +'%Y-%m-%d %H:%M UTC')" "$(du -h "$f" | cut -f1)" "$f"
      done
  echo
  echo "Restore with:  restore.sh <dump> --into <database>"
  exit 0
fi

dump="$1"; shift
while [ $# -gt 0 ]; do
  case "$1" in
    --into) target="${2:-}"; shift 2 ;;
    --overwrite) overwrite=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -f "$dump" ] || die "no such dump: $dump"
[ -n "$target" ] || die "pass --into <database>"

pg_restore --list "$dump" >/dev/null 2>&1 || die "$dump is not a readable custom-format dump"

exists=$(psql --dbname=postgres --quiet --no-align --tuples-only \
  --command="SELECT 1 FROM pg_database WHERE datname = '$target';")

if [ -n "$exists" ]; then
  [ "$overwrite" = "1" ] || die "$target already exists; pass --overwrite to replace it, or --into a new name"

  connections=$(psql --dbname=postgres --quiet --no-align --tuples-only \
    --command="SELECT count(*) FROM pg_stat_activity WHERE datname = '$target' AND pid <> pg_backend_pid();")

  if [ "$connections" != "0" ]; then
    die "$target has $connections open connection(s) — stop the app first (docker compose stop app)"
  fi

  echo
  echo "  About to DROP the database '$target' and replace it with"
  echo "  $(basename "$dump") ($(du -h "$dump" | cut -f1), taken $(date -u -r "$dump" +'%Y-%m-%d %H:%M UTC'))."
  echo
  printf "  Type the database name to confirm: "
  read -r confirm
  [ "$confirm" = "$target" ] || die "confirmation did not match; nothing was changed"

  psql --dbname=postgres --quiet --command="DROP DATABASE \"$target\";"
  log "dropped $target"
fi

psql --dbname=postgres --quiet --command="CREATE DATABASE \"$target\";"
log "restoring $(basename "$dump") into $target"

# Not --exit-on-error here, unlike the verify script: on a real recovery you
# want as much of the data back as possible, and then to read what failed.
# Errors are printed and counted rather than aborting the run.
pg_restore --dbname="$target" --no-owner --no-privileges --verbose "$dump" 2>&1 \
  | grep -Ei 'error|warning' || true

users=$(psql --dbname="$target" --quiet --no-align --tuples-only --command="SELECT count(*) FROM users;" 2>/dev/null || echo "?")
log "done — $target has users=$users"
echo
echo "  If this looks right and you restored into a scratch name, promote it with:"
echo "    docker compose stop app"
echo "    psql -c 'ALTER DATABASE $PGDATABASE RENAME TO ${PGDATABASE}_old;'"
echo "    psql -c 'ALTER DATABASE $target RENAME TO $PGDATABASE;'"
echo "    docker compose start app"
