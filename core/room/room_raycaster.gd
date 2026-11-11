class_name RoomRaycaster
extends RefCounted
## Трассировщик лучей курсора мыши для 3D-комнат ([RoomBase]).
##
## Устраняет дублирование физического рейкаста при движении мыши (смена курсора)
## и при клике левой кнопкой (выбор цели взаимодействия или точки навигации).

const RAY_LENGTH: float = 1000.0

## Классификация объекта, в который попал луч курсора.
enum HitKind {
	NONE = 0,         ## Луч ни во что не попал.
	SURFACE = 1,      ## Обычная поверхность (пол/стена) для перемещения игрока.
	PICKUP = 2,       ## Подбираемый предмет с методом `collect()`.
	QUEST_OBJECT = 3, ## Квестовый объект [QuestInteractable] в режиме клика (`trigger_mode == 0`).
	INTERACTABLE = 4, ## Дочерняя зона `InteractArea` объекта с методом `interact()` (дверь, сундук).
}


## Выполняет рейкаст из [param camera] через экранную точку [param screen_pos] в [param world_3d]
## и возвращает словарь:
## [br]`{"kind": HitKind, "target": Node3D, "position": Vector3, "is_interactive": bool}`.
static func cast_screen_ray(camera: Camera3D, world_3d: World3D, screen_pos: Vector2) -> Dictionary:
	var empty_result: Dictionary = {
		"kind": HitKind.NONE,
		"target": null,
		"position": Vector3.ZERO,
		"is_interactive": false,
	}
	if camera == null or world_3d == null:
		return empty_result

	var ray_from: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var ray_to: Vector3 = ray_from + ray_dir * RAY_LENGTH

	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collide_with_areas = true

	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return empty_result

	var hit_pos: Vector3 = hit.get("position", Vector3.ZERO) as Vector3
	var collider: Object = hit.get("collider", null)

	var quest_target: QuestInteractable = _resolve_quest_interactable(collider)
	if collider is Area3D and collider.has_method("collect"):
		return {
			"kind": HitKind.PICKUP,
			"target": collider as Node3D,
			"position": hit_pos,
			"is_interactive": true,
		}

	if quest_target != null and quest_target.trigger_mode == 0:
		return {
			"kind": HitKind.QUEST_OBJECT,
			"target": quest_target,
			"position": hit_pos,
			"is_interactive": true,
		}

	if collider is Node and (collider as Node).name == "InteractArea":
		var parent_node: Node = (collider as Node).get_parent()
		if parent_node is Node3D and parent_node.has_method("interact"):
			return {
				"kind": HitKind.INTERACTABLE,
				"target": parent_node as Node3D,
				"position": hit_pos,
				"is_interactive": true,
			}

	return {
		"kind": HitKind.SURFACE,
		"target": collider as Node3D if collider is Node3D else null,
		"position": hit_pos,
		"is_interactive": false,
	}


static func _resolve_quest_interactable(collider: Object) -> QuestInteractable:
	if collider is QuestInteractable:
		return collider as QuestInteractable
	if collider is Node and (collider as Node).get_parent() is QuestInteractable:
		return (collider as Node).get_parent() as QuestInteractable
	return null

