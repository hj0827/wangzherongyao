extends RefCounted

const BACK_OPEN := "open"
const BACK_CLOSE := "close"
const BACK_LEAVE := "leave"

static func back_action(online: bool, overlay_open: bool, result_shown: bool) -> String:
	if result_shown:
		return BACK_LEAVE
	if overlay_open:
		return BACK_CLOSE
	return BACK_OPEN

static func freezes_simulation(online: bool) -> bool:
	return not online

static func title(online: bool) -> String:
	return "对局菜单" if online else "暂停"

static func hint(online: bool) -> String:
	if online:
		return "联机对局不会暂停 · 离开将放弃本局"
	return "返回后将放弃当前对局"

static func pause_label(online: bool) -> String:
	return "菜单" if online else "暂停"
