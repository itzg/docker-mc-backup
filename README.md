[![Docker Pulls](https://img.shields.io/docker/pulls/itzg/mc-backup.svg)](https://hub.docker.com/r/itzg/mc-backup)
[![Build](https://github.com/itzg/docker-mc-backup/actions/workflows/build.yml/badge.svg)](https://github.com/itzg/docker-mc-backup/actions/workflows/build.yml)
[![Discord](https://img.shields.io/discord/660567679458869252?label=Discord&logo=discord)](https://discord.gg/DXfKpjB)

Provides a side-car container to back up [itzg/minecraft-server](https://github.com/itzg/docker-minecraft-server) world data. Backups are coordinated automatically by using RCON to flush data, pause writes, and resume after backup is completed. 

**This does NOT support Bedrock edition. Use [a community provided solution](https://github.com/itzg/docker-minecraft-bedrock-server#community-solutions) for that.**

## Environment variables

##### Common variables:

- `SRC_DIR`=/data
- `BACKUP_NAME`=world
- `INITIAL_DELAY`=2m
- `BACKUP_INTERVAL`=24h
- `PAUSE_IF_NO_PLAYERS`=false
- `PLAYERS_ONLINE_CHECK_INTERVAL`=5m
- `PRUNE_BACKUPS_DAYS`=7
- `PRUNE_RESTIC_RETENTION`=--keep-within 7d
- `SERVER_PORT`=25565
- `RCON_HOST`=localhost
- `RCON_PORT`=25575
- `RCON_PASSWORD`=minecraft
- `RCON_PASSWORD_FILE`: Can be set to read the RCON password from a file. Overrides `RCON_PASSWORD` if both are set.
- `RCON_RETRIES`=5 : Set to a negative value to retry indefinitely
- `RCON_RETRY_INTERVAL`=10s
- `INCLUDES`=. : comma separated list of include patterns relative to directory specified by `SRC_DIR` where `.` specifies all of that directory should be included in the backup. 

  **For Restic** the default is the value of `SRC_DIR` to remain backward compatible with previous images.
- `EXCLUDES`=\*.jar,cache,logs,\*.tmp : commas separated list of file patterns to exclude from the backup. To disable exclusions, set to an empty string.
- `EXCLUDES_FILE`: Can be set to read the list of excludes (one per line) from a file. Can be used with `EXCLUDES` to add more excludes.
- `BACKUP_METHOD`=tar
- `RESTIC_ADDITIONAL_TAGS`=mc_backups : additional tags to apply to the backup. Set to an empty string to disable additional tags.
- `RESTIC_VERBOSE`=false : set to "true" to enable verbose output during restic backup operation
- `TZ` : Can be set to the timezone to use for logging
- `PRE_SAVE_ALL_SCRIPT`, `PRE_BACKUP_SCRIPT`, `PRE_SAVE_ON_SCRIPT`, `POST_BACKUP_SCRIPT`, `*_SCRIPT_FILE`: See [Backup scripts](#backup-scripts)

If `PRUNE_BACKUPS_DAYS` is set to a positive number, it'll delete old `.tgz` backup files from `DEST_DIR`. By default deletes backups older than a week.

If `BACKUP_INTERVAL` is set to 0 or smaller, script will run once and exit.

Both `INITIAL_DELAY` and `BACKUP_INTERVAL` accept times in `sleep` format: `NUMBER[SUFFIX] NUMBER[SUFFIX] ...`.
SUFFIX may be 's' for seconds (the default), 'm' for minutes, 'h' for hours or 'd' for days.

Examples:
- `BACKUP_INTERVAL`="1.5d" -> backup every one and a half days (36 hours)
- `BACKUP_INTERVAL`="2h 30m" -> backup every two and a half hours
- `INITIAL_DELAY`="120" -> wait 2 minutes before starting

The `PAUSE_IF_NO_PLAYERS` option lets you pause backups if no players are online.

If `PAUSE_IF_NO_PLAYERS`="true" and there are no players online after a backup is made, then instead of immediately scheduling the next backup, the script will start checking the server's player count every `PLAYERS_ONLINE_CHECK_INTERVAL` (defaults to 5 minutes). Once a player joins the server, the next backup will be scheduled in `BACKUP_INTERVAL`.

`EXCLUDES` is a comma-separated list of glob(3) patterns to exclude from backups. By default excludes all jar files (plugins, server files), logs folder and cache (used by i.e. PaperMC server).

##### `tar` backup method

- `DEST_DIR`=/backups
- `LINK_LATEST`=false
- `TAR_COMPRESS_METHOD`=gzip
- `ZSTD_PARAMETERS`=-3 --long=25 --single-thread

`LINK_LATEST` is a true/false flag that creates a symbolic link to the latest backup.

`TAR_COMPRESS_METHOD` is the compression method used by tar. Valid value: gzip bzip2 zstd

`ZSTD_PARAMETERS` sets the parameters for `zstd` compression. The `--long` parameter affects RAM requirements for both compression and decompression (the default of 25 means 2^25 bytes = 32 MB).

##### `rsync` backup method

- `DEST_DIR`=/backups
- `LINK_LATEST`=false

`LINK_LATEST` is a true/false flag that creates a symbolic link to the latest backup.

##### `restic` backup method

See [restic documentation](https://restic.readthedocs.io/en/latest/030_preparing_a_new_repo.html) on what variables are needed to be defined.
At least one of `RESTIC_PASSWORD*` variables need to be defined, along with `RESTIC_REPOSITORY`.

Use the `RESTIC_ADDITIONAL_TAGS` variable to define a space separated list of additional restic tags. The backup will always be tagged with the value of `BACKUP_NAME`. e.g.: `RESTIC_ADDITIONAL_TAGS=mc_backups foo bar` will tag your backup with `foo`, `bar`, `mc_backups` and the value of `BACKUP_NAME`.

By default, the hostname, typically the container/pod's name, will be used as the Restic backup's hostname. That can be overridden by setting `RESTIC_HOSTNAME` 

You can fine tune the retention cycle of the restic backups using the `PRUNE_RESTIC_RETENTION` variable. Take a look at the [restic documentation](https://restic.readthedocs.io/en/latest/060_forget.html) for details.

> **_EXAMPLE_**  
> Setting `PRUNE_RESTIC_RETENTION` to `--keep-daily 7 --keep-weekly 5 --keep-monthly 12 --keep-yearly 75` will keep the most recent 7 daily snapshots, then 4 (remember, 7 dailies already include a week!) last-day-of-the-weeks and 11 or 12 last-day-of-the-months (11 or 12 depends if the 5 weeklies cross a month). And finally 75 last-day-of-the-year snapshots. All other snapshots are removed.

| :warning: | When using restic as your backup method, make sure that you fix your container hostname to a constant value! Otherwise, each time a container restarts it'll use a different, random hostname which will cause it not to rotate your backups created by previous instances! |
|-----------|---|

| :warning: | When using restic, at least one of `HOSTNAME` or `BACKUP_NAME` must be unique, when sharing a repository. Otherwise other instances using the same repository might prune your backups prematurely. |
|-----------|---|

| :warning: | SFTP restic backend is not directly supported. Please use RCLONE backend with SFTP support. |
|-----------|---|

- Information about required S3 permissions [can be found here](https://restic.readthedocs.io/en/latest/080_examples.html)

##### `rclone` backup method
Rclone acts as the `tar` backup method but automatically moves the compressed files to a remote drive via [rclone](https://rclone.org/).

There are a few special environment variables for the rclone method.

- `RCLONE_REMOTE` is the name of the remote you've configured in your rclone.conf, see [remote setup](https://rclone.org/remote_setup/).
- `RCLONE_COMPRESS_METHOD`=gzip
- `DEST_DIR`=/backups is the container path where the archive is temporarily created
- `RCLONE_DEST_DIR` is the directory on the remote

Other parameters such as `PRUNE_BACKUPS_DAYS`, `ZSTD_PARAMETERS`, and `BACKUP_NAME` are all used as well.

**Note** that you will need to place your rclone config file in `/config/rclone/rclone.conf`.
This can be done by adding it through docker-compose,

```yaml
- ./rclone.config:/config/rclone/rclone.conf:ro
```
or by running the config wizard in a container and mounting the volume.
```shell
docker run -it --rm -v rclone-config:/config/rclone rclone/rclone config
```

then you must bind the volume **for the mc-backup process**
```yaml
volumes:
  - rclone-config:/config/rclone
```
**and the service**
```yaml
volumes:
  rclone-config:
    external: true
```

## Volumes

- `/data` :
  Should be attached read-only to the same volume as the `/data` of the `itzg/minecraft-server` container
- `/backups` :
  The volume where incremental tgz files will be created, if using tar backup method.

## Restoring tar backups

This image includes a script called `restore-backup` which will:
1. Check if the `$SRC_DIR` (default is `/data`) is empty
2. and if any files are available in `$DEST_DIR` (default is `/backups`), 
3. then un-tars the newest one into `$SRC_DIR`

The [compose file example](#docker-compose) shows creating an "init container" to run the restore

## Restoring rsync backups

This image includes a script called `restore-rsync-backup` which will:
1. Check if the `$SRC_DIR` (default is `/data`) is empty
2. and if any folders are available in `$DEST_DIR` (default is `/backups`), 
3. then rsyncs back the newest one into `$SRC_DIR`

The [compose file example](#docker-compose) shows creating an "init container" to run the restore

## On-demand backups

If you would like to kick off a backup prior to the next backup interval, you can `exec` the command `backup now` within the running backup container. For example, using the [Docker Compose example](examples/docker-compose.yml) where the service name is `backups`, the exec command becomes:

```shell
docker-compose exec backups backup now
```

This mechanism can also be used to avoid a long running container completely by running a temporary container, such as:

```shell
docker run --rm ...data and backup -v args... itzg/mc-backup backup now
```

## Backup scripts

The `PRE_SAVE_ALL_SCRIPT`, `PRE_BACKUP_SCRIPT`, `PRE_SAVE_ON_SCRIPT`, and `POST_BACKUP_SCRIPT`, variables may be set to a bash script to run before and after the backup process.
Potential use-cases include sending notifications, or replicating a restic repository to a remote store.

The backup waits for the server to respond to a rcon "save-on" command before running the scripts. After, the `PRE_SAVE_ALL_SCRIPT` is run, followed by rcon "save-off" and "save-all" commands. The, the `PRE_BACKUP_SCRIPT` is run, followed by the backup process. Then, the `PRE_SAVE_ON_SCRIPT` is run, followed by a rcon "save-on" command. Finally, the `POST_BACKUP_SCRIPT` is run.

Alternatively `PRE_SAVE_ALL_SCRIPT_FILE` `PRE_BACKUP_SCRIPT_FILE`, `PRE_SAVE_ON_SCRIPT_FILE`, and `POST_BACKUP_SCRIPT_FILE` may be set to the path of a script that has been mounted into the container. The file must be executable.

Note that `*_FILE` variables will be overridden by their non-FILE versions if both are set.

Some notes:

- When specifying the script directly in Docker compose files any `$` that are being used to refer to environment variables must be doubled up (i.e. `$$`) else Compose will try to substitute them

### Example

With an executable file called `post-backup.sh` next to the compose file with the following contents

```sh
echo "Backup from $RCON_HOST to $DEST_DIR finished"
```

and the following compose definition

```yaml
version: '3.7'

services:
  mc:
    image: itzg/minecraft-server
    ports:
      - "25565:25565"
    environment:
      EULA: "TRUE"
      TYPE: PAPER
    volumes:
      - mc:/data
  backups:
    image: itzg/mc-backup
    environment:
      BACKUP_INTERVAL: "2h"
      RCON_HOST: mc
      PRE_BACKUP_SCRIPT: |
        echo "Before backup!"
        echo "Also before backup from $$RCON_HOST to $$DEST_DIR"
      POST_BACKUP_SCRIPT_FILE: /post-backup.sh
    volumes:
      # mount the same volume used by server, but read-only
      - mc:/data:ro
      # use a host attached directory so that it in turn can be backed up
      # to external/cloud storage
      - ./mc-backups:/backups
      - ./post-backup.sh:/post-backup.sh:ro

volumes:
  mc: {}

```

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
version: "3.8"

services:
  mc:
    image: itzg/minecraft-server:latest
    ports:
      - "25565:25565"
    environment:
      EULA: "TRUE"
      TYPE: PAPER
    depends_on:
      restore-backup:
        condition: service_completed_successfully
    volumes:
      - ./mc-data:/data
  # "init" container for mc to restore the data volume when empty    
  restore-backup:
    # Same image as mc, but any base image with bash and tar will work
    image: itzg/mc-backup
    restart: "no"
    entrypoint: restore-tar-backup
    volumes:
      # Must be same mount as mc service, needs to be writable
      - ./mc-data:/data
      # Must be same mount as backups service, but can be read-only
      - ./mc-backups:/backups:ro
  backups:
    image: itzg/mc-backup
    depends_on:
      mc:
        condition: service_healthy
    environment:
      BACKUP_INTERVAL: "2h"
      RCON_HOST: mc
      # since this service waits for mc to be healthy, no initial delay is needed
      INITIAL_DELAY: 0
    volumes:
      - ./mc-data:/data:ro
      - ./mc-backups:/backups
```

### Restic with rclone

Setup the rclone configuration for the desired remote location
```shell
docker run -it --rm -v rclone-config:/config/rclone rclone/rclone config
```

Setup the `itzg/mc-backup` container with the following specifics
- Set `BACKUP_METHOD` to `restic`
- Set `RESTIC_PASSWORD` to a restic backup repository password to use
- Use `rclone:` as the prefix on the `RESTIC_REPOSITORY`
- Append the rclone config name, colon (`:`), and specific sub-path for the config type

In the following example `CFG_NAME` and `BUCKET_NAME` need to be changed to specifics for the rclone configuration you created:
```yaml
version: "3"

services:
  mc:
    image: itzg/minecraft-server
    environment:
      EULA: "TRUE"
    ports:
      - 25565:25565
    volumes:
      - mc:/data
  backup:
    image: itzg/mc-backup
    environment:
      RCON_HOST: mc
      BACKUP_METHOD: restic
      RESTIC_PASSWORD: password
      RESTIC_REPOSITORY: rclone:CFG_NAME:BUCKET_NAME
    volumes:
      # mount volume pre-configured using a host mounted file
      - ./rclone.conf:/config/rclone/rclone.conf
      # or configure one into a named volume using
      # docker run -it --rm -v rclone-config:/config/rclone rclone/rclone config
      # and change the above to
      # - rclone-config:/config/rclone
      - mc:/data:ro
      - backups:/backup

volumes:
# Uncomment this if using the config step above
#  rclone-config:
#    external: true
  mc: {}
  backups: {}
```
