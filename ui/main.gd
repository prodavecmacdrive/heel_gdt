class_name MainTerminalUI
extends Control
## Главный контроллер интерфейса терминала наблюдения, инвентаря игрока, системного меню и загрузки секторов (комнат).
##
## Использует [TerminalThemeBuilder] и [LocalizationUtils] для построения стилей, карточек камер,
## модального окна системного меню/настроек и мгновенного переключения языка на лету.

@export_category("Terminal UI")

@export_group("Startup & Routing")
## Путь к сцене комнаты (`*.tscn`), которая загружается по умолчанию при запуске игры из главного терминала.
@export_file("*.tscn") var default_room: String = "res://rooms/room_01.tscn"

@export_group("Inventory & Storage")
## Максимальное количество слотов в личном инвентаре игрока (по умолчанию `16`).
@export_range(1, 64, 1) var player_inventory_capacity: int = 16

## Максимальное количество слотов в окне контейнера/сундука (по умолчанию `4`).
@export_range(1, 32, 1) var chest_storage_capacity: int = 4

## Длительность отображения текстового сообщения в нижней статус-панели до начала плавного затухания (в секундах).
@export_range(0.5, 15.0, 0.1) var status_display_duration: float = 2.5

# Left Panel Nodes
@onready var cam_list: VBoxContainer = $MainLayout/LeftPanel/LeftVBox/CamScroll/CamList
@onready var cam_title_label: Label = $MainLayout/LeftPanel/LeftVBox/CamTitle
@onready var menu_btn: Button = $MainLayout/LeftPanel/LeftVBox/HeaderButtons/MenuButton
@onready var note_btn: Button = $MainLayout/LeftPanel/LeftVBox/HeaderButtons/NoteButton
@onready var map_btn: Button = $MainLayout/LeftPanel/LeftVBox/HeaderButtons/MapButton

# Center Zone Nodes
@onready var center_zone: Control = $MainLayout/CenterZone
@onready var header_label: Label = $MainLayout/CenterZone/CenterVBox/HeaderLabel
@onready var sub_viewport_container: SubViewportContainer = $MainLayout/CenterZone/CenterVBox/ViewportContainer
@onready var main_subviewport: SubViewport = $MainLayout/CenterZone/CenterVBox/ViewportContainer/MainSubViewport
@onready var room_container: Node3D = $MainLayout/CenterZone/CenterVBox/ViewportContainer/MainSubViewport/RoomContainer
@onready var chest_ui: PanelContainer = $MainLayout/CenterZone/ChestUI
@onready var chest_title_label: Label = $MainLayout/CenterZone/ChestUI/ChestVBox/ChestHeader/ChestTitle
@onready var chest_grid: GridContainer = $MainLayout/CenterZone/ChestUI/ChestVBox/ChestGrid
@onready var chest_close_btn: Button = $MainLayout/CenterZone/ChestUI/ChestVBox/ChestHeader/ChestCloseButton
@onready var status_panel: PanelContainer = $MainLayout/CenterZone/StatusPanel
@onready var status_label: Label = $MainLayout/CenterZone/StatusPanel/StatusLabel

# Right Panel Nodes
@onready var inventory_title_label: Label = $MainLayout/RightPanel/RightVBox/InventoryTitle
@onready var inventory_grid: GridContainer = $MainLayout/RightPanel/RightVBox/InventoryScroll/InventoryGrid

# Runtime State
var active_room: Node = null
var current_scene_path: String = ""
var room_cameras: Array[Camera3D] = []
var cam_cards: Array[PanelContainer] = []
var cam_card_labels: Array[Label] = []
var cam_sync_pairs: Array[Dictionary] = []
var active_cam_index: int = 0
var active_chest: Node3D = null

var player_slot_buttons: Array[Button] = []
var chest_slot_buttons: Array[Button] = []
var status_tween: Tween = null

var slot_normal_style: StyleBoxFlat = null
var slot_hover_style: StyleBoxFlat = null
var slot_pressed_style: StyleBoxFlat = null
var slot_active_style: StyleBoxFlat = null
var slot_active_hover_style: StyleBoxFlat = null

# System Menu & Settings Modal Nodes
var system_menu_backdrop: ColorRect = null
var system_menu_panel: PanelContainer = null
var menu_main_vbox: VBoxContainer = null
var menu_settings_vbox: VBoxContainer = null
var menu_title_label: Label = null
var menu_continue_btn: Button = null
var menu_settings_btn: Button = null
var menu_exit_btn: Button = null
var settings_title_label: Label = null
var settings_lang_label: Label = null
var settings_lang_option: OptionButton = null
var settings_back_btn: Button = null
var _available_locale_codes: PackedStringArray = PackedStringArray()


func _ready() -> void:
	LocalizationUtils.ensure_loaded()
	GameManager.main_ui = self
	GameManager.room_change_requested.connect(_on_room_change_requested)
	GameManager.active_item_changed.connect(func(_item: String) -> void:
		_update_active_item_highlight()
	)
	if not GameManager.locale_changed.is_connected(_on_locale_changed):
		GameManager.locale_changed.connect(_on_locale_changed)

	TerminalThemeBuilder.apply_terminal_chrome(
		$MainLayout/LeftPanel as PanelContainer,
		$MainLayout/RightPanel as PanelContainer,
		chest_ui,
		status_panel,
		header_label,
		status_label
	)

	menu_btn.pressed.connect(_toggle_system_menu)
	note_btn.pressed.connect(func() -> void:
		show_status_message(LocalizationUtils.resolve("UI_STATUS_NOTES_STUB"))
	)
	map_btn.pressed.connect(func() -> void:
		show_status_message(LocalizationUtils.resolve("UI_STATUS_MAP_STUB"))
	)

	chest_close_btn.pressed.connect(_on_chest_close_pressed)

	sub_viewport_container.mouse_exited.connect(func() -> void:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	)

	_build_inventory_slots()
	_build_chest_slots()
	_build_system_menu_modal()
	refresh_localized_ui()

	status_panel.visible = false
	status_panel.modulate.a = 0.0

	var room_to_load: String = default_room
	if not GameManager.temp_start_room_path.is_empty():
		room_to_load = GameManager.temp_start_room_path
		GameManager.temp_start_room_path = ""

	if not room_to_load.is_empty():
		load_room(room_to_load)


func _process(_delta: float) -> void:
	for pair: Dictionary in cam_sync_pairs:
		var src: Variant = pair.get("source", null)
		var prev: Variant = pair.get("preview", null)
		if src is Camera3D and prev is Camera3D and is_instance_valid(src) and is_instance_valid(prev):
			(prev as Camera3D).global_transform = (src as Camera3D).global_transform


func _on_locale_changed(_new_locale: String) -> void:
	refresh_localized_ui()


## Переводит и обновляет все надписи терминала, заголовок сектора, карточки камер, слоты инвентаря и системное меню.
func refresh_localized_ui() -> void:
	if menu_btn != null:
		menu_btn.text = LocalizationUtils.resolve("UI_BTN_MENU")
	if note_btn != null:
		note_btn.text = LocalizationUtils.resolve("UI_BTN_NOTES")
	if map_btn != null:
		map_btn.text = LocalizationUtils.resolve("UI_BTN_MAP")
	if cam_title_label != null:
		cam_title_label.text = LocalizationUtils.resolve("UI_SURVEILLANCE_TITLE")
	if inventory_title_label != null:
		inventory_title_label.text = LocalizationUtils.resolve("UI_INVENTORY_TITLE")
	if chest_title_label != null:
		chest_title_label.text = LocalizationUtils.resolve("UI_CHEST_TITLE")

	_update_sector_header_text()

	for i: int in range(cam_card_labels.size()):
		var lbl: Label = cam_card_labels[i]
		if lbl != null and is_instance_valid(lbl):
			lbl.text = LocalizationUtils.format("UI_CAM_LABEL_FORMAT", [i + 1])

	if menu_title_label != null:
		menu_title_label.text = LocalizationUtils.resolve("UI_MENU_TITLE")
	if menu_continue_btn != null:
		menu_continue_btn.text = LocalizationUtils.resolve("UI_MENU_CONTINUE")
	if menu_settings_btn != null:
		menu_settings_btn.text = LocalizationUtils.resolve("UI_MENU_SETTINGS")
	if menu_exit_btn != null:
		menu_exit_btn.text = LocalizationUtils.resolve("UI_MENU_EXIT")
	if settings_title_label != null:
		settings_title_label.text = LocalizationUtils.resolve("UI_SETTINGS_TITLE")
	if settings_lang_label != null:
		settings_lang_label.text = LocalizationUtils.resolve("UI_SETTINGS_LANGUAGE")
	if settings_back_btn != null:
		settings_back_btn.text = LocalizationUtils.resolve("UI_SETTINGS_BACK")

	_populate_language_selector()
	update_inventory_ui()
	update_chest_ui()


func _update_sector_header_text() -> void:
	if header_label == null:
		return
	if active_room == null and current_scene_path.is_empty():
		return
	var raw_sector_title: String = _resolve_raw_sector_title(active_room, current_scene_path)
	var localized_sector: String = LocalizationUtils.resolve(raw_sector_title)
	header_label.text = LocalizationUtils.format("UI_SECTOR_HEADER_FORMAT", [localized_sector])


func _build_system_menu_modal() -> void:
	if center_zone == null:
		return

	system_menu_backdrop = ColorRect.new()
	system_menu_backdrop.name = "SystemMenuBackdrop"
	system_menu_backdrop.color = Color(0.02, 0.03, 0.05, 0.78)
	system_menu_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	system_menu_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	system_menu_backdrop.visible = false
	center_zone.add_child(system_menu_backdrop)

	system_menu_panel = PanelContainer.new()
	system_menu_panel.name = "SystemMenuModal"
	system_menu_panel.custom_minimum_size = Vector2(320.0, 250.0)
	system_menu_panel.layout_mode = 1
	system_menu_panel.anchors_preset = Control.PRESET_CENTER
	system_menu_panel.anchor_left = 0.5
	system_menu_panel.anchor_top = 0.5
	system_menu_panel.anchor_right = 0.5
	system_menu_panel.anchor_bottom = 0.5
	system_menu_panel.offset_left = -160.0
	system_menu_panel.offset_top = -125.0
	system_menu_panel.offset_right = 160.0
	system_menu_panel.offset_bottom = 125.0
	system_menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	system_menu_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var modal_style: StyleBoxFlat = TerminalThemeBuilder.create_box_style(
		Color(0.07, 0.09, 0.12, 0.98),
		Color(0.25, 0.85, 0.55, 1.0),
		2,
		6,
		18.0
	)
	system_menu_panel.add_theme_stylebox_override("panel", modal_style)
	system_menu_backdrop.add_child(system_menu_panel)

	var container_stack := VBoxContainer.new()
	container_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	system_menu_panel.add_child(container_stack)

	# --- Main Menu View ---
	menu_main_vbox = VBoxContainer.new()
	menu_main_vbox.name = "MainMenuView"
	menu_main_vbox.add_theme_constant_override("separation", 12)
	container_stack.add_child(menu_main_vbox)

	menu_title_label = Label.new()
	menu_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_title_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.65))
	menu_title_label.add_theme_font_size_override("font_size", 16)
	menu_main_vbox.add_child(menu_title_label)

	var main_sep := HSeparator.new()
	menu_main_vbox.add_child(main_sep)

	menu_continue_btn = TerminalThemeBuilder.create_menu_action_button()
	menu_continue_btn.pressed.connect(close_system_menu)
	menu_main_vbox.add_child(menu_continue_btn)

	menu_settings_btn = TerminalThemeBuilder.create_menu_action_button()
	menu_settings_btn.pressed.connect(_show_settings_view)
	menu_main_vbox.add_child(menu_settings_btn)

	menu_exit_btn = TerminalThemeBuilder.create_menu_action_button()
	menu_exit_btn.pressed.connect(func() -> void:
		get_tree().quit()
	)
	menu_main_vbox.add_child(menu_exit_btn)

	# --- Settings View ---
	menu_settings_vbox = VBoxContainer.new()
	menu_settings_vbox.name = "SettingsView"
	menu_settings_vbox.visible = false
	menu_settings_vbox.add_theme_constant_override("separation", 14)
	container_stack.add_child(menu_settings_vbox)

	settings_title_label = Label.new()
	settings_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.65))
	settings_title_label.add_theme_font_size_override("font_size", 16)
	menu_settings_vbox.add_child(settings_title_label)

	var settings_sep := HSeparator.new()
	menu_settings_vbox.add_child(settings_sep)

	var lang_vbox := VBoxContainer.new()
	lang_vbox.add_theme_constant_override("separation", 6)
	menu_settings_vbox.add_child(lang_vbox)

	settings_lang_label = Label.new()
	settings_lang_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.8))
	lang_vbox.add_child(settings_lang_label)

	settings_lang_option = OptionButton.new()
	settings_lang_option.custom_minimum_size = Vector2(220.0, 36.0)
	var opt_normal: StyleBoxFlat = TerminalThemeBuilder.create_box_style(
		Color(0.11, 0.14, 0.18, 0.96),
		Color(0.28, 0.45, 0.38, 1.0),
		2,
		4,
		8.0
	)
	var opt_hover: StyleBoxFlat = TerminalThemeBuilder.create_box_style(
		Color(0.15, 0.22, 0.2, 0.98),
		Color(0.3, 0.95, 0.6, 1.0),
		2,
		4,
		8.0
	)
	settings_lang_option.add_theme_stylebox_override("normal", opt_normal)
	settings_lang_option.add_theme_stylebox_override("hover", opt_hover)
	settings_lang_option.add_theme_stylebox_override("pressed", opt_hover)
	settings_lang_option.add_theme_stylebox_override("focus", opt_hover)
	settings_lang_option.add_theme_color_override("font_color", Color(0.9, 0.96, 0.92))
	settings_lang_option.item_selected.connect(_on_language_option_selected)
	lang_vbox.add_child(settings_lang_option)

	settings_back_btn = TerminalThemeBuilder.create_menu_action_button()
	settings_back_btn.pressed.connect(_show_main_menu_view)
	menu_settings_vbox.add_child(settings_back_btn)


func _populate_language_selector() -> void:
	if settings_lang_option == null:
		return
	_available_locale_codes = LocalizationUtils.get_available_locales()
	var current_loc: String = LocalizationUtils.get_locale()

	settings_lang_option.set_block_signals(true)
	settings_lang_option.clear()
	var active_idx: int = 0
	for i: int in range(_available_locale_codes.size()):
		var code: String = _available_locale_codes[i]
		var display_name: String = LocalizationUtils.get_locale_display_name(code)
		settings_lang_option.add_item(display_name, i)
		if code == current_loc:
			active_idx = i
	if _available_locale_codes.size() > 0:
		settings_lang_option.select(active_idx)
	settings_lang_option.set_block_signals(false)


func _on_language_option_selected(index: int) -> void:
	if index < 0 or index >= _available_locale_codes.size():
		return
	var chosen_locale: String = _available_locale_codes[index]
	GameManager.set_locale(chosen_locale)


func _toggle_system_menu() -> void:
	if system_menu_backdrop == null:
		return
	if system_menu_backdrop.visible:
		close_system_menu()
	else:
		open_system_menu()


## Открывает модальное системное меню поверх центрального экрана наблюдения.
func open_system_menu() -> void:
	if system_menu_backdrop == null:
		return
	_show_main_menu_view()
	_populate_language_selector()
	system_menu_backdrop.visible = true


## Закрывает модальное системное меню и возвращает управление терминалу.
func close_system_menu() -> void:
	if system_menu_backdrop == null:
		return
	system_menu_backdrop.visible = false


func _show_main_menu_view() -> void:
	if menu_main_vbox != null:
		menu_main_vbox.visible = true
	if menu_settings_vbox != null:
		menu_settings_vbox.visible = false


func _show_settings_view() -> void:
	if menu_main_vbox != null:
		menu_main_vbox.visible = false
	if menu_settings_vbox != null:
		menu_settings_vbox.visible = true
	_populate_language_selector()


func _on_room_change_requested(scene_path: String, _door_id: String) -> void:
	load_room(scene_path)


## Загружает сцену комнаты `scene_path` внутрь 3D-окна терминала и перестраивает список камер наблюдения.
func load_room(scene_path: String) -> void:
	if scene_path.is_empty():
		if not current_scene_path.is_empty():
			scene_path = current_scene_path
		elif not default_room.is_empty():
			scene_path = default_room
		else:
			return

	if active_room != null:
		if is_instance_valid(active_room):
			room_container.remove_child(active_room)
			active_room.queue_free()
		active_room = null

	_on_room_chest_closed()

	var packed_scene: PackedScene = load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Main: Failed to load room scene at: " + scene_path)
		return

	current_scene_path = scene_path
	var new_room: Node = packed_scene.instantiate()
	active_room = new_room
	room_container.add_child(new_room)

	_update_sector_header_text()

	if new_room.has_signal("status_message_requested"):
		new_room.connect("status_message_requested", show_status_message)
	if new_room.has_signal("chest_opened"):
		new_room.connect("chest_opened", _on_room_chest_opened)
	if new_room.has_signal("chest_closed"):
		new_room.connect("chest_closed", _on_room_chest_closed)
	if new_room.has_signal("player_inventory_updated"):
		new_room.connect("player_inventory_updated", update_inventory_ui)

	var player_node: Node = new_room.get_node_or_null("Player")
	if player_node != null and player_node.has_signal("inventory_updated"):
		if not player_node.is_connected("inventory_updated", update_inventory_ui):
			player_node.connect("inventory_updated", update_inventory_ui)

	_setup_cameras()
	update_inventory_ui()


func _resolve_raw_sector_title(room_node: Node, scene_path: String) -> String:
	if room_node != null:
		if "sector_name" in room_node and not str(room_node.get("sector_name")).is_empty():
			return str(room_node.get("sector_name"))
		if "room_name" in room_node and not str(room_node.get("room_name")).is_empty():
			return str(room_node.get("room_name"))
	var base_name: String = scene_path.get_file().get_basename()
	return base_name.replace("_", " ").to_upper()


func _setup_cameras() -> void:
	for child: Node in cam_list.get_children():
		child.queue_free()
	cam_cards.clear()
	cam_card_labels.clear()
	cam_sync_pairs.clear()
	room_cameras.clear()

	if active_room == null:
		return

	if active_room.has_method("get_room_cameras"):
		var cams_from_room: Variant = active_room.call("get_room_cameras")
		if cams_from_room is Array:
			for cam: Variant in cams_from_room:
				if cam is Camera3D and not room_cameras.has(cam as Camera3D):
					room_cameras.append(cam as Camera3D)

	if room_cameras.is_empty():
		var cam_container: Node = active_room.get_node_or_null("Cameras")
		if cam_container != null:
			for child: Node in cam_container.get_children():
				if child is Camera3D and not room_cameras.has(child as Camera3D):
					room_cameras.append(child as Camera3D)

	if room_cameras.is_empty():
		var found_cams: Array[Node] = active_room.find_children("*", "Camera3D", true, false)
		for cam_node: Node in found_cams:
			if cam_node is Camera3D and not cam_node.name.begins_with("_Fallback") and not cam_node.name.begins_with("_TerminalFallback"):
				var is_excluded: bool = false
				var p: Node = cam_node.get_parent()
				while p != null and p != active_room:
					if p is SubViewport or p.name == "Player":
						is_excluded = true
						break
					p = p.get_parent()
				if not is_excluded and not room_cameras.has(cam_node as Camera3D):
					room_cameras.append(cam_node as Camera3D)

		room_cameras.sort_custom(func(a: Camera3D, b: Camera3D) -> bool:
			return a.name.naturalnocasecmp_to(b.name) < 0
		)

	if room_cameras.is_empty():
		var fallback_cam := Camera3D.new()
		fallback_cam.name = "_TerminalFallbackCamera"
		fallback_cam.position = Vector3(0.0, 12.0, 12.0)
		active_room.add_child(fallback_cam)
		fallback_cam.look_at(Vector3.ZERO, Vector3.UP)
		room_cameras.append(fallback_cam)

	var target_world: World3D = main_subviewport.find_world_3d()
	if target_world == null:
		target_world = main_subviewport.world_3d

	for i: int in range(room_cameras.size()):
		var card_info: Dictionary = TerminalThemeBuilder.create_camera_preview_card(
			room_cameras[i],
			target_world,
			i,
			select_camera
		)
		var card: PanelContainer = card_info["card"] as PanelContainer
		var preview_cam: Camera3D = card_info["preview_cam"] as Camera3D
		var card_lbl: Label = card_info.get("label", null) as Label
		cam_sync_pairs.append({
			"source": room_cameras[i],
			"preview": preview_cam,
		})
		cam_list.add_child(card)
		cam_cards.append(card)
		cam_card_labels.append(card_lbl)

	select_camera(0)


## Переключает главное окно наблюдения на камеру с индексом `index`.
func select_camera(index: int) -> void:
	if index < 0 or index >= room_cameras.size() or room_cameras[index] == null:
		return
	active_cam_index = index
	room_cameras[index].make_current()

	if active_room != null and active_room.has_method("select_camera"):
		active_room.call("select_camera", index)

	for i: int in range(cam_cards.size()):
		TerminalThemeBuilder.set_camera_card_active(cam_cards[i], i == index)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_toggle_system_menu()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_clear_active_item_selection()


func _clear_active_item_selection() -> void:
	if not GameManager.active_item.is_empty():
		GameManager.set_active_item("")
		show_status_message(LocalizationUtils.resolve("UI_STATUS_SELECTION_CLEARED"))


func _build_inventory_slots() -> void:
	for child: Node in inventory_grid.get_children():
		child.queue_free()
	player_slot_buttons.clear()

	var styles: Dictionary = TerminalThemeBuilder.create_inventory_slot_styles()
	slot_normal_style = styles["normal"] as StyleBoxFlat
	slot_hover_style = styles["hover"] as StyleBoxFlat
	slot_pressed_style = styles["pressed"] as StyleBoxFlat
	slot_active_style = styles["active"] as StyleBoxFlat
	slot_active_hover_style = styles["active_hover"] as StyleBoxFlat

	for i: int in range(player_inventory_capacity):
		var btn: Button = TerminalThemeBuilder.create_slot_button(
			slot_normal_style,
			slot_hover_style,
			slot_pressed_style,
			Color(0.9, 0.92, 0.95)
		)
		var slot_idx: int = i
		btn.pressed.connect(func() -> void:
			_on_player_slot_clicked(slot_idx)
		)
		btn.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_clear_active_item_selection()
		)
		inventory_grid.add_child(btn)
		player_slot_buttons.append(btn)


func _build_chest_slots() -> void:
	for child: Node in chest_grid.get_children():
		child.queue_free()
	chest_slot_buttons.clear()

	var styles: Dictionary = TerminalThemeBuilder.create_chest_slot_styles()
	var normal_style: StyleBoxFlat = styles["normal"] as StyleBoxFlat
	var hover_style: StyleBoxFlat = styles["hover"] as StyleBoxFlat
	var pressed_style: StyleBoxFlat = styles["pressed"] as StyleBoxFlat

	for i: int in range(chest_storage_capacity):
		var btn: Button = TerminalThemeBuilder.create_slot_button(
			normal_style,
			hover_style,
			pressed_style,
			Color(0.95, 0.9, 0.8)
		)
		var slot_idx: int = i
		btn.pressed.connect(func() -> void:
			_on_chest_slot_clicked(slot_idx)
		)
		btn.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_clear_active_item_selection()
		)
		chest_grid.add_child(btn)
		chest_slot_buttons.append(btn)


## Синхронизирует отображение слотов инвентаря с массивом `GameManager.player_inventory`,
## выводя локализованные названия предметов и подсказки (`tooltip_text`).
func update_inventory_ui() -> void:
	if not GameManager.active_item.is_empty() and not GameManager.player_inventory.has(GameManager.active_item):
		GameManager.set_active_item("")

	for i: int in range(player_slot_buttons.size()):
		var btn: Button = player_slot_buttons[i]
		if btn != null:
			if i < GameManager.player_inventory.size():
				var raw_id: String = GameManager.player_inventory[i]
				btn.text = LocalizationUtils.resolve_item_name(raw_id)
				btn.tooltip_text = LocalizationUtils.resolve_item_description(raw_id)
			else:
				btn.text = ""
				btn.tooltip_text = ""

	_update_active_item_highlight()


func _update_active_item_highlight() -> void:
	for i: int in range(player_slot_buttons.size()):
		var btn: Button = player_slot_buttons[i]
		if btn == null:
			continue
		var is_selected: bool = false
		if i < GameManager.player_inventory.size():
			var item_id: String = GameManager.player_inventory[i]
			if not item_id.is_empty() and item_id == GameManager.active_item:
				is_selected = true

		if is_selected:
			btn.add_theme_stylebox_override("normal", slot_active_style)
			btn.add_theme_stylebox_override("hover", slot_active_hover_style)
			btn.add_theme_stylebox_override("focus", slot_active_style)
			btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6))
		else:
			btn.add_theme_stylebox_override("normal", slot_normal_style)
			btn.add_theme_stylebox_override("hover", slot_hover_style)
			btn.add_theme_stylebox_override("focus", slot_hover_style)
			btn.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))


## Синхронизирует слоты открытого окна контейнера с массивом предметов `active_chest.items`,
## выводя локализованные названия предметов.
func update_chest_ui() -> void:
	if active_chest == null or not chest_ui.visible:
		return
	var items_arr: Array = []
	if active_chest.get("items") != null:
		items_arr = active_chest.get("items") as Array
	for i: int in range(chest_slot_buttons.size()):
		var btn: Button = chest_slot_buttons[i]
		if btn != null:
			if i < items_arr.size():
				var raw_id: String = str(items_arr[i])
				btn.text = LocalizationUtils.resolve_item_name(raw_id)
				btn.tooltip_text = LocalizationUtils.resolve_item_description(raw_id)
			else:
				btn.text = ""
				btn.tooltip_text = ""


func _on_player_slot_clicked(slot_index: int) -> void:
	if active_chest == null or not chest_ui.visible:
		if slot_index < GameManager.player_inventory.size():
			var item_id: String = GameManager.player_inventory[slot_index]
			if not item_id.is_empty():
				var display_item: String = LocalizationUtils.resolve_item_name(item_id)
				if GameManager.active_item == item_id:
					GameManager.set_active_item("")
					show_status_message(LocalizationUtils.format("UI_STATUS_ITEM_DESELECTED", [display_item]))
				else:
					GameManager.set_active_item(item_id)
					show_status_message(LocalizationUtils.format("UI_STATUS_ITEM_SELECTED", [display_item]))
		else:
			_clear_active_item_selection()
		return

	if slot_index < GameManager.player_inventory.size() and active_chest.get("items") != null:
		var items_arr: Array = active_chest.get("items") as Array
		if items_arr.size() < chest_storage_capacity:
			var item: String = GameManager.player_inventory.pop_at(slot_index)
			if GameManager.active_item == item:
				GameManager.set_active_item("")
			items_arr.append(item)
			if active_chest.has_method("save_chest_items"):
				active_chest.call("save_chest_items")
			update_inventory_ui()
			update_chest_ui()
			var display_item: String = LocalizationUtils.resolve_item_name(item)
			show_status_message(LocalizationUtils.format("UI_STATUS_STORED_IN_CHEST", [display_item]))
		else:
			show_status_message(LocalizationUtils.format("UI_STATUS_CHEST_FULL", [chest_storage_capacity]))


func _on_chest_slot_clicked(slot_index: int) -> void:
	if active_chest == null or not chest_ui.visible:
		return

	if active_chest.get("items") != null:
		var items_arr: Array = active_chest.get("items") as Array
		if slot_index < items_arr.size():
			if GameManager.player_inventory.size() < player_inventory_capacity:
				var item: String = str(items_arr.pop_at(slot_index))
				GameManager.player_inventory.append(item)
				if active_chest.has_method("save_chest_items"):
					active_chest.call("save_chest_items")
				update_inventory_ui()
				update_chest_ui()
				var display_item: String = LocalizationUtils.resolve_item_name(item)
				show_status_message(LocalizationUtils.format("UI_STATUS_TAKEN_FROM_CHEST", [display_item]))
			else:
				show_status_message(LocalizationUtils.format("UI_STATUS_INVENTORY_FULL", [player_inventory_capacity]))


func _on_room_chest_opened(chest_node: Node3D) -> void:
	active_chest = chest_node
	chest_ui.visible = true
	update_chest_ui()


func _on_room_chest_closed() -> void:
	chest_ui.visible = false
	active_chest = null


func _on_chest_close_pressed() -> void:
	_on_room_chest_closed()
	if active_room != null and active_room.has_method("close_chest"):
		active_room.call("close_chest")


## Отображает всплывающее сообщение в нижней части центрального экрана с автоматическим плавным исчезновением.
func show_status_message(text: String) -> void:
	if status_label == null or status_panel == null:
		return
	var resolved_text: String = LocalizationUtils.resolve(text)
	status_label.text = "> " + resolved_text
	status_panel.visible = true
	status_panel.modulate.a = 1.0

	if status_tween != null and status_tween.is_valid():
		status_tween.kill()

	status_tween = create_tween()
	status_tween.tween_interval(status_display_duration)
	status_tween.tween_property(status_panel, "modulate:a", 0.0, 0.8)
	status_tween.tween_callback(func() -> void:
		if status_panel != null and status_panel.modulate.a <= 0.01:
			status_panel.visible = false
	)
