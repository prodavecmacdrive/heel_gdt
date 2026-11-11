@tool
class_name GroundSnap
extends RefCounted
## Прилипание объектов к поверхности пола с помощью вертикального луча.
##
## Заменяет четыре копии метода [code]_snap_to_ground()[/code], которые раньше жили
## в двери, сундуке, подбираемом предмете и игроке.

## Высота, с которой стартует луч поиска пола (в глобальных координатах).
const RAY_TOP: float = 20.0
## Нижняя граница луча поиска пола.
const RAY_BOTTOM: float = -20.0


## Опускает/поднимает [param body] так, чтобы его начало координат оказалось на
## [param height_offset] метров выше найденного пола. Возвращает true, если пол найден.
## [br]Собственный коллайдер тела (если это [CollisionObject3D]) исключается автоматически.
static func snap(body: Node3D, height_offset: float, extra_exclude: Array[RID] = []) -> bool:
	if body == null or not body.is_inside_tree():
		return false
	var world: World3D = body.get_world_3d()
	if world == null:
		return false

	var exclude: Array[RID] = extra_exclude.duplicate()
	if body is CollisionObject3D:
		exclude.append((body as CollisionObject3D).get_rid())

	var origin: Vector3 = body.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(origin.x, RAY_TOP, origin.z),
		Vector3(origin.x, RAY_BOTTOM, origin.z)
	)
	query.exclude = exclude

	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var hit_pos: Vector3 = hit["position"] as Vector3
	body.global_position = Vector3(origin.x, hit_pos.y + height_offset, origin.z)
	return true


## Отложенный вариант: ждёт один физический кадр (коллизии комнаты успевают
## зарегистрироваться) и затем выполняет [method snap]. Только для рантайма.
static func snap_after_physics_frame(body: Node3D, height_offset: float) -> void:
	if body == null or Engine.is_editor_hint() or not body.is_inside_tree():
		return
	await body.get_tree().physics_frame
	if is_instance_valid(body):
		snap(body, height_offset)

