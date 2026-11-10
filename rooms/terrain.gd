extends StaticBody3D

func _ready() -> void:
	var noise = FastNoiseLite.new()
	noise.frequency = 0.05
	
	var col_shape = $CollisionShape3D.shape as HeightMapShape3D
	var heights: PackedFloat32Array = []
	
	# Заповнюємо висоти для фізичної колізії (33x33 точки)
	for z in range(33):
		for x in range(33):
			var h = noise.get_noise_2d(x, z) * 3.0
			heights.append(h)
	col_shape.map_data = heights
	
	# Конвертуємо PlaneMesh у повноцінний ArrayMesh
	var plane_mesh = $MeshInstance3D.mesh
	var arr_mesh = ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane_mesh.get_mesh_arrays())
	
	# Модифікуємо координати вершин
	var mdt = MeshDataTool.new()
	mdt.create_from_surface(arr_mesh, 0)
	for i in range(mdt.get_vertex_count()):
		var v = mdt.get_vertex(i)
		v.y = noise.get_noise_2d(v.x + 16.0, v.z + 16.0) * 3.0
		mdt.set_vertex(i, v)
	
	arr_mesh.clear_surfaces()
	mdt.commit_to_surface(arr_mesh)
	$MeshInstance3D.mesh = arr_mesh
