Backup and Restore Mediawiki DB and Config
-------------------------------------------

This docker image will backup the mediawiki database (MySQL based) and config files (full mediawiki folder including extensions, images, skin and etc.,) into given s3 bucket.

## Development setup

* Docker 20.10.12 or latest
* Docker compose 1.29.2 or latest
* Direnv 2.28.0 or latest

## Backup

To start the backup container

```bash
docker-compose up -d wiki-backup
```

The **required environmental** variables are

MYSQL_HOST - Host or IP address of MySQL instance

MYSQL_USER

MYSQL_PORT

MYSQLDUMP_DATABASE - Database to backup

S3_ACCESS_KEY_ID

S3_SECRET_ACCESS_KEY

S3_BUCKET - Bucket name


**Optionals** are

MYSQL_PORT - Default 3306.

S3_ENDPOINT - Use this respective endpoint if its [minio](https://min.io/) or [digitalocean spaces](https://www.digitalocean.com/products/spaces)

S3_PREFIX - Mention this different folder from the root

S3_REGION - Default is us-west-1

CRON_TIME_HOURLY = 0 */1 * * * (every 1 hour)
CRON_TIME_DAILY = 30 */24 * * * (every 24 hours , 30mins past mid night)
CRON_TIME_WEEKLY = 0 3 * * SUN (3am on SUNDAY)
CRON_TIME_MONTHLY = 0 4 1 * * (4am on 1st of every month)

S3_LIFECYCLE_EXPIRATION_DAYS_FOR_HOURLY_BACKUP=1 - retain for 24 hours - 24 copies
S3_LIFECYCLE_EXPIRATION_DAYS_FOR_DAILY_BACKUP=7 - retain for 7 days - 7 copies
S3_LIFECYCLE_EXPIRATION_DAYS_FOR_WEEKLY_BACKUP=31 - retain 4 copies (1 month)
S3_LIFECYCLE_EXPIRATION_DAYS_FOR_MONTHLY_BACKUP=365 - retain 12 copies (1 year)

INIT_BACKUP - To run backup at startup. Default is 0 disabled.

S3_LIFECYCLE_EXPIRATION_DAYS - To set the s3 lifecycle expiration days. Default is 0 disabled. More [info](https://docs.aws.amazon.com/cli/latest/reference/s3api/put-bucket-lifecycle.html)


This will backup MySQL database and everything in `/mediawiki` mounted folder.

## Restore

To restore the from s3 backup

```
docker-compose run wiki-backup restore
```

Then you will entered into a shell. By default it will display the latest 10 backup files like below

```bash
docker-compose run --rm wiki-backup restore
Creating mediawiki-backup-restore_wiki-backup_run ... done
2022/03/06 15:39:13 Waiting for: tcp://db:3306
2022/03/06 15:39:13 Connected to tcp://db:3306
2022-03-06 07:50:04  440 Bytes 2022-03-06T075000Z.dump.sql.gz
2022-03-06 07:45:04  441 Bytes 2022-03-06T074500Z.dump.sql.gz
2022-03-06 07:40:04  440 Bytes 2022-03-06T074000Z.dump.sql.gz
2022-03-06 07:37:23  440 Bytes 2022-03-06T073718Z.dump.sql.gz
bash-5.1#
```

The required env with above is

RESTORE_DATABASE

### Commands

The available commands are

```
list_s3_top_ten
list_s3
restore <fileName>
```

The fileName will be without extensions like 2022-03-06T075000Z or latest

For example

```bash
bash-5.1# restore 2022-03-06T075000Z
Restoring Started at 2022-03-06T155133Z
Restoring DB my_wiki ...
Restoring DB my_wiki success!
Restoring Ends at 2022-03-06T155144Z

```

If you want to restore any other backup from weekly/daily/hourly folders, you can prefix it.

```bash
list_s3 daily
restore daily/2022-09-27T154250Z.daily
```

### To validate the restore

Set your S3 credentials in .env file. Then

```
docker-compose up -d db
docker-compose run --rm -e "RESTORE_DATABASE=my_wiki" wiki-backup restore
```

Then exec into the restore container

### To override anything on restore

```bash
docker-compose run --rm -e "RESTORE_DATABASE=new_my_wiki" -v "/var/www/html:/mediawiki" wiki-backup restore
```

Refer

docker-compose run --help

## S3 Clean up

While retention policy on s3 is supposed to keep the folders tidy, these commands might help manually remove files when they are not necessary.

```
bash-5.1# aws $AWS_ARGS s3 rm s3://$S3_BUCKET/wiki/testing/hourly/ --dryrun --recursive --exclude "*" --include "*.gz"
```

The `--dryrun` flag does not delete files, instead shows what would be deleted. When you are confident about deleting the files listed, you can run the command without the `--dryrun` flag. 

Note : `$AWS_ARGS` is loaded within the backup container. If not run the following manually.

```
export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY
```
