#!/bin/bash

vaults=`zfs list -H -o name -r tank/backup|grep -v ^tank/backup$|sed 's@^tank/backup/@@'`
echo "$vaults" | parallel -j 3 --dry-run -a - zfs-cron-monthly -f daily -v {1}

