#!/bin/bash

abac_policy_dir=${TOKEN_DIR:-/var/srv/kubernetes}
abac_policy_file="${abac_policy_dir}/abac.json"

create_accounts=($@)

if [ ! -f ${abac_policy_file} ]; then
  echo "Cannot find abac policy file, It should be create by kube-gen-abac-policy-generic.sh"
  exit 1
fi
for account in "${create_accounts[@]}"; do
  if grep "${account}" "${abac_policy_file}" ; then
    continue
  fi
  echo "{\"apiVersion\":\"abac.authorization.kubernetes.io/v1beta1\",\"kind\":\"Policy\",\"spec\":{\"user\":\"${account}\",\"namespace\":\"*\",\"resource\":\"*\",\"apiGroup\":\"*\"}}" >> ${abac_policy_file}
  echo "Add ${account} abac policy"
done
