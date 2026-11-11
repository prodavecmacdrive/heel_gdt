class_name RoomBase
extends Node3D
## Базовый контроллер игровой комнаты (сектора бункера).
##
## Отвечает за:
## [br]• перенаправление прямого запуска сцены (F6) в оболочку главного терминала (`res://ui/main.tscn`);
## [br]• сбор камер наблюдения, дверей и контейнеров комнаты;
## [br]• позиционирование игрока у целевого шлюза при переходе между комнатами;
## [br]• обработку кликов и наведения мыши в 3D-окне через [RoomRaycaster].

signal status_message_requested(msg: String)
signal chest_opened(chest: Node3D)
signal chest_closed
signal player_inventory_updated

const MAIN_UI_SCENE_PATH: String = "res://ui/main.tscn"
const PLAYER_SCENE: PackedScene = preload("res://entities/player/player.tscn")

@export_category("Room Controller")

@export_group("Identity & State")
## Отображаемое название сектора/комнаты в верхней шапке главного терминала (например, `"БЛОК УПРАВЛЕНИЯ А-01"`).
## Если оставить пустым, заголовок автоматически формируется из имени файла сцены.
@export var sector_name: String = ""

@export_group("Navigation & Spawning")
## Если включено, при старте комнаты навигационная сетка `NavigationRegion3D` автоматически перезапекается
## после инициализации физики всех дочерних объектов.
@export var auto_bake_navigation: bool = true

## Если включено и узел `Player` отсутствует в сцене комнаты, экземпляр игрока создаётся автоматически.
@export var auto_spawn_player: bool = true

## Высота по оси Y (в метрах), на которую устанавливается центр капсулы игрока при переходе через шлюз.
@export var default_spawn_height: float = 1.0

## Свойство обратной совместимости со старым именем `room_name`.
var room_name: String:
	get:
		return sector_name
	set(val):
		sector_name = val

@export_group("Surveillance & Cameras")
## Список фиксированных камер наблюдения в комнате.
## Если массив пуст, контроллер комнаты автоматически находит все узлы [Camera3D] внутри сцены,
## исключая камеры игрока и внутренние viewport'ы, сортируя их по естественному порядку имён.
@export var cameras: Array[Camera3D] = []

var player: CharacterBody3D = null
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
			get_tree().change_scene_to_file.call_deferred(MAIN_UI_SCENE_PATH)
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
	if auto_bake_navigation and nav_region != null and nav_region.navigation_mesh != null:
		if nav_region.navigation_mesh.get_polygon_count() == 0:
			NavigationUtils.request_bake(nav_region, false)
	_position_player_at_door()


func _ensure_player() -> void:
	player = get_node_or_null("Player") as CharacterBody3D
	if player == null and auto_spawn_player and PLAYER_SCENE != null:
		player = PLAYER_SCENE.instantiate() as CharacterBody3D
		player.name = "Player"
		add_child(player)
		_player_was_auto_spawned = true

	if player != null and player.has_signal("inventory_updated"):
		if not player.is_connected("inventory_updated", _on_player_inventory_updated):
			player.connect("inventory_updated", _on_player_inventory_updated)


func _on_player_inventory_updated() -> void:
	player_inventory_updated.emit()


func _is_valid_room_camera(cam_node: Node) -> bool:
	if not (cam_node is Camera3D):
		return false
	if cam_node.name.begins_with("_Fallback") or cam_node.name.begins_with("_TerminalFallback"):
		return false
	var p: Node = cam_node.get_parent()
	while p != null and p != self:
		if p is SubViewport or (player != null and p == player) or p.name == "Player":
			return false
		p = p.get_parent()
	return true


func _collect_room_cameras() -> void:
	var room_cams: Array[Camera3D] = get_room_cameras()
	if room_cams.is_empty():
		var fallback_cam := Camera3D.new()
		fallback_cam.name = "_FallbackCamera"
		fallback_cam.position = Vector3(0.0, 12.0, 12.0)
		add_child(fallback_cam)
		fallback_cam.look_at(Vector3.ZERO, Vector3.UP)
		fallback_cam.make_current()
		cameras.append(fallback_cam)
	else:
		if cameras.is_empty():
			cameras = room_cams
		select_camera(0)


## Возвращает упорядоченный список камер наблюдения комнаты.
## Если массив `cameras` заполнен вручную, возвращает его валидные элементы.
## В противном случае выполняет глубокий поиск всех [Camera3D] в комнате (исключая игрока и SubViewport).
func get_room_cameras() -> Array[Camera3D]:
	var valid_custom_cams: Array[Camera3D] = []
	for cam: Camera3D in cameras:
		if is_instance_valid(cam) and not cam.is_queued_for_deletion():
			valid_custom_cams.append(cam)
	if not valid_custom_cams.is_empty():
		return valid_custom_cams

	var result: Array[Camera3D] = []
	var found_cameras: Array[Node] = find_children("*", "Camera3D", true, false)
	for cam_node: Node in found_cameras:
		if _is_valid_room_camera(cam_node) and not result.has(cam_node as Camera3D):
			result.append(cam_node as Camera3D)

	result.sort_custom(func(a: Camera3D, b: Camera3D) -> bool:
		return a.name.naturalnocasecmp_to(b.name) < 0
	)

	if result.is_empty():
		var fallback: Camera3D = get_node_or_null("_FallbackCamera") as Camera3D
		if fallback != null and is_instance_valid(fallback):
			result.append(fallback)

	return result


## Делает камеру с индексом `index` активной в комнате.
func select_camera(index: int) -> void:
	var room_cams: Array[Camera3D] = get_room_cameras()
	if index < 0 or index >= room_cams.size() or room_cams[index] == null:
		return
	room_cams[index].make_current()


func _setup_chests() -> void:
	var chests: Array[Node] = SceneTreeUtils.collect_descendants(self, func(n: Node) -> bool:
		return n.has_signal("chest_opened")
	)
	for chest: Node in chests:
		if not chest.is_connected("chest_opened", _on_chest_opened):
			chest.connect("chest_opened", _on_chest_opened.bind(chest as Node3D))
		if chest.has_signal("chest_locked_attempt"):
			chest.connect("chest_locked_attempt", func(needed: Variant) -> void:
				var needed_str: String = _format_needed_items_list(needed)
				show_status_message(LocalizationUtils.format("UI_STATUS_CHEST_LOCKED", [needed_str]))
			)
		if chest.has_signal("chest_unlocked"):
			chest.connect("chest_unlocked", func(key_name: String) -> void:
				var display_key: String = LocalizationUtils.resolve_item_name(key_name)
				show_status_message(LocalizationUtils.format("UI_STATUS_CHEST_UNLOCKED", [display_key]))
			)


func _format_needed_items_list(needed: Variant) -> String:
	if needed is Array or needed is PackedStringArray:
		var parts: PackedStringArray = PackedStringArray()
		for item_ref: Variant in needed:
			var resolved_name: String = LocalizationUtils.resolve_item_name(str(item_ref))
			if not resolved_name.is_empty() and not parts.has(resolved_name):
				parts.append(resolved_name)
		return ", ".join(parts)
	return LocalizationUtils.resolve_item_name(str(needed))


func _setup_doors() -> void:
	var doors: Array[Node] = _find_all_doors(self)
	for door: Node in doors:
		if door.has_signal("door_locked"):
			door.connect("door_locked", func(needed: String) -> void:
				var display_needed: String = LocalizationUtils.resolve_item_name(needed)
				show_status_message(LocalizationUtils.format("UI_STATUS_DOOR_LOCKED", [display_needed]))
			)
		if door.has_signal("door_opened"):
			door.connect("door_opened", func() -> void:
				show_status_message(LocalizationUtils.resolve("UI_STATUS_DOOR_OPENED"))
			)


func _find_all_doors(parent: Node) -> Array[Node]:
	return SceneTreeUtils.collect_descendants(parent, func(n: Node) -> bool:
		return "door_id" in n
	)


func _on_chest_opened(_items: Array[String], chest_node: Node3D) -> void:
	active_chest = chest_node
	chest_opened.emit(chest_node)


## Закрывает открытый контейнер (сундук) и оповещает интерфейс.
func close_chest() -> void:
	if active_chest != null:
		active_chest = null
		chest_closed.emit()


## Выводит текстовое сообщение в статусную строку терминала.
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
		var hit_info: Dictionary = RoomRaycaster.cast_screen_ray(
			active_cam,
			get_world_3d(),
			(event as InputEventMouseMotion).position
		)
		var is_interactive: bool = bool(hit_info.get("is_interactive", false))
		Input.set_default_cursor_shape(
			Input.CURSOR_POINTING_HAND if is_interactive else Input.CURSOR_ARROW
		)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not GameManager.active_item.is_empty():
			GameManager.set_active_item("")
			show_status_message(LocalizationUtils.resolve("UI_STATUS_SELECTION_CLEARED"))
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var click_info: Dictionary = RoomRaycaster.cast_screen_ray(
			active_cam,
			get_world_3d(),
			(event as InputEventMouseButton).position
		)
		var kind: int = int(click_info.get("kind", RoomRaycaster.HitKind.NONE))
		if kind == RoomRaycaster.HitKind.NONE:
			return

		var target: Node3D = click_info.get("target", null) as Node3D
		if kind == RoomRaycaster.HitKind.PICKUP or kind == RoomRaycaster.HitKind.QUEST_OBJECT or kind == RoomRaycaster.HitKind.INTERACTABLE:
			if player != null and target != null:
				player.interact_with_item(target)
		else:
			close_chest()
			if player != null:
				var hit_pos: Vector3 = click_info.get("position", Vector3.ZERO) as Vector3
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
	if not GameManager.target_door_id.is_empty():
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
		if spawn_node is Node3D:
			spawn_pos = (spawn_node as Node3D).global_position

	if player != null:
		player.global_position = Vector3(spawn_pos.x, default_spawn_height, spawn_pos.z)
		player.velocity = Vector3.ZERO
		var nav_agent: Variant = player.get("nav_agent")
		if nav_agent is NavigationAgent3D:
			(nav_agent as NavigationAgent3D).target_position = player.global_position

	GameManager.is_door_transition = false
	GameManager.target_door_id = ""
