package sspanel

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/XrayR-project/XrayR/api"
)

func TestStatus405KeepsOtherReports(t *testing.T) {
	var lock sync.Mutex
	counts := map[string]int{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		k := r.Method + " " + r.URL.Path
		lock.Lock()
		counts[k]++
		lock.Unlock()
		if k == "POST /mod_mu/nodes/2/info" {
			w.Header().Set("Allow", "GET")
			w.WriteHeader(http.StatusMethodNotAllowed)
			_, _ = w.Write([]byte("<html>405 PRIVATE_BODY</html>"))
			return
		}
		w.Header().Set("Content-Type", "application/json")
		if k == "GET /mod_mu/nodes/2/info" {
			_, _ = w.Write([]byte(`{"ret":1,"data":{"version":"1.0.0","server":"example.com","custom_config":{"offset_port_node":443,"network":"tcp","enable_vless":true}}}`))
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"ret": 1, "data": nil})
	}))
	defer server.Close()
	c := New(&api.Config{APIHost: server.URL, NodeID: 2, NodeType: "V2ray"})
	if _, err := c.GetNodeInfo(); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if err := c.ReportNodeStatus(&api.NodeStatus{}); err != nil {
			t.Fatal(err)
		}
	}
	traffic := []api.UserTraffic{{UID: 1, Upload: 100, Download: 200}}
	online := []api.OnlineUser{{UID: 1, IP: "127.0.0.1"}}
	if err := c.ReportUserTraffic(&traffic); err != nil {
		t.Fatal(err)
	}
	if err := c.ReportNodeOnlineUsers(&online); err != nil {
		t.Fatal(err)
	}
	if _, err := c.GetNodeInfo(); err != nil {
		t.Fatal(err)
	}
	lock.Lock()
	defer lock.Unlock()
	for k, want := range map[string]int{
		"POST /mod_mu/nodes/2/info":  1,
		"GET /mod_mu/nodes/2/info":   2,
		"POST /mod_mu/users/traffic": 1,
		"POST /mod_mu/users/aliveip": 1,
	} {
		if counts[k] != want {
			t.Errorf("%s: got %d requests, want %d", k, counts[k], want)
		}
	}
}

func TestStatusErrorsRemainVisible(t *testing.T) {
	for _, status := range []int{400, 401, 403, 500} {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(status)
			_, _ = w.Write([]byte("<html>PRIVATE_BODY</html>"))
		}))
		c := New(&api.Config{APIHost: server.URL, NodeID: 2, NodeType: "V2ray"})
		for i := 0; i < 2; i++ {
			err := c.ReportNodeStatus(&api.NodeStatus{})
			if err == nil || !strings.Contains(err.Error(), "HTTP ") || strings.Contains(err.Error(), "PRIVATE_BODY") || c.statusUnsupported.Load() {
				t.Fatalf("HTTP %d must return a compact error without disabling reporting; got %v", status, err)
			}
		}
		server.Close()
	}
}

func TestNodeGet405StillErrors(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusMethodNotAllowed)
		_, _ = w.Write([]byte("<html>PRIVATE_BODY</html>"))
	}))
	defer server.Close()
	c := New(&api.Config{APIHost: server.URL, NodeID: 2, NodeType: "V2ray"})
	if _, err := c.GetNodeInfo(); err == nil || !strings.Contains(err.Error(), "GET") || strings.Contains(err.Error(), "PRIVATE_BODY") {
		t.Fatalf("GET 405 must remain an error: %v", err)
	}
}
