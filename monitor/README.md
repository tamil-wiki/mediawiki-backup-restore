= Tamil Wiki Backup Monitoring

Tamil wiki database and images are backed up every hour through a cron job. Daily, weekly, monthly backups are also maintained. There has been instances where the backup failed to run. This monitor is to check s3 for the latest backups uploaded and alert if the houly backup is delayed for more than 1.5 hours.

== Build

```
docker build -t tamilwiki/monitor:v0.0.1 .
```

This will build the docker image, with tag `v0.0.1`. This version should be used within the `.env` file, as the value for `MONITOR_DOCKER_IMAGE_VERSION`. 

== Run

1. Update the `.env.example` with the right values
2. Rename `.env.example` to `.env` within the `monitor` folder
3. Do not mutate the `.env` file in any other folder, especially if you have `compose-deployment`
4. Start the container from `monitor` folder 

```
docker-compose up -d
```

