## hex_terrain_builder.gd — 平地地形网格几何构建（M1a-T3；docs/04-tasks-m1.md M1a-T3
##   + docs/hexhammer-m1a-map-implementation-research.md「Mesh、分块与材质」「推荐的最小架构」）
## 约定与决策（翻案须先改 04 对应验收，不动架构）：
## - 纯逻辑类：RefCounted、零场景节点（ADR-2）；产出 ArrayMesh（Resource，headless 可建
##   可测）+ 元数据 Dictionary。场景挂载在 scripts/ui/map_view.gd（view 层）——删
##   scripts/ui/** 不影响本文件与 tests/（分层纪律的可执行表达，02 §3 验收口径）。
## - 依赖方向：本文件 → hex_math.gd（T1）+ map_data.gd（T2），只读不反向；几何读数据，
##   数据层不感知渲染（02 §1 依赖只向下）。
## - chunk 制：offset (col,row) 空间矩形（Rect2i）划分、右/下越界裁剪；60×40 / 10×10
##   = 6×4 = 24 块。chunk 边界 ≠ 地图边界——每格几何只由本格全局数据决定，不存在跨块
##   悬空面。每 chunk 按地形类型组织 surface（类型首次出现序），不每格一个 surface。
## - 顶点一律用地图全局坐标（HexMath.axial_to_world / cell_vertex 同一公式现算），
##   chunk 节点不偏移——相邻 chunk 接缝顶点按构造逐位相等（04 M1a-T3 细化：「接缝
##   顶点从同一全局格心/边参数计算，不在两个 chunk 内各自扰动」）。
## - 几何（首版平地；elevation 属 T4，本版不读）：每格 = 格心 + 6 外顶点的三角扇，
##   6 三角 / 18 索引 / 7 顶点；顶点 i = HexMath.cell_vertex（顶点角 30°−60°·i）；
##   三角 (格心, v_i, v_{i+1})：u(θi)×u(θi+1) 的 y 分量 = sin(θi−θi+1) = sin60° > 0，
##   法线恒 +Y（正面朝上）。
## - 法线：显式 (0,1,0)（平顶硬法线；不用 generate_normals——按共享顶点平滑，不符约定）。
## - UV 约定（T8「换贴图不改主线」的接口地基）：顶面 UV = 以格心为原点、外接圆半径
##   归一的 [0,1]²：u = 0.5 + (x−cx)/(2·size)、v = 0.5 − (z−cz)/(2·size)
##   （v 北零：−z → v 减小，贴图上边 = 北）。
## - 材质槽 = 地形类型 → 材质映射表（色块起步：id → Color → StandardMaterial3D；T8 材质
##   资源化时换 .tres 表，本文件接口不变）。不用顶点色显示地形，故材质不开
##   vertex_color_use_as_albedo（04 M1a-T3 细化：若改顶点色路线须显式开该属性，默认 false）。
## - 色表缺图内地形 id → 显式失败（返回 null，无隐式兜底色——与 MapData「无隐式兜底」同口径）。
## - 元数据结构（surfaces[i] 与 mesh 的 surface i 一一对应；cells/vertex_base 为 chunk 内
##   行主序）：{"chunk": Rect2i, "mesh": ArrayMesh, "surfaces": [{"terrain": int,
##   "cells": Array[Vector2i], "vertex_base": {axial → 7·i}, "vertex_count": int,
##   "index_count": int}]}；顶点寻址：vertex_base[cell] + 0 = 格心，+1+k = 顶点 k（k=0..5）。
class_name HexTerrainBuilder
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")

## 每格几何常量（三角扇）：7 顶点 / 18 索引（= 6 三角）
const VERTS_PER_CELL := 7
const INDICES_PER_CELL := 18

## 默认地形色板（色块起步的占位语义；「类型→含义」由内容层定，T8 材质资源化时替换）
const DEFAULT_TERRAIN_COLORS := {
	0: Color(0.36, 0.54, 0.30),  # 草
	1: Color(0.55, 0.45, 0.30),  # 泥
	2: Color(0.52, 0.52, 0.56),  # 岩
	3: Color(0.25, 0.40, 0.60),  # 水
	4: Color(0.78, 0.70, 0.45),  # 沙
	5: Color(0.20, 0.38, 0.22),  # 林
}

# ---------------- chunk 划分 ----------------

## 行主序产出覆盖全图的 chunk 矩形（右/下越界裁剪，无重叠无遗漏）。
## 图尺寸或 chunk 尺寸 ≤0 → 空数组（调用方据此显式失败，不静默出半张图）。
static func chunk_rects_for(map_width: int, map_height: int, chunk_cols: int, chunk_rows: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	if map_width <= 0 or map_height <= 0 or chunk_cols <= 0 or chunk_rows <= 0:
		return out
	var col0 := 0
	while col0 < map_width:
		var row0 := 0
		while row0 < map_height:
			out.append(Rect2i(
				col0, row0,
				mini(chunk_cols, map_width - col0),
				mini(chunk_rows, map_height - row0),
			))
			row0 += chunk_rows
		col0 += chunk_cols
	return out


## chunk 矩形内的格子（行主序，与 MapData.cells() 同序限制到矩形；矩形与图求交）。
static func chunk_cells(map: MapDataClass, chunk: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in range(chunk.position.y, chunk.position.y + chunk.size.y):
		if row < 0 or row >= map.height:
			continue
		for col in range(chunk.position.x, chunk.position.x + chunk.size.x):
			if col < 0 or col >= map.width:
				continue
			out.append(Hex.axial_of(Vector2i(col, row)))
	return out

# ---------------- 构建入口 ----------------

## 整图分块构建（SurfaceTool 起步，04 M1a-T3 细化；三角化已验证后再议 ArrayMesh 直填）。
## 返回 {"chunks": Array[chunk 字典], "chunk_rects": Array[Rect2i],
##   "materials": {被用到的 terrain id → 共享材质}, "size": float}；
## 任一地形 id 缺色表 → null（先全图预检后建，不做一半丢弃）。
static func build_map(map: MapDataClass, chunk_cols := 10, chunk_rows := 10, terrain_colors := {}, size := 1.0) -> Variant:
	var colors: Dictionary = terrain_colors if not terrain_colors.is_empty() else DEFAULT_TERRAIN_COLORS
	var needed := {}
	for cell in map.cells():
		var tid := map.terrain_at(cell)
		if tid == MapDataClass.TERRAIN_NONE or not colors.has(tid):
			return null
		needed[tid] = true
	var materials := {}
	for tid in needed:
		materials[tid] = _make_material(colors[tid])
	var chunks: Array = []
	var rects := chunk_rects_for(map.width, map.height, chunk_cols, chunk_rows)
	for rect in rects:
		var built: Variant = build_chunk(map, rect, materials, size)
		if built == null:
			return null
		chunks.append(built)
	return {"chunks": chunks, "chunk_rects": rects, "materials": materials, "size": size}


## 单 chunk 构建。materials 须含 chunk 内全部地形 id（build_map 已预建共享表；直调自备，
## 缺 id / 空矩形（无格）→ null）。
static func build_chunk(map: MapDataClass, chunk: Rect2i, materials: Dictionary, size := 1.0) -> Variant:
	var cells := chunk_cells(map, chunk)
	if cells.is_empty():
		return null
	# 按地形分组（组内保持 chunk 行主序；surface 序 = 类型首次出现序）
	var groups := {}
	var order: Array[int] = []
	for cell in cells:
		var tid := map.terrain_at(cell)
		if tid == MapDataClass.TERRAIN_NONE or not materials.has(tid):
			return null
		if not groups.has(tid):
			groups[tid] = [] as Array[Vector2i]
			order.append(tid)
		(groups[tid] as Array[Vector2i]).append(cell)
	var mesh := ArrayMesh.new()
	var surfaces: Array = []
	for tid in order:
		var group: Array[Vector2i] = groups[tid]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(materials[tid])
		var vertex_base := {}
		for i in group.size():
			var cell: Vector2i = group[i]
			var base := i * VERTS_PER_CELL
			vertex_base[cell] = base
			var center := Hex.axial_to_world(cell, size)
			_emit_vertex(st, center, center, size)  # 格心 → UV (0.5, 0.5)
			for k in 6:
				_emit_vertex(st, Hex.cell_vertex(cell, k, size), center, size)
			for k in 6:
				st.add_index(base)                          # 格心
				st.add_index(base + 1 + k)                  # 顶点 k
				st.add_index(base + 1 + (k + 1) % 6)        # 顶点 k+1（三角扇）
		st.commit(mesh)
		surfaces.append({
			"terrain": tid,
			"cells": group,
			"vertex_base": vertex_base,
			"vertex_count": group.size() * VERTS_PER_CELL,
			"index_count": group.size() * INDICES_PER_CELL,
		})
	return {"chunk": chunk, "mesh": mesh, "surfaces": surfaces}

# ---------------- 内部 ----------------

## 单顶点：法线恒 +Y；UV 按顶面约定以格心归一（格心自身 → (0.5,0.5)）。
static func _emit_vertex(st: SurfaceTool, world_pos: Vector3, center: Vector3, size: float) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(
		0.5 + (world_pos.x - center.x) / (2.0 * size),
		0.5 - (world_pos.z - center.z) / (2.0 * size),
	))
	st.add_vertex(world_pos)


## 色块材质（T8 材质资源化前的起步实现）：无顶点色路线 → 不开 vertex_color_use_as_albedo。
static func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat
