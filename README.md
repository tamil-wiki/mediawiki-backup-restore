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

CRON_TIME - Default is "0 */1 * * *". Runs every hour 0th min.


This will backup MySQL database and everything in `/mediawiki` mounted folder.

## Restore

To restore the from s3 backup

```
docker-compose run wiki-backup restore
```

Then you will entered into a shell. By default it will display the latest 10 backup files like below

```bash
docker-compose run wiki-backup restore
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

### To override anything on restore

```bash
docker-compose run -e "RESTORE_DATABASE=new_my_wiki" -v "/var/www/html:/mediawiki" wiki-backup restore
```

Refer

docker-compose run --help