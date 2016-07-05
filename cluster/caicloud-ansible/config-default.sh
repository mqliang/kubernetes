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
# Derived params for kube-up (calculated based on above params: DO NOT CHANGE).
# If above configs are changed manually, remember to call the function.
# -----------------------------------------------------------------------------
function calculate-default {
  INSTANCE_SSH_EXTERNAL="${MASTER_SSH_INFO},${NODE_SSH_INFO}"

  IFS=',' read -ra ssh_info <<< "${INSTANCE_SSH_EXTERNAL}"
  export NUM_NODES=${#ssh_info[@]}

  if [[ -z "${CLUSTER_VIP-}" ]]; then
    IFS=',' read -ra ssh_info <<< "${MASTER_SSH_INFO}"
    NUM_MASTERS=${#ssh_info[@]}
    if [[ $NUM_MASTERS -gt 1 ]]; then
      echo "Warning: you have ${NUM_MASTERS} masters, but you don't set CLUSTER_VIP environment variable."
    fi
    # We will use the ip of the first master
    first_master_ssh_info=${MASTER_SSH_INFO%%,*}
    CLUSTER_VIP=${first_master_ssh_info#*@}
  fi

  CAICLOUD_K8S_CFG_CLUSTER_VIP=${CLUSTER_VIP}
}

calculate-default
