@tool
class_name RoomMeshGenerator
extends RefCounted
## Статический генератор процедурной 3D-геометрии комнат (пол, потолок, сегменты стен, маркеры дверей).
##
## Используется плагином [RoomBuilder] для построения как произвольных контурных помещений (`Path3D`),
## так и прямоугольных коробок (`BoxMesh`).


## Строит `ArrayMesh` пола по замкнутому 2D-полигону `poly_2d` с нормалями, направленными вверх (`Vector3.UP`).
static func build_contour_floor_mesh(poly_2d: PackedVector2Array, color: Color) -> ArrayMesh:
	return _build_horizontal_polygon_mesh(poly_2d, 0.0, Vector3.UP, color, 0.7)


## Строит `ArrayMesh` потолка по 2D-полигону `poly_2d` на высоте `wall_height` с нормалями вниз (`Vector3.DOWN`).
static func build_contour_ceiling_mesh(poly_2d: PackedVector2Array, wall_height: float, color: Color) -> ArrayMesh:
	return _build_horizontal_polygon_mesh(poly_2d, wall_height, Vector3.DOWN, color, 0.85)


## Строит `BoxMesh` прямоугольного пола заданной ширины `width` и глубины `depth`.
static func build_box_floor_mesh(width: float, depth: float, color: Color) -> BoxMesh:
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(width, 0.4, depth)
	box_mesh.material = create_surface_material(color, 0.7)
	return box_mesh


## Строит `ArrayMesh` прямоугольного потолка на высоте `wall_height` с нормалями вниз (`Vector3.DOWN`).
static func build_box_ceiling_mesh(width: float, depth: float, wall_height: float, color: Color) -> ArrayMesh:
	var half_w: float = width * 0.5
	var half_d: float = depth * 0.5
	var rect_poly: PackedVector2Array = PackedVector2Array([
		Vector2(-half_w, -half_d),
		Vector2(half_w, -half_d),
		Vector2(half_w, half_d),
		Vector2(-half_w, half_d),
	])
	return _build_horizontal_polygon_mesh(rect_poly, wall_height, Vector3.DOWN, color, 0.85)


## Создаёт стандартный матовый материал для поверхностей комнаты.
static func create_surface_material(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	return mat


## Вычисляет массив сегментов стен (`{"transform": Transform3D, "length": float}`) вдоль контура `poly_2d`.
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

		segments.append({
			"transform": Transform3D(seg_basis, seg_pos),
			"length": seg_len,
		})
	return segments


## Вычисляет трансформацию двери на самом длинном сегменте контура `poly_2d` (лицом внутрь помещения).
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
	var door_offset: float = wall_thickness * 0.5 + 0.3
	var door_pos: Vector3 = Vector3(mid_ab.x, 1.2, mid_ab.z) + inward_norm * door_offset
	var door_basis := Basis(dir_ab, Vector3.UP, inward_norm)

	return Transform3D(door_basis, door_pos)


## Строит векторную стрелку `ImmediateMesh`, указывающую направление входа/выхода перед дверью.
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


static func _build_horizontal_polygon_mesh(
	poly_2d: PackedVector2Array,
	y_level: float,
	target_normal: Vector3,
	color: Color,
	roughness: float
) -> ArrayMesh:
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(poly_2d)
	if triangles.is_empty():
		push_warning("[RoomMeshGenerator] Failed to triangulate polygon.")
		return null

	var want_up: bool = target_normal.y >= 0.0
	var mesh: ArrayMesh = _commit_triangulated_surface(poly_2d, triangles, y_level, target_normal, want_up)

	# Проверка ориентации нормали после generate_normals() и переворот при необходимости
	var arrays: Array = mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if not normals.is_empty():
		var is_wrong_way: bool = (want_up and normals[0].y < 0.0) or (not want_up and normals[0].y > 0.0)
		if is_wrong_way:
			mesh = _commit_triangulated_surface(poly_2d, triangles, y_level, target_normal, not want_up)

	mesh.surface_set_material(0, create_surface_material(color, roughness))
	return mesh


static func _commit_triangulated_surface(
	poly_2d: PackedVector2Array,
	triangles: PackedInt32Array,
	y_level: float,
	target_normal: Vector3,
	clockwise_from_top: bool
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i: int in range(0, triangles.size(), 3):
		var i0: int = triangles[i]
		var i1: int = triangles[i + 1]
		var i2: int = triangles[i + 2]

		var v0 := Vector3(poly_2d[i0].x, y_level, poly_2d[i0].y)
		var v1 := Vector3(poly_2d[i1].x, y_level, poly_2d[i1].y)
		var v2 := Vector3(poly_2d[i2].x, y_level, poly_2d[i2].y)

		var face_norm: Vector3 = (v1 - v0).cross(v2 - v0)
		var tri_indices: Array[int] = [i0, i1, i2]
		if (clockwise_from_top and face_norm.y > 0.0) or (not clockwise_from_top and face_norm.y < 0.0):
			tri_indices = [i0, i2, i1]

		for idx: int in tri_indices:
			var pt: Vector2 = poly_2d[idx]
			var v := Vector3(pt.x, y_level, pt.y)
			st.set_normal(target_normal)
			st.set_uv(Vector2(v.x, v.z) * 0.25)
			st.add_vertex(v)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()
