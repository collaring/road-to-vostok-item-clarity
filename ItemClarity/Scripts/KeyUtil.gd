extends RefCounted

# Keybind helpers shared by the search box, inventory hotkeys and the settings
# panel. Binds use MCM's Keycode format: a physical keycode in "value" plus
# altPressed / controlPressed / metaPressed / shiftPressed. A value of 0 means
# unbound.

const MODIFIERS = ["altPressed", "controlPressed", "metaPressed", "shiftPressed"]


static func make_bind(entry) -> Dictionary:
	var bind := {"value": 0, "altPressed": false, "controlPressed": false, "metaPressed": false, "shiftPressed": false}
	if entry is Dictionary:
		bind["value"] = int(entry.get("value", entry.get("default", 0)))
		for m in MODIFIERS:
			bind[m] = bool(entry.get(m, false))
	elif entry is int:
		bind["value"] = entry
	return bind


static func matches(event: InputEvent, bind: Dictionary) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	var code: int = int(bind.get("value", 0))
	if code == 0 or event.physical_keycode != code:
		return false
	return event.alt_pressed == bind.get("altPressed", false) \
		and event.ctrl_pressed == bind.get("controlPressed", false) \
		and event.meta_pressed == bind.get("metaPressed", false) \
		and event.shift_pressed == bind.get("shiftPressed", false)


static func label(bind: Dictionary) -> String:
	var code: int = int(bind.get("value", 0))
	if code == 0:
		return "Unbound"
	var parts: Array = []
	if bind.get("controlPressed", false): parts.append("Ctrl")
	if bind.get("altPressed", false): parts.append("Alt")
	if bind.get("shiftPressed", false): parts.append("Shift")
	if bind.get("metaPressed", false): parts.append("Meta")
	var logical: int = DisplayServer.keyboard_get_keycode_from_physical(code)
	parts.append(OS.get_keycode_string(logical if logical != 0 else code))
	return "+".join(parts)


# Removes every keyboard binding from the game's InputMap (except the ui_*
# editor actions) so key presses match no game action, e.g. while typing in
# the search box or capturing a keybind. Returns what to pass to restore().
static func suspend_bindings() -> Dictionary:
	var suspended := {}
	for action in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			continue
		var keys: Array = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				keys.append(ev)
		if not keys.is_empty():
			suspended[action] = keys
			for ev in keys:
				InputMap.action_erase_event(action, ev)
	return suspended


static func restore_bindings(suspended: Dictionary) -> void:
	for action in suspended:
		if InputMap.has_action(action):
			for ev in suspended[action]:
				if not InputMap.action_has_event(action, ev):
					InputMap.action_add_event(action, ev)


# A press that already reached Input (Input registers keys before _input runs)
# is undone by feeding Input the matching release while bindings still exist
static func cancel_press(event: InputEventKey) -> void:
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
