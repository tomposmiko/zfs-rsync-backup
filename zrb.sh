#!/bin/bash
# set -x

# default variables
pool="tank"
BACKUP_DATASET="$pool/zrb"
PATH="/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
date=$(date "+%Y-%m-%d--%H-%M")

GLOBAL_CONFIG_DIR="/etc/zrb"

SNAPSHOT_PREFIX="zrb"
FREQ_LIST="daily"
expire=no
QUIET_NOTIFICATIONS=1
INTERACTIVE_SESSION=0


_f_declare_f_say() {
    if [[ $- == *i* ]]; then
        export QUIET_NOTIFICATIONS=0
        export INTERACTIVE_SESSION=1
    fi

    if [[ $INTERACTIVE_SESSION -eq 1 ]]
    then
        # shellcheck disable=SC2317
        f_say() { echo -ne "$1"; echo -e "$C_NOCOLOR"; }

        export C_GREEN="\e[1;32m"
        export C_RED="\e[1;31m"
        export C_BLUE="\e[1;34m"
        export C_PURPLE="\e[1;35m"
        export C_CYAN="\e[1;36m"
        export C_NOCOLOR="\e[0m"
    else
        # do nothing
        # shellcheck disable=SC2317
        f_say() { echo -ne "$1"; true; }
    fi

    export -f f_say
}

_f_declare_f_say

# logging
#f_log() {
#  date=`date "+%Y-%m-%d %T"`
#  echo "$date $HOSTNAME: $*" >> $logfile;
#}
#
#tempfile=`mktemp /tmp/zrb.XXXX`
#
#echo "CLI: $0 $*" >> $tempfile

f_check_switch_param() {
    if ( ! echo "$1" | grep -q "^[A-Za-z0-9]" ); then
        f_say "$C_RED Missing argument!"

        exit 1
    fi
}

f_usage() {
  echo "Usage:"
  echo " $0 -v VAULT [ -p SNAPSHOT_PREFIX ] [ -f FREQUENCY ] [ -e EXPIRING ]"
  echo " $0 -a SOURCE -v VAULT"
  echo " $0 -l VAULT"
  echo
  echo "  -p|--prefix <snapshot refix>      [zrb]"
  echo "  -v|--vault <vault>"
  echo "  -f|--freq <freq types>    hourly,[daily],weekly,monthly (comma separated list)"
  echo "  -g|--conffir <dir path>"
  echo "  -x|--exclude-file <file>  path to shared exclude file"
  echo "  -e|--expire <goal>        yes | [no] | only"
  echo "  -a|--add <source>         create vault and add source"
  echo "  -l|--list <vault>         display vault"
  echo "  -q|--quiet"
  echo
  exit 1
}

f_process_args() {
    # Exit if no arguments!
    # shellcheck disable=SC2219
    let $# || f_usage

    while [ "$#" -gt "0" ]; do
        case "$1" in
            -p|--prefix)
                PARAM=$2
                f_check_switch_param "$PARAM"
                SNAPSHOT_PREFIX=$PARAM

                shift 2
            ;;

            -v|--vault)
                PARAM=$2
                f_check_switch_param "$PARAM"
                vault=$PARAM

                shift 2
            ;;

            -e|--expire)
                PARAM=$2
                f_check_switch_param "$PARAM"
                expire=$PARAM

                shift 2
            ;;

            -f|--freq)
                PARAM=$2
                f_check_switch_param "$PARAM"
                FREQ_LIST=$(echo "$PARAM" | tr , ' ')

                shift 2
            ;;

            -g|--confdir)
                PARAM=$2
                f_check_switch_param "$PARAM"
                GLOBAL_CONFIG_DIR="$PARAM"

                shift 2
            ;;

            -x|--exclude-file)
                PARAM=$2
                f_check_switch_param "$PARAM"
                backup_exclude_param="$PARAM"

                shift 2
            ;;

            -a|--add-vault)
                PARAM=$2
                f_check_switch_param "$PARAM"
                data_source=$PARAM

                shift 2
            ;;

            -l|--list)
                PARAM=$2
                f_check_switch_param "$PARAM"
                vault_to_list=$PARAM

                shift 2
            ;;

            -q|--quiet)
                QUIET_NOTIFICATIONS=1

                shift 1
            ;;


            -h|--help|*)
                f_usage
            ;;
        esac
    done
}

f_process_args "$@"

################# validate global config directory #####################
if echo "$GLOBAL_CONFIG_DIR" | grep -q ^/;
then
  global_exclude="$GLOBAL_CONFIG_DIR/exclude"
  global_expire="$GLOBAL_CONFIG_DIR/expire"
  global_placeholder="$GLOBAL_CONFIG_DIR/placeholder"
  global_notify_address="$GLOBAL_CONFIG_DIR/notify_address"
else
  echo "configdir does not start with /" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
  f_say "$C_RED configdir does not start with /"
  exit 1
fi
################# validate global config directory #####################


if [ -f "$GLOBAL_CONFIG_DIR/BACKUP_DATASET" ];
then
  export BACKUP_DATASET=$(cat "$GLOBAL_CONFIG_DIR/BACKUP_DATASET")
fi

export backup_vault_dest="/$BACKUP_DATASET/$vault/data"
export backup_vault_conf="/$BACKUP_DATASET/$vault/config"
export backup_vault_log="/$BACKUP_DATASET/$vault/log"

f_check_email_notify_address() {
  if [ -f "$global_notify_address" ];
  then
    email_notify_address=$(cat "$global_notify_address")
  else
    email_notify_address="root"
  fi
}
f_check_email_notify_address

########################## initializing vault #########################
if [ -n "$data_source" ];
then
  # check for directory of vault
  if [ -d "/$BACKUP_DATASET/$vault" ]; then
    f_say "$C_RED Cannot add vault!"
    f_say "$C_RED Existing directory: /$BACKUP_DATASET/$vault !"
    exit 1
  fi

  # check for zfs dataset of vault
  if zfs list -s name "$BACKUP_DATASET/$vault" > /dev/null 2>&1; then
    f_say "$C_RED Cannot add vault!"
    f_say "$C_RED Existing dataset: $BACKUP_DATASET/$vault !"
    exit 1
  fi
  if zfs create "$BACKUP_DATASET/$vault";
  then
    mkdir "$backup_vault_conf"
    mkdir "$backup_vault_dest"
    mkdir "$backup_vault_log"
    echo "$data_source" > "$backup_vault_conf/source"

  else
    f_say "$C_RED Cannot create dataset:"
    f_say "$C_RED $ zfs create $BACKUP_DATASET/$vault"
    exit 1
  fi
  echo
  zfs list -s name "$BACKUP_DATASET/$vault"
  echo
  f_say "$C_GREEN Data source: $data_source"
  echo
  exit 0
fi
########################## initializing vault #########################


################## snapshots listing of vault #######################
if [ -n "$vault_to_list" ];
then
  # if the parameter is full path
  if echo "$vault_to_list" | grep -q "^$BACKUP_DATASET";
  then
    zfs list -s name -t all -r "$vault_to_list"
  else
    # parameter is NOT full path, must be a matched string, can be multiple paths
    fs_to_list=$(zfs list -o name -s name | grep "^$BACKUP_DATASET/.*$vault_to_list")
    if [ x"$fs_to_list" == x"$BACKUP_DATASET" ];
    then
      echo "No matching filesystem!" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
      f_say "$C_RED No matching filesystem!"
    else
      zfs list -s name -t all -r "$fs_to_list"
    fi
  fi
  exit 0
fi
################## snapshots listing of vault #######################


################## checks for entries in vault ######################
# check for zfs dataset of vault
if ! zfs list -s name "$BACKUP_DATASET/$vault" > /dev/null 2>&1; then
  echo "Non-existent dataset for vault: $BACKUP_DATASET/$vault !" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
  f_say "$C_RED Non-existent dataset for vault: $BACKUP_DATASET/$vault !"
  exit 1
fi

# check for directory of vault
if [ ! -d "/$BACKUP_DATASET/$vault" ]; then
  echo "Non-existent vault directory: /$BACKUP_DATASET/$vault !" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
  f_say "$C_RED Non-existent vault directory: /$BACKUP_DATASET/$vault !"
  exit 1
fi

# check for config directory of vault
if [ ! -d "$backup_vault_conf" ]; then
  echo "Non-existent config directory: $backup_vault_conf !" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
  f_say "$C_RED Non-existent config directory: $backup_vault_conf !"
  exit 1
fi

# check for data directory of vault
if [ ! -d "$backup_vault_dest" ]; then
  echo "Non-existent rsync destination directory: $backup_vault_dest !" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
  f_say "$C_RED Non-existent rsync destination directory: $backup_vault_dest !"
  exit 1
fi

# check for log directory of vault
if [ ! -d "$backup_vault_log" ]; then
  echo "Non-existent rsync destination directory: $backup_vault_log !" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
  f_say "$C_RED Non-existent rsync destination directory: $backup_vault_log !"
  exit 1
fi
################## checks for entries in vault ######################


############## check if backup is disabled for this vault ###################
if [ -f "$backup_vault_conf/DISABLE" ];
then
  exit 0
fi
############## check if backup is disabled for this vault ###################


############## initializing backup source ###############
# path of the source
# Eg.: /mnt/source/dir
#    host:/mnt/source/dir
#
if [ -f "$backup_vault_conf/source" ];
then
  export backup_source=$(cat "$backup_vault_conf/source")
else
  echo "Non-existent source file: $backup_vault_conf/source !" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
  f_say "$C_RED Non-existent source file: $backup_vault_conf/source !"
  exit 1
fi
############## initializing backup source ###############

############### exclude file for rsync ##################
if [ -n "$backup_exclude_param" ];
then
  rsync_exclude_param="--exclude-from=$backup_exclude_param"
fi
############### exclude file for rsync ##################


################ vault exclude file ######################
if [ -f "$backup_vault_conf/exclude" ];
then
  if [ -n "$backup_exclude_param" ];
  then
    f_say "$C_RED The switch '--exclude-file' and the 'vault specific exclude' file are mutually exclusive!"
    f_say "$C_RED switch: $backup_exclude_param"
    f_say "$C_RED exclude file: $backup_vault_conf/exclude"
    exit 1
  fi
  rsync_exclude_file="--exclude-from=$backup_vault_conf/exclude"
fi
################ vault exclude file ######################

################ vault notification file ######################
if [ -f "$backup_vault_conf/notify" ];
then
  vault_notify_address=$(cat "$backup_vault_conf/notify")
  if [ -n "$vault_notify_address" ];
  then
    if ! echo "$vault_notify_address" | grep -q @;
    then
      f_say "red $vault_notify_address is not a valid email address"
      exit 1
    fi
    email_notify_address="$email_notify_address,$vault_notify_address"
  fi
fi
################ vault notification file ######################

f_check_placeholder() {
  # check if there is a specific file available to make sure, fs is mounted if its a network share (nfs, samba etc.)
  if echo "$backup_source" | grep -q -Eo ^"/";
  then
    file_placeholder=""
    [ -e "$global_placeholder" ] && file_placeholder=$(cat "$global_placeholder")
    [ -f "$backup_vault_conf/placeholder" ] && file_placeholder=$(cat "$backup_vault_conf/placeholder")
    if [ ! -e "$backup_source/$file_placeholder" ];
    then
      echo "Placeholder file defined but does not exist: $backup_source/$file_placeholder !" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
      f_say "$C_RED Placeholder file defined but does not exist: $backup_source/$file_placeholder !"
      f_say "$C_RED Filesystem is not mounted?"
      exit 1
    fi
  fi
}

################ pre-run script ######################
#if [ -f "$backup_vault_conf/pre-run.sh" ];
#  then
#    bash $backup_vault_conf/pre-run.sh
#fi
################ pre-run script ######################

f_expire() {
  if [ -f "$global_expire" ];
  then
    # shellcheck disable=SC1090
    . "$global_expire"
  else
    echo "No default expire file: $global_expire !" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
    f_say "$C_RED No default expire file: $global_expire !"
    exit 1
  fi

  # shellcheck disable=SC1090,SC1091
  test -f "$backup_vault_conf/expire" && . "$backup_vault_conf/expire"
  expire_rule="expire_${freq_type}"
  expire_limit=$(date "+%s" -d "${!expire_rule} ago")

  snap_list=$(mktemp /tmp/snap_list.XXXXXX)
  zfs list -t snap -r -H "$BACKUP_DATASET/$vault" -o name -s name |cut -f2 -d@ > "${snap_list}"
  snap_all_num=$(grep -c "${SNAPSHOT_PREFIX}_${freq_type}_" "${snap_list}")

  # default is $least_keep_count
  snap_min_count="least_keep_count_${freq_type}"
  snap_count=${!snap_min_count}
  # shellcheck disable=SC2013 disable=SC2002
  for snap_name in $(cat "$snap_list" | grep "$freq_type"); do ##CAT ABUSE
    # shellcheck disable=SC2001
    snap_date=$(echo "$snap_name" | sed "s,\(${SNAPSHOT_PREFIX}\)_\(${freq_type}\)_\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)--\([0-9][0-9]\)-\([0-9][0-9]\),\3 \4:\5,")
    snap_epoch=$(date "+%s" -d "$snap_date")
    if [ "$snap_epoch" -lt "$expire_limit" ];
    then
      if [ "$snap_count" -lt "$snap_all_num" ] ;
      then
        snap_count=$(("$snap_count"+1))
        f_say "$C_GREEN  ${BACKUP_DATASET}/${vault}@${snap_name}"
        zfs destroy "${BACKUP_DATASET}/${vault}@${snap_name}"
      else
        break
      fi
    fi
  done
  rm -f "$snap_list"
}


################ expiring only ##################
if [ "$expire" == only ];
then
  for freq_type in $FREQ_LIST; do
    f_expire
  done
  exit 0
fi
################ expiring only ##################


# remove old log file
rm -f "$backup_vault_log/rsync.log"

# rsync parameters
rsync_args="-vrltH --delete --delete-excluded -pgo --stats -h -D --numeric-ids --inplace --log-file=$backup_vault_log/rsync.log --exclude-from=$global_exclude $rsync_exclude_param $rsync_exclude_file"

f_lock_create() {
  lockfile="$backup_vault_log/lock"
  #pid_now=`pgrep -f "zrb.sh.* $vault"`
  pid_now=$$
  basename=$(basename "$0")
  if pid_locked=$(cat "$lockfile" 2>/dev/null);
  then
    # shellcheck disable=SC2009
    if ps --no-headers -o args -p "$pid_locked" | grep -q "${basename}.* $vault";
    then
      echo "Backup job is already running!" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
      f_say "$C_RED Backup job is already running!"
      exit 1
    else
      f_say "$C_PURPLE Stale pidfile exists...removing."
      f_lock_remove
    fi
  fi
  echo "$pid_now" > "$lockfile"
}

f_finished_create() {
  if [ "$rsync_ret" -eq 0 ];
  then
    touch "/$BACKUP_DATASET/$vault/FINISHED"
  fi
}

f_finished_remove() {
  file_finished="/$BACKUP_DATASET/$vault/FINISHED"
  if [ -f "$file_finished" ];
  then
    rm -f "$file_finished"
  else
    echo "Last backup was not succesful. Continuing from the last point." | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
    f_say "$C_RED Last backup was not succesful. Continuing from the last point."
  fi
}


f_lock_remove() {
  rm -f "$lockfile"
}

f_check_remote_host() {
    # return if the backup source is a local directory
    if (echo "$backup_source" | grep -q -Eo ^"/[0-9a-z@\.-]+"); then
        return 0
    fi

  if echo "$backup_source" | grep -q -Eo ^"[0-9a-z@\.-]+";
  then
    export backup_host=$(echo "$backup_source" | grep -Eo ^"[0-9a-z@\.-]+")
  fi

  if [ -n "$backup_host" ];
  then
    #echo "DEBUG: backup_host - f_check_remote_host: $backup_host"
    if ! ssh ${ssh_args[@]} "$backup_host" 'echo -n' 2>/dev/null
    then
      echo "Host $backup_host is not accessible!" | mail -s "zrb.sh ERROR: $vault" "$email_notify_address"
      f_say "$C_RED Host $backup_host is not accessible!"
      exit 1
    fi
  fi
}

f_pre_run_script() {
  #echo "DEBUG: backup_host - f_pre_run_script: $backup_host"
  pre_run_script="/$BACKUP_DATASET/$vault/config/pre-run.sh"
  if [ -f "$pre_run_script" ];
  then
    bash "$pre_run_script"
  fi
}

f_post_run_script() {
  #echo "DEBUG: backup_host - f_post_run_script: $backup_host"
  post_run_script="/$BACKUP_DATASET/$vault/config/post-run.sh"
  if [ -f "$post_run_script" ];
  then
    bash "$post_run_script"
  fi
}

f_ssh_config() {
  ssh_config="/$BACKUP_DATASET/$vault/config/ssh"
  if [ -f "$ssh_config" ];
  then
    ssh_args="-F $ssh_config"
  fi
}

f_rsync() {
  # shellcheck disable=SC2086
  #rsync-novanished.sh $rsync_args "$backup_source/" "$backup_vault_dest/"
  #rsync-novanished.sh ${rsync_args[@]} "$backup_source/" "$backup_vault_dest/"
  ssh_config="/$BACKUP_DATASET/$vault/config/ssh"
  if [ -f "$ssh_config" ];
  then
    rsync --rsync-path 'sudo rsync' -e "ssh -F $ssh_config" ${rsync_args[@]} "$backup_source/" "$backup_vault_dest/"
  else
    rsync --rsync-path 'sudo rsync' ${rsync_args[@]} "$backup_source/" "$backup_vault_dest/"
  fi

  exit_code=$?

  if [ $exit_code -eq 24 ] || [ $exit_code -eq 23 ]; then
    return 0
  fi

  return $exit_code
}

################## doing rsync ####################
f_ssh_config
f_check_remote_host
f_check_placeholder
f_lock_create
#echo "DEBUG: backup_host - before f_pre_run_script: $backup_host"
f_pre_run_script
f_finished_remove

############################### rsync ################################
f_say "$C_GREEN VAULT:$C_BLUE $vault"

date_start_epoch=$(date '+%s')
date_start_human=$(date -d "@$date_start_epoch" '+%Y-%m-%d %H:%M')
echo -e "BEGIN:\t$date_start_human" > "$backup_vault_log/report.txt"

if [ $QUIET_NOTIFICATIONS -eq 1 ];
then
  f_rsync > /dev/null
else
  f_say "$C_GREEN  START:$C_BLUE $date_start_human"
  f_rsync
fi
rsync_ret=$?
############################### rsync ################################

f_post_run_script

date_finish_epoch=$(date '+%s')
date_finish_human=$(date -d "@$date_finish_epoch" '+%Y-%m-%d %H:%M')
echo -e "FINISH:\t$date_finish_human" >> "$backup_vault_log/report.txt"
if [ ! $QUIET_NOTIFICATIONS -eq 1 ];
then
  f_say "$C_GREEN  FINISH:$C_BLUE $date_finish_human"
fi

duetime_epoch=$(("$date_finish_epoch" - "$date_start_epoch"))
duetime_human=$(printf '%d day(s) %02d:%02d:%02d\n' $((duetime_epoch/86400)) $((duetime_epoch/3600%24)) $((duetime_epoch/60%60)) $((duetime_epoch%60)))
echo "DELTA: $duetime_human ($duetime_epoch sec)" >> "$backup_vault_log/report.txt"
if [ ! $QUIET_NOTIFICATIONS -eq 1 ];
then
  f_say "$C_GREEN  DELTA:$C_BLUE $duetime_human"
fi

f_lock_remove
if [ ! $rsync_ret -eq 0 ];
then
  echo "rsync exited with non-zero status code: $rsync_ret !" | mail -s "$HOSTNAME zrb.sh ERROR: $vault" "$email_notify_address"
  f_say "$C_RED rsync exited with non-zero status code!"
  exit 1
fi
f_finished_create
################## doing rsync ####################

################# doing snapshot & expiring ##############
for freq_type in $FREQ_LIST;do
  zfs snap "$BACKUP_DATASET/$vault@${SNAPSHOT_PREFIX}_${freq_type}_${date}"
  if [ "$expire" == yes ];
  then
    f_expire
  fi
done
################# doing snapshot & expiring ##############

echo
