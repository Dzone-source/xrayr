package integration

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	_ "github.com/XrayR-project/XrayR/cmd/distro/all"
	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/core"
)

func TestDeviceProfileEnforcement(t *testing.T) {
	binary := os.Getenv("XRAYR_TEST_BINARY")
	if binary == "" {
		t.Skip("set XRAYR_TEST_BINARY to a built XrayR executable")
	}
	echo, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer echo.Close()
	go func() {
		for {
			c, e := echo.Accept()
			if e != nil {
				return
			}
			go func() { defer c.Close(); io.Copy(c, c) }()
		}
	}()
	probe, _ := net.Listen("tcp", "127.0.0.1:0")
	port := probe.Addr().(*net.TCPAddr).Port
	probe.Close()
	ids := []string{"11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"}
	var mu sync.Mutex
	totals := map[int]int64{}
	allowed := []bool{true, true}
	sawBoth := false
	panel := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		path := r.URL.Path
		var data any = []any{}
		mu.Lock()
		defer mu.Unlock()
		switch path {
		case "/mod_mu/nodes/2/info":
			if r.Method == "POST" {
				w.WriteHeader(405)
				return
			}
			data = map[string]any{"version": "1.0.0", "server": "node.test", "sort": 11, "custom_config": map[string]any{"offset_port_node": port, "network": "tcp", "enable_vless": true, "security": "none"}}
		case "/mod_mu/users":
			if r.URL.Query().Get("device_profiles") != "1" {
				t.Error("node did not announce device capability")
			}
			list := []map[string]any{}
			for i, active := range allowed {
				if active {
					list = append(list, map[string]any{"id": 7, "device_id": i + 1, "uuid": ids[i], "node_iplimit": 0})
				}
			}
			data = list
		case "/mod_mu/users/traffic":
			var report struct {
				Data []struct {
					UID      int   `json:"user_id"`
					DeviceID int   `json:"device_id"`
					Up       int64 `json:"u"`
					Down     int64 `json:"d"`
				}
			}
			json.NewDecoder(r.Body).Decode(&report)
			for _, row := range report.Data {
				if row.UID != 7 || row.DeviceID < 1 || row.DeviceID > 2 {
					t.Error("traffic lost device/account mapping")
				}
				totals[row.DeviceID] += row.Up + row.Down
			}
		case "/mod_mu/users/aliveip":
			var body struct {
				Data []struct {
					UID      int `json:"user_id"`
					DeviceID int `json:"device_id"`
				}
			}
			json.NewDecoder(r.Body).Decode(&body)
			found := map[int]bool{}
			for _, u := range body.Data {
				if u.UID != 7 {
					t.Error("device lost owner mapping")
				}
				found[u.DeviceID] = true
			}
			if found[1] && found[2] {
				sawBoth = true
			}
		}
		json.NewEncoder(w).Encode(map[string]any{"ret": 1, "data": data})
	}))
	defer panel.Close()
	config := fmt.Sprintf(`{"Log":{"Level":"none"},"Nodes":[{"PanelType":"SSpanel","ApiConfig":{"ApiHost":%q,"NodeID":2,"NodeType":"V2ray"},"ControllerConfig":{"ListenIP":"127.0.0.1","UpdatePeriodic":1,"CertConfig":{"CertMode":"none"}}}]}`, panel.URL)
	dir := t.TempDir()
	configPath := filepath.Join(dir, "config.json")
	os.WriteFile(configPath, []byte(config), 0600)
	var output bytes.Buffer
	command := exec.Command(binary, "--config", configPath)
	command.Stdout = &output
	command.Stderr = &output
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		command.Process.Kill()
		command.Wait()
		if t.Failed() {
			t.Log(output.String())
		}
	}()
	for i := 0; i < 100; i++ {
		c, e := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 100*time.Millisecond)
		if e == nil {
			c.Close()
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	clients := make([]*core.Instance, 2)
	connections := make([]net.Conn, 2)
	for i, id := range ids {
		config := fmt.Sprintf(`{"log":{"loglevel":"none"},"outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"127.0.0.1","port":%d,"users":[{"id":%q,"encryption":"none"}]}]},"streamSettings":{"network":"tcp","security":"none"}}]}`, port, id)
		cfg, e := core.LoadConfig("json", strings.NewReader(config))
		if e != nil {
			t.Fatal(e)
		}
		client, e := core.New(cfg)
		if e != nil {
			t.Fatal(e)
		}
		clients[i] = client
		defer client.Close()
		if e = client.Start(); e != nil {
			t.Fatal(e)
		}
		c, e := core.Dial(context.Background(), client, xnet.TCPDestination(xnet.ParseAddress("127.0.0.1"), xnet.Port(echo.Addr().(*net.TCPAddr).Port)))
		if e != nil {
			t.Fatal(e)
		}
		connections[i] = c
		defer c.Close()
		if !ping(c) {
			t.Fatalf("device %d could not connect", i+1)
		}
	}
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		mu.Lock()
		both := sawBoth
		mu.Unlock()
		if both {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	mu.Lock()
	both := sawBoth
	allowed[0] = false
	mu.Unlock()
	if !both {
		t.Fatal("active devices sharing one IP were not both reported")
	}
	if !waitClosed(connections[0]) {
		t.Fatal("revoked device stream remained online")
	}
	if !ping(connections[1]) {
		t.Fatal("revoking one profile cut the other profile")
	}
	payload := bytes.Repeat([]byte("profile-two-payload"), 8192)
	connections[1].SetDeadline(time.Now().Add(3 * time.Second))
	if _, err = connections[1].Write(payload); err != nil {
		t.Fatal(err)
	}
	received := make([]byte, len(payload))
	if _, err = io.ReadFull(connections[1], received); err != nil || !bytes.Equal(received, payload) {
		t.Fatal("remaining profile failed payload transfer")
	}
	mu.Lock()
	allowed[1] = false
	mu.Unlock()
	if !waitClosed(connections[1]) {
		t.Fatal("account-wide revocation left a stream online")
	}
	deadline = time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		mu.Lock()
		total := totals[2]
		mu.Unlock()
		if total >= int64(2*len(payload)) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("final traffic for revoked profile was not reported to its account")
}
func ping(c net.Conn) bool {
	c.SetDeadline(time.Now().Add(500 * time.Millisecond))
	if _, e := c.Write([]byte("p")); e != nil {
		return false
	}
	var b [1]byte
	_, e := io.ReadFull(c, b[:])
	return e == nil && b[0] == 'p'
}
func waitClosed(c net.Conn) bool {
	deadline := time.Now().Add(6 * time.Second)
	for time.Now().Before(deadline) {
		if !ping(c) {
			return true
		}
		time.Sleep(100 * time.Millisecond)
	}
	return false
}
