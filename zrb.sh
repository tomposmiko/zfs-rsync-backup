#!/bin/bash -e
#set -x

# default variables
pool="tank"
backup_dataset="$pool/backup"
date=$(date "+%Y-%m-%d--%H-%M")

global_config_dir="/$pool/etc/zrb"
global_exclude="$global_config_dir/exclude"
global_expire="$global_config_dir/expire"

prefix=zrb
freq_list=daily
expire=no
quiet=0

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


if tty > /dev/null;
    then
        #interactive=1
        quiet=0
    else
        quiet=1
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
		say "$red Missing argument!"
		exit 1
	fi
}

f_usage(){
	echo "Usage:"
	echo " $0 -p PREFIX -v VAULT -f FREQUENCY"
	echo " $0 -a SOURCE -v VAULT"
	echo " $0 -l VAULT"
	echo " $0 -v VAULT -e only"
	echo
	echo "	-p|--prefix <prefix>      [zrb]"
	echo "	-v|--vault <vault>        "
	echo "	-f|--freq <freq types>    hourly,[daily],weekly,monthly (comma separated list)"
	echo "	-x|--exclude-file <file>  path to shared exclude file"
	echo "	-e|--expire	<goal>		  yes | [no] | only"
	echo "	-a|--add <source>         create vault and add source"
	echo "	-l|--list <vault>         display vault"
	echo "	-q|--quiet                quiet"
	echo
	exit 1
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

	-e|--expire)
		PARAM=$2
		f_check_switch_param $PARAM
		expire=$PARAM
		shift 2
	;;

	-f|--freq)
		PARAM=$2
		f_check_switch_param $PARAM
		freq_list=$(echo $PARAM| tr , ' ')
		shift 2
	;;

	-x|--exclude-file)
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

backup_vault_dest="/$backup_dataset/$vault/data"
backup_vault_conf="/$backup_dataset/$vault/config"
backup_vault_log="/$backup_dataset/$vault/log"


if [ ! -z $data_source ];
	then
		# check for directory of vault
		if [ -d /$backup_dataset/$vault ]; then
			say "$red Cannot add vault!"
			say "$red Existing directory: /$backup_dataset/$vault !"
	        exit 1
		fi

		# check for zfs dataset of vault
		if zfs list -s name $backup_dataset/$vault > /dev/null 2>&1; then
			say "$red Cannot add vault!"
        	say "$red Existing dataset: $backup_dataset/$vault !"
        	exit 1
		fi
		if zfs create $backup_dataset/$vault;
			then
				mkdir $backup_vault_conf
				mkdir $backup_vault_dest
				mkdir $backup_vault_log
				echo $data_source > $backup_vault_conf/source

			else
				say "$red Cannot create dataset:"
				say "$red $ zfs create $backup_dataset/$vault"
				exit 1
		fi
		echo
		zfs list -s name $backup_dataset/$vault
		echo
		say "$green Data source: $data_source"
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
		say "$red Non-existent dataset for vault: $backup_dataset/$vault !"
		exit 1
fi

# check for vault directory
if [ ! -d /$backup_dataset/$vault ]; then
		say "$red Non-existent vault directory: /$backup_dataset/$vault !"
		exit 1
fi

# check for vault/config directory
if [ ! -d $backup_vault_conf ]; then
		say "$red Non-existent config directory: $backup_vault_conf !"
		exit 1
fi

# check for vault/data directory
if [ ! -d $backup_vault_dest ]; then
		say "$red Non-existent rsync destination directory: $backup_vault_dest !"
		exit 1
fi

# check for vault/log directory
if [ ! -d $backup_vault_log ]; then
		sat "$red Non-existent rsync destination directory: $backup_vault_log !"
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
		backup_source=$(cat $backup_vault_conf/source)
	else
		say "$red Non-existent source file: $backup_vault_conf/source !"
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
				say "$red The switch '--exclude-file' and 'vault specific exclude' file are mutually exclusive!"
				say "$red switch: $backup_exclude_param"
				say "$red exclude file: $backup_vault_conf/exclude"
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
	test -f $backup_vault_conf/expire && . $backup_vault_conf/expire
	expire_rule="expire_${freq_type}"
	expire_limit=`date "+%s" -d "${!expire_rule} ago"`

	snap_list=`mktemp /tmp/snap_list.XXXXXX`
	zfs list -t snap -r -H tank/backup/$vault -o name -s name |cut -f2 -d@ > ${snap_list}
	for snap_orig in `cat $snap_list`;do
		snap_date=`echo $snap_orig | sed "s,\(${prefix}\)_\(${freq_type}\)_\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)--\([0-9][0-9]\)-\([0-9][0-9]\),\3 \4:\5,"`
		snap_epoch=`date "+%s" -d "$snap_date"`
		if [ $snap_epoch -lt $expire_limit ];
			then
				say "$green ${snap_orig}"
		fi
	done
	rm -f $snap_list
}


if [ $expire == only ];
	then
		for freq_type in $freq_list;do
			f_expire
		done
		exit 0
fi


# rsync parameters
rsync_args="-vrltH -h --delete -pgo --stats -D --numeric-ids --inplace --exclude-from=$global_exclude $rsync_exclude_param"

f_lock_create(){
	lockfile="$backup_vault_log/lock"
	if pid_locked=`cat $lockfile 2>/dev/null`;
		then
			#pid_now=`pgrep -f "/bin/bash -e ./zrb.sh -v.* $vault"`
			pid_now=$$
			if [ $pid_locked -eq $pid_now ];
				then
					say "$red Backup job is already running!"
					exit 1
				else
					say "$purple Stale pidfile exists...removing."
					rm -f $lockfile
			fi
		else
			echo $$ > $lockfile
	fi
}

f_lock_remove(){
	rm -f lockfile
}

f_rsync() {
    rsync-novanished.sh $rsync_args $backup_source/ $backup_vault_dest/
}


################## doing rsync ####################
f_lock_create
# rsync
if [ $quiet -eq 1 ];
	then
		say "$green $vault"
		#f_rsync $rsync_args $backup_source/ $backup_vault_dest/ > $backup_vault_log/rsync.log
		f_rsync > $backup_vault_log/rsync.log
	else
		#f_rsync $rsync_args $backup_source/ $backup_vault_dest/ | tee $backup_vault_log/rsync.log
		f_rsync | tee $backup_vault_log/rsync.log
fi

if [ $? -eq 0 ];
	then
		touch /$backup_dataset/$vault/FINISHED
fi
f_lock_remove
################## doing rsync ####################

for freq_type in $freq_list;do
	zfs snap $backup_dataset/$vault@${prefix}_${freq_type}_${date}
	if [ $expire == yes ];
    	then
            f_expire
	fi
done
