@tool
class_name NavigationUtils
extends RefCounted
## Поиск [NavigationRegion3D] и безопасный запуск запекания навигационной сетки.
##
## [NavigationRegion3D] по умолчанию анализирует только свои дочерние узлы, поэтому
## препятствия должны находиться внутри региона. Все проверки и запуски запекания
## проходят через этот класс, чтобы не дублировать логику в сущностях.

const _PENDING_REBAKE_META: StringName = &"_nav_rebake_pending"

const DEFAULT_CELL_SIZE: float = 0.25
const DEFAULT_CELL_HEIGHT: float = 0.25
const DEFAULT_AGENT_HEIGHT: float = 2.0
const DEFAULT_AGENT_RADIUS: float = 0.5
const DEFAULT_AGENT_MAX_CLIMB: float = 0.25


## Находит регион навигации для [param node]: сначала среди предков, затем среди
## потомков корня сцены. Возвращает null, если регион не найден.
static func find_region(node: Node) -> NavigationRegion3D:
	if node == null:
		return null
	var ancestor: Node = SceneTreeUtils.find_ancestor(node, func(n: Node) -> bool: return n is NavigationRegion3D)
	if ancestor != null:
		return ancestor as NavigationRegion3D

	var scene_root: Node = SceneTreeUtils.resolve_scene_root(node)
	if scene_root == null:
		return null
	if scene_root is NavigationRegion3D:
		return scene_root as NavigationRegion3D
	var found: Array[Node] = scene_root.find_children("*", "NavigationRegion3D", true, false)
	if not found.is_empty():
		return found[0] as NavigationRegion3D
	return null


## true, если [param node] находится внутри [param region] (будет учтён при запекании).
static func is_inside_region(node: Node, region: NavigationRegion3D) -> bool:
	return node != null and region != null and region.is_ancestor_of(node)


## Настраивает анализ статических коллайдеров при запекании (без чтения GPU-мешей из RenderingServer),
## что устраняет предупреждение о парсинге визуальных мешей в рантайме.
static func enable_collider_parsing(region: NavigationRegion3D) -> void:
	if region == null or region.navigation_mesh == null:
		return
	if region.navigation_mesh.geometry_parsed_geometry_type != NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS:
		region.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS


## Стандартизирует параметры навигационной сетки для предотвращения предупреждений о потере точности вокселей
## и предупреждений о чтении GPU-мешей из RenderingServer при рантайм-запекании.
static func standardize_navigation_mesh(nav_mesh: NavigationMesh) -> void:
	if nav_mesh == null:
		return
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.cell_size = DEFAULT_CELL_SIZE
	nav_mesh.cell_height = DEFAULT_CELL_HEIGHT
	nav_mesh.agent_height = DEFAULT_AGENT_HEIGHT
	nav_mesh.agent_radius = DEFAULT_AGENT_RADIUS
	nav_mesh.agent_max_climb = DEFAULT_AGENT_MAX_CLIMB


## Запрашивает перезапекание. Если регион уже печётся, запрос не теряется:
## повторное запекание будет выполнено один раз сразу после завершения текущего.
static func request_bake(region: NavigationRegion3D, parse_colliders: bool = true, on_thread: bool = true) -> void:
	if region == null or region.navigation_mesh == null:
		return
	standardize_navigation_mesh(region.navigation_mesh)
	if region.is_baking():
		if not region.has_meta(_PENDING_REBAKE_META):
			region.set_meta(_PENDING_REBAKE_META, true)
			region.bake_finished.connect(func() -> void:
				if is_instance_valid(region):
					region.remove_meta(_PENDING_REBAKE_META)
					request_bake(region, false, on_thread)
			, CONNECT_ONE_SHOT)
		return
	region.bake_navigation_mesh(on_thread)
