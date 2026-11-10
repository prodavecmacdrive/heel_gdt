class_name ItemPickup
extends Area3D

# Уникальный ID конкретного объекта в мире (например: "room_01_key", "room_02_battery")
@export var item_id: String = ""
# Название предмета, которое попадет в инвентарь игрока
@export var item_name: String = "Предмет"

func _ready() -> void:
	# Если ID не задан, генерируем временный на основе имени ноды
	if item_id == "":
		item_id = name

	# Проверяем по глобальной памяти: если уже подбирали — удаляем со сцены
	if GameManager.get_flag(item_id, false):
		queue_free()
		return

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
		global_position.y = hit.position.y + 0.2

func collect() -> void:
	# Запоминаем факт подбора в глобальную память
	GameManager.set_flag(item_id, true)
	queue_free()
