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

# Source env if exists
if [[ -f /addon-manager/env.sh ]]; then
  source /addon-manager/env.sh
fi

if [[ ! -d /addon-manager/configmap ]]; then
  mkdir -p /addon-manager/configmap
fi

# Generate configmap from cfg
if [[ "${GENERATE_CONFIGMAP-}" == "true" ]]; then
  if [[ -f /addon-manager/configmap.cfg && -f /addon-manager/configmap-template.yaml ]]; then
    build-scripts
  else
    echo "configmap.cfg or configmap-template.yaml not found" >&2
    exit 1
  fi
fi

if [[ "${CAICLOUD_K8S_CFG_STRING_DEPLOY_CAICLOUD_STACK-}" == "true" ]]; then
  # Check secret
  if [[ ! -f /addon-manager/cds-executor-secret.yaml ]]; then
    echo "cds executor secret not found" >&2
    exit 1
  fi

  # Check configmap
  if [[ "${CAICLOUD_K8S_CFG_NUMBER_GENERATE_CONFIGMAP-}" != "true" ]]; then
    if [[ ! -f /addon-manager/configmap.yaml ]]; then
      echo "configmap not found" >&2
      exit 1
    fi
  fi
fi

KUBE_CURRENT=$(dirname "${BASH_SOURCE}")
KUBE_ROOT="$KUBE_CURRENT/../.."

# Get cluster configuration parameters from config-default.
source "${KUBE_ROOT}/cluster/caicloud-baremetal/config-default.sh"
source "${KUBE_ROOT}/cluster/caicloud/common.sh"
source "${KUBE_ROOT}/cluster/lib/util.sh"

# -----------------------------------------------------------------------------
# Cluster specific library utility functions.
# -----------------------------------------------------------------------------
# Verify cluster prerequisites.
function verify-prereqs {
  if [[ "${AUTOMATICALLY_INSTALL_TOOLS-}" == "YES" ]]; then
    install-ansible
  fi

  # Check needed binaries
  if [[ `uname` != "Darwin" ]]; then
    needed_binaries=("expect" "ansible" "ansible-playbook" "sshpass" "netaddr")
    for binary in ${needed_binaries[@]}; do
      if [[ `eval which ${binary}` == "" ]]; then
        log "${color_red}Can't find ${binary} binary in PATH, please fix and retry.${color_norm}"
        exit 1
      fi
    done
  fi

  # Make sure we have set MASTER_SSH_INFO
  if [[ "$MASTER_SSH_INFO" == "" ]]; then
    log "${color_red}MASTER_SSH_INFO is not been set.${color_norm}"
    exit 1
  fi

  mkdir -p ${KUBE_CURRENT}/.ansible
}

# Verify cluster prerequisites for upgrade/downgrade.
function op-verify-prereqs {
  if [[ "${OP_MASTER_SSH_INFO-}" == "" ]] && [[ "${OP_NODE_SSH_INFO-}" == "" ]]; then
    log "${color_red}OP_MASTER_SSH_INFO or OP_NODE_SSH_INFO is not been set.${color_norm}"
    exit 1
  fi

  op-fetch-kubectl
}

# Instantiate a kubernetes cluster.
function kube-up {
  # Make sure we have set NODE_SSH_INFO
  if [[ "$NODE_SSH_INFO" == "" ]]; then
    log "${color_red}NODE_SSH_INFO is not been set.${color_norm}"
    exit 1
  fi

  # Print all environment and local variables at this point.
  log "+++++ Running kube-up with variables ..."
  set -o posix; set

  set-k8s-op-install

  # Make sure we have:
  #  1. a staging area
  #  2. a public/private key pair used to provision instances.
  ensure-temp-dir
  ensure-ssh-agent

  if [[ "${SETUP_INSTANCES-}" == "YES" ]]; then
    setup-instances
  fi

  set-kubectl-path

  create-inventory-file
  create-extra-vars-json-file
  save-extra-vars-json-file

  start-kubernetes-by-ansible
  ret=$?
  if [[ $ret -ne 0 ]]; then
    log "${color_red}Failed to start kubernetes by ansible.${color_norm}"
    exit $ret
  fi
}

# Delete a kubernetes cluster.
function kube-down {
  # Make sure we have set NODE_SSH_INFO
  if [[ "$NODE_SSH_INFO" == "" ]]; then
    log "NODE_SSH_INFO is not been set."
    exit 1
  fi

  set-k8s-op-uninstall
  create-inventory-file
  create-extra-vars-json-file
  clear-kubernetes-by-ansible
}

# Compare the version to check if it can upgrade.
function can-upgrade {
  if [[ "${CAICLOUD_K8S_CFG_STRING_KUBE_CAICLOUD_VERSION-}" == "" ]]; then
    log "${color_red}You need to choose the right version for upgrading by 'CAICLOUD_K8S_CFG_STRING_KUBE_CAICLOUD_VERSION'${color_norm}"
    log "${color_red}Optionally, you can change the base image version by 'CAICLOUD_K8S_CFG_STRING_KUBE_BASE_VERSION'${color_norm}"
    exit 1
  fi
  
  current_caicloud_version=`get-kubectl-version "Server Version"`

  res_comp=`version_compare ${CAICLOUD_K8S_CFG_STRING_KUBE_CAICLOUD_VERSION#v} ${current_caicloud_version#v}`

  if [[ ${res_comp} -eq 1 ]]; then
    log "${color_green}Current version: ${current_caicloud_version}, prepare to upgrade to the new version: ${CAICLOUD_K8S_CFG_STRING_KUBE_CAICLOUD_VERSION}${color_norm}"
  else
    log "${color_red}Current version: ${current_caicloud_version}, couldn't upgrade to version ${CAICLOUD_K8S_CFG_STRING_KUBE_CAICLOUD_VERSION}${color_norm}"
    exit 1
  fi
}

# Upgrade kubernetes nodes.
function kube-upgrade {
  can-upgrade
  set-k8s-op-upgrade

  ensure-ssh-agent
  if [[ "${SETUP_INSTANCES-}" == "YES" ]]; then
    op-setup-instances
  fi

  op-create-inventory-file
  create-extra-vars-json-file
  do-op-by-ansible
  ret=$?
  if [[ $ret -ne 0 ]]; then
    log "${color_red}Failed to upgrade nodes by ansible.${color_norm}"
    exit $ret
  fi
}

# Downgrade kubernetes nodes.
function kube-downgrade {
  set-k8s-op-downgrade
  op-create-inventory-file
  create-extra-vars-json-file
  do-op-by-ansible
  ret=$?
  if [[ $ret -ne 0 ]]; then
    log "${color_red}Failed to downgrade nodes by ansible.${color_norm}"
    exit $ret
  fi
}


# Validate nodes after upgraded.
function validate-nodes {
  get-hostname-from-op-inventory
  
  IFS=',' read -ra nodes_array <<< "${HOSTNAME_FROM_INVENTORY_FILE}"
  for (( i = 0; i < ${#nodes_array[*]}; i++ )); do
    ${KUBE_ROOT}/cluster/validate-node.sh "${nodes_array[$i]}"
  done
}

# Find master to work with.
function detect-master {
  export KUBE_MASTER_IP=${KUBE_MASTER_IP:-"cluster.caicloudprivatetest.com"}
  export KUBE_MASTER=${KUBE_MASTER:-"cluster.caicloudprivatetest.com"}
}

# Execute prior to running tests to build a release if required for env.
function test-build-release {
  log "Running test-build-release for ansible"
  # Make sure we have a sensible version.
  source ${KUBE_ROOT}/hack/caicloud/common.sh
  export KUBE_GIT_VERSION="${K8S_VERSION}+caicloud-ansible-e2e"
  export KUBE_GIT_TREE_STATE="clean"
  caicloud-build-local
}
