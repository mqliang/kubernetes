#!/bin/bash

basic_auth_dir=${TOKEN_DIR:-/var/srv/kubernetes}
basic_auth_file="${basic_auth_dir}/basic-auth.csv"

# Ensure that we have a password created for validating to the master. Note
# the username/password here is used to login to kubernetes cluster, not for
# ssh into machines.
#
# Vars set (if not set already):
#   KUBE_USER
#   KUBE_PASSWORD
if [[ -z "${USER_NAME-}" ]]; then
  USER_NAME=admin
fi
if [[ -z "${PASSWORD-}" ]]; then
  PASSWORD=$(python -c 'import string,random; print "".join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(16))')
fi

#############################################################################
# Create basic-auth.csv used by apiserver to authenticate clients using HTTP basic auth.
#############################################################################
(
  umask 077
  echo "${PASSWORD},${USER_NAME},admin" > ${basic_auth_file}
)

#############################################################################
# Generate kubeconfig data for the control machine.
# Assumed vars:
#   CM_KUBECONFIG
#   KUBE_MASTER_IP
#   KUBE_USER
#   KUBE_PASSWORD
#   CONTEXT
#
# If the apiserver supports bearer auth, also provide:
#   KUBE_BEARER_TOKEN
#
# The following can be omitted for --insecure-skip-tls-verify
#   KUBE_CERT
#   KUBE_KEY
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

if [[ -z "${CAICLOUD_CERT_DIR:-}" ]]; then
  cluster_args+=("--insecure-skip-tls-verify=true")
else
  cluster_args+=(
    "--certificate-authority=${CAICLOUD_CERT_DIR}/ca.crt"
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
if [[ ! -z "${USER_CERT_DIR:-}" ]]; then
  user_args+=(
   "--client-certificate=${USER_CERT_DIR}/kubecfg.crt"
   "--client-key=${USER_CERT_DIR}/kubecfg.key"
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
