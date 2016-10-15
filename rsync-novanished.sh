#!/bin/sh
rsync "$@"
e=$?
if test $e = 24 -o $e = 23 ;
	then
		exit 0
fi

exit $e
