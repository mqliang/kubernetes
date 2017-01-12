#!/bin/bash

# Config for stategrid

ecs_domain_name=${ecs_domain_name-"ecs.cloud.zj.sgcc.com.cn"}
slb_domain_name=${slb_domain_name-"slb.cloud.zj.sgcc.com.cn"}

DOMAIN_NAME_IN_DNS=${DOMAIN_NAME_IN_DNS-"YES"}

CAICLOUD_ALIYUN_CFG_STRING_REGION_ID=${CAICLOUD_ALIYUN_CFG_STRING_REGION_ID-"cn-linping-zjdw-d01"}
CAICLOUD_ALIYUN_CFG_STRING_ZONE_ID=${CAICLOUD_ALIYUN_CFG_STRING_ZONE_ID-"cn-linping-zjdw-a"}
CAICLOUD_ALIYUN_CFG_STRING_INSTANCE_PASSWORD=${CAICLOUD_ALIYUN_CFG_STRING_INSTANCE_PASSWORD-"Admin1234"}
CAICLOUD_ALIYUN_CFG_STRING_ECS_ENDPOINT="http://${ecs_domain_name}"
CAICLOUD_ALIYUN_CFG_STRING_SLB_ENDPOINT="http://${slb_domain_name}"
CAICLOUD_ALIYUN_CFG_STRING_SLB_ADDRESS_TYPE="intranet"
# centos7u0_64_20G_zyy_20150130.vhd | ubuntu1404_64_20G_zyy_20150513.vhd
CAICLOUD_ALIYUN_CFG_STRING_IMAGE_ID=${CAICLOUD_ALIYUN_CFG_STRING_IMAGE_ID-"centos7u0_64_20G_zyy_20150130.vhd"}
CAICLOUD_ALIYUN_CFG_STRING_MASTER_INSTANCE_TYPE=${CAICLOUD_ALIYUN_CFG_STRING_MASTER_INSTANCE_TYPE-"ecs.s3.large"}
CAICLOUD_ALIYUN_CFG_STRING_NODE_INSTANCE_TYPE=${CAICLOUD_ALIYUN_CFG_STRING_NODE_INSTANCE_TYPE-"ecs.s3.large"}
CAICLOUD_ALIYUN_CFG_STRING_PUBLIC_IP_NEEDED=${CAICLOUD_ALIYUN_CFG_STRING_PUBLIC_IP_NEEDED-"NO"}
CAICLOUD_ALIYUN_CFG_STRING_ADD_DATA_DISK_FLAG=${CAICLOUD_ALIYUN_CFG_STRING_ADD_DATA_DISK_FLAG-"YES"}

CAICLOUD_K8S_CFG_STRING_HOST_PROVIDER="aliyun"

# For config file 'endpoints.xml' used by aliyuncli
# Comma separated
private_region_ids="cn-linping-zjdw-d01"
# ProductName@DomainName
private_products="Ecs@${ecs_domain_name},Slb@${slb_domain_name}"
