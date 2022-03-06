#! /usr/bin/env bash
# set -e

RESTORE_DIR="/restore"

if [[ -z "$S3_ENDPOINT" ]]; then
  AWS_ARGS=""
else
  AWS_ARGS="--endpoint-url $S3_ENDPOINT"
fi

list_s3_top_ten() {
  echo "Top ten"
}

list_s3() {
  if [[ -z "$S3_PREFIX" ]]; then
    aws $AWS_ARGS s3 ls s3://$S3_BUCKET/
  else
    aws $AWS_ARGS s3 ls s3://$S3_BUCKET/$S3_PREFIX/
  fi
}

restore_db() {
  echo "Restoring DB"
}

restore_mediawiki() {
  echo "Restoring Mediawiki"
}

restore_all() {
  RESTORE_START_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
  echo "Restoring Started at $RESTORE_START_TIME"
  RESTORE_END_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
  echo "Restoring Ends at $RESTORE_END_TIME"
}

