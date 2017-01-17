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

package aliyun_pd

import (
	"fmt"
	"os"
	"path"
	"strconv"

	"k8s.io/kubernetes/pkg/api"
	"k8s.io/kubernetes/pkg/api/resource"
	"k8s.io/kubernetes/pkg/types"
	"k8s.io/kubernetes/pkg/util/exec"
	"k8s.io/kubernetes/pkg/util/mount"
	utilstrings "k8s.io/kubernetes/pkg/util/strings"
	"k8s.io/kubernetes/pkg/volume"

	"github.com/golang/glog"
)

// This is the primary entrypoint for volume plugins. It is called from kubelet
// to register volume plugin.
func ProbeVolumePlugins() []volume.VolumePlugin {
	return []volume.VolumePlugin{&aliyunPersistentDiskPlugin{nil}}
}

// Main implementation of aliyun volume plugin.
type aliyunPersistentDiskPlugin struct {
	// VolumeHost is an interface that plugins can use to access the kubelet.
	host volume.VolumeHost
}

// Make sure aliyunPersistentDiskPlugin acutally implements volume interfaces.
// Note: auto-provision is used to automatically provision a PersistentVolume to
// bind to an unfulfilled PersistentVolumeClaim: it won't be called if there is
// no unfulfilled PersistentVolumeClaim. The operations are done in
var _ volume.VolumePlugin = &aliyunPersistentDiskPlugin{}
var _ volume.PersistentVolumePlugin = &aliyunPersistentDiskPlugin{}
var _ volume.DeletableVolumePlugin = &aliyunPersistentDiskPlugin{}
var _ volume.ProvisionableVolumePlugin = &aliyunPersistentDiskPlugin{}

const (
	aliyunPersistentDiskPluginName = "kubernetes.io/aliyun-pd"
)

func (plugin *aliyunPersistentDiskPlugin) Init(host volume.VolumeHost) error {
	plugin.host = host
	return nil
}

func (plugin *aliyunPersistentDiskPlugin) GetPluginName() string {
	return aliyunPersistentDiskPluginName
}

func (plugin *aliyunPersistentDiskPlugin) GetVolumeName(spec *volume.Spec) (string, error) {
	volumeSource, _, err := getVolumeSource(spec)
	if err != nil {
		return "", err
	}
	return volumeSource.VolumeID, nil
}

// CanSupport checks if the PersistentDiskPlugin can support given spec. It is
// called from plugin manager.
func (plugin *aliyunPersistentDiskPlugin) CanSupport(spec *volume.Spec) bool {
	return (spec.PersistentVolume != nil && spec.PersistentVolume.Spec.AliyunPersistentDisk != nil) ||
		(spec.Volume != nil && spec.Volume.AliyunPersistentDisk != nil)
}

func (plugin *aliyunPersistentDiskPlugin) RequiresRemount() bool {
	return false
}

// GetAccessModes describes the ways a given volume can be accessed/mounted.
func (plugin *aliyunPersistentDiskPlugin) GetAccessModes() []api.PersistentVolumeAccessMode {
	// Aliyun persistent disk can only be mounted once.
	return []api.PersistentVolumeAccessMode{
		api.ReadWriteOnce,
	}
}

// NewMounter returns a mounter interface used for kubelet to setup/mount volume.
func (plugin *aliyunPersistentDiskPlugin) NewMounter(spec *volume.Spec, pod *api.Pod, _ volume.VolumeOptions) (volume.Mounter, error) {
	// Inject real implementations here, test through the internal function.
	return plugin.newMounterInternal(spec, pod.UID, &AliyunDiskUtil{}, plugin.host.GetMounter())
}

func (plugin *aliyunPersistentDiskPlugin) newMounterInternal(spec *volume.Spec, podUID types.UID, manager pdManager, mounter mount.Interface) (volume.Mounter, error) {
	// PDs used directly in a pod have a ReadOnly flag set by the pod author.
	// PDs used as a PersistentVolume gets the ReadOnly flag indirectly through the persistent-claim volume used to mount the PV.
	var readOnly bool
	var pd *api.AliyunPersistentDiskVolumeSource
	if spec.Volume != nil && spec.Volume.AliyunPersistentDisk != nil {
		pd = spec.Volume.AliyunPersistentDisk
		readOnly = pd.ReadOnly
	} else {
		pd = spec.PersistentVolume.Spec.AliyunPersistentDisk
		readOnly = spec.ReadOnly
	}

	volumeID := pd.VolumeID
	fsType := pd.FSType
	partition := ""
	if pd.Partition != 0 {
		partition = strconv.Itoa(int(pd.Partition))
	}

	return &aliyunPersistentDiskMounter{
		aliyunPersistentDisk: &aliyunPersistentDisk{
			podUID:    podUID,
			volName:   spec.Name(),
			volumeID:  volumeID,
			partition: partition,
			manager:   manager,
			mounter:   mounter,
			plugin:    plugin,
		},
		fsType:      fsType,
		readOnly:    readOnly,
		diskMounter: &mount.SafeFormatAndMount{mounter, exec.New()},
	}, nil
}

// NewUnmounter returns a unmounter to cleanup/unmount the volumes.
func (plugin *aliyunPersistentDiskPlugin) NewUnmounter(volName string, podUID types.UID) (volume.Unmounter, error) {
	// Inject real implementations here, test through the internal function.
	return plugin.newUnmounterInternal(volName, podUID, &AliyunDiskUtil{}, plugin.host.GetMounter())
}

func (plugin *aliyunPersistentDiskPlugin) newUnmounterInternal(volName string, podUID types.UID, manager pdManager, mounter mount.Interface) (volume.Unmounter, error) {
	return &aliyunPersistentDiskUnmounter{&aliyunPersistentDisk{
		podUID:  podUID,
		volName: volName,
		manager: manager,
		mounter: mounter,
		plugin:  plugin,
	}}, nil
}

// NewDeleter returns a deleter to delete the volumes.
func (plugin *aliyunPersistentDiskPlugin) NewDeleter(spec *volume.Spec) (volume.Deleter, error) {
	return plugin.newDeleterInternal(spec, &AliyunDiskUtil{})
}

func (plugin *aliyunPersistentDiskPlugin) newDeleterInternal(spec *volume.Spec, manager pdManager) (volume.Deleter, error) {
	if spec.PersistentVolume != nil && spec.PersistentVolume.Spec.AliyunPersistentDisk == nil {
		return nil, fmt.Errorf("spec.PersistentVolumeSource.AliyunPersistentDisk is nil")
	}
	return &aliyunPersistentDiskDeleter{
		aliyunPersistentDisk: &aliyunPersistentDisk{
			volName:  spec.Name(),
			volumeID: spec.PersistentVolume.Spec.AliyunPersistentDisk.VolumeID,
			manager:  manager,
			plugin:   plugin,
		}}, nil
}

// NewProvisioner returns a provisioner to create the volumes.
func (plugin *aliyunPersistentDiskPlugin) NewProvisioner(options volume.VolumeOptions) (volume.Provisioner, error) {
	return plugin.newProvisionerInternal(options, &AliyunDiskUtil{})
}

func (plugin *aliyunPersistentDiskPlugin) newProvisionerInternal(options volume.VolumeOptions, manager pdManager) (volume.Provisioner, error) {
	return &aliyunPersistentDiskProvisioner{
		aliyunPersistentDisk: &aliyunPersistentDisk{
			manager: manager,
			plugin:  plugin,
		},
		options: options,
	}, nil
}

func (plugin *aliyunPersistentDiskPlugin) ConstructVolumeSpec(volName, mountPath string) (*volume.Spec, error) {
	mounter := plugin.host.GetMounter()
	pluginDir := plugin.host.GetPluginDir(plugin.GetPluginName())
	sourceName, err := mounter.GetDeviceNameFromMount(mountPath, pluginDir)
	if err != nil {
		return nil, err
	}
	aliVolume := &api.Volume{
		Name: volName,
		VolumeSource: api.VolumeSource{
			AliyunPersistentDisk: &api.AliyunPersistentDiskVolumeSource{
				VolumeID: sourceName,
			},
		},
	}
	return volume.NewSpecFromVolume(aliVolume), nil
}

// pdManager abstracts interface to PD operations.
type pdManager interface {
	CreateDisk(provisioner *aliyunPersistentDiskProvisioner) (volumeID string, volumeSizeGB int, labels map[string]string, err error)
	// Deletes a disk in aliyun.
	DeleteDisk(deleter *aliyunPersistentDiskDeleter) error
}

// aliyunPersistentDisk are disk resources provided by aliyun that are attached to
// the kubelet's host machine and exposed to the pod.
type aliyunPersistentDisk struct {
	// Name of the volume in provider.
	volName string
	// Unique id of the PD, used to find the disk resource in the provider.
	volumeID string
	// Mount the disk to Pod with podUID.
	podUID types.UID
	// Specifies the partition to mount
	partition string
	// Utility interface that provides API calls to the provider to attach/detach disks.
	manager pdManager
	// Mounter interface that provides system calls to mount the global path to the pod local path.
	mounter mount.Interface
	// Reference to PD plugin.
	plugin *aliyunPersistentDiskPlugin
	// Placeholder for aliyun since it doesn't yet support metrics.
	volume.MetricsNil
}

// GetPath returns the directory path the volume is mounted to. The path is a host path, e.g.
// /var/lib/kubelet/pods/11053ab6-4ba7/volumes/kubernetes.io~pd/mongodb~volume
func (pd *aliyunPersistentDisk) GetPath() string {
	name := aliyunPersistentDiskPluginName
	return pd.plugin.host.GetPodVolumeDir(pd.podUID, utilstrings.EscapeQualifiedNameForDisk(name), pd.volName)
}

// aliyunPersistentDiskBuilder setup and mounts persistent disk.
type aliyunPersistentDiskMounter struct {
	*aliyunPersistentDisk
	// Filesystem type, optional.
	fsType string
	// Specifies whether the disk will be attached as read-only.
	readOnly bool
	// diskMounter provides the interface that is used to mount the actual block device.
	diskMounter *mount.SafeFormatAndMount
}

var _ volume.Mounter = &aliyunPersistentDiskMounter{}

// Checks prior to mount operations to verify that the required components (binaries, etc.)
// to mount the volume are available on the underlying node.
// If not, it returns an error
func (b *aliyunPersistentDiskMounter) CanMount() error {
	return nil
}

// GetAttributes returns the attributes of the mounter.
func (b *aliyunPersistentDiskMounter) GetAttributes() volume.Attributes {
	return volume.Attributes{
		ReadOnly:        b.readOnly,
		Managed:         !b.readOnly,
		SupportsSELinux: false,
	}
}

// SetUp attaches the disk and bind mounts to default path.
func (b *aliyunPersistentDiskMounter) SetUp(fsGroup *int64) error {
	return b.SetUpAt(b.GetPath(), fsGroup)
}

// SetUpAt attaches the disk and bind mounts to the volume path.
func (b *aliyunPersistentDiskMounter) SetUpAt(dir string, fsGroup *int64) error {
	notMnt, err := b.mounter.IsLikelyNotMountPoint(dir)
	glog.V(4).Infof("PersistentDisk set up: %s %v %v", dir, !notMnt, err)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	if !notMnt {
		return nil
	}

	// Get the place where we globally mount the disk. The disk will be mounted at
	// `globalPDPath` first, then will be bind-mounted to `dir`.
	globalPDPath := makeGlobalPDPath(b.plugin.host, b.volumeID)
	glog.V(2).Infof("Mount PersistentDisk at %v", globalPDPath)

	// Create `dir` to prepare for bind mount.
	if err := os.MkdirAll(dir, 0750); err != nil {
		return err
	}

	// Perform a bind mount to the full path to allow duplicate mounts of the same PD.
	options := []string{"bind"}
	if b.readOnly {
		options = append(options, "ro")
	}
	err = b.mounter.Mount(globalPDPath, dir, "", options)
	if err != nil {
		notMnt, mntErr := b.mounter.IsLikelyNotMountPoint(dir)
		if mntErr != nil {
			glog.Errorf("IsLikelyNotMountPoint check failed: %v", mntErr)
			return err
		}
		if !notMnt {
			if mntErr = b.mounter.Unmount(dir); mntErr != nil {
				glog.Errorf("Failed to unmount: %v", mntErr)
				return err
			}
			notMnt, mntErr := b.mounter.IsLikelyNotMountPoint(dir)
			if mntErr != nil {
				glog.Errorf("IsLikelyNotMountPoint check failed: %v", mntErr)
				return err
			}
			if !notMnt {
				// This is very odd, we don't expect it.  We'll try again next sync loop.
				glog.Errorf("%s is still mounted, despite call to unmount().  Will try again next sync loop.", dir)
				return err
			}
		}
		os.Remove(dir)
		return err
	}

	return nil
}

var _ volume.Unmounter = &aliyunPersistentDiskUnmounter{}

// aliyunPersistentDiskUnmounter setup and mounts persistent disk.
type aliyunPersistentDiskUnmounter struct {
	*aliyunPersistentDisk
}

// Unmounts the bind mount, and detaches the disk only if the PD
// resource was the last reference to that disk on the kubelet.
func (c *aliyunPersistentDiskUnmounter) TearDown() error {
	return c.TearDownAt(c.GetPath())
}

// Unmounts the bind mount, and detaches the disk only if the PD
// resource was the last reference to that disk on the kubelet.
func (c *aliyunPersistentDiskUnmounter) TearDownAt(dir string) error {
	notMnt, err := c.mounter.IsLikelyNotMountPoint(dir)
	if err != nil {
		glog.V(2).Info("Error checking if mountpoint ", dir, ": ", err)
		return err
	}
	if notMnt {
		glog.V(2).Info("Not mountpoint, deleting")
		return os.Remove(dir)
	}

	refs, err := mount.GetMountRefs(c.mounter, dir)
	if err != nil {
		glog.V(2).Info("Error getting mountrefs for ", dir, ": ", err)
		return err
	}
	if len(refs) == 0 {
		glog.Warning("Did not find pod-mount for ", dir, " during tear-down")
	}
	// Unmount the bind-mount inside this pod.
	if err := c.mounter.Unmount(dir); err != nil {
		glog.V(2).Info("Error unmounting dir ", dir, ": ", err)
		return err
	}

	notMnt, mntErr := c.mounter.IsLikelyNotMountPoint(dir)
	if mntErr != nil {
		glog.Errorf("IsLikelyNotMountPoint check failed: %v", mntErr)
		return err
	}
	if notMnt {
		if err := os.Remove(dir); err != nil {
			glog.V(2).Info("Error removing mountpoint ", dir, ": ", err)
			return err
		}
	}
	return nil
}

var _ volume.Deleter = &aliyunPersistentDiskDeleter{}

type aliyunPersistentDiskDeleter struct {
	*aliyunPersistentDisk
}

func (d *aliyunPersistentDiskDeleter) GetPath() string {
	name := aliyunPersistentDiskPluginName
	return d.plugin.host.GetPodVolumeDir(d.podUID, utilstrings.EscapeQualifiedNameForDisk(name), d.volName)
}

func (d *aliyunPersistentDiskDeleter) Delete() error {
	return d.manager.DeleteDisk(d)
}

var _ volume.Provisioner = &aliyunPersistentDiskProvisioner{}

type aliyunPersistentDiskProvisioner struct {
	*aliyunPersistentDisk
	options volume.VolumeOptions
}

func (c *aliyunPersistentDiskProvisioner) Provision() (*api.PersistentVolume, error) {
	volumeID, sizeGB, labels, err := c.manager.CreateDisk(c)
	if err != nil {
		return nil, err
	}

	pv := &api.PersistentVolume{
		ObjectMeta: api.ObjectMeta{
			Name:   c.options.PVName,
			Labels: map[string]string{},
			Annotations: map[string]string{
				"kubernetes.io/createdby": "aliyun-disk-dynamic-provisioner",
			},
		},
		Spec: api.PersistentVolumeSpec{
			PersistentVolumeReclaimPolicy: c.options.PersistentVolumeReclaimPolicy,
			AccessModes:                   c.options.PVC.Spec.AccessModes,
			Capacity: api.ResourceList{
				api.ResourceName(api.ResourceStorage): resource.MustParse(fmt.Sprintf("%dGi", sizeGB)),
			},
			PersistentVolumeSource: api.PersistentVolumeSource{
				AliyunPersistentDisk: &api.AliyunPersistentDiskVolumeSource{
					VolumeID:  volumeID,
					FSType:    "ext4",
					Partition: 0,
					ReadOnly:  false,
				},
			},
		},
	}

	if len(labels) != 0 {
		if pv.Labels == nil {
			pv.Labels = make(map[string]string)
		}
		for k, v := range labels {
			pv.Labels[k] = v
		}
	}

	return pv, nil
}

// makeGlobalPDPath creates a directory path which is used to mount the persistent disk.
// Note this is different from dir returned from GetPath(), we will later bind mount that
// directory.
func makeGlobalPDPath(host volume.VolumeHost, volumeID string) string {
	return path.Join(host.GetPluginDir(aliyunPersistentDiskPluginName), "mounts", volumeID)
}

// getVolumeSource gets volume source from volume spec.
func getVolumeSource(spec *volume.Spec) (*api.AliyunPersistentDiskVolumeSource, bool, error) {
	if spec.Volume != nil && spec.Volume.AliyunPersistentDisk != nil {
		return spec.Volume.AliyunPersistentDisk, spec.Volume.AliyunPersistentDisk.ReadOnly, nil
	} else if spec.PersistentVolume != nil && spec.PersistentVolume.Spec.AliyunPersistentDisk != nil {
		return spec.PersistentVolume.Spec.AliyunPersistentDisk, spec.ReadOnly, nil
	}
	return nil, false, fmt.Errorf("Spec does not reference aliyun volume type")
}
