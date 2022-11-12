#! /usr/bin/env bash
# set -x
# set -e

export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY

if [[ -z "$S3_ENDPOINT" ]]; then
  AWS_ARGS=""
else
  AWS_ARGS="--endpoint-url $S3_ENDPOINT"
fi

list_s3() {
  if [[ -z "$S3_PREFIX" ]]; then
    S3_PATH= "s3://$S3_BUCKET"
  else
    S3_PATH="s3://$S3_BUCKET/$S3_PREFIX"
  fi

  if [[ ! -z "$1" ]]; then
    S3_PATH="$S3_PATH/$1"
  fi

  echo "Listing all files from $S3_PATH"
  aws $AWS_ARGS s3 ls $S3_PATH/ --human-readable
}
s3_latest_mediawiki_dump_backup_record=$(list_s3 hourly | tail -1) 
echo "Latest mediawiki dump record: $s3_latest_mediawiki_dump_backup_record"
s3_latest_sql_dump_backup_record=$(list_s3 hourly | tail -2 | head -1) 
echo "Latest sql dump record: $s3_latest_sql_dump_backup_record"

t1=$(echo $s3_latest_mediawiki_dump_backup_record | awk '{print substr($0,1,19)}')
mediawiki_dump_time=$(date -d "$t1" +%s)
t2=$(echo $s3_latest_sql_dump_backup_record | awk '{print substr($0,1,19)}')
sql_dump_time=$(date -d "$t2" +%s)
current_date_time=$(date +%s)
seconds_since_mediawiki_dump=$((current_date_time-mediawiki_dump_time))
seconds_since_sql_dump=$((current_date_time-sql_dump_time))

# basic calculator bc is needed to retain floating point values in hours 
hours_since_mediawiki_dump=$(bc <<< "scale=2; $seconds_since_mediawiki_dump/60/60")
hours_since_sql_dump=$(bc <<< "scale=2; $seconds_since_sql_dump/60/60")
echo "Hours since mediawiki Dump: $hours_since_mediawiki_dump"
echo "Hours since sql Dump: $hours_since_sql_dump"

# check if the backup is within the required timeframe 
minimum_backup_time_requirement=1.5 
mediawiki_backup_delayed=$(echo "$hours_since_mediawiki_dump > $minimum_backup_time_requirement" |bc -l)
sql_backup_delayed=$(echo "$hours_since_sql_dump > $minimum_backup_time_requirement" |bc -l)

# if not, notify 
if [[ $((mediawiki_backup_delayed + sql_backup_delayed)) > 0 ]] ; then 
    curl -X POST $DISCORD_NOTIFICATION_URL -H 'Content-Type: application/json' -d '{"embeds":[{"color":"14365807","title":"MediaWiki Backup","type":"rich","description":"Backup Cron Testing","fields":[{"name":"Mediawiki Backup Time","value":"'"$hours_since_mediawiki_dump hours ago"'"},{"name":"DB Bakup Time","value":"'"$hours_since_sql_dump hours ago"'"},{"name":"frequency","value":"hourly"},{"name":"S3 Bucket","value":"'"$S3_PREFIX"'"}]}]}'
    echo "Notified the delay in backup cron"
else 
    echo "No delay in hourly backup. Hence, no notification sent."
fi

# if there is a backup , no notification is sent. 