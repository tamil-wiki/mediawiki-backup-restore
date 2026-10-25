#! /usr/bin/env bash
# set -e
# Fail a pipeline when any command in it fails, not only the last one.
set -o pipefail

logger() {
  echo $(date +"%Y-%m-%dT%H%M%SZ") "$@"
}

# Upload a local backup file to S3 and refresh the "latest" copy.
# Returns non-zero when any upload fails, so callers can fail the backup.
copy_s3 () {
  local SRC_FILE=$1
  local DEST_FILE=$2
  local FREQUENCY=$3
  local DEST_LATEST_FILE="latest.${DEST_FILE#*.}"
  local UPLOAD_STATUS

  if [[ -z "$S3_ENDPOINT" ]]; then
    AWS_ARGS=""
  else
    AWS_ARGS="--endpoint-url $S3_ENDPOINT"
  fi

  logger "Uploading ${DEST_FILE} on S3..."
  if [[ -z "$S3_PREFIX" ]]; then
    # backup without prefix
    aws $AWS_ARGS s3 cp $SRC_FILE s3://$S3_BUCKET/$FREQUENCY/$DEST_FILE && \
    aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$FREQUENCY/$DEST_FILE s3://$S3_BUCKET/$FREQUENCY/$DEST_LATEST_FILE
    UPLOAD_STATUS=$?
  else
    aws $AWS_ARGS s3 cp $SRC_FILE s3://$S3_BUCKET/$S3_PREFIX/$FREQUENCY/$DEST_FILE && \
    aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$S3_PREFIX/$FREQUENCY/$DEST_FILE s3://$S3_BUCKET/$S3_PREFIX/$FREQUENCY/$DEST_LATEST_FILE
    UPLOAD_STATUS=$?
    # The hourly latest copy also goes to the prefix root, used by restore_latest.
    if [[ "$UPLOAD_STATUS" == "0" && "$FREQUENCY" == "hourly" ]]; then
      aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$S3_PREFIX/$FREQUENCY/$DEST_FILE s3://$S3_BUCKET/$S3_PREFIX/$DEST_LATEST_FILE
      UPLOAD_STATUS=$?
    fi
  fi
  # Status is captured right after each upload. Checking $? after the if/fi
  # block would read 0 whenever no branch ran, hiding upload failures.
  rm -f $SRC_FILE
  if [ "$UPLOAD_STATUS" == "0" ]; then
    logger "Successfully uploading ${FREQUENCY} backup file ${DEST_FILE} on S3"
  else
    logger "Error uploading ${FREQUENCY} backup file ${DEST_FILE} on S3"
    return 1
  fi
}

# Dump the MySQL database, gzip it and upload it to S3.
# Returns non-zero when mysqldump, gzip or the upload fails.
db_backup () {
  logger "Creating dump for ${MYSQLDUMP_DATABASE} from ${MYSQL_HOST}..."
  local DUMP_SQL_FILE="$BACKUP_DIR/$DUMP_START_TIME.dump.sql"
  local DUMP_FILE="$DUMP_SQL_FILE.gz"
  # Check mysqldump on its own. Earlier only gzip's status was checked, so a
  # failed or partial dump was still compressed and uploaded as a backup.
  if ! mysqldump --single-transaction $MYSQLDUMP_OPTIONS $MYSQL_HOST_OPTS $MYSQL_SSL_OPTS $MYSQLDUMP_DATABASE > $DUMP_SQL_FILE; then
    logger "Error creating mysqldump"
    rm -f "$DUMP_SQL_FILE"
    return 1
  fi
  logger "Compressing $DUMP_SQL_FILE"
  if ! gzip -f "$DUMP_SQL_FILE"; then
    logger "Error compressing $DUMP_SQL_FILE"
    rm -f "$DUMP_SQL_FILE" "$DUMP_FILE"
    return 1
  fi
  copy_s3 $DUMP_FILE "$DUMP_START_TIME.$FREQUENCY.dump.sql.gz" $FREQUENCY
}

# Tar and gzip the /mediawiki folder (uploaded images etc.) and upload it to S3.
# Returns non-zero when tar or the upload fails.
image_backup () {
  local MEDIAWIKI_DIR="/mediawiki"
  local DUMP_FILE="$BACKUP_DIR/$DUMP_START_TIME.mediawiki.tar.gz"
  if [ ! -d $MEDIAWIKI_DIR ]; then
    logger "Skipping mediawiki backup, $MEDIAWIKI_DIR is not mounted"
    return 0
  fi
  logger "Creating $DUMP_FILE from $MEDIAWIKI_DIR"
  if ! tar -czf "$DUMP_FILE" -C "$(dirname "$MEDIAWIKI_DIR")" "$(basename "$MEDIAWIKI_DIR")"; then
    logger "Error creating mediawiki"
    rm -f "$DUMP_FILE"
    return 1
  fi
  copy_s3 $DUMP_FILE "$DUMP_START_TIME.$FREQUENCY.mediawiki.tar.gz" $FREQUENCY
}

FREQUENCY=${1:-hourly}
MYSQL_HOST_OPTS="-h $MYSQL_HOST -P $MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD"
DUMP_START_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
BACKUP_DIR="/backup"
logger "Backup frequency ${FREQUENCY}"
logger "Backup is started at ${DUMP_START_TIME}"

# Both backups are on by default. Set one to "false" to run the DB and the
# image backups separately, e.g. on different servers or schedules.
DB_BACKUP_REQUIRED=${DB_BACKUP_REQUIRED:-true}
IMAGE_BACKUP_REQUIRED=${IMAGE_BACKUP_REQUIRED:-true}
BACKUP_STATUS=0

if [[ "$DB_BACKUP_REQUIRED" == "true" ]]; then
  db_backup || BACKUP_STATUS=1
else
  logger "Skipping DB backup, DB_BACKUP_REQUIRED=${DB_BACKUP_REQUIRED}"
fi

if [[ "$IMAGE_BACKUP_REQUIRED" == "true" ]]; then
  image_backup || BACKUP_STATUS=1
else
  logger "Skipping mediawiki backup, IMAGE_BACKUP_REQUIRED=${IMAGE_BACKUP_REQUIRED}"
fi

if [[ "$DB_BACKUP_REQUIRED" != "true" && "$IMAGE_BACKUP_REQUIRED" != "true" ]]; then
  logger "Warning: both DB_BACKUP_REQUIRED and IMAGE_BACKUP_REQUIRED are disabled, nothing was backed up"
fi

DUMP_END_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
if [[ "$BACKUP_STATUS" == "0" ]]; then
  logger "Backup is ends at ${DUMP_END_TIME}"
else
  logger "Backup failed, ends at ${DUMP_END_TIME}"
fi
exit $BACKUP_STATUS
