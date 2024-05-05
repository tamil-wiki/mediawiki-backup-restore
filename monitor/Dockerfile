FROM alpine:3.19.1
LABEL maintainer "vijayabharathib <yajiv.vijay@gmail.com>"

RUN apk add --no-cache --update \
      tzdata \
      bash \      
      openssl \
      curl \
      python3 \
      py3-pip \
      gettext \
      aws-cli && \
      rm -rf /var/cache/apk/*

RUN mkdir /alert
ENV S3_ACCESS_KEY_ID ""
ENV S3_BUCKET ""
ENV S3_ENDPOINT ""
ENV S3_PREFIX ""
ENV S3_REGION "us-west-1"
ENV S3_SECRET_ACCESS_KEY ""
ENV TIMEOUT "30s"
ENV DISCORD_NOTIFICATION_URL ""
ENV CRON_MONITOR_TIME "*/45 * * * *"
COPY ["entrypoint.sh", "cron_monitor.sh", "/"]

RUN chmod +x /entrypoint.sh
RUN chmod +x /cron_monitor.sh

ENTRYPOINT [ "/entrypoint.sh" ]

CMD ["post_test_notification"]