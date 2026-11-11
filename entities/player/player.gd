@tool
class_name Player
extends CharacterBody3D
## Контроллер персонажа игрока с 2.5D-спрайтовым ригом и навигацией по [NavigationAgent3D].
##
## Использует общие модули [SpriteRenderSettings], [SpriteUtils], [PlaceholderTextures] и [GroundSnap],
## обеспечивая полное единообразие параметров отображения и физики с остальными сущностями проекта.

signal inventory_updated

const GRAVITY: float = 9.8

@export_category("Player Controller")

@export_group("Movement & Interaction")
## Скорость горизонтального перемещения персонажа по навигационному маршруту (в метрах в секунду).
@export_range(0.5, 25.0, 0.1) var speed: float = 5.0

## Максимальная дистанция (в метрах), на которой персонаж может взаимодействовать с целевым предметом или объектом.
@export_range(0.5, 10.0, 0.1) var interaction_distance: float = 2.5

## Критическая отметка высоты по оси Y, ниже которой срабатывает защита от выпадения за пределы уровня
## (персонаж возвращается на высоту `ground_offset` с обнулением скорости).
@export var void_fall_threshold: float = -5.0

@export_group("Physics & Collision")
## Если включено, при старте сцены персонаж автоматически привязывается к поверхности пола вертикальным лучом.
@export var snap_to_ground: bool = true

## Смещение центра капсулы персонажа над точкой пола при срабатывании `snap_to_ground` (в метрах).
## При стандартной высоте капсулы 2.0 м значение `1.0` ставит ступни ровно на поверхность пола.
@export var ground_offset: float = 1.0

@export_group("2D Sprite Settings")
@export_subgroup("Texture & Animation")
## Ресурс покадровых анимаций персонажа (`idle`, `walk`, либо направленные `idle_left`/`idle_right`, `walk_left`/`walk_right`).
## Если назначен, для рендеринга используется дочерний `AnimatedSprite3D`.
@export var sprite_frames: SpriteFrames = null:
	set(val):
		sprite_frames = val
		if is_inside_tree():
			_refresh_sprite_rig()

## Статическая текстура персонажа (используется, когда `sprite_frames` не задан).
## Если оставить пустым, автоматически генерируется пиксельный силуэт космонавта из [PlaceholderTextures].
@export var sprite_texture: Texture2D = null:
	set(val):
		sprite_texture = val
		if is_inside_tree():
			_refresh_sprite_rig()

@export_subgroup("Orientation & Anchor")
## Если включено, спрайт автоматически отражается по горизонтали (`flip_h`) относительно ракурса активной камеры комнаты.
## Если выключено, контроллер ищет отдельные анимации с суффиксами `_left` и `_right`.
@export var auto_flip_h: bool = true:
	set(val):
		auto_flip_h = val
		if is_inside_tree():
			_refresh_sprite_rig()

## Режим поворота спрайта персонажа к активной камере:
## [br]• `Y-Billboard` (0) — поворот только вокруг вертикальной оси Y (рекомендуется для 2.5D-персонажей);
## [br]• `Fixed / Disabled` (1) — фиксированная ориентация;
## [br]• `Full Billboard` (2) — полный поворот к камере по всем осям.
@export_enum("Y-Billboard", "Fixed / Disabled", "Full Billboard") var billboard_mode: int = 0:
	set(val):
		billboard_mode = val
		if is_inside_tree():
			_refresh_sprite_rig()

## Точка привязки (pivot) спрайта относительно ступней персонажа (`Y = -1.0`):
## [br]• `Bottom Center` (0) — нижний край спрайта стоит на уровне пола;
## [br]• `Top Center` (1) — верхний край совмещён с точкой привязки;
## [br]• `Center` (2) — центр спрайта совмещён с точкой привязки.
@export_enum("Bottom Center", "Top Center", "Center") var sprite_anchor: int = 0:
	set(val):
		sprite_anchor = val
		if is_inside_tree():
			_refresh_sprite_rig()

## Дополнительный сдвиг спрайта персонажа в пикселях относительно выбранной точки привязки (`sprite_anchor`).
@export var custom_pixel_offset: Vector2 = Vector2.ZERO:
	set(val):
		custom_pixel_offset = val
		if is_inside_tree():
			_refresh_sprite_rig()

@export_group("Material & Lighting")
## Размер одного пикселя спрайта персонажа в метрах 3D-пространства.
@export var pixel_size: float = 0.03:
	set(val):
		pixel_size = maxf(0.0005, val)
		if is_inside_tree():
			_refresh_sprite_rig()

## Если включено, спрайт персонажа реагирует на источники света и тени комнаты.
@export var shaded: bool = true:
	set(val):
		shaded = val
		if is_inside_tree():
			_refresh_sprite_rig()

## Порог альфа-отсечения (`alpha_scissor_threshold`) для чёткого силуэта и корректных теней.
@export_range(0.0, 1.0, 0.01) var alpha_scissor_threshold: float = 0.5:
	set(val):
		alpha_scissor_threshold = clampf(val, 0.0, 1.0)
		if is_inside_tree():
			_refresh_sprite_rig()

## Режим отбрасывания теней спрайтом персонажа:
## [br]• `Off` (0) — тени отключены;
## [br]• `On` (1) — односторонняя тень;
## [br]• `Double-Sided` (2) — двусторонняя силуэтная тень (рекомендуется для 2.5D-персонажей).
@export_enum("Off", "On", "Double-Sided") var shadow_casting_mode: int = 2:
	set(val):
		shadow_casting_mode = val
		if is_inside_tree():
			_refresh_sprite_rig()

## Свойство обратной совместимости для переключения силуэтных теней.
var cast_silhouette_shadows: bool = true:
	get:
		return shadow_casting_mode != 0
	set(val):
		shadow_casting_mode = 2 if val else 0

@onready var nav_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D") as NavigationAgent3D

var target_item: Node3D = null
var _facing_left: bool = false


func _ready() -> void:
	_refresh_sprite_rig()

	if Engine.is_editor_hint():
		return

	if nav_agent == null:
		nav_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D

	if snap_to_ground:
		GroundSnap.snap_after_physics_frame(self, ground_offset)


func _refresh_sprite_rig() -> void:
	if not is_inside_tree():
		return

	var capsule_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if capsule_mesh != null:
		capsule_mesh.visible = false

	var sprite_node: Sprite3D = get_node_or_null("Sprite3D") as Sprite3D
	if sprite_node == null:
		sprite_node = Sprite3D.new()
		sprite_node.name = "Sprite3D"
		add_child(sprite_node)

	var anim_sprite_node: AnimatedSprite3D = get_node_or_null("AnimatedSprite3D") as AnimatedSprite3D
	if anim_sprite_node == null:
		anim_sprite_node = AnimatedSprite3D.new()
		anim_sprite_node.name = "AnimatedSprite3D"
		add_child(anim_sprite_node)

	sprite_node.position = Vector3(0.0, -1.0, 0.0)
	anim_sprite_node.position = Vector3(0.0, -1.0, 0.0)

	var render_settings: SpriteRenderSettings = _build_render_settings()

	if sprite_frames != null:
		sprite_node.visible = false
		anim_sprite_node.visible = true
		anim_sprite_node.sprite_frames = sprite_frames
		var frame_px: Vector2 = SpriteUtils.get_frame_size(sprite_frames, "", Vector2(32.0, 64.0))
		render_settings.apply_to(anim_sprite_node, frame_px)
		_update_animation_and_facing(false)
	else:
		anim_sprite_node.visible = false
		sprite_node.visible = true
		var tex: Texture2D = sprite_texture if sprite_texture != null else PlaceholderTextures.character()
		sprite_node.texture = tex
		var frame_px: Vector2 = tex.get_size() if tex != null else Vector2(32.0, 64.0)
		render_settings.apply_to(sprite_node, frame_px)


func _build_render_settings() -> SpriteRenderSettings:
	var settings := SpriteRenderSettings.new()
	settings.pixel_size = pixel_size
	settings.flip_h = _facing_left if auto_flip_h else false
	settings.shaded = shaded
	settings.alpha_scissor_threshold = alpha_scissor_threshold
	settings.billboard_mode = billboard_mode as SpriteRenderSettings.BillboardMode
	settings.shadow_mode = shadow_casting_mode as SpriteRenderSettings.ShadowMode
	settings.anchor = sprite_anchor as SpriteRenderSettings.Anchor
	settings.pixel_offset = custom_pixel_offset
	return settings


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if global_position.y < void_fall_threshold:
		global_position.y = ground_offset
		velocity = Vector3.ZERO

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if nav_agent != null and not nav_agent.is_navigation_finished():
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		var dir: Vector3 = next_pos - global_position
		dir.y = 0.0

		if dir.length() > 0.1:
			var norm_dir: Vector3 = dir.normalized()
			velocity.x = norm_dir.x * speed
			velocity.z = norm_dir.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_try_interact_with_target()

	var horiz_vel: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var is_moving: bool = horiz_vel.length() > 0.1

	if is_moving:
		_update_camera_relative_facing(horiz_vel)

	_update_animation_and_facing(is_moving)
	move_and_slide()

	if global_position.y < void_fall_threshold:
		global_position.y = ground_offset
		velocity = Vector3.ZERO


func _try_interact_with_target() -> void:
	if target_item == null or not is_instance_valid(target_item):
		target_item = null
		return

	var dist: float = global_position.distance_to(target_item.global_position)
	var can_interact: bool = dist < interaction_distance
	if not can_interact and target_item is Area3D:
		can_interact = (target_item as Area3D).overlaps_body(self)

	if not can_interact:
		return

	if target_item.has_method("collect"):
		var item_title: String = str(target_item.get("item_name"))
		GameManager.player_inventory.append(item_title)
		target_item.call("collect")
		inventory_updated.emit()
		var room_node: Node = get_parent()
		if room_node != null and room_node.has_method("show_status_message"):
			var display_title: String = LocalizationUtils.resolve_item_name(item_title)
			room_node.call("show_status_message", LocalizationUtils.format("UI_STATUS_ITEM_OBTAINED", [display_title]))
	elif target_item.has_method("interact"):
		target_item.call("interact", self)

	target_item = null


func _update_camera_relative_facing(horiz_vel: Vector3) -> void:
	var viewport: Viewport = get_viewport()
	var active_cam: Camera3D = viewport.get_camera_3d() if viewport != null else null
	var cam_right: Vector3 = active_cam.global_transform.basis.x if active_cam != null else Vector3.RIGHT
	cam_right.y = 0.0
	if cam_right.length_squared() > 0.0001:
		cam_right = cam_right.normalized()
	var dot_right: float = horiz_vel.normalized().dot(cam_right)
	if dot_right < -0.05:
		_facing_left = true
	elif dot_right > 0.05:
		_facing_left = false


func _update_animation_and_facing(is_moving: bool) -> void:
	var sprite_node: Sprite3D = get_node_or_null("Sprite3D") as Sprite3D
	var anim_sprite_node: AnimatedSprite3D = get_node_or_null("AnimatedSprite3D") as AnimatedSprite3D

	if sprite_frames != null and anim_sprite_node != null:
		var base_anim: String = "walk" if is_moving else "idle"
		var candidates: PackedStringArray = PackedStringArray()
		if auto_flip_h:
			anim_sprite_node.flip_h = _facing_left
			candidates.append(base_anim)
		else:
			anim_sprite_node.flip_h = false
			var dir_suffix: String = "_left" if _facing_left else "_right"
			candidates.append(base_anim + dir_suffix)
			candidates.append(base_anim)

		var chosen_anim: String = SpriteUtils.resolve_animation(sprite_frames, candidates)
		SpriteUtils.play(anim_sprite_node, chosen_anim, true)
	elif sprite_node != null:
		sprite_node.flip_h = _facing_left if auto_flip_h else false


## Задаёт точку назначения для навигационного агента и сбрасывает текущую цель взаимодействия.
func move_to(target_pos: Vector3) -> void:
	target_item = null
	if nav_agent != null:
		nav_agent.target_position = target_pos


## Направляет персонажа к интерактивному объекту `item` для последующего подбора или взаимодействия.
func interact_with_item(item: Node3D) -> void:
	target_item = item
	if nav_agent != null and item != null:
		nav_agent.target_position = item.global_position
