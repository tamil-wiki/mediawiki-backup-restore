#! /usr/bin/env bash
# set -x
# set -e

RESTORE_DIR="/restore"
MEDIAWIKI_DIR="/mediawiki"

if [[ -z "$S3_ENDPOINT" ]]; then
  AWS_ARGS=""
else
  AWS_ARGS="--endpoint-url $S3_ENDPOINT"
fi

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
    aws $AWS_ARGS s3 ls s3://$S3_BUCKET/$(date +"%Y-%m-%d") --human-readable | sort -r | head -n 10
  else
    aws $AWS_ARGS s3 ls s3://$S3_BUCKET/$S3_PREFIX/$(date +"%Y-%m-%d") --human-readable | sort -r | head -n 10
  fi
}

list_s3() {
  if [[ -z "$S3_PREFIX" ]]; then
    aws $AWS_ARGS s3 ls s3://$S3_BUCKET/ --human-readable
  else
    aws $AWS_ARGS s3 ls s3://$S3_BUCKET/$S3_PREFIX/ --human-readable
  fi
}

restore_db() {
  mkdir -p $RESTORE_DIR
  echo "Restoring DB $RESTORE_DATABASE ..."
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

  if [[ -f $RESTORE_DIR/$1 ]]; then
    echo "${MYSQL_RESTORE_OPTIONS}$(gzip -dc $RESTORE_DIR/$1)" > $RESTORE_DIR/dump.sql
    collationName=$(mysql -s -N $MYSQL_HOST_OPTS $RESTORE_DATABASE -e "SELECT collation_name FROM information_schema.COLLATIONS WHERE collation_name='utf8mb4_0900_ai_ci';")
    if [[ -z $collationName ]]; then
      sed -i 's/utf8mb4_0900_ai_ci/utf8_general_ci/g' $RESTORE_DIR/dump.sql
      sed -i 's/CHARSET=utf8mb4/CHARSET=utf8/g' $RESTORE_DIR/dump.sql
    fi

    mysql $MYSQL_HOST_OPTS $RESTORE_DATABASE < $RESTORE_DIR/dump.sql
    if [ "$?" == "0" ]; then
      success="0"
    fi
    rm -rf $RESTORE_DIR/$1 $RESTORE_DIR/dump.sql
  else
    echo "File $1 not exits."
  fi

  if [ "$success" == "0" ]; then
    echo "Restoring DB $RESTORE_DATABASE success!"
  else
    echo "Restoring DB $RESTORE_DATABASE failed"
  fi

}

restore_mediawiki() {
  mkdir -p $RESTORE_DIR
  echo "Restoring Mediawiki ..."
  RESTORE_FILE=$RESTORE_DIR/$1
  if [[ -z "$S3_PREFIX" ]]; then
    aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$1 $RESTORE_FILE
  else
    aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$S3_PREFIX/$1 $RESTORE_FILE
  fi

  tar -xzvf $RESTORE_FILE -C $(dirname $MEDIAWIKI_DIR)

  if [ "$?" == "0" ]; then
    echo "Restoring Mediawiki $1 success!"
    rm -rf $RESTORE_FILE
  else
    echo "Restoring Mediawiki $1 failed"
  fi
}

restore_latest() {
  restore "latest"
}

restore() {
  # The fileName will be without extensions like 2022-03-06T075000Z or latest
  fileName=$1
  RESTORE_START_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
  echo "Restoring Started at $RESTORE_START_TIME"

  # Restoring DB
  SQL_DUMP_FILE="$fileName.dump.sql.gz"
  if [[ "$(_s3_key_exists $SQL_DUMP_FILE)" != "0" ]]; then
    echo "The given dump ${SQL_DUMP_FILE} file is does not exists."
    return 1
  fi
  restore_db $SQL_DUMP_FILE

  # Restoring mediawiki
  if [ -d $MEDIAWIKI_DIR ]; then
    WIKI_DUMP_FILE="$fileName.mediawiki.tar.gz"
    if [[ "$(_s3_key_exists $WIKI_DUMP_FILE)" != "0" ]]; then
      echo "The given mediawiki ${WIKI_DUMP_FILE} file is does not exists."
      return 1
    fi
    restore_mediawiki $WIKI_DUMP_FILE
  fi

  RESTORE_END_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
  echo "Restoring Ends at $RESTORE_END_TIME"
}

