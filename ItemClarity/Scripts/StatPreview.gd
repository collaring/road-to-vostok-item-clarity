extends Node

# Character panel helpers:
#   - Preview: hovering a usable item shows what each vital would become if
#     consumed (Character.Consume simply adds itemData.health/energy/... to
#     gameData). The game's Vital label keeps updating underneath; we hide it
#     and draw our own label on top while previewing.
#   - Stat hover: hovering a vital outlines every usable item that raises it
#     (drawn by CompatHighlight via stat_filter).

const PREVIEW_NODE_NAME = "_icc_preview"
const UP_COLOR = Color(0.45, 0.85, 1.0)
const DOWN_COLOR = Color(1.0, 0.55, 0.2)
# Vital.Type enum order -> gameData / ItemData property
const STAT_PROPS = ["health", "energy", "hydration", "mental", "temperature"]

var preview_enabled := true
var highlight_enabled := true
var interface: Node = null  # set by Main
var compat: Node = null     # CompatHighlight, set by Main

var _game_data: Resource = null
var _vitals: Array = []     # Vital controls in the character panel
var _vital_rects: Dictionary = {}  # instance id -> Rect2 the vital actually covers
var _vitals_at: int = -10000
var _previewing: Resource = null


func _ready() -> void:
	_game_data = load("res://Resources/GameData.tres")


func configure(preview: bool, highlight: bool) -> void:
	preview_enabled = preview
	highlight_enabled = highlight
	if not preview_enabled:
		_clear_preview()
	if not highlight_enabled and compat:
		compat.stat_filter = ""


func _get_interface() -> Node:
	if interface == null or not is_instance_valid(interface):
		interface = get_node_or_null("/root/Map/Core/UI/Interface")
	return interface


func _process(_delta: float) -> void:
	var ui = _get_interface()
	if ui == null or not ui.visible or not ("characterUI" in ui) or not ui.characterUI.is_visible_in_tree():
		_clear_preview()
		if compat:
			compat.stat_filter = ""
		return
	_refresh_vitals(ui.characterUI)

	# Preview for the hovered item
	var data: Resource = null
	if preview_enabled and not ("itemDragged" in ui and ui.itemDragged):
		var item = ui.hoverItem if ui.hoverItem else ui.hoverEquipment
		if item and "slotData" in item and item.slotData and item.slotData.itemData:
			data = item.slotData.itemData
			if not data.usable:
				data = null
	if data != _previewing:
		_clear_preview()
		if data:
			_show_preview(data)

	# Stat hover -> outline items that raise it
	if compat:
		var stat := ""
		if highlight_enabled and data == null:
			var mouse: Vector2 = ui.characterUI.get_global_mouse_position()
			for vital in _vitals:
				if is_instance_valid(vital) and vital.is_visible_in_tree() 						and _vital_rects.get(vital.get_instance_id(), Rect2()).has_point(mouse):
					stat = _stat_of(vital)
					break
		compat.stat_filter = stat


func _refresh_vitals(panel: Node) -> void:
	var now := Time.get_ticks_msec()
	if now - _vitals_at < 2000 and not _vitals.is_empty():
		return
	_vitals_at = now
	_vitals = []
	_find_vitals(panel)
	# Vitals report ~zero size (children placed manually), so measure what
	# their label + value actually cover for hover detection
	_vital_rects = {}
	for vital in _vitals:
		_vital_rects[vital.get_instance_id()] = _covered_rect(vital, Rect2())


func _covered_rect(node: Node, acc: Rect2) -> Rect2:
	if node is Control:
		if not node.visible or node.name == PREVIEW_NODE_NAME:
			return acc
		var r: Rect2 = node.get_global_rect()
		if r.size.x > 0 and r.size.y > 0:
			acc = r if acc.size == Vector2.ZERO else acc.merge(r)
	for child in node.get_children():
		acc = _covered_rect(child, acc)
	return acc


func _find_vitals(node: Node) -> void:
	if node is Control and "type" in node and "value" in node and node.get("value") is Label:
		if _stat_of(node) != "":
			_vitals.append(node)
	for child in node.get_children():
		_find_vitals(child)


func _stat_of(vital: Node) -> String:
	var t = vital.get("type")
	if t is int and t >= 0 and t < STAT_PROPS.size():
		return STAT_PROPS[t]
	return ""


func _show_preview(data: Resource) -> void:
	_previewing = data
	for vital in _vitals:
		if not is_instance_valid(vital):
			continue
		var stat := _stat_of(vital)
		var delta: float = float(data.get(stat)) if stat in data else 0.0
		if delta == 0.0:
			continue
		var label: Label = vital.value
		var current: float = float(_game_data.get(stat))
		var result: float = clamp(current + delta, 0.0, 100.0)

		var overlay = Label.new()
		overlay.name = PREVIEW_NODE_NAME
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.text = str(int(round(result)))
		overlay.horizontal_alignment = label.horizontal_alignment
		overlay.vertical_alignment = label.vertical_alignment
		var font_size = label.get_theme_font_size("font_size")
		overlay.add_theme_font_size_override("font_size", font_size)
		overlay.add_theme_color_override("font_color", UP_COLOR if delta > 0 else DOWN_COLOR)

		# Small "+5" just right of the digits (not the column edge), raised
		var change = Label.new()
		change.text = ("+" if delta > 0 else "") + str(int(round(delta)))
		var small_size: int = max(10, int(font_size * 0.45))
		change.add_theme_font_size_override("font_size", small_size)
		change.add_theme_color_override("font_color", UP_COLOR if delta > 0 else DOWN_COLOR)
		change.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var font: Font = label.get_theme_font("font")
		var digits_w: float = font.get_string_size(overlay.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var digits_left: float = 0.0
		match label.horizontal_alignment:
			HORIZONTAL_ALIGNMENT_CENTER:
				digits_left = (label.size.x - digits_w) / 2.0
			HORIZONTAL_ALIGNMENT_RIGHT:
				digits_left = label.size.x - digits_w
		var text_h: float = font.get_height(font_size)
		var digits_top: float = (label.size.y - text_h) / 2.0 if label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER else 0.0
		change.position = Vector2(digits_left + digits_w + 1, digits_top)
		overlay.add_child(change)

		# Not a child of the label: the game tints it via modulate (red/yellow/
		# green) and children inherit that. Sit over it from the Vital instead.
		vital.add_child(overlay)
		if vital is Container:
			overlay.top_level = true
			overlay.global_position = label.global_position
		else:
			overlay.position = label.global_position - vital.global_position
		overlay.size = label.size
		label.self_modulate.a = 0.0  # hide the game's number while previewing


func _clear_preview() -> void:
	_previewing = null
	for vital in _vitals:
		if not is_instance_valid(vital):
			continue
		var label = vital.get("value")
		if label is Label:
			label.self_modulate.a = 1.0
		var overlay = vital.get_node_or_null(PREVIEW_NODE_NAME)
		if overlay:
			overlay.free()
