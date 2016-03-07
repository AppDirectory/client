// Auto-generated by avdl-compiler v1.1.1 (https://github.com/keybase/node-avdl-compiler)
//   Input file: avdl/update_common.avdl

package keybase1

import (
	rpc "github.com/keybase/go-framed-msgpack-rpc"
)

type Asset struct {
	Name      string `codec:"name" json:"name"`
	Url       string `codec:"url" json:"url"`
	Digest    string `codec:"digest" json:"digest"`
	Signature string `codec:"signature" json:"signature"`
	LocalPath string `codec:"localPath" json:"localPath"`
}

type UpdateType int

const (
	UpdateType_NORMAL   UpdateType = 0
	UpdateType_BUGFIX   UpdateType = 1
	UpdateType_CRITICAL UpdateType = 2
)

type Update struct {
	Version      string     `codec:"version" json:"version"`
	Name         string     `codec:"name" json:"name"`
	Description  string     `codec:"description" json:"description"`
	Instructions *string    `codec:"instructions,omitempty" json:"instructions,omitempty"`
	Type         UpdateType `codec:"type" json:"type"`
	PublishedAt  *Time      `codec:"publishedAt,omitempty" json:"publishedAt,omitempty"`
	Asset        *Asset     `codec:"asset,omitempty" json:"asset,omitempty"`
}

type UpdateCommonInterface interface {
}

func UpdateCommonProtocol(i UpdateCommonInterface) rpc.Protocol {
	return rpc.Protocol{
		Name:    "keybase.1.updateCommon",
		Methods: map[string]rpc.ServeHandlerDescription{},
	}
}

type UpdateCommonClient struct {
	Cli rpc.GenericClient
}
