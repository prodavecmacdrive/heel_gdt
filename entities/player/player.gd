extends CharacterBody3D
signal inventory_updated

@export var speed: float = 5.0
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var target_item: Node3D = null

func _ready() -> void:
	# Ждем кадр, чтобы ландшафт успел сгенерировать холмы
	await get_tree().physics_frame
	_snap_to_ground()

func _snap_to_ground() -> void:
	var space_state = get_world_3d().direct_space_state
	var from_pos = Vector3(global_position.x, 20.0, global_position.z)
	var to_pos = Vector3(global_position.x, -20.0, global_position.z)
	var query = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = [get_rid()] # Игнорируем собственное тело персонажа

	var hit = space_state.intersect_ray(query)
	if hit:
		# Высота капсулы 2 м, центр на 1 м выше пола
		global_position.y = hit.position.y + 1.0

func _physics_process(delta: float) -> void:
	if global_position.y < -5.0:
		global_position.y = 1.0
		velocity = Vector3.ZERO

	if not is_on_floor():
		velocity.y -= 9.8 * delta

	if not nav_agent.is_navigation_finished():
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		var dir: Vector3 = (next_pos - global_position)
		dir.y = 0 # Движемся строго в горизонтальной плоскости
		
		# Если до следующей путевой точки осталось меньше 0.4 м, переключаемся дальше
		if dir.length() > 0.1:
			velocity.x = dir.normalized().x * speed
			velocity.z = dir.normalized().z * speed
	else:
		velocity.x = 0
		velocity.z = 0
		if target_item != null:
			var dist = global_position.distance_to(target_item.global_position)
			if dist < 2.5:
				if target_item.has_method("collect"):
					var item_title = target_item.item_name
					GameManager.player_inventory.append(item_title)
					target_item.collect()
					inventory_updated.emit()
					var room_node = get_parent()
					if room_node.has_method("show_status_message"):
						room_node.show_status_message("Получен предмет: " + item_title)
				elif target_item.has_method("interact"):
					target_item.interact(self)
				target_item = null

	move_and_slide()

	if global_position.y < -5.0:
		global_position.y = 1.0
		velocity = Vector3.ZERO

func move_to(target_pos: Vector3) -> void:
	target_item = null
	nav_agent.target_position = target_pos

func interact_with_item(item: Node3D) -> void:
	target_item = item
	nav_agent.target_position = item.global_position
