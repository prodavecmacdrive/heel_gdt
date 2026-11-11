@tool
class_name SpriteRenderSettings
extends RefCounted
## Набор параметров отрисовки 2.5D-спрайта и их применение к [SpriteBase3D].
##
## Используется [QuestInteractable] и [Player], чтобы оба типа сущностей рисовали
## спрайты одинаково: пиксельная фильтрация, альфа-отсечение, тени-силуэты,
## биллборд и привязка (anchor) к точке опоры.

## Режим поворота спрайта к камере.
enum BillboardMode {
	Y_BILLBOARD,    ## Поворот только вокруг вертикальной оси Y (персонажи и стоящие предметы).
	FIXED,          ## Без поворота: спрайт ориентирован трансформацией узла (декали, плакаты).
	FULL_BILLBOARD, ## Полный поворот к камере по всем осям (частицы, иконки).
}

## Режим отбрасывания теней.
enum ShadowMode {
	OFF,          ## Тени не отбрасываются.
	ON,           ## Тень отбрасывается только лицевой стороной.
	DOUBLE_SIDED, ## Тень-силуэт с обеих сторон (рекомендуется для билбордов).
}

## Точка привязки спрайта к началу координат узла.
enum Anchor {
	BOTTOM_CENTER, ## Нижний центр — «ноги» стоят на полу в точке узла.
	TOP_CENTER,    ## Верхний центр — спрайт свисает вниз (люстры, вывески).
	CENTER,        ## Центр изображения совпадает с точкой узла.
}

var pixel_size: float = 0.01
var flip_h: bool = false
var shaded: bool = true
var alpha_scissor_threshold: float = 0.5
var billboard_mode: BillboardMode = BillboardMode.Y_BILLBOARD
var shadow_mode: ShadowMode = ShadowMode.DOUBLE_SIDED
var anchor: Anchor = Anchor.BOTTOM_CENTER
var pixel_offset: Vector2 = Vector2.ZERO


## Применяет все параметры к [param sprite]. [param frame_size_px] — размер одного
## кадра в пикселях (нужен для вычисления смещения привязки).
func apply_to(sprite: SpriteBase3D, frame_size_px: Vector2) -> void:
	sprite.pixel_size = pixel_size
	sprite.flip_h = flip_h
	sprite.shaded = shaded
	sprite.double_sided = true
	sprite.centered = true
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.alpha_scissor_threshold = alpha_scissor_threshold
	sprite.cast_shadow = to_shadow_setting(shadow_mode)
	sprite.billboard = to_billboard(billboard_mode)
	sprite.offset = compute_offset(frame_size_px)


## Смещение спрайта в пикселях с учётом привязки и пользовательского сдвига.
func compute_offset(frame_size_px: Vector2) -> Vector2:
	var base: Vector2 = Vector2.ZERO
	match anchor:
		Anchor.BOTTOM_CENTER:
			base = Vector2(0.0, frame_size_px.y * 0.5)
		Anchor.TOP_CENTER:
			base = Vector2(0.0, -frame_size_px.y * 0.5)
	return base + pixel_offset


## Локальные границы спрайта (в метрах) для генерации коллизий.
## [param depth] — толщина коробки по оси Z.
func compute_local_bounds(frame_size_px: Vector2, depth: float) -> AABB:
	var size: Vector3 = Vector3(frame_size_px.x * pixel_size, frame_size_px.y * pixel_size, depth)
	var offset_px: Vector2 = compute_offset(frame_size_px)
	var center: Vector3 = Vector3(offset_px.x * pixel_size, offset_px.y * pixel_size, 0.0)
	return AABB(center - size * 0.5, size)


static func to_billboard(mode: BillboardMode) -> BaseMaterial3D.BillboardMode:
	match mode:
		BillboardMode.FIXED:
			return BaseMaterial3D.BILLBOARD_DISABLED
		BillboardMode.FULL_BILLBOARD:
			return BaseMaterial3D.BILLBOARD_ENABLED
	return BaseMaterial3D.BILLBOARD_FIXED_Y


static func to_shadow_setting(mode: ShadowMode) -> GeometryInstance3D.ShadowCastingSetting:
	match mode:
		ShadowMode.OFF:
			return GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ShadowMode.ON:
			return GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED

