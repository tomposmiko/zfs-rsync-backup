#!/bin/bash -e
pool="tank"
backup_dataset="$pool/backup"
date=$(date "+Y-%m-%d--%H-%M")
backup_exclude_global="/$pool/etc/zrb/exclude"


prefix="zrb"
# comma separated list
freq_list="echo $1|tr , ' '"

vault="$2"

rsync_args="-vrltH --delete -pgo --stats -D --numeric-ids"
rsync="rsync $rsync_args"

backup_vault_dest="$backup_dataset/$vault/data"
backup_vault_conf="$backup_dataset/$vault/config"
backup_source=$(cut -d'=' -f2 $backup_vault_conf/source)
backup_exclude_vault="$backup_vault_conf/exclude"




$rsync --exclude-from=$backup_exclude_vault $backup_source/ $backup_vault_dest/
err=$?
if [ $err = 24 ];
	then
		return 0
fi



for freq_type in $freq_list;do
	zfs snap $backup_dataset/$vault@${prefix}-${freq_type}-${date}
done
