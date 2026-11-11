@tool
class_name PlaceholderTextures
extends RefCounted
## Процедурные текстуры-заглушки для сущностей без назначенной графики.
##
## Текстуры кешируются в статических переменных и создаются один раз за сессию.

static var _character_cache: ImageTexture = null


## Пиксельный силуэт космонавта 32×64 (ноги в нижнем ряду, визор смотрит вправо).
static func character() -> ImageTexture:
	if _character_cache == null:
		_character_cache = _build_character()
	return _character_cache


static func _build_character() -> ImageTexture:
	var img: Image = Image.create(32, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	var outline: Color = Color(0.08, 0.1, 0.14, 1.0)
	var helmet: Color = Color(0.28, 0.36, 0.44, 1.0)
	var visor: Color = Color(0.2, 0.95, 0.85, 1.0)
	var suit: Color = Color(0.85, 0.48, 0.18, 1.0)
	var pack: Color = Color(0.22, 0.25, 0.3, 1.0)
	var belt: Color = Color(0.16, 0.18, 0.22, 1.0)
	var badge: Color = Color(0.25, 0.95, 0.45, 1.0)
	var legs: Color = Color(0.2, 0.24, 0.3, 1.0)
	var boots: Color = Color(0.12, 0.14, 0.18, 1.0)

	_outlined_rect(img, Rect2i(10, 4, 13, 15), helmet, outline)  # Шлем
	_fill_rect(img, Rect2i(15, 8, 7, 6), visor)                   # Визор
	_outlined_rect(img, Rect2i(5, 20, 4, 17), pack, outline, true) # Рюкзак (без правой рамки)
	_outlined_rect(img, Rect2i(9, 19, 15, 23), suit, outline)     # Торс
	_fill_rect(img, Rect2i(10, 37, 13, 4), belt)                  # Пояс
	_fill_rect(img, Rect2i(17, 23, 4, 4), badge)                  # Нашивка
	_vertical_outlined(img, Rect2i(10, 42, 6, 15), legs, outline) # Левая нога
	_vertical_outlined(img, Rect2i(17, 42, 6, 15), legs, outline) # Правая нога
	_fill_rect(img, Rect2i(10, 57, 14, 7), boots)                 # Ботинки

	return ImageTexture.create_from_image(img)


static func _fill_rect(img: Image, rect: Rect2i, color: Color) -> void:
	img.fill_rect(rect, color)


static func _outlined_rect(img: Image, rect: Rect2i, fill: Color, outline: Color, open_right: bool = false) -> void:
	img.fill_rect(rect, outline)
	var inner: Rect2i = rect.grow_individual(-1, -1, 0 if open_right else -1, -1)
	if inner.size.x > 0 and inner.size.y > 0:
		img.fill_rect(inner, fill)


static func _vertical_outlined(img: Image, rect: Rect2i, fill: Color, outline: Color) -> void:
	img.fill_rect(rect, outline)
	var inner: Rect2i = rect.grow_individual(-1, 0, -1, 0)
	if inner.size.x > 0:
		img.fill_rect(inner, fill)

