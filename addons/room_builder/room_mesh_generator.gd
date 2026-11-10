@tool
class_name RoomMeshGenerator
extends RefCounted

static func build_contour_floor_mesh(poly_2d: PackedVector2Array, color: Color) -> ArrayMesh:
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(poly_2d)
	if triangles.is_empty():
		push_warning("[RoomMeshGenerator] Failed to triangulate floor polygon.")
		return null

	var st_floor := SurfaceTool.new()
	st_floor.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i: int in range(0, triangles.size(), 3):
		var i0: int = triangles[i]
		var i1: int = triangles[i + 1]
		var i2: int = triangles[i + 2]

		var p0_2d: Vector2 = poly_2d[i0]
		var p1_2d: Vector2 = poly_2d[i1]
		var p2_2d: Vector2 = poly_2d[i2]

		var v0 := Vector3(p0_2d.x, 0.0, p0_2d.y)
		var v1 := Vector3(p1_2d.x, 0.0, p1_2d.y)
		var v2 := Vector3(p2_2d.x, 0.0, p2_2d.y)

		# In Godot, front faces use Clockwise winding.
		# When viewed from +Y looking down, cross product (v1 - v0).cross(v2 - v0).y < 0.0 is Clockwise.
		# If CCW (y > 0.0), swap indices [i0, i2, i1] so normal faces UP (Vector3.UP) into the room.
		var face_norm: Vector3 = (v1 - v0).cross(v2 - v0)
		var tri_indices: Array[int] = [i0, i1, i2]
		if face_norm.y > 0.0:
			tri_indices = [i0, i2, i1]

		for idx: int in tri_indices:
			var p2: Vector2 = poly_2d[idx]
			var v := Vector3(p2.x, 0.0, p2.y)
			st_floor.set_normal(Vector3.UP)
			st_floor.set_uv(Vector2(v.x, v.z) * 0.25)
			st_floor.add_vertex(v)

	st_floor.generate_normals()
	st_floor.generate_tangents()

	var floor_mesh: ArrayMesh = st_floor.commit()

	# Safeguard: Verify floor normal points UP (+Y)
	var floor_arrays: Array = floor_mesh.surface_get_arrays(0)
	var floor_normals: PackedVector3Array = floor_arrays[Mesh.ARRAY_NORMAL]
	if floor_normals.size() > 0 and floor_normals[0].y < 0.0:
		st_floor.clear()
		st_floor.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i: int in range(0, triangles.size(), 3):
			var i0: int = triangles[i]
			var i1: int = triangles[i + 1]
			var i2: int = triangles[i + 2]
			var v0 := Vector3(poly_2d[i0].x, 0.0, poly_2d[i0].y)
			var v1 := Vector3(poly_2d[i1].x, 0.0, poly_2d[i1].y)
			var v2 := Vector3(poly_2d[i2].x, 0.0, poly_2d[i2].y)
			var face_norm: Vector3 = (v1 - v0).cross(v2 - v0)
			var tri_indices: Array[int] = [i0, i1, i2]
			if face_norm.y < 0.0:
				tri_indices = [i0, i2, i1]
			for idx: int in tri_indices:
				var v := Vector3(poly_2d[idx].x, 0.0, poly_2d[idx].y)
				st_floor.set_normal(Vector3.UP)
				st_floor.set_uv(Vector2(v.x, v.z) * 0.25)
				st_floor.add_vertex(v)
		st_floor.generate_normals()
		st_floor.generate_tangents()
		floor_mesh = st_floor.commit()

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = color
	floor_mat.roughness = 0.7
	floor_mat.cull_mode = BaseMaterial3D.CULL_BACK
	floor_mesh.surface_set_material(0, floor_mat)

	return floor_mesh

static func build_contour_ceiling_mesh(poly_2d: PackedVector2Array, wall_height: float, color: Color) -> ArrayMesh:
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(poly_2d)
	if triangles.is_empty():
		push_warning("[RoomMeshGenerator] Failed to triangulate ceiling polygon.")
		return null

	var st_ceil := SurfaceTool.new()
	st_ceil.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i: int in range(0, triangles.size(), 3):
		var i0: int = triangles[i]
		var i1: int = triangles[i + 1]
		var i2: int = triangles[i + 2]

		var p0_2d: Vector2 = poly_2d[i0]
		var p1_2d: Vector2 = poly_2d[i1]
		var p2_2d: Vector2 = poly_2d[i2]

		var v0 := Vector3(p0_2d.x, wall_height, p0_2d.y)
		var v1 := Vector3(p1_2d.x, wall_height, p1_2d.y)
		var v2 := Vector3(p2_2d.x, wall_height, p2_2d.y)

		# Viewed from +Y looking down, CCW (face_norm.y > 0.0) makes the ceiling a back-face from above
		# and a front-face from below (viewed from inside room floor looking up).
		# Normal will point DOWN (Vector3.DOWN) into the room.
		var face_norm: Vector3 = (v1 - v0).cross(v2 - v0)
		var tri_indices: Array[int] = [i0, i1, i2]
		if face_norm.y < 0.0:
			tri_indices = [i0, i2, i1]

		for idx: int in tri_indices:
			var p2: Vector2 = poly_2d[idx]
			var v := Vector3(p2.x, wall_height, p2.y)
			st_ceil.set_normal(Vector3.DOWN)
			st_ceil.set_uv(Vector2(v.x, v.z) * 0.25)
			st_ceil.add_vertex(v)

	st_ceil.generate_normals()
	st_ceil.generate_tangents()

	var ceil_mesh: ArrayMesh = st_ceil.commit()

	# Safeguard: Verify ceiling normal points DOWN (-Y) into the room
	var ceil_arrays: Array = ceil_mesh.surface_get_arrays(0)
	var ceil_normals: PackedVector3Array = ceil_arrays[Mesh.ARRAY_NORMAL]
	if ceil_normals.size() > 0 and ceil_normals[0].y > 0.0:
		st_ceil.clear()
		st_ceil.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i: int in range(0, triangles.size(), 3):
			var i0: int = triangles[i]
			var i1: int = triangles[i + 1]
			var i2: int = triangles[i + 2]
			var v0 := Vector3(poly_2d[i0].x, wall_height, poly_2d[i0].y)
			var v1 := Vector3(poly_2d[i1].x, wall_height, poly_2d[i1].y)
			var v2 := Vector3(poly_2d[i2].x, wall_height, poly_2d[i2].y)
			var face_norm: Vector3 = (v1 - v0).cross(v2 - v0)
			var tri_indices: Array[int] = [i0, i1, i2]
			if face_norm.y > 0.0:
				tri_indices = [i0, i2, i1]
			for idx: int in tri_indices:
				var v := Vector3(poly_2d[idx].x, wall_height, poly_2d[idx].y)
				st_ceil.set_normal(Vector3.DOWN)
				st_ceil.set_uv(Vector2(v.x, v.z) * 0.25)
				st_ceil.add_vertex(v)
		st_ceil.generate_normals()
		st_ceil.generate_tangents()
		ceil_mesh = st_ceil.commit()

	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = color
	ceil_mat.roughness = 0.85
	ceil_mat.cull_mode = BaseMaterial3D.CULL_BACK
	ceil_mesh.surface_set_material(0, ceil_mat)

	return ceil_mesh

static func build_box_floor_mesh(width: float, depth: float, color: Color) -> BoxMesh:
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(width, 0.4, depth)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	box_mesh.material = mat
	return box_mesh

static func build_box_ceiling_mesh(width: float, depth: float, wall_height: float, color: Color) -> ArrayMesh:
	var st_ceil := SurfaceTool.new()
	st_ceil.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_w: float = width * 0.5
	var half_d: float = depth * 0.5

	var v0 := Vector3(-half_w, wall_height, -half_d)
	var v1 := Vector3(half_w, wall_height, -half_d)
	var v2 := Vector3(half_w, wall_height, half_d)
	var v3 := Vector3(-half_w, wall_height, half_d)

	# CCW when viewed from above (+Y looking down) makes it a back-face from above
	# and front-face from below (normal points DOWN into room).
	# Triangle 1: v0 -> v2 -> v1
	st_ceil.set_normal(Vector3.DOWN)
	st_ceil.set_uv(Vector2(-half_w, -half_d) * 0.25)
	st_ceil.add_vertex(v0)
	st_ceil.set_normal(Vector3.DOWN)
	st_ceil.set_uv(Vector2(half_w, half_d) * 0.25)
	st_ceil.add_vertex(v2)
	st_ceil.set_normal(Vector3.DOWN)
	st_ceil.set_uv(Vector2(half_w, -half_d) * 0.25)
	st_ceil.add_vertex(v1)

	# Triangle 2: v0 -> v3 -> v2
	st_ceil.set_normal(Vector3.DOWN)
	st_ceil.set_uv(Vector2(-half_w, -half_d) * 0.25)
	st_ceil.add_vertex(v0)
	st_ceil.set_normal(Vector3.DOWN)
	st_ceil.set_uv(Vector2(-half_w, half_d) * 0.25)
	st_ceil.add_vertex(v3)
	st_ceil.set_normal(Vector3.DOWN)
	st_ceil.set_uv(Vector2(half_w, half_d) * 0.25)
	st_ceil.add_vertex(v2)

	st_ceil.generate_normals()
	st_ceil.generate_tangents()

	var ceil_mesh: ArrayMesh = st_ceil.commit()

	# Safeguard: Verify normal points DOWN (-Y)
	var ceil_arrays: Array = ceil_mesh.surface_get_arrays(0)
	var ceil_normals: PackedVector3Array = ceil_arrays[Mesh.ARRAY_NORMAL]
	if ceil_normals.size() > 0 and ceil_normals[0].y > 0.0:
		st_ceil.clear()
		st_ceil.begin(Mesh.PRIMITIVE_TRIANGLES)
		st_ceil.set_normal(Vector3.DOWN)
		st_ceil.set_uv(Vector2(-half_w, -half_d) * 0.25)
		st_ceil.add_vertex(v0)
		st_ceil.set_normal(Vector3.DOWN)
		st_ceil.set_uv(Vector2(half_w, -half_d) * 0.25)
		st_ceil.add_vertex(v1)
		st_ceil.set_normal(Vector3.DOWN)
		st_ceil.set_uv(Vector2(half_w, half_d) * 0.25)
		st_ceil.add_vertex(v2)

		st_ceil.set_normal(Vector3.DOWN)
		st_ceil.set_uv(Vector2(-half_w, -half_d) * 0.25)
		st_ceil.add_vertex(v0)
		st_ceil.set_normal(Vector3.DOWN)
		st_ceil.set_uv(Vector2(half_w, half_d) * 0.25)
		st_ceil.add_vertex(v2)
		st_ceil.set_normal(Vector3.DOWN)
		st_ceil.set_uv(Vector2(-half_w, half_d) * 0.25)
		st_ceil.add_vertex(v3)
		st_ceil.generate_normals()
		st_ceil.generate_tangents()
		ceil_mesh = st_ceil.commit()

	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = color
	ceil_mat.roughness = 0.85
	ceil_mat.cull_mode = BaseMaterial3D.CULL_BACK
	ceil_mesh.surface_set_material(0, ceil_mat)

	return ceil_mesh

static func calculate_wall_segments(poly_2d: PackedVector2Array, wall_height: float) -> Array[Dictionary]:
	var count_2d: int = poly_2d.size()
	var segments: Array[Dictionary] = []
	for i: int in range(count_2d):
		var p_curr_2d: Vector2 = poly_2d[i]
		var p_next_2d: Vector2 = poly_2d[(i + 1) % count_2d]
		var p_curr := Vector3(p_curr_2d.x, 0.0, p_curr_2d.y)
		var p_next := Vector3(p_next_2d.x, 0.0, p_next_2d.y)
		var seg_len: float = p_curr.distance_to(p_next)
		if seg_len < 0.05:
			continue

		var seg_dir: Vector3 = (p_next - p_curr).normalized()
		var y_axis: Vector3 = Vector3.UP
		var x_axis: Vector3 = y_axis.cross(seg_dir).normalized()
		var seg_basis := Basis(x_axis, y_axis, seg_dir)
		var mid_pt: Vector3 = (p_curr + p_next) * 0.5
		var seg_pos := Vector3(mid_pt.x, wall_height * 0.5, mid_pt.z)
		var seg_xform := Transform3D(seg_basis, seg_pos)

		segments.append({
			"transform": seg_xform,
			"length": seg_len
		})
	return segments

static func calculate_contour_door_transform(poly_2d: PackedVector2Array, wall_thickness: float) -> Transform3D:
	var count_2d: int = poly_2d.size()
	if count_2d < 2:
		return Transform3D.IDENTITY

	var best_idx: int = -1
	var max_len: float = 0.0
	for i: int in range(count_2d):
		var seg_len: float = poly_2d[i].distance_to(poly_2d[(i + 1) % count_2d])
		if seg_len > max_len:
			max_len = seg_len
			best_idx = i

	if best_idx == -1 or max_len < 0.05:
		return Transform3D.IDENTITY

	var p_a_2d: Vector2 = poly_2d[best_idx]
	var p_b_2d: Vector2 = poly_2d[(best_idx + 1) % count_2d]
	var p_a := Vector3(p_a_2d.x, 0.0, p_a_2d.y)
	var p_b := Vector3(p_b_2d.x, 0.0, p_b_2d.y)
	var dir_ab: Vector3 = (p_b - p_a).normalized()
	var norm_candidate: Vector3 = dir_ab.cross(Vector3.UP).normalized()
	var mid_2d: Vector2 = (p_a_2d + p_b_2d) * 0.5
	var test_pt: Vector2 = mid_2d + Vector2(norm_candidate.x, norm_candidate.z) * 0.5
	var inward_norm: Vector3 = norm_candidate
	if not Geometry2D.is_point_in_polygon(test_pt, poly_2d):
		inward_norm = -norm_candidate

	var mid_ab: Vector3 = (p_a + p_b) * 0.5
	# Door sits flush with threshold at Y = 0.0 (door mesh height 2.4, center at Y = 1.2)
	# Offset inward into room so downward raycast clears the wall and hits floor at Y = 0.0
	var door_offset: float = wall_thickness * 0.5 + 0.3
	var door_pos: Vector3 = Vector3(mid_ab.x, 1.2, mid_ab.z) + inward_norm * door_offset
	var door_basis := Basis(dir_ab, Vector3.UP, inward_norm)

	return Transform3D(door_basis, door_pos)

static func create_door_indicator_mesh() -> ImmediateMesh:
	var imm_mesh := ImmediateMesh.new()
	imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	imm_mesh.surface_add_vertex(Vector3(0.0, -1.18, 0.0))
	imm_mesh.surface_add_vertex(Vector3(0.0, -1.18, 1.5))

	imm_mesh.surface_add_vertex(Vector3(-0.25, -1.18, 1.2))
	imm_mesh.surface_add_vertex(Vector3(0.0, -1.18, 1.5))

	imm_mesh.surface_add_vertex(Vector3(0.25, -1.18, 1.2))
	imm_mesh.surface_add_vertex(Vector3(0.0, -1.18, 1.5))

	imm_mesh.surface_add_vertex(Vector3(-0.4, -1.18, 0.0))
	imm_mesh.surface_add_vertex(Vector3(0.4, -1.18, 0.0))

	imm_mesh.surface_end()
	return imm_mesh

