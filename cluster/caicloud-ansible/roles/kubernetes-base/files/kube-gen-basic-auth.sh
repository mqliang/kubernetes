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
umask 077
echo "${PASSWORD},${USER_NAME},admin" > ${basic_auth_file}
echo "Done : generated 'basic-auth.csv'."
