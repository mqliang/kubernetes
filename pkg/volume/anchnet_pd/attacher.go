/*
Copyright 2016 The Kubernetes Authors All rights reserved.

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
	"path"
	"strconv"
	"time"

	"github.com/golang/glog"
	"k8s.io/kubernetes/pkg/cloudprovider/providers/anchnet"
	"k8s.io/kubernetes/pkg/types"
	"k8s.io/kubernetes/pkg/util/exec"
	"k8s.io/kubernetes/pkg/util/mount"
	"k8s.io/kubernetes/pkg/volume"
)

type anchnetPersistentDiskAttacher struct {
	host           volume.VolumeHost
	anchnetVolumes anchnet_cloud.Volumes
}

var _ volume.Attacher = &anchnetPersistentDiskAttacher{}

var _ volume.AttachableVolumePlugin = &anchnetPersistentDiskPlugin{}

func (plugin *anchnetPersistentDiskPlugin) NewAttacher() (volume.Attacher, error) {
	anchnetCloud, err := getCloudProvider(plugin.host.GetCloudProvider())
	if err != nil {
		return nil, err
	}

	return &anchnetPersistentDiskAttacher{
		host:           plugin.host,
		anchnetVolumes: anchnetCloud,
	}, nil
}

func (plugin *anchnetPersistentDiskPlugin) GetDeviceMountRefs(deviceMountPath string) ([]string, error) {
	mounter := plugin.host.GetMounter()
	return mount.GetMountRefs(mounter, deviceMountPath)
}

func (attacher *anchnetPersistentDiskAttacher) Attach(spec *volume.Spec, nodeName types.NodeName) (string, error) {
	volumeSource, readOnly, err := getVolumeSource(spec)
	if err != nil {
		return "", err
	}

	diskName := volumeSource.VolumeID

	// anchnetCloud.AttachDisk checks if disk is already attached to node and
	// succeeds in that case, so no need to do that separately.
	devicePath, err := attacher.anchnetVolumes.AttachDisk(diskName, nodeName, readOnly)
	if err != nil {
		glog.Errorf("Error attaching volume %q: %+v", diskName, err)
		return "", err
	}

	return devicePath, nil
}

// VolumesAreAttached checks whether the list of volumes still attached to the specified
// the node. It returns a map which maps from the volume spec to the checking result.
// If an error is occured during checking, the error will be returned
func (attacher *anchnetPersistentDiskAttacher) VolumesAreAttached(specs []*volume.Spec, nodeName types.NodeName) (map[*volume.Spec]bool, error) {
	volumesAttachedCheck := make(map[*volume.Spec]bool)
	volumeSpecMap := make(map[string]*volume.Spec)
	volumeIDList := []string{}
	for _, spec := range specs {
		volumeSource, _, err := getVolumeSource(spec)
		if err != nil {
			glog.Errorf("Error getting volume (%q) source : %v", spec.Name(), err)
			continue
		}

		volumeIDList = append(volumeIDList, volumeSource.VolumeID)
		volumesAttachedCheck[spec] = true
		volumeSpecMap[volumeSource.VolumeID] = spec
	}
	attachedResult, err := attacher.anchnetVolumes.DisksAreAttached(volumeIDList, nodeName)
	if err != nil {
		glog.Errorf(
			"Error checking if volumes (%v) are attached to current node (%q). err=%v",
			volumeIDList, nodeName, err)
		return volumesAttachedCheck, err
	}

	for volumeID, attached := range attachedResult {
		if !attached {
			spec := volumeSpecMap[volumeID]
			volumesAttachedCheck[spec] = false
			glog.V(2).Infof("VolumesAreAttached: check volume %q (specName: %q) is no longer attached", volumeID, spec.Name())
		}
	}
	return volumesAttachedCheck, nil
}

func (attacher *anchnetPersistentDiskAttacher) WaitForAttach(spec *volume.Spec, devicePath string, timeout time.Duration) (string, error) {
	volumeSource, _, err := getVolumeSource(spec)
	if err != nil {
		return "", err
	}

	volumeID := volumeSource.VolumeID
	partition := ""
	if volumeSource.Partition != 0 {
		partition = strconv.Itoa(int(volumeSource.Partition))
	}

	if devicePath == "" {
		return "", fmt.Errorf("WaitForAttach failed for Anchnet Volume %q: devicePath is empty.", volumeID)
	}

	ticker := time.NewTicker(checkSleepDuration)
	defer ticker.Stop()
	timer := time.NewTimer(timeout)
	defer timer.Stop()

	for {
		select {
		case <-ticker.C:
			glog.V(5).Infof("Checking Anchnet Volume %q is attached.", volumeID)
			if devicePath != "" {
				devicePaths := getDiskByIdPaths(partition, devicePath)
				path, err := verifyDevicePath(devicePaths)
				if err != nil {
					// Log error, if any, and continue checking periodically. See issue #11321
					glog.Errorf("Error verifying Anchnet Volume (%q) is attached: %v", volumeID, err)
				} else if path != "" {
					// A device path has successfully been created for the PD
					glog.Infof("Successfully found attached Anchnet Volume %q.", volumeID)
					return path, nil
				}
			} else {
				glog.V(5).Infof("Anchnet Volume (%q) is not attached yet", volumeID)
			}
		case <-timer.C:
			return "", fmt.Errorf("Could not find attached Anchnet Volume %q. Timeout waiting for mount paths to be created.", volumeID)
		}
	}
}

func (attacher *anchnetPersistentDiskAttacher) GetDeviceMountPath(
	spec *volume.Spec) (string, error) {
	volumeSource, _, err := getVolumeSource(spec)
	if err != nil {
		return "", err
	}

	return makeGlobalPDPath(attacher.host, volumeSource.VolumeID), nil
}

// FIXME: this method can be further pruned.
func (attacher *anchnetPersistentDiskAttacher) MountDevice(spec *volume.Spec, devicePath string, deviceMountPath string) error {
	mounter := attacher.host.GetMounter()
	notMnt, err := mounter.IsLikelyNotMountPoint(deviceMountPath)
	if err != nil {
		if os.IsNotExist(err) {
			if err := os.MkdirAll(deviceMountPath, 0750); err != nil {
				return err
			}
			notMnt = true
		} else {
			return err
		}
	}

	volumeSource, readOnly, err := getVolumeSource(spec)
	if err != nil {
		return err
	}

	options := []string{}
	if readOnly {
		options = append(options, "ro")
	}
	if notMnt {
		diskMounter := &mount.SafeFormatAndMount{Interface: mounter, Runner: exec.New()}
		err = diskMounter.FormatAndMount(devicePath, deviceMountPath, volumeSource.FSType, options)
		if err != nil {
			os.Remove(deviceMountPath)
			return err
		}
	}
	return nil
}

type anchnetPersistentDiskDetacher struct {
	mounter        mount.Interface
	anchnetVolumes anchnet_cloud.Volumes
}

var _ volume.Detacher = &anchnetPersistentDiskDetacher{}

func (plugin *anchnetPersistentDiskPlugin) NewDetacher() (volume.Detacher, error) {
	anchnetCloud, err := getCloudProvider(plugin.host.GetCloudProvider())
	if err != nil {
		return nil, err
	}

	return &anchnetPersistentDiskDetacher{
		mounter:        plugin.host.GetMounter(),
		anchnetVolumes: anchnetCloud,
	}, nil
}

func (detacher *anchnetPersistentDiskDetacher) Detach(deviceMountPath string, nodeName types.NodeName) error {
	volumeID := path.Base(deviceMountPath)

	attached, err := detacher.anchnetVolumes.DiskIsAttached(volumeID, nodeName)
	if err != nil {
		// Log error and continue with detach
		glog.Errorf(
			"Error checking if volume (%q) is already attached to current node (%q). Will continue and try detach anyway. err=%v",
			volumeID, nodeName, err)
	}

	if err == nil && !attached {
		// Volume is already detached from node.
		glog.Infof("detach operation was successful. volume %q is already detached from node %q.", volumeID, nodeName)
		return nil
	}

	if err = detacher.anchnetVolumes.DetachDisk(volumeID, nodeName); err != nil {
		glog.Errorf("Error detaching volumeID %q: %v", volumeID, err)
		return err
	}
	return nil
}

func (detacher *anchnetPersistentDiskDetacher) WaitForDetach(devicePath string, timeout time.Duration) error {
	ticker := time.NewTicker(checkSleepDuration)
	defer ticker.Stop()
	timer := time.NewTimer(timeout)
	defer timer.Stop()

	for {
		select {
		case <-ticker.C:
			glog.V(5).Infof("Checking device %q is detached.", devicePath)
			if pathExists, err := pathExists(devicePath); err != nil {
				return fmt.Errorf("Error checking if device path exists: %v", err)
			} else if !pathExists {
				return nil
			}
		case <-timer.C:
			return fmt.Errorf("Timeout reached; PD Device %v is still attached", devicePath)
		}
	}
}

func (detacher *anchnetPersistentDiskDetacher) UnmountDevice(deviceMountPath string) error {
	volume := path.Base(deviceMountPath)
	if err := unmountPDAndRemoveGlobalPath(deviceMountPath, detacher.mounter); err != nil {
		glog.Errorf("Error unmounting %q: %v", volume, err)
	}

	return nil
}
