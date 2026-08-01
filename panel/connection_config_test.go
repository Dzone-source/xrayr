package panel

import "testing"

func TestNormalizeConnectionConfigClampsLegacyUplinkOnly(t *testing.T) {
	c := &ConnectionConfig{
		Handshake:    4,
		ConnIdle:     300,
		UplinkOnly:   5,
		DownlinkOnly: 30,
		BufferSize:   64,
	}
	normalizeConnectionConfig(c)
	if c.UplinkOnly != 3600 {
		t.Fatalf("UplinkOnly=%d, want 3600", c.UplinkOnly)
	}
	if c.DownlinkOnly != 3600 {
		t.Fatalf("DownlinkOnly=%d, want 3600", c.DownlinkOnly)
	}
	if c.ConnIdle != 300 {
		t.Fatalf("ConnIdle=%d, want 300 (already safe)", c.ConnIdle)
	}
}

func TestParseConnectionConfigIgnoresZeroOverrides(t *testing.T) {
	// Missing YAML keys unmarshal as 0 — must keep defaults, not wipe them.
	policy := parseConnectionConfig(&ConnectionConfig{})
	if policy.UplinkOnly == nil || *policy.UplinkOnly != 3600 {
		t.Fatalf("UplinkOnly=%v, want 3600", policy.UplinkOnly)
	}
	if policy.ConnectionIdle == nil || *policy.ConnectionIdle != 600 {
		t.Fatalf("ConnIdle=%v, want 600", policy.ConnectionIdle)
	}
	if policy.BufferSize == nil || *policy.BufferSize != 1024 {
		t.Fatalf("BufferSize=%v, want 1024", policy.BufferSize)
	}
}
