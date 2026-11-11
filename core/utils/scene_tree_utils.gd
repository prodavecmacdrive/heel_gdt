@tool
class_name SceneTreeUtils
extends RefCounted
## Статические утилиты для безопасной работы с деревом сцены в редакторе и в игре.
##
## Единая точка для трёх операций, которые раньше дублировались во многих скриптах:
## [br]• определение корня сцены (для назначения [member Node.owner]);
## [br]• назначение владельца сгенерированным узлам, чтобы они сохранялись в [code].tscn[/code];
## [br]• создание дочерних узлов с корректным владельцем.


## Возвращает корень сцены, которому должен принадлежать [param node].
## [br]В редакторе — редактируемая сцена (если узел внутри неё), в игре — [member Node.owner]
## (корень комнаты), затем текущая сцена и, в крайнем случае, родитель.
static func resolve_scene_root(node: Node) -> Node:
	if node == null:
		return null
	if Engine.is_editor_hint() and node.is_inside_tree():
		var edited: Node = node.get_tree().edited_scene_root
		if edited != null and (edited == node or edited.is_ancestor_of(node)):
			return edited
	if node.owner != null:
		return node.owner
	if node.is_inside_tree() and node.get_tree().current_scene != null:
		return node.get_tree().current_scene
	return node.get_parent()


## Назначает [param scene_root] владельцем узла [param node] (если это не сам корень).
static func adopt(node: Node, scene_root: Node) -> void:
	if node == null or scene_root == null or node == scene_root:
		return
	node.owner = scene_root


## Рекурсивно назначает владельца только тем узлам, у которых его нет.
## [br]Не трогает узлы вложенных инстансов сцен, поэтому безопасна для любых поддеревьев.
static func adopt_orphans_recursive(node: Node, scene_root: Node) -> void:
	if node == null or scene_root == null:
		return
	if node != scene_root and node.owner == null:
		node.owner = scene_root
	for child: Node in node.get_children():
		adopt_orphans_recursive(child, scene_root)


## Добавляет [param child] к [param parent] и, если [param persist] = true, делает его
## сохраняемым в сцене (владелец — корень сцены [param parent]).
static func add_child_owned(parent: Node, child: Node, persist: bool = true) -> void:
	parent.add_child(child)
	if persist:
		adopt(child, resolve_scene_root(parent))


## Возвращает ближайшего предка [param node], для которого [param predicate] вернул true.
static func find_ancestor(node: Node, predicate: Callable) -> Node:
	var current: Node = node.get_parent() if node != null else null
	while current != null:
		if bool(predicate.call(current)):
			return current
		current = current.get_parent()
	return null


## Рекурсивно собирает всех потомков [param root], для которых [param predicate] вернул true.
static func collect_descendants(root: Node, predicate: Callable) -> Array[Node]:
	var result: Array[Node] = []
	if root == null:
		return result
	for child: Node in root.get_children():
		if bool(predicate.call(child)):
			result.append(child)
		result.append_array(collect_descendants(child, predicate))
	return result


## Перемещает [param node] под [param new_parent], сохраняя глобальную трансформацию
## и восстанавливая владельца в редакторе.
static func reparent_preserving(node: Node, new_parent: Node) -> void:
	if node == null or new_parent == null or node.get_parent() == new_parent:
		return
	var scene_root: Node = resolve_scene_root(node)
	node.reparent(new_parent, true)
	if Engine.is_editor_hint() and scene_root != null:
		adopt(node, scene_root)
		adopt_orphans_recursive(node, scene_root)

