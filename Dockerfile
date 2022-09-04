FROM alpine:3.15.0
LABEL maintainer "Arulraj V <me@arulraj.net>"

RUN apk add --no-cache --update \
      tzdata \
      bash \
      mysql-client \
      gzip \
      openssl \
      curl \
      python3 \
      py3-pip \
      gettext && \
      pip3 install --no-cache-dir \
      awscli && \
      # mariadb-connector-c && \
      rm -rf /var/cache/apk/*

RUN curl -L --insecure https://github.com/jwilder/dockerize/releases/download/v0.6.1/dockerize-alpine-linux-amd64-v0.6.1.tar.gz | tar -xz -C /usr/local/bin/
RUN chmod +x /usr/local/bin/dockerize

ARG GIT_COMMIT_ID=unspecified
ENV GIT_COMMIT_ID=$GIT_COMMIT_ID

# Every hour at 0th min
ENV CRON_TIME "0 */1 * * *"
ENV MYSQL_HOST "mysql"
ENV MYSQL_PASSWORD "secret"
ENV MYSQL_PORT "3306"
ENV MYSQL_USER "root"
ENV MYSQLDUMP_DATABASE "my_wiki"
ENV MYSQLDUMP_OPTIONS ""
ENV RESTORE_DATABASE ""
ENV S3_ACCESS_KEY_ID ""
ENV S3_BUCKET ""
ENV S3_ENDPOINT ""
ENV S3_LIFECYCLE_EXPIRATION_DAYS ""
ENV S3_PREFIX ""
ENV S3_REGION "us-west-1"
ENV S3_SECRET_ACCESS_KEY ""
ENV TIMEOUT "30s"

COPY ["entrypoint.sh", "backup.sh", "restore.sh", "lifecycle.json.template", "/"]

VOLUME ["/backup"]

ENTRYPOINT [ "/entrypoint.sh" ]

CMD [ "backup" ]
