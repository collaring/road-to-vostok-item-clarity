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

# Containers are big flat boxes: the inverted hull alone only shows on faces
# seen side-on, as a hairline. So they also get a glow: a faint tint over the
# whole surface that brightens toward edges turning away from you (fresnel).
const GLOW_SHADER = """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;

uniform vec4 outline_color : source_color = vec4(1.0);

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = outline_color.rgb;
	ALPHA = clamp(outline_color.a * (0.6 + rim * 3.0), 0.0, 0.9);
}
"""

const DOT_NODE_NAME = "_icc_dot"
const DOT_SIZE = 0.008     # with fixed_size this is roughly 6px at 1080p
const DOT_ALPHA = 0.85     # dots are tiny, so they ignore the outline's low alpha
const DOT_LIFT = 0.04      # metres above the object's top, so it doesn't hide the dot

# Camera-facing dot of constant screen size. "pull" moves it toward the camera
# (per instance), so a dot centred inside an object clears the object's own
# surface while walls and anything else in front still hide it.
const DOT_SHADER = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D dot_texture : source_color, filter_linear;
uniform vec4 dot_color : source_color = vec4(1.0);
uniform float dot_size = 0.008;
instance uniform float pull = 0.0;

void vertex() {
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	center.xyz += normalize(-center.xyz) * pull;
	float dist = max(-center.z, 0.05);
	center.xy += VERTEX.xy * dot_size * dist;
	POSITION = PROJECTION_MATRIX * center;
}

void fragment() {
	ALBEDO = dot_color.rgb;
	ALPHA = texture(dot_texture, UV).a * dot_color.a;
}
"""

enum Style { OUTLINE, DOT }
var style: int = Style.OUTLINE

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
var _glow_shader: Shader = null
var _pickups: Dictionary = {}     # instance id -> Pickup
var _containers: Dictionary = {}  # instance id -> LootContainer
var _outlined: Dictionary = {}    # instance id -> [Array[MeshInstance3D], ShaderMaterial, dot or null]
var _dot_material: ShaderMaterial = null
var _container_dot_material: ShaderMaterial = null
var dot_centered := true
var _dot_mesh: QuadMesh = null
var _dot_shader: Shader = null
var _dot_texture: Texture2D = null
var _dot_for: Dictionary = {}  # outline material -> matching dot material

# Marks: containers highlighted for a reason (search match, Quick Stack target)
# in that reason's colour, overriding the normal "unsearched" outline. A mark
# lasts while the inventory is open, then `linger` seconds after it closes, so
# it doesn't expire behind the inventory screen before you see it.
var _marks: Dictionary = {}          # instance id -> {node, tag, until, linger}
var _mark_materials: Dictionary = {} # tag -> ShaderMaterial
var _mark_colors: Dictionary = {}    # tag -> full-strength colour (marks fade from it)
var _timer := 0.0


func _ready() -> void:
	_game_data = load("res://Resources/GameData.tres")
	var shader = Shader.new()
	shader.code = OUTLINE_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("outline_color", Color("#ffffff26"))
	_glow_shader = Shader.new()
	_glow_shader.code = GLOW_SHADER
	_container_material = _make_container_material(Color("#ffd24d26"))

	# Dot style: a round, camera-facing quad of constant screen size
	var tex = GradientTexture2D.new()
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	tex.gradient = gradient
	_dot_mesh = QuadMesh.new()
	_dot_mesh.size = Vector2(1, 1)  # scaled in the shader
	var dot_shader = Shader.new()
	dot_shader.code = DOT_SHADER
	_dot_shader = dot_shader
	_dot_texture = tex
	_dot_material = _make_dot_material(dot_shader, tex, Color("#ffffff26"))
	_container_dot_material = _make_dot_material(dot_shader, tex, Color("#ffd24d26"))
	_dot_for[_material] = _dot_material
	_dot_for[_container_material] = _container_dot_material


func _make_dot_material(shader: Shader, tex: Texture2D, color: Color) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("dot_texture", tex)
	m.set_shader_parameter("dot_size", DOT_SIZE)
	_set_dot_color(m, color)
	return m


func _set_dot_color(m: ShaderMaterial, color: Color) -> void:
	m.set_shader_parameter("dot_color", Color(color.r, color.g, color.b, DOT_ALPHA))


# Glow over the surface, with the hull edge layered behind it as next_pass
func _make_container_material(color: Color) -> ShaderMaterial:
	var glow = ShaderMaterial.new()
	glow.shader = _glow_shader
	var edge = ShaderMaterial.new()
	edge.shader = _material.shader
	glow.next_pass = edge
	_set_container_color(glow, color)
	return glow


func _set_container_color(glow: ShaderMaterial, color: Color) -> void:
	glow.set_shader_parameter("outline_color", color)
	if glow.next_pass is ShaderMaterial:
		glow.next_pass.set_shader_parameter("outline_color", color)


func set_dot_centered(value: bool) -> void:
	if value == dot_centered:
		return
	dot_centered = value
	if style == Style.DOT:
		_clear(_pickups)
		_clear(_containers)
		_timer = CHECK_INTERVAL


func set_style(value: int) -> void:
	if value == style:
		return
	_clear(_pickups)
	_clear(_containers)
	style = value
	_timer = CHECK_INTERVAL

func configure(on: bool, dist: float, color: Color, shelters: bool) -> void:
	enabled = on
	distance = dist
	in_shelters = shelters
	_material.set_shader_parameter("outline_color", color)
	_set_dot_color(_dot_material, color)
	if not enabled:
		_clear(_pickups)
	_timer = CHECK_INTERVAL  # re-evaluate on the next frame


func configure_containers(on: bool, dist: float, color: Color) -> void:
	containers_enabled = on
	container_distance = dist
	_set_container_color(_container_material, color)
	_set_dot_color(_container_dot_material, color)
	if not containers_enabled:
		_clear(_containers)
	_timer = CHECK_INTERVAL


func track(node: Node) -> void:
	if node is Pickup:
		_pickups[node.get_instance_id()] = node
	elif node is LootContainer:
		_containers[node.get_instance_id()] = node


func _process(delta: float) -> void:
	_fade_marks()
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

	_update_marks()
	if containers_enabled:
		_update(_containers, _container_material, container_distance, origin, _container_eligible, _marks)


func _update(nodes: Dictionary, material: ShaderMaterial, dist: float, origin: Vector3, eligible: Callable, skip: Dictionary = {}) -> void:
	var max_sq: float = dist * dist
	for id in nodes.keys():
		var node = nodes[id]
		if not is_instance_valid(node):
			nodes.erase(id)
			_outlined.erase(id)  # its meshes were freed along with it
			continue
		if not node.is_inside_tree() or skip.has(id):
			continue
		# Distance first: eligibility walks up the tree, and most of the map is far away
		var near: bool = node.global_position.distance_squared_to(origin) <= max_sq and eligible.call(node)
		if near and not _outlined.has(id):
			_outline(node, material)
		elif not near and _outlined.has(id):
			_unoutline(id)


# ── Marks ────────────────────────────────────────────────────────────────────

# Replaces this tag's marks with `nodes`
func set_marks(tag: String, nodes: Array, color: Color, linger: float) -> void:
	clear_marks(tag)
	var mat: ShaderMaterial = _mark_materials.get(tag)
	if mat == null:
		mat = _make_container_material(color)  # marks are always containers
		_mark_materials[tag] = mat
		_dot_for[mat] = _make_dot_material(_dot_shader, _dot_texture, color)
	_mark_colors[tag] = color
	_set_container_color(mat, color)
	_set_dot_color(_dot_for[mat], color)
	for node in nodes:
		if is_instance_valid(node):
			_marks[node.get_instance_id()] = {"node": node, "tag": tag, "until": -1, "linger": linger}
	_timer = CHECK_INTERVAL  # show right away


# Once a mark's countdown has started (inventory closed), its colour eases out
# to nothing over that time instead of switching off. Runs every frame so the
# fade is smooth, but only does work while something is actually fading.
func _fade_marks() -> void:
	if _marks.is_empty():
		return
	var now := Time.get_ticks_msec()
	var ends: Dictionary = {}  # tag -> [latest until, linger]
	for id in _marks:
		var m: Dictionary = _marks[id]
		if m["until"] != -1:
			var cur = ends.get(m["tag"])
			if cur == null or m["until"] > cur[0]:
				ends[m["tag"]] = [m["until"], m["linger"]]
	for tag in ends:
		var mat: ShaderMaterial = _mark_materials.get(tag)
		var base: Color = _mark_colors.get(tag, Color.WHITE)
		if mat == null:
			continue
		var total: float = max(1.0, float(ends[tag][1]) * 1000.0)
		var t: float = clamp(float(ends[tag][0] - now) / total, 0.0, 1.0)
		t = t * t  # ease out: lingers bright, then falls away
		_set_container_color(mat, Color(base.r, base.g, base.b, base.a * t))
		var dot: ShaderMaterial = _dot_for.get(mat)
		if dot:
			dot.set_shader_parameter("dot_color", Color(base.r, base.g, base.b, DOT_ALPHA * t))


func clear_marks(tag: String) -> void:
	for id in _marks.keys():
		if _marks[id]["tag"] == tag:
			_marks.erase(id)
			if _outlined.has(id) and _outlined[id][1] == _mark_materials.get(tag):
				_unoutline(id)  # the normal container pass picks it up again if eligible


func _update_marks() -> void:
	if _marks.is_empty():
		return
	var ui_open: bool = interface != null and is_instance_valid(interface) and interface.visible
	var now := Time.get_ticks_msec()
	for id in _marks.keys():
		var m: Dictionary = _marks[id]
		var node = m["node"]
		var mat: ShaderMaterial = _mark_materials.get(m["tag"])
		if not is_instance_valid(node):
			_marks.erase(id)
			_outlined.erase(id)
			continue
		if m["until"] == -1 and not ui_open:
			m["until"] = now + int(m["linger"] * 1000.0)  # countdown starts once you can see it
		if m["until"] != -1 and now > m["until"]:
			_marks.erase(id)
			if _outlined.has(id) and _outlined[id][1] == mat:
				_unoutline(id)
			continue
		if _outlined.has(id) and _outlined[id][1] != mat:
			_unoutline(id)
		if not _outlined.has(id) and node.is_inside_tree():
			_outline(node, mat)


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
	if style == Style.DOT:
		_outlined[node.get_instance_id()] = [[], material, _add_dot(node, meshes, material)]
		return
	var applied: Array = []
	for mesh in meshes:
		# Don't fight anything else that already uses the overlay slot
		if mesh.material_overlay == null:
			mesh.material_overlay = material
			applied.append(mesh)
	_outlined[node.get_instance_id()] = [applied, material, null]


# Dot above the top-centre of the object's combined bounds, or at its centre
func _add_dot(node: Node, meshes: Array, material: ShaderMaterial) -> Node:
	if meshes.is_empty() or not (node is Node3D):
		return null
	var bounds: AABB = meshes[0].global_transform * meshes[0].get_aabb()
	for i in range(1, meshes.size()):
		bounds = bounds.merge(meshes[i].global_transform * meshes[i].get_aabb())
	var dot = MeshInstance3D.new()
	dot.name = DOT_NODE_NAME
	dot.mesh = _dot_mesh
	dot.material_override = _dot_for.get(material, _dot_material)
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(dot)
	var center: Vector3 = bounds.get_center()
	if dot_centered:
		dot.global_position = center
		# Enough to clear the object's own surface toward the camera
		dot.set_instance_shader_parameter("pull", bounds.size.length() * 0.5 + 0.02)
	else:
		dot.global_position = Vector3(center.x, bounds.end.y + DOT_LIFT, center.z)
	return dot


func _unoutline(id: int) -> void:
	var entry = _outlined.get(id)
	if entry:
		for mesh in entry[0]:
			if is_instance_valid(mesh) and mesh.material_overlay == entry[1]:
				mesh.material_overlay = null
		if entry[2] != null and is_instance_valid(entry[2]):
			entry[2].queue_free()
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
	if node is MeshInstance3D and node.visible and node.name != DOT_NODE_NAME:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out, false)
