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

# Kubernetes team hosts a lot of images on gcr.io, which is blocked by GFW.
# The script pulls such images from gcr.io, and push to index.caicloud.io
# The script must be ran on host outside of GFW.

KUBE_ROOT=$(dirname "${BASH_SOURCE}")/../..
PROCESSED_LOG="/tmp/k8s_synced_images"

# Sync a single image. $1 will be pulled, then tagged and pushed as $2.
#
# Input:
#   $1 The image to pull
#   $2 The image to push
function sync_image {
  docker pull "$1"
  exit_code="$?"
  if [[ "${exit_code}" != "0" ]]; then
    echo "********** ERROR ********** Unable to pull", "$1"
    return ${exit_code}
  fi
  docker tag "$1" "$2"
  docker push "$2"
  exit_code="$?"
  if [[ "${exit_code}" != "0" ]]; then
    echo "********** ERROR ********** Unable to push", "$2"
    return ${exit_code}
  fi
}

# Replace special images that are not easy to use regex.
function replace_special_images {
  # Special handling for gcr.io/google_containers/kube-cross:vX.Y.Z, which
  # uses an environment variable 'KUBE_BUILD_IMAGE_CROSS_TAG' defined in
  # build/common.sh to decide its tag number.
  source ${KUBE_ROOT}/build/common.sh
  cp ${KUBE_ROOT}/build/build-image/Dockerfile ${KUBE_ROOT}/build/build-image/Dockerfile.bk
  perl -X -i -pe "s/KUBE_BUILD_IMAGE_CROSS_TAG/${KUBE_BUILD_IMAGE_CROSS_TAG}/g" ${KUBE_ROOT}/build/build-image/Dockerfile
  trap "mv ${KUBE_ROOT}/build/build-image/Dockerfile.bk ${KUBE_ROOT}/build/build-image/Dockerfile" EXIT
}

#
# Start syncing images
#

# Clear PROCESSED_LOG, where we save list of processed images.
rm -rf $PROCESSED_LOG

# Replace special images that are not easy to use regex.
replace_special_images

# Avoid bail out when error pulling/pushing a single image. Must be set after
# replace_special_images, since it calls source ${KUBE_ROOT}/build/common.sh
# which enables errexit.
set +o errexit

# Sync images using regex.
PATTERNS=(
  "gcr.io/google_containers/[^\", ]*"
  "gcr.io/google-containers/[^\", ]*"
  "gcr.io/google_samples/[^\", ]*"
  "gcr.io/google-samples/[^\", ]*"
)
GCR_PREFIXES=(
  "gcr.io/google_containers/"
  "gcr.io/google-containers/"
  "gcr.io/google_samples/"
  "gcr.io/google-samples/"
)
CAICLOUD_PREFIXES=(
  "index.caicloud.io/caicloudgcr/google_containers"
  "index.caicloud.io/caicloudgcr/google-containers"
  "index.caicloud.io/caicloudgcr/google_samples"
  "index.caicloud.io/caicloudgcr/google-samples"
)
for i in `seq "${#PATTERNS[@]}"`; do
  index=$(($i-1))
  grep -IhEro "${PATTERNS[$index]}" \
       --include \*.go \
       --include \*.json \
       --include \*.yaml \
       --include \*.yaml.in \
       --include \*.yml \
       --include Dockerfile \
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
       ${KUBE_ROOT}/test/e2e/testing-manifests | sort -u |
    while read -r gcr_image ; do
      gcr_image=${gcr_image%;}
      image=${gcr_image#"${GCR_PREFIXES[$index]}"}
      caicloud_image="${CAICLOUD_PREFIXES[$index]}_$image"
      echo "++++++++++ Pulling image ${gcr_image} from gcr.io, and push to ${caicloud_image}"
      sync_image "$gcr_image" "$caicloud_image"
      if [[ "$?" != "0" ]]; then
        echo "ERROR: $caicloud_image" >> $PROCESSED_LOG
      else
        echo "$caicloud_image" >> $PROCESSED_LOG
      fi
      echo ""
    done
done

echo
echo "============================================"
echo "Done processing images. Processed images can be found at $PROCESSED_LOG"
echo "============================================"
