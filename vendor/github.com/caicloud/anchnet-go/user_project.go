// Copyright 2015 anchnet-go authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package anchnet

// Implements anchnet user project related APIs

//
// CreateUserProject creates a user project under anchnet account.
//
type CreateUserProjectRequest struct {
	RequestCommon `json:",inline"`
	LoginID       string `json:"loginId,omitempty"`
	Sex           string `json:"sex,omitempty"`
	ProjectName   string `json:"project_name,omitempty"`
	Email         string `json:"email,omitempty"`
	ContactName   string `json:"contactName,omitempty"`
	Mobile        string `json:"mobile,omitempty"`
	LoginPasswd   string `json:"loginPasswd,omitempty"`
}

type CreateUserProjectResponse struct {
	ResponseCommon `json:",inline"`
	ApiID          string `json:"api_id,omitempty"`
	JobID          string `json:"job_id,omitempty"`
}

//
// DescribeProjects returns the information of a project
//
type DescribeProjectsRequest struct {
	RequestCommon `json:",inline"`
	Projects      string `json:"projects,omitempty"`
	SearchWord    string `json:"search_word,omitempty"`
}

type DescribeProjectsResponse struct {
	ResponseCommon `json:",inline"`
	ItemSet        []DescribeProjectsItem `json:"item_set,omitempty"`
}

type DescribeProjectsItem struct {
	ProjectType string `json:"project_type,omitempty"`
	ProjectID   string `json:"project_id,omitempty"`
	ProjectName string `json:"project_name,omitempty"`
	// NOTE: This is internal ID used in anchnet, which is used to transfer money; this
	// ID is a number. Not to be confused with UserID below in DescribeUsers, which is
	// also a user ID, but public ID, in the format of "user-xxxxxx". This ID is used to
	// share image.
	UserID  int                     `json:"userid,omitempty"`
	Status  string                  `json:"status,omitempty"`
	Balance DescribeProjectsBalance `json:"balance,omitempty"`
}

type DescribeProjectsBalance struct {
	Value   string  `json:"value,omitempty"`
	Coupon  string  `json:"coupon,omitempty"`
	Consume float64 `json:"consume,omitempty"`
}

//
// Transfer transfers money to sub account
//
type TransferRequest struct {
	RequestCommon `json:",inline"`
	// NOTE: This is internal ID used in anchnet, which is used to transfer money; this
	// ID is a number. Not to be confused with UserID below in DescribeUsers, which is
	// also a user ID, but public ID, in the format of "user-xxxxxx". This ID is used to
	// share image.
	UserID int    `json:"userId,omitempty"`
	Value  string `json:"value,omitempty"`
	Why    string `json:"why,omitempty"`
}

type TransferResponse struct {
	ResponseCommon `json:",inline"`
}

//
// DescribeUsersRequest describes users (sub-accounts) of a main account.
//
type DescribeUsersRequest struct {
	RequestCommon `json:",inline"`
	// Use 'sub' for sub-accounts.
	Type       string `json:"type,omitempty"`
	SearchWord string `json:"search_word,omitempty"`
}

type DescribeUsersResponse struct {
	ResponseCommon `json:",inline"`
	ItemSet        []DescribeUsersItem `json:"item_set,omitempty"`
	TotalCount     int                 `json:"total_count,omitempty"`
}

type DescribeUsersItem struct {
	LoginID       string `json:"loginid,omitempty"`
	ParentAccount string `json:"parent_account,omitempty"`
	Username      string `json:"username,omitempty"`
	UserID        string `json:"usr_id,omitmpty"`
}

type GetChargeSummaryRequest struct {
	RequestCommon `json:",inline"`
}

type GetChargeSummaryResponse struct {
	ResponseCommon `json:",inline"`
	TotalSum       string                 `json:"total_sum,omitempty"`
	ItemSet        []GetChargeSummaryItem `json:"item_set,omitempty"`
}

type GetChargeSummaryItem struct {
	ResourceType  string `json:"resource_type,omitempty"`
	ResourceCount int    `json:"resource_count,omitempty"`
	TotalSum      string `json:"total_sum,omitempty"`
}
