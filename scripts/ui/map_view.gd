## map_view.gd — 地图场景挂载（M1a-T3 view 层；ADR-13；调研架构位 MapView/TerrainChunk）
## view 层纪律：本文件属 scripts/ui/**，可被整体删除——tests/ 与 addons/ 几何构建器
##   均不感知本文件（「删 scripts/ui/** 后 tests 全绿」的分层验收口径，02 §3）。
## 挂载规则：
## - 每 chunk 一个 MeshInstance3D（60×40 / 10×10 = 24 节点），绝不每格一个场景节点
##   （04 M1a-T3 细化）；chunk 节点名含 offset 原点，便于场景树目检。
## - mesh 顶点已是地图全局坐标（构建器约定）→ chunk 节点全部置于原点、零偏移——
##   接缝零错位的挂载面保证（节点一偏移就破坏全局坐标约定）。
## - 碰撞/拾取挂 T5、高亮挂 T7、相机 rig 挂 T6——本文件只做静态地形挂载。
class_name MapView
extends Node3D

const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const TerrainStyleClass := preload("res://scripts/core/data/terrain_style.gd")

var chunk_nodes: Array[MeshInstance3D] = []
var build_info: Dictionary = {}

## 按材质表构建（materials = 地形 id → Material 映射；.tres 载体 =
## TerrainMaterialLibrary.materials，主线默认表 resources/terrain/terrain_materials_default.tres
## ——M1a-T8 材质槽；elevation_step/solid_factor 透传 T4 高程几何参数）。
## 构建失败（材质表缺图内 id、表值非 Material、参数非法等）→ false。
func build(map: MapDataClass, chunk_cols := 10, chunk_rows := 10, materials := {},
		size := 1.0, elevation_step := 1.0, solid_factor := 0.8) -> bool:
	clear()
	var result: Variant = Builder.build_map(map, chunk_cols, chunk_rows, materials,
		size, elevation_step, solid_factor)
	return _mount(result)


## 按色板权重混合构建（M1a+ BLEND-01；palette = 地形 id → Color，blend_material =
## 顶点色 albedo 导管——官方工厂 HexTerrainBlend.make_blend_material，传 null → 构建
## 失败）。色板建议来源 = HexTerrainBlend.palette_from_materials(材质库.materials)
## ——与 fallback 共用同一 .tres，换表即两风格同时换观感。mesh 顶点 COLOR 承载过渡
## 权重；几何/face 表与 build 完全一致（拾取/碰撞挂接不变——同一 setup 入口）。
## 构建失败（色板缺图内 id、色值非法、参数非法等）→ false。
func build_blend(map: MapDataClass, palette: Dictionary, chunk_cols := 10, chunk_rows := 10,
		blend_material: Material = null, size := 1.0, elevation_step := 1.0,
		solid_factor := 0.8) -> bool:
	clear()
	var result: Variant = Builder.build_map_blend(map, palette, chunk_cols, chunk_rows,
		blend_material, size, elevation_step, solid_factor)
	return _mount(result)


## 按 style 资源构建（M1a+ BLEND-03「纹理可替换，不改世界事实」的换装入口）：
## style = TerrainStyle .tres（检查器可换——mode 选 SLOTS 色块 / BLEND 过渡，
## material_library 是两路线共同外观来源）。解析在数据层（style.inputs_for），
## 本方法只按 mode 分发到 build / build_blend 同一挂载面——换 style 不换几何/
## face 表/碰撞（不变量锚 = tests/test_terrain_style.gd：summary/ARRAY_INDEX/
## face 表逐位一致、材质实例不同）。
## style 为空 / 对本图不可解析（缺库/缺槽/BLEND 缺导管）→ false。
func build_with_style(map: MapDataClass, style: TerrainStyleClass, chunk_cols := 10,
		chunk_rows := 10, size := 1.0, elevation_step := 1.0,
		solid_factor := 0.8) -> bool:
	if style == null:
		return false
	var inputs: Variant = style.inputs_for(map)
	if not (inputs is Dictionary):
		return false
	var d: Dictionary = inputs
	if d["mode"] == "blend":
		return build_blend(map, d["palette"], chunk_cols, chunk_rows,
			d["blend_material"], size, elevation_step, solid_factor)
	return build(map, chunk_cols, chunk_rows, d["materials"], size,
		elevation_step, solid_factor)


## 构建结果挂载（两 style 共用：每 chunk 一个 MeshInstance3D、节点置原点零偏移——
## mesh 顶点已是地图全局坐标；非 Dictionary 构建结果 → false）。
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
	build_info = {}
