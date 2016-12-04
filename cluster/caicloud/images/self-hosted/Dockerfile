FROM index.caicloud.io/caicloud/ubuntu

RUN apt-get update && apt-get install -y curl
RUN apt-get clean  && rm -rf /var/lib/apt/lists/*  /tmp/*

WORKDIR /opt
ADD self-hosted.sh /opt/
