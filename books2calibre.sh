#!/usr/bin/env bash

progname=${0##*/}
progname=${progname%%.*}
tmpsh=$(mktemp $PWD/${progname}.sh.XXXXXXXX)
trap 'rm -f $tmpsh' EXIT
coproc calibre-server --port 8081
./books2calibre.pl >$tmpsh
kill $COPROC_PID
sh $tmpsh
