#!/usr/bin/env bash

mkdir -p ./backups
mkdir -p ./data

cleanup() {
  rm -rf ./backups/*
  rm -rf ./data/*
}

# Set inital state to PASS
overall_status=0

# Build from current filesystem
echo "BUILDING..."
docker compose build > /dev/null

#
# BACKUP_ON_STARTUP = true (default)
#

echo "Test 1 - BACKUP_ON_STARTUP = true"

cleanup
docker compose -f docker-compose.yml up -d > /dev/null
sleep 20 # Wait for backup to run TODO: Use a more robust method
backup_count=$(ls -1 backups | wc -l)
echo "Output: ${backup_count} backups"

if [ 1 -eq "$(ls -1 backups | wc -l)" ]; then
  echo "PASS"
else
  echo "FAIL"
  overall_status=1
fi

#
# BACKUP_ON_STARTUP = false
#

echo "Test 2 - BACKUP_ON_STARTUP = false"

cleanup
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d > /dev/null
sleep 20 # Wait for backup to run TODO: Use a more robust method
backup_count=$(ls -1 backups | wc -l)
echo "Output: ${backup_count} backups"

if [ 0 -eq "$(ls -1 backups | wc -l)" ]; then
  echo "PASS"
else
  echo "FAIL"
  overall_status=1
fi

#
# BACKUP_ON_STARUP = false, ONE_SHOT
#

echo "Test 3 - BACKUP_ON_STARTUP = false, ONE_SHOT"

cleanup
docker compose exec backup backup now > /dev/null
sleep 20 # Wait for backup to run TODO: Use a more robust method
backup_count=$(ls -1 backups | wc -l)
echo "Output: ${backup_count} backups"

if [ 1 -eq "$(ls -1 backups | wc -l)" ]; then
  echo "PASS"
else
  echo "FAIL"
  overall_status=1
fi

# Clean up
docker compose down
cleanup

exit $overall_status

