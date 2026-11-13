package panel_test

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/XrayR-project/XrayR/api"
	"github.com/XrayR-project/XrayR/common/mylego"
	"github.com/XrayR-project/XrayR/panel"
	"github.com/XrayR-project/XrayR/service/controller"
)

func TestSSPanelTypedConfigStartup(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	listener.Close()
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		var data any
		switch r.URL.Path {
		case "/mod_mu/nodes/2/info":
			data = map[string]any{
				"version": "1.0.0", "server": "example.com", "sort": 0, "node_speedlimit": 0,
				"custom_config": map[string]any{
					"offset_port_user": 0, "offset_port_node": port, "network": "tcp",
					"security": "reality", "flow": "xtls-rprx-vision", "host": "example.com",
					"sni": "example.com", "public_key": "fixture-only", "short_id": "1122334455667788",
					"fingerprint": "chrome", "allow_insecure": false, "enable_vless": true, "enable_reality": true,
				},
			}
		case "/mod_mu/users":
			data = []map[string]any{{"id": 1, "uuid": "eb4799e5-7ea7-4bab-a850-e955cebe095e", "node_speedlimit": 0, "node_iplimit": 0}}
		case "/mod_mu/func/detect_rules":
			data = []any{}
		default:
			t.Errorf("unexpected panel request: %s", r.URL.Path)
			http.NotFound(w, r)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"ret": 1, "data": data})
	}))
	defer server.Close()
	p := panel.New(&panel.Config{
		LogConfig:        &panel.LogConfig{Level: "warning"},
		ConnectionConfig: &panel.ConnectionConfig{Handshake: 8, ConnIdle: 600, UplinkOnly: 3600, DownlinkOnly: 3600, BufferSize: 1024},
		NodesConfig: []*panel.NodesConfig{{
			PanelType: "SSpanel",
			ApiConfig: &api.Config{APIHost: server.URL, NodeID: 2, NodeType: "V2ray", EnableVless: true, VlessFlow: "xtls-rprx-vision", Timeout: 30},
			ControllerConfig: &controller.Config{
				ListenIP: "127.0.0.1", SendIP: "0.0.0.0", UpdatePeriodic: 90,
				EnableREALITY: true,
				REALITYConfigs: &controller.REALITYConfig{
					Dest: "example.com:443", ServerNames: []string{"example.com"},
					PrivateKey: base64.RawURLEncoding.EncodeToString(key.Bytes()), ShortIds: []string{"1122334455667788"},
				},
				CertConfig: &mylego.CertConfig{CertMode: "none"},
			},
		}},
	})
	p.Start()
	defer p.Close()
	if !p.Running || len(p.Service) != 1 {
		t.Fatal("SSpanel node did not start")
	}
	conn, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	conn.Close()
}
