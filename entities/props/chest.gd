@tool
class_name Chest
extends StaticBody3D
## Контейнер хранения предметов (сундук/шкафчик) с поддержкой замка и сохранения содержимого в [GameManager].
##
## Интегрирован с единым реестром квестов ([QuestRegistry]):
## [br]• `required_item`, `items` и `unlock_items` автоматически формируют выпадающие списки из базы предметов;
## [br]• поддерживает 1-клик регистрацию новых предметов и своего `object_id` прямо из Инспектора.

signal chest_opened(chest_items: Array[String])
signal chest_locked_attempt(needed_items: Array[String])
signal chest_unlocked(key_name: String)

@export_category("Storage Container")

@export_group("Identity & State")
## Уникальный идентификатор контейнера в мире (например, `"room_01_chest"`).
## Используется для сохранения состояния замка (`<object_id>_unlocked`) и списка предметов (`<object_id>_items`) в [GameManager].
@export var object_id: String = "room_01_chest"

## Если включено, контейнер заперт и перед открытием требует наличия `required_item` (или предмета из `unlock_items`) в инвентаре игрока.
@export var is_locked: bool = true

@export_group("Container Contents")
## Стартовый список предметов из [QuestRegistry], находящихся внутри контейнера (максимум 4 слота в UI).
## Каждый элемент массива выбирается через динамический выпадающий список.
@export var items: Array[String] = ["Батарейка", "Записка"]

@export_group("Item Requirement")
## Основной предмет (ключ) из [QuestRegistry], необходимый для отпирания контейнера (например, `"Ключ"`).
@export var required_item: String = "Ключ"

## Дополнительный список подходящих ключей/предметов из [QuestRegistry], любой из которых может отпереть контейнер.
@export var unlock_items: Array[String] = ["Ключ"]

## Если включено, ключ удаляется из инвентаря игрока в момент отпирания контейнера.
@export var consume_item: bool = false

@export_group("Quest Registry Quick-Add")
## Введите новый строковый ID предмета для быстрой регистрации в [QuestRegistry] прямо из Инспектора сундука.
@export var quick_register_item_id: String = ""

## Кнопка редактора: регистрирует `quick_register_item_id` в [QuestRegistry] и добавляет его в содержимое сундука (`items`).
@export_tool_button("Register & Add to Contents") var register_content_btn: Callable = _quick_register_content_item

## Кнопка редактора: регистрирует `quick_register_item_id` в [QuestRegistry] и назначает его как ключ (`required_item`).
@export_tool_button("Register & Assign as Key") var register_key_btn: Callable = _quick_register_key_item

## Кнопка редактора: регистрирует текущий `object_id` контейнера и его флаг отпирания в [QuestRegistry].
@export_tool_button("Register Chest Object ID") var register_obj_btn: Callable = _quick_register_object_id

@export_group("Physics & Collision")
@export_subgroup("Ground Placement")
## Если включено, при старте сцены контейнер автоматически опускается на поверхность пола вертикальным лучом.
@export var snap_to_ground: bool = true

## Вертикальное смещение центра контейнера над полом (по умолчанию `0.4` м для сундука высотой `0.8` м).
@export var ground_offset: float = 0.4

## Свойства обратной совместимости со старыми именами (`chest_id`, `consume_key_on_unlock`).
var chest_id: String:
	get:
		return object_id
	set(val):
		object_id = val

var consume_key_on_unlock: bool:
	get:
		return consume_item
	set(val):
		consume_item = val

var is_open: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if bool(GameManager.get_flag(object_id + "_unlocked", false)):
		is_locked = false

	if GameManager.world_state.has(object_id + "_items"):
		var saved_items: Array = GameManager.get_flag(object_id + "_items", []) as Array
		items.clear()
		for it: Variant in saved_items:
			items.append(str(it))
	else:
		save_chest_items()

	if snap_to_ground:
		GroundSnap.snap_after_physics_frame(self, ground_offset)


func _validate_property(property: Dictionary) -> void:
	var prop_name: String = str(property.get("name", ""))
	if prop_name == "required_item":
		QuestRegistry.configure_item_property_hint(property, required_item, true)
	elif prop_name == "items":
		QuestRegistry.configure_item_array_property_hint(property, items)
	elif prop_name == "unlock_items":
		QuestRegistry.configure_item_array_property_hint(property, unlock_items)


func _quick_register_content_item() -> void:
	var target_id: String = quick_register_item_id.strip_edges()
	if target_id.is_empty():
		push_warning("Chest: Укажите quick_register_item_id для регистрации нового предмета в QuestRegistry.")
		return
	QuestRegistry.register_and_save_item(
		target_id,
		target_id,
		"Quest Item",
		"Предмет из контейнера %s" % object_id
	)
	if not items.has(target_id):
		items.append(target_id)
	quick_register_item_id = ""
	notify_property_list_changed()


func _quick_register_key_item() -> void:
	var target_id: String = quick_register_item_id.strip_edges()
	if target_id.is_empty():
		target_id = required_item.strip_edges()
	if target_id.is_empty():
		push_warning("Chest: Укажите quick_register_item_id для регистрации нового ключа в QuestRegistry.")
		return
	QuestRegistry.register_and_save_item(
		target_id,
		target_id,
		"Key",
		"Ключ от контейнера %s" % object_id
	)
	required_item = target_id
	if not unlock_items.has(target_id):
		unlock_items.append(target_id)
	quick_register_item_id = ""
	notify_property_list_changed()


func _quick_register_object_id() -> void:
	var target_id: String = object_id.strip_edges()
	if target_id.is_empty():
		push_warning("Chest: Поле object_id пусто — нечего регистрировать.")
		return
	QuestRegistry.register_and_save_object_id(target_id)
	QuestRegistry.register_and_save_flag(
		target_id + "_unlocked",
		false,
		"Puzzle",
		"Флаг отпирания контейнера %s" % target_id
	)
	notify_property_list_changed()


## Сохраняет текущий массив предметов контейнера в `GameManager.world_state`.
func save_chest_items() -> void:
	GameManager.set_flag(object_id + "_items", items.duplicate())


## Обрабатывает взаимодействие игрока с контейнером (проверка ключа, отпирание и открытие окна обмена предметами).
func interact(player_node: CharacterBody3D = null) -> void:
	if is_locked:
		var candidates: Array[String] = _collect_unlock_candidates()
		var key_found: String = ""
		for candidate_item: String in candidates:
			if GameManager.has_inventory_item(candidate_item):
				key_found = candidate_item
				break

		if not key_found.is_empty():
			is_locked = false
			GameManager.set_flag(object_id + "_unlocked", true)
			chest_unlocked.emit(key_found)
			if consume_item:
				GameManager.consume_inventory_item(key_found)
				if player_node != null and player_node.has_signal("inventory_updated"):
					player_node.emit_signal("inventory_updated")
		else:
			chest_locked_attempt.emit(candidates)
			return

	is_open = true
	chest_opened.emit(items)


func _collect_unlock_candidates() -> Array[String]:
	var result: Array[String] = []
	if not required_item.is_empty():
		result.append(required_item)
	for candidate: String in unlock_items:
		if not candidate.is_empty() and not result.has(candidate):
			result.append(candidate)
	return result
