#!/usr/bin/env bash
#
# The backup loop: the entrypoint of the gamend-backup image
# (docker/backup/README.md), run as a compose service, never by hand.
#
# One dump per interval into /backups/daily, promoted into /backups/weekly on
# Mondays and /backups/monthly on the 1st, each directory pruned to its own
# count. Every dump is verified readable before it is kept, because an
# unverified dump is a belief rather than a backup.
#
# Design notes worth knowing before changing anything here:
#
#   * The image is the SAME postgres major the server runs, so `pg_dump` can
#     never be older than the server it is dumping. A newer server with an
#     older pg_dump is a hard error, and it is the usual way a backup job
#     silently stops working after an upgrade.
#
#   * The schedule is an INTERVAL, not a wall-clock hour. A container that was
#     down at 03:00 would skip that day entirely under cron semantics; here it
#     notices the newest dump is stale and runs on the next start. That is the
#     failure mode this job exists to survive.
#
#   * `-Fc` (custom format) rather than plain SQL: it is compressed, and
#     `pg_restore` can list it, restore one table from it, or restore it into a
#     differently-named database. A plain .sql dump can do none of that.
#
#   * Off-host copying is deliberately NOT built in. Drop an executable at
#     /backups/post_backup.sh and it is called with the new dump's path; that
#     keeps rclone/rsync/restic credentials out of this repo and out of the
#     image. Until something copies these off the box, a backup on the same
#     disk as the database only protects against a bad migration, not a dead
#     disk.
#
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups}"
EVERY_SECONDS="${BACKUP_EVERY_SECONDS:-86400}"
KEEP_DAILY="${BACKUP_KEEP_DAILY:-14}"
KEEP_WEEKLY="${BACKUP_KEEP_WEEKLY:-8}"
KEEP_MONTHLY="${BACKUP_KEEP_MONTHLY:-12}"
RUN_ONCE="${BACKUP_RUN_ONCE:-0}"

log() { printf '%s db_backup %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

fail() {
  # One greppable line per failure: wherever the container's stdout is
  # collected, `db_backup FAILED` is what an alert rule should watch for — a
  # backup job nobody is told about is the same as no backup job.
  log "FAILED $*"
  return 1
}

wait_for_db() {
  local waited=0
  until pg_isready --quiet; do
    if [ "$waited" -ge 300 ]; then
      fail "database not ready after ${waited}s"
      return 1
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

# Seconds since the last SUCCESSFUL dump, or a very large number when there has
# never been one.
#
# The stamp file is the source of truth rather than a file mtime: promotion uses
# hard links and an off-host hook may touch files, so mtimes are not reliably
# "when we last backed up". Two guards keep the stamp honest — an empty daily
# directory always means "due now", whatever the stamp says.
newest_age() {
  local last

  if [ -z "$(ls -1 "$BACKUP_DIR"/daily/*.dump 2>/dev/null)" ]; then
    echo 999999999
    return
  fi

  last=$(cat "$BACKUP_DIR/.last_run" 2>/dev/null || true)

  case "$last" in
    ''|*[!0-9]*) echo 999999999 ;;
    *) echo $(($(date +%s) - last)) ;;
  esac
}

# Keep the newest $2 files in directory $1, delete the rest.
#
# `ls -1t` rather than `find -printf`: the names this script generates contain
# no spaces or newlines by construction, so the simple form is safe, and it
# keeps the script runnable outside the container for testing.
prune() {
  local dir="$1" keep="$2" removed count
  # `|| true` because an empty directory makes the glob literal, which makes
  # ls exit non-zero, which `set -o pipefail` would turn into a dead script on
  # the very first run — when weekly and monthly are both empty.
  removed=$(ls -1t "$dir"/*.dump 2>/dev/null | tail -n "+$((keep + 1))" || true)

  if [ -n "$removed" ]; then
    count=$(printf '%s\n' "$removed" | wc -l | tr -d ' ')
    printf '%s\n' "$removed" | while read -r f; do rm -f -- "$f"; done
    log "pruned $count from $(basename "$dir"), keeping $keep"
  fi
}

run_backup() {
  local stamp file tmp size
  stamp=$(date -u +%Y%m%d-%H%M%S)
  file="$BACKUP_DIR/daily/${PGDATABASE}-${stamp}.dump"
  tmp="${file}.partial"

  wait_for_db || return 1

  log "dumping ${PGDATABASE} from ${PGHOST}"

  # Written to .partial and only renamed once verified, so an interrupted or
  # corrupt dump can never be mistaken for a good one by the restore scripts,
  # which always take the newest *.dump.
  if ! pg_dump --format=custom --compress=6 --file="$tmp" 2>&1; then
    rm -f -- "$tmp"
    fail "pg_dump returned non-zero"
    return 1
  fi

  # Reading the table of contents back proves the archive is not truncated and
  # that pg_restore can parse it. It is the cheapest check that distinguishes
  # "a file exists" from "a backup exists".
  if ! pg_restore --list "$tmp" >/dev/null 2>&1; then
    rm -f -- "$tmp"
    fail "dump failed its readability check and was discarded"
    return 1
  fi

  mv -- "$tmp" "$file"
  date +%s > "$BACKUP_DIR/.last_run"
  size=$(du -h "$file" | cut -f1)
  log "wrote $(basename "$file") ($size)"

  # Promote rather than re-dump: a weekly is a hard link to that day's daily,
  # so it costs no extra disk until the daily is pruned out from under it.
  if [ "$(date -u +%u)" = "1" ]; then
    ln -f -- "$file" "$BACKUP_DIR/weekly/$(basename "$file")"
    log "promoted to weekly"
  fi

  if [ "$(date -u +%d)" = "01" ]; then
    ln -f -- "$file" "$BACKUP_DIR/monthly/$(basename "$file")"
    log "promoted to monthly"
  fi

  prune "$BACKUP_DIR/daily" "$KEEP_DAILY"
  prune "$BACKUP_DIR/weekly" "$KEEP_WEEKLY"
  prune "$BACKUP_DIR/monthly" "$KEEP_MONTHLY"

  # The off-host hook. Failure is logged and does not fail the backup: the dump
  # on local disk is already safe, and a broken upload should not stop tomorrow's
  # dump from being taken.
  if [ -x "$BACKUP_DIR/post_backup.sh" ]; then
    if "$BACKUP_DIR/post_backup.sh" "$file"; then
      log "post_backup.sh ok"
    else
      log "FAILED post_backup.sh returned non-zero (dump is still on local disk)"
    fi
  fi
}

mkdir -p "$BACKUP_DIR"/{daily,weekly,monthly}

log "started; every ${EVERY_SECONDS}s, keeping ${KEEP_DAILY} daily / ${KEEP_WEEKLY} weekly / ${KEEP_MONTHLY} monthly"

if [ "$RUN_ONCE" = "1" ]; then
  run_backup
  exit $?
fi

while true; do
  age=$(newest_age)

  if [ "$age" -ge "$EVERY_SECONDS" ]; then
    # `|| true` so a single failed run cannot kill the loop: tomorrow's dump
    # should still be attempted, and the FAILED line is already logged.
    run_backup || true
    sleep "$EVERY_SECONDS"
  else
    # Sleep exactly until the next one is due rather than polling.
    sleep $((EVERY_SECONDS - age))
  fi
done
