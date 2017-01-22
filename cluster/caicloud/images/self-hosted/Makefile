# Makefile
#
#
.PHONY: build push

IMAGE = self-hosted
TAG = v0.0.4

build:
	docker build -t cargo.caicloud.io/caicloud/$(IMAGE):$(TAG) .

push:
	docker push cargo.caicloud.io/caicloud/$(IMAGE):$(TAG)	
