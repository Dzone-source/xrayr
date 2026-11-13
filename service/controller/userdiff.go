package controller

import "github.com/XrayR-project/XrayR/api"

// compareUserList uses one index instead of two maps and an intersection slice.
// The full record is the key so a changed credential or limit remains a removal
// followed by an addition, as required by the inbound user manager.
func compareUserList(old, new *[]api.UserInfo) (deleted, added []api.UserInfo) {
	users := make(map[api.UserInfo]bool, len(*old))
	for _, user := range *old {
		users[user] = false
	}
	for _, user := range *new {
		if _, exists := users[user]; !exists {
			added = append(added, user)
		}
		users[user] = true
	}
	for user, retained := range users {
		if !retained {
			deleted = append(deleted, user)
		}
	}
	return deleted, added
}
