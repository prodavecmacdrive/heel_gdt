@tool
class_name QuestInteractable
extends Area3D
## Универсальный интерактивный объект и триггер квестовой системы.
##
## Объединяет:
## [br]• квестовую машину состояний с сохранением в [GameManager];
## [br]• проверку и применение предметов из инвентаря;
## [br]• 2D-спрайтовое или 3D-мешевое визуальное представление ([InteractableVisualRig]);
## [br]• генерацию зон взаимодействия, твёрдых препятствий и 1-клик запекание NavMesh ([InteractablePhysicsBuilder]).

const INTERNAL_SPRITE_NAME: String = InteractableVisualRig.INTERNAL_SPRITE_NAME
const INTERNAL_ANIM_SPRITE_NAME: String = InteractableVisualRig.INTERNAL_ANIM_SPRITE_NAME
const INTERNAL_MESH_NAME: String = InteractableVisualRig.INTERNAL_MESH_NAME
const INTERNAL_OBSTACLE_NAME: String = InteractablePhysicsBuilder.INTERNAL_OBSTACLE_NAME

@export_category("Quest Interactable")

@export_group("Identity & State")
## Уникальный идентификатор объекта в мире (например, `"terminal_door_01"`).
## Используется для сохранения состояния (`<object_id>_state`) в [GameManager] между переходами по комнатам.
@export var object_id: String = ""

## Текущее логическое состояние объекта: `"default"` (исходное) или `"active"` (активированное).
## Автоматически переключается в `"active"` при успешном взаимодействии и влияет на выбор анимации и текста осмотра.
@export var current_state: String = "default":
	set(val):
		current_state = val
		if is_inside_tree():
			_update_sprite_animation_for_state()

## Способ активации объекта:
## [br]• `Click` (0) — игрок кликает мышью по объекту и подходит к нему;
## [br]• `Step Enter` (1) — срабатывает автоматически, когда капсула игрока входит в зону `Area3D`.
@export_enum("Click", "Step Enter") var trigger_mode: int = 0

## Если включено, объект срабатывает только один раз за всю игру, после чего фиксируется в состоянии `"active"`
## (а в режиме `Step Enter` отключает дальнейший мониторинг входов).
@export var one_shot: bool = false

@export_group("Inspection & Feedback")
@export_subgroup("Inspection")
## Текст описания, выводимый в статус-бар терминала при обычном осмотре объекта в исходном состоянии (`"default"`).
@export var inspect_text: String = ""

## Текст описания, выводимый при осмотре объекта после того, как он уже перешёл в состояние `"active"`.
## Если оставить пустым, будет использоваться основной `inspect_text`.
@export var active_inspect_text: String = ""

@export_subgroup("Feedback Messages")
## Сообщение, отображаемое в момент успешной активации объекта или применения верного предмета.
@export var success_text: String = ""

## Сообщение, отображаемое при попытке применить неподходящий предмет из инвентаря.
@export var fail_text: String = "Это здесь не сработает."

@export_group("Item Requirement")
## Название или идентификатор предмета из инвентаря игрока, необходимый для активации объекта (например, `"Ключ"`).
## Если оставить пустым, объект активируется простым кликом/входом без предмета.
@export var required_item: String = ""

## Если включено, требуемый предмет (`required_item`) будет удалён из инвентаря игрока после успешного применения.
@export var consume_item: bool = true

@export_group("Target & Visual Transitions")
## Имя глобального булевого флага в `GameManager.world_state`, который будет установлен в `true` при успешной активации.
@export var set_flag_on_success: String = ""

## Путь к целевому узлу сцены (например, запертой двери `Door` или источнику света `Light3D`),
## который нужно разблокировать (`is_locked = false`), переключить или вызвать на нём `on_quest_trigger()`.
@export var target_node: NodePath = NodePath("")

## Список узлов сцены, которые станут видимыми (`visible = true`) после перехода объекта в состояние `"active"`
## (и будут скрыты в состоянии `"default"`).
@export var nodes_to_show_on_success: Array[NodePath] = []

## Список узлов сцены, которые будут скрыты (`visible = false`) после перехода объекта в состояние `"active"`
## (и видимы в состоянии `"default"`).
@export var nodes_to_hide_on_success: Array[NodePath] = []

@export_group("Quest Registry Quick-Add")
## Введите новый строковый идентификатор предмета или глобального флага, чтобы мгновенно зарегистрировать его в едином реестре (`res://data/quest_registry.tres`) прямо из Инспектора.
@export var quick_register_id: String = ""

## Необязательное описание нового предмета или флага для документации в реестре квестов.
@export var quick_register_description: String = ""

## Кнопка редактора: регистрирует `quick_register_id` (или текущий `required_item`) как предмет в [QuestRegistry], назначает его в `required_item` и обновляет выпадающий список Инспектора.
@export_tool_button("Register & Assign Item") var register_item_btn: Callable = _quick_register_item

## Кнопка редактора: регистрирует `quick_register_id` (или текущий `set_flag_on_success`) как глобальный флаг в [QuestRegistry], назначает его в `set_flag_on_success` и обновляет выпадающий список.
@export_tool_button("Register & Assign Flag") var register_flag_btn: Callable = _quick_register_flag

## Кнопка редактора: регистрирует текущий `object_id` этого узла в списке постоянных объектов [QuestRegistry].
@export_tool_button("Register Object ID") var register_obj_btn: Callable = _quick_register_object_id

@export_group("Physics & Collision")
@export_subgroup("Obstacle & Navigation")
## Делает объект физически непроходимым препятствием: создаёт внутренний `StaticBody3D`,
## автоматически перемещает узел внутрь `NavigationRegion3D` и перезапекает навигационную сетку (NavMesh).
@export var is_solid_obstacle: bool = false:
	set(val):
		is_solid_obstacle = val
		if is_inside_tree():
			_handle_obstacle_toggle(val)

## Если включено, размер физического препятствия рассчитывается автоматически по границам текущего 2D-спрайта или 3D-меша.
@export var auto_size_obstacle: bool = true:
	set(val):
		auto_size_obstacle = val
		if is_inside_tree():
			_refresh_obstacle()
			if is_solid_obstacle:
				_auto_bake_nav_mesh()

## Ручной размер коробки физического препятствия в метрах (используется, когда `auto_size_obstacle` выключен).
@export var obstacle_size: Vector3 = Vector3(1.0, 1.0, 1.0):
	set(val):
		obstacle_size = val
		if is_inside_tree():
			_refresh_obstacle()
			if is_solid_obstacle:
				_auto_bake_nav_mesh()

@export_subgroup("Interaction Area")
## Инструмент редактора: при установке галочки автоматически создаёт или подгоняет дочерний `CollisionShape3D` (`BoxShape3D`)
## под габариты визуального представления объекта, после чего сбрасывается обратно в `false`.
@export var generate_box_collision: bool = false:
	set(val):
		if val:
			_generate_box_collision()
		generate_box_collision = false

@export_group("Visual Representation")
## Режим визуального отображения объекта:
## [br]• `External / Custom` (0) — использует собственные дочерние узлы сцены, добавленные вручную;
## [br]• `2D Sprite / Sequence` (1) — создаёт внутренний 2.5D-спрайт или анимацию;
## [br]• `3D Mesh` (2) — создаёт внутренний `MeshInstance3D` с указанным ресурсом `mesh_resource`.
@export_enum("External / Custom", "2D Sprite / Sequence", "3D Mesh") var visual_mode: int = 0:
	set(val):
		visual_mode = val
		if is_inside_tree():
			_refresh_all_geometry()

## Ресурс 3D-меша для отображения в режиме `3D Mesh` (`visual_mode == 2`).
@export var mesh_resource: Mesh = null:
	set(val):
		mesh_resource = val
		if is_inside_tree():
			_refresh_all_geometry()

## Переопределение материала для внутреннего 3D-меша в режиме `3D Mesh`.
@export var mesh_material_override: Material = null:
	set(val):
		mesh_material_override = val
		if is_inside_tree():
			_refresh_visuals()

@export_group("2D Sprite Settings")
@export_subgroup("Texture & Atlas")
## Статическая текстура или спрайт-лист для режима `2D Sprite / Sequence` (когда `sprite_frames` не задан).
@export var sprite_texture: Texture2D = null:
	set(val):
		sprite_texture = val
		if is_inside_tree():
			_refresh_all_geometry()

## Количество кадров по горизонтали в текстуре-атласе `sprite_texture`.
@export_range(1, 64, 1) var hframes: int = 1:
	set(val):
		hframes = maxi(1, val)
		if is_inside_tree():
			_refresh_visuals()
			_refresh_obstacle()

## Количество кадров по вертикали в текстуре-атласе `sprite_texture`.
@export_range(1, 64, 1) var vframes: int = 1:
	set(val):
		vframes = maxi(1, val)
		if is_inside_tree():
			_refresh_visuals()
			_refresh_obstacle()

## Индекс отображаемого кадра из текстуры-атласа `sprite_texture` (от `0` до `hframes * vframes - 1`).
@export var frame: int = 0:
	set(val):
		frame = maxi(0, val)
		if is_inside_tree():
			_refresh_visuals()

@export_subgroup("Animation Sequence")
## Ресурс покадровой анимации `SpriteFrames`. Если назначен, вместо статического `Sprite3D` используется `AnimatedSprite3D`.
@export var sprite_frames: SpriteFrames = null:
	set(val):
		sprite_frames = val
		if is_inside_tree():
			_refresh_all_geometry()

## Имя анимации в `sprite_frames`, проигрываемой в исходном состоянии (`"default"`).
@export var default_anim: String = "default":
	set(val):
		default_anim = val
		if is_inside_tree():
			_update_sprite_animation_for_state()

## Имя анимации в `sprite_frames`, проигрываемой после перехода объекта в состояние `"active"`.
@export var active_anim: String = "active":
	set(val):
		active_anim = val
		if is_inside_tree():
			_update_sprite_animation_for_state()

## Если включено, выбранная анимация в `sprite_frames` запускается автоматически.
@export var auto_play_anim: bool = true:
	set(val):
		auto_play_anim = val
		if is_inside_tree():
			_update_sprite_animation_for_state()

@export_subgroup("Orientation & Anchor")
## Отражает 2D-спрайт по горизонтали.
@export var flip_h: bool = false:
	set(val):
		flip_h = val
		if is_inside_tree():
			_refresh_visuals()

## Режим поворота 2D-спрайта к камере:
## [br]• `Y-Billboard` (0) — вращение только вокруг вертикальной оси Y;
## [br]• `Fixed / Disabled` (1) — фиксированная ориентация в пространстве (для настенных панелей и плакатов);
## [br]• `Full Billboard` (2) — полный поворот лицом к камере по всем осям.
@export_enum("Y-Billboard", "Fixed / Disabled", "Full Billboard") var billboard_mode: int = 0:
	set(val):
		billboard_mode = val
		if is_inside_tree():
			_refresh_visuals()

## Точка привязки (pivot) 2D-спрайта относительно позиции узла:
## [br]• `Bottom Center` (0) — нижний край спрайта стоит на уровне пола (Y = 0 локально);
## [br]• `Top Center` (1) — верхний край привязан к точке узла (для потолочных объектов);
## [br]• `Center` (2) — геометрический центр спрайта в начале координат узла.
@export_enum("Bottom Center", "Top Center", "Center") var sprite_anchor: int = 0:
	set(val):
		sprite_anchor = val
		if is_inside_tree():
			_refresh_all_geometry()

## Дополнительное смещение 2D-спрайта в пикселях относительно выбранной точки привязки (`sprite_anchor`).
@export var custom_pixel_offset: Vector2 = Vector2.ZERO:
	set(val):
		custom_pixel_offset = val
		if is_inside_tree():
			_refresh_all_geometry()

@export_group("Material & Lighting")
## Размер одного пикселя 2D-спрайта в метрах трёхмерного пространства (определяет физический масштаб спрайта в мире).
@export var pixel_size: float = 0.01:
	set(val):
		pixel_size = maxf(0.0005, val)
		if is_inside_tree():
			_refresh_all_geometry()

## Если включено, 2D-спрайт воспринимает освещение и тени от источников света в комнате (`Light3D`).
@export var shaded: bool = true:
	set(val):
		shaded = val
		if is_inside_tree():
			_refresh_visuals()

## Порог альфа-отсечения (`alpha_scissor_threshold`) для чётких краёв спрайта и корректного отбрасывания силуэтной тени.
@export_range(0.0, 1.0, 0.01) var alpha_scissor_threshold: float = 0.5:
	set(val):
		alpha_scissor_threshold = clampf(val, 0.0, 1.0)
		if is_inside_tree():
			_refresh_visuals()

## Режим отбрасывания теней:
## [br]• `Off` (0) — без теней;
## [br]• `On` (1) — односторонняя тень;
## [br]• `Double-Sided` (2) — двусторонняя силуэтная тень (рекомендуется для 2.5D-спрайтов).
@export_enum("Off", "On", "Double-Sided") var shadow_casting_mode: int = 2:
	set(val):
		shadow_casting_mode = val
		if is_inside_tree():
			_refresh_visuals()


func _ready() -> void:
	_refresh_visuals()
	_refresh_obstacle()
	_ensure_interaction_collision(false)

	if is_solid_obstacle and Engine.is_editor_hint():
		var nav_region: NavigationRegion3D = NavigationUtils.find_region(self)
		if nav_region != null and get_parent() != nav_region:
			_handle_obstacle_toggle(true)

	if Engine.is_editor_hint():
		return

	current_state = QuestActionExecutor.restore_state(
		object_id,
		set_flag_on_success,
		one_shot,
		current_state
	)

	if current_state == "active":
		QuestActionExecutor.update_visual_nodes(self, nodes_to_show_on_success, nodes_to_hide_on_success, true)
		QuestActionExecutor.apply_target_state_if_completed(self, target_node)
		if trigger_mode == 1:
			monitoring = false
	else:
		QuestActionExecutor.update_visual_nodes(self, nodes_to_show_on_success, nodes_to_hide_on_success, false)

	_update_sprite_animation_for_state()

	if trigger_mode == 1 and not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Выполняет взаимодействие игрока с данным объектом (вызывается из `Player` или при входе в триггер).
func interact(player_node: CharacterBody3D = null) -> void:
	var succeeded: bool = QuestActionExecutor.process_interaction(
		self,
		player_node,
		current_state,
		required_item,
		consume_item,
		target_node,
		set_flag_on_success,
		inspect_text,
		active_inspect_text,
		fail_text
	)
	if succeeded:
		_execute_success()


func _execute_success() -> void:
	current_state = "active"
	QuestActionExecutor.execute_success(
		self,
		object_id,
		set_flag_on_success,
		one_shot,
		trigger_mode,
		target_node,
		nodes_to_show_on_success,
		nodes_to_hide_on_success,
		success_text,
		active_inspect_text,
		inspect_text
	)
	_update_sprite_animation_for_state()


func _on_body_entered(body: Node) -> void:
	if trigger_mode != 1 or current_state == "active":
		return
	if body is CharacterBody3D and (body.name == "Player" or body.has_method("move_to")):
		interact(body as CharacterBody3D)


func _build_render_settings() -> SpriteRenderSettings:
	var settings := SpriteRenderSettings.new()
	settings.pixel_size = pixel_size
	settings.flip_h = flip_h
	settings.shaded = shaded
	settings.alpha_scissor_threshold = alpha_scissor_threshold
	settings.billboard_mode = billboard_mode as SpriteRenderSettings.BillboardMode
	settings.shadow_mode = shadow_casting_mode as SpriteRenderSettings.ShadowMode
	settings.anchor = sprite_anchor as SpriteRenderSettings.Anchor
	settings.pixel_offset = custom_pixel_offset
	return settings


func _refresh_all_geometry() -> void:
	_refresh_visuals()
	_refresh_obstacle()
	_ensure_interaction_collision(true)
	if is_solid_obstacle:
		_auto_bake_nav_mesh()


func _refresh_visuals() -> void:
	InteractableVisualRig.refresh_visuals(
		self,
		visual_mode,
		mesh_resource,
		mesh_material_override,
		sprite_texture,
		hframes,
		vframes,
		frame,
		sprite_frames,
		_build_render_settings(),
		current_state,
		default_anim,
		active_anim,
		auto_play_anim
	)


func _update_sprite_animation_for_state() -> void:
	InteractableVisualRig.update_sprite_animation(
		self,
		visual_mode,
		sprite_frames,
		current_state,
		default_anim,
		active_anim,
		auto_play_anim,
		_build_render_settings(),
		sprite_texture,
		hframes,
		vframes
	)


func _get_visual_bounds() -> Dictionary:
	return InteractableVisualRig.compute_visual_bounds(
		self,
		visual_mode,
		mesh_resource,
		sprite_frames,
		sprite_texture,
		hframes,
		vframes,
		current_state,
		default_anim,
		active_anim,
		_build_render_settings()
	)


func _refresh_obstacle() -> void:
	InteractablePhysicsBuilder.refresh_obstacle(
		self,
		is_solid_obstacle,
		auto_size_obstacle,
		obstacle_size,
		visual_mode,
		sprite_anchor,
		_get_visual_bounds()
	)


func _ensure_interaction_collision(allow_update_if_internal: bool = false) -> void:
	InteractablePhysicsBuilder.ensure_interaction_collision(
		self,
		_get_visual_bounds(),
		visual_mode,
		allow_update_if_internal
	)


func _generate_box_collision() -> void:
	InteractablePhysicsBuilder.generate_box_collision(self, _get_visual_bounds())


func _handle_obstacle_toggle(enabled: bool) -> void:
	InteractablePhysicsBuilder.handle_obstacle_toggle(
		self,
		enabled,
		auto_size_obstacle,
		obstacle_size,
		visual_mode,
		sprite_anchor,
		_get_visual_bounds()
	)


func _auto_bake_nav_mesh() -> void:
	if not is_inside_tree():
		return
	var nav_region: NavigationRegion3D = NavigationUtils.find_region(self)
	NavigationUtils.request_bake(nav_region, true)


func _get_configuration_warnings() -> PackedStringArray:
	return InteractablePhysicsBuilder.get_configuration_warnings(self)


func _validate_property(property: Dictionary) -> void:
	var prop_name: String = str(property.get("name", ""))
	if prop_name == "required_item":
		QuestRegistry.configure_item_property_hint(property, required_item, true)
	elif prop_name == "set_flag_on_success":
		QuestRegistry.configure_flag_property_hint(property, set_flag_on_success, true)


func _quick_register_item() -> void:
	var target_id: String = quick_register_id.strip_edges()
	if target_id.is_empty():
		target_id = required_item.strip_edges()
	if target_id.is_empty():
		push_warning("QuestInteractable: Укажите quick_register_id для регистрации нового предмета в QuestRegistry.")
		return
	var desc: String = quick_register_description.strip_edges()
	if desc.is_empty():
		desc = "Предмет, зарегистрированный из узла %s" % name
	QuestRegistry.register_and_save_item(target_id, target_id, "Quest Item", desc)
	required_item = target_id
	quick_register_id = ""
	quick_register_description = ""
	notify_property_list_changed()


func _quick_register_flag() -> void:
	var target_id: String = quick_register_id.strip_edges()
	if target_id.is_empty():
		target_id = set_flag_on_success.strip_edges()
	if target_id.is_empty() and not object_id.strip_edges().is_empty():
		target_id = object_id.strip_edges()
	if target_id.is_empty():
		push_warning("QuestInteractable: Укажите quick_register_id для регистрации нового флага в QuestRegistry.")
		return
	var desc: String = quick_register_description.strip_edges()
	if desc.is_empty():
		desc = "Флаг, зарегистрированный из узла %s" % name
	QuestRegistry.register_and_save_flag(target_id, false, "Puzzle", desc)
	set_flag_on_success = target_id
	quick_register_id = ""
	quick_register_description = ""
	notify_property_list_changed()


func _quick_register_object_id() -> void:
	var target_id: String = object_id.strip_edges()
	if target_id.is_empty():
		target_id = quick_register_id.strip_edges()
	if target_id.is_empty():
		push_warning("QuestInteractable: Поле object_id пусто — нечего регистрировать.")
		return
	object_id = target_id
	QuestRegistry.register_and_save_object_id(target_id)
	notify_property_list_changed()
