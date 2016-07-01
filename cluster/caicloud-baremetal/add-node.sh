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
set -o pipefail

# Get cluster configuration parameters from config-default. KUBE_DISTRO
# will be available after sourcing file config-default.sh.
source "${KUBE_ROOT}/cluster/caicloud-baremetal/config-default.sh"
source "${KUBE_ROOT}/cluster/caicloud-baremetal/util.sh"
source "${KUBE_ROOT}/cluster/caicloud/common.sh"
source "${KUBE_ROOT}/cluster/caicloud/${KUBE_DISTRO}/helper.sh"

function kube-add-nodes {
  log "+++++ Running kube-add-nodes ..."
  (set -o posix; set)

  # Make sure we have:
  #  1. a staging area
  #  2. ssh capability
  ensure-temp-dir
  ensure-ssh-agent

  # Set up all instances. Note we are setting up master instance again to
  # copy over the public key because we might be doing scale up on a different
  # machine.
  setup-instances
  setup-baremetal-instances

  # Clean up created node if we failed after new nodes are created.
  trap-add 'clean-up-working-dir "${MASTER_SSH_EXTERNAL}" "${NODE_SSH_EXTERNAL}"' EXIT

  # We have the binaries stored at master during kube-up, so we just fetch
  # tarball from master.
  local pids=""
  install-binaries-from-master & pids="$pids $!"
  install-packages & pids="$pids $!"
  wait $pids

  # Place kubelet-kubeconfig and kube-proxy-kubeconfig in working dir.
  ssh-to-instance \
    "${MASTER_SSH_EXTERNAL}" \
    "sudo cp /etc/caicloud/kubelet-kubeconfig /etc/caicloud/kube-proxy-kubeconfig ~/kube"

  # Send node config files and start the node.
  send-node-files
  start-node-kubernetes

  source "${KUBE_ROOT}/cluster/common.sh"
  # create-kubeconfig assumes master ip is in the variable KUBE_MASTER_IP.
  # Also, in bare metal environment, we are deploying on master instance,
  # so we make sure it can find kubectl binary.
  if [[ ${USE_SELF_SIGNED_CERT} == "true" ]]; then
    KUBE_MASTER_IP="${MASTER_IIP}"
  else
    KUBE_MASTER_IP="${MASTER_DOMAIN_NAME}"
  fi

  find-kubectl-binary
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

  source "${KUBE_ROOT}/cluster/kube-env.sh"
  source "${KUBE_ROOT}/cluster/kube-util.sh"

  ALLOWED_NOTREADY_NODES="${ALLOWED_NOTREADY_NODES:-0}"
  # These env vars are for accessing apiserver and will be passed in by
  # cluster-admin
  APISERVER_ADDR=${APISERVER_ADDR:-""}
  APISERVER_USERNAME=${APISERVER_USERNAME:-""}
  APISERVER_PASSWORD=${APISERVER_PASSWORD:-""}

  EXPECTED_NUM_NODES="${NUM_NODES}"
  # Replace "," with "\|". e.g. i-5sff0els,i-fg0de7t5 => i-5sff0els\|i-fg0de7t5
  NODE_REGEX=${NODE_HOSTNAME_ARR//,/\\|}
  if [[ -z "${APISERVER_ADDR}" || -z "${APISERVER_USERNAME}" || -z "${APISERVER_PASSWORD}" ]]; then
    echo -e "${color_red}Apiserver info not provided, Can't validate new nodes...${color_norm}"
    exit 1
  fi
  # unset current context to ignore default kubeconfig files.
  "${KUBE_ROOT}/cluster/kubectl.sh" config unset current-context || true
  KUBECTL_OPTS="--server=${APISERVER_ADDR} --username=${APISERVER_USERNAME} --password=${APISERVER_PASSWORD} --insecure-skip-tls-verify"
  # Make several attempts to deal with slow cluster birth.
  return_value=0
  attempt=0
  while true; do
    # The "kubectl get nodes -o template" exports node information.
    #
    # Echo the output and gather 2 counts:
    #  - Total number of nodes.
    #  - Number of "ready" nodes.
    node=$("${KUBE_ROOT}/cluster/kubectl.sh" get nodes ${KUBECTL_OPTS} | grep -i "\b\(${NODE_REGEX}\)\b") || true
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
        "${KUBE_ROOT}/cluster/kubectl.sh" get nodes ${KUBECTL_OPTS}
        if [ "$((${EXPECTED_NUM_NODES} - ${ready}))" -gt "${ALLOWED_NOTREADY_NODES}" ]; then
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
  "${KUBE_ROOT}/cluster/kubectl.sh" get nodes ${KUBECTL_OPTS}

  attempt=0
  while true; do
    # The "kubectl componentstatuses -o template" exports components health information.
    #
    # Echo the output and gather 2 counts:
    #  - Total number of componentstatuses.
    #  - Number of "healthy" components.
    cs_status=$("${KUBE_ROOT}/cluster/kubectl.sh" get componentstatuses -o template --template='{{range .items}}{{with index .conditions 0}}{{.type}}:{{.status}},{{end}}{{end}}' --api-version=v1 ${KUBECTL_OPTS}) || true
    componentstatuses=$(echo "${cs_status}" | tr "," "\n" | grep -c 'Healthy:') || true
    healthy=$(echo "${cs_status}" | tr "," "\n" | grep -c 'Healthy:True') || true

    if ((componentstatuses > healthy)); then
      if ((attempt < 5)); then
        echo -e "${color_yellow}Cluster not working yet.${color_norm}"
        attempt=$((attempt+1))
        sleep 30
      else
        echo -e " ${color_yellow}Validate output:${color_norm}"
        "${KUBE_ROOT}/cluster/kubectl.sh" get cs ${KUBECTL_OPTS}
        echo -e "${color_red}Validation returned one or more failed components. Cluster is probably broken.${color_norm}"
        exit 1
      fi
    else
      break
    fi
  done

  echo "Validate output:"
  "${KUBE_ROOT}/cluster/kubectl.sh" get cs ${KUBECTL_OPTS}
  if [ "${return_value}" == "0" ]; then
    echo -e "${color_green}Cluster validation succeeded${color_norm}"
  else
    echo -e "${color_yellow}Cluster validation encountered some problems, but cluster should be in working order${color_norm}"
  fi

  exit "${return_value}"
}
