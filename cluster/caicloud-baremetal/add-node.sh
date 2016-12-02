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

  if [[ -z "${MASTER_EXTERNAL_SSH_INFO-}" ]]; then
    MASTER_EXTERNAL_SSH_INFO=${MASTER_INTERNAL_SSH_INFO}
  fi
  if [[ -z "${NODE_EXTERNAL_SSH_INFO-}" ]]; then
    NODE_EXTERNAL_SSH_INFO=${NODE_INTERNAL_SSH_INFO}
  fi

  # ssh info used in ansible
  CAICLOUD_K8S_CFG_STRING_MASTER_NAME_PREFIX=$MASTER_NAME_PREFIX
  CAICLOUD_K8S_CFG_STRING_NODE_NAME_PREFIX=$NODE_NAME_PREFIX

  CAICLOUD_K8S_CFG_STRING_MASTER_EXTERNAL_SSH_INFO=$MASTER_EXTERNAL_SSH_INFO
  CAICLOUD_K8S_CFG_STRING_MASTER_INTERNAL_SSH_INFO=$MASTER_INTERNAL_SSH_INFO
  CAICLOUD_K8S_CFG_STRING_NODE_EXTERNAL_SSH_INFO=$NODE_EXTERNAL_SSH_INFO
  CAICLOUD_K8S_CFG_STRING_NODE_INTERNAL_SSH_INFO=$NODE_INTERNAL_SSH_INFO

  if [[ ! -z "${MASTER_INSTACE_ID_INFO-}" ]]; then
    CAICLOUD_K8S_CFG_STRING_MASTER_INSTACE_ID_INFO=$MASTER_INSTACE_ID_INFO
  fi
  if [[ ! -z "${NODE_INSTACE_ID_INFO-}" ]]; then
    CAICLOUD_K8S_CFG_STRING_NODE_INSTACE_ID_INFO=$NODE_INSTACE_ID_INFO
  fi
}

# Note: If clean-on-fail failed, nothing to do for now.
function clean-on-fail {
  log "+++++ Try clean-on-fail ..."
  ansible-playbook -v -i $KUBE_CURRENT/.ansible/inventory --extra-vars "@$KUBE_CURRENT/.ansible/extra_vars.json" $KUBE_ROOT/cluster/caicloud-ansible/playbooks/adhoc/remove-node.yml
}

function kube-add-nodes {
  log "+++++ Running kube-add-nodes ..."
  (set -o posix; set)

  set-k8s-op-install
  
  # Make sure we have:
  #  1. a staging area
  #  2. a public/private key pair used to provision instances.
  ensure-temp-dir
  ensure-ssh-agent

  if [[ "${SETUP_INSTANCES-}" == "YES" ]]; then
    setup-instances
  fi

  ensure-kubectl-binary

  create-extra-vars-json-file

  add-node-by-ansible
  ret=$?
  if [[ $ret -ne 0 ]]; then
    echo "Failed to start kubernetes by ansible." >&2
    # Nothing to do if node ip exists
    if [ -f "$KUBE_CURRENT/node_names.bashrc" ]; then
      clean-on-fail
    fi
    exit $ret
  fi
}

# Assumed vars:
#   KUBE_CURRENT
#   KUBE_ROOT
function add-node-by-ansible {
 # use in-memory inventory
 ansible-playbook -v --extra-vars "@$KUBE_CURRENT/.ansible/extra_vars.json" $KUBE_ROOT/cluster/caicloud-ansible/add-node.yml
}

# No need to report for baremetal cluster
function report-new-nodes {
  echo "Nothing to be reported for baremetal"
}

# Validates that the newly added nodes are healthy.
# Error codes are:
# 0 - success
# 1 - fatal (cluster is unlikely to work)
# 2 - non-fatal (encountered some errors, but cluster should be working correctly)
function validate-new-node {
  if [ -f "${KUBE_ROOT}/cluster/env.sh" ]; then
    source "${KUBE_ROOT}/cluster/env.sh"
  fi

  # Get current node name
  if [ -f "$KUBE_CURRENT/node_names.bashrc" ]; then
    source "$KUBE_CURRENT/node_names.bashrc"
  else
    echo "Can't load node_names.bashrc"
    exit 1
  fi

  source "${KUBE_ROOT}/cluster/lib/util.sh"
  source "${KUBE_ROOT}/cluster/kube-util.sh"

  ALLOWED_NOTREADY_NODES="${ALLOWED_NOTREADY_NODES:-0}"
  IFS=',' read -ra current_node <<< "${NODE_HOSTNAME_ARR}"
  EXPECTED_NUM_NODES="${#current_node[*]}"
  # Replace "," with "\|". e.g. i-5sff0els,i-fg0de7t5 => i-5sff0els\|i-fg0de7t5
  NODE_REGEX=${NODE_HOSTNAME_ARR//,/\\|}
  # Make several attempts to deal with slow cluster birth.
  return_value=0
  attempt=0
  while true; do
    # The "kubectl get nodes -o template" exports node information.
    #
    # Echo the output and gather 2 counts:
    #  - Total number of nodes.
    #  - Number of "ready" nodes.
    node=$("${KUBE_ROOT}/cluster/kubectl.sh" get nodes | grep -i "\b\(${NODE_REGEX}\)\b") || true
    found=$(($(echo "${node}" | wc -l))) || true
    ready=$(($(echo "${node}" | grep -v "NotReady" | wc -l ))) || true

    if (( "${found}" == "${EXPECTED_NUM_NODES}" )) && (( "${ready}" == "${EXPECTED_NUM_NODES}")); then
      break
    elif (( "${found}" > "${EXPECTED_NUM_NODES}" )) && (( "${ready}" > "${EXPECTED_NUM_NODES}")); then
      echo -e "${color_red}Detected ${ready} ready nodes, found ${found} nodes out of expected ${EXPECTED_NUM_NODES}. Found more nodes than expected, your cluster may not behave correctly.${color_norm}"
      break
    else
      # Set the timeout to ~25minutes (100 x 15 second) to avoid timeouts for 1000-node clusters.
      if (( attempt > 100 )); then
        echo -e "${color_red}Detected ${ready} ready nodes, found ${found} nodes out of expected ${EXPECTED_NUM_NODES}. Your cluster may not be fully functional.${color_norm}"
        "${KUBE_ROOT}/cluster/kubectl.sh" get nodes
        if [ "$((${EXPECTED_NUM_NODES} - ${ready}))" -gt "${ALLOWED_NOTREADY_NODES}" ]; then
          clean-on-fail
          exit 1
        else
          return_value=2
          break
        fi
      else
        echo -e "${color_yellow}Waiting for ${EXPECTED_NUM_NODES} ready nodes. ${ready} ready nodes, ${found} registered. Retrying.${color_norm}"
      fi
      attempt=$((attempt+1))
      sleep 15
    fi
  done
  echo "Found ${found} node(s)."
  "${KUBE_ROOT}/cluster/kubectl.sh" get nodes

  attempt=0
  while true; do
    # The "kubectl componentstatuses -o template" exports components health information.
    #
    # Echo the output and gather 2 counts:
    #  - Total number of componentstatuses.
    #  - Number of "healthy" components.
    cs_status=$("${KUBE_ROOT}/cluster/kubectl.sh" get componentstatuses -o template --template='{{range .items}}{{with index .conditions 0}}{{.type}}:{{.status}},{{end}}{{end}}' --api-version=v1) || true
    componentstatuses=$(echo "${cs_status}" | tr "," "\n" | grep -c 'Healthy:') || true
    healthy=$(echo "${cs_status}" | tr "," "\n" | grep -c 'Healthy:True') || true

    if ((componentstatuses > healthy)); then
      if ((attempt < 5)); then
        echo -e "${color_yellow}Cluster not working yet.${color_norm}"
        attempt=$((attempt+1))
        sleep 30
      else
        echo -e " ${color_yellow}Validate output:${color_norm}"
        "${KUBE_ROOT}/cluster/kubectl.sh" get cs
        echo -e "${color_red}Validation returned one or more failed components. Cluster is probably broken.${color_norm}"
        clean-on-fail
        exit 1
      fi
    else
      break
    fi
  done

  echo "Validate output:"
  "${KUBE_ROOT}/cluster/kubectl.sh" get cs
  if [ "${return_value}" == "0" ]; then
    echo -e "${color_green}Cluster validation succeeded${color_norm}"
  else
    echo -e "${color_yellow}Cluster validation encountered some problems, but cluster should be in working order${color_norm}"
  fi

  exit "${return_value}"
}
