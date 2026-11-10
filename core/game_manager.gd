extends Node

signal room_change_requested(scene_path: String, target_door_id: String)

# Временный путь к сцене комнаты для прямого запуска через F6
var temp_start_room_path: String = ""

# Ссылка на корневую оболочку интерфейса Main
var main_ui: Control = null

# Глобальный карман игрока (переезжает сюда из player.gd)
var player_inventory: Array[String] = []

# Хранилище постоянных фактов мира: {"room_01_key_taken": true, "room_01_chest_open": true}
var world_state: Dictionary = {}

# ID двери/маркера, у которого нужно заспавнить игрока в загружаемой комнате
var target_door_id: String = ""

# Флаг активного перехода через дверь (для позиционирования игрока)
var is_door_transition: bool = false

# Вспомогательный метод для быстрой проверки флага (возвращает false, если флаг еще не создан)
func get_flag(flag_name: String, default_value: Variant = false) -> Variant:
	return world_state.get(flag_name, default_value)

# Вспомогательный метод для записи состояния
func set_flag(flag_name: String, value: Variant) -> void:
	world_state[flag_name] = value

# Централизованный переход между комнатами
func change_room(scene_path: String, door_id: String = "") -> void:
	target_door_id = door_id
	is_door_transition = true
	if room_change_requested.get_connections().is_empty():
		if scene_path != "":
			get_tree().change_scene_to_file(scene_path)
		else:
			get_tree().reload_current_scene()
	else:
		room_change_requested.emit(scene_path, door_id)

# Обратная совместимость с предыдущими вызовами
func change_scene_with_door(scene_path: String, door_id: String = "") -> void:
	change_room(scene_path, door_id)
