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
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/golang/glog"
	"k8s.io/kubernetes/pkg/cloudprovider/providers/anchnet"
	"k8s.io/kubernetes/pkg/volume"
)

// AnchnetDiskUtil implements pdManager which abstracts interface to PD operations.
type AnchnetDiskUtil struct{}

func (util *AnchnetDiskUtil) AttachAndMountDisk(b *anchnetPersistentDiskMounter, globalPDPath string) error {
	cloud, err := getCloudProvider(b.anchnetPersistentDisk.plugin)
	if err != nil {
		return err
	}
	devicePath, err := cloud.AttachDisk("", b.volumeID, b.readOnly)
	if err != nil {
		return err
	}
	if b.partition != "" {
		devicePath = devicePath + b.partition
	}
	numTries := 0
	for {
		_, err := os.Stat(devicePath)
		if err == nil {
			break
		}
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		numTries++
		if numTries == 10 {
			return errors.New("Could not attach disk: Timeout after 10s (" + devicePath + ")")
		}
		time.Sleep(time.Second)
	}

	// Only mount the PD globally once.
	notMnt, err := b.mounter.IsLikelyNotMountPoint(globalPDPath)
	if err != nil {
		if os.IsNotExist(err) {
			if err := os.MkdirAll(globalPDPath, 0750); err != nil {
				return err
			}
			notMnt = true
		} else {
			return err
		}
	}
	options := []string{}
	if b.readOnly {
		options = append(options, "ro")
	}
	if notMnt {
		err = b.diskMounter.FormatAndMount(devicePath, globalPDPath, b.fsType, options)
		if err != nil {
			os.Remove(globalPDPath)
			return err
		}
	}
	return nil
}

func (util *AnchnetDiskUtil) DetachDisk(c *anchnetPersistentDiskUnmounter) error {
	// Unmount the global PD mount, which should be the only one.
	globalPDPath := makeGlobalPDPath(c.plugin.host, c.volumeID)
	if err := c.mounter.Unmount(globalPDPath); err != nil {
		glog.Info("Error unmount dir ", globalPDPath, ": ", err)
		return err
	}
	if err := os.Remove(globalPDPath); err != nil {
		glog.Info("Error removing dir ", globalPDPath, ": ", err)
		return err
	}
	// Detach the disk.
	cloud, err := getCloudProvider(c.anchnetPersistentDisk.plugin)
	if err != nil {
		return err
	}
	if err := cloud.DetachDisk("", c.volumeID); err != nil {
		glog.Info("Error detaching disk ", c.volumeID, ": ", err)
		return err
	}
	return nil
}

func (util *AnchnetDiskUtil) CreateDisk(p *anchnetPersistentDiskProvisioner) (volumeID string, volumeSizeGB int, labels map[string]string, err error) {
	cloud, err := getCloudProvider(p.anchnetPersistentDisk.plugin)
	if err != nil {
		return "", 0, nil, err
	}

	// No limit about an Anchnet PD' name length, by now, set it at most 255 characters
	name := volume.GenerateVolumeName(p.options.ClusterName, p.options.PVName, 255)
	requestBytes := p.options.Capacity.Value()
	requestGB := volume.RoundUpSize(requestBytes, 1024*1024*1024)

	volumeID, err = cloud.CreateVolume(&anchnet_cloud.VolumeOptions{
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
	cloud, err := getCloudProvider(deleter.anchnetPersistentDisk.plugin)
	if err != nil {
		return err
	}

	if err = cloud.DeleteVolume(deleter.volumeID); err != nil {
		glog.V(2).Infof("Error deleting Anchnet PD volume %s: %v", deleter.volName, err)
		return err
	}
	glog.V(2).Infof("Successfully deleted Anchnet PD volume %s", deleter.volName)
	return nil
}

// Return cloud provider
func getCloudProvider(plugin *anchnetPersistentDiskPlugin) (*anchnet_cloud.Anchnet, error) {
	if plugin == nil {
		return nil, fmt.Errorf("Failed to get Anchnet Cloud Provider. plugin object is nil.")
	}
	if plugin.host == nil {
		return nil, fmt.Errorf("Failed to get Anchnet Cloud Provider. plugin.host object is nil.")
	}

	cloudProvider := plugin.host.GetCloudProvider()
	anchnetCloudProvider, ok := cloudProvider.(*anchnet_cloud.Anchnet)
	if !ok || anchnetCloudProvider == nil {
		return nil, fmt.Errorf("Failed to get Anchnet Cloud Provider. plugin.host.GetCloudProvider returned %v instead", cloudProvider)
	}

	return anchnetCloudProvider, nil
}
