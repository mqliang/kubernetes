/*
Copyright 2015 The Kubernetes Authors All rights reserved.

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

package anchnet_cloud

import (
	"github.com/GoogleCloudPlatform/kubernetes/pkg/cloudprovider"
)

const AnchnetZone = "ac1"

//
// Following methods implement Cloudprovider.Zones.
//
var _ cloudprovider.Zones = (*Anchnet)(nil)

// GetZone returns the Zone containing the current failure zone and locality region
// that the program is running in. In anchnet, there is only one zone - 'ac1'.
func (an *Anchnet) GetZone() (cloudprovider.Zone, error) {
	zone := cloudprovider.Zone{
		FailureDomain: AnchnetZone,
		Region:        AnchnetZone,
	}
	return zone, nil
}
