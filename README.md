[![Docker Pulls](https://img.shields.io/docker/pulls/itzg/mc-backup.svg)](https://hub.docker.com/r/itzg/mc-backup)
[![Build Status](https://travis-ci.org/itzg/docker-mc-backup.svg?branch=master)](https://travis-ci.org/itzg/docker-mc-backup)
[![Discord](https://img.shields.io/discord/660567679458869252?label=Discord&logo=discord)](https://discord.gg/DXfKpjB)

Provides a side-car container to backup itzg/minecraft-server world data.

## Environment variables

##### Common variables:

- `SRC_DIR`=/data
- `BACKUP_NAME`=world
- `INITIAL_DELAY`=2m
- `BACKUP_INTERVAL`=24h
- `PRUNE_BACKUPS_DAYS`=7
- `PRUNE_RESTIC_RETENTION`=--keep-within 7d
- `RCON_HOST`=localhost
- `RCON_PORT`=25575
- `RCON_PASSWORD`=minecraft
- `EXCLUDES`=\*.jar,cache,logs
- `BACKUP_METHOD`=tar
- `RESTIC_ADDITIONAL_TAGS`=mc_backups

If `PRUNE_BACKUPS_DAYS` is set to a positive number, it'll delete old `.tgz` backup files from `DEST_DIR`. By default deletes backups older than a week.

If `BACKUP_INTERVAL` is set to 0 or smaller, script will run once and exit.

Both `INITIAL_DELAY` and `BACKUP_INTERVAL` accept times in `sleep` format: `NUMBER[SUFFIX] NUMBER[SUFFIX] ...`.
SUFFIX may be 's' for seconds (the default), 'm' for minutes, 'h' for hours or 'd' for days.

Examples:
- `BACKUP_INTERVAL`="1.5d" -> backup every one and a half days (36 hours)
- `BACKUP_INTERVAL`="2h 30m" -> backup every two and a half hours
- `INITIAL_DELAY`="120" -> wait 2 minutes before starting

`EXCLUDES` is a comma-separated list of glob(3) patterns to exclude from backups. By default excludes all jar files (plugins, server files), logs folder and cache (used by i.e. PaperMC server).

##### `tar` backup method

- `DEST_DIR`=/backups
- `LINK_LATEST`=false

`LINK_LATEST` is a true/false flag that creates a symbolic link to the latest backup.

##### `restic` backup method

See [restic documentation](https://restic.readthedocs.io/en/latest/030_preparing_a_new_repo.html) on what variables are needed to be defined.
At least one of `RESTIC_PASSWORD*` variables need to be defined, along with `RESTIC_REPOSITORY`.

Use the `RESTIC_ADDITIONAL_TAGS` variable to define a space separated list of additional restic tags. The backup will always be tagged with the value of `BACKUP_NAME`. e.g.: `RESTIC_ADDITIONAL_TAGS=mc_backups foo bar` will tag your backup with `foo`, `bar`, `mc_backups` and the value of `BACKUP_NAME`.

You can finetune the retention cycle of the restic backups using the `PRUNE_RESTIC_RETENTION` variable. Take a look at the [restic documentation](https://restic.readthedocs.io/en/latest/060_forget.html) for details.

> **_EXAMPLE_**  
> Setting `PRUNE_RESTIC_RETENTION` to `--keep-daily 7 --keep-weekly 5 --keep-monthly 12 --keep-yearly 75` will keep the most recent 7 daily snapshots, then 4 (remember, 7 dailies already include a week!) last-day-of-the-weeks and 11 or 12 last-day-of-the-months (11 or 12 depends if the 5 weeklies cross a month). And finally 75 last-day-of-the-year snapshots. All other snapshots are removed.

:warning: | When using restic as your backup method, make sure that you fix your container hostname to a constant value! Otherwise, each time a container restarts it'll use a different, random hostname which will cause it not to rotate your backups created by previous instances!
---|---

:warning: | When using restic, at least one of `HOSTNAME` or `BACKUP_NAME` must be unique, when sharing a repository. Otherwise other instances using the same repository might prune your backups prematurely.
---|---

:warning: | SFTP restic backend is not directly supported. Please use RCLONE backend with SFTP support.
---|---

## Volumes

- `/data` :
  Should be attached read-only to the same volume as the `/data` of the `itzg/minecraft-server` container
- `/backups` :
  The volume where incremental tgz files will be created, if using tar backup method.

## Example

### Kubernetes

An example StatefulSet deployment is provided [in this repository](test-deploy.yaml).

The important part is the containers definition of the deployment:

```yaml
containers:
  - name: mc
    image: itzg/minecraft-server
    env:
      - name: EULA
        value: "TRUE"
    volumeMounts:
      - mountPath: /data
        name: data
  - name: backup
    image: mc-backup
    imagePullPolicy: Never
    securityContext:
      runAsUser: 1000
    env:
      - name: BACKUP_INTERVAL
        value: "2h 30m"
    volumeMounts:
      - mountPath: /data
        name: data
        readOnly: true
      - mountPath: /backups
        name: backups
```

### Docker Compose

```yaml
version: '3.7'

services:
  mc:
    image: itzg/minecraft-server
    ports:
    - 25565:25565
    environment:
      EULA: "TRUE"
    volumes:
    - mc:/data
  backups:
    image: itzg/mc-backup
    environment:
      BACKUP_INTERVAL: "2h"
      # instead of network_mode below, could declare RCON_HOST
      # RCON_HOST: mc
    volumes:
    # mount the same volume used by server, but read-only
    - mc:/data:ro
    # use a host attached directory so that it in turn can be backed up
    # to external/cloud storage
    - ./mc-backups:/backups
    # share network namespace with server to simplify rcon access
    network_mode: "service:mc"

volumes:
  mc: {}
```
