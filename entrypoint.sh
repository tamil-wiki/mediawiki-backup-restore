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

# env files needed for aws cli
export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY
if [[ ! -z "$S3_REGION" ]]; then
  export AWS_DEFAULT_REGION=$S3_REGION
fi

if [[ "$1" == "backup" ]]; then

  if [[ -z "${MYSQLDUMP_DATABASE}" ]];then
    echo "The MYSQLDUMP_DATABASE env can't be empty."
    exit 1
  fi

  # Check connectivity
  dockerize -wait tcp://${MYSQL_HOST}:${MYSQL_PORT} -timeout ${TIMEOUT}
  # Backup at start up
  if [[ "${INIT_BACKUP}" -gt "0" ]]; then
    echo "Create a backup on the startup"
    /backup.sh daily
  fi

  if [[ -z "$S3_ENDPOINT" ]]; then
    AWS_ARGS=""
  else
    AWS_ARGS="--endpoint-url $S3_ENDPOINT"
  fi

  # Setup bucket expiration policy
  if [[ "${S3_LIFECYCLE_EXPIRATION_DAYS_FOR_HOURLY_BACKUP}" -gt "0" ]]; then
    envsubst < /lifecycle.json.template > /lifecycle.json
    aws $AWS_ARGS s3api put-bucket-lifecycle --bucket $S3_BUCKET --lifecycle-configuration file://lifecycle.json
    aws $AWS_ARGS s3api get-bucket-lifecycle --bucket $S3_BUCKET
  fi

  # CRON_TIME_HOURLY = 0 */1 * * * (every 1 hour)
  # CRON_TIME_DAILY = 0 */24 * * * (every 24 hours)
  # CRON_TIME_WEEKLY = 0 3 * * SUN (3am on SUNDAY)
  # CRON_TIME_MONTHLY = 0 4 1 * * (4am on 1st of every month)

  
  echo "${CRON_TIME_HOURLY} bash /backup.sh hourly 2>&1 >> /dev/stdout" > /tmp/crontab.conf
  echo "${CRON_TIME_DAILY} bash /backup.sh daily 2>&1 >> /dev/stdout" >> /tmp/crontab.conf
  echo "${CRON_TIME_WEEKLY} bash /backup.sh weekly 2>&1 >> /dev/stdout" >> /tmp/crontab.conf
  echo "${CRON_TIME_MONTHLY} bash /backup.sh monthly 2>&1 >> /dev/stdout" >> /tmp/crontab.conf
  
  crontab /tmp/crontab.conf
  echo "Running cron task manager in foreground"
  exec crond -f -L /dev/stdout
elif [[ "$1" == "restore" ]]; then

  if [[ -z "${RESTORE_DATABASE}" ]];then
    echo "The RESTORE_DATABASE env can't be empty."
    exit 1
  fi

  # Check connectivity
  dockerize -wait tcp://${MYSQL_HOST}:${MYSQL_PORT} -timeout ${TIMEOUT}
  # Restore at start up
  source /restore.sh
  list_s3_top_ten

  if [[ "${INIT_RESTORE}" -gt "0" ]]; then
    restore_latest
    exit 0
  fi
  # By default restoring is a manual activity
  echo "#! /usr/bin/env bash" > /root/.bashrc
  echo "source /restore.sh" >> /root/.bashrc
  exec bash
fi

# assume user want to run his own process, for example a `bash` shell to explore this image
exec "$@"
