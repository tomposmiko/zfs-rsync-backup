#!/bin/bash


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



vaults=`mktemp /tmp/vaults.XXXX`

zfs list -H -s name -o name -r tank/backup|grep -v ^tank/backup$|sed 's@^tank/backup/@@' > $vaults
parallel -v -j 2 -a $vaults zrb.sh -f $freq_list -v {1} > /dev/null
#rm $vaults
