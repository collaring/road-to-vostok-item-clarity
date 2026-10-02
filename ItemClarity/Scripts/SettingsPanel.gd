extends CanvasLayer

# Built-in settings window, so the mod is fully configurable without MCM.
# Reads and writes the same MCM-format config.ini, so both menus stay in sync.

const CONFIG_PATH = "user://MCM/ItemClarity/config.ini"
const SECTIONS = ["Bool", "Dropdown", "Float", "Color"]

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


func _ready() -> void:
	layer = 100
	_game_data = load("res://Resources/GameData.tres")

	_root = Control.new()
	_root.name = "ItemClaritySettings"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = load("res://UI/Themes/Theme.tres")
	if theme is Theme:
		_root.theme = theme
	add_child(_root)

	_button = Button.new()
	_button.text = "Item Clarity"
	_button.tooltip_text = "Item Clarity settings"
	_button.focus_mode = Control.FOCUS_NONE
	_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_left = -136
	_button.offset_top = 8
	_button.offset_right = -8
	_button.offset_bottom = 38
	_button.visible = false
	_button.pressed.connect(_toggle_window)
	_root.add_child(_button)


func _process(_delta: float) -> void:
	var open := _is_inventory_open()
	_button.visible = open
	if not open and _window != null and _window.visible:
		_window.visible = false


func _is_inventory_open() -> bool:
	if _game_data == null or not ("interface" in _game_data):
		return false
	if "settings" in _game_data and _game_data.settings:
		return false
	if "isDead" in _game_data and _game_data.isDead:
		return false
	return bool(_game_data.interface)


func _toggle_window() -> void:
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
	close.pressed.connect(func(): _window.visible = false)
	header.add_child(close)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tabs)

	var footer = HBoxContainer.new()
	vbox.add_child(footer)
	footer.add_theme_constant_override("separation", 12)
	# Reset on the left, Save on the right, status message centered between them
	var reset = Button.new()
	reset.text = "Reset to Defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(_reset_to_defaults)
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
	save.pressed.connect(_save)
	footer.add_child(save)


func _rebuild_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()

	var lists: Dictionary = {}  # category -> VBoxContainer
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

	for pair in _ordered_keys():
		var section: String = pair[0]
		var key: String = pair[1]
		var entry = _cfg.get_value(section, key, null)
		if not entry is Dictionary:
			continue
		var category: String = entry.get("category", "General")
		if not lists.has(category):
			continue
		var control = _make_control(section, key, entry)
		if control == null:
			continue
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
			return picker
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


func _category_order() -> Array:
	var cats: Array = []
	if _cfg.has_section("Category"):
		for cat in _cfg.get_section_keys("Category"):
			cats.append(cat)
		cats.sort_custom(_by_menu_pos)
	if cats.is_empty():
		cats = ["General"]
	return cats


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
