#!/bin/bash

#
# Check if the machine has the ip: WAITING_CHECK_IP.
#
# Assumed vars:
#   WAITING_CHECK_IP

local_ips=`ip addr show |grep "inet " | awk -F ' ' '{print $2}' | awk -F '/' '{print $1}'`

for ip in ${local_ips}; do
  if [[ "${ip}" == "${WAITING_CHECK_IP}" ]]; then
    echo "Found: YES"
    exit
  fi
done

echo "Found: NO"
