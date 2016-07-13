/*
Copyright 2015 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package cloudprovider

import (
	// Cloud providers
	_ "k8s.io/kubernetes/pkg/cloudprovider/providers/aliyun"
	_ "k8s.io/kubernetes/pkg/cloudprovider/providers/anchnet"
	_ "k8s.io/kubernetes/pkg/cloudprovider/providers/aws"
	_ "k8s.io/kubernetes/pkg/cloudprovider/providers/azure"
	_ "k8s.io/kubernetes/pkg/cloudprovider/providers/cloudstack"
	_ "k8s.io/kubernetes/pkg/cloudprovider/providers/gce"
	_ "k8s.io/kubernetes/pkg/cloudprovider/providers/mesos"
	_ "k8s.io/kubernetes/pkg/cloudprovider/providers/openstack"
	_ "k8s.io/kubernetes/pkg/cloudprovider/providers/ovirt"
	_ "k8s.io/kubernetes/pkg/cloudprovider/providers/rackspace"
	_ "k8s.io/kubernetes/pkg/cloudprovider/providers/vsphere"
)
