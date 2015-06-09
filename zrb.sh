#!/bin/bash
#set -x

# default variables
pool="tank"
backup_dataset="$pool/backup"
PATH="/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
date=$(date "+%Y-%m-%d--%H-%M")

global_config_dir="/$pool/etc/zrb"

prefix=zrb
freq_list=daily
expire=no
quiet=1
interactive=0

if /usr/bin/tty > /dev/null;
    then
        quiet=0
        interactive=1
fi


# https://github.com/maxtsepkov/bash_colors/blob/master/bash_colors.sh
uncolorize () { sed -r "s/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g"; }
if [[ $interactive -eq 1 ]]
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
#tempfile=`mktemp /tmp/zrb.XXXX`
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
	echo " $0 -v VAULT [ -p PREFIX ] [ -f FREQUENCY ] [ -e EXPIRING ]"
	echo " $0 -a SOURCE -v VAULT"
	echo " $0 -l VAULT"
	echo
	echo "	-p|--prefix <prefix>      [zrb]"
	echo "	-v|--vault <vault>"
	echo "	-f|--freq <freq types>    hourly,[daily],weekly,monthly (comma separated list)"
	echo "	-g|--conffir <dir path>"
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

	-g|--confdir)
		PARAM=$2
		f_check_switch_param $PARAM
		global_config_dir=$PARAM
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


################# validate global config directory #####################
if echo $global_config_dir |grep -q ^/;
	then
		global_exclude="$global_config_dir/exclude"
		global_expire="$global_config_dir/expire"
	else
		say "$red configdir does not start with /"
		exit 1
fi
################# validate global config directory #####################


if [ -f $global_config_dir/backup_dataset ];
	then
		backup_dataset=`cat  $global_config_dir/backup_dataset`
fi

backup_vault_dest="/$backup_dataset/$vault/data"
backup_vault_conf="/$backup_dataset/$vault/config"
backup_vault_log="/$backup_dataset/$vault/log"

########################## initializing vault #########################
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
########################## initializing vault #########################


################## snapshots listing of vault #######################
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
################## snapshots listing of vault #######################


################## checks for entries in vault ######################
# check for zfs dataset of vault
if ! zfs list -s name $backup_dataset/$vault > /dev/null 2>&1;then
		say "$red Non-existent dataset for vault: $backup_dataset/$vault !"
		exit 1
fi

# check for directory of vault
if [ ! -d /$backup_dataset/$vault ]; then
		say "$red Non-existent vault directory: /$backup_dataset/$vault !"
		exit 1
fi

# check for config directory of vault
if [ ! -d $backup_vault_conf ]; then
		say "$red Non-existent config directory: $backup_vault_conf !"
		exit 1
fi

# check for data directory of vault
if [ ! -d $backup_vault_dest ]; then
		say "$red Non-existent rsync destination directory: $backup_vault_dest !"
		exit 1
fi

# check for log directory of vault
if [ ! -d $backup_vault_log ]; then
		say "$red Non-existent rsync destination directory: $backup_vault_log !"
		exit 1
fi
################## checks for entries in vault ######################


############## check if backup is disabled for this vault ###################
if [ -f $backup_vault_conf/DISABLE ];
	then
		exit 0
fi
############## check if backup is disabled for this vault ###################


############## initializing backup source ###############
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
############## initializing backup source ###############


############### exclude file for rsync ##################
if [ ! -z $backup_exclude_param ];
	then
		rsync_exclude_param="--exclude-from=$backup_exclude_param"
fi
############### exclude file for rsync ##################


################ global exclude file ######################
if [ -f $backup_vault_conf/exclude ];
	then
		if [ ! -z $backup_exclude_param ];
			then
				say "$red The switch '--exclude-file' and the 'vault specific exclude' file are mutually exclusive!"
				say "$red switch: $backup_exclude_param"
				say "$red exclude file: $backup_vault_conf/exclude"
				exit 1
		fi
		rsync_exclude_file="--exclude-from=$backup_vault_conf/exclude"
fi
################ global exclude file ######################


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
	zfs list -t snap -r -H $backup_dataset/$vault -o name -s name |cut -f2 -d@ > ${snap_list}
	snap_all_num=`grep -c "${prefix}_${freq_type}_" ${snap_list}`

	# default is $least_keep_count
	snap_min_count="least_keep_count_${freq_type}"
	snap_count=${!snap_min_count}
	for snap_name in `cat $snap_list | grep ${freq_type}`;do
		snap_date=`echo $snap_name | sed "s,\(${prefix}\)_\(${freq_type}\)_\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)--\([0-9][0-9]\)-\([0-9][0-9]\),\3 \4:\5,"`
		snap_epoch=`date "+%s" -d "$snap_date"`
		if [ $snap_epoch -lt $expire_limit ];
			then
				if [ $snap_count -lt $snap_all_num ] ;
					then
						let snap_count=${snap_count}+1
						say "$green    ${backup_dataset}/${vault}@${snap_name}"
						zfs destroy ${backup_dataset}/${vault}@${snap_name}
					else
						break
				fi
		fi
	done
	rm -f $snap_list
}


################ expiring only ##################
if [ $expire == only ];
	then
		for freq_type in $freq_list;do
			f_expire
		done
		exit 0
fi
################ expiring only ##################


# rsync parameters
rsync_args="-vrltH -z --delete --delete-excluded -pgo --stats -h -D --numeric-ids --inplace --log-file=$backup_vault_log/rsync.log --exclude-from=$global_exclude $rsync_exclude_param $rsync_exclude_file"

f_lock_create(){
	lockfile="$backup_vault_log/lock"
	#pid_now=`pgrep -f "zrb.sh.* $vault"`
	pid_now=$$
    basename=`basename $0`
	if pid_locked=`cat $lockfile 2>/dev/null`;
		then
			if ps --no-headers -o args -p $pid_locked |grep -q "${basename}.* $vault";
				then
					say "$red Backup job is already running!"
					exit 1
				else
					say "$purple Stale pidfile exists...removing."
					f_lock_remove
			fi
	fi
	echo $pid_now > $lockfile
}

f_finished_create(){
	if [ $rsync_ret -eq 0 ];
	    then
    	    touch /$backup_dataset/$vault/FINISHED
	fi
}

f_finished_remove(){
	file_finished=/$backup_dataset/$vault/FINISHED
	if [ -f $file_finished ];
		then
			rm -f $file_finished
		else
			say "$red Last backup was not succesful. Continuing from the last point."
	fi
}


f_lock_remove(){
    rm -f $lockfile
}

f_rsync() {
    rsync-novanished.sh $rsync_args $backup_source/ $backup_vault_dest/
}


################## doing rsync ####################
f_lock_create
f_finished_remove
# rsync
say "$green VAULT:$blue $vault"

date_start_epoch="`date '+%s'`"
date_start_human="`date -d @${date_start_epoch} '+%Y-%m-%d %H:%M'`"
echo -e "BEGIN:\t$date_start_human" > $backup_vault_log/report.txt

if [ $quiet -eq 1 ];
	then
		f_rsync > /dev/null
	else
		say "$green    START:$blue $date_start_human"
		f_rsync
fi
rsync_ret=$?

date_finish_epoch="`date '+%s'`"
date_finish_human="`date -d @${date_finish_epoch} '+%Y-%m-%d %H:%M'`"
echo -e "FINISH:\t$date_finish_human" >> $backup_vault_log/report.txt
if [ ! $quiet -eq 1 ];
	then
		say "$green    FINISH:$blue $date_finish_human"
fi

duetime_epoch=$[${date_finish_epoch} - ${date_start_epoch}]
duetime_human="`printf '%d day(s) %02d:%02d:%02d\n' $((duetime_epoch/86400)) $((duetime_epoch/3600%24)) $((duetime_epoch/60%60)) $((duetime_epoch%60))`"
echo "DELTA: $duetime_human ($duetime_epoch sec)" >> $backup_vault_log/report.txt
if [ ! $quiet -eq 1 ];
	then
		say "$green    DELTA:$blue $duetime_human"
fi

f_lock_remove
if [ ! $rsync_ret -eq 0 ];
	then
		say "$red rsync exited with non-zero status code!"
		exit 1
fi
f_finished_create
################## doing rsync ####################

################# doing snapshot & expiring ##############
for freq_type in $freq_list;do
	zfs snap $backup_dataset/$vault@${prefix}_${freq_type}_${date}
	if [ $expire == yes ];
    	then
            f_expire
	fi
done
################# doing snapshot & expiring ##############
