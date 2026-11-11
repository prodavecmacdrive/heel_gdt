@tool
class_name InteractableVisualRig
extends RefCounted
## Модуль управления визуальным представлением интерактивного объекта ([QuestInteractable]).
##
## Отвечает исключительно за создание, настройку и переключение внутренних визуальных узлов
## ([Sprite3D], [AnimatedSprite3D], [MeshInstance3D]), а также за расчёт их габаритов (AABB)
## для генератора коллизий и навигационных препятствий.

const INTERNAL_SPRITE_NAME: String = "_VisualSprite3D"
const INTERNAL_ANIM_SPRITE_NAME: String = "_VisualAnimatedSprite3D"
const INTERNAL_MESH_NAME: String = "_VisualMesh3D"
const MIN_BOUNDS_SIZE: Vector3 = Vector3(0.5, 0.5, 0.5)

## Режим визуального отображения объекта.
enum VisualMode {
	EXTERNAL_CUSTOM = 0, ## Используются дочерние или родительские узлы сцены, созданные вручную.
	SPRITE_2D = 1,       ## Внутренний 2D-спрайт ([Sprite3D]) или покадровая анимация ([AnimatedSprite3D]).
	MESH_3D = 2,         ## Внутренний 3D-меш ([MeshInstance3D]) на основе ресурса [Mesh].
}


## Синхронизирует внутренние визуальные узлы [param host] в соответствии с выбранным режимом.
static func refresh_visuals(
	host: Node3D,
	visual_mode: int,
	mesh_resource: Mesh,
	mesh_material_override: Material,
	sprite_texture: Texture2D,
	hframes: int,
	vframes: int,
	frame: int,
	sprite_frames: SpriteFrames,
	render_settings: SpriteRenderSettings,
	current_state: String,
	default_anim: String,
	active_anim: String,
	auto_play_anim: bool
) -> void:
	if host == null or not host.is_inside_tree():
		return

	var sprite_node: Sprite3D = host.get_node_or_null(INTERNAL_SPRITE_NAME) as Sprite3D
	var anim_sprite_node: AnimatedSprite3D = host.get_node_or_null(INTERNAL_ANIM_SPRITE_NAME) as AnimatedSprite3D
	var mesh_node: MeshInstance3D = host.get_node_or_null(INTERNAL_MESH_NAME) as MeshInstance3D

	if visual_mode == VisualMode.EXTERNAL_CUSTOM:
		if sprite_node != null:
			sprite_node.visible = false
		if anim_sprite_node != null:
			anim_sprite_node.visible = false
		if mesh_node != null:
			mesh_node.visible = false
		return

	if visual_mode == VisualMode.SPRITE_2D:
		if mesh_node != null:
			mesh_node.visible = false

		var frame_px: Vector2 = compute_sprite_pixel_size(
			sprite_frames,
			sprite_texture,
			hframes,
			vframes,
			current_state,
			default_anim,
			active_anim
		)

		if sprite_frames != null:
			if sprite_node != null:
				sprite_node.visible = false
			if anim_sprite_node == null:
				anim_sprite_node = AnimatedSprite3D.new()
				anim_sprite_node.name = INTERNAL_ANIM_SPRITE_NAME
				host.add_child(anim_sprite_node)
			anim_sprite_node.visible = true
			anim_sprite_node.sprite_frames = sprite_frames
			render_settings.apply_to(anim_sprite_node, frame_px)
			update_sprite_animation(
				host,
				visual_mode,
				sprite_frames,
				current_state,
				default_anim,
				active_anim,
				auto_play_anim,
				render_settings,
				sprite_texture,
				hframes,
				vframes
			)
		else:
			if anim_sprite_node != null:
				anim_sprite_node.visible = false
			if sprite_node == null:
				sprite_node = Sprite3D.new()
				sprite_node.name = INTERNAL_SPRITE_NAME
				host.add_child(sprite_node)
			sprite_node.visible = true
			sprite_node.texture = sprite_texture
			sprite_node.hframes = maxi(1, hframes)
			sprite_node.vframes = maxi(1, vframes)
			var max_frames: int = sprite_node.hframes * sprite_node.vframes
			sprite_node.frame = clampi(frame, 0, maxi(0, max_frames - 1))
			render_settings.apply_to(sprite_node, frame_px)
		return

	if visual_mode == VisualMode.MESH_3D:
		if sprite_node != null:
			sprite_node.visible = false
		if anim_sprite_node != null:
			anim_sprite_node.visible = false
		if mesh_node == null:
			mesh_node = MeshInstance3D.new()
			mesh_node.name = INTERNAL_MESH_NAME
			host.add_child(mesh_node)
		mesh_node.visible = true
		mesh_node.mesh = mesh_resource
		mesh_node.material_override = mesh_material_override
		mesh_node.cast_shadow = SpriteRenderSettings.to_shadow_setting(render_settings.shadow_mode)


## Обновляет активную анимацию [AnimatedSprite3D] при смене состояния объекта.
static func update_sprite_animation(
	host: Node3D,
	visual_mode: int,
	sprite_frames: SpriteFrames,
	current_state: String,
	default_anim: String,
	active_anim: String,
	auto_play_anim: bool,
	render_settings: SpriteRenderSettings,
	sprite_texture: Texture2D,
	hframes: int,
	vframes: int
) -> void:
	if host == null or visual_mode != VisualMode.SPRITE_2D or sprite_frames == null:
		return
	var anim_sprite_node: AnimatedSprite3D = host.get_node_or_null(INTERNAL_ANIM_SPRITE_NAME) as AnimatedSprite3D
	if anim_sprite_node == null:
		return

	var candidates: PackedStringArray = PackedStringArray()
	if current_state == "active" and not active_anim.is_empty():
		candidates.append(active_anim)
	candidates.append(default_anim)

	var target_anim: String = SpriteUtils.resolve_animation(sprite_frames, candidates)
	SpriteUtils.play(anim_sprite_node, target_anim, auto_play_anim)

	var px_size: Vector2 = compute_sprite_pixel_size(
		sprite_frames,
		sprite_texture,
		hframes,
		vframes,
		current_state,
		default_anim,
		active_anim
	)
	anim_sprite_node.offset = render_settings.compute_offset(px_size)


## Вычисляет размер текущего кадра спрайта в пикселях.
static func compute_sprite_pixel_size(
	sprite_frames: SpriteFrames,
	sprite_texture: Texture2D,
	hframes: int,
	vframes: int,
	current_state: String,
	default_anim: String,
	active_anim: String
) -> Vector2:
	if sprite_frames != null:
		var candidates: PackedStringArray = PackedStringArray()
		if current_state == "active" and not active_anim.is_empty():
			candidates.append(active_anim)
		candidates.append(default_anim)
		var resolved_anim: String = SpriteUtils.resolve_animation(sprite_frames, candidates)
		return SpriteUtils.get_frame_size(sprite_frames, resolved_anim)

	if sprite_texture != null:
		return SpriteUtils.get_atlas_frame_size(sprite_texture, hframes, vframes)

	return SpriteUtils.DEFAULT_FRAME_SIZE


## Возвращает словарь `{"size": Vector3, "center": Vector3}` с локальными габаритами визуала.
## Гарантирует минимальный размер `Vector3(0.5, 0.5, 0.5)` по каждой оси.
static func compute_visual_bounds(
	host: Node3D,
	visual_mode: int,
	mesh_resource: Mesh,
	sprite_frames: SpriteFrames,
	sprite_texture: Texture2D,
	hframes: int,
	vframes: int,
	current_state: String,
	default_anim: String,
	active_anim: String,
	render_settings: SpriteRenderSettings
) -> Dictionary:
	if visual_mode == VisualMode.SPRITE_2D:
		var px_size: Vector2 = compute_sprite_pixel_size(
			sprite_frames,
			sprite_texture,
			hframes,
			vframes,
			current_state,
			default_anim,
			active_anim
		)
		var w: float = maxf(MIN_BOUNDS_SIZE.x, px_size.x * render_settings.pixel_size)
		var h: float = maxf(MIN_BOUNDS_SIZE.y, px_size.y * render_settings.pixel_size)
		var d: float = MIN_BOUNDS_SIZE.z
		var offset_px: Vector2 = render_settings.compute_offset(px_size)
		var center: Vector3 = Vector3(
			offset_px.x * render_settings.pixel_size,
			offset_px.y * render_settings.pixel_size,
			0.0
		)
		return {"size": Vector3(w, h, d), "center": center}

	if visual_mode == VisualMode.MESH_3D:
		if mesh_resource != null:
			var aabb: AABB = mesh_resource.get_aabb()
			if aabb.size.length_squared() > 0.0001:
				var sz: Vector3 = Vector3(
					maxf(MIN_BOUNDS_SIZE.x, aabb.size.x),
					maxf(MIN_BOUNDS_SIZE.y, aabb.size.y),
					maxf(MIN_BOUNDS_SIZE.z, aabb.size.z)
				)
				return {"size": sz, "center": aabb.get_center()}
		return {"size": MIN_BOUNDS_SIZE, "center": Vector3.ZERO}

	if host == null:
		return {"size": MIN_BOUNDS_SIZE, "center": Vector3.ZERO}

	# EXTERNAL_CUSTOM: 1. Проверяем дочерние MeshInstance3D внутри самого узла
	var own_meshes: Array[Node] = host.find_children("*", "MeshInstance3D", true, false)
	for m_node: Node in own_meshes:
		if m_node is MeshInstance3D and m_node.name != INTERNAL_MESH_NAME:
			var m_inst: MeshInstance3D = m_node as MeshInstance3D
			var aabb: AABB = m_inst.get_aabb()
			if aabb.size.length_squared() > 0.0001:
				var sz: Vector3 = Vector3(
					maxf(MIN_BOUNDS_SIZE.x, aabb.size.x),
					maxf(MIN_BOUNDS_SIZE.y, aabb.size.y),
					maxf(MIN_BOUNDS_SIZE.z, aabb.size.z)
				)
				return {"size": sz, "center": aabb.get_center()}

	# EXTERNAL_CUSTOM: 2. Проверяем родительский или соседний MeshInstance3D
	var mesh_inst: MeshInstance3D = null
	var parent_node: Node = host.get_parent()
	if parent_node is MeshInstance3D:
		mesh_inst = parent_node as MeshInstance3D
	elif parent_node != null:
		for child: Node in parent_node.get_children():
			if child is MeshInstance3D and child.name != INTERNAL_MESH_NAME:
				mesh_inst = child as MeshInstance3D
				break

	var target_size: Vector3 = MIN_BOUNDS_SIZE
	var target_pos: Vector3 = Vector3.ZERO

	if mesh_inst != null:
		var aabb: AABB = mesh_inst.get_aabb()
		if aabb.size.length_squared() > 0.0001:
			target_size = Vector3(
				maxf(MIN_BOUNDS_SIZE.x, aabb.size.x),
				maxf(MIN_BOUNDS_SIZE.y, aabb.size.y),
				maxf(MIN_BOUNDS_SIZE.z, aabb.size.z)
			)
			target_pos = aabb.get_center()
			if parent_node == mesh_inst:
				target_pos -= host.position
			else:
				target_pos = (mesh_inst.position + aabb.get_center()) - host.position

	return {"size": target_size, "center": target_pos}

