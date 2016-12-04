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
AUTOMATICALLY_INSTALL_TOOLS=${AUTOMATICALLY_INSTALL_TOOLS-"YES"}
ANSIBLE_VERSION=${ANSIBLE_VERSION-"2.1.0.0"}

# Ansible environment variable prefix.
# Used by create-extra-vars-json-file-common function.
K8S_STRING_PREFIX="CAICLOUD_K8S_CFG_STRING_"
K8S_NUMBER_PREFIX="CAICLOUD_K8S_CFG_NUMBER_"

# For the option --hostname-override
# Used by create-inventory-file in caicloud/common.sh
MASTER_NAME_PREFIX=${MASTER_NAME_PREFIX-"kube-master-"}
NODE_NAME_PREFIX=${NODE_NAME_PREFIX-"kube-node-"}

CLUSTER_NAME=${CLUSTER_NAME-"kube-default"}

DNS_HOST_NAME=${DNS_HOST_NAME-"caicloudstack"}

# Setup instances or not.
SETUP_INSTANCES=${SETUP_INSTANCES-"YES"}

SSH_PRIVATE_KEY_FILE=${SSH_PRIVATE_KEY_FILE-"$HOME/.ssh/id_rsa"}
SSH_PUBLIC_KEY_FILE=${SSH_PUBLIC_KEY_FILE-"$SSH_PRIVATE_KEY_FILE.pub"}

CAICLOUD_K8S_CFG_STRING_KUBECTL_SH=${CAICLOUD_K8S_CFG_STRING_BIN_DIR-'/usr/bin'}/kubectl

CAICLOUD_K8S_CFG_STRING_KUBE_CURRENT=$KUBE_CURRENT

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

  if [[ ! -z "${CLUSTER_NAME-}" ]]; then
    CAICLOUD_K8S_CFG_STRING_CLUSTER_NAME=${CLUSTER_NAME}
  fi

  if [[ ! -z "${BASE_DOMAIN_NAME-}" ]]; then
    CAICLOUD_K8S_CFG_STRING_BASE_DOMAIN_NAME=${BASE_DOMAIN_NAME}
  fi

  if [[ ! -z "${USER_CERT_DIR-}" ]]; then
    # Remove the last '/'
    CAICLOUD_K8S_CFG_STRING_USER_CERT_DIR=${USER_CERT_DIR%/}
  fi

  if [[ ! -z "${LOAD_BALANCER_VIP-}" ]]; then
    CAICLOUD_K8S_CFG_STRING_LOAD_BALANCER_VIP=${LOAD_BALANCER_VIP}
  fi

  if [[ ! -z "${USE_HYPERKUBE-}" ]]; then
    CAICLOUD_K8S_CFG_NUMBER_USE_HYPERKUBE=${USE_HYPERKUBE}
  fi

  CAICLOUD_K8S_CFG_STRING_KUBERNETES_PROVIDER=${KUBERNETES_PROVIDER}
}

calculate-default

function set-kubectl-path {
  if [[ -z "${CAICLOUD_K8S_CFG_STRING_BIN_DIR-}" ]]; then
    # Needed to match with "{{ bin_dir }} of ansible"
    export KUBECTL_PATH="/usr/bin/kubectl"
  else
    # Install kubectl to CAICLOUD_K8S_CFG_STRING_BIN_DIR
    export KUBECTL_PATH="${CAICLOUD_K8S_CFG_STRING_BIN_DIR}/kubectl"
  fi
}

function set-k8s-op-install {
  CAICLOUD_K8S_CFG_STRING_K8S_OP="OP_INSTALL"
}

function set-k8s-op-uninstall {
  CAICLOUD_K8S_CFG_STRING_K8S_OP="OP_UNINSTALL"
}

function set-k8s-op-upgrade {
  CAICLOUD_K8S_CFG_STRING_K8S_OP="OP_UPGRADE"
}

function set-k8s-op-downgrade {
  CAICLOUD_K8S_CFG_STRING_K8S_OP="OP_DOWNGRADE"
}

function op-fetch-kubectl {
  if [[ "${CAICLOUD_K8S_CFG_STRING_CONTROL_MACHINE_IS_MASTER:-NO}" == "NO" ]]; then
    if [[ `which kubectl 1>/dev/null 2>&1; echo $?` -ne 0 ]]; then
      fetch-kubectl-binary
    else
      export KUBECTL_PATH=`which kubectl`
    fi
    fetch-kubeconfig-from-master
  fi
}

# Following may move to caicloud/common.sh

# Ensure apiserver domain can be resolved. May not work on multi-master
# Not work in Pod
function ensure-apiserver-hosts {
  if [[ -z "${DNS_HOST_NAME-}" ]]; then
    DNS_HOST_NAME="cluster"
  fi

  if [[ -z "${BASE_DOMAIN_NAME-}" ]]; then
    BASE_DOMAIN_NAME="caicloudprivatetest.com"
  fi

  apiserver_domain=${DNS_HOST_NAME}.${BASE_DOMAIN_NAME}
  IFS=',' read -ra external_ssh_info <<< "${MASTER_EXTERNAL_SSH_INFO}"
  IFS=':@' read -ra e_ssh_info <<< "${external_ssh_info[0]}"
  apiserver_ip=${e_ssh_info[2]}

  found_hosts=`cat /etc/hosts | grep "${apiserver_domain}" | grep "${apiserver_ip}" | wc -l`

  if [[ $found_hosts == 0 ]]; then
    echo "Add hosts ${apiserver_ip} ${apiserver_domain}"
    # remove wrong hosts
    sed -i "/${apiserver_domain}/d" /etc/hosts
    echo "${apiserver_ip} ${apiserver_domain}" >> /etc/hosts
  fi
}

# Ensure kubectl binary exist in KUBECTL_PATH
function ensure-kubectl-binary {
  find-kubectl-binary
  # If cann't find kubectl binary, we need to fetch it from master node.
  if [[ -z "${KUBECTL_PATH-}" ]]; then
    # Assume on linux amd64
    locations=(
      "${KUBE_ROOT}/_output/dockerized/bin/linux/amd64/kubectl"
      "${KUBE_ROOT}/_output/local/bin/linux/amd64/kubectl"
      "${KUBE_ROOT}/platforms/linux/amd64/kubectl"
    )
    kubectl=$( (ls -t "${locations[@]}" 2>/dev/null || true) | head -1 )
    if [[ ! -x "$kubectl" ]]; then
      export KUBECTL_PATH="${CAICLOUD_K8S_CFG_STRING_BIN_DIR-'/usr/bin'}/kubectl"
      ansible-playbook -v -i $KUBE_CURRENT/.ansible/inventory --extra-vars "fetch_kubectl_binary=1 bin_dir=${CAICLOUD_K8S_CFG_STRING_BIN_DIR-'/usr/bin'}" $KUBE_ROOT/cluster/caicloud-ansible/playbooks/adhoc/fetch-kubectl.yml
      ret=$?
      if [[ $ret -ne 0 ]]; then
        echo "Failed to fetch kubectl binary by ansible." >&2
        exit 1
      fi
    else
      export CAICLOUD_K8S_CFG_STRING_KUBECTL_SH="$(pwd)/$kubectl"
      export KUBECTL_PATH=$kubectl
    fi
  else
    export CAICLOUD_K8S_CFG_STRING_KUBECTL_SH="$KUBECTL_PATH"
  fi
}
