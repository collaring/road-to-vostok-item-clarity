extends Node

# Counts how many of each item the player owns: inventory + equipment (live),
# the shelter you're standing in (live), and every other shelter (from its
# save file, so it works away from home). Raid loot is never counted.
#
# Counting follows the game's task hand-in rule (Task.CanInput): every item is
# one unit, but a stackable item only counts if the stack holds at least its
# defaultAmount (magazines excepted).

const CACHE_TIME_MS = 1000

var interface: Node = null  # set by Main when the Interface node appears

var _game_data: Resource = null
var _counts: Dictionary = {}      # resource_path -> int
var _counted_at: int = -CACHE_TIME_MS
var _shelter_cache: Dictionary = {}  # file path -> {"mtime": int, "counts": Dictionary}


func _ready() -> void:
	_game_data = load("res://Resources/GameData.tres")


func get_count(path: String) -> int:
	if Time.get_ticks_msec() - _counted_at >= CACHE_TIME_MS:
		_recount()
	return _counts.get(path, 0)


func invalidate() -> void:
	_counted_at = -CACHE_TIME_MS


func _get_interface() -> Node:
	if interface == null or not is_instance_valid(interface):
		interface = get_node_or_null("/root/Map/Core/UI/Interface")
	return interface


func _recount() -> void:
	_counted_at = Time.get_ticks_msec()
	_counts = {}
	var current_shelter := _current_shelter()

	# Player: live inventory and equipment
	var ui = _get_interface()
	if ui:
		if "inventoryGrid" in ui and ui.inventoryGrid:
			_count_item_nodes(ui.inventoryGrid)
		if "equipment" in ui and ui.equipment:
			_count_item_nodes(ui.equipment)

	# Current shelter: live, since its save file may be out of date
	if current_shelter != "":
		_count_live_shelter(ui)

	# Every other shelter: from save files
	for file in DirAccess.get_files_at("user://"):
		if not file.ends_with(".tres"):
			continue
		if file.get_basename() == current_shelter:
			continue
		var path = "user://" + file
		var counts = _shelter_counts(path)
		for key in counts:
			_counts[key] = _counts.get(key, 0) + counts[key]


# Name of the shelter map we're in (matches its save file name), or ""
func _current_shelter() -> String:
	if _game_data == null:
		return ""
	if not ("shelter" in _game_data) or not _game_data.shelter:
		return ""
	if "currentMap" in _game_data and _game_data.currentMap != null:
		return str(_game_data.currentMap)
	return ""


func _count_live_shelter(ui: Node) -> void:
	var open_container: Node = null
	if ui and "container" in ui and ui.container:
		open_container = ui.container
		# The open container's contents live in the container grid until closed
		if "containerGrid" in ui and ui.containerGrid:
			_count_item_nodes(ui.containerGrid)
	var map = get_node_or_null("/root/Map")
	if map:
		_walk_world(map, open_container)


func _walk_world(node: Node, skip: Node) -> void:
	if node == skip:
		return
	if node is LootContainer:
		_count_slots(node.storage)
	elif node is Pickup:
		if node.slotData:
			_count_slot(node.slotData)
	elif node.name == "UI":
		return  # inventory UI is counted separately
	for child in node.get_children():
		_walk_world(child, skip)


func _shelter_counts(path: String) -> Dictionary:
	var mtime = FileAccess.get_modified_time(path)
	var cached = _shelter_cache.get(path)
	if cached and cached["mtime"] == mtime:
		return cached["counts"]
	var counts: Dictionary = {}
	if _is_shelter_save(path):
		var save = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if save:
			var saved: Dictionary = _counts
			_counts = counts
			if "furnitures" in save and save.furnitures:
				for furniture in save.furnitures:
					if furniture and "storage" in furniture:
						_count_slots(furniture.storage)
			if "items" in save and save.items:
				for item_save in save.items:
					if item_save and "slotData" in item_save and item_save.slotData:
						_count_slot(item_save.slotData)
			_counts = saved
	_shelter_cache[path] = {"mtime": mtime, "counts": counts}
	return counts


# Cheap header check so we don't load unrelated .tres files from user://
func _is_shelter_save(path: String) -> bool:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var header = f.get_line()
	return header.contains("script_class=\"ShelterSave\"")


func _count_item_nodes(node: Node) -> void:
	for child in node.get_children():
		if "slotData" in child and child is Panel:
			if child.slotData:
				_count_slot(child.slotData)
		else:
			_count_item_nodes(child)


func _count_slots(slots) -> void:
	if slots == null:
		return
	for slot in slots:
		if slot:
			_count_slot(slot)


func _count_slot(slot: Resource) -> void:
	var data = slot.itemData
	if data and data.resource_path != "":
		var needed: int = 0
		if data.defaultAmount != 0 and data.subtype != "Magazine":
			needed = data.defaultAmount
		if needed == 0 or slot.amount >= needed:
			_counts[data.resource_path] = _counts.get(data.resource_path, 0) + 1
	# Items stored inside this one (backpacks, rigs, cases)
	if "storage" in slot:
		_count_slots(slot.storage)
