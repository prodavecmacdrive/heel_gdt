class_name TerminalThemeBuilder
extends RefCounted
## Фабрика визуальных стилей (`StyleBoxFlat`) и UI-виджетов для главного терминала ([MainTerminalUI]).
##
## Изолирует конструирование тем оформления, слотов инвентаря/сундука и карточек
## камер видеонаблюдения от логики управления состоянием интерфейса.


## Создаёт базовый прямоугольный стиль со скруглёнными углами и рамкой.
static func create_box_style(
	bg: Color,
	border: Color,
	border_width: int = 2,
	corner_radius: int = 4,
	content_margin: float = -1.0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	if content_margin >= 0.0:
		style.set_content_margin_all(content_margin)
	return style


## Возвращает набор стилей для слотов инвентаря игрока.
static func create_inventory_slot_styles() -> Dictionary:
	return {
		"normal": create_box_style(Color(0.11, 0.13, 0.16, 0.95), Color(0.25, 0.29, 0.35, 1.0), 2, 4),
		"hover": create_box_style(Color(0.15, 0.18, 0.2, 0.9), Color(0.2, 0.95, 0.55, 1.0), 1, 3),
		"pressed": create_box_style(Color(0.08, 0.1, 0.12, 0.95), Color(0.2, 0.95, 0.55, 1.0), 2, 3),
		"active": create_box_style(Color(0.12, 0.22, 0.18, 0.98), Color(0.2, 0.95, 0.55, 1.0), 2, 4),
		"active_hover": create_box_style(Color(0.16, 0.28, 0.22, 0.98), Color(0.4, 1.0, 0.7, 1.0), 2, 4),
	}


## Возвращает набор стилей для слотов контейнера (сундука).
static func create_chest_slot_styles() -> Dictionary:
	return {
		"normal": create_box_style(Color(0.13, 0.15, 0.19, 0.95), Color(0.35, 0.4, 0.45, 1.0), 2, 4),
		"hover": create_box_style(Color(0.18, 0.22, 0.28, 0.95), Color(0.9, 0.7, 0.3, 1.0), 2, 4),
		"pressed": create_box_style(Color(0.22, 0.26, 0.34, 0.95), Color(1.0, 0.8, 0.4, 1.0), 2, 4),
	}


## Применяет фирменное оформление терминала к основным панелям и заголовкам.
static func apply_terminal_chrome(
	left_panel: PanelContainer,
	right_panel: PanelContainer,
	chest_ui: PanelContainer,
	status_panel: PanelContainer,
	header_label: Label,
	status_label: Label
) -> void:
	var side_panel_style: StyleBoxFlat = create_box_style(
		Color(0.07, 0.08, 0.1, 0.96),
		Color(0.2, 0.24, 0.28, 1.0),
		1,
		0,
		8.0
	)
	if left_panel != null:
		left_panel.add_theme_stylebox_override("panel", side_panel_style)
	if right_panel != null:
		right_panel.add_theme_stylebox_override("panel", side_panel_style)

	if chest_ui != null:
		var chest_style: StyleBoxFlat = create_box_style(
			Color(0.09, 0.1, 0.13, 0.98),
			Color(0.35, 0.4, 0.48, 1.0),
			2,
			6,
			12.0
		)
		chest_ui.add_theme_stylebox_override("panel", chest_style)

	if status_panel != null:
		var status_style: StyleBoxFlat = create_box_style(
			Color(0.05, 0.07, 0.09, 0.9),
			Color(0.2, 0.5, 0.35, 0.9),
			1,
			4,
			6.0
		)
		status_panel.add_theme_stylebox_override("panel", status_style)

	if header_label != null:
		header_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.6))
	if status_label != null:
		status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))


## Создаёт кнопку слота для сетки инвентаря или сундука.
static func create_slot_button(
	normal_style: StyleBoxFlat,
	hover_style: StyleBoxFlat,
	pressed_style: StyleBoxFlat,
	font_color: Color,
	min_size: Vector2 = Vector2(80.0, 80.0)
) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = min_size
	btn.clip_text = false
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("focus", hover_style)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_font_size_override("font_size", 12)
	return btn


## Создаёт карточку предпросмотра камеры наблюдения с собственным `SubViewport`.
## Возвращает словарь `{"card": PanelContainer, "preview_cam": Camera3D}`.
static func create_camera_preview_card(
	source_cam: Camera3D,
	target_world: World3D,
	cam_index: int,
	on_selected: Callable
) -> Dictionary:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(160.0, 110.0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_camera_card_active(card, false)

	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vpc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(vpc)

	var vp := SubViewport.new()
	vp.own_world_3d = false
	if target_world != null:
		vp.world_3d = target_world
	vp.handle_input_locally = false
	vp.size = Vector2i(160, 110)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vpc.add_child(vp)

	var preview_cam := Camera3D.new()
	preview_cam.global_transform = source_cam.global_transform
	preview_cam.projection = source_cam.projection
	preview_cam.fov = source_cam.fov
	preview_cam.size = source_cam.size
	preview_cam.near = source_cam.near
	preview_cam.far = source_cam.far
	preview_cam.keep_aspect = source_cam.keep_aspect
	preview_cam.make_current()
	vp.add_child(preview_cam)

	var label := Label.new()
	label.name = "CamLabel"
	label.text = LocalizationUtils.format("UI_CAM_LABEL_FORMAT", [cam_index + 1])
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.6))
	card.add_child(label)

	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			on_selected.call(cam_index)
	)

	return {
		"card": card,
		"preview_cam": preview_cam,
		"label": label,
	}


## Обновляет рамку карточки камеры (активная/обычная).
static func set_camera_card_active(card: PanelContainer, is_active: bool) -> void:
	if card == null:
		return
	var style: StyleBoxFlat = null
	if is_active:
		style = create_box_style(Color(0.14, 0.2, 0.24, 0.95), Color(0.2, 0.85, 0.55, 1.0), 2, 4)
	else:
		style = create_box_style(Color(0.08, 0.1, 0.12, 0.9), Color(0.25, 0.3, 0.35, 1.0), 2, 4)
	card.add_theme_stylebox_override("panel", style)


## Создаёт кнопку в фирменном нуарном стиле системного меню терминала.
static func create_menu_action_button(min_height: float = 38.0) -> Button:
	var normal_style: StyleBoxFlat = create_box_style(
		Color(0.11, 0.14, 0.18, 0.96),
		Color(0.26, 0.34, 0.4, 1.0),
		2,
		4,
		8.0
	)
	var hover_style: StyleBoxFlat = create_box_style(
		Color(0.15, 0.22, 0.2, 0.98),
		Color(0.25, 0.95, 0.6, 1.0),
		2,
		4,
		8.0
	)
	var pressed_style: StyleBoxFlat = create_box_style(
		Color(0.08, 0.12, 0.11, 0.98),
		Color(0.4, 1.0, 0.7, 1.0),
		2,
		4,
		8.0
	)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(220.0, min_height)
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("focus", hover_style)
	btn.add_theme_color_override("font_color", Color(0.88, 0.94, 0.9))
	btn.add_theme_color_override("font_hover_color", Color(0.4, 1.0, 0.7))
	btn.add_theme_font_size_override("font_size", 14)
	return btn

