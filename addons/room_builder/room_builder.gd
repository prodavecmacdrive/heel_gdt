@tool
class_name RoomBuilder
extends Node3D
## Инструмент редактора для процедурной генерации 3D-геометрии комнаты (пола, стен, потолка, навигации и шлюза).
##
## Поддерживает два режима построения:
## [br]• по замкнутому криволинейному/многоугольному контуру `Path3D` (`contour_path`);
## [br]• по прямоугольным габаритам (`room_width` × `room_depth`), если контур не используется.

const ROOM_BASE_SCRIPT_PATH: String = "res://core/room_base.gd"
const DOOR_SCENE: PackedScene = preload("res://entities/door/door.tscn")
const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")

@export_category("Room Builder")

@export_group("Contour Mode")
## Путь к узлу `Path3D`, задающему 2D-контур пола и стен комнаты в плоскости XZ.
## Если оставить пустым, генератор автоматически найдёт узел `"Contour"` в корне сцены.
@export_node_path("Path3D") var contour_path: NodePath = NodePath("")

## Шаг дискретизации кривой `Curve3D` в метрах при запекании точек контура (меньше — плавнее изгибы, больше — меньше полигонов).
@export_range(0.1, 10.0, 0.1) var bake_interval: float = 1.0

@export_group("Room Dimensions")
## Ширина комнаты по оси X в метрах (используется для прямоугольного режима, если контур `Path3D` содержит менее 3 точек).
@export_range(4.0, 100.0, 0.5) var room_width: float = 16.0

## Глубина комнаты по оси Z в метрах (используется для прямоугольного режима).
@export_range(4.0, 100.0, 0.5) var room_depth: float = 16.0

## Высота стен и уровень потолка комнаты по оси Y в метрах.
@export_range(2.0, 20.0, 0.25) var wall_height: float = 4.0

## Толщина генерируемых стен и их физических коллайдеров в метрах.
@export_range(0.1, 2.0, 0.05) var wall_thickness: float = 0.4

## Если включено, над комнатой создаётся односторонний потолок (прозрачный при взгляде камеры сверху снаружи).
@export var generate_ceiling: bool = true

@export_group("Surface Colors")
## Базовый цвет (`albedo_color`) материала пола.
@export var floor_color: Color = Color(0.4, 0.42, 0.45)

## Базовый цвет (`albedo_color`) материала стен и потолка.
@export var wall_color: Color = Color(0.32, 0.35, 0.38)

@export_group("Doorway Setup")
## Если включено, при генерации комнаты автоматически создаётся экземпляр шлюза `Door` (`res://entities/door/door.tscn`).
@export var spawn_default_door: bool = true

## Стена, у которой размещается шлюз в прямоугольном режиме построения:
## [br]• `North (-Z)` (0) — северная стена;
## [br]• `South (+Z)` (1) — южная стена;
## [br]• `East (+X)` (2) — восточная стена;
## [br]• `West (-X)` (3) — западная стена.
@export_enum("North (-Z)", "South (+Z)", "East (+X)", "West (-X)") var door_wall: int = 0

## Идентификатор `door_id`, назначаемый автоматически создаваемому шлюзу.
@export var default_door_id: String = "door_main"

@export_group("Testing & Setup")
## Если включено, при отсутствии узла `Player` в сцене автоматически создаёт тестового игрока перед точкой спавна двери.
@export var spawn_test_player: bool = true

@export_group("Room Builder Actions")
## Кнопка редактора: создаёт стандартный квадратный контур `Contour` (`Path3D` 10×10 м) в корне сцены.
@export_tool_button("Create Default Contour") var create_contour_btn: Callable = create_default_contour

## Кнопка редактора: перестраивает пол, стены, потолок, шлюз и запекает `NavigationRegion3D`.
@export_tool_button("Generate Room Shell") var generate_btn: Callable = generate_room_shell

## Кнопка редактора: удаляет сгенерированные узлы геометрии, навигации, двери и тестового игрока.
@export_tool_button("Clear Geometry") var clear_btn: Callable = clear_geometry

## Кнопка редактора: прикрепляет базовый скрипт контроллера комнаты (`res://core/room_base.gd`) к корневому узлу сцены.
@export_tool_button("Apply room_base.gd to Root") var apply_base_btn: Callable = apply_room_base_to_root


func _ready() -> void:
	if Engine.is_editor_hint():
		var contour_node: Path3D = _resolve_contour_node()
		if contour_node == null:
			create_default_contour()


## Создаёт прямоугольный узел `Contour` (`Path3D`) в корне редактируемой сцены, если он ещё не существует.
func create_default_contour() -> Path3D:
	if not Engine.is_editor_hint():
		return null
	var scene_root: Node = _resolve_scene_root()
	if scene_root == null:
		push_warning("[RoomBuilder] Cannot create contour: edited_scene_root is null.")
		return null

	var existing: Path3D = _resolve_contour_node()
	if existing != null:
		print("[RoomBuilder] Contour already exists: ", existing.name)
		return existing

	var path := Path3D.new()
	path.name = "Contour"
	var curve := Curve3D.new()
	curve.add_point(Vector3(-5.0, 0.0, -5.0))
	curve.add_point(Vector3(5.0, 0.0, -5.0))
	curve.add_point(Vector3(5.0, 0.0, 5.0))
	curve.add_point(Vector3(-5.0, 0.0, 5.0))
	curve.add_point(Vector3(-5.0, 0.0, -5.0))
	path.curve = curve

	scene_root.add_child(path)
	path.owner = scene_root
	print("[RoomBuilder] Created default rectangular Contour Path3D under: ", scene_root.name)
	return path


## Полностью перестраивает оболочку комнаты (контейнеры, `NavigationRegion3D`, пол, стены, потолок, дверь и игрока).
func generate_room_shell() -> void:
	if not Engine.is_editor_hint():
		return

	clear_geometry()

	var scene_root: Node = _resolve_scene_root()
	if scene_root == null:
		push_warning("[RoomBuilder] Cannot generate room shell: edited_scene_root is null.")
		return

	if self != scene_root and scene_root.get_script() == null:
		var base_script: Script = load(ROOM_BASE_SCRIPT_PATH) as Script
		if base_script != null:
			scene_root.set_script(base_script)

	_get_or_create_container(scene_root, "Lighting")
	_get_or_create_container(scene_root, "Cameras")
	_get_or_create_container(scene_root, "Props")

	var nav_region := NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	scene_root.add_child(nav_region)
	nav_region.owner = scene_root

	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = 1
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_max_climb = 0.25
	nav_mesh.agent_max_slope = 45.0
	nav_region.navigation_mesh = nav_mesh

	var contour_node: Path3D = _resolve_contour_node()
	if contour_node == null:
		contour_node = create_default_contour()

	if contour_node != null and contour_node.curve != null and contour_node.curve.point_count >= 3:
		_build_from_contour(scene_root, nav_region, contour_node)
	else:
		_build_floor(scene_root, nav_region)
		_build_walls(scene_root, nav_region)
		_build_box_ceiling(scene_root)
		var spawned_door: Node3D = null
		if spawn_default_door:
			spawned_door = _build_door(scene_root)
		if spawn_test_player:
			_spawn_test_player_if_needed(scene_root, spawned_door)

	nav_region.bake_navigation_mesh(false)


## Очищает ранее сгенерированную геометрию комнаты из корня сцены.
func clear_geometry() -> void:
	if not Engine.is_editor_hint():
		return

	var scene_root: Node = _resolve_scene_root()
	if scene_root == null:
		return

	for node_name: String in ["NavigationRegion3D", "Door", "Floor", "Ceiling", "Walls", "Player", "ExitIndicator"]:
		_safe_free_child(scene_root, node_name)


## Назначает скрипт `res://core/room_base.gd` корневому узлу текущей редактируемой сцены.
func apply_room_base_to_root() -> void:
	if not Engine.is_editor_hint():
		return

	var scene_root: Node = _resolve_scene_root()
	if scene_root == null:
		push_warning("[RoomBuilder] Cannot apply script: edited_scene_root is null.")
		return

	var base_script: Script = load(ROOM_BASE_SCRIPT_PATH) as Script
	if base_script != null:
		scene_root.set_script(base_script)
		print("[RoomBuilder] Successfully applied 'res://core/room_base.gd' to scene root: ", scene_root.name)
	else:
		push_error("[RoomBuilder] Failed to load 'res://core/room_base.gd'.")


func _safe_free_child(parent: Node, child_name: String) -> void:
	var child: Node = parent.get_node_or_null(child_name)
	if child != null:
		parent.remove_child(child)
		child.free()


func _lock_node(node: Node) -> void:
	node.set_meta("_edit_lock_", true)
	node.set_meta("_edit_group_", true)


func _resolve_scene_root() -> Node:
	if not Engine.is_editor_hint():
		return null
	var root: Node = SceneTreeUtils.resolve_scene_root(self)
	return root if root != null else self


func _resolve_contour_node() -> Path3D:
	var scene_root: Node = _resolve_scene_root()
	if not contour_path.is_empty():
		var target: Node = get_node_or_null(contour_path)
		if target is Path3D:
			return target as Path3D
		if scene_root != null:
			target = scene_root.get_node_or_null(contour_path)
			if target is Path3D:
				return target as Path3D

	if scene_root != null:
		var fallback: Node = scene_root.get_node_or_null("Contour")
		if fallback is Path3D:
			return fallback as Path3D

	var local_fallback: Node = get_node_or_null("Contour")
	if local_fallback is Path3D:
		return local_fallback as Path3D

	return null


func _get_or_create_container(scene_root: Node, container_name: String) -> Node3D:
	var container: Node3D = scene_root.get_node_or_null(container_name) as Node3D
	if container == null:
		container = Node3D.new()
		container.name = container_name
		scene_root.add_child(container)
		container.owner = scene_root
	return container


func _build_from_contour(scene_root: Node, nav_region: Node, path_node: Path3D) -> void:
	var curve: Curve3D = path_node.curve
	curve.bake_interval = bake_interval
	var raw_points: PackedVector3Array = curve.get_baked_points()
	if raw_points.size() < 3:
		push_warning("[RoomBuilder] Path3D curve produced fewer than 3 baked points.")
		return

	var xform: Transform3D = Transform3D.IDENTITY
	if scene_root is Node3D:
		xform = (scene_root as Node3D).global_transform.affine_inverse() * path_node.global_transform
	else:
		xform = path_node.transform

	var points_3d: PackedVector3Array = PackedVector3Array()
	for pt: Vector3 in raw_points:
		points_3d.append(xform * pt)

	if points_3d.size() >= 2 and points_3d[0].is_equal_approx(points_3d[points_3d.size() - 1]):
		points_3d.remove_at(points_3d.size() - 1)

	if points_3d.size() < 3:
		push_warning("[RoomBuilder] Contour points after deduplication are less than 3.")
		return

	var poly_2d: PackedVector2Array = PackedVector2Array()
	for pt: Vector3 in points_3d:
		poly_2d.append(Vector2(pt.x, pt.z))

	if Geometry2D.is_polygon_clockwise(poly_2d):
		poly_2d.reverse()

	var floor_mesh: ArrayMesh = RoomMeshGenerator.build_contour_floor_mesh(poly_2d, floor_color)
	if floor_mesh != null:
		var floor_body := StaticBody3D.new()
		floor_body.name = "Floor"
		floor_body.collision_layer = 1
		floor_body.collision_mask = 1
		_lock_node(floor_body)
		nav_region.add_child(floor_body)
		floor_body.owner = scene_root

		var concave_shape := ConcavePolygonShape3D.new()
		concave_shape.set_faces(floor_mesh.get_faces())

		var floor_col := CollisionShape3D.new()
		floor_col.name = "CollisionShape3D"
		_lock_node(floor_col)
		floor_col.shape = concave_shape
		floor_body.add_child(floor_col)
		floor_col.owner = scene_root

		var floor_mesh_inst := MeshInstance3D.new()
		floor_mesh_inst.name = "MeshInstance3D"
		_lock_node(floor_mesh_inst)
		floor_mesh_inst.mesh = floor_mesh
		floor_body.add_child(floor_mesh_inst)
		floor_mesh_inst.owner = scene_root

	if generate_ceiling:
		var ceil_mesh: ArrayMesh = RoomMeshGenerator.build_contour_ceiling_mesh(poly_2d, wall_height, wall_color)
		if ceil_mesh != null:
			_add_ceiling_node(scene_root, ceil_mesh)

	var wall_segments: Array[Dictionary] = RoomMeshGenerator.calculate_wall_segments(poly_2d, wall_height)
	var walls_body := StaticBody3D.new()
	walls_body.name = "Walls"
	_lock_node(walls_body)
	nav_region.add_child(walls_body)
	walls_body.owner = scene_root

	var wall_mat: StandardMaterial3D = RoomMeshGenerator.create_surface_material(wall_color, 0.85)
	for i: int in range(wall_segments.size()):
		var seg: Dictionary = wall_segments[i]
		var seg_xform: Transform3D = seg["transform"] as Transform3D
		var seg_len: float = float(seg["length"])
		var seg_size := Vector3(wall_thickness, wall_height, seg_len)

		var wall_box_shape := BoxShape3D.new()
		wall_box_shape.size = seg_size

		var wall_col := CollisionShape3D.new()
		wall_col.name = "CollisionShape3D_%d" % i
		_lock_node(wall_col)
		wall_col.shape = wall_box_shape
		wall_col.transform = seg_xform
		walls_body.add_child(wall_col)
		wall_col.owner = scene_root

		var wall_box_mesh := BoxMesh.new()
		wall_box_mesh.size = seg_size
		wall_box_mesh.material = wall_mat

		var wall_mesh_inst := MeshInstance3D.new()
		wall_mesh_inst.name = "MeshInstance3D_%d" % i
		_lock_node(wall_mesh_inst)
		wall_mesh_inst.mesh = wall_box_mesh
		wall_mesh_inst.transform = seg_xform
		walls_body.add_child(wall_mesh_inst)
		wall_mesh_inst.owner = scene_root

	var spawned_door: Node3D = null
	if spawn_default_door and DOOR_SCENE != null and poly_2d.size() >= 2:
		var door_xform: Transform3D = RoomMeshGenerator.calculate_contour_door_transform(poly_2d, wall_thickness)
		if door_xform != Transform3D.IDENTITY:
			var door_instance: Node3D = DOOR_SCENE.instantiate() as Node3D
			door_instance.name = "Door"
			scene_root.add_child(door_instance)
			door_instance.owner = scene_root
			door_instance.transform = door_xform
			door_instance.set("door_id", default_door_id)
			_attach_door_indicator(door_instance, scene_root)
			spawned_door = door_instance

	if spawn_test_player:
		_spawn_test_player_if_needed(scene_root, spawned_door)


func _add_ceiling_node(scene_root: Node, ceil_mesh: ArrayMesh) -> void:
	var ceil_body := StaticBody3D.new()
	ceil_body.name = "Ceiling"
	ceil_body.collision_layer = 0
	ceil_body.collision_mask = 0
	_lock_node(ceil_body)
	scene_root.add_child(ceil_body)
	ceil_body.owner = scene_root

	var ceil_mesh_inst := MeshInstance3D.new()
	ceil_mesh_inst.name = "MeshInstance3D"
	_lock_node(ceil_mesh_inst)
	ceil_mesh_inst.mesh = ceil_mesh
	ceil_body.add_child(ceil_mesh_inst)
	ceil_mesh_inst.owner = scene_root


func _attach_door_indicator(door_instance: Node3D, scene_root: Node) -> void:
	var indicator := MeshInstance3D.new()
	indicator.name = "ExitIndicator"
	_lock_node(indicator)
	indicator.mesh = RoomMeshGenerator.create_door_indicator_mesh()

	var ind_mat := StandardMaterial3D.new()
	ind_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ind_mat.albedo_color = Color(0.1, 0.9, 0.3)
	ind_mat.no_depth_test = true
	indicator.material_override = ind_mat

	door_instance.add_child(indicator)
	indicator.owner = scene_root


func _spawn_test_player_if_needed(scene_root: Node, door_instance: Node3D) -> void:
	if not spawn_test_player or scene_root.get_node_or_null("Player") != null or PLAYER_SCENE == null:
		return

	var player_node: Node3D = PLAYER_SCENE.instantiate() as Node3D
	player_node.name = "Player"
	scene_root.add_child(player_node)
	player_node.owner = scene_root

	var spawn_pos := Vector3(0.0, 1.0, 0.0)
	if door_instance != null:
		var spawn_pt: Node = door_instance.get_node_or_null("SpawnPoint")
		if spawn_pt is Node3D:
			spawn_pos = (spawn_pt as Node3D).global_position
			spawn_pos.y = 1.0
		else:
			spawn_pos = Vector3(door_instance.global_position.x, 1.0, door_instance.global_position.z)

	player_node.global_position = spawn_pos


func _build_floor(scene_root: Node, parent: Node) -> StaticBody3D:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 1
	_lock_node(floor_body)
	floor_body.position = Vector3(0.0, -0.2, 0.0)
	parent.add_child(floor_body)
	floor_body.owner = scene_root

	var col_shape := CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	_lock_node(col_shape)
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(room_width, 0.4, room_depth)
	col_shape.shape = box_shape
	floor_body.add_child(col_shape)
	col_shape.owner = scene_root

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	_lock_node(mesh_inst)
	mesh_inst.mesh = RoomMeshGenerator.build_box_floor_mesh(room_width, room_depth, floor_color)
	floor_body.add_child(mesh_inst)
	mesh_inst.owner = scene_root

	return floor_body


func _build_walls(scene_root: Node, parent: Node) -> void:
	var half_w: float = room_width * 0.5
	var half_d: float = room_depth * 0.5
	var half_h: float = wall_height * 0.5
	var half_t: float = wall_thickness * 0.5

	_create_wall(scene_root, parent, "WallNorth", Vector3(0.0, half_h, -half_d - half_t), Vector3(room_width + wall_thickness * 2.0, wall_height, wall_thickness))
	_create_wall(scene_root, parent, "WallSouth", Vector3(0.0, half_h, half_d + half_t), Vector3(room_width + wall_thickness * 2.0, wall_height, wall_thickness))
	_create_wall(scene_root, parent, "WallEast", Vector3(half_w + half_t, half_h, 0.0), Vector3(wall_thickness, wall_height, room_depth))
	_create_wall(scene_root, parent, "WallWest", Vector3(-half_w - half_t, half_h, 0.0), Vector3(wall_thickness, wall_height, room_depth))


func _create_wall(scene_root: Node, parent: Node, wall_name: String, wall_pos: Vector3, wall_size: Vector3) -> StaticBody3D:
	var wall_body := StaticBody3D.new()
	wall_body.name = wall_name
	_lock_node(wall_body)
	wall_body.position = wall_pos
	parent.add_child(wall_body)
	wall_body.owner = scene_root

	var col_shape := CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	_lock_node(col_shape)
	var box_shape := BoxShape3D.new()
	box_shape.size = wall_size
	col_shape.shape = box_shape
	wall_body.add_child(col_shape)
	col_shape.owner = scene_root

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	_lock_node(mesh_inst)
	var box_mesh := BoxMesh.new()
	box_mesh.size = wall_size
	box_mesh.material = RoomMeshGenerator.create_surface_material(wall_color, 0.85)
	mesh_inst.mesh = box_mesh
	wall_body.add_child(mesh_inst)
	mesh_inst.owner = scene_root

	return wall_body


func _build_box_ceiling(scene_root: Node) -> void:
	if not generate_ceiling:
		return
	var ceil_mesh: ArrayMesh = RoomMeshGenerator.build_box_ceiling_mesh(room_width, room_depth, wall_height, wall_color)
	if ceil_mesh != null:
		_add_ceiling_node(scene_root, ceil_mesh)


func _build_door(scene_root: Node) -> Node3D:
	if DOOR_SCENE == null:
		return null
	var door_instance: Node3D = DOOR_SCENE.instantiate() as Node3D
	door_instance.name = "Door"
	scene_root.add_child(door_instance)
	door_instance.owner = scene_root
	door_instance.set("door_id", default_door_id)

	var half_w: float = room_width * 0.5
	var half_d: float = room_depth * 0.5
	var offset: float = wall_thickness * 0.5 + 0.3

	match door_wall:
		0:
			door_instance.position = Vector3(0.0, 1.2, -half_d + offset)
			door_instance.rotation_degrees = Vector3(0.0, 0.0, 0.0)
		1:
			door_instance.position = Vector3(0.0, 1.2, half_d - offset)
			door_instance.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		2:
			door_instance.position = Vector3(half_w - offset, 1.2, 0.0)
			door_instance.rotation_degrees = Vector3(0.0, -90.0, 0.0)
		3:
			door_instance.position = Vector3(-half_w + offset, 1.2, 0.0)
			door_instance.rotation_degrees = Vector3(0.0, 90.0, 0.0)

	_attach_door_indicator(door_instance, scene_root)
	return door_instance
