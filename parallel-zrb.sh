#!/bin/bash

set -x

export PATH="$HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# default variables
pool="tank"
backup_dataset="$pool/backup"
PATH="/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
date=$(date "+%Y-%m-%d--%H-%M")

global_config_dir="/$pool/etc/zrb"
global_exclude="$global_config_dir/exclude"
global_expire="$global_config_dir/expire"

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
        say() { echo -ne $1; true; }
fi


f_check_switch_param(){
	if echo x"$1" |grep -q ^x$;then
		echo "Missing argument!"
		exit 1
	fi
}

f_usage(){
	echo "Usage:"
	echo "  $0                    verbose output"
	echo "  $0 -q                 display vaults"
	echo "  $0 -qq                full quiet"
    echo "  $0 -f <freq types>    hourly,[daily],weekly,monthly (comma separated list)"
	echo
}

# Exit if no arguments!
#let $# || { f_usage; exit 1; }

while [ "$#" -gt "0" ]; do
  case "$1" in
    -f|--freq)
        PARAM=$2
        f_check_switch_param $PARAM
        freq_list=$PARAM
        shift 2
    ;;

	-q)
		quiet_little=1
		break
	;;

	-qq)
		quiet_full=1
		break
	;;

    ""$)
        quiet_none=1
        break
	;;

	-h|--help)
		f_usage
		exit 0
	;;
  esac
done

if tty > /dev/null;
	then
		interactive=1
fi

# set default frequency to daily
if [ -z "$freq_list" ];
    then
        freq_list="daily"
fi

if [ -f $global_config_dir/backup_dataset ];
    then
        backup_dataset=`cat $global_config_dir/backup_dataset`
fi

f_lock_create(){
    pid_now=$$
	basename=`basename $0`
    lockfile="/var/run/${basename}.lock"
    if pid_locked=`cat $lockfile 2>/dev/null`;
        then
            if ps --no-headers -o args -p $pid_locked |grep -q "${basename}";
                then
                    say "$red $0 is already running!"
                    exit 1
                else
                    say "$purple Stale pidfile exists...removing."
                    f_lock_remove
            fi
    fi
    echo $pid_now > $lockfile
}

f_lock_remove(){
    rm -f $lockfile
}


f_lock_create
vaults=`mktemp /tmp/vaults.XXXX`

zfs list -H -s name -o name -r $backup_dataset|grep -v ^$backup_dataset$|sed "s@^${backup_dataset}/@@" > $vaults
echo "BEGIN: `date`"
parallel -j 4 -a $vaults zrb.sh -e yes -f $freq_list -v {1}
rm $vaults
echo "END: `date`"
f_lock_remove
