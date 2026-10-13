## terrain_view_data.gd — 地形调试视图数据派生（纯逻辑件；T6 S2 前置「调试预览」
##   harness 的数据面——docs/M1a-terrain-T6-stylized-execution-plan.md §4 S2 预览工具
##   先于生成器改动落地：提案 docs/evidence/风格化地图生成方案_群山平原与派系适配_修订版.md
##   §实施分期 P0「调试预览」（:236）五视图的数据派生；region/skeleton 两视图
##   随 S3 分区骨架落地（T6 §5 验收「S2 五视图中区域/骨架两视图出数」——
##   从挂点转实做，依赖 WorldData 地貌分区/骨架事实）
## 合同：纯静态函数、RefCounted、零场景节点、只读 MapData/MapConnectivity/
##   WorldData、不改入参地图（ADR-2）；双消费者 = tests/test_terrain_view_data.gd
##   （逐行为锚定）与 tools/terrain_debug_views.gd（渲染面）——派生口径变更须同步
##   两侧测试锚（tools/land_matrix_fixtures.gd「固定 fixture 库供测试与工具共用」先例）。
## 视图口径（归一化规则写死——渲染确定性与跨版本可比的前提）：
##   - height 高度灰度：gray = (高程 − min)/(max − min)，min/max 取全图（水格 0 档
##     参与归一——水 = 最暗）；range = 0（常数场）→ 恒 0.5（统一中灰的显式态，
##     「渲染成功但无起伏」不与「未渲染」混淆）；
##   - slope 坡度：slope(格) = 对全部界内邻居的 max |高程差|（最大邻差 = 最陡方向
##     代理；与 hex_terrain_builder.classify_edge 的 Δ 幅值同源但**不分类**——视图
##     要的是强度不是档位）；gray = slope/max_slope；全平 → 恒 0.0（无坡 = 最暗，
##     与 height 的常数场 0.5 显式区分——两个退化态各自可辨）；
##   - passability 可用通行连通片：连通片口径 = MapConnectivity.check（通行格 BFS、
##     neighbors_existing 邻接——**不复读实现**，唯一权威）；分级着色 = 按片大小降序
##     秩：秩 0（最大片）→ 色板首项亮灰基准（可用主体一眼可辨），其余按秩循环取
##     固定色板（多片断路/孤岛的分辨力）；同大小并列 → 首发现序在前（确定性）；
##     不可通行格 → IMPASSABLE_COLOR（近黑灰，与纯黑背景及灰度数据色 8 位差 ≥ 25
##     ——图幅范围恒可读）；
##   - region 区域（S3 实做）：灰度 = 群山权重连续场——gray = lerp(平原亮 0.78,
##     群山暗 0.30, w)，w = WorldData.cell_mountain_weights/1000（千分整数）。
##     **纯灰度连续场**（提案 :278「统一灰度」评审口径的分区面——大片群山区/
##     平原区两档主导 + 过渡带渐变，不靠颜色区分）；无区域事实（dual_noise 路线/
##     旧图/无 world 伴生）→ has_data=false + 具名原因（S2 合同「无区域数据」
##     显式态——不产伪字段）；
##   - skeleton 骨架（S3 实做）：四级灰度结构图——谷底 0.45 / 支脉 0.65 / 主脊
##     0.95 / 背景 0.18（同格多属取最高优先级：主脊 > 支脉 > 谷底）；同样
##     has_data=false 显式态。孤峰层随 S4 扩（预留：值域加档不改既有档）。
class_name TerrainViewData
extends RefCounted

const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapConnectivity := preload("res://scripts/content/map_connectivity.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")

## 视图名固定序（CLI views=all 的展开序；五视图全部实做——region/skeleton 自 S3）
const VIEW_ORDER: Array[String] = ["height", "slope", "passability", "region", "skeleton"]

## 已实做视图（S3 起 region/skeleton 转实做——数据依赖面见各视图头注）
const IMPLEMENTED_VIEWS: Array[String] = ["height", "slope", "passability", "region", "skeleton"]

## 不可通行格色（近黑灰 ~40/255：与纯黑背景、灰度数据最暗值均差 ≥ 25/255——
## 判定容差（render_probe CHANNEL_TOL=14）之外，slope=0/水格 0 档纯黑数据格
## 与背景亦可分辨；图幅范围恒可读的取色依据）
const IMPASSABLE_COLOR := Color(40.0 / 255.0, 40.0 / 255.0, 40.0 / 255.0)

## 连通片分级色板：首项 = 最大片亮灰基准（主体中性亮灰）；其余秩循环取后 7 项
## （色相分离的调试色——本视图是结构性调试视图，非灰度评审面：提案 :278 的
## 「统一灰度」人工评审属 S7，与本视图用途互补不冲突）
const COMPONENT_PALETTE: Array[Color] = [
	Color(0.92, 0.92, 0.92),  # 秩 0 最大片——亮灰基准
	Color(0.89, 0.25, 0.30),  # 红
	Color(0.20, 0.78, 0.44),  # 绿
	Color(0.25, 0.62, 0.90),  # 蓝
	Color(0.94, 0.77, 0.20),  # 黄
	Color(0.63, 0.38, 0.72),  # 紫
	Color(0.15, 0.73, 0.68),  # 青
	Color(0.88, 0.55, 0.18),  # 橙
]

# ---------------- 高度灰度 ----------------

## 高度灰度视图：逐格高程归一化灰度。返回 {
##   "view": "height", "implemented": true,
##   "values": PackedFloat32Array（cells() 固定遍历序，[0,1]）,
##   "colors": PackedColorArray（灰度 Color(v,v,v)，与 values 同序）,
##   "min_elevation": int, "max_elevation": int, "range": int }
static func height_view(map: MapDataClass) -> Dictionary:
	var cells := map.cells()
	var min_e := 0
	var max_e := 0
	var first := true
	for cell in cells:
		var e := map.elevation_at(cell)
		if first:
			min_e = e
			max_e = e
			first = false
		else:
			min_e = mini(min_e, e)
			max_e = maxi(max_e, e)
	var range_e := max_e - min_e
	var values := PackedFloat32Array()
	var colors := PackedColorArray()
	values.resize(cells.size())
	colors.resize(cells.size())
	for i in cells.size():
		var e := map.elevation_at(cells[i])
		var v := 0.5 if range_e == 0 else float(e - min_e) / float(range_e)
		values[i] = v
		colors[i] = Color(v, v, v)
	return {
		"view": "height", "implemented": true, "values": values, "colors": colors,
		"min_elevation": min_e, "max_elevation": max_e, "range": range_e,
	}

# ---------------- 坡度 ----------------

## 坡度视图：逐格最大邻差归一化灰度。返回 {
##   "view": "slope", "implemented": true,
##   "values": PackedFloat32Array, "colors": PackedColorArray（同上序）,
##   "max_slope": int }
static func slope_view(map: MapDataClass) -> Dictionary:
	var cells := map.cells()
	var slopes := PackedInt32Array()
	slopes.resize(cells.size())
	var max_slope := 0
	for i in cells.size():
		var cell: Vector2i = cells[i]
		var s := 0
		for nb in map.neighbors_existing(cell):
			s = maxi(s, absi(map.elevation_at(cell) - map.elevation_at(nb)))
		slopes[i] = s
		max_slope = maxi(max_slope, s)
	var values := PackedFloat32Array()
	var colors := PackedColorArray()
	values.resize(cells.size())
	colors.resize(cells.size())
	for i in cells.size():
		var v := float(slopes[i]) / float(max_slope) if max_slope > 0 else 0.0
		values[i] = v
		colors[i] = Color(v, v, v)
	return {
		"view": "slope", "implemented": true, "values": values, "colors": colors,
		"max_slope": max_slope,
	}

# ---------------- 可用通行连通片 ----------------

## 可用通行连通片视图（分级着色）。返回 {
##   "view": "passability", "implemented": true,
##   "colors": PackedColorArray（cells() 序；不可通行格 = IMPASSABLE_COLOR）,
##   "ranks": PackedInt32Array（格 → 所在片秩；不可通行 = -1——秩表即图例表）,
##   "passable_total"/"component_count"/"largest_size"/"largest_fraction"/"ok":
##     MapConnectivity.check 同名值（复读报告，不再算第二遍）,
##   "isolated_count": int, "component_sizes": Array[int]（按秩降序——分级图例） }
static func passability_view(map: MapDataClass) -> Dictionary:
	var report := MapConnectivity.check(map)
	var components: Array = report["components"]
	# 分级排序：片大小降序；并列 → 首发现序在前（check 的 BFS 发现序确定——确定性）
	var order: Array = []
	for i in components.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var sa: int = (components[a] as Array).size()
		var sb: int = (components[b] as Array).size()
		if sa != sb:
			return sa > sb
		return a < b)
	var rank_of := {}
	for rank in order.size():
		rank_of[order[rank]] = rank
	var cell_color := {}
	var cell_rank := {}
	for ci in components.size():
		var c := component_color(int(rank_of[ci]))
		for cell in components[ci]:
			cell_color[cell] = c
			cell_rank[cell] = int(rank_of[ci])
	var sizes: Array[int] = []
	for rank in order.size():
		sizes.append((components[int(order[rank])] as Array).size())
	var cells := map.cells()
	var colors := PackedColorArray()
	var ranks := PackedInt32Array()
	colors.resize(cells.size())
	ranks.resize(cells.size())
	for i in cells.size():
		var cell: Vector2i = cells[i]
		if cell_color.has(cell):
			colors[i] = cell_color[cell]
			ranks[i] = cell_rank[cell]
		else:
			colors[i] = IMPASSABLE_COLOR
			ranks[i] = -1
	return {
		"view": "passability", "implemented": true, "colors": colors, "ranks": ranks,
		"passable_total": report["passable_total"],
		"component_count": report["component_count"],
		"largest_size": report["largest_size"],
		"largest_fraction": report["largest_fraction"],
		"ok": report["ok"],
		"isolated_count": (report["isolated_cells"] as Array).size(),
		"component_sizes": sizes,
	}

## 连通片色：秩 0 → 色板首项（最大片亮灰基准）；其余按秩循环取后 7 项。
static func component_color(rank: int) -> Color:
	if rank <= 0:
		return COMPONENT_PALETTE[0]
	return COMPONENT_PALETTE[1 + (rank - 1) % (COMPONENT_PALETTE.size() - 1)]

# ---------------- 区域（S3 实做：群山权重连续场灰度）----------------

## region 视图灰度档（写死——跨版本可比）：平原亮 / 群山暗（暗 = 高重量——
## 与 height 视图「高 = 亮」反向，两视图并排不混淆）
const REGION_PLAIN_GRAY := 0.78
const REGION_MOUNTAIN_GRAY := 0.30

## 区域视图：gray = lerp(平原亮, 群山暗, w)——WorldData.cell_mountain_weights
## 千分整数驱动的**纯灰度连续场**（大片两档主导 + 过渡带渐变；提案 :278「统一
## 灰度、不靠颜色区分」的分区面）。返回 {
##   "view": "region", "implemented": true, "has_data": bool,
##   "reason": String（has_data=false 时具名）,
##   "values": PackedFloat32Array（cells() 序，w ∈ [0,1]）,
##   "colors": PackedColorArray（灰度 Color(v,v,v)）,
##   "region_count"/"mountain_regions"/"plain_regions": int,
##   "high_cells"/"low_cells": int（w ≥0.7 / ≤0.3 格数——两档主导在场的证据面）}
static func region_view(map: MapDataClass, world: WorldDataClass = null) -> Dictionary:
	var no_data := _no_region_data_reason(world)
	if no_data != "":
		return {"view": "region", "implemented": true, "has_data": false,
			"reason": no_data}
	var cells := map.cells()
	var values := PackedFloat32Array()
	var colors := PackedColorArray()
	values.resize(cells.size())
	colors.resize(cells.size())
	var high := 0
	var low := 0
	for i in cells.size():
		var w := float(world.cell_mountain_weights[i]) / 1000.0
		var g := lerpf(REGION_PLAIN_GRAY, REGION_MOUNTAIN_GRAY, w)
		values[i] = w
		colors[i] = Color(g, g, g)
		if w >= 0.7:
			high += 1
		if w <= 0.3:
			low += 1
	var mountain_regions := 0
	for rg in world.terrain_regions:
		if rg.dominant_landform == WorldDataClass.TerrainRegion.DominantLandform.MOUNTAINS:
			mountain_regions += 1
	return {
		"view": "region", "implemented": true, "has_data": true,
		"values": values, "colors": colors,
		"region_count": world.terrain_regions.size(),
		"mountain_regions": mountain_regions,
		"plain_regions": world.terrain_regions.size() - mountain_regions,
		"high_cells": high, "low_cells": low,
	}

# ---------------- 骨架（S3 实做：主脊/支脉/谷底四级灰度）----------------

## skeleton 视图灰度档（写死；孤峰层 S4 预留加档——值域加档不改既有档）
const SKELETON_BG_GRAY := 0.18
const SKELETON_VALLEY_GRAY := 0.45
const SKELETON_BRANCH_GRAY := 0.65
const SKELETON_SPINE_GRAY := 0.95

## 骨架视图：主脊 0.95 / 支脉 0.65 / 谷底 0.45 / 背景 0.18（同格多属取最高
## 优先级：主脊 > 支脉 > 谷底）。返回 { "view": "skeleton",
##   "implemented": true, "has_data": bool, "reason": String,
##   "ranks": PackedInt32Array（-1 背景/0 谷底/1 支脉/2 主脊——秩表即图例表）,
##   "colors": PackedColorArray,
##   "ranges"/"branches"/"valleys"/"valley_cells": int }
static func skeleton_view(map: MapDataClass, world: WorldDataClass = null) -> Dictionary:
	var no_data := _no_region_data_reason(world)
	if no_data != "":
		return {"view": "skeleton", "implemented": true, "has_data": false,
			"reason": no_data}
	var cells := map.cells()
	var ranks := PackedInt32Array()
	ranks.resize(cells.size())
	for i in cells.size():
		ranks[i] = -1
	for vl in world.valleys:
		for cid in vl.cells:
			if cid >= 0 and cid < ranks.size() and ranks[cid] < 0:
				ranks[cid] = 0
	for br in world.ridge_branches:
		for cid in br.cells:
			if cid >= 0 and cid < ranks.size() and ranks[cid] < 1:
				ranks[cid] = 1
	for mr in world.mountain_ranges:
		for cid in mr.spine_cells:
			if cid >= 0 and cid < ranks.size():
				ranks[cid] = 2
	var colors := PackedColorArray()
	colors.resize(cells.size())
	for i in cells.size():
		var g := SKELETON_BG_GRAY
		match ranks[i]:
			0:
				g = SKELETON_VALLEY_GRAY
			1:
				g = SKELETON_BRANCH_GRAY
			2:
				g = SKELETON_SPINE_GRAY
		colors[i] = Color(g, g, g)
	var valley_cells := 0
	for vl in world.valleys:
		valley_cells += vl.cells.size()
	return {
		"view": "skeleton", "implemented": true, "has_data": true,
		"ranks": ranks, "colors": colors,
		"ranges": world.mountain_ranges.size(),
		"branches": world.ridge_branches.size(),
		"valleys": world.valleys.size(),
		"valley_cells": valley_cells,
	}


## 无区域数据原因（region/skeleton 共用）：无 world 伴生 / 区域事实为空——
## dual_noise 路线与旧图的显式态（S2 合同：显式报「无区域数据」不产伪字段）。
static func _no_region_data_reason(world: WorldDataClass) -> String:
	if world == null:
		return "无区域数据（未提供 WorldData——银行样图缺 .world.json 伴生或调用方未传）"
	if world.terrain_regions.is_empty():
		return "无区域数据（dual_noise 路线/旧图——regions 模板路线才产分区事实）"
	return ""

# ---------------- 统一分派 ----------------

## 视图名单一分派（渲染/CLI 唯一入口）：实做视图各归其位（region/skeleton 自
## S3 转实做——数据面见各视图头注）；未知名 → implemented=false（原因具名——
## 调用方显式报「未实现」，不冒充）。world 缺省 = 数据面视图走 has_data=false。
static func derive(view_name: String, map: MapDataClass,
		world: WorldDataClass = null) -> Dictionary:
	match view_name:
		"height":
			return height_view(map)
		"slope":
			return slope_view(map)
		"passability":
			return passability_view(map)
		"region":
			return region_view(map, world)
		"skeleton":
			return skeleton_view(map, world)
		_:
			return {
				"view": view_name, "implemented": false,
				"reason": "未知视图 %s（可选：%s）" % [view_name, ", ".join(VIEW_ORDER)],
			}
