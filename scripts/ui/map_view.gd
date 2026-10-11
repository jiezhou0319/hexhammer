## map_view.gd — 地图场景挂载（M1a-T3 view 层；ADR-13；调研架构位 MapView/TerrainChunk）
## view 层纪律：本文件属 scripts/ui/**，可被整体删除——tests/ 与 addons/ 几何构建器
##   均不感知本文件（「删 scripts/ui/** 后 tests 全绿」的分层验收口径，02 §3）。
## 挂载规则：
## - 每 chunk 一个 MeshInstance3D（60×40 / 10×10 = 24 节点），绝不每格一个场景节点
##   （04 M1a-T3 细化）；chunk 节点名含 offset 原点，便于场景树目检。
## - mesh 顶点已是地图全局坐标（构建器约定）→ chunk 节点全部置于原点、零偏移——
##   接缝零错位的挂载面保证（节点一偏移就破坏全局坐标约定）。
## - 碰撞/拾取挂 T5、高亮挂 T7、相机 rig 挂 T6——本文件只做静态地形挂载。
##   例外（T3/T4 表现层伴生）：水面/路面第二 mesh 零碰撞体随 world 挂载；桥面
##   碰撞汤（LAYER_TERRAIN）是拾取通道的一部分（桥面先于河床命中，ROAD-02 ④）。
class_name MapView
extends Node3D

const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const TerrainStyleClass := preload("res://scripts/core/data/terrain_style.gd")
const LandformProfileClass := preload("res://scripts/core/data/landform_profile.gd")
const GridLineBuilder := preload("res://addons/hexhammer/hex_grid_line_builder.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const WaterBuilder := preload("res://addons/hexhammer/water_geometry_builder.gd")
const RoadBuilder := preload("res://addons/hexhammer/road_geometry_builder.gd")

var chunk_nodes: Array[MeshInstance3D] = []
## 格线层节点（GRID-01：独立 mesh 层，每 chunk 一个 MeshInstance3D、零碰撞体——
## 不进拾取层；style 关格线时恒空）
var grid_nodes: Array[MeshInstance3D] = []
## 水面层节点（T3 WATER-02：水面第二 mesh，每 chunk 一个 MeshInstance3D、零碰撞
## 体——不进拾取层（LAYER_TERRAIN 之外的纯表现层）；无河无水体时恒空）
var water_nodes: Array[MeshInstance3D] = []
## 路面层节点（T4 ROAD-01/02：路面/桥面第二 mesh，每 chunk 一个 MeshInstance3D、
## 零碰撞体——路面不进拾取层；桥面碰撞汤由 deck_pick_bodies 单独挂 LAYER_TERRAIN
## （桥面拾取先于河床命中，ROAD-02 ④）；无路无桥时两数组恒空）
var road_nodes: Array[MeshInstance3D] = []
## 桥面碰撞体（LAYER_TERRAIN——桥面进碰撞则射线先于河床命中；face 表在
## build_info.road_chunks[i].deck_face_table，拾取解析走 bridge_deck 分支）
var deck_pick_bodies: Array[StaticBody3D] = []
var build_info: Dictionary = {}

## 按材质表构建（materials = 地形 id → Material 映射；.tres 载体 =
## TerrainMaterialLibrary.materials，主线默认表 resources/terrain/terrain_materials_default.tres
## ——M1a-T8 材质槽；elevation_step/solid_factor 透传 T4 高程几何参数；
## profile = LandformProfile 几何档（T2 起：null/全关 = 基线单斜面+80° 陡面，
## 阶地/真崖档见 addons/hexhammer/hex_terrain_builder.gd 头注）；
## world = WorldData（T3 起可选：有河 link 边带下切 + 水面第二 mesh；T4 起有路/桥
## 时另建路面第二 mesh + 桥面碰撞汤）；
## water_material = 水面材质，null = 官方工厂；road_material = 路面材质，null = 工厂）。
## 构建失败（材质表缺图内 id、表值非 Material、参数非法等）→ false。
func build(map: MapDataClass, chunk_cols := 10, chunk_rows := 10, materials := {},
		size := 1.0, elevation_step := 1.0, solid_factor := 0.8,
		profile: LandformProfileClass = null, world: WorldDataClass = null,
		water_material: Material = null, road_material: Material = null) -> bool:
	clear()
	var result: Variant = Builder.build_map(map, chunk_cols, chunk_rows, materials,
		size, elevation_step, solid_factor, profile, world)
	if not _mount(result):
		return false
	if not _mount_water(map, world, chunk_cols, chunk_rows, water_material,
			size, elevation_step, solid_factor):
		return false
	return _mount_road(map, world, chunk_cols, chunk_rows, road_material,
		size, elevation_step, solid_factor)


## 按色板权重混合构建（M1a+ BLEND-01；palette = 地形 id → Color，blend_material =
## 顶点色 albedo 导管——官方工厂 HexTerrainBlend.make_blend_material，传 null → 构建
## 失败）。色板建议来源 = HexTerrainBlend.palette_from_materials(材质库.materials)
## ——与 fallback 共用同一 .tres，换表即两风格同时换观感。mesh 顶点 COLOR 承载过渡
## 权重；几何/face 表与 build 完全一致（拾取/碰撞挂接不变——同一 setup 入口）。
## 构建失败（色板缺图内 id、色值非法、参数非法等）→ false。
func build_blend(map: MapDataClass, palette: Dictionary, chunk_cols := 10, chunk_rows := 10,
		blend_material: Material = null, size := 1.0, elevation_step := 1.0,
		solid_factor := 0.8, profile: LandformProfileClass = null,
		world: WorldDataClass = null, water_material: Material = null,
		road_material: Material = null) -> bool:
	clear()
	var result: Variant = Builder.build_map_blend(map, palette, chunk_cols, chunk_rows,
		blend_material, size, elevation_step, solid_factor, profile, world)
	if not _mount(result):
		return false
	if not _mount_water(map, world, chunk_cols, chunk_rows, water_material,
			size, elevation_step, solid_factor):
		return false
	return _mount_road(map, world, chunk_cols, chunk_rows, road_material,
		size, elevation_step, solid_factor)


## 按 style 资源构建（M1a+ BLEND-03「纹理可替换，不改世界事实」的换装入口）：
## style = TerrainStyle .tres（检查器可换——mode 选 SLOTS 色块 / BLEND 过渡，
## material_library 是两路线共同外观来源）。解析在数据层（style.inputs_for），
## 本方法只按 mode 分发到 build / build_blend 同一挂载面——换 style 不换几何/
## face 表/碰撞（不变量锚 = tests/test_terrain_style.gd：summary/ARRAY_INDEX/
## face 表逐位一致、材质实例不同）。
## style 为空 / 对本图不可解析（缺库/缺槽/BLEND 缺导管/格线参数非法）→ false。
func build_with_style(map: MapDataClass, style: TerrainStyleClass, chunk_cols := 10,
		chunk_rows := 10, size := 1.0, elevation_step := 1.0,
		solid_factor := 0.8, profile: LandformProfileClass = null,
		world: WorldDataClass = null) -> bool:
	if style == null:
		return false
	var inputs: Variant = style.inputs_for(map)
	if not (inputs is Dictionary):
		return false
	var d: Dictionary = inputs
	var ok := false
	if d["mode"] == "blend":
		ok = build_blend(map, d["palette"], chunk_cols, chunk_rows,
			d["blend_material"], size, elevation_step, solid_factor, profile,
			world, d["water_material"], d.get("road_material"))
	else:
		ok = build(map, chunk_cols, chunk_rows, d["materials"], size,
			elevation_step, solid_factor, profile, world,
			d["water_material"], d.get("road_material"))
	if not ok:
		return false
	# 格线层（GRID-01）：输入带 grid_line 键（style.grid_line_enabled）才建——
	# 独立 mesh、零碰撞体（不截获拾取）；关 = 不建 = 地形与无格线基线逐位一致
	if d.has("grid_line"):
		return _mount_grid(map, chunk_cols, chunk_rows, d["grid_line"], size, elevation_step)
	return true


## 格线层挂载：每 chunk 一个 MeshInstance3D（同地形挂载面：顶点已是全局坐标、
## 节点零偏移；材质 = style 解析出的格线材质）。
func _mount_grid(map: MapDataClass, chunk_cols: int, chunk_rows: int,
		grid_inputs: Dictionary, size: float, elevation_step: float) -> bool:
	var result: Variant = GridLineBuilder.build_map(map, chunk_cols, chunk_rows,
		grid_inputs["material"], size, elevation_step, grid_inputs["width"])
	if not (result is Dictionary):
		return false
	for chunk_info in (result as Dictionary)["chunks"]:
		var cd: Dictionary = chunk_info
		var rect: Rect2i = cd["chunk"]
		var node := MeshInstance3D.new()
		node.name = "GridLine_c%d_r%d" % [rect.position.x, rect.position.y]
		node.mesh = cd["mesh"] as ArrayMesh
		add_child(node)
		grid_nodes.append(node)
	return true


## 水面层挂载（T3 WATER-02）：每 chunk 一个 MeshInstance3D（同地形挂载面：顶点已
## 是全局坐标、节点零偏移）；**零碰撞体、不进拾取层**（水面不截获地形拾取）。
## world 为空或无河无水体 → 不建（合法态：无河世界 = 无水面层）；材质 = 调用方
## 传入或官方工厂。
func _mount_water(map: MapDataClass, world: WorldDataClass, chunk_cols: int,
		chunk_rows: int, water_material: Material, size: float,
		elevation_step: float, solid_factor: float) -> bool:
	if world == null or (world.rivers.is_empty() and world.water_bodies.is_empty()):
		return true  # 无河无水体：无水面层（「没有能力就没有数据」的渲染面）
	var mat := water_material if water_material != null \
		else WaterBuilder.make_water_material()
	var result: Variant = WaterBuilder.build_map(map, world, chunk_cols, chunk_rows,
		mat, size, elevation_step, solid_factor)
	if not (result is Dictionary):
		return false
	for chunk_info in (result as Dictionary)["chunks"]:
		var cd: Dictionary = chunk_info
		var rect: Rect2i = cd["chunk"]
		if (cd["mesh"] as ArrayMesh).get_surface_count() == 0:
			continue  # 本 chunk 无水面几何（无河无水体成员）——不挂空节点
		var node := MeshInstance3D.new()
		node.name = "Water_c%d_r%d" % [rect.position.x, rect.position.y]
		node.mesh = cd["mesh"] as ArrayMesh
		add_child(node)
		water_nodes.append(node)
	return true


## 路面层挂载（T4 ROAD-01/02）：每 chunk 一个 MeshInstance3D（同地形挂载面：顶点
## 已是全局坐标、节点零偏移）——**零地形碰撞体**（路面贴本格顶面，穿面命中地形
## 面归属同格，无需另建）；**桥面碰撞汤单独挂 LAYER_TERRAIN 体**（桥面进碰撞则
## 射线先于河床命中——候选 = bank 两格，ROAD-02 ④；拾取解析走 bridge_deck 分支，
## face 表随 build_info.road_chunks 留档）。world 为空或无路无桥 → 不建（合法态）。
func _mount_road(map: MapDataClass, world: WorldDataClass, chunk_cols: int,
		chunk_rows: int, road_material: Material, size: float,
		elevation_step: float, solid_factor: float) -> bool:
	if world == null or (world.roads.is_empty() and world.crossings.is_empty()):
		return true  # 无路无桥：无路面层（「没有能力就没有数据」的渲染面）
	var mat := road_material if road_material != null \
		else RoadBuilder.make_road_material()
	var result: Variant = RoadBuilder.build_map(map, world, chunk_cols, chunk_rows,
		mat, size, elevation_step, solid_factor)
	if not (result is Dictionary):
		return false
	build_info["road_chunks"] = (result as Dictionary)["chunks"]
	for chunk_info in (result as Dictionary)["chunks"]:
		var cd: Dictionary = chunk_info
		var rect: Rect2i = cd["chunk"]
		if (cd["mesh"] as ArrayMesh).get_surface_count() == 0:
			continue  # 本 chunk 无路面几何（无路格）——不挂空节点
		var node := MeshInstance3D.new()
		node.name = "Road_c%d_r%d" % [rect.position.x, rect.position.y]
		node.mesh = cd["mesh"] as ArrayMesh
		add_child(node)
		road_nodes.append(node)
		# 桥面碰撞体：deck_collision 三角汤 → ConcavePolygonShape3D（与地形碰撞体
		# 同形状/同层；face_index ↔ deck_face_table 逐索引对应——桥面拾取通道）
		var soup: PackedVector3Array = cd["deck_collision"]
		if soup.size() == 0:
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(soup)
		var body := StaticBody3D.new()
		body.name = "DeckCollision_c%d_r%d" % [rect.position.x, rect.position.y]
		body.collision_layer = 1  # LAYER_TERRAIN（HexPicking.LAYER_TERRAIN = 1）
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
		deck_pick_bodies.append(body)
	return true


## 构建结果挂载（两 style 共用：每 chunk 一个 MeshInstance3D、节点置原点零偏移——
## mesh 顶点已是全局坐标；非 Dictionary 构建结果 → false）。
func _mount(result: Variant) -> bool:
	if not (result is Dictionary):
		return false
	var chunks: Array = (result as Dictionary)["chunks"]
	for chunk_info in chunks:
		var cd: Dictionary = chunk_info
		var rect: Rect2i = cd["chunk"]
		var node := MeshInstance3D.new()
		node.name = "Chunk_c%d_r%d" % [rect.position.x, rect.position.y]
		node.mesh = cd["mesh"] as ArrayMesh
		add_child(node)
		chunk_nodes.append(node)
	build_info = result as Dictionary
	return true

func clear() -> void:
	for node in chunk_nodes:
		node.queue_free()
	chunk_nodes.clear()
	for node in grid_nodes:
		node.queue_free()
	grid_nodes.clear()
	for node in water_nodes:
		node.queue_free()
	water_nodes.clear()
	for node in road_nodes:
		node.queue_free()
	road_nodes.clear()
	for body in deck_pick_bodies:
		body.queue_free()
	deck_pick_bodies.clear()
	build_info = {}
