#! /usr/bin/env bash

# Validations

if [[ -z "${MYSQL_HOST}" ]];then
  echo "The MYSQL_HOST env can't be empty."
  exit 1
fi

if [[ -z "${MYSQL_PORT}" ]];then
  echo "The MYSQL_PORT env can't be empty."
  exit 1
fi

if [[ -z "${MYSQL_USER}" ]];then
  echo "The MYSQL_USER env can't be empty."
  exit 1
fi

if [[ -z "${MYSQL_PASSWORD}" ]];then
  echo "The MYSQL_PASSWORD env can't be empty."
  exit 1
fi

if [[ -z "${MYSQLDUMP_DATABASE}" ]];then
  echo "The MYSQLDUMP_DATABASE env can't be empty."
  exit 1
fi

if [[ -z "${S3_ACCESS_KEY_ID}" ]];then
  echo "The S3_ACCESS_KEY_ID env can't be empty."
  exit 1
fi

if [[ -z "${S3_SECRET_ACCESS_KEY}" ]];then
  echo "The S3_SECRET_ACCESS_KEY env can't be empty."
  exit 1
fi

if [[ -z "${S3_BUCKET}" ]];then
  echo "The S3_BUCKET env can't be empty."
  exit 1
fi

# env files needed for aws cli
export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY
if [[ ! -z "$S3_REGION" ]]; then
  export AWS_DEFAULT_REGION=$S3_REGION
fi

if [[ "$1" == "backup" ]]; then
  # Check connectivity
  dockerize -wait tcp://${MYSQL_HOST}:${MYSQL_PORT} -timeout ${TIMEOUT}
  # Backup at start up
  if [[ "${INIT_BACKUP}" -gt "0" ]]; then
    echo "Create a backup on the startup"
    /backup.sh
  fi

  echo "${CRON_TIME} bash /backup.sh 2>&1 >> /dev/stdout" > /tmp/crontab.conf
  crontab /tmp/crontab.conf
  echo "Running cron task manager in foreground"
  exec crond -f -L /dev/stdout
elif [[ "$1" == "restore" ]]; then
  # Check connectivity
  dockerize -wait tcp://${MYSQL_HOST}:${MYSQL_PORT} -timeout ${TIMEOUT}
  # Restore at start up
  # TODO: AV
fi

# assume user want to run his own process, for example a `bash` shell to explore this image
exec "$@"
