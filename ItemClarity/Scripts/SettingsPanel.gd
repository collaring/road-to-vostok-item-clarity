extends CanvasLayer

# Built-in settings window, so the mod is fully configurable without MCM.
# Reads and writes the same MCM-format config.ini, so both menus stay in sync.

const CONFIG_PATH = "user://MCM/ItemClarity/config.ini"
const SECTIONS = ["Bool", "Dropdown", "Float", "Color", "Keycode"]
const KeyUtil = preload("res://ItemClarity/Scripts/KeyUtil.gd")

var config_node: Node = null   # ItemClarityConfig autoload, set by Main
var main_node: Node = null     # ItemClarity autoload, set by Main

var _game_data: Resource = null
var _root: Control = null
var _button: Button = null
var _window: PanelContainer = null
var _tabs: TabContainer = null
var _status: Label = null
var _cfg: ConfigFile = null
var _dirty := false
var _popup_owners: Array = []  # OptionButtons / ColorPickerButtons with popups
var _occupied_by_us := false
# Keybind capture: the button waiting for a key, its setting, and the game
# bindings suspended meanwhile (so Esc/Tab/etc. can't trigger game actions)
var _capture_button: Button = null
var _capture_key := ""
var _capture_suspended: Dictionary = {}
# Button in the game's settings screens (main menu and Esc), under MCM's
var _menu_button: Button = null
var _menu_settings: Control = null  # the game's settings node it belongs to
var _mcm_button: Control = null     # MCM's button, found once per scene
var _mcm_search_at: int = -10000
var _menu_search_at: int = -10000
var _from_menu := false             # window was opened from a settings screen
const MENU_BUTTON_SIZE = 55.0
const INVENTORY_BUTTON_SIZE = 38.0
const ICON_PATH = "res://ItemClarity/Icon.png"
var _icon: Texture2D = null


func _ready() -> void:
	layer = 100
	# The Esc settings screen pauses the tree; keep working so the window can
	# be opened and used from there
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game_data = load("res://Resources/GameData.tres")

	_root = Control.new()
	_root.name = "ItemClaritySettings"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = load("res://UI/Themes/Theme.tres")
	if theme is Theme:
		_root.theme = theme
	add_child(_root)

	_icon = _load_icon()
	_button = Button.new()
	_button.tooltip_text = "Item Clarity Settings"
	_button.focus_mode = Control.FOCUS_NONE
	_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_left = -(INVENTORY_BUTTON_SIZE + 8)
	_button.offset_top = 8
	_button.offset_right = -8
	_button.offset_bottom = 8 + INVENTORY_BUTTON_SIZE
	_style_icon_button(_button, "Item Clarity")
	_button.visible = false
	_button.pressed.connect(func():
		_from_menu = false
		_toggle_window()
	)
	_root.add_child(_button)


func _process(_delta: float) -> void:
	var open := _is_inventory_open()
	_button.visible = open
	_update_menu_button()
	if _window != null and _window.visible:
		# Close along with whatever it was opened from
		if (_from_menu and not _menu_visible()) or (not _from_menu and not open):
			_window.visible = false
	if _capture_button and (_window == null or not _window.visible):
		_end_capture()
	# Only block inventory interaction when opened over the inventory
	_set_occupied(_window != null and _window.visible and not _from_menu)


# ── Settings-screen button (main menu + Esc menu) ───────────────────────────

# Same places MCM puts its button: the main menu's UI_Settings panel, or the
# Settings node under Map in-game. Those nodes are rebuilt with each scene, so
# the button is recreated when it goes missing (searching at most once a second).
func _update_menu_button() -> void:
	if _menu_button == null or not is_instance_valid(_menu_button):
		_menu_button = null
		var now := Time.get_ticks_msec()
		if now - _menu_search_at < 1000:
			return
		_menu_search_at = now
		_create_menu_button()
		if _menu_button == null:
			return
	_menu_button.visible = _menu_visible()
	if _menu_button.visible:
		# Directly under MCM's button when MCM is installed, else in its spot
		var screen: Vector2 = _menu_button.get_viewport_rect().size
		# MCM may create its button after ours; look again now and then until found
		if (_mcm_button == null or not is_instance_valid(_mcm_button)) and Time.get_ticks_msec() - _mcm_search_at > 2000:
			_find_mcm_button()
		var y := 30.0
		if _mcm_button and is_instance_valid(_mcm_button) and _mcm_button.visible:
			y = _mcm_button.global_position.y + MENU_BUTTON_SIZE + 10.0
		_menu_button.global_position = Vector2(screen.x - (MENU_BUTTON_SIZE + 30.0), y)


func _create_menu_button() -> void:
	var scene = get_tree().current_scene
	if scene == null or scene.name == "Death":
		return
	var parent: Node = null
	var settings = get_tree().root.find_child("UI_Settings", true, false)
	if settings and scene.name == "Menu":
		_menu_settings = settings.get_parent()
		parent = _menu_settings.get_parent()
	else:
		var map = get_tree().root.get_node_or_null("Map")
		settings = map.find_child("Settings", true, false) if map else null
		if settings == null:
			return
		_menu_settings = settings
		parent = settings
	if not (_menu_settings is CanvasItem):
		return
	var b = Button.new()
	b.name = "ItemClarity_Settings_Button"
	b.tooltip_text = "Item Clarity Settings"
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(MENU_BUTTON_SIZE, MENU_BUTTON_SIZE)
	b.custom_minimum_size = b.size
	_style_icon_button(b, "IC")
	b.pressed.connect(func():
		_from_menu = true
		_toggle_window()
	)
	parent.add_child(b)
	_find_mcm_button()
	b.top_level = true  # position in screen space regardless of the parent's layout
	_menu_button = b


func _find_mcm_button() -> void:
	_mcm_search_at = Time.get_ticks_msec()
	var mcm = get_tree().root.find_child("MCM_Settings_Button", true, false)
	_mcm_button = mcm if mcm is Control else null


# The game's menu click (what UIManager/Interface.PlayClick play). Played
# directly because Interface.PlayClick only sounds while the inventory is open,
# and this window also opens from the main menu and the Esc menu.
var _audio_library: Resource = null
var _audio_instance: PackedScene = null


func _play_click() -> void:
	if _audio_library == null:
		_audio_library = load("res://Resources/AudioLibrary.tres")
		_audio_instance = load("res://Resources/AudioInstance2D.tscn")
	if _audio_library == null or _audio_instance == null or not ("UIClick" in _audio_library):
		return
	var click = _audio_instance.instantiate()
	add_child(click)  # inherits PROCESS_MODE_ALWAYS, so it plays and frees itself while paused too
	click.PlayInstance(_audio_library.UIClick)


# The icon ships as a plain PNG (no editor import), so build the texture from
# its bytes at runtime
func _load_icon() -> Texture2D:
	var bytes := FileAccess.get_file_as_bytes(ICON_PATH)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	image.generate_mipmaps()  # stays smooth when drawn small
	return ImageTexture.create_from_image(image)


# Dark square button showing the logo; falls back to text if it didn't load
func _style_icon_button(b: Button, fallback_text: String) -> void:
	if _icon:
		b.icon = _icon
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	else:
		b.text = fallback_text
		b.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var box = StyleBoxFlat.new()
		box.bg_color = Color(0.09, 0.09, 0.11, 0.95) if state == "normal" else Color(0.17, 0.17, 0.2, 0.95)
		box.border_color = Color(0.4, 0.4, 0.45) if state == "normal" else Color(0.75, 0.6, 0.85)
		box.set_border_width_all(1)
		var pad: float = b.custom_minimum_size.x * 0.12 if b.custom_minimum_size.x > 0 else 4.0
		box.set_content_margin_all(pad)
		b.add_theme_stylebox_override(state, box)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))


func _menu_visible() -> bool:
	return _menu_settings != null and is_instance_valid(_menu_settings) and _menu_settings.is_visible_in_tree()


func _exit_tree() -> void:
	_end_capture()
	_set_occupied(false)


# ── Keybind capture ─────────────────────────────────────────────────────────

func _start_capture(button: Button, key: String) -> void:
	if _capture_button:
		var same := _capture_button == button
		_end_capture()
		if same:
			return  # clicking the waiting button again cancels
	_capture_button = button
	_capture_key = key
	button.text = "Press a key..."
	_capture_suspended = KeyUtil.suspend_bindings()
	if main_node and main_node.has_method("set_key_capture"):
		main_node.set_key_capture(true)


func _end_capture() -> void:
	if _capture_button == null:
		return
	KeyUtil.restore_bindings(_capture_suspended)
	_capture_suspended = {}
	if main_node and main_node.has_method("set_key_capture"):
		main_node.set_key_capture(false)
	if is_instance_valid(_capture_button):
		_capture_button.text = KeyUtil.label(KeyUtil.make_bind(_cfg.get_value("Keycode", _capture_key, {})))
	_capture_button = null
	_capture_key = ""


func _input(event: InputEvent) -> void:
	if _capture_button == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	match event.physical_keycode:
		KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META:
			return  # wait for the actual key; modifiers are recorded with it
		KEY_ESCAPE:
			_end_capture()
			return
		KEY_BACKSPACE, KEY_DELETE:
			_set_keybind(_capture_key, 0, false, false, false, false)
		_:
			_set_keybind(_capture_key, event.physical_keycode,
				event.alt_pressed, event.ctrl_pressed, event.meta_pressed, event.shift_pressed)
	_end_capture()


func _set_keybind(key: String, code: int, alt: bool, ctrl: bool, meta: bool, shift: bool) -> void:
	var entry: Dictionary = _cfg.get_value("Keycode", key, {})
	entry["value"] = code
	entry["type"] = "Key"
	entry["altPressed"] = alt
	entry["controlPressed"] = ctrl
	entry["metaPressed"] = meta
	entry["shiftPressed"] = shift
	_cfg.set_value("Keycode", key, entry)
	_dirty = true
	_set_status("Unsaved changes")


func _is_inventory_open() -> bool:
	if _game_data == null or not ("interface" in _game_data):
		return false
	if "settings" in _game_data and _game_data.settings:
		return false
	if "isDead" in _game_data and _game_data.isDead:
		return false
	return bool(_game_data.interface)


# The game polls left_mouse / context in Interface._physics_process, so GUI
# handling alone doesn't stop clicks on this window reaching the inventory.
# While the window is open we set gameData.isOccupied, which makes the game
# skip all item interaction. Only cleared again if we were the ones to set it.
func _set_occupied(on: bool) -> void:
	if _game_data == null or not ("isOccupied" in _game_data):
		return
	if on and (_occupied_by_us or not _game_data.isOccupied):
		_game_data.isOccupied = true  # re-applied if the game clears it meanwhile
		_occupied_by_us = true
	elif not on and _occupied_by_us:
		_game_data.isOccupied = false
		_occupied_by_us = false


func _toggle_window() -> void:
	_play_click()
	if _window != null and _window.visible:
		_window.visible = false
		return
	_cfg = ConfigFile.new()
	if _cfg.load(CONFIG_PATH) != OK:
		_cfg = _defaults()
	elif config_node and config_node.has_method("merge_defaults"):
		config_node.merge_defaults(_cfg, _defaults())
	_dirty = false
	if _window == null:
		_build_window()
	_rebuild_tabs()
	_set_status("")
	_window.visible = true


func _defaults() -> ConfigFile:
	if config_node and config_node.has_method("build_defaults"):
		return config_node.build_defaults()
	return ConfigFile.new()


# ── Window ───────────────────────────────────────────────────────────────────

func _build_window() -> void:
	_window = PanelContainer.new()
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.anchor_left = 0.5
	_window.anchor_right = 0.5
	_window.anchor_top = 0.5
	_window.anchor_bottom = 0.5
	_window.offset_left = -280
	_window.offset_right = 280
	_window.offset_top = -300
	_window.offset_bottom = 300
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.07, 0.07, 0.97)
	bg.border_color = Color(0.35, 0.35, 0.35)
	bg.set_border_width_all(1)
	bg.set_content_margin_all(12)
	_window.add_theme_stylebox_override("panel", bg)
	_window.visible = false
	_root.add_child(_window)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_window.add_child(vbox)

	var header = HBoxContainer.new()
	vbox.add_child(header)
	var title = Label.new()
	title.text = "Item Clarity Settings"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)
	var close = Button.new()
	close.text = " X "
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func():
		_play_click()
		_window.visible = false
	)
	header.add_child(close)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# tab_clicked, not tab_changed: rebuilding the tabs on open also changes tab
	_tabs.tab_clicked.connect(func(_i): _play_click())
	vbox.add_child(_tabs)

	var footer = HBoxContainer.new()
	vbox.add_child(footer)
	footer.add_theme_constant_override("separation", 12)
	# Reset on the left, Save on the right, status message centered between them
	var reset = Button.new()
	reset.text = "Reset to Defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func():
		_play_click()
		_reset_to_defaults()
	)
	footer.add_child(reset)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 12)
	footer.add_child(_status)
	var save = Button.new()
	save.text = "Save"
	save.custom_minimum_size = Vector2(80, 0)
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(func():
		_play_click()
		_save()
	)
	footer.add_child(save)


func _rebuild_tabs() -> void:
	_popup_owners = []
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()

	# Settings are categorised "Tab: Section" (so MCM, which only has headings,
	# shows the same structure); here the part before ": " picks the tab
	var lists: Dictionary = {}  # tab -> VBoxContainer
	for category in _category_order():
		var scroll = ScrollContainer.new()
		scroll.name = category
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_tabs.add_child(scroll)
		var list = VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 6)
		scroll.add_child(list)
		lists[category] = list

	var last_group: Dictionary = {}  # tab -> section heading last shown in it
	for pair in _ordered_keys():
		var section: String = pair[0]
		var key: String = pair[1]
		var entry = _cfg.get_value(section, key, null)
		if not entry is Dictionary:
			continue
		var parts: PackedStringArray = str(entry.get("category", "General")).split(": ", true, 1)
		var category: String = parts[0]
		var group: String = parts[1] if parts.size() > 1 else ""
		if not lists.has(category):
			continue
		var control = _make_control(section, key, entry)
		if control == null:
			continue
		if group != "" and last_group.get(category, "") != group:
			_add_group_header(lists[category], group, last_group.has(category))
			last_group[category] = group
		var row = HBoxContainer.new()
		row.tooltip_text = entry.get("tooltip", "")
		var label = Label.new()
		label.text = entry.get("name", key)
		label.tooltip_text = row.tooltip_text
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(label)
		row.add_child(control)
		lists[category].add_child(row)


func _add_group_header(list: VBoxContainer, title: String, spaced: bool) -> void:
	if spaced:
		var gap = Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		list.add_child(gap)
	var label = Label.new()
	label.text = title.to_upper()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	list.add_child(label)
	var line = HSeparator.new()
	list.add_child(line)


func _make_control(section: String, key: String, entry: Dictionary) -> Control:
	var value = entry.get("value", entry.get("default"))
	match section:
		"Bool":
			var check = CheckBox.new()
			check.button_pressed = bool(value)
			check.focus_mode = Control.FOCUS_NONE
			check.toggled.connect(func(on): _set_value(section, key, on))
			return check
		"Dropdown":
			var opt = OptionButton.new()
			opt.focus_mode = Control.FOCUS_NONE
			opt.custom_minimum_size = Vector2(150, 0)
			for o in entry.get("options", []):
				opt.add_item(str(o))
			opt.select(int(value))
			opt.item_selected.connect(func(i): _set_value(section, key, i))
			_popup_owners.append(opt)
			return opt
		"Float":
			var box = HBoxContainer.new()
			var slider = HSlider.new()
			slider.min_value = float(entry.get("minRange", 0.0))
			slider.max_value = float(entry.get("maxRange", 1.0))
			slider.step = float(entry.get("step", 0.01))
			slider.value = float(value)
			slider.custom_minimum_size = Vector2(150, 0)
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.focus_mode = Control.FOCUS_NONE
			var readout = Label.new()
			readout.custom_minimum_size = Vector2(40, 0)
			readout.text = "%.2f" % slider.value
			slider.value_changed.connect(func(v):
				readout.text = "%.2f" % v
				_set_value(section, key, v)
			)
			box.add_child(slider)
			box.add_child(readout)
			return box
		"Color":
			var picker = ColorPickerButton.new()
			picker.color = value if value is Color else Color(0, 0, 0, 0)
			picker.edit_alpha = entry.get("allowAlpha", true)
			picker.custom_minimum_size = Vector2(64, 24)
			picker.focus_mode = Control.FOCUS_NONE
			picker.color_changed.connect(func(c): _set_value(section, key, c))
			_popup_owners.append(picker)
			return picker
		"Keycode":
			var bind_button = Button.new()
			bind_button.text = KeyUtil.label(KeyUtil.make_bind(entry))
			bind_button.tooltip_text = "Click, then press a key. Esc cancels, Backspace unbinds."
			bind_button.custom_minimum_size = Vector2(150, 0)
			bind_button.focus_mode = Control.FOCUS_NONE
			bind_button.pressed.connect(func(): _start_capture(bind_button, key))
			return bind_button
	return null


# Definition order from the config script, falling back to file order
func _ordered_keys() -> Array:
	if config_node and "ordered_keys" in config_node and not config_node.ordered_keys.is_empty():
		return config_node.ordered_keys
	var keys: Array = []
	for section in SECTIONS:
		if _cfg.has_section(section):
			for key in _cfg.get_section_keys(section):
				keys.append([section, key])
	return keys


# Tabs, in order: the "Tab" part of each "Tab: Section" heading, by menu_pos
func _category_order() -> Array:
	var headings: Array = []
	if _cfg.has_section("Category"):
		for cat in _cfg.get_section_keys("Category"):
			headings.append(cat)
		headings.sort_custom(_by_menu_pos)
	var tabs: Array = []
	for heading in headings:
		var tab: String = str(heading).split(": ", true, 1)[0]
		if tab not in tabs:
			tabs.append(tab)
	if tabs.is_empty():
		tabs = ["General"]
	return tabs


func _by_menu_pos(a: String, b: String) -> bool:
	var pa: int = int(_cfg.get_value("Category", a, {}).get("menu_pos", 99))
	var pb: int = int(_cfg.get_value("Category", b, {}).get("menu_pos", 99))
	return pa < pb


# ── Actions ──────────────────────────────────────────────────────────────────

func _set_value(section: String, key: String, value) -> void:
	var entry: Dictionary = _cfg.get_value(section, key, {})
	entry["value"] = value
	_cfg.set_value(section, key, entry)
	_dirty = true
	_set_status("Unsaved changes")


func _reset_to_defaults() -> void:
	for section in SECTIONS:
		if not _cfg.has_section(section):
			continue
		for key in _cfg.get_section_keys(section):
			var entry = _cfg.get_value(section, key)
			if entry is Dictionary and entry.has("default"):
				entry["value"] = entry["default"]
				if section == "Keycode":
					for m in KeyUtil.MODIFIERS:
						entry[m] = false
				_cfg.set_value(section, key, entry)
	_dirty = true
	_rebuild_tabs()
	_set_status("Defaults restored, press Save to apply")


func _save() -> void:
	DirAccess.make_dir_recursive_absolute(CONFIG_PATH.get_base_dir())
	if _cfg.save(CONFIG_PATH) != OK:
		_set_status("Could not save settings")
		return
	_dirty = false
	if main_node and main_node.has_method("refresh_all_slots"):
		main_node.refresh_all_slots()
	_set_status("Saved")


func _set_status(text: String) -> void:
	if _status:
		_status.text = text
