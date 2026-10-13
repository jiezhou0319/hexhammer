## terrain_view_data.gd — 地形调试视图数据派生（纯逻辑件；T6 S2 前置「调试预览」
##   harness 的数据面——docs/M1a-terrain-T6-stylized-execution-plan.md §4 S2 预览工具
##   先于生成器改动落地：提案 docs/evidence/风格化地图生成方案_群山平原与派系适配_修订版.md
##   §实施分期 P0「调试预览」（:236）五视图中的数据派生三个实做 + 两个挂点）
## 合同：纯静态函数、RefCounted、零场景节点、只读 MapData/MapConnectivity、不改入参
##   地图（ADR-2）；双消费者 = tests/test_terrain_view_data.gd（逐行为锚定）与
##   tools/terrain_debug_views.gd（渲染面）——派生口径变更须同步两侧测试锚
##   （tools/land_matrix_fixtures.gd「固定 fixture 库供测试与工具共用」先例）。
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
##   - region/skeleton：挂点预留（依赖 S3/S4 落地的 TerrainRegion/TerrainSkeleton
##     数据，本阶段不存在）——derive() 分派恒返回 implemented=false + 具名原因，
##     不产伪字段（提案「关闭一个尚未实现能力不产生伪字段」锚的视图面表达）。
class_name TerrainViewData
extends RefCounted

const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapConnectivity := preload("res://scripts/content/map_connectivity.gd")

## 视图名固定序（CLI views=all 的展开序；region/skeleton = 挂点）
const VIEW_ORDER: Array[String] = ["height", "slope", "passability", "region", "skeleton"]

## 已实做视图（region/skeleton 依赖 S3/S4 数据，未落地）
const IMPLEMENTED_VIEWS: Array[String] = ["height", "slope", "passability"]

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

# ---------------- 挂点预留（S3/S4 落地后填充）----------------

## region 视图（挂点）：依赖 TerrainRegion（WorldData regions 组，S3 分区骨架）——
## 未落地，显式 implemented=false，不产伪字段。
static func region_view(_map: MapDataClass) -> Dictionary:
	return {
		"view": "region", "implemented": false,
		"reason": "未实现：region 视图依赖 TerrainRegion（S3 分区骨架）数据，本阶段为挂点预留",
	}

## skeleton 视图（挂点）：依赖 TerrainSkeleton（山系/宽谷/盆地/孤峰，S3/S4）——
## 未落地，显式 implemented=false，不产伪字段。
static func skeleton_view(_map: MapDataClass) -> Dictionary:
	return {
		"view": "skeleton", "implemented": false,
		"reason": "未实现：skeleton 视图依赖 TerrainSkeleton（S3 骨架/S4 孤峰）数据，本阶段为挂点预留",
	}

# ---------------- 统一分派 ----------------

## 视图名单一分派（渲染/CLI 唯一入口）：实做视图各归其位；挂点/未知名 →
## implemented=false（原因具名——调用方显式报「未实现」，不冒充）。
static func derive(view_name: String, map: MapDataClass) -> Dictionary:
	match view_name:
		"height":
			return height_view(map)
		"slope":
			return slope_view(map)
		"passability":
			return passability_view(map)
		"region":
			return region_view(map)
		"skeleton":
			return skeleton_view(map)
		_:
			return {
				"view": view_name, "implemented": false,
				"reason": "未知视图 %s（可选：%s）" % [view_name, ", ".join(VIEW_ORDER)],
			}
