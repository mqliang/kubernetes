#!/bin/bash

lsmod | grep "ip_vs" > /dev/null || {
  
  grep "^##LOAD_IP_VS" /etc/modules > /dev/null 2>&1 || {
    echo "##LOAD_IP_VS" >> /etc/modules
    echo "ip_vs" >> /etc/modules
    echo "ip_vs_wrr" >> /etc/modules
    echo "ip_vs_rr" >> /etc/modules
    echo "ip_vs_dh" >> /etc/modules
    echo "ip_vs_sh" >> /etc/modules
  }
  
  modprobe ip_vs
  modprobe ip_vs_wrr
  modprobe ip_vs_rr
  modprobe ip_vs_dh
  modprobe ip_vs_sh
}

find1=`grep "^net.ipv4.ip_forward" /etc/sysctl.conf | wc -l`
if [ "x$find1" == "x1" ]; then
  sed -i "/^net.ipv4.ip_forward/s/[^ ]*$/1/g" /etc/sysctl.conf
else
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
fi

find2=`grep "^net.ipv4.ip_nonlocal_bind" /etc/sysctl.conf | wc -l`
if [ "x$find2" == "x1" ]; then
  sed -i "/^net.ipv4.ip_nonlocal_bind/s/[^ ]*$/1/g" /etc/sysctl.conf
else
  echo "net.ipv4.ip_nonlocal_bind = 1" >> /etc/sysctl.conf
fi

sysctl -p
