@tool
class_name QuestRegistry
extends RefCounted
## Статический менеджер доступа к единому реестру квестов (`res://data/quest_registry.tres`).
##
## Обеспечивает:
## [br]• загрузку, кэширование и сохранение центральной базы [QuestRegistryData] в редакторе и в рантайме;
## [br]• генерацию динамических списков `PROPERTY_HINT_ENUM` для выпадающих меню Инспектора (`_validate_property`);
## [br]• быструю регистрацию новых предметов, флагов и `object_id` в 1 клик прямо из Инспектора сущностей;
## [br]• предзаполнение стандартными данными комнат (`room_01.tscn`, `room_02.tscn`) для нулевой регрессии.

const REGISTRY_DIR: String = "res://data"
const REGISTRY_PATH: String = "res://data/quest_registry.tres"

static var _cached_registry: QuestRegistryData = null


## Загружает и возвращает центральный ресурс [QuestRegistryData].
## Если файл `res://data/quest_registry.tres` ещё не существует, создаёт его со стандартным набором данных проекта.
static func get_registry(force_reload: bool = false) -> QuestRegistryData:
	if _cached_registry != null and not force_reload:
		return _cached_registry

	if ResourceLoader.exists(REGISTRY_PATH):
		var cache_mode: ResourceLoader.CacheMode = (
			ResourceLoader.CACHE_MODE_REPLACE if force_reload else ResourceLoader.CACHE_MODE_REUSE
		)
		var loaded: Resource = ResourceLoader.load(REGISTRY_PATH, "", cache_mode)
		if loaded is QuestRegistryData:
			_cached_registry = loaded as QuestRegistryData
			_ensure_default_entries(_cached_registry)
			return _cached_registry

	_cached_registry = QuestRegistryData.new()
	_ensure_default_entries(_cached_registry)
	save_registry(_cached_registry)
	return _cached_registry


## Сохраняет ресурс реестра на диск по каноническому пути `res://data/quest_registry.tres`.
static func save_registry(registry: QuestRegistryData = null) -> Error:
	var target: QuestRegistryData = registry if registry != null else get_registry()
	if target == null:
		return ERR_INVALID_PARAMETER

	_cached_registry = target

	var abs_dir: String = ProjectSettings.globalize_path(REGISTRY_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)

	target.resource_path = REGISTRY_PATH
	var err: Error = ResourceSaver.save(target, REGISTRY_PATH)
	if err != OK:
		push_warning("QuestRegistry: Не удалось сохранить реестр по пути %s (код %d)" % [REGISTRY_PATH, err])
	return err


## Гарантирует наличие базовых предметов, флагов и объектов из существующих сцен (`room_01.tscn`, `room_02.tscn`).
static func _ensure_default_entries(reg: QuestRegistryData) -> bool:
	if reg == null:
		return false

	var modified: bool = false

	var default_items: Array[Dictionary] = [
		{
			"id": "Ключ",
			"name": "Ключ",
			"category": "Key",
			"desc": "Стандартный ключ доступа сектора 01. Открывает запертый контейнер и электронный терминал шлюза.",
			"color": Color(1.0, 0.85, 0.2),
		},
		{
			"id": "Батарейка",
			"name": "Батарейка",
			"category": "Tool",
			"desc": "Энергетический элемент питания для портативных приборов и резервных цепей.",
			"color": Color(0.3, 0.85, 0.5),
		},
		{
			"id": "Записка",
			"name": "Записка",
			"category": "Document",
			"desc": "Рукописная служебная заметка персонала бункера с подсказками по кодам безопасности.",
			"color": Color(0.9, 0.9, 0.8),
		},
		{
			"id": "Отвертка",
			"name": "Отвертка",
			"category": "Tool",
			"desc": "Слесарный инструмент для демонтажа вентиляционных решёток и сервисных панелей.",
			"color": Color(0.4, 0.7, 1.0),
		},
		{
			"id": "Карточка",
			"name": "Карточка",
			"category": "Key",
			"desc": "Магнитная ключ-карта допуска сотрудника технического сектора.",
			"color": Color(0.95, 0.4, 0.35),
		},
	]

	for item_def: Dictionary in default_items:
		var item_id: String = str(item_def["id"])
		if not reg.has_item(item_id):
			reg.register_item(
				item_id,
				str(item_def["name"]),
				str(item_def["category"]),
				str(item_def["desc"]),
				item_def["color"] as Color
			)
			modified = true

	var default_flags: Array[Dictionary] = [
		{
			"id": "room_01_key",
			"default": false,
			"category": "Item State",
			"desc": "Флаг подбора предмета 'Ключ' с пола в комнате room_01.",
		},
		{
			"id": "terminal_door_01",
			"default": false,
			"category": "Puzzle",
			"desc": "Флаг успешной разблокировки терминала шлюза в комнате room_01.",
		},
		{
			"id": "room_01_chest_unlocked",
			"default": false,
			"category": "Puzzle",
			"desc": "Флаг отпирания контейнера хранения в комнате room_01.",
		},
		{
			"id": "room_02_chest_unlocked",
			"default": false,
			"category": "Puzzle",
			"desc": "Флаг отпирания контейнера хранения в комнате room_02.",
		},
		{
			"id": "door_01_unlocked",
			"default": false,
			"category": "Door",
			"desc": "Флаг снятия блокировки с шлюза door_01.",
		},
	]

	for flag_def: Dictionary in default_flags:
		var flag_id: String = str(flag_def["id"])
		if not reg.has_flag(flag_id):
			reg.register_flag(
				flag_id,
				bool(flag_def["default"]),
				str(flag_def["category"]),
				str(flag_def["desc"])
			)
			modified = true

	var default_objects: Array[String] = [
		"room_01_key",
		"room_01_chest",
		"terminal_door_01",
		"room_02_chest",
	]

	for obj_id: String in default_objects:
		if not reg.has_object_id(obj_id):
			reg.register_object_id(obj_id)
			modified = true

	return modified


## Возвращает массив всех зарегистрированных идентификаторов предметов.
static func get_item_ids() -> PackedStringArray:
	return get_registry().get_item_ids()


## Возвращает массив всех зарегистрированных идентификаторов глобальных флагов.
static func get_flag_ids() -> PackedStringArray:
	return get_registry().get_flag_ids()


## Находит и возвращает данные предмета [ItemData] по его ID или названию.
static func get_item_data(id_or_name: String) -> ItemData:
	return get_registry().find_item(id_or_name)


## Находит и возвращает описание флага [WorldFlagData] по его `flag_id`.
static func get_flag_data(flag_id: String) -> WorldFlagData:
	return get_registry().find_flag(flag_id)


## Проверяет, эквивалентны ли два строковых идентификатора/имени предмета согласно реестру.
static func items_match(item_a: String, item_b: String) -> bool:
	if item_a.is_empty() or item_b.is_empty():
		return false
	if item_a == item_b:
		return true
	var data_a: ItemData = get_item_data(item_a)
	if data_a != null and data_a.matches_identifier(item_b):
		return true
	return false


## Быстро регистрирует новый предмет в реестре и сразу сохраняет `quest_registry.tres`.
static func register_and_save_item(
	item_id: String,
	item_name: String = "",
	category: String = "Quest Item",
	description: String = ""
) -> ItemData:
	var reg: QuestRegistryData = get_registry()
	var item: ItemData = reg.register_item(item_id, item_name, category, description)
	if item != null:
		save_registry(reg)
		LocalizationUtils.sync_project_strings_to_csv()
	return item


## Быстро регистрирует новый глобальный флаг в реестре и сразу сохраняет `quest_registry.tres`.
static func register_and_save_flag(
	flag_id: String,
	default_value: bool = false,
	category: String = "Puzzle",
	description: String = ""
) -> WorldFlagData:
	var reg: QuestRegistryData = get_registry()
	var flag: WorldFlagData = reg.register_flag(flag_id, default_value, category, description)
	if flag != null:
		save_registry(reg)
	return flag


## Быстро регистрирует `object_id` в реестре и сразу сохраняет `quest_registry.tres`.
static func register_and_save_object_id(object_id: String) -> bool:
	var reg: QuestRegistryData = get_registry()
	var added: bool = reg.register_object_id(object_id)
	if added:
		save_registry(reg)
	return added


## Формирует строку `hint_string` для `PROPERTY_HINT_ENUM` со всеми предметами из реестра.
## Всегда включает пустой вариант `""` в начале, чтобы опциональные поля можно было оставить пустыми,
## а также сохраняет текущее значение [param current_value], если оно ещё не внесено в реестр.
static func build_item_enum_hint(current_value: String = "", allow_empty: bool = true) -> String:
	var ids: PackedStringArray = get_item_ids()
	var options: PackedStringArray = PackedStringArray()
	if allow_empty:
		options.append("")
	for id: String in ids:
		if not options.has(id):
			options.append(id)
	if not current_value.is_empty() and not options.has(current_value):
		options.append(current_value)
	return ",".join(options)


## Формирует строку `hint_string` для `PROPERTY_HINT_ENUM` со всеми глобальными флагами из реестра.
static func build_flag_enum_hint(current_value: String = "", allow_empty: bool = true) -> String:
	var ids: PackedStringArray = get_flag_ids()
	var options: PackedStringArray = PackedStringArray()
	if allow_empty:
		options.append("")
	for id: String in ids:
		if not options.has(id):
			options.append(id)
	if not current_value.is_empty() and not options.has(current_value):
		options.append(current_value)
	return ",".join(options)


## Настраивает словарь свойства `property` в `_validate_property` как выпадающий список предметов (`PROPERTY_HINT_ENUM`).
static func configure_item_property_hint(property: Dictionary, current_value: String = "", allow_empty: bool = true) -> void:
	property["hint"] = PROPERTY_HINT_ENUM
	property["hint_string"] = build_item_enum_hint(current_value, allow_empty)


## Настраивает словарь свойства `property` в `_validate_property` для типизированного массива `Array[String]`,
## чтобы каждый элемент массива выбирался из выпадающего списка зарегистрированных предметов.
static func configure_item_array_property_hint(property: Dictionary, current_items: Array[String] = []) -> void:
	var ids: PackedStringArray = get_item_ids()
	var options: PackedStringArray = PackedStringArray()
	options.append("")
	for id: String in ids:
		if not options.has(id):
			options.append(id)
	for existing: String in current_items:
		if not existing.is_empty() and not options.has(existing):
			options.append(existing)
	var enum_csv: String = ",".join(options)
	property["hint"] = PROPERTY_HINT_TYPE_STRING
	property["hint_string"] = "%d/%d:%s" % [TYPE_STRING, PROPERTY_HINT_ENUM, enum_csv]


## Настраивает словарь свойства `property` в `_validate_property` как выпадающий список флагов (`PROPERTY_HINT_ENUM`).
static func configure_flag_property_hint(property: Dictionary, current_value: String = "", allow_empty: bool = true) -> void:
	property["hint"] = PROPERTY_HINT_ENUM
	property["hint_string"] = build_flag_enum_hint(current_value, allow_empty)

