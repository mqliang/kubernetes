# Aliyun instance Ansible

This playbook and set of roles set up aliyun instances for a kubernetes cluster. 

## Before starting

* Record the aliyun access key id and access key secret.
* Record the number of kubernetes minion nodes, default 2 minion nodes (Only one master support).
* Make sure the version of your ansible running machine is equal to or greater than 2.1.0.0 and python-netaddr installed.

## Setup

### Configure Aliyun instances options

There are various places to configure aliyun instances:

- `group_vars/all.yml`: contains options each role will use, namely aliyun access key id, access key secret, security group name and aliyun region id.

- `roles/ntpdate/default/main.yml`: contains options for ntpdate to sync the linux server time with network time servers.

- `roles/aliyuncli/default/main.yml`: contains options for aliyuncli tool.

- `roles/up/default/main.yml`: contains options for creating aliyun instances.

- `roles/down/default/main.yml`: contains options for deleting aliyun instances.

The options are described there in full detail.

## Running the playbook

### Create aliyun instances

After going through the setup, run the following command to create aliyun instances:

```
ansible-playbook -v --extra-vars="access_key_id=XXXX access_key_secret=YYYY" cluster/caicloud-aliyun/run.yml
```

or put environment variables in a json file, for example `extra_vars.json`:
```
{
    "access_key_id": "XXXX",
    "access_key_secret": "YYYY",
    "minion_node_num": 3
}
```

and then run the following command:

```
ansible-playbook -v --extra-vars "@extra_vars.json" cluster/caicloud-aliyun/run.yml
```

### Delete aliyun instances

If we want to delete aliyun instances, make sure set `delete_instance_flag="YES"` (refer to `roles/down/default/main.yml`), then run the following command:

```
ansible-playbook -v cluster/caicloud-aliyun/delete.yml
```

For example:

```
ansible-playbook -v --extra-vars="access_key_id=XXXX access_key_secret=YYYY delete_instance_flag=YES" cluster/caicloud-aliyun/delete.yml
```

It will delete all the instances in the aliyun security group (refer to `group_vars/all.yml`).

This will work on Ubuntu and CentOS.
