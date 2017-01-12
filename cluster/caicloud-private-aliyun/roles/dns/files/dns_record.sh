#!/bin/bash

dns_record_name=${1}
dns_recore_ip=${2}
dns_op_type=${3} # OP_INSTALL|OP_UNINSTALL

# Note: curl will alway return 200 from stategrid dns server,
# so we need anather method to check it.
#curl_opt="-s -o /dev/null -w %{http_code}"
curl_opt="-s"

dns_api="http://dnsapi1.tbsite.net/cgi-bin/dnsapi.cgi"

# Validate ipv4
function valid_ipv4 {
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    echo "$stat"
}

function get_dns_record_ip {
  ip=`nslookup ${dns_record_name} | tail -2 | sed -e '/^$/d' -e '/;;/d' | awk '{print $2}'`
  res=`valid_ipv4 $ip`
  if [[ $res -eq 0 ]]; then
    echo "$ip"
  else
    echo ""
  fi
}

function add_dns_record {
  res=`curl ${curl_opt} "${dns_api}?name=${dns_record_name}&ip=${dns_recore_ip}&action=add"`
  ret_code=$?
  if [[ ${ret_code} -gt 0 ]]; then
    echo "[Error] curl return code: ${ret_code}"
    exit 1
  fi
  #if [ "${res}" != "200" ]; then
  #  echo "add_dns_record error: ${res}"
  #  exit 1
  #fi
  error_found=`echo ${res} | grep 'ERROR' | wc -l`
  if [[ ${error_found} -gt 0 ]]; then
    echo "add_dns_record error: ${res}"
    exit 1
  fi
  echo "add_dns_record ok"
}

function update_dns_record {
  res=`curl ${curl_opt} "${dns_api}?name=${dns_record_name}&ip=${dns_recore_ip}&action=update"`
  ret_code=$?
  if [[ ${ret_code} -gt 0 ]]; then
    echo "[Error] curl return code: ${ret_code}"
    exit 1
  fi
  #if [ "${res}" != "200" ]; then
  #  echo "update_dns_record error: ${res}"
  #  exit 1
  #fi
  error_found=`echo ${res} | grep ERROR | wc -l`
  if [[ ${error_found} -gt 0 ]]; then
    echo "update_dns_record error: ${res}"
    exit 1
  fi
  echo "update_dns_record ok"
}

function remove_dns_record {
  res=`curl ${curl_opt} "${dns_api}?name=${dns_record_name}&ip=${dns_recore_ip}&action=remove"`
  ret_code=$?
  if [[ ${ret_code} -gt 0 ]]; then
    echo "[Error] curl return code: ${ret_code}"
    exit 1
  fi
  #if [ "${res}" != "200" ]; then
  #  echo "remove_dns_record error: ${res}"
  #  exit 1
  #fi
  error_found=`echo ${res} | grep ERROR | wc -l`
  if [[ ${error_found} -gt 0 ]]; then
    echo "remove_dns_record error: ${res}"
    exit 1
  fi
  echo "remove_dns_record ok"
}

if [ "${dns_op_type}" == "OP_UNINSTALL" ]; then
  check_ip=`get_dns_record_ip`
  # Make sure dns record exists before removing
  if [ "x${check_ip}" != "x" ]; then
    remove_dns_record
  else
    echo "Dns record has been already removed"
  fi
elif [[ "${dns_op_type}" == "OP_INSTALL" ]]; then
  check_ip=`get_dns_record_ip`
  # Make sure dns record don't exist beforing add, otherwise updating.
  if [ "x${check_ip}" == "x" ]; then
    add_dns_record
  elif [ "${check_ip}" != "${dns_recore_ip}" ]; then
    update_dns_record
  fi
else
  echo "Cann't support ${dns_op_type}"
  exit 1
fi
