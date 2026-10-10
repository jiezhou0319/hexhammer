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
## - 绕序双层口径（2026-10-10 F-1 修复，Fable 审查）：
##   · raw 顶点 soup 保持几何序 cross(B−A,C−A).y > 0（俯视逆时针，全方向旋转对称）：
##     顶面 (格心, inner_k, inner_{k+1})；边带 (v1,v3,v4)+(v1,v4,v2)；角落 (p1,p3,p2)
##     ——碰撞汤翻转（hex_picking.chunk_collision_faces 直读 raw 顶点）与 faces 元数据
##     （face_index 映射）都锚定 raw 序，**不变**；
##   · 渲染**索引**逐三角翻转为 (base, base+2, base+1)：索引三角 = 俯视**顺时针**
##     = Godot 正面（引擎口径：front face = clockwise winding）——默认 CULL_BACK 下
##     俯视可见。法线/UV 仍随 raw 顶点走（描述面朝向与纹理，与剔除面无关）。
## - 法线硬边策略（M1a-T8 显式定死）：**全 flat shading、全硬边**——每三角独立 3 顶点 +
##   面法线，不焊接顶点、不做任何平滑（平顶/陡壁的硬边是低模策略地形的目标可读性；
##   平滑法线=顶点焊接+按面分类平滑组，属表现层后续升级，翻案须回改 04 与测试锚）。
## - UV 约定（M1a-T8 定死——「换贴图不改主线」的接口前提，否则美术无从对表；
##   细则与取舍全文见 docs/notes/m1a-t8-art-branch.md，翻案须同步改
##   tests/test_hex_terrain_materials.gd 的 UV 锚）：
##   · 尺寸：1 纹理重复 [0,1]² = 2R×2R 世界方形（R = size 外接圆半径）；
##     整体缩放属材质参数（uv1_scale），不动 mesh；
##   · 水平面（顶面 / 平连边带 / 等高角落）：世界平面映射 u = x/2R、v = −z/2R
##     ——平地整图无缝连续平铺（换贴图即所见的基础）；
##   · 侧面（|Δh|≥1 边带，斜坡/陡面）：u = XZ 沿边切向投影/2R（HexMath.
##     edge_tangent_world，每方向 u 轴随边向）、v = −y/2R——竖向纹理随高程走
##     （Δ1 半纹、Δ2 恰一整纹；对真竖直墙纵横比正确，本作 80° 陡面拉伸 ≈1.5%）；
##   · 非等高角落（补洞小三角）：u = x/2R（平面 u）、v = −y/2R——u 与两侧边带
##     轴不连续、相邻方向边带 u 轴相差 60°：登记为已接受代价（选无缝平铺贴图
##     时不显眼；边界混色/Texture2DArray/三平面映射属后续升级，04 M1a-T8 明示不做）。
## - 材质槽 = 地形类型 → 材质映射表（M1a-T8 资源化）：调用方传 {terrain_id: Material}
##   平面表（.tres 载体 = TerrainMaterialLibrary，scripts/core/data/；主线默认表 =
##   resources/terrain/terrain_materials_default.tres 色块起步）；边带/角落归属生成者
##   的地形 surface。不用顶点色 → 材质不开 vertex_color_use_as_albedo（04 M1a-T3 细化）。
##   表缺图内地形 id / 表值非 Material / elevation_step ≤0 / solid_factor ∉ (0,1)
##   → 显式失败（null）。
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

## 整图分块构建。materials = 地形 id → Material 映射表（TerrainMaterialLibrary.materials
##   的 .tres 载体见 scripts/core/data/terrain_material_library.gd；测试/工具可自建表）。
##   返回 {"chunks": Array[chunk 字典], "chunk_rects": Array[Rect2i],
##   "materials": {被用到的 terrain id → 表内共享材质实例}（echo 输入表，不合成新材质）,
##   "size": float, "elevation_step": float, "solid_factor": float}；
## 任一地形 id 缺表 / 表值非 Material / 参数非法 → null（先全图预检后建，不做一半丢弃）。
static func build_map(map: MapDataClass, chunk_cols := 10, chunk_rows := 10,
		materials: Dictionary = {}, size := 1.0,
		elevation_step := DEFAULT_ELEVATION_STEP,
		solid_factor := DEFAULT_SOLID_FACTOR) -> Variant:
	if elevation_step <= 0.0 or solid_factor <= 0.0 or solid_factor >= 1.0 or size <= 0.0:
		return null
	# chunk 参数显式拒绝（2026-10-10 接口硬化）：此前 chunk_rects_for 对 ≤0 返回
	# 空数组，本函数照走循环产出 chunks=0 的 Dictionary——「空成功」会被调用层
	# 当构建成功（T1~T4 复核反例：build_map(map, 0, 10)）。空图是否可构建属
	# view 层契约另议，不在本条范围。
	if chunk_cols <= 0 or chunk_rows <= 0:
		return null
	if not _material_table_valid(map, materials):
		return null
	var used := {}
	for cell in map.cells():
		used[map.terrain_at(cell)] = true
	var shared := {}
	for tid in used:
		shared[tid] = materials[tid]
	var chunks: Array = []
	var rects := chunk_rects_for(map.width, map.height, chunk_cols, chunk_rows)
	for rect in rects:
		var built: Variant = build_chunk(map, rect, shared, size, elevation_step, solid_factor)
		if built == null:
			return null
		chunks.append(built)
	return {
		"chunks": chunks,
		"chunk_rects": rects,
		"materials": shared,
		"size": size,
		"elevation_step": elevation_step,
		"solid_factor": solid_factor,
	}


## 单 chunk 构建。materials 须含 chunk 内全部地形 id（build_map 已过滤共享表；直调自备，
## 缺 id / 表值非 Material / 空矩形（无格）/ 参数非法 → null）。
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
		if tid == MapDataClass.TERRAIN_NONE or not (materials.has(tid) and materials[tid] is Material):
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
		# ① 顶面：格心 + 六内顶点三角扇（每格恒 6 面；首版平整不扰动；水平面 → 平面 UV）
		for k in 6:
			var a := center
			var b := Hex.inner_vertex(cell, k, size, solid_factor, h)
			var c := Hex.inner_vertex(cell, (k + 1) % 6, size, solid_factor, h)
			vi = _emit_face(st, vi, a, b, c, Vector3.UP,
				_uv_planar(a, size), _uv_planar(b, size), _uv_planar(c, size))
			faces.append({"kind": "top", "cell": cell, "dir": k})
			top_count += 1
		# ② 边带：共享边由两格稳定 ID 较小者生成（界外邻格 → 不生成，无悬空连接）。
		#   UV 随边分类：平连 = 水平面（与顶面同一世界平面映射，整图连续）；
		#   斜坡/陡面 = 侧面（u 沿边切向、v 跟高程——T8 约定，见类头注）
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
			var n1 := _face_normal(v1, v3, v4)
			var n2 := _face_normal(v1, v4, v2)
			if etype == EDGE_FLAT:
				vi = _emit_face(st, vi, v1, v3, v4, n1,
					_uv_planar(v1, size), _uv_planar(v3, size), _uv_planar(v4, size))
				vi = _emit_face(st, vi, v1, v4, v2, n2,
					_uv_planar(v1, size), _uv_planar(v4, size), _uv_planar(v2, size))
			else:
				var tangent := Hex.edge_tangent_world(d)
				vi = _emit_face(st, vi, v1, v3, v4, n1,
					_uv_side_edge(v1, tangent, size), _uv_side_edge(v3, tangent, size),
					_uv_side_edge(v4, tangent, size))
				vi = _emit_face(st, vi, v1, v4, v2, n2,
					_uv_side_edge(v1, tangent, size), _uv_side_edge(v4, tangent, size),
					_uv_side_edge(v2, tangent, size))
			faces.append({"kind": "edge", "cell": cell, "dir": d, "edge_type": etype})
			faces.append({"kind": "edge", "cell": cell, "dir": d, "edge_type": etype})
			edge_count += 2
		# ③ 角落：顶点 k 三格 ID 最小者生成补洞三角（三格任一界外 → 不生成）。
		#   UV：三格等高 = 水平面 → 平面映射；否则 = 侧面（u 平面、v 跟高程——T8 约定）
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
			var n := _face_normal(p1, p3, p2)
			if map.elevation_at(cell) == map.elevation_at(nb_k) and map.elevation_at(cell) == map.elevation_at(nb_k1):
				vi = _emit_face(st, vi, p1, p3, p2, n,
					_uv_planar(p1, size), _uv_planar(p3, size), _uv_planar(p2, size))
			else:
				vi = _emit_face(st, vi, p1, p3, p2, n,
					_uv_side_corner(p1, size), _uv_side_corner(p3, size), _uv_side_corner(p2, size))
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


## 单三角：法线显式（面法线 = flat shading 硬边口径）+ 调用方算好的逐顶点 UV
## + 顶点 + 递增显式索引（base = 调用方维护的顶点游标；返回更新后的游标）。
## faces 序 = 三角序（本函数只 emit，面记录由调用方追加——两者严格同步）。
## UV 由调用方按面分类选取（平面/侧面公式见下方 _uv_*——T8 约定的唯一计算点，
## 不在两处各算）。
## 索引序 = (base, base+2, base+1)：索引三角俯视**顺时针** = Godot 正面（F-1 修复，
## 2026-10-10）；raw 顶点序保持几何逆时针（碰撞/face 表口径，见类头注「绕序双层口径」）。
static func _emit_face(st: SurfaceTool, base: int, a: Vector3, b: Vector3, c: Vector3,
		n: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2) -> int:
	st.set_normal(n)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_uv(uv_c)
	st.add_vertex(c)
	st.add_index(base)
	st.add_index(base + 2)
	st.add_index(base + 1)
	return base + 3


## 水平面 UV（顶面/平连边带/等高角落）：世界平面映射 u = x/2R、v = −z/2R
##（T8 约定；平地整图无缝连续平铺——与归属格无关，跨 chunk 自然连续）。
static func _uv_planar(p: Vector3, size: float) -> Vector2:
	return Vector2(p.x / (2.0 * size), -p.z / (2.0 * size))


## 侧面 UV（|Δh|≥1 边带）：u = XZ 沿边切向投影/2R（tangent = HexMath.edge_tangent_world，
## 每方向随边向）、v = −y/2R（竖向纹理随高程走：Δ1 半纹、Δ2 恰一整纹）。
static func _uv_side_edge(p: Vector3, tangent: Vector3, size: float) -> Vector2:
	return Vector2((p.x * tangent.x + p.z * tangent.z) / (2.0 * size), -p.y / (2.0 * size))


## 侧面 UV（非等高角落补洞三角）：u = 平面 u = x/2R、v = −y/2R（与两侧边带 u 轴
## 不连续——已接受代价，见类头注与 docs/notes/m1a-t8-art-branch.md）。
static func _uv_side_corner(p: Vector3, size: float) -> Vector2:
	return Vector2(p.x / (2.0 * size), -p.y / (2.0 * size))


## 面法线（flat shading；绕序保证 cross 模 > 0——三角 xz 投影恒有正面积，归一安全）。
static func _face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (b - a).cross(c - a).normalized()


## 全图材质表预检：图内任一格地形 id 缺槽 / 槽值非 Material → false
##（「无隐式兜底」——不做缺槽补色、不静默跳格）。
static func _material_table_valid(map: MapDataClass, materials: Variant) -> bool:
	if not (materials is Dictionary):
		return false
	var table: Dictionary = materials
	for cell in map.cells():
		var tid := map.terrain_at(cell)
		if tid == MapDataClass.TERRAIN_NONE or not table.has(tid):
			return false
		if not (table[tid] is Material):
			return false
	return true
