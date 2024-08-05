#! /usr/bin/env bash

# Validations


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

if [[ -z "${S3_PREFIX_FOR_MONITORING}" ]];then
  echo "The S3_PREFIX_FOR_MONITORING env can't be empty."
  exit 1
fi

if [[ -z "${DISCORD_NOTIFICATION_URL}" ]];then
  echo "The DISCORD_NOTIFICATION_URL env can't be empty."
  exit 1
fi

# env files needed for aws cli
export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY

if [[ ! -z "$S3_REGION" ]]; then
  export AWS_DEFAULT_REGION=$S3_REGION
fi

source /cron_monitor.sh
echo "#! /usr/bin/env bash" > /root/.bashrc
echo "source /cron_monitor.sh" >> /root/.bashrc
echo "${CRON_MONITOR_TIME} bash /cron_monitor.sh 2>&1 >> /dev/stdout" >> /tmp/crontab.conf

crontab /tmp/crontab.conf
echo "Running cron task manager in foreground"
exec crond -f -L /dev/stdout
# assume user want to run his own process, for example a `bash` shell to explore this image
exec "$@"