## hex_picking.gd — 拾取链路纯逻辑层（M1a-T5；docs/04-tasks-m1.md M1a-T5 + 调研文档
##   「拾取：先打通当前设计，再补边界归属」+ 2026-10-09 三个微决策）
## 链路（04 M1a-T5 细化）：屏幕射线 → 对地形 mesh 物理 raycast（view 层，见
##   scripts/ui/map_picker.gd）→ 世界坐标 → **地图根局部坐标** → 本模块解析 → 格子。
##   本文件只做「局部命中点 + 命中面 → 格子」与「碰撞数据/面映射构建」，全部纯静态
##   函数、零场景节点（ADR-2；删 scripts/ui/** 不影响本文件与 tests/）。
## 归属规则（微决策 3，2026-10-09 拍板；翻案须先改 04 对应验收，不动架构）：
## - 顶面（kind="top"）：归本格（面归属格即命中格；与浮点 axial+rounding 的交叉
##   一致性由 tests/test_hex_picking.gd 锚定——内六边形整块 round 回本格）。
## - 边带（kind="edge"，两格候选）：
##   · flat（|Δh|=0）/ slope（|Δh|=1）：**局部 XZ 最近逻辑格心**；距离相等 →
##     棋盘固定 ID（MapData.index_of，行主序存储下标——与 T4 归属规则同一比较器）
##     较小者决胜；
##   · cliff（|Δh|≥2，Catlike 式陡连接面）：归**高地侧**（并列最高取 ID 较小者）。
## - 角落（kind="corner"，三格候选）：微决策 3 未单列角落，按同一分类口径泛化——
##   三格高程 max−min ≥ 2 视作悬崖形角落 → 归最高格（并列最高取 ID 较小者）；
##   否则（全等高 / 差一级）按斜坡口径 → 局部 XZ 最近逻辑格心 + ID 决胜。
##   【登记为 T5 的解释性落字，与边带规则同构；翻案须明说并回改对应测试。】
## 最近格心的「相等」判定：|dA−dB| ≤ TIE_EPS·size 视作相等（浮点对称点两条计算
##   路径差 ~1e-15，实际最近距离差 ≥ 0.05·size 量级——窗口隔开十余个数量级）。
## face→格映射（04 M1a-T5 细化「face_index 仅对 ConcavePolygonShape3D 有效」的落实）：
## - 碰撞三角形 = T4 mesh 顶点数组按 surface 构建序拼接（builder 逐面 3 顶点显式
##   索引提交 → 顶点序 = 三角序，T4 测试已锚定），**自提交顺序即映射顺序**；
## - chunk_face_table 与 soup 逐索引对应（triangle i ↔ faces[i]），由
##   tests/test_hex_picking.gd 对 mesh 顶点/面记录逐位核对；
## - 引擎 face_index 是否等于自提交序（ConcavePolygonShape3D 语义）由
##   tools/picking_scene_check.gd 小场景校验（跑真物理帧，独立于 headless 门禁——
##   4.7.2 脚本 API 无 space_step，SceneTree._init 内物理空间永不被 step，已探测）。
## 碰撞层约定（层号 = Godot collision_layer 位序 1~32；view 层与工具共用本常量）：
## - LAYER_TERRAIN：静态地形，**唯一允许被拾取射线命中的层**（射线 mask=MASK_TERRAIN_ONLY）；
## - LAYER_PICKABLE：棋子/高亮/装饰等一切可能挡在射线上的物体（拾取射线 mask 恒不含）。
## 依赖方向：本文件 → hex_math.gd（T1）/ map_data.gd（T2）/ hex_terrain_builder.gd
##   （T3/T4 元数据），只读不反向。
class_name HexPicking
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")

## 地形碰撞层（拾取射线唯一许可层）
const LAYER_TERRAIN := 1
## 棋子/高亮/装饰层（拾取射线 mask 恒不含——不得截获地形拾取）
const LAYER_PICKABLE := 2
## 拾取射线 mask：只查地形层
const MASK_TERRAIN_ONLY := 1 << (LAYER_TERRAIN - 1)

## 「最近格心」距离相等判定窗口（相对 size；见类头注量级论证）
const TIE_EPS := 1e-6

# ---------------- 碰撞数据 / face→格映射（自提交三角形顺序）----------------

## chunk 碰撞三角形汤（每 3 顶点一三角）。三角形**顺序** = mesh surface 构建序 ×
## surface 内三角序——与 chunk_face_table 逐索引对应（「自提交碰撞三角形顺序」）；
## 三角形**顶点序**逐面翻转为 (a, c, b)：Godot 正面绕序 = 顺时针（从可见侧看，
## ConcavePolygonShape3D 射线实测同口径——cross(B−A,C−A) 朝射线来侧的面被当作
## 背面拒绝），T4 mesh 的 cross 朝上绕序须翻转后提交，否则 intersect_ray 全 miss
##（2026-10-09 引擎探针实测；渲染 mesh 的绕序问题属 T4，见任务交付说明）。
static func chunk_collision_faces(chunk_info: Dictionary) -> PackedVector3Array:
	var mesh: ArrayMesh = chunk_info["mesh"]
	var out := PackedVector3Array()
	var surfaces: Array = chunk_info["surfaces"]
	for si in surfaces.size():
		var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		var tri_count := verts.size() / 3
		for t in tri_count:
			var base := t * 3
			out.append(verts[base])       # a
			out.append(verts[base + 2])   # c（翻转：Godot 正面 = 顺时针）
			out.append(verts[base + 1])   # b
	return out


## chunk face 表：triangle i ↔ faces[i]（kind/cell/dir[/edge_type]，T4 builder 元数据
## 原样传递）。intersect_ray 返回的 face_index 直接作下标。
static func chunk_face_table(chunk_info: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var surfaces: Array = chunk_info["surfaces"]
	for sd in surfaces:
		var faces: Array = sd["faces"]
		out.append_array(faces)
	return out


## 单 chunk 拾取数据一次成形（view 层碰撞体与测试/工具共用入口）：
## {"chunk": Rect2i, "collision_faces": PackedVector3Array, "face_table": Array[Dictionary]}
static func chunk_pick_data(chunk_info: Dictionary) -> Dictionary:
	return {
		"chunk": chunk_info["chunk"],
		"collision_faces": chunk_collision_faces(chunk_info),
		"face_table": chunk_face_table(chunk_info),
	}

# ---------------- 命中解析（局部坐标 + face → 格子）----------------

## 射线命中解析入口：local_pos = 命中点（**地图根局部坐标**），face_index = 引擎
## ConcavePolygonShape3D 命中面号，face_table = 该碰撞体的 chunk_face_table。
## face_index 越界（非地形面/未知面命中——mask 纪律下不应发生）→ null（显式失败，
## 无静默兜底；调用方按 miss 处理）。
static func resolve_hit(local_pos: Vector3, face_index: int, face_table: Array,
		map: MapDataClass, size := 1.0) -> Variant:
	if face_index < 0 or face_index >= face_table.size():
		return null
	return resolve_face(local_pos, face_table[face_index], map, size)


## 单面归属分发。face 为 T4 builder 面记录（{"kind","cell","dir"[,"edge_type"]}）；
## kind 未知 / 字段缺失 → null。
static func resolve_face(local_pos: Vector3, face: Dictionary,
		map: MapDataClass, size := 1.0) -> Variant:
	match String(face.get("kind", "")):
		"top":
			return face["cell"]  # 顶面归本格
		"edge":
			return pick_edge_band(local_pos, face["cell"], int(face["dir"]), map, size)
		"corner":
			return pick_corner(local_pos, face["cell"], int(face["dir"]), map, size)
		_:
			return null

# ---------------- 归属规则（微决策 3；纯逻辑重点覆盖面）----------------

## 边带归属（两格候选）：flat/slope → 局部 XZ 最近逻辑格心 + ID 决胜；
## cliff（|Δh|≥2）→ 高地侧。
static func pick_edge_band(local_pos: Vector3, cell: Vector2i, dir: int,
		map: MapDataClass, size := 1.0) -> Vector2i:
	var candidates := edge_cells(cell, dir)
	var delta := map.elevation_at(candidates[0]) - map.elevation_at(candidates[1])
	if Builder.classify_edge(delta) == Builder.EDGE_CLIFF:
		return pick_highest(candidates, map)
	return pick_by_nearest_center(local_pos, candidates, map, size)


## 角落归属（三格候选）：max−min ≥ 2（悬崖形）→ 最高格；否则最近格心 + ID 决胜。
## 调用契约：cell/k 对应的角落面存在（三格界内——builder 只为界内 trio 生成角落）。
static func pick_corner(local_pos: Vector3, cell: Vector2i, k: int,
		map: MapDataClass, size := 1.0) -> Vector2i:
	var candidates := corner_cells(cell, k)
	var lowest := map.elevation_at(candidates[0])
	var highest := lowest
	for i in range(1, candidates.size()):
		var h := map.elevation_at(candidates[i])
		lowest = mini(lowest, h)
		highest = maxi(highest, h)
	if highest - lowest >= 2:
		return pick_highest(candidates, map)
	return pick_by_nearest_center(local_pos, candidates, map, size)


## 候选格集：边带 = 该边两格（面归属格 + dir 向邻格）
static func edge_cells(cell: Vector2i, dir: int) -> Array[Vector2i]:
	return [cell, Hex.neighbor(cell, dir)]


## 候选格集：角落 = 相邻三格（面归属格 + 顶点 k 两侧邻格 N(k)/N(k−1)，与 T4 生成口径一致）
static func corner_cells(cell: Vector2i, k: int) -> Array[Vector2i]:
	return [cell, Hex.neighbor(cell, k), Hex.neighbor(cell, k - 1)]


## 局部 XZ 最近逻辑格心；距离相等（≤ TIE_EPS·size）→ 稳定 ID（index_of）较小者。
## 候选顺序不影响结果（决胜只看 ID 与距离）。
static func pick_by_nearest_center(local_pos: Vector3, candidates: Array[Vector2i],
		map: MapDataClass, size := 1.0) -> Vector2i:
	var best: Vector2i = candidates[0]
	var best_d := _xz_dist_sq(local_pos, best, size)
	for i in range(1, candidates.size()):
		var c: Vector2i = candidates[i]
		var d := _xz_dist_sq(local_pos, c, size)
		if d < best_d - TIE_EPS * size:
			best = c
			best_d = d
		elif absf(d - best_d) <= TIE_EPS * size and map.index_of(c) < map.index_of(best):
			best = c
			best_d = d
	return best


## 高地侧（悬崖/悬崖形角落）：最高高程者；并列最高 → 稳定 ID 较小者。
static func pick_highest(candidates: Array[Vector2i], map: MapDataClass) -> Vector2i:
	var best: Vector2i = candidates[0]
	for i in range(1, candidates.size()):
		var c: Vector2i = candidates[i]
		var hc := map.elevation_at(c)
		var hb := map.elevation_at(best)
		if hc > hb or (hc == hb and map.index_of(c) < map.index_of(best)):
			best = c
	return best


## 局部点 → 格心 XZ 距离平方（格心由 HexMath 全局公式现算——与几何构建同一参数源）
static func _xz_dist_sq(local_pos: Vector3, cell: Vector2i, size: float) -> float:
	var center := Hex.axial_to_world(cell, size)
	var dx := local_pos.x - center.x
	var dz := local_pos.z - center.z
	return dx * dx + dz * dz
