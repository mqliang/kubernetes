<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Caicloud kubernetes](#caicloud-kubernetes)
  - [Overview](#overview)
  - [How to do a release](#how-to-do-a-release)
  - [Maintenance](#maintenance)
    - [Rebase to latest public mainstream](#rebase-to-latest-public-mainstream)
    - [Things need to be updated after rebasing](#things-need-to-be-updated-after-rebasing)
    - [Changes relative to public mainstream](#changes-relative-to-public-mainstream)
      - [New files or directories](#new-files-or-directories)
      - [Changes to individual files](#changes-to-individual-files)
      - [Depedencies](#depedencies)
  - [Cluster resize](#cluster-resize)
      - [Scale up](#scale-up)
  - [Cluster upgrade](#cluster-upgrade)
    - [Caveats](#caveats)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Caicloud kubernetes

## Overview

Caicloud kubernetes is a customized kubernetes hosted by [caicloud.io](https://caicloud.io). Currently, we support [Anchnet](http://cloud.51idc.com/),
and baremetal. There is plan to add more cloudproviders. Kubernetes is the building block of caicloud.io, the long term plan is to enrich its ecosystem
to enable enterprise use cases.

## How to do a release

To build release, use script `hack/caicloud/build-release.sh`. The script will build caicloud kubernetes binaries, i.e. kubelet, apiserver, etc. It
will also build script release, i.e. kube-up.sh, kube-down.sh etc. By default, it will create two tarballs (binaries and scripts) and push to qiniu,
it will also create cloud images, which can be used to create an image from cloudprovider directly. To see its full description, run (assuming at
kubernetes root directory):
```
./hack/caicloud/build-release.sh
```

E.g. following command will build tarballs tagged with version v1.0.1:
```
./hack/caicloud/build-release.sh v1.0.1
```

## Maintenance

A couple points related to how to maintain caicloud kubernetes.

### Rebase to latest public mainstream

* Find the tag commit to rebase
* Checkout to caicloud master branch
* git rebase --preserve-merges -i $COMMIT_ID
* git push private-upstream master -f

A couple of points to facilitate rebase:

* Use `git config --global rerere.enabled true` to reuse recorded resolution
* As we changed API types, we'll always get conflict with generated files: it is better to just use upstream code and re-generate the files
  - When conflict, use `git checkout --theirs`, e.g. `git checkout --theirs -- pkg/apis/extensions/deep_copy_generated.go`
  - After rebase, follow [API Change](https://github.com/kubernetes/kubernetes/blob/master/docs/devel/api_changes.md) to re-generate the files

### Things need to be updated after rebasing

- Merge conflict from customized changes (we try to keep this as minimal as possible)
- In `hack/caicloud/`, we have scripts fixing GFW issues, make sure it still works with newer kubernetes version
  - k8s-replace.sh
  - k8s-restore.sh
  - sync-images.sh
- Run  to sync all gcr.io images to index.caicloud.io
  - `hack/caicloud/sync-images.sh`
- Test the new version
  - `hack/build-go.sh`
  - `hack/test-go.sh`
    - To fix individual test, use `go test`, e.g. `godep go test ./pkg/controller/service`
  - `hack/test-integration.sh`
  - `hack/caicloud/caicloud-e2e-test.sh`
    - See README.md of individual cloudprovider for details
- Update "K8S_VERSION" in `cluster/caicloud/common.sh`

### Changes relative to public mainstream

#### New files or directories

These are brand new folders created to support our cloudprovider:

- cluster/caicloud/
  - Central documentation about caicloud kubernetes
  - Common utilities about kube-up/kube-down of caicloud kubernetes
- cluster/caicloud-anchnet/
  - Scripts used to bring up cluster in anchnet
- cluster/caicloud-baremetal/
  - Scripts used to bring up baremetal cluster
- cluster/kube-add-node.sh
  - A new script used to add a new node into cluster
- cluster/kube-halt.sh
  - A new script used to stop a running cluster
- cluster/kube-restart.sh
  - A new script used to start a stopped cluster
- hack/caicloud/
  - Various tools for working with caicloud kubernetes
- examples/caicloud/
  - Examples for caicloud, typically about how to use caicloud supported cloudproviders
- pkg/cloudprovider/providers/anchnet/
  - Go package used for anchnet plugin
- pkg/volume/anchnet_pd/
  - Go package used for anchnet persistent volume plugin

#### Changes to individual files

These are individual files we have to change in order to meet our requirements:

##### Support anchnet disk

- cmd/kubelet/app/plugins.go
  - To load anchnet volume plugin
- pkg/api/types.go, pkg/api/v1/types.go
  - To add `AnchnetPersistentDisk` field in `VolumeSource` structure
  - To add `AnchnetPersistendDisk` field in `PersistentVolumeSource` structure
- pkg/api/validation/validation.go
  - To support validate anchnet persistent disk
- pkg/api/deep_copy_generated.go, pkg/api/v1/conversion_generated.go, pkg/api/v1/deep_copy_generated.go, pkg/expapi/deep_copy_generated.go, pkg/expapi/v1/conversion_generated.go, pkg/expapi/v1/deep_copy_generated.go
  - To support API type changes
  - Auto generated by hack/update-genereated-deep-copies.sh and hack/update-generated-conversions.sh

##### Add cluster name to external service

- pkg/controller/servicecontroller.go, pkg/controller/servicecontroller_test.go pkg/cloudprovider/cloud.go
  - To support creating loadbalancer prefixed with cluster name

##### Fix e2e test

- test/e2e/util.go
  - To use correct ssh private key & user for e2e test
  - Increase timeout constants
- test/e2e/service.go
  - Enable external loadbalancer by modfiying SkipUnlessProviderIs("gce", "gke", "aws", "caicloud-anchnet")
- test/e2e/austocaling_utils.go
  - Increase timeoutRC

#### Depedencies

- Add more dependencies in godeps:
  - Anchnet-go: SDK for anchnet API

## Cluster resize

#### Scale up

Cluster scale up is done using `kube-add-node.sh` script, which add node(s) to a running cluster. This script will use binaries kept at master to
bring up a new cluster node (One caveat is that older versions of cluster don't have binaries stored at master node). Currently we only support adding
nodes to caicloud-anchnet cluster.

## Cluster upgrade

Cluster upgrade is done using `kube-push.sh` script, which pushes new binaries and configurations to running cluster (The ultimate goal in kubernetes
is self-hosting and do rolling upgrade on cluster components). Note all configurations will be pushed to cluster except certs, credentials, etc. See
respective cloudprovider documentation about how to use the script.

Manually upgrade a user's kubernetes cluster is more involved, e.g.
```
CAICLOUD_KUBE_VERSION=v0.5.2 CLUSTER_NAME=7004de97-5aa9-495f-b443-3755463288e9 KUBERNETES_PROVIDER=caicloud-anchnet KUBE_INSTANCE_PASSWORD=fRBz6rqZ2VZODqv0 PROJECT_ID=pro-VE2200D8 ./cluster/kube-push.sh
```

### Caveats

Before upgrading cluster, it's important to understand the following points:

- Cluster version
  It's important to make sure current cluster version is compatible with new cluster version. To check current cluster version, use `kubectl version`,
  or consult cluster manager (not working yet). By convention, version x.x.X is bound to be compatible with x.x.Y, and x.X.x is mostly compatible with
  x.Y.x. The best practice is to create a test cluster with old version, deploy sample applications, and then try upgrade to desired version. To upgrade
  from X.x.x to Y.x.x, it's better to do a full migration.

- External loadbalancer
  Upon restart, service controller will call cloudprovider for all the services existed in the cluster (including those don't need external loadbalancer).
  Bear in mind that this will create quit a bit burden on cloudproviders. For services without external loadbalancer, service controller will ignore and
  simply create its cache. For services with external loadbalancer, we'll first delete the external loadbalancer and re-recreate one with the same IP
  address. TODO: switch to full sync instead of deleting and recreating.

- Existing Pod
  Upgrading cluster involves restarting all kubernetes components as well as docker. Upon restart, kubelet will fetch its pods and sync their status.
  Since etcd data is persistent, kubelet will see the pods initially assigned to it. Therefore, existing Pod won't be migrated or restarted by kubelet.
  However, we'll also restart docker (e.g. upgrade docker version, change network setting, etc), in which case existing containers WILL be restarted by
  kubelet. The best we can do is to separate docker upgrade from kubernetes upgrade, provided as an option during kube-push.
