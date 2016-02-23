#!/bin/bash

# Copyright 2015 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Provides utility functions for talking back to cluster deployment executor.

# Sends out request based on the input url.
#
# Input:
# $1 The full url to access.
#
# Output:
# stdout: normal execution information.
# stderr: Record the url if fails.
function send-request-with-retry {
  if [[ ! -z $1 ]]; then
    local attempt=0
    local full_command="curl -sL -w %{http_code} $1 -o /dev/null"
    while true; do
      echo "Attempt ${attempt}: ${full_command}"
      local resp_code=$(${full_command})
      echo "response_code: ${resp_code}"
      if [[ ${resp_code} == "200" ]]; then
        break
      fi
      attempt=$(($attempt+1))
      if (( attempt > 3 )); then
        echo "Failed to send the following request to executor \n: $1" 1>&2
        break
      fi
      sleep $(($attempt*2))
    done
  fi
}

# Note: for the rest functions, we assume the following variables are always set.
# Vars set:
# EXECUTOR_HOST_NAME
# EXECUTION_ID
#

# Report a list of ips back to the executor for recording.
# Input:
# $1 The list of comma deliminated ips.
# $2 M or N. M indicates the ips reported belong to the master,
#    and N indicates ips are for regular nodes.
#
function report-ips {
  if [[ ${REPORT_KUBE_STATUS-} == "Y" ]]; then
    if [[ ! -z "${EXECUTOR_HOST_NAME-}" && ! -z "${EXECUTION_ID-}" ]]; then
      send-request-with-retry "$EXECUTOR_HOST_NAME/report_ips?id=${EXECUTION_ID}&ips=$1&type=$2"
    else
      echo "EXECUTOR_HOST_NAME or EXECUTION_ID is not set up. report-ips failed."
    fi
  fi
}

# Report a list of instance ids back to the executor for recording.
#
# Input:
# $1 The list of comma deliminated instance ids.
# $2 M or N. M indicates the ips reported belong to the master,
#    and N indicates ips are for regular nodes.
#
function report-instance-ids {
  if [[ ${REPORT_KUBE_STATUS-} == "Y" ]]; then
    if [[ ! -z "${EXECUTOR_HOST_NAME-}" && ! -z "${EXECUTION_ID-}" ]]; then
      send-request-with-retry "$EXECUTOR_HOST_NAME/report_instance_ids?id=${EXECUTION_ID}&instances=$1&type=$2"
    else
      echo "EXECUTOR_HOST_NAME or EXECUTION_ID is not set up. report-instance-ids failed."
    fi
  fi
}

# Report a list of security group ids back to the executor for recording.
#
# Input:
# $1 The list of comma deliminated security group ids.
# $2 M or N. M indicates the ips reported belong to the master,
#    and N indicates ips are for regular nodes.
#
function report-security-group-ids {
  if [[ ${REPORT_KUBE_STATUS-} == "Y" ]]; then
    if [[ ! -z "${EXECUTOR_HOST_NAME-}" && ! -z "${EXECUTION_ID-}" ]]; then
      send-request-with-retry "$EXECUTOR_HOST_NAME/report_security_group_ids?id=${EXECUTION_ID}&security_groups=$1&type=$2"
    else
      echo "EXECUTOR_HOST_NAME or EXECUTION_ID is not set up. report-security-group-ids failed."
    fi
  fi
}

# Report a list of external ip ids back to the executor for recording.
#
# Input:
# $1 The list of comma deliminated eip ids.
#
function report-eip-ids {
  if [[ ${REPORT_KUBE_STATUS-} == "Y" ]]; then
    if [[ ! -z "${EXECUTOR_HOST_NAME-}" && ! -z "${EXECUTION_ID-}" ]]; then
      send-request-with-retry "$EXECUTOR_HOST_NAME/report_eip_ids?id=${EXECUTION_ID}&eips=$1"
    else
      echo "EXECUTOR_HOST_NAME or EXECUTION_ID is not set up. report-eip-ids failed."
    fi
  fi
}

# Report project ID (anchnet subaccount).
function report-project-id {
  if [[ ${REPORT_KUBE_STATUS-} == "Y" ]]; then
    if [[ ! -z "${EXECUTOR_HOST_NAME-}" && ! -z "${KUBE_USER-}" ]]; then
      send-request-with-retry "$EXECUTOR_HOST_NAME/report_project_id?uid=${PROJECT_USER}&projectid=$1"
    else
      echo "EXECUTOR_HOST_NAME or KUBE_USER is not set up. report-project-id failed."
    fi
  fi
}

# Make an log.
#
# Input:
# $1 a code of LogLevelType in execution_report_collection.go
# $2 a message to log
function report-log-entry {
  message=`echo $2 | base64`
  if [[ ${REPORT_KUBE_STATUS-} == "Y" ]]; then
    if [[ ! -z "${EXECUTOR_HOST_NAME-}" && ! -z "${EXECUTION_ID-}" ]]; then
      send-request-with-retry "$EXECUTOR_HOST_NAME/log?id=${EXECUTION_ID}&level=$1&encoded_msg=$message"
    else
      echo "EXECUTOR_HOST_NAME or EXECUTION_ID is not set up. report-log-entry failed."
    fi
  fi
}

# Make a user message log. The message will be sent to end user.
#
# Input:
# $1 a message to log
function report-user-message {
  # "1" is the log level set in executor; the level means "Info" and will be sent to end user.
  report-log-entry "1" "$1"
}

# Commands for testing only
# REPORT_KUBE_STATUS="Y"
# EXECUTOR_HOST_NAME=localhost:8765
# EXECUTION_ID=55b599d0e4c2036358000003
# report-ips ip1,ip2 M
# report-ips ip1,ip2 N
# report-instance-ids master-instance,node-instance1,node-instance2 N
# report-security-group-ids sg1,sg2 M
# report-eip-ids eip1,eip2
# report-log-entry 1 msg