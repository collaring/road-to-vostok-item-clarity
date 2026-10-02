extends Node

# Highlights every visible item compatible with the hovered (or dragged) item.
# ItemData.compatible is one-directional (weapon -> ammo/magazines/attachments,
# magazine -> ammo), so two items match if either lists the other.

const HIGHLIGHT_NODE_NAME = "_icc_compat"

var enabled := true
var color := Color("#ffffff46")
var interface: Node = null  # set by Main when the Interface node appears
var stat_filter: String = ""  # set by StatPreview: outline usable items raising this stat

var _items: Dictionary = {}       # instance id -> tracked item node (Panel with slotData)
var _highlighted: Array = []      # item nodes currently showing a highlight
var _source_path: String = ""     # resource path of the item we highlight for
var _compat_cache: Dictionary = {}  # resource_path -> Dictionary of compatible paths


func set_enabled(value: bool) -> void:
	enabled = value
	_clear()
	_source_path = ""


func set_color(value: Color) -> void:
	color = value
	_clear()
	_source_path = ""


func track(item: Node) -> void:
	_items[item.get_instance_id()] = item
	# A new item appearing (opening a container, splitting a stack) while a
	# highlight is active should light up too
	if _source_path != "":
		_apply(item)


func _get_interface() -> Node:
	if interface == null or not is_instance_valid(interface):
		interface = get_node_or_null("/root/Map/Core/UI/Interface")
	return interface


func _process(_delta: float) -> void:
	if not enabled:
		return
	var ui = _get_interface()
	var source: Node = null
	if ui != null and ui.visible:
		if "itemDragged" in ui and ui.itemDragged:
			source = ui.itemDragged
		elif "hoverItem" in ui and ui.hoverItem:
			source = ui.hoverItem
		elif "hoverEquipment" in ui and ui.hoverEquipment:
			source = ui.hoverEquipment
	var path := _item_path(source)
	if path == "" and stat_filter != "":
		path = "stat:" + stat_filter
	if path == _source_path:
		return
	_clear()
	_source_path = path
	if path == "":
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
	var path := _item_path(item)
	if path == "" or path == _source_path:
		return
	if _source_path.begins_with("stat:"):
		var stat := _source_path.substr(5)
		var data = item.slotData.itemData
		if not (data.usable and stat in data and float(data.get(stat)) > 0.0):
			return
	elif not (_compatible_paths(_source_path).has(path) or _compatible_paths(path).has(_source_path)):
		return
	if item.get_node_or_null(HIGHLIGHT_NODE_NAME) != null:
		return
	var overlay = Panel.new()
	overlay.name = HIGHLIGHT_NODE_NAME
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, color.a * 0.15)
	style.border_color = color
	style.set_border_width_all(2)
	overlay.add_theme_stylebox_override("panel", style)
	item.add_child(overlay)  # last child, so it draws on top of the icon
	_highlighted.append(item)


func _clear() -> void:
	for item in _highlighted:
		if is_instance_valid(item):
			var overlay = item.get_node_or_null(HIGHLIGHT_NODE_NAME)
			if overlay:
				overlay.free()
	_highlighted = []


func _item_path(item: Node) -> String:
	if item == null or not is_instance_valid(item) or not ("slotData" in item):
		return ""
	if item.slotData == null or item.slotData.itemData == null:
		return ""
	return item.slotData.itemData.resource_path


func _compatible_paths(path: String) -> Dictionary:
	if _compat_cache.has(path):
		return _compat_cache[path]
	var result: Dictionary = {}
	var data = load(path) if path != "" else null
	if data != null and "compatible" in data and data.compatible != null:
		for other in data.compatible:
			if other != null and other.resource_path != "":
				result[other.resource_path] = true
	# Weapons reference their ammo through WeaponData.ammo, not compatible
	if data != null and "ammo" in data:
		var ammo = data.get("ammo")
		var ammo_list: Array = ammo if ammo is Array else [ammo]
		for a in ammo_list:
			if a is Resource and a.resource_path != "":
				result[a.resource_path] = true
	_compat_cache[path] = result
	return result
