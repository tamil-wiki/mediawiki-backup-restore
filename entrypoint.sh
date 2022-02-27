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

# Backup at start up
if [[ "${INIT_BACKUP}" -gt "0" ]]; then
  echo "Create a backup on the startup"
  /backup.sh
fi

echo "${CRON_TIME} bash /backup.sh 2>&1 >> /dev/stdout" > /tmp/crontab.conf
crontab /tmp/crontab.conf
echo "Running cron task manager in foreground"
exec crond -f -L /dev/stdout