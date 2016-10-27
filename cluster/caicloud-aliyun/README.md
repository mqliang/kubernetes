# Caicloud aliyun cloudprovider

Aliyun cloudprovider provides an ansible deployment of aliyun instances and kubernetes cluster.

## Set environment variables

### Required
We must set the following two environment variables:
```
ACCESS_KEY_ID
ACCESS_KEY_SECRET
    User aliyun account information, required to access aliyun cloud service.
```

### Optional

```
NUM_NODES
    The number of aliyun instances for kubernetes minion nodes. Default: 2

AUTOMATICALLY_INSTALL_TOOLS
    `Ansible`, `aliyuncli` and there `dependencies` will not be installed by default, namely: `AUTOMATICALLY_INSTALL_TOOLS="NO"`. If you want to install them automatically, you need to set: `AUTOMATICALLY_INSTALL_TOOLS="YES"`.

DNS_HOST_NAME
    Let you reach the kubernetes cluster by host name. For example, if DNS_HOST_NAME is `test` and BASE_DOMAIN_NAME is `caicloudapp.com`, we will access the kubernetes cluster by `https://test.caicloudapp.com`.
    Default value is "caicloudstack".

BASE_DOMAIN_NAME
    For example: caicloudapp.com.
    Default value is "caicloudapp.com".
    Required: USER_CERT_DIR.

USER_CERT_DIR
    User certificates directory, including ca.crt, master.crt, master.key. Required: BASE_DOMAIN_NAME

DOMAIN_NAME_IN_DNS
    Determine whether to process domain name (${DNS_HOST_NAME}.${BASE_DOMAIN_NAME}) in aliyun dns when kube-up and kube-down.
    If `DOMAIN_NAME_IN_DNS == YES`, domain name will be added/deleted when kube-up/kube-down.
    Default value is `YES` (valid value: `YES/NO`).

CAICLOUD_ACCESS_KEY_ID
CAICLOUD_ACCESS_KEY_SECRET
    Caicloud aliyun account information, required to access aliyun dns, when `DOMAIN_NAME_IN_DNS == YES`.

DELETE_INSTANCE_FLAG
    Determine whether to delete aliyun instances when kube-down.
    Default value is `YES` (valid value: `YES/NO`).

REPORT_KUBE_STATUS
    Default value is `N` (valid value: `Y/N`).
EXECUTOR_HOST_NAME
EXECUTION_ID
    To indicate if the execution status needs to be reported back to caicloud executor.

NTPDATE_SYNC_TIME
    Determine whether to sync time with ntpdate tool.
    Default value is `NO` (valid value: `YES/NO`).

CLUSTER_NAME
    If defined, we will use it as the security_group_name, master_name_prefix and node_name_prefix (in caicloud-aliyun/group_vars/all.yml). And it's no need to set MASTER_NAME_PREFIX and NODE_NAME_PREFIX.
MASTER_NAME_PREFIX
    For aliyun instances hostname and the option --hostname-override on masters. It will be ignored if CLUSTER_NAME is set.
    Default value is "kube-master-".
NODE_NAME_PREFIX
    For aliyun instances hostname and the option --hostname-override on nodes. It will be ignored if CLUSTER_NAME is set.
    Default value is "kube-node-".
```

## Change aliyun instances deployment configurations

We can change the default configurations of the aliyun instances by environment variables. If not seting these environment variables, It will use the default values. For details, please refer to [README-ALIYUN-INSTANCE](README-ALIYUN-INSTANCE.md).

Naming rules of aliyun instances environment variables:
```
CAICLOUD_ALIYUN_CFG_NUMBER_XX_YY
CAICLOUD_ALIYUN_CFG_STRING_XX_YY
```

`CAICLOUD_ALIYUN_CFG_NUMBER_/STRING_` is the prefix, `NUMBER` means its value is a number, `STRING` means its value is a string, and `XX_YY` is the variable name in uppercase.

For example, default value of `security_group_name` variable is `"kube-default"`, if we want to change the default value to `"dev-1"`, we should set the `CAICLOUD_ALIYUN_CFG_STRING_SECURITY_GROUP_NAME` environment variable:
```
# Recommended for each cluster to set up a security group
export CAICLOUD_ALIYUN_CFG_STRING_SECURITY_GROUP_NAME="dev-1"
```

## Change kubernetes cluster configurations

We can change the default configurations of the kubernetes cluster by environment variables. If not seting these environment variables, It will use the default values. For details, please refer to [README-ANSIBLE](../caicloud-ansible/README-ANSIBLE.md).

Naming rules of kubernetes cluster environment variables:
```
CAICLOUD_K8S_CFG_NUMBER_XX_YY
CAICLOUD_K8S_CFG_STRING_XX_YY
```

`CAICLOUD_K8S_CFG_NUMBER/STRING` is the prefix, `NUMBER` means its value is a number, `STRING` means its value is a string, and `XX_YY` is the variable name in uppercase.

For example, default value of `host_provider` variable is `"vagrant"`, if we want to change the default value to `"aliyun"`, we should set the `CAICLOUD_K8S_CFG_STRING_HOST_PROVIDER` environment variable:
```
export CAICLOUD_K8S_CFG_STRING_HOST_PROVIDER="aliyun"
```

**Note:**

The machine on which we deploy kubernetes cluster is “Control Machine”. By default, control machine is not one of masters. If control machine is just one of masters, then we should set:
```
export CAICLOUD_K8S_CFG_STRING_CONTROL_MACHINE_IS_MASTER="YES"
```

Because we will fetch kubectl binary from master0 and add the mapping of master ip and domain into /etc/hosts on the control machine. Then we will access the kubernetes cluster by https://caicloudstack.caicloudprivatetest.com or https://caicloudstack.caicloudapp.com.

## Bring up kubernete cluster on aliyun instances

Now, to bring up kubernete cluster, simply run:
```
KUBERNETES_PROVIDER=caicloud-aliyun ./cluster/kube-up.sh
```

## Bring down kubernetes cluster on aliyun instances

```
KUBERNETES_PROVIDER=caicloud-aliyun ./cluster/kube-down.sh
```

**Note:**

Aliyun instances will not be stopped and deleted after bringing down kubernetes cluster by default. If we also want to delete aliyun instances, please add `CAICLOUD_ALIYUN_CFG_STRING_DELETE_INSTANCE_FLAG="YES"`:

```
export CAICLOUD_ALIYUN_CFG_STRING_DELETE_INSTANCE_FLAG="YES"
KUBERNETES_PROVIDER=caicloud-aliyun ./cluster/kube-down.sh
```
