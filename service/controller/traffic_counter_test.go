package controller

import (
	"sync/atomic"
	"testing"
)

type testTrafficCounter struct{ value atomic.Int64 }

func (c *testTrafficCounter) Value() int64      { return c.value.Load() }
func (c *testTrafficCounter) Set(v int64) int64 { return c.value.Swap(v) }
func (c *testTrafficCounter) Add(v int64) int64 { return c.value.Add(v) }
func TestAcknowledgedTrafficPreservesBytesArrivingDuringReport(t *testing.T) {
	c := &Controller{}
	counter := &testTrafficCounter{}
	counter.Set(10)
	up := []trafficCounter{{counter: counter, value: counter.Value()}}
	down := []trafficCounter{}
	counter.Add(5)
	c.resetTraffic(&up, &down)
	if counter.Value() != 5 {
		t.Fatalf("lost bytes during reporting: %d", counter.Value())
	}
}
