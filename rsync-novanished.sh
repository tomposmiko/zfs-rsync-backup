#!/bin/bash -x

#rsync --rsync-path "sudo rsync" "$@"
args=("$@")
rsync --rsync-path='sudo rsync' "${args[@]}"
e=$?
if [ $e -eq 24 -o $e -eq 23 ]; then
  exit 0
fi
exit $e
