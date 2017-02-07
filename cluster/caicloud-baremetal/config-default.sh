#!/bin/bash

# Copyright 2015 The Kubernetes Authors All rights reserved.
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
# Linux distribution of underline machines.
KUBE_DISTRO=${KUBE_DISTRO:-"trusty"}

# ssh information for master (comma separated string).
MASTER_SSH_INFO=${MASTER_SSH_INFO:-"vagrant:vagrant@192.168.205.10"}

# ssh information for nodes (comma separated string).
NODE_SSH_INFO=${NODE_SSH_INFO:-"vagrant:vagrant@192.168.205.11,vagrant:vagrant@192.168.205.12"}

# Name of the cluster. This is used for constructing the prefix of resource IDs
# in anchnet. The same name needs to be specified when running kube-down to
# release the resources acquired during kube-up.
CLUSTER_NAME=${CLUSTER_NAME:-"kube-default"}
# This is a more meaningful name to user and will be passed into monitoring for
# paging later.
CLUSTER_ALIAS=${CLUSTER_ALIAS:-"kube-default"}

# The version of caicloud release to use if building release is not required.
# E.g. v1.0.2, 2015-09-09-15-30-30, etc.
CAICLOUD_KUBE_VERSION=${CAICLOUD_KUBE_VERSION:-"v1.2.4+v0.9.1"}

# KUBE_USER uniquely identifies a caicloud user. This is the user that owns the
# cluster, and will be used to create kubeconfig file.
KUBE_USER=${KUBE_USER:-""}

# Docker version. Ideally, this should come with CAICLOUD_KUBE_VERSION, but
# there is no easy to enforce docker version in caicloud kubernetes release,
# so we define it here separately.
DOCKER_VERSION=${DOCKER_VERSION:-"1.9.1"}

# To indicate if the execution status needs to be reported back to caicloud
# executor via curl. Set it to be Y if reporting is needed.
REPORT_KUBE_STATUS=${REPORT_KUBE_STATUS:-"N"}

# Whether we use self signed cert for apiserver
USE_SELF_SIGNED_CERT=${USE_SELF_SIGNED_CERT:-"true"}

# Provider name used internally.
CAICLOUD_PROVIDER=${CAICLOUD_PROVIDER:-""}

# These environment vars are used by monitoring and have fake default values.
# The default value are mainly used for getting us through the kube-up process
# when doing kube-up by hand (e.g. deploying caicloud stack on private cloud)
# since we don't have any real values for these env vars yet. For clusters
# brought up by caicloud stack (user clusters), these values are passed in by cds
CLUSTER_ID=${CLUSTER_ID:-"32793e34-79d2-432b-ac17-708b61b80e6a"}
CLUSTER_TOKEN=${CLUSTER_TOKEN:-"eSbsyAr2eDatXBxa"}
CAICLOUD_UID=${CAICLOUD_UID:-"110ec58a-a0f2-4ac4-8393-c866d813b8d1"}

# Used by monitoring to indicate which environment we are running on
RUNNING_ENV=${RUNNING_ENV:-"dev"}
# The default paging url is an invalid one which is only for when running kube-up locally.
PAGING_EXTERNAL_ADDR=${PAGING_EXTERNAL_ADDR:-"http://paging-dev/api/paging"}

# If we want to register master kubelet as a node. Note, since kubernetes 1.2,
# it's better to always set this to true. We can disable scheduling user pod
# to master via REGISTER_MASTER_SCHEDULABLE.
REGISTER_MASTER_KUBELET=${REGISTER_MASTER_KUBELET:-"true"}

# If we want to register master kubelet as a node.
REGISTER_MASTER_SCHEDULABLE=${REGISTER_MASTER_SCHEDULABLE:-"false"}

#
# Following params in the section should rarely change.
#

# URL path of the server hosting caicloud kubernetes release.
CAICLOUD_HOST_URL=${CAICLOUD_HOST_URL:-"http://7xli2p.dl1.z0.glb.clouddn.com"}

# Caicloud registry mirror.
REGISTRY_MIRROR=${REGISTRY_MIRROR:-"https://docker-mirror.caicloud.io"}

# Ubuntu/Debian apt mirrors. The mirros are used in their relative order - if the
# first one failed, then switch to second one, etc. Make sure retry count is larger
# than the list; otherwise not all of the mirrors will be used.
APT_MIRRORS=${APT_MIRRORS:-"\
http://mirrors.aliyun.com/ubuntu/,\
http://mirrors.163.com/ubuntu/,\
http://ftp.sjtu.edu.cn/ubuntu/"}

# -----------------------------------------------------------------------------
# Parameter from executor for cluster addons.
# -----------------------------------------------------------------------------
# Optional: Install cluster DNS.
ENABLE_CLUSTER_DNS=${ENABLE_CLUSTER_DNS:-true}
DNS_SERVER_IP=${DNS_SERVER_IP:-10.254.0.100} # Must be a IP in SERVICE_CLUSTER_IP_RANGE.
DNS_DOMAIN=${DNS_DOMAIN:-"cluster.local"}
DNS_REPLICAS=${DNS_REPLICAS:-1}

# Optional: Install cluster monitoring. Resource requirement is calculated at last.
ENABLE_CLUSTER_MONITORING=${ENABLE_CLUSTER_MONITORING:-true}

# Optional: When set to true, fluentd, elasticsearch and kibana will be setup as
# part of the cluster bring up.
ENABLE_CLUSTER_LOGGING=${ENABLE_CLUSTER_LOGGING:-true}
ELASTICSEARCH_REPLICAS=${ELASTICSEARCH_REPLICAS:-2}
KIBANA_REPLICAS=${KIBANA_REPLICAS:-1}

# Optional: Install kubernetes dashboard.
ENABLE_CLUSTER_DASHBOARD=${ENABLE_CLUSTER_DASHBOARD:-true}
DASHBOARD_REPLICAS=${DASHBOARD_REPLICAS:-1}

# Optional: Install cluster registry.
ENABLE_CLUSTER_REGISTRY=${ENABLE_CLUSTER_REGISTRY:-false}


# -----------------------------------------------------------------------------
# Cluster IP address and ranges: all are static configuration values.
# -----------------------------------------------------------------------------
# Define the IP range used for service cluster IPs. If this is ever changed,
# fixed cluster service IP needs to be changed as well, including DNS_SERVER_IP.
SERVICE_CLUSTER_IP_RANGE=10.254.0.0/16  # formerly PORTAL_NET

# Define the IP range used for flannel overlay network, should not conflict
# with above SERVICE_CLUSTER_IP_RANGE.
FLANNEL_NET=192.168.64.0/20
FLANNEL_SUBNET_LEN=24
FLANNEL_SUBNET_MIN=192.168.64.0
FLANNEL_SUBNET_MAX=192.168.79.0
FLANNEL_TYPE="host-gw"

# MASTER_INSECURE_* is used to serve insecure connection. It is either
#   localhost, blocked by firewall, or use with nginx, etc.
# KUBELET_PORT is the port kubelet server serves on.
# Note, the above configs should rarely change.
MASTER_INSECURE_ADDRESS="127.0.0.1"
MASTER_INSECURE_PORT="8080"

# The IP address or interface for kubelet to serve on.
KUBELET_ADDRESS="0.0.0.0"
KUBELET_PORT="10250"

DNS_HOST_NAME=${DNS_HOST_NAME:-"cluster"}
BASE_DOMAIN_NAME=${BASE_DOMAIN_NAME:-"caicloudapp.com"}

# -----------------------------------------------------------------------------
# Misc static configurations.
# -----------------------------------------------------------------------------
# Admission Controllers to invoke prior to persisting objects in cluster.
ADMISSION_CONTROL=NamespaceLifecycle,LimitRanger,SecurityContextDeny,ServiceAccount,ResourceQuota

# The infra container used for every Pod.
POD_INFRA_CONTAINER="caicloudgcr/pause:1.0"

# Namespace used to create cluster wide services, e.g. logging, dns, etc.
# The name is from upstream and shouldn't be changed.
SYSTEM_NAMESPACE="kube-system"

# Extra options to set on the Docker command line.  This is useful for setting
# --insecure-registry for local registries.
DOCKER_OPTS=""


# -----------------------------------------------------------------------------
# Derived params for kube-up (calculated based on above params: DO NOT CHANGE).
# If above configs are changed manually, remember to call the function.
# -----------------------------------------------------------------------------
function calculate-default {
  # If KUBE_USER is specified, set the path to save per user k8s config file;
  # otherwise, use default one from k8s.
  if [[ ! -z ${KUBE_USER-} ]]; then
    KUBECONFIG="$HOME/.kube/config_${CLUSTER_NAME}"
  fi

  # Master IP and node IPs. Note we intentially use NODE_IPS instead of using
  # NODE_IIPS here since the IPs can be public IPs.
  MASTER_IP=${MASTER_SSH_INFO#*@}
  NODE_IPS=""
  IFS=',' read -ra node_info_array <<< "${NODE_SSH_INFO}"
  for node_info in "${node_info_array[@]}"; do
    IFS=':@' read -ra ssh_info <<< "${node_info}"
    if [[ -z "${NODE_IPS-}" ]]; then
      NODE_IPS="${ssh_info[2]}"
    else
      NODE_IPS="${NODE_IPS},${ssh_info[2]}"
    fi
  done

  # However, we also treat Master/node IP as their internal IPs.
  MASTER_IIP=${MASTER_IP}
  NODE_IIPS=${NODE_IPS}

  # Create node IP address array and NUM_NODES.
  IFS=',' read -ra NODE_IIPS_ARR <<< "${NODE_IIPS}"
  export NUM_NODES=${#NODE_IIPS_ARR[@]}

  NUM_MASTERS=${NUM_MASTERS:-1}
  # Note that master_name and node_name are name of the instances in anchnet, which
  # is helpful to group instances; however, anchnet API works well with instance id,
  # so we provide instance id to kubernetes as nodename and hostname, which makes it
  # easy to query anchnet in kubernetes.
  MASTER_NAME="${CLUSTER_NAME}-master"
  NODE_NAME_PREFIX="${CLUSTER_NAME}-node"

  # All instances' ssh info.
  INSTANCE_SSH_INFO="${MASTER_SSH_INFO},${NODE_SSH_INFO}"
  INSTANCE_SSH_EXTERNAL="${MASTER_SSH_INFO},${NODE_SSH_INFO}"
  MASTER_SSH_EXTERNAL="${MASTER_SSH_INFO}"
  NODE_SSH_EXTERNAL="${NODE_SSH_INFO}"

  # Context to use in kubeconfig.
  CONTEXT="baremetal_${CLUSTER_NAME}"

  # Caicloud tarball package name.
  CAICLOUD_KUBE_PKG="caicloud-kube-${CAICLOUD_KUBE_VERSION}.tar.gz"

  # Final URL of caicloud tarball URL.
  CAICLOUD_TARBALL_URL="${CAICLOUD_HOST_URL}/${CAICLOUD_KUBE_PKG}"

  if [[ ${USE_SELF_SIGNED_CERT} == "false" ]]; then
    MASTER_DOMAIN_NAME="${DNS_HOST_NAME}.${BASE_DOMAIN_NAME}"
  fi

  # MASTER_SECURE_* is accessed directly from outside world, serving HTTPS.
  MASTER_SECURE_ADDRESS=${MASTER_IIP}
  if [[ ${USE_SELF_SIGNED_CERT} == "false" ]]; then
    MASTER_SECURE_PORT="6443"
  else
    MASTER_SECURE_PORT="443"
  fi

  # Calculate heapster memory limit based on number of nodes. Number come from
  # cluster/addons/cluster-monitoring/influxdb/heapster-controller.yaml
  METRICS_MEMORY="$((100 + ${NUM_NODES} * 4))Mi"
  EVENTER_MEMORY="$((100 * 1024 + ${NUM_NODES} * 500))Ki"

  # cluster/caicloud/addons/quota.yaml.in
  # dns 170Mi, es (1024+5Mi)*2, monitoring 750Mi, heapster (200+5*n)Mi, fluentd 200Mi*n, (kibana 50Mi, dashboard 50Mi)
  QUOTA_MEMORY="$((3178 + (${NUM_NODES}+ ${NUM_MASTERS}) * 205))Mi"
  # dns 310m, es 305m*2, monitoring 300m, heapster 200m, fluentd 20m*n, (kibana 100m, dashboard 100m)    
  QUOTA_CPU="$((1420+ (${NUM_NODES} + ${NUM_MASTERS}) * 20))m"
}

calculate-default
