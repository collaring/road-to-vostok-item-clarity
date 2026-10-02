extends Node

# "Tooltip Rework": smooths out the game's inventory tooltip without replacing
# any game script. The game (Interface._physics_process) hides the tooltip on
# every mouse movement, positions it only at physics rate, refreshes content
# every 10 physics frames and never keeps it on screen. We patch around that:
#   - before the game's physics tick, sync lastMousePosition so moving the
#     mouse no longer counts as "moved" and the tooltip stays up
#   - every rendered frame (after the game), place it next to the cursor,
#     clamped to the screen, and refresh it instantly when the hover changes

const CURSOR_OFFSET = Vector2(20, 20)
const SCREEN_MARGIN = 8.0
const FADE_TIME = 0.08

var enabled := true
var interface: Node = null  # set by Main when the Interface node appears

var _last_hover: Object = null
var _shown := false
var _tween: Tween = null


func _ready() -> void:
	# Run our physics step before the game's, and our frame step after it
	process_physics_priority = -100
	process_priority = 100


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		var tooltip = _get_tooltip()
		if tooltip:
			tooltip.modulate.a = 1.0
		_shown = false
		_last_hover = null


func _get_interface() -> Node:
	if interface == null or not is_instance_valid(interface):
		interface = get_node_or_null("/root/Map/Core/UI/Interface")
	return interface


func _get_tooltip() -> Control:
	var ui = _get_interface()
	if ui == null or not ("tooltip" in ui):
		return null
	var tooltip = ui.tooltip
	if tooltip is Control and is_instance_valid(tooltip):
		return tooltip
	return null


func _active(ui: Node) -> bool:
	return enabled and ui != null and ui.visible \
		and ("tooltipMode" in ui) and ui.tooltipMode == 1


func _physics_process(_delta: float) -> void:
	var ui = _get_interface()
	if not _active(ui) or not ("lastMousePosition" in ui):
		return
	ui.lastMousePosition = ui.get_global_mouse_position()


func _process(_delta: float) -> void:
	var ui = _get_interface()
	if not _active(ui):
		return
	var tooltip = _get_tooltip()
	if tooltip == null:
		return
	if not tooltip.visible:
		_shown = false
		_last_hover = null
		return

	# Refresh content right away when sliding onto a different item. Same
	# precedence as the game: Info, then equipment, then item (last call wins)
	var hover: Object = null
	var is_info := false
	if ui.hoverInfo:
		hover = ui.hoverInfo
		is_info = true
	elif ui.hoverEquipment:
		hover = ui.hoverEquipment
	elif ui.hoverItem:
		hover = ui.hoverItem
	if hover != null and hover != _last_hover:
		_last_hover = hover
		if is_info:
			tooltip.Info(hover)
		else:
			tooltip.Update(hover)

	_place(tooltip)

	if not _shown:
		_shown = true
		if _tween and _tween.is_valid():
			_tween.kill()
		tooltip.modulate.a = 0.0
		_tween = create_tween()
		_tween.tween_property(tooltip, "modulate:a", 1.0, FADE_TIME)


func _place(tooltip: Control) -> void:
	# Size the visible panel from its minimum size so it's correct even on the
	# frame its content changed (layout hasn't run yet)
	var panel: Control = tooltip.panel if "panel" in tooltip and tooltip.panel is Control else tooltip
	var size: Vector2 = panel.get_combined_minimum_size()
	size.x = max(size.x, panel.size.x)

	var mouse: Vector2 = tooltip.get_global_mouse_position()
	var screen: Vector2 = tooltip.get_viewport_rect().size

	var pos: Vector2 = mouse + CURSOR_OFFSET
	if pos.x + size.x > screen.x - SCREEN_MARGIN:
		pos.x = mouse.x - CURSOR_OFFSET.x - size.x  # flip to the left of the cursor
	if pos.y + size.y > screen.y - SCREEN_MARGIN:
		pos.y = screen.y - SCREEN_MARGIN - size.y
	pos.x = clamp(pos.x, SCREEN_MARGIN, max(SCREEN_MARGIN, screen.x - SCREEN_MARGIN - size.x))
	pos.y = clamp(pos.y, SCREEN_MARGIN, max(SCREEN_MARGIN, screen.y - SCREEN_MARGIN - size.y))

	# The panel may sit at an offset inside the tooltip root
	var panel_offset: Vector2 = panel.global_position - tooltip.global_position
	tooltip.global_position = (pos - panel_offset).round()
