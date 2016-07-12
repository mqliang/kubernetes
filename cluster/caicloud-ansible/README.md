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

### Optional

```
DNS_HOST_NAME
    Let you reach the kubernetes cluster by host name. For example, if DNS_HOST_NAME is test and BASE_DOMAIN_NAME is caicloudapp.com, we will access the kubernetes cluster by https://test.caicloudapp.com.

BASE_DOMAIN_NAME
    For example: caicloudapp.com. Required: USER_CERT_DIR
USER_CERT_DIR
    User certificates directory, including ca.crt, master.crt, master.key. Required: BASE_DOMAIN_NAME
```

**Note:**

If deploying a caicloud stack in **private cloud environment**, we must set:
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
