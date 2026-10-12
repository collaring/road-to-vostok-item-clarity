extends Node

# Inventory tools, shown above the inventory (and above the open container
# while in a shelter):
#   Sort        - merge partial stacks, then re-pack the grid by category,
#                 falling back to the original layout if it doesn't fit
#   Quick Stack - (shelter only) move inventory items into nearby containers
#                 that already hold the same item, like Terraria
#
# Every move goes through the game's own Grid.Pick / Place / Spawn (or
# Interface.AutoPlace) so the grid's occupancy cells stay correct. Closed
# containers are edited through LootContainer.storage, which is exactly what
# Loader.SaveShelter writes and FillContainerGrid reads back.

const CELL = 64
const GAP = 6.0
const ROW_H = 26.0

# Styled after the game's dark panels: translucent fill, thin grey border
const BTN_BG = Color(0.08, 0.08, 0.08, 0.85)
const BTN_BG_HOVER = Color(0.16, 0.16, 0.16, 0.9)
const BTN_BG_PRESSED = Color(0.24, 0.24, 0.24, 0.95)
const BTN_BORDER = Color(0.38, 0.38, 0.38)
const BTN_BORDER_HOVER = Color(0.75, 0.75, 0.75)
const BTN_TEXT = Color(0.82, 0.82, 0.82)
const BTN_TEXT_HOVER = Color(1, 1, 1)

enum { NONE, PARTIAL, DONE }

# Sort order by item folder (res://Items/<Category>/...)
const CATEGORY_ORDER = [
	"Weapons", "Ammo", "Attachments", "Grenades", "Knives", "Medical",
	"Consumables", "Backpacks", "Rigs", "Armor", "Helmets", "Belts",
	"Clothing", "Keys", "Electronics", "Instruments", "Fishing", "Books",
	"Lore", "Misc",
]

var enabled := true
var quick_range := 6.0
var interface: Node = null    # set by Main
var counter: Node = null      # ItemCounter: knows the LootContainers in the world

var _game_data: Resource = null
var _inv_row: HBoxContainer = null
var _cont_row: HBoxContainer = null
var _quick_button: Button = null
var _status: Label = null
var _status_until: int = 0
var _bounds_cache: Dictionary = {}  # panel instance id -> [msec, Rect2]


func _ready() -> void:
	_game_data = load("res://Resources/GameData.tres")


func configure(on: bool, range_m: float) -> void:
	enabled = on
	quick_range = range_m


# ── UI ───────────────────────────────────────────────────────────────────────

func _make_rows() -> void:
	_inv_row = HBoxContainer.new()
	_inv_row.name = "_icc_inv_tools"
	_inv_row.add_theme_constant_override("separation", 6)
	_add_button(_inv_row, "↕ Sort", "Merge partial stacks and sort your inventory by category.", func(): _sort(interface.inventoryGrid))
	_quick_button = _add_button(_inv_row, "⇥ Quick Stack",
		"Move inventory items into nearby shelter containers that already hold the same item.", _quick_stack)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", BTN_TEXT)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	_inv_row.add_child(_status)

	_cont_row = HBoxContainer.new()
	_cont_row.name = "_icc_cont_tools"
	_cont_row.add_theme_constant_override("separation", 6)
	_add_button(_cont_row, "↕ Sort", "Merge partial stacks and sort this container by category.", func(): _sort(interface.containerGrid))


func _add_button(row: HBoxContainer, text: String, tip: String, action: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	_style_button(b)
	b.pressed.connect(func():
		if _busy():
			interface.PlayError()
			return
		action.call()
	)
	row.add_child(b)
	return b


func _style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _box(BTN_BG, BTN_BORDER))
	b.add_theme_stylebox_override("hover", _box(BTN_BG_HOVER, BTN_BORDER_HOVER))
	b.add_theme_stylebox_override("pressed", _box(BTN_BG_PRESSED, BTN_BORDER_HOVER))
	b.add_theme_stylebox_override("hover_pressed", _box(BTN_BG_PRESSED, BTN_BORDER_HOVER))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", BTN_TEXT)
	b.add_theme_color_override("font_hover_color", BTN_TEXT_HOVER)
	b.add_theme_color_override("font_pressed_color", BTN_TEXT_HOVER)
	b.add_theme_color_override("font_hover_pressed_color", BTN_TEXT_HOVER)
	b.custom_minimum_size = Vector2(0, ROW_H)


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box


func _process(_delta: float) -> void:
	if _inv_row == null or not is_instance_valid(_inv_row) or not is_instance_valid(_cont_row):
		_make_rows()
	var ui = _get_interface()
	var open := enabled and ui != null and _is_inventory_open()
	var in_shelter := _in_shelter()

	var show_inv: bool = open and "inventoryUI" in ui and ui.inventoryUI.is_visible_in_tree()
	var show_cont: bool = open and in_shelter and "container" in ui and ui.container != null \
		and "containerUI" in ui and ui.containerUI.is_visible_in_tree()
	_inv_row.visible = show_inv
	_cont_row.visible = show_cont
	_quick_button.visible = in_shelter
	if not show_inv and not show_cont:
		return

	_attach(ui, _inv_row)
	_attach(ui, _cont_row)
	if show_inv:
		_place_above(ui.inventoryUI, _inv_row)
	if show_cont:
		_place_above(ui.containerUI, _cont_row)
	if _status_until != 0 and Time.get_ticks_msec() > _status_until:
		_status.text = ""
		_status_until = 0


func _say(text: String) -> void:
	_status.text = text
	_status_until = Time.get_ticks_msec() + 3000


# Same placement trick as the search box: live inside the Interface, right
# before the tooltip, so tooltips draw over the buttons
func _attach(ui: Node, row: Control) -> void:
	if not ("tooltip" in ui) or not (ui.tooltip is Control):
		return
	var tooltip: Control = ui.tooltip
	var parent = tooltip.get_parent()
	if row.get_parent() != parent:
		if row.get_parent():
			row.reparent(parent, false)
		else:
			parent.add_child(row)
	# Draw before whichever overlay comes first: the right-click menu or tooltip.
	# Only move when we're after it, so several of our controls never ping-pong.
	var anchor_idx: int = tooltip.get_index()
	if "context" in ui and ui.context is Control and ui.context.get_parent() == parent:
		anchor_idx = min(anchor_idx, ui.context.get_index())
	if row.get_index() > anchor_idx:
		parent.move_child(row, anchor_idx)


func _place_above(panel: Control, row: Control) -> void:
	var id := panel.get_instance_id()
	var cached = _bounds_cache.get(id)
	var now := Time.get_ticks_msec()
	if cached == null or now - cached[0] > 250:
		cached = [now, _covered_rect(panel, Rect2())]
		_bounds_cache[id] = cached
	var bounds: Rect2 = cached[1]
	if bounds.size.x < 64:
		return
	row.global_position = Vector2(bounds.position.x, bounds.position.y - ROW_H - GAP).round()
	row.size = Vector2(bounds.size.x, ROW_H)


# Panels report ~zero size (children placed manually); measure what they cover
func _covered_rect(node: Node, acc: Rect2) -> Rect2:
	if node is Control:
		if not node.visible or node.name.begins_with("_icc"):
			return acc
		if "slotData" in node:
			return acc
		var r: Rect2 = node.get_global_rect()
		if r.size.x > 0 and r.size.y > 0:
			acc = r if acc.size == Vector2.ZERO else acc.merge(r)
	for child in node.get_children():
		acc = _covered_rect(child, acc)
	return acc


# ── State helpers ────────────────────────────────────────────────────────────

func _get_interface() -> Node:
	if interface == null or not is_instance_valid(interface):
		interface = get_node_or_null("/root/Map/Core/UI/Interface")
	return interface


func _is_inventory_open() -> bool:
	if _game_data == null or not ("interface" in _game_data):
		return false
	if "settings" in _game_data and _game_data.settings:
		return false
	if "isDead" in _game_data and _game_data.isDead:
		return false
	return bool(_game_data.interface)


func _in_shelter() -> bool:
	return _game_data != null and "shelter" in _game_data and bool(_game_data.shelter)


# Never rearrange while the game is mid-action (dragging, loading, using...)
func _busy() -> bool:
	var ui = _get_interface()
	if ui == null:
		return true
	if "itemDragged" in ui and ui.itemDragged:
		return true
	if "activeProgress" in ui and ui.activeProgress:
		return true
	return _game_data != null and "isOccupied" in _game_data and _game_data.isOccupied


func _category_index(item: Node) -> int:
	var segments: PackedStringArray = item.slotData.itemData.resource_path.split("/")
	if segments.size() > 3:
		var idx := CATEGORY_ORDER.find(segments[3])
		if idx >= 0:
			return idx
	return CATEGORY_ORDER.size()


func _area(item: Node) -> int:
	var s: Vector2 = item.slotData.itemData.size
	return int(s.x) * int(s.y)


# ── Sort ─────────────────────────────────────────────────────────────────────

func _sort(grid) -> void:
	if grid == null or not ("items" in grid):
		return
	# Merging first only ever frees space, so it can only help the layout fit
	var merged := _stack(grid)
	var merged_text := "" if merged == 0 else ", merged %d stack%s" % [merged, "" if merged == 1 else "s"]
	var items: Array = grid.items.duplicate()
	if items.is_empty():
		return
	var originals: Array = []
	for it in items:
		originals.append([it, it.global_position, it.rotated])

	# Category order first; if that doesn't pack, biggest-first always packs best
	var by_category := items.duplicate()
	by_category.sort_custom(func(a, b):
		var ca := _category_index(a)
		var cb := _category_index(b)
		if ca != cb:
			return ca < cb
		if a.slotData.itemData.name != b.slotData.itemData.name:
			return a.slotData.itemData.name < b.slotData.itemData.name
		return a.slotData.amount > b.slotData.amount
	)
	var by_size := by_category.duplicate()
	by_size.sort_custom(func(a, b): return _area(a) > _area(b))

	for order in [by_category, by_size]:
		for it in items:
			if grid.items.has(it):
				grid.Pick(it)
		if _pack(grid, order):
			if merged > 0:
				interface.PlayStack()
			else:
				interface.PlayClick()
			interface.UpdateStats(false)
			_say("Sorted" + merged_text)
			return

	# Neither order fits: put everything back exactly where it was
	for it in items:
		if grid.items.has(it):
			grid.Pick(it)
	for entry in originals:
		var it = entry[0]
		if it.rotated != entry[2]:
			interface.Rotate(it)
		it.global_position = entry[1]
		grid.Place(it)
	interface.PlayError()
	interface.UpdateStats(false)
	_say("Not enough room to sort" + merged_text)


func _pack(grid, order: Array) -> bool:
	for it in order:
		if it.rotated:
			interface.Rotate(it)
		if not grid.Spawn(it):
			interface.Rotate(it)
			if not grid.Spawn(it):
				return false
	return true


# ── Stack (part of Sort) ─────────────────────────────────────────────────────

# Merges partial stacks of the same item; returns how many stacks were removed
func _stack(grid) -> int:
	var groups: Dictionary = {}
	for it in grid.items:
		var data = it.slotData.itemData
		if data.stackable:
			if not groups.has(data.file):
				groups[data.file] = []
			groups[data.file].append(it)
	var merged := 0
	for file in groups:
		var list: Array = groups[file]
		if list.size() < 2:
			continue
		var max_amount: int = list[0].slotData.itemData.maxAmount
		var total := 0
		for it in list:
			total += int(it.slotData.amount)
		list.sort_custom(func(a, b): return a.slotData.amount > b.slotData.amount)
		for it in list:
			var take: int = min(max_amount, total)
			total -= take
			if take <= 0:
				grid.Pick(it)
				it.queue_free()
				merged += 1
			elif it.slotData.amount != take:
				it.slotData.amount = take
				it.UpdateDetails()
	return merged


# ── Quick Stack ──────────────────────────────────────────────────────────────

func _quick_stack() -> void:
	if not _in_shelter():
		return
	var ui = interface
	var targets := _nearby_containers()
	if targets.is_empty():
		ui.PlayError()
		_say("No containers nearby")
		return
	var moved := 0
	var used: Dictionary = {}
	for it in ui.inventoryGrid.items.duplicate():
		if not is_instance_valid(it):
			continue
		for c in targets:
			var result: int = _deposit_open(it, ui) if c == ui.container else _deposit_storage(it, c)
			if result != NONE:
				used[c] = true
			if result == DONE:
				moved += 1
				break
	if moved > 0 or not used.is_empty():
		ui.PlayStack()
		ui.UpdateStats(false)
		if counter:
			counter.invalidate()
		_say("Quick stacked %d item%s into %d container%s" % [
			moved, "" if moved == 1 else "s", used.size(), "" if used.size() == 1 else "s"])
	else:
		ui.PlayError()
		_say("Nothing matches nearby containers")


# Shelter furniture containers in range, nearest first. The open one counts
# regardless of distance.
func _nearby_containers() -> Array:
	var result: Array = []
	if counter == null or not counter.has_method("get_containers"):
		return result
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return result
	var origin: Vector3 = camera.global_position
	var max_sq := quick_range * quick_range
	for c in counter.get_containers():
		if not c.is_inside_tree() or not c.furniture or c.locked or not c.is_visible_in_tree():
			continue
		if c == interface.container or c.global_position.distance_squared_to(origin) <= max_sq:
			result.append(c)
	result.sort_custom(func(a, b):
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	return result


# Closed container: work on LootContainer.storage directly
func _deposit_storage(item: Node, c: Node) -> int:
	var data = item.slotData.itemData
	var file: String = data.file
	var has := false
	for s in c.storage:
		if s and s.itemData and s.itemData.file == file:
			has = true
			break
	if not has:
		return NONE

	var remaining: int = int(item.slotData.amount)
	var topped := false
	if data.stackable:
		for s in c.storage:
			if s and s.itemData and s.itemData.file == file and s.amount < data.maxAmount:
				var add: int = min(data.maxAmount - s.amount, remaining)
				s.amount += add
				remaining -= add
				topped = true
				if remaining <= 0:
					break
		if remaining <= 0:
			interface.inventoryGrid.Pick(item)
			item.queue_free()
			return DONE

	var spot = _free_spot(c, data)
	if spot != null:
		var slot = SlotData.new()
		slot.Update(item.slotData)
		if data.stackable:
			slot.amount = remaining
		slot.GridSave(spot[0] * CELL, spot[1])
		c.storage.append(slot)
		c.storaged = true
		interface.inventoryGrid.Pick(item)
		item.queue_free()
		return DONE

	if topped:
		item.slotData.amount = remaining
		item.UpdateDetails()
		return PARTIAL
	return NONE


# Open container: its contents live in the container grid until it closes
func _deposit_open(item: Node, ui: Node) -> int:
	var grid = ui.containerGrid
	var data = item.slotData.itemData
	var file: String = data.file
	var matches: Array = []
	for e in grid.items:
		if e.slotData.itemData.file == file:
			matches.append(e)
	if matches.is_empty():
		return NONE

	var topped := false
	if data.stackable:
		var remaining: int = int(item.slotData.amount)
		for e in matches:
			if e.slotData.amount < data.maxAmount:
				var add: int = min(data.maxAmount - e.slotData.amount, remaining)
				e.slotData.amount += add
				e.UpdateDetails()
				remaining -= add
				topped = true
				if remaining <= 0:
					break
		if remaining <= 0:
			ui.inventoryGrid.Pick(item)
			item.queue_free()
			return DONE
		item.slotData.amount = remaining
		item.UpdateDetails()

	# Moves the item with Pick/Spawn, and puts it back in the inventory if full
	if ui.AutoPlace(item, grid, ui.inventoryGrid, false):
		return DONE
	return PARTIAL if topped else NONE


# First free cell for an item in a closed container's grid, trying the item
# upright and then rotated. Returns [Vector2 cell, rotated] or null.
func _free_spot(c: Node, data: Resource):
	var w: int = clamp(int(c.containerSize.x), 4, 8)
	var h: int = clamp(int(c.containerSize.y), 1, 13)
	var occupied: Dictionary = {}
	for s in c.storage:
		if s == null or s.itemData == null:
			continue
		var sx: int = int(s.itemData.size.y if s.gridRotated else s.itemData.size.x)
		var sy: int = int(s.itemData.size.x if s.gridRotated else s.itemData.size.y)
		var cx: int = int(round(s.gridPosition.x / CELL))
		var cy: int = int(round(s.gridPosition.y / CELL))
		for x in range(cx, cx + sx):
			for y in range(cy, cy + sy):
				occupied[Vector2i(x, y)] = true
	for rotated in [false, true]:
		var iw: int = int(data.size.y if rotated else data.size.x)
		var ih: int = int(data.size.x if rotated else data.size.y)
		for y in range(0, h - ih + 1):
			for x in range(0, w - iw + 1):
				var free := true
				for dx in range(iw):
					for dy in range(ih):
						if occupied.has(Vector2i(x + dx, y + dy)):
							free = false
							break
					if not free:
						break
				if free:
					return [Vector2(x, y), rotated]
	return null
