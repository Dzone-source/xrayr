package controller

import (
	"testing"

	"github.com/XrayR-project/XrayR/api"
)

func TestCompareUserListSpeedLimitChangeDoesNotDelete(t *testing.T) {
	old := &[]api.UserInfo{{
		UID: 1, UUID: "u1", Passwd: "p1", SpeedLimit: 0, DeviceLimit: 0,
	}}
	new := &[]api.UserInfo{{
		UID: 1, UUID: "u1", Passwd: "p1", SpeedLimit: 625000, DeviceLimit: 2,
	}}

	deleted, added, updated := compareUserList(old, new)
	if len(deleted) != 0 || len(added) != 0 {
		t.Fatalf("speed/device limit change must not remove+add: deleted=%d added=%d", len(deleted), len(added))
	}
	if len(updated) != 1 || updated[0].SpeedLimit != 625000 || updated[0].DeviceLimit != 2 {
		t.Fatalf("expected one updated user, got %#v", updated)
	}
}

func TestCompareUserListCredentialChangeRemoves(t *testing.T) {
	old := &[]api.UserInfo{{
		UID: 1, UUID: "old-uuid", Passwd: "p1", SpeedLimit: 0,
	}}
	new := &[]api.UserInfo{{
		UID: 1, UUID: "new-uuid", Passwd: "p1", SpeedLimit: 0,
	}}

	deleted, added, updated := compareUserList(old, new)
	if len(deleted) != 1 || len(added) != 1 || len(updated) != 0 {
		t.Fatalf("uuid change should remove+add: deleted=%d added=%d updated=%d", len(deleted), len(added), len(updated))
	}
}

func TestNodeInfoRequiresInboundRebuildIgnoresSpeedLimit(t *testing.T) {
	old := &api.NodeInfo{
		NodeType: "Trojan", NodeID: 1, Port: 443, TransportProtocol: "tcp",
		EnableTLS: true, SpeedLimit: 0, Host: "a.example.com",
	}
	new := &api.NodeInfo{
		NodeType: "Trojan", NodeID: 1, Port: 443, TransportProtocol: "tcp",
		EnableTLS: true, SpeedLimit: 1250000, Host: "b.example.com",
	}
	if nodeInfoRequiresInboundRebuild(old, new) {
		t.Fatal("SpeedLimit/Host-only change on Trojan TCP must not rebuild inbound")
	}
	new.Port = 8443
	if !nodeInfoRequiresInboundRebuild(old, new) {
		t.Fatal("Port change must rebuild inbound")
	}
}

func TestCompareUserListAddAndDelete(t *testing.T) {
	old := &[]api.UserInfo{
		{UID: 1, UUID: "a"},
		{UID: 2, UUID: "b"},
	}
	new := &[]api.UserInfo{
		{UID: 2, UUID: "b"},
		{UID: 3, UUID: "c"},
	}

	deleted, added, updated := compareUserList(old, new)
	if len(deleted) != 1 || deleted[0].UID != 1 {
		t.Fatalf("expected delete uid 1, got %#v", deleted)
	}
	if len(added) != 1 || added[0].UID != 3 {
		t.Fatalf("expected add uid 3, got %#v", added)
	}
	if len(updated) != 0 {
		t.Fatalf("expected no updates, got %#v", updated)
	}
}
