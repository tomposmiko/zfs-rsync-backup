#!/bin/bash -e
pool="tank"
backup_dataset="$pool/backup"
date=$(date "+%Y-%m-%d--%H-%M")
backup_exclude_default="/$pool/etc/zrb/exclude"
prefix=zrb

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
	echo "	$0 -p PREFIX -v VAULT -f FREQUENCY"
	echo "	$0 -a SOURCE -v VAULT"
	echo "	$0 -l VAULT"
	echo
	echo "	   -p|--prefix <prefix>      default: zrb"
	echo "	   -v|--vault <vault>        "
	echo "	   -f|--freq <freq type>     hourly,daily,weekly,monthly (comma separated list)"
	echo "	   -e|--exclude-file <file>  path to common exclude file"
	echo "	   -a|--add <source>         create vault and add source"
	echo "	   -l|--list <vault>         display vault"
	echo
}

# Exit if no arguments!
let $# || { f_usage; exit 1; }

while [ "$#" -gt "0" ]; do
  case "$1" in
	-p|--prefix)
		PARAM=$2
		f_check_switch_param $PARAM
		prefix=$PARAM
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
		backup_exclude_param=$PARAM
		shift 2
	;;

	-a|--add-vault)
		PARAM=$2
		f_check_switch_param $PARAM
		data_source=$PARAM
		shift 2
	;;

	-l|--list)
		PARAM=$2
		f_check_switch_param $PARAM
		vault_to_list=$PARAM
		shift 2
	;;

	-h|--help|*)
		f_usage
		exit 0
	;;
  esac
done

backup_vault_dest="/$backup_dataset/$vault/data"
backup_vault_conf="/$backup_dataset/$vault/config"
backup_vault_log="/$backup_dataset/$vault/log"


if [ -n $data_source ];
	then
		# check for vault directory
		if [ -d /$backup_dataset/$vault ]; then
			echo "Cannot add vault!"
        	echo "Existent vault directory: /$backup_dataset/$vault !"
	        exit 1
		fi

		# check for vault zfs dataset
		if zfs list $backup_dataset/$vault > /dev/null 2>&1; then
			echo "Cannot add vault!"
        	echo "Existent dataset for vault: $backup_dataset/$vault !"
        	exit 1
		fi
		if zfs create $backup_dataset/$vault;
			then
				mkdir $backup_vault_conf
				mkdir $backup_vault_dest
				mkdir $backup_vault_log
				echo $data_source > $backup_vault_conf/source

			else
				echo "Cannot create dataset:"
				echo "$ zfs create $backup_dataset/$vault"
				exit 1
		fi
		echo
		zfs list $backup_dataset/$vault
		echo
		echo "Data source: $data_source"
		echo
		exit 0
fi

if [ -n $vault_to_list ];
	then
		if echo $vault_to_list | grep -q ^$backup_dataset;
			then
				zfs list -t all -r $vault_to_list
			else
				zfs list -t all -r $backup_dataset/$vault_to_list
		fi
		exit 0
fi

# check for vault zfs dataset
if ! zfs list $backup_dataset/$vault > /dev/null 2>&1;then
		echo "Non-existent dataset for vault: $backup_dataset/$vault !"
		exit 1
fi

# check for vault directory
if [ ! -d /$backup_dataset/$vault ]; then
		echo "Non-existent vault directory: /$backup_dataset/$vault !"
		exit 1
fi

# check for vault/config directory
if [ ! -d $backup_vault_conf ]; then
		echo "Non-existent config directory: $backup_vault_conf !"
		exit 1
fi

# check for vault/data directory
if [ ! -d $backup_vault_dest ]; then
		echo "Non-existent rsync destination directory: $backup_vault_dest !"
		exit 1
fi

# check for vault/log directory
if [ ! -d $backup_vault_log ]; then
		echo "Non-existent rsync destination directory: $backup_vault_log !"
		exit 1
fi

# path of the source
# Eg.: /mnt/source/dir
#      host:/mnt/source/dir
#
if [ -f $backup_vault_conf/source ];
	then
		#backup_source=$(cut -d'=' -f2 $backup_vault_conf/source)
		backup_source=$(cat $backup_vault_conf/source)
	else
		echo "Non-existent source file: $backup_vault_conf/source !"
		exit 1
fi

# exclude file for rsync
#
if [ -n $backup_exclude_param ];
	then
		rsync_exclude_param="--exclude-from=$backup_exclude_param"
fi

if [ -f $backup_vault_conf/exclude ];
	then
		if [ -n $backup_exclude_param ];
			then
				echo "Both --exclude-file switch and vault specific exclude file present at the same time!"
				echo "switch: $backup_exclude_param"
				echo "file: $backup_vault_conf/exclude"
				exit 1
		fi
		backup_exclude_file=$backup_vault_conf/exclude
fi


if ! echo "$freq_list"|egrep -wq '(hourly|daily|weekly|monthly)';then
	echo "No frequency defined (hourly|daily|weekly|monthly)!"
	exit 1
fi

# rsync parameters
rsync_args="-vrltH -h --delete -pgo --stats -D --numeric-ids --inplace --exclude-from=$backup_exclude_default $rsync_exclude_param"


rsync $rsync_args $backup_source/ $backup_vault_dest/ > $backup_vault_log/rsync.log
err=$?
if [ $err = 24 ];
	then
		return 0
fi



for freq_type in $freq_list;do
	zfs snap $backup_dataset/$vault@${prefix}-${freq_type}-${date}
done
