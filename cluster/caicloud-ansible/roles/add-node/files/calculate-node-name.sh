#!/bin/bash

current_node=$("$kubectl" get node | grep node | awk '{print $1}' | awk -F '-' '{print $3}' | sort -n)
current_node=($current_node)
added_node_num=0
total_node_num=$TOTAL_NODE_NUM
for (( i = 0; i < ${#current_node[*]} + $total_node_num; i++ )); do
  j=$((i+1))
  if [[ ${current_node[$i - $added_node_num]} != $j ]]; then
    echo "${NODE_NAME_PREFIX}${j}"
    ((added_node_num++))
  fi
  if (( $added_node_num  == $total_node_num )); then
    break
  fi
done