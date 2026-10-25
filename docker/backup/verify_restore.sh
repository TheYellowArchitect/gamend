#!/usr/bin/env bash
#
# Restore the newest dump into a throwaway database, count what came back, and
# drop it. This is the half of a backup that people skip and then discover, on
# the one day it matters, that they never had.
#
# Safe by construction: it only ever CREATEs and DROPs a database named
# gamend_verify_<timestamp>. It never writes to the live one.
#
#   docker compose run --rm db_backup /usr/local/bin/verify_restore.sh
#
# Run it monthly, and after any Postgres upgrade — a major-version bump is the
# most likely thing to make an old dump unrestorable.
#
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups}"
VERIFY_DB="gamend_verify_$(date -u +%Y%m%d%H%M%S)"

log() { printf '%s verify_restore %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

# `|| true` is load-bearing: a glob that matches nothing is passed to ls
# literally, ls exits non-zero, and `set -o pipefail` would abort the script
# before it could print its own "no dump found" message.
newest=$(ls -1t "$BACKUP_DIR"/daily/*.dump "$BACKUP_DIR"/weekly/*.dump \
  "$BACKUP_DIR"/monthly/*.dump 2>/dev/null | head -1 || true)

if [ -z "$newest" ]; then
  log "FAILED no dump found under $BACKUP_DIR"
  exit 1
fi

log "verifying $(basename "$newest") ($(du -h "$newest" | cut -f1))"

cleanup() {
  psql --dbname=postgres --quiet --command="DROP DATABASE IF EXISTS \"$VERIFY_DB\";" >/dev/null 2>&1 || true
}
trap cleanup EXIT

psql --dbname=postgres --quiet --command="CREATE DATABASE \"$VERIFY_DB\";"

# --exit-on-error so a partial restore is a failure rather than a warning we
# scroll past. --no-owner/--no-privileges because the scratch database has no
# reason to carry the production role grants.
if ! pg_restore --dbname="$VERIFY_DB" --no-owner --no-privileges --exit-on-error "$newest"; then
  log "FAILED restore did not complete cleanly"
  exit 1
fi

log "restored; row counts follow"

# The point of counting is that a dump can restore perfectly and still be empty.
# These are the tables whose loss would actually end the project.
psql --dbname="$VERIFY_DB" --quiet --no-align --tuples-only --command="
  SELECT format('  %-28s %s', relname, n_live_tup)
  FROM pg_stat_user_tables
  WHERE n_live_tup > 0
  ORDER BY n_live_tup DESC
  LIMIT 25;"

total=$(psql --dbname="$VERIFY_DB" --quiet --no-align --tuples-only --command="
  SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';")

users=$(psql --dbname="$VERIFY_DB" --quiet --no-align --tuples-only --command="
  SELECT count(*) FROM users;" 2>/dev/null || echo "?")

log "restored $total tables; users=$users"

if [ "$users" = "0" ] || [ "$users" = "?" ]; then
  log "FAILED the restore produced no users — treat this dump as bad"
  exit 1
fi

log "OK — this dump is restorable"
