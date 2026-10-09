## hex_terrain_builder.gd — 连续高程地形网格几何构建（M1a-T3 平地 → M1a-T4 高程分层与
##   连续连接；docs/04-tasks-m1.md M1a-T4 + 调研文档「连续高程网格：用顶面、边带、角落拆开」
##   / Catlike §3 结构移植）
## 约定与决策（翻案须先改 04 对应验收，不动架构）：
## - 纯逻辑类：RefCounted、零场景节点（ADR-2）；产出 ArrayMesh + 元数据 Dictionary。
##   场景挂载在 scripts/ui/map_view.gd（view 层）——删 scripts/ui/** 不影响本文件与
##   tests/（02 §3「删 ui 后测试全绿」的可执行表达）。
## - 依赖方向：本文件 → hex_math.gd（T1）+ map_data.gd（T2），只读不反向。
## - 三步纯几何（04 M1a-T4 细化，逐格）：
##   ① 顶面：格心 + 六内顶点三角扇（首版平整不扰动；微决策 2：站立/高亮只盖内顶面）；
##   ② 边带：A.inner_d / A.inner_{d+1} 平移 bridge_d 成四边形——等高平连 / 差一级斜坡 /
##     更大高差陡面（微决策 1 = Catlike 式陡连接面，非垂直墙；首版单斜面，不阶梯化）；
##   ③ 角落：顶点 k 相邻三格（cell、dir k 邻、dir k−1 邻）独立补洞三角
##     (inner_k, inner_k+bridge_{k-1}, inner_k+bridge_k)——两两边带拼合不保证角落封闭。
## - 归属规则（防重复面；04 M1a-T4 细化）：
##   · 共享边带：两格稳定 ID（MapData.index_of，行主序存储下标）较小者生成；
##   · 共享角落：顶点 k 三格中 ID 最小者生成（三格 ID 即唯一 key）；
##   · chunk 只生成"归属权在本 chunk 内"的几何——归属判断用全局 index_of，chunk 天然
##     可读邻块格子数据（chunk 边界 ≠ 地图边界：跨块边带/角落由归属块生成，本块跳过）；
##   · 接缝顶点从同一全局参数计算：HexMath.inner_vertex / bridge_xz（全局格心现算），
##     每条几何唯一生成路径 → 跨 chunk 顶点逐位一致，不存在两路扰动。
## - 边界规则（T2 口径在几何面的落实）：边带邻居或角落三格任一界外 → 不生成该连接
##   （无悬空面）；地图外沿 = 内六边形锯齿边缘、无侧壁（外沿侧壁属表现层升级，不在本任务）。
## - 逐面 emit（flat shading）：每三角独立 3 顶点 + 显式递增索引，faces 序 = 三角序
##   （为 T5 拾取的 face_index→格映射预留直接对应）。法线 = 面法线现算
##   （顶面恒 +Y；边带/角落 = cross 归一——绕序保证 y 分量 > 0，陡面朝上侧倾斜）。
## - 绕序（cross(B−A,C−A).y > 0 口径，全方向旋转对称成立）：
##   顶面 (格心, inner_k, inner_{k+1})；边带 (v1,v3,v4)+(v1,v4,v2)；角落 (p1,p3,p2)。
## - UV 约定（T3 接口不变）：以归属格格心归一 u = 0.5+(x−cx)/2·size、v = 0.5−(z−cz)/2·size；
##   边带/角落顶点可越出 [0,1]（连续延展，色块材质无纹理不受影响；贴图时代由 T8 定采样）。
## - 材质槽 = 地形类型 → 材质映射（色块起步，T8 资源化替换）；边带/角落归属生成者的地形
##   surface。不用顶点色 → 材质不开 vertex_color_use_as_albedo（04 M1a-T3 细化）。
## - 色表缺图内地形 id / elevation_step ≤0 / solid_factor ∉ (0,1) → 显式失败（null）。
## - 元数据：{"chunk": Rect2i, "mesh": ArrayMesh, "surfaces": [{"terrain": int,
##   "cells": Array[Vector2i]（该地形格，chunk 行主序）, "faces": Array[Dictionary]
##   （与 mesh 三角一一对应：kind="top"|"edge"|"corner"、cell=归属格、dir=顶面扇区 k/
##   边带方向 d/角落顶点 k、edge_face 另带 edge_type）, "face_counts": {top,edge,corner},
##   "vertex_count": 3×面数, "index_count": 3×面数}]}。
class_name HexTerrainBuilder
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")

## 默认内六边形缩进（Catlike 同款 0.8：连接带宽 = (1−solid)·√3·size ≈ 0.35·size）
const DEFAULT_SOLID_FACTOR := 0.8
## 默认每层高程的世界高度（相对 size=1 的格：一层 ≈ 内切圆半径 0.87 的 1.15 倍）
const DEFAULT_ELEVATION_STEP := 1.0

## 边带分类（微决策 1；T5 拾取归属将复用同分类——悬崖归高地侧）
const EDGE_FLAT := "flat"    # 等高平连（|Δh| = 0）
const EDGE_SLOPE := "slope"  # 差一级斜坡（|Δh| = 1，首版单斜面）
const EDGE_CLIFF := "cliff"  # 更大高差陡面（|Δh| ≥ 2，Catlike 式陡连接面）

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


## chunk 矩形内的格子（行主序；矩形与图求交）。注意：几何生成读全图数据（邻块可读），
## 本函数只圈定"归属权候选格"——跨界边带/角落是否归本块由全局稳定 ID 判定。
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

# ---------------- 边带分类 ----------------

## 高差 → 连接类型（Catlike 口径：|Δh|=0 Flat、=1 Slope、≥2 Cliff）。
static func classify_edge(delta_elevation: int) -> String:
	var d := absi(delta_elevation)
	if d == 0:
		return EDGE_FLAT
	if d == 1:
		return EDGE_SLOPE
	return EDGE_CLIFF

# ---------------- 构建入口 ----------------

## 整图分块构建。返回 {"chunks": Array[chunk 字典], "chunk_rects": Array[Rect2i],
##   "materials": {被用到的 terrain id → 共享材质}, "size": float,
##   "elevation_step": float, "solid_factor": float}；
## 任一地形 id 缺色表 / 参数非法 → null（先全图预检后建，不做一半丢弃）。
static func build_map(map: MapDataClass, chunk_cols := 10, chunk_rows := 10,
		terrain_colors := {}, size := 1.0,
		elevation_step := DEFAULT_ELEVATION_STEP,
		solid_factor := DEFAULT_SOLID_FACTOR) -> Variant:
	if elevation_step <= 0.0 or solid_factor <= 0.0 or solid_factor >= 1.0 or size <= 0.0:
		return null
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
		var built: Variant = build_chunk(map, rect, materials, size, elevation_step, solid_factor)
		if built == null:
			return null
		chunks.append(built)
	return {
		"chunks": chunks,
		"chunk_rects": rects,
		"materials": materials,
		"size": size,
		"elevation_step": elevation_step,
		"solid_factor": solid_factor,
	}


## 单 chunk 构建。materials 须含 chunk 内全部地形 id（build_map 已预建共享表；直调自备，
## 缺 id / 空矩形（无格）/ 参数非法 → null）。
static func build_chunk(map: MapDataClass, chunk: Rect2i, materials: Dictionary,
		size := 1.0, elevation_step := DEFAULT_ELEVATION_STEP,
		solid_factor := DEFAULT_SOLID_FACTOR) -> Variant:
	if elevation_step <= 0.0 or solid_factor <= 0.0 or solid_factor >= 1.0 or size <= 0.0:
		return null
	var cells := chunk_cells(map, chunk)
	if cells.is_empty():
		return null
	# 按地形分组（组内保持 chunk 行主序；surface 序 = 类型首次出现序——T3 口径沿用）
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
		surfaces.append(_build_surface(map, tid, groups[tid], materials[tid], size,
			elevation_step, solid_factor, mesh))
	return {"chunk": chunk, "mesh": mesh, "surfaces": surfaces}


# ---------------- 单 surface（一种地形类型的全部归属几何） ----------------

## chunk 内同地形格的顶面 + 归属边带 + 归属角落，逐面 emit 到共享 mesh 的新 surface。
static func _build_surface(map: MapDataClass, terrain_id: int, group: Array[Vector2i],
		material: Material, size: float, elevation_step: float, solid_factor: float,
		mesh: ArrayMesh) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	var faces: Array[Dictionary] = []
	var top_count := 0
	var edge_count := 0
	var corner_count := 0
	var vi := 0  # surface 内顶点游标（faces 序 = 三角序 = 顶点序）
	for cell in group:
		var id := map.index_of(cell)
		var h := _y_of(map, cell, elevation_step)
		var center := Hex.axial_to_world(cell, size)
		center.y = h
		# ① 顶面：格心 + 六内顶点三角扇（每格恒 6 面；首版平整不扰动）
		for k in 6:
			var a := center
			var b := Hex.inner_vertex(cell, k, size, solid_factor, h)
			var c := Hex.inner_vertex(cell, (k + 1) % 6, size, solid_factor, h)
			vi = _emit_face(st, vi, a, b, c, center, size, Vector3.UP)
			faces.append({"kind": "top", "cell": cell, "dir": k})
			top_count += 1
		# ② 边带：共享边由两格稳定 ID 较小者生成（界外邻格 → 不生成，无悬空连接）
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not map.has_cell(nb):
				continue
			var nb_id := map.index_of(nb)
			if nb_id < id:
				continue
			var etype := classify_edge(map.elevation_at(cell) - map.elevation_at(nb))
			var hnb := _y_of(map, nb, elevation_step)
			var br := Hex.bridge_xz(cell, d, size, solid_factor)
			var v1 := Hex.inner_vertex(cell, d, size, solid_factor, h)
			var v2 := Hex.inner_vertex(cell, (d + 1) % 6, size, solid_factor, h)
			var v3 := v1 + Vector3(br.x, 0.0, br.y)
			var v4 := v2 + Vector3(br.x, 0.0, br.y)
			v3.y = hnb
			v4.y = hnb
			vi = _emit_face(st, vi, v1, v3, v4, center, size, _face_normal(v1, v3, v4))
			vi = _emit_face(st, vi, v1, v4, v2, center, size, _face_normal(v1, v4, v2))
			faces.append({"kind": "edge", "cell": cell, "dir": d, "edge_type": etype})
			faces.append({"kind": "edge", "cell": cell, "dir": d, "edge_type": etype})
			edge_count += 2
		# ③ 角落：顶点 k 三格 ID 最小者生成补洞三角（三格任一界外 → 不生成）
		for k in 6:
			var nb_k := Hex.neighbor(cell, k)
			var nb_k1 := Hex.neighbor(cell, k - 1)  # 方向 k−1（neighbor 内部 wrapi）
			if not map.has_cell(nb_k) or not map.has_cell(nb_k1):
				continue
			if map.index_of(nb_k) < id or map.index_of(nb_k1) < id:
				continue
			var br_k := Hex.bridge_xz(cell, k, size, solid_factor)
			var br_k1 := Hex.bridge_xz(cell, k - 1, size, solid_factor)
			var p1 := Hex.inner_vertex(cell, k, size, solid_factor, h)
			var p2 := p1 + Vector3(br_k.x, 0.0, br_k.y)   # dir k 邻格侧端点
			var p3 := p1 + Vector3(br_k1.x, 0.0, br_k1.y)  # dir k−1 邻格侧端点
			p2.y = _y_of(map, nb_k, elevation_step)
			p3.y = _y_of(map, nb_k1, elevation_step)
			vi = _emit_face(st, vi, p1, p3, p2, center, size, _face_normal(p1, p3, p2))
			faces.append({"kind": "corner", "cell": cell, "dir": k})
			corner_count += 1
	st.commit(mesh)
	return {
		"terrain": terrain_id,
		"cells": group,
		"faces": faces,
		"face_counts": {"top": top_count, "edge": edge_count, "corner": corner_count},
		"vertex_count": faces.size() * 3,
		"index_count": faces.size() * 3,
	}

# ---------------- 内部 ----------------

## 格高程 → 世界 y（int 分层 × 步长；可为负）。
static func _y_of(map: MapDataClass, cell: Vector2i, elevation_step: float) -> float:
	return float(map.elevation_at(cell)) * elevation_step


## 单三角：法线显式 + UV（归属格格心归一，T3 公式沿用）+ 顶点 + 递增显式索引
##（base = 调用方维护的顶点游标；返回更新后的游标）。
## faces 序 = 三角序（本函数只 emit，面记录由调用方追加——两者严格同步）。
static func _emit_face(st: SurfaceTool, base: int, a: Vector3, b: Vector3, c: Vector3,
		ref: Vector3, size: float, n: Vector3) -> int:
	st.set_normal(n)
	st.set_uv(Vector2(0.5 + (a.x - ref.x) / (2.0 * size), 0.5 - (a.z - ref.z) / (2.0 * size)))
	st.add_vertex(a)
	st.set_normal(n)
	st.set_uv(Vector2(0.5 + (b.x - ref.x) / (2.0 * size), 0.5 - (b.z - ref.z) / (2.0 * size)))
	st.add_vertex(b)
	st.set_normal(n)
	st.set_uv(Vector2(0.5 + (c.x - ref.x) / (2.0 * size), 0.5 - (c.z - ref.z) / (2.0 * size)))
	st.add_vertex(c)
	st.add_index(base)
	st.add_index(base + 1)
	st.add_index(base + 2)
	return base + 3


## 面法线（flat shading；绕序保证 cross 模 > 0——三角 xz 投影恒有正面积，归一安全）。
static func _face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (b - a).cross(c - a).normalized()


## 色块材质（T8 材质资源化前的起步实现）：无顶点色路线 → 不开 vertex_color_use_as_albedo。
static func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat
