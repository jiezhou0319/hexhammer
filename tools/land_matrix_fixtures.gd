## land_matrix_fixtures.gd — T2 连接矩阵固定小图 fixture（LAND-01 ④；执行方案 §3
##   LAND-01 技法移植设计 ②④：矩阵产出物 = tools/make_fixed_maps.gd 特征常量区
##   （:35-53）先例的固定小图，穷举全部局部高程组合，兼作 LAND-02/03 公共
##   fixture（含 cliff_wall 面）与 render_probe 新 CHECK 图）
## 布局（特征常量写死、零随机——「固定小图」的可复现口径）：
##   · 边矩阵带（EDGE_ROW）：Δ ∈ 0..max_e 每档 × 方向 0..5 各一对格（A=0 层、
##     B=Δ 层，A→B 方向 = d）——「Δ0..Δmax(3,threshold) × 方向旋转覆盖」全档
##     齐备（默认 threshold=3 → Δ3 即崖样本，「平/坡/崖全部闭合并可见」由
##     Δ0/Δ1/Δ3 覆盖、Δ2 阶地为 LAND-02 前置）；
##   · 角矩阵带（CORNER_ROW）：三格高程 (0..max_e)³ 按 (min,mid,max) 等价类归并
##     （值域随 cliff_threshold 同步扩——上界 = max(3, threshold)，固定 0–3 会漏
##     高阈值下的崖角组合，修订记录三之 8）——每等价类一组三格（角 k=1：中心 +
##     N(·,1) + N(·,0)），赋值 (a,b,c) = 升序三元组；
##   · 带间与对间距（PAIR_SPACING）≥ 2 空列：互不邻接，特征格高程不被邻带污染
##     （跨带边全为 Δ0 平连——矩阵归因干净；fixture 构建时自检无格冲突）。
## 合同：纯数据件、纯静态函数、零场景节点（ADR-2 同构；land_spike_fixtures.gd
##   先例）。双消费者 = tests/test_landform_terraces.gd（穷举/流形锚）与
##   tools/render_probe.gd（T2 CHECK 图）——布局改动须同步两处测试锚。
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")

## 特征常量区（make_fixed_maps :35-53 先例：调布局 = 改这里 + 同步测试锚）
const EDGE_ROW := 2          # 边矩阵带所在 offset 行（±1 行为其方向 excursion）
const CORNER_ROW := 7        # 角矩阵带所在行（角组用到 row−1）
const PAIR_COL0 := 2         # 首对/首组起始列
const PAIR_SPACING := 4      # 对间距（列）——≥2 空列保证互不邻接
## 边矩阵档上界 = max(3, cliff_threshold)（LAND-01 ②：穷举上界恒 ≥ cliff_threshold；
## 默认档 3 → Δ0..Δ3，threshold=4 → Δ0..Δ4）
static func edge_delta_max(cliff_threshold: int) -> int:
	return maxi(3, cliff_threshold)

## 边矩阵图：Δ0..max_e × 方向 0..5 的成对格（A 在左、B = N(A,d)）。
## 返回新 MapData（其余格高程 0——平连基底）。
static func build_edge_matrix(cliff_threshold := 3) -> MapDataClass:
	var dmax := edge_delta_max(cliff_threshold)
	var width := PAIR_COL0 + PAIR_SPACING * (dmax + 1) * 6 + 2
	var map := MapDataClass.new(width, EDGE_ROW + 2)
	var used := {}
	var pair := 0
	for delta in dmax + 1:
		for d in 6:
			var a := Hex.axial_of(Vector2i(PAIR_COL0 + PAIR_SPACING * pair, EDGE_ROW))
			var b := Hex.neighbor(a, d)
			_claim(map, used, a, 0, delta, d, pair)
			_claim(map, used, b, delta, delta, d, pair)
			pair += 1
	return map

## 角矩阵图：三格 (0..max_e)³ 全部 (min,mid,max) 等价类（多重集升序枚举），角组 =
## 中心 X + N(X,1) + N(X,0)（顶点 k=1 三格），赋值 (a,b,c) 依次给 (X, N1, N0)。
static func build_corner_matrix(cliff_threshold := 3) -> MapDataClass:
	var dmax := edge_delta_max(cliff_threshold)
	var classes := _corner_classes(dmax)
	var width := PAIR_COL0 + PAIR_SPACING * classes.size() + 2
	var map := MapDataClass.new(width, CORNER_ROW + 2)
	var used := {}
	for j in classes.size():
		var trio: Array = classes[j]
		var x := Hex.axial_of(Vector2i(PAIR_COL0 + PAIR_SPACING * j, CORNER_ROW))
		var n1 := Hex.neighbor(x, 1)
		var n0 := Hex.neighbor(x, 0)
		_claim(map, used, x, int(trio[0]), -1, j, -1)
		_claim(map, used, n1, int(trio[1]), -1, j, -2)
		_claim(map, used, n0, int(trio[2]), -1, j, -3)
	return map

## 组合矩阵图 = 边带 + 角带（一次构建双矩阵——流形/面数穷举与 render_probe 共用）。
static func build_matrix(cliff_threshold := 3) -> MapDataClass:
	var dmax := edge_delta_max(cliff_threshold)
	var edge_w := PAIR_COL0 + PAIR_SPACING * (dmax + 1) * 6 + 2
	var classes := _corner_classes(dmax)
	var corner_w := PAIR_COL0 + PAIR_SPACING * classes.size() + 2
	var map := MapDataClass.new(maxi(edge_w, corner_w), CORNER_ROW + 2)
	var used := {}
	var pair := 0
	for delta in dmax + 1:
		for d in 6:
			var a := Hex.axial_of(Vector2i(PAIR_COL0 + PAIR_SPACING * pair, EDGE_ROW))
			var b := Hex.neighbor(a, d)
			_claim(map, used, a, 0, delta, d, pair)
			_claim(map, used, b, delta, delta, d, pair)
			pair += 1
	for j in classes.size():
		var trio: Array = classes[j]
		var x := Hex.axial_of(Vector2i(PAIR_COL0 + PAIR_SPACING * j, CORNER_ROW))
		_claim(map, used, x, int(trio[0]), -1, j, -1)
		_claim(map, used, Hex.neighbor(x, 1), int(trio[1]), -1, j, -2)
		_claim(map, used, Hex.neighbor(x, 0), int(trio[2]), -1, j, -3)
	return map

## (0..max_e)³ 的 (min,mid,max) 等价类全集（多重集升序枚举——a≤b≤c；max_e=3 →
## C(6,3)=20 类）。顺序确定性（字典序），测试按序对表。
static func _corner_classes(max_e: int) -> Array:
	var out: Array = []
	for a in max_e + 1:
		for b in range(a, max_e + 1):
			for c in range(b, max_e + 1):
				out.append([a, b, c])
	return out

## 特征格占位 + 高程写入 + 冲突自检（同格二次占用 = 布局错误——push_error 上报，
## 不静默覆盖：矩阵归因干净优先于容错）。
static func _claim(map: MapDataClass, used: Dictionary, cell: Vector2i,
		elevation: int, _delta: int, _dir: int, _pair: int) -> void:
	if not map.has_cell(cell):
		push_error("[矩阵图] 特征格越界 %s（布局参数错误——检查宽度计算）" % str(cell))
		return
	if used.has(cell):
		push_error("[矩阵图] 特征格冲突 %s（间距不足？PAIR_SPACING=%d）" % [str(cell), PAIR_SPACING])
		return
	used[cell] = true
	map.set_elevation(cell, elevation)
