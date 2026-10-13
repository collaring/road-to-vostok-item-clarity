extends Node

# Carry-weight bar under the equipment stats row. Mirrors the game's own rules
# (Interface.UpdateStats): capacity is baseCarryWeight plus every equipped
# item's capacity, only items in the inventory grid count, and you're
# overweight once that weight exceeds capacity. The header turns yellow at
# 50% and red past 100%, so the bar uses the same thresholds.
#
# Hovering (or dragging) an item from a container or trader previews where its
# weight would take you; hovering one of your own items highlights its share.

const BAR_HEIGHT = 8.0
const GAP = 6.0
const LABEL_H = 16.0

# Defaults; the actual colours are user settings (Colors > Carry Weight Bar)
const DEFAULT_OK = Color(0.35, 0.85, 0.35)
const DEFAULT_WARN = Color(0.95, 0.8, 0.2)
const DEFAULT_OVER = Color(1.0, 0.35, 0.3)
const SEARCH_BOX_H = 30.0  # the search box sits directly under the inventory
const COLOR_BG = Color(0.06, 0.06, 0.06, 0.85)
const COLOR_BORDER = Color(0.3, 0.3, 0.3)

var enabled := true
var interface: Node = null  # set by Main

enum Position { UNDER_STATS, UNDER_INVENTORY }
var position_mode: int = Position.UNDER_STATS
var below_search := true      # Under Inventory: leave room for the search box
var color_ok := DEFAULT_OK
var color_warn := DEFAULT_WARN
var color_over := DEFAULT_OVER

var _root: Control = null
var _bar: Control = null
var _label: Label = null
var _bounds := Rect2()
var _bounds_at: int = -1000

# What the bar shows this frame
var _weight := 0.0
var _capacity := 0.0
var _preview := 0.0      # weight a hovered container item would add
var _share := 0.0        # weight of a hovered inventory item


func configure(on: bool, pos: int, search_on: bool, ok: Color, warn: Color, over: Color) -> void:
	enabled = on
	if pos != position_mode:
		_bounds = Rect2()  # re-measure against the new anchor
	position_mode = pos
	below_search = search_on
	color_ok = ok
	color_warn = warn
	color_over = over
	if not enabled and _root and is_instance_valid(_root):
		_root.visible = false


func _make() -> void:
	_root = Control.new()
	_root.name = "_icc_weight_bar"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	_root.add_child(_bar)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_root.add_child(_label)


func _get_interface() -> Node:
	if interface == null or not is_instance_valid(interface):
		interface = get_node_or_null("/root/Map/Core/UI/Interface")
	return interface


func _process(_delta: float) -> void:
	if _root == null or not is_instance_valid(_root):
		_make()
	var ui = _get_interface()
	# Anchor: the equipment stats row, or the inventory (some mods, like Gear
	# Storage Expansion, use the space under the equipment stats)
	var anchor: Control = null
	if ui:
		if position_mode == Position.UNDER_INVENTORY:
			anchor = ui.inventoryUI if "inventoryUI" in ui and ui.inventoryUI is Control else null
		else:
			anchor = ui.get_node_or_null("Equipment/Stats")
	var show: bool = enabled and ui != null and ui.visible and anchor != null and anchor.is_visible_in_tree() \
		and "currentInventoryCapacity" in ui
	_root.visible = show
	if not show:
		return
	_attach(ui)
	_place(anchor)

	_weight = float(ui.currentInventoryWeight)
	_capacity = max(0.01, float(ui.currentInventoryCapacity))
	_preview = 0.0
	_share = 0.0
	var item = ui.itemDragged if ("itemDragged" in ui and ui.itemDragged) else ui.hoverItem
	if item and is_instance_valid(item) and item.has_method("Weight"):
		var from_inventory: bool
		if item == ui.itemDragged:
			from_inventory = "returnGrid" in ui and ui.returnGrid == ui.inventoryGrid
		else:
			from_inventory = item.get_parent() == ui.inventoryGrid
		if from_inventory:
			_share = float(item.Weight())
		elif item.get_parent() != ui.equipment and not ("equipped" in item and item.equipped):
			_preview = float(item.Weight())

	_update_label()
	_bar.queue_redraw()


func _update_label() -> void:
	if _preview > 0.0:
		var after := _weight + _preview
		var text := "+%.1f kg -> %.1f / %.1f kg" % [_preview, after, _capacity]
		if after > _capacity and _weight <= _capacity:
			text += "  Overweight"
		_label.text = text
		_label.add_theme_color_override("font_color", _readable(color_over) if after > _capacity else Color(0.8, 0.8, 0.8))
	else:
		_label.text = "%.1f / %.1f kg" % [_weight, _capacity]
		_label.add_theme_color_override("font_color", _readable(color_over) if _weight > _capacity else Color(0.75, 0.75, 0.75))


func _color_for(fraction: float) -> Color:
	if fraction > 1.0:
		return color_over
	if fraction >= 0.5:
		return color_warn
	return color_ok


# Label text uses the colour at full opacity so it stays legible
func _readable(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 1.0)


func _draw_bar() -> void:
	var w: float = _bar.size.x
	var h: float = _bar.size.y
	_bar.draw_rect(Rect2(0, 0, w, h), COLOR_BG)
	var fraction: float = _weight / _capacity
	var fill: float = clamp(fraction, 0.0, 1.0) * w
	_bar.draw_rect(Rect2(0, 0, fill, h), _color_for(fraction))
	# Share of a hovered inventory item: bright band at the end of the fill
	if _share > 0.0:
		var share_w: float = clamp(_share / _capacity, 0.0, 1.0) * w
		var start: float = max(0.0, fill - share_w)
		var band := Rect2(start, 0, fill - start, h)
		_bar.draw_rect(band, Color(1, 1, 1, 0.55))
		_bar.draw_rect(band, Color(1, 1, 1, 0.9), false, 1.0)
	# Preview of a hovered container item: bright solid segment after the fill,
	# with a white seam where it starts so it reads against the same colour
	if _preview > 0.0:
		var after: float = (_weight + _preview) / _capacity
		var end: float = clamp(after, 0.0, 1.0) * w
		if end > fill:
			var seg := Rect2(fill, 0, end - fill, h)
			_bar.draw_rect(seg, _color_for(after).lightened(0.45))
			_bar.draw_rect(seg, Color(1, 1, 1, 0.85), false, 1.0)
			_bar.draw_line(Vector2(fill, -1), Vector2(fill, h + 1), Color(1, 1, 1, 0.95), 2.0)
	# Tick at 50%, where the game starts calling it heavy (yellow)
	_bar.draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, h), Color(1, 1, 1, 0.25), 1.0)
	_bar.draw_rect(Rect2(0, 0, w, h), COLOR_BORDER, false, 1.0)


# Live inside the Interface right before the right-click menu / tooltip, so
# both draw over the bar (same approach as the search box and buttons)
func _attach(ui: Node) -> void:
	if not ("tooltip" in ui) or not (ui.tooltip is Control):
		return
	var tooltip: Control = ui.tooltip
	var parent = tooltip.get_parent()
	if _root.get_parent() != parent:
		if _root.get_parent():
			_root.reparent(parent, false)
		else:
			parent.add_child(_root)
	var anchor_idx: int = tooltip.get_index()
	if "context" in ui and ui.context is Control and ui.context.get_parent() == parent:
		anchor_idx = min(anchor_idx, ui.context.get_index())
	if _root.get_index() > anchor_idx:
		parent.move_child(_root, anchor_idx)


# Directly under the anchor (equipment stats row or inventory), same width.
# Under the inventory it also clears the search box, which sits right there.
func _place(anchor: Control) -> void:
	var now := Time.get_ticks_msec()
	if now - _bounds_at > 250 or _bounds.size == Vector2.ZERO:
		_bounds_at = now
		_bounds = _covered_rect(anchor, Rect2())
	if _bounds.size.x < 64:
		return
	var y: float = _bounds.end.y + GAP
	if position_mode == Position.UNDER_INVENTORY:
		y = _bounds.end.y + 8.0 + (SEARCH_BOX_H + GAP if below_search else 0.0)
	_root.global_position = Vector2(_bounds.position.x, y).round()
	_root.size = Vector2(_bounds.size.x, BAR_HEIGHT + LABEL_H)
	_bar.position = Vector2.ZERO
	_bar.size = Vector2(_bounds.size.x, BAR_HEIGHT)
	_label.position = Vector2(0, BAR_HEIGHT + 1)
	_label.size = Vector2(_bounds.size.x, LABEL_H)


# The stats row reports ~zero size (children placed manually): measure them
func _covered_rect(node: Node, acc: Rect2) -> Rect2:
	if node is Control:
		if not node.visible or node.name.begins_with("_icc"):
			return acc
		if "slotData" in node:
			return acc  # items sit inside the grid; skip them
		var r: Rect2 = node.get_global_rect()
		if r.size.x > 0 and r.size.y > 0:
			acc = r if acc.size == Vector2.ZERO else acc.merge(r)
	for child in node.get_children():
		acc = _covered_rect(child, acc)
	return acc
