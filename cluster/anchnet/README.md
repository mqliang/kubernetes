## Anchnet cloudprovider

Anchnet cloudprovider is internally supported by caicloud.io. It conforms to kubernetes cloudprovider plugin convention, and can be considered natively supported by kubernetes.

### Background on anchnet cloudprovider

[Anchnet](http://cloud.51idc.com/) is one of caicloud's IDC/IaaS parteners. It has most common features seen in other cloudproviders, e.g. Cloud Instances, External IPs, Load
balancers, etc, see [help center](http://cloud.51idc.com/help/cloud/index.html). [API doc](http://cloud.51idc.com/help/api/index.html) lists all public APIs (there are some
internal ones also). SDK is developed by caicloud team at https://github.com/caicloud/anchnet-go.

### Create a cluster using anchnet

To create a kubernetes cluster, make sure you've installed anchnet SDK. To install:
```
go get github.com/caicloud/anchnet-go/anchnet
```

This will install binary `anchnet` under `$GOPATH/bin`. The binary also needs a config file (e.g ~/.anchnet/config) with API keys, see [anchnet SDK](https://github.com/caicloud/anchnet-go),
After the setup, you can create the cluster by simply run:
```
KUBERNETES_PROVIDER=anchnet ./cluster/kube-up.sh
```

##### Options:

Following is a curated list of options used for kube-up; there are a lot of other configurations not listed here, see `config-default.sh`, `executor-config.sh`.

* `CLUSTER_NAME`: The name of newly created cluster. This is used to identify cluster; all resources will be prefixed with this name. The variable is default to "k8s-default".
  E.g. the following command will create a cluster named "caicloud-rocks", and all instances (plus other resources) will be prefixed with "caicloud-rocks".
    ```
    KUBERNETES_PROVIDER=anchnet CLUSTER_NAME=caicloud-rocks ./cluster/kube-up.sh
    ```

* `PROJECT_ID`: The project to use. In anchnet, project is actually a sub-account, it helps admin to manage resources. All resouces under a project (sub-account) is isolated
  from others. An anchnet account can have multiple sub-accounts. The variable is default to empty string, which means main-account. E.g. following command creates a cluster
  named "caicloud-rocks" under project "pro-H4ZW87K2" ("pro-H4ZW87K2" must exist):
    ```
    KUBERNETES_PROVIDER=anchnet CLUSTER_NAME=caicloud-rocks PROJECT_ID=pro-H4ZW87K2 ./cluster/kube-up.sh
    ```

* `KUBE_USER`: The kubernetes user name. This variable is default to empty string. If `KUBE_USER` is set, the `kubeconfig` file, which has all the information of how to access
  the cluster, will be created at `$HOME/.kube/config_${KUBE_USER}`. If not set, default location (`$HOME/.kube/config`) will be used. In production, we should always set
  `KUBE_USER`, leaving it empty should only be used during development. The variable has some correlation with `PROJECT_ID`:

  * If `PROJECT_ID` is set, it means this `KUBE_USER` has already been accociated with a sub account before, so that we just bring up cluster under that sub account:
    E.g. following command creates a cluster under a specific sub account:
    ```
    KUBERNETES_PROVIDER=anchnet CLUSTER_NAME=caicloud-rocks KUBE_USER=test_user PROJECT_ID=pro-H4ZW87K2 ./cluster/kube-up.sh
    ```

  * If `PROJECT_ID` is not set, it means this is the first time user wants to create a cluster and there is no anchnet sub account associated with `KUBE_USER`. In this case,
    an anchnet sub account will be automatically created and reported back to executor service, and the cluster will be allocated to the newly created sub account.
    E.g. following command will create a sub-account and then create a cluster:
    ```
    KUBERNETES_PROVIDER=anchnet CLUSTER_NAME=caicloud-rocks KUBE_USER=test_user ./cluster/kube-up.sh
    ```

* `ANCHNET_CONFIG_FILE`: The config file supplied to `anchnet` SDK CLI. Default value is `~/.anchnet/config`. Usually, you don't have to change the value, unless you want to
  create cluster under another anchnet account (NOT sub-account).

### Delete a cluster

To bring down a cluster, run:

```
KUBERNETES_PROVIDER=anchnet ./cluster/kube-down.sh
```

##### Options:

* `CLUSTER_NAME`: Delete cluster with given name.

* `PROJECT_ID`: Delete cluster from sub-account with given id. E.g. following command deletes cluster "caicloud-rocks" under project "pro-H4ZW87K2".
  ```
  KUBERNETES_PROVIDER=anchnet CLUSTER_NAME=caicloud-rocks PROJECT_ID=pro-H4ZW87K2 ./cluster/kube-down.sh
  ```

### Update a cluster

To update a cluster, run:

```
KUBERNETES_PROVIDER=anchnet ./cluster/kube-push.sh
```

Updating a cluster will build current code base and push/restart cluster, useful for development.

##### Options:

Same options as deleting a cluster.