#!/bin/bash 
# Self-hosting for Caicloud-stack control cluster
# There are 2 steps to do
# (1) Create user in authserver, then get uid and token of the created user
# (2) Register kubernetes cluster to database for display
# usage : ./self_hosted.sh  caicloud-stack  caicloud-baremetal "vagrant:vagrant@192.168.10.109,vagrant:vagrant@192.168.10.121"  "vagrant:vagrant@192.168.10.110,vagrant:vagrant@192.168.10.122"  caicloud-stack  caicloudprivatetest.com  eSbsyAr2eDatXBxa   7EJncehPDHdVI0kJ true
#		para_01:  cluster_name      eg. caicloud-stack
#		para_02:  provider          eg. caicloud-baremetal
#		para_03:  master_ssh        eg. "vagrant:vagrant@192.168.10.109,vagrant:vagrant@192.168.10.121"
#		para_04:  node_ssh:	        eg. "vagrant:vagrant@192.168.10.110,vagrant:vagrant@192.168.10.122"
#		para_05:  dns_hostname      eg. caicloud-stack
#		para_06:  base_domain_name  eg. caicloudprivatetest.com
#		para_07:  cluster_token     eg. eSbsyAr2eDatXBxa
#		para_08:  kube_pwd          eg. 7EJncehPDHdVI0kJ
#		para_09:  controlcluster    eg. true

#  step 0: Do master_ssh and node_ssh information transform.
#  The ssh info string before this transform like this : "vagrant:vagrant@192.168.10.109,vagrant:vagrant@192.168.10.121",
#  after this transform, the  ssh info like this: ["vagrant:vagrant@192.168.10.109","vagrant:vagrant@192.168.10.121"]

#  step 0.1: Transform the master_ssh from  "vagrant:vagrant@192.168.10.109,vagrant:vagrant@192.168.10.121" to ["vagrant:vagrant@192.168.10.109","vagrant:vagrant@192.168.10.121"]
#  In processing a string contain double quotation marks (") may encounter unpredictable error, we use "::" instead double quotation marks (") in string
IFS=',' read -ra master_ssh_array <<< "$3"
num_M=${#master_ssh_array[*]}
master_ssh="["
for (( i = 0; i < ${#master_ssh_array[*]}; i++ )); do
	master_ssh="${master_ssh}::${master_ssh_array[$i]}::,"
done
master_ssh="${master_ssh%,}"
master_ssh="${master_ssh}]"
master_ssh="${master_ssh//::/\"}"

#  step 0.2: Transform the node_ssh from  "vagrant:vagrant@192.168.10.110,vagrant:vagrant@192.168.10.122" to ["vagrant:vagrant@192.168.10.110","vagrant:vagrant@192.168.10.122"]
#  In processing a string contain double quotation marks (") may encounter unpredictable error, we use "::" instead double quotation marks (") in string
IFS=',' read -ra node_ssh_array <<< "$4"
num_N=${#node_ssh_array[*]}
node_ssh="["
for (( i = 0; i < ${#node_ssh_array[*]}; i++ )); do
	node_ssh="${node_ssh}::${node_ssh_array[$i]}::,"
done
node_ssh="${node_ssh%,}"
node_ssh="${node_ssh}]"
node_ssh="${node_ssh//::/\"}"

# Step 1: Create user "caicloudadmin" in authserver, get uid and token of the user "caicloudadmin"
#AUTH_SERVER_URL=https://192.168.10.211/api/v1/proxy/namespaces/default/services/auth-server:3000
AUTH_SERVER_URL=http://auth-server:3000

for (( i = 0; i < 40; i++ )); do
	User_Token=`curl -k -w %{http_code} -H "Accept: application/json" -H "Content-Type: application/json"  -X POST -d '{ 
		"username": "caicloudadmin", 
		"password": "caicloudadmin"
	}' "$AUTH_SERVER_URL/api/v0.1/admin"`

	ret=`echo $User_Token  | awk -F\} '{print $(NF)}' `
	if [ "$ret" == "200" ]
	then
		echo "Getting uid and token success."
		break
	else
		if [ "$i" == "39" ]
		then
                echo "Getting uid and token failure."
                exit 1
        fi
		sleep 30
	fi
done

# Step 2: Register Caicloud-stack control cluster 
Uid=`echo $User_Token  | awk -F\" '{print $(NF-5)}' `
Ownertoken=`echo $User_Token  | awk -F\" '{print $(NF-1)}' `
#CDS_SERVER_URL=https://192.168.10.211/api/v1/proxy/namespaces/default/services/cds-server:9000
CDS_SERVER_URL=http://cds-server:9000

for (( i = 0; i < 40; i++ )); do
	ClusterID=`curl -X POST -w %{http_code} -H "Accept: application/json" -H "Content-Type: application/json"  -H "Cache-Control: no-cache" -d "{
		\"cluster_name\": \"$1\",
		\"provider\": \"$2\",
		\"num_of_masters\": $num_M,
		\"num_of_nodes\": $num_N,
		\"mem\": 2048,
		\"cpu\": 4,
		\"master_ssh\": $master_ssh,
		\"node_ssh\":	$node_ssh,
		\"dns_hostname\": \"$5\",
		\"base_domain_name\": \"$6\",
		\"owner_token\": \"$Ownertoken\",
		\"cluster_token\": \"$7\",
		\"kube_pwd\": \"$8\",
		\"controlcluster\": $9
	}
	" "$CDS_SERVER_URL/api/v0.1/$Uid/clusters/register"`

	ret=`echo $ClusterID  | awk -F\} '{print $(NF)}' `
	if [ "$ret" == "200" ]
	then
		echo "Self-hosting caicloud caicloud-stack cluster success."
		break
	else
		if [ "$i" == "39" ]
		then
			echo "Self-hosting caicloud caicloud-stack cluster failure."
			exit 1
        fi

		sleep 30
	fi
done
