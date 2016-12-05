/*
Copyright 2016 The Kubernetes Authors.

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

package cidrallocation

import (
	"fmt"
	"net"
	"time"

	"github.com/golang/glog"
	"k8s.io/kubernetes/pkg/api/errors"
	"k8s.io/kubernetes/pkg/api/v1"
	"k8s.io/kubernetes/pkg/client/cache"
	clientset "k8s.io/kubernetes/pkg/client/clientset_generated/release_1_5"
	"k8s.io/kubernetes/pkg/client/record"
	"k8s.io/kubernetes/pkg/controller"
	"k8s.io/kubernetes/pkg/controller/informers"
	utilruntime "k8s.io/kubernetes/pkg/util/runtime"
	"k8s.io/kubernetes/pkg/util/wait"
	"k8s.io/kubernetes/pkg/util/workqueue"
)

// TODO: figure out the good setting for those constants.
const (
	// podCIDRUpdateRetry controls the number of retries of writing Node.Spec.PodCIDR update.
	podCIDRUpdateRetry = 5

	// TODO: make this configurable
	ConcurrentNodeCIDRSyncs = 5
)

type CIDRAllocationController struct {
	kubeClient   clientset.Interface
	nodeInformer informers.NodeInformer

	clusterCIDR *net.IPNet
	serviceCIDR *net.IPNet
	cidrs       *cidrSet

	nodeLister *cache.StoreToNodeLister
	nodeSynced cache.InformerSynced

	recorder record.EventRecorder
	// nodes that need to be synced
	queue workqueue.RateLimitingInterface

	// To allow injection for testing.
	syncHandler func(nodeKey string) error
}

func NewCIDRAllocationController(
	nodeInformer informers.NodeInformer,
	kubeClient clientset.Interface,

	clusterCIDR *net.IPNet,
	serviceCIDR *net.IPNet,
	nodeCIDRMaskSize int,
) (*CIDRAllocationController, error) {

	if clusterCIDR == nil {
		glog.Fatal("NodeController: Must specify clusterCIDR if allocateNodeCIDRs == true.")
	}
	mask := clusterCIDR.Mask
	if maskSize, _ := mask.Size(); maskSize > nodeCIDRMaskSize {
		glog.Fatal("NodeController: Invalid clusterCIDR, mask size of clusterCIDR must be less than nodeCIDRMaskSize.")
	}

	ac := &CIDRAllocationController{
		kubeClient:   kubeClient,
		nodeInformer: nodeInformer,
		clusterCIDR:  clusterCIDR,
		serviceCIDR:  serviceCIDR,
		cidrs:        newCIDRSet(clusterCIDR, nodeCIDRMaskSize),
		queue:        workqueue.NewNamedRateLimitingQueue(workqueue.DefaultControllerRateLimiter(), "node-cidr-allocator"),
	}

	ac.nodeInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: ac.AllocateOrOccupyCIDR,
		UpdateFunc: func(_, obj interface{}) {
			ac.AllocateOrOccupyCIDR(obj)
		},
		DeleteFunc: ac.ReleaseCIDR,
	})

	ac.nodeSynced = nodeInformer.Informer().HasSynced
	ac.nodeLister = nodeInformer.Lister()

	return ac, nil
}

func (ac *CIDRAllocationController) Run(workers int, stopCh <-chan struct{}) {
	defer utilruntime.HandleCrash()

	glog.Infof("Starting ServiceAccount controller")

	ac.filterOutServiceRange(ac.serviceCIDR)

	if !cache.WaitForCacheSync(stopCh, ac.nodeSynced) {
		return
	}

	ac.filterOutAlreadyAllocated()

	for i := 0; i < workers; i++ {
		go wait.Until(ac.worker, time.Second, stopCh)
	}

	<-stopCh
	glog.Infof("Shutting down ServiceAccount controller")
}

// Marks all CIDRs with subNetMaskSize that belongs to serviceCIDR as used,
// so that they won't be assignable.
func (ac *CIDRAllocationController) filterOutServiceRange(serviceCIDR *net.IPNet) {
	if serviceCIDR == nil {
		glog.V(0).Info("No Service CIDR provided. Skipping filtering out service addresses.")
		return
	}
	// Checks if service CIDR has a nonempty intersection with cluster CIDR. It is the case if either
	// clusterCIDR contains serviceCIDR with clusterCIDR's Mask applied (this means that clusterCIDR contains serviceCIDR)
	// or vice versa (which means that serviceCIDR contains clusterCIDR).
	if !ac.cidrs.clusterCIDR.Contains(serviceCIDR.IP.Mask(ac.cidrs.clusterCIDR.Mask)) && !serviceCIDR.Contains(ac.cidrs.clusterCIDR.IP.Mask(serviceCIDR.Mask)) {
		return
	}

	if err := ac.cidrs.occupy(serviceCIDR); err != nil {
		glog.Errorf("Error filtering out service cidr %v: %v", serviceCIDR, err)
	}
}

func (ac *CIDRAllocationController) filterOutAlreadyAllocated() {
	nodeList, err := ac.nodeLister.List()
	if err != nil {
		// This will actually NEVER happen
		glog.Errorf("Failed to list all nodes, cannot proceed without updating CIDR map")
	}

	for _, node := range nodeList.Items {
		if node.Spec.PodCIDR == "" {
			glog.Infof("Node %v has no CIDR, ignoring", node.Name)
			continue
		} else {
			glog.Infof("Node %v has CIDR %s, occupying it in CIDR map", node.Name, node.Spec.PodCIDR)
		}

		_, podCIDR, err := net.ParseCIDR(node.Spec.PodCIDR)
		if err != nil {
			glog.Errorf("failed to parse node %s, CIDR %s", node.Name, node.Spec.PodCIDR)
			continue
		}

		if err := ac.cidrs.occupy(podCIDR); err != nil {
			// This will happen if:
			// 1. We find garbage in the podCIDR field. Retrying is useless.
			// 2. CIDR out of range: This means a node CIDR has changed.
			glog.Errorf("Failed to mard node %v cidr as occupied", node)
		}
	}
}

// AllocateOrOccupyCIDR looks at the given node, assigns it a valid CIDR
// if it doesn't currently have one or mark the CIDR as used if the node already have one.
func (r *CIDRAllocationController) AllocateOrOccupyCIDR(obj interface{}) {
	key, err := controller.KeyFunc(obj)
	if err != nil {
		utilruntime.HandleError(fmt.Errorf("Couldn't get key for object %+v: %v", obj, err))
		return
	}

	node := obj.(*v1.Node)

	if node.Spec.PodCIDR != "" {
		if err := r.occupyCIDR(node); err == nil {
			return
		}
		// failed to occupy cidr, it's because cidr is invalid, we should reallocate one fot it
	}

	r.queue.Add(key)
}

// ReleaseCIDR releases the CIDR of the removed node
func (r *CIDRAllocationController) ReleaseCIDR(obj interface{}) {
	node, isNode := obj.(*v1.Node)
	// We can get DeletedFinalStateUnknown instead of *v1.Node here and we need to handle that correctly. #34692
	if !isNode {
		deletedState, ok := obj.(cache.DeletedFinalStateUnknown)
		if !ok {
			glog.Errorf("Received unexpected object: %v", obj)
			return
		}
		node, ok = deletedState.Obj.(*v1.Node)
		if !ok {
			glog.Errorf("DeletedFinalStateUnknown contained non-Node object: %v", deletedState.Obj)
			return
		}
	}

	if node == nil || node.Spec.PodCIDR == "" {
		return
	}
	_, podCIDR, err := net.ParseCIDR(node.Spec.PodCIDR)
	if err != nil {
		glog.Errorf("Failed to parse CIDR %s on Node %v: %v", node.Spec.PodCIDR, node.Name, err)
	}

	glog.V(4).Infof("release CIDR %s", node.Spec.PodCIDR)
	if err = r.cidrs.release(podCIDR); err != nil {
		glog.Errorf("Error when releasing CIDR %v: %v", node.Spec.PodCIDR, err)
	}
	return
}

func (r *CIDRAllocationController) occupyCIDR(node *v1.Node) error {
	if node.Spec.PodCIDR == "" {
		return nil
	}
	_, podCIDR, err := net.ParseCIDR(node.Spec.PodCIDR)
	if err != nil {
		return fmt.Errorf("failed to parse node %s, CIDR %s", node.Name, node.Spec.PodCIDR)
	}
	return r.cidrs.occupy(podCIDR)
}

// worker runs a worker thread that just dequeues items, processes them, and marks them done.
// It enforces that the syncHandler is never invoked concurrently with the same key.
func (ac *CIDRAllocationController) worker() {
	for ac.processNextWorkItem() {
	}
}

func (ac *CIDRAllocationController) processNextWorkItem() bool {
	key, quit := ac.queue.Get()
	if quit {
		return false
	}
	defer ac.queue.Done(key)

	err := ac.syncHandler(key.(string))
	if err == nil {
		ac.queue.Forget(key)
		return true
	}

	utilruntime.HandleError(fmt.Errorf("Sync %q failed with %v", key, err))
	ac.queue.AddRateLimited(key)

	return true
}

func (ac *CIDRAllocationController) syncNode(key string) error {
	obj, exists, err := ac.nodeLister.Store.GetByKey(key)
	if !exists {
		glog.V(4).Infof("Node has been deleted %v", key)
		return nil
	}
	if err != nil {
		return err
	}
	node := *obj.(*v1.Node)

	if node.Spec.PodCIDR != "" {
		return nil
	}

	cidr, err := ac.cidrs.allocateNext()
	if err != nil {
		return err
	}

	return ac.updateCIDRAllocation(node.Name, cidr)
}

// Assigns CIDR to Node and sends an update to the API server.
func (r *CIDRAllocationController) updateCIDRAllocation(nodeName string, cidr *net.IPNet) error {
	var err error
	var node *v1.Node

	for rep := 0; rep < podCIDRUpdateRetry; rep++ {
		// TODO: change it to using PATCH instead of full Node updates.
		node, err = r.kubeClient.Core().Nodes().Get(nodeName)
		if err != nil {
			glog.Errorf("Failed while getting node %v to retry updating Node.Spec.PodCIDR: %v", nodeName, err)
			continue
		}
		if node.Spec.PodCIDR != "" {
			glog.Errorf("Node %v already has allocated CIDR %v. Releasing assigned one if different.", node.Name, node.Spec.PodCIDR)
			if node.Spec.PodCIDR != cidr.String() {
				if err := r.cidrs.release(cidr); err != nil {
					glog.Errorf("Error when releasing CIDR %v", cidr.String())
				}
			}
			return nil
		}
		node.Spec.PodCIDR = cidr.String()
		if _, err := r.kubeClient.Core().Nodes().Update(node); err != nil {
			glog.Errorf("Failed while updating Node.Spec.PodCIDR (%d retries left): %v", podCIDRUpdateRetry-rep-1, err)
		} else {
			break
		}
	}
	if err != nil {
		recordNodeStatusChange(r.recorder, node, "CIDRAssignmentFailed")
		// We accept the fact that we may leek CIDRs here. This is safer than releasing
		// them in case when we don't know if request went through.
		// NodeController restart will return all falsely allocated CIDRs to the pool.
		if !errors.IsServerTimeout(err) {
			glog.Errorf("CIDR assignment for node %v failed: %v. Releasing allocated CIDR", nodeName, err)
			if releaseErr := r.cidrs.release(cidr); releaseErr != nil {
				glog.Errorf("Error releasing allocated CIDR for node %v: %v", nodeName, releaseErr)
			}
		}
	}
	return err
}

func recordNodeStatusChange(recorder record.EventRecorder, node *v1.Node, new_status string) {
	ref := &v1.ObjectReference{
		Kind:      "Node",
		Name:      node.Name,
		UID:       node.UID,
		Namespace: "",
	}
	glog.V(2).Infof("Recording status change %s event message for node %s", new_status, node.Name)
	// TODO: This requires a transaction, either both node status is updated
	// and event is recorded or neither should happen, see issue #6055.
	recorder.Eventf(ref, v1.EventTypeNormal, new_status, "Node %s status is now: %s", node.Name, new_status)
}
