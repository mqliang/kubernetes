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

# Ansible 1.2.1 and later have host key checking enabled by default.
# If a host is reinstalled and has a different key in ‘known_hosts’, this will
# result in an error message until corrected. If a host is not initially in
# ‘known_hosts’ this will result in prompting for confirmation of the key,
# which results in an interactive experience if using Ansible, from say, cron.
# You might not want this.
export ANSIBLE_HOST_KEY_CHECKING=False

# Use posix environment.
export LC_ALL="C"
export LANG="C"

# Default: automatically install ansible and dependencies.
AUTOMATICALLY_INSTALL_ANSIBLE=${AUTOMATICALLY_INSTALL_ANSIBLE-"YES"}
ANSIBLE_VERSION=${ANSIBLE_VERSION-"2.1.0.0"}

# Ansible environment variable prefix.
STRING_PREFIX="CAICLOUD_K8S_CFG_STRING_"
NUMBER_PREFIX="CAICLOUD_K8S_CFG_NUMBER_"

# -----------------------------------------------------------------------------
# Derived params for kube-up (calculated based on above params: DO NOT CHANGE).
# If above configs are changed manually, remember to call the function.
# -----------------------------------------------------------------------------
function calculate-default {
  if [[ -z "${MASTER_INTERNAL_SSH_INFO-}" ]]; then
    MASTER_INTERNAL_SSH_INFO=${MASTER_SSH_INFO}
  fi
  if [[ -z "${MASTER_EXTERNAL_SSH_INFO-}" ]]; then
    MASTER_EXTERNAL_SSH_INFO=${MASTER_INTERNAL_SSH_INFO}
  fi
  if [[ -z "${NODE_INTERNAL_SSH_INFO-}" ]]; then
    NODE_INTERNAL_SSH_INFO=${NODE_SSH_INFO}
  fi
  if [[ -z "${NODE_EXTERNAL_SSH_INFO-}" ]]; then
    NODE_EXTERNAL_SSH_INFO=${NODE_INTERNAL_SSH_INFO}
  fi

  INSTANCE_SSH_EXTERNAL="${MASTER_EXTERNAL_SSH_INFO},${NODE_EXTERNAL_SSH_INFO}"

  IFS=',' read -ra ssh_info <<< "${INSTANCE_SSH_EXTERNAL}"
  export NUM_NODES=${#ssh_info[@]}

  if [[ ! -z "${DNS_HOST_NAME-}" ]]; then
    CAICLOUD_K8S_CFG_STRING_DNS_HOST_NAME=${DNS_HOST_NAME}
  fi

  if [[ ! -z "${BASE_DOMAIN_NAME-}" ]]; then
    CAICLOUD_K8S_CFG_STRING_BASE_DOMAIN_NAME=${BASE_DOMAIN_NAME}
  fi

  if [[ ! -z "${USER_CERT_DIR-}" ]]; then
    # Remove the last '/'
    CAICLOUD_K8S_CFG_STRING_USER_CERT_DIR=${USER_CERT_DIR%/}
  fi

  # Now only support single master
  # Todo: support multi-master
  CAICLOUD_K8S_CFG_STRING_KUBE_MASTER_IP=${MASTER_SSH_INFO#*@}
}

calculate-default

# Telling ansible to fetch kubectl from master.
# Need to run before create-extra-vars-json-file function.
function fetch-kubectl-binary {
  CAICLOUD_K8S_CFG_NUMBER_FETCH_KUBECTL_BINARY=1

  if [[ -z "${CAICLOUD_K8S_CFG_STRING_BIN_DIR-}" ]]; then
    # Needed to match with "{{ bin_dir }} of ansible"
    export KUBECTL_PATH="/usr/bin/kubectl"
  else
    # Ansible will fetch kubectl binary to bin_dir from master
    export KUBECTL_PATH="${CAICLOUD_K8S_CFG_STRING_BIN_DIR}/kubectl"
  fi
}
