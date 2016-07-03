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

We must set the following two environment variables:
```
MASTER_SSH_INFO
    The master node ssh information in the format of "username:password@ip_address". HA master is currently supported.

NODE_SSH_INFO
    The worker node ssh information in the format of "username:password@ip_address".
```

## Change default configurations

We can change the default configurations of the kubernetes cluster by environment variables. If not seting these environment variables, It will use the default values. For details, please refer to [README-ANSIBLE](README-ANSIBLE.md).

Naming rules of environment variables:
```
CAICLOUD_K8S_CFG_XX_YY
```

`CAICLOUD_K8S_CFG_` is the prefix, and `XX_YY` is the variable name in uppercase.

For example, default value of `host_provider` variable is `"vagrant"`, if we want to change the default value to `"anchnet"`, we should set the `CAICLOUD_K8S_CFG_HOST_PROVIDER` environment variable:
```
export CAICLOUD_K8S_CFG_HOST_PROVIDER="anchnet"
```

## Bring up kubernete cluster

Now, to bring up kubernete cluster, simply run:
```
KUBERNETES_PROVIDER=caicloud-ansible ./cluster/kube-up.sh
```

## Bring down kubernetes cluster
Todo...
