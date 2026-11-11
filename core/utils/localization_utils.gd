@tool
class_name LocalizationUtils
extends RefCounted
## Универсальная гибридная система локализации, динамический парсер `res://data/translations.csv`
## и автоматический синхронизатор текстов со всех сцен и реестра проекта.
##
## Правила разрешения текста ([method resolve]):
## [br]• если строка пуста — возвращается `""`;
## [br]• если строка обёрнута в двойные кавычки (например, `"Просто текст"`) — внешние кавычки снимаются, а текст выводится буквально без поиска перевода;
## [br]• иначе строка ищется в загруженной таблице переводов (`TranslationServer` / `translations.csv`) для текущего языка; при отсутствии перевода возвращается значение базового языка или сама исходная строка.

const CSV_PATH: String = "res://data/translations.csv"
const SCAN_DIRS: Array[String] = ["res://rooms", "res://entities"]
const TEXT_PROPERTY_NAMES: Array[String] = [
	"sector_name",
	"room_name",
	"inspect_text",
	"active_inspect_text",
	"success_text",
	"fail_text",
	"item_name",
	"required_item",
]
const ARRAY_TEXT_PROPERTY_NAMES: Array[String] = [
	"items",
	"unlock_items",
]

static var _is_loaded: bool = false
static var _active_locale: String = "ru"
static var _locales: PackedStringArray = PackedStringArray()
static var _key_order: PackedStringArray = PackedStringArray()
static var _table: Dictionary = {}


## Гарантирует, что таблица `res://data/translations.csv` загружена и зарегистрирована в [TranslationServer].
static func ensure_loaded(force_reload: bool = false) -> void:
	if _is_loaded and not force_reload:
		return
	load_csv(CSV_PATH)


## Загружает и парсит CSV-файл локализации, динамически определяя все языковые колонки из заголовка
## и регистрируя объекты [Translation] в [TranslationServer].
static func load_csv(csv_path: String = CSV_PATH) -> bool:
	_locales.clear()
	_key_order.clear()
	_table.clear()

	if not FileAccess.file_exists(csv_path):
		_is_loaded = true
		return false

	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		push_warning("LocalizationUtils: Не удалось открыть файл локализации: %s" % csv_path)
		_is_loaded = true
		return false

	var header: PackedStringArray = file.get_csv_line()
	if header.size() < 2:
		file.close()
		_is_loaded = true
		return false

	for c: int in range(1, header.size()):
		var loc_code: String = header[c].strip_edges()
		if not loc_code.is_empty():
			_locales.append(loc_code)

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.is_empty():
			continue
		var key: String = row[0]
		if key.is_empty():
			continue
		if not _table.has(key):
			_key_order.append(key)
			_table[key] = {}

		var row_dict: Dictionary = _table[key] as Dictionary
		for i: int in range(_locales.size()):
			var col_idx: int = i + 1
			var val: String = row[col_idx] if col_idx < row.size() else ""
			row_dict[_locales[i]] = val

	file.close()
	_register_with_translation_server()

	if _locales.size() > 0 and not _locales.has(_active_locale):
		_active_locale = _locales[0]

	TranslationServer.set_locale(_active_locale)
	_is_loaded = true
	return true


## Регистрирует все языковые колонки из таблицы в глобальном [TranslationServer].
static func _register_with_translation_server() -> void:
	for loc: String in _locales:
		var tr_obj := Translation.new()
		tr_obj.locale = loc
		for key: String in _key_order:
			var row_dict: Dictionary = _table.get(key, {}) as Dictionary
			var translated: String = str(row_dict.get(loc, ""))
			if not translated.is_empty():
				tr_obj.add_message(StringName(key), translated)
		TranslationServer.add_translation(tr_obj)


## Возвращает список всех доступных кодов языков, обнаруженных в заголовке `translations.csv`.
static func get_available_locales() -> PackedStringArray:
	ensure_loaded()
	if _locales.is_empty():
		return PackedStringArray(["ru", "en"])
	return _locales


## Возвращает код текущего активного языка (например, `"ru"` или `"en"`).
static func get_locale() -> String:
	ensure_loaded()
	return _active_locale


## Возвращает человекочитаемое название языка для отображения в меню настроек.
static func get_locale_display_name(locale_code: String) -> String:
	var code_lower: String = locale_code.strip_edges().to_lower()
	if code_lower == "ru":
		return "RU — Русский"
	if code_lower == "en":
		return "EN — English"
	if code_lower == "uk":
		return "UK — Українська"
	if code_lower == "de":
		return "DE — Deutsch"
	if code_lower == "fr":
		return "FR — Français"
	if code_lower == "es":
		return "ES — Español"
	var server_name: String = TranslationServer.get_locale_name(code_lower)
	if not server_name.is_empty() and server_name != code_lower:
		return "%s — %s" % [locale_code.to_upper(), server_name]
	return locale_code.to_upper()


## Переключает активный язык игры и синхронизирует [TranslationServer].
static func set_locale(locale_code: String) -> void:
	ensure_loaded()
	var clean_code: String = locale_code.strip_edges()
	if clean_code.is_empty():
		return
	_active_locale = clean_code
	TranslationServer.set_locale(_active_locale)


## Проверяет, обёрнута ли строка в двойные кавычки (правило буквального вывода без перевода).
static func is_quoted_literal(text: String) -> bool:
	return text.length() >= 2 and text.begins_with("\"") and text.ends_with("\"")


## Разрешает строку по правилам гибридной локализации:
## [br]1. Пустая строка -> `""`.
## [br]2. Строка в кавычках `"..."` -> возвращает содержимое без внешних кавычек.
## [br]3. Ищет перевод по ключу/тексту для текущей локали; если не найден — откатывается к первой колонке CSV или возвращает исходную строку.
static func resolve(text: String) -> String:
	if text.is_empty():
		return ""

	if is_quoted_literal(text):
		return text.substr(1, text.length() - 2)

	ensure_loaded()

	if _table.has(text):
		var row_dict: Dictionary = _table[text] as Dictionary
		var active_val: String = str(row_dict.get(_active_locale, ""))
		if not active_val.is_empty():
			return active_val
		if not _locales.is_empty():
			var fallback_val: String = str(row_dict.get(_locales[0], ""))
			if not fallback_val.is_empty():
				return fallback_val

	var server_tr: String = TranslationServer.translate(StringName(text))
	if not server_tr.is_empty() and server_tr != text:
		return server_tr

	return text


## Разрешает строку или ключ локализации и подставляет аргументы форматирования (`%s`, `%d`).
static func format(key_or_text: String, args: Array = []) -> String:
	var pattern: String = resolve(key_or_text)
	if args.is_empty():
		return pattern
	return pattern % args


## Возвращает локализованное отображаемое название предмета по его ID или имени из [QuestRegistry].
static func resolve_item_name(item_id_or_name: String) -> String:
	if item_id_or_name.is_empty():
		return ""
	var item_data: ItemData = QuestRegistry.get_item_data(item_id_or_name)
	if item_data != null and not item_data.item_name.is_empty():
		return resolve(item_data.item_name)
	return resolve(item_id_or_name)


## Возвращает локализованное описание предмета по его ID или имени из [QuestRegistry].
static func resolve_item_description(item_id_or_name: String) -> String:
	if item_id_or_name.is_empty():
		return ""
	var item_data: ItemData = QuestRegistry.get_item_data(item_id_or_name)
	if item_data != null and not item_data.description.is_empty():
		return resolve(item_data.description)
	return ""


## Автоматически сканирует все предметы в [QuestRegistry], все сцены в `res://rooms/` и `res://entities/`
## и добавляет новые ключи/строки в `res://data/translations.csv`, сохраняя все существующие переводы и колонки.
## Возвращает количество добавленных новых ключей.
static func sync_project_strings_to_csv(csv_path: String = CSV_PATH) -> int:
	ensure_loaded(true)

	if _locales.is_empty():
		_locales = PackedStringArray(["ru", "en"])

	var discovered_keys: PackedStringArray = _collect_all_project_translatable_strings()
	var added_count: int = 0

	for key: String in discovered_keys:
		if key.is_empty() or is_quoted_literal(key):
			continue
		if not _table.has(key):
			_key_order.append(key)
			var new_row: Dictionary = {}
			for i: int in range(_locales.size()):
				var loc: String = _locales[i]
				new_row[loc] = key if i == 0 else ""
			_table[key] = new_row
			added_count += 1

	if added_count > 0 or not FileAccess.file_exists(csv_path):
		save_csv(csv_path)
		load_csv(csv_path)

	return added_count


## Сохраняет текущую таблицу переводов в CSV-файл `res://data/translations.csv`.
static func save_csv(csv_path: String = CSV_PATH) -> Error:
	var dir_path: String = csv_path.get_base_dir()
	var abs_dir: String = ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)

	var file: FileAccess = FileAccess.open(csv_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	var header: PackedStringArray = PackedStringArray(["keys"])
	for loc: String in _locales:
		header.append(loc)
	file.store_csv_line(header)

	for key: String in _key_order:
		var row_dict: Dictionary = _table.get(key, {}) as Dictionary
		var line: PackedStringArray = PackedStringArray([key])
		for loc: String in _locales:
			line.append(str(row_dict.get(loc, "")))
		file.store_csv_line(line)

	file.close()
	return OK


## Собирает все переводимые строки и ключи из UI, [QuestRegistry] и всех `.tscn` сцен проекта.
static func _collect_all_project_translatable_strings() -> PackedStringArray:
	var collected: PackedStringArray = PackedStringArray()

	var core_keys: Array[String] = [
		"UI_BTN_MENU",
		"UI_BTN_NOTES",
		"UI_BTN_MAP",
		"UI_SURVEILLANCE_TITLE",
		"UI_INVENTORY_TITLE",
		"UI_CHEST_TITLE",
		"UI_SECTOR_HEADER_FORMAT",
		"UI_CAM_LABEL_FORMAT",
		"UI_MENU_TITLE",
		"UI_MENU_CONTINUE",
		"UI_MENU_SETTINGS",
		"UI_MENU_EXIT",
		"UI_SETTINGS_TITLE",
		"UI_SETTINGS_LANGUAGE",
		"UI_SETTINGS_BACK",
		"UI_STATUS_NOTES_STUB",
		"UI_STATUS_MAP_STUB",
		"UI_STATUS_ITEM_SELECTED",
		"UI_STATUS_ITEM_DESELECTED",
		"UI_STATUS_SELECTION_CLEARED",
		"UI_STATUS_STORED_IN_CHEST",
		"UI_STATUS_TAKEN_FROM_CHEST",
		"UI_STATUS_CHEST_FULL",
		"UI_STATUS_INVENTORY_FULL",
		"UI_STATUS_ITEM_OBTAINED",
		"UI_STATUS_CHEST_LOCKED",
		"UI_STATUS_CHEST_UNLOCKED",
		"UI_STATUS_DOOR_LOCKED",
		"UI_STATUS_DOOR_OPENED",
		"UI_DEFAULT_FAIL_TEXT",
	]
	for k: String in core_keys:
		_add_unique_string(collected, k)

	var reg: QuestRegistryData = QuestRegistry.get_registry()
	if reg != null:
		for item_def: ItemData in reg.items:
			if item_def == null:
				continue
			_add_unique_string(collected, item_def.get_effective_id())
			_add_unique_string(collected, item_def.item_name)
			_add_unique_string(collected, item_def.description)

	for scan_dir: String in SCAN_DIRS:
		var scene_files: PackedStringArray = _find_tscn_files_recursive(scan_dir)
		for scene_path: String in scene_files:
			var base_title: String = scene_path.get_file().get_basename().replace("_", " ").to_upper()
			if scene_path.begins_with("res://rooms/") and scene_path.get_file() != "bunker_master.tscn":
				_add_unique_string(collected, base_title)
			_extract_strings_from_scene(scene_path, collected)

	return collected


static func _add_unique_string(list: PackedStringArray, value: String) -> void:
	var clean: String = value.strip_edges()
	if clean.is_empty() or is_quoted_literal(clean):
		return
	if not list.has(clean):
		list.append(clean)


static func _find_tscn_files_recursive(dir_path: String) -> PackedStringArray:
	var results: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return results

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var full_path: String = dir_path.path_join(entry)
			if dir.current_is_dir():
				var sub_files: PackedStringArray = _find_tscn_files_recursive(full_path)
				for sf: String in sub_files:
					results.append(sf)
			elif entry.ends_with(".tscn"):
				results.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
	results.sort()
	return results


static func _extract_strings_from_scene(scene_path: String, out_list: PackedStringArray) -> void:
	if not ResourceLoader.exists(scene_path):
		return
	var packed: PackedScene = ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return
	var state: SceneState = packed.get_state()
	if state == null:
		return

	var node_count: int = state.get_node_count()
	for i: int in range(node_count):
		var prop_count: int = state.get_node_property_count(i)
		for p: int in range(prop_count):
			var p_name: String = String(state.get_node_property_name(i, p))
			var p_val: Variant = state.get_node_property_value(i, p)
			if p_name in TEXT_PROPERTY_NAMES and p_val is String:
				_add_unique_string(out_list, p_val as String)
			elif p_name in ARRAY_TEXT_PROPERTY_NAMES and (p_val is Array or p_val is PackedStringArray):
				for elem: Variant in p_val:
					_add_unique_string(out_list, str(elem))

