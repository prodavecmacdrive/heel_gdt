@tool
class_name InteractablePhysicsBuilder
extends RefCounted
## Генератор коллизий взаимодействия, твёрдых препятствий и интеграции с [NavigationRegion3D].
##
## Выделен из [QuestInteractable], чтобы полностью изолировать физическую инженерию
## и работу с деревом сцены редактора от квестовой логики.

const INTERNAL_OBSTACLE_NAME: String = "_ObstacleStaticBody3D"
const MIN_SHAPE_SIZE: Vector3 = Vector3(0.5, 0.5, 0.5)


## Находит дочерний [CollisionShape3D], принадлежащий непосредственно [param host].
static func find_interaction_collision_shape(host: Node) -> CollisionShape3D:
	if host == null:
		return null
	for child: Node in host.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


## Гарантирует наличие валидного [CollisionShape3D] у [param host], устраняя жёлтый
## треугольник предупреждения в редакторе Godot.
static func ensure_interaction_collision(
	host: Area3D,
	visual_bounds: Dictionary,
	visual_mode: int,
	allow_update_if_internal: bool = false
) -> void:
	if host == null or not host.is_inside_tree():
		return

	var col_shape: CollisionShape3D = find_interaction_collision_shape(host)
	if col_shape == null or col_shape.shape == null:
		generate_box_collision(host, visual_bounds)
		return

	var scene_root: Node = SceneTreeUtils.resolve_scene_root(host)
	if scene_root != null and col_shape.owner == null:
		col_shape.owner = scene_root

	if allow_update_if_internal and visual_mode != 0:
		var target_size: Vector3 = _clamp_min_size(visual_bounds.get("size", MIN_SHAPE_SIZE) as Vector3)
		var target_pos: Vector3 = visual_bounds.get("center", Vector3.ZERO) as Vector3
		if col_shape.shape is BoxShape3D:
			(col_shape.shape as BoxShape3D).size = target_size
		col_shape.position = target_pos

	host.update_configuration_warnings()


## Создаёт или обновляет дочерний [CollisionShape3D] с [BoxShape3D] по габаритам [param visual_bounds].
static func generate_box_collision(host: Area3D, visual_bounds: Dictionary) -> void:
	if host == null:
		return

	var col_shape: CollisionShape3D = find_interaction_collision_shape(host)
	if col_shape == null:
		col_shape = CollisionShape3D.new()
		col_shape.name = "CollisionShape3D"
		host.add_child(col_shape)

	var box_shape: BoxShape3D = null
	if col_shape.shape is BoxShape3D:
		box_shape = col_shape.shape as BoxShape3D
	else:
		box_shape = BoxShape3D.new()
		col_shape.shape = box_shape

	var target_size: Vector3 = _clamp_min_size(visual_bounds.get("size", MIN_SHAPE_SIZE) as Vector3)
	var target_pos: Vector3 = visual_bounds.get("center", Vector3.ZERO) as Vector3

	box_shape.size = target_size
	col_shape.position = target_pos

	var scene_root: Node = SceneTreeUtils.resolve_scene_root(host)
	if scene_root != null and col_shape.owner == null:
		col_shape.owner = scene_root

	host.update_configuration_warnings()
	host.notify_property_list_changed()


## Создаёт, обновляет или удаляет внутренний [StaticBody3D]-коллайдер препятствия.
static func refresh_obstacle(
	host: Node3D,
	is_solid_obstacle: bool,
	auto_size_obstacle: bool,
	obstacle_size: Vector3,
	visual_mode: int,
	sprite_anchor: int,
	visual_bounds: Dictionary
) -> void:
	if host == null or not host.is_inside_tree():
		return

	var obstacle_body: StaticBody3D = host.get_node_or_null(INTERNAL_OBSTACLE_NAME) as StaticBody3D
	if not is_solid_obstacle:
		if obstacle_body != null:
			obstacle_body.collision_layer = 0
			obstacle_body.collision_mask = 0
			obstacle_body.queue_free()
		return

	var is_new_body: bool = false
	if obstacle_body == null:
		obstacle_body = StaticBody3D.new()
		obstacle_body.name = INTERNAL_OBSTACLE_NAME
		host.add_child(obstacle_body)
		is_new_body = true

	obstacle_body.collision_layer = 1
	obstacle_body.collision_mask = 0

	var col_shape: CollisionShape3D = obstacle_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var is_new_shape: bool = false
	if col_shape == null:
		col_shape = CollisionShape3D.new()
		col_shape.name = "CollisionShape3D"
		obstacle_body.add_child(col_shape)
		is_new_shape = true

	var box_shape: BoxShape3D = null
	if col_shape.shape is BoxShape3D:
		box_shape = col_shape.shape as BoxShape3D
	else:
		box_shape = BoxShape3D.new()
		col_shape.shape = box_shape

	if auto_size_obstacle:
		var b_size: Vector3 = _clamp_min_size(visual_bounds.get("size", MIN_SHAPE_SIZE) as Vector3)
		var b_center: Vector3 = visual_bounds.get("center", Vector3.ZERO) as Vector3
		box_shape.size = b_size
		col_shape.position = b_center
	else:
		var sz: Vector3 = _clamp_min_size(obstacle_size)
		box_shape.size = sz
		if visual_mode == 1:
			if sprite_anchor == 0:
				col_shape.position = Vector3(0.0, sz.y * 0.5, 0.0)
			elif sprite_anchor == 1:
				col_shape.position = Vector3(0.0, -sz.y * 0.5, 0.0)
			else:
				col_shape.position = Vector3.ZERO
		else:
			col_shape.position = Vector3.ZERO

	var scene_root: Node = SceneTreeUtils.resolve_scene_root(host)
	if scene_root != null:
		if is_new_body and obstacle_body.owner == null:
			obstacle_body.owner = scene_root
		if is_new_shape and col_shape.owner == null:
			col_shape.owner = scene_root


## Выполняет 1-клик перемещение [param host] в [NavigationRegion3D] (или обратно)
## с сохранением глобальной трансформации, владельцев узлов и автоматическим перезапеканием NavMesh.
static func handle_obstacle_toggle(
	host: Node3D,
	enabled: bool,
	auto_size_obstacle: bool,
	obstacle_size: Vector3,
	visual_mode: int,
	sprite_anchor: int,
	visual_bounds: Dictionary
) -> void:
	if host == null or not host.is_inside_tree():
		return

	var nav_region: NavigationRegion3D = NavigationUtils.find_region(host)
	var scene_root: Node = SceneTreeUtils.resolve_scene_root(host)

	if enabled:
		if nav_region != null and host.get_parent() != nav_region:
			if not host.is_node_ready() or not Engine.is_editor_hint():
				host.call_deferred("reparent", nav_region, true)
			else:
				var old_gt: Transform3D = host.global_transform
				host.reparent(nav_region)
				host.global_transform = old_gt
				if scene_root != null:
					_update_owner_recursive(host, scene_root)

		refresh_obstacle(
			host,
			true,
			auto_size_obstacle,
			obstacle_size,
			visual_mode,
			sprite_anchor,
			visual_bounds
		)

		NavigationUtils.request_bake(nav_region, true)
	else:
		refresh_obstacle(
			host,
			false,
			auto_size_obstacle,
			obstacle_size,
			visual_mode,
			sprite_anchor,
			visual_bounds
		)

		if nav_region != null and host.get_parent() == nav_region and nav_region.get_parent() != null:
			if not host.is_node_ready() or not Engine.is_editor_hint():
				host.call_deferred("reparent", nav_region.get_parent(), true)
			else:
				var old_gt: Transform3D = host.global_transform
				host.reparent(nav_region.get_parent())
				host.global_transform = old_gt
				if scene_root != null:
					_update_owner_recursive(host, scene_root)

		NavigationUtils.request_bake(nav_region, false)


## Рекурсивно обновляет `owner` для [param node] и всех его дочерних узлов после `reparent()`.
static func _update_owner_recursive(node: Node, scene_root: Node) -> void:
	if node == null or scene_root == null:
		return
	if node != scene_root:
		node.owner = scene_root
	for child: Node in node.get_children():
		_update_owner_recursive(child, scene_root)


## Проверяет наличие валидной формы столкновения для предупреждений конфигурации в редакторе.
static func get_configuration_warnings(host: Area3D) -> PackedStringArray:
	var warnings: PackedStringArray = PackedStringArray()
	if host == null:
		return warnings
	var has_shape: bool = false
	for child: Node in host.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			has_shape = true
			break
		elif child is CollisionPolygon3D:
			has_shape = true
			break
	if not has_shape:
		warnings.append("QuestInteractable требует дочерний CollisionShape3D с заданной формой для обработки кликов и входа игрока.")
	return warnings


static func _clamp_min_size(sz: Vector3) -> Vector3:
	return Vector3(
		maxf(MIN_SHAPE_SIZE.x, sz.x),
		maxf(MIN_SHAPE_SIZE.y, sz.y),
		maxf(MIN_SHAPE_SIZE.z, sz.z)
	)

