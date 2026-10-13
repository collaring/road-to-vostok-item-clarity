extends CanvasLayer

# Small dot at the centre of the screen, either always or only while the game's
# Interactor ray is on an item you can pick up, a container or a door (the same check
# the game uses before letting you interact), so you can see exactly where
# you're pointing without guessing where the screen centre is.

enum Mode { OFF, ALWAYS, ON_TARGET }

var mode: int = Mode.ON_TARGET
var color := Color(1, 1, 1, 0.85)
var radius := 2.5

var _game_data: Resource = null
var _canvas: Control = null
var _interactor: Node = null
var _interactor_checked_at: int = -10000
var _hide_flags: Array = []  # GameData flags that hide the dot, filtered once to ones that exist


func _ready() -> void:
	layer = 50  # above the HUD, below our own UI layers
	# The Esc menu pauses the tree (UIManager.ToggleSettings); keep updating so
	# we can hide ourselves instead of freezing on screen
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game_data = load("res://Resources/GameData.tres")
	if _game_data:
		for flag in ["interface", "settings", "menu", "isDead", "isAiming", "isScoped", "isPlacing", "decor", "freeze"]:
			if flag in _game_data:
				_hide_flags.append(flag)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)


func configure(new_mode: int, new_color: Color, new_radius: float) -> void:
	mode = new_mode
	color = new_color
	radius = new_radius
	if _canvas:
		_canvas.queue_redraw()
		if mode == Mode.OFF:
			_canvas.visible = false
	set_process(mode != Mode.OFF)  # nothing to do at all when it's off


func _process(_delta: float) -> void:
	var show := _should_show()
	if _canvas.visible != show:
		_canvas.visible = show


func _on_draw() -> void:
	var center: Vector2 = _canvas.size / 2.0
	# Thin dark rim keeps the dot readable on bright snow and sky
	_canvas.draw_circle(center, radius + 1.0, Color(0, 0, 0, color.a * 0.5))
	_canvas.draw_circle(center, radius, color)


func _should_show() -> bool:
	if mode == Mode.OFF or _game_data == null or get_tree().paused:
		return false
	for flag in _hide_flags:
		if _game_data.get(flag):
			return false
	if mode == Mode.ALWAYS:
		return true
	return _on_target()


# Interactor (a RayCast3D) sets gameData.interaction and keeps its last
# collider in "target"; it reports items via the "Item" group and containers
# via an Interactable collider whose owner is the LootContainer.
func _on_target() -> bool:
	if not ("interaction" in _game_data) or not _game_data.interaction:
		return false
	var ray = _get_interactor()
	if ray == null or not ray.is_colliding():
		return false
	var target = ray.get("target")
	if target == null or not is_instance_valid(target):
		return false
	if target.is_in_group("Item"):
		return true
	if not target.is_in_group("Interactable"):
		return false
	return target.owner is LootContainer or target.owner is Door


func _get_interactor() -> Node:
	if _interactor and is_instance_valid(_interactor) and _interactor.is_inside_tree():
		return _interactor
	_interactor = null
	var now := Time.get_ticks_msec()
	if now - _interactor_checked_at < 1000:
		return null  # don't search the tree every frame while it's missing
	_interactor_checked_at = now
	var core = get_node_or_null("/root/Map/Core")
	if core:
		_interactor = _find_interactor(core)
	return _interactor


func _find_interactor(node: Node) -> Node:
	if node is RayCast3D:
		var script = node.get_script()
		if script and script.resource_path.ends_with("Interactor.gd"):
			return node
	for child in node.get_children():
		var found = _find_interactor(child)
		if found:
			return found
	return null
