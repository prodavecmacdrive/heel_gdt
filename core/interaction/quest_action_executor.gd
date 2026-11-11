@tool
class_name QuestActionExecutor
extends RefCounted
## Исполнитель квестовой логики, переходов состояний и обратной связи для [QuestInteractable].
##
## Отвечает за:
## [br]• чтение и сохранение состояния объекта в [GameManager];
## [br]• проверку и расходование требуемого предмета (`required_item`, `consume_item`);
## [br]• активацию целевых узлов (`target_node`) и переключение видимости групп узлов;
## [br]• отправку сообщений статуса в терминал комнаты/интерфейса.


## Восстанавливает сохранённое состояние объекта при загрузке сцены.
## Возвращает актуальную строку состояния (`"default"` или `"active"`).
static func restore_state(
	object_id: String,
	set_flag_on_success: String,
	one_shot: bool,
	initial_state: String
) -> String:
	var resolved_state: String = initial_state
	if not object_id.is_empty():
		resolved_state = str(GameManager.get_flag(object_id + "_state", resolved_state))
	elif not set_flag_on_success.is_empty():
		resolved_state = str(GameManager.get_flag(set_flag_on_success + "_state", resolved_state))

	var effective_flag: String = get_effective_flag_id(object_id, set_flag_on_success)
	if resolved_state != "active" and one_shot and not effective_flag.is_empty():
		if bool(GameManager.get_flag(effective_flag, false)):
			resolved_state = "active"

	return resolved_state


## Возвращает эффективный ключ флага (`object_id`, либо `set_flag_on_success`).
static func get_effective_flag_id(object_id: String, set_flag_on_success: String) -> String:
	if not object_id.is_empty():
		return object_id
	return set_flag_on_success


## Обрабатывает попытку взаимодействия с объектом.
## Возвращает `true`, если взаимодействие привело к успешной активации (`_execute_success`).
static func process_interaction(
	host: Node,
	player_node: CharacterBody3D,
	current_state: String,
	required_item: String,
	consume_item: bool,
	target_node: NodePath,
	set_flag_on_success: String,
	inspect_text: String,
	active_inspect_text: String,
	fail_text: String
) -> bool:
	if current_state == "active":
		if not GameManager.active_item.is_empty():
			var resolved_fail: String = LocalizationUtils.resolve(fail_text if not fail_text.is_empty() else "UI_DEFAULT_FAIL_TEXT")
			if not resolved_fail.is_empty():
				show_message(host, resolved_fail)
			GameManager.set_active_item("")
		else:
			var text_to_show: String = active_inspect_text if not active_inspect_text.is_empty() else inspect_text
			var resolved_inspect: String = LocalizationUtils.resolve(text_to_show)
			if not resolved_inspect.is_empty():
				show_message(host, resolved_inspect)
		return false

	if not GameManager.active_item.is_empty():
		if not required_item.is_empty() and QuestRegistry.items_match(GameManager.active_item, required_item):
			if consume_item:
				GameManager.consume_inventory_item(GameManager.active_item)
				if player_node != null and player_node.has_signal("inventory_updated"):
					player_node.emit_signal("inventory_updated")
			GameManager.set_active_item("")
			return true
		else:
			var resolved_fail: String = LocalizationUtils.resolve(fail_text if not fail_text.is_empty() else "UI_DEFAULT_FAIL_TEXT")
			if not resolved_fail.is_empty():
				show_message(host, resolved_fail)
			GameManager.set_active_item("")
			return false
	else:
		if required_item.is_empty() and (not target_node.is_empty() or not set_flag_on_success.is_empty()):
			return true
		var resolved_inspect: String = LocalizationUtils.resolve(inspect_text)
		if not resolved_inspect.is_empty():
			show_message(host, resolved_inspect)
		return false


## Фиксирует успешную активацию в [GameManager], воздействует на целевой узел и показывает сообщение.
static func execute_success(
	host: Area3D,
	object_id: String,
	set_flag_on_success: String,
	one_shot: bool,
	trigger_mode: int,
	target_node: NodePath,
	nodes_to_show: Array[NodePath],
	nodes_to_hide: Array[NodePath],
	success_text: String,
	active_inspect_text: String,
	inspect_text: String
) -> void:
	if not object_id.is_empty():
		GameManager.set_flag(object_id + "_state", "active")
	elif not set_flag_on_success.is_empty():
		GameManager.set_flag(set_flag_on_success + "_state", "active")

	if not set_flag_on_success.is_empty():
		GameManager.set_flag(set_flag_on_success, true)

	var flag_id: String = get_effective_flag_id(object_id, set_flag_on_success)
	if one_shot and not flag_id.is_empty():
		GameManager.set_flag(flag_id, true)

	update_visual_nodes(host, nodes_to_show, nodes_to_hide, true)

	if trigger_mode == 1 and one_shot and host != null:
		host.monitoring = false

	if host != null and not target_node.is_empty():
		var target: Node = host.get_node_or_null(target_node)
		if target != null:
			if target.has_method("on_quest_trigger"):
				target.call("on_quest_trigger")
			if target is Light3D:
				(target as Light3D).visible = not (target as Light3D).visible
			if "is_locked" in target:
				target.set("is_locked", false)

	if not success_text.is_empty():
		show_message(host, LocalizationUtils.resolve(success_text))
	elif not active_inspect_text.is_empty():
		show_message(host, LocalizationUtils.resolve(active_inspect_text))
	elif not inspect_text.is_empty():
		show_message(host, LocalizationUtils.resolve(inspect_text))


## Переключает видимость списков узлов в зависимости от активности объекта.
static func update_visual_nodes(
	host: Node,
	nodes_to_show: Array[NodePath],
	nodes_to_hide: Array[NodePath],
	is_active: bool
) -> void:
	if host == null:
		return
	for path: NodePath in nodes_to_show:
		_set_node_visibility(host, path, is_active)
	for path: NodePath in nodes_to_hide:
		_set_node_visibility(host, path, not is_active)


## Применяет разблокировку к целевому узлу при повторном входе в комнату, если квест уже выполнен.
static func apply_target_state_if_completed(host: Node, target_node: NodePath) -> void:
	if host == null or target_node.is_empty():
		return
	var target: Node = host.get_node_or_null(target_node)
	if target != null:
		if "is_locked" in target:
			target.set("is_locked", false)
		if target.has_method("on_quest_restored"):
			target.call("on_quest_restored")


## Отправляет текстовое сообщение в статус-панель текущей комнаты или главного терминала.
static func show_message(host: Node, msg: String) -> void:
	if msg.is_empty():
		return
	var room: Node = SceneTreeUtils.find_ancestor(host, func(n: Node) -> bool:
		return n.has_method("show_status_message")
	)
	if room != null:
		room.call("show_status_message", msg)
	elif GameManager.main_ui != null and GameManager.main_ui.has_method("show_status_message"):
		GameManager.main_ui.call("show_status_message", msg)


static func _set_node_visibility(host: Node, path: NodePath, is_vis: bool) -> void:
	if path.is_empty():
		return
	var node: Node = host.get_node_or_null(path)
	if node is Node3D:
		(node as Node3D).visible = is_vis
	elif node is CanvasItem:
		(node as CanvasItem).visible = is_vis

