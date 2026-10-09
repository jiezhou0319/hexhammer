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
	if not (result is Dictionary):
		return false
	var chunks: Array = result["chunks"]
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
