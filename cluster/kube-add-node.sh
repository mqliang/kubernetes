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

# Add new node(s) to a running kubernetes cluster. This script assumes that
# master already stores necessary files/packages to bring up a new node. To
# be specific, the following should exist on master:
#
#   /etc/caicloud/caicloud-kube.tar.gz    -- caicloud kubernetes related binaries.
#   /etc/caicloud/kubelet-kubeconfig      -- config needed by kubelet to access master
#   /etc/caicloud/kube-proxy-kubeconfig   -- config needed by kube-proxy to access master
#
# The number of new nodes to add equals to ${NUM_MINIONS}.
#
# New versions of kube-up will place these files at the right location during
# kube-up. The binaries tarball should also be updated when we upgrade cluster.
set -o nounset
set -o pipefail

KUBE_ROOT=$(dirname "${BASH_SOURCE}")/..

PROVIDER_ADD_NODE_UTILS="${KUBE_ROOT}/cluster/${KUBERNETES_PROVIDER}/add-node.sh"
if [ -f ${PROVIDER_ADD_NODE_UTILS} ]; then
	source "${PROVIDER_ADD_NODE_UTILS}"
fi

source "${KUBE_ROOT}/cluster/kube-env.sh"

echo "... Creating new instances using provider: $KUBERNETES_PROVIDER" >&2

echo "... calling verify-prereqs" >&2
verify-prereqs

echo "... calling kube-add-nodes" >&2
kube-add-nodes

echo "... calling report-new-nodes" >&2
report-new-nodes

# still need to validate cluster after scaling up
echo "... calling validate-cluster" >&2

# Override errexit
(validate-new-node) && validate_result="$?" || validate_result="$?"

# We have two different failure modes from validate cluster:
# - 1: fatal error - cluster won't be working correctly
# - 2: weak error - something went wrong, but cluster probably will be working correctly
# We always exit in case 1), but if EXIT_ON_WEAK_ERROR != true, then we don't fail on 2).
if [[ "${validate_result}" == "1" ]]; then
  exit 1
elif [[ "${validate_result}" == "2" ]]; then
  if [[ "${EXIT_ON_WEAK_ERROR}" == "true" ]]; then
    exit 1;
  else
    echo "...ignoring non-fatal errors in validate-cluster" >&2
  fi
fi

exit 0
