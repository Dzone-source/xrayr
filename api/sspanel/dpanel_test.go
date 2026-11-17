package sspanel

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/XrayR-project/XrayR/api"
)

func TestDPanelCustomConfig(t *testing.T) {
	for _, version := range []string{"1.0.0", "2023.2"} {
		t.Run(version, func(t *testing.T) {
			fixture := `{"ret":1,"data":{"version":"` + version + `","server":"node.test","sort":11,"type":"V2ray","node_speedlimit":0,"custom_config":{"offset_port_user":443,"offset_port_node":443,"network":"tcp","security":"reality","flow":"xtls-rprx-vision","host":"node.test","sni":"example.com","short_id":"abcd","fingerprint":"chrome","allow_insecure":false,"enable_vless":true,"enable_reality":true}}}`
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/mod_mu/nodes/2/info" {
					t.Error("unexpected path")
				}
				w.Header().Set("Content-Type", "application/json")
				w.Write([]byte(fixture))
			}))
			defer server.Close()
			client := New(&api.Config{APIHost: server.URL, Key: "fixture-only", NodeID: 2, NodeType: "V2ray"})
			node, err := client.GetNodeInfo()
			if err != nil {
				t.Fatal(err)
			}
			if node.Port != 443 || !node.EnableVless || !node.EnableREALITY || node.TransportProtocol != "tcp" || node.VlessFlow != "xtls-rprx-vision" {
				t.Fatalf("incorrect node: %+v", node)
			}
			// Explicit legacy override must still be respected, and return a format error safely.
			client.DisableCustomConfig = true
			if _, err = client.GetNodeInfo(); err == nil || !strings.Contains(err.Error(), "semicolon-separated") {
				t.Fatalf("legacy override not respected: %v", err)
			}
		})
	}
}

func TestDPanelScalarCompatibility(t *testing.T) {
	for _, config := range []string{
		`{"offset_port_node":"443","enable_vless":"1","allow_insecure":"0","enable_reality":true}`,
		`{"offset_port_node":443,"enable_vless":true,"allow_insecure":false,"enable_reality":true}`,
		`{"offset_port_node":443,"enable_vless":1,"allow_insecure":0,"enable_reality":true}`,
	} {
		var decoded CustomConfig
		if err := json.Unmarshal([]byte(config), &decoded); err != nil {
			t.Fatal(err)
		}
		if decoded.OffsetPortNode != "443" || decoded.EnableVless != "1" || decoded.AllowInsecure != "0" {
			t.Fatalf("unexpected config: %+v", decoded)
		}
	}
	client := &APIClient{NodeType: "V2ray"}
	for _, port := range []string{`0`, `65536`, `-1`, `1.5`, `true`, `{}`} {
		if _, err := client.ParseSSPanelNodeInfo(&NodeInfoResponse{CustomConfig: json.RawMessage(`{"offset_port_node":` + port + `}`)}); err == nil {
			t.Fatalf("accepted invalid port %s", port)
		}
	}
}

func TestDPanelUnsupportedStatusPost(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Error("expected POST")
		}
		calls++
		w.WriteHeader(http.StatusMethodNotAllowed)
	}))
	defer server.Close()
	client := New(&api.Config{APIHost: server.URL, NodeID: 2})
	client.version = "1.0.0"
	for i := 0; i < 2; i++ {
		if err := client.ReportNodeStatus(&api.NodeStatus{}); err != nil {
			t.Fatal(err)
		}
	}
	if calls != 1 {
		t.Fatalf("repeated unsupported status reports: %d", calls)
	}
}

func TestDPanelLegacyFallback(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"ret":1,"data":{"version":"2020.1","server":"node.test;443;0;ws;tls;path=/proxy","custom_config":null}}`))
	}))
	defer server.Close()
	client := New(&api.Config{APIHost: server.URL, NodeID: 2, NodeType: "V2ray"})
	node, err := client.GetNodeInfo()
	if err != nil {
		t.Fatal(err)
	}
	if node.Port != 443 || node.Path != "/proxy" || !node.EnableTLS {
		t.Fatalf("legacy changed: %+v", node)
	}
}

func TestDeviceProfilesKeepOwnerAndDistinctCredentials(t *testing.T) {
	client := New(&api.Config{NodeID: 2, NodeType: "V2ray"})
	list := []UserResponse{{ID: 7, DeviceID: 1, UUID: "uuid-one", DeviceLimit: 1, AliveIP: 9}, {ID: 7, DeviceID: 2, UUID: "uuid-two"}, {ID: 8, UUID: "legacy"}}
	users, err := client.ParseUserListResponse(&list)
	if err != nil {
		t.Fatal(err)
	}
	if len(*users) != 3 {
		t.Fatal("IP counts incorrectly removed device credentials")
	}
	if (*users)[0].UID != 7 || (*users)[1].UID != 7 || (*users)[0].Email == (*users)[1].Email || (*users)[0].DeviceLimit != 0 || (*users)[2].DeviceID != 0 {
		t.Fatalf("invalid device mapping: %+v", users)
	}
}
