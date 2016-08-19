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

package anchnet_pd

import (
	"fmt"
	"os"
	"path"
	"strconv"

	"github.com/golang/glog"
	"k8s.io/kubernetes/pkg/api"
	"k8s.io/kubernetes/pkg/api/resource"
	anchnet_cloud "k8s.io/kubernetes/pkg/cloudprovider/providers/anchnet"
	"k8s.io/kubernetes/pkg/types"
	"k8s.io/kubernetes/pkg/util/exec"
	"k8s.io/kubernetes/pkg/util/mount"
	utilstrings "k8s.io/kubernetes/pkg/util/strings"
	"k8s.io/kubernetes/pkg/volume"
)

// This is the primary entrypoint for volume plugins. It is called from kubelet
// to register volume plugin.
func ProbeVolumePlugins() []volume.VolumePlugin {
	return []volume.VolumePlugin{&anchnetPersistentDiskPlugin{nil}}
}

// Main implementation of anchnet volume plugin.
type anchnetPersistentDiskPlugin struct {
	// VolumeHost is an interface that plugins can use to access the kubelet.
	host volume.VolumeHost
}

// Make sure anchnetPersistentDiskPlugin acutally implements volume interfaces.
// Note: auto-provision is used to automatically provision a PersistentVolume to
// bind to an unfulfilled PersistentVolumeClaim: it won't be called if there is
// no unfulfilled PersistentVolumeClaim. The operations are done in
var _ volume.VolumePlugin = &anchnetPersistentDiskPlugin{}
var _ volume.PersistentVolumePlugin = &anchnetPersistentDiskPlugin{}
var _ volume.DeletableVolumePlugin = &anchnetPersistentDiskPlugin{}
var _ volume.ProvisionableVolumePlugin = &anchnetPersistentDiskPlugin{}

const (
	anchnetPersistentDiskPluginName = "kubernetes.io/anchnet-pd"
)

func (plugin *anchnetPersistentDiskPlugin) Init(host volume.VolumeHost) error {
	plugin.host = host
	return nil
}

func (plugin *anchnetPersistentDiskPlugin) GetPluginName() string {
	return anchnetPersistentDiskPluginName
}

func (plugin *anchnetPersistentDiskPlugin) GetVolumeName(spec *volume.Spec) (string, error) {
	volumeSource, _, err := getVolumeSource(spec)
	if err != nil {
		return "", err
	}
	return volumeSource.VolumeID, nil
}

// CanSupport checks if the PersistentDiskPlugin can support given spec. It is
// called from plugin manager.
func (plugin *anchnetPersistentDiskPlugin) CanSupport(spec *volume.Spec) bool {
	return (spec.PersistentVolume != nil && spec.PersistentVolume.Spec.AnchnetPersistentDisk != nil) ||
		(spec.Volume != nil && spec.Volume.AnchnetPersistentDisk != nil)
}

func (plugin *anchnetPersistentDiskPlugin) RequiresRemount() bool {
	return false
}

// GetAccessModes describes the ways a given volume can be accessed/mounted.
func (plugin *anchnetPersistentDiskPlugin) GetAccessModes() []api.PersistentVolumeAccessMode {
	// Anchnet persistent disk can only be mounted once.
	return []api.PersistentVolumeAccessMode{
		api.ReadWriteOnce,
	}
}

// NewMounter returns a mounter interface used for kubelet to setup/mount volume.
func (plugin *anchnetPersistentDiskPlugin) NewMounter(spec *volume.Spec, pod *api.Pod, _ volume.VolumeOptions) (volume.Mounter, error) {
	// Inject real implementations here, test through the internal function.
	return plugin.newMounterInternal(spec, pod.UID, &AnchnetDiskUtil{}, plugin.host.GetMounter())
}

func (plugin *anchnetPersistentDiskPlugin) newMounterInternal(spec *volume.Spec, podUID types.UID, manager pdManager, mounter mount.Interface) (volume.Mounter, error) {
	// PDs used directly in a pod have a ReadOnly flag set by the pod author.
	// PDs used as a PersistentVolume gets the ReadOnly flag indirectly through the persistent-claim volume used to mount the PV.
	var readOnly bool
	var pd *api.AnchnetPersistentDiskVolumeSource
	if spec.Volume != nil && spec.Volume.AnchnetPersistentDisk != nil {
		pd = spec.Volume.AnchnetPersistentDisk
		readOnly = pd.ReadOnly
	} else {
		pd = spec.PersistentVolume.Spec.AnchnetPersistentDisk
		readOnly = spec.ReadOnly
	}

	volumeID := pd.VolumeID
	fsType := pd.FSType
	partition := ""
	if pd.Partition != 0 {
		partition = strconv.Itoa(pd.Partition)
	}

	return &anchnetPersistentDiskMounter{
		anchnetPersistentDisk: &anchnetPersistentDisk{
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
func (plugin *anchnetPersistentDiskPlugin) NewUnmounter(volName string, podUID types.UID) (volume.Unmounter, error) {
	// Inject real implementations here, test through the internal function.
	return plugin.newUnmounterInternal(volName, podUID, &AnchnetDiskUtil{}, plugin.host.GetMounter())
}

func (plugin *anchnetPersistentDiskPlugin) newUnmounterInternal(volName string, podUID types.UID, manager pdManager, mounter mount.Interface) (volume.Unmounter, error) {
	return &anchnetPersistentDiskUnmounter{&anchnetPersistentDisk{
		podUID:  podUID,
		volName: volName,
		manager: manager,
		mounter: mounter,
		plugin:  plugin,
	}}, nil
}

// NewDeleter returns a deleter to delete the volumes.
func (plugin *anchnetPersistentDiskPlugin) NewDeleter(spec *volume.Spec) (volume.Deleter, error) {
	return plugin.newDeleterInternal(spec, &AnchnetDiskUtil{})
}

func (plugin *anchnetPersistentDiskPlugin) newDeleterInternal(spec *volume.Spec, manager pdManager) (volume.Deleter, error) {
	if spec.PersistentVolume != nil && spec.PersistentVolume.Spec.AnchnetPersistentDisk == nil {
		return nil, fmt.Errorf("spec.PersistentVolumeSource.AnchnetPersistentDisk is nil")
	}
	return &anchnetPersistentDiskDeleter{
		anchnetPersistentDisk: &anchnetPersistentDisk{
			volName:  spec.Name(),
			volumeID: spec.PersistentVolume.Spec.AnchnetPersistentDisk.VolumeID,
			manager:  manager,
			plugin:   plugin,
		}}, nil
}

// NewProvisioner returns a provisioner to create the volumes.
func (plugin *anchnetPersistentDiskPlugin) NewProvisioner(options volume.VolumeOptions) (volume.Provisioner, error) {
	if len(options.AccessModes) == 0 {
		options.AccessModes = plugin.GetAccessModes()
	}
	return plugin.newProvisionerInternal(options, &AnchnetDiskUtil{})
}

func (plugin *anchnetPersistentDiskPlugin) newProvisionerInternal(options volume.VolumeOptions, manager pdManager) (volume.Provisioner, error) {
	return &anchnetPersistentDiskProvisioner{
		anchnetPersistentDisk: &anchnetPersistentDisk{
			manager: manager,
			plugin:  plugin,
		},
		options: options,
	}, nil
}

// pdManager abstracts interface to PD operations.
type pdManager interface {
	// AttachAndMountDisk attaches a disk specified by a volume.anchnetPersistentDisk
	// to current kubelet. The mount path is 'globalPDPath'.
	AttachAndMountDisk(b *anchnetPersistentDiskMounter, globalPDPath string) error
	// DetachDisk detaches/unmount the disk from the kubelet's host machine.
	DetachDisk(c *anchnetPersistentDiskUnmounter) error
	// Creates a disk in anchnet.
	CreateDisk(provisioner *anchnetPersistentDiskProvisioner) (volumeID string, volumeSizeGB int, labels map[string]string, err error)
	// Deletes a disk in anchnet.
	DeleteDisk(deleter *anchnetPersistentDiskDeleter) error
}

// anchnetPersistentDisk are disk resources provided by anchnet that are attached to
// the kubelet's host machine and exposed to the pod.
type anchnetPersistentDisk struct {
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
	plugin *anchnetPersistentDiskPlugin
	// Placeholder for anchnet since it doesn't yet support metrics.
	volume.MetricsNil
}

func detachDiskLogError(pd *anchnetPersistentDisk) {
	err := pd.manager.DetachDisk(&anchnetPersistentDiskUnmounter{pd})
	if err != nil {
		glog.Warningf("Failed to detach disk: %v (%v)", pd, err)
	}
}

// GetPath returns the directory path the volume is mounted to. The path is a host path, e.g.
// /var/lib/kubelet/pods/11053ab6-4ba7/volumes/kubernetes.io~pd/mongodb~volume
func (pd *anchnetPersistentDisk) GetPath() string {
	name := anchnetPersistentDiskPluginName
	return pd.plugin.host.GetPodVolumeDir(pd.podUID, utilstrings.EscapeQualifiedNameForDisk(name), pd.volName)
}

// getVolumeProvider returns anchnet volumes interface.
func (pd *anchnetPersistentDisk) getVolumeProvider() (anchnet_cloud.Volumes, error) {
	cloud := pd.plugin.host.GetCloudProvider()
	volumes, ok := cloud.(anchnet_cloud.Volumes)
	if !ok {
		return nil, fmt.Errorf("cloudprovider anchnet doesn't support volumes interface")
	}
	return volumes, nil
}

// anchnetPersistentDiskMounter setup and mounts persistent disk.
type anchnetPersistentDiskMounter struct {
	*anchnetPersistentDisk
	// Filesystem type, optional.
	fsType string
	// Specifies whether the disk will be attached as read-only.
	readOnly bool
	// diskMounter provides the interface that is used to mount the actual block device.
	diskMounter *mount.SafeFormatAndMount
}

var _ volume.Mounter = &anchnetPersistentDiskMounter{}

// GetAttributes returns the attributes of the mounter.
func (b *anchnetPersistentDiskMounter) GetAttributes() volume.Attributes {
	return volume.Attributes{
		ReadOnly:        b.readOnly,
		Managed:         !b.readOnly,
		SupportsSELinux: false,
	}
}

// SetUp attaches the disk and bind mounts to default path.
func (b *anchnetPersistentDiskMounter) SetUp(fsGroup *int64) error {
	return b.SetUpAt(b.GetPath(), fsGroup)
}

// SetUpAt attaches the disk and bind mounts to the volume path.
func (b *anchnetPersistentDiskMounter) SetUpAt(dir string, fsGroup *int64) error {
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

	// Call pdManager, which in turn calls cloudprovider to setup up disk. The disk
	// must exist, i.e. b.VolumeID is a valid identifier (vol-xxxxxx).
	if err := b.manager.AttachAndMountDisk(b, globalPDPath); err != nil {
		return err
	}

	// Create `dir` to prepare for bind mount.
	if err := os.MkdirAll(dir, 0750); err != nil {
		// TODO: we should really eject the attach/detach out into its own control loop.
		detachDiskLogError(b.anchnetPersistentDisk)
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
		// TODO: we should really eject the attach/detach out into its own control loop.
		detachDiskLogError(b.anchnetPersistentDisk)
		return err
	}

	return nil
}

var _ volume.Unmounter = &anchnetPersistentDiskUnmounter{}

// anchnetPersistentDiskUnmounter setup and mounts persistent disk.
type anchnetPersistentDiskUnmounter struct {
	*anchnetPersistentDisk
}

// Unmounts the bind mount, and detaches the disk only if the PD
// resource was the last reference to that disk on the kubelet.
func (c *anchnetPersistentDiskUnmounter) TearDown() error {
	return c.TearDownAt(c.GetPath())
}

// Unmounts the bind mount, and detaches the disk only if the PD
// resource was the last reference to that disk on the kubelet.
func (c *anchnetPersistentDiskUnmounter) TearDownAt(dir string) error {
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
	// If len(refs) is 1, then all bind mounts have been removed, and the
	// remaining reference is the global mount. It is safe to detach.
	if len(refs) == 1 {
		// c.volumeID is not initially set for volume-unmounters, so set it here.
		c.volumeID = path.Base(refs[0])
		if err := c.manager.DetachDisk(c); err != nil {
			glog.V(2).Info("Failed to detach disk ", c.volumeID)
			return err
		}
	} else {
		glog.V(2).Info("Found multiple refs; won't detach anchnet volume: %v", refs)
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

var _ volume.Deleter = &anchnetPersistentDiskDeleter{}

type anchnetPersistentDiskDeleter struct {
	*anchnetPersistentDisk
}

func (d *anchnetPersistentDiskDeleter) GetPath() string {
	name := anchnetPersistentDiskPluginName
	return d.plugin.host.GetPodVolumeDir(d.podUID, utilstrings.EscapeQualifiedNameForDisk(name), d.volName)
}

func (d *anchnetPersistentDiskDeleter) Delete() error {
	return d.manager.DeleteDisk(d)
}

var _ volume.Provisioner = &anchnetPersistentDiskProvisioner{}

type anchnetPersistentDiskProvisioner struct {
	*anchnetPersistentDisk
	options volume.VolumeOptions
}

func (c *anchnetPersistentDiskProvisioner) Provision() (*api.PersistentVolume, error) {
	volumeID, sizeGB, labels, err := c.manager.CreateDisk(c)
	if err != nil {
		return nil, err
	}

	pv := &api.PersistentVolume{
		ObjectMeta: api.ObjectMeta{
			Name:   c.options.PVName,
			Labels: map[string]string{},
			Annotations: map[string]string{
				"kubernetes.io/createdby": "anchent-disk-dynamic-provisioner",
			},
		},
		Spec: api.PersistentVolumeSpec{
			PersistentVolumeReclaimPolicy: c.options.PersistentVolumeReclaimPolicy,
			AccessModes:                   c.options.AccessModes,
			Capacity: api.ResourceList{
				api.ResourceName(api.ResourceStorage): resource.MustParse(fmt.Sprintf("%dGi", sizeGB)),
			},
			PersistentVolumeSource: api.PersistentVolumeSource{
				AWSElasticBlockStore: &api.AWSElasticBlockStoreVolumeSource{
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
	return path.Join(host.GetPluginDir(anchnetPersistentDiskPluginName), "mounts", volumeID)
}

// getVolumeSource gets volume source from volume spec.
func getVolumeSource(spec *volume.Spec) (*api.AnchnetPersistentDiskVolumeSource, bool, error) {
	if spec.Volume != nil && spec.Volume.AnchnetPersistentDisk != nil {
		return spec.Volume.AnchnetPersistentDisk, spec.Volume.AWSElasticBlockStore.ReadOnly, nil
	} else if spec.PersistentVolume != nil && spec.PersistentVolume.Spec.AnchnetPersistentDisk != nil {
		return spec.PersistentVolume.Spec.AnchnetPersistentDisk, spec.ReadOnly, nil
	}
	return nil, false, fmt.Errorf("Spec does not reference anchnet volume type")
}
