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

# Need access key ID and secret access key to access aliyun cloud service
ACCESS_KEY_ID=${ACCESS_KEY_ID:-""}
ACCESS_KEY_SECRET=${ACCESS_KEY_SECRET:-""}

# Masters alse are known as unschedulable or shcedulable nodes.
NUM_MASTERS=${NUM_MASTERS:-1}
NUM_NODES=${NUM_NODES:-2}

DELETE_INSTANCE_FLAG=${DELETE_INSTANCE_FLAG:-"YES"}

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
AUTOMATICALLY_INSTALL_TOOLS=${AUTOMATICALLY_INSTALL_TOOLS-"NO"}
ANSIBLE_VERSION=${ANSIBLE_VERSION-"2.1.0.0"}

# Ansible aliyun instances environment variable prefix.
ALIYUN_STRING_PREFIX="CAICLOUD_ALIYUN_CFG_STRING_"
ALIYUN_NUMBER_PREFIX="CAICLOUD_ALIYUN_CFG_NUMBER_"

# Ansible kubernetes environment variable prefix.
K8S_STRING_PREFIX="CAICLOUD_K8S_CFG_STRING_"
K8S_NUMBER_PREFIX="CAICLOUD_K8S_CFG_NUMBER_"

# For aliyun instances hostname and the option --hostname-override
MASTER_NAME_PREFIX=${MASTER_NAME_PREFIX-"kube-master-"}
NODE_NAME_PREFIX=${NODE_NAME_PREFIX-"kube-node-"}

DNS_HOST_NAME=${DNS_HOST_NAME-"caicloudstack"}
BASE_DOMAIN_NAME=${BASE_DOMAIN_NAME-"caicloudapp.com"}
DOMAIN_NAME_IN_DNS=${DOMAIN_NAME_IN_DNS-"YES"}
CLUSTER_NAME=${CLUSTER_NAME-"kube-default"}

# Use ntpdate tool to sync time
NTPDATE_SYNC_TIME=${NTPDATE_SYNC_TIME-"NO"}

# For both aliyun config and k8s config
CLOUD_CONFIG_DIR="/var/run"

# Set envirenment variables both for booting up and down aliyun instance:
#   CAICLOUD_ALIYUN_CFG_STRING_XX_YY
#   CAICLOUD_ALIYUN_CFG_NUMBER_XX_YY
#
# Assumed vars:
#   ACCESS_KEY_ID
#   ACCESS_KEY_SECRET
function aliyun-instance-prelogue-common {
  if [[ ! -z "${CLUSTER_NAME-}" ]]; then
    CAICLOUD_ALIYUN_CFG_STRING_SECURITY_GROUP_NAME=${CLUSTER_NAME}
    MASTER_NAME_PREFIX="${CLUSTER_NAME}-master-"
    NODE_NAME_PREFIX="${CLUSTER_NAME}-node-"
  fi

  CAICLOUD_ALIYUN_CFG_STRING_MASTER_NAME_PREFIX=${MASTER_NAME_PREFIX}
  CAICLOUD_ALIYUN_CFG_STRING_NODE_NAME_PREFIX=${NODE_NAME_PREFIX}
  CAICLOUD_ALIYUN_CFG_STRING_ACCESS_KEY_ID=${ACCESS_KEY_ID}
  CAICLOUD_ALIYUN_CFG_STRING_ACCESS_KEY_SECRET=${ACCESS_KEY_SECRET}
  CAICLOUD_ALIYUN_CFG_STRING_CLOUD_CONFIG_DIR=${CLOUD_CONFIG_DIR}

  if [[ "${DOMAIN_NAME_IN_DNS-}" == "YES" ]]; then
    if [[ -z "${DNS_HOST_NAME-}" ]] || [[ -z "${BASE_DOMAIN_NAME-}" ]]; then
      echo "DNS_HOST_NAME and BASE_DOMAIN_NAME are needed, if DOMAIN_NAME_IN_DNS == YES" >&2
      exit 1
    fi
    if [[ -z "${CAICLOUD_ACCESS_KEY_ID-}" ]] || [[ -z "${CAICLOUD_ACCESS_KEY_SECRET-}" ]]; then
      echo "CAICLOUD_ACCESS_KEY_ID and CAICLOUD_ACCESS_KEY_SECRET are needed, if DOMAIN_NAME_IN_DNS == YES" >&2
      exit 1
    fi
    CAICLOUD_ALIYUN_CFG_STRING_DOMAIN_NAME_IN_DNS=${DOMAIN_NAME_IN_DNS}
    CAICLOUD_ALIYUN_CFG_STRING_DNS_HOST_NAME="${DNS_HOST_NAME}"
    CAICLOUD_ALIYUN_CFG_STRING_BASE_DOMAIN_NAME="${BASE_DOMAIN_NAME}"
    CAICLOUD_ALIYUN_CFG_STRING_CAICLOUD_ACCESS_KEY_ID="${CAICLOUD_ACCESS_KEY_ID}"
    CAICLOUD_ALIYUN_CFG_STRING_CAICLOUD_ACCESS_KEY_SECRET="${CAICLOUD_ACCESS_KEY_SECRET}"
  fi

  if [[ ! -z "${NTPDATE_SYNC_TIME-}" ]]; then
    CAICLOUD_ALIYUN_CFG_STRING_NTPDATE_SYNC_TIME="${NTPDATE_SYNC_TIME}"
  fi
} 

# Set envirenment variables for booting up aliyun instance.
#
# Assumed vars:
#   NUM_MASTERS
#   NUM_NODES
function aliyun-instance-up-prelogue {
  # Now only support single master
  # Todo: support multi-master
  if [[ ${NUM_MASTERS} -gt 1 ]]; then
    echo "Now only support single master." >&2
    exit 1
  fi
  CAICLOUD_ALIYUN_CFG_NUMBER_MASTER_NODE_NUM=${NUM_MASTERS}
  CAICLOUD_ALIYUN_CFG_NUMBER_MINION_NODE_NUM=${NUM_NODES}
  CAICLOUD_ALIYUN_CFG_STRING_DNS_PROCESS_OPT="ADD"

  aliyun-instance-prelogue-common
}

function aliyun-instance-down-prelogue {
  if [[ ! -z "${DELETE_INSTANCE_FLAG-}" ]]; then
    CAICLOUD_ALIYUN_CFG_STRING_DELETE_INSTANCE_FLAG=${DELETE_INSTANCE_FLAG}
  fi
  CAICLOUD_ALIYUN_CFG_STRING_DNS_PROCESS_OPT="DELETE"

  aliyun-instance-prelogue-common
}

# Read instance ssh info from instance.master and instance.node
# and set the following environment variables:
#   MASTER_EXTERNAL_SSH_INFO
#   MASTER_INTERNAL_SSH_INFO
#   NODE_EXTERNAL_SSH_INFO
#   NODE_INTERNAL_SSH_INFO
#   KUBE_CURRENT
function read-instance-ssh-info {
  if [[ ! -s ${KUBE_CURRENT}/instance.master ]] || [[ ! -s ${KUBE_CURRENT}/instance.node ]]; then
    echo "Maybe instance ssh info file don't exist in ${KUBE_CURRENT}." >&2
    exit 1
  fi

  # Format in file:
  #   InstanceId:i-287m9nbxf InstanceName:kube-master-1 HostName:i-287m9nbxf User:root Password:Caicloud-k8s PublicIpAddress:114.215.83.202 InnerIpAddress:10.163.120.156
  #
  # Note: If the aliyun instance has no PublicIpAddress or InnerIpAddress,
  #   it will be set NONE in the field. For example: PublicIpAddress:NONE.
  instance_id_info=""
  external_ssh_info=""
  inner_ssh_info=""
  while read line; do
    # Get user name
    instance_id=`echo ${line} | sed s'/:/ /g' | awk '{print $2}'`
    username=`echo ${line} | sed s'/:/ /g' | awk '{print $8}'`
    password=`echo ${line} | sed s'/:/ /g' | awk '{print $10}'`
    public_ip=`echo ${line} | sed s'/:/ /g' | awk '{print $12}'`
    inner_ip=`echo ${line} | sed s'/:/ /g' | awk '{print $14}'`
    if [[ ${public_ip} == "NONE" ]] || [[ ${inner_ip} == "NONE" ]]; then
      echo "Public ip address or inner ip address is missing" >&2
      exit 1
    fi
    instance_id_info="${instance_id_info},${instance_id}"
    external_ssh_info="${external_ssh_info},${username}:${password}@${public_ip}"
    inner_ssh_info="${inner_ssh_info},${username}:${password}@${inner_ip}"
  done < ${KUBE_CURRENT}/instance.master
  MASTER_INSTACE_ID_INFO=${instance_id_info#,}
  MASTER_EXTERNAL_SSH_INFO=${external_ssh_info#,}
  MASTER_INTERNAL_SSH_INFO=${inner_ssh_info#,}

  instance_id_info=""
  external_ssh_info=""
  inner_ssh_info=""
  while read line; do
    # Get user name
    instance_id=`echo ${line} | sed s'/:/ /g' | awk '{print $2}'`
    username=`echo ${line} | sed s'/:/ /g' | awk '{print $8}'`
    password=`echo ${line} | sed s'/:/ /g' | awk '{print $10}'`
    public_ip=`echo ${line} | sed s'/:/ /g' | awk '{print $12}'`
    inner_ip=`echo ${line} | sed s'/:/ /g' | awk '{print $14}'`
    if [[ ${public_ip} == "NONE" ]] || [[ ${inner_ip} == "NONE" ]]; then
      echo "Public ip address or inner ip address is missing" >&2
      exit 1
    fi
    instance_id_info="${instance_id_info},${instance_id}"
    external_ssh_info="${external_ssh_info},${username}:${password}@${public_ip}"
    inner_ssh_info="${inner_ssh_info},${username}:${password}@${inner_ip}"
  done < ${KUBE_CURRENT}/instance.node
  # Remove the first ','
  NODE_INSTACE_ID_INFO=${instance_id_info#,}
  NODE_EXTERNAL_SSH_INFO=${external_ssh_info#,}
  NODE_INTERNAL_SSH_INFO=${inner_ssh_info#,}
}

# Set envirenment variables for kubernetes cluster deployment.
#
# Assumed vars:
#   NUM_MASTERS
#   NUM_NODES
function aliyun-instance-epilogue {
  # Read aliyun instances ssh info
  read-instance-ssh-info

  # For cluster validate
  # Note: we will run kubelet on all masters
  export NUM_NODES=$((NUM_MASTERS+NUM_NODES))

  # For setup-instances function
  INSTANCE_SSH_EXTERNAL="${MASTER_EXTERNAL_SSH_INFO},${NODE_EXTERNAL_SSH_INFO}"

  if [[ ! -z "${CLUSTER_NAME-}" ]]; then
    CAICLOUD_K8S_CFG_STRING_CLUSTER_NAME=${CLUSTER_NAME}
    
  fi

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
  CAICLOUD_K8S_CFG_STRING_KUBE_MASTER_IP=${MASTER_EXTERNAL_SSH_INFO#*@}
  CAICLOUD_K8S_CFG_STRING_CLOUD_CONFIG_DIR=${CLOUD_CONFIG_DIR}
}

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
