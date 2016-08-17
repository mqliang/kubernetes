<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Caicloud kubernetes](#caicloud-kubernetes)
  - [Overview](#overview)
  - [Release procedure](#release-procedure)
  - [Rebase procedure](#rebase-procedure)
    - [Steps to rebase to upstream](#steps-to-rebase-to-upstream)
    - [Changes relative to public mainstream](#changes-relative-to-public-mainstream)
      - [New files or directories](#new-files-or-directories)
      - [Changes to individual files](#changes-to-individual-files)
      - [Depedencies](#depedencies)
- [Cluster resize (outdated)](#cluster-resize-outdated)
    - [Scale up](#scale-up)
- [Cluster upgrade (outdated)](#cluster-upgrade-outdated)
  - [Caveats](#caveats)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Caicloud kubernetes

## Overview

Caicloud kubernetes is a customized kubernetes hosted by [caicloud.io](https://caicloud.io). Currently,
we support [Anchnet](http://cloud.51idc.com/), and baremetal. There is plan to add more cloudproviders.
Kubernetes is the building block of caicloud.io, the long term plan is to enrich its ecosystem to enable
enterprise use cases.

## Release procedure

To build release, use script `hack/caicloud/build-release.sh`. The script will:
- Build caicloud kubernetes binaries tarball, including kubelet, apiserver, etc., and push to qiniu
- Build script release, i.e. kube-up.sh, kube-down.sh, etc., and push to qiniu
- Build a docker image containing all the scripts: the docker image is used by cluster admin
- Create cloud images, which can be used to create an instance from cloudprovider directly

To see its full description, run (assuming at kubernetes root directory):
```
./hack/caicloud/build-release.sh
```

Note about release version, quite a few kubernetes components will explicitly check cluster version, e.g.
it will decide if a feature is available based on version number (parse semvar); therefore, we can't
simply use our own version. To solve the problem, we append our version to kubernetes version as a metadata,
which can pass version check and still keep our own version. For example. following command will build
tarballs tagged with version v1.2.0+v1.0.1, assuming upstream kubernetes version is v1.2.0:
```
./hack/caicloud/build-release.sh v1.0.1
```

## Rebase procedure

### Steps to rebase to upstream

- Find the tag commit to rebase and checkout to caicloud master branch
  - Checkout to a new branch, e.g. `git checkout -b rebase-branch`
  - If we want to rebase to v1.3, then run `git log --grep "v1.3"` to find the commit
- Run `git rebase --preserve-merges -i $COMMIT_ID` and resolve conflicts
  - Use `git config --global rerere.enabled true` to reuse recorded resolution (this is a global configuration,
    so only need to run once)
  - Note as we've changed API types, we'll always get conflict with generated files: it is better to just
    use upstream code and re-generate the files, i.e. if there is conflict with generated files, use
    `git checkout --theirs`, e.g. `git checkout --theirs -- pkg/apis/extensions/deep_copy_generated.go`
- Run `hack/caicloud/sync-images.sh` to sync all gcr.io images to index.caicloud.io
  - The script needs to be ran in a remote server (outside of GFW)
  - Make sure it works with newer kubernetes version, and no images are left over
- Run `hack/caicloud/k8s-replace.sh` and `hack/caicloud/k8s-restore.sh`
  - Make sure they work with newer kubernetes version
- Run `./hack/update-codegen.sh` to generate conversion and deepcopy files
  - For conversion, there are two kinds of conversions: one manually written and the other auto-generated.
    As of now (k8s 1.3), manually written ones depends on some functions in auto-generated ones; therefore,
    we can't just remove old generated files and hope they are regenerated. The best approach is to comment
    all functions in all conversion_generated.go, then uncomment the ones that are used in conversion.go
  - For deepcopy, same rule apply. Comment out error part and re-ran the scripts
  - Even though `update-codegen.sh` generate conversion and deepcopy, it also expects types.generated.go and
    types.go to compile. If script fails due to compilation error with types.generated.go, comment out the
    error part (don't just remove types.generated.go)
  - For details, see [API Change](https://github.com/kubernetes/kubernetes/blob/master/docs/devel/api_changes.md)
- Run `./hack/update-codecgen.sh` to generate types.generated.go
  - Due to the fixes above, the script should hopely run without any problem
- Update godep and vendor (as of k8s 1.3)
  - Checkout to upstream branch (the version to rebase to), and run `godep restore`
  - Run `rm -rf Godeps vendor` to clean all vendor directories
  - Run `./hack/godep-save.sh` to re-create vendor files, make sure required packages exist under GOPATH, e.g.
    "github.com/caicloud/anchnet-go".
- Update `K8S_VERSION` in `hack/caicloud/common.sh`
- Build and run basic tests
  - Build code base: `hack/build-go.sh`
  - Run unit test: `hack/test-go.sh`
    - To fix individual test, use `go test`, e.g. `godep go test ./pkg/controller/service`
  - Run integration test: `hack/test-integration.sh`
  - Run end-to-end test
    - e2e script located at `hack/caicloud/caicloud-e2e-test.sh`
    - See `README.md` of individual cloudprovider for details
- If during rebase, new commits can be checked in to caicloud master; we need to rebase that to our current
  rebase branch as well. The workflow is:
  - Record commit id from where we checked out the rebase branch (new latest commit from caicloud master
    when we create the new branch). Let's call it M. E.g.
    ```
    $ git log
    commit 7d6ae97cea7c181d6539f710e0428dbe57c8bd6f
      Update docs while rebasing 1.3

    commit 5d2806ecbbd017fd4ef63913d28faaf28127b87c
      Caicloud add anchnet provider

    commit 12b1da297cef6730aa7afa8aa828500bec42661f
      Kubernetes upstream version 1.3
    ```
    Commit "5d2806ecbbd017fd4ef63913d28faaf28127b87c" is where we created the rebase branch, so we record
    the commit.
  - Suppose the commits that are newly checked in into caicloud master after we start rebase are (X..Y).
    To move them into rebase branch, run:
    ```
    git rebase --onto M <commit before X> Y
    git rebase HEAD rebase-branch
    ```
    After this, we've successfully moved the new commits to rebase branch.
  - We may need to run test again to make sure things won't break.
- If everything is fine, run `git push private-upstream master -f`

### Changes relative to public mainstream

We've added new files/directory and changed a few existing files to support more providers and to meet our
requirements; to view them, first find the commit we based on. For example, in version "v1.3.3", we do:
```
git log --grep "v1.3.3"
```

Then run git diff to see relative changes, e.g.
```
git diff $BASE_COMMIT_IE HEAD --name-only
```

Following is a selected list of the files/directories and why we did the change. The list may not be complete,
when in doubt, consult git.

#### New files or directories

These are newly created directories:

- cluster/caicloud/
  - Central documentation about caicloud kubernetes
  - Common utilities about kube-up/kube-down of caicloud kubernetes
- cluster/caicloud-anchnet/
  - Scripts used to bring up cluster in anchnet
- cluster/caicloud-baremetal/
  - Scripts used to bring up baremetal cluster
- cluster/caicloud-ansible/
  - Scripts used to bring up baremetal cluster using ansible
- hack/caicloud/
  - Various tools for working with caicloud kubernetes
- examples/caicloud/
  - Examples for caicloud, typically about how to use caicloud supported cloudproviders
- pkg/cloudprovider/providers/anchnet/
  - Go package used for anchnet plugin
- pkg/cloudprovider/providers/aliyun/
  - Go package used for anchnet plugin
- pkg/volume/anchnet_pd/
  - Go package used for anchnet persistent volume plugin
- plugin/plugin/pkg/admission/hostpathdeny/
  - Go package used to reject hostpath mount
- cluster/kube-add-node.sh
  - A new script used to add a new node into cluster
- cluster/kube-halt.sh
  - A new script used to stop a running cluster
- cluster/kube-restart.sh
  - A new script used to start a stopped cluster

#### Changes to individual files

Following are API and plugin related changes:

- cmd/kubelet/app/plugins.go
  - To load anchnet volume plugin
- cmd/kube-apiserver/app/plugins.go
  - To load admission control plugin
- pkg/api/types.go, pkg/api/v1/types.go
  - To add `AnchnetPersistentDisk` field in `VolumeSource` structure
  - To add `AnchnetPersistendDisk` field in `PersistentVolumeSource` structure
- pkg/api/validation/validation.go
  - To support validate anchnet persistent disk
- pkg/api*/*_generated.go
  - To support API type changes, see above for how these are generated

Following are e2e test related changes:

- test/e2e/e2e.go, test/e2e/kubectl.go, etc
  - Increase timeout, add 'caicloud-anchnet' to some tests
- hack/ginkgo-e2e.sh
  - Run k8s-replace before actually running e2e tests.
- Misc yaml files (change to index.caicloud.io to speed up e2e test)
  - docs/user-guide/pod.yaml
  - example/guestbook-go/redis-master-controller.json
  - example/guestbook-go/redis-slave-controller.json

Others changes:

- pkg/controller/servicecontroller.go, pkg/cloudprovider/providers/aws/aws.go, etc
  - To support creating loadbalancer prefixed with cluster name

#### Depedencies

- Add more dependencies in vendor:
  - anchnet-go: SDK for anchnet API
  - aliyun: SDK for aliyun API

# Cluster resize (outdated)

### Scale up

Cluster scale up is done using `kube-add-node.sh` script, which add node(s) to a running cluster. This
script will use binaries kept at master to bring up a new cluster node (One caveat is that older versions
of cluster don't have binaries stored at master node).

# Cluster upgrade (outdated)

Cluster upgrade is done using `kube-push.sh` script, which pushes new binaries and configurations to
running cluster (The ultimate goal in kubernetes is self-hosting and do rolling upgrade on cluster
components). Note all configurations will be pushed to cluster except certs, credentials, etc. See
respective cloudprovider documentation about how to use the script.

Manually upgrade a user's kubernetes cluster is more involved, e.g.
```
CAICLOUD_KUBE_VERSION=v0.5.2 CLUSTER_NAME=7004de97-5aa9-495f-b443-3755463288e9 KUBERNETES_PROVIDER=caicloud-anchnet KUBE_INSTANCE_PASSWORD=fRBz6rqZ2VZODqv0 PROJECT_ID=pro-VE2200D8 ./cluster/kube-push.sh
```

## Caveats

Before upgrading cluster, it's important to understand the following points:

- Cluster version
  It's important to make sure current cluster version is compatible with new cluster version. To check
  current cluster version, use `kubectl version`, or consult cluster manager (not working yet). By
  convention, version x.x.X is bound to be compatible with x.x.Y, and x.X.x is mostly compatible with
  x.Y.x. The best practice is to create a test cluster with old version, deploy sample applications,
  and then try upgrade to desired version. To upgrade from X.x.x to Y.x.x, it's better to do a full
  migration.

- External loadbalancer
  Upon restart, service controller will call cloudprovider for all the services existed in the cluster
  (including those don't need external loadbalancer). Bear in mind that this will create quit a bit
  burden on cloudproviders. For services without external loadbalancer, service controller will ignore
  and simply create its cache. For services with external loadbalancer, we'll first delete the external
  loadbalancer and re-recreate one with the same IP address. TODO: switch to full sync instead of deleting
  and recreating.

- Existing Pod
  Upgrading cluster involves restarting all kubernetes components as well as docker. Upon restart, kubelet
  will fetch its pods and sync their status. Since etcd data is persistent, kubelet will see the pods
  initially assigned to it. Therefore, existing Pod won't be migrated or restarted by kubelet. However,
  we'll also restart docker (e.g. upgrade docker version, change network setting, etc), in which case
  existing containers WILL be restarted by kubelet. The best we can do is to separate docker upgrade from
  kubernetes upgrade, provided as an option during kube-push.
