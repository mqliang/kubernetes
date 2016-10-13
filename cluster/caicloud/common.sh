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

#
# The script contains common configs and functions used to provision caicloud
# kubernetes. Assumed vars in some of the functions should be available after
# sourcing file: cluster/${KUBERNETES_PROVIDER}/config-default.sh.
#

# -----------------------------------------------------------------------------
# Cluster related common operations.
# -----------------------------------------------------------------------------

# Deploy caicloud enabled addons.
#
# At this point, addon secrets should be created (in create-certs-and-credentials).
# Note we have to create the secrets beforehand, so that when provisioning master,
# it knows all the tokens (including addons). All other addons related setup will
# need to be performed here.
#
# Addon yaml files are copied from cluster/addons, with slight modifications to
# fit into caicloud environment.
#
# Assumed vars:
#   KUBE_TEMP
#   KUBE_ROOT
#   DNS_REPLICAS
#   DNS_SERVER_IP
#   ELASTICSEARCH_REPLICAS
#   MASTER_SSH_EXTERNAL
function deploy-addons {
  log "+++++ Start deploying caicloud addons"
  # Replace placeholder with our configuration for dns rc/svc.
  local -r skydns_rc_file="${KUBE_ROOT}/cluster/caicloud/addons/dns/skydns-rc.yaml.in"
  local -r skydns_svc_file="${KUBE_ROOT}/cluster/caicloud/addons/dns/skydns-svc.yaml.in"
  sed -e "s/{{ pillar\['dns_replicas'\] }}/${DNS_REPLICAS}/g;\
          s/{{ pillar\['dns_domain'\] }}/${DNS_DOMAIN}/g;\
          s|{{ pillar\['dns_image_etcd'\] }}|${DNS_IMAGE_ETCD}|g;\
          s|{{ pillar\['dns_image_kube2sky'\] }}|${DNS_IMAGE_KUBE2SKY}|g;\
          s|{{ pillar\['dns_image_skydns'\] }}|${DNS_IMAGE_SKYDNS}|g;\
          s|{{ pillar\['dns_image_healthz'\] }}|${DNS_IMAGE_HEALTHZ}|g" ${skydns_rc_file} > ${KUBE_TEMP}/skydns-rc.yaml
  sed -e "s/{{ pillar\['dns_server'\] }}/${DNS_SERVER_IP}/g" ${skydns_svc_file} > ${KUBE_TEMP}/skydns-svc.yaml

  # Replace placeholder with our configuration for elasticsearch rc.
  local -r elasticsearch_rc_file="${KUBE_ROOT}/cluster/caicloud/addons/logging/elasticsearch-rc.yaml.in"
  sed -e "s/{{ pillar\['elasticsearch_replicas'\] }}/${ELASTICSEARCH_REPLICAS}/g;\
          s|{{ pillar\['elasticsearch_image_elasticsearch'\] }}|${ELASTICSEARCH_IMAGE_ELASTICSEARCH}|g;\
          s|{{ pillar\['elasticsearch_image_escron'\] }}|${ELASTICSEARCH_IMAGE_ESCRON}|g" ${elasticsearch_rc_file} > ${KUBE_TEMP}/elasticsearch-rc.yaml

  # Replace placeholder with our configuration for heapster rc.
  local -r heapster_rc_file="${KUBE_ROOT}/cluster/caicloud/addons/monitoring/heapster-controller.yaml.in"
  sed -e "s/{{ pillar\['metrics_memory'\] }}/${METRICS_MEMORY}/g;s/{{ pillar\['eventer_memory'\] }}/${EVENTER_MEMORY}/g;\
          s|{{ pillar\['heapster_image_heapster'\] }}|${HEAPSTER_IMAGE_HEAPSTER}|g" ${heapster_rc_file} > ${KUBE_TEMP}/heapster-controller.yaml

  # Replace placeholder with our configuration for heapster rc.
  local -r grafana_rc_file="${KUBE_ROOT}/cluster/caicloud/addons/monitoring/grafana-controller.yaml.in"
  sed -e "s|{{ pillar\['monitoring_image_grafana'\] }}|${MONITORING_IMAGE_GRAFANA}|g" ${grafana_rc_file} > ${KUBE_TEMP}/grafana-controller.yaml

  # Replace placeholder with our configuration for influxdb rc.
  local -r influxdb_rc_file="${KUBE_ROOT}/cluster/caicloud/addons/monitoring/influxdb-controller.yaml.in"
  sed -e "s|{{ pillar\['monitoring_image_influxdb'\] }}|${MONITORING_IMAGE_INFLUXDB}|g" ${influxdb_rc_file} > ${KUBE_TEMP}/influxdb-controller.yaml

  # Replace placeholder with our configuration for monitoring server daemonset.
  local -r monitoring_server_daemonset_file="${KUBE_ROOT}/cluster/caicloud/addons/monitoring/server-daemonset.yaml.in"
  sed -e "s|{{ pillar\['monitoring_image_server'\] }}|${MONITORING_IMAGE_SERVER}|g" ${monitoring_server_daemonset_file} > ${KUBE_TEMP}/monitoring-server-daemonset.yaml

  # Replace placeholder with our configuration for monitoring watcher rc.
  local -r monitoring_watcher_rc_file="${KUBE_ROOT}/cluster/caicloud/addons/monitoring/watcher-controller.yaml.in"
  sed -e "s/{{ pillar\['cluster_id'\] }}/${CLUSTER_ID}/g;\
          s/{{ pillar\['caicloud_uid'\] }}/${CAICLOUD_UID}/g;\
          s/{{ pillar\['cluster_token'\] }}/${CLUSTER_TOKEN}/g;\
          s/{{ pillar\['cluster_name'\] }}/${CLUSTER_ALIAS}/g;\
          s|{{ pillar\['paging_url'\] }}|${PAGING_EXTERNAL_ADDR}|g;\
          s/{{ pillar\['running_enviroment'\] }}/${RUNNING_ENV}/g;\
          s|{{ pillar\['network_checker_pods_num'\] }}|${NETWORK_CHECKER_PODS_NUM}|g;\
          s|{{ pillar\['network_checker_public_host'\] }}|${NETWORK_CHECKER_PUBLIC_HOST}|g;\
          s|{{ pillar\['enable_public_network'\] }}|${ENABLE_PUBLIC_NETWORK}|g;\
          s|{{ pillar\['monitoring_image_watcher'\] }}|${MONITORING_IMAGE_WATCHER}|g" ${monitoring_watcher_rc_file} > ${KUBE_TEMP}/monitoring-watcher-controller.yaml

  # Replace placeholder with our configuration for kube-system quota
  local -r quota_file="${KUBE_ROOT}/cluster/caicloud/addons/quota.yaml.in"
  sed -e "s/{{ pillar\['quota_cpu'\] }}/${QUOTA_CPU}/g;s/{{ pillar\['quota_memory'\] }}/${QUOTA_MEMORY}/g" ${quota_file} > ${KUBE_TEMP}/quota.yaml

  local -r registry_yaml_file="${KUBE_ROOT}/cluster/caicloud/addons/registry/registry-rc.yaml"
  sed -e "s|{{ pillar\['registry_image'\] }}|${REGISTRY_IMAGE}|g" ${registry_yaml_file} > ${KUBE_TEMP}/registry-rc.yaml

  # Copy addon configurationss and startup script to master instance under ~/kube.
  rm -rf ${KUBE_TEMP}/addons
  mkdir -p ${KUBE_TEMP}/addons/dns ${KUBE_TEMP}/addons/logging ${KUBE_TEMP}/addons/monitoring ${KUBE_TEMP}/addons/registry
  # dns rc/svc
  cp ${KUBE_TEMP}/skydns-rc.yaml \
     ${KUBE_TEMP}/skydns-svc.yaml \
     ${KUBE_TEMP}/addons/dns
  # logging rc/svc
  cp ${KUBE_TEMP}/elasticsearch-rc.yaml \
     ${KUBE_ROOT}/cluster/caicloud/addons/logging/elasticsearch-svc.yaml \
     ${KUBE_TEMP}/addons/logging
  # monitoring rc/svc
  cp ${KUBE_TEMP}/heapster-controller.yaml \
     ${KUBE_TEMP}/grafana-controller.yaml \
     ${KUBE_TEMP}/influxdb-controller.yaml \
     ${KUBE_TEMP}/monitoring-server-daemonset.yaml \
     ${KUBE_TEMP}/monitoring-watcher-controller.yaml \
     ${KUBE_ROOT}/cluster/caicloud/addons/monitoring/grafana-service.yaml \
     ${KUBE_ROOT}/cluster/caicloud/addons/monitoring/heapster-service.yaml \
     ${KUBE_ROOT}/cluster/caicloud/addons/monitoring/influxdb-service.yaml \
     ${KUBE_ROOT}/cluster/caicloud/addons/monitoring/server-service.yaml \
     ${KUBE_ROOT}/cluster/caicloud/addons/monitoring/server-mongo-controller.yaml \
     ${KUBE_ROOT}/cluster/caicloud/addons/monitoring/server-mongo-service.yaml \
     ${KUBE_TEMP}/addons/monitoring
  # registry rc/svc
  cp ${KUBE_TEMP}/registry-rc.yaml ${KUBE_ROOT}/cluster/caicloud/addons/registry/registry-svc.yaml \
     ${KUBE_TEMP}/addons/registry
  scp-to-instance-expect "${MASTER_SSH_EXTERNAL}" \
    "${KUBE_TEMP}/addons \
    ${KUBE_ROOT}/cluster/caicloud/addons/namespace.yaml \
    ${KUBE_ROOT}/cluster/caicloud/addons/limitrange.yaml \
    ${KUBE_TEMP}/quota.yaml \
    ${KUBE_ROOT}/cluster/caicloud/addons/addons-start.sh" \
    "~/kube"

  # Call 'addons-start.sh' to start addons.
  ssh-to-instance-expect "${MASTER_SSH_EXTERNAL}" \
    "SYSTEM_NAMESPACE=${SYSTEM_NAMESPACE} \
     ENABLE_CLUSTER_DNS=${ENABLE_CLUSTER_DNS} \
     ENABLE_CLUSTER_LOGGING=${ENABLE_CLUSTER_LOGGING} \
     ENABLE_CLUSTER_MONITORING=${ENABLE_CLUSTER_MONITORING} \
     ENABLE_CLUSTER_REGISTRY=${ENABLE_CLUSTER_REGISTRY} \
     MASTER_INSECURE_ADDRESS=${MASTER_INSECURE_ADDRESS} \
     MASTER_INSECURE_PORT=${MASTER_INSECURE_PORT} \
     ./kube/addons-start.sh"
}

# Create certificate pairs and credentials for the cluster.
# Note: Some of the code in this function is inspired from gce/util.sh,
# make-ca-cert.sh.
#
# These are used for static cert distribution (e.g. static clustering) at
# cluster creation time. This will be obsoleted once we implement dynamic
# clustering.
#
# The following certificate pairs are created:
#
#  - ca (the cluster's certificate authority)
#  - server
#
# Assumed vars
#   KUBE_ROOT
#   KUBE_TEMP
#   MASTER_NAME
#   MASTER_SECURE_PORT
#   DNS_DOMAIN
#   SERVICE_CLUSTER_IP_RANGE
#   MASTER_IIP *
#   MASTER_EIP *
#
# Vars set:
#   KUBELET_TOKEN
#   KUBE_PROXY_TOKEN
#   KUBE_BEARER_TOKEN
#   CERT_DIR
#   CA_CERT - Path to ca cert
#   KUBE_CERT - Path to kubectl client cert
#   KUBE_KEY - Path to kubectl client key
#   CA_CERT_BASE64
#   MASTER_CERT_BASE64
#   MASTER_KEY_BASE64
#   KUBELET_CERT_BASE64
#   KUBELET_KEY_BASE64
#   KUBECTL_CERT_BASE64
#   KUBECTL_KEY_BASE64
#
# Files created:
#   ${KUBE_TEMP}/kubelet-kubeconfig
#   ${KUBE_TEMP}/kube-proxy-kubeconfig
#   ${KUBE_TEMP}/known-tokens.csv
#   ${KUBE_TEMP}/abac.json
#   ${KUBE_TEMP}/easy-rsa-master/easyrsa3/pki/ca.crt
#   ${KUBE_TEMP}/easy-rsa-master/easyrsa3/pki/issued/master.crt
#   ${KUBE_TEMP}/easy-rsa-master/easyrsa3/pki/private/master.key
#   ${KUBE_TEMP}/easy-rsa-master/easyrsa3/pki/issued/kubelet.crt
#   ${KUBE_TEMP}/easy-rsa-master/easyrsa3/pki/private/kubelet.key
#   ${KUBE_TEMP}/easy-rsa-master/easyrsa3/pki/issued/kubectl.crt
#   ${KUBE_TEMP}/easy-rsa-master/easyrsa3/pki/private/kubectl.key
function create-certs-and-credentials {
  log "+++++ Create certificates, credentials and secrets"

  # 'octects' will be an arrary of segregated IP, e.g. 192.168.3.0/24 => 192 168 3 0
  # 'service_ip' is the first IP address in SERVICE_CLUSTER_IP_RANGE; it is the service
  #  created to represent kubernetes api itself, i.e. kubectl get service:
  #    NAME         LABELS                                    SELECTOR   IP(S)         PORT(S)
  #    kubernetes   component=apiserver,provider=kubernetes   <none>     192.168.3.1   443/TCP
  # 'sans' are all the possible names that the ca certifcate certifies.
  local octects=($(echo "${SERVICE_CLUSTER_IP_RANGE}" | sed -e 's|/.*||' -e 's/\./ /g'))
  ((octects[3]+=1))
  local service_ip=$(echo "${octects[*]}" | sed 's/ /./g')
  local sans="IP:${MASTER_IIP},IP:${service_ip}"
  # Add external IP if provided.
  if [[ "${MASTER_EIP:-}" != "" ]]; then
    sans="${sans},IP:${MASTER_EIP}"
    master_ip="${MASTER_EIP}"
  else
    master_ip="${MASTER_IIP}"
  fi
  sans="${sans},DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc"
  sans="${sans},DNS:kubernetes.default.svc.${DNS_DOMAIN},DNS:${MASTER_NAME},DNS:master"

  # The directory where all certs/keys will be placed at.
  mkdir -p ${KUBE_TEMP}/certs

  # Create cluster certificates.
  (
    cp "${KUBE_ROOT}/cluster/caicloud/tools/easy-rsa.tar.gz" "${KUBE_TEMP}"
    cd "${KUBE_TEMP}"
    tar xzf easy-rsa.tar.gz > /dev/null 2>&1
    cd easy-rsa-master/easyrsa3
    ./easyrsa init-pki > /dev/null 2>&1
    ./easyrsa --batch "--req-cn=${master_ip}@$(date +%s)" build-ca nopass > /dev/null 2>&1
    ./easyrsa --subject-alt-name="${sans}" build-server-full master nopass > /dev/null 2>&1
    ./easyrsa build-client-full kubelet nopass > /dev/null 2>&1
    ./easyrsa build-client-full kubectl nopass > /dev/null 2>&1
  ) || {
    log "${color_red}=== Failed to generate certificates: Aborting ===${color_norm}"
    exit 2
  }
  SELF_SIGNED_CERT_DIR="${KUBE_TEMP}/easy-rsa-master/easyrsa3"
  # Path to certificates, used to create kubeconfig for kubectl.
  CA_CERT="${SELF_SIGNED_CERT_DIR}/pki/ca.crt"
  KUBE_CERT="${SELF_SIGNED_CERT_DIR}/pki/issued/kubectl.crt"
  KUBE_KEY="${SELF_SIGNED_CERT_DIR}/pki/private/kubectl.key"
  # By default, linux wraps base64 output every 76 cols, so we use 'tr -d' to remove whitespaces.
  # Note 'base64 -w0' doesn't work on Mac OS X, which has different flags.
  SELF_SIGNED_CA_CERT_BASE64=$(cat "${SELF_SIGNED_CERT_DIR}/pki/ca.crt" | base64 | tr -d '\r\n')
  # organize the directory a little bit
  cp ${SELF_SIGNED_CERT_DIR}/pki/ca.crt ${SELF_SIGNED_CERT_DIR}/pki/issued/master.crt ${SELF_SIGNED_CERT_DIR}/pki/private/master.key \
     ${KUBE_TEMP}/certs

  if [[ ${USE_SELF_SIGNED_CERT} == "false" ]]; then
    mkdir -p ${KUBE_TEMP}/certs/caicloudapp_certs
    CERT_DIR=${CERT_DIR:-"${KUBE_ROOT}/cluster/caicloud/certs"}
    # Path to CA certificates. CA_CERT is reset to a valid CA cert(e.g. Geotrust) in case we present
    # a CA verified cert to users since CA_CERT will be used to build kubeconfig file.
    CA_CERT="${CERT_DIR}/ca.crt"
    cp ${CERT_DIR}/ca.crt ${CERT_DIR}/master.crt ${CERT_DIR}/master.key ${KUBE_TEMP}/certs/caicloudapp_certs
  fi
  # Generate bearer tokens for this cluster. This may disappear, upstream issue:
  # https://github.com/GoogleCloudPlatform/kubernetes/issues/3168
  KUBELET_TOKEN=$(dd if=/dev/urandom bs=128 count=1 2>/dev/null | base64 | tr -d "=+/" | dd bs=32 count=1 2>/dev/null)
  KUBE_PROXY_TOKEN=$(dd if=/dev/urandom bs=128 count=1 2>/dev/null | base64 | tr -d "=+/" | dd bs=32 count=1 2>/dev/null)
  KUBE_BEARER_TOKEN=$(dd if=/dev/urandom bs=128 count=1 2>/dev/null | base64 | tr -d "=+/" | dd bs=32 count=1 2>/dev/null)

  # Create a username/password for accessing cluster.
  get-password

  # Create kubeconfig used by kubelet and kube-proxy to connect to apiserver.
  (
    umask 077;
    cat > "${KUBE_TEMP}/kubelet-kubeconfig" <<EOF
apiVersion: v1
kind: Config
users:
- name: kubelet
  user:
    token: ${KUBELET_TOKEN}
clusters:
- name: local
  cluster:
    certificate-authority-data: ${SELF_SIGNED_CA_CERT_BASE64}
contexts:
- context:
    cluster: local
    user: kubelet
  name: service-account-context
current-context: service-account-context
EOF
  )

  (
    umask 077;
    cat > "${KUBE_TEMP}/kube-proxy-kubeconfig" <<EOF
apiVersion: v1
kind: Config
users:
- name: kube-proxy
  user:
    token: ${KUBE_PROXY_TOKEN}
clusters:
- name: local
  cluster:
    certificate-authority-data: ${SELF_SIGNED_CA_CERT_BASE64}
contexts:
- context:
    cluster: local
    user: kube-proxy
  name: service-account-context
current-context: service-account-context
EOF
  )

  # Create known-tokens.csv used by apiserver to authenticate clients using tokens.
  (
    umask 077;
    echo "${KUBE_BEARER_TOKEN},admin,admin" > "${KUBE_TEMP}/known-tokens.csv"
    echo "${KUBELET_TOKEN},kubelet,kubelet" >> "${KUBE_TEMP}/known-tokens.csv"
    echo "${KUBE_PROXY_TOKEN},kube_proxy,kube_proxy" >> "${KUBE_TEMP}/known-tokens.csv"
  )

  # Create basic-auth.csv used by apiserver to authenticate clients using HTTP basic auth.
  (
    umask 077
    echo "${KUBE_PASSWORD},${KUBE_USER},admin" > "${KUBE_TEMP}/basic-auth.csv"
  )

  # Create abac.json used by apiserver to controll access.
  (
    umask 077
    echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"*\",\"nonResourcePath\":\"*\",\"readonly\":true}}" > "${KUBE_TEMP}/abac.json"
    echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"admin\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> "${KUBE_TEMP}/abac.json"
    echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"system:controller_manager\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> "${KUBE_TEMP}/abac.json"
    echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"kubelet\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> "${KUBE_TEMP}/abac.json"
    echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"kube_proxy\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> "${KUBE_TEMP}/abac.json"
    echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"system:logging\",\"namespace\": \"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> "${KUBE_TEMP}/abac.json"
    echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"system:monitoring\",\"namespace\": \"*\",\"resource\": \"*\",\"apiGroup\":\"*\"}}" >> "${KUBE_TEMP}/abac.json"
    echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"system:serviceaccount:kube-system:default\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> "${KUBE_TEMP}/abac.json"
    echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"system:serviceaccount:default:default\",\"namespace\":\"default\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> "${KUBE_TEMP}/abac.json"
    echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"group\":\"admin\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> "${KUBE_TEMP}/abac.json"
    echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"group\":\"viewer\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\",\"readonly\":true}}" >> "${KUBE_TEMP}/abac.json"
  )

  # Create tokens for service accounts. 'service_accounts' refers to things that
  # provide services based on apiserver, including scheduler, controller_manager
  # and addons (Note scheduler and controller_manager are not actually used in
  # our setup, but we keep it here for tracking. The reason for having such secrets
  # for these service accounts is to run them as Pod, aka, self-hosting).
  local -r service_accounts=("system:scheduler" "system:controller_manager")
  for account in "${service_accounts[@]}"; do
    token=$(dd if=/dev/urandom bs=128 count=1 2>/dev/null | base64 | tr -d "=+/" | dd bs=32 count=1 2>/dev/null)
    create-kubeconfig-secret "${token}" "${account}" "https://${master_ip}:${MASTER_SECURE_PORT}" "${KUBE_TEMP}/${account}-secret.yaml"
    echo "${token},${account},${account}" >> "${KUBE_TEMP}/known-tokens.csv"
  done
}

# Create a kubeconfig file used for addons to contact apiserver. Note this is not
# used to create kubeconfig for kubelet and kube-proxy, since they have slightly
# different contents. This is only used in function "create-certs-and-credentials".
#
# Input:
#   $1 The base64 encoded token
#   $2 Username, e.g. system:dns
#   $3 Server to connect to, e.g. master_ip:port
#   $4 File to write the secret.
function create-kubeconfig-secret {
  local -r token=${1}
  local -r username=${2}
  local -r server=${3}
  local -r file=${4}
  local -r safe_username=$(tr -s ':_' '--' <<< "${username}")

  # Make a kubeconfig file with token.
  cat > "${KUBE_TEMP}/kubeconfig" <<EOF
apiVersion: v1
kind: Config
users:
- name: ${username}
  user:
    token: ${token}
clusters:
- name: local
  cluster:
     server: ${server}
     certificate-authority-data: ${SELF_SIGNED_CA_CERT_BASE64}
contexts:
- context:
    cluster: local
    user: ${username}
    namespace: ${SYSTEM_NAMESPACE}
  name: service-account-context
current-context: service-account-context
EOF

  local -r kubeconfig_base64=$(cat "${KUBE_TEMP}/kubeconfig" | base64 | tr -d '\r\n')
  cat > ${file} <<EOF
apiVersion: v1
data:
  kubeconfig: ${kubeconfig_base64}
kind: Secret
metadata:
  name: token-${safe_username}
type: Opaque
EOF
}

# Start a kubernetes cluster. The function assumes that master and nodes have
# already been setup correctly.
#
# Assumed vars:
#   MASTER_SSH_EXTERNAL
#   NODE_SSH_EXTERNAL
function start-kubernetes {
  local pids=""
  IFS=',' read -ra node_ssh_info <<< "${NODE_SSH_EXTERNAL}"
  ssh-to-instance-expect "${MASTER_SSH_EXTERNAL}" \
    "sudo ./kube/master-start.sh" & pids="${pids} $!"
  for ssh_info in "${node_ssh_info[@]}"; do
    ssh-to-instance-expect "${ssh_info}" \
      "sudo ./kube/node-start.sh" & pids="${pids} $!"
  done
  wait ${pids}
}

# Cleanup a kubernetes cluster - stop all kubernetes components and data.
#
# Assumed vars:
#   MASTER_SSH_EXTERNAL
#   NODE_SSH_EXTERNAL
function cleanup-kubernetes {
  local pids=""
  IFS=',' read -ra node_ssh_info <<< "${NODE_SSH_EXTERNAL}"
  ssh-to-instance-expect "${MASTER_SSH_EXTERNAL}" \
    "sudo ./kube/master-cleanup.sh" & pids="${pids} $!"
  for ssh_info in "${node_ssh_info[@]}"; do
    ssh-to-instance-expect "${ssh_info}" "sudo ./kube/node-cleanup.sh" & pids="${pids} $!"
  done
  wait ${pids}
}

# Start kubernetes component only on nodes. The function assumes that nodes have
# already been setup correctly.
#
# Assumed vars:
#   NODE_SSH_EXTERNAL
function start-node-kubernetes {
  local pids=""
  IFS=',' read -ra node_ssh_info <<< "${NODE_SSH_EXTERNAL}"
  for ssh_info in "${node_ssh_info[@]}"; do
    ssh-to-instance-expect "${ssh_info}" "sudo ./kube/node-start.sh" & pids="${pids} $!"
  done
  wait ${pids}
}

# This is used in both kube-up and kube-add-node to create a comma separated
# string of node internal ips based on the cluster config NODE_IIP_RANGE and
# NUM_NODES. E.g. if NODE_IIP_RANGE is 10.244.1.0/16 and NUM_NODES is 2,
# then output is: "10.244.1.0,10.244.1.1".
# Since the internal ip assignment is consecutive for now, we will have to
# start from the next of the last internal ip we have already assigned.
# For kube-up, we have 0 occupied internal ip to start with. For kube-add-node, we have
# ${NUM_RUNNING_NODES} occupied internal ip.
# One known issue: https://github.com/caicloud/caicloud-kubernetes/issues/283
#
# Assumed vars:
#   NODE_IIP_RANGE
#   NUM_NODES
#   NUM_RUNNING_NODES
#
# Vars set:
#   NODE_IIPS
function create-node-internal-ips-variable {
  # Transform NODE_IIP_RANGE into different info, e.g. 10.244.1.0/16 =>
  #   cidr = 16
  #   ip_octects = 10 244 1 0
  #   mask_octects = 255 255 0 0
  cidr=($(echo "$NODE_IIP_RANGE" | sed -e 's|.*/||'))
  ip_octects=($(echo "$NODE_IIP_RANGE" | sed -e 's|/.*||' -e 's/\./ /g'))
  mask_octects=($(cdr2mask ${cidr} | sed -e 's/\./ /g'))

  # Total Number of hosts in this subnet. e.g. 10.244.1.0/16 => 65535. This number
  # excludes address all-ones address (*.255.255); for all-zeros address (*.0.0),
  # we decides how to exclude it below.
  total_count=$(((2**(32-${cidr}))-1))

  # Number of used hosts in this subnet. E.g. For 10.244.1.0/16, there are already
  # 256 addresses allocated (10.244.0.1, 10.244.0.2, etc, typically for master
  # instances), we need to exclude these IP addresses when counting the real number
  # of nodes we can use. See below comment above how we handle all-zeros address.
  used_count=0
  weight=($((2**32)) $((2**16)) $((2**8)) 1)
  for (( i = 0; i < 4; i++ )); do
    current=$(( ((255 - mask_octects[i]) & ip_octects[i]) * weight[i] ))
    used_count=$(( used_count + current ))
  done

  # If used_count is 0, then our format must be something like 10.244.0.0/16, where
  # host part is all-zeros. In this case, we add one to used_count to exclude the
  # all-zeros address. If used_count is not 0, then we already excluded all-zeros
  # address in the above calculation, e.g. for 10.244.1.0/16, we get 256 used addresses,
  # which includes all-zero address.
  local host_zeros=false
  if [[ ${used_count} == 0 ]]; then
    ((used_count+=1))
    host_zeros=true
  fi

  if (( ${NUM_RUNNING_NODES} + ${NUM_NODES} > (total_count - used_count) )); then
    log "Number of nodes is larger than allowed node internal IP address"
    kube-up-complete N
    exit 1
  fi

  # We could just compute the starting point directly but I'm lazy...
  for (( i = 0; i < ${NUM_RUNNING_NODES}; i++ )); do
    # Avoid using all-zeros address for CIDR like 10.244.0.0/16.
    if [[ ${i} == 0 && ${host_zeros} == true ]]; then
      ((ip_octects[3]+=1))
    fi
    ((ip_octects[3]+=1))
    for (( k = 3; k > 0; k--)); do
      if [[ "${ip_octects[k]}" == "256" ]]; then
        ip_octects[k]=0
        ((ip_octects[k-1]+=1))
      fi
    done
  done

  NODE_IIPS=""
  # Since we've checked the required number of hosts < total number of hosts,
  # we can just simply add 1 to previous IP.
  for (( i = 0; i < ${NUM_NODES}; i++ )); do
    # Avoid using all-zeros address for CIDR like 10.244.0.0/16.
    if [[ ${i} == 0 && ${host_zeros} == true ]]; then
      ((ip_octects[3]+=1))
    fi
    local ip=$(echo "${ip_octects[*]}" | sed 's/ /./g')
    if [[ -z "${NODE_IIPS-}" ]]; then
      NODE_IIPS="${ip}"
    else
      NODE_IIPS="${NODE_IIPS},${ip}"
    fi
    ((ip_octects[3]+=1))
    for (( k = 3; k > 0; k--)); do
      if [[ "${ip_octects[k]}" == "256" ]]; then
        ip_octects[k]=0
        ((ip_octects[k-1]+=1))
      fi
    done
  done
}

# Convert cidr to netmask, e.g. 16 -> 255.255.0.0. This is only called from
# function "create-node-internal-ips-variable".
#
# Input:
#   $1 cidr
function cdr2mask {
  # Number of args to shift, 255..255, first non-255 byte, zeroes
  set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
  [ $1 -gt 1 ] && shift $1 || shift
  echo ${1-0}.${2-0}.${3-0}.${4-0}
}

# Fetch tarball from CAICLOUD_TARBALL_URL and save it to ${KUBE_TEMP}; then
# extract it to ${KUBE_TEMP}. The tarball is used to bring up caicloud kubernetes
# cluster.
#
# Assumed vars:
#   KUBE_TEMP
#   CAICLOUD_KUBE_PKG
#   CAICLOUD_TARBALL_URL
function fetch-and-extract-tarball {
  log "+++++ Fetch and extract caicloud kubernetes tarball"
  cd ${KUBE_TEMP}
  if [[ ! -f /tmp/${CAICLOUD_KUBE_PKG} ]]; then
    wget ${CAICLOUD_TARBALL_URL}
    cp ${CAICLOUD_KUBE_PKG} /tmp
    mv ${CAICLOUD_KUBE_PKG} caicloud-kube.tar.gz
  else
    cp /tmp/${CAICLOUD_KUBE_PKG} ${KUBE_TEMP}/caicloud-kube.tar.gz
  fi
  tar xvzf caicloud-kube.tar.gz
  cd - > /dev/null
}

# Fetch tarball in master instance.
#
# Assumed vars:
#   MASTER_SSH_EXTERNAL
function fetch-tarball-in-master {
  command-exec-and-retry "fetch-tarball-in-master-internal ${MASTER_SSH_EXTERNAL}" 2 "false"
}
function fetch-tarball-in-master-internal {
  log "+++++ Start fetching and installing tarball from: ${CAICLOUD_TARBALL_URL}."

  # Fetch tarball for master node.
  ssh-to-instance-expect "${1}" "wget ${CAICLOUD_TARBALL_URL} -O ~/caicloud-kube.tar.gz && \
sudo mkdir -p /etc/caicloud && sudo cp ~/caicloud-kube.tar.gz /etc/caicloud && \
sudo chmod go-rwx /etc/caicloud"
}

# Distribute tarball from master to nodes. After installation, each node will
# have binaires in ~/kube/master and ~/kube/node. Note, we MUST be able to ssh
# to master without using password.
#
# Assumed vars:
#   CAICLOUD_TARBALL_URL
#   MASTER_SSH_EXTERNAL *
#   NODE_SSH_EXTERNAL *
#   NODE_SSH_INTERNAL *
#   INSTANCE_SSH_EXTERNAL *
function install-binaries-from-master {
  command-exec-and-retry "install-binaries-from-master-internal" 2 "false"
}
function install-binaries-from-master-internal {
  local pids=""
  local fail=0

  # Distribute tarball from master to nodes. Use internal address if possible.
  if [[ -z "${NODE_SSH_INTERNAL:-}" ]]; then
    IFS=',' read -ra node_ssh_info <<< "${NODE_SSH_EXTERNAL}"
  else
    IFS=',' read -ra node_ssh_info <<< "${NODE_SSH_INTERNAL}"
  fi
  IFS=':@' read -ra master_ssh_info <<< "${MASTER_SSH_EXTERNAL}"
  for (( i = 0; i < ${#node_ssh_info[*]}; i++ )); do
    IFS=':@' read -ra ssh_info <<< "${node_ssh_info[$i]}"
    expect <<EOF &
set timeout -1
spawn ssh -t -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=quiet \
  ${master_ssh_info[0]}@${master_ssh_info[2]} \
"sudo cp /etc/caicloud/caicloud-kube.tar.gz ~/ && \
scp -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=quiet \
  ~/caicloud-kube.tar.gz ${ssh_info[0]}@${ssh_info[2]}:~/caicloud-kube.tar.gz"

expect {
  "*?assword*" {
    send -- "${ssh_info[1]}\r"
    exp_continue
  }
  "?ommand failed" {exit 1}
  "lost connection" { exit 1 }
  eof {}
}
EOF
    pids="$pids $!"
  done

  wait-pids "${pids}" "+++++ Wait for tarball to be distributed to all nodes"
  if [[ "$?" != "0" ]]; then
    return 1
  fi

  # Extract and install tarball for all instances.
  pids=""
  IFS=',' read -ra instance_ssh_info <<< "${INSTANCE_SSH_EXTERNAL}"
  for (( i = 0; i < ${#instance_ssh_info[*]}; i++ )); do
    ssh-to-instance-expect "${instance_ssh_info[$i]}" "\
tar xvzf caicloud-kube.tar.gz && mkdir -p ~/kube/master && \
cp caicloud-kube/etcd caicloud-kube/etcdctl caicloud-kube/flanneld caicloud-kube/kube-apiserver \
  caicloud-kube/kube-controller-manager caicloud-kube/kubectl caicloud-kube/kube-scheduler \
  caicloud-kube/kubelet caicloud-kube/kube-proxy ~/kube/master && \
mkdir -p ~/kube/node && \
cp caicloud-kube/etcd caicloud-kube/etcdctl caicloud-kube/flanneld caicloud-kube/kubectl \
  caicloud-kube/kubelet caicloud-kube/kube-proxy ~/kube/node && \
rm -rf caicloud-kube.tar.gz caicloud-kube || \
echo 'Command failed installing tarball binaries on remote host ${instance_ssh_info[$i]}'" &
    pids="$pids $!"
  done

  wait-pids "${pids}" "+++++ Wait for all instances to install tarball"
}

# Ask for a password which will be used for all instances.
#
# Vars set:
#   KUBE_INSTANCE_PASSWORD
function prompt-instance-password {
  read -s -p "Please enter password for new instances: " KUBE_INSTANCE_PASSWORD
  echo
  read -s -p "Password (again): " another
  echo
  if [[ "${KUBE_INSTANCE_PASSWORD}" != "${another}" ]]; then
    log "Passwords do not match"
    exit 1
  fi
}


# -----------------------------------------------------------------------------
# Generic common operations.
# -----------------------------------------------------------------------------
SSH_OPTS="-oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=quiet"

# This function is a wrapper of setup-instance to setup a list of instances.
#
# Assumed vars:
#   INSTANCE_SSH_EXTERNAL
function setup-instances {
  IFS=',' read -ra instance_ssh_info <<< "${INSTANCE_SSH_EXTERNAL}"
  for (( i = 0; i < ${#instance_ssh_info[*]}; i++ )); do
    IFS=':@' read -ra ssh_info <<< "${instance_ssh_info[$i]}"
    setup-instance "${ssh_info[2]}" "${ssh_info[0]}" "${ssh_info[1]}"
  done
}

# This function mainly does the following:
# 1. ssh to the machine and put the host's pub key to instance's authorized_keys,
#    so future ssh commands do not require password to login.
# 2. Also, if username is not 'root', we setup sudoer for the user so that we do
#    not need to feed in password when executing commands.
# 3. Create login user without sudo privilege so that actual user won't have access
#    to stuff like anchnet api keys. The login user will be handed over to caicloud
#    user. Pass empty string to disable creating login user.
#
# Input:
#   $1 Instance external IP address
#   $2 Instance user name
#   $3 Instance user password
#   $4 Login user name
#   $5 Login user password
function setup-instance {
  attempt=0

  while true; do
    log "Attempt $(($attempt+1)) to setup instance ssh for $1"
    expect <<EOF
set timeout $((($attempt+1)*3))
spawn scp -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=quiet \
  $HOME/.ssh/id_rsa.pub ${2}@${1}:~/host_rsa.pub

expect {
  "*?assword*" {
    send -- "${3}\r"
    exp_continue
  }
  "lost connection" { exit 1 }
  timeout { exit 1 }
  eof {}
}
EOF

    expect <<EOF
set timeout $((($attempt+1)*3))
spawn ssh -t -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=quiet \
  ${2}@${1} "\
umask 077 && mkdir -p ~/.ssh && cat ~/host_rsa.pub >> ~/.ssh/authorized_keys && rm -rf ~/host_rsa.pub && \
sudo sh -c 'echo \"${2} ALL=(ALL) NOPASSWD: ALL\" | (EDITOR=\"tee -a\" visudo)'"

expect {
  "*?assword*" {
    send -- "${3}\r"
    exp_continue
  }
  "lost connection" { exit 1 }
  timeout { exit 1 }
  eof {}
}
EOF

    if [[ ! -z "${4:-}" ]]; then
      expect <<EOF
set timeout $((($attempt+1)*3))
spawn ssh -t -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=quiet \
  ${2}@${1} "\
sudo adduser --quiet --disabled-password --gecos \"${4}\" ${4} &&
echo \"${4}:${5}\" | sudo chpasswd"

expect {
  "*?assword*" {
    send -- "${3}\r"
    exp_continue
  }
  "lost connection" { exit 1 }
  timeout { exit 1 }
  eof {}
}
EOF
    fi

    if [[ "$?" != "0" ]]; then
      # We give more attempts for setting up ssh to allow slow instance startup.
      if (( attempt > 40 )); then
        echo
        log "${color_red}Unable to setup instance ssh for $1 (sorry!)${color_norm}" >&2
        kube-up-complete N
        exit 1
      fi
    else
      log "${color_green}[ssh to instance working]${color_norm}"
      break
    fi
    # No need to sleep here, we increment timout in expect.
    log "${color_yellow}[ssh to instance not working yet]${color_norm}"
    attempt=$(($attempt+1))
  done
}

# Wrapper for clean-up-working-dir-internal
function clean-up-working-dir {
  # Only do cleanups on success
  [[ "$?" == "0" ]] || return 1
  command-exec-and-retry "clean-up-working-dir-internal" 3 "false"
}
# This function simply remove the ~/kube directory from instances
#
# Assumed vars:
#   INSTANCE_SSH_EXTERNAL
function clean-up-working-dir-internal {
  local pids=""
  log "+++++ Start cleaning working dir. "

  IFS=',' read -ra instance_ssh_info <<< "${INSTANCE_SSH_EXTERNAL}"
  for ssh_info in "${instance_ssh_info[@]}"; do
    ssh-to-instance-expect "${ssh_info}" "sudo mv ~/kube /etc/caicloud" & pids="${pids} $!"
  done

  log-oneline "+++++ Wait for all instances to clean up working dir ..."
  local fail=0
  for pid in ${pids}; do
    wait $pid || let "fail+=1"
  done
  if [[ "$fail" == "0" ]]; then
    log "${color_green}Done${color_norm}"
    return 0
  else
    log "${color_red}Failed${color_norm}"
    return 1
  fi
}

# Timestamped log, e.g. log "cluster created".
#
# Input:
#   $1 Log string.
function log {
  echo -e "[`TZ=Asia/Shanghai date`] ${1}"
}

# Timestamped log without newline, e.g. log "cluster created".
#
# Input:
#   $1 Log string.
function log-oneline {
  echo -en "[`TZ=Asia/Shanghai date`] ${1}"
}

# Create a temp dir that'll be deleted at the end of bash session.
#
# Vars set:
#   KUBE_TEMP
function ensure-temp-dir {
  if [[ -z ${KUBE_TEMP-} ]]; then
    KUBE_TEMP=$(mktemp -d -t kubernetes.XXXXXX)
    trap-add 'rm -rf "${KUBE_TEMP}"' EXIT
  fi
}

# Create ~/.ssh/id_rsa.pub if it doesn't exist, and make it is added to
# ssh-agent.
function ensure-ssh-agent {
  if [[ ! -f ${HOME}/.ssh/id_rsa.pub ]]; then
    log "+++++++++ Create public/private key pair in ~/.ssh/id_rsa"
    ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''
  fi
  ssh-add -L > /dev/null 2>&1
  # Could not open a connection to authentication agent (ssh-agent),
  # try creating one.
  if [[ "$?" == "2" ]]; then
    eval "$(ssh-agent)" > /dev/null
    trap-add "kill ${SSH_AGENT_PID}" EXIT
  fi
  ssh-add -L > /dev/null 2>&1
  # The agent has no identities, try adding one of the default identities,
  # with or without pass phrase.
  if [[ "$?" == "1" ]]; then
    ssh-add || true
  fi
  # Expect at least one identity to be available.
  if ! ssh-add -L > /dev/null 2>&1; then
    echo "Could not find or add an SSH identity."
    echo "Please start ssh-agent, add your identity, and retry."
    exit 1
  fi
}

# Make sure ~/kube exists on the master/node. This is used in kube-push
# because we now clean up ~/kube directory once the cluster is up and running.
#
# Input:
#   $1 instance external ssh information
function ensure-working-dir {
  ssh-to-instance-expect "${1}" "mkdir -p ~/kube/master ~/kube/node"
}

# Ensure that we have a password created for validating to the master. Note
# the username/password here is used to login to kubernetes cluster, not for
# ssh into machines.
#
# Vars set (if not set already):
#   KUBE_USER
#   KUBE_PASSWORD
function get-password {
  if [[ -z ${KUBE_USER-} ]]; then
    KUBE_USER=admin
  fi
  if [[ -z ${KUBE_PASSWORD-} ]]; then
    KUBE_PASSWORD=$(python -c 'import string,random; print "".join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(16))')
  fi
}

# Add trap cmd to signal(s). Since there is no better way of setting multiple
# trap cmds on a signal, we are just appending new command to the current trap
# cmd.
#
# Input:
#   $1 trap cmd to add
#   $2 signals to add cmd to
function trap-add {
  local trap_add_cmd=$1; shift
  local new_cmd=""
  for trap_add_name in "$@"; do
    # Grab the currently defined trap commands for this trap
    existing_cmd=`trap -p "${trap_add_name}" |  awk -F"'" '{print $2}'`

    if [[ -z "${existing_cmd}" ]];then
      new_cmd=${trap_add_cmd}
    else
      new_cmd="${existing_cmd};${trap_add_cmd}"
    fi

    # Assign the test
    trap "${new_cmd}" "${trap_add_name}" || \
      echo "unable to add to trap ${trap_add_name}"
  done
}

# ssh to given node and execute command, e.g.
#   ssh-to-instance "root:password@43.254.54.58" "touch abc && mkdir def"
#
# Input:
#   $1 ssh info, e.g. root:password@43.254.54.58
#   $2 Command string
#   $3 Optional timeout
function ssh-to-instance-expect {
  IFS=':@' read -ra ssh_info <<< "${1}"
  timeout=${3:-"-1"}
  expect <<EOF
set timeout ${timeout}
spawn ssh -t ${SSH_OPTS} ${ssh_info[0]}@${ssh_info[2]} ${2}
expect {
  "*?assword*" {
    send -- "${ssh_info[1]}\r"
    exp_continue
  }
  "?ommand failed" {exit 1}
  "lost connection" { exit 1 }
  eof {}
}
EOF
}

# scp files to given instance, e.g.
#  scp-to-instance "root:password@43.254.54.58" "file1 file2" "~/destdir"
#
# Input:
#   $1 ssh info, e.g. root:password@43.254.54.58
#   $2 files to copy, separate with space
#   $3 destination directory on remote machine
#   $4 Optional timeout
function scp-to-instance-expect {
  IFS=':@' read -ra ssh_info <<< "${1}"
  timeout=${4:-"-1"}
  expect <<EOF
set timeout ${timeout}
spawn scp -r ${SSH_OPTS} ${2} ${ssh_info[0]}@${ssh_info[2]}:${3}
expect {
  "*?assword:" {
    send -- "${ssh_info[1]}\r"
    exp_continue
  }
  "?ommand failed" {exit 1}
  "lost connection" { exit 1 }
  eof {}
}
EOF
}

# scp files to given instance and execute command, e.g.
#  scp-to-instance "root:password@43.254.54.58" "file1" "~/destdir" "source ~/destdir/file1"
#
# Input:
#   $1 ssh info, e.g. root:password@43.254.54.58
#   $2 files to copy, separate with space
#   $3 destination directory on remote machine
#   $4 Command string
#   $5 Optional timeout
function scp-then-execute-expect {
  IFS=':@' read -ra ssh_info <<< "${1}"
  timeout=${5:-"-1"}
  expect <<EOF
set timeout ${timeout}
spawn scp -r ${SSH_OPTS} ${2} ${ssh_info[0]}@${ssh_info[2]}:${3}
expect {
  "*?assword:" {
    send -- "${ssh_info[1]}\r"
    exp_continue
  }
  "?ommand failed" {exit 1}
  "lost connection" { exit 1 }
  eof {}
}
EOF

  expect <<EOF
set timeout ${timeout}
spawn ssh -t ${SSH_OPTS} ${ssh_info[0]}@${ssh_info[2]} ${4}
expect {
  "*?assword*" {
    send -- "${ssh_info[1]}\r"
    exp_continue
  }
  "?ommand failed" {exit 1}
  "lost connection" { exit 1 }
  eof {}
}
EOF
}

# ssh to given node and execute command, e.g.
#   ssh-to-instance "root:password@43.254.54.58" "touch abc && mkdir def"
# The function doesn't use expect, just plan ssh.
#
# Input:
#   $1 ssh info, e.g. root:password@43.254.54.58
#   $2 Command string
function ssh-to-instance {
  IFS=':@' read -ra ssh_info <<< "${1}"
  ssh -t ${SSH_OPTS} ${ssh_info[0]}@${ssh_info[2]} ${2}
}

# scp files to given instance, e.g.
#  scp-to-instance "root:password@43.254.54.58" "file1 file2" "~/destdir"
# The function doesn't use expect, just plan scp.
#
# Input:
#   $1 ssh info, e.g. root:password@43.254.54.58
#   $2 files to copy, separate with space
#   $3 destination directory on remote machine
function scp-to-instance {
  IFS=':@' read -ra ssh_info <<< "${1}"
  scp -r ${SSH_OPTS} ${2} ${ssh_info[0]}@${ssh_info[2]}:${3}
}

# scp files to given instance and execute command, e.g.
#  scp-to-instance "root:password@43.254.54.58" "file1" "~/destdir" "source ~/destdir/file1"
# The function doesn't use expect, just plan ssh and scp.
#
# Input:
#   $1 ssh info, e.g. root:password@43.254.54.58
#   $2 files to copy, separate with space
#   $3 destination directory on remote machine
#   $4 Command string
function scp-then-execute {
  IFS=':@' read -ra ssh_info <<< "${1}"
  scp -r ${SSH_OPTS} ${2} ${ssh_info[0]}@${ssh_info[2]}:${3}
  ssh -t ${SSH_OPTS} ${ssh_info[0]}@${ssh_info[2]} ${4}
}

# Wait a list of pids (or whitespace separated). If any one of them fails,
# return 1, otherwise, return 0.
#
# Input:
#   $1 Pids to wait
#   $2 A string of what's being waited
function wait-pids {
  log-oneline "${2}"
  local fail=0
  for pid in ${1}; do
    wait ${pid} || let "fail+=1"
  done
  if [[ "${fail}" == "0" ]]; then
    echo -e "${color_green}Done${color_norm}"
    return 0
  else
    echo -e "${color_red}Failed${color_norm}"
    return 1
  fi
}

# Build all binaries using docker. Note there are some restrictions we need
# to fix if the provision host is running in mainland China; it is fixed in
# k8s-replace.sh.
function caicloud-build-release {
  cd ${KUBE_ROOT}
  hack/caicloud/k8s-replace.sh
  trap-add '${KUBE_ROOT}/hack/caicloud/k8s-restore.sh' EXIT
  build/release.sh
  cd -
}

# Like build release, but only build server binary (linux amd64).
function caicloud-build-server {
  cd ${KUBE_ROOT}
  hack/caicloud/k8s-replace.sh
  trap-add '${KUBE_ROOT}/hack/caicloud/k8s-restore.sh' EXIT
  build/run.sh hack/build-go.sh
  cd -
}

# Build cross platform binaries. Use DOCKER_HOST if docker is running elsewhere.
function caicloud-build-cross {
  cd ${KUBE_ROOT}
  hack/caicloud/k8s-replace.sh
  trap-add '${KUBE_ROOT}/hack/caicloud/k8s-restore.sh' EXIT
  ./build/run.sh hack/build-cross.sh
  cd -
}

# Build release tarball and push to qiniu.
#
# Inputs:
#   $1 Tarball version
function caicloud-build-tarball {
  cd ${KUBE_ROOT}
  BUILD_CLOUD_IMAGE=N ./hack/caicloud/build-release.sh ${1}
  cd -
}

# Build local binaries.
#
# Inputs:
#   $1 Binary target to build, e.g. "cmd/kubectl" to only build kubectl
function caicloud-build-local {
  cd ${KUBE_ROOT}
  hack/caicloud/k8s-replace.sh
  trap-add '${KUBE_ROOT}/hack/caicloud/k8s-restore.sh' EXIT
  hack/build-go.sh "$@"
  cd -
}

# Build local kubectl binary, put under _output/local/bin/kubectl.
function caicloud-build-local-kubectl {
  caicloud-build-local "cmd/kubectl"
}

# Clean up repository.
function make-clean {
  cd ${KUBE_ROOT}
  make clean
  cd -
}

# Evaluate a json string and return required fields. Example:
# $ echo '{"action":"RunInstances", "ret_code":0}' | json_val '["action"]'
# $ RunInstance
#
# Input:
#   $1 A valid string for indexing json string.
#   $stdin A json string
#
# Output:
#   stdout: value at given index (empty if error occurs).
#   stderr: any parsing error
function json_val {
  python -c '
import json,sys,datetime,pytz
try:
  obj = json.load(sys.stdin)
  print obj'$1'
except Exception as e:
  timestamp = datetime.datetime.now(pytz.timezone("Asia/Shanghai")).strftime("%a %b %d %H:%M:%S %Z %Y")
  sys.stderr.write("[%s] Unable to parse json string: %s. Please retry\n" % (timestamp, e))
'
}

# Evaluate a json string and return length of required fields. Example:
# $ echo '{"price": [{"item1":12}, {"item2":21}]}' | json_len '["price"]'
# $ 2
#
# Input:
#   $1 A valid string for indexing json string.
#   $stdin A json string
#
# Output:
#   stdout: length at given index (empty if error occurs).
#   stderr: any parsing error
function json_len {
  python -c '
import json,sys,datetime,pytz
try:
  obj = json.load(sys.stdin)
  print len(obj'$1')
except Exception as e:
  timestamp = datetime.datetime.now(pytz.timezone("Asia/Shanghai")).strftime("%a %b %d %H:%M:%S %Z %Y")
  sys.stderr.write("[%s] Unable to parse json string: %s. Please retry\n" % (timestamp, e))
'
}

# Add a top level field in a json file. e.g.:
# $ json_add_field key.json "privatekey" "456"
# {"publickey": "123"} ==> {"publickey": "123", "privatekey": "456"}
#
# Input:
#   $1 Absolute path to the json file
#   $2 Key of the field to be added
#   $3 Value of the field to be added
#
# Output:
#   A top level field gets added to $1
function json_add_field {
  python -c '
import json
with open("'$1'") as f:
  data = json.load(f)
data.update({"'$2'": "'$3'"})
with open("'$1'", "w") as f:
  json.dump(data, f)
'
}

# Like python's join, e.g.
#  ARRAY=[a b c d]
#  JOINED=`join "," $ARRAY[@]`
function join {
  local IFS="$1"
  shift
  echo "$*"
}

# Find kubectl binary from pre-defined locations. If found, set KUBECTL_PATH
# variable; otherwise, do nothing. This is used for kube-up - if KUBECTL_PATH
# is not set, kubernetes will look in the following path, which doesn't always
# present.
#  "${KUBE_ROOT}/_output/dockerized/bin/${host_os}/${host_arch}/kubectl"
#  "${KUBE_ROOT}/_output/local/bin/${host_os}/${host_arch}/kubectl"
#  "${KUBE_ROOT}/platforms/${host_os}/${host_arch}/kubectl"
#
# Vars set:
#   KUBECTL_PATH
function find-kubectl-binary {
  # First, search from possible locations.
  locations=("/opt/bin/kubectl" "/usr/bin/kubectl" "/usr/local/bin/kubectl" "${GOPATH:-}/bin/kubectl")
  for location in ${locations[@]}; do
    if [[ -x ${location} ]]; then
      export KUBECTL_PATH=${location}
      break
    fi
  done
  # Second, if not found, use 'which kubectl' if it exists.
  if [[ -z "${KUBECTL_PATH-}" ]]; then
    if [[ -x `which kubectl` ]]; then
      export KUBECTL_PATH=`which kubectl`
    fi
  fi
}

# A helper function that executes a command (or shell function), and retries on
# failure. If the command can't succeed within given attempts, the script will
# exit directly.
#
# Input:
#   $1 command string to execute
#   $2 number of retries, default to 20
#   $3 report failure; if true, report failure to caicloud cluster manager.
function command-exec-and-retry {
  local attempt=0
  local count=${2-20}
  local report=${3-"true"}
  while true; do
    eval $1
    if [[ "$?" != "0" ]]; then
      if (( attempt >= ${count} )); then
        echo
        log "${color_red}Unable to execute command [$1]: Timeout${color_norm}" >&2
        if [[ "${report}" = "true" ]]; then
           kube-up-complete N
        fi
        exit 1
      fi
    else
      log "${color_green}Command [$1] ok${color_norm}" >&2
      break
    fi
    log "${color_yellow}Command [$1] not ok, will retry${color_norm}" >&2
    attempt=$(($attempt+1))
    sleep $(($attempt*2))
  done
}

# Provides utility functions for talking back to cluster deployment executor.

# Sends out request based on the input url.
#
# Input:
#   $1 The full url to access.
#
# Output:
#   stdout: normal execution information.
#   stderr: Record the url if fails.
function send-request-with-retry {
  if [[ ! -z $1 ]]; then
    local attempt=0
    local full_command="curl -sL -w %{http_code} $1 -o /dev/null"
    while true; do
      echo "Attempt ${attempt}: ${full_command}"
      local resp_code=$(${full_command})
      echo "response_code: ${resp_code}"
      if [[ ${resp_code} == "200" ]]; then
        break
      fi
      attempt=$(($attempt+1))
      if (( attempt > 3 )); then
        echo "Failed to send the following request to executor \n: $1" 1>&2
        break
      fi
      sleep $(($attempt*2))
    done
  fi
}

# Report a list of ips back to the executor for recording.
#
# Input:
#   $1 The list of comma deliminated ips.
#   $2 M or N. M indicates the ips reported belong to the master,
#      and N indicates ips are for regular nodes.
#
# Assumed vars:
#   EXECUTOR_HOST_NAME
#   EXECUTION_ID
function report-ips {
  if [[ ${REPORT_KUBE_STATUS-} == "Y" ]]; then
    if [[ ! -z "${EXECUTOR_HOST_NAME-}" && ! -z "${EXECUTION_ID-}" ]]; then
      send-request-with-retry "$EXECUTOR_HOST_NAME/report_ips?id=${EXECUTION_ID}&ips=$1&type=$2"
    else
      echo "EXECUTOR_HOST_NAME or EXECUTION_ID is not set up. report-ips failed."
    fi
  fi
}

# Assumed vars:
#   REPORT_KUBE_STATUS
#   MASTER_INTERNAL_SSH_INFO
#   NODE_INTERNAL_SSH_INFO
#
# Optional vars:
#   MASTER_EXTERNAR_SSH_INFO
#   NODE_EXTERNAL_SSH_INFO
function report-ips-to-executor {
  if [[ ${REPORT_KUBE_STATUS-} == "N" ]]; then
    return
  fi

  if [[ -z "${MASTER_EXTERNAL_SSH_INFO-}" ]]; then
    MASTER_EXTERNAL_SSH_INFO=${MASTER_INTERNAL_SSH_INFO}
  fi
  if [[ -z "${NODE_EXTERNAL_SSH_INFO-}" ]]; then
    NODE_EXTERNAL_SSH_INFO=${NODE_INTERNAL_SSH_INFO}
  fi

  MASTER_EIPS=""
  IFS=',' read -ra external_ssh_info <<< "${MASTER_EXTERNAL_SSH_INFO}"
  for (( i = 0; i < ${#external_ssh_info[*]}; i++ )); do
    IFS=':@' read -ra e_ssh_info <<< "${external_ssh_info[$i]}"
    MASTER_EIPS="${MASTER_EIPS},${e_ssh_info[2]}"
  done
  MASTER_EIPS=${MASTER_EIPS#,}
  report-ips ${MASTER_EIPS} M

  NODE_EIPS=""
  IFS=',' read -ra external_ssh_info <<< "${NODE_EXTERNAL_SSH_INFO}"
  for (( i = 0; i < ${#external_ssh_info[*]}; i++ )); do
    IFS=':@' read -ra e_ssh_info <<< "${external_ssh_info[$i]}"
    NODE_EIPS="${NODE_EIPS},${e_ssh_info[2]}"
  done
  NODE_EIPS=${NODE_EIPS#,}
  report-ips ${NODE_EIPS} N
}


# Report a list of instance ids back to the executor for recording.
#
# Input:
#   $1 The list of comma deliminated instance ids.
#   $2 M or N. M indicates the ips reported belong to the master,
#      and N indicates ips are for regular nodes.
#
# Assumed vars:
#   EXECUTOR_HOST_NAME
#   EXECUTION_ID
function report-instance-ids {
  if [[ ${REPORT_KUBE_STATUS-} == "Y" ]]; then
    if [[ ! -z "${EXECUTOR_HOST_NAME-}" && ! -z "${EXECUTION_ID-}" ]]; then
      send-request-with-retry "$EXECUTOR_HOST_NAME/report_instance_ids?id=${EXECUTION_ID}&instances=$1&type=$2"
    else
      echo "EXECUTOR_HOST_NAME or EXECUTION_ID is not set up. report-instance-ids failed."
    fi
  fi
}

# Report a list of security group ids back to the executor for recording.
#
# Input:
#   $1 The list of comma deliminated security group ids.
#   $2 M or N. M indicates the ips reported belong to the master,
#      and N indicates ips are for regular nodes.
#
# Assumed vars:
#   EXECUTOR_HOST_NAME
#   EXECUTION_ID
function report-security-group-ids {
  if [[ ${REPORT_KUBE_STATUS-} == "Y" ]]; then
    if [[ ! -z "${EXECUTOR_HOST_NAME-}" && ! -z "${EXECUTION_ID-}" ]]; then
      send-request-with-retry "$EXECUTOR_HOST_NAME/report_security_group_ids?id=${EXECUTION_ID}&security_groups=$1&type=$2"
    else
      echo "EXECUTOR_HOST_NAME or EXECUTION_ID is not set up. report-security-group-ids failed."
    fi
  fi
}

# Report a list of external ip ids back to the executor for recording.
#
# Input:
#   $1 The list of comma deliminated eip ids.
#
# Assumed vars:
#   EXECUTOR_HOST_NAME
#   EXECUTION_ID
function report-eip-ids {
  if [[ ${REPORT_KUBE_STATUS-} == "Y" ]]; then
    if [[ ! -z "${EXECUTOR_HOST_NAME-}" && ! -z "${EXECUTION_ID-}" ]]; then
      send-request-with-retry "$EXECUTOR_HOST_NAME/report_eip_ids?id=${EXECUTION_ID}&eips=$1"
    else
      echo "EXECUTOR_HOST_NAME or EXECUTION_ID is not set up. report-eip-ids failed."
    fi
  fi
}

# Report project ID (anchnet subaccount).
#
# Assumed vars:
#   EXECUTOR_HOST_NAME
#   EXECUTION_ID
function report-project-id {
  if [[ ${REPORT_KUBE_STATUS-} == "Y" ]]; then
    if [[ ! -z "${EXECUTOR_HOST_NAME-}" && ! -z "${KUBE_USER-}" ]]; then
      send-request-with-retry "$EXECUTOR_HOST_NAME/report_project_id?uid=${PROJECT_USER}&projectid=$1"
    else
      echo "EXECUTOR_HOST_NAME or KUBE_USER is not set up. report-project-id failed."
    fi
  fi
}

# Send a log to executor.
#
# Input:
#   $1 a code of LogLevelType in execution_report_collection.go
#   $2 a message to log
#
# Assumed vars:
#   EXECUTOR_HOST_NAME
#   EXECUTION_ID
function report-log-entry {
  message=`echo $2 | base64`
  if [[ ${REPORT_KUBE_STATUS-} == "Y" ]]; then
    if [[ ! -z "${EXECUTOR_HOST_NAME-}" && ! -z "${EXECUTION_ID-}" ]]; then
      send-request-with-retry "$EXECUTOR_HOST_NAME/log?id=${EXECUTION_ID}&level=$1&encoded_msg=$message"
    else
      echo "EXECUTOR_HOST_NAME or EXECUTION_ID is not set up. report-log-entry failed."
    fi
  fi
}

# Send a user message log. The message will be sent to end user.
#
# Input:
#   $1 a message to log
#
# Assumed vars:
#   EXECUTOR_HOST_NAME
#   EXECUTION_ID
function report-user-message {
  # "1" is the log level set in executor; the level means "Info" and will be sent to end user.
  report-log-entry "1" "$1"
}

# Create inventory file for ansible
#
# Note:
#   Make sure ansible_host is host_ip instead of hostname.
#   MASTER_INSTACE_ID_INFO and NODE_INSTACE_ID_INFO is used for cloudproviders,
#   for example aliyun, anchnet. We will use instance id as the inventory_hostname.
#
# Assumed vars:
#   MASTER_INTERNAL_SSH_INFO
#   NODE_INTERNAL_SSH_INFO
#   KUBE_CURRENT
#   MASTER_NAME_PREFIX
#   NODE_NAME_PREFIX
#
# Optional vars:
#   MASTER_EXTERNAL_SSH_INFO
#   NODE_EXTERNAL_SSH_INFO
#   MASTER_INSTACE_ID_INFO
#   NODE_INSTACE_ID_INFO
function create-inventory-file {
  if [[ -z "${MASTER_EXTERNAL_SSH_INFO-}" ]]; then
    MASTER_EXTERNAL_SSH_INFO=${MASTER_INTERNAL_SSH_INFO}
  fi
  if [[ -z "${NODE_EXTERNAL_SSH_INFO-}" ]]; then
    NODE_EXTERNAL_SSH_INFO=${NODE_INTERNAL_SSH_INFO}
  fi

  inventory_file=$KUBE_CURRENT/inventory
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
      hostname_in_ventory="${instance_id_info[i]}"
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
      hostname_in_ventory="${instance_id_info[i]}"
    else
      hostname_in_ventory="${MASTER_NAME_PREFIX}${j}"
    fi
    IFS=':@' read -ra e_ssh_info <<< "${external_ssh_info[$i]}"
    IFS=':@' read -ra i_ssh_info <<< "${internal_ssh_info[$i]}"
    echo "${hostname_in_ventory} ansible_host=${e_ssh_info[2]} ansible_user=${e_ssh_info[0]} ansible_ssh_pass=${e_ssh_info[1]} internal_ip=${i_ssh_info[2]}" >> $inventory_file
  done
  echo "" >> $inventory_file

  # Set node roles
  echo "[nodes]" >> $inventory_file
  IFS=',' read -ra external_ssh_info <<< "${NODE_EXTERNAL_SSH_INFO}"
  IFS=',' read -ra internal_ssh_info <<< "${NODE_INTERNAL_SSH_INFO}"
  if [[ ! -z "${NODE_INSTACE_ID_INFO-}" ]]; then
    IFS=',' read -ra instance_id_info <<< "${NODE_INSTACE_ID_INFO}"
  fi

  for (( i = 0; i < ${#external_ssh_info[*]}; i++ )); do
    j=$((i+1))
    if [[ ! -z "${NODE_INSTACE_ID_INFO-}" ]]; then
      hostname_in_ventory="${instance_id_info[i]}"
    else
      hostname_in_ventory="${NODE_NAME_PREFIX}${j}"
    fi
    IFS=':@' read -ra e_ssh_info <<< "${external_ssh_info[$i]}"
    IFS=':@' read -ra i_ssh_info <<< "${internal_ssh_info[$i]}"
    echo "${hostname_in_ventory} ansible_host=${e_ssh_info[2]} ansible_user=${e_ssh_info[0]} ansible_ssh_pass=${e_ssh_info[1]} internal_ip=${i_ssh_info[2]}" >> $inventory_file
  done
  echo "" >> $inventory_file
}

# -----------------------------------------------------------------------------
# Create extra vars json file for ansible-playbook
#
# Environment variables passing in a json formatted string to extra-vars.
# If not seting these environment variables, It will use the default values.
#
# We will resolve the environment variables according prefix.
#
# Assumed vars:
#   KUBE_CURRENT
#   K8S_STRING_PREFIX
#   K8S_NUMBER_PREFIX
# -----------------------------------------------------------------------------
function create-extra-vars-json-file {
  create-extra-vars-json-file-common ${KUBE_CURRENT}/extra_vars.json ${K8S_STRING_PREFIX} ${K8S_NUMBER_PREFIX}
}

# Input:
#   $1 extra vars file
#   $2 string prefix
#   $3 number prefix
function create-extra-vars-json-file-common {
  extra_vars_file=${1}
  string_prefix=${2}
  number_prefix=${3}

  touch ${extra_vars_file}

  echo "{" > ${extra_vars_file}

  OLDIFS=$IFS

  # resolve string type environment variables.
  set | grep "^${string_prefix}*" | \
  while read line; do
    IFS='=' read -ra var_array <<< "${line}"
    # Get XX_YY and change into lowercase: xx_yy
    var_name=`eval echo \$\{var_array[0]\#${string_prefix}\} | tr '[:upper:]' '[:lower:]'`
    echo "  \"${var_name}\": \"${var_array[1]}\"," >> ${extra_vars_file}
  done

  # resolve number type environment variables.
  set | grep "^${number_prefix}*" | \
  while read line; do
    IFS='=' read -ra var_array <<< "${line}"
    # Get XX_YY and change into lowercase: xx_yy
    var_name=`eval echo \$\{var_array[0]\#${number_prefix}\} | tr '[:upper:]' '[:lower:]'`
    echo "  \"${var_name}\": ${var_array[1]}," >> ${extra_vars_file}
  done

  IFS=$OLDIFS

  # Remove the trailing comma
  sed -i -zr 's/,([^,]*$)/\1/' ${extra_vars_file}

  echo "}" >> ${extra_vars_file}
}

# Assumed vars:
#   KUBE_CURRENT
#   KUBE_ROOT
function start-kubernetes-by-ansible {
  ansible-playbook -v -i $KUBE_CURRENT/inventory --extra-vars "@$KUBE_CURRENT/extra_vars.json" $KUBE_ROOT/cluster/caicloud-ansible/cluster.yml
}

# Assumed vars:
#   KUBE_CURRENT
#   KUBE_ROOT
function clear-kubernetes-by-ansible {
  ansible-playbook -v -i $KUBE_CURRENT/inventory --extra-vars "@$KUBE_CURRENT/extra_vars.json" $KUBE_ROOT/cluster/caicloud-ansible/playbooks/adhoc/uninstall.yml
}

# Install ansible.
#
# Assumed vars:
#   ANSIBLE_VERSION
function install-ansible {
  set -e

  os_distro=$(grep '^NAME=' /etc/os-release | sed s'/NAME=//' | sed s'/"//g' | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

  if [[ ${os_distro} == "ubuntu" ]]; then
    sudo apt-get install -y build-essential python-dev python-pip libxml2-dev libxslt1-dev zlib1g-dev libffi-dev libssl-dev expect sshpass
  elif [[ ${os_distro} == "centos" ]]; then
    sudo yum install -y epel-release gcc g++ kernel-devel python-simplejson openssl-devel python-devel libffi-devel python-pip expect sshpass
    sudo yum clean all
  fi

  sudo pip install --upgrade pip
  sudo pip install setuptools
  sudo pip install --upgrade setuptools
  sudo pip install simplejson
  sudo pip install --upgrade simplejson
  sudo pip install netaddr
  sudo pip install ansible==${ANSIBLE_VERSION}
  echo ""
  ansible --version

  set +e
}

function install-ntpdate {
  if [[ -z "${os_distro-}" ]]; then
    os_distro=$(grep '^NAME=' /etc/os-release | sed s'/NAME=//' | sed s'/"//g' | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
  fi

  if [[ ${os_distro} == "ubuntu" ]]; then
    sudo apt-get install -y ntpdate
  elif [[ ${os_distro} == "centos" ]]; then
    sudo yum install -y ntpdate
  fi
}
