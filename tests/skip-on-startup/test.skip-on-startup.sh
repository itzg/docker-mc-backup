#!/usr/bin/env bash

mkdir -p ./backups
mkdir -p ./data

get_backup_count() {
  backup_count=$(ls -1 backups | wc -l)
  echo "Output: ${backup_count} backups"
}

cleanup_backups() {
  rm -rf ./backups/*
}

cleanup_all() {
  docker compose down
  cleanup_backups
  rm -rf ./data/*
}

## Clean up upon failure or reaching the end
trap cleanup_all EXIT

setup() {
  # Set inital exit state to PASS (0)
  overall_status=0

  # Build from current filesystem
  echo "Building..."
  docker compose build > /dev/null

  echo "Starting server..."
  rm -rf ./data/*
  docker compose up mc -d > /dev/null
}

run_test1(){
  echo -e "\nTest 1: BACKUP_ON_STARTUP=true"
  cleanup_backups
  docker compose -f docker-compose.yml up backup -d > /dev/null
  sleep 5
  get_backup_count

  if [ 1 -eq "$backup_count" ]; then
    echo "PASS"
  else
    echo "FAIL"
    overall_status=1
  fi
}

run_test2() {
  echo -e "\nTest 2: BACKUP_ON_STARTUP=false"
  cleanup_backups
  docker compose -f docker-compose.yml -f docker-compose.override.yml up backup -d > /dev/null
  sleep 5
  get_backup_count

  if [ 0 -eq "$backup_count" ]; then
    echo "PASS"
  else
    echo "FAIL"
    overall_status=1
  fi
}

run_test3() {
  echo -e "\nTest 3: BACKUP_ON_STARTUP=false, ONE_SHOT=true"
  cleanup_backups
  docker compose exec backup backup now > /dev/null
  get_backup_count

  if [ 1 -eq "$backup_count" ]; then
    echo "PASS"
  else
    echo "FAIL"
    overall_status=1
  fi
}

setup
run_test1
run_test2
run_test3

exit $overall_status
