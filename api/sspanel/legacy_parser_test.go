package sspanel

import (
	"strings"
	"testing"
)

func TestLegacyV2rayRejectsTruncatedServer(t *testing.T) {
	client := &APIClient{NodeType: "V2ray", NodeID: 2}
	for _, server := range []string{"", "node.example", "node.example;443", "node.example;443;0", "node.example;443;0;ws", "node.example;443;0;ws;tls"} {
		t.Run(server, func(t *testing.T) {
			if _, err := client.ParseV2rayNodeResponse(&NodeInfoResponse{RawServerString: server}); err == nil {
				t.Fatal("expected a format error")
			}
		})
	}
}

func TestLegacyV2rayOptions(t *testing.T) {
	client := &APIClient{NodeType: "V2ray", NodeID: 2}
	node, err := client.ParseV2rayNodeResponse(&NodeInfoResponse{RawServerString: "node.example;443;0;ws;tls;path=/proxy?token=a=b|host=node.example", SpeedLimit: 8})
	if err != nil {
		t.Fatal(err)
	}
	if node.Port != 443 || node.Path != "/proxy?token=a=b" || node.Host != "node.example" || node.TransportProtocol != "ws" || !node.EnableTLS || node.SpeedLimit != 1000000 {
		t.Fatalf("unexpected parsed node: %+v", node)
	}
	_, err = client.ParseV2rayNodeResponse(&NodeInfoResponse{RawServerString: "node.example;443;0;ws;tls;host"})
	if err == nil || !strings.Contains(err.Error(), "key=value") {
		t.Fatalf("expected invalid option error, got %v", err)
	}
}
