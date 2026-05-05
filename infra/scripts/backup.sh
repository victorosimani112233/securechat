#!/bin/bash
# SecureChat — PostgreSQL + Redis backup script
# Cron'la calistirin (gunluk):
#   0 3 * * * /opt/securechat/infra/scripts/backup.sh >> /var/log/securechat-backup.log 2>&1
#
# Backup dizini env ile ayarlanabilir; default: /opt/securechat/backups
# Eski backup'lar 14 gun sonra silinir (BACKUP_RETENTION_DAYS env).

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/securechat/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
TS=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR/postgres" "$BACKUP_DIR/redis"

echo "[$(date)] Backup basladi"

# --- PostgreSQL ---
PG_FILE="$BACKUP_DIR/postgres/securechat-${TS}.sql.gz"
docker exec securechat-postgres \
    pg_dump -U securechat -d securechat --clean --if-exists \
    | gzip -9 > "$PG_FILE"
PG_SIZE=$(du -h "$PG_FILE" | cut -f1)
echo "[$(date)] Postgres backup: $PG_FILE ($PG_SIZE)"

# --- Redis ---
# Redis BGSAVE → snapshot RDB dosyasini yedekle
docker exec securechat-redis \
    redis-cli -a "$REDIS_PASSWORD" --no-auth-warning BGSAVE > /dev/null
sleep 5 # BGSAVE asenkron — baska bir BGSAVE devam etmiyorsa hemen biter
RDB_FILE="$BACKUP_DIR/redis/dump-${TS}.rdb.gz"
docker cp securechat-redis:/data/dump.rdb - 2>/dev/null \
    | gzip -9 > "$RDB_FILE" || echo "[!] Redis backup atlandi"
RDB_SIZE=$(du -h "$RDB_FILE" 2>/dev/null | cut -f1 || echo "0")
echo "[$(date)] Redis backup: $RDB_FILE ($RDB_SIZE)"

# --- Eski backup'lari temizle ---
find "$BACKUP_DIR/postgres" -name "*.sql.gz" -mtime +"$RETENTION_DAYS" -delete 2>/dev/null
find "$BACKUP_DIR/redis" -name "*.rdb.gz" -mtime +"$RETENTION_DAYS" -delete 2>/dev/null

echo "[$(date)] Backup tamam. Eski dosyalar (>$RETENTION_DAYS gun) temizlendi."

# --- Opsiyonel: S3/B2 sync (uncomment edip ayarla) ---
# aws s3 sync "$BACKUP_DIR" s3://securechat-backups/ --delete
# rclone sync "$BACKUP_DIR" b2:securechat-backups/ --delete-excluded
