@tool
class_name ItemPickup
extends Area3D
## Подбираемый предмет в 3D-мире, который при сборе помещается в `GameManager.player_inventory`.
##
## Интегрирован с единым реестром квестов ([QuestRegistry]):
## [br]• поле `item_name` выбирается из динамического выпадающего списка зарегистрированных предметов;
## [br]• поддерживает 1-клик регистрацию нового предмета и `object_id` прямо из Инспектора;
## [br]• использует `object_id` для сохранения факта подбора в `GameManager.world_state`.

@export_category("Item Pickup")

@export_group("Identity & State")
## Уникальный идентификатор этого экземпляра предмета в мире (например, `"room_01_key"`).
## Если оставить пустым, при запуске автоматически используется имя узла (`name`).
@export var object_id: String = ""

@export_group("Pickup Data")
## Предмет из единого реестра ([QuestRegistry]), который добавляется в инвентарь игрока при подборе (например, `"Ключ"`).
## Выбирается из динамического выпадающего списка в Инспекторе.
@export var item_name: String = "Ключ"

@export_group("Quest Registry Quick-Add")
## Введите новый строковый ID предмета для быстрой регистрации в [QuestRegistry] прямо из Инспектора.
@export var quick_register_item_id: String = ""

## Кнопка редактора: регистрирует `quick_register_item_id` в [QuestRegistry], назначает его в `item_name` и обновляет выпадающий список.
@export_tool_button("Register & Assign Pickup Item") var register_item_btn: Callable = _quick_register_item

## Кнопка редактора: регистрирует текущий `object_id` этого подбираемого предмета в [QuestRegistry].
@export_tool_button("Register Pickup Object ID") var register_obj_btn: Callable = _quick_register_object_id

@export_group("Physics & Collision")
@export_subgroup("Ground Placement")
## Если включено, при старте сцены предмет автоматически опускается на поверхность пола вертикальным лучом.
@export var snap_to_ground: bool = true

## Вертикальное смещение предмета над точкой пола (в метрах).
@export var ground_offset: float = 0.2

## Свойство обратной совместимости со старым именем `item_id`.
var item_id: String:
	get:
		return object_id
	set(val):
		object_id = val


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if object_id.is_empty():
		object_id = String(name)

	if bool(GameManager.get_flag(object_id, false)):
		queue_free()
		return

	if snap_to_ground:
		GroundSnap.snap_after_physics_frame(self, ground_offset)


func _validate_property(property: Dictionary) -> void:
	var prop_name: String = str(property.get("name", ""))
	if prop_name == "item_name":
		QuestRegistry.configure_item_property_hint(property, item_name, true)


func _quick_register_item() -> void:
	var target_id: String = quick_register_item_id.strip_edges()
	if target_id.is_empty():
		target_id = item_name.strip_edges()
	if target_id.is_empty():
		push_warning("ItemPickup: Укажите quick_register_item_id для регистрации нового предмета в QuestRegistry.")
		return
	QuestRegistry.register_and_save_item(
		target_id,
		target_id,
		"Quest Item",
		"Подбираемый предмет (%s)" % (object_id if not object_id.is_empty() else name)
	)
	item_name = target_id
	quick_register_item_id = ""
	notify_property_list_changed()


func _quick_register_object_id() -> void:
	var target_id: String = object_id.strip_edges()
	if target_id.is_empty():
		target_id = String(name)
	object_id = target_id
	QuestRegistry.register_and_save_object_id(target_id)
	QuestRegistry.register_and_save_flag(
		target_id,
		false,
		"Item State",
		"Флаг подбора предмета %s (%s)" % [item_name, target_id]
	)
	notify_property_list_changed()


## Помечает предмет как подобранный в [GameManager] и удаляет его со сцены.
func collect() -> void:
	GameManager.set_flag(object_id, true)
	queue_free()
