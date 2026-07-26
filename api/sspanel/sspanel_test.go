package sspanel_test

import (
	"encoding/json"
	"fmt"
	"testing"

	"github.com/XrayR-project/XrayR/api"
	"github.com/XrayR-project/XrayR/api/sspanel"
)

func CreateClient() api.API {
	apiConfig := &api.Config{
		APIHost:  "http://127.0.0.1:667",
		Key:      "123",
		NodeID:   3,
		NodeType: "V2ray",
	}
	client := sspanel.New(apiConfig)
	return client
}

func TestGetV2rayNodeInfo(t *testing.T) {
	client := CreateClient()

	nodeInfo, err := client.GetNodeInfo()
	if err != nil {
		t.Error(err)
	}
	t.Log(nodeInfo)
}

func TestGetSSNodeInfo(t *testing.T) {
	apiConfig := &api.Config{
		APIHost:  "http://127.0.0.1:667",
		Key:      "123",
		NodeID:   64,
		NodeType: "Shadowsocks",
	}
	client := sspanel.New(apiConfig)
	nodeInfo, err := client.GetNodeInfo()
	if err != nil {
		t.Error(err)
	}
	t.Log(nodeInfo)
}

func TestGetTrojanNodeInfo(t *testing.T) {
	apiConfig := &api.Config{
		APIHost:  "http://127.0.0.1:667",
		Key:      "123",
		NodeID:   72,
		NodeType: "Trojan",
	}
	client := sspanel.New(apiConfig)
	nodeInfo, err := client.GetNodeInfo()
	if err != nil {
		t.Error(err)
	}
	t.Log(nodeInfo)
}

func TestGetSSInfo(t *testing.T) {
	client := CreateClient()

	nodeInfo, err := client.GetNodeInfo()
	if err != nil {
		t.Error(err)
	}
	t.Log(nodeInfo)
}

func TestGetUserList(t *testing.T) {
	client := CreateClient()

	userList, err := client.GetUserList()
	if err != nil {
		t.Error(err)
	}

	t.Log(userList)
}

func TestReportNodeStatus(t *testing.T) {
	client := CreateClient()
	nodeStatus := &api.NodeStatus{
		CPU: 1, Mem: 1, Disk: 1, Uptime: 256,
	}
	err := client.ReportNodeStatus(nodeStatus)
	if err != nil {
		t.Error(err)
	}
}

func TestReportReportNodeOnlineUsers(t *testing.T) {
	client := CreateClient()
	userList, err := client.GetUserList()
	if err != nil {
		t.Error(err)
	}

	onlineUserList := make([]api.OnlineUser, len(*userList))
	for i, userInfo := range *userList {
		onlineUserList[i] = api.OnlineUser{
			UID: userInfo.UID,
			IP:  fmt.Sprintf("1.1.1.%d", i),
		}
	}
	// client.Debug()
	err = client.ReportNodeOnlineUsers(&onlineUserList)
	if err != nil {
		t.Error(err)
	}
}

func TestReportReportUserTraffic(t *testing.T) {
	client := CreateClient()
	userList, err := client.GetUserList()
	if err != nil {
		t.Error(err)
	}
	generalUserTraffic := make([]api.UserTraffic, len(*userList))
	for i, userInfo := range *userList {
		generalUserTraffic[i] = api.UserTraffic{
			UID:      userInfo.UID,
			Upload:   114514,
			Download: 114514,
		}
	}
	// client.Debug()
	err = client.ReportUserTraffic(&generalUserTraffic)
	if err != nil {
		t.Error(err)
	}
}

func TestGetNodeRule(t *testing.T) {
	client := CreateClient()

	ruleList, err := client.GetNodeRule()
	if err != nil {
		t.Error(err)
	}

	t.Log(ruleList)
}

func TestReportIllegal(t *testing.T) {
	client := CreateClient()

	detectResult := []api.DetectResult{
		{UID: 1, RuleID: 2},
		{UID: 1, RuleID: 3},
	}
	client.Debug()
	err := client.ReportIllegal(&detectResult)
	if err != nil {
		t.Error(err)
	}
}

func TestParseV2rayNodeResponseShortServerString(t *testing.T) {
	client := sspanel.New(&api.Config{
		APIHost:  "http://127.0.0.1:667",
		Key:      "123",
		NodeID:   1,
		NodeType: "V2ray",
	})

	_, err := client.ParseV2rayNodeResponse(&sspanel.NodeInfoResponse{
		RawServerString: "vn1.co2.vn",
	})
	if err == nil {
		t.Fatal("expected error for short legacy server string, got nil")
	}
	t.Log(err)
}

func TestParseV2rayNodeResponseValidLegacy(t *testing.T) {
	client := sspanel.New(&api.Config{
		APIHost:  "http://127.0.0.1:667",
		Key:      "123",
		NodeID:   1,
		NodeType: "V2ray",
	})

	nodeInfo, err := client.ParseV2rayNodeResponse(&sspanel.NodeInfoResponse{
		RawServerString: "vn1.co2.vn;443;0;ws;tls;path=/v2|host=vn1.co2.vn",
		SpeedLimit:      100,
	})
	if err != nil {
		t.Fatal(err)
	}
	if nodeInfo.Port != 443 {
		t.Fatalf("port=%d want 443", nodeInfo.Port)
	}
	if nodeInfo.TransportProtocol != "ws" {
		t.Fatalf("transport=%s want ws", nodeInfo.TransportProtocol)
	}
	if !nodeInfo.EnableTLS {
		t.Fatal("expected EnableTLS=true")
	}
}

func TestParseSSPanelNodeInfoReality(t *testing.T) {
	client := sspanel.New(&api.Config{
		APIHost:  "http://127.0.0.1:667",
		Key:      "123",
		NodeID:   1,
		NodeType: "V2ray",
	})

	custom := []byte(`{
		"offset_port_node": "443",
		"host": "www.amazon.com",
		"network": "tcp",
		"security": "reality",
		"enable_vless": "1",
		"flow": "xtls-rprx-vision",
		"enable_reality": true,
		"reality-opts": {
			"dest": "www.amazon.com:443",
			"server_names": ["www.amazon.com"],
			"private_key": "test-key",
			"short_ids": ["", "0123456789abcdef"]
		}
	}`)

	nodeInfo, err := client.ParseSSPanelNodeInfo(&sspanel.NodeInfoResponse{
		CustomConfig: custom,
		SpeedLimit:   100,
		Version:      "2022.1",
	})
	if err != nil {
		t.Fatal(err)
	}
	if !nodeInfo.EnableVless {
		t.Fatal("expected EnableVless")
	}
	if !nodeInfo.EnableREALITY {
		t.Fatal("expected EnableREALITY")
	}
	if nodeInfo.EnableTLS {
		t.Fatal("REALITY should not force EnableTLS")
	}
	if nodeInfo.Port != 443 {
		t.Fatalf("port=%d want 443", nodeInfo.Port)
	}
}

// DPanel often sends numeric ports and boolean allow_insecure; that used to panic XrayR on Trojan/V2ray start.
func TestParseSSPanelNodeInfoDPanelNumericPort(t *testing.T) {
	client := sspanel.New(&api.Config{
		APIHost:  "http://127.0.0.1:667",
		Key:      "123",
		NodeID:   1,
		NodeType: "Trojan",
	})

	custom := []byte(`{
		"offset_port_user": 443,
		"offset_port_node": 443,
		"network": "tcp",
		"host": "jp3.co2.vn",
		"allow_insecure": false,
		"mux": false,
		"udp": true
	}`)

	nodeInfo, err := client.ParseSSPanelNodeInfo(&sspanel.NodeInfoResponse{
		CustomConfig: custom,
		SpeedLimit:   0,
		Version:      "1.0.0",
		RawServerString: "jp3.co2.vn",
		Type:            "DPanel",
	})
	if err != nil {
		t.Fatal(err)
	}
	if nodeInfo.Port != 443 {
		t.Fatalf("port=%d want 443", nodeInfo.Port)
	}
	if !nodeInfo.EnableTLS {
		t.Fatal("Trojan should EnableTLS")
	}
	if nodeInfo.TransportProtocol != "tcp" {
		t.Fatalf("transport=%s want tcp", nodeInfo.TransportProtocol)
	}
	if nodeInfo.Host != "jp3.co2.vn" {
		t.Fatalf("host=%s want jp3.co2.vn", nodeInfo.Host)
	}
}

func TestParseSSPanelNodeInfoVmessWSNumericPort(t *testing.T) {
	client := sspanel.New(&api.Config{
		APIHost:  "http://127.0.0.1:667",
		Key:      "123",
		NodeID:   3,
		NodeType: "V2ray",
	})

	custom := []byte(`{
		"offset_port_node": 80,
		"network": "ws",
		"security": "none",
		"host": "jp3.co2.vn",
		"path": "/v2ray",
		"allow_insecure": false
	}`)

	nodeInfo, err := client.ParseSSPanelNodeInfo(&sspanel.NodeInfoResponse{
		CustomConfig: custom,
		SpeedLimit:   100,
	})
	if err != nil {
		t.Fatal(err)
	}
	if nodeInfo.Port != 80 {
		t.Fatalf("port=%d want 80", nodeInfo.Port)
	}
	if nodeInfo.TransportProtocol != "ws" {
		t.Fatalf("transport=%s want ws", nodeInfo.TransportProtocol)
	}
	if nodeInfo.EnableTLS {
		t.Fatal("security none should not EnableTLS")
	}
}

func TestFlexStringUnmarshal(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{`"443"`, "443"},
		{`443`, "443"},
		{`443.0`, "443"},
		{`true`, "true"},
		{`false`, "false"},
		{`null`, ""},
	}
	for _, tc := range cases {
		var f sspanel.FlexString
		if err := json.Unmarshal([]byte(tc.in), &f); err != nil {
			t.Fatalf("unmarshal %s: %v", tc.in, err)
		}
		if f.String() != tc.want {
			t.Fatalf("%s -> %q want %q", tc.in, f.String(), tc.want)
		}
	}
}
