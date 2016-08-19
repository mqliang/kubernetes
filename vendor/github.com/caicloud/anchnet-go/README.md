# Go client for anchnet API

Go client library for [anchnet](http://cloud.51idc.com/help/api/api_list.html)

## Overview

The library preserves all semantics from anchnet APIs.

`anchnet/` is the CLI tool implementation based on the client, see [README](anchnet/README.md)

## Authentication
Authentication is done reading a config file `~/.anchnet/config`. Example file:
```json
{
  "publickey":  "U9WGEXYO19ysz607rLXwOyC",
  "privatekey": "K4XX2OPKMA2VrMo4WjLFbRMMH3djEfW94LK4d1W"
}
```

## How to do a build release

To build a newer version, simply run
```
make release VERSION=v1.0.1
```
This will create two release tarballs `anchnet-go-darwin-amd64-v1.0.1.tar.gz` and `anchnet-go-linux-amd64-v1.0.1.tar.gz` under `_output` directory, and
push the tarball to toolserver and qiniu. Under the hood, it uses script `./anchnet/build-tarball.sh`, e.g.
```
$ ./anchnet/build-tarball.sh help
Error: caicloud version must be provided.

Usage:
  ./build-tarball.sh vesion

Parameter:
  version        Tarball release version, must in the form of vA.B.C, where A, B, C are digits, e.g. v1.0.1
  ...
  ...
```
