#!/bin/bash

#set -x

# default variables
export PATH="/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export QUIET_NOTIFICATIONS=1
export INTERACTIVE_SESSION=0

export BACKUP_DATASET="tank/zrb"
export GLOBAL_CONFIG_DIR="/etc/zrb"
export GLOBAL_EXCLUDE_RULE="$GLOBAL_CONFIG_DIR/exclude"
export GLOBAL_EXPIRE_RULE="$GLOBAL_CONFIG_DIR/expire"
export FREQ_LIST="daily"
export LOCK_FILE="/var/run/${SCRIPT_BASENAME}.lock"
export VAULTS_FILE="/tmp/vaults.txt"

export SCRIPT_BASENAME="${0##*/}"

f_check_switch_param() {
    if ( echo x"$1" | grep -q ^x$ ); then
        f_say "$C_RED Missing argument!"

        exit 1
    fi
}

f_date() {
    local text="$1"

    echo -n "$text"

    date +"%Y-%m-%d %H:%M %Z"
}

f_declare_f_say() {
    if [[ $- == *i* ]]; then
        export QUIET_NOTIFICATIONS=0
        export INTERACTIVE_SESSION=1
    fi

    if [[ $INTERACTIVE_SESSION -eq 1 ]]
    then
        f_say() { echo -ne "$1"; echo -e "$C_NOCOLOR"; }

        export C_GREEN="\e[1;32m"
        export C_RED="\e[1;31m"
        export C_BLUE="\e[1;34m"
        export C_PURPLE="\e[1;35m"
        export C_CYAN="\e[1;36m"
        export C_NOCOLOR="\e[0m"
    else
        # do nothing
        f_say() { echo -ne "$1"; true; }
    fi

    export -f f_say
}

f_process_args() {
    while [ "$#" -gt "0" ]; do
        case "$1" in
            -f|--freq)
                PARAM=$2
                f_check_switch_param "$PARAM"

                FREQ_LIST="$PARAM"

                shift 2
            ;;

            -h|--help)
                f_usage
            ;;
        esac
    done
}

f_usage() {
    echo "Usage:"
    echo "    $0                    verbose output"
    echo "    $0 --q1               list vaults during progress"
    echo "    $0 --q2               full quiet"
    echo "    $0 -f <freq>          hourly,[daily],weekly,monthly (comma separated list)"
    echo

    exit 1
}

f_list_vaults() {
    if ( ! zfs list -H -s name -o name "$BACKUP_DATASET" ) ; then
        f_say "$C_RED    Unable to access the ZFS dataset: '$BACKUP_DATASET'"

        exit 1
    fi

    local dataset

    for dataset in $( zfs list -r -H -s name -o name "$BACKUP_DATASET" | grep -v "$BACKUP_DATASET$" ); do
        zfs list -H -s name -o name -r "$dataset" | grep -q "${dataset}/" || echo "$dataset";
    done | sed "s@^${BACKUP_DATASET}/@@"
}

f_lock_create() {
    local pid_now=$$

    if pid_locked=$(cat "$LOCK_FILE" 2>/dev/null);
        then
            if ( ps --no-headers -o args -p "$pid_locked" | grep -q "${SCRIPT_BASENAME}" );
                then
                    f_say "$C_RED $0 is already running!"

                    exit 1
                else
                    f_say "$C_PURPLE Stale pidfile exists...removing."

                    f_lock_remove
            fi
    fi

    echo "$pid_now" > "$LOCK_FILE"
}

f_lock_remove() {
    rm -f "$LOCK_FILE"
}

f_read_global_config() {
    if [ -f "$GLOBAL_CONFIG_DIR/BACKUP_DATASET" ];
        then
            BACKUP_DATASET=$(cat "$GLOBAL_CONFIG_DIR/BACKUP_DATASET")
    fi
}

f_run_parallel_jobs() {
    VAULTS_FILE=$1

    f_date "BEGIN: "

    # shellcheck disable=SC1083
    parallel -j 4 -a "$VAULTS_FILE" zrb.sh -e yes -f "$FREQ_LIST" -v {1}

    f_date "FINISH: "
}

f_declare_f_say

f_process_args "$@"

f_read_global_config

f_lock_create

f_list_vaults | tee "$VAULTS_FILE" > /dev/null

f_run_parallel_jobs "$VAULTS_FILE"

f_lock_remove
