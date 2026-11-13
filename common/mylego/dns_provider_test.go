package mylego

import (
	"strings"
	"testing"
)

func TestLowmemDNSProvider(t *testing.T) {
	provider, err := newDNSProvider("cloudflare")
	if provider != nil || err == nil || !strings.Contains(err.Error(), "DNS challenge support is not included") {
		t.Fatal("optimized build must explain supported certificate modes")
	}
}
