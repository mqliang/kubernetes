#!/usr/bin/env bash

# Assumed var:
#   DOCKER_VERSION
#   OS_DISTRO

if [[ -z "${DOCKER_VERSION-}" ]] || [[ -z "${OS_DISTRO}" ]]; then
  echo "Error: DOCKER_VERSION or OS_DISTRO is empty" >&2
  exit 1
fi

flag=1

# Check docker version
docker_bin=`which docker`
if [[ ! -z ${docker_bin} ]]; then
  match=`docker --version | grep "${DOCKER_VERSION}" | wc -l`
  if [[ $match -eq 1 ]]; then
    flag=0
  fi
fi

# If docker is failed to find or docker version is not matched,
# then remove docker-xxxx, for example:
#   docker-engine.x86_64
#   docker-selinux.x86_64
if [[ ${flag} -eq 1 ]]; then
  distro=`echo ${OS_DISTRO} | tr '[:upper:]' '[:lower:]'`
  if [[ ${distro} == "centos" ]]; then
    docker_components=`yum list installed | grep docker | awk -F' ' '{print $1}'`
    for component in ${docker_components}; do
      sudo yum remove -y ${component}
    done
  elif [[ ${distro} == "ubuntu" ]]; then
    docker_components=`dpkg --list | grep "^i" | grep docker | awk -F' ' '{print $2}'`
    for component in ${docker_components}; do
      sudo apt-get remove -y ${component}
    done
  fi
fi
