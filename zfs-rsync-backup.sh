#!/bin/bash -e
pool="tank"
backup_dataset="$pool/backup"
date=$(date "+Y-%m-%d--%H-%M")
backup_exclude_default="/$pool/etc/zrb/exclude"

# logging
#f_log(){
#	date=`date "+%Y-%m-%d %T"`
#	echo "$date $HOSTNAME: $*" >> $logfile;
#}
#
#tempfile=`mktemp /tmp/zpull.XXXX`
#
#echo "CLI: $0 $*" >> $tempfile

f_check_switch_param(){
	if echo x"$1" |grep -q ^x$;then
		echo "Missing argument!"
		exit 1
	fi
}

f_usage(){
	echo "Usage:"
	echo "	zrb -p PREFIX -v VAULT -f FREQUENCY"
	echo
	echo "	   -p|--prefix <prefix>      default: zrb"
	echo "	   -v|--vault <vault>        "
	echo "	   -f|--freq <freq type>     hourly,daily,weekly,monthly (comma separated list)"
	echo
}


# Exit if no arguments!
let $# || { f_usage; exit 1; }

while [ "$#" -gt "0" ]; do
  case "$1" in
	-p|--prefix)
		PARAM=$2
		f_check_switch_param $PARAM
		prefix={$PARAM:zrb}
		shift 2
	;;

	-v|--vault)
		PARAM=$2
		f_check_switch_param $PARAM
		vault=$PARAM
		shift 2
	;;

	-f|--freq)
		PARAM=$2
		f_check_switch_param $PARAM
		freq_list=$(echo $PARAM| tr , ' ')
		shift 2
	;;

	-e|--exclude-file)
		PARAM=$2
		f_check_switch_param $PARAM
		backup_exclude_param=${PARAM:-$backup_exclude_default}


	-h|--help|*)
		f_usage
		exit 0
	;;
  esac
done

rsync_args="-vrltH --delete -pgo --stats -D --numeric-ids"
rsync="rsync $rsync_args"

backup_vault_dest="$backup_dataset/$vault/data"
backup_vault_conf="$backup_dataset/$vault/config"

if [ ! -d $backup_vault_conf ]; then
		echo "Non-existent config directory: $backup_vault_conf !"
		exit 1
fi

if [ ! -d $backup_vault_dest ]; then
		echo "Non-existent rsync destination directory: $backup_vault_dest !"
		exit 1
fi

# path of the source
# Eg.: /mnt/source/dir
#      host:/mnt/source/dir
#
if [ -f $backup_vault_conf/source ];
	then
		backup_source=$(cut -d'=' -f2 $backup_vault_conf/source)
	else
		echo "Non-existent source file: $backup_vault_conf/source !"
		exit 1
fi

# exclude file for rsync
#
if [ -f $backup_vault_conf/exclude ];
	then
		if [ ! -z $backup_exclude_param ];
			then
				echo "The --exclude-file swich and the exclude file in vault present at the same time!"
				echo "switch: $backup_exclude_param"
				echo "file: $backup_vault_conf/exclude"
				exit 1
		fi
		backup_exclude_file=$backup_vault_conf/exclude
	else
		backup_exclude_file=$backup_exclude_param
	
fi



$rsync --exclude-from=$backup_exclude_file $backup_source/ $backup_vault_dest/
err=$?
if [ $err = 24 ];
	then
		return 0
fi



for freq_type in $freq_list;do
	zfs snap $backup_dataset/$vault@${prefix}-${freq_type}-${date}
done



