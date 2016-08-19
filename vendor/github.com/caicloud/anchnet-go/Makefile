# Makefile
#
# Targets:
#   build
#   test
#   release

# Build local binaries.
build:
	cd anchnet && go build . && cd -
.PHONY: build

# Unit test.
test:
	go test .
.PHONY: test

# Make release, must pass version, e.g. make release VERSION=v0.1.0
release:
	UPLOAD_TO_QINIU=Y ./anchnet/build-tarball.sh $(VERSION)
.PHONY: release

# Clean up.
clean:
	rm -rf anchnet-go/anchnet/anchnet
	rm -rf _output
.PHONY: clean
