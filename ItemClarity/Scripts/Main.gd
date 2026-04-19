extends Node

const BORDER_THICKNESS = 3
const OVERLAY_NODE_NAME = "_icc_border"
const TASK_ICON_NODE_NAME = "_icc_task"
const CONFIG_PATH = "user://MCM/ItemClarity/config.ini"

# task_needed_paths: resource_path -> Array[String] of formatted lines like "x2 for Gunsmith: Warm Meal"
var _task_needed_paths: Dictionary = {}
# crafting_recipe_paths: resource_path -> Array[String] of recipe names that use this item as ingredient
var _crafting_recipe_paths: Dictionary = {}
var _tooltip_quest_label: Label = null
var _tooltip_recipe_label: Label = null
var _tooltip_price_label: Label = null
var _hovered_item_key: String = ""
var _hovered_price_text: String = ""  # cached price-per-slot string for current hover

# Cached config — loaded once on ready, refreshed by MCM on save
var _conf: Dictionary = {}
var _traders_mtime: int = -1      # last-seen modification time of Traders.tres
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


func _on_node_added(node: Node) -> void:
	if not _is_item_node(node):
		if node.name == "Tooltip" and node is Control:
			node.ready.connect(_setup_tooltip_label.bind(node), CONNECT_ONE_SHOT)
		elif node.name == "Interface" and "tooltipDelay" in node:
			_apply_tooltip_delay(node)
		return
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
	_remove_all_overlays(get_tree().get_root())
	_load_task_data()
	_load_recipe_data()
	_scan_existing_items()
	var interface = get_node_or_null("/root/Map/Core/UI/Interface")
	if interface and "tooltipDelay" in interface:
		_apply_tooltip_delay(interface)


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
		"color_coding_mode": 0,  # 0=Category, 1=Rarity, 2=None
		"task_marking":       true,
		"noted_tasks_only":   false,
		"recipe_tooltip":     true,
		"price_per_slot":     true,
		"task_marker_corner": 0,
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
	result["task_marker_corner"] = _get_int(cfg,  "Dropdown",  "taskMarkerCorner",    0)
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
	return result


func _get_int(cfg: ConfigFile, section: String, key: String, default: int) -> int:
	var v = cfg.get_value(section, key, default)
	if v is Dictionary: return int(v.get("value", default))
	return int(v)


func _get_bool(cfg: ConfigFile, section: String, key: String, default: bool) -> bool:
	var v = cfg.get_value(section, key, default)
	if v is Dictionary: return v.get("value", default)
	return bool(v)


func _get_color(cfg: ConfigFile, section: String, key: String, default: Color) -> Color:
	var v = cfg.get_value(section, key, default)
	if v is Dictionary: return v.get("value", default)
	if v is Color: return v
	return default


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
	# mode == 2 (None): color stays transparent

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
	if _is_item_node(node):
		apply_color_to_item(node)
		apply_task_icon(node)
		apply_recipe_hover(node)
	for child in node.get_children():
		_walk_and_color(child)


func _is_item_node(node: Node) -> bool:
	return ("slotData" in node) and (node is Panel)

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

	var completed_by_trader: Dictionary = {}
	if trader_save:
		completed_by_trader = {
			"Generalist": _to_string_array(trader_save.get("generalist") if trader_save.get("generalist") != null else []),
			"Doctor":     _to_string_array(trader_save.get("doctor")     if trader_save.get("doctor")     != null else []),
			"Gunsmith":   _to_string_array(trader_save.get("gunsmith")   if trader_save.get("gunsmith")   != null else []),
			"Grandma":    _to_string_array(trader_save.get("grandma")    if trader_save.get("grandma")    != null else []),
		}

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

		var completed: Array = completed_by_trader.get(trader_id, [])

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
				var line = "x" + str(count) + " for " + trader_id + ": " + task.name
				_task_needed_paths[key].append(line)


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
	# Position: configurable corner
	var corner: int = _conf.get("task_marker_corner", 0)
	match corner:
		1: # Bottom Left
			icon_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			icon_label.offset_left = -2
			icon_label.offset_top = -20
			icon_label.offset_right = 18
			icon_label.offset_bottom = -2
		2: # Top Right
			icon_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			icon_label.offset_left = -18
			icon_label.offset_top = 2
			icon_label.offset_right = 2
			icon_label.offset_bottom = 20
		3: # Top Left
			icon_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
			icon_label.offset_left = -2
			icon_label.offset_top = 2
			icon_label.offset_right = 18
			icon_label.offset_bottom = 20
		_: # Bottom Right (default, 0)
			icon_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			icon_label.offset_left = -18
			icon_label.offset_top = -20
			icon_label.offset_right = 2
			icon_label.offset_bottom = -2
	item.add_child(icon_label)

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


func _on_task_item_mouse_entered(item: Node, key: String) -> void:
	# Use the item's slotData for durability/condition
	if not "slotData" in item or item.slotData == null or item.slotData.itemData == null:
		_hovered_item_key = ""
		_hovered_price_text = ""
		return
	_hovered_item_key = key
	var condition := 1.0
	if "condition" in item.slotData and item.slotData.condition != null:
		condition = float(item.slotData.condition)
		if condition > 1.0:
			condition /= 100.0
	# Pre-compute price-per-slot so _process doesn't call load() every frame
	_hovered_price_text = ""
	if _conf.get("price_per_slot", true) and key != "":
		var item_res = load(key)
		if item_res != null:
			var base_value: float = float(item_res.get("value"))
			var value: float = base_value * condition
			var size: Vector2 = item_res.get("size")
			var slots: int = max(1, int(size.x) * int(size.y))
			var pps: int = int(round(value / float(slots)))
			_hovered_price_text = str(pps) + "€ / slot"

func _on_task_item_mouse_exited() -> void:
	_hovered_item_key = ""
	_hovered_price_text = ""


func _process(_delta: float) -> void:
	if _tooltip_quest_label == null and _tooltip_recipe_label == null and _tooltip_price_label == null:
		return
	# Walk up: Label -> Elements (VBox) -> Margin -> Panel -> Tooltip (Control)
	var ref_label = _tooltip_quest_label if _tooltip_quest_label != null else (_tooltip_recipe_label if _tooltip_recipe_label != null else _tooltip_price_label)
	if not is_instance_valid(ref_label):
		_tooltip_quest_label = null
		_tooltip_recipe_label = null
		_tooltip_price_label = null
		return
	var tooltip_root = ref_label.get_parent().get_parent().get_parent().get_parent()
	var tooltip_visible = is_instance_valid(tooltip_root) and tooltip_root.visible
	if _tooltip_quest_label != null and is_instance_valid(_tooltip_quest_label):
		if not tooltip_visible:
			_tooltip_quest_label.visible = false
		else:
			var task_info: Array = _task_needed_paths.get(_hovered_item_key, [])
			if task_info.is_empty():
				_tooltip_quest_label.visible = false
			else:
				_tooltip_quest_label.text = "Needed for tasks:\n" + "\n".join(task_info)
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
			_tooltip_price_label.text = _hovered_price_text
			_tooltip_price_label.visible = true


func _setup_tooltip_label(tooltip: Node) -> void:
	if _tooltip_quest_label != null and _tooltip_recipe_label != null and _tooltip_price_label != null:
		return

	var vbox = tooltip.get_node_or_null("Panel/Margin/Elements")
	if vbox == null:
		return

	var info_node = vbox.get_node_or_null("Info")
	var insert_after_idx = info_node.get_index() if info_node else vbox.get_child_count() - 1

	# Insert price label first, so it appears at the top
	if _tooltip_price_label == null:
		var price_label = Label.new()
		price_label.name = "_icc_price_label"
		price_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		price_label.custom_minimum_size = Vector2(256.0, 0.0)
		price_label.add_theme_font_size_override("font_size", 12)
		price_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))  # Light green
		price_label.visible = false
		vbox.add_child(price_label)
		# Move to just after Info (or top if no Info)
		vbox.move_child(price_label, insert_after_idx + 1)
		_tooltip_price_label = price_label
		insert_after_idx += 1

	if _tooltip_quest_label == null:
		var quest_label = Label.new()
		quest_label.name = "_icc_quest_label"
		quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		quest_label.custom_minimum_size = Vector2(256.0, 0.0)
		quest_label.add_theme_font_size_override("font_size", 12)
		quest_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.0))  # Gold
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


func _dump_children(node: Node, depth: int) -> String:
	var indent = "  ".repeat(depth)
	var s = indent + node.name + " (" + node.get_class() + ")\n"
	for child in node.get_children():
		s += _dump_children(child, depth + 1)
	return s


func _find_config_node() -> Node:
	var root = get_tree().get_root()
	for child in root.get_children():
		if child.name == "ItemClarityConfig":
			return child
		for grandchild in child.get_children():
			if grandchild.name == "ItemClarityConfig":
				return grandchild
	return null
