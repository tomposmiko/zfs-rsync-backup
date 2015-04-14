#!/bin/sh
rsync "$@"
e=$?
if test $e = 24;
	then
		exit 0
fi

exit $e
