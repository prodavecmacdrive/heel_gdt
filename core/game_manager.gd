extends Node
## Глобальный синглтон (Autoload) управления состоянием мира, инвентарём игрока, локализацией и переходами между комнатами.
##
## Интегрирован с центральным реестром квестов ([QuestRegistry]) и гибридной системой локализации ([LocalizationUtils]):
## [br]• при старте загружает `res://data/translations.csv` и инициализирует `world_state` значениями по умолчанию всех флагов;
## [br]• хранит список предметов игрока (`player_inventory`), активный предмет (`active_item`) и активный язык (`current_locale`);
## [br]• оповещает интерфейс о смене языка через сигнал `locale_changed`;
## [br]• маршрутизирует смену комнат через главный терминал (`main_ui`).

signal room_change_requested(scene_path: String, target_door_id: String)
signal active_item_changed(item_id: String)
signal world_flag_changed(flag_name: String, new_value: Variant)
signal locale_changed(new_locale: String)

## Временный путь к сцене комнаты при прямом запуске комнаты из редактора (F6).
var temp_start_room_path: String = ""

## Ссылка на корневой контроллер интерфейса главного терминала (`res://ui/main.gd`).
var main_ui: Control = null

## Глобальный инвентарь игрока (список строковых идентификаторов/названий предметов).
var player_inventory: Array[String] = []

## Текущий выбранный предмет в инвентаре игрока для применения на объекты мира (`""`, если ничего не выбрано).
var active_item: String = ""

## Словарь постоянных фактов и состояний игрового мира (`{"room_01_key": true, "terminal_door_01_state": "active"}`).
var world_state: Dictionary = {}

## Идентификатор целевой двери (`door_id`), у которой должен появиться игрок после загрузки новой комнаты.
var target_door_id: String = ""

## Флаг активного перехода через дверь (указывает `RoomBase` позиционировать игрока у целевого шлюза).
var is_door_transition: bool = false

## Код текущего активного языка интерфейса и текстов мира (например, `"ru"` или `"en"`).
var current_locale: String = "ru"


func _ready() -> void:
	LocalizationUtils.ensure_loaded()
	current_locale = LocalizationUtils.get_locale()
	initialize_world_state_from_registry()


## Переключает активный язык игры и оповещает все подписанные элементы UI и комнат через `locale_changed`.
func set_locale(locale_code: String) -> void:
	LocalizationUtils.set_locale(locale_code)
	var updated_locale: String = LocalizationUtils.get_locale()
	if current_locale != updated_locale:
		current_locale = updated_locale
	locale_changed.emit(current_locale)


## Возвращает массив всех доступных кодов языков из `res://data/translations.csv`.
func get_available_locales() -> PackedStringArray:
	return LocalizationUtils.get_available_locales()


## Инициализирует `world_state` значениями по умолчанию всех флагов, зарегистрированных в [QuestRegistry].
## Не перезаписывает флаги, которые уже были установлены в текущей сессии.
func initialize_world_state_from_registry() -> void:
	var reg: QuestRegistryData = QuestRegistry.get_registry()
	if reg == null:
		return
	for flag_def: WorldFlagData in reg.flags:
		if flag_def != null and not flag_def.flag_id.is_empty():
			if not world_state.has(flag_def.flag_id):
				world_state[flag_def.flag_id] = flag_def.default_value


## Возвращает ресурс метаданных предмета [ItemData] из центрального реестра по его ID или имени (или `null`, если не найден).
func get_item_data(item_id_or_name: String) -> ItemData:
	return QuestRegistry.get_item_data(item_id_or_name)


## Возвращает локализованное человекочитаемое имя предмета из [QuestRegistry] и [LocalizationUtils].
func get_item_display_name(item_id_or_name: String) -> String:
	return LocalizationUtils.resolve_item_name(item_id_or_name)


## Проверяет, есть ли в инвентаре игрока предмет, соответствующий [param required_id_or_name] (с учётом синонимов `item_id` / `item_name` в реестре).
func has_inventory_item(required_id_or_name: String) -> bool:
	if required_id_or_name.is_empty():
		return false
	for inv_item: String in player_inventory:
		if QuestRegistry.items_match(inv_item, required_id_or_name):
			return true
	return false


## Удаляет один экземпляр предмета [param required_id_or_name] из инвентаря игрока. Возвращает `true`, если предмет был найден и удалён.
func consume_inventory_item(required_id_or_name: String) -> bool:
	if required_id_or_name.is_empty():
		return false
	for i: int in range(player_inventory.size()):
		if QuestRegistry.items_match(player_inventory[i], required_id_or_name):
			var removed: String = player_inventory[i]
			player_inventory.remove_at(i)
			if QuestRegistry.items_match(active_item, removed):
				set_active_item("")
			if main_ui != null and main_ui.has_method("update_inventory_ui"):
				main_ui.call("update_inventory_ui")
			return true
	return false


## Проверяет корректность перехода состояния для постоянного объекта [param object_id].
func validate_state_transition(object_id: String, new_state: String) -> bool:
	if new_state != "default" and new_state != "active":
		push_warning("GameManager: Неизвестное целевое состояние '%s' для объекта '%s'" % [new_state, object_id])
		return false
	return true


## Устанавливает или сбрасывает активный выбранный предмет инвентаря и оповещает подписчиков.
func set_active_item(item_id: String) -> void:
	if active_item != item_id:
		active_item = item_id
		active_item_changed.emit(active_item)


## Возвращает значение флага `flag_name` из `world_state` (или `default_value`, если флаг ещё не задан).
func get_flag(flag_name: String, default_value: Variant = false) -> Variant:
	if world_state.has(flag_name):
		return world_state[flag_name]
	var flag_def: WorldFlagData = QuestRegistry.get_flag_data(flag_name)
	if flag_def != null:
		return flag_def.default_value
	return default_value


## Записывает значение `value` для ключа `flag_name` в глобальное хранилище `world_state`.
func set_flag(flag_name: String, value: Variant) -> void:
	if flag_name.is_empty():
		return
	world_state[flag_name] = value
	world_flag_changed.emit(flag_name, value)


## Выполняет переход в комнату `scene_path` с позиционированием игрока у двери `door_id`.
func change_room(scene_path: String, door_id: String = "") -> void:
	target_door_id = door_id
	is_door_transition = true
	if room_change_requested.get_connections().is_empty():
		if not scene_path.is_empty():
			get_tree().change_scene_to_file(scene_path)
		else:
			get_tree().reload_current_scene()
	else:
		room_change_requested.emit(scene_path, door_id)


## Метод обратной совместимости для вызова `change_room()`.
func change_scene_with_door(scene_path: String, door_id: String = "") -> void:
	change_room(scene_path, door_id)
