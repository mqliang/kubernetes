#!/bin/bash

# Copyright 2016 The Kubernetes Authors All rights reserved.
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

# -----------------------------------------------------------------------------
# Params from executor for kube-up.
# -----------------------------------------------------------------------------
MASTER_SSH_INFO=${MASTER_SSH_INFO:-"vagrant:vagrant@192.168.205.10"}
NODE_SSH_INFO=${NODE_SSH_INFO:-"vagrant:vagrant@192.168.205.11,vagrant:vagrant@192.168.205.12"}

# -----------------------------------------------------------------------------
# Environment variables passing in a json formatted string to extra-vars.
# If not seting these environment variables, It will use the default values.
#
# We will resolve the following environment variables:
#   CAICLOUD_CONFIG_XX_YY
#
# Assumed vars:
#   KUBE_CURRENT
# -----------------------------------------------------------------------------
function create-extra-vars {
  if [[ -z "${KUBE_CURRENT-}" ]]; then
    echo "KUBE_CURRENT is not been set."
    exit 1
  fi

  EXTRA_VARS_FILE="${KUBE_CURRENT}/extra_vars.json"
  touch ${EXTRA_VARS_FILE}

  echo "{" > ${EXTRA_VARS_FILE}

  OLDIFS=$IFS
  # resolve CAICLOUD_CONFIG_XX_YY environment variables.
  set | grep "^CAICLOUD_K8S_CFG_*" | \
  while read line; do
    IFS='=' read -ra var_array <<< "${line}"
    # Get XX_YY and change into lowercase: xx_yy
    var_name=$(echo ${var_array[0]#CAICLOUD_K8S_CFG_} | tr '[:upper:]' '[:lower:]')
    echo "  \"${var_name}\": ${var_array[1]}," >> ${EXTRA_VARS_FILE}
  done
  IFS=$OLDIFS

  # Remove the trailing comma
  sed -i -zr 's/,([^,]*$)/\1/' ${EXTRA_VARS_FILE}

  echo "}" >> ${EXTRA_VARS_FILE}
}

# -----------------------------------------------------------------------------
# Derived params for kube-up (calculated based on above params: DO NOT CHANGE).
# If above configs are changed manually, remember to call the function.
# -----------------------------------------------------------------------------
function calculate-default {
  INSTANCE_SSH_EXTERNAL="${MASTER_SSH_INFO},${NODE_SSH_INFO}"

  # We will install kubelet on masters and nodes, so they will all be considered as nodes.
  IFS=',' read -ra ssh_info <<< "${INSTANCE_SSH_EXTERNAL}"
  export NUM_NODES=${#ssh_info[@]}
}

calculate-default
