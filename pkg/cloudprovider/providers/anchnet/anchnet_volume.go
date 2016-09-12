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

package anchnet_cloud

import (
	"fmt"
	"io/ioutil"
	"strings"
	"time"

	"github.com/golang/glog"

	anchnet_client "github.com/caicloud/anchnet-go"
	"k8s.io/kubernetes/pkg/api/unversioned"
)

const (
	// Number of retries when unable to fetch device name from anchnet.
	RetryCountOnDeviceEmpty = 5
	// Constant interval between two retries for the above situation.
	RetryIntervalOnDeviceEmpty = 6 * time.Second
)

// Volumes is an interface for managing cloud-provisioned volumes.
type Volumes interface {
	// AttachDisk attaches the disk to the specified instance. `instanceID` can be empty
	// to mean "the instance on which we are running".
	// Returns the device path (e.g. /dev/xvdf) where we attached the volume.
	AttachDisk(instanceID string, volumeID string, readOnly bool) (string, error)
	// DetachDisk detaches the disk from the specified instance. `instanceID` can be empty
	// to mean "the instance on which we are running"
	DetachDisk(instanceID string, volumeID string) error
	// Create a volume with the specified options.
	CreateDisk(volumeOptions *VolumeOptions) (volumeID string, err error)
	// Delete a volume.
	DeleteDisk(volumeID string) error
	// Check if the volume is already attached to the instance
	DiskIsAttached(instanceID, diskName string) (bool, error)
}

var _ Volumes = (*Anchnet)(nil)

// AttachDisk attaches the disk to the specified instance. `instanceID` can be empty
// to mean "the instance on which we are running".
// Returns the device path (e.g. /dev/xvdf) where we attached the volume.
func (an *Anchnet) AttachDisk(instanceID string, volumeID string, readOnly bool) (string, error) {
	glog.Infof("AttachDisk(%v, %v, %v)", instanceID, volumeID, readOnly)
	/*
		// Do not support attaching volume for other instances.
		if instanceID != "" {
			return "", errors.New("unable to attach disk for instance other than self instance")
		}

		// Get hostname and convert it to instance ID. During cluster provisioning, we set hostname to
		// lowercased instance ID. Ideally, we can issue a request to cloudprovider to get instance
		// information of the host itself, but anchnet lacks the API.
		hostname, err := os.Hostname()
		if err != nil {
			return "", err
		}
		instanceID = convertToInstanceID(hostname)

		// Before attaching volume, check /sys/block for known disks. This is used in case anchnet
		// doesn't return device name from describe volume API.
		existing, err := readSysBlock("sd")
		if err != nil {
			return "", err
		}
	*/

	// Do the volume attach.
	attach_response, err := an.attachVolume(instanceID, volumeID)
	if err != nil {
		return "", err
	}
	jobSucceeded, err := an.WaitJobSucceededOrFailed(attach_response.JobID)
	if err != nil {
		return "", err
	}
	if !jobSucceeded {
		return "", fmt.Errorf("Failed to attach volume %v to instance %v", volumeID, instanceID)
	}

	devicePath := ""
	for i := 0; i < RetryCountOnDeviceEmpty; i++ {
		describe_response, err := an.describeVolume(volumeID)
		if err != nil || describe_response.ItemSet[0].Device == "" {
			glog.Infof("Volume %s device path is empty, retrying", volumeID)
			time.Sleep(RetryIntervalOnDeviceEmpty)
		} else {
			return describe_response.ItemSet[0].Device, nil
		}
	}

	/*
		if devicePath == "" {
			glog.Infof("Unable to fetch device name from describeVolume endpoint, fallback to search /sys/block")
			glog.Infof("AttachDisk found existing disks %+v", existing)
			// After attaching volume, check /sys/block again.
			current, err := readSysBlock("sd")
			if err != nil {
				return "", err
			}
			glog.Infof("AttachDisk found current disks %+v", current)

			existingMap := make(map[string]bool)
			for _, disk := range existing {
				existingMap[disk] = true
			}

			var diff []string
			for _, disk := range current {
				if _, ok := existingMap[disk]; !ok {
					diff = append(diff, disk)
				}
			}
			if len(diff) != 1 {
				return "", fmt.Errorf("Unable to find volume %v", diff)
			}
			devicePath = "/dev/" + diff[0]
		}
	*/

	glog.Infof("Found device path %+v", devicePath)
	return devicePath, nil
}

// DetachDisk detaches the disk from the specified instance. `instanceID` can be empty
// to mean "the instance on which we are running"
func (an *Anchnet) DetachDisk(instanceID string, volumeID string) error {
	glog.Infof("DetachDisk(%v, %v)", instanceID, volumeID)
	detach_response, err := an.detachVolume(volumeID)
	if err != nil {
		return err
	}
	jobSucceeded, err := an.WaitJobSucceededOrFailed(detach_response.JobID)
	if err != nil {
		return err
	}
	if !jobSucceeded {
		return fmt.Errorf("Failed to detach volume %v from instance %v", volumeID, instanceID)
	}
	return nil
}

// Create a volume with the specified options.
func (an *Anchnet) CreateDisk(volumeOptions *VolumeOptions) (volumeID string, err error) {
	glog.Infof("CreateDisk(%v, %v)", volumeOptions.Name, volumeOptions.CapacityGB)

	if volumeOptions.CapacityGB < 10 || volumeOptions.CapacityGB > 1000 || volumeOptions.CapacityGB%10 != 0 {
		return "", fmt.Errorf("Invalid capacity, must in [10, 1000] and be multiples of 10")
	}

	create_response, err := an.createVolume(volumeOptions)
	if err != nil {
		return
	}
	jobSucceeded, err := an.WaitJobSucceededOrFailed(create_response.JobID)
	if err != nil {
		return
	}
	if !jobSucceeded {
		return "", fmt.Errorf("Failed to create volume")
	}
	return create_response.VolumeIDs[0], nil
}

// Delete a volume.
func (an *Anchnet) DeleteDisk(volumeID string) error {
	glog.Infof("DeleteDisk: %v", volumeID)
	delete_response, err := an.deleteVolume(volumeID)
	if err != nil {
		return err
	}
	jobSucceeded, err := an.WaitJobSucceededOrFailed(delete_response.JobID)
	if err != nil {
		return err
	}
	if !jobSucceeded {
		fmt.Errorf("Failed to delete volume %v", volumeID)
	}
	return nil
}

// attachVolumes attaches a volume to given instance.
func (an *Anchnet) attachVolume(instanceID string, volumeID string) (*anchnet_client.AttachVolumesResponse, error) {
	for i := 0; i < RetryCountOnError; i++ {
		request := anchnet_client.AttachVolumesRequest{
			InstanceID: instanceID,
			VolumeIDs:  []string{volumeID},
		}
		var response anchnet_client.AttachVolumesResponse
		err := an.client.SendRequest(request, &response)
		if err == nil {
			glog.Infof("Attached volume %v to instance %v", volumeID, instanceID)
			return &response, nil
		} else {
			glog.Infof("Attempt %d: failed to attach volume: %v\n", i, err)
		}
		time.Sleep(time.Duration(i+1) * RetryIntervalOnError)
	}
	return nil, fmt.Errorf("Unable to attach volume %v to instance %v", volumeID, instanceID)
}

// detachVolumes detaches a volume.
func (an *Anchnet) detachVolume(volumeID string) (*anchnet_client.DetachVolumesResponse, error) {
	for i := 0; i < RetryCountOnError; i++ {
		request := anchnet_client.DetachVolumesRequest{
			VolumeIDs: []string{volumeID},
		}
		var response anchnet_client.DetachVolumesResponse
		err := an.client.SendRequest(request, &response)
		if err == nil {
			glog.Infof("Detached volume %v", volumeID)
			return &response, nil
		} else {
			glog.Infof("Attempt %d: failed to detach volume: %v\n", i, err)
		}
		time.Sleep(time.Duration(i+1) * RetryIntervalOnError)
	}
	return nil, fmt.Errorf("Unable to detach volume %v", volumeID)
}

// createVolume create a volume.
func (an *Anchnet) createVolume(options *VolumeOptions) (*anchnet_client.CreateVolumesResponse, error) {
	for i := 0; i < RetryCountOnError; i++ {
		request := anchnet_client.CreateVolumesRequest{
			VolumeName: options.Name,
			VolumeType: anchnet_client.VolumeTypeCapacity, //TODO(mqliang): expose this in API
			Size:       options.CapacityGB,
			Count:      1,
		}
		var response anchnet_client.CreateVolumesResponse
		err := an.client.SendRequest(request, &response)
		if err == nil {
			glog.Infof("Create volume name: %v", options.Name)
			return &response, nil
		} else {
			glog.Infof("Attempt %d: failed to create volume: %v\n", i, err)
		}
		time.Sleep(time.Duration(i+1) * RetryIntervalOnError)
	}
	return nil, fmt.Errorf("Unable to create volume %v", options.Name)
}

// deleteVolume delete a volume.
func (an *Anchnet) deleteVolume(volumeID string) (*anchnet_client.DeleteVolumesResponse, error) {
	for i := 0; i < RetryCountOnError; i++ {
		request := anchnet_client.DeleteVolumesRequest{
			VolumeIDs: []string{volumeID},
		}
		var response anchnet_client.DeleteVolumesResponse
		err := an.client.SendRequest(request, &response)
		if err == nil {
			glog.Infof("Delete volume ID: %v", volumeID)
			return &response, nil
		} else {
			glog.Infof("Attempt %d: failed to delete volume: %v\n", i, err)
		}
		time.Sleep(time.Duration(i+1) * RetryIntervalOnError)
	}
	return nil, fmt.Errorf("Unable to delete volume %v", volumeID)
}

// describeVolume describe a volume.
func (an *Anchnet) describeVolume(volumeID string) (*anchnet_client.DescribeVolumesResponse, error) {
	for i := 0; i < RetryCountOnError; i++ {
		request := anchnet_client.DescribeVolumesRequest{
			VolumeIDs: []string{volumeID},
		}
		var response anchnet_client.DescribeVolumesResponse
		err := an.client.SendRequest(request, &response)
		if err == nil {
			glog.Infof("Found volume %v", volumeID)
			return &response, nil
		} else {
			glog.Infof("Attempt %d: failed to describe volume: %v\n", i, err)
		}
		time.Sleep(time.Duration(i+1) * RetryIntervalOnError)
	}
	return nil, fmt.Errorf("Unable to describe volume %v", volumeID)
}

// Builds the labels that should be automatically added to a PersistentVolume backed by a Anchnet PD
// Specifically, this builds FailureDomain (zone) and Region labels.
// The PersistentVolumeLabel admission controller calls this and adds the labels when a PV is created.
func (an *Anchnet) GetAutoLabelsForPD(name string) (map[string]string, error) {
	zone, err := an.GetZone()
	if err != nil {
		return nil, err
	}

	labels := make(map[string]string)
	labels[unversioned.LabelZoneFailureDomain] = zone.FailureDomain
	labels[unversioned.LabelZoneRegion] = zone.Region

	return labels, nil
}

func (aly *Anchnet) DiskIsAttached(instanceID, volumeID string) (bool, error) {
	info, err := aly.describeVolume(volumeID)
	if err != nil {
		return false, err
	}
	if info.ItemSet[0].Instance.InstanceID == instanceID {
		return true, nil
	}
	return false, nil
}

// readSysBlock reads /sys/block and returns a list of devices start with `prefix`.
func readSysBlock(prefix string) ([]string, error) {
	dirs, err := ioutil.ReadDir("/sys/block")
	if err != nil {
		return nil, err
	}

	var result []string
	for _, dir := range dirs {
		if strings.HasPrefix(dir.Name(), prefix) {
			result = append(result, dir.Name())
		}
	}

	return result, nil
}
