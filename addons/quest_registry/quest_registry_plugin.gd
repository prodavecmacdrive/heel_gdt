@tool
extends EditorPlugin
## Плагин редактора Godot для единого реестра квестов ("Quest Registry") и валидации связей по проекту.
##
## Добавляет нижнюю вкладку **"Quest Registry"** в редактор, связывает выбор строк таблиц
## с открытием соответствующей сцены `.tscn` и выделением целевого узла в дереве сцены,
## а также автоматически обновляет аудит при сохранении сцен.

const PANEL_SCRIPT: GDScript = preload("res://addons/quest_registry/quest_registry_panel.gd")

var _panel: QuestRegistryPanel = null
var _panel_button: Button = null


func _enter_tree() -> void:
	QuestRegistry.get_registry()

	_panel = PANEL_SCRIPT.new() as QuestRegistryPanel
	_panel.navigate_to_scene_node_requested.connect(_on_navigate_to_scene_node)
	_panel.inspect_registry_resource_requested.connect(_on_inspect_registry_resource)
	_panel_button = add_control_to_bottom_panel(_panel, "Quest Registry")

	if not scene_saved.is_connected(_on_scene_saved):
		scene_saved.connect(_on_scene_saved)


func _exit_tree() -> void:
	if scene_saved.is_connected(_on_scene_saved):
		scene_saved.disconnect(_on_scene_saved)

	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
		_panel_button = null


func _on_scene_saved(_filepath: String) -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.refresh_all(true)


func _on_inspect_registry_resource() -> void:
	var reg: QuestRegistryData = QuestRegistry.get_registry()
	if reg != null:
		EditorInterface.edit_resource(reg)


func _on_navigate_to_scene_node(scene_path: String, node_path: String) -> void:
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return

	EditorInterface.open_scene_from_path(scene_path)
	call_deferred("_select_node_in_edited_scene", node_path)


func _select_node_in_edited_scene(node_path: String) -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return

	var target: Node = root
	if not node_path.is_empty() and node_path != ".":
		var clean_path: String = node_path.trim_prefix("./")
		var found: Node = root.get_node_or_null(clean_path)
		if found != null:
			target = found

	var selection: EditorSelection = EditorInterface.get_selection()
	if selection != null:
		selection.clear()
		selection.add_node(target)
	EditorInterface.edit_node(target)

