#! /usr/bin/env bash

MYSQL_HOST_OPTS="-h $MYSQL_HOST -P $MYSQL_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD"
DUMP_START_TIME=$(date +"%Y-%m-%dT%H%M%SZ")

echo "Backup is started at ${DUMP_START_TIME}"














DUMP_END_TIME=$(date +"%Y-%m-%dT%H%M%SZ")
echo "Backup is ends at ${DUMP_END_TIME}"