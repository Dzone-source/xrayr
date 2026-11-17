package limiter

import (
	"sync"
	"testing"

	"github.com/XrayR-project/XrayR/api"
)

func TestReuseBucketAndDeviceLimit(t *testing.T) {
	l := New()
	users := []api.UserInfo{{UID: 1, Email: "user", SpeedLimit: 1000, DeviceLimit: 1}}
	if err := l.AddInboundLimiter("test", 0, &users, nil); err != nil {
		t.Fatal(err)
	}
	key := "test|user|1"
	first, limited, rejected := l.GetUserBucket("test", key, "192.0.2.1")
	if first == nil || !limited || rejected {
		t.Fatal("first connection rejected or unthrottled")
	}
	again, limited, rejected := l.GetUserBucket("test", key, "192.0.2.1")
	if again != first || !limited || rejected {
		t.Fatal("existing connection must reuse its bucket")
	}
	if _, _, rejected := l.GetUserBucket("test", key, "192.0.2.2"); !rejected {
		t.Fatal("device limit was bypassed")
	}
	users[0].SpeedLimit = 0
	if err := l.UpdateInboundLimiter("test", &users); err != nil {
		t.Fatal(err)
	}
	if bucket, limited, rejected := l.GetUserBucket("test", key, "192.0.2.1"); bucket != nil || limited || rejected {
		t.Fatal("removing rate limit did not take effect")
	}
}

func BenchmarkExistingConnection(b *testing.B) {
	l := New()
	users := []api.UserInfo{{UID: 1, Email: "user", SpeedLimit: 1000, DeviceLimit: 1}}
	if err := l.AddInboundLimiter("test", 0, &users, nil); err != nil {
		b.Fatal(err)
	}
	l.GetUserBucket("test", "test|user|1", "192.0.2.1")
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		l.GetUserBucket("test", "test|user|1", "192.0.2.1")
	}
}

func TestConcurrentBucketCreation(t *testing.T) {
	l := New()
	users := []api.UserInfo{{UID: 1, Email: "user", SpeedLimit: 1000, DeviceLimit: 1}}
	if err := l.AddInboundLimiter("test", 0, &users, nil); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	for i := 0; i < 32; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			bucket, limited, rejected := l.GetUserBucket("test", "test|user|1", "192.0.2.1")
			if bucket == nil || !limited || rejected {
				t.Error("concurrent creation failed")
			}
			again, _, _ := l.GetUserBucket("test", "test|user|1", "192.0.2.1")
			if again != bucket {
				t.Error("concurrent connections must share a bucket")
			}
		}()
	}
	wg.Wait()
}

func TestRemoveRevokedCredentialMetadata(t *testing.T) {
	l := New()
	users := []api.UserInfo{{UID: 1, Email: "device:1", DeviceID: 1, SpeedLimit: 1000}}
	if err := l.AddInboundLimiter("node", 0, &users, nil); err != nil {
		t.Fatal(err)
	}
	email := "node|device:1|1"
	l.GetUserBucket("node", email, "192.0.2.1")
	l.RemoveUsers("node", []string{email})
	raw, _ := l.InboundInfo.Load("node")
	in := raw.(*InboundInfo)
	if _, ok := in.UserInfo.Load(email); ok {
		t.Fatal("revoked metadata retained")
	}
	if _, ok := in.BucketHub.Load(email); ok {
		t.Fatal("revoked rate bucket retained")
	}
}
