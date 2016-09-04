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
source "${KUBE_ROOT}/cluster/lib/util.sh"
source "${KUBE_ROOT}/cluster/caicloud-aliyun/config-default.sh"
source "${KUBE_ROOT}/cluster/caicloud/common.sh"

function create-extra-vars-json-file-aliyun {
  create-extra-vars-json-file-common ${KUBE_CURRENT}/extra_vars.aliyun.json ${ALIYUN_STRING_PREFIX} ${ALIYUN_NUMBER_PREFIX}
}

function aliyun-instances-up {
  ansible-playbook -v --extra-vars "@$KUBE_CURRENT/extra_vars.aliyun.json" $KUBE_CURRENT/run.yml
  if [[ $? != 0 ]]; then
    exit 1
  fi
}

function aliyun-instances-down {
  ansible-playbook -v --extra-vars "@$KUBE_CURRENT/extra_vars.aliyun.json" $KUBE_CURRENT/delete.yml
  if [[ $? != 0 ]]; then
    exit 1
  fi
}

# Get ssh info from aliyun instances.
function get-aliyun-instances-ssh-info {
  ansible-playbook -v --extra-vars "@$KUBE_CURRENT/extra_vars.aliyun.json" $KUBE_CURRENT/get.yml
  if [[ $? != 0 ]]; then
    exit 1
  fi
}

# Install aliyuncli tool
function install-aliyuncli {
  ansible-playbook -v $KUBE_CURRENT/install-aliyuncli.yml
  if [[ $? != 0 ]]; then
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# Cluster specific library utility functions.
# -----------------------------------------------------------------------------
# Verify cluster prerequisites.
function verify-prereqs {
  if [[ "${AUTOMATICALLY_INSTALL_TOOLS-}" == "YES" ]]; then
    install-ansible
    install-ntpdate
    install-aliyuncli
  fi

  # Check needed binaries
  needed_binaries=("expect" "ansible" "ansible-playbook" "sshpass" "netaddr")
  for binary in ${needed_binaries[@]}; do
    if [[ `eval which ${binary}` == "" ]]; then
      log "Can't find ${binary} binary in PATH, please fix and retry."
      exit 1
    fi
  done

  # Make sure we have set ACCESS_KEY_ID and ACCESS_KEY_SECRET
  if [[ "$ACCESS_KEY_ID" == "" ]]; then
    log "ACCESS_KEY_ID is not been set."
    exit 1
  fi
  if [[ "$ACCESS_KEY_SECRET" == "" ]]; then
    log "ACCESS_KEY_SECRET is not been set."
    exit 1
  fi  
}

# Instantiate a kubernetes cluster
function kube-up {
  # Creating aliyun instances
  aliyun-instance-up-prelogue
  create-extra-vars-json-file-aliyun
  aliyun-instances-up
  aliyun-instance-epilogue

  report-ips-to-executor

  # Print all environment and local variables at this point.
  log "+++++ Running kube-up with variables ..."
  set -o posix; set

  # Make sure we have:
  #  1. a staging area
  #  2. a public/private key pair used to provision instances.
  ensure-temp-dir
  ensure-ssh-agent

  setup-instances

  find-kubectl-binary
  # If cann't find kubectl binary, we need to fetch it from master node.
  if [[ -z "${KUBECTL_PATH-}" ]]; then
    fetch-kubectl-binary
  fi

  create-inventory-file
  create-extra-vars-json-file

  start-kubernetes-by-ansible
  ret=$?
  if [[ $ret -ne 0 ]]; then
    echo "Failed to start kubernetes by ansible." >&2
    exit $ret
  fi
}

# Delete a kubernetes cluster
function kube-down {
  aliyun-instance-down-prelogue
  create-extra-vars-json-file-aliyun

  if [[ ${DELETE_INSTANCE_FLAG} == "NO" ]]; then
    get-aliyun-instances-ssh-info
    aliyun-instance-epilogue
    create-inventory-file
    create-extra-vars-json-file
    clear-kubernetes-by-ansible
  else
    # Try to deleting aliyun instances
    aliyun-instances-down
  fi
}
