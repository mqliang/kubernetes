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

// This is the default algorithm provider for the scheduler.
package defaults

import (
	"os"
	"strconv"

	"k8s.io/kubernetes/pkg/util/sets"
	"k8s.io/kubernetes/plugin/pkg/scheduler"
	"k8s.io/kubernetes/plugin/pkg/scheduler/algorithm"
	"k8s.io/kubernetes/plugin/pkg/scheduler/algorithm/predicates"
	"k8s.io/kubernetes/plugin/pkg/scheduler/algorithm/priorities"
	"k8s.io/kubernetes/plugin/pkg/scheduler/factory"

	"github.com/golang/glog"
)

// Amazon reccomends having no more that 40 volumes attached to an instance,
// and at least one of those is for the system root volume.
const DefaultMaxEBSVolumes = 39

// GCE instances can have up to 16 PD volumes attached.
const DefaultMaxGCEPDVolumes = 16

// getMaxVols checks the max PD volumes environment variable, otherwise returning a default value
func getMaxVols(defaultVal int) int {
	if rawMaxVols := os.Getenv("KUBE_MAX_PD_VOLS"); rawMaxVols != "" {
		if parsedMaxVols, err := strconv.Atoi(rawMaxVols); err != nil {
			glog.Errorf("Unable to parse maxiumum PD volumes value, using default of %v: %v", defaultVal, err)
		} else if parsedMaxVols <= 0 {
			glog.Errorf("Maximum PD volumes must be a positive value, using default of %v", defaultVal)
		} else {
			return parsedMaxVols
		}
	}

	return defaultVal
}

func init() {
	factory.RegisterAlgorithmProvider(factory.DefaultProvider, defaultPredicates(), defaultPriorities())
	// EqualPriority is a prioritizer function that gives an equal weight of one to all nodes
	// Register the priority function so that its available
	// but do not include it as part of the default priorities
	factory.RegisterPriorityFunction("EqualPriority", scheduler.EqualPriority, 1)

	// ServiceSpreadingPriority is a priority config factory that spreads pods by minimizing
	// the number of pods (belonging to the same service) on the same node.
	// Register the factory so that it's available, but do not include it as part of the default priorities
	// Largely replaced by "SelectorSpreadPriority", but registered for backward compatibility with 1.0
	factory.RegisterPriorityConfigFactory(
		"ServiceSpreadingPriority",
		factory.PriorityConfigFactory{
			Function: func(args factory.PluginFactoryArgs) algorithm.PriorityFunction {
				return priorities.NewSelectorSpreadPriority(args.PodLister, args.ServiceLister, algorithm.EmptyControllerLister{}, algorithm.EmptyReplicaSetLister{})
			},
			Weight: 1,
		},
	)
	// PodFitsPorts has been replaced by PodFitsHostPorts for better user understanding.
	// For backwards compatibility with 1.0, PodFitsPorts is regitered as well.
	factory.RegisterFitPredicate("PodFitsPorts", predicates.PodFitsHostPorts)
}

func defaultPredicates() sets.String {
	return sets.NewString(
		// Fit is defined based on the absence of port conflicts.
		factory.RegisterFitPredicate("PodFitsHostPorts", predicates.PodFitsHostPorts),
		// Fit is determined by resource availability.
		factory.RegisterFitPredicateFactory(
			"PodFitsResources",
			func(args factory.PluginFactoryArgs) algorithm.FitPredicate {
				return predicates.NewResourceFitPredicate(args.NodeInfo)
			},
		),
		// Fit is determined by non-conflicting disk volumes.
		factory.RegisterFitPredicate("NoDiskConflict", predicates.NoDiskConflict),
		// Fit is determined by volume zone requirements.
		factory.RegisterFitPredicateFactory(
			"NoVolumeZoneConflict",
			func(args factory.PluginFactoryArgs) algorithm.FitPredicate {
				return predicates.NewVolumeZonePredicate(args.NodeInfo, args.PVInfo, args.PVCInfo)
			},
		),
		// Fit is determined by node selector query.
		factory.RegisterFitPredicateFactory(
			"MatchNodeSelector",
			func(args factory.PluginFactoryArgs) algorithm.FitPredicate {
				return predicates.NewSelectorMatchPredicate(args.NodeInfo)
			},
		),
		// Fit is determined by the presence of the Host parameter and a string match
		factory.RegisterFitPredicate("HostName", predicates.PodFitsHost),

		// Fit is determined by whether or not there would be too many AWS EBS volumes attached to the node
		factory.RegisterFitPredicateFactory(
			"MaxEBSVolumeCount",
			func(args factory.PluginFactoryArgs) algorithm.FitPredicate {
				// TODO: allow for generically parameterized scheduler predicates, because this is a bit ugly
				maxVols := getMaxVols(DefaultMaxEBSVolumes)
				return predicates.NewMaxPDVolumeCountPredicate(predicates.EBSVolumeFilter, maxVols, args.PVInfo, args.PVCInfo)
			},
		),

		// Fit is determined by whether or not there would be too many GCE PD volumes attached to the node
		factory.RegisterFitPredicateFactory(
			"MaxGCEPDVolumeCount",
			func(args factory.PluginFactoryArgs) algorithm.FitPredicate {
				// TODO: allow for generically parameterized scheduler predicates, because this is a bit ugly
				maxVols := getMaxVols(DefaultMaxGCEPDVolumes)
				return predicates.NewMaxPDVolumeCountPredicate(predicates.GCEPDVolumeFilter, maxVols, args.PVInfo, args.PVCInfo)
			},
		),
	)
}

func defaultPriorities() sets.String {
	return sets.NewString(
		// Prioritize nodes by least requested utilization.
		factory.RegisterPriorityFunction("LeastRequestedPriority", priorities.LeastRequestedPriority, 1),
		// Prioritizes nodes to help achieve balanced resource usage
		factory.RegisterPriorityFunction("BalancedResourceAllocation", priorities.BalancedResourceAllocation, 1),
		// spreads pods by minimizing the number of pods (belonging to the same service or replication controller) on the same node.
		factory.RegisterPriorityConfigFactory(
			"SelectorSpreadPriority",
			factory.PriorityConfigFactory{
				Function: func(args factory.PluginFactoryArgs) algorithm.PriorityFunction {
					return priorities.NewSelectorSpreadPriority(args.PodLister, args.ServiceLister, args.ControllerLister, args.ReplicaSetLister)
				},
				Weight: 1,
			},
		),
		factory.RegisterPriorityConfigFactory(
			"NodeAffinityPriority",
			factory.PriorityConfigFactory{
				Function: func(args factory.PluginFactoryArgs) algorithm.PriorityFunction {
					return priorities.NewNodeAffinityPriority(args.NodeLister)
				},
				Weight: 1,
			},
		),
	)
}
