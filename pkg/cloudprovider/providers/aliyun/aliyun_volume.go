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

package aliyun

import (
	"fmt"
	"io/ioutil"
	"strings"
	"time"

	"github.com/denverdino/aliyungo/common"
	"github.com/denverdino/aliyungo/ecs"
	"github.com/golang/glog"
	"k8s.io/kubernetes/pkg/api/unversioned"
	"k8s.io/kubernetes/pkg/util/sets"
	"k8s.io/kubernetes/pkg/volume"
)

const DefaultMaxAliyunPDVolumes = 5

const (
	// Number of retries when unable to fetch device name from aliyun.
	RetryCountOnDeviceEmpty = 5
	// Constant interval between two retries for the above situation.
	RetryIntervalOnDeviceEmpty = 6 * time.Second
)

const (
	// Number of retries when getting errors while accessing aliyun, e.g.
	// request too frequent.
	RetryCountOnError = 5
	// Initial interval between two retries for the above situation. Following
	// retry interval will be doubled.
	RetryIntervalOnError = 2 * time.Second
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

	// Create a disk with the specified options.
	CreateDisk(volumeOptions *VolumeOptions) (volumeID string, err error)
	// Delete a disk.
	DeleteDisk(volumeID string) error

	// Check if the volume is already attached to the instance
	DiskIsAttached(instanceID, diskName string) (bool, error)
}

type VolumeOptions struct {
	CapacityGB int
	Name       string
}

var _ Volumes = (*Aliyun)(nil)

// AttachDisk attaches the disk to the specified instance. `instanceID` can be empty
// to mean "the instance on which we are running".
// Returns the device path (e.g. /dev/xvdf) where we attached the volume.
func (aly *Aliyun) AttachDisk(instanceID string, volumeID string, readOnly bool) (string, error) {
	glog.Infof("AttachDisk(%v, %v, %v)", instanceID, volumeID, readOnly)
	/*
		// Do not support attaching volume for other instances.
		if instanceID != "" {
			return "", errors.New("unable to attach disk for instance other than self instance")
		}

		// Get hostname and convert it to instance ID. During cluster provisioning, we set hostname to
		// lowercased instance ID. Ideally, we can issue a request to cloudprovider to get instance
		// information of the host itself, but aliyun lacks the API.
		hostname, err := os.Hostname()
		if err != nil {
			return "", err
		}
		instanceID = nameToInstanceId(hostname)

		// Before attaching volume, check /sys/block for known disks. This is used in case aliyun
		// doesn't return device name from describe volume API.
		existing, err := readSysBlock("xvd")
		if err != nil {
			return "", err
		}
	*/

	// Do the volume attach.
	if err := aly.attachVolume(instanceID, volumeID); err != nil {
		return "", err
	}

	devicePath := ""
	for i := 0; i < RetryCountOnDeviceEmpty; i++ {
		diskInfo, err := aly.describeVolume(volumeID)
		if err != nil || diskInfo.Device == "" {
			glog.Infof("Volume %s device path is empty, retrying", volumeID)
			time.Sleep(RetryIntervalOnDeviceEmpty)
		} else {
			return diskInfo.Device, nil
		}
	}
	/*
		if devicePath == "" {
			glog.Infof("Unable to fetch device name from describeVolume endpoint, fallback to search /sys/block")
			glog.Infof("AttachDisk found existing disks %+v", existing)
			// After attaching volume, check /sys/block again.
			current, err := readSysBlock("xvd")
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
func (aly *Aliyun) DetachDisk(instanceID string, volumeID string) error {
	glog.Infof("DetachDisk(%v, %v)", instanceID, volumeID)
	return aly.detachVolume(instanceID, volumeID)
}

// Create a volume with the specified options.
func (aly *Aliyun) CreateDisk(options *VolumeOptions) (string, error) {
	glog.Infof("CreateDisk(%v, %v)", options.Name, options.CapacityGB)

	if options.CapacityGB < 5 || options.CapacityGB > 2000 {
		return "", fmt.Errorf("Invalid capacity, must in [5, 2000]")
	}

	zones, err := aly.getAllZones()
	if err != nil {
		return "", fmt.Errorf("error querying for all zones: %v", err)
	}
	zone := volume.ChooseZoneForVolume(zones, options.Name)

	for i := 0; i < RetryCountOnError; i++ {
		diskID, err := aly.ecsClient.CreateDisk(&ecs.CreateDiskArgs{
			RegionId:     common.Region(aly.regionID),
			ZoneId:       zone,
			DiskName:     options.Name,
			DiskCategory: ecs.DiskCategoryCloud, //TODO(mqliang): expose this in API
			Size:         options.CapacityGB,
		})
		if err == nil {
			glog.Infof("Create volume name: %v", options.Name)
			return diskID, nil
		} else {
			glog.Infof("Attempt %d: failed to create volume: %v\n", i, err)
		}
		time.Sleep(time.Duration(i+1) * RetryIntervalOnError)
	}
	return "", fmt.Errorf("Unable to create volume %v", options.Name)
}

// Delete a volume.
func (aly *Aliyun) DeleteDisk(volumeID string) error {
	glog.Infof("DeleteDisk: %v", volumeID)

	volume, err := aly.describeVolume(volumeID)
	if err != nil {
		return err
	}
	if volume.Status != ecs.DiskStatusAvailable {
		return fmt.Errorf("Could not delete volume %v since its status is %v", volumeID, volume.Status)
	}

	for i := 0; i < RetryCountOnError; i++ {
		err := aly.ecsClient.DeleteDisk(volumeID)
		if err == nil {
			glog.Infof("Delete volume ID: %v", volumeID)
			return nil
		} else {
			glog.Infof("Attempt %d: failed to delete volume: %v\n", i, err)
		}
		time.Sleep(time.Duration(i+1) * RetryIntervalOnError)
	}
	return fmt.Errorf("Unable to delete volume %v", volumeID)
}

// attachVolumes attaches a volume to given instance.
func (aly *Aliyun) attachVolume(instanceID string, volumeID string) error {
	if couldAttach, reason := aly.couldOperateDisk(instanceID, volumeID); !couldAttach {
		return fmt.Errorf("Unable to attach volume %v from %v since %v", volumeID, instanceID, reason)
	}

	for i := 0; i < RetryCountOnError; i++ {
		if err := aly.ecsClient.AttachDisk(&ecs.AttachDiskArgs{
			InstanceId: instanceID,
			DiskId:     volumeID,
		}); err == nil {
			glog.Infof("Attached volume %v to instance %v", volumeID, instanceID)
			return nil
		} else {
			glog.Infof("Attempt %d: failed to attach volume: %v\n", i, err)
		}

		time.Sleep(time.Duration(i+1) * RetryIntervalOnError)
	}
	return fmt.Errorf("Unable to attach volume %v to instance %v", volumeID, instanceID)
}

// detachVolumes detaches a volume.
func (aly *Aliyun) detachVolume(instanceID, volumeID string) error {
	if couldDetach, reason := aly.couldOperateDisk(instanceID, volumeID); !couldDetach {
		return fmt.Errorf("Unable to detach volume %v from %v since %v", volumeID, instanceID, reason)
	}

	for i := 0; i < RetryCountOnError; i++ {
		if err := aly.ecsClient.DetachDisk(instanceID, volumeID); err == nil {
			glog.Infof("Detached volume %v from %v", volumeID, instanceID)
			return nil
		} else {
			glog.Infof("Attempt %d: failed to detach volume: %v\n", i, err)
		}

		time.Sleep(time.Duration(i+1) * RetryIntervalOnError)
	}
	return fmt.Errorf("Unable to detach volume %v from %v", volumeID, instanceID)
}

func (aly *Aliyun) couldOperateDisk(instanceID, diskID string) (bool, string) {
	volume, err := aly.describeVolume(diskID)
	if err != nil {
		return false, err.Error()
	}
	if !volume.Portable {
		return false, fmt.Sprintf("volume %s is not portable", diskID)
	}

	instance, err := aly.describeInstance(instanceID)
	if err != nil {
		return false, err.Error()
	}
	if instance.Status != ecs.Running && instance.Status != ecs.Stopped {
		return false, fmt.Sprintf("instance %v's status is %v", instanceID, instance.Status)
	}
	for _, lock := range instance.OperationLocks.LockReason {
		if lock.LockReason == ecs.LockReasonSecurity {
			return false, fmt.Sprintf("volume %v is locked", diskID)
		}
	}
	return true, ""
}

// describeVolume describe a volume.
func (aly *Aliyun) describeVolume(volumeID string) (*ecs.DiskItemType, error) {
	for i := 0; i < RetryCountOnError; i++ {
		disks, _, err := aly.ecsClient.DescribeDisks(&ecs.DescribeDisksArgs{
			RegionId: common.Region(aly.regionID),
			DiskIds:  []string{volumeID},
		})
		if err == nil && len(disks) != 0 {
			glog.Infof("Found volume %v", volumeID)
			return &disks[0], nil
		} else {
			glog.Infof("Attempt %d: failed to describe volume: %v\n", i, err)
		}
		time.Sleep(time.Duration(i+1) * RetryIntervalOnError)
	}
	return nil, fmt.Errorf("Unable to describe volume %v", volumeID)
}

// describeInstance describe a instance.
func (aly *Aliyun) describeInstance(instanceID string) (*ecs.InstanceAttributesType, error) {
	for i := 0; i < RetryCountOnError; i++ {
		instance, err := aly.ecsClient.DescribeInstanceAttribute(instanceID)
		if err == nil {
			return instance, nil
		} else {
			glog.Infof("Attempt %d: failed to describe volume: %v\n", i, err)
		}
		time.Sleep(time.Duration(i+1) * RetryIntervalOnError)
	}
	return nil, fmt.Errorf("Unable to describe instance %v", instanceID)
}

func (aly *Aliyun) describeInstanceList() (instances []ecs.InstanceAttributesType, err error) {
	for i := 0; i < RetryCountOnError; i++ {
		if instances, _, err = aly.ecsClient.DescribeInstances(&ecs.DescribeInstancesArgs{
			RegionId: common.Region(aly.regionID),
		}); err == nil {
			return instances, nil
		} else {
			glog.Infof("Attempt %d: failed to describe volume: %v\n", i, err)
		}
		time.Sleep(time.Duration(i+1) * RetryIntervalOnError)
	}
	return instances, fmt.Errorf("Unable to fetch instance list due to: %v", err)
}

// Builds the labels that should be automatically added to a PersistentVolume backed by a Aliyun PD
// Specifically, this builds FailureDomain (zone) and Region labels.
// The PersistentVolumeLabel admission controller calls this and adds the labels when a PV is created.
func (aly *Aliyun) GetAutoLabelsForPD(volumeID string) (map[string]string, error) {
	info, err := aly.describeVolume(volumeID)
	if err != nil {
		return nil, err
	}
	if info.ZoneId == "" {
		return nil, fmt.Errorf("volume %v did not have AZ information", info.DiskChargeType)
	}

	labels := make(map[string]string)
	labels[unversioned.LabelZoneRegion] = string(info.RegionId)
	labels[unversioned.LabelZoneFailureDomain] = info.ZoneId

	return labels, nil
}

func (aly *Aliyun) DiskIsAttached(instanceID, volumeID string) (bool, error) {
	info, err := aly.describeVolume(volumeID)
	if err != nil {
		return false, err
	}
	if info.InstanceId == instanceID {
		return true, nil
	}
	return false, nil
}

// getAllZones retrieves  a list of all the zones in which nodes are running
// It currently involves querying all instances
func (aly *Aliyun) getAllZones() (sets.String, error) {
	// We don't currently cache this; it is currently used only in volume
	// creation which is expected to be a comparatively rare occurence.

	// TODO: Caching / expose api.Nodes to the cloud provider?
	// TODO: We could also query for subnets, I think
	instances, err := aly.describeInstanceList()
	if err != nil {
		return nil, err
	}
	if len(instances) == 0 {
		return nil, fmt.Errorf("no instances returned")
	}

	zones := sets.NewString()

	for _, instance := range instances {
		if instance.ZoneId != "" {
			zones.Insert(instance.ZoneId)
		}
	}

	glog.V(2).Infof("Found instances in zones %s", zones)
	return zones, nil
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
