#!/bin/bash

for i in `seq 10`; do
  wpod=$(kubectl get pods --namespace=kube-system|grep weave|awk '{print $3}')
  if [ ! "$wpod" ] && [ $i -lt 10 ]; then
    sleep 5
    echo "waiting..."
  elif [ ! "$wpod" ] && [ $i -ge 10 ]; then
    echo "failed to get status, exist..."
    exit
  else
    echo "ok, pod is creating..."
    break
  fi
done

for i in $wpod; do

  flag=8
  while true;do
    if  [ $i != 'Running' ] && [ $flag -gt 0 ]; then
      echo "*** Detected weave pod's status $i ***\n    wait running ...\n"
      sleep 60
      : $((flag = $flag - 1))
    elif [ $i = 'Running' ]; then
      echo "** weave pod's status turn into running. **\n   weave should be Ready !"
      break
    else
      echo "Oops, weave pod status kept in $i, failed turn into running..."
      exit
    fi
  done

done
