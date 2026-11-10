extends Node3D

signal status_message_requested(msg: String)
signal chest_opened(chest: Node3D)
signal chest_closed
signal player_inventory_updated

var player: CharacterBody3D = null
var cameras: Array[Camera3D] = []
var nav_region: NavigationRegion3D = null
var active_chest: Node3D = null
var _player_was_auto_spawned: bool = false

func _ready() -> void:
	if get_parent() == get_tree().root:
		var target_path: String = scene_file_path
		if target_path.is_empty() and get_tree().current_scene != null:
			target_path = get_tree().current_scene.scene_file_path
		
		if not target_path.is_empty():
			GameManager.temp_start_room_path = target_path
			get_tree().change_scene_to_file("res://ui/main.tscn")
			return

	var legacy_ui: Node = get_node_or_null("UI")
	if legacy_ui != null:
		legacy_ui.queue_free()

	nav_region = get_node_or_null("NavigationRegion3D") as NavigationRegion3D

	_ensure_player()
	_collect_room_cameras()
	_setup_chests()
	_setup_doors()

	await get_tree().physics_frame
	await get_tree().physics_frame
	if nav_region != null and nav_region.navigation_mesh != null:
		nav_region.bake_navigation_mesh()
	_position_player_at_door()

func _ensure_player() -> void:
	player = get_node_or_null("Player") as CharacterBody3D
	if player == null:
		var player_scene: PackedScene = load("res://entities/player/player.tscn") as PackedScene
		if player_scene != null:
			player = player_scene.instantiate() as CharacterBody3D
			player.name = "Player"
			add_child(player)
			_player_was_auto_spawned = true

	if player != null:
		if not player.inventory_updated.is_connected(_on_player_inventory_updated):
			player.inventory_updated.connect(_on_player_inventory_updated)

func _on_player_inventory_updated() -> void:
	player_inventory_updated.emit()

func _collect_room_cameras() -> void:
	cameras.clear()

	var cam_container: Node = get_node_or_null("Cameras")
	if cam_container != null:
		for child: Node in cam_container.get_children():
			if child is Camera3D and not cameras.has(child as Camera3D):
				cameras.append(child as Camera3D)

	var found_cameras: Array[Node] = find_children("*", "Camera3D", true, false)
	for cam_node: Node in found_cameras:
		if cam_node is Camera3D:
			var is_excluded: bool = false
			var p: Node = cam_node.get_parent()
			while p != null and p != self:
				if p is SubViewport or (player != null and p == player):
					is_excluded = true
					break
				p = p.get_parent()

			if not is_excluded and not cameras.has(cam_node as Camera3D):
				cameras.append(cam_node as Camera3D)

	if cameras.is_empty():
		var fallback_cam := Camera3D.new()
		fallback_cam.name = "_FallbackCamera"
		fallback_cam.position = Vector3(0.0, 12.0, 12.0)
		add_child(fallback_cam)
		fallback_cam.look_at(Vector3.ZERO, Vector3.UP)
		fallback_cam.make_current()
		cameras.append(fallback_cam)
	else:
		select_camera(0)

func get_room_cameras() -> Array[Camera3D]:
	return cameras

func select_camera(index: int) -> void:
	if index < 0 or index >= cameras.size() or cameras[index] == null:
		return
	cameras[index].make_current()

func _setup_chests() -> void:
	var chests: Array[Node] = []
	var direct_chest_nav: Node = get_node_or_null("NavigationRegion3D/Chest")
	if direct_chest_nav != null:
		chests.append(direct_chest_nav)
	var direct_chest_props: Node = get_node_or_null("Props/Chest")
	if direct_chest_props != null and not chests.has(direct_chest_props):
		chests.append(direct_chest_props)

	var found_bodies: Array[Node] = find_children("*", "StaticBody3D", true, false)
	for b: Node in found_bodies:
		if b.has_signal("chest_opened") and not chests.has(b):
			chests.append(b)

	for chest: Node in chests:
		if chest.has_signal("chest_opened"):
			if not chest.is_connected("chest_opened", _on_chest_opened):
				chest.connect("chest_opened", _on_chest_opened.bind(chest as Node3D))
		if chest.has_signal("chest_locked_attempt"):
			chest.connect("chest_locked_attempt", func(needed: Variant) -> void:
				show_status_message("Сундук заперт. Требуется: " + str(needed))
			)
		if chest.has_signal("chest_unlocked"):
			chest.connect("chest_unlocked", func(key_name: String) -> void:
				show_status_message("Сундук открыт с помощью: " + key_name)
			)

func _setup_doors() -> void:
	var doors: Array[Node] = _find_all_doors(self)
	for door: Node in doors:
		if door.has_signal("door_locked"):
			door.connect("door_locked", func(needed: String) -> void:
				show_status_message("Шлюз заблокирован. Требуется: " + needed)
			)
		if door.has_signal("door_opened"):
			door.connect("door_opened", func() -> void:
				show_status_message("Шлюз открыт. Переход в сектор...")
			)

func _find_all_doors(parent: Node) -> Array[Node]:
	var doors: Array[Node] = []
	for child: Node in parent.get_children():
		if "door_id" in child:
			doors.append(child)
		doors.append_array(_find_all_doors(child))
	return doors

func _on_chest_opened(_items: Array[String], chest_node: Node3D) -> void:
	active_chest = chest_node
	chest_opened.emit(chest_node)

func close_chest() -> void:
	if active_chest != null:
		active_chest = null
		chest_closed.emit()

func show_status_message(msg: String) -> void:
	status_message_requested.emit(msg)
	if GameManager.main_ui != null and GameManager.main_ui.has_method("show_status_message"):
		GameManager.main_ui.call("show_status_message", msg)

func _unhandled_input(event: InputEvent) -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var active_cam: Camera3D = viewport.get_camera_3d()
	if active_cam == null:
		return

	if event is InputEventMouseMotion:
		var mouse_pos: Vector2 = event.position
		var ray_from: Vector3 = active_cam.project_ray_origin(mouse_pos)
		var ray_dir: Vector3 = active_cam.project_ray_normal(mouse_pos)
		var ray_to: Vector3 = ray_from + ray_dir * 1000.0

		var world_3d: World3D = get_world_3d()
		if world_3d == null:
			return
		var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
		query.collide_with_areas = true
		var hit: Dictionary = space_state.intersect_ray(query)

		var is_hovering_interactive: bool = false
		if not hit.is_empty():
			var collider: Object = hit.get("collider", null)
			if collider is Area3D and collider.has_method("collect"):
				is_hovering_interactive = true
			elif collider is Node and (collider as Node).name == "InteractArea":
				is_hovering_interactive = true

		if is_hovering_interactive:
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		else:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_pos: Vector2 = event.position
		var ray_from: Vector3 = active_cam.project_ray_origin(mouse_pos)
		var ray_dir: Vector3 = active_cam.project_ray_normal(mouse_pos)
		var ray_to: Vector3 = ray_from + ray_dir * 1000.0

		var world_3d: World3D = get_world_3d()
		if world_3d == null:
			return
		var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
		query.collide_with_areas = true
		var result: Dictionary = space_state.intersect_ray(query)

		if not result.is_empty():
			var collider: Object = result.get("collider", null)
			if collider is Area3D and collider.has_method("collect"):
				if player != null:
					player.interact_with_item(collider as Node3D)
			elif collider is Node and (collider as Node).name == "InteractArea" and (collider as Node).get_parent() != null and (collider as Node).get_parent().has_method("interact"):
				if player != null:
					player.interact_with_item((collider as Node).get_parent() as Node3D)
			else:
				close_chest()
				if player != null:
					var hit_pos: Vector3 = result.get("position", Vector3.ZERO) as Vector3
					player.move_to(hit_pos)

func _position_player_at_door() -> void:
	if not GameManager.is_door_transition:
		return

	var doors: Array[Node] = _find_all_doors(self)
	if doors.is_empty():
		GameManager.is_door_transition = false
		GameManager.target_door_id = ""
		return

	var target_door: Node = null
	if GameManager.target_door_id != "":
		for door: Node in doors:
			if String(door.get("door_id")) == GameManager.target_door_id:
				target_door = door
				break

	if target_door == null:
		target_door = doors[0]

	var spawn_pos: Vector3 = (target_door as Node3D).global_position if target_door is Node3D else Vector3.ZERO
	if target_door.has_method("get_spawn_position"):
		spawn_pos = target_door.call("get_spawn_position")
	else:
		var spawn_node: Node = target_door.get_node_or_null("SpawnPoint")
		if spawn_node is Marker3D:
			spawn_pos = (spawn_node as Marker3D).global_position
		elif spawn_node is Node3D:
			spawn_pos = (spawn_node as Node3D).global_position

	if player != null:
		player.global_position = Vector3(spawn_pos.x, 1.0, spawn_pos.z)
		player.velocity = Vector3.ZERO
		var nav_agent: Variant = player.get("nav_agent")
		if nav_agent != null and nav_agent is NavigationAgent3D:
			(nav_agent as NavigationAgent3D).target_position = player.global_position

	GameManager.is_door_transition = false
	GameManager.target_door_id = ""
