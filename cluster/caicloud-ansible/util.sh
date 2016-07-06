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

# In kube-up.sh, bash is set to exit on error. However, we need to retry
# on error. Therefore, we disable errexit here.
set +o errexit

KUBE_CURRENT=$(dirname "${BASH_SOURCE}")
KUBE_ROOT="$KUBE_CURRENT/../.."

# Get cluster configuration parameters from config-default.
source "${KUBE_ROOT}/cluster/caicloud-ansible/config-default.sh"
source "${KUBE_ROOT}/cluster/caicloud/common.sh"

# -----------------------------------------------------------------------------
# Cluster specific library utility functions.
# -----------------------------------------------------------------------------
# Verify cluster prerequisites.
function verify-prereqs {
  # Check needed binaries
  needed_binaries=("expect" "ansible" "ansible-playbook" "sshpass" "netaddr")
  for binary in ${needed_binaries[@]}; do
    if [[ `eval which ${binary}` == "" ]]; then
      log "Can't find ${binary} binary in PATH, please fix and retry."
      exit 1
    fi
  done

  # Make sure we have set MASTER_SSH_INFO and NODE_SSH_INFO
  if [[ "$MASTER_SSH_INFO" == "" ]]; then
    log "MASTER_SSH_INFO is not been set."
    exit 1
  fi
  if [[ "$NODE_SSH_INFO" == "" ]]; then
    log "NODE_SSH_INFO is not been set."
    exit 1
  fi
}

# Instantiate a kubernetes cluster
function kube-up {
  # Print all environment and local variables at this point.
  log "+++++ Running kube-up with variables ..."
  set -o posix; set

  # Make sure we have:
  #  1. a staging area
  #  2. a public/private key pair used to provision instances.
  ensure-temp-dir
  ensure-ssh-agent

  setup-instances

  create-inventory-file
  create-extra-vars-json-file

  start-kubernetes-by-ansible
}

# Delete a kubernetes cluster
function kube-down {
  # Todo
  :
}
