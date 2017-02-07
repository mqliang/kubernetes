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

# The script restores changes from k8s-replace.sh. This is necessary since we
# don't want to change upstream code.

KUBE_ROOT=$(dirname "${BASH_SOURCE}")/../..

# Restore all 'gcr.io' images from index.caicloud.io.
PATTERNS=(
  "index.caicloud.io/caicloudgcr/google_containers_[^\", ]*"
  "index.caicloud.io/caicloudgcr/google-containers_[^\", ]*"
  "index.caicloud.io/caicloudgcr/google_samples_[^\", ]*"
  "index.caicloud.io/caicloudgcr/google-samples_[^\", ]*"
)
SUBSTITUTIONS=(
  "s|index.caicloud.io/caicloudgcr/google_containers_|gcr.io/google_containers/|g"
  "s|index.caicloud.io/caicloudgcr/google-containers_|gcr.io/google-containers/|g"
  "s|index.caicloud.io/caicloudgcr/google_samples_|gcr.io/google_samples/|g"
  "s|index.caicloud.io/caicloudgcr/google-samples_|gcr.io/google-samples/|g"
)

for i in `seq "${#PATTERNS[@]}"`; do
  index=$(($i-1))
  grep -rl "${PATTERNS[$index]}" \
       --include \*.go \
       --include \*.json \
       --include \*.yaml \
       --include \*.yaml.in \
       --include \*.yml \
       --include Dockerfile \
       --include Makefile \
       --include \*.manifest \
       ${KUBE_ROOT}/test \
       ${KUBE_ROOT}/test/images \
       ${KUBE_ROOT}/docs/user-guide \
       ${KUBE_ROOT}/examples \
       ${KUBE_ROOT}/cluster/addons \
       ${KUBE_ROOT}/cluster/saltbase \
       ${KUBE_ROOT}/contrib \
       ${KUBE_ROOT}/docs \
       ${KUBE_ROOT}/build \
       ${KUBE_ROOT}/cmd \
       ${KUBE_ROOT}/test/e2e/testing-manifests |
    xargs perl -X -i -pe "${SUBSTITUTIONS[$index]}"
done

# Restore bindata.go
mv ${KUBE_ROOT}/test/e2e/generated/bindata.go.bk \
   ${KUBE_ROOT}/test/e2e/generated/bindata.go

# Restore google.com.
perl -i -pe "s|baidu.com|google.com|g" \
     ${KUBE_ROOT}/test/e2e/networking.go \
     ${KUBE_ROOT}/test/e2e/dns.go

# restore debian-iptables-amd64
perl -i -pe "s|index.caicloud.io/caicloudgcr/google_containers_debian-iptables-amd64|gcr.io/google_containers/debian-iptables-amd64|g" \
     ${KUBE_ROOT}/build/common.sh
