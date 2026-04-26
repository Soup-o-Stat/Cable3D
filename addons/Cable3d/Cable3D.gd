@tool
class_name Cable3D
extends Path3D

enum PresetShape {
	NONE,
	STRAIGHT,
	HANGING,
	ZIGZAG,
	ARC,
	CIRCLE}

@export var preset_shape: PresetShape = PresetShape.NONE:
	set(value):
		preset_shape = value
		if value != PresetShape.NONE:
			_apply_preset(value)
			preset_shape = PresetShape.NONE

@export var source_mesh: Mesh:
	set(value):
		source_mesh = value
		_cached_mesh = value
		_request_update()

@export var source_scene: PackedScene:
	set(value):
		source_scene = value
		_cached_mesh = _extract_mesh_from_scene(value)
		_request_update()

var _cached_mesh: Mesh

@export_range(0.01, 10.0, 0.01) var segment_length: float = 0.5:
	set(value):
		segment_length = max(value, 0.01)
		_request_update()

@export var material: Material:
	set(value):
		material = value
		_apply_material()

@export var align_to_curve: bool = true:
	set(value):
		align_to_curve = value
		_request_update()

@export var twist_per_meter: float = 0.0:
	set(value):
		twist_per_meter = value
		_request_update()

@export var random_rotation: float = 0.0:
	set(value):
		random_rotation = max(value, 0.0)
		_request_update()

@export var random_offset: float = 0.0:
	set(value):
		random_offset = max(value, 0.0)
		_request_update()

@export var scale_along: Vector3 = Vector3.ONE:
	set(value):
		scale_along = value
		_request_update()

@export var sag_amount: float = 0.0:
	set(value):
		sag_amount = value
		_request_update()

@export var rotation_offset: Vector3 = Vector3.ZERO:
	set(value):
		rotation_offset = value
		_request_update()

@export_range(0.0, 1.0, 0.01) var corner_smoothing: float = 0.0:
	set(value):
		corner_smoothing = clamp(value, 0.0, 1.0)
		_request_update()

@export var auto_update: bool = true

@export var regenerate: bool = false:
	set(value):
		regenerate = false
		_generate()

var multimesh_instance: MultiMeshInstance3D
var _needs_update := true
var _last_curve_length := -1.0

func _ready():
	if not multimesh_instance:
		multimesh_instance = MultiMeshInstance3D.new()
		multimesh_instance.name = "CableMultiMesh"
		add_child(multimesh_instance)
	if not curve:
		curve = Curve3D.new()
	_generate()

func _process(_delta):
	if not Engine.is_editor_hint():
		return
	if not auto_update:
		return
	if curve:
		var len = curve.get_baked_length()
		if len != _last_curve_length:
			_last_curve_length = len
			_request_update()
	if _needs_update:
		_generate()

func _extract_mesh_from_scene(scene: PackedScene) -> Mesh:
	if not scene:
		return null
	var instance = scene.instantiate()
	var meshes: Array = []
	_collect_meshes(instance, Transform3D.IDENTITY, meshes)
	instance.queue_free()
	if meshes.is_empty():
		return null
	return _merge_meshes(meshes)

func _collect_meshes(node: Node, parent_transform: Transform3D, meshes: Array):
	var current_transform = parent_transform
	if node is Node3D:
		current_transform = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh:
		meshes.append({"mesh": node.mesh, "transform": current_transform})
	for child in node.get_children():
		_collect_meshes(child, current_transform, meshes)

func _merge_meshes(meshes: Array) -> Mesh:
	var merged = ArrayMesh.new()
	for data in meshes:
		var mesh: Mesh = data.mesh
		var transform: Transform3D = data.transform
		for s in range(mesh.get_surface_count()):
			var arrays = mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			if vertices:
				for i in range(vertices.size()):
					vertices[i] = transform * vertices[i]
				arrays[Mesh.ARRAY_VERTEX] = vertices
			var normals = arrays[Mesh.ARRAY_NORMAL]
			if normals:
				for i in range(normals.size()):
					normals[i] = transform.basis * normals[i]
				arrays[Mesh.ARRAY_NORMAL] = normals
			var idx = merged.get_surface_count()
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat = mesh.surface_get_material(s)
			if mat:
				merged.surface_set_material(idx, mat)
	return merged

func _apply_preset(type):
	if not curve:
		curve = Curve3D.new()
	curve.clear_points()
	match type:
		PresetShape.STRAIGHT:
			curve.add_point(Vector3(0, 0, 0))
			curve.add_point(Vector3(5, 0, 0))
		PresetShape.HANGING:
			curve.add_point(Vector3(0, 0, 0))
			curve.add_point(Vector3(2.5, -2, 0))
			curve.add_point(Vector3(5, 0, 0))
		PresetShape.ZIGZAG:
			curve.add_point(Vector3(0, 0, 0))
			curve.add_point(Vector3(1, 1, 0))
			curve.add_point(Vector3(2, -1, 0))
			curve.add_point(Vector3(3, 1, 0))
			curve.add_point(Vector3(4, 0, 0))
		PresetShape.ARC:
			curve.add_point(Vector3(0, 0, 0))
			curve.add_point(Vector3(2.5, 2, 0))
			curve.add_point(Vector3(5, 0, 0))
		PresetShape.CIRCLE:
			var radius = 2.5
			var segments = 16
			for i in range(segments + 1):
				var a = float(i) / float(segments) * TAU
				curve.add_point(Vector3(cos(a) * radius, 0, sin(a) * radius))
	_request_update()

func _request_update():
	_needs_update = true

func _apply_material():
	if not multimesh_instance:
		return
	multimesh_instance.material_override = material if material else null

func _generate():
	_needs_update = false
	if not _cached_mesh or not curve:
		return
	if curve.point_count < 2:
		return
	var length = curve.get_baked_length()
	if length <= 0.0:
		return
	_last_curve_length = length
	var count = int(length / segment_length)
	if count <= 0:
		return
	count = min(count, 10000)
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _cached_mesh
	mm.instance_count = count
	var accumulated_twist := 0.0
	var prev_basis := Basis.IDENTITY
	for i in range(count):
		var distance = i * segment_length
		var t = distance / length
		var pos = curve.sample_baked(distance)
		var pos_next = curve.sample_baked(min(distance + 0.1, length))
		var forward = (pos_next - pos).normalized()
		var up = Vector3.UP
		var right = forward.cross(up).normalized()
		up = right.cross(forward).normalized()
		var target_basis = Basis(right, up, -forward)
		var transform := Transform3D.IDENTITY
		transform.origin = pos
		if sag_amount != 0.0:
			transform.origin.y -= (4.0 * t * (1.0 - t)) * sag_amount
		if align_to_curve:
			if corner_smoothing > 0.0:
				target_basis = prev_basis.slerp(target_basis, corner_smoothing)
			prev_basis = target_basis
			var basis = target_basis
			if twist_per_meter != 0.0:
				accumulated_twist += twist_per_meter * segment_length
				basis = basis.rotated(basis.z, accumulated_twist)
			if random_rotation != 0.0:
				basis = basis.rotated(basis.z, deg_to_rad(randf_range(-random_rotation, random_rotation)))
			transform.basis = basis
		if rotation_offset != Vector3.ZERO:
			var rot = Basis.from_euler(Vector3(
				deg_to_rad(rotation_offset.x),
				deg_to_rad(rotation_offset.y),
				deg_to_rad(rotation_offset.z)))
			transform.basis *= rot
		if random_offset != 0.0:
			transform.origin += Vector3(
				randf_range(-random_offset, random_offset),
				randf_range(-random_offset, random_offset),
				randf_range(-random_offset, random_offset))
		transform.basis = transform.basis.scaled(scale_along)
		mm.set_instance_transform(i, transform)
	multimesh_instance.multimesh = mm
	_apply_material()
