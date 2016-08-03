# Caicloud ansible cloudprovider

Ansible cloudprovider provides an ansible deployment of kubernetes cluster. It assumes nothing but a few running instances.

## Create a development cluster

To create a kubernetes cluster for local developement, first create VMs using Vagrant file:
```
VAGRANT_VAGRANTFILE=Vagrantfile.ubuntu vagrant up
or
VAGRANT_VAGRANTFILE=Vagrantfile.centos vagrant up
```

This will create three ubuntu VMs with dedicated IP addresses.

## Set environment variables

### Required
We must set the following two environment variables:
```
MASTER_SSH_INFO
    The master node ssh information in the format of "username:password@ip_address".

NODE_SSH_INFO
    The worker node ssh information in the format of "username:password@ip_address".
```

or

```
MASTER_INTERNAL_SSH_INFO
    The master node ssh information in the format of "username:password@ip_address" with an internal ip address.

NODE_INTERNAL_SSH_INFO
    The worker node ssh information in the format of "username:password@ip_address" with an internal ip address.
```

**Note:**

Actually, if we set `XX_SSH_INFO` (`XX` means `MASTER` or `NODE`) but don't set `XX_INTERNAL_SSH_INFO`, then `XX_INTERNAL_SSH_INFO` will be initialized by `XX_SSH_INFO`.

If we set `XX_INTERNAL_SSH_INFO`, then `XX_SSH_INFO` will be ignored.

### Optional

```
MASTER_EXTERNAL_SSH_INFO
    If the master node have an external ip address, then we can supply the ssh information with an external ip address in the format of "username:password@ip_address".
    If we don't set `MASTER_EXTERNAL_SSH_INFO`, then it will be initialized by `MASTER_INTERNAL_SSH_INFO` by default.

NODE_EXTERNAL_SSH_INFO
    If the minion node have an external ip address, then we can supply the ssh information with an external ip address in the format of "username:password@ip_address".
    If we don't set `NODE_EXTERNAL_SSH_INFO`, then it will be initialized by `NODE_INTERNAL_SSH_INFO` by default.

AUTOMATICALLY_INSTALL_TOOLS
    Ansible and it's dependencies will be installed by default, namely: `AUTOMATICALLY_INSTALL_TOOLS="YES"`. If you want to manually install ansible and dependencies, you need to set: `AUTOMATICALLY_INSTALL_TOOLS="NO"`.

DNS_HOST_NAME
    Let you reach the kubernetes cluster by host name. For example, if DNS_HOST_NAME is test and BASE_DOMAIN_NAME is caicloudapp.com, we will access the kubernetes cluster by https://test.caicloudapp.com.
    Default value is "caicloudstack".

BASE_DOMAIN_NAME
    For example: caicloudapp.com. Required: USER_CERT_DIR
USER_CERT_DIR.
    User certificates directory, including ca.crt, master.crt, master.key. Required: BASE_DOMAIN_NAME.

MASTER_NAME_PREFIX
    For the option of --hostname-override on masters.
    Default value is "kube-master-".
NODE_NAME_PREFIX
    For the option of --hostname-override on nodes.
    Default value is "kube-node-".
```

**Note:**

If deploying a caicloud stack in **private cloud environment** and control machine is not master, then we need to set:
```
DNS_HOST_NAME="caicloudstack"
```

Because in that case, we will add the mapping of master ip and domain into /etc/hosts on the control machine. Then we will access the kubernetes cluster by https://caicloudstack.caicloudprivatetest.com or https://caicloudstack.caicloudapp.com.

## Change default configurations

We can change the default configurations of the kubernetes cluster by environment variables. If not seting these environment variables, It will use the default values. For details, please refer to [README-ANSIBLE](README-ANSIBLE.md).

Naming rules of environment variables:
```
CAICLOUD_K8S_CFG_NUMBER_XX_YY
CAICLOUD_K8S_CFG_STRING_XX_YY
```

`CAICLOUD_K8S_CFG_NUMBER/STRING` is the prefix, `NUMBER` means its value is a number, `STRING` means its value is a string, and `XX_YY` is the variable name in uppercase.

For example, default value of `host_provider` variable is `"vagrant"`, if we want to change the default value to `"anchnet"`, we should set the `CAICLOUD_K8S_CFG_STRING_HOST_PROVIDER` environment variable:
```
export CAICLOUD_K8S_CFG_STRING_HOST_PROVIDER="anchnet"
```

## Bring up kubernete cluster

Now, to bring up kubernete cluster, simply run:
```
KUBERNETES_PROVIDER=caicloud-ansible ./cluster/kube-up.sh
```

## Bring down kubernetes cluster
```
KUBERNETES_PROVIDER=caicloud-ansible ./cluster/kube-down.sh
```

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

Typical workflow for running ansible e2e tests:

- Step1:
  Create a new test release:
  ```
  BUILD_CLOUD_IMAGE=N ./hack/caicloud/build-release.sh v0.10.0-e2e
  ```

- Step2:
  Create a new cluster:
  ```
  $ AUTOMATICALLY_INSTALL_ANSIBLE=NO CAICLOUD_K8S_CFG_STRING_KUBE_VERSION=v1.3.3+v0.10.0-e2e KUBERNETES_PROVIDER=caicloud-ansible ./cluster/kube-up.sh
  ```
  Note "v1.3.3" is the upstream kubernetes version defined in `./hack/caicloud/common.sh`.

- Step3:
  Run e2e tests:
  ```
  $ TEST_BUILD=Y TEST_UP=N KUBERNETES_PROVIDER=caicloud-ansible ./hack/caicloud/caicloud-e2e-test.sh
  ```
  Note for e2e tests, we need to tell e2e framework where to find kubernetes master (apart from ~/.kube/config
  file). This is achieved via KUBE_MASTER_IP and KUBE_MASTER environment. Default value is set at
  `./cluster/caicloud-ansible/util.sh#detect-master`.

  Following command runs conformance test:
  ```
  $ TEST_BUILD=N TEST_UP=N CAICLOUD_TEST_FOCUS_REGEX="\[Conformance]" KUBERNETES_PROVIDER=caicloud-ansible ./hack/caicloud/caicloud-e2e-test.sh
  ```

- Step4:
  Test features enabled in caicloud, on the same cluster e.g.
  ```
  $ TEST_BUILD=N TEST_UP=N CAICLOUD_TEST_FOCUS_REGEX="\[Feature:Elasticsearch\]" KUBERNETES_PROVIDER=caicloud-ansible ./hack/caicloud/caicloud-e2e-test.sh
  ```

- Step5:
  Re-run failed tests. You may want to create a new cluster (or update binaries) if you touches core kubernetes codebase:
  ```
  $ TEST_BUILD=Y TEST_UP=N CAICLOUD_TEST_FOCUS_REGEX="\[ReplicationController.*light\]" KUBERNETES_PROVIDER=caicloud-ansible ./hack/caicloud/caicloud-e2e-test.sh
  ```
