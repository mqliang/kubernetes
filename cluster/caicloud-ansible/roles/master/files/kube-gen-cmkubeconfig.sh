#!/bin/bash

basic_auth_dir=${TOKEN_DIR:-/var/srv/kubernetes}
basic_auth_file="${basic_auth_dir}/basic-auth.csv"

if [[ ! -s "${basic_auth_file}" ]]; then
  echo "Error: file[${basic_auth_file}] is empty." >&2
  exit 1
fi

# content: password,username,groupname
content="`cat ${basic_auth_file}`"

# get user name and password
USER_NAME_PASSWORD="${content%,*}"
USER_NAME="${USER_NAME_PASSWORD#*,}"
PASSWORD="${USER_NAME_PASSWORD%,*}"

#############################################################################
# Generate kubeconfig data for the control machine.
# Assumed vars:
#   CM_KUBECONFIG
#   MASTER_IP
#   USER_NAME
#   PASSWORD
#   CONTEXT
#   USER_CERT_DIR
#   CAICLOUD_CERT_DIR
#############################################################################
# Make sure kubectl in PATH
kubectl=`which kubectl`
if [[ -z "${kubectl}" ]]; then
  echo "Can't find kubectl binary in PATH." >&2
  exit 1
fi

export KUBECONFIG=${CM_KUBECONFIG}
# KUBECONFIG determines the file we write to, but it may not exist yet
if [[ ! -e "${KUBECONFIG}" ]]; then
  mkdir -p $(dirname "${KUBECONFIG}")
  touch "${KUBECONFIG}"
fi

cluster_args=(
    "--server=https://${MASTER_IP}"
)

if [[ -z "${CA_CERT_DIR:-}" ]]; then
  cluster_args+=("--insecure-skip-tls-verify=true")
else
  cluster_args+=(
    "--certificate-authority=${CA_CERT_DIR}/ca.crt"
    "--embed-certs=true"
  )
fi

user_args=()
if [[ ! -z "${USER_NAME:-}" && ! -z "${PASSWORD:-}" ]]; then
  user_args+=(
   "--username=${USER_NAME}"
   "--password=${PASSWORD}"
  )
fi
if [[ ! -z "${CERT_DIR:-}" ]]; then
  user_args+=(
   "--client-certificate=${CERT_DIR}/kubecfg.crt"
   "--client-key=${CERT_DIR}/kubecfg.key"
   "--embed-certs=true"
  )
fi

"${kubectl}" config set-cluster "${CONTEXT}" "${cluster_args[@]}"
if [[ -n "${user_args[@]:-}" ]]; then
  "${kubectl}" config set-credentials "${CONTEXT}" "${user_args[@]}"
fi
"${kubectl}" config set-context "${CONTEXT}" --cluster="${CONTEXT}" --user="${CONTEXT}"
"${kubectl}" config use-context "${CONTEXT}"  --cluster="${CONTEXT}"

echo "Done : wrote config for ${CONTEXT} to ${KUBECONFIG}"
