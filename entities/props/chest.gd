extends StaticBody3D

signal chest_opened(chest_items: Array[String])
signal chest_locked_attempt(needed_items: Array[String])
signal chest_unlocked(key_name: String)

@export var chest_id: String = "room_01_chest"
@export var is_locked: bool = true
@export var unlock_items: Array[String] = ["Ключ"]
@export var consume_key_on_unlock: bool = false
@export var items: Array[String] = ["Батарейка", "Записка"]

var is_open: bool = false

func _ready() -> void:
	# 1. Восстанавливаем состояние замка
	if GameManager.get_flag(chest_id + "_unlocked", false):
		is_locked = false

	# 2. Восстанавливаем содержимое сундука из глобальной памяти
	if GameManager.world_state.has(chest_id + "_items"):
		var saved_items: Array = GameManager.get_flag(chest_id + "_items", [])
		items.clear()
		for it in saved_items:
			items.append(str(it))
	else:
		# Если этот сундук открывают в игре впервые — фиксируем его стартовый лут
		save_chest_items()

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
		global_position.y = hit.position.y + 0.4

func save_chest_items() -> void:
	GameManager.set_flag(chest_id + "_items", items.duplicate())

func interact(player: CharacterBody3D = null) -> void:
	if is_locked:
		var key_found: String = ""
		for item_name in unlock_items:
			if item_name in GameManager.player_inventory:
				key_found = item_name
				break

		if key_found != "":
			is_locked = false
			# Навсегда запоминаем, что сундук открыт
			GameManager.set_flag(chest_id + "_unlocked", true)
			chest_unlocked.emit(key_found)
			if consume_key_on_unlock:
				GameManager.player_inventory.erase(key_found)
				if player:
					player.inventory_updated.emit()
		else:
			chest_locked_attempt.emit(unlock_items)
			return

	is_open = true
	chest_opened.emit(items)
