package controller

import (
	"fmt"
	"reflect"
	"testing"

	"github.com/XrayR-project/XrayR/api"
)

func TestCompareUserList(t *testing.T) {
	a := api.UserInfo{UID: 1, Email: "a", SpeedLimit: 100}
	b := api.UserInfo{UID: 2, Email: "b"}
	changed := a
	changed.SpeedLimit = 200
	for _, tc := range []struct {
		name                     string
		old, new, deleted, added []api.UserInfo
	}{
		{"empty", nil, nil, nil, nil},
		{"same", []api.UserInfo{a, b}, []api.UserInfo{b, a}, nil, nil},
		{"add", []api.UserInfo{a}, []api.UserInfo{a, b}, nil, []api.UserInfo{b}},
		{"delete", []api.UserInfo{a, b}, []api.UserInfo{b}, []api.UserInfo{a}, nil},
		{"update", []api.UserInfo{a}, []api.UserInfo{changed}, []api.UserInfo{a}, []api.UserInfo{changed}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			deleted, added := compareUserList(&tc.old, &tc.new)
			if !reflect.DeepEqual(deleted, tc.deleted) || !reflect.DeepEqual(added, tc.added) {
				t.Fatalf("got deleted=%v added=%v; want deleted=%v added=%v", deleted, added, tc.deleted, tc.added)
			}
		})
	}
}

func BenchmarkCompareUserList(b *testing.B) {
	for _, size := range []int{1000, 10000} {
		b.Run(fmt.Sprint(size), func(b *testing.B) {
			old := make([]api.UserInfo, size)
			for i := range old {
				old[i] = api.UserInfo{UID: i, Email: fmt.Sprintf("user-%d", i)}
			}
			next := append([]api.UserInfo(nil), old...)
			next[len(next)-1].SpeedLimit = 1024
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				compareUserList(&old, &next)
			}
		})
	}
}
