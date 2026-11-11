@tool
class_name QuestRegistryData
extends Resource
## Централизованный ресурс базы данных единого реестра квестов (`res://data/quest_registry.tres`).
##
## Служит единым источником истины (Single Source of Truth) для всех игровых предметов ([ItemData]),
## глобальных флагов мира ([WorldFlagData]) и постоянных идентификаторов объектов сцен (`object_id`).

@export_category("Unified Quest Registry")

@export_group("Items Catalog")
## Массив всех зарегистрированных игровых предметов проекта ([ItemData]).
@export var items: Array[ItemData] = []

@export_group("World Flags Catalog")
## Массив всех зарегистрированных глобальных булевых флагов состояния мира ([WorldFlagData]).
@export var flags: Array[WorldFlagData] = []

@export_group("Persistent Object IDs")
## Список зарегистрированных уникальных идентификаторов объектов (`object_id`), сохраняющих своё состояние в [GameManager].
@export var registered_object_ids: PackedStringArray = PackedStringArray()


## Возвращает упорядоченный массив всех уникальных идентификаторов предметов в реестре.
func get_item_ids() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for item: ItemData in items:
		if item == null:
			continue
		var eff_id: String = item.get_effective_id()
		if not eff_id.is_empty() and not result.has(eff_id):
			result.append(eff_id)
	return result


## Возвращает упорядоченный массив всех уникальных идентификаторов глобальных флагов в реестре.
func get_flag_ids() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for flag: WorldFlagData in flags:
		if flag == null:
			continue
		if not flag.flag_id.is_empty() and not result.has(flag.flag_id):
			result.append(flag.flag_id)
	return result


## Находит и возвращает ресурс [ItemData] по его `item_id` или `item_name` (или `null`, если не найден).
func find_item(id_or_name: String) -> ItemData:
	if id_or_name.is_empty():
		return null
	for item: ItemData in items:
		if item != null and item.matches_identifier(id_or_name):
			return item
	return null


## Находит и возвращает ресурс [WorldFlagData] по его `flag_id` (или `null`, если не найден).
func find_flag(p_flag_id: String) -> WorldFlagData:
	if p_flag_id.is_empty():
		return null
	for flag: WorldFlagData in flags:
		if flag != null and flag.flag_id == p_flag_id:
			return flag
	return null


## Проверяет, зарегистрирован ли предмет с указанным идентификатором или именем.
func has_item(id_or_name: String) -> bool:
	return find_item(id_or_name) != null


## Проверяет, зарегистрирован ли флаг с указанным `flag_id`.
func has_flag(p_flag_id: String) -> bool:
	return find_flag(p_flag_id) != null


## Проверяет, зарегистрирован ли указанный `object_id` в списке постоянных объектов.
func has_object_id(p_object_id: String) -> bool:
	if p_object_id.is_empty():
		return false
	return registered_object_ids.has(p_object_id)


## Регистрирует новый предмет или обновляет существующий. Возвращает экземпляр [ItemData].
func register_item(
	p_id: String,
	p_name: String = "",
	p_category: String = "Quest Item",
	p_description: String = "",
	p_color: Color = Color.WHITE
) -> ItemData:
	var clean_id: String = p_id.strip_edges()
	if clean_id.is_empty():
		return null

	var clean_name: String = p_name.strip_edges()
	if clean_name.is_empty():
		clean_name = clean_id

	var existing: ItemData = find_item(clean_id)
	if existing != null:
		existing.item_id = clean_id
		if not p_name.strip_edges().is_empty():
			existing.item_name = clean_name
		if not p_category.is_empty():
			existing.category = p_category
		if not p_description.is_empty():
			existing.description = p_description
		return existing

	var new_item := ItemData.new()
	new_item.item_id = clean_id
	new_item.item_name = clean_name
	new_item.category = p_category if not p_category.is_empty() else "Quest Item"
	new_item.description = p_description
	new_item.color = p_color
	items.append(new_item)
	emit_changed()
	return new_item


## Регистрирует новый глобальный флаг или обновляет существующий. Возвращает экземпляр [WorldFlagData].
func register_flag(
	p_flag_id: String,
	p_default_value: bool = false,
	p_category: String = "Puzzle",
	p_description: String = ""
) -> WorldFlagData:
	var clean_id: String = p_flag_id.strip_edges()
	if clean_id.is_empty():
		return null

	var existing: WorldFlagData = find_flag(clean_id)
	if existing != null:
		existing.default_value = p_default_value
		if not p_category.is_empty():
			existing.category = p_category
		if not p_description.is_empty():
			existing.description = p_description
		return existing

	var new_flag := WorldFlagData.new()
	new_flag.flag_id = clean_id
	new_flag.default_value = p_default_value
	new_flag.category = p_category if not p_category.is_empty() else "Puzzle"
	new_flag.description = p_description
	flags.append(new_flag)
	emit_changed()
	return new_flag


## Регистрирует уникальный `object_id` объекта сцены, если он ещё не присутствует в списке.
func register_object_id(p_object_id: String) -> bool:
	var clean_id: String = p_object_id.strip_edges()
	if clean_id.is_empty() or registered_object_ids.has(clean_id):
		return false
	registered_object_ids.append(clean_id)
	emit_changed()
	return true


## Удаляет предмет из реестра по его идентификатору или имени. Возвращает `true`, если предмет был удалён.
func remove_item(id_or_name: String) -> bool:
	for i: int in range(items.size() - 1, -1, -1):
		var it: ItemData = items[i]
		if it != null and it.matches_identifier(id_or_name):
			items.remove_at(i)
			emit_changed()
			return true
	return false


## Удаляет глобальный флаг из реестра по его `flag_id`. Возвращает `true`, если флаг был удалён.
func remove_flag(p_flag_id: String) -> bool:
	for i: int in range(flags.size() - 1, -1, -1):
		var fl: WorldFlagData = flags[i]
		if fl != null and fl.flag_id == p_flag_id:
			flags.remove_at(i)
			emit_changed()
			return true
	return false


## Удаляет `object_id` из списка зарегистрированных объектов.
func remove_object_id(p_object_id: String) -> bool:
	var idx: int = registered_object_ids.find(p_object_id)
	if idx != -1:
		registered_object_ids.remove_at(idx)
		emit_changed()
		return true
	return false

