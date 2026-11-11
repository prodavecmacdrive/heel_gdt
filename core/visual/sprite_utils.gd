@tool
class_name SpriteUtils
extends RefCounted
## Вспомогательные функции для [SpriteFrames], текстур-атласов и [AnimatedSprite3D].

## Размер кадра по умолчанию, если определить его не удалось.
const DEFAULT_FRAME_SIZE: Vector2 = Vector2(64.0, 64.0)


## Возвращает первое существующее в [param frames] имя анимации из [param candidates].
## [br]Если ни одно не найдено — [code]"default"[/code] или первую доступную анимацию.
## Пустая строка означает, что анимаций нет совсем.
static func resolve_animation(frames: SpriteFrames, candidates: PackedStringArray) -> String:
	if frames == null:
		return ""
	for anim_name: String in candidates:
		if not anim_name.is_empty() and frames.has_animation(anim_name):
			return anim_name
	if frames.has_animation(&"default"):
		return "default"
	var names: PackedStringArray = frames.get_animation_names()
	return names[0] if not names.is_empty() else ""


## Размер первого кадра анимации [param anim_name] (или первой непустой анимации).
static func get_frame_size(frames: SpriteFrames, anim_name: String = "", fallback: Vector2 = DEFAULT_FRAME_SIZE) -> Vector2:
	if frames == null:
		return fallback
	var ordered: PackedStringArray = PackedStringArray()
	if not anim_name.is_empty():
		ordered.append(anim_name)
	ordered.append_array(frames.get_animation_names())
	for candidate: String in ordered:
		if frames.has_animation(candidate) and frames.get_frame_count(candidate) > 0:
			var tex: Texture2D = frames.get_frame_texture(candidate, 0)
			if tex != null:
				return tex.get_size()
	return fallback


## Размер одного кадра текстуры-атласа, разрезанной на [param hframes] × [param vframes].
static func get_atlas_frame_size(texture: Texture2D, hframes: int, vframes: int, fallback: Vector2 = DEFAULT_FRAME_SIZE) -> Vector2:
	if texture == null:
		return fallback
	return Vector2(
		float(texture.get_width()) / float(maxi(1, hframes)),
		float(texture.get_height()) / float(maxi(1, vframes))
	)


## Запускает [param anim_name] на [param sprite], не перезапуская уже играющую анимацию.
## [br]При [param autoplay] = false анимация выбирается, но воспроизведение останавливается.
static func play(sprite: AnimatedSprite3D, anim_name: String, autoplay: bool = true) -> void:
	if sprite == null or sprite.sprite_frames == null or anim_name.is_empty():
		return
	if not sprite.sprite_frames.has_animation(anim_name):
		return
	if not autoplay:
		sprite.animation = anim_name
		sprite.stop()
		return
	if String(sprite.animation) != anim_name or not sprite.is_playing():
		sprite.play(anim_name)

