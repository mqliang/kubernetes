# Makefile
#
#
.PHONY: build push

IMAGE = self-hosted
TAG = v0.0.3

build:
	docker build -t index.caicloud.io/caicloud/$(IMAGE):$(TAG) .

push:
	docker push index.caicloud.io/caicloud/$(IMAGE):$(TAG)	
