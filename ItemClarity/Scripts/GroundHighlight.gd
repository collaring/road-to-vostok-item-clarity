extends Node

# Outlines items lying on the ground (game class Pickup) when you're nearby.
# Uses each mesh's material_overlay with an inverted-hull outline shader, so
# no extra nodes are added to the world and the game's own materials are
# untouched. Distance is checked a few times per second, not every frame.

const CHECK_INTERVAL = 0.2

const OUTLINE_SHADER = """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix;

uniform vec4 outline_color : source_color = vec4(1.0);
uniform float grow = 0.004;

void vertex() {
	VERTEX += NORMAL * grow;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
"""

var enabled := true
var distance := 8.0
var in_shelters := false

var _game_data: Resource = null
var _material: ShaderMaterial = null
var _pickups: Array = []
var _outlined: Dictionary = {}  # pickup instance id -> Array[MeshInstance3D]
var _timer := 0.0


func _ready() -> void:
	_game_data = load("res://Resources/GameData.tres")
	var shader = Shader.new()
	shader.code = OUTLINE_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	set_color(Color("#ffffff0f"))


func configure(on: bool, dist: float, color: Color, shelters: bool) -> void:
	enabled = on
	distance = dist
	in_shelters = shelters
	set_color(color)
	if not enabled:
		_clear_all()
	_timer = CHECK_INTERVAL  # re-evaluate on the next frame


func set_color(color: Color) -> void:
	if _material:
		_material.set_shader_parameter("outline_color", color)


func track(node: Node) -> void:
	if node is Pickup and node not in _pickups:
		_pickups.append(node)


func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	if not enabled:
		return
	if not in_shelters and _game_data and "shelter" in _game_data and _game_data.shelter:
		_clear_all()
		return
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin: Vector3 = camera.global_position
	var max_sq: float = distance * distance
	var alive: Array = []
	for pickup in _pickups:
		if not is_instance_valid(pickup):
			continue
		alive.append(pickup)
		if not pickup.is_inside_tree():
			continue
		var near: bool = pickup.global_position.distance_squared_to(origin) <= max_sq
		var id: int = pickup.get_instance_id()
		if near and not _outlined.has(id):
			_outline(pickup)
		elif not near and _outlined.has(id):
			_unoutline(id)
	# Forget outlines on pickups that were picked up / freed
	for id in _outlined.keys():
		if not is_instance_id_valid(id):
			_outlined.erase(id)
	_pickups = alive


func _outline(pickup: Node) -> void:
	var meshes: Array = []
	_collect_meshes(pickup, meshes)
	var applied: Array = []
	for mesh in meshes:
		# Don't fight anything else that already uses the overlay slot
		if mesh.material_overlay == null:
			mesh.material_overlay = _material
			applied.append(mesh)
	_outlined[pickup.get_instance_id()] = applied


func _unoutline(id: int) -> void:
	for mesh in _outlined.get(id, []):
		if is_instance_valid(mesh) and mesh.material_overlay == _material:
			mesh.material_overlay = null
	_outlined.erase(id)


func _clear_all() -> void:
	for id in _outlined.keys():
		_unoutline(id)


# Includes attachment meshes on weapons lying on the ground
func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and node.visible:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)
