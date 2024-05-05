#! /usr/bin/env bash
# set -x
# set -e

# File path to store the variable value

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
s3_latest_mediawiki_dump_backup_record=$(list_s3 hourly | grep "mediawiki" | tail -1) 
echo "Latest mediawiki dump record: $s3_latest_mediawiki_dump_backup_record"
s3_latest_sql_dump_backup_record=$(list_s3 hourly | grep "sql" | tail -1) 
echo "Latest sql dump record: $s3_latest_sql_dump_backup_record"

t1=$(echo $s3_latest_mediawiki_dump_backup_record | awk '{print substr($0,1,19)}')
mediawiki_dump_time=$(date -d "$t1" +%s)
t2=$(echo $s3_latest_sql_dump_backup_record | awk '{print substr($0,1,19)}')
sql_dump_time=$(date -d "$t2" +%s)
current_date_time=$(date +%s)
seconds_since_mediawiki_dump=$((current_date_time-mediawiki_dump_time))
seconds_since_sql_dump=$((current_date_time-sql_dump_time))

# basic calculator bc is needed to retain floating point values in hours 
hours_since_mediawiki_dump=$(echo "scale=2; $seconds_since_mediawiki_dump/60/60" | bc)
hours_since_sql_dump=$(echo "scale=2; $seconds_since_sql_dump/60/60" | bc)
echo "Hours since mediawiki Dump: $hours_since_mediawiki_dump"
echo "Hours since sql Dump: $hours_since_sql_dump"

# check if the backup is within the required timeframe 
minimum_backup_time_requirement=1.5 
mediawiki_backup_delayed=$(echo "$hours_since_mediawiki_dump > $minimum_backup_time_requirement" |bc -l)
sql_backup_delayed=$(echo "$hours_since_sql_dump > $minimum_backup_time_requirement" |bc -l)

hours_since_mediawiki_dump=$(( seconds_since_mediawiki_dump / 3600 ))
remaining_seconds=$(( seconds_since_mediawiki_dump % 3600 ))
minutes_since_mediawiki_dump=$(( remaining_seconds / 60 ))

hours_since_sql_dump=$(( seconds_since_sql_dump / 3600 ))
remaining_seconds=$(( seconds_since_sql_dump % 3600 ))
minutes_since_sql_dump=$(( remaining_seconds / 60 ))

ALERT_DIR="/alert"
state_of_alert="$ALERT_DIR/state_of_alert.env"

# Read the value of the variable from the file
if [ -f "$state_of_alert" ]; then
    ONGOING_BACKUP_DELAY_ALERT_NOTIFIED=$(<"$state_of_alert")
else
    ONGOING_BACKUP_DELAY_ALERT_NOTIFIED="false"
fi

if [[ $((mediawiki_backup_delayed + sql_backup_delayed)) > 0 ]] ; then 
  result="Hourly Backup Failed"
  notification_color="14365807" # red 
  notify="true"
  ONGOING_BACKUP_DELAY_ALERT_NOTIFIED="true"
elif [ "$ONGOING_BACKUP_DELAY_ALERT_NOTIFIED" = "true" ]; then
  result="Hourly Backup Recovered"
  notification_color="5763719" # green
  notify="true"
  ONGOING_BACKUP_DELAY_ALERT_NOTIFIED="false"
else 
  ONGOING_BACKUP_DELAY_ALERT_NOTIFIED="false"
  notify="false"
fi 

# Write the updated value back to the file
echo "$ONGOING_BACKUP_DELAY_ALERT_NOTIFIED" > "$state_of_alert"

# if not, notify 
if [ "$notify" = "true" ] ; then 
    curl -X POST $DISCORD_NOTIFICATION_URL -H 'Content-Type: application/json' \
      -d '{"embeds":[{ 
      "color":"'"$notification_color"'",
      "title":"MediaWiki Backup",
      "type":"rich",
      "description":"'"$result"'",
      "fields":[
        {
          "name":"Time Since Last Mediawiki Image Backup",
          "value":"'"$hours_since_mediawiki_dump hours $minutes_since_mediawiki_dump minutes ago"'"
          },{
          "name":"Latest Mediawiki Image Backup Timestamp",
          "value":"'"$t1"'"
          },{
          "name":"Time Since Last DB SQL Bakup",
          "value":"'"$hours_since_sql_dump hours $minutes_since_sql_dump minutes ago"'"
          },{
          "name":"Latest DB SQL Backup Timestamp",
          "value":"'"$t2"'"
          },{
          "name":"frequency",
          "value":"hourly"
          },{
          "name":"S3 Bucket",
          "value":"'"$S3_PREFIX"'"
        }]}]}'
    echo "Notification sent: $result"
else 
    echo "No delay in hourly backup. Hence, no notification sent."
fi

# if there is a backup , no notification is sent. 