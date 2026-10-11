## river_fixtures.gd — 河段边序列 fixture 生成器（M1a T3 WATER-01；沿
##   tools/land_matrix_fixtures.gd「固定 fixture 库供测试与工具共用」先例）
## 职责：为 tests/test_water_*.gd 与 tools/make_fixed_maps.gd 提供**几何驱动**的
##   边序列构造——链的连续性（相邻边共角点）由世界坐标 vertex_xz 直接判定
##   （独立于 WorldData.corner_id_of 的 ID 派生：构造用几何、校验用 ID，两条
##   路径互证，测试不复制实现）。
## 生成器三类（WATER-01 测试锚「fixture 枚举具体边序列形状、不命名转向」，拍板⑩）：
## - around_cell_chain：绕单格边界走 count 条边——弯样（count<6）/ 角点级环样本
##   （count=6：六条**不同**边经同一批角点闭合成环——「边不复用 ≠ 无环」的
##   拒绝样本，修订记录三之 4）；
## - greedy_chain：确定性贪心角点走——每步在当前端点角点的两条延续边中按
##   「score = 南向 z − |x − 目标列|」取最大（并列取 link_id 字典序小）；
##   目标列由 Callable 给出（make_fixed_maps 传正弦 RIVER_* 常量、测试传常值）；
##   南向连续两步走向相反 = edge[k] 与 edge[k+2] 平行的走廊样自然产出；
## - mouth 邻接查询等小工具（固定图河口水体构造用）。
## 纯静态、零场景节点（ADR-2）；只读 MapData/HexMath，不写任何数据。
class_name RiverFixtures
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")

## 角点几何同一性容差：同一物理角点在不同格的 vertex_xz 表达式（格心 + size·
## cos/sin，float32 三角函数）下差随坐标量级放大——60×40 图实测最大 ~3.8e-6；
## 真不同角点距离 ≥ size·0.5 = 0.5（隔五个数量级，1e-4 窗口安全且不粘连邻角）。
const CORNER_EPS := 1e-4

# ---------------- 基础查询 ----------------

## 全图规范化 link 集（升序——构造与对账共用）。
static func all_links(map: MapDataClass) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in map.cells():
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not map.has_cell(nb):
				continue
			var lid := WorldDataClass.link_id_of(map.index_of(cell), map.index_of(nb))
			if not out.has(lid):
				out.append(lid)
	out.sort()
	return out


## cell 稳定 ID → axial 格（WorldData._cell_of_id 同式，公开只读版）。
static func cell_of_id(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))


## link 两端角点的世界 XZ（几何口径：边 = owner 格顶点 d 与 d+1 的连线）。
static func link_corners(map: MapDataClass, link: Vector2i) -> Array[Vector2]:
	var a := cell_of_id(map, link.x)
	var b := cell_of_id(map, link.y)
	var d := Hex.dir_between(a, b)
	if d < 0:
		return []
	return [Hex.vertex_xz(a, d, 1.0), Hex.vertex_xz(a, d + 1, 1.0)]


## link 中点世界 XZ（贪心打分用）。
static func link_mid(map: MapDataClass, link: Vector2i) -> Vector2:
	var a := Hex.axial_to_world(cell_of_id(map, link.x), 1.0)
	var b := Hex.axial_to_world(cell_of_id(map, link.y), 1.0)
	return Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)


## 两 link 是否共角点（几何判定——独立于 WorldData.corner_id_of）。
static func links_share_corner(map: MapDataClass, l1: Vector2i, l2: Vector2i) -> bool:
	for c1 in link_corners(map, l1):
		for c2 in link_corners(map, l2):
			if c1.distance_to(c2) < CORNER_EPS:
				return true
	return false


## 过角点的其他边（corner = 世界 XZ；exclude 排除当前边）——角点延续候选。
static func links_at_corner(map: MapDataClass, links: Array[Vector2i],
		corner: Vector2, exclude: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for lk in links:
		if lk == exclude:
			continue
		for c in link_corners(map, lk):
			if c.distance_to(corner) < CORNER_EPS:
				out.append(lk)
				break
	return out

# ---------------- 链生成器 ----------------

## 绕单格边界走 count 条边（k = 0..count−1 的 link(cell, N_k)——相邻边共角点
## cell 顶点 k+1；count=6 = 整圈闭环：六条不同边、首尾角点重合——角点级环样本）。
## 要求 cell 六邻全界内（返回前显式校验，不满足 → 空数组）。
static func around_cell_chain(map: MapDataClass, cell: Vector2i, count: int) -> Array[Vector2i]:
	if not map.has_cell(cell) or count < 1 or count > 6:
		return []
	for d in 6:
		if not map.has_cell(Hex.neighbor(cell, d)):
			return []
	var out: Array[Vector2i] = []
	for k in count:
		out.append(WorldDataClass.link_id_of(map.index_of(cell),
			map.index_of(Hex.neighbor(cell, k))))
	return out


## 确定性贪心角点走：start 起 steps 步，每步在当前端点角点的延续边中取
## score 最大者（score = 中点 z − |中点 x − target_x(row)|；并列取 link_id 字典序
## 较小——确定性钉死）。target_x_of_row: Callable(row: int) -> float（列口径）。
## 起步端点 = start 边两角点中较南者（南向生长；WATER-01 固定图/走廊 fixture 共用）。
## 延续边为空（图界收口）→ 提前返回已走序列。
static func greedy_chain(map: MapDataClass, links: Array[Vector2i], start: Vector2i,
		steps: int, target_x_of_row: Callable) -> Array[Vector2i]:
	var chain: Array[Vector2i] = [start]
	var corners := link_corners(map, start)
	if corners.size() != 2:
		return []
	var cur: Vector2 = corners[1] if corners[1].y >= corners[0].y else corners[0]
	for i in steps:
		var cands := links_at_corner(map, links, cur, chain[chain.size() - 1])
		if cands.is_empty():
			break
		var best: Vector2i = cands[0]
		var best_score := _south_score(map, best, target_x_of_row)
		for lk in cands:
			var s := _south_score(map, lk, target_x_of_row)
			if s > best_score + CORNER_EPS \
					or (absf(s - best_score) <= CORNER_EPS and lk < best):
				best = lk
				best_score = s
		chain.append(best)
		var cs := link_corners(map, best)
		if cs.size() != 2:
			break
		cur = cs[0] if cs[0].distance_to(cur) > CORNER_EPS else cs[1]
	return chain


## 南向贪心打分：z 越大越南（主项）+ 距目标列横向偏差惩罚（正弦/直走廊共用；
## 权重 1.0 = 一步横偏恰被一步南下抵消——南向主导、横向贴合）。
static func _south_score(map: MapDataClass, link: Vector2i,
		target_x_of_row: Callable) -> float:
	var mid := link_mid(map, link)
	var row := int(round(Hex.world_to_axial_f(Vector3(mid.x, 0.0, mid.y), 1.0).y))
	var target_x: Variant = target_x_of_row.call(row)
	return mid.y - absf(mid.x - float(target_x))
