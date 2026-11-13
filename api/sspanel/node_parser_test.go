package sspanel

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/XrayR-project/XrayR/api"
)

func TestLegacyV2rayValidation(t *testing.T) {
	c := &APIClient{NodeType: "V2ray", EnableVless: true, VlessFlow: "xtls-rprx-vision"}
	for _, server := range []string{"", "example.com", "example.com;443", "host;0;0;tcp;;", "host;65536;0;tcp;;", "host;443;0;tcp;;invalid"} {
		t.Run(server, func(t *testing.T) {
			if _, err := c.ParseV2rayNodeResponse(&NodeInfoResponse{RawServerString: server}); err == nil {
				t.Fatal("invalid legacy input must return an error instead of panicking")
			}
		})
	}
	node, err := c.ParseV2rayNodeResponse(&NodeInfoResponse{RawServerString: "example.com;443;0;tcp;;path=/test?token=a=b|host=example.com"})
	if err != nil {
		t.Fatal(err)
	}
	if node.Port != 443 || node.Path != "/test?token=a=b" || node.Host != "example.com" || !node.EnableVless || node.VlessFlow != "xtls-rprx-vision" {
		t.Fatalf("legacy fields were not preserved: %+v", node)
	}
}

func TestNodeFormatSelection(t *testing.T) {
	for _, tc := range []struct {
		name, version, server, custom string
		disable, wantError            bool
		port                          uint32
	}{
		{"missing-version-modern", "", "example.com", `{"offset_port_node":"443","network":"tcp","enable_vless":"1","flow":"xtls-rprx-vision"}`, false, false, 443},
		{"old-version-modern-shape", "2020.1", "example.com", `{"offset_port_node":"443","network":"tcp"}`, false, false, 443},
		{"legacy-kept", "2020.1", "example.com;8443;0;tcp;;", `{"offset_port_node":"443","network":"tcp"}`, false, false, 8443},
		{"modern-version", "2021.11", "example.com", `{"offset_port_node":"443","network":"tcp"}`, false, false, 443},
		{"explicit-legacy-override", "", "example.com", `{"offset_port_node":"443","network":"tcp"}`, true, true, 0},
		{"incomplete-custom", "", "example.com", `{"network":"tcp"}`, false, true, 0},
		{"null-custom", "", "example.com", `null`, false, true, 0},
		{"invalid-port-no-payload-leak", "2021.11", "example.com", `{"offset_port_node":"invalid","network":"tcp","reality-opts":{"private_key":"DO_NOT_LOG_THIS"}}`, false, true, 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/mod_mu/nodes/2/info" {
					t.Errorf("unexpected path %s", r.URL.Path)
				}
				_ = json.NewEncoder(w).Encode(Response{Ret: 1, Data: mustNodeJSON(t, tc.version, tc.server, tc.custom)})
			}))
			defer server.Close()
			c := New(&api.Config{APIHost: server.URL, NodeID: 2, NodeType: "V2ray", DisableCustomConfig: tc.disable})
			node, err := c.GetNodeInfo()
			if tc.wantError {
				if err == nil {
					t.Fatal("expected validation error")
				}
				if strings.Contains(err.Error(), "DO_NOT_LOG_THIS") {
					t.Fatal("node payload leaked in error")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if node.Port != tc.port || node.TransportProtocol != "tcp" {
				t.Fatalf("unexpected node fields: %+v", node)
			}
			if tc.name == "missing-version-modern" && (!node.EnableVless || node.VlessFlow != "xtls-rprx-vision") {
				t.Fatal("modern VLESS Vision settings were not preserved")
			}
		})
	}
}

func mustNodeJSON(t *testing.T, version, server, custom string) json.RawMessage {
	t.Helper()
	data, err := json.Marshal(NodeInfoResponse{Version: version, RawServerString: server, CustomConfig: json.RawMessage(custom)})
	if err != nil {
		t.Fatal(err)
	}
	return data
}
