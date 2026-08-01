package limiter

import (
	"sync"
	"testing"

	"golang.org/x/time/rate"
)

func TestWaitRateChunksWhenNExceedsBurst(t *testing.T) {
	lim := rate.NewLimiter(rate.Limit(1000), 1000)
	// Previously WaitN(5000) returned error immediately when n > burst.
	waitRate(lim, 5000)
}

func TestNewSpeedLimiterMinBurst(t *testing.T) {
	lim := newSpeedLimiter(625000) // 5 Mbps
	if lim == nil {
		t.Fatal("expected limiter")
	}
	if lim.Burst() < 4*1024*1024 {
		t.Fatalf("burst=%d, want >= 4MiB", lim.Burst())
	}
}

func TestStoreDirBucketsCreatesSeparateLimiters(t *testing.T) {
	hub := new(sync.Map)
	storeDirBuckets(hub, "user1", 625000)
	v, ok := hub.Load("user1")
	if !ok {
		t.Fatal("missing buckets")
	}
	b := v.(*dirBuckets)
	if b.up == nil || b.down == nil || b.up == b.down {
		t.Fatalf("expected distinct up/down limiters: %#v", b)
	}
	storeDirBuckets(hub, "user1", 0)
	if _, ok := hub.Load("user1"); ok {
		t.Fatal("expected delete on limit=0")
	}
}
