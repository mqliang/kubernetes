#!/bin/sh
#
# Copyright 2016 The Caicloud Authors All rights reserved.
#
# Author: KeonTang <ikeontang@gmail.com>
#
# for ANY state transition.
# "notify" script is called AFTER the
# notify_* script(s) and is executed
# with 4 arguments provided by keepalived
# (ie don’t include parameters in the notify line).
# arguments
# $1 = "GROUP"|"INSTANCE"
# $2 = name of group or instance
# $3 = target state of transition
# $4 = The priority value
#     ("MASTER"|"BACKUP"|"FAULT")
#STATE_FILE="/var/run/keepalived.$1.$2.state"
#NOW=$(TZ='Asia/Shanghai' date)
#echo "$NOW" > $STATE_FILE
#echo -e "GROUP|INSTANCE\t\tNAME\t\tROLE\t\tPRIORITY" >> $STATE_FILE
#echo -e "$1\t\t$2\t\t$3\t\t$4" >> $STATE_FILE
# For container, we should 
echo "[`date`] State Transition: { GROUP|INSTANCE: $1, NAME: $2, ROLE: $3, PRIORITY: $4 }"
