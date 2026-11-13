package limiter

import (
	"fmt"
	"sync"
	"testing"

	"github.com/XrayR-project/XrayR/api"
)

func testLimiter(tb testing.TB, speed uint64, devices int) (*Limiter, string) {
	tb.Helper()
	l := New()
	users := []api.UserInfo{{UID: 1, Email: "user", SpeedLimit: speed, DeviceLimit: devices}}
	if err := l.AddInboundLimiter("node", 0, &users, nil); err != nil {
		tb.Fatal(err)
	}
	return l, "node|user|1"
}

func TestUserBucketReuse(t *testing.T) {
	l, email := testLimiter(t, 1024, 1)
	first, limited, rejected := l.GetUserBucket("node", email, "127.0.0.1")
	if first == nil || !limited || rejected {
		t.Fatal("first connection should have a speed limiter")
	}
	second, limited, rejected := l.GetUserBucket("node", email, "127.0.0.1")
	if second != first || !limited || rejected {
		t.Fatal("connections must share the user's token bucket")
	}
	if _, _, rejected := l.GetUserBucket("node", email, "127.0.0.2"); !rejected {
		t.Fatal("device limit must still reject a second IP")
	}
	users := []api.UserInfo{{UID: 1, Email: "user", SpeedLimit: 2048, DeviceLimit: 1}}
	if err := l.UpdateInboundLimiter("node", &users); err != nil {
		t.Fatal(err)
	}
	if first.Limit() != 2048 || first.Burst() != 2048 {
		t.Fatal("existing bucket must receive speed updates")
	}
	users[0].SpeedLimit = 0
	if err := l.UpdateInboundLimiter("node", &users); err != nil {
		t.Fatal(err)
	}
	if bucket, limited, rejected := l.GetUserBucket("node", email, "127.0.0.1"); bucket != nil || limited || rejected {
		t.Fatal("removing the speed limit must remove the cached bucket")
	}
}

func TestOnlineDeviceReporting(t *testing.T) {
	l, email := testLimiter(t, 1024, 1)
	l.GetUserBucket("node", email, "127.0.0.1")
	l.GetUserBucket("node", email, "127.0.0.1")
	online, err := l.GetOnlineDevice("node")
	if err != nil || len(*online) != 1 || (*online)[0].UID != 1 || (*online)[0].IP != "127.0.0.1" {
		t.Fatalf("wrong online report: %v, %v", online, err)
	}
	if _, _, rejected := l.GetUserBucket("node", email, "127.0.0.2"); rejected {
		t.Fatal("IP tracking must reset for the next reporting interval")
	}
}

func TestConcurrentUserBucket(t *testing.T) {
	l, email := testLimiter(t, 1024, 0)
	var wg sync.WaitGroup
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			for j := 0; j < 100; j++ {
				bucket, limited, rejected := l.GetUserBucket("node", email, fmt.Sprintf("127.0.0.%d", i))
				if bucket == nil || !limited || rejected {
					t.Error("unlimited devices should be accepted")
				}
			}
		}(i)
	}
	wg.Wait()
}

func TestDeleteUserLimiter(t *testing.T) {
	l, email := testLimiter(t, 1024, 1)
	l.GetUserBucket("node", email, "127.0.0.1")
	l.DeleteUserLimiter("node", email)
	value, _ := l.InboundInfo.Load("node")
	info := value.(*InboundInfo)
	for name, state := range map[string]*sync.Map{
		"users": info.UserInfo, "buckets": info.BucketHub, "online IPs": info.UserOnlineIP,
	} {
		if _, exists := state.Load(email); exists {
			t.Errorf("deleted user retained in %s", name)
		}
	}
	// Re-adding a user must not reuse the deleted user's device restriction.
	users := []api.UserInfo{{UID: 1, Email: "user", SpeedLimit: 2048, DeviceLimit: 1}}
	if err := l.UpdateInboundLimiter("node", &users); err != nil {
		t.Fatal(err)
	}
	if bucket, _, rejected := l.GetUserBucket("node", email, "127.0.0.2"); rejected || bucket.Limit() != 2048 {
		t.Fatal("re-added user must start with fresh state")
	}
}

func BenchmarkUserBucket(b *testing.B) {
	for _, speed := range []uint64{0, 1024 * 1024} {
		b.Run(fmt.Sprintf("speed=%d", speed), func(b *testing.B) {
			l, email := testLimiter(b, speed, 0)
			l.GetUserBucket("node", email, "127.0.0.1")
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				l.GetUserBucket("node", email, "127.0.0.1")
			}
		})
	}
}
