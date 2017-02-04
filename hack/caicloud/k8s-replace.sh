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

# The script fixes a couple of hiccups for developing kubernetes behind GFW.
# This is necessary since we don't want to change upstream code.
#
# Conversion rule:
#   gcr.io/google_containers/es-kibana -> cargo.caicloud.io/caicloudgcr/google_containers_es-kibana
#   gcr.io/google_samples/frontend     -> cargo.caicloud.io/caicloudgcr/google_samples_frontend

KUBE_ROOT=$(dirname "${BASH_SOURCE}")/../..

# 'gcr.io' is blocked - replace all gcr.io images to cargo.caicloud.io/caicloudgcr.
PATTERNS=(
  "gcr.io/google_containers/[^\", ]*"
  "gcr.io/google-containers/[^\", ]*"
  "gcr.io/google_samples/[^\", ]*"
  "gcr.io/google-samples/[^\", ]*"
)
SUBSTITUTIONS=(
  "s|gcr.io/google_containers/|cargo.caicloud.io/caicloudgcr/google_containers_|g"
  "s|gcr.io/google-containers/|cargo.caicloud.io/caicloudgcr/google-containers_|g"
  "s|gcr.io/google_samples/|cargo.caicloud.io/caicloudgcr/google_samples_|g"
  "s|gcr.io/google-samples/|cargo.caicloud.io/caicloudgcr/google-samples_|g"
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
       ${KUBE_ROOT}/docs \
       ${KUBE_ROOT}/build-tools \
       ${KUBE_ROOT}/cmd \
       ${KUBE_ROOT}/test/e2e/testing-manifests |
    xargs perl -X -i -pe "${SUBSTITUTIONS[$index]}"
done

# For e2e tests in newer release, yaml files are compiled into "test/e2e/generated/bindata.go".
# Previously, the yaml files are read from various directories. This is documented
# in test/e2e/framework/gobindata_util.go. Therefore, before building binaries, run
# this script and we'll have correct images compiled into the binaries.
if [[ `which go-bindata` == "" ]]; then
  go get -u github.com/jteeuwen/go-bindata/...
fi
if [[ ! -f test/e2e/generated/bindata.go.bk ]]; then
  # Compile only if bindata.go.bk doesn't exist (replace.sh can be called
  # multiple times).
  cd ${KUBE_ROOT}
  mv test/e2e/generated/bindata.go test/e2e/generated/bindata.go.bk
  go-bindata \
    -pkg generated -ignore .jpg -ignore .png -ignore .md \
    ./examples/* ./docs/user-guide/* test/e2e/testing-manifests/kubectl/* test/images/*
  mv bindata.go test/e2e/generated
  gofmt -s -w test/e2e/generated/bindata.go
  cd - > /dev/null
fi

# Change google.com to baidu.com, which is used to check network connectivity.
perl -i -pe "s|google.com|baidu.com|g" \
     ${KUBE_ROOT}/test/e2e/networking.go \
     ${KUBE_ROOT}/test/e2e/dns.go

# Change image in build-tools/common.sh, which is not replaced above
perl -i -pe "s|gcr.io/google_containers/debian-iptables-amd64|cargo.caicloud.io/caicloudgcr/google_containers_debian-iptables-amd64|g" \
     ${KUBE_ROOT}/build-tools/common.sh
