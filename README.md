[![Docker Pulls](https://img.shields.io/docker/pulls/itzg/mc-backup.svg)](https://hub.docker.com/r/itzg/mc-backup)
[![Build Status](https://travis-ci.org/itzg/docker-mc-backup.svg?branch=master)](https://travis-ci.org/itzg/docker-mc-backup)

Provides a side-car container to backup itzg/minecraft-server world data.

## Environment variables

##### Common variables:

- `SRC_DIR`=/data
- `BACKUP_NAME`=world
- `INITIAL_DELAY`=2m
- `BACKUP_INTERVAL`=24h
- `PRUNE_BACKUPS_DAYS`=7
- `RCON_PORT`=25575
- `RCON_PASSWORD`=minecraft
- `EXCLUDES`=\*.jar,cache,logs
- `BACKUP_METHOD`=tar

If `PRUNE_BACKUP_DAYS` is set to a positive number, it'll delete old `.tgz` backup files from `DEST_DIR`. By default deletes backups older than a week.

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


:warning: | When using restic as your backup method, make sure that you fix your container hostname to a constant value! Otherwise, each time a container restarts it'll use a different, random hostname which will cause it not to rotate your backups created by previous instances!
---|---

:warning: | When using restic, at least one of `HOSTNAME` or `BACKUP_NAME` must be unique, when sharing a repository. Otherwise other instances using the same repository might prune your backups prematurely.
---|---

## Volumes

- `/data` :
  Should be attached read-only to the same volume as the `/data` of the `itzg/minecraft-server` container
- `/backups` :
  The volume where incremental tgz files will be created, if using tar backup method.

## Example

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
