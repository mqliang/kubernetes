#!/bin/bash

cdp_username=${1}
cdp_password=${2}
cdp_ip=${3}
cdp_device=${4}
# Size of the first partion for /var/lib/docker
cdp_first_size=${5}
cdp_success_flag=${6}

# First create two partitions, and then format the disk, and then mount,
# and finally add the two partitions to /etc/fstab
expect <<EOF
set timeout 20
spawn ssh -tt -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null ${cdp_username}@${cdp_ip} "echo \"n
p
1

+${cdp_first_size}G
n
p
2


w
\" | sudo fdisk ${cdp_device} && \
sudo mkfs.ext4 ${cdp_device}1 && \
sudo mkfs.ext4 ${cdp_device}2 && \
sudo mkdir -p /var/lib/docker && \
sudo mkdir -p /var/lib/kubelet && \
sudo mount ${cdp_device}1 /var/lib/docker && \
sudo mount ${cdp_device}2 /var/lib/kubelet && \
sudo echo \"${cdp_device}1 /var/lib/docker ext4 defaults 0 1\" >> /etc/fstab && \
sudo echo \"${cdp_device}2 /var/lib/docker ext4 defaults 0 1\" >> /etc/fstab && \
echo ${cdp_success_flag}"

expect {
  "*?assword*" {
    send -- "${cdp_password}\r"
    exp_continue
  }
  "lost connection" { exit 1 }
  timeout { exit 1 }
  eof {}
}
EOF
