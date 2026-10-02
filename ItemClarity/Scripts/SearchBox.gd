extends CanvasLayer

# Inventory search: matching items get an outline, everything else is dimmed.
#
# The game reads hotkeys in _input (UIManager) before any GUI control sees the
# key, so a normal LineEdit would toggle the inventory when you type its key.
# This layer is kept as the last child of the root, which makes it receive
# _input first; while focused it handles typing itself and consumes the keys.
#
# The LineEdit itself is moved into the game's Interface, just before the
# tooltip, so it draws above the inventory but underneath tooltips.

const HIGHLIGHT_NODE_NAME = "_icc_search"
const DIM_ALPHA = 0.25

const GAP = 8.0

var _bounds := Rect2()
var _bounds_at: int = -1000

var enabled := true
var interface: Node = null  # set by Main when the Interface node appears
var color := Color(1.0, 0.85, 0.30, 0.90)

var _game_data: Resource = null
var _root: Control = null
var _edit: LineEdit = null
var _items: Dictionary = {}      # instance id -> tracked item node
var _affected: Array = []        # item nodes we changed (outline or dim)
var _tokens: PackedStringArray = []
var _haystacks: Dictionary = {}  # resource_path -> normalized search text
var _suspended: Dictionary = {}  # action -> Array[InputEventKey] removed while typing


func _ready() -> void:
	layer = 100
	_game_data = load("res://Resources/GameData.tres")

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = load("res://UI/Themes/Theme.tres")
	if theme is Theme:
		_root.theme = theme
	add_child(_root)
	_make_edit()


# Recreated if it was freed along with the Interface on a map change
func _make_edit() -> void:
	_edit = LineEdit.new()
	_edit.placeholder_text = "Search items..."
	_edit.clear_button_enabled = true
	_edit.context_menu_enabled = false
	_edit.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_edit.offset_left = -400
	_edit.offset_top = 8
	_edit.offset_right = -144
	_edit.offset_bottom = 38
	_edit.visible = false
	_edit.text_changed.connect(_on_text_changed)
	_edit.focus_entered.connect(_suspend_key_bindings)
	_edit.focus_exited.connect(_restore_key_bindings)
	_root.add_child(_edit)


# Put the box right before the tooltip in the game's UI so tooltips cover it
func _attach() -> void:
	if interface == null or not is_instance_valid(interface):
		interface = get_node_or_null("/root/Map/Core/UI/Interface")
	if interface == null or not ("tooltip" in interface):
		return
	var tooltip = interface.tooltip
	if not (tooltip is Control) or not is_instance_valid(tooltip):
		return
	var parent = tooltip.get_parent()
	if _edit.get_parent() != parent:
		_edit.reparent(parent, false)
	var tip_idx: int = tooltip.get_index()
	if _edit.get_index() > tip_idx:
		parent.move_child(_edit, tip_idx)
	elif _edit.get_index() < tip_idx - 1:
		parent.move_child(_edit, tip_idx - 1)


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_reset()


func set_color(value: Color) -> void:
	color = value
	_refilter()


func track(item: Node) -> void:
	_items[item.get_instance_id()] = item
	if not _tokens.is_empty():
		_apply(item)


func _process(_delta: float) -> void:
	# Safety net: never leave bindings suspended without a focused box
	if not _suspended.is_empty() and not (is_instance_valid(_edit) and _edit.has_focus()):
		_restore_key_bindings()
	if _edit == null or not is_instance_valid(_edit):
		_make_edit()
		_tokens = PackedStringArray()
		_affected = []
	var open := enabled and _is_inventory_open()
	if _edit.visible != open:
		_edit.visible = open
		if not open:
			_reset()
	if open:
		_attach()
		_place()


# Sit directly under the player inventory panel, matching its width
func _place() -> void:
	if interface == null or not is_instance_valid(interface):
		interface = get_node_or_null("/root/Map/Core/UI/Interface")
	var panel: Control = null
	if interface and "inventoryUI" in interface and interface.inventoryUI is Control:
		panel = interface.inventoryUI
	if panel == null or not panel.is_visible_in_tree():
		var screen: Vector2 = _edit.get_viewport_rect().size
		_edit.global_position = Vector2(screen.x - 400, 8)
		_edit.size = Vector2(256, 30)
		return
	# The panel itself reports ~zero size (children are placed manually), so
	# measure what it actually covers. Re-measured a few times per second.
	var now := Time.get_ticks_msec()
	if now - _bounds_at > 250 or _bounds.size == Vector2.ZERO:
		_bounds_at = now
		_bounds = _covered_rect(panel, Rect2())
	if _bounds.size.x < 64:
		return
	_edit.global_position = Vector2(_bounds.position.x, _bounds.end.y + GAP).round()
	_edit.size = Vector2(_bounds.size.x, 30)


func _covered_rect(node: Node, acc: Rect2) -> Rect2:
	if node is Control:
		if not node.visible:
			return acc
		if "slotData" in node or node.name.begins_with("_icc"):
			return acc  # items sit inside the grid; skip them for speed
		var xform: Transform2D = node.get_global_transform()
		var r := Rect2(xform.origin, node.size * xform.get_scale())
		if r.size.x > 0 and r.size.y > 0:
			acc = r if acc.size == Vector2.ZERO else acc.merge(r)
	for child in node.get_children():
		acc = _covered_rect(child, acc)
	return acc


func _is_inventory_open() -> bool:
	if _game_data == null or not ("interface" in _game_data):
		return false
	if "settings" in _game_data and _game_data.settings:
		return false
	if "isDead" in _game_data and _game_data.isDead:
		return false
	return bool(_game_data.interface)


func _input(event: InputEvent) -> void:
	if _edit == null or not is_instance_valid(_edit) or not _edit.is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed and _edit.has_focus():
		if not _edit.get_global_rect().has_point(event.position):
			_edit.release_focus()
		return
	if not (event is InputEventKey):
		return
	if not _edit.has_focus():
		# F or Space jumps into the search box
		if event.pressed and not event.echo and event.keycode in [KEY_F, KEY_SPACE] \
				and not (event.ctrl_pressed or event.alt_pressed or event.shift_pressed or event.meta_pressed):
			var focused = get_viewport().gui_get_focus_owner()
			if focused is LineEdit or focused is TextEdit:
				return
			get_viewport().set_input_as_handled()
			_cancel_press(event)
			_edit.grab_focus()
			_edit.caret_column = _edit.text.length()
		return
	get_viewport().set_input_as_handled()
	# Some game code polls Input directly (e.g. fire mode on "b"), and Input
	# registers the press before _input runs. Release every action bound to
	# this key so those polls don't see it.
	if not event.pressed:
		return
	match event.keycode:
		KEY_ESCAPE:
			_edit.text = ""
			_on_text_changed("")
			_edit.release_focus()
		KEY_ENTER, KEY_KP_ENTER:
			_edit.release_focus()
		KEY_BACKSPACE:
			if event.ctrl_pressed:
				_set_text("")
			elif _edit.text.length() > 0:
				_set_text(_edit.text.substr(0, _edit.text.length() - 1))
		KEY_V when event.ctrl_pressed:
			_set_text(_edit.text + DisplayServer.clipboard_get().strip_edges())
		_:
			if event.unicode >= 32 and not event.ctrl_pressed:
				_set_text(_edit.text + char(event.unicode))


# Some game code polls Input directly (fire mode on "b", etc.), and Input has
# already registered a key by the time _input runs, so consuming events isn't
# enough. While the box is focused, keyboard bindings are removed from the
# InputMap so typed keys match no action; they're restored on focus loss.
func _suspend_key_bindings() -> void:
	if not _suspended.is_empty():
		return
	for action in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			continue  # LineEdit-style editor actions, not game controls
		var keys: Array = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				keys.append(ev)
		if not keys.is_empty():
			_suspended[action] = keys
			for ev in keys:
				InputMap.action_erase_event(action, ev)


func _restore_key_bindings() -> void:
	for action in _suspended:
		if InputMap.has_action(action):
			for ev in _suspended[action]:
				if not InputMap.action_has_event(action, ev):
					InputMap.action_add_event(action, ev)
	_suspended = {}


func _exit_tree() -> void:
	_restore_key_bindings()


# A press that already reached Input (F / Space opening the box) is undone by
# feeding Input the matching release while the bindings still exist
func _cancel_press(event: InputEventKey) -> void:
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)


func _set_text(text: String) -> void:
	_edit.text = text
	_edit.caret_column = text.length()
	_on_text_changed(text)


func _on_text_changed(text: String) -> void:
	_tokens = PackedStringArray()
	for word in text.to_lower().split(" ", false):
		var token = _normalize(word)
		if token != "":
			_tokens.append(token)
	_refilter()


func _refilter() -> void:
	_clear()
	if _tokens.is_empty():
		return
	for id in _items.keys():
		var item = _items[id]
		if is_instance_valid(item):
			_apply(item)
		else:
			_items.erase(id)


func _apply(item: Node) -> void:
	if not is_instance_valid(item) or not item.is_inside_tree():
		return
	if not ("slotData" in item) or item.slotData == null or item.slotData.itemData == null:
		return
	if _matches(item.slotData.itemData):
		if item.get_node_or_null(HIGHLIGHT_NODE_NAME) == null:
			var overlay = Panel.new()
			overlay.name = HIGHLIGHT_NODE_NAME
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
			var style = StyleBoxFlat.new()
			style.bg_color = Color(color.r, color.g, color.b, color.a * 0.15)
			style.border_color = color
			style.set_border_width_all(2)
			overlay.add_theme_stylebox_override("panel", style)
			item.add_child(overlay)
	else:
		item.modulate.a = DIM_ALPHA
	if item not in _affected:
		_affected.append(item)


func _clear() -> void:
	for item in _affected:
		if is_instance_valid(item):
			item.modulate.a = 1.0
			var overlay = item.get_node_or_null(HIGHLIGHT_NODE_NAME)
			if overlay:
				overlay.free()
	_affected = []


func _reset() -> void:
	if _edit and is_instance_valid(_edit):
		_edit.text = ""
		_edit.release_focus()
	_tokens = PackedStringArray()
	_clear()


# Every word typed must appear somewhere in the item's searchable text
func _matches(data: Resource) -> bool:
	var path: String = data.resource_path
	if not _haystacks.has(path):
		var parts: Array = []
		for prop in ["name", "display", "type", "subtype", "caliber"]:
			if prop in data and data.get(prop) != null:
				parts.append(str(data.get(prop)))
		# Category folder, e.g. res://Items/Medical/... -> "Medical"
		var segments = path.split("/")
		if segments.size() > 3:
			parts.append(segments[3])
		_haystacks[path] = _normalize(" ".join(parts).to_lower())
	var hay: String = _haystacks[path]
	for token in _tokens:
		if not hay.contains(token):
			return false
	return true


# Lowercase alphanumerics only, so "762" matches "7.62x39" and "w lock" "W. Lock"
func _normalize(text: String) -> String:
	var out := ""
	for c in text:
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == " ":
			out += c
	return out
