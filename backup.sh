#! /usr/bin/env bash

copy_s3 () {
  SRC_FILE=$1
  DEST_FILE=$2

  if [[ -z "$S3_ENDPOINT" ]]; then
    AWS_ARGS=""
  else
    AWS_ARGS="--endpoint-url $S3_ENDPOINT"
  fi

  echo "Uploading ${DEST_FILE} on S3..."
  if [[ -z "$S3_PREFIX" ]]
    # backup without prefix
    cat $SRC_FILE | aws $AWS_ARGS s3 cp - s3://$S3_BUCKET/$DEST_FILE
  else
    cat $SRC_FILE | aws $AWS_ARGS s3 cp - s3://$S3_BUCKET/$S3_PREFIX/$DEST_FILE
  fi
  if [ "$?" == "0" ]; then
    rm -f $SRC_FILE
  else
    echo "Error uploading ${DEST_FILE} on S3"
  fi
}

MYSQL_HOST_OPTS="-h $MYSQL_HOST -P $MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD"
DUMP_START_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
BACKUP_DIR="/backup"

echo "Backup is started at ${DUMP_START_TIME}"
echo "Creating dump for ${MYSQLDUMP_DATABASE} from ${MYSQL_HOST}..."
DUMP_FILE="$BACKUP_DIR/$DUMP_START_TIME.dump.sql.gz"
mysqldump $MYSQL_HOST_OPTS $MYSQLDUMP_OPTIONS $MYSQLDUMP_DATABASE | gzip > $DUMP_FILE

if [ "$?" == "0" ]; then
  S3_FILE="$DUMP_START_TIME.dump.sql.gz"
  copy_s3 $DUMP_FILE $S3_FILE
else
  echo "Error creating mysqldump"
fi

DUMP_END_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
echo "Backup is ends at ${DUMP_END_TIME}"