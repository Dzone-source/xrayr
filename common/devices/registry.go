// Package devices tracks active streams by issued credential, never by client IP.
package devices

import (
	"fmt"
	"sync"
	"time"

	"github.com/XrayR-project/XrayR/api"
)

type stream struct {
	ip   string
	stop func()
}
type credential struct {
	tag     string
	user    api.UserInfo
	expires time.Time
	next    uint64
	streams map[uint64]stream
}
type Registry struct {
	tags  map[string]bool
	mu    sync.Mutex
	users map[string]*credential
	done  chan struct{}
	once  sync.Once
}

func New() *Registry {
	r := &Registry{users: make(map[string]*credential), tags: make(map[string]bool), done: make(chan struct{})}
	go func() {
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				r.expire(time.Now())
			case <-r.done:
				return
			}
		}
	}()
	return r
}
func key(tag string, u api.UserInfo) string { return fmt.Sprintf("%s|%s|%d", tag, u.Email, u.UID) }
func (r *Registry) Refresh(tag string, users []api.UserInfo, ttl time.Duration) {
	r.mu.Lock()
	r.tags[tag] = true
	keep := make(map[string]bool)
	for _, u := range users {
		k := key(tag, u)
		keep[k] = true
		entry := r.users[k]
		if entry == nil {
			entry = &credential{tag: tag, user: u, streams: make(map[uint64]stream)}
			r.users[k] = entry
		}
		entry.expires = time.Time{}
		if u.DeviceID > 0 {
			entry.expires = time.Now().Add(ttl)
		}
	}
	var stops []func()
	for k, entry := range r.users {
		if entry.tag == tag && !keep[k] {
			for _, s := range entry.streams {
				stops = append(stops, s.stop)
			}
			delete(r.users, k)
		}
	}
	r.mu.Unlock()
	for _, stop := range stops {
		stop()
	}
}

// Controls separates panel-owned inbounds from independently configured custom inbounds.
func (r *Registry) Controls(tag string) bool { r.mu.Lock(); defer r.mu.Unlock(); return r.tags[tag] }

// Begin rejects revoked/stale credentials even when their inbound authentication was cached.
func (r *Registry) Begin(email, ip string, stop func()) (func(), bool) {
	r.mu.Lock()
	entry := r.users[email]
	if entry == nil || (!entry.expires.IsZero() && !time.Now().Before(entry.expires)) {
		r.mu.Unlock()
		return nil, false
	}
	entry.next++
	id := entry.next
	entry.streams[id] = stream{ip: ip, stop: stop}
	r.mu.Unlock()
	var once sync.Once
	return func() { once.Do(func() { r.mu.Lock(); delete(entry.streams, id); r.mu.Unlock() }) }, true
}
func (r *Registry) Snapshot(tag string) []api.OnlineUser {
	r.mu.Lock()
	defer r.mu.Unlock()
	result := []api.OnlineUser{}
	for _, entry := range r.users {
		if entry.tag != tag || entry.user.DeviceID <= 0 || !time.Now().Before(entry.expires) {
			continue
		}
		ips := make(map[string]int)
		for _, s := range entry.streams {
			ips[s.ip]++
		}
		for ip, count := range ips {
			result = append(result, api.OnlineUser{UID: entry.user.UID, DeviceID: entry.user.DeviceID, IP: ip, Connections: count})
		}
	}
	return result
}
func (r *Registry) expire(now time.Time) {
	r.mu.Lock()
	var stops []func()
	for k, entry := range r.users {
		if !entry.expires.IsZero() && !now.Before(entry.expires) {
			for _, s := range entry.streams {
				stops = append(stops, s.stop)
			}
			delete(r.users, k)
		}
	}
	r.mu.Unlock()
	for _, stop := range stops {
		stop()
	}
}
func (r *Registry) Close() {
	r.once.Do(func() {
		close(r.done)
		r.mu.Lock()
		var stops []func()
		for _, e := range r.users {
			for _, s := range e.streams {
				stops = append(stops, s.stop)
			}
		}
		r.users = make(map[string]*credential)
		r.mu.Unlock()
		for _, stop := range stops {
			stop()
		}
	})
}
