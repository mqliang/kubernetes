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
	"encoding/json"
	"fmt"
	"io"
	"time"

	"github.com/denverdino/aliyungo/common"
	"github.com/denverdino/aliyungo/ecs"
	"github.com/denverdino/aliyungo/slb"
	"github.com/golang/glog"
	"k8s.io/kubernetes/pkg/api"
	"k8s.io/kubernetes/pkg/client/cache"
	"k8s.io/kubernetes/pkg/cloudprovider"
)

const (
	ProviderName = "aliyun"
	// TTL for API call cache.
	cacheTTL = 3 * time.Hour
)

type LoadBalancerOpts struct {
	// internet | intranet, default: internet
	AddressType        slb.AddressType           `json:"addressType"`
	InternetChargeType common.InternetChargeType `json:"internetChargeType"`
	// Bandwidth peak of the public network instance charged per fixed bandwidth.
	// Value:1-1000(in Mbps), default: 1
	Bandwidth int `json:"bandwidth"`
}

type Config struct {
	Global struct {
		AccessKeyID     string `json:"accessKeyID"`
		AccessKeySecret string `json:"accessKeySecret"`
		RegionID        string `json:"regionID"`
		ZoneID          string `json:"zoneID"`
	}
	LoadBalancer LoadBalancerOpts
}

// A single Kubernetes cluster can run in multiple zones,
// but only within the same region (and cloud provider).
type Aliyun struct {
	ecsClient *ecs.Client
	slbClient *slb.Client
	regionID  string
	zoneID    string
	lbOpts    LoadBalancerOpts

	// An address cache used to cache NodeAddresses.
	addressCache cache.Store
	// A constant address cache used to cache NodeAddresses. Ideally, we should
	// just use addressCache above, but if aliyun ecs api is unavailabe
	// while addressCache expires, we'll end up evict all pods. This constant
	// address cache never changes, so in case of such API unavailability, we
	// use this const cache. In all normal cases, the timed address cache will
	// be used.
	constAddressCache map[string][]api.NodeAddress
}

// An entry in addressCache.
type AddressCacheEntry struct {
	name      string
	addresses []api.NodeAddress
}

func init() {
	cloudprovider.RegisterCloudProvider(ProviderName, func(config io.Reader) (cloudprovider.Interface, error) {
		cfg, err := readConfig(config)
		if err != nil {
			return nil, err
		}
		return newAliyun(cfg)
	})
}

func readConfig(config io.Reader) (Config, error) {
	if config == nil {
		err := fmt.Errorf("No cloud provider config given")
		return Config{}, err
	}

	cfg := Config{}
	if err := json.NewDecoder(config).Decode(&cfg); err != nil {
		glog.Errorf("Couldn't parse config: %v", err)
		return Config{}, err
	}

	return cfg, nil
}

// newAliyun returns a new instance of Aliyun cloud provider.
func newAliyun(config Config) (cloudprovider.Interface, error) {
	if config.Global.AccessKeyID == "" || config.Global.AccessKeySecret == "" || config.Global.RegionID == "" || config.Global.ZoneID == "" {
		return nil, fmt.Errorf("Invalid fields in config file")
	}

	ecsClient := ecs.NewClient(config.Global.AccessKeyID, config.Global.AccessKeySecret)
	slbClient := slb.NewClient(config.Global.AccessKeyID, config.Global.AccessKeySecret)

	if config.LoadBalancer.AddressType == "" {
		config.LoadBalancer.AddressType = slb.InternetAddressType
	}

	if config.LoadBalancer.InternetChargeType == "" {
		/* Valid value: paybytraffic|paybybandwidth
		 *  https://help.aliyun.com/document_detail/27577.html?spm=5176.product27537.6.118.R6Bqe6
		 *
		 * aliyun bug:
		 * We cloudn't use common.PayByBandwidth:
		 *     PayByBandwidth = InternetChargeType("PayByBandwidth"))
		 * but InternetChargeType("paybybandwidth")
		 */
		config.LoadBalancer.InternetChargeType = common.InternetChargeType("paybytraffic")
	}

	if config.LoadBalancer.AddressType == slb.InternetAddressType && config.LoadBalancer.InternetChargeType == common.InternetChargeType("paybybandwidth") {
		if config.LoadBalancer.Bandwidth == 0 {
			config.LoadBalancer.Bandwidth = 1
		}

		if config.LoadBalancer.Bandwidth < 1 || config.LoadBalancer.Bandwidth > 1000 {
			return nil, fmt.Errorf("LoadBalancer.Bandwidth '%d' is out of range [1, 1000]", config.LoadBalancer.Bandwidth)
		}
	}

	keyFunc := func(obj interface{}) (string, error) {
		entry, ok := obj.(AddressCacheEntry)
		if !ok {
			return "", cache.KeyError{Obj: obj, Err: fmt.Errorf("Unable to convert entry object to AddressCacheEntry")}
		}
		return entry.name, nil
	}

	aly := Aliyun{
		ecsClient:         ecsClient,
		slbClient:         slbClient,
		regionID:          config.Global.RegionID,
		zoneID:            config.Global.ZoneID,
		lbOpts:            config.LoadBalancer,
		addressCache:      cache.NewTTLStore(keyFunc, cacheTTL),
		constAddressCache: make(map[string][]api.NodeAddress),
	}

	glog.V(4).Infof("new Aliyun: '%v'", aly)

	return &aly, nil
}

func (aly *Aliyun) LoadBalancer() (cloudprovider.LoadBalancer, bool) {
	glog.V(4).Info("aliyun.LoadBalancer() called")
	return aly, true
}

// Instances returns an implementation of Interface.Instances for Aliyun cloud.
func (aly *Aliyun) Instances() (cloudprovider.Instances, bool) {
	glog.V(4).Info("aliyun.Instances() called")
	return aly, true
}

func (aly *Aliyun) Zones() (cloudprovider.Zones, bool) {
	return aly, true
}

func (aly *Aliyun) Clusters() (cloudprovider.Clusters, bool) {
	glog.V(4).Info("aliyun.Clusters() called")
	return nil, false
}

func (aly *Aliyun) Routes() (cloudprovider.Routes, bool) {
	return nil, false
}

func (aly *Aliyun) ProviderName() string {
	return ProviderName
}

// ScrubDNS filters DNS settings for pods.
func (aly *Aliyun) ScrubDNS(nameservers, searches []string) (nsOut, srchOut []string) {
	return nameservers, searches
}

func (aly *Aliyun) GetZone() (cloudprovider.Zone, error) {
	glog.V(1).Infof("Current zone is %v", aly.regionID)

	return cloudprovider.Zone{
		FailureDomain: aly.zoneID,
		Region:        aly.regionID,
	}, nil
}
