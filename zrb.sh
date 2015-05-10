#!/bin/bash -e

# default variables
pool="tank"
backup_dataset="$pool/backup"
date=$(date "+%Y-%m-%d--%H-%M")

global_config_dir="/$pool/etc/zrb"
global_exclude="$global_config_dir/exclude"
global_expire="$global_config_dir/expire"

prefix=zrb
freq_list=daily


# https://github.com/maxtsepkov/bash_colors/blob/master/bash_colors.sh
uncolorize () { sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g"; }
if [[ $- != *i* ]]
   then say() { echo -ne $1;echo -e $nocolor; }
		# Colors, yo!
		green="\e[1;32m"
		red="\e[1;31m"
		blue="\e[1;34m"
		purple="\e[1;35m"
		cyan="\e[1;36m"
		nocolor="\e[0m"
   else
		# do nothing
		say() { true; }
fi

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
	echo "	   -p|--prefix <prefix>      [zrb]"
	echo "	   -v|--vault <vault>        "
	echo "	   -f|--freq <freq types>    hourly,[daily],weekly,monthly (comma separated list)"
	echo "	   -e|--exclude-file <file>  path to shared exclude file"
	echo "	   -a|--add <source>         create vault and add source"
	echo "	   -l|--list <vault>         display vault"
	echo "	   -q|--quiet				 quiet"
	echo
}

f_rsync() {
	rsync-novanished.sh $@
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

	-q|--quiet)
		quiet=1
		shift 1
	;;


	-h|--help|*)
		f_usage
		exit 0
	;;
  esac
done

if tty > /dev/null;
	then
		interactive=1
fi



backup_vault_dest="/$backup_dataset/$vault/data"
backup_vault_conf="/$backup_dataset/$vault/config"
backup_vault_log="/$backup_dataset/$vault/log"


if [ ! -z $data_source ];
	then
		# check for vault directory
		if [ -d /$backup_dataset/$vault ]; then
			echo "Cannot add vault!"
        	echo "Existing vault directory: /$backup_dataset/$vault !"
	        exit 1
		fi

		# check for vault zfs dataset
		if zfs list -s name $backup_dataset/$vault > /dev/null 2>&1; then
			echo "Cannot add vault!"
        	echo "Existing dataset: $backup_dataset/$vault !"
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
		zfs list -s name $backup_dataset/$vault
		echo
		echo "Data source: $data_source"
		echo
		exit 0
fi

if [ ! -z $vault_to_list ];
	then
		if echo $vault_to_list | grep -q ^$backup_dataset;
			then
				zfs list -s name -t all -r $vault_to_list
			else
				zfs list -s name -t all -r $backup_dataset/$vault_to_list
		fi
		exit 0
fi

# check for vault zfs dataset
if ! zfs list -s name $backup_dataset/$vault > /dev/null 2>&1;then
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


if [ -f $backup_vault_conf/DISABLE ];
	then
		exit 0
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
if [ ! -z $backup_exclude_param ];
	then
		rsync_exclude_param="--exclude-from=$backup_exclude_param"
fi

if [ -f $backup_vault_conf/exclude ];
	then
		if [ ! -z $backup_exclude_param ];
			then
				echo "Both --exclude-file switch and vault specific exclude file present at the same time!"
				echo "switch: $backup_exclude_param"
				echo "file: $backup_vault_conf/exclude"
				exit 1
		fi
		backup_exclude_file=$backup_vault_conf/exclude
fi

f_expire(){
if [ -f $global_expire ];
	then
		. $global_expire
	else
		say "$red No default expire file: $global_expire !"
		exit 1
fi
snap_list=`mktemp /tmp/dataset_list.XXXXXX`
zfs list -t snap -r -H tank/backup/$vault -o name -s name |cut -f2 -d@ > ${snap_list}
for snap_orig in `cat $snap_list`;do
	snap_date=`echo $snap_orig | sed -e "s/${prefix}_${freq}_//" -e 's/--/ /'`
	snap_epoch=`date "+%s" -d "$snap_date"`
	date_current=`date "+%s"`
	say "$green ${snap_orig}"
	#zfs destroy ${dataset}
done

rm -f $dataset_list

}


# rsync parameters
rsync_args="-vrltH -h --delete -pgo --stats -D --numeric-ids --inplace --exclude-from=$global_exclude $rsync_exclude_param"

# locking
lockfile="$backup_vault_log/lock"
if pid_locked=`cat $lockfile 2>/dev/null`;
	then
		#pid_now=`pgrep -f "/bin/bash -e ./zrb.sh -v.* $vault"`
		pid_now=$$
		if [ $pid_locked -eq $pid_now ];
			then
				echo "Backup job is already running!"
				exit 1
			else
				echo "Stale pidfile exists...removing."
				rm -f $lockfile
		fi
	else
		echo $$ > $lockfile
fi


# rsync
if [ -z $interactive ];
	then
		echo $vault
		f_rsync $rsync_args $backup_source/ $backup_vault_dest/ > $backup_vault_log/rsync.log
	else
		if [ x$quiet == x1 ];
			then
				echo $vault
				f_rsync $rsync_args $backup_source/ $backup_vault_dest/ > $backup_vault_log/rsync.log
			else
				f_rsync $rsync_args $backup_source/ $backup_vault_dest/ | tee $backup_vault_log/rsync.log
		fi
fi

if [ $? -eq 0 ];
	then
		touch /$backup_dataset/$vault/FINISHED
fi
rm -f $lockfile


for freq_type in $freq_list;do
	zfs snap $backup_dataset/$vault@${prefix}_${freq_type}_${date}
done
