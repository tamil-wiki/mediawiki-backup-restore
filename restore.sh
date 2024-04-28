#! /usr/bin/env bash
# set -x
# set -e
set -o pipefail

RESTORE_DIR="/restore"
MEDIAWIKI_DIR="/mediawiki"
DONT_CHANGE_DUMP_FILE=${DONT_CHANGE_DUMP_FILE:-true}

if [[ -z "$S3_ENDPOINT" ]]; then
  AWS_ARGS=""
else
  AWS_ARGS="--endpoint-url $S3_ENDPOINT"
fi

logger() {
  echo $(date +"%Y-%m-%dT%H%M%SZ") "$@"
}

# Validate the given file exists in S3
_s3_key_exists() {
  if [[ -z "$S3_PREFIX" ]]; then
    aws $AWS_ARGS s3api head-object --bucket $S3_BUCKET --key $1 > /dev/null || not_exists=true
  else
    aws $AWS_ARGS s3api head-object --bucket $S3_BUCKET --key $S3_PREFIX/$1 > /dev/null || not_exists=true
  fi
  if [ $not_exists ]; then
    echo 1
  else
    echo 0
  fi
}

list_s3_top_ten() {
  if [[ -z "$S3_PREFIX" ]]; then
    S3_PATH= "s3://$S3_BUCKET"
  else
    S3_PATH="s3://$S3_BUCKET/$S3_PREFIX"
  fi

  if [[ ! -z "$1" ]]; then
    S3_PATH="$S3_PATH/$1"
  fi

  logger "Listing top 10 files from $S3_PATH"
  aws $AWS_ARGS s3 ls $S3_PATH/$(date +"%Y-%m-%d") --human-readable | sort -r | head -n 10
}

list_s3() {
  if [[ -z "$S3_PREFIX" ]]; then
    S3_PATH= "s3://$S3_BUCKET"
  else
    S3_PATH="s3://$S3_BUCKET/$S3_PREFIX"
  fi

  if [[ ! -z "$1" ]]; then
    S3_PATH="$S3_PATH/$1"
  fi

  logger "Listing all files from $S3_PATH"
  aws $AWS_ARGS s3 ls $S3_PATH/ --human-readable
}

restore_db() {
  mkdir -p $RESTORE_DIR
  logger "Restoring DB $RESTORE_DATABASE ..."
  success="1"
  MYSQL_HOST_OPTS="-h $MYSQL_HOST -P $MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD"
  # Drop all tables if exists

  echo \
    "SET FOREIGN_KEY_CHECKS = 0;" \
    $(mysqldump --add-drop-table --no-data $MYSQL_HOST_OPTS $RESTORE_DATABASE | grep 'DROP TABLE') \
    "SET FOREIGN_KEY_CHECKS = 1;" \
  | mysql $MYSQL_HOST_OPTS $RESTORE_DATABASE

  if [[ -z "$S3_PREFIX" ]]; then
    aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$1 $RESTORE_DIR
  else
    aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$S3_PREFIX/$1 $RESTORE_DIR
  fi
  RESTORE_FILE=$(basename $1)
  if [[ -f $RESTORE_DIR/$RESTORE_FILE ]]; then
    logger "Extracting..."
    gzip -dvkc $RESTORE_DIR/$RESTORE_FILE > $RESTORE_DIR/dump.sql
    logger "The size of the restore file is $(du -hs $RESTORE_DIR/dump.sql | awk '{print $1}')."

    if [[ "$DONT_CHANGE_DUMP_FILE" == "false" ]]; then
      if [[ ! -z "$MYSQL_RESTORE_OPTIONS" ]]; then
        logger "Adding restore options..."
        sed -i "1i${MYSQL_RESTORE_OPTIONS}" $RESTORE_DIR/dump.sql
      fi

      defaultCollationName=$(mysql -s -N $MYSQL_HOST_OPTS $RESTORE_DATABASE -e "SELECT @@collation_database;")
      defaultCharset=$(mysql -s -N $MYSQL_HOST_OPTS $RESTORE_DATABASE -e "SELECT @@character_set_database;")

      # Replace default collation if utf8mb4_0900_ai_ci is not supported.
      collation0900aiciName=$(mysql -s -N $MYSQL_HOST_OPTS $RESTORE_DATABASE -e "SELECT collation_name FROM information_schema.COLLATIONS WHERE collation_name='utf8mb4_0900_ai_ci';")
      if [[ -z $collation0900aiciName ]]; then
        logger "Replacing default collation..."
        sed -i "s/utf8mb4_0900_ai_ci/$defaultCollationName/g" $RESTORE_DIR/dump.sql
      fi

      # Replace default charset if utf8mb4 is not supported.
      charsetutf8mb4Name=$(mysql -s -N $MYSQL_HOST_OPTS $RESTORE_DATABASE -e "SELECT character_set_name FROM information_schema.CHARACTER_SETS WHERE character_set_name='utf8mb4';")
      if [[ -z $charsetutf8mb4Name ]]; then
        logger "Replacing default charset..."
        sed -i "s/CHARSET=utf8mb4/CHARSET=$defaultCharset/g" $RESTORE_DIR/dump.sql
      fi
    fi

    logger "Restoring..."
    mysql $MYSQL_HOST_OPTS $RESTORE_DATABASE < $RESTORE_DIR/dump.sql
    if [ "$?" == "0" ]; then
      success="0"
    fi
    rm -rf $RESTORE_DIR/$RESTORE_FILE $RESTORE_DIR/dump.sql
  else
    logger "File $1 not exits."
  fi

  if [ "$success" == "0" ]; then
    logger "Restoring DB $RESTORE_DATABASE success!"
  else
    logger "Restoring DB $RESTORE_DATABASE failed"
  fi

}

restore_mediawiki() {
  mkdir -p $RESTORE_DIR
  logger "Restoring Mediawiki ..."
  RESTORE_FILE=$RESTORE_DIR/$1
  if [[ -z "$S3_PREFIX" ]]; then
    aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$1 $RESTORE_FILE
  else
    aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$S3_PREFIX/$1 $RESTORE_FILE
  fi

  logger "Extracting..."
  pv $RESTORE_FILE | tar -xzf - -C $(dirname $MEDIAWIKI_DIR)

  if [ "$?" == "0" ]; then
    logger "Restoring Mediawiki $1 success!"
  else
    logger "Restoring Mediawiki $1 failed"
  fi
  rm -rf $RESTORE_FILE
}

restore_latest() {
  restore "latest.hourly"
}

restore() {
  # The fileName will be without extensions like 2022-03-06T075000Z or latest
  fileName=$1
  RESTORE_START_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
  logger "Restoring Started at $RESTORE_START_TIME"

  # Restoring DB
  SQL_DUMP_FILE="$fileName.dump.sql.gz"
  if [[ "$(_s3_key_exists $SQL_DUMP_FILE)" != "0" ]]; then
    logger "The given dump ${SQL_DUMP_FILE} file is does not exists."
    return 1
  fi
  restore_db $SQL_DUMP_FILE

  # Restoring mediawiki
  if [ -d $MEDIAWIKI_DIR ]; then
    WIKI_DUMP_FILE="$fileName.mediawiki.tar.gz"
    if [[ "$(_s3_key_exists $WIKI_DUMP_FILE)" != "0" ]]; then
      logger "The given mediawiki ${WIKI_DUMP_FILE} file is does not exists."
      return 1
    fi
    restore_mediawiki $WIKI_DUMP_FILE
  fi

  RESTORE_END_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
  logger "Restoring Ends at $RESTORE_END_TIME"
}
