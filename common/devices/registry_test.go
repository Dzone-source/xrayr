package devices

import (
	"github.com/XrayR-project/XrayR/api"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestRevokeClosesOnlySelectedDevice(t *testing.T) {
	r := New()
	defer r.Close()
	users := []api.UserInfo{{UID: 7, DeviceID: 1, Email: "device:1"}, {UID: 7, DeviceID: 2, Email: "device:2"}}
	r.Refresh("node", users, time.Minute)
	var stopped1, stopped2 atomic.Bool
	done1, ok := r.Begin(key("node", users[0]), "192.0.2.1", func() { stopped1.Store(true) })
	if !ok {
		t.Fatal("denied active device")
	}
	defer done1()
	done2, ok := r.Begin(key("node", users[1]), "192.0.2.1", func() { stopped2.Store(true) })
	if !ok {
		t.Fatal("denied second device sharing IP")
	}
	defer done2()
	if len(r.Snapshot("node")) != 2 {
		t.Fatal("devices behind same IP were merged")
	}
	r.Refresh("node", users[1:], time.Minute)
	if !stopped1.Load() || stopped2.Load() {
		t.Fatal("revocation affected the wrong streams")
	}
	if _, ok = r.Begin(key("node", users[0]), "192.0.2.2", func() {}); ok {
		t.Fatal("stale authenticated credential bypassed revocation")
	}
}
func TestLeaseExpiryAndSuccessfulRefresh(t *testing.T) {
	r := New()
	defer r.Close()
	users := []api.UserInfo{{UID: 3, DeviceID: 9, Email: "device:9"}}
	r.Refresh("node", users, time.Minute)
	var stopped atomic.Bool
	done, ok := r.Begin(key("node", users[0]), "2001:db8::1", func() { stopped.Store(true) })
	if !ok {
		t.Fatal("denied")
	}
	defer done()
	r.Refresh("node", users, 2*time.Minute)
	r.expire(time.Now().Add(time.Minute))
	if stopped.Load() {
		t.Fatal("refresh did not extend lease")
	}
	r.expire(time.Now().Add(3 * time.Minute))
	if !stopped.Load() {
		t.Fatal("expired permission kept stream online")
	}
}
func TestConcurrentStreamsRelease(t *testing.T) {
	r := New()
	defer r.Close()
	u := api.UserInfo{UID: 1, DeviceID: 2, Email: "device:2"}
	r.Refresh("tag", []api.UserInfo{u}, time.Minute)
	var wg sync.WaitGroup
	for i := 0; i < 32; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			done, ok := r.Begin(key("tag", u), "192.0.2.1", func() {})
			if ok {
				r.Snapshot("tag")
				done()
				done()
			}
		}()
	}
	wg.Wait()
	if len(r.Snapshot("tag")) != 0 {
		t.Fatal("completed streams still reported online")
	}
}

func TestLegacyToDeviceCutsSharedCredential(t *testing.T) {
	r := New()
	defer r.Close()
	legacy := api.UserInfo{UID: 7}
	if r.Controls("manual-inbound") {
		t.Fatal("custom inbound should not be controlled")
	}
	r.Refresh("node", []api.UserInfo{legacy}, time.Minute)
	var stopped atomic.Bool
	done, ok := r.Begin(key("node", legacy), "192.0.2.1", func() { stopped.Store(true) })
	if !ok {
		t.Fatal("legacy user denied")
	}
	defer done()
	r.expire(time.Now().Add(24 * time.Hour))
	if stopped.Load() {
		t.Fatal("legacy policy should not expire on control-plane outage")
	}
	r.Refresh("node", []api.UserInfo{{UID: 7, DeviceID: 1, Email: "device:1"}}, time.Minute)
	if !stopped.Load() {
		t.Fatal("enabling device mode left shared UUID online")
	}
}
