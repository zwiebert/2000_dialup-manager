#! /bin/sh

progdir=$(dirname $0)
progname=$(basename $0)

input=$HOME/.dialup_cost.log

perl $progdir/stat_new.pl < "$input"

read line
