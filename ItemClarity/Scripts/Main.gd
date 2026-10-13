extends Node

const OVERLAY_NODE_NAME = "_icc_border"
const TASK_ICON_NODE_NAME = "_icc_task"
const CONFIG_PATH = "user://MCM/ItemClarity/config.ini"

# task_needed_paths: resource_path -> Array of {"count": 2, "text": "Gunsmith: Warm Meal"}
var _task_needed_paths: Dictionary = {}
# crafting_recipe_paths: resource_path -> Array[String] of recipe names that use this item as ingredient
var _crafting_recipe_paths: Dictionary = {}
var _tooltip_quest_label: RichTextLabel = null
var _quest_text_cache := ""  # avoid re-parsing BBCode every frame
var _tooltip_recipe_label: Label = null
var _tooltip_price_label: RichTextLabel = null
var _tooltip_compare_label: RichTextLabel = null
var _hovered_compare_text := ""
var _compare_text_cache := ""
var _price_text_cache := ""
var _tooltip_root: Control = null
var _tooltip_rework: Node = null
var _compat: Node = null
var _counter: Node = null
var _search: Node = null
var _ground: Node = null
var _task_icons: Dictionary = {}  # instance id -> [icon Label, item resource path]
var _stats: Node = null
var _tools: Node = null
var _crosshair: Node = null
var _hovered_item_key: String = ""
var _hovered_price_text: String = ""  # cached price-per-slot string for current hover

# Cached config — loaded once on ready, refreshed by MCM on save
var _conf: Dictionary = {}
var _config_mtime: int = -1       # last-seen modification time of config.ini
var _traders_mtime: int = -1     # last-seen modification time of Traders.tres
var _traders_os_path: String = "" # resolved OS path cached at startup

# All category and rarity colors are now read from MCM config.
# Defaults (alpha baked in at 0.15) are used when no config file exists.
const DEFAULT_OPACITY = 0.15

const ALL_CATEGORIES = [
	"Ammo", "Armor", "Attachments", "Backpacks", "Belts",
	"Books", "Clothing", "Consumables", "Electronics", "Fishing",
	"Grenades", "Helmets", "Instruments", "Keys", "Knives",
	"Lore", "Medical", "Misc", "Rigs", "Weapons",
]


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_conf = _read_config()
	_config_mtime = FileAccess.get_modified_time(CONFIG_PATH)
	var panel = load("res://ItemClarity/Scripts/SettingsPanel.gd").new()
	panel.config_node = _find_config_node()
	panel.main_node = self
	add_child(panel)
	_tooltip_rework = load("res://ItemClarity/Scripts/TooltipRework.gd").new()
	_tooltip_rework.set_enabled(_conf.get("tooltip_rework", true))
	add_child(_tooltip_rework)
	_compat = load("res://ItemClarity/Scripts/CompatHighlight.gd").new()
	_apply_compat_config()
	add_child(_compat)
	_stats = load("res://ItemClarity/Scripts/StatPreview.gd").new()
	_stats.compat = _compat
	_stats.configure(_conf.get("stat_preview", true), _conf.get("stat_preview", true))
	add_child(_stats)
	_counter = load("res://ItemClarity/Scripts/ItemCounter.gd").new()
	add_child(_counter)
	_tools = load("res://ItemClarity/Scripts/InventoryTools.gd").new()
	_tools.counter = _counter
	_apply_tools_config()
	add_child(_tools)
	_crosshair = load("res://ItemClarity/Scripts/Crosshair.gd").new()
	add_child(_crosshair)
	_apply_crosshair_config()
	_ground = load("res://ItemClarity/Scripts/GroundHighlight.gd").new()
	add_child(_ground)
	_apply_ground_config()
	_tools.ground = _ground
	# Search must be the root's last child so it gets keyboard input before the game
	_search = load("res://ItemClarity/Scripts/SearchBox.gd").new()
	_search.set_enabled(_conf.get("search_box", true))
	_apply_keybinds()
	get_tree().root.add_child.call_deferred(_search)
	_traders_os_path = ProjectSettings.globalize_path("user://Traders.tres")
	_traders_mtime = FileAccess.get_modified_time(_traders_os_path)
	_load_task_data()
	_load_recipe_data()
	_scan_existing_items()
	_find_and_setup_tooltip(get_tree().get_root())
	get_tree().node_added.connect(_on_node_added)
	# Slow timer: refreshes task completion state (e.g. after finishing a task)
	var timer = Timer.new()
	timer.wait_time = 5.0
	timer.autostart = true
	timer.timeout.connect(_on_rescan_timer)
	add_child(timer)
	# Fast timer: turns task markers green once you own enough
	var icon_timer = Timer.new()
	icon_timer.wait_time = 1.0
	icon_timer.autostart = true
	icon_timer.timeout.connect(_recolor_task_icons)
	add_child(icon_timer)


func _on_node_added(node: Node) -> void:
	if _ground:
		_ground.track(node)
	if _counter:
		_counter.track(node)
	if _search and node != _search and node.get_parent() == get_tree().root:
		_keep_search_last.call_deferred()
	if not _is_item_node(node):
		if node.name == "Tooltip" and node is Control:
			node.ready.connect(_setup_tooltip_label.bind(node), CONNECT_ONE_SHOT)
		elif node.name == "Interface" and "tooltipDelay" in node:
			_apply_tooltip_delay(node)
			if _tooltip_rework:
				_tooltip_rework.interface = node
			if _compat:
				_compat.interface = node
			if _counter:
				_counter.interface = node
			if _stats:
				_stats.interface = node
			if _ground:
				_ground.interface = node
			if _tools:
				_tools.interface = node
			if _search:
				_search.interface = node
		return
	if _compat:
		_compat.track(node)
	if _search:
		_search.track(node)
	if node.is_node_ready():
		apply_color_to_item(node)
		apply_task_icon(node)
		apply_recipe_hover(node)
	else:
		node.ready.connect(func():
			apply_color_to_item(node)
			apply_task_icon(node)
			apply_recipe_hover(node)
		, CONNECT_ONE_SHOT)


func _on_rescan_timer() -> void:
	# Pick up hand edits to config.ini (or saves from anything else) without a restart
	if FileAccess.get_modified_time(CONFIG_PATH) != _config_mtime:
		refresh_all_slots()
	var mtime: int = FileAccess.get_modified_time(_traders_os_path)
	if mtime == _traders_mtime:
		# File unchanged — skip expensive reload entirely
		if _tooltip_quest_label == null or not is_instance_valid(_tooltip_quest_label) \
				or _tooltip_recipe_label == null or not is_instance_valid(_tooltip_recipe_label) \
				or _tooltip_price_label == null or not is_instance_valid(_tooltip_price_label):
			_tooltip_quest_label = null
			_tooltip_recipe_label = null
			_tooltip_price_label = null
			_find_and_setup_tooltip(get_tree().get_root())
		return
	_traders_mtime = mtime
	var old_paths = _task_needed_paths.duplicate()
	_load_task_data()
	if _task_needed_paths != old_paths:
		_scan_existing_items()


func _find_and_setup_tooltip(node: Node) -> void:
	if _tooltip_quest_label != null:
		return
	if node.name == "Tooltip" and node is Control:
		_setup_tooltip_label(node)
	if _tooltip_quest_label != null:
		return
	for child in node.get_children():
		_find_and_setup_tooltip(child)


func refresh_all_slots() -> void:
	_conf = _read_config()
	_config_mtime = FileAccess.get_modified_time(CONFIG_PATH)
	if _tooltip_rework:
		_tooltip_rework.set_enabled(_conf.get("tooltip_rework", true))
	if _compat:
		_apply_compat_config()
	if _search:
		_search.set_enabled(_conf.get("search_box", true))
		_apply_keybinds()
	if _ground:
		_apply_ground_config()
	if _tools:
		_apply_tools_config()
	if _crosshair:
		_apply_crosshair_config()
	if _stats:
		_stats.configure(_conf.get("stat_preview", true), _conf.get("stat_preview", true))
	_remove_all_overlays(get_tree().get_root())
	_load_task_data()
	_load_recipe_data()
	_scan_existing_items()
	var interface = get_node_or_null("/root/Map/Core/UI/Interface")
	if interface and "tooltipDelay" in interface:
		_apply_tooltip_delay(interface)


func _apply_crosshair_config() -> void:
	_crosshair.configure(
		_conf.get("crosshair_mode", 2),
		_conf.get("crosshair_color", Color(1.0, 1.0, 1.0, 0.85)),
		_conf.get("crosshair_size", 2.5))


const KeyUtil = preload("res://ItemClarity/Scripts/KeyUtil.gd")


# Keybinds live on the search box layer, which sees keys before the game
func _apply_keybinds() -> void:
	var binds: Dictionary = _conf.get("binds", {})
	_search.focus_bind = binds.get("icFocusSearch", KeyUtil.make_bind(KEY_SPACE))
	_search.hotkeys = [
		[binds.get("icSort", KeyUtil.make_bind(0)), _tools.sort_hotkey],
		[binds.get("icQuickStack", KeyUtil.make_bind(0)), _tools.quick_stack_hotkey],
	]


# Called by the settings panel while it waits for a new keybind
func set_key_capture(on: bool) -> void:
	if _search:
		_search.capturing = on


func _apply_tools_config() -> void:
	_tools.configure(
		_conf.get("inventory_tools", true),
		_conf.get("quick_stack_range", 6.0))


func _apply_ground_config() -> void:
	_ground.set_style(_conf.get("world_style", 0))
	_ground.set_dot_centered(_conf.get("world_dot_centered", true))
	_ground.configure(
		_conf.get("ground_highlight", true),
		_conf.get("ground_distance", 8.0),
		_conf.get("ground_color", Color("#ffffff26")),
		_conf.get("ground_shelters", false))
	_ground.configure_containers(
		_conf.get("container_highlight", false),
		_conf.get("container_distance", 8.0),
		_conf.get("container_color", Color("#ffd24d26")))


func _keep_search_last() -> void:
	if _search and _search.is_inside_tree():
		var root = get_tree().root
		root.move_child(_search, root.get_child_count() - 1)


func _apply_compat_config() -> void:
	_compat.set_color(_conf.get("compat_color", Color("#ffffff46")))
	_compat.set_enabled(_conf.get("compat_highlight", true))


func _apply_tooltip_delay(interface: Node) -> void:
	var cfg = ConfigFile.new()
	var delay: float = 0.1
	if cfg.load(CONFIG_PATH) == OK:
		var v = cfg.get_value("Float", "tooltipDelay", 0.1)
		delay = float(v.get("value", 0.1) if v is Dictionary else v)
	interface.tooltipDelay = delay


func _remove_all_overlays(node: Node) -> void:
	var existing = node.get_node_or_null(OVERLAY_NODE_NAME)
	if existing:
		existing.free()
	var existing_icon = node.get_node_or_null(TASK_ICON_NODE_NAME)
	if existing_icon:
		existing_icon.free()
	var existing_hover = node.get_node_or_null("_icc_hover")
	if existing_hover:
		existing_hover.free()
	for child in node.get_children():
		_remove_all_overlays(child)


func _read_config() -> Dictionary:
	var result = {
		"color_coding_mode": 0,  # 0=Category, 1=Rarity, 2=Value, 3=None
		"value_metric":      0,  # 0=Per Slot, 1=Total
		"val_colors": VALUE_TIER_DEFAULTS.duplicate(),
		"task_marking":       true,
		"noted_tasks_only":   false,
		"recipe_tooltip":     true,
		"price_per_slot":     true,
		"tooltip_rework":     true,
		"compat_highlight":   true,
		"search_box":         true,
		"inventory_tools":    true,
		"quick_stack_range":  6.0,
		"stat_preview":       true,
		"ground_highlight":   true,
		"ground_distance":    8.0,
		"ground_color":       Color("#ffffff26"),
		"ground_shelters":    false,
		"world_style":        0,
		"crosshair_mode":     2,
		"crosshair_color":    Color(1.0, 1.0, 1.0, 0.85),
		"crosshair_size":     2.5,
		"world_dot_centered": true,
		"container_highlight": false,
		"container_distance": 8.0,
		"container_color":    Color("#ffd24d26"),
		"task_have_count":    true,
		"compare_equipped":   true,
		"task_details_always": false,
		"compat_color":       Color("#ffffff46"),
		"cat_colors": {
			"Ammo":        Color(0.15, 0.65, 0.15, DEFAULT_OPACITY),
			"Armor":       Color(0.55, 0.15, 0.75, DEFAULT_OPACITY),
			"Attachments": Color(0.15, 0.65, 0.15, DEFAULT_OPACITY),
			"Backpacks":   Color(0.55, 0.15, 0.75, DEFAULT_OPACITY),
			"Belts":       Color(0.55, 0.15, 0.75, DEFAULT_OPACITY),
			"Books":       Color(0.0,  0.0,  0.0,  0.0),
			"Clothing":    Color(0.55, 0.15, 0.75, DEFAULT_OPACITY),
			"Consumables": Color(0.90, 0.60, 0.05, DEFAULT_OPACITY),
			"Electronics": Color(0.0,  0.0,  0.0,  0.0),
			"Fishing":     Color(0.0,  0.0,  0.0,  0.0),
			"Grenades":    Color(0.15, 0.65, 0.15, DEFAULT_OPACITY),
			"Helmets":     Color(0.55, 0.15, 0.75, DEFAULT_OPACITY),
			"Instruments": Color(0.0,  0.0,  0.0,  0.0),
			"Keys":        Color(0.95, 0.40, 0.70, DEFAULT_OPACITY),
			"Knives":      Color(0.25, 0.25, 0.25, DEFAULT_OPACITY),
			"Lore":        Color(0.0,  0.0,  0.0,  0.0),
			"Medical":     Color(0.85, 0.10, 0.10, DEFAULT_OPACITY),
			"Misc":        Color(0.0,  0.0,  0.0,  0.0),
			"Rigs":        Color(0.55, 0.15, 0.75, DEFAULT_OPACITY),
			"Weapons":     Color(0.25, 0.25, 0.25, DEFAULT_OPACITY),
		},
		"rar_colors": {
			0: Color(0.40, 0.40, 0.40, DEFAULT_OPACITY),
			1: Color(0.60, 0.20, 0.80, DEFAULT_OPACITY),
			2: Color(1.00, 0.65, 0.00, DEFAULT_OPACITY),
		},
	}
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		print("[IC] config file not found, using defaults")
		return result
	result["color_coding_mode"] = _get_int(cfg, "Dropdown", "colorCodingMode", 0)
	result["task_marking"]       = _get_bool(cfg, "Bool", "taskMarking",         true)
	result["noted_tasks_only"]   = _get_bool(cfg, "Bool", "notedTasksOnly",      false)
	result["recipe_tooltip"]     = _get_bool(cfg, "Bool", "recipeTooltip",       true)
	result["price_per_slot"]     = _get_bool(cfg, "Bool", "pricePerSlot",        true)
	result["tooltip_rework"]     = _get_bool(cfg, "Bool", "tooltipRework",       true)
	result["task_details_always"] = _get_bool(cfg, "Bool", "taskDetailsAlways", false)
	result["compare_equipped"]   = _get_bool(cfg, "Bool", "compareEquipped",    true)
	result["task_have_count"]    = _get_bool(cfg, "Bool", "taskHaveCount",       true)
	result["ground_highlight"]   = _get_bool(cfg, "Bool", "groundHighlight",     true)
	result["ground_distance"]    = _get_float(cfg, "Float", "groundHighlightDistance", 8.0)
	result["ground_color"]       = _get_color(cfg, "Color", "groundHighlightColor", Color("#ffffff26"))
	result["crosshair_mode"]     = _get_int(cfg, "Dropdown", "crosshairMode", 2)
	result["crosshair_color"]    = _get_color(cfg, "Color", "crosshairColor", Color(1.0, 1.0, 1.0, 0.85))
	result["crosshair_size"]     = _get_float(cfg, "Float", "crosshairSize", 2.5)
	result["world_style"]        = _get_int(cfg, "Dropdown", "worldHighlightStyle", 0)
	result["world_dot_centered"] = _get_int(cfg, "Dropdown", "worldDotPosition", 1) == 1
	result["ground_shelters"]    = _get_bool(cfg, "Bool", "groundHighlightShelters", false)
	result["container_highlight"] = _get_bool(cfg, "Bool", "containerHighlight",  false)
	result["container_distance"] = _get_float(cfg, "Float", "containerHighlightDistance", 8.0)
	result["container_color"]    = _get_color(cfg, "Color", "containerHighlightColor", Color("#ffd24d26"))
	result["stat_preview"]       = _get_bool(cfg, "Bool", "statPreview",         true)
	result["binds"] = {
		"icFocusSearch": KeyUtil.make_bind(cfg.get_value("Keycode", "icFocusSearch", KEY_SPACE)),
		"icSort":        KeyUtil.make_bind(cfg.get_value("Keycode", "icSort", 0)),
		"icQuickStack":  KeyUtil.make_bind(cfg.get_value("Keycode", "icQuickStack", 0)),
		"icTaskDetails": KeyUtil.make_bind(cfg.get_value("Keycode", "icTaskDetails", KEY_ALT)),
	}
	result["inventory_tools"]    = _get_bool(cfg, "Bool", "inventoryTools",      true)
	result["quick_stack_range"]  = _get_float(cfg, "Float", "quickStackRange",   6.0)
	result["search_box"]         = _get_bool(cfg, "Bool", "searchBox",           true)
	result["compat_highlight"]   = _get_bool(cfg, "Bool", "compatHighlight",     true)
	result["compat_color"]       = _get_color(cfg, "Color", "compatHighlightColor", Color("#ffffff46"))
	result["cat_colors"] = {
		"Ammo":        _get_color(cfg, "Color", "catAmmo",        Color(0.15, 0.65, 0.15, DEFAULT_OPACITY)),
		"Armor":       _get_color(cfg, "Color", "catArmor",       Color(0.55, 0.15, 0.75, DEFAULT_OPACITY)),
		"Attachments": _get_color(cfg, "Color", "catAttachments", Color(0.15, 0.65, 0.15, DEFAULT_OPACITY)),
		"Backpacks":   _get_color(cfg, "Color", "catBackpacks",   Color(0.55, 0.15, 0.75, DEFAULT_OPACITY)),
		"Belts":       _get_color(cfg, "Color", "catBelts",       Color(0.55, 0.15, 0.75, DEFAULT_OPACITY)),
		"Books":       _get_color(cfg, "Color", "catBooks",       Color(0.0,  0.0,  0.0,  0.0)),
		"Clothing":    _get_color(cfg, "Color", "catClothing",    Color(0.55, 0.15, 0.75, DEFAULT_OPACITY)),
		"Consumables": _get_color(cfg, "Color", "catConsumables", Color(0.90, 0.60, 0.05, DEFAULT_OPACITY)),
		"Electronics": _get_color(cfg, "Color", "catElectronics", Color(0.0,  0.0,  0.0,  0.0)),
		"Fishing":     _get_color(cfg, "Color", "catFishing",     Color(0.0,  0.0,  0.0,  0.0)),
		"Grenades":    _get_color(cfg, "Color", "catGrenades",    Color(0.15, 0.65, 0.15, DEFAULT_OPACITY)),
		"Helmets":     _get_color(cfg, "Color", "catHelmets",     Color(0.55, 0.15, 0.75, DEFAULT_OPACITY)),
		"Instruments": _get_color(cfg, "Color", "catInstruments", Color(0.0,  0.0,  0.0,  0.0)),
		"Keys":        _get_color(cfg, "Color", "catKeys",        Color(0.95, 0.40, 0.70, DEFAULT_OPACITY)),
		"Knives":      _get_color(cfg, "Color", "catKnives",      Color(0.25, 0.25, 0.25, DEFAULT_OPACITY)),
		"Lore":        _get_color(cfg, "Color", "catLore",        Color(0.0,  0.0,  0.0,  0.0)),
		"Medical":     _get_color(cfg, "Color", "catMedical",     Color(0.85, 0.10, 0.10, DEFAULT_OPACITY)),
		"Misc":        _get_color(cfg, "Color", "catMisc",        Color(0.0,  0.0,  0.0,  0.0)),
		"Rigs":        _get_color(cfg, "Color", "catRigs",        Color(0.55, 0.15, 0.75, DEFAULT_OPACITY)),
		"Weapons":     _get_color(cfg, "Color", "catWeapons",     Color(0.25, 0.25, 0.25, DEFAULT_OPACITY)),
	}
	result["rar_colors"] = {
		0: _get_color(cfg, "Color", "rarCommon",    Color(0.40, 0.40, 0.40, DEFAULT_OPACITY)),
		1: _get_color(cfg, "Color", "rarRare",      Color(0.60, 0.20, 0.80, DEFAULT_OPACITY)),
		2: _get_color(cfg, "Color", "rarLegendary", Color(1.00, 0.65, 0.00, DEFAULT_OPACITY)),
	}
	result["value_metric"] = _get_int(cfg, "Dropdown", "valueMetric", 0)
	var val_colors: Array = []
	for i in VALUE_TIER_KEYS.size():
		val_colors.append(_get_color(cfg, "Color", VALUE_TIER_KEYS[i], VALUE_TIER_DEFAULTS[i]))
	result["val_colors"] = val_colors
	return result


func _get_int(cfg: ConfigFile, section: String, key: String, default: int) -> int:
	var v = cfg.get_value(section, key, default)
	if v is Dictionary: return int(v.get("value", default))
	return int(v)


func _get_float(cfg: ConfigFile, section: String, key: String, default: float) -> float:
	var v = cfg.get_value(section, key, default)
	if v is Dictionary: return float(v.get("value", default))
	return float(v)


func _get_bool(cfg: ConfigFile, section: String, key: String, default: bool) -> bool:
	var v = cfg.get_value(section, key, default)
	if v is Dictionary: return v.get("value", default)
	return bool(v)


func _get_color(cfg: ConfigFile, section: String, key: String, default: Color) -> Color:
	var v = cfg.get_value(section, key, default)
	if v is Dictionary: return v.get("value", default)
	if v is Color: return v
	return default


# ── Compare with equipped gear ───────────────────────────────────────────────
# Hovering gear or a weapon (not the one you're wearing) shows how it differs
# from what's equipped in its slot. ItemData.slots names the slots an item fits;
# each is a Slot panel under Interface.equipment, holding the equipped item as
# its first child (the same check the game uses to allow equipping).

const COMPARE_BETTER = Color(0.45, 0.9, 0.45)
const COMPARE_WORSE = Color(1.0, 0.45, 0.4)
const COMPARE_HEADER = Color(0.6, 0.6, 0.6)


func _compare_text(item: Node) -> String:
	if not _conf.get("compare_equipped", true) or not ("slotData" in item):
		return ""
	if "equipped" in item and item.equipped:
		return ""  # this is the equipped one
	var data = item.slotData.itemData
	if data == null or not ("slots" in data) or data.slots.is_empty():
		return ""
	var ui = _tooltip_rework.interface if _tooltip_rework else null
	if ui == null or not is_instance_valid(ui) or not ("equipment" in ui) or ui.equipment == null:
		return ""

	# Items like pistols list both Primary and Secondary, so pick the equipped
	# item most like this one: same weaponType (pistol vs rifle), then same
	# subtype, then whatever occupies the first slot it fits
	var candidates: Array = []
	var has_free_slot := false
	for slot_name in data.slots:
		var slot = ui.equipment.get_node_or_null(str(slot_name))
		if slot and slot.get_child_count() > 0 and "slotData" in slot.get_child(0):
			candidates.append(slot.get_child(0))
		elif slot:
			has_free_slot = true
	var equipped: Node = _most_similar(data, candidates, has_free_slot)

	var rows: Array = []
	for stat in _compare_stats(data):
		var mine: float = _stat_value(item, stat[0])
		var theirs: float = _stat_value(equipped, stat[0]) if equipped else 0.0
		if is_equal_approx(mine, theirs):
			continue
		var diff: float = mine - theirs
		var better: bool = (diff > 0.0) == stat[2]
		rows.append("[color=#%s]%s[/color]" % [(COMPARE_BETTER if better else COMPARE_WORSE).to_html(false),
			_format_stat(stat, mine, theirs, diff, equipped != null)])
	if rows.is_empty():
		return ""
	var header := "vs equipped " + _bb_escape(str(equipped.slotData.itemData.name)) if equipped else "Nothing equipped in that slot"
	return "[color=#%s]%s[/color]\n%s" % [COMPARE_HEADER.to_html(false), header, "\n".join(rows)]


# A pistol with your Secondary slot free shouldn't be compared to your rifle:
# with no similar item equipped and a slot free, it counts as "nothing equipped"
func _most_similar(data: Resource, candidates: Array, has_free_slot: bool) -> Node:
	if candidates.is_empty():
		return null
	for field in ["weaponType", "subtype"]:
		if not (field in data) or str(data.get(field)) == "":
			continue
		for c in candidates:
			var other = c.slotData.itemData
			if field in other and str(other.get(field)) == str(data.get(field)):
				return c
	return null if has_free_slot else candidates[0]


# [key, label, higher_is_better, unit, is_level]
func _compare_stats(data: Resource) -> Array:
	var stats: Array = []
	var type: String = str(data.type) if "type" in data else ""
	if type == "Weapon":
		stats.append(["damage", "Damage", true, "", false])
		stats.append(["penetration", "Penetration", true, "", true])
	if type in ["Armor", "Helmet", "Rig"]:
		stats.append(["protection", "Protection", true, "", true])
	stats.append(["capacity", "Capacity", true, " kg", false])
	stats.append(["insulation", "Insulation", true, "", false])
	stats.append(["weight", "Weight", false, " kg", false])
	return stats


func _stat_value(item: Node, key: String) -> float:
	if item == null or not ("slotData" in item) or item.slotData == null:
		return 0.0
	var data = item.slotData.itemData
	match key:
		"weight":
			return float(item.Weight()) if item.has_method("Weight") else float(data.weight)
		"protection":
			# A rig's armour level comes from the plate inserted in it (as in the game's tooltip)
			if str(data.type) == "Rig" and "nested" in item.slotData:
				for nested in item.slotData.nested:
					if nested and str(nested.type) == "Armor":
						return float(nested.protection)
				return 0.0
			return float(data.protection) if "protection" in data else 0.0
	return float(data.get(key)) if key in data and data.get(key) != null else 0.0


func _format_stat(stat: Array, mine: float, theirs: float, diff: float, has_equipped: bool) -> String:
	var label: String = stat[1]
	var unit: String = stat[3]
	if stat[4]:  # levels read better as "3 -> 4"
		return "%s Level %d -> %d" % [label, int(theirs), int(mine)] if has_equipped else "%s Level %d" % [label, int(mine)]
	var plus_minus := "+" if diff > 0.0 else "-"
	var amount: float = absf(diff)
	var text := str(int(round(amount))) if is_equal_approx(amount, round(amount)) or amount >= 10.0 else "%.1f" % amount
	return "%s %s%s%s" % [label, plus_minus, text, unit]


# ── Value color coding ───────────────────────────────────────────────────────
# Items are tiered against every lootable item in the game (LT_Master), by
# percentile, because prices are heavily skewed: a linear scale would paint
# almost everything the "cheap" colour.

const VALUE_TIER_KEYS = ["valLow", "valFair", "valGood", "valGreat", "valTop"]
const VALUE_TIER_DEFAULTS = [
	Color(0.45, 0.45, 0.45, 0.15), Color(0.30, 0.75, 0.35, 0.15), Color(0.25, 0.55, 0.95, 0.15),
	Color(0.65, 0.30, 0.90, 0.15), Color(1.00, 0.70, 0.10, 0.18),
]
const VALUE_PERCENTILES = [0.40, 0.70, 0.88, 0.95]  # tier boundaries
var _value_cuts: Dictionary = {}  # metric -> [4 boundary values]


const VALUE_TIER_NAMES = ["Low", "Fair", "Good", "Great", "Elite"]


# Tier of an item on the game-wide value scale (0 = Low ... 4 = Top), using the
# Value Measure setting so it always agrees with Value colour coding
func _value_tier(item: Node) -> int:
	var metric: int = _conf.get("value_metric", 0)
	var cuts: Array = _value_boundaries(metric)
	var v: float = _item_value(item, metric)
	var tier := 0
	while tier < cuts.size() and v >= cuts[tier]:
		tier += 1
	return tier


# "(Great)" in the tier's colour at full strength (the item tints are ~15%
# alpha, unreadable as text). Shown whether or not Value colour coding is on.
func _value_tier_bbcode(item: Node) -> String:
	var tier := _value_tier(item)
	var colors: Array = _conf.get("val_colors", VALUE_TIER_DEFAULTS)
	var c: Color = colors[tier] if tier < colors.size() else Color.WHITE
	c.a = 1.0
	if c.get_luminance() < 0.45:
		c = c.lightened(0.45)  # keep dark tier colours readable on the dark tooltip
	return "[color=#%s](%s)[/color]" % [c.to_html(false), VALUE_TIER_NAMES[tier]]


func _value_color(item: Node) -> Color:
	var tier := _value_tier(item)
	var colors: Array = _conf.get("val_colors", VALUE_TIER_DEFAULTS)
	return colors[tier] if tier < colors.size() else Color(0, 0, 0, 0)


# Live value, the same number the tooltip shows (stack amount, loaded ammo,
# condition, attachments), per slot or in total
func _item_value(item: Node, metric: int) -> float:
	var data = item.slotData.itemData
	var value: float = float(item.Value()) if item.has_method("Value") else float(data.value)
	if metric == 1:
		return value
	return value / float(max(1, int(data.size.x) * int(data.size.y)))


func _value_boundaries(metric: int) -> Array:
	if _value_cuts.has(metric):
		return _value_cuts[metric]
	var values: Array = []
	var master = load("res://Loot/LT_Master.tres")
	if master and "items" in master:
		var seen: Dictionary = {}
		for data in master.items:
			if data == null or seen.has(data.resource_path):
				continue
			seen[data.resource_path] = true
			var v: float = float(data.value)
			if metric == 0:
				v /= float(max(1, int(data.size.x) * int(data.size.y)))
			values.append(v)
	var cuts: Array = []
	if values.size() >= 10:
		values.sort()
		for p in VALUE_PERCENTILES:
			cuts.append(values[min(values.size() - 1, int(p * values.size()))])
	else:
		# Loot table unavailable: rough fixed boundaries in euros
		cuts = [40.0, 120.0, 350.0, 900.0] if metric == 0 else [100.0, 400.0, 1200.0, 3000.0]
	_value_cuts[metric] = cuts
	print("[ItemClarity] value tiers (%s): %s" % ["per slot" if metric == 0 else "total", str(cuts)])
	return cuts


func _get_category(item: Node) -> String:
	var path: String = item.slotData.itemData.resource_path
	# path looks like res://Items/Medical/bandage.tres
	for category in ALL_CATEGORIES:
		if path.contains("/" + category + "/"):
			return category
	return ""


func apply_color_to_item(item: Node) -> void:
	if not "slotData" in item or item.slotData == null:
		return
	if item.slotData.itemData == null:
		return

	if item.get_node_or_null(OVERLAY_NODE_NAME) != null:
		return

	var color: Color = Color(0, 0, 0, 0)
	var mode: int = _conf.get("color_coding_mode", 0)

	if mode == 0:
		# Category coding
		var cat = _get_category(item)
		if cat != "":
			color = _conf["cat_colors"].get(cat, Color(0, 0, 0, 0))
		# Fall back to rarity if category has no color assigned
		if color.a == 0:
			var rarity: int = item.slotData.itemData.rarity
			color = _conf["rar_colors"].get(rarity, Color(0, 0, 0, 0))
	elif mode == 1:
		# Rarity coding only
		var rarity: int = item.slotData.itemData.rarity
		color = _conf["rar_colors"].get(rarity, Color(0, 0, 0, 0))
	elif mode == 2:
		color = _value_color(item)
	# mode == 3 (None): color stays transparent

	if color.a == 0:
		return
	# Color alpha is configured per-color (set via MCM color picker)

	var overlay = Panel.new()
	overlay.name = OVERLAY_NODE_NAME
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	var style = StyleBoxFlat.new()
	style.bg_color = color
	overlay.add_theme_stylebox_override("panel", style)

	item.add_child(overlay)
	item.move_child(overlay, 0)


func _scan_existing_items() -> void:
	_walk_and_color(get_tree().get_root())


func _walk_and_color(node: Node) -> void:
	if _ground:
		_ground.track(node)
	if _counter:
		_counter.track(node)
	if _is_item_node(node):
		if _compat:
			_compat.track(node)
		if _search:
			_search.track(node)
		apply_color_to_item(node)
		apply_task_icon(node)
		apply_recipe_hover(node)
	for child in node.get_children():
		_walk_and_color(child)


# Runs for every node the game adds (bullets, particles, sounds...), so the
# cheap class check goes first and the by-name property lookup second
func _is_item_node(node: Node) -> bool:
	return node is Panel and "slotData" in node

# ── Recipe tracking ──────────────────────────────────────────────────────────

func _load_recipe_data() -> void:
	_crafting_recipe_paths = {}
	if not _conf.get("recipe_tooltip", true):
		return
	var recipes_res = load("res://Crafting/Recipes.tres")
	if recipes_res == null:
		return
	# Recipes.tres stores recipes in per-category properties (not a single array):
	# consumables, electronics, equipment, furniture, medical, misc, weapons
	const CATEGORY_PROPS = ["consumables", "electronics", "equipment", "furniture", "medical", "misc", "weapons"]
	for cat_prop in CATEGORY_PROPS:
		if not (cat_prop in recipes_res):
			continue
		var recipe_list = recipes_res.get(cat_prop)
		if recipe_list == null:
			continue
		for recipe in recipe_list:
			if recipe == null:
				continue
			# Skip weapon repair recipes
			var is_repair: bool = recipe.get("repair") if "repair" in recipe else false
			if is_repair:
				continue
			var recipe_name: String = recipe.get("name") if "name" in recipe else ""
			var inputs = recipe.get("input") if "input" in recipe else null
			if inputs == null or recipe_name == "":
				continue
			for ingredient in inputs:
				if ingredient == null:
					continue
				var key: String = ingredient.resource_path
				if key == "":
					continue
				if key not in _crafting_recipe_paths:
					_crafting_recipe_paths[key] = []
				if recipe_name not in _crafting_recipe_paths[key]:
					_crafting_recipe_paths[key].append(recipe_name)


func apply_recipe_hover(item: Node) -> void:
	if not _conf.get("recipe_tooltip", true) and not _conf.get("price_per_slot", true):
		return
	if not "slotData" in item or item.slotData == null:
		return
	if item.slotData.itemData == null:
		return
	var key: String = item.slotData.itemData.resource_path
	# Only add hover zone if this item has something to show in the tooltip
	var has_recipe = _conf.get("recipe_tooltip", true) and _crafting_recipe_paths.has(key)
	var has_price = _conf.get("price_per_slot", true) and key != ""
	if not has_recipe and not has_price:
		return
	# Reuse the existing hover zone if already added by apply_task_icon,
	# otherwise we need our own hover connection
	var hover_zone = item.get_node_or_null("_icc_hover")
	if hover_zone == null:
		hover_zone = Control.new()
		hover_zone.name = "_icc_hover"
		hover_zone.mouse_filter = Control.MOUSE_FILTER_PASS
		hover_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
		item.add_child(hover_zone)
		# Pass both the item node and the key so both price and task tooltips work
		hover_zone.mouse_entered.connect(_on_task_item_mouse_entered.bind(item, key))
		hover_zone.mouse_exited.connect(_on_task_item_mouse_exited)


# ── Task tracking ─────────────────────────────────────────────────────────────

func _load_task_data() -> void:
	_task_needed_paths = {}
	if not _conf.get("task_marking", true):
		return

	# Load save data to know which tasks are completed per trader
	var trader_save = load("user://Traders.tres") if FileAccess.file_exists("user://Traders.tres") else null

	# Build set of noted task resource paths if the filter is enabled
	var noted_paths: Dictionary = {}
	var noted_only: bool = _conf.get("noted_tasks_only", false)
	if noted_only and trader_save and trader_save.get("taskNotes") != null:
		for noted_task in trader_save.get("taskNotes"):
			if noted_task != null and noted_task.resource_path != "":
				noted_paths[noted_task.resource_path] = true

	var trader_dirs = DirAccess.get_directories_at("res://Traders/")
	if trader_dirs.is_empty():
		return

	for trader_id in trader_dirs:
		var trader_res_path = "res://Traders/" + trader_id + "/" + trader_id + ".tres"
		var trader = load(trader_res_path)
		if trader == null:
			continue
		if not ("tasks" in trader) or trader.tasks == null:
			continue

		# TraderSave stores completed task names in a lowercase property per trader
		# (generalist, doctor, gunsmith, driver, hunter, ...)
		var completed: Array = []
		if trader_save:
			var saved = trader_save.get(trader_id.to_lower())
			if saved != null:
				completed = _to_string_array(saved)

		for task in trader.tasks:
			if task == null or not ("name" in task) or not ("deliver" in task):
				continue
			if task.name in completed:
				continue
			if noted_only and task.resource_path not in noted_paths:
				continue
			# Count how many of each item this task needs
			var counts: Dictionary = {}
			for item_data in task.deliver:
				if item_data == null:
					continue
				var key: String = item_data.resource_path
				if key == "":
					continue
				counts[key] = counts.get(key, 0) + 1
			for key in counts:
				if key not in _task_needed_paths:
					_task_needed_paths[key] = []
				var count: int = counts[key]
				# "needs" is shared by every item of this task: what handing it in takes
				_task_needed_paths[key].append({"count": count, "text": trader_id + ": " + task.name, "needs": counts})


func _to_string_array(arr) -> Array:
	var result: Array = []
	for v in arr:
		result.append(str(v))
	return result


func apply_task_icon(item: Node) -> void:
	if not _conf.get("task_marking", true):
		return
	if not "slotData" in item or item.slotData == null:
		return
	if item.slotData.itemData == null:
		return

	var key: String = item.slotData.itemData.resource_path
	var task_info: Array = _task_needed_paths.get(key, [])
	var existing_icon: Node = item.get_node_or_null(TASK_ICON_NODE_NAME)

	if task_info.is_empty():
		# Not a task item  Eremove icon if it was previously added
		if existing_icon:
			existing_icon.queue_free()
		return

	if existing_icon:
		return  # Already has icon

	# Add a small colored label in the top-right corner
	var icon_label = Label.new()
	icon_label.name = TASK_ICON_NODE_NAME
	icon_label.text = "!"
	icon_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.0))  # Gold
	icon_label.add_theme_font_size_override("font_size", 14)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.mouse_filter = Control.MOUSE_FILTER_PASS
	# Circle background
	var circle_style = StyleBoxFlat.new()
	circle_style.bg_color = Color(0.15, 0.15, 0.15, 0.85)
	circle_style.border_color = Color(1.0, 0.75, 0.0)
	circle_style.border_width_left   = 1
	circle_style.border_width_right  = 1
	circle_style.border_width_top    = 1
	circle_style.border_width_bottom = 1
	circle_style.corner_radius_top_left     = 10
	circle_style.corner_radius_top_right    = 10
	circle_style.corner_radius_bottom_left  = 10
	circle_style.corner_radius_bottom_right = 10
	circle_style.content_margin_left  = 3
	circle_style.content_margin_right = 3
	icon_label.add_theme_stylebox_override("normal", circle_style)
	# Top-left corner: the bottom corners clash with stack counts like "30"
	icon_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	icon_label.offset_left = -2
	icon_label.offset_top = 2
	icon_label.offset_right = 18
	icon_label.offset_bottom = 20
	item.add_child(icon_label)
	icon_label.draw.connect(_draw_task_ring.bind(icon_label))
	_task_icons[icon_label.get_instance_id()] = [icon_label, key]
	_color_task_icon(icon_label, key)

	# Invisible full-rect hover zone covers the whole item slot so hovering
	# anywhere on the item triggers the tooltip, not just the "!" icon
	var hover_zone = Control.new()
	hover_zone.name = "_icc_hover"
	hover_zone.mouse_filter = Control.MOUSE_FILTER_PASS
	hover_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	item.add_child(hover_zone)
	# Pass both the item node and the key so both price and task tooltips work
	hover_zone.mouse_entered.connect(_on_task_item_mouse_entered.bind(item, key))
	hover_zone.mouse_exited.connect(_on_task_item_mouse_exited)


const TASK_COLOR = Color(1.0, 0.75, 0.0)       # gold: still needed
const TASK_DONE_COLOR = Color(0.35, 0.9, 0.35)  # green: you own enough for every task


func _recolor_task_icons() -> void:
	if _task_icons.is_empty():
		return
	var interface = _tooltip_rework.interface if _tooltip_rework else null
	if interface == null or not is_instance_valid(interface) or not interface.visible:
		return  # markers are only seen with the inventory open
	for id in _task_icons.keys():
		var entry: Array = _task_icons[id]
		if not is_instance_valid(entry[0]):
			_task_icons.erase(id)
			continue
		_color_task_icon(entry[0], entry[1])


# Marker states: 0 gold (need more), 1 green (enough of this item for every
# task), 2 ready (some task it belongs to can be handed in now: blue-pink ring)
func _color_task_icon(icon: Label, key: String) -> void:
	var state := 0
	if _counter and _conf.get("task_have_count", true):
		var needed := 0
		for task in _task_needed_paths.get(key, []):
			needed += int(task["count"])
			if state < 2 and _task_ready(task.get("needs", {})):
				state = 2
		if state == 0 and needed > 0 and _counter.get_count(key) >= needed:
			state = 1
	# Theme overrides trigger a redraw, so only touch the icon when it changes
	if icon.has_meta("icc_state") and icon.get_meta("icc_state") == state:
		return
	icon.set_meta("icc_state", state)
	var color: Color = [TASK_COLOR, TASK_DONE_COLOR, Color(1, 1, 1)][state]
	icon.add_theme_color_override("font_color", color)
	var style = icon.get_theme_stylebox("normal")
	if style is StyleBoxFlat:
		style.border_color = Color(0, 0, 0, 0) if state == 2 else color  # ring drawn instead
	icon.queue_redraw()


# Blue-to-pink ring for the "ready" state, drawn over the marker's circle
func _draw_task_ring(icon: Label) -> void:
	if not icon.has_meta("icc_state") or icon.get_meta("icc_state") != 2:
		return
	var center: Vector2 = icon.size / 2.0
	var radius: float = min(icon.size.x, icon.size.y) / 2.0 - 0.75
	var segments := 32
	for i in segments:
		var a0: float = TAU * float(i) / segments - PI / 2.0
		var a1: float = TAU * float(i + 1) / segments - PI / 2.0
		# blue at the top, pink at the bottom, like the logo
		var t: float = (1.0 - cos(a0 + PI / 2.0)) / 2.0
		icon.draw_arc(center, radius, a0, a1, 3, READY_BLUE.lerp(READY_PINK, t), 1.5, true)


func _on_task_item_mouse_entered(item: Node, key: String) -> void:
	# Use the item's slotData for durability/condition
	if not "slotData" in item or item.slotData == null or item.slotData.itemData == null:
		_hovered_item_key = ""
		_hovered_price_text = ""
		return
	_hovered_item_key = key
	_hovered_compare_text = _compare_text(item)
	# Pre-compute price-per-slot so _process doesn't recompute it every frame
	_hovered_price_text = ""
	if _conf.get("price_per_slot", true) and key != "":
		var data = item.slotData.itemData
		var value: float
		if item.has_method("Value"):
			# Same number the tooltip shows as "Value": stack amount for ammo,
			# loaded rounds for magazines/weapons, condition and attachments
			value = float(item.Value())
		else:
			var condition := 1.0
			if "condition" in item.slotData and item.slotData.condition != null:
				condition = float(item.slotData.condition) / 100.0
			value = float(data.value) * condition
		var size: Vector2 = data.size
		var slots: int = max(1, int(size.x) * int(size.y))
		var pps: int = int(round(value / float(slots)))
		_hovered_price_text = str(pps) + "€ / slot  " + _value_tier_bbcode(item)

# "x2 for Gunsmith: Warm Meal (have 1/2)", coloured gold (need more), green
# (enough of this item) or with a blue-pink "Ready" (whole task can be handed
# in). Holding the Task Details key lists the task's other items too.
func _format_task_lines(key: String, task_info: Array) -> Array:
	var show_have: bool = _conf.get("task_have_count", true) and _counter != null
	var have: int = _counter.get_count(key) if show_have else 0
	var details := _task_details_held()
	var lines: Array = []
	var has_others := false
	for task in task_info:
		var line = "x" + str(task["count"]) + " for " + _bb_escape(task["text"])
		if not show_have:
			lines.append(line)
			continue
		line += " (have " + str(have) + "/" + str(task["count"]) + ")"
		var needs: Dictionary = task.get("needs", {})
		if _task_ready(needs):
			line = "[color=#%s]%s[/color]  %s" % [TASK_DONE_COLOR.to_html(false), line, _gradient_text("Ready")]
		elif have >= int(task["count"]):
			line = "[color=#%s]%s[/color]" % [TASK_DONE_COLOR.to_html(false), line]
		lines.append(line)
		if needs.size() > 1:
			has_others = true
			if details:
				for other in needs:
					if other == key:
						continue
					var need: int = int(needs[other])
					var got: int = _counter.get_count(other)
					var c: Color = TASK_DONE_COLOR if got >= need else TASK_MISSING_COLOR
					lines.append("   [color=#%s]- %s %d/%d[/color]" % [c.to_html(false), _bb_escape(_item_name(other)), got, need])
	if has_others and not details:
		var key_name: String = KeyUtil.label(_conf.get("binds", {}).get("icTaskDetails", KeyUtil.make_bind(KEY_ALT)))
		lines.append("[color=#8a8a8a][font_size=11]Hold %s for task details[/font_size][/color]" % key_name)
	return lines


const TASK_MISSING_COLOR = Color(1.0, 0.5, 0.45)
const READY_BLUE = Color(0.243, 0.776, 1.0)   # same fade as the mod's logo
const READY_PINK = Color(1.0, 0.31, 0.72)
var _item_names: Dictionary = {}


# Every item this task needs is owned in the required amount. Judged per task:
# two tasks sharing your only Beer can both show ready, since either one could
# be handed in right now.
func _task_ready(needs: Dictionary) -> bool:
	if _counter == null or needs.is_empty():
		return false
	for k in needs:
		if _counter.get_count(k) < int(needs[k]):
			return false
	return true


func _task_details_held() -> bool:
	if _conf.get("task_details_always", false):
		return true
	var bind: Dictionary = _conf.get("binds", {}).get("icTaskDetails", KeyUtil.make_bind(KEY_ALT))
	var code: int = int(bind.get("value", 0))
	return code != 0 and Input.is_physical_key_pressed(code)


func _item_name(path: String) -> String:
	if not _item_names.has(path):
		var data = load(path)
		_item_names[path] = str(data.name) if data and "name" in data else path.get_file().get_basename()
	return _item_names[path]


func _bb_escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _gradient_text(text: String) -> String:
	var out := ""
	var n: int = max(1, text.length() - 1)
	for i in text.length():
		var c: Color = READY_BLUE.lerp(READY_PINK, float(i) / float(n))
		out += "[color=#%s]%s[/color]" % [c.to_html(false), text[i]]
	return out


func _on_task_item_mouse_exited() -> void:
	_hovered_compare_text = ""
	_hovered_item_key = ""
	_hovered_price_text = ""


func _process(_delta: float) -> void:
	if _tooltip_quest_label == null and _tooltip_recipe_label == null and _tooltip_price_label == null:
		return
	var ref_label = _tooltip_quest_label if _tooltip_quest_label != null else (_tooltip_recipe_label if _tooltip_recipe_label != null else _tooltip_price_label)
	if not is_instance_valid(ref_label) or not is_instance_valid(_tooltip_root):
		_tooltip_quest_label = null
		_tooltip_recipe_label = null
		_tooltip_price_label = null
		_tooltip_root = null
		return
	var tooltip_visible = _tooltip_root.is_visible_in_tree()
	if _tooltip_quest_label != null and is_instance_valid(_tooltip_quest_label):
		if not tooltip_visible:
			_tooltip_quest_label.visible = false
		else:
			var task_info: Array = _task_needed_paths.get(_hovered_item_key, [])
			if task_info.is_empty():
				_tooltip_quest_label.visible = false
			else:
				var text: String = "Needed for tasks:\n" + "\n".join(_format_task_lines(_hovered_item_key, task_info))
				if text != _quest_text_cache:
					_quest_text_cache = text
					_tooltip_quest_label.text = text
				_tooltip_quest_label.visible = true
	if _tooltip_recipe_label != null and is_instance_valid(_tooltip_recipe_label):
		if not tooltip_visible:
			_tooltip_recipe_label.visible = false
		else:
			var recipe_info: Array = _crafting_recipe_paths.get(_hovered_item_key, [])
			if recipe_info.is_empty() or not _conf.get("recipe_tooltip", true):
				_tooltip_recipe_label.visible = false
			else:
				_tooltip_recipe_label.text = "Used in crafting:\n" + "\n".join(recipe_info)
				_tooltip_recipe_label.visible = true
	if _tooltip_price_label != null and is_instance_valid(_tooltip_price_label):
		if not tooltip_visible or not _conf.get("price_per_slot", true) or _hovered_price_text == "":
			_tooltip_price_label.visible = false
		else:
			if _hovered_price_text != _price_text_cache:
				_price_text_cache = _hovered_price_text
				_tooltip_price_label.text = _hovered_price_text
			_tooltip_price_label.visible = true
	if _tooltip_compare_label != null and is_instance_valid(_tooltip_compare_label):
		if not tooltip_visible or _hovered_compare_text == "":
			_tooltip_compare_label.visible = false
		else:
			if _hovered_compare_text != _compare_text_cache:
				_compare_text_cache = _hovered_compare_text
				_tooltip_compare_label.text = _hovered_compare_text
			_tooltip_compare_label.visible = true


func _setup_tooltip_label(tooltip: Node) -> void:
	if _tooltip_quest_label != null and _tooltip_recipe_label != null and _tooltip_price_label != null:
		return

	# The container was "Panel/Margin/Elements" before the Oct 2026 update and is
	# now "Panel/Margin/VBox"; locate it via the Info label so renames don't break us
	var info_node = tooltip.find_child("Info", true, false)
	var vbox = info_node.get_parent() if info_node else null
	if not vbox is VBoxContainer:
		vbox = tooltip.get_node_or_null("Panel/Margin/VBox")
	if vbox == null:
		vbox = tooltip.get_node_or_null("Panel/Margin/Elements")
	if vbox == null:
		return
	_tooltip_root = tooltip
	if info_node and info_node.get_parent() != vbox:
		info_node = null
	var insert_after_idx = info_node.get_index() if info_node else vbox.get_child_count() - 1

	# Insert price label first, so it appears at the top
	if _tooltip_price_label == null:
		# RichTextLabel so the value tier word can carry its own colour
		var price_label = RichTextLabel.new()
		price_label.name = "_icc_price_label"
		price_label.bbcode_enabled = true
		price_label.fit_content = true
		price_label.scroll_active = false
		price_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		price_label.custom_minimum_size = Vector2(256.0, 0.0)
		price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price_label.add_theme_font_size_override("normal_font_size", 12)
		price_label.add_theme_color_override("default_color", Color(0.6, 1.0, 0.6))  # Light green
		_price_text_cache = ""
		price_label.visible = false
		vbox.add_child(price_label)
		# Move to just after Info (or top if no Info)
		vbox.move_child(price_label, insert_after_idx + 1)
		_tooltip_price_label = price_label
		insert_after_idx += 1

	if _tooltip_compare_label == null:
		var compare_label = RichTextLabel.new()
		compare_label.name = "_icc_compare_label"
		compare_label.bbcode_enabled = true
		compare_label.fit_content = true
		compare_label.scroll_active = false
		compare_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		compare_label.custom_minimum_size = Vector2(256.0, 0.0)
		compare_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		compare_label.add_theme_font_size_override("normal_font_size", 12)
		compare_label.visible = false
		vbox.add_child(compare_label)
		vbox.move_child(compare_label, insert_after_idx + 1)
		_tooltip_compare_label = compare_label
		_compare_text_cache = ""
		insert_after_idx += 1

	if _tooltip_quest_label == null:
		# RichTextLabel so each task line can have its own colour
		var quest_label = RichTextLabel.new()
		quest_label.name = "_icc_quest_label"
		quest_label.bbcode_enabled = true
		quest_label.fit_content = true
		quest_label.scroll_active = false
		quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		quest_label.custom_minimum_size = Vector2(256.0, 0.0)
		quest_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quest_label.add_theme_font_size_override("normal_font_size", 12)
		quest_label.add_theme_color_override("default_color", TASK_COLOR)
		_quest_text_cache = ""
		quest_label.visible = false
		vbox.add_child(quest_label)
		vbox.move_child(quest_label, insert_after_idx + 1)
		_tooltip_quest_label = quest_label
		insert_after_idx += 1

	if _tooltip_recipe_label == null:
		var recipe_label = Label.new()
		recipe_label.name = "_icc_recipe_label"
		recipe_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		recipe_label.custom_minimum_size = Vector2(256.0, 0.0)
		recipe_label.add_theme_font_size_override("font_size", 12)
		recipe_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))  # Light blue
		recipe_label.visible = false
		vbox.add_child(recipe_label)
		vbox.move_child(recipe_label, insert_after_idx + 1)
		_tooltip_recipe_label = recipe_label
		insert_after_idx += 1


func _find_config_node() -> Node:
	var root = get_tree().get_root()
	for child in root.get_children():
		if child.name == "ItemClarityConfig":
			return child
		for grandchild in child.get_children():
			if grandchild.name == "ItemClarityConfig":
				return grandchild
	return null
