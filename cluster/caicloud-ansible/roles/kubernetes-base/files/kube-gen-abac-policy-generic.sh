#!/bin/bash

abac_policy_dir=${TOKEN_DIR:-/var/srv/kubernetes}
abac_policy_file="${abac_policy_dir}/abac.json"

#############################################################################
# Create abac.json used by apiserver to controll access
#############################################################################
touch "${abac_policy_file}"
echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"*\",\"nonResourcePath\":\"*\",\"readonly\":true}}" > ${abac_policy_file}
echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"healthz\",\"nonResourcePath\":\"/healthz\",\"readonly\":true}}" >> ${abac_policy_file}
echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"admin\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> ${abac_policy_file}
echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"system:controller_manager\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> ${abac_policy_file}
echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"kubelet\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> ${abac_policy_file}
echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"kube_proxy\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> ${abac_policy_file}
echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"system:logging\",\"namespace\": \"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> ${abac_policy_file}
echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"system:monitoring\",\"namespace\": \"*\",\"resource\": \"*\",\"apiGroup\":\"*\"}}" >> ${abac_policy_file}
echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"system:serviceaccount:kube-system:default\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> ${abac_policy_file}
echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"system:serviceaccount:default:default\",\"namespace\":\"default\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> ${abac_policy_file}
echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"group\":\"admin\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> ${abac_policy_file}
echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"group\":\"viewer\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\",\"readonly\":true}}" >> ${abac_policy_file}
