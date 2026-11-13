package controller

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"testing"

	"github.com/XrayR-project/XrayR/api"
	"github.com/XrayR-project/XrayR/common/mylego"
	"github.com/xtls/xray-core/app/proxyman"
	"github.com/xtls/xray-core/proxy/vless"
)

func TestVlessVisionReality(t *testing.T) {
	// Generate a disposable key: no deployment keys or panel credentials.
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	config := &Config{
		ListenIP: "127.0.0.1", EnableREALITY: true,
		REALITYConfigs: &REALITYConfig{
			Dest: "example.com:443", ServerNames: []string{"example.com"},
			PrivateKey: base64.RawURLEncoding.EncodeToString(key.Bytes()),
			ShortIds:   []string{"1122334455667788"},
		},
		CertConfig: &mylego.CertConfig{CertMode: "none"},
	}
	node := &api.NodeInfo{
		NodeType: "V2ray", EnableVless: true, VlessFlow: "xtls-rprx-vision",
		Port: 10443, TransportProtocol: "tcp",
	}
	inbound, err := InboundBuilder(config, node, "test-reality")
	if err != nil {
		t.Fatal(err)
	}
	receiver, err := inbound.ReceiverSettings.GetInstance()
	if err != nil {
		t.Fatal(err)
	}
	stream := receiver.(*proxyman.ReceiverConfig).StreamSettings
	if stream.SecurityType != "xray.transport.internet.reality.Config" {
		t.Fatalf("unexpected transport security: %s", stream.SecurityType)
	}
	c := &Controller{nodeInfo: node, Tag: "test-reality"}
	users := []api.UserInfo{{UID: 1, Email: "test", UUID: "eb4799e5-7ea7-4bab-a850-e955cebe095e"}}
	accounts := c.buildVlessUser(&users)
	account, err := accounts[0].Account.GetInstance()
	if err != nil {
		t.Fatal(err)
	}
	if account.(*vless.Account).Flow != "xtls-rprx-vision" {
		t.Fatal("Vision flow was not preserved")
	}
}
