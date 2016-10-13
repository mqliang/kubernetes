<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Anchnet cloudprovider](#anchnet-cloudprovider)
  - [Background on anchnet cloudprovider](#background-on-anchnet-cloudprovider)
  - [Create a cluster using anchnet](#create-a-cluster-using-anchnet)
      - [Options:](#options)
  - [Delete a cluster](#delete-a-cluster)
      - [Options:](#options-1)
  - [Update a cluster](#update-a-cluster)
      - [Options:](#options-2)
  - [Add node to a cluster](#add-node-to-a-cluster)
  - [Stop a running cluster](#stop-a-running-cluster)
  - [Restart a cluster](#restart-a-cluster)
      - [Options:](#options-3)
  - [Test](#test)
    - [Unit Test](#unit-test)
    - [Integration Test](#integration-test)
    - [e2e test](#e2e-test)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Anchnet cloudprovider

Anchnet cloudprovider is internally supported by [caicloud.io](https://caicloud.io). It implements kubernetes cloudprovider plugin, and
can be considered natively supported by kubernetes.

## Background on anchnet cloudprovider

[Anchnet](http://cloud.51idc.com/) is one of caicloud's IDC/IaaS parteners. It has most common features seen in other cloudproviders, e.g.
Cloud Instances, External IPs, Load balancers, etc, see [help center](http://cloud.51idc.com/help/cloud/index.html).
[API doc](http://cloud.51idc.com/help/api/index.html) lists all public APIs (there are some internal ones also). SDK is developed by caicloud
team at https://github.com/caicloud/anchnet-go.

## Create a cluster using anchnet

To create a kubernetes cluster, make sure you've installed anchnet SDK. To install:
```
go get github.com/caicloud/anchnet-go/anchnet
```

This will install binary `anchnet` under `$GOPATH/bin` - make sure it's in your `PATH` variable. The binary also needs a config file
(e.g ~/.anchnet/config) with API keys, see [anchnet SDK](https://github.com/caicloud/anchnet-go). After the setup, you can create a cluster
by simply running:
```
KUBERNETES_PROVIDER=caicloud-anchnet ./cluster/kube-up.sh
```

#### Options:

There are quite a few options used to create a cluster in anchnet, located at `config-default.sh`. Following is a curated list of options
used in kube-up. For a full list of options, consult the file.

* `CLUSTER_NAME`: The name of newly created cluster. This is used to identify a cluster - all resources will be prefixed with this name.
  The variable is default to "kube-default". E.g. the following command will create a cluster named "caicloud-rocks", and all instances
  (plus other resources like firewall) will be prefixed with "caicloud-rocks".
  ```
  KUBERNETES_PROVIDER=caicloud-anchnet CLUSTER_NAME=caicloud-rocks ./cluster/kube-up.sh
  ```

* `PROJECT_ID`: The project to use. In anchnet, project is actually a sub-account, it helps admin to manage resources. All resouces under
  a project (sub-account) is isolated from others. An anchnet account can have multiple sub-accounts. The variable is default to an empty
  string, which means main-account. E.g. following command creates a cluster named "caicloud-rocks" under project "pro-H4ZW87K2"
  ("pro-H4ZW87K2" must exist, see below):
  ```
  KUBERNETES_PROVIDER=caicloud-anchnet CLUSTER_NAME=caicloud-rocks PROJECT_ID=pro-H4ZW87K2 ./cluster/kube-up.sh
  ```

* `PROJECT_USER`: The anchnet sub-account user name. This variable is default to empty string. If `PROJECT_USER` is set, the `kubeconfig`
  file, which has all the information of how to access the cluster, will be created at `$HOME/.kube/config_${PROJECT_USER}`. If not set,
  default location (`$HOME/.kube/config`) will be used. In production, we should always set `PROJECT_USER`, leaving it empty should only
  be used during development. The variable has some correlation with `PROJECT_ID`:

  * If `PROJECT_ID` is set, it means this `PROJECT_USER` has already been accociated with a sub-account before, so that we just bring up
    cluster under that sub-account: E.g. following command creates a cluster under a specific sub-account:
    ```
    KUBERNETES_PROVIDER=caicloud-anchnet CLUSTER_NAME=caicloud-rocks PROJECT_USER=test_user PROJECT_ID=pro-H4ZW87K2 ./cluster/kube-up.sh
    ```

  * If `PROJECT_ID` is not set, it means this is the first time user wants to create a cluster and there is no sub account associated with
    `PROJECT_USER`. In this case, a sub account will be automatically created and reported back to executor service, and the cluster will
    be created in the new sub-account. E.g. following command will create a sub-account and then create a cluster:
    ```
    KUBERNETES_PROVIDER=caicloud-anchnet CLUSTER_NAME=caicloud-rocks PROJECT_USER=test_user ./cluster/kube-up.sh
    ```

* `CAICLOUD_KUBE_VERSION`: The version of caicloud release to use if building release is not required. E.g. 2015-09-09-15-30, v1.0.2, etc.
  Default value is current release version (or a previous version if `config-default.sh` is not updated). The version must exist in
  `CAICLOUD_HOST_URL`. E.g., following command creates a cluster using caicloud kubernetes version `v0.2.0`.
  ```
  KUBERNETES_PROVIDER=caicloud-anchnet CAICLOUD_KUBE_VERSION=v0.2.0 ./cluster/kube-up.sh
  ```

* `CAICLOUD_HOST_URL`: The host from which kube-up fetches release. Default to `http://7xli2p.dl1.z0.glb.clouddn.com`.

* `BUILD_TARBALL`: Decide if building tarball is needed, one of "Y" and "N" If the parameter is Y, then use `BUILD_VERSION` as release
  version; otherwise, use `CAICLOUD_KUBE_VERSION`. Using two different versions avoid overriding existing tarball version. E.g. following
  command creates a cluster from current code base. The version must be the form of `$(TZ=Asia/Shanghai date +%Y-%m-%d-%H-%M)`.
  ```
  KUBERNETES_PROVIDER=caicloud-anchnet BUILD_TARBALL=Y ./cluster/kube-up.sh
  ```

* `BUILD_VERSION`: The version to build during kube-up (for development mainly). Default value is current date and time, i.e.
  `$(TZ=Asia/Shanghai date +%Y-%m-%d-%H-%M)`.

* `ANCHNET_CONFIG_FILE`: The config file supplied to `anchnet` SDK CLI. Default value is `~/.anchnet/config`. Usually, you don't have
  to change the value, unless you want to create cluster under another anchnet account (NOT sub-account).

* `KUBE_DISTRO`: The Linux distribution of underline OS, currently only ubuntu:trusty is supported.

* `REGISTER_MASTER_KUBELET`: The flag controls whether we registry master as a node, this is true by default.

* `ENABLE_CLUSTER_DNS`: Decide if cluster dns addon needs to be created, default to true. DNS addon is essential and should always be true.

* `ENABLE_CLUSTER_LOGGING`: Decide if cluster logging addon needs to be created.

* `ENABLE_CLUSTER_DASHBOARD`: Decide if cluster dashboard addon needs to be created.

* `ENABLE_CLUSTER_REGISTRY`: Decide if cluster registry addon needs to be created.

* `ENABLE_CLUSTER_MONITORING`: Decide if cluster monitoring addon needs to be created.

## Delete a cluster

Deleting a cluster will delete everything associated with the cluster, including instances, vxnet, external ips, firewalls, etc. To bring
down a cluster, run:
```
KUBERNETES_PROVIDER=caicloud-anchnet ./cluster/kube-down.sh
```

#### Options:

* `CLUSTER_NAME`: Delete cluster with given name.

* `PROJECT_ID`: Delete cluster from sub-account with given id. E.g. following command deletes cluster "caicloud-rocks" under project "pro-H4ZW87K2".
  ```
  KUBERNETES_PROVIDER=caicloud-anchnet CLUSTER_NAME=caicloud-rocks PROJECT_ID=pro-H4ZW87K2 ./cluster/kube-down.sh
  ```

## Update a cluster

Updating a cluster will build current code base and push/restart cluster, useful for development. To update a cluster, run:

```
KUBERNETES_PROVIDER=caicloud-anchnet ./cluster/kube-push.sh
```

#### Options:

* `CLUSTER_NAME`: Delete cluster with given name.

* `PROJECT_ID`: Delete cluster from sub-account with given id.

* `CAICLOUD_KUBE_VERSION`: Which version to deploy.

## Add node to a cluster

In case we want to add node(s) to a running cluster, we can run:
```
CLUSTER_NAME=kube-default MASTER_EIP=103.21.116.147 NUM_NODES=1 KUBERNETES_PROVIDER=caicloud-anchnet ./cluster/kube-add-node.sh
```

Note this is not working as of now.

## Stop a running cluster

we can simply do the following to shut down a running cluster:
```
CLUSTER_NAME=kube-default KUBERNETES_PROVIDER=caicloud-anchnet ./cluster/kube-halt.sh
```

## Restart a cluster

If we want to restart a cluster which has been stopped before, we can do:
```
CLUSTER_NAME=kube-default KUBERNETES_PROVIDER=caicloud-anchnet ./cluster/kube-restart.sh
```

#### Options:

* `INSTANCE_USER`: Instance user of the master (e.g. ubuntu). This will also be used to create new nodes

* `KUBE_INSTANCE_PASSWORD`: Instance password of the master (e.g. caicloud2015ABC). This will also be used to create new nodes

## Test

### Unit Test

Running unit test is the same as upstream, i.e.
```
./hack/test-go.sh
```

### Integration Test

Running integration test is the same as upstream, i.e.
```
./hack/test-integration.sh
```

### e2e test

Typical workflow for running anchnet e2e tests:

- Step1:
  Build codebase, create a new cluster and run default set of tests. `tee` is used to redirect to both stdout and file):
  ```
  $ KUBERNETES_PROVIDER=caicloud-anchnet ./hack/caicloud/caicloud-e2e-test.sh 2>&1 | tee ~/e2e-output
  ```
  To use another anchnet account, add `ANCHNET_CONFIG_FILE=$HOME/.anchnet/config-devtest`; to increase bandwidth, add `MASTER_BW=5 NODE_BW=30`.

- Step2:
  Test features enabled in caicloud, on the same cluster e.g.
  ```
  $ TEST_BUILD=N TEST_UP=N CAICLOUD_TEST_FOCUS_REGEX="\[Feature:Elasticsearch\]" KUBERNETES_PROVIDER=caicloud-anchnet ./hack/caicloud/caicloud-e2e-test.sh
  ```
  Note `ANCHNET_CONFIG_FILE` is required if the cluster is creating with this option.

- Step3:
  Re-run failed tests. You may want to create a new cluster if you touches core kubernetes codebase:
  ```
  $ TEST_BUILD=Y TEST_UP=N CAICLOUD_TEST_FOCUS_REGEX="\[ReplicationController.*light\]" KUBERNETES_PROVIDER=caicloud-anchnet ./hack/caicloud/caicloud-e2e-test.sh
  ```
