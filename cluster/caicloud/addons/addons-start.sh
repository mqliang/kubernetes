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

# The script is supposed to run at master instance to create addons.
# It looks for environment variables for enabling/disabling addons, e.g.
# ENABLE_CLUSTER_DNS, ENABLE_CLUSTER_LOGGING, etc, see config-default.sh.
# It is assumed that required addons yaml files are copied to ~/kube
# directory.

set -o errexit
set -o nounset
set -o pipefail

ENABLE_KUBE_SYSTEM_QUOTA=${ENABLE_KUBE_SYSTEM_QUOTA:-true}
ENABLE_CLUSTER_DNS=${ENABLE_CLUSTER_DNS:-false}
ENABLE_CLUSTER_LOGGING=${ENABLE_CLUSTER_LOGGING:-false}
ENABLE_CLUSTER_MONITORING=${ENABLE_CLUSTER_MONITORING:-false}
ENABLE_CLUSTER_REGISTRY=${ENABLE_CLUSTER_REGISTRY:-false}
SYSTEM_NAMESPACE=${SYSTEM_NAMESPACE:-"kube-system"}
MASTER_INSECURE_ADDRESS=${MASTER_INSECURE_ADDRESS:-"127.0.0.1"}
MASTER_INSECURE_PORT=${MASTER_INSECURE_PORT:-"8080"}

# Do retries when failing in objects creation from yaml files. It
# is assumed kubectl exists, i.e. /opt/bin/kubectl.
#
# Input:
#   $1 path to yaml file
#   $2 max retries
#   $3 delay between retries
#   $4 namespace in which the object should be created
function create-resource-from-file {
  config_file=$1
  tries=$2
  delay=$3
  namespace=$4
  while [ ${tries} -gt 0 ]; do
    /opt/bin/kubectl --server="${MASTER_INSECURE_ADDRESS}:${MASTER_INSECURE_PORT}" \
                     --namespace="${namespace}" create -f "${config_file}" && \
      echo "== Successfully started ${config_file} in namespace ${namespace} at $(date -Is)" && \
      return 0;
    let tries=tries-1;
    echo "== Failed to start ${config_file}. ${tries} tries remaining. =="
    sleep ${delay};
  done
  return 1;
}

function create-kube-system-namespace {
  # Update system namespace if it already exists. We used to delete kube-system namespace and recreate it,
  # but now kube-system is created by default and is protected from being deleted (scripts will just error
  # out if we try to delete it). So we switch to 'kubectl apply -f' here.
  /opt/bin/kubectl apply -f ~/kube/namespace.yaml --server="${MASTER_INSECURE_ADDRESS}:${MASTER_INSECURE_PORT}"
}

function create-kube-system-quota {
  create-resource-from-file ~/kube/quota.yaml 100 10 "${SYSTEM_NAMESPACE}"
}

function create-kube-system-limit-range {
  create-resource-from-file ~/kube/limitrange.yaml 100 10 "${SYSTEM_NAMESPACE}"
}

function create-dns-addon {
  for obj in $(find ~/kube/addons/dns -type f -name \*.yaml -o -name \*.json); do
    create-resource-from-file ${obj} 10 10 "${SYSTEM_NAMESPACE}"
  done
}

function create-logging-addon {
  for obj in $(find ~/kube/addons/logging -type f -name \*.yaml -o -name \*.json); do
    create-resource-from-file ${obj} 10 10 "${SYSTEM_NAMESPACE}"
  done
}

function create-monitoring-addon {
  for obj in $(find ~/kube/addons/monitoring -type f -name \*.yaml -o -name \*.json); do
    create-resource-from-file ${obj} 10 10 "${SYSTEM_NAMESPACE}"
  done
}

function create-registry-addon {
  for obj in $(find ~/kube/addons/registry -type f -name \*.yaml -o -name \*.json); do
    create-resource-from-file ${obj} 10 10 "${SYSTEM_NAMESPACE}"
  done
}


create-kube-system-namespace
create-kube-system-quota
create-kube-system-limit-range

if [[ "${ENABLE_CLUSTER_DNS}" == "true" ]]; then
  create-dns-addon
fi

if [[ "${ENABLE_CLUSTER_LOGGING}" == "true" ]]; then
  create-logging-addon
fi

if [[ "${ENABLE_CLUSTER_MONITORING}" == "true" ]]; then
  create-monitoring-addon
fi

if [[ "${ENABLE_CLUSTER_REGISTRY}" == "true" ]]; then
  create-registry-addon
fi
