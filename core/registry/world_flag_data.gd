@tool
class_name WorldFlagData
extends Resource
## Ресурс описания глобального флага состояния мира для [QuestRegistryData] и [GameManager].
##
## Определяет уникальный идентификатор флага (`flag_id`), его стартовое значение при начале новой игры
## (`default_value`) и документацию для геймдизайнера (`description`).

@export_category("World Flag Definition")

@export_group("Flag Identity & Default")
## Уникальный строковый идентификатор глобального флага в `GameManager.world_state` (например, `"terminal_door_01"`).
@export var flag_id: String = ""

## Значение флага по умолчанию при инициализации мира до начала прохождения (обычно `false`).
@export var default_value: bool = false

## Логическая категория флага для фильтрации и группировки в панели реестра.
@export_enum("Puzzle", "Door", "Trigger", "Item State", "Story") var category: String = "Puzzle"

@export_group("Developer Notes")
## Описание того, какое событие, шлюз или квестовую головоломку контролирует данный флаг.
@export_multiline var description: String = ""

