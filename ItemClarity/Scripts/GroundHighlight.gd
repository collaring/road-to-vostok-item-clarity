extends Node

# World highlights: outlines items lying on the ground (game class Pickup)
# and, optionally, containers you haven't searched yet (LootContainer) when
# you're nearby. Uses each mesh's material_overlay with an inverted-hull
# outline shader, so no extra nodes are added to the world and the game's
# own materials are untouched. Distance is checked a few times per second.

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

# Ground items
var enabled := true
var distance := 8.0
var in_shelters := false
# Containers
var containers_enabled := false
var container_distance := 8.0

var interface: Node = null  # set by Main; used to skip the container you have open

var _game_data: Resource = null
var _material: ShaderMaterial = null
var _container_material: ShaderMaterial = null
var _pickups: Dictionary = {}     # instance id -> Pickup
var _containers: Dictionary = {}  # instance id -> LootContainer
var _outlined: Dictionary = {}    # instance id -> [Array[MeshInstance3D], ShaderMaterial]
var _timer := 0.0


func _ready() -> void:
	_game_data = load("res://Resources/GameData.tres")
	var shader = Shader.new()
	shader.code = OUTLINE_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("outline_color", Color("#ffffff26"))
	_container_material = ShaderMaterial.new()
	_container_material.shader = shader
	_container_material.set_shader_parameter("outline_color", Color("#ffd24d26"))


func configure(on: bool, dist: float, color: Color, shelters: bool) -> void:
	enabled = on
	distance = dist
	in_shelters = shelters
	_material.set_shader_parameter("outline_color", color)
	if not enabled:
		_clear(_pickups)
	_timer = CHECK_INTERVAL  # re-evaluate on the next frame


func configure_containers(on: bool, dist: float, color: Color) -> void:
	containers_enabled = on
	container_distance = dist
	_container_material.set_shader_parameter("outline_color", color)
	if not containers_enabled:
		_clear(_containers)
	_timer = CHECK_INTERVAL


func track(node: Node) -> void:
	if node is Pickup:
		_pickups[node.get_instance_id()] = node
	elif node is LootContainer:
		_containers[node.get_instance_id()] = node


func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin: Vector3 = camera.global_position

	var in_shelter: bool = _game_data and "shelter" in _game_data and _game_data.shelter
	if enabled and (in_shelters or not in_shelter):
		_update(_pickups, _material, distance, origin, _item_eligible)
	else:
		_clear(_pickups)

	if containers_enabled:
		_update(_containers, _container_material, container_distance, origin, _container_eligible)


func _update(nodes: Dictionary, material: ShaderMaterial, dist: float, origin: Vector3, eligible: Callable) -> void:
	var max_sq: float = dist * dist
	for id in nodes.keys():
		var node = nodes[id]
		if not is_instance_valid(node):
			nodes.erase(id)
			_outlined.erase(id)  # its meshes were freed along with it
			continue
		if not node.is_inside_tree():
			continue
		var near: bool = eligible.call(node) and node.global_position.distance_squared_to(origin) <= max_sq
		if near and not _outlined.has(id):
			_outline(node, material)
		elif not near and _outlined.has(id):
			_unoutline(id)


# Only items the player can actually pick up: the game's Interactor only acts
# on colliders in the "Item" group (trader displays and set dressing aren't),
# and guns held by living NPCs are skipped until the NPC dies.
func _item_eligible(pickup: Node) -> bool:
	if not pickup.is_in_group("Item"):
		return false
	if pickup is CollisionObject3D and pickup.collision_layer == 0:
		return false
	# Trader shelves: TraderDisplay.gd freezes its Pickups and disables their
	# collision shape, which is what makes them impossible to pick up
	if "collision" in pickup and pickup.collision is CollisionShape3D and pickup.collision.disabled:
		return false
	var parent = pickup.get_parent()
	var script = parent.get_script() if parent else null
	if script and script.resource_path.ends_with("TraderDisplay.gd"):
		return false
	return _not_on_living_npc(pickup)


# Unsearched, openable containers. LootContainer.Interact refuses when locked
# (trader displays lock theirs too); shelter furniture is flagged "furniture";
# stashes that didn't spawn are hidden; "storaged" becomes true once you've
# opened and closed it, and containers are rebuilt every raid.
func _container_eligible(container: Node) -> bool:
	if container.locked or container.furniture or container.storaged:
		return false
	if not container.is_visible_in_tree():
		return false
	if interface and is_instance_valid(interface) and "container" in interface and interface.container == container:
		return false  # open right now
	return _not_on_living_npc(container)


func _not_on_living_npc(node: Node) -> bool:
	var parent = node.get_parent()
	while parent != null:
		if "dead" in parent and parent.get("dead") is bool:
			return parent.dead
		parent = parent.get_parent()
	return true


func _outline(node: Node, material: ShaderMaterial) -> void:
	var meshes: Array = []
	_collect_meshes(node, meshes)
	var applied: Array = []
	for mesh in meshes:
		# Don't fight anything else that already uses the overlay slot
		if mesh.material_overlay == null:
			mesh.material_overlay = material
			applied.append(mesh)
	_outlined[node.get_instance_id()] = [applied, material]


func _unoutline(id: int) -> void:
	var entry = _outlined.get(id)
	if entry:
		for mesh in entry[0]:
			if is_instance_valid(mesh) and mesh.material_overlay == entry[1]:
				mesh.material_overlay = null
	_outlined.erase(id)


func _clear(nodes: Dictionary) -> void:
	for id in nodes.keys():
		if _outlined.has(id):
			_unoutline(id)


# Includes attachment meshes on weapons lying on the ground. Doesn't descend
# into Pickups nested under another node (e.g. a gun on a body), which are
# outlined on their own terms.
func _collect_meshes(node: Node, out: Array, root: bool = true) -> void:
	if not root and node is Pickup:
		return
	if node is MeshInstance3D and node.visible:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out, false)
