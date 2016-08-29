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

package aliyun_pd

import (
	"errors"
	"fmt"
	"os"
	"time"

	"k8s.io/kubernetes/pkg/cloudprovider/providers/aliyun"
	"k8s.io/kubernetes/pkg/volume"

	"github.com/golang/glog"
)

// AliyunDiskUtil implements pdManager which abstracts interface to PD operations.
type AliyunDiskUtil struct{}

func (util *AliyunDiskUtil) AttachAndMountDisk(b *aliyunPersistentDiskMounter, globalPDPath string) error {
	cloud, err := getCloudProvider(b.aliyunPersistentDisk.plugin)
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

func (util *AliyunDiskUtil) DetachDisk(c *aliyunPersistentDiskUnmounter) error {
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
	cloud, err := getCloudProvider(c.aliyunPersistentDisk.plugin)
	if err != nil {
		return err
	}
	if err := cloud.DetachDisk("", c.volumeID); err != nil {
		glog.Info("Error detaching disk ", c.volumeID, ": ", err)
		return err
	}
	return nil
}

func (util *AliyunDiskUtil) CreateDisk(p *aliyunPersistentDiskProvisioner) (volumeID string, volumeSizeGB int, labels map[string]string, err error) {
	cloud, err := getCloudProvider(p.aliyunPersistentDisk.plugin)
	if err != nil {
		return "", 0, nil, err
	}

	// No limit about an Aliyun PD' name length, by now, set it at most 255 characters
	name := volume.GenerateVolumeName(p.options.ClusterName, p.options.PVCName, 255)
	requestBytes := p.options.Capacity.Value()
	requestGB := volume.RoundUpSize(requestBytes, 1024*1024*1024)

	volumeID, err = cloud.CreateVolume(&aliyun.VolumeOptions{
		Name:       name,
		CapacityGB: int(requestGB),
	})
	if err != nil {
		glog.V(2).Infof("Error creating Aliyun PD volume: %v", err)
		return "", 0, nil, err
	}
	glog.V(2).Infof("Successfully created Aliyun PD volume %s", name)

	labels, err = cloud.GetAutoLabelsForPD(volumeID)
	if err != nil {
		// We don't really want to leak the volume here...
		glog.Errorf("error getting labels for volume %q: %v", name, err)
	}

	return volumeID, int(requestGB), labels, nil
}

func (util *AliyunDiskUtil) DeleteDisk(deleter *aliyunPersistentDiskDeleter) error {
	cloud, err := getCloudProvider(deleter.aliyunPersistentDisk.plugin)
	if err != nil {
		return err
	}

	if err = cloud.DeleteVolume(deleter.volumeID); err != nil {
		glog.V(2).Infof("Error deleting Aliyun PD volume %s: %v", deleter.volName, err)
		return err
	}
	glog.V(2).Infof("Successfully deleted Aliyun PD volume %s", deleter.volName)
	return nil
}

// Return cloud provider
func getCloudProvider(plugin *aliyunPersistentDiskPlugin) (*aliyun.Aliyun, error) {
	if plugin == nil {
		return nil, fmt.Errorf("Failed to get Aliyun Cloud Provider. plugin object is nil.")
	}
	if plugin.host == nil {
		return nil, fmt.Errorf("Failed to get Aliyun Cloud Provider. plugin.host object is nil.")
	}

	cloudProvider := plugin.host.GetCloudProvider()
	aliyunCloudProvider, ok := cloudProvider.(*aliyun.Aliyun)
	if !ok || aliyunCloudProvider == nil {
		return nil, fmt.Errorf("Failed to get Aliyun Cloud Provider. plugin.host.GetCloudProvider returned %v instead", cloudProvider)
	}

	return aliyunCloudProvider, nil
}
