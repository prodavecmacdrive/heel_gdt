@tool
class_name BunkerMaster
extends Node3D
## Мастер-сцена и 3D-визуализатор связей между шлюзами (`Door`) различных секторов бункера.
##
## Отображает в окне редактора цветные линии переходов между дверями комнат:
## [br]• зелёный — связь валидна и перепад высот в пределах `elevation_tolerance`;
## [br]• оранжевый — связь валидна, но двери находятся на разной высоте по оси Y;
## [br]• красный крест — целевая сцена или `target_door_id` не найдены.

class LineSegment:
	var from: Vector3 = Vector3.ZERO
	var to: Vector3 = Vector3.ZERO
	var color: Color = Color.WHITE

	func _init(p_from: Vector3, p_to: Vector3, p_color: Color) -> void:
		from = p_from
		to = p_to
		color = p_color

const VISUALIZER_NAME: String = "_BunkerLinkVisualizer"
const COLOR_VALID: Color = Color(0.2, 0.9, 0.3)
const COLOR_ELEVATION_MISMATCH: Color = Color(1.0, 0.55, 0.1)
const COLOR_MISSING_TARGET: Color = Color(1.0, 0.15, 0.15)

@export_category("Bunker Master")

@export_group("Link Visualization")
## Если включено, в 3D-вьюпорте редактора отображаются диагностические линии связей между всеми шлюзами дочерних комнат.
@export var show_connections: bool = true:
	set(value):
		show_connections = value
		if Engine.is_editor_hint():
			rebuild_links()

## Допустимое расхождение по высоте (ось Y, в метрах) между связанными дверями, при превышении которого связь помечается предупреждением.
@export_range(0.05, 2.0, 0.05) var elevation_tolerance: float = 0.5:
	set(value):
		elevation_tolerance = value
		if Engine.is_editor_hint():
			rebuild_links()

@export_group("Master Actions")
## Кнопка редактора: проверяет все шлюзы дочерних комнат и выводит подробный отчёт о связях в консоль Output.
@export_tool_button("Validate Bunker Links") var validate_btn: Callable = validate_bunker

## Кнопка редактора: принудительно перестраивает 3D-линии визуализации связей между шлюзами.
@export_tool_button("Rebuild Links") var rebuild_btn: Callable = rebuild_links

var _last_self_transform: Transform3D = Transform3D.IDENTITY
var _last_room_transforms: Dictionary = {}


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		if not child_entered_tree.is_connected(_on_child_entered_tree):
			child_entered_tree.connect(_on_child_entered_tree)
		if not child_exiting_tree.is_connected(_on_child_exiting_tree):
			child_exiting_tree.connect(_on_child_exiting_tree)


func _ready() -> void:
	if Engine.is_editor_hint():
		_sync_transforms()
		call_deferred("rebuild_links")


func _on_child_entered_tree(node: Node) -> void:
	if not Engine.is_editor_hint() or node.name == VISUALIZER_NAME:
		return
	call_deferred("rebuild_links")


func _on_child_exiting_tree(node: Node) -> void:
	if not Engine.is_editor_hint() or node.name == VISUALIZER_NAME:
		return
	call_deferred("rebuild_links")


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return

	var rooms: Array[Node3D] = _get_room_nodes()
	var changed: bool = false

	if not _last_self_transform.is_equal_approx(global_transform):
		changed = true
	elif rooms.size() != _last_room_transforms.size():
		changed = true
	else:
		for room: Node3D in rooms:
			if not _last_room_transforms.has(room):
				changed = true
				break
			var prev_t: Transform3D = _last_room_transforms[room] as Transform3D
			if not prev_t.is_equal_approx(room.global_transform):
				changed = true
				break

	if changed:
		_sync_transforms()
		rebuild_links()


func _sync_transforms() -> void:
	_last_self_transform = global_transform
	_last_room_transforms.clear()
	for room: Node3D in _get_room_nodes():
		_last_room_transforms[room] = room.global_transform


func _get_or_create_visualizer() -> MeshInstance3D:
	var visualizer: MeshInstance3D = get_node_or_null(VISUALIZER_NAME) as MeshInstance3D
	if visualizer == null:
		visualizer = MeshInstance3D.new()
		visualizer.name = VISUALIZER_NAME
		visualizer.mesh = ImmediateMesh.new()
		visualizer.material_override = _create_visualizer_material()
		add_child(visualizer)
		visualizer.owner = null
	else:
		if visualizer.owner != null:
			visualizer.owner = null
		if not (visualizer.mesh is ImmediateMesh):
			visualizer.mesh = ImmediateMesh.new()
		if visualizer.material_override == null:
			visualizer.material_override = _create_visualizer_material()
	return visualizer


func _create_visualizer_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	return mat


func _get_room_nodes() -> Array[Node3D]:
	var rooms: Array[Node3D] = []
	for child: Node in get_children():
		if child is Node3D and not child.scene_file_path.is_empty():
			rooms.append(child as Node3D)
	return rooms


func _find_doors_in_node(parent: Node) -> Array[Node3D]:
	var doors: Array[Node3D] = []
	for child: Node in parent.get_children():
		if child is Node3D and _is_door_node(child):
			doors.append(child as Node3D)
		doors.append_array(_find_doors_in_node(child))
	return doors


func _is_door_node(node: Node) -> bool:
	if not (node is Node3D):
		return false
	var script_obj: Variant = node.get_script()
	if script_obj is Script:
		var script_path: String = (script_obj as Script).resource_path
		if script_path.ends_with("door.gd"):
			return true
	return node.get("door_id") != null


func _normalize_scene_path(path_or_uid: String) -> String:
	if path_or_uid.is_empty():
		return ""
	if path_or_uid.begins_with("uid://"):
		var resolved: String = ""
		if ResourceUID.has_method("uid_to_path"):
			resolved = ResourceUID.uid_to_path(path_or_uid)
		if resolved.is_empty():
			var id: int = ResourceUID.text_to_id(path_or_uid)
			if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
				resolved = ResourceUID.get_id_path(id)
		if not resolved.is_empty():
			return resolved
	return path_or_uid


func _match_room_scene(room_node: Node3D, target_scene_str: String) -> bool:
	var room_path: String = room_node.scene_file_path
	if room_path.is_empty() or target_scene_str.is_empty():
		return false
	if room_path == target_scene_str:
		return true
	var norm_target: String = _normalize_scene_path(target_scene_str)
	var norm_room: String = _normalize_scene_path(room_path)
	if norm_target == norm_room or norm_target == room_path:
		return true
	if target_scene_str.begins_with("uid://"):
		var uid_id: int = ResourceUID.text_to_id(target_scene_str)
		if uid_id != ResourceUID.INVALID_ID and ResourceLoader.has_method("get_resource_uid"):
			var room_uid: int = ResourceLoader.get_resource_uid(room_path)
			if room_uid == uid_id:
				return true
	return false


func _evaluate_door_link(door: Node3D, rooms: Array[Node3D]) -> Dictionary:
	var target_scene_raw: String = String(door.get("target_scene"))
	var target_door_id: String = String(door.get("target_door_id"))

	if target_scene_raw.is_empty():
		return _make_link_result("ERROR", "[ERROR: Target not found] (Empty target_scene)", null, Vector3.ZERO, 0.0)

	if target_door_id.is_empty():
		return _make_link_result("ERROR", "[ERROR: Target not found] (Empty target_door_id)", null, Vector3.ZERO, 0.0)

	var target_room: Node3D = null
	for room: Node3D in rooms:
		if _match_room_scene(room, target_scene_raw):
			target_room = room
			break

	if target_room == null:
		return _make_link_result("ERROR", "[ERROR: Target not found] (Target room not placed in BunkerMaster)", null, Vector3.ZERO, 0.0)

	var target_room_doors: Array[Node3D] = _find_doors_in_node(target_room)
	var target_door: Node3D = null
	for t_door: Node3D in target_room_doors:
		if String(t_door.get("door_id")) == target_door_id:
			target_door = t_door
			break

	if target_door == null:
		return _make_link_result("ERROR", "[ERROR: Target not found] (Door '%s' not found in target room)" % target_door_id, null, Vector3.ZERO, 0.0)

	var spawn_pos: Vector3 = target_door.global_position
	var spawn_node: Node = target_door.get_node_or_null("SpawnPoint")
	if spawn_node is Node3D:
		spawn_pos = (spawn_node as Node3D).global_position

	var y_diff: float = absf(door.global_position.y - target_door.global_position.y)
	if y_diff > elevation_tolerance:
		return _make_link_result("WARNING", "[WARNING: Y-Delta %.2fm]" % y_diff, target_door, spawn_pos, y_diff)

	return _make_link_result("OK", "[OK]", target_door, spawn_pos, y_diff)


func _make_link_result(
	status_type: String,
	status_string: String,
	target_door: Node3D,
	target_spawn_pos: Vector3,
	y_diff: float
) -> Dictionary:
	return {
		"status_type": status_type,
		"status_string": status_string,
		"target_door": target_door,
		"target_spawn_pos": target_spawn_pos,
		"y_diff": y_diff,
	}


## Перестраивает 3D-линии связей между всеми шлюзами дочерних сцен комнат.
func rebuild_links() -> void:
	if not Engine.is_editor_hint():
		return

	var visualizer: MeshInstance3D = _get_or_create_visualizer()
	var imm_mesh: ImmediateMesh = visualizer.mesh as ImmediateMesh
	if imm_mesh == null:
		imm_mesh = ImmediateMesh.new()
		visualizer.mesh = imm_mesh

	imm_mesh.clear_surfaces()

	if not show_connections:
		return

	var rooms: Array[Node3D] = _get_room_nodes()
	var lines: Array[LineSegment] = []

	for room: Node3D in rooms:
		var doors: Array[Node3D] = _find_doors_in_node(room)
		for door: Node3D in doors:
			var link: Dictionary = _evaluate_door_link(door, rooms)
			var status_type: String = String(link.get("status_type", ""))

			match status_type:
				"OK":
					var start_pos: Vector3 = door.global_position
					var end_pos: Vector3 = link.get("target_spawn_pos", start_pos) as Vector3
					lines.append(LineSegment.new(start_pos, end_pos, COLOR_VALID))

				"WARNING":
					var start_pos: Vector3 = door.global_position
					var end_pos: Vector3 = link.get("target_spawn_pos", start_pos) as Vector3
					lines.append(LineSegment.new(start_pos, end_pos, COLOR_ELEVATION_MISMATCH))
					var vert_base: Vector3 = Vector3(end_pos.x, start_pos.y, end_pos.z)
					lines.append(LineSegment.new(vert_base, end_pos, COLOR_ELEVATION_MISMATCH))

				"ERROR":
					var start_pos: Vector3 = door.global_position
					var top_pos: Vector3 = start_pos + Vector3(0.0, 2.5, 0.0)
					lines.append(LineSegment.new(start_pos, top_pos, COLOR_MISSING_TARGET))
					const CROSS_EXTENT: float = 0.3
					lines.append(LineSegment.new(top_pos + Vector3(-CROSS_EXTENT, 0.0, 0.0), top_pos + Vector3(CROSS_EXTENT, 0.0, 0.0), COLOR_MISSING_TARGET))
					lines.append(LineSegment.new(top_pos + Vector3(0.0, -CROSS_EXTENT, 0.0), top_pos + Vector3(0.0, CROSS_EXTENT, 0.0), COLOR_MISSING_TARGET))
					lines.append(LineSegment.new(top_pos + Vector3(0.0, 0.0, -CROSS_EXTENT), top_pos + Vector3(0.0, 0.0, CROSS_EXTENT), COLOR_MISSING_TARGET))

	if lines.is_empty():
		return

	imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for seg: LineSegment in lines:
		imm_mesh.surface_set_color(seg.color)
		imm_mesh.surface_add_vertex(visualizer.to_local(seg.from))
		imm_mesh.surface_set_color(seg.color)
		imm_mesh.surface_add_vertex(visualizer.to_local(seg.to))
	imm_mesh.surface_end()


## Выводит в консоль диагностическую сводку по всем шлюзам и межкомнатным переходам.
func validate_bunker() -> void:
	var rooms: Array[Node3D] = _get_room_nodes()
	print("==================================================")
	print("[BunkerMaster] Validating Bunker Links...")
	print("Found %d room(s)." % rooms.size())

	var total_doors: int = 0
	var count_ok: int = 0
	var count_warn: int = 0
	var count_err: int = 0

	for room: Node3D in rooms:
		var room_name: String = room.name
		var room_scene: String = room.scene_file_path
		print("Room: %s (%s)" % [room_name, room_scene])

		var doors: Array[Node3D] = _find_doors_in_node(room)
		if doors.is_empty():
			print("  (No doors found)")
			continue

		for door: Node3D in doors:
			total_doors += 1
			var d_id: String = String(door.get("door_id"))
			var t_scene: String = String(door.get("target_scene"))
			var t_door_id: String = String(door.get("target_door_id"))

			var link: Dictionary = _evaluate_door_link(door, rooms)
			var status_str: String = String(link.get("status_string", ""))
			var target_desc: String = "Target: '%s' Door: '%s'" % [t_scene, t_door_id]

			print("  - Door '%s' -> %s | %s" % [d_id, target_desc, status_str])

			var status_type: String = String(link.get("status_type", ""))
			match status_type:
				"OK":
					count_ok += 1
				"WARNING":
					count_warn += 1
				"ERROR":
					count_err += 1

	print("Summary: %d door(s) scanned, %d OK, %d Warning(s), %d Error(s)." % [total_doors, count_ok, count_warn, count_err])
	print("==================================================")
