#!/usr/bin/env bash
# Nightly Postgres logical backup: pg_dump inside the compose postgres
# service, verified with pg_restore --list before it leaves the container,
# then uploaded to S3 with write-only credentials.
#
# Configuration comes from the environment (systemd EnvironmentFile):
#   PG_BACKUP_BUCKET            required, S3 bucket name
#   AWS_ACCESS_KEY_ID           required, write-only backup credentials
#   AWS_SECRET_ACCESS_KEY       required
#   AWS_REGION                  required
#   PG_BACKUP_PREFIX            key prefix, default "postgres"
#   PG_BACKUP_APP_PATH          compose project dir, default /srv/bfp
#   PG_BACKUP_COMPOSE_FILES     default "compose.yaml compose.production.yaml"
#   PG_BACKUP_SPOOL_DIR         local spool, default /var/backups/pg
#   PG_BACKUP_SPOOL_KEEP        local dumps to keep, default 2
#   PG_BACKUP_HEALTHCHECK_URL   optional, pinged only after a verified upload
set -euo pipefail

: "${PG_BACKUP_BUCKET:?PG_BACKUP_BUCKET is required}"

app_path="${PG_BACKUP_APP_PATH:-/srv/bfp}"
prefix="${PG_BACKUP_PREFIX:-postgres}"
spool_dir="${PG_BACKUP_SPOOL_DIR:-/var/backups/pg}"
spool_keep="${PG_BACKUP_SPOOL_KEEP:-2}"

compose_args=()
for file in ${PG_BACKUP_COMPOSE_FILES:-compose.yaml compose.production.yaml}; do
  compose_args+=(-f "$file")
done

cd "$app_path"

db_name="$(docker compose "${compose_args[@]}" exec -T postgres printenv POSTGRES_DB)"
db_name="${db_name//$'\r'/}"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
dump_file="$spool_dir/${db_name}-${stamp}.dump"

mkdir -p "$spool_dir"
chmod 700 "$spool_dir"
trap 'rm -f "$dump_file.partial"' EXIT

# Dump and verify inside the container so a truncated or corrupt archive
# can never reach the spool, then stream the verified bytes out.
docker compose "${compose_args[@]}" exec -T postgres sh -c '
  set -eu
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc --file /tmp/pg_backup.dump
  pg_restore --list /tmp/pg_backup.dump >/dev/null
  cat /tmp/pg_backup.dump
  rm -f /tmp/pg_backup.dump
' >"$dump_file.partial"

if [ ! -s "$dump_file.partial" ]; then
  echo "backup failed: empty dump for $db_name" >&2
  exit 1
fi
mv "$dump_file.partial" "$dump_file"

s3_url="s3://$PG_BACKUP_BUCKET/$prefix/$db_name/$(basename "$dump_file")"
aws s3 cp --only-show-errors "$dump_file" "$s3_url"

# Keep a couple of recent dumps on disk for fast local restores; the daily
# Lightsail snapshot picks these up too.
ls -1t "$spool_dir"/*.dump 2>/dev/null | tail -n +"$((spool_keep + 1))" | xargs -r rm -f --

if [ -n "${PG_BACKUP_HEALTHCHECK_URL:-}" ]; then
  curl -fsS -m 10 --retry 3 -o /dev/null "$PG_BACKUP_HEALTHCHECK_URL" || true
fi

echo "backup ok: $s3_url ($(du -h "$dump_file" | cut -f1))"
