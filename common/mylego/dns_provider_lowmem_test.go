//go:build lowmem

package mylego

import (
	"strings"
	"testing"
)

func TestLowmemDNSProvider(t *testing.T) {
	provider, err := newDNSProvider("cloudflare")
	if provider != nil || err == nil || !strings.Contains(err.Error(), "standard build") {
		t.Fatal("lowmem must explain how to restore DNS certificate support")
	}
}
