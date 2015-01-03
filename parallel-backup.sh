#!/bin/bash

vaults=`zfs list -H -o name -r tank/backup|grep -v ^tank/backup$|sed 's@^tank/backup/@@'`
echo "$vaults" | parallel -v -j 2 -a - zrb.sh -f daily -v {1}

