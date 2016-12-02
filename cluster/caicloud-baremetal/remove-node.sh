#!/bin/bash

# Copyright 2014 The Kubernetes Authors All rights reserved.
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

set -o nounset

KUBE_CURRENT=$(dirname "${BASH_SOURCE}")
KUBE_ROOT="$KUBE_CURRENT/../.."

# Get cluster configuration parameters from config-default. KUBE_DISTRO
# will be available after sourcing file config-default.sh.
source "${KUBE_ROOT}/cluster/caicloud-baremetal/config-default.sh"
source "${KUBE_ROOT}/cluster/caicloud/common.sh"

# -----------------------------------------------------------------------------
# Cluster specific library utility functions.
# -----------------------------------------------------------------------------
# Verify cluster prerequisites.
function verify-prereqs {
  if [[ "${AUTOMATICALLY_INSTALL_TOOLS-}" == "YES" ]]; then
    install-ansible
  fi

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

  fetch-kubeconfig-from-master
}

# Create inventory file for ansible
#
# Make sure ansible_host is host_ip instead of hostname
#
# Assumed vars:
#   MASTER_INTERNAL_SSH_INFO
#   NODE_INTERNAL_SSH_INFO
#   KUBE_CURRENT
#
# Optional vars:
#   MASTER_EXTERNAL_SSH_INFO
#   NODE_EXTERNAL_SSH_INFO
function create-inventory-file-for-remove-node {
  if [[ -z "${MASTER_EXTERNAL_SSH_INFO-}" ]]; then
    MASTER_EXTERNAL_SSH_INFO=${MASTER_INTERNAL_SSH_INFO}
  fi
  if [[ -z "${NODE_EXTERNAL_SSH_INFO-}" ]]; then
    NODE_EXTERNAL_SSH_INFO=${NODE_INTERNAL_SSH_INFO}
  fi

  if [[ ! -d "$KUBE_CURRENT/.ansible" ]]; then
    mkdir -p $KUBE_CURRENT/.ansible
  fi

  inventory_file=$KUBE_CURRENT/.ansible/inventory
  # Set master roles
  echo "[masters]" > $inventory_file
  IFS=',' read -ra external_ssh_info <<< "${MASTER_EXTERNAL_SSH_INFO}"
  IFS=',' read -ra internal_ssh_info <<< "${MASTER_INTERNAL_SSH_INFO}"
  if [[ ! -z "${MASTER_INSTACE_ID_INFO-}" ]]; then
    IFS=',' read -ra instance_id_info <<< "${MASTER_INSTACE_ID_INFO}"
  fi
  for (( i = 0; i < ${#external_ssh_info[*]}; i++ )); do
    j=$((i+1))
    if [[ ! -z "${MASTER_INSTACE_ID_INFO-}" ]]; then
      hostname_in_ventory="${instance_id_info[$i]}"
    else
      hostname_in_ventory="${MASTER_NAME_PREFIX}${j}"
    fi
    IFS=':@' read -ra e_ssh_info <<< "${external_ssh_info[$i]}"
    IFS=':@' read -ra i_ssh_info <<< "${internal_ssh_info[$i]}"
    # External ip is used by ansible, but internal ip is used by kubernetes components
    echo "${hostname_in_ventory} ansible_host=${e_ssh_info[2]} ansible_user=${e_ssh_info[0]} ansible_ssh_pass=${e_ssh_info[1]} internal_ip=${i_ssh_info[2]}" >> $inventory_file
  done
  echo "" >> $inventory_file

  # Set etcd roles
  echo "[etcd]" >> $inventory_file
  # It's the same with masters
  for (( i = 0; i < ${#external_ssh_info[*]}; i++ )); do
    j=$((i+1))
    if [[ ! -z "${MASTER_INSTACE_ID_INFO-}" ]]; then
      hostname_in_ventory="${instance_id_info[$i]}"
    else
      hostname_in_ventory="${MASTER_NAME_PREFIX}${j}"
    fi
    IFS=':@' read -ra e_ssh_info <<< "${external_ssh_info[$i]}"
    IFS=':@' read -ra i_ssh_info <<< "${internal_ssh_info[$i]}"
    echo "${hostname_in_ventory} ansible_host=${e_ssh_info[2]} ansible_user=${e_ssh_info[0]} ansible_ssh_pass=${e_ssh_info[1]} internal_ip=${i_ssh_info[2]}" >> $inventory_file
  done
  echo "" >> $inventory_file

  ensure-kubectl-binary
  
  # Set node roles
  echo "[nodes]" >> $inventory_file
  IFS=',' read -ra external_ssh_info <<< "${NODE_EXTERNAL_SSH_INFO}"
  IFS=',' read -ra internal_ssh_info <<< "${NODE_INTERNAL_SSH_INFO}"
  current_node_info=$("${KUBE_ROOT}/cluster/kubectl.sh" get node -o template --template='{{range .items}}{{.metadata.name}}{{print ","}}{{range .status.addresses}}{{if or (eq .type "ExternalIP") (eq .type "LegacyHostIP")}}{{.address}}{{print "\n"}}{{end}}{{end}}{{end}}' | grep -v master)
  current_node_info=($current_node_info)
  for (( i = 0; i < ${#external_ssh_info[*]}; i++ )); do
    j=$((i+1))
    IFS=':@' read -ra e_ssh_info <<< "${external_ssh_info[$i]}"
    IFS=':@' read -ra i_ssh_info <<< "${internal_ssh_info[$i]}"
    found=0
    for (( j = 0; j < ${#current_node_info[*]}; j++ )); do
      IFS=',' read -ra c_node_info <<< "${current_node_info[$j]}"
      if [[ ${c_node_info[1]} == ${e_ssh_info[2]} ]]; then
        found=1
        echo "${c_node_info[0]} ansible_host=${e_ssh_info[2]} ansible_user=${e_ssh_info[0]} ansible_ssh_pass=${e_ssh_info[1]} internal_ip=${i_ssh_info[2]}" >> $inventory_file
        break
      fi
    done
    if [[ $found != 1 ]]; then
      echo "can't find node ${e_ssh_info[2]}, exit"
      exit 1
    fi
    # TODO match node name and ip.
  done
  echo "" >> $inventory_file
}

function fetch-kubeconfig-from-master {
  IFS=',' read -ra external_ssh_info <<< "${MASTER_EXTERNAL_SSH_INFO}"
  mkdir -p $HOME/.kube
  scp-from-instance-expect ${external_ssh_info[0]} "/etc/kubernetes/kubectl.kubeconfig"  $HOME/.kube/config
}

function kube-remove-nodes {
  log "+++++ Running kube-remove-nodes ..."
  (set -o posix; set)
  
  # Make sure we have:
  #  1. a staging area
  #  2. a public/private key pair used to provision instances.
  ensure-temp-dir
  ensure-ssh-agent

  if [[ "${SETUP_INSTANCES-}" == "YES" ]]; then
    setup-instances
  fi

  create-inventory-file-for-remove-node

  create-extra-vars-json-file

  remove-node-by-ansible
  ret=$?
  if [[ $ret -ne 0 ]]; then
    echo "Failed to remove nodes by ansible." >&2
    exit $ret
  fi
}

# Assumed vars:
#   KUBE_CURRENT
#   KUBE_ROOT
function remove-node-by-ansible {
  ansible-playbook -v -i $KUBE_CURRENT/.ansible/inventory --extra-vars "@$KUBE_CURRENT/.ansible/extra_vars.json" $KUBE_ROOT/cluster/caicloud-ansible/playbooks/adhoc/remove-node.yml
}

# No need to report for baremetal cluster
function report-remove-nodes {
  echo "Nothing to be reported for baremetal"
}



# Validates that old nodes are removed.
# Error codes are:
# 0 - success
# 1 - fatal (cluster is unlikely to work)
# 2 - non-fatal (encountered some errors, but cluster should be working correctly)
function validate-remove-node {
  echo "Nothing to do for now"
}
