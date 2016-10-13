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

# The script builds two tarballs, one containing caicloud kubernetes binaries
# and other binaries (etcd, flannel, etc); the other one contains caicloud
# kubernetes scripts, like kube-up, kube-dwon, etc.

set -o errexit
set -o nounset
set -o pipefail

function usage {
  echo -e "Usage:"
  echo -e "  ./build-release.sh [version]"
  echo -e ""
  echo -e "Parameter:"
  echo -e " version\tRelease version. If provided, the tag must be the form of vA.B.C+meta, where"
  echo -e "        \tA, B, C are digits, e.g. v1.0.1+e2e. If not provided, current date/time will"
  echo -e "        \tbe used, i.e. YYYY-mm-DD-HH-MM-SS, where YYY is year, mm is month, DD is day,"
  echo -e "        \tHH is hour, MM is minute and SS is second, e.g. 2015-09-10-18-15-30. The second"
  echo -e "        \tcase is used for development."
  echo -e ""
  echo -e "Environment variable:"
  echo -e " ETCD_VERSION     \tetcd version to use. etcd will be packed into release tarball. Default value ${ETCD_VERSION}"
  echo -e " FLANNEL_VERSION  \tflannel version to use. flannel will be packed into release tarball. Default value: ${FLANNEL_VERSION}"
  echo -e " UPLOAD_TO_QINIU  \tUpload to qiniu.com or not, options: Y or N. Default to ${UPLOAD_TO_QINIU}"
  echo -e " BUILD_CLOUD_IMAGE\tBuild cloud image or not, options: Y or N. Default to ${BUILD_CLOUD_IMAGE}"
  echo -e " RELEASE_HYPERKUBE\tBuild and upload hyperkube docker image or not, options: Y or N. Default to ${RELEASE_HYPERKUBE}"
}

# KUBE_ROOT is a absolute path to root of the repo
KUBE_ROOT=$(cd "$(dirname ${BASH_SOURCE})/../.." && pwd)

# -----------------------------------------------------------------------------
# Parameters for building tarball.
# -----------------------------------------------------------------------------
# Do we want to upload the release tarball to qiniu: Y or N. Default to Y.
UPLOAD_TO_QINIU=${UPLOAD_TO_QINIU:-"Y"}

# Do we want to build cloud image: Y or N. Default to Y.
BUILD_CLOUD_IMAGE=${BUILD_CLOUD_IMAGE:-"Y"}

# Do we want to build script docker image: Y or N. Default to Y.
BUILD_SCRIPTS_DOCKER_IMAGE=${BUILD_SCRIPTS_DOCKER_IMAGE:-"Y"}

# Do we want to build and upload hyperkube docker image: Y or N. Default to Y.
RELEASE_HYPERKUBE=${RELEASE_HYPERKUBE:-"Y"}

# Get configs and commone utilities.
source ${KUBE_ROOT}/hack/caicloud/common.sh

# Find caicloud kubernetes release version.
if [[ "$#" == "1" ]]; then
  if [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" ]]; then
    echo -e ""
    usage
    exit 0
  elif [[ ! $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+ && ! $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
    # We also allow passing date/time directly, this is usually used internally.
    echo -e "Error: Version format error, see usage."
    echo -e ""
    usage
    exit 1
  else
    CAICLOUD_VERSION=${1}
  fi
else
  echo -e ""
  usage
  exit 0
fi

# Final caicloud kubernetes version consists of upstream version and caicloud
# version. Also, our own information must go to version meta data, see:
# http://semver.org/#spec-item-9 and http://semver.org/#spec-item-10.
CAICLOUD_KUBE_VERSION=${K8S_VERSION}+${CAICLOUD_VERSION}

# DO NOT CHANGE. Derived variables for tarball building.
CAICLOUD_KUBE_PKG="caicloud-kube-${CAICLOUD_KUBE_VERSION}.tar.gz"
CAICLOUD_KUBE_KUBECTL_PKG="caicloud-kubectl-${CAICLOUD_KUBE_VERSION}.tar.gz"
CAICLOUD_KUBE_SCRIPT_PKG="caicloud-kube-script-${CAICLOUD_KUBE_VERSION}.tar.gz"
CAICLOUD_KUBE_SCRIPT_DOCKER_IMAGE="index.caicloud.io/caicloud/caicloud-kubernetes"
CAICLOUD_CAICLOUD_REGISTRY="index.caicloud.io/caicloud"

# -----------------------------------------------------------------------------
# Start building tarball from current code base.
# -----------------------------------------------------------------------------
cd ${KUBE_ROOT}

# Make sure we have correct version information, e.g. when using `kubectl version`,
# we'll get caicloud kubernetes version instead of random git tree status. The
# variables here are used in ./hack/lib/version.sh.
export KUBE_GIT_VERSION=${CAICLOUD_KUBE_VERSION}
export KUBE_GIT_TREE_STATE="clean"

# Work around mainland network connection.
hack/caicloud/k8s-replace.sh
trap '${KUBE_ROOT}/hack/caicloud/k8s-restore.sh' EXIT
build/run.sh hack/build-go.sh
if [[ "$?" != "0" ]]; then
  echo "Error building server binaries"
  exit 1
fi

echo "Building tarball ${CAICLOUD_KUBE_PKG} and ${CAICLOUD_KUBE_SCRIPT_PKG}"

# Fetch non-kube binaries.
if [[ ! -f /tmp/${ETCD_PACKAGE} ]]; then
  wget ${ETCD_URL} -P /tmp
fi
mkdir -p etcd-linux && tar xzf /tmp/${ETCD_PACKAGE} -C etcd-linux --strip-components=1

if [[ ! -f /tmp/${FLANNEL_PACKAGE} ]]; then
  wget ${FLANNEL_URL} -P /tmp
fi
mkdir -p flannel-linux && tar xzf /tmp/${FLANNEL_PACKAGE} -C flannel-linux --strip-components=1

# Reset output directory.
rm -rf ${KUBE_ROOT}/_output/caicloud && mkdir -p ${KUBE_ROOT}/_output/caicloud

# Make tarball caicloud-kub-${CAICLOUD_KUBE_VERSION}.tar.gz
mkdir -p caicloud-kube
cp etcd-linux/etcd etcd-linux/etcdctl flannel-linux/flanneld \
   _output/dockerized/bin/linux/amd64/kube-apiserver \
   _output/dockerized/bin/linux/amd64/kube-controller-manager \
   _output/dockerized/bin/linux/amd64/kube-proxy \
   _output/dockerized/bin/linux/amd64/kube-scheduler \
   _output/dockerized/bin/linux/amd64/kubectl \
   _output/dockerized/bin/linux/amd64/kubelet \
   caicloud-kube
tar czf ${KUBE_ROOT}/_output/caicloud/${CAICLOUD_KUBE_PKG} caicloud-kube
rm -rf etcd-linux flannel-linux caicloud-kube

# Make tarball caicloud-kub-script-${CAICLOUD_KUBE_VERSION}.tar.gz. Note we preserve
# kubectl path since kubectl.sh assumes some locations.
mkdir -p caicloud-kube-script
cp -R hack cluster build caicloud-kube-script
rm -rf caicloud-kube-script/cluster/caicloud/certs
mkdir -p caicloud-kube-script/_output/dockerized/bin/linux/amd64/
cp _output/dockerized/bin/linux/amd64/kubectl caicloud-kube-script/_output/dockerized/bin/linux/amd64/
# Build docker image that will be used by cluster manager. The image contains all the k8s scripts
if [[ "$BUILD_SCRIPTS_DOCKER_IMAGE" == "Y" ]]; then
  cp -R caicloud-kube-script ${KUBE_ROOT}/hack/caicloud
  cd ${KUBE_ROOT}/hack/caicloud
  docker build -t ${CAICLOUD_KUBE_SCRIPT_DOCKER_IMAGE}:${CAICLOUD_VERSION} .
  docker push ${CAICLOUD_KUBE_SCRIPT_DOCKER_IMAGE}:${CAICLOUD_VERSION}
  rm -rf caicloud-kube-script
  cd - > /dev/null
fi
tar czf ${KUBE_ROOT}/_output/caicloud/${CAICLOUD_KUBE_SCRIPT_PKG} caicloud-kube-script
rm -rf caicloud-kube-script

# Make tarball caicloud-kubectl-${CAICLOUD_KUBE_VERSION}.tar.gz.
mkdir -p caicloud-kubectl
cp _output/dockerized/bin/linux/amd64/kubectl caicloud-kubectl
tar czf ${KUBE_ROOT}/_output/caicloud/${CAICLOUD_KUBE_KUBECTL_PKG} caicloud-kubectl
rm -rf caicloud-kubectl

cd - > /dev/null

# Build and upload hyperkube docker image.
if [[ "$RELEASE_HYPERKUBE" == "Y" ]]; then
  make -C $KUBE_ROOT WHAT=cmd/hyperkube KUBE_STATIC_OVERRIDES="hyperkube" KUBE_BUILD_PLATFORMS="linux/amd64"
  VERSION="${CAICLOUD_VERSION}" REGISTRY="${CAICLOUD_CAICLOUD_REGISTRY}" make -C $KUBE_ROOT/cluster/caicloud/images/hyperkube/ "push"
fi

# Decide if we upload releases to Qiniu.
if [[ "${UPLOAD_TO_QINIU}" == "Y" ]]; then
  if [[ "$(which qrsync)" == "" ]]; then
    echo "Can't find qrsync cli binary in PATH - unable to upload to Qiniu."
    exit 1
  fi
  # Change directory to qiniu-conf.json: Qiniu SDK has assumptions about path.
  cd ${KUBE_ROOT}/hack/caicloud
  qrsync qiniu-conf.json
  cd - > /dev/null
fi

function create-cloud-image {
  KUBERNETES_PROVIDER=$1
  ANCHNET_CONFIG_FILE=$2
  source "${KUBE_ROOT}/cluster/kube-util.sh"
  source "${KUBE_ROOT}/cluster/lib/util.sh"
  build-instance-image
}

# Decide if we create cloud images.
if [[ "${BUILD_CLOUD_IMAGE}" == "Y" ]]; then
  # config-xinzhang is the anchnet account used to host all clusters.
  create-cloud-image "caicloud-anchnet" "$HOME/.anchnet/config-xinzhangcmu"
fi

# A reminder for creating Github release.
if [[ "$#" == "1" && $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo -e "Finished building release. If this is a formal release, please remember to create a release tag at Github at:"
  echo -e "  https://github.com/caicloud/caicloud-kubernetes/releases"
fi
