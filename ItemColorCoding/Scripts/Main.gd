extends Node

const BORDER_THICKNESS = 3
const OVERLAY_NODE_NAME = "_icc_border"
const CONFIG_PATH = "user://MCM/ItemColorCoding/config.ini"

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
	print("[ICC] Main ready")
	await get_tree().process_frame
	await get_tree().process_frame
	var conf = _read_config()
	print("[ICC] config loaded, category=", conf["category_enabled"], " rarity=", conf["rarity_enabled"])
	_scan_existing_items()
	get_tree().node_added.connect(_on_node_added)
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.autostart = true
	timer.timeout.connect(_scan_existing_items)
	add_child(timer)


func _on_node_added(node: Node) -> void:
	if not _is_item_node(node):
		return
	if node.is_node_ready():
		apply_color_to_item(node)
	else:
		node.ready.connect(apply_color_to_item.bind(node), CONNECT_ONE_SHOT)


func refresh_all_slots() -> void:
	print("[ICC] refresh_all_slots")
	_remove_all_overlays(get_tree().get_root())
	_scan_existing_items()


func _remove_all_overlays(node: Node) -> void:
	var existing = node.get_node_or_null(OVERLAY_NODE_NAME)
	if existing:
		existing.queue_free()
	for child in node.get_children():
		_remove_all_overlays(child)


func _read_config() -> Dictionary:
	var result = {
		"category_enabled": true,
		"rarity_enabled": false,
		"use_border": false,
		"opacity": DEFAULT_OPACITY
	}
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		print("[ICC] config file not found, using defaults")
		return result
	result["category_enabled"] = _get_bool(cfg,  "Bool",  "categoryColorCoding", true)
	result["rarity_enabled"]   = _get_bool(cfg,  "Bool",  "rarityColorCoding",   false)
	result["use_border"]       = _get_bool(cfg,  "Bool",  "useBorder",           false)
	result["opacity"]          = _get_float(cfg, "Float", "borderOpacity",       DEFAULT_OPACITY)
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
	print("[ICC] coloring item cat=", _get_category(item), " color=", color)

	var overlay = Panel.new()
	overlay.name = OVERLAY_NODE_NAME
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	var style = StyleBoxFlat.new()
	if conf["use_border"]:
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = color
		style.border_width_left   = BORDER_THICKNESS
		style.border_width_right  = BORDER_THICKNESS
		style.border_width_top    = BORDER_THICKNESS
		style.border_width_bottom = BORDER_THICKNESS
	else:
		style.bg_color = color
	overlay.add_theme_stylebox_override("panel", style)

	item.add_child(overlay)
	item.move_child(overlay, 0)


func _scan_existing_items() -> void:
	_walk_and_color(get_tree().get_root())


func _walk_and_color(node: Node) -> void:
	if _is_item_node(node):
		apply_color_to_item(node)
	for child in node.get_children():
		_walk_and_color(child)


func _is_item_node(node: Node) -> bool:
	return ("slotData" in node) and (node is Panel)
