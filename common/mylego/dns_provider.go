package mylego

import (
	"fmt"

	"github.com/go-acme/lego/v4/challenge"
)

// This optimized distribution omits the DNS provider SDKs. It retains the same
// proxy protocols, transports, routing, and HTTP/TLS certificate challenges.
func newDNSProvider(name string) (challenge.Provider, error) {
	return nil, fmt.Errorf("DNS certificate provider %q is unavailable in the lowmem build; use CertMode file/http/tls; DNS challenge support is not included", name)
}
