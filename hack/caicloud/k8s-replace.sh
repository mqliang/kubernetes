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

KUBE_ROOT=$(dirname "${BASH_SOURCE}")/../..
source "${KUBE_ROOT}/hack/caicloud/common.sh"

# 'gcr.io' is blocked - replace all gcr.io images to ones we uploaded to
# index.caicloud.io/caicloudgcr account.
grep -rl "gcr.io/google_containers/[^\", ]*" \
     --include \*.go --include \*.json --include \*.yaml --include \*.yaml.in --include \*.yml --include Dockerfile --include \*.manifest \
     ${KUBE_ROOT}/test ${KUBE_ROOT}/examples ${KUBE_ROOT}/cluster/addons ${KUBE_ROOT}/cluster/saltbase ${KUBE_ROOT}/contrib ${KUBE_ROOT}/docs ${KUBE_ROOT}/build |
  xargs perl -X -i -pe 's|gcr.io/google_containers/|index.caicloud.io/caicloudgcr/google_containers_|g'
grep -rl "gcr.io/google_samples/[^\", ]*" \
     --include \*.go --include \*.json --include \*.yaml --include \*.yaml.in --include \*.yml --include Dockerfile --include \*.manifest \
     ${KUBE_ROOT}/test ${KUBE_ROOT}/examples ${KUBE_ROOT}/cluster/addons ${KUBE_ROOT}/cluster/saltbase ${KUBE_ROOT}/contrib ${KUBE_ROOT}/docs ${KUBE_ROOT}/build |
  xargs perl -X -i -pe 's|gcr.io/google_samples/|index.caicloud.io/caicloudgcr/google_samples_|g'

# Our cloudprovider supports following e2e tests.
perl -i -pe 's|\QSkipUnlessProviderIs("gce", "gke", "aws")\E|SkipUnlessProviderIs("gce", "gke", "aws", "caicloud-anchnet")|g' \
     ${KUBE_ROOT}/test/e2e/kubectl.go
perl -i -pe 's|\QSkipUnlessProviderIs("gce", "gke", "aws")\E|SkipUnlessProviderIs("gce", "gke", "aws", "caicloud-anchnet")|g' \
     ${KUBE_ROOT}/test/e2e/service.go
perl -i -pe "s|google.com|baidu.com|g" ${KUBE_ROOT}/test/e2e/networking.go
