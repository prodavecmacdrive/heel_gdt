extends StaticBody3D

signal door_opened
signal door_locked(needed_key: String)

# Уникальный ID этой двери в комнате
@export var door_id: String = "door_01"

# Путь к сцене, куда ведет дверь (выбирается в Inspector)
@export_file("*.tscn") var target_scene: String = ""

# ID двери в следующей комнате, у маркера которой нужно поставить игрока
@export var target_door_id: String = "door_02"

@export var is_locked: bool = false
@export var required_key: String = ""

@onready var spawn_point: Marker3D = $SpawnPoint

func _ready() -> void:
	await get_tree().physics_frame
	_snap_to_ground()

func _snap_to_ground() -> void:
	var space_state = get_world_3d().direct_space_state
	var from_pos = Vector3(global_position.x, 20.0, global_position.z)
	var to_pos = Vector3(global_position.x, -20.0, global_position.z)
	var query = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = [get_rid()]

	var hit = space_state.intersect_ray(query)
	if hit:
		global_position.y = hit.position.y + 1.2

func get_spawn_position() -> Vector3:
	if spawn_point != null:
		return spawn_point.global_position
	var sp: Node = get_node_or_null("SpawnPoint")
	if sp is Node3D:
		return (sp as Node3D).global_position
	return global_position + global_transform.basis.z * 1.2

func interact(player: CharacterBody3D = null) -> void:
	if is_locked:
		if required_key != "" and required_key in GameManager.player_inventory:
			is_locked = false
			door_opened.emit()
			_enter_door()
		else:
			door_locked.emit(required_key)
			return
	else:
		door_opened.emit()
		_enter_door()

func _enter_door() -> void:
	GameManager.target_door_id = target_door_id
	
	await get_tree().create_timer(0.6).timeout
	if target_scene != "":
		GameManager.change_room(target_scene, target_door_id)
	else:
		var current_path: String = get_tree().current_scene.scene_file_path if get_tree().current_scene != null else ""
		GameManager.change_room(current_path, target_door_id)
