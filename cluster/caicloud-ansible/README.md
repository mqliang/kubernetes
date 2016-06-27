# Kubernetes Ansible

This playbook and set of roles set up a Kubernetes cluster onto machines. They can be real hardware, VMs, things in
a public cloud, etc. Anything that you can connect to via SSH.

## Before starting

* Record the masters' IP address/hostname (only support a single master)
* Record the etcd's IP address/hostname (often same as master, only one)
* Record the nodes' IP addresses/hostname (master will be added as scheduling disabled)
* Make sure your ansible running machine has ansible 2.0 and python-netaddr installed.

## Setup

### Configure inventory

Add the system information gathered above into the 'inventory' file, or create a new inventory file for the cluster.

### Configure Cluster options

There are various places to configure cluster:

- `group_vars/all.yml`: contains cluster level options like cluster name, addons, network plugin, etc.

- `roles/etcd/default/main.yml`: contains options for etcd.

- `roles/docker/default/main.yml`: contains options for docker.

- `roles/flannel/default/main.yml`: contains options for flannel.

- `roles/kubernetes-base/default/main.yml`: contains options for kubernetes.

The options are described there in full detail.

## Running the playbook

After going through the setup, run the following command:

`ansible-playbook -v -i cluster/caicloud-ansible/inventory.vagrant cluster/caicloud-ansible/cluster.yml`

This will work on Ubuntu and CentOS.

### Targeted runs

You can just setup certain parts instead of doing it all, e.g. to only run addons:

```
`ansible-playbook -v -i cluster/caicloud-ansible/inventory.vagrant cluster/caicloud-ansible/cluster.yml -t addons`
```
