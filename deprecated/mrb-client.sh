#!/bin/bash

pw=$(date | md5sum | cut -f1 -d' ')

mysql -e "create user zrb@localhost identified by '"$pw"'"
mysql -e "grant SELECT, SHOW VIEW, LOCK TABLES, RELOAD, REPLICATION CLIENT, PROCESS on *.* to zrb@localhost"
echo -e "[client]\nuser=zrb\npassword='$pw'" > /home/backup-zrb/.my.cnf

