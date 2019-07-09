[![Docker Pulls](https://img.shields.io/docker/pulls/itzg/mc-backup.svg)](https://hub.docker.com/r/itzg/mc-backup)

Provides a side-car container to backup itzg/minecraft-server world data.

## Environment variables

- `SRC_DIR`=/data
- `DEST_DIR`=/backups
- `BACKUP_NAME`=world
- `INITIAL_DELAY`=120
- `INTERVAL_SEC`=86400
- `TYPE`=VANILLA
- `LEVEL`=world
- `RCON_PORT`=25575
- `RCON_PASSWORD`=minecraft
    
## Volumes

- `/data` :
  Should be attached read-only to the same volume as the `/data` of the `itzg/minecraft-server` container
- `/backups` :
  The volume where incremental tgz files will be created.
  
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
      - name: INTERVAL_SEC
        value: "3600"
    volumeMounts:
      - mountPath: /data
        name: data
        readOnly: true
      - mountPath: /backups
        name: backups
```
