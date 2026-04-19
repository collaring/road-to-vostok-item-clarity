extends Node

const BORDER_THICKNESS = 3
const OVERLAY_NODE_NAME = "_icc_border"
const TASK_ICON_NODE_NAME = "_icc_task"
const CONFIG_PATH = "user://MCM/ItemClarity/config.ini"

# task_needed_paths: resource_path -> Array[String] of formatted lines like "x2 for Gunsmith: Warm Meal"
var _task_needed_paths: Dictionary = {}
var _tooltip_quest_label: Label = null
var _hovered_item_key: String = ""

const DEFAULT_COMMON    = Color(0.40, 0.40, 0.40)
const DEFAULT_RARE      = Color(0.60, 0.20, 0.80)
const DEFAULT_LEGENDARY = Color(1.00, 0.65, 0.00)
const DEFAULT_OPACITY   = 0.15

# Category colors
const CAT_MEDICAL     = Color(0.85, 0.10, 0.10)  # Red
const CAT_AMMO        = Color(0.15, 0.65, 0.15)  # Green
const CAT_GRENADES    = Color(0.15, 0.65, 0.15)  # Green
const CAT_ATTACHMENTS = Color(0.15, 0.65, 0.15)  # Green
const CAT_BACKPACKS   = Color(0.55, 0.15, 0.75)  # Purple
const CAT_ARMOR       = Color(0.55, 0.15, 0.75)  # Purple
const CAT_BELTS       = Color(0.55, 0.15, 0.75)  # Purple
const CAT_CLOTHING    = Color(0.55, 0.15, 0.75)  # Purple
const CAT_HELMETS     = Color(0.55, 0.15, 0.75)  # Purple
const CAT_KEYS        = Color(0.85, 0.70, 0.00)  # Gold
const CAT_WEAPONS     = Color(0.25, 0.25, 0.25)  # Dark gray
const CAT_KNIVES      = Color(0.25, 0.25, 0.25)  # Dark gray
const CAT_RIGS        = Color(0.55, 0.15, 0.75)  # Purple
const CAT_CONSUMABLES = Color(0.90, 0.60, 0.05)  # Orange-yellow

const CATEGORY_COLORS = {
	"Medical":     CAT_MEDICAL,
	"Ammo":        CAT_AMMO,
	"Grenades":    CAT_GRENADES,
	"Attachments": CAT_ATTACHMENTS,
	"Backpacks":   CAT_BACKPACKS,
	"Armor":       CAT_ARMOR,
	"Belts":       CAT_BELTS,
	"Clothing":    CAT_CLOTHING,
	"Helmets":     CAT_HELMETS,
	"Keys":        CAT_KEYS,
	"Weapons":     CAT_WEAPONS,
	"Knives":      CAT_KNIVES,
	"Rigs":        CAT_RIGS,
	"Consumables": CAT_CONSUMABLES,
}


func _ready() -> void:
	print("[IC] Main ready")
	await get_tree().process_frame
	await get_tree().process_frame
	_load_task_data()
	var conf = _read_config()
	print("[IC] config loaded, category=", conf["category_enabled"], " rarity=", conf["rarity_enabled"])
	_scan_existing_items()
	_find_and_setup_tooltip(get_tree().get_root())
	get_tree().node_added.connect(_on_node_added)
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.autostart = true
	timer.timeout.connect(_on_rescan_timer)
	add_child(timer)


func _on_node_added(node: Node) -> void:
	if not _is_item_node(node):
		# Check if it's the Tooltip node  Ehook our quest label into it
		if node.name == "Tooltip" and node is Control:
			node.ready.connect(_setup_tooltip_label.bind(node), CONNECT_ONE_SHOT)
		return
	if node.is_node_ready():
		apply_color_to_item(node)
		apply_task_icon(node)
	else:
		node.ready.connect(func():
			apply_color_to_item(node)
			apply_task_icon(node)
		, CONNECT_ONE_SHOT)


func _on_rescan_timer() -> void:
	_load_task_data()
	_scan_existing_items()
	if _tooltip_quest_label == null or not is_instance_valid(_tooltip_quest_label):
		_tooltip_quest_label = null
		_find_and_setup_tooltip(get_tree().get_root())
	# Re-apply tooltip delay in case Interface just loaded
	var cfg_node = _find_config_node()
	if cfg_node and cfg_node.has_method("_apply_tooltip_delay"):
		var cfg = ConfigFile.new()
		if cfg.load(CONFIG_PATH) == OK:
			cfg_node._apply_tooltip_delay(cfg)


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
	print("[IC] refresh_all_slots")
	_remove_all_overlays(get_tree().get_root())
	_load_task_data()
	_scan_existing_items()


func _remove_all_overlays(node: Node) -> void:
	var existing = node.get_node_or_null(OVERLAY_NODE_NAME)
	if existing:
		existing.queue_free()
	var existing_icon = node.get_node_or_null(TASK_ICON_NODE_NAME)
	if existing_icon:
		existing_icon.queue_free()
	var existing_hover = node.get_node_or_null("_icc_hover")
	if existing_hover:
		existing_hover.queue_free()
	for child in node.get_children():
		_remove_all_overlays(child)


func _read_config() -> Dictionary:
	var result = {
		"category_enabled": true,
		"rarity_enabled": false,
		"opacity": DEFAULT_OPACITY
	}
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		print("[IC] config file not found, using defaults")
		return result
	result["category_enabled"] = _get_bool(cfg,  "Bool",  "categoryColorCoding", true)
	result["rarity_enabled"]   = _get_bool(cfg,  "Bool",  "rarityColorCoding",   false)
	result["opacity"]          = _get_float(cfg, "Float", "borderOpacity",       DEFAULT_OPACITY)
	result["task_marking"]     = _get_bool(cfg,  "Bool",  "taskMarking",         true)
	return result


func _get_bool(cfg: ConfigFile, section: String, key: String, default: bool) -> bool:
	var v = cfg.get_value(section, key, default)
	if v is Dictionary: return v.get("value", default)
	return bool(v)


func _get_color(cfg: ConfigFile, section: String, key: String, default: Color) -> Color:
	var v = cfg.get_value(section, key, default)
	if v is Dictionary: return v.get("value", default)
	if v is Color: return v
	return default


func _get_float(cfg: ConfigFile, section: String, key: String, default: float) -> float:
	var v = cfg.get_value(section, key, default)
	if v is Dictionary: return float(v.get("value", default))
	return float(v)


func _get_category(item: Node) -> String:
	var path: String = item.slotData.itemData.resource_path
	# path looks like res://Items/Medical/bandage.tres
	for category in CATEGORY_COLORS:
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

	var conf = _read_config()
	var color: Color = Color(0, 0, 0, 0)

	# Category coding takes priority
	if conf["category_enabled"]:
		var cat = _get_category(item)
		if cat != "":
			color = CATEGORY_COLORS[cat]

	# Fall back to rarity coding if no category matched
	if color.a == 0 and conf["rarity_enabled"]:
		var rarity: int = item.slotData.itemData.rarity
		match rarity:
			0: color = DEFAULT_COMMON
			1: color = DEFAULT_RARE
			2: color = DEFAULT_LEGENDARY

	if color.a == 0:
		return

	color.a = conf["opacity"]
	print("[IC] coloring item cat=", _get_category(item), " color=", color)

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
	for child in node.get_children():
		_walk_and_color(child)


func _is_item_node(node: Node) -> bool:
	return ("slotData" in node) and (node is Panel)


# ── Task tracking ─────────────────────────────────────────────────────────────

func _load_task_data() -> void:
	_task_needed_paths = {}
	if not _read_config()["task_marking"]:
		return

	# Load save data to know which tasks are completed per trader
	var trader_save = load("user://Traders.tres") if FileAccess.file_exists("user://Traders.tres") else null

	var completed_by_trader: Dictionary = {}
	if trader_save:
		completed_by_trader = {
			"Generalist": _to_string_array(trader_save.get("generalist") if trader_save.get("generalist") != null else []),
			"Doctor":     _to_string_array(trader_save.get("doctor")     if trader_save.get("doctor")     != null else []),
			"Gunsmith":   _to_string_array(trader_save.get("gunsmith")   if trader_save.get("gunsmith")   != null else []),
			"Grandma":    _to_string_array(trader_save.get("grandma")    if trader_save.get("grandma")    != null else []),
		}
		print("[IC] completed tasks: ", completed_by_trader)
	else:
		print("[IC] no Traders.tres save found")

	var trader_dirs = DirAccess.get_directories_at("res://Traders/")
	print("[IC] trader dirs: ", trader_dirs)
	if trader_dirs.is_empty():
		print("[IC] res://Traders/ returned no directories, skipping task tracking")
		return

	for trader_id in trader_dirs:
		var trader_res_path = "res://Traders/" + trader_id + "/" + trader_id + ".tres"
		var trader = load(trader_res_path)
		if trader == null:
			print("[IC] could not load trader: ", trader_res_path)
			continue
		if not ("tasks" in trader) or trader.tasks == null:
			print("[IC] trader ", trader_id, " has no tasks property")
			continue

		var completed: Array = completed_by_trader.get(trader_id, [])
		print("[IC] trader ", trader_id, " has ", trader.tasks.size(), " tasks, ", completed.size(), " completed")

		for task in trader.tasks:
			if task == null or not ("name" in task) or not ("deliver" in task):
				continue
			if task.name in completed:
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

	print("[IC] task tracking loaded, ", _task_needed_paths.size(), " distinct needed items")


func _to_string_array(arr) -> Array:
	var result: Array = []
	for v in arr:
		result.append(str(v))
	return result


func apply_task_icon(item: Node) -> void:
	if not _read_config()["task_marking"]:
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
	# Position: bottom-right corner, nudged up and right slightly
	icon_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	icon_label.offset_left = -18
	icon_label.offset_top = -20
	icon_label.offset_right = 2
	icon_label.offset_bottom = -2
	item.add_child(icon_label)

	# Invisible full-rect hover zone  Ecovers the whole item slot so hovering
	# anywhere on the item triggers the tooltip, not just the "!" icon
	var hover_zone = Control.new()
	hover_zone.name = "_icc_hover"
	hover_zone.mouse_filter = Control.MOUSE_FILTER_PASS
	hover_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	item.add_child(hover_zone)
	hover_zone.mouse_entered.connect(_on_task_item_mouse_entered.bind(key))
	hover_zone.mouse_exited.connect(_on_task_item_mouse_exited)


func _on_task_item_mouse_entered(item_key: String) -> void:
	print("[IC] mouse_entered item key=", item_key)
	_hovered_item_key = item_key


func _on_task_item_mouse_exited() -> void:
	print("[IC] mouse_exited")
	_hovered_item_key = ""


func _process(_delta: float) -> void:
	if _tooltip_quest_label == null:
		return
	if not is_instance_valid(_tooltip_quest_label):
		_tooltip_quest_label = null
		return
	# Walk up: Label -> Elements (VBox) -> Margin -> Panel -> Tooltip (Control)
	var tooltip_root = _tooltip_quest_label.get_parent().get_parent().get_parent().get_parent()
	if not is_instance_valid(tooltip_root):
		_tooltip_quest_label.visible = false
		return
	# Debug once when hovering
	if _hovered_item_key != "":
		print("[IC] _process: hovered=", _hovered_item_key, " tooltip_root.visible=", tooltip_root.visible, " modulate=", tooltip_root.modulate)
	if not tooltip_root.visible:
		_tooltip_quest_label.visible = false
		return
	var task_info: Array = _task_needed_paths.get(_hovered_item_key, [])
	if task_info.is_empty():
		_tooltip_quest_label.visible = false
	else:
		_tooltip_quest_label.text = "Needed for tasks:\n" + "\n".join(task_info)
		_tooltip_quest_label.visible = true


func _setup_tooltip_label(tooltip: Node) -> void:
	if _tooltip_quest_label != null:
		return

	var vbox = tooltip.get_node_or_null("Panel/Margin/Elements")
	if vbox == null:
		return

	var label = Label.new()
	label.name = "_icc_quest_label"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size = Vector2(256.0, 0.0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.0))  # Gold
	label.visible = false

	# Insert after the "Info" node if it exists, otherwise just append
	var info_node = vbox.get_node_or_null("Info")
	vbox.add_child(label)
	if info_node:
		vbox.move_child(label, info_node.get_index() + 1)

	_tooltip_quest_label = label
	print("[IC] Tooltip quest label set up")


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
