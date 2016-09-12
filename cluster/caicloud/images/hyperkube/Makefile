# Copyright 2016 The Kubernetes Authors All rights reserved.
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

# Build the hyperkube image.
#
# Usage:
#   VERSION=v1.1.2 [REGISTRY="gcr.io/google_containers"] make build

REGISTRY?="index.caicloud.io/caicloud"
ARCH=amd64
BASEIMAGE=index.caicloud.io\\/caicloud\\/alpine:3.3
TEMP_DIR:=$(shell mktemp -d)

## Comment in for arm builds, must be run on an arm machine
# ARCH=arm
# need to escape '/' for the regexp below
# BASEIMAGE=armbuild\\/debian:jessie

all: build

build:
ifndef VERSION
    $(error VERSION is undefined)
endif
	cp ./* ${TEMP_DIR}
	if [ ! -f ../../../../_output/local/bin/linux/${ARCH}/hyperkube ] ; then \
		make -C ../../../../ WHAT=cmd/hyperkube KUBE_STATIC_OVERRIDES="hyperkube" KUBE_BUILD_PLATFORMS="linux/amd64" ; \
	fi
	cp ../../../../_output/local/bin/linux/${ARCH}/hyperkube ${TEMP_DIR}
	cd ${TEMP_DIR} && chmod +x hyperkube && perl -X -i -pe "s/BASEIMAGE/${BASEIMAGE}/g" Dockerfile
	docker build -t ${REGISTRY}/hyperkube-${ARCH}:${VERSION} ${TEMP_DIR}
	# Backward compatibility.  TODO: deprecate this image tag
ifeq ($(ARCH),amd64)
	docker tag ${REGISTRY}/hyperkube-${ARCH}:${VERSION} ${REGISTRY}/hyperkube:${VERSION}
endif

push: build
	docker push ${REGISTRY}/hyperkube-${ARCH}:${VERSION}
ifeq ($(ARCH),amd64)
	docker push ${REGISTRY}/hyperkube:${VERSION}
endif

.PHONY: all
