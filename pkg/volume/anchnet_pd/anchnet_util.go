/*
Copyright 2014 The Kubernetes Authors All rights reserved.

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

package anchnet_pd

import (
	"fmt"
	"os"
	"time"

	"github.com/golang/glog"
	"k8s.io/kubernetes/pkg/cloudprovider"
	"k8s.io/kubernetes/pkg/cloudprovider/providers/anchnet"
	"k8s.io/kubernetes/pkg/util/mount"
	"k8s.io/kubernetes/pkg/volume"
)

const (
	diskPartitionSuffix = ""
	checkSleepDuration  = time.Second
)

// AnchnetDiskUtil implements pdManager which abstracts interface to PD operations.
type AnchnetDiskUtil struct{}

func (util *AnchnetDiskUtil) CreateDisk(p *anchnetPersistentDiskProvisioner) (volumeID string, volumeSizeGB int, labels map[string]string, err error) {
	cloud, err := getCloudProvider(p.anchnetPersistentDisk.plugin.host.GetCloudProvider())
	if err != nil {
		return "", 0, nil, err
	}

	// No limit about an Anchnet PD' name length, by now, set it at most 255 characters
	name := volume.GenerateVolumeName(p.options.ClusterName, p.options.PVName, 255)
	requestBytes := p.options.Capacity.Value()
	requestGB := volume.RoundUpSize(requestBytes, 1024*1024*1024)

	volumeID, err = cloud.CreateDisk(&anchnet_cloud.VolumeOptions{
		Name:       name,
		CapacityGB: int(requestGB),
	})
	if err != nil {
		glog.V(2).Infof("Error creating Anchnet PD volume: %v", err)
		return "", 0, nil, err
	}
	glog.V(2).Infof("Successfully created Anchnet PD volume %s", name)

	labels, err = cloud.GetAutoLabelsForPD(name)
	if err != nil {
		// We don't really want to leak the volume here...
		glog.Errorf("error getting labels for volume %q: %v", name, err)
	}

	return volumeID, int(requestGB), labels, nil
}

func (util *AnchnetDiskUtil) DeleteDisk(deleter *anchnetPersistentDiskDeleter) error {
	cloud, err := getCloudProvider(deleter.anchnetPersistentDisk.plugin.host.GetCloudProvider())
	if err != nil {
		return err
	}

	if err = cloud.DeleteDisk(deleter.volumeID); err != nil {
		glog.V(2).Infof("Error deleting Anchnet PD volume %s: %v", deleter.volName, err)
		return err
	}
	glog.V(2).Infof("Successfully deleted Anchnet PD volume %s", deleter.volName)
	return nil
}

// Return cloud provider
func getCloudProvider(cloudProvider cloudprovider.Interface) (*anchnet_cloud.Anchnet, error) {
	anchnetCloudProvider, ok := cloudProvider.(*anchnet_cloud.Anchnet)
	if !ok || anchnetCloudProvider == nil {
		return nil, fmt.Errorf("Failed to get Anchnet Cloud Provider. GetCloudProvider returned %v instead", cloudProvider)
	}

	return anchnetCloudProvider, nil
}

// Unmount the global PD mount, which should be the only one, and delete it.
func unmountPDAndRemoveGlobalPath(globalMountPath string, mounter mount.Interface) error {
	err := mounter.Unmount(globalMountPath)
	os.Remove(globalMountPath)
	return err
}

// Checks if the specified path exists
func pathExists(path string) (bool, error) {
	_, err := os.Stat(path)
	if err == nil {
		return true, nil
	} else if os.IsNotExist(err) {
		return false, nil
	} else {
		return false, err
	}
}

// Returns list of all paths for given EBS mount
// This is more interesting on GCE (where we are able to identify volumes under /dev/disk-by-id)
// Here it is mostly about applying the partition path
func getDiskByIdPaths(partition string, devicePath string) []string {
	devicePaths := []string{}
	if devicePath != "" {
		devicePaths = append(devicePaths, devicePath)
	}

	if partition != "" {
		for i, path := range devicePaths {
			devicePaths[i] = path + diskPartitionSuffix + partition
		}
	}

	return devicePaths
}

// Returns the first path that exists, or empty string if none exist.
func verifyDevicePath(devicePaths []string) (string, error) {
	for _, path := range devicePaths {
		if pathExists, err := pathExists(path); err != nil {
			return "", fmt.Errorf("Error checking if path exists: %v", err)
		} else if pathExists {
			return path, nil
		}
	}

	return "", nil
}
