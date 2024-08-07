#!/usr/bin/env bash

mkdir -p ./backups
mkdir -p ./data

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

old_timestamp=$(TZ=UTC+96 date +%Y%m%d%H%M) # Two days old

run_test1(){
  echo -e "\nTest 1: Ensure default behavior, no suffix"
  cleanup_backups

  docker compose run --build backup now
  preserved_backup_count=$(find backups/ -name "*.tgz" -name "*preserve*" | wc -l)
  not_preserved_backup_count=$(find backups/ -name "*.tgz" -not -name "*preserve*" | wc -l)
  
  echo "Preserved backups: ${preserved_backup_count}"
  echo "Not-Preserved backups: ${not_preserved_backup_count}"

  # Ensure typical backup does not have "-preserve" suffix
  if [ 1 -eq "$not_preserved_backup_count" ]; then
    echo "PASS"
  else
    echo "FAIL"
    overall_status=1
  fi
}

run_test2(){
  echo -e "\nTest 1: Ensure added suffix and preserved are not pruned"
  cleanup_backups

  # Two old backups
  touch -t "$old_timestamp" "./backups/fake-backup-preserve.tgz"
  touch -t "$old_timestamp" "./backups/fake-backup.tgz"

  # Plus current preserved backup
  docker compose -f docker-compose.yml -f docker-compose.override.yml run --build backup now > /dev/null
   
  preserved_backup_count=$(find backups/ -name "*.tgz" -name "*preserve*" | wc -l)
  not_preserved_backup_count=$(find backups/ -name "*.tgz" -not -name "*preserve*" | wc -l)
  
  echo "Preserved backups: ${preserved_backup_count}"
  echo "Not-Preserved backups: ${not_preserved_backup_count}"

  # Ensure there's 
  # 2 preserved (1 old + 1 new)
  # 0 not preserved (1 pruned)
  if [[ 2 -eq "$preserved_backup_count" && 0 -eq "$not_preserved_backup_count" ]]; then
    echo "PASS"
    else
    echo "FAIL"
    overall_status=1
  fi
}

setup
run_test1
run_test2

exit $overall_status

