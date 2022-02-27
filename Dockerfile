FROM alpine:3.15.0
LABEL maintainer "Arulraj V <me@arulraj.net>"

RUN apk add --no-cache --update \
      tzdata \
      bash \
      mysql-client \
      gzip \
      openssl \
      curl && \
      # mariadb-connector-c && \
      rm -rf /var/cache/apk/*

RUN curl -L --insecure https://github.com/jwilder/dockerize/releases/download/v0.6.1/dockerize-alpine-linux-amd64-v0.6.1.tar.gz | tar -xz -C /usr/local/bin/
RUN chmod u+x /usr/local/bin/dockerize

ARG GIT_COMMIT_ID=unspecified
ENV GIT_COMMIT_ID=$GIT_COMMIT_ID

ENV CRON_TIME "0 */1 * * *"
ENV MYSQL_HOST "mysql"
ENV MYSQL_PASSWORD "secret"
ENV MYSQL_PORT 3306
ENV MYSQL_USER "root"
ENV MYSQLDUMP_DATABASE "--all-databases"
ENV MYSQLDUMP_OPTIONS ""
ENV RESTORE_DB_NAME ""
ENV RESTORE_FILENAME ""
ENV S3_ACCESS_KEY_ID ""
ENV S3_BUCKET ""
ENV S3_ENDPOINT ""
ENV S3_PREFIX "backup"
ENV S3_REGION "us-west-1"
ENV S3_S3V4 "no"
ENV S3_SECRET_ACCESS_KEY ""
ENV TIMEOUT "30s"

COPY ["entrypoint.sh", "backup.sh", "/"]

VOLUME ["/backup"]

CMD dockerize -wait tcp://${MYSQL_HOST}:${MYSQL_PORT} -timeout ${TIMEOUT} /entrypoint.sh