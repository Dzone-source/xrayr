//go:build !lowmem

package mylego

import (
	"github.com/go-acme/lego/v4/challenge"
	"github.com/go-acme/lego/v4/providers/dns"
)

func newDNSProvider(name string) (challenge.Provider, error) {
	return dns.NewDNSChallengeProviderByName(name)
}
