extends Control

@export_file("*.tscn") var default_room: String = "res://rooms/room_01.tscn"

# Left Panel Nodes
@onready var cam_list: VBoxContainer = $MainLayout/LeftPanel/LeftVBox/CamScroll/CamList
@onready var menu_btn: Button = $MainLayout/LeftPanel/LeftVBox/HeaderButtons/MenuButton
@onready var note_btn: Button = $MainLayout/LeftPanel/LeftVBox/HeaderButtons/NoteButton
@onready var map_btn: Button = $MainLayout/LeftPanel/LeftVBox/HeaderButtons/MapButton

# Center Zone Nodes
@onready var header_label: Label = $MainLayout/CenterZone/CenterVBox/HeaderLabel
@onready var sub_viewport_container: SubViewportContainer = $MainLayout/CenterZone/CenterVBox/ViewportContainer
@onready var main_subviewport: SubViewport = $MainLayout/CenterZone/CenterVBox/ViewportContainer/MainSubViewport
@onready var room_container: Node3D = $MainLayout/CenterZone/CenterVBox/ViewportContainer/MainSubViewport/RoomContainer
@onready var chest_ui: PanelContainer = $MainLayout/CenterZone/ChestUI
@onready var chest_grid: GridContainer = $MainLayout/CenterZone/ChestUI/ChestVBox/ChestGrid
@onready var chest_close_btn: Button = $MainLayout/CenterZone/ChestUI/ChestVBox/ChestHeader/ChestCloseButton
@onready var status_panel: PanelContainer = $MainLayout/CenterZone/StatusPanel
@onready var status_label: Label = $MainLayout/CenterZone/StatusPanel/StatusLabel

# Right Panel Nodes
@onready var inventory_grid: GridContainer = $MainLayout/RightPanel/RightVBox/InventoryScroll/InventoryGrid

# Runtime State
var active_room: Node = null
var current_scene_path: String = ""
var room_cameras: Array[Camera3D] = []
var cam_cards: Array[PanelContainer] = []
var cam_sync_pairs: Array[Dictionary] = []
var active_cam_index: int = 0
var active_chest: Node3D = null

var player_slot_buttons: Array[Button] = []
var chest_slot_buttons: Array[Button] = []
var status_tween: Tween = null

func _ready() -> void:
	GameManager.main_ui = self
	GameManager.room_change_requested.connect(_on_room_change_requested)
	_apply_terminal_styles()

	menu_btn.pressed.connect(func() -> void:
		show_status_message("СИСТЕМА: Главное меню")
	)
	note_btn.pressed.connect(func() -> void:
		show_status_message("ЗАПИСИ: Логи терминала доступны в консоли")
	)
	map_btn.pressed.connect(func() -> void:
		show_status_message("НАВИГАЦИЯ: Схема бункера в разработке")
	)

	chest_close_btn.pressed.connect(_on_chest_close_pressed)

	sub_viewport_container.mouse_exited.connect(func() -> void:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	)

	_build_inventory_slots()
	_build_chest_slots()

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

func _on_room_change_requested(scene_path: String, _door_id: String) -> void:
	load_room(scene_path)

func load_room(scene_path: String) -> void:
	if scene_path == "":
		if current_scene_path != "":
			scene_path = current_scene_path
		elif default_room != "":
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

	var sector_title: String = ""
	if "sector_name" in new_room and str(new_room.get("sector_name")) != "":
		sector_title = str(new_room.get("sector_name"))
	elif "room_name" in new_room and str(new_room.get("room_name")) != "":
		sector_title = str(new_room.get("room_name"))
	else:
		var base_name: String = scene_path.get_file().get_basename()
		sector_title = base_name.replace("_", " ").to_upper()
	header_label.text = "[ СЕКТОР: " + sector_title + " ]"

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
		if not player_node.inventory_updated.is_connected(update_inventory_ui):
			player_node.connect("inventory_updated", update_inventory_ui)

	await get_tree().process_frame
	_setup_cameras()
	update_inventory_ui()

func _setup_cameras() -> void:
	for card: PanelContainer in cam_cards:
		if is_instance_valid(card):
			card.queue_free()
	cam_cards.clear()
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
			if cam_node is Camera3D:
				var is_excluded: bool = false
				var p: Node = cam_node.get_parent()
				while p != null and p != active_room:
					if p is SubViewport or p.name == "Player":
						is_excluded = true
						break
					p = p.get_parent()
				if not is_excluded and not room_cameras.has(cam_node as Camera3D):
					room_cameras.append(cam_node as Camera3D)

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
		var source_cam: Camera3D = room_cameras[i]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(160, 110)

		var normal_style: StyleBoxFlat = _create_slot_style(Color(0.08, 0.1, 0.12, 0.9), Color(0.25, 0.3, 0.35, 1.0))
		card.add_theme_stylebox_override("panel", normal_style)

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
		preview_cam.fov = source_cam.fov
		preview_cam.near = source_cam.near
		preview_cam.far = source_cam.far
		preview_cam.make_current()
		vp.add_child(preview_cam)

		cam_sync_pairs.append({
			"source": source_cam,
			"preview": preview_cam
		})

		var label := Label.new()
		label.text = " CAM %02d" % (i + 1)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.6))
		card.add_child(label)

		var cam_idx: int = i
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				select_camera(cam_idx)
		)

		cam_list.add_child(card)
		cam_cards.append(card)

	select_camera(0)

func select_camera(index: int) -> void:
	if index < 0 or index >= room_cameras.size() or room_cameras[index] == null:
		return
	active_cam_index = index
	room_cameras[index].make_current()

	if active_room != null and active_room.has_method("select_camera"):
		active_room.select_camera(index)

	for i: int in range(cam_cards.size()):
		if cam_cards[i] != null:
			if i == index:
				var active_style: StyleBoxFlat = _create_slot_style(Color(0.14, 0.2, 0.24, 0.95), Color(0.2, 0.85, 0.55, 1.0))
				cam_cards[i].add_theme_stylebox_override("panel", active_style)
			else:
				var normal_style: StyleBoxFlat = _create_slot_style(Color(0.08, 0.1, 0.12, 0.9), Color(0.25, 0.3, 0.35, 1.0))
				cam_cards[i].add_theme_stylebox_override("panel", normal_style)

func _build_inventory_slots() -> void:
	for child: Node in inventory_grid.get_children():
		child.queue_free()
	player_slot_buttons.clear()

	var normal_style: StyleBoxFlat = _create_slot_style(Color(0.11, 0.13, 0.16, 0.95), Color(0.25, 0.29, 0.35, 1.0))
	var hover_style: StyleBoxFlat = _create_slot_style(Color(0.16, 0.2, 0.26, 0.95), Color(0.3, 0.7, 0.9, 1.0))
	var pressed_style: StyleBoxFlat = _create_slot_style(Color(0.2, 0.25, 0.32, 0.95), Color(0.4, 0.85, 1.0, 1.0))

	for i: int in range(16):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(80, 80)
		btn.clip_text = false
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", pressed_style)
		btn.add_theme_stylebox_override("focus", hover_style)
		btn.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
		btn.add_theme_font_size_override("font_size", 12)

		var slot_idx: int = i
		btn.pressed.connect(func() -> void:
			_on_player_slot_clicked(slot_idx)
		)

		inventory_grid.add_child(btn)
		player_slot_buttons.append(btn)

func _build_chest_slots() -> void:
	for child: Node in chest_grid.get_children():
		child.queue_free()
	chest_slot_buttons.clear()

	var normal_style: StyleBoxFlat = _create_slot_style(Color(0.13, 0.15, 0.19, 0.95), Color(0.35, 0.4, 0.45, 1.0))
	var hover_style: StyleBoxFlat = _create_slot_style(Color(0.18, 0.22, 0.28, 0.95), Color(0.9, 0.7, 0.3, 1.0))
	var pressed_style: StyleBoxFlat = _create_slot_style(Color(0.22, 0.26, 0.34, 0.95), Color(1.0, 0.8, 0.4, 1.0))

	for i: int in range(4):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(80, 80)
		btn.clip_text = false
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", pressed_style)
		btn.add_theme_stylebox_override("focus", hover_style)
		btn.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
		btn.add_theme_font_size_override("font_size", 12)

		var slot_idx: int = i
		btn.pressed.connect(func() -> void:
			_on_chest_slot_clicked(slot_idx)
		)

		chest_grid.add_child(btn)
		chest_slot_buttons.append(btn)

func update_inventory_ui() -> void:
	for i: int in range(16):
		if i < player_slot_buttons.size() and player_slot_buttons[i] != null:
			if i < GameManager.player_inventory.size():
				player_slot_buttons[i].text = GameManager.player_inventory[i]
			else:
				player_slot_buttons[i].text = ""

func update_chest_ui() -> void:
	if active_chest == null or not chest_ui.visible:
		return
	var items_arr: Array = []
	if active_chest.get("items") != null:
		items_arr = active_chest.get("items") as Array
	for i: int in range(4):
		if i < chest_slot_buttons.size() and chest_slot_buttons[i] != null:
			if i < items_arr.size():
				chest_slot_buttons[i].text = str(items_arr[i])
			else:
				chest_slot_buttons[i].text = ""

func _on_player_slot_clicked(slot_index: int) -> void:
	if active_chest == null or not chest_ui.visible:
		if slot_index < GameManager.player_inventory.size():
			show_status_message("Предмет: " + GameManager.player_inventory[slot_index])
		return

	if slot_index < GameManager.player_inventory.size() and active_chest.get("items") != null:
		var items_arr: Array = active_chest.get("items") as Array
		if items_arr.size() < 4:
			var item: String = GameManager.player_inventory.pop_at(slot_index)
			items_arr.append(item)
			if active_chest.has_method("save_chest_items"):
				active_chest.save_chest_items()
			update_inventory_ui()
			update_chest_ui()
			show_status_message("Помещено в сундук: " + item)
		else:
			show_status_message("Сундук полон (макс. 4 предмета)")

func _on_chest_slot_clicked(slot_index: int) -> void:
	if active_chest == null or not chest_ui.visible:
		return

	if active_chest.get("items") != null:
		var items_arr: Array = active_chest.get("items") as Array
		if slot_index < items_arr.size():
			if GameManager.player_inventory.size() < 16:
				var item: String = str(items_arr.pop_at(slot_index))
				GameManager.player_inventory.append(item)
				if active_chest.has_method("save_chest_items"):
					active_chest.save_chest_items()
				update_inventory_ui()
				update_chest_ui()
				show_status_message("Взято из сундука: " + item)
			else:
				show_status_message("Инвентарь полон (макс. 16 предметов)")

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
		active_room.close_chest()

func show_status_message(text: String) -> void:
	if status_label == null or status_panel == null:
		return
	status_label.text = "> " + text
	status_panel.visible = true
	status_panel.modulate.a = 1.0

	if status_tween != null and status_tween.is_valid():
		status_tween.kill()

	status_tween = create_tween()
	status_tween.tween_interval(2.5)
	status_tween.tween_property(status_panel, "modulate:a", 0.0, 0.8)
	status_tween.tween_callback(func() -> void:
		if status_panel != null and status_panel.modulate.a <= 0.01:
			status_panel.visible = false
	)

func _create_slot_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style

func _apply_terminal_styles() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.08, 0.1, 0.96)
	panel_style.border_color = Color(0.2, 0.24, 0.28, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(8.0)

	var left_panel: PanelContainer = $MainLayout/LeftPanel as PanelContainer
	var right_panel: PanelContainer = $MainLayout/RightPanel as PanelContainer
	if left_panel != null:
		left_panel.add_theme_stylebox_override("panel", panel_style)
	if right_panel != null:
		right_panel.add_theme_stylebox_override("panel", panel_style)

	var chest_style := StyleBoxFlat.new()
	chest_style.bg_color = Color(0.09, 0.1, 0.13, 0.98)
	chest_style.border_color = Color(0.35, 0.4, 0.48, 1.0)
	chest_style.set_border_width_all(2)
	chest_style.set_corner_radius_all(6)
	chest_style.set_content_margin_all(12.0)
	if chest_ui != null:
		chest_ui.add_theme_stylebox_override("panel", chest_style)

	var status_style := StyleBoxFlat.new()
	status_style.bg_color = Color(0.05, 0.07, 0.09, 0.9)
	status_style.border_color = Color(0.2, 0.5, 0.35, 0.9)
	status_style.set_border_width_all(1)
	status_style.set_corner_radius_all(4)
	status_style.set_content_margin_all(6.0)
	if status_panel != null:
		status_panel.add_theme_stylebox_override("panel", status_style)

	header_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.6))
	status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
