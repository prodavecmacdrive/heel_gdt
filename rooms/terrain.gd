class_name TerrainGenerator
extends StaticBody3D
## Процедурный генератор рельефа поверхности и физической коллизии `HeightMapShape3D` на базе шума Перлина/Симплекса.

@export_category("Terrain Generator")

@export_group("Noise & Relief")
## Частота шума `FastNoiseLite`: меньшие значения дают плавные холмы, большие — частый и резкий рельеф.
@export_range(0.005, 0.5, 0.005) var noise_frequency: float = 0.05

## Амплитуда (максимальный перепад высот в метрах) генерируемого рельефа по оси Y.
@export_range(0.0, 20.0, 0.1) var height_scale: float = 3.0

## Количество точек сетки высот по ширине и глубине для `HeightMapShape3D` (по умолчанию `33` для сетки 32×32 м).
@export_range(2, 129, 1) var grid_resolution: int = 33


func _ready() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = noise_frequency

	var col_node: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_node != null and col_node.shape is HeightMapShape3D:
		var col_shape: HeightMapShape3D = col_node.shape as HeightMapShape3D
		var heights: PackedFloat32Array = PackedFloat32Array()
		for z: int in range(grid_resolution):
			for x: int in range(grid_resolution):
				var h: float = noise.get_noise_2d(float(x), float(z)) * height_scale
				heights.append(h)
		col_shape.map_data = heights

	var mesh_node: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_node == null or mesh_node.mesh == null:
		return

	var plane_mesh: Mesh = mesh_node.mesh
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane_mesh.get_mesh_arrays())

	var half_span: float = float(grid_resolution - 1) * 0.5
	var mdt := MeshDataTool.new()
	mdt.create_from_surface(arr_mesh, 0)
	for i: int in range(mdt.get_vertex_count()):
		var v: Vector3 = mdt.get_vertex(i)
		v.y = noise.get_noise_2d(v.x + half_span, v.z + half_span) * height_scale
		mdt.set_vertex(i, v)

	arr_mesh.clear_surfaces()
	mdt.commit_to_surface(arr_mesh)
	mesh_node.mesh = arr_mesh
