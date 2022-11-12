#! /usr/bin/env bash
# set -e

copy_s3 () {
  SRC_FILE=$1
  DEST_FILE=$2
  FREQUENCY=$3
  DEST_LATEST_FILE="latest.${DEST_FILE#*.}"

  if [[ -z "$S3_ENDPOINT" ]]; then
    AWS_ARGS=""
  else
    AWS_ARGS="--endpoint-url $S3_ENDPOINT"
  fi

  echo "Uploading ${DEST_FILE} on S3..."
  if [[ -z "$S3_PREFIX" ]]; then
    # backup without prefix
    aws $AWS_ARGS s3 cp $SRC_FILE s3://$S3_BUCKET/$FREQUENCY/$DEST_FILE && \
    aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$FREQUENCY/$DEST_FILE s3://$S3_BUCKET/$FREQUENCY/$DEST_LATEST_FILE
  else
    aws $AWS_ARGS s3 cp $SRC_FILE s3://$S3_BUCKET/$S3_PREFIX/$FREQUENCY/$DEST_FILE && \
    aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$S3_PREFIX/$FREQUENCY/$DEST_FILE s3://$S3_BUCKET/$S3_PREFIX/$FREQUENCY/$DEST_LATEST_FILE
    if [[ "$FREQUENCY" == "hourly"  ]]; then
      aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$S3_PREFIX/$FREQUENCY/$DEST_FILE s3://$S3_BUCKET/$S3_PREFIX/$DEST_LATEST_FILE
    fi
  fi
  if [ "$?" == "0" ]; then
    echo "Successfully uploading ${FREQUENCY} backup file ${DEST_FILE} on S3"
  else
    echo "Error uploading ${FREQUENCY} backup file ${DEST_FILE} on S3"
  fi
  rm -f $SRC_FILE
}
FREQUENCY=$1
MYSQL_HOST_OPTS="-h $MYSQL_HOST -P $MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD"
DUMP_START_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
BACKUP_DIR="/backup"

echo "Backup frequency ${FREQUENCY}"
echo "Backup is started at ${DUMP_START_TIME}"
echo "Creating dump for ${MYSQLDUMP_DATABASE} from ${MYSQL_HOST}..."
DUMP_SQL_FILE="$BACKUP_DIR/$DUMP_START_TIME.dump.sql"
DUMP_FILE="$DUMP_SQL_FILE.gz"
mysqldump --single-transaction $MYSQLDUMP_OPTIONS $MYSQL_HOST_OPTS $MYSQL_SSL_OPTS $MYSQLDUMP_DATABASE > $DUMP_SQL_FILE
echo "Compressing $DUMP_SQL_FILE"
gzip -f "$DUMP_SQL_FILE"

if [ "$?" == "0" ]; then
  S3_FILE="$DUMP_START_TIME.$FREQUENCY.dump.sql.gz"
  copy_s3 $DUMP_FILE $S3_FILE $FREQUENCY
else
  echo "Error creating mysqldump"
fi

MEDIAWIKI_DIR="/mediawiki"
DUMP_FILE="$BACKUP_DIR/$DUMP_START_TIME.mediawiki.tar.gz"
# backup mediawiki folder
if [ -d $MEDIAWIKI_DIR ]; then
  echo "Creating $DUMP_FILE from $MEDIAWIKI_DIR"
  # Gzip mediawiki folder
  tar -czf $DUMP_FILE -C $(dirname $MEDIAWIKI_DIR) $(basename $MEDIAWIKI_DIR)
  if [ "$?" == "0" ]; then
    S3_FILE="$DUMP_START_TIME.$FREQUENCY.mediawiki.tar.gz"
    copy_s3 $DUMP_FILE $S3_FILE $FREQUENCY
  else
    echo "Error creating mediawiki"
  fi
fi

DUMP_END_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
echo "Backup is ends at ${DUMP_END_TIME}"
