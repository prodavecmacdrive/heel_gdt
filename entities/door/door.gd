@tool
class_name Door
extends StaticBody3D
## Межкомнатный шлюз (дверь), обеспечивающий переход игрока между сценами комнат и позиционирование у точки спавна.
##
## Поддерживает запирание на ключ (`is_locked`, `required_item`, `consume_item`), сохранение состояния
## разблокировки в [GameManager], динамический выбор ключа из [QuestRegistry] и автоматическое прилипание к полу через [GroundSnap].

signal door_opened
signal door_locked(needed_key: String)

@export_category("Door Portal")

@export_group("Identity & State")
## Уникальный идентификатор объекта шлюза для сохранения состояния замка (`<object_id>_unlocked`) в [GameManager].
## Если оставить пустым, состояние замка привязывается к `door_id` текущей сцены.
@export var object_id: String = ""

## Уникальный идентификатор этой двери внутри текущей комнаты (например, `"door_01"` или `"door_main"`).
## На него ссылаются двери других комнат через свой параметр `target_door_id`, а также плагин `BunkerMaster`.
@export var door_id: String = "door_01"

## Если включено, шлюз заперт и требует наличия предмета `required_item` в инвентаре игрока
## (либо внешней разблокировки через [QuestInteractable]).
@export var is_locked: bool = false

@export_group("Portal Transition")
## Путь или UID файла сцены комнаты (`*.tscn`), в которую ведёт этот шлюз при проходе.
@export_file("*.tscn") var target_scene: String = ""

## Идентификатор целевой двери (`door_id`) в загружаемой комнате, у маркера `SpawnPoint` которой появится игрок.
@export var target_door_id: String = "door_02"

## Задержка в секундах перед сменой сцены после открытия шлюза.
@export_range(0.0, 5.0, 0.05) var transition_delay: float = 0.6

@export_group("Item Requirement")
## Предмет из единого реестра ([QuestRegistry]), отпирающий этот шлюз напрямую при взаимодействии (например, `"Ключ"`).
## Выбирается из динамического выпадающего списка в Инспекторе.
@export var required_item: String = ""

## Если включено, предмет `required_item` удаляется из инвентаря игрока при отпирании двери.
@export var consume_item: bool = false

@export_group("Quest Registry Quick-Add")
## Введите новый строковый ID предмета-ключа для быстрой регистрации в [QuestRegistry] прямо из Инспектора двери.
@export var quick_register_item_id: String = ""

## Кнопка редактора: регистрирует `quick_register_item_id` в [QuestRegistry], назначает его в `required_item` и обновляет выпадающий список.
@export_tool_button("Register & Assign Key Item") var register_item_btn: Callable = _quick_register_item

## Кнопка редактора: регистрирует текущий `object_id` (или `door_id`) шлюза в центральной базе [QuestRegistry].
@export_tool_button("Register Door Object ID") var register_obj_btn: Callable = _quick_register_object_id

@export_group("Physics & Collision")
@export_subgroup("Ground Placement")
## Если включено, при старте сцены дверь автоматически выравнивается по высоте пола вертикальным лучом.
@export var snap_to_ground: bool = true

## Вертикальное смещение центра двери относительно найденной точки пола (по умолчанию `1.2` м для двери высотой `2.4` м).
@export var ground_offset: float = 1.2

## Свойство обратной совместимости со старым именем `required_key`.
var required_key: String:
	get:
		return required_item
	set(val):
		required_item = val

@onready var spawn_point: Marker3D = get_node_or_null("SpawnPoint") as Marker3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	var unlock_flag: String = _get_unlock_flag_key()
	if not unlock_flag.is_empty() and bool(GameManager.get_flag(unlock_flag, false)):
		is_locked = false

	if snap_to_ground:
		GroundSnap.snap_after_physics_frame(self, ground_offset)


func _validate_property(property: Dictionary) -> void:
	var prop_name: String = str(property.get("name", ""))
	if prop_name == "required_item":
		QuestRegistry.configure_item_property_hint(property, required_item, true)


func _quick_register_item() -> void:
	var target_id: String = quick_register_item_id.strip_edges()
	if target_id.is_empty():
		target_id = required_item.strip_edges()
	if target_id.is_empty():
		push_warning("Door: Укажите quick_register_item_id для регистрации нового ключа в QuestRegistry.")
		return
	QuestRegistry.register_and_save_item(
		target_id,
		target_id,
		"Key",
		"Ключ от шлюза %s" % (door_id if not door_id.is_empty() else name)
	)
	required_item = target_id
	quick_register_item_id = ""
	notify_property_list_changed()


func _quick_register_object_id() -> void:
	var target_id: String = object_id.strip_edges()
	if target_id.is_empty():
		target_id = door_id.strip_edges()
	if target_id.is_empty():
		push_warning("Door: Укажите object_id или door_id для регистрации в QuestRegistry.")
		return
	QuestRegistry.register_and_save_object_id(target_id)
	var unlock_flag: String = _get_unlock_flag_key()
	if not unlock_flag.is_empty():
		QuestRegistry.register_and_save_flag(unlock_flag, false, "Door", "Флаг разблокировки шлюза %s" % target_id)
	notify_property_list_changed()


## Возвращает глобальную позицию точки появления игрока перед этой дверью.
func get_spawn_position() -> Vector3:
	if spawn_point != null:
		return spawn_point.global_position
	var sp: Node = get_node_or_null("SpawnPoint")
	if sp is Node3D:
		return (sp as Node3D).global_position
	return global_position + global_transform.basis.z * 1.2


## Вызывается, когда игрок подходит к шлюзу и взаимодействует с ним.
func interact(player_node: CharacterBody3D = null) -> void:
	if is_locked:
		if not required_item.is_empty() and GameManager.has_inventory_item(required_item):
			is_locked = false
			var unlock_flag: String = _get_unlock_flag_key()
			if not unlock_flag.is_empty():
				GameManager.set_flag(unlock_flag, true)
			if consume_item:
				GameManager.consume_inventory_item(required_item)
				if player_node != null and player_node.has_signal("inventory_updated"):
					player_node.emit_signal("inventory_updated")
			door_opened.emit()
			_enter_door()
		else:
			door_locked.emit(required_item)
			return
	else:
		door_opened.emit()
		_enter_door()


## Вызывается из [QuestInteractable] при дистанционной разблокировке двери через терминал/рычаг.
func on_quest_trigger() -> void:
	is_locked = false
	var unlock_flag: String = _get_unlock_flag_key()
	if not unlock_flag.is_empty():
		GameManager.set_flag(unlock_flag, true)


func _enter_door() -> void:
	GameManager.target_door_id = target_door_id
	await get_tree().create_timer(transition_delay).timeout
	if not target_scene.is_empty():
		GameManager.change_room(target_scene, target_door_id)
	else:
		var current_path: String = get_tree().current_scene.scene_file_path if get_tree().current_scene != null else ""
		GameManager.change_room(current_path, target_door_id)


func _get_unlock_flag_key() -> String:
	if not object_id.is_empty():
		return object_id + "_unlocked"
	if not door_id.is_empty():
		var scene_prefix: String = "room"
		if is_inside_tree() and get_tree().current_scene != null:
			scene_prefix = String(get_tree().current_scene.name)
		return scene_prefix + "_" + door_id + "_unlocked"
	return ""
