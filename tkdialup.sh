#! /bin/sh

progdir=$(dirname $0)
progname=$(basename $0)

cd "$progdir" && exec perl -w ./tkdialup.pl $*
