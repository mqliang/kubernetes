// Copyright 2015 anchnet-go authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package anchnet

//
// CaptureInstance creates an image from a stopped instance.
//
type CaptureInstanceRequest struct {
	RequestCommon `json:",inline"`
	ImageName     string `json:"image_name,omitempty"`
	Instance      string `json:"instance,omitempty"`
}

type CaptureInstanceResponse struct {
	ResponseCommon `json:",inline"`
	ImageID        string `json:"image_id,omitempty"`
}

//
// GrantImageToUsers allows users to access an image. This is often used to grant
// image from main account to sub-accounts.
//
type GrantImageToUsersRequest struct {
	RequestCommon `json:",inline"`
	ImageID       string   `json:"image,omitempty"`
	UserIDs       []string `json:"users,omitempty"`
}

type GrantImageToUsersResponse struct {
	ResponseCommon `json:",inline"`
}

//
// RevokeImageFromUsers unshares an image from users.
//
type RevokeImageFromUsersRequest struct {
	RequestCommon `json:",inline"`
	// Note, this is a lit of string.
	ImageIDs []string `json:"image,omitempty"`
	UserIDs  []string `json:"users,omitempty"`
}

type RevokeImageFromUsersResponse struct {
	ResponseCommon `json:",inline"`
}

//
// DescribeImageUsers lists all users who have access to an image.
//
type DescribeImageUsersRequest struct {
	RequestCommon `json:",inline"`
	// Note, this is a lit of string.
	ImageIDs []string `json:"image_id,omitempty"`
	Offset   int      `json:"offset,omitempty"`
	Limit    int      `json:"limit,omitempty"`
}

type DescribeImageUsersResponse struct {
	ResponseCommon `json:",inline"`
	UserSet        []DescribeImageUsersItem `json:"user_set,omitempty"`
	TotalCount     int                      `json:"total_count,omitempty"`
}

type DescribeImageUsersItem struct {
	ImageID  string `json:"image_id,omitempty"`
	UserID   string `json:"usr_id,omitempty"`
	Username string `json:"username,omitempty"`
}
