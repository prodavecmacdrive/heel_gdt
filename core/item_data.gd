@tool
class_name ItemData
extends Resource
## Ресурс описания игрового предмета для единого реестра квестов ([QuestRegistry]), инвентаря и проверок взаимодействий.

@export_category("Item Data")

@export_group("Identity & Presentation")
## Уникальный строковый идентификатор предмета в центральном реестре (например, `"Ключ"` или `"key_security_01"`).
## Если оставить пустым, в качестве идентификатора используется `item_name`.
@export var item_id: String = ""

## Человекочитаемое название предмета, отображаемое в слотах инвентаря и сообщениях статуса терминала.
@export var item_name: String = "Предмет"

## Категория предмета для систематизации в редакторе реестра.
@export_enum("Key", "Tool", "Quest Item", "Consumable", "Document") var category: String = "Quest Item"

## Иконка предмета для отображения в интерфейсе инвентаря и в таблице реестра.
@export var icon: Texture2D = null

## Акцентный цвет предмета для подсветки слота или иконки в интерфейсе.
@export var color: Color = Color.WHITE

@export_group("Documentation & Metadata")
## Подробное описание предмета и его роли в квестовых цепочках (для геймдизайнера и осмотра).
@export_multiline var description: String = ""

## Произвольные дополнительные параметры предмета (например, заряд батареи, код допуска и т.д.).
@export var metadata: Dictionary = {}

## Свойство обратной совместимости со старым именем `name`.
var name: String:
	get:
		return item_name
	set(val):
		item_name = val


## Возвращает эффективный уникальный идентификатор предмета (`item_id`, либо `item_name`, если `item_id` пуст).
func get_effective_id() -> String:
	if not item_id.is_empty():
		return item_id
	return item_name


## Проверяет, соответствует ли этот ресурс предмета переданному идентификатору или имени [param query].
func matches_identifier(query: String) -> bool:
	if query.is_empty():
		return false
	return item_id == query or item_name == query
