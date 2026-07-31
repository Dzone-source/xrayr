package controller

import (
	"context"
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/sagernet/sing-shadowsocks/shadowaead_2022"
	C "github.com/sagernet/sing/common"
	"github.com/xtls/xray-core/common/errors"
	"github.com/xtls/xray-core/common/protocol"
	"github.com/xtls/xray-core/common/serial"
	"github.com/xtls/xray-core/infra/conf"
	"github.com/xtls/xray-core/proxy/shadowsocks"
	"github.com/xtls/xray-core/proxy/shadowsocks_2022"
	"github.com/xtls/xray-core/proxy/trojan"
	"github.com/xtls/xray-core/proxy/vless"

	"github.com/XrayR-project/XrayR/api"
)

var AEADMethod = map[shadowsocks.CipherType]uint8{
	shadowsocks.CipherType_AES_128_GCM:        0,
	shadowsocks.CipherType_AES_256_GCM:        0,
	shadowsocks.CipherType_CHACHA20_POLY1305:  0,
	shadowsocks.CipherType_XCHACHA20_POLY1305: 0,
}

func (c *Controller) buildVmessUser(userInfo *[]api.UserInfo) (users []*protocol.User) {
	users = make([]*protocol.User, len(*userInfo))
	for i, user := range *userInfo {
		vmessAccount := &conf.VMessAccount{
			ID:       user.UUID,
			Security: "auto",
		}
		users[i] = &protocol.User{
			Level:   0,
			Email:   c.buildUserTag(&user), // Email: InboundTag|email|uid
			Account: serial.ToTypedMessage(vmessAccount.Build()),
		}
	}
	return users
}

func (c *Controller) buildVlessUser(userInfo *[]api.UserInfo) (users []*protocol.User) {
	users = make([]*protocol.User, len(*userInfo))
	for i, user := range *userInfo {
		vlessAccount := &vless.Account{
			Id:   user.UUID,
			Flow: c.nodeInfo.VlessFlow,
		}
		users[i] = &protocol.User{
			Level:   0,
			Email:   c.buildUserTag(&user),
			Account: serial.ToTypedMessage(vlessAccount),
		}
	}
	return users
}

func (c *Controller) buildTrojanUser(userInfo *[]api.UserInfo) (users []*protocol.User) {
	users = make([]*protocol.User, 0, len(*userInfo)*2)
	for _, user := range *userInfo {
		// DPanel/SSPanel clients may use UUID or passwd as Trojan password.
		// Register both so "not a valid user" does not happen after sub/format mismatch.
		passwords := make([]string, 0, 2)
		seen := map[string]struct{}{}
		for _, p := range []string{user.UUID, user.Passwd} {
			if p == "" {
				continue
			}
			if _, ok := seen[p]; ok {
				continue
			}
			seen[p] = struct{}{}
			passwords = append(passwords, p)
		}
		if len(passwords) == 0 {
			errors.LogError(context.Background(), "[UID: %d] trojan password empty (uuid and passwd)", user.UID)
			continue
		}
		for i, password := range passwords {
			email := c.buildUserTag(&user)
			if i > 0 {
				email = fmt.Sprintf("%s#p%d", email, i)
			}
			users = append(users, &protocol.User{
				Level: 0,
				Email: email,
				Account: serial.ToTypedMessage(&trojan.Account{
					Password: password,
				}),
			})
		}
	}
	return users
}

func (c *Controller) buildSSUser(userInfo *[]api.UserInfo, method string) (users []*protocol.User) {
	users = make([]*protocol.User, len(*userInfo))

	for i, user := range *userInfo {
		// shadowsocks2022 Key = "openssl rand -base64 32" and multi users needn't cipher method
		if C.Contains(shadowaead_2022.List, strings.ToLower(method)) {
			e := c.buildUserTag(&user)
			userKey, err := c.checkShadowsocksPassword(user.Passwd, method)
			if err != nil {
				errors.LogError(context.Background(), "[UID: %d] %s", user.UID, err)
				continue
			}
			users[i] = &protocol.User{
				Level: 0,
				Email: e,
				Account: serial.ToTypedMessage(&shadowsocks_2022.Account{
					Key:   userKey,
				}),
			}
		} else {
			users[i] = &protocol.User{
				Level: 0,
				Email: c.buildUserTag(&user),
				Account: serial.ToTypedMessage(&shadowsocks.Account{
					Password:   user.Passwd,
					CipherType: cipherFromString(method),
				}),
			}
		}
	}
	return users
}

func (c *Controller) buildSSPluginUser(userInfo *[]api.UserInfo) (users []*protocol.User) {
	users = make([]*protocol.User, len(*userInfo))

	for i, user := range *userInfo {
		// shadowsocks2022 Key = openssl rand -base64 32 and multi users needn't cipher method
		if C.Contains(shadowaead_2022.List, strings.ToLower(user.Method)) {
			e := c.buildUserTag(&user)
			userKey, err := c.checkShadowsocksPassword(user.Passwd, user.Method)
			if err != nil {
				errors.LogError(context.Background(), "[UID: %d] %s", user.UID, err)
				continue
			}
			users[i] = &protocol.User{
				Level: 0,
				Email: e,
				Account: serial.ToTypedMessage(&shadowsocks_2022.Account{
					Key:   userKey,
				}),
			}
		} else {
			// Check if the cypher method is AEAD
			cypherMethod := cipherFromString(user.Method)
			if _, ok := AEADMethod[cypherMethod]; ok {
				users[i] = &protocol.User{
					Level: 0,
					Email: c.buildUserTag(&user),
					Account: serial.ToTypedMessage(&shadowsocks.Account{
						Password:   user.Passwd,
						CipherType: cypherMethod,
					}),
				}
			}
		}
	}
	return users
}

func cipherFromString(c string) shadowsocks.CipherType {
	switch strings.ToLower(c) {
	case "aes-128-gcm", "aead_aes_128_gcm":
		return shadowsocks.CipherType_AES_128_GCM
	case "aes-256-gcm", "aead_aes_256_gcm":
		return shadowsocks.CipherType_AES_256_GCM
	case "chacha20-poly1305", "aead_chacha20_poly1305", "chacha20-ietf-poly1305":
		return shadowsocks.CipherType_CHACHA20_POLY1305
	case "none", "plain":
		return shadowsocks.CipherType_NONE
	default:
		return shadowsocks.CipherType_UNKNOWN
	}
}

func (c *Controller) buildUserTag(user *api.UserInfo) string {
	return fmt.Sprintf("%s|%s|%d", c.Tag, user.Email, user.UID)
}

func (c *Controller) checkShadowsocksPassword(password string, method string) (string, error) {
	if strings.Contains(c.panelType, "V2board") {
		var userKey string
		if len(password) < 16 {
			return "", newError("shadowsocks2022 key's length must be greater than 16").AtWarning()
		}
		if method == "2022-blake3-aes-128-gcm" {
			userKey = password[:16]
		} else {
			if len(password) < 32 {
				return "", newError("shadowsocks2022 key's length must be greater than 32").AtWarning()
			}
			userKey = password[:32]
		}
		return base64.StdEncoding.EncodeToString([]byte(userKey)), nil
	} else {
		return password, nil
	}
}
