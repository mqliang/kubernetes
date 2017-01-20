#!/bin/bash

set -o errexit

# See detail here: https://docs.docker.com/engine/userguide/storagedriver/device-mapper-driver/

# Exit if lv exist
lvs -o+seg_monitor | grep 'thinpool docker' && exit 0

# Clean old docker files
rm -rf /var/lib/docker

# Create a physical volume
pvcreate -y ${DOCKER_PARTITION}

# Create a ‘docker’ volume group
vgcreate docker ${DOCKER_PARTITION}

# Create a thin pool named thinpool
lvcreate --wipesignatures y -n thinpool docker -l 95%VG
lvcreate --wipesignatures y -n thinpoolmeta docker -l 1%VG

# Convert the pool to a thin pool
lvconvert -y --zero n -c 512K --thinpool docker/thinpool --poolmetadata docker/thinpoolmeta

# Configure autoextension of thin pools via an lvm profile
cat <<'EOF' > /etc/lvm/profile/docker-thinpool.profile 
activation {
    thin_pool_autoextend_threshold=80
    thin_pool_autoextend_percent=20
}
EOF

# Apply your new lvm profile
lvchange

# Verify the lv is monitored
lvs -o+seg_monitor
