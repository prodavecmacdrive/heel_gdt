@tool
class_name QuestRegistryPanel
extends Control
## Визуальная панель редактора Godot ("Quest Registry") для управления единым реестром предметов,
## глобальных флагов, постоянных `object_id` и аудита квестовых связей во всех сценах проекта.

signal navigate_to_scene_node_requested(scene_path: String, node_path: String)
signal inspect_registry_resource_requested

const COLOR_OK: Color = Color(0.3, 0.9, 0.55)
const COLOR_ERROR: Color = Color(1.0, 0.35, 0.35)
const COLOR_WARNING: Color = Color(1.0, 0.78, 0.25)
const COLOR_MUTED: Color = Color(0.65, 0.72, 0.78)

var _summary_label: Label = null
var _tabs: TabContainer = null

var _items_tree: Tree = null
var _item_id_input: LineEdit = null
var _item_name_input: LineEdit = null
var _item_cat_option: OptionButton = null
var _item_desc_input: LineEdit = null

var _flags_tree: Tree = null
var _flag_id_input: LineEdit = null
var _flag_default_check: CheckBox = null
var _flag_cat_option: OptionButton = null
var _flag_desc_input: LineEdit = null

var _objects_tree: Tree = null
var _issues_tree: Tree = null

var _last_audit_report: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 280.0)
	_build_ui()
	refresh_all(true)


## Перезагружает данные из [QuestRegistry], запускает аудит проекта и обновляет все таблицы интерфейса.
func refresh_all(run_audit: bool = true) -> void:
	if _items_tree == null:
		return
	if run_audit or _last_audit_report.is_empty():
		_last_audit_report = QuestValidator.audit_project()

	_populate_items_tree()
	_populate_flags_tree()
	_populate_objects_tree()
	_populate_issues_tree()
	_update_summary_badge()


func _build_ui() -> void:
	for child: Node in get_children():
		child.queue_free()

	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 6)
	add_child(root_vbox)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	root_vbox.add_child(toolbar)

	var title_lbl := Label.new()
	title_lbl.text = " [ ЕДИНЫЙ РЕЕСТР КВЕСТОВ & ВАЛИДАТОР ] "
	title_lbl.add_theme_color_override("font_color", COLOR_OK)
	toolbar.add_child(title_lbl)

	_summary_label = Label.new()
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_label.add_theme_color_override("font_color", COLOR_MUTED)
	toolbar.add_child(_summary_label)

	var audit_btn := Button.new()
	audit_btn.text = "Audit Project (Проверить проект)"
	audit_btn.pressed.connect(func() -> void:
		refresh_all(true)
		if _tabs != null:
			_tabs.current_tab = 3
	)
	toolbar.add_child(audit_btn)

	var sync_btn := Button.new()
	sync_btn.text = "Sync Scene IDs (Синхр. из сцен)"
	sync_btn.pressed.connect(func() -> void:
		var added: int = QuestValidator.sync_discovered_to_registry()
		refresh_all(true)
		print("QuestRegistry: Синхронизировано новых записей из сцен: %d" % added)
	)
	toolbar.add_child(sync_btn)

	var csv_sync_btn := Button.new()
	csv_sync_btn.text = "Sync CSV (Локализация)"
	csv_sync_btn.pressed.connect(func() -> void:
		var added_keys: int = LocalizationUtils.sync_project_strings_to_csv()
		print("LocalizationUtils: Синхронизировано новых ключей в translations.csv: %d" % added_keys)
	)
	toolbar.add_child(csv_sync_btn)

	var inspect_btn := Button.new()
	inspect_btn.text = "Открыть .tres в Инспекторе"
	inspect_btn.pressed.connect(func() -> void:
		inspect_registry_resource_requested.emit()
	)
	toolbar.add_child(inspect_btn)

	var save_btn := Button.new()
	save_btn.text = "Сохранить реестр"
	save_btn.pressed.connect(func() -> void:
		QuestRegistry.save_registry()
		refresh_all(true)
	)
	toolbar.add_child(save_btn)

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(_tabs)

	_build_items_tab()
	_build_flags_tab()
	_build_objects_tab()
	_build_issues_tab()


func _build_items_tab() -> void:
	var tab_vbox := VBoxContainer.new()
	tab_vbox.name = "Предметы (Items)"
	tab_vbox.add_theme_constant_override("separation", 4)
	_tabs.add_child(tab_vbox)

	_items_tree = Tree.new()
	_items_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_items_tree.columns = 7
	_items_tree.column_titles_visible = true
	_items_tree.hide_root = true
	_items_tree.set_column_title(0, "Item ID")
	_items_tree.set_column_title(1, "Название")
	_items_tree.set_column_title(2, "Категория")
	_items_tree.set_column_title(3, "Где создаётся (Produced In)")
	_items_tree.set_column_title(4, "Где требуется (Required By)")
	_items_tree.set_column_title(5, "Описание")
	_items_tree.set_column_title(6, "Действие")
	_items_tree.set_column_expand(0, true)
	_items_tree.set_column_expand(1, true)
	_items_tree.set_column_expand(2, false)
	_items_tree.set_column_custom_minimum_width(2, 100)
	_items_tree.set_column_expand(3, true)
	_items_tree.set_column_expand(4, true)
	_items_tree.set_column_expand(5, true)
	_items_tree.set_column_expand(6, false)
	_items_tree.set_column_custom_minimum_width(6, 95)
	_items_tree.item_activated.connect(_on_items_tree_activated)
	_items_tree.item_selected.connect(_on_items_tree_selected)
	tab_vbox.add_child(_items_tree)

	var add_bar := HBoxContainer.new()
	add_bar.add_theme_constant_override("separation", 6)
	tab_vbox.add_child(add_bar)

	_item_id_input = LineEdit.new()
	_item_id_input.placeholder_text = "Item ID (напр. Ключ)"
	_item_id_input.custom_minimum_size = Vector2(150.0, 0.0)
	add_bar.add_child(_item_id_input)

	_item_name_input = LineEdit.new()
	_item_name_input.placeholder_text = "Отображаемое имя"
	_item_name_input.custom_minimum_size = Vector2(150.0, 0.0)
	add_bar.add_child(_item_name_input)

	_item_cat_option = OptionButton.new()
	for cat: String in ["Key", "Tool", "Quest Item", "Consumable", "Document"]:
		_item_cat_option.add_item(cat)
	add_bar.add_child(_item_cat_option)

	_item_desc_input = LineEdit.new()
	_item_desc_input.placeholder_text = "Описание предмета и его роли в квестах..."
	_item_desc_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_bar.add_child(_item_desc_input)

	var add_btn := Button.new()
	add_btn.text = "+ Добавить / Обновить предмет"
	add_btn.pressed.connect(_on_add_item_pressed)
	add_bar.add_child(add_btn)


func _build_flags_tab() -> void:
	var tab_vbox := VBoxContainer.new()
	tab_vbox.name = "Флаги мира (World Flags)"
	tab_vbox.add_theme_constant_override("separation", 4)
	_tabs.add_child(tab_vbox)

	_flags_tree = Tree.new()
	_flags_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flags_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_flags_tree.columns = 6
	_flags_tree.column_titles_visible = true
	_flags_tree.hide_root = true
	_flags_tree.set_column_title(0, "Flag ID")
	_flags_tree.set_column_title(1, "По умолч.")
	_flags_tree.set_column_title(2, "Категория")
	_flags_tree.set_column_title(3, "Связанные узлы сцен")
	_flags_tree.set_column_title(4, "Описание")
	_flags_tree.set_column_title(5, "Действие")
	_flags_tree.set_column_expand(0, true)
	_flags_tree.set_column_expand(1, false)
	_flags_tree.set_column_custom_minimum_width(1, 85)
	_flags_tree.set_column_expand(2, false)
	_flags_tree.set_column_custom_minimum_width(2, 100)
	_flags_tree.set_column_expand(3, true)
	_flags_tree.set_column_expand(4, true)
	_flags_tree.set_column_expand(5, false)
	_flags_tree.set_column_custom_minimum_width(5, 95)
	_flags_tree.item_activated.connect(_on_flags_tree_activated)
	_flags_tree.item_selected.connect(_on_flags_tree_selected)
	tab_vbox.add_child(_flags_tree)

	var add_bar := HBoxContainer.new()
	add_bar.add_theme_constant_override("separation", 6)
	tab_vbox.add_child(add_bar)

	_flag_id_input = LineEdit.new()
	_flag_id_input.placeholder_text = "Flag ID (напр. power_restored)"
	_flag_id_input.custom_minimum_size = Vector2(180.0, 0.0)
	add_bar.add_child(_flag_id_input)

	_flag_default_check = CheckBox.new()
	_flag_default_check.text = "Default = true"
	add_bar.add_child(_flag_default_check)

	_flag_cat_option = OptionButton.new()
	for cat: String in ["Puzzle", "Door", "Trigger", "Item State", "Story"]:
		_flag_cat_option.add_item(cat)
	add_bar.add_child(_flag_cat_option)

	_flag_desc_input = LineEdit.new()
	_flag_desc_input.placeholder_text = "Описание события или головоломки, которой управляет флаг..."
	_flag_desc_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_bar.add_child(_flag_desc_input)

	var add_btn := Button.new()
	add_btn.text = "+ Добавить / Обновить флаг"
	add_btn.pressed.connect(_on_add_flag_pressed)
	add_bar.add_child(add_btn)


func _build_objects_tab() -> void:
	var tab_vbox := VBoxContainer.new()
	tab_vbox.name = "Объекты сцен (Object IDs)"
	tab_vbox.add_theme_constant_override("separation", 4)
	_tabs.add_child(tab_vbox)

	_objects_tree = Tree.new()
	_objects_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objects_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_objects_tree.columns = 6
	_objects_tree.column_titles_visible = true
	_objects_tree.hide_root = true
	_objects_tree.set_column_title(0, "Object ID")
	_objects_tree.set_column_title(1, "Тип сущности")
	_objects_tree.set_column_title(2, "Сцена (.tscn)")
	_objects_tree.set_column_title(3, "Путь узла")
	_objects_tree.set_column_title(4, "Статус в реестре")
	_objects_tree.set_column_title(5, "Навигация")
	_objects_tree.set_column_expand(0, true)
	_objects_tree.set_column_expand(1, false)
	_objects_tree.set_column_custom_minimum_width(1, 130)
	_objects_tree.set_column_expand(2, true)
	_objects_tree.set_column_expand(3, true)
	_objects_tree.set_column_expand(4, false)
	_objects_tree.set_column_custom_minimum_width(4, 150)
	_objects_tree.set_column_expand(5, false)
	_objects_tree.set_column_custom_minimum_width(5, 130)
	_objects_tree.item_activated.connect(_on_objects_tree_activated)
	_objects_tree.item_selected.connect(_on_objects_tree_selected)
	tab_vbox.add_child(_objects_tree)


func _build_issues_tab() -> void:
	var tab_vbox := VBoxContainer.new()
	tab_vbox.name = "Аудит и ошибки (Validator)"
	tab_vbox.add_theme_constant_override("separation", 4)
	_tabs.add_child(tab_vbox)

	_issues_tree = Tree.new()
	_issues_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_issues_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_issues_tree.columns = 6
	_issues_tree.column_titles_visible = true
	_issues_tree.hide_root = true
	_issues_tree.set_column_title(0, "Уровень")
	_issues_tree.set_column_title(1, "Категория")
	_issues_tree.set_column_title(2, "ID ссылки")
	_issues_tree.set_column_title(3, "Описание проблемы")
	_issues_tree.set_column_title(4, "Сцена и узел")
	_issues_tree.set_column_title(5, "Переход")
	_issues_tree.set_column_expand(0, false)
	_issues_tree.set_column_custom_minimum_width(0, 90)
	_issues_tree.set_column_expand(1, false)
	_issues_tree.set_column_custom_minimum_width(1, 180)
	_issues_tree.set_column_expand(2, false)
	_issues_tree.set_column_custom_minimum_width(2, 130)
	_issues_tree.set_column_expand(3, true)
	_issues_tree.set_column_expand(4, true)
	_issues_tree.set_column_expand(5, false)
	_issues_tree.set_column_custom_minimum_width(5, 130)
	_issues_tree.item_activated.connect(_on_issues_tree_activated)
	_issues_tree.item_selected.connect(_on_issues_tree_selected)
	tab_vbox.add_child(_issues_tree)


func _populate_items_tree() -> void:
	_items_tree.clear()
	var root: TreeItem = _items_tree.create_item()
	var reg: QuestRegistryData = QuestRegistry.get_registry()
	var item_usages: Dictionary = _last_audit_report.get("item_usages", {}) as Dictionary

	for item_def: ItemData in reg.items:
		if item_def == null:
			continue
		var eff_id: String = item_def.get_effective_id()
		var row: TreeItem = _items_tree.create_item(root)
		row.set_text(0, eff_id)
		row.set_text(1, item_def.item_name)
		row.set_text(2, item_def.category)

		var u_info: Dictionary = item_usages.get(eff_id, {}) as Dictionary
		var prod_list: Array = u_info.get("produced_in", []) as Array
		var req_list: Array = u_info.get("required_in", []) as Array

		row.set_text(3, _format_usage_summary(prod_list))
		row.set_text(4, _format_usage_summary(req_list))
		row.set_text(5, item_def.description)
		row.set_text(6, "[Удалить]")
		row.set_custom_color(6, COLOR_ERROR)

		if prod_list.is_empty() and not req_list.is_empty():
			row.set_custom_color(3, COLOR_WARNING)
		elif not prod_list.is_empty():
			row.set_custom_color(3, COLOR_OK)

		var nav_meta: Dictionary = {"item_id": eff_id}
		if not prod_list.is_empty():
			var first_p: Dictionary = prod_list[0] as Dictionary
			nav_meta["scene_path"] = first_p.get("scene_path", "")
			nav_meta["node_path"] = first_p.get("node_path", "")
		elif not req_list.is_empty():
			var first_r: Dictionary = req_list[0] as Dictionary
			nav_meta["scene_path"] = first_r.get("scene_path", "")
			nav_meta["node_path"] = first_r.get("node_path", "")
		row.set_metadata(0, nav_meta)


func _populate_flags_tree() -> void:
	_flags_tree.clear()
	var root: TreeItem = _flags_tree.create_item()
	var reg: QuestRegistryData = QuestRegistry.get_registry()
	var flag_usages: Dictionary = _last_audit_report.get("flag_usages", {}) as Dictionary

	for flag_def: WorldFlagData in reg.flags:
		if flag_def == null:
			continue
		var fid: String = flag_def.flag_id
		var row: TreeItem = _flags_tree.create_item(root)
		row.set_text(0, fid)
		row.set_text(1, "true" if flag_def.default_value else "false")
		row.set_text(2, flag_def.category)

		var f_info: Dictionary = flag_usages.get(fid, {}) as Dictionary
		var set_list: Array = f_info.get("set_in", []) as Array
		row.set_text(3, _format_usage_summary(set_list))
		row.set_text(4, flag_def.description)
		row.set_text(5, "[Удалить]")
		row.set_custom_color(5, COLOR_ERROR)

		var nav_meta: Dictionary = {"flag_id": fid}
		if not set_list.is_empty():
			var first_s: Dictionary = set_list[0] as Dictionary
			nav_meta["scene_path"] = first_s.get("scene_path", "")
			nav_meta["node_path"] = first_s.get("node_path", "")
		row.set_metadata(0, nav_meta)


func _populate_objects_tree() -> void:
	_objects_tree.clear()
	var root: TreeItem = _objects_tree.create_item()
	var discovered: Array = _last_audit_report.get("discovered_objects", []) as Array

	for obj_entry: Dictionary in discovered:
		var row: TreeItem = _objects_tree.create_item(root)
		var obj_id: String = str(obj_entry.get("object_id", ""))
		var ent_type: String = str(obj_entry.get("entity_type", ""))
		var scene_path: String = str(obj_entry.get("scene_path", ""))
		var node_path: String = str(obj_entry.get("node_path", ""))
		var is_reg: bool = bool(obj_entry.get("is_registered", false))

		row.set_text(0, obj_id)
		row.set_text(1, ent_type)
		row.set_text(2, scene_path.get_file())
		row.set_text(3, node_path)
		row.set_text(4, "Зарегистрирован" if is_reg else "Не в реестре (Sync)")
		row.set_custom_color(4, COLOR_OK if is_reg else COLOR_WARNING)
		row.set_text(5, "[Открыть узел]")
		row.set_custom_color(5, COLOR_OK)
		row.set_metadata(0, {
			"scene_path": scene_path,
			"node_path": node_path,
		})


func _populate_issues_tree() -> void:
	_issues_tree.clear()
	var root: TreeItem = _issues_tree.create_item()
	var issues: Array = _last_audit_report.get("issues", []) as Array

	if issues.is_empty():
		var ok_row: TreeItem = _issues_tree.create_item(root)
		ok_row.set_text(0, "OK")
		ok_row.set_custom_color(0, COLOR_OK)
		ok_row.set_text(1, "All Checks Passed")
		ok_row.set_text(2, "-")
		ok_row.set_text(3, "Все квестовые связи, предметы, флаги и object_id валидны! Ошибок не обнаружено.")
		ok_row.set_text(4, "-")
		ok_row.set_text(5, "")
		return

	for issue: Dictionary in issues:
		var row: TreeItem = _issues_tree.create_item(root)
		var sev: String = str(issue.get("severity", "WARNING"))
		var cat: String = str(issue.get("category", ""))
		var id_ref: String = str(issue.get("id_ref", ""))
		var msg: String = str(issue.get("message", ""))
		var scene_path: String = str(issue.get("scene_path", ""))
		var node_path: String = str(issue.get("node_path", ""))

		row.set_text(0, sev)
		row.set_custom_color(0, COLOR_ERROR if sev == "ERROR" else COLOR_WARNING)
		row.set_text(1, cat)
		row.set_text(2, id_ref)
		row.set_text(3, msg)
		if not scene_path.is_empty():
			row.set_text(4, "%s :: %s" % [scene_path.get_file(), node_path])
			row.set_text(5, "[Открыть узел]")
			row.set_custom_color(5, COLOR_OK)
		else:
			row.set_text(4, "(Глобальный реестр)")
			row.set_text(5, "")

		row.set_metadata(0, {
			"scene_path": scene_path,
			"node_path": node_path,
		})


func _update_summary_badge() -> void:
	if _summary_label == null:
		return
	var reg: QuestRegistryData = QuestRegistry.get_registry()
	var issues: Array = _last_audit_report.get("issues", []) as Array
	var discovered: Array = _last_audit_report.get("discovered_objects", []) as Array

	var err_count: int = 0
	var warn_count: int = 0
	for issue: Dictionary in issues:
		if str(issue.get("severity", "")) == "ERROR":
			err_count += 1
		else:
			warn_count += 1

	_summary_label.text = "Предметов: %d  |  Флагов: %d  |  Объектов в сценах: %d  |  Ошибок: %d  |  Предупреждений: %d" % [
		reg.items.size(),
		reg.flags.size(),
		discovered.size(),
		err_count,
		warn_count,
	]
	if err_count > 0:
		_summary_label.add_theme_color_override("font_color", COLOR_ERROR)
	elif warn_count > 0:
		_summary_label.add_theme_color_override("font_color", COLOR_WARNING)
	else:
		_summary_label.add_theme_color_override("font_color", COLOR_OK)


func _format_usage_summary(usages: Array) -> String:
	if usages.is_empty():
		return "— (Не используется)"
	var parts: PackedStringArray = PackedStringArray()
	for u: Dictionary in usages:
		var s_file: String = str(u.get("scene_path", "")).get_file().get_basename()
		var n_name: String = str(u.get("node_name", ""))
		parts.append("%s:%s" % [s_file, n_name])
	return ", ".join(parts)


func _on_add_item_pressed() -> void:
	var new_id: String = _item_id_input.text.strip_edges()
	if new_id.is_empty():
		return
	var new_name: String = _item_name_input.text.strip_edges()
	if new_name.is_empty():
		new_name = new_id
	var cat: String = _item_cat_option.get_item_text(_item_cat_option.selected)
	var desc: String = _item_desc_input.text.strip_edges()

	QuestRegistry.register_and_save_item(new_id, new_name, cat, desc)
	_item_id_input.text = ""
	_item_name_input.text = ""
	_item_desc_input.text = ""
	refresh_all(true)


func _on_add_flag_pressed() -> void:
	var new_id: String = _flag_id_input.text.strip_edges()
	if new_id.is_empty():
		return
	var def_val: bool = _flag_default_check.button_pressed
	var cat: String = _flag_cat_option.get_item_text(_flag_cat_option.selected)
	var desc: String = _flag_desc_input.text.strip_edges()

	QuestRegistry.register_and_save_flag(new_id, def_val, cat, desc)
	_flag_id_input.text = ""
	_flag_default_check.button_pressed = false
	_flag_desc_input.text = ""
	refresh_all(true)


func _on_items_tree_selected() -> void:
	var item: TreeItem = _items_tree.get_selected()
	if item == null:
		return
	var col: int = _items_tree.get_selected_column()
	var meta: Dictionary = item.get_metadata(0) as Dictionary
	var item_id: String = str(meta.get("item_id", ""))

	if col == 6 and not item_id.is_empty():
		var reg: QuestRegistryData = QuestRegistry.get_registry()
		if reg.remove_item(item_id):
			QuestRegistry.save_registry(reg)
			refresh_all(true)
		return

	_item_id_input.text = item.get_text(0)
	_item_name_input.text = item.get_text(1)
	_item_desc_input.text = item.get_text(5)


func _on_items_tree_activated() -> void:
	var item: TreeItem = _items_tree.get_selected()
	if item == null:
		return
	_emit_navigation_from_item(item)


func _on_flags_tree_selected() -> void:
	var item: TreeItem = _flags_tree.get_selected()
	if item == null:
		return
	var col: int = _flags_tree.get_selected_column()
	var meta: Dictionary = item.get_metadata(0) as Dictionary
	var flag_id: String = str(meta.get("flag_id", ""))

	if col == 5 and not flag_id.is_empty():
		var reg: QuestRegistryData = QuestRegistry.get_registry()
		if reg.remove_flag(flag_id):
			QuestRegistry.save_registry(reg)
			refresh_all(true)
		return

	_flag_id_input.text = item.get_text(0)
	_flag_default_check.button_pressed = (item.get_text(1) == "true")
	_flag_desc_input.text = item.get_text(4)


func _on_flags_tree_activated() -> void:
	var item: TreeItem = _flags_tree.get_selected()
	if item == null:
		return
	_emit_navigation_from_item(item)


func _on_objects_tree_selected() -> void:
	var item: TreeItem = _objects_tree.get_selected()
	if item == null:
		return
	if _objects_tree.get_selected_column() == 5:
		_emit_navigation_from_item(item)


func _on_objects_tree_activated() -> void:
	var item: TreeItem = _objects_tree.get_selected()
	if item == null:
		return
	_emit_navigation_from_item(item)


func _on_issues_tree_selected() -> void:
	var item: TreeItem = _issues_tree.get_selected()
	if item == null:
		return
	if _issues_tree.get_selected_column() == 5:
		_emit_navigation_from_item(item)


func _on_issues_tree_activated() -> void:
	var item: TreeItem = _issues_tree.get_selected()
	if item == null:
		return
	_emit_navigation_from_item(item)


func _emit_navigation_from_item(item: TreeItem) -> void:
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary):
		return
	var dict: Dictionary = meta as Dictionary
	var scene_path: String = str(dict.get("scene_path", ""))
	var node_path: String = str(dict.get("node_path", ""))
	if not scene_path.is_empty():
		navigate_to_scene_node_requested.emit(scene_path, node_path)
