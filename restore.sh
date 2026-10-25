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

# Validate the given file exists in S3. Prints 0 when it exists, 1 otherwise.
_s3_key_exists() {
  local not_exists=""
  if [[ -z "$S3_PREFIX" ]]; then
    aws $AWS_ARGS s3api head-object --bucket $S3_BUCKET --key $1 > /dev/null 2>&1 || not_exists=true
  else
    aws $AWS_ARGS s3api head-object --bucket $S3_BUCKET --key $S3_PREFIX/$1 > /dev/null 2>&1 || not_exists=true
  fi
  if [ $not_exists ]; then
    echo 1
  else
    echo 0
  fi
}

list_s3_top_ten() {
  if [[ -z "$S3_PREFIX" ]]; then
    S3_PATH="s3://$S3_BUCKET"
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
    S3_PATH="s3://$S3_BUCKET"
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

# Restore the latest hourly DB dump and mediawiki archive.
restore_latest() {
  restore "latest.hourly"
}

# Restore a DB dump and a mediawiki archive from S3.
#
# Usage:
#   restore <name>
#     <name> has no extension, e.g. 2022-03-06T075000Z, latest.hourly or
#     daily/2022-09-27T154250Z.daily. It expands to <name>.dump.sql.gz and
#     <name>.mediawiki.tar.gz. The DB dump must exist. If the mediawiki
#     archive is missing (e.g. IMAGE_BACKUP_REQUIRED=false at backup time),
#     a warning is logged and only the DB is restored.
#
#   restore <db file> <mediawiki file>
#     Full file names, used when the DB and images were backed up separately,
#     e.g. restore hourly/2024-01-01T100000Z.hourly.dump.sql.gz \
#                  daily/2024-01-01T003000Z.daily.mediawiki.tar.gz
#     Both files must exist, otherwise nothing is restored.
restore() {
  local SQL_DUMP_FILE WIKI_DUMP_FILE
  local wiki_required="false"

  if [[ $# -eq 1 && -n "$1" ]]; then
    SQL_DUMP_FILE="$1.dump.sql.gz"
    WIKI_DUMP_FILE="$1.mediawiki.tar.gz"
  elif [[ $# -eq 2 && -n "$1" && -n "$2" ]]; then
    SQL_DUMP_FILE="$1"
    WIKI_DUMP_FILE="$2"
    wiki_required="true"
  else
    logger "Usage: restore <name> | restore <db file> <mediawiki file>"
    return 1
  fi

  # Validate every file before restoring anything, so a missing file never
  # leaves a half restored wiki (new DB with old images or the reverse).
  if [[ "$(_s3_key_exists $SQL_DUMP_FILE)" != "0" ]]; then
    logger "The given dump ${SQL_DUMP_FILE} file does not exist."
    return 1
  fi

  if [ ! -d $MEDIAWIKI_DIR ]; then
    logger "Warning: $MEDIAWIKI_DIR is not mounted, skipping mediawiki restore."
    WIKI_DUMP_FILE=""
  elif [[ "$(_s3_key_exists $WIKI_DUMP_FILE)" != "0" ]]; then
    if [[ "$wiki_required" == "true" ]]; then
      logger "The given mediawiki ${WIKI_DUMP_FILE} file does not exist."
      return 1
    fi
    logger "Warning: mediawiki ${WIKI_DUMP_FILE} file does not exist, restoring the DB only."
    WIKI_DUMP_FILE=""
  fi

  RESTORE_START_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
  logger "Restoring Started at $RESTORE_START_TIME"

  restore_db $SQL_DUMP_FILE

  if [[ -n "$WIKI_DUMP_FILE" ]]; then
    restore_mediawiki $WIKI_DUMP_FILE
  fi

  RESTORE_END_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
  logger "Restoring Ends at $RESTORE_END_TIME"
}
