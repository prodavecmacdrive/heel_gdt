@tool
class_name QuestValidator
extends RefCounted
## Анализатор сцен и валидатор целостности квестовых связей проекта.
##
## Сканирует файлы комнат (`*.tscn`) через `SceneState` без инстанцирования узлов и проверяет:
## [br]• **Broken Links (ERROR):** ссылки на незарегистрированные предметы или флаги;
## [br]• **Duplicate Object IDs (ERROR):** дублирующиеся `object_id` у разных объектов, ведущие к перезаписи `GameManager.world_state`;
## [br]• **Orphan / Dead-End Items & Flags (WARNING):** предметы, которые требуются для прохождения, но нигде не лежат в мире, или неиспользуемые флаги.

const ROOMS_DIR: String = "res://rooms"


## Выполняет полный аудит всех сцен комнат в `res://rooms/` и сопоставляет их с [QuestRegistry].
## Возвращает структурированный отчёт со списками объектов, матрицей использования предметов/флагов и найденными проблемами.
static func audit_project() -> Dictionary:
	var registry: QuestRegistryData = QuestRegistry.get_registry()
	var room_files: PackedStringArray = _collect_room_scene_files(ROOMS_DIR)

	var discovered_objects: Array[Dictionary] = []
	var item_usages: Dictionary = {}
	var flag_usages: Dictionary = {}
	var issues: Array[Dictionary] = []

	for item_id: String in registry.get_item_ids():
		item_usages[item_id] = {
			"produced_in": [],
			"required_in": [],
		}

	for flag_id: String in registry.get_flag_ids():
		flag_usages[flag_id] = {
			"set_in": [],
			"read_in": [],
		}

	var object_id_map: Dictionary = {}

	for scene_path: String in room_files:
		var entities: Array[Dictionary] = _scan_scene_entities(scene_path)
		for ent: Dictionary in entities:
			var ent_type: String = str(ent.get("entity_type", ""))
			var node_path: String = str(ent.get("node_path", ""))
			var node_name: String = str(ent.get("node_name", ""))
			var obj_id: String = str(ent.get("object_id", "")).strip_edges()

			if not obj_id.is_empty():
				var obj_entry: Dictionary = {
					"object_id": obj_id,
					"entity_type": ent_type,
					"scene_path": scene_path,
					"node_path": node_path,
					"node_name": node_name,
					"is_registered": registry.has_object_id(obj_id),
				}
				discovered_objects.append(obj_entry)

				if not object_id_map.has(obj_id):
					object_id_map[obj_id] = []
				(object_id_map[obj_id] as Array).append(obj_entry)

			if ent_type == "ItemPickup":
				var item_name: String = str(ent.get("item_name", "")).strip_edges()
				if not item_name.is_empty():
					_record_item_usage(item_usages, registry, item_name, true, {
						"scene_path": scene_path,
						"node_path": node_path,
						"node_name": node_name,
						"entity_type": ent_type,
						"context": "Подбираемый предмет в мире (ItemPickup)",
					})
					if not registry.has_item(item_name):
						issues.append({
							"severity": "ERROR",
							"category": "Broken Item Link",
							"id_ref": item_name,
							"message": "ItemPickup '%s' выдаёт предмет '%s', который не зарегистрирован в QuestRegistry." % [node_name, item_name],
							"scene_path": scene_path,
							"node_path": node_path,
						})

				var pickup_flag: String = obj_id if not obj_id.is_empty() else node_name
				if not pickup_flag.is_empty():
					_record_flag_usage(flag_usages, pickup_flag, true, true, {
						"scene_path": scene_path,
						"node_path": node_path,
						"node_name": node_name,
						"entity_type": ent_type,
						"context": "Флаг сохранения подбора предмета",
					})

			elif ent_type == "Chest":
				var chest_items: Array[String] = ent.get("items", []) as Array[String]
				for c_item: String in chest_items:
					var clean_item: String = c_item.strip_edges()
					if clean_item.is_empty():
						continue
					_record_item_usage(item_usages, registry, clean_item, true, {
						"scene_path": scene_path,
						"node_path": node_path,
						"node_name": node_name,
						"entity_type": ent_type,
						"context": "Лежит в контейнере (Chest.items)",
					})
					if not registry.has_item(clean_item):
						issues.append({
							"severity": "ERROR",
							"category": "Broken Item Link",
							"id_ref": clean_item,
							"message": "Контейнер '%s' содержит предмет '%s', отсутствующий в QuestRegistry." % [node_name, clean_item],
							"scene_path": scene_path,
							"node_path": node_path,
						})

				var is_locked: bool = bool(ent.get("is_locked", false))
				if is_locked:
					var req_keys: Array[String] = []
					var req_main: String = str(ent.get("required_item", "")).strip_edges()
					if not req_main.is_empty():
						req_keys.append(req_main)
					var unlock_arr: Array[String] = ent.get("unlock_items", []) as Array[String]
					for u_item: String in unlock_arr:
						var clean_u: String = u_item.strip_edges()
						if not clean_u.is_empty() and not req_keys.has(clean_u):
							req_keys.append(clean_u)

					for key_id: String in req_keys:
						_record_item_usage(item_usages, registry, key_id, false, {
							"scene_path": scene_path,
							"node_path": node_path,
							"node_name": node_name,
							"entity_type": ent_type,
							"context": "Отпирает контейнер (Chest)",
						})
						if not registry.has_item(key_id):
							issues.append({
								"severity": "ERROR",
								"category": "Broken Item Link",
								"id_ref": key_id,
								"message": "Запертый контейнер '%s' требует ключ '%s', не зарегистрированный в QuestRegistry." % [node_name, key_id],
								"scene_path": scene_path,
								"node_path": node_path,
							})

				if not obj_id.is_empty():
					var chest_flag: String = obj_id + "_unlocked"
					_record_flag_usage(flag_usages, chest_flag, true, true, {
						"scene_path": scene_path,
						"node_path": node_path,
						"node_name": node_name,
						"entity_type": ent_type,
						"context": "Флаг отпирания контейнера",
					})

			elif ent_type == "QuestInteractable":
				var req_item: String = str(ent.get("required_item", "")).strip_edges()
				if not req_item.is_empty():
					_record_item_usage(item_usages, registry, req_item, false, {
						"scene_path": scene_path,
						"node_path": node_path,
						"node_name": node_name,
						"entity_type": ent_type,
						"context": "Требуется для активации (QuestInteractable.required_item)",
					})
					if not registry.has_item(req_item):
						issues.append({
							"severity": "ERROR",
							"category": "Broken Item Link",
							"id_ref": req_item,
							"message": "Объект '%s' требует предмет '%s', который отсутствует в QuestRegistry." % [node_name, req_item],
							"scene_path": scene_path,
							"node_path": node_path,
						})

				var flag_on_success: String = str(ent.get("set_flag_on_success", "")).strip_edges()
				if not flag_on_success.is_empty():
					_record_flag_usage(flag_usages, flag_on_success, true, true, {
						"scene_path": scene_path,
						"node_path": node_path,
						"node_name": node_name,
						"entity_type": ent_type,
						"context": "Устанавливается при успехе (set_flag_on_success)",
					})
					if not registry.has_flag(flag_on_success):
						issues.append({
							"severity": "ERROR",
							"category": "Broken Flag Link",
							"id_ref": flag_on_success,
							"message": "Объект '%s' устанавливает незарегистрированный флаг '%s'." % [node_name, flag_on_success],
							"scene_path": scene_path,
							"node_path": node_path,
						})

				if not obj_id.is_empty():
					_record_flag_usage(flag_usages, obj_id, true, true, {
						"scene_path": scene_path,
						"node_path": node_path,
						"node_name": node_name,
						"entity_type": ent_type,
						"context": "Состояние объекта (<object_id>_state)",
					})

			elif ent_type == "Door":
				var door_req_item: String = str(ent.get("required_item", "")).strip_edges()
				if not door_req_item.is_empty():
					_record_item_usage(item_usages, registry, door_req_item, false, {
						"scene_path": scene_path,
						"node_path": node_path,
						"node_name": node_name,
						"entity_type": ent_type,
						"context": "Ключ от шлюза (Door.required_item)",
					})
					if not registry.has_item(door_req_item):
						issues.append({
							"severity": "ERROR",
							"category": "Broken Item Link",
							"id_ref": door_req_item,
							"message": "Шлюз '%s' требует ключ '%s', который не зарегистрирован в QuestRegistry." % [node_name, door_req_item],
							"scene_path": scene_path,
							"node_path": node_path,
						})

				var door_id_str: String = str(ent.get("door_id", "")).strip_edges()
				var unlock_flag_key: String = (obj_id + "_unlocked") if not obj_id.is_empty() else (door_id_str + "_unlocked" if not door_id_str.is_empty() else "")
				if not unlock_flag_key.is_empty():
					_record_flag_usage(flag_usages, unlock_flag_key, true, true, {
						"scene_path": scene_path,
						"node_path": node_path,
						"node_name": node_name,
						"entity_type": ent_type,
						"context": "Флаг разблокировки шлюза",
					})

	for obj_id_key: String in object_id_map.keys():
		var occurrences: Array = object_id_map[obj_id_key] as Array
		if occurrences.size() > 1:
			var locations: PackedStringArray = PackedStringArray()
			for occ: Dictionary in occurrences:
				locations.append("%s (%s)" % [str(occ["scene_path"]).get_file(), str(occ["node_path"])])
			var first_occ: Dictionary = occurrences[0] as Dictionary
			issues.append({
				"severity": "ERROR",
				"category": "Duplicate Object ID",
				"id_ref": obj_id_key,
				"message": "Дублирующийся object_id '%s' обнаружен в %d узлах: %s. Это приведёт к конфликту состояний в GameManager!" % [
					obj_id_key,
					occurrences.size(),
					", ".join(locations)
				],
				"scene_path": str(first_occ["scene_path"]),
				"node_path": str(first_occ["node_path"]),
			})

	for item_key: String in item_usages.keys():
		var u_data: Dictionary = item_usages[item_key] as Dictionary
		var produced: Array = u_data["produced_in"] as Array
		var required: Array = u_data["required_in"] as Array

		if not required.is_empty() and produced.is_empty():
			var first_req: Dictionary = required[0] as Dictionary
			issues.append({
				"severity": "WARNING",
				"category": "Unobtainable Item (Dead-End)",
				"id_ref": item_key,
				"message": "Предмет '%s' требуется для прохождения (%s), но нигде не размещён в комнатах или контейнерах!" % [
					item_key,
					str(first_req["node_name"])
				],
				"scene_path": str(first_req["scene_path"]),
				"node_path": str(first_req["node_path"]),
			})
		elif produced.is_empty() and required.is_empty():
			issues.append({
				"severity": "WARNING",
				"category": "Orphan Registry Item",
				"id_ref": item_key,
				"message": "Предмет '%s' зарегистрирован в базе, но ни разу не используется ни в одной комнате." % item_key,
				"scene_path": "",
				"node_path": "",
			})

	for flag_def: WorldFlagData in registry.flags:
		if flag_def == null or flag_def.flag_id.is_empty():
			continue
		var fid: String = flag_def.flag_id
		if not flag_usages.has(fid):
			issues.append({
				"severity": "WARNING",
				"category": "Orphan World Flag",
				"id_ref": fid,
				"message": "Флаг '%s' зарегистрирован в реестре, но не связан ни с одним объектом в комнатах." % fid,
				"scene_path": "",
				"node_path": "",
			})
		else:
			var f_data: Dictionary = flag_usages[fid] as Dictionary
			var set_list: Array = f_data["set_in"] as Array
			var read_list: Array = f_data["read_in"] as Array
			if set_list.is_empty() and read_list.is_empty():
				issues.append({
					"severity": "WARNING",
					"category": "Orphan World Flag",
					"id_ref": fid,
					"message": "Флаг '%s' зарегистрирован в реестре, но не используется ни в одной сцене." % fid,
					"scene_path": "",
					"node_path": "",
				})

	return {
		"rooms_scanned": room_files,
		"discovered_objects": discovered_objects,
		"item_usages": item_usages,
		"flag_usages": flag_usages,
		"issues": issues,
	}


## Автоматически регистрирует все найденные в сценах предметы, флаги и `object_id` в [QuestRegistry].
## Возвращает количество добавленных записей.
static func sync_discovered_to_registry() -> int:
	var report: Dictionary = audit_project()
	var reg: QuestRegistryData = QuestRegistry.get_registry()
	var added_count: int = 0

	var discovered_objects: Array = report.get("discovered_objects", []) as Array
	for obj_entry: Dictionary in discovered_objects:
		var obj_id: String = str(obj_entry.get("object_id", "")).strip_edges()
		if not obj_id.is_empty() and not reg.has_object_id(obj_id):
			reg.register_object_id(obj_id)
			added_count += 1

	var item_usages: Dictionary = report.get("item_usages", {}) as Dictionary
	for item_id: String in item_usages.keys():
		if not item_id.is_empty() and not reg.has_item(item_id):
			reg.register_item(item_id, item_id, "Quest Item", "Автоматически импортировано из сцен комнат")
			added_count += 1

	var flag_usages: Dictionary = report.get("flag_usages", {}) as Dictionary
	for flag_id: String in flag_usages.keys():
		if not flag_id.is_empty() and not reg.has_flag(flag_id):
			reg.register_flag(flag_id, false, "Puzzle", "Автоматически импортировано из сцен комнат")
			added_count += 1

	if added_count > 0:
		QuestRegistry.save_registry(reg)
	var csv_added: int = LocalizationUtils.sync_project_strings_to_csv()
	return added_count + csv_added


static func _record_item_usage(
	item_usages: Dictionary,
	registry: QuestRegistryData,
	raw_item_id: String,
	is_produced: bool,
	entry: Dictionary
) -> void:
	var resolved_key: String = raw_item_id
	var item_data: ItemData = registry.find_item(raw_item_id)
	if item_data != null:
		resolved_key = item_data.get_effective_id()

	if not item_usages.has(resolved_key):
		item_usages[resolved_key] = {
			"produced_in": [],
			"required_in": [],
		}

	var target_list_key: String = "produced_in" if is_produced else "required_in"
	((item_usages[resolved_key] as Dictionary)[target_list_key] as Array).append(entry)


static func _record_flag_usage(
	flag_usages: Dictionary,
	flag_id: String,
	is_set: bool,
	is_read: bool,
	entry: Dictionary
) -> void:
	if flag_id.is_empty():
		return
	if not flag_usages.has(flag_id):
		flag_usages[flag_id] = {
			"set_in": [],
			"read_in": [],
		}
	if is_set:
		((flag_usages[flag_id] as Dictionary)["set_in"] as Array).append(entry)
	if is_read:
		((flag_usages[flag_id] as Dictionary)["read_in"] as Array).append(entry)


## Собирает список всех файлов сцен комнат (`*.tscn`) в папке `res://rooms/` (исключая `bunker_master.tscn`).
static func _collect_room_scene_files(dir_path: String) -> PackedStringArray:
	var results: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return results

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir():
			if file_name.ends_with(".tscn") and file_name != "bunker_master.tscn":
				results.append(dir_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	results.sort()
	return results


## Извлекает метаданные всех интерактивных сущностей из `SceneState` указанной сцены без её инстанцирования.
static func _scan_scene_entities(scene_path: String) -> Array[Dictionary]:
	var entities: Array[Dictionary] = []
	if not ResourceLoader.exists(scene_path):
		return entities

	var packed: PackedScene = ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return entities

	var state: SceneState = packed.get_state()
	if state == null:
		return entities

	var node_count: int = state.get_node_count()
	for i: int in range(node_count):
		var node_name: String = String(state.get_node_name(i))
		var node_path: String = String(state.get_node_path(i))
		var instance_scene: PackedScene = state.get_node_instance(i)
		var instance_path: String = instance_scene.resource_path if instance_scene != null else ""

		var props: Dictionary = {}
		var prop_count: int = state.get_node_property_count(i)
		for p: int in range(prop_count):
			var p_name: String = String(state.get_node_property_name(i, p))
			var p_val: Variant = state.get_node_property_value(i, p)
			props[p_name] = p_val

		var script_res: Variant = props.get("script", null)
		var script_path: String = ""
		if script_res is Script:
			script_path = (script_res as Script).resource_path
		elif script_res is Resource:
			script_path = (script_res as Resource).resource_path

		var entity_type: String = _classify_entity(script_path, instance_path)
		if entity_type.is_empty():
			continue

		var record: Dictionary = _build_default_entity_record(entity_type, node_name, node_path)
		for k: String in props.keys():
			if k == "items" or k == "unlock_items":
				var str_arr: Array[String] = []
				var raw_val: Variant = props[k]
				if raw_val is Array or raw_val is PackedStringArray:
					for elem: Variant in raw_val:
						str_arr.append(str(elem))
				record[k] = str_arr
			else:
				record[k] = props[k]

		entities.append(record)

	return entities


static func _classify_entity(script_path: String, instance_path: String) -> String:
	if script_path.ends_with("quest_interactable.gd"):
		return "QuestInteractable"
	if script_path.ends_with("door.gd") or instance_path.ends_with("door.tscn"):
		return "Door"
	if script_path.ends_with("chest.gd") or instance_path.ends_with("chest.tscn"):
		return "Chest"
	if script_path.ends_with("item_pickup.gd") or instance_path.ends_with("key.tscn"):
		return "ItemPickup"
	return ""


static func _build_default_entity_record(entity_type: String, node_name: String, node_path: String) -> Dictionary:
	var base: Dictionary = {
		"entity_type": entity_type,
		"node_name": node_name,
		"node_path": node_path,
		"object_id": "",
	}
	if entity_type == "Chest":
		base["object_id"] = "room_01_chest"
		base["is_locked"] = true
		var default_items: Array[String] = ["Батарейка", "Записка"]
		var default_unlock: Array[String] = ["Ключ"]
		base["items"] = default_items
		base["required_item"] = "Ключ"
		base["unlock_items"] = default_unlock
	elif entity_type == "Door":
		base["door_id"] = "door_01"
		base["is_locked"] = false
		base["required_item"] = ""
	elif entity_type == "ItemPickup":
		base["item_name"] = "Ключ"
	elif entity_type == "QuestInteractable":
		base["required_item"] = ""
		base["set_flag_on_success"] = ""
		base["target_node"] = NodePath("")
	return base

