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

CAICLOUD_CUSTOMER=${CAICLOUD_CUSTOMER:-""}
if [[ -z "${CAICLOUD_CUSTOMER}" ]]; then
  echo "Error: CAICLOUD_CUSTOMER must be set." >&2
  exit 1
else
  customer_config_file="${KUBE_CURRENT}/customers/${CAICLOUD_CUSTOMER}/config-${CAICLOUD_CUSTOMER}.sh"
  if [[ ! -f "${customer_config_file}" ]]; then
    echo "Error: cann't find ${customer_config_file}"
    exit 1
  fi
  source "${customer_config_file}"
fi

# Get cluster configuration parameters from config-default.
source "${KUBE_ROOT}/cluster/lib/util.sh"
source "${KUBE_ROOT}/cluster/caicloud-private-aliyun/config-default.sh"
source "${KUBE_ROOT}/cluster/caicloud/common.sh"

function create-extra-vars-json-file-aliyun {
  if [[ ! -d "$KUBE_CURRENT/.ansible" ]]; then
    mkdir -p $KUBE_CURRENT/.ansible
  fi

  create-extra-vars-json-file-common ${KUBE_CURRENT}/.ansible/extra_vars.aliyun.json ${ALIYUN_STRING_PREFIX} ${ALIYUN_NUMBER_PREFIX}
}

function aliyun-instances-up {
  ansible-playbook -v --extra-vars "@$KUBE_CURRENT/.ansible/extra_vars.aliyun.json" $KUBE_CURRENT/run.yml
  if [[ $? != 0 ]]; then
    exit 1
  fi
}

function aliyun-instances-down {
  ansible-playbook -v --extra-vars "@$KUBE_CURRENT/.ansible/extra_vars.aliyun.json" $KUBE_CURRENT/delete.yml
  if [[ $? != 0 ]]; then
    exit 1
  fi
}

# Get ssh info from aliyun instances.
function get-aliyun-instances-ssh-info {
  ansible-playbook -v --extra-vars "@$KUBE_CURRENT/.ansible/extra_vars.aliyun.json" $KUBE_CURRENT/get.yml
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
  set-k8s-op-install
  # Creating aliyun instances
  aliyun-instance-up-prelogue
  create-extra-vars-json-file-aliyun
  create-endpoints
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

  set-kubectl-path

  create-inventory-file
  create-extra-vars-json-file
  save-extra-vars-json-file

  start-kubernetes-by-ansible
  ret=$?
  if [[ $ret -ne 0 ]]; then
    echo "Failed to start kubernetes by ansible." >&2
    exit $ret
  fi
}

# Delete a kubernetes cluster
function kube-down {
  set-k8s-op-uninstall
  aliyun-instance-down-prelogue
  create-extra-vars-json-file-aliyun
  create-endpoints

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

# Create config file 'endpoints.xml' for aliyuncli
function create-endpoints {
  if [[ -z "${private_region_ids}" ]] || [[ -z "${private_products}" ]]; then
    echo "Error: private_region_ids and private_products are both needed to be set" >&2
    exit 1
  fi

  endpoints_file_dir="$KUBE_CURRENT/roles/aliyuncli/files"
  endpoints_file="${endpoints_file_dir}/endpoints.xml"
  mkdir -p ${endpoints_file_dir}

  echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" > ${endpoints_file}
  echo "<Endpoints>" >> ${endpoints_file}
  echo "    <Endpoint name=\"cn-hangzhou\">" >> ${endpoints_file}
  echo "        <RegionIds>" >> ${endpoints_file}
  
  IFS=',' read -ra region_id_array <<< "${private_region_ids}"
  for (( i = 0; i < ${#region_id_array[*]}; i++ )); do
    echo "            <RegionId>${region_id_array[$i]}</RegionId>" >> ${endpoints_file}
  done

  echo "        </RegionIds>" >> ${endpoints_file}
  echo "        <Products>" >> ${endpoints_file}

  IFS=',' read -ra product_array <<< "${private_products}"
  for (( i = 0; i < ${#product_array[*]}; i++ )); do
    IFS='@' read -ra product <<< "${product_array[$i]}"
    echo "            <Product>" >> ${endpoints_file}
    echo "                <ProductName>${product[0]}</ProductName>" >> ${endpoints_file}
    echo "                <DomainName>${product[1]}</DomainName>" >> ${endpoints_file}
    echo "            </Product>" >> ${endpoints_file}
  done

  echo "        </Products>" >> ${endpoints_file}
  echo "    </Endpoint>" >> ${endpoints_file}
  echo "</Endpoints>" >> ${endpoints_file}
}
