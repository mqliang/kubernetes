#!/bin/bash

# Copyright 2016 The Kubernetes Authors.
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

# Validates that the nodes is healthy.
# Error codes are:
# 0 - success
# 1 - fatal (cluster is unlikely to work)
# 2 - non-fatal (encountered some errors, but cluster should be working correctly)

# Input:
#   $1 hostnames of a node, for example: "kube-node-1", "kube-master"

set -o errexit
set -o nounset
set -o pipefail

validete_node_hostname=${1}

KUBE_ROOT=$(dirname "${BASH_SOURCE}")/..

if [ -f "${KUBE_ROOT}/cluster/env.sh" ]; then
  source "${KUBE_ROOT}/cluster/env.sh"
fi

source "${KUBE_ROOT}/cluster/lib/util.sh"
source "${KUBE_ROOT}/cluster/kube-util.sh"

# Run kubectl and retry upon failure.
function kubectl_retry() {
  tries=3
  while ! "${KUBE_ROOT}/cluster/kubectl.sh" "$@"; do
    tries=$((tries-1))
    if [[ ${tries} -le 0 ]]; then
      echo "('kubectl $@' failed, giving up)" >&2
      return 1
    fi
    echo "(kubectl failed, will retry ${tries} times)" >&2
    sleep 1
  done
}

EXPECTED_NUM_NODES="1"

# Make several attempts to deal with slow cluster birth.
return_value=0
attempt=0

while true; do
  # Pause between iterations of this large outer loop.
  if [[ ${attempt} -gt 0 ]]; then
    sleep 15
  fi
  attempt=$((attempt+1))

  # The "kubectl get node xxxx -o template" exports node information.
  #
  # Echo the output and check the node if it is healthy.
  #
  # Suppress errors from kubectl output because during cluster bootstrapping
  # for clusters where the master node is registered, the apiserver will become
  # available and then get restarted as the kubelet configures the docker bridge.
  node=$(kubectl_retry get node ${validete_node_hostname}) || continue
  ready=$(($(echo "${node}" | grep -v "NotReady" | wc -l ) - 1))

  if (( "${ready}" == "${EXPECTED_NUM_NODES}")); then
    break
  fi

  # Set the timeout to ~1minutes (4 x 15 second) to avoid timeouts for 1000-node clusters.
  if [[ "${attempt}" -gt "${last_run:-4}" ]]; then
    echo -e "${color_yellow}Your node \"${validete_node_hostname}\" may not be fully functional.${color_norm}"
  else
    echo -e "${color_yellow}Waiting for ${validete_node_hostname} to be ready.${color_norm}"
  fi
done

kubectl_retry get node ${validete_node_hostname}
