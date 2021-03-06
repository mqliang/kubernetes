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

package predicates

import (
	"fmt"
	"reflect"
	"testing"

	"k8s.io/kubernetes/pkg/api"
	"k8s.io/kubernetes/pkg/api/resource"
	"k8s.io/kubernetes/plugin/pkg/scheduler/algorithm"
	"k8s.io/kubernetes/plugin/pkg/scheduler/schedulercache"
)

type FakeNodeInfo api.Node

func (n FakeNodeInfo) GetNodeInfo(nodeName string) (*api.Node, error) {
	node := api.Node(n)
	return &node, nil
}

type FakeNodeListInfo []api.Node

func (nodes FakeNodeListInfo) GetNodeInfo(nodeName string) (*api.Node, error) {
	for _, node := range nodes {
		if node.Name == nodeName {
			return &node, nil
		}
	}
	return nil, fmt.Errorf("Unable to find node: %s", nodeName)
}

type FakePersistentVolumeClaimInfo []api.PersistentVolumeClaim

func (pvcs FakePersistentVolumeClaimInfo) GetPersistentVolumeClaimInfo(namespace string, pvcID string) (*api.PersistentVolumeClaim, error) {
	for _, pvc := range pvcs {
		if pvc.Name == pvcID && pvc.Namespace == namespace {
			return &pvc, nil
		}
	}
	return nil, fmt.Errorf("Unable to find persistent volume claim: %s/%s", namespace, pvcID)
}

type FakePersistentVolumeInfo []api.PersistentVolume

func (pvs FakePersistentVolumeInfo) GetPersistentVolumeInfo(pvID string) (*api.PersistentVolume, error) {
	for _, pv := range pvs {
		if pv.Name == pvID {
			return &pv, nil
		}
	}
	return nil, fmt.Errorf("Unable to find persistent volume: %s", pvID)
}

func makeResources(milliCPU int64, memory int64, pods int64) api.NodeResources {
	return api.NodeResources{
		Capacity: api.ResourceList{
			api.ResourceCPU:    *resource.NewMilliQuantity(milliCPU, resource.DecimalSI),
			api.ResourceMemory: *resource.NewQuantity(memory, resource.BinarySI),
			api.ResourcePods:   *resource.NewQuantity(pods, resource.DecimalSI),
		},
	}
}

func makeAllocatableResources(milliCPU int64, memory int64, pods int64) api.ResourceList {
	return api.ResourceList{
		api.ResourceCPU:    *resource.NewMilliQuantity(milliCPU, resource.DecimalSI),
		api.ResourceMemory: *resource.NewQuantity(memory, resource.BinarySI),
		api.ResourcePods:   *resource.NewQuantity(pods, resource.DecimalSI),
	}
}

func newResourcePod(usage ...resourceRequest) *api.Pod {
	containers := []api.Container{}
	for _, req := range usage {
		containers = append(containers, api.Container{
			Resources: api.ResourceRequirements{
				Requests: api.ResourceList{
					api.ResourceCPU:    *resource.NewMilliQuantity(req.milliCPU, resource.DecimalSI),
					api.ResourceMemory: *resource.NewQuantity(req.memory, resource.BinarySI),
				},
			},
		})
	}
	return &api.Pod{
		Spec: api.PodSpec{
			Containers: containers,
		},
	}
}

func TestPodFitsResources(t *testing.T) {
	enoughPodsTests := []struct {
		pod      *api.Pod
		nodeInfo *schedulercache.NodeInfo
		fits     bool
		test     string
		wErr     error
	}{
		{
			pod: &api.Pod{},
			nodeInfo: schedulercache.NewNodeInfo(
				newResourcePod(resourceRequest{milliCPU: 10, memory: 20})),
			fits: true,
			test: "no resources requested always fits",
			wErr: nil,
		},
		{
			pod: newResourcePod(resourceRequest{milliCPU: 1, memory: 1}),
			nodeInfo: schedulercache.NewNodeInfo(
				newResourcePod(resourceRequest{milliCPU: 10, memory: 20})),
			fits: false,
			test: "too many resources fails",
			wErr: newInsufficientResourceError(cpuResourceName, 1, 10, 10),
		},
		{
			pod: newResourcePod(resourceRequest{milliCPU: 1, memory: 1}),
			nodeInfo: schedulercache.NewNodeInfo(
				newResourcePod(resourceRequest{milliCPU: 5, memory: 5})),
			fits: true,
			test: "both resources fit",
			wErr: nil,
		},
		{
			pod: newResourcePod(resourceRequest{milliCPU: 1, memory: 2}),
			nodeInfo: schedulercache.NewNodeInfo(
				newResourcePod(resourceRequest{milliCPU: 5, memory: 19})),
			fits: false,
			test: "one resources fits",
			wErr: newInsufficientResourceError(memoryResoureceName, 2, 19, 20),
		},
		{
			pod: newResourcePod(resourceRequest{milliCPU: 5, memory: 1}),
			nodeInfo: schedulercache.NewNodeInfo(
				newResourcePod(resourceRequest{milliCPU: 5, memory: 19})),
			fits: true,
			test: "equal edge case",
			wErr: nil,
		},
	}

	for _, test := range enoughPodsTests {
		node := api.Node{Status: api.NodeStatus{Capacity: makeResources(10, 20, 32).Capacity, Allocatable: makeAllocatableResources(10, 20, 32)}}

		fit := ResourceFit{FakeNodeInfo(node)}
		fits, err := fit.PodFitsResources(test.pod, "machine", test.nodeInfo)
		if !reflect.DeepEqual(err, test.wErr) {
			t.Errorf("%s: unexpected error: %v, want: %v", test.test, err, test.wErr)
		}
		if fits != test.fits {
			t.Errorf("%s: expected: %v got %v", test.test, test.fits, fits)
		}
	}

	notEnoughPodsTests := []struct {
		pod      *api.Pod
		nodeInfo *schedulercache.NodeInfo
		fits     bool
		test     string
		wErr     error
	}{
		{
			pod: &api.Pod{},
			nodeInfo: schedulercache.NewNodeInfo(
				newResourcePod(resourceRequest{milliCPU: 10, memory: 20})),
			fits: false,
			test: "even without specified resources predicate fails when there's no space for additional pod",
			wErr: newInsufficientResourceError(podCountResourceName, 1, 1, 1),
		},
		{
			pod: newResourcePod(resourceRequest{milliCPU: 1, memory: 1}),
			nodeInfo: schedulercache.NewNodeInfo(
				newResourcePod(resourceRequest{milliCPU: 5, memory: 5})),
			fits: false,
			test: "even if both resources fit predicate fails when there's no space for additional pod",
			wErr: newInsufficientResourceError(podCountResourceName, 1, 1, 1),
		},
		{
			pod: newResourcePod(resourceRequest{milliCPU: 5, memory: 1}),
			nodeInfo: schedulercache.NewNodeInfo(
				newResourcePod(resourceRequest{milliCPU: 5, memory: 19})),
			fits: false,
			test: "even for equal edge case predicate fails when there's no space for additional pod",
			wErr: newInsufficientResourceError(podCountResourceName, 1, 1, 1),
		},
	}
	for _, test := range notEnoughPodsTests {
		node := api.Node{Status: api.NodeStatus{Capacity: api.ResourceList{}, Allocatable: makeAllocatableResources(10, 20, 1)}}

		fit := ResourceFit{FakeNodeInfo(node)}
		fits, err := fit.PodFitsResources(test.pod, "machine", test.nodeInfo)
		if !reflect.DeepEqual(err, test.wErr) {
			t.Errorf("%s: unexpected error: %v, want: %v", test.test, err, test.wErr)
		}
		if fits != test.fits {
			t.Errorf("%s: expected: %v got %v", test.test, test.fits, fits)
		}
	}
}

func TestPodFitsHost(t *testing.T) {
	tests := []struct {
		pod  *api.Pod
		node string
		fits bool
		test string
	}{
		{
			pod:  &api.Pod{},
			node: "foo",
			fits: true,
			test: "no host specified",
		},
		{
			pod: &api.Pod{
				Spec: api.PodSpec{
					NodeName: "foo",
				},
			},
			node: "foo",
			fits: true,
			test: "host matches",
		},
		{
			pod: &api.Pod{
				Spec: api.PodSpec{
					NodeName: "bar",
				},
			},
			node: "foo",
			fits: false,
			test: "host doesn't match",
		},
	}

	for _, test := range tests {
		result, err := PodFitsHost(test.pod, test.node, schedulercache.NewNodeInfo())
		if err != nil {
			t.Errorf("unexpected error: %v", err)
		}
		if result != test.fits {
			t.Errorf("unexpected difference for %s: got: %v expected %v", test.test, test.fits, result)
		}
	}
}

func newPod(host string, hostPorts ...int) *api.Pod {
	networkPorts := []api.ContainerPort{}
	for _, port := range hostPorts {
		networkPorts = append(networkPorts, api.ContainerPort{HostPort: port})
	}
	return &api.Pod{
		Spec: api.PodSpec{
			NodeName: host,
			Containers: []api.Container{
				{
					Ports: networkPorts,
				},
			},
		},
	}
}

func TestPodFitsHostPorts(t *testing.T) {
	tests := []struct {
		pod      *api.Pod
		nodeInfo *schedulercache.NodeInfo
		fits     bool
		test     string
	}{
		{
			pod:      &api.Pod{},
			nodeInfo: schedulercache.NewNodeInfo(),
			fits:     true,
			test:     "nothing running",
		},
		{
			pod: newPod("m1", 8080),
			nodeInfo: schedulercache.NewNodeInfo(
				newPod("m1", 9090)),
			fits: true,
			test: "other port",
		},
		{
			pod: newPod("m1", 8080),
			nodeInfo: schedulercache.NewNodeInfo(
				newPod("m1", 8080)),
			fits: false,
			test: "same port",
		},
		{
			pod: newPod("m1", 8000, 8080),
			nodeInfo: schedulercache.NewNodeInfo(
				newPod("m1", 8080)),
			fits: false,
			test: "second port",
		},
		{
			pod: newPod("m1", 8000, 8080),
			nodeInfo: schedulercache.NewNodeInfo(
				newPod("m1", 8001, 8080)),
			fits: false,
			test: "second port",
		},
	}
	for _, test := range tests {
		fits, err := PodFitsHostPorts(test.pod, "machine", test.nodeInfo)
		if err != nil {
			t.Errorf("unexpected error: %v", err)
		}
		if test.fits != fits {
			t.Errorf("%s: expected %v, saw %v", test.test, test.fits, fits)
		}
	}
}

func TestGetUsedPorts(t *testing.T) {
	tests := []struct {
		pods []*api.Pod

		ports map[int]bool
	}{
		{
			[]*api.Pod{
				newPod("m1", 9090),
			},
			map[int]bool{9090: true},
		},
		{
			[]*api.Pod{
				newPod("m1", 9090),
				newPod("m1", 9091),
			},
			map[int]bool{9090: true, 9091: true},
		},
		{
			[]*api.Pod{
				newPod("m1", 9090),
				newPod("m2", 9091),
			},
			map[int]bool{9090: true, 9091: true},
		},
	}

	for _, test := range tests {
		ports := getUsedPorts(test.pods...)
		if !reflect.DeepEqual(test.ports, ports) {
			t.Errorf("expect %v, got %v", test.ports, ports)
		}
	}
}

func TestDiskConflicts(t *testing.T) {
	volState := api.PodSpec{
		Volumes: []api.Volume{
			{
				VolumeSource: api.VolumeSource{
					GCEPersistentDisk: &api.GCEPersistentDiskVolumeSource{
						PDName: "foo",
					},
				},
			},
		},
	}
	volState2 := api.PodSpec{
		Volumes: []api.Volume{
			{
				VolumeSource: api.VolumeSource{
					GCEPersistentDisk: &api.GCEPersistentDiskVolumeSource{
						PDName: "bar",
					},
				},
			},
		},
	}
	tests := []struct {
		pod      *api.Pod
		nodeInfo *schedulercache.NodeInfo
		isOk     bool
		test     string
	}{
		{&api.Pod{}, schedulercache.NewNodeInfo(), true, "nothing"},
		{&api.Pod{}, schedulercache.NewNodeInfo(&api.Pod{Spec: volState}), true, "one state"},
		{&api.Pod{Spec: volState}, schedulercache.NewNodeInfo(&api.Pod{Spec: volState}), false, "same state"},
		{&api.Pod{Spec: volState2}, schedulercache.NewNodeInfo(&api.Pod{Spec: volState}), true, "different state"},
	}

	for _, test := range tests {
		ok, err := NoDiskConflict(test.pod, "machine", test.nodeInfo)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if test.isOk && !ok {
			t.Errorf("expected ok, got none.  %v %s %s", test.pod, test.nodeInfo, test.test)
		}
		if !test.isOk && ok {
			t.Errorf("expected no ok, got one.  %v %s %s", test.pod, test.nodeInfo, test.test)
		}
	}
}

func TestAWSDiskConflicts(t *testing.T) {
	volState := api.PodSpec{
		Volumes: []api.Volume{
			{
				VolumeSource: api.VolumeSource{
					AWSElasticBlockStore: &api.AWSElasticBlockStoreVolumeSource{
						VolumeID: "foo",
					},
				},
			},
		},
	}
	volState2 := api.PodSpec{
		Volumes: []api.Volume{
			{
				VolumeSource: api.VolumeSource{
					AWSElasticBlockStore: &api.AWSElasticBlockStoreVolumeSource{
						VolumeID: "bar",
					},
				},
			},
		},
	}
	tests := []struct {
		pod      *api.Pod
		nodeInfo *schedulercache.NodeInfo
		isOk     bool
		test     string
	}{
		{&api.Pod{}, schedulercache.NewNodeInfo(), true, "nothing"},
		{&api.Pod{}, schedulercache.NewNodeInfo(&api.Pod{Spec: volState}), true, "one state"},
		{&api.Pod{Spec: volState}, schedulercache.NewNodeInfo(&api.Pod{Spec: volState}), false, "same state"},
		{&api.Pod{Spec: volState2}, schedulercache.NewNodeInfo(&api.Pod{Spec: volState}), true, "different state"},
	}

	for _, test := range tests {
		ok, err := NoDiskConflict(test.pod, "machine", test.nodeInfo)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if test.isOk && !ok {
			t.Errorf("expected ok, got none.  %v %s %s", test.pod, test.nodeInfo, test.test)
		}
		if !test.isOk && ok {
			t.Errorf("expected no ok, got one.  %v %s %s", test.pod, test.nodeInfo, test.test)
		}
	}
}

func TestRBDDiskConflicts(t *testing.T) {
	volState := api.PodSpec{
		Volumes: []api.Volume{
			{
				VolumeSource: api.VolumeSource{
					RBD: &api.RBDVolumeSource{
						CephMonitors: []string{"a", "b"},
						RBDPool:      "foo",
						RBDImage:     "bar",
						FSType:       "ext4",
					},
				},
			},
		},
	}
	volState2 := api.PodSpec{
		Volumes: []api.Volume{
			{
				VolumeSource: api.VolumeSource{
					RBD: &api.RBDVolumeSource{
						CephMonitors: []string{"c", "d"},
						RBDPool:      "foo",
						RBDImage:     "bar",
						FSType:       "ext4",
					},
				},
			},
		},
	}
	tests := []struct {
		pod      *api.Pod
		nodeInfo *schedulercache.NodeInfo
		isOk     bool
		test     string
	}{
		{&api.Pod{}, schedulercache.NewNodeInfo(), true, "nothing"},
		{&api.Pod{}, schedulercache.NewNodeInfo(&api.Pod{Spec: volState}), true, "one state"},
		{&api.Pod{Spec: volState}, schedulercache.NewNodeInfo(&api.Pod{Spec: volState}), false, "same state"},
		{&api.Pod{Spec: volState2}, schedulercache.NewNodeInfo(&api.Pod{Spec: volState}), true, "different state"},
	}

	for _, test := range tests {
		ok, err := NoDiskConflict(test.pod, "machine", test.nodeInfo)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if test.isOk && !ok {
			t.Errorf("expected ok, got none.  %v %s %s", test.pod, test.nodeInfo, test.test)
		}
		if !test.isOk && ok {
			t.Errorf("expected no ok, got one.  %v %s %s", test.pod, test.nodeInfo, test.test)
		}
	}
}

func TestPodFitsSelector(t *testing.T) {
	tests := []struct {
		pod    *api.Pod
		labels map[string]string
		fits   bool
		test   string
	}{
		{
			pod:  &api.Pod{},
			fits: true,
			test: "no selector",
		},
		{
			pod: &api.Pod{
				Spec: api.PodSpec{
					NodeSelector: map[string]string{
						"foo": "bar",
					},
				},
			},
			fits: false,
			test: "missing labels",
		},
		{
			pod: &api.Pod{
				Spec: api.PodSpec{
					NodeSelector: map[string]string{
						"foo": "bar",
					},
				},
			},
			labels: map[string]string{
				"foo": "bar",
			},
			fits: true,
			test: "same labels",
		},
		{
			pod: &api.Pod{
				Spec: api.PodSpec{
					NodeSelector: map[string]string{
						"foo": "bar",
					},
				},
			},
			labels: map[string]string{
				"foo": "bar",
				"baz": "blah",
			},
			fits: true,
			test: "node labels are superset",
		},
		{
			pod: &api.Pod{
				Spec: api.PodSpec{
					NodeSelector: map[string]string{
						"foo": "bar",
						"baz": "blah",
					},
				},
			},
			labels: map[string]string{
				"foo": "bar",
			},
			fits: false,
			test: "node labels are subset",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": [{
								"matchExpressions": [{
									"key": "foo",
									"operator": "In",
									"values": ["bar", "value2"]
								}]
							}]
						}}}`,
					},
				},
			},
			labels: map[string]string{
				"foo": "bar",
			},
			fits: true,
			test: "Pod with matchExpressions using In operator that matches the existing node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": [{
								"matchExpressions": [{
									"key": "kernel-version",
									"operator": "Gt",
									"values": ["2.4"]
								}]
							}]
						}}}`,
					},
				},
			},
			labels: map[string]string{
				"kernel-version": "2.6",
			},
			fits: true,
			test: "Pod with matchExpressions using Gt operator that matches the existing node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": [{
								"matchExpressions": [{
									"key": "mem-type",
									"operator": "NotIn",
									"values": ["DDR", "DDR2"]
								}]
							}]
						}}}`,
					},
				},
			},
			labels: map[string]string{
				"mem-type": "DDR3",
			},
			fits: true,
			test: "Pod with matchExpressions using NotIn operator that matches the existing node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": [{
								"matchExpressions": [{
									"key": "GPU",
									"operator": "Exists"
								}]
							}]
						}}}`,
					},
				},
			},
			labels: map[string]string{
				"GPU": "NVIDIA-GRID-K1",
			},
			fits: true,
			test: "Pod with matchExpressions using Exists operator that matches the existing node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": [{
								"matchExpressions": [{
									"key": "foo",
									"operator": "In",
									"values": ["value1", "value2"]
								}]
							}]
						}}}`,
					},
				},
			},
			labels: map[string]string{
				"foo": "bar",
			},
			fits: false,
			test: "Pod with affinity that don't match node's labels won't schedule onto the node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": null
						}}}`,
					},
				},
			},
			labels: map[string]string{
				"foo": "bar",
			},
			fits: false,
			test: "Pod with a nil []NodeSelectorTerm in affinity, can't match the node's labels and won't schedule onto the node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": []
						}}}`,
					},
				},
			},
			labels: map[string]string{
				"foo": "bar",
			},
			fits: false,
			test: "Pod with an empty []NodeSelectorTerm in affinity, can't match the node's labels and won't schedule onto the node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": [{}, {}]
						}}}`,
					},
				},
			},
			labels: map[string]string{
				"foo": "bar",
			},
			fits: false,
			test: "Pod with invalid NodeSelectTerms in affinity will match no objects and won't schedule onto the node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": [{"matchExpressions": [{}]}]
						}}}`,
					},
				},
			},
			labels: map[string]string{
				"foo": "bar",
			},
			fits: false,
			test: "Pod with empty MatchExpressions is not a valid value will match no objects and won't schedule onto the node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						"some-key": "some-value",
					},
				},
			},
			labels: map[string]string{
				"foo": "bar",
			},
			fits: true,
			test: "Pod with no Affinity will schedule onto a node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": null
						}}`,
					},
				},
			},
			labels: map[string]string{
				"foo": "bar",
			},
			fits: true,
			test: "Pod with Affinity but nil NodeSelector will schedule onto a node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": [{
								"matchExpressions": [{
									"key": "GPU",
									"operator": "Exists"
								}, {
									"key": "GPU",
									"operator": "NotIn",
									"values": ["AMD", "INTER"]
								}]
							}]
						}}}`,
					},
				},
			},
			labels: map[string]string{
				"GPU": "NVIDIA-GRID-K1",
			},
			fits: true,
			test: "Pod with multiple matchExpressions ANDed that matches the existing node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": [{
								"matchExpressions": [{
									"key": "GPU",
									"operator": "Exists"
								}, {
									"key": "GPU",
									"operator": "In",
									"values": ["AMD", "INTER"]
								}]
							}]
						}}}`,
					},
				},
			},
			labels: map[string]string{
				"GPU": "NVIDIA-GRID-K1",
			},
			fits: false,
			test: "Pod with multiple matchExpressions ANDed that doesn't match the existing node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": [
								{
									"matchExpressions": [{
										"key": "foo",
										"operator": "In",
										"values": ["bar", "value2"]
									}]
								},
								{
									"matchExpressions": [{
										"key": "diffkey",
										"operator": "In",
										"values": ["wrong", "value2"]
									}]
								}
							]
						}}}`,
					},
				},
			},
			labels: map[string]string{
				"foo": "bar",
			},
			fits: true,
			test: "Pod with multiple NodeSelectorTerms ORed in affinity, matches the node's labels and will schedule onto the node",
		},
		// TODO: Uncomment this test when implement RequiredDuringSchedulingRequiredDuringExecution
		//		{
		//			pod: &api.Pod{
		//				ObjectMeta: api.ObjectMeta{
		//					Annotations: map[string]string{
		//						api.AffinityAnnotationKey: `
		//						{"nodeAffinity": {
		//							"requiredDuringSchedulingRequiredDuringExecution": {
		//								"nodeSelectorTerms": [{
		//									"matchExpressions": [{
		//										"key": "foo",
		//										"operator": "In",
		//										"values": ["bar", "value2"]
		//									}]
		//								}]
		//							},
		//							"requiredDuringSchedulingIgnoredDuringExecution": {
		//								"nodeSelectorTerms": [{
		//									"matchExpressions": [{
		//										"key": "foo",
		//										"operator": "NotIn",
		//										"values": ["bar", "value2"]
		//									}]
		//								}]
		//							}
		//						}}`,
		//					},
		//				},
		//			},
		//			labels: map[string]string{
		//				"foo": "bar",
		//			},
		//			fits: false,
		//			test: "Pod with an Affinity both requiredDuringSchedulingRequiredDuringExecution and " +
		//				"requiredDuringSchedulingIgnoredDuringExecution indicated that don't match node's labels and won't schedule onto the node",
		//		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": [{
								"matchExpressions": [{
									"key": "foo",
									"operator": "Exists"
								}]
							}]
						}}}`,
					},
				},
				Spec: api.PodSpec{
					NodeSelector: map[string]string{
						"foo": "bar",
					},
				},
			},
			labels: map[string]string{
				"foo": "bar",
			},
			fits: true,
			test: "Pod with an Affinity and a PodSpec.NodeSelector(the old thing that we are deprecating) " +
				"both are satisfied, will schedule onto the node",
		},
		{
			pod: &api.Pod{
				ObjectMeta: api.ObjectMeta{
					Annotations: map[string]string{
						api.AffinityAnnotationKey: `
						{"nodeAffinity": { "requiredDuringSchedulingIgnoredDuringExecution": {
							"nodeSelectorTerms": [{
								"matchExpressions": [{
									"key": "foo",
									"operator": "Exists"
								}]
							}]
						}}}`,
					},
				},
				Spec: api.PodSpec{
					NodeSelector: map[string]string{
						"foo": "bar",
					},
				},
			},
			labels: map[string]string{
				"foo": "barrrrrr",
			},
			fits: false,
			test: "Pod with an Affinity matches node's labels but the PodSpec.NodeSelector(the old thing that we are deprecating) " +
				"is not satisfied, won't schedule onto the node",
		},
	}

	for _, test := range tests {
		node := api.Node{ObjectMeta: api.ObjectMeta{Labels: test.labels}}

		fit := NodeSelector{FakeNodeInfo(node)}
		fits, err := fit.PodSelectorMatches(test.pod, "machine", schedulercache.NewNodeInfo())
		if err != nil {
			t.Errorf("unexpected error: %v", err)
		}
		if fits != test.fits {
			t.Errorf("%s: expected: %v got %v", test.test, test.fits, fits)
		}
	}
}

func TestNodeLabelPresence(t *testing.T) {
	label := map[string]string{"foo": "bar", "bar": "foo"}
	tests := []struct {
		pod      *api.Pod
		labels   []string
		presence bool
		fits     bool
		test     string
	}{
		{
			labels:   []string{"baz"},
			presence: true,
			fits:     false,
			test:     "label does not match, presence true",
		},
		{
			labels:   []string{"baz"},
			presence: false,
			fits:     true,
			test:     "label does not match, presence false",
		},
		{
			labels:   []string{"foo", "baz"},
			presence: true,
			fits:     false,
			test:     "one label matches, presence true",
		},
		{
			labels:   []string{"foo", "baz"},
			presence: false,
			fits:     false,
			test:     "one label matches, presence false",
		},
		{
			labels:   []string{"foo", "bar"},
			presence: true,
			fits:     true,
			test:     "all labels match, presence true",
		},
		{
			labels:   []string{"foo", "bar"},
			presence: false,
			fits:     false,
			test:     "all labels match, presence false",
		},
	}
	for _, test := range tests {
		node := api.Node{ObjectMeta: api.ObjectMeta{Labels: label}}
		labelChecker := NodeLabelChecker{FakeNodeInfo(node), test.labels, test.presence}
		fits, err := labelChecker.CheckNodeLabelPresence(test.pod, "machine", schedulercache.NewNodeInfo())
		if err != nil {
			t.Errorf("unexpected error: %v", err)
		}
		if fits != test.fits {
			t.Errorf("%s: expected: %v got %v", test.test, test.fits, fits)
		}
	}
}

func TestServiceAffinity(t *testing.T) {
	selector := map[string]string{"foo": "bar"}
	labels1 := map[string]string{
		"region": "r1",
		"zone":   "z11",
	}
	labels2 := map[string]string{
		"region": "r1",
		"zone":   "z12",
	}
	labels3 := map[string]string{
		"region": "r2",
		"zone":   "z21",
	}
	labels4 := map[string]string{
		"region": "r2",
		"zone":   "z22",
	}
	node1 := api.Node{ObjectMeta: api.ObjectMeta{Name: "machine1", Labels: labels1}}
	node2 := api.Node{ObjectMeta: api.ObjectMeta{Name: "machine2", Labels: labels2}}
	node3 := api.Node{ObjectMeta: api.ObjectMeta{Name: "machine3", Labels: labels3}}
	node4 := api.Node{ObjectMeta: api.ObjectMeta{Name: "machine4", Labels: labels4}}
	node5 := api.Node{ObjectMeta: api.ObjectMeta{Name: "machine5", Labels: labels4}}
	tests := []struct {
		pod      *api.Pod
		pods     []*api.Pod
		services []api.Service
		node     string
		labels   []string
		fits     bool
		test     string
	}{
		{
			pod:    new(api.Pod),
			node:   "machine1",
			fits:   true,
			labels: []string{"region"},
			test:   "nothing scheduled",
		},
		{
			pod:    &api.Pod{Spec: api.PodSpec{NodeSelector: map[string]string{"region": "r1"}}},
			node:   "machine1",
			fits:   true,
			labels: []string{"region"},
			test:   "pod with region label match",
		},
		{
			pod:    &api.Pod{Spec: api.PodSpec{NodeSelector: map[string]string{"region": "r2"}}},
			node:   "machine1",
			fits:   false,
			labels: []string{"region"},
			test:   "pod with region label mismatch",
		},
		{
			pod:      &api.Pod{ObjectMeta: api.ObjectMeta{Labels: selector}},
			pods:     []*api.Pod{{Spec: api.PodSpec{NodeName: "machine1"}, ObjectMeta: api.ObjectMeta{Labels: selector}}},
			node:     "machine1",
			services: []api.Service{{Spec: api.ServiceSpec{Selector: selector}}},
			fits:     true,
			labels:   []string{"region"},
			test:     "service pod on same node",
		},
		{
			pod:      &api.Pod{ObjectMeta: api.ObjectMeta{Labels: selector}},
			pods:     []*api.Pod{{Spec: api.PodSpec{NodeName: "machine2"}, ObjectMeta: api.ObjectMeta{Labels: selector}}},
			node:     "machine1",
			services: []api.Service{{Spec: api.ServiceSpec{Selector: selector}}},
			fits:     true,
			labels:   []string{"region"},
			test:     "service pod on different node, region match",
		},
		{
			pod:      &api.Pod{ObjectMeta: api.ObjectMeta{Labels: selector}},
			pods:     []*api.Pod{{Spec: api.PodSpec{NodeName: "machine3"}, ObjectMeta: api.ObjectMeta{Labels: selector}}},
			node:     "machine1",
			services: []api.Service{{Spec: api.ServiceSpec{Selector: selector}}},
			fits:     false,
			labels:   []string{"region"},
			test:     "service pod on different node, region mismatch",
		},
		{
			pod:      &api.Pod{ObjectMeta: api.ObjectMeta{Labels: selector, Namespace: "ns1"}},
			pods:     []*api.Pod{{Spec: api.PodSpec{NodeName: "machine3"}, ObjectMeta: api.ObjectMeta{Labels: selector, Namespace: "ns1"}}},
			node:     "machine1",
			services: []api.Service{{Spec: api.ServiceSpec{Selector: selector}, ObjectMeta: api.ObjectMeta{Namespace: "ns2"}}},
			fits:     true,
			labels:   []string{"region"},
			test:     "service in different namespace, region mismatch",
		},
		{
			pod:      &api.Pod{ObjectMeta: api.ObjectMeta{Labels: selector, Namespace: "ns1"}},
			pods:     []*api.Pod{{Spec: api.PodSpec{NodeName: "machine3"}, ObjectMeta: api.ObjectMeta{Labels: selector, Namespace: "ns2"}}},
			node:     "machine1",
			services: []api.Service{{Spec: api.ServiceSpec{Selector: selector}, ObjectMeta: api.ObjectMeta{Namespace: "ns1"}}},
			fits:     true,
			labels:   []string{"region"},
			test:     "pod in different namespace, region mismatch",
		},
		{
			pod:      &api.Pod{ObjectMeta: api.ObjectMeta{Labels: selector, Namespace: "ns1"}},
			pods:     []*api.Pod{{Spec: api.PodSpec{NodeName: "machine3"}, ObjectMeta: api.ObjectMeta{Labels: selector, Namespace: "ns1"}}},
			node:     "machine1",
			services: []api.Service{{Spec: api.ServiceSpec{Selector: selector}, ObjectMeta: api.ObjectMeta{Namespace: "ns1"}}},
			fits:     false,
			labels:   []string{"region"},
			test:     "service and pod in same namespace, region mismatch",
		},
		{
			pod:      &api.Pod{ObjectMeta: api.ObjectMeta{Labels: selector}},
			pods:     []*api.Pod{{Spec: api.PodSpec{NodeName: "machine2"}, ObjectMeta: api.ObjectMeta{Labels: selector}}},
			node:     "machine1",
			services: []api.Service{{Spec: api.ServiceSpec{Selector: selector}}},
			fits:     false,
			labels:   []string{"region", "zone"},
			test:     "service pod on different node, multiple labels, not all match",
		},
		{
			pod:      &api.Pod{ObjectMeta: api.ObjectMeta{Labels: selector}},
			pods:     []*api.Pod{{Spec: api.PodSpec{NodeName: "machine5"}, ObjectMeta: api.ObjectMeta{Labels: selector}}},
			node:     "machine4",
			services: []api.Service{{Spec: api.ServiceSpec{Selector: selector}}},
			fits:     true,
			labels:   []string{"region", "zone"},
			test:     "service pod on different node, multiple labels, all match",
		},
	}

	for _, test := range tests {
		nodes := []api.Node{node1, node2, node3, node4, node5}
		serviceAffinity := ServiceAffinity{algorithm.FakePodLister(test.pods), algorithm.FakeServiceLister(test.services), FakeNodeListInfo(nodes), test.labels}
		fits, err := serviceAffinity.CheckServiceAffinity(test.pod, test.node, schedulercache.NewNodeInfo())
		if err != nil {
			t.Errorf("unexpected error: %v", err)
		}
		if fits != test.fits {
			t.Errorf("%s: expected: %v got %v", test.test, test.fits, fits)
		}
	}
}

func TestEBSVolumeCountConflicts(t *testing.T) {
	oneVolPod := &api.Pod{
		Spec: api.PodSpec{
			Volumes: []api.Volume{
				{
					VolumeSource: api.VolumeSource{
						AWSElasticBlockStore: &api.AWSElasticBlockStoreVolumeSource{VolumeID: "ovp"},
					},
				},
			},
		},
	}
	ebsPVCPod := &api.Pod{
		Spec: api.PodSpec{
			Volumes: []api.Volume{
				{
					VolumeSource: api.VolumeSource{
						PersistentVolumeClaim: &api.PersistentVolumeClaimVolumeSource{
							ClaimName: "someEBSVol",
						},
					},
				},
			},
		},
	}
	splitPVCPod := &api.Pod{
		Spec: api.PodSpec{
			Volumes: []api.Volume{
				{
					VolumeSource: api.VolumeSource{
						PersistentVolumeClaim: &api.PersistentVolumeClaimVolumeSource{
							ClaimName: "someNonEBSVol",
						},
					},
				},
				{
					VolumeSource: api.VolumeSource{
						PersistentVolumeClaim: &api.PersistentVolumeClaimVolumeSource{
							ClaimName: "someEBSVol",
						},
					},
				},
			},
		},
	}
	twoVolPod := &api.Pod{
		Spec: api.PodSpec{
			Volumes: []api.Volume{
				{
					VolumeSource: api.VolumeSource{
						AWSElasticBlockStore: &api.AWSElasticBlockStoreVolumeSource{VolumeID: "tvp1"},
					},
				},
				{
					VolumeSource: api.VolumeSource{
						AWSElasticBlockStore: &api.AWSElasticBlockStoreVolumeSource{VolumeID: "tvp2"},
					},
				},
			},
		},
	}
	splitVolsPod := &api.Pod{
		Spec: api.PodSpec{
			Volumes: []api.Volume{
				{
					VolumeSource: api.VolumeSource{
						HostPath: &api.HostPathVolumeSource{},
					},
				},
				{
					VolumeSource: api.VolumeSource{
						AWSElasticBlockStore: &api.AWSElasticBlockStoreVolumeSource{VolumeID: "svp"},
					},
				},
			},
		},
	}
	nonApplicablePod := &api.Pod{
		Spec: api.PodSpec{
			Volumes: []api.Volume{
				{
					VolumeSource: api.VolumeSource{
						HostPath: &api.HostPathVolumeSource{},
					},
				},
			},
		},
	}
	emptyPod := &api.Pod{
		Spec: api.PodSpec{},
	}

	tests := []struct {
		newPod       *api.Pod
		existingPods []*api.Pod
		maxVols      int
		fits         bool
		test         string
	}{
		{
			newPod:       oneVolPod,
			existingPods: []*api.Pod{twoVolPod, oneVolPod},
			maxVols:      4,
			fits:         true,
			test:         "fits when node capacity >= new pod's EBS volumes",
		},
		{
			newPod:       twoVolPod,
			existingPods: []*api.Pod{oneVolPod},
			maxVols:      2,
			fits:         false,
			test:         "doesn't fit when node capacity < new pod's EBS volumes",
		},
		{
			newPod:       splitVolsPod,
			existingPods: []*api.Pod{twoVolPod},
			maxVols:      3,
			fits:         true,
			test:         "new pod's count ignores non-EBS volumes",
		},
		{
			newPod:       twoVolPod,
			existingPods: []*api.Pod{splitVolsPod, nonApplicablePod, emptyPod},
			maxVols:      3,
			fits:         true,
			test:         "existing pods' counts ignore non-EBS volumes",
		},
		{
			newPod:       ebsPVCPod,
			existingPods: []*api.Pod{splitVolsPod, nonApplicablePod, emptyPod},
			maxVols:      3,
			fits:         true,
			test:         "new pod's count considers PVCs backed by EBS volumes",
		},
		{
			newPod:       splitPVCPod,
			existingPods: []*api.Pod{splitVolsPod, oneVolPod},
			maxVols:      3,
			fits:         true,
			test:         "new pod's count ignores PVCs not backed by EBS volumes",
		},
		{
			newPod:       twoVolPod,
			existingPods: []*api.Pod{oneVolPod, ebsPVCPod},
			maxVols:      3,
			fits:         false,
			test:         "existing pods' counts considers PVCs backed by EBS volumes",
		},
		{
			newPod:       twoVolPod,
			existingPods: []*api.Pod{oneVolPod, twoVolPod, ebsPVCPod},
			maxVols:      4,
			fits:         true,
			test:         "already-mounted EBS volumes are always ok to allow",
		},
		{
			newPod:       splitVolsPod,
			existingPods: []*api.Pod{oneVolPod, oneVolPod, ebsPVCPod},
			maxVols:      3,
			fits:         true,
			test:         "the same EBS volumes are not counted multiple times",
		},
	}

	pvInfo := FakePersistentVolumeInfo{
		{
			ObjectMeta: api.ObjectMeta{Name: "someEBSVol"},
			Spec: api.PersistentVolumeSpec{
				PersistentVolumeSource: api.PersistentVolumeSource{
					AWSElasticBlockStore: &api.AWSElasticBlockStoreVolumeSource{},
				},
			},
		},
		{
			ObjectMeta: api.ObjectMeta{Name: "someNonEBSVol"},
			Spec: api.PersistentVolumeSpec{
				PersistentVolumeSource: api.PersistentVolumeSource{},
			},
		},
	}

	pvcInfo := FakePersistentVolumeClaimInfo{
		{
			ObjectMeta: api.ObjectMeta{Name: "someEBSVol"},
			Spec:       api.PersistentVolumeClaimSpec{VolumeName: "someEBSVol"},
		},
		{
			ObjectMeta: api.ObjectMeta{Name: "someNonEBSVol"},
			Spec:       api.PersistentVolumeClaimSpec{VolumeName: "someNonEBSVol"},
		},
	}

	filter := VolumeFilter{
		FilterVolume: func(vol *api.Volume) (string, bool) {
			if vol.AWSElasticBlockStore != nil {
				return vol.AWSElasticBlockStore.VolumeID, true
			}
			return "", false
		},

		FilterPersistentVolume: func(pv *api.PersistentVolume) (string, bool) {
			if pv.Spec.AWSElasticBlockStore != nil {
				return pv.Spec.AWSElasticBlockStore.VolumeID, true
			}
			return "", false
		},
	}

	for _, test := range tests {
		pred := NewMaxPDVolumeCountPredicate(filter, test.maxVols, pvInfo, pvcInfo)
		fits, err := pred(test.newPod, "some-node", schedulercache.NewNodeInfo(test.existingPods...))
		if err != nil {
			t.Errorf("unexpected error: %v", err)
		}

		if fits != test.fits {
			t.Errorf("%s: expected %v, got %v", test.test, test.fits, fits)
		}
	}
}
