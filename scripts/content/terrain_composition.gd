## terrain_composition.gd — 宏观分区与地貌骨架生成器（T6 S3；执行方案
##   docs/M1a-terrain-T6-stylized-execution-plan.md §5 + 提案
##   docs/evidence/风格化地图生成方案_群山平原与派系适配_修订版.md §宏观分区
##   :61-71 / §群山与孤峰的不同职责 :73-82 / §连续高度与过渡 :84-98；
##   T6 S4 增孤峰地标项——§6 + 提案 :78-82）
## 职责：regions 模板路线的 composition 阶段四步（每步纯函数、独立可测）：
##   ① 宏观分区——种子布点（layout 通道）→ Voronoi 归属 → 小区域合并 →
##     主导地貌指派（region 通道）→ 核心格/过渡半径/连续权重场/邻接表；
##   ② 地貌骨架——群山区主山系（有走向脊线 + 纵向强度终止/降低，提案 :96）+
##     支脉 + 宽谷（mountain 通道）；平原区 = 大片低起伏（无骨架对象——缓丘由
##     基础场承载，提案 :68）；
##   ③ 连续高度混合——提案 :88-94 设计表达式：
##       最终高度 = 基础大陆高度（geography 双噪声归一场）
##                 + 群山权重 × 骨架高度（区域抬升 + 脊线核 + 宽谷下切）
##                 + 平原权重 × 缓丘（基础场低增益）
##                 + 振幅受限细节（独立细节场；平原振幅 ≤ 群山振幅——提案 :98
##                   平原起伏预算）
##     产物是连续场（写入 GenState.heights），量化/投影仍由既有 quantize 阶段
##     独占——「先连续地形、后格级投影」纪律（提案 :102 主线序）；
##   ④ 孤峰地标（S4，isolated_peak 通道）——提案 :88-94 表达式第四项：
##     显式对象（中心/影响半径/峰高/圆锥轮廓）在有效平原内按预算/间距/避让
##     布点后叠加锥形增益。**主山系内部突出峰不自动算孤峰**（提案 :79——按对象
##     归属判定：候选中心距一切脊/支脉格 ≥ 最小间距，骨架峰只属骨架对象）；
##     数量由有效平原面积与预算决定，小图可零座（提案 :82）。
## 随机通道纪律：四通道各管一步（layout=布点、region=地貌指派、mountain=骨架、
##   isolated_peak=孤峰布点），互相独立可锚（改 mountain 不动分区；改 region 不动
##   布点；改 isolated_peak 不动前三步任何事实）；细节场是连续噪声（第三场），
##   seed 偏移 2027 与植被场 1013 及全部通道偏移互质错开（两层随机不串流）。
## 全部数值参数 = **未验证起调值**（模板 regions 组传入；T6 方案 §10）。
## 纯逻辑类：RefCounted、零场景节点、不写任何数据（ADR-2；删 scripts/ui/**
##   后 tests 全绿）。生成器配置（模板）不进世界事实（草案 §1.2 边界维持）。
class_name TerrainComposition
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")

# ---- 连续场固定配置（写死保证复现——WorldPipeline.VEGETATION_* 同纪律；
#      口味变更 = GENERATOR_VERSION+1）----

## 细节场 seed 偏移（第三连续场：与植被场 1013、五+四通道偏移 101..907 互异）
const DETAIL_FIELD_SEED_OFFSET := 2027
## 细节场频率 = 基础场频率 × 此倍率（细节 = 高频小起伏，基础 = 低频大陆形态）
const DETAIL_FREQUENCY_SCALE := 4.0
## 细节场 FBM 倍频数（小起伏 2 档足够——细节场不承担构图）
const DETAIL_OCTAVES := 2

# ---- 骨架固定数值（未验证起调值——写死进生成器版本管理，提案数值档随模板）----

## 群山区整体抬升（mw=1 处的基础骨架高度——「群山是区域结构」的区域面）
const MOUNTAIN_BASE_UPLIFT := 0.30
## 平原缓丘增益（平原骨架 = 基础场 × 此值——大片低起伏，非平地）
const PLAIN_ROLLING_GAIN := 0.12
## 平原细节振幅上限（提案 :98 平原起伏预算的振幅面）
const PLAIN_DETAIL_AMPLITUDE := 0.05
## 群山细节振幅（群山细节强度可更高，提案 :98；0.12 起调——量化 Δ 预算
## 与山体可读性的折中，未验证起调值）
const MOUNTAIN_DETAIL_AMPLITUDE := 0.12
## 脊线宽度 = 过渡半径 × 此倍率（山体横向尺度与过渡带同源——山前丘陵连贯）
const RIDGE_WIDTH_SCALE := 1.2
## 宽谷带宽 = 过渡半径 × 此倍率（谷底带宽度；提案 :68 宽谷）
const VALLEY_SPAN_SCALE := 0.75
## 宽谷下切深度（骨架高度在谷底的衰减比例——谷地低于两侧山肩）
const VALLEY_CARVE := 0.70
## 主脊纵向强度的最低档（两端终止/降低——提案 :96「避免边界被切断的山脊」：
## 强度向两端衰减到地板值再由横向 falloff 归零，脊线永不被硬切断）
const SPINE_TAPER_FLOOR := 0.15
## 支脉强度 = 主脊强度 × 此倍率（支脉矮于主脊，提案 :77 层次）
const BRANCH_STRENGTH_SCALE := 0.5

# ---- 孤峰固定数值（S4；未验证起调值——布点规则写死，峰参数随模板）----

## 有效平原判档（群山权重 ≤ 此值的格 = 有效平原——预算分母与候选池同档；
## 与 region/skeleton 视图的 w≤0.3「平原主导档」同阈，提案 :78「有效平原面积」）
const EFFECTIVE_PLAIN_WEIGHT_MAX := 0.30

# ---------------- 入口 ----------------

## composition 阶段唯一入口。入参：
##   map                已建载体（geography 阶段产出）
##   base_heights       geography 双噪声原始采样（本函数内归一为基础场）
##   base_min/base_max  基础场极值（geography 阶段产出）
##   rngs               {"layout", "region", "mountain", "isolated_peak"} 四通道 rng
##   cfg                模板 regions 组 + {"seed", "base_frequency", "sea_level"}
## 返回 {"ok", "error",
##   "regions": Array[WorldDataClass.TerrainRegion]（region_id 升序）,
##   "ranges": Array[WorldDataClass.MountainRangeData],
##   "branches": Array[WorldDataClass.RidgeBranchData],
##   "valleys": Array[WorldDataClass.ValleyData],
##   "peaks": Array[WorldDataClass.IsolatedPeakData]（peak_id 升序；可空——小图
##     零孤峰合法态，提案 :82）,
##   "cell_regions": Array[int]（行长，-1 不出现——regions 路线全覆盖）,
##   "cell_mountain_weights": Array[int]（千分整数 0..1000）,
##   "heights": PackedFloat32Array（混合后连续高度——quantize 的唯一输入）,
##   "stats": {结构统计 + 连续场邻差诊断（max_neighbor_delta /
##     boundary_max_delta——「过渡带无阶跃」的留证面）+ 孤峰统计}}
static func generate(map: MapDataClass, base_heights: PackedFloat32Array,
		base_min: float, base_max: float, rngs: Dictionary, cfg: Dictionary) -> Dictionary:
	var cell_n := map.cell_count()
	if cell_n == 0:
		return {"ok": false, "error": "空图无分区意义（regions 路线须 ≥1 格）"}
	if base_heights.size() != cell_n:
		return {"ok": false, "error": "基础场长度 %d ≠ 格数 %d（geography 产物损坏）" \
			% [base_heights.size(), cell_n]}
	var base_range := base_max - base_min
	var base := PackedFloat32Array()
	base.resize(cell_n)
	for i in cell_n:
		base[i] = (float(base_heights[i]) - base_min) / base_range if base_range > 0.0 else 0.5

	# ① 宏观分区
	var part := partition(map, rngs["layout"], rngs["region"], {
		"region_count": int(cfg["region_count"]),
		"region_min_core_cells": int(cfg["region_min_core_cells"]),
		"region_transition_width": float(cfg["region_transition_width"]),
	})
	if not part["ok"]:
		return {"ok": false, "error": "宏观分区失败：%s" % part["error"]}
	var regions: Array = part["regions"]
	var cell_region: Array[int] = part["cell_region"]
	var weight_mountains: PackedFloat32Array = part["weight_mountains"]

	# ② 地貌骨架（只进群山区）
	var skel := build_skeleton(map, regions, cell_region, rngs["mountain"], {
		"mountain_range_count": int(cfg["mountain_range_count"]),
		"mountain_branch_count": int(cfg["mountain_branch_count"]),
		"transition_radius": int(part["transition_radius"]),
	})
	if not skel["ok"]:
		return {"ok": false, "error": "地貌骨架失败：%s" % skel["error"]}

	# ③ 连续高度混合（提案 :88-94 表达式前三项——第四项孤峰在 ④ 叠加）
	var detail := _detail_field(map, int(cfg["seed"]), float(cfg["base_frequency"]))
	var skeleton_height: PackedFloat32Array = skel["skeleton_height"]
	var heights := PackedFloat32Array()
	heights.resize(cell_n)
	var cells := map.cells()
	for i in cell_n:
		var mw := float(weight_mountains[i])
		var detail_amp := lerpf(PLAIN_DETAIL_AMPLITUDE, MOUNTAIN_DETAIL_AMPLITUDE, mw)
		heights[i] = base[i] + mw * float(skeleton_height[i]) \
			+ (1.0 - mw) * (PLAIN_ROLLING_GAIN * float(base[i])) \
			+ detail_amp * (float(detail[i]) - 0.5)
	var mix_min := INF
	var mix_max := -INF
	for v in heights:
		mix_min = minf(mix_min, v)
		mix_max = maxf(mix_max, v)

	# ④ 孤峰地标（S4：表达式第四项——布点消耗 isolated_peak 通道）
	var peak_result := place_isolated_peaks(map, heights, mix_min, mix_max,
		weight_mountains, cell_region, {
			"ranges": skel["ranges"],
			"branches": skel["branches"],
		}, rngs["isolated_peak"], {
			"sea_level": float(cfg["sea_level"]),
			"peak_area_budget_ratio": float(cfg["peak_area_budget_ratio"]),
			"peak_influence_radius": int(cfg["peak_influence_radius"]),
			"peak_height": int(cfg["peak_height"]),
			"peak_spacing_radius_scale": float(cfg["peak_spacing_radius_scale"]),
		})
	if not peak_result["ok"]:
		return {"ok": false, "error": "孤峰布点失败：%s" % peak_result["error"]}
	var peaks: Array = peak_result["peaks"]
	for pk in peaks:
		var peak: WorldDataClass.IsolatedPeakData = pk
		var center := _cell_of_id(map, peak.cell_id)
		var gain := float(peak.peak_height) / 1000.0
		for other in map.cells():
			var d := Hex.distance(center, other)
			if d > peak.influence_radius:
				continue
			heights[map.index_of(other)] += gain * cone_falloff(d, peak.influence_radius)

	# 格级事实（千分整数——落盘确定形状）
	var cell_mountain_weights: Array[int] = []
	cell_mountain_weights.resize(cell_n)
	for i in cell_n:
		cell_mountain_weights[i] = clampi(int(round(float(weight_mountains[i]) * 1000.0)), 0, 1000)

	# 连续场邻差诊断（「过渡带无分区编号断缝」的留证面——机器断言在 tests）
	var step := _neighbor_step_stats(map, heights, cell_region)
	var peak_stats: Dictionary = peak_result["stats"]
	return {"ok": true, "error": "",
		"regions": regions,
		"ranges": skel["ranges"],
		"branches": skel["branches"],
		"valleys": skel["valleys"],
		"peaks": peaks,
		"cell_regions": cell_region,
		"cell_mountain_weights": cell_mountain_weights,
		"heights": heights,
		"stats": {
			"region_count": regions.size(),
			"mountain_regions": part["mountain_region_count"],
			"plain_regions": regions.size() - int(part["mountain_region_count"]),
			"transition_radius": int(part["transition_radius"]),
			"core_cells": int(part["core_cell_count"]),
			"transition_cells": cell_n - int(part["core_cell_count"]),
			"adjacency_pairs": int(part["adjacency_pairs"]),
			"ranges": (skel["ranges"] as Array).size(),
			"branches": (skel["branches"] as Array).size(),
			"valley_cells": int(skel["valley_cell_count"]),
			"effective_plain_cells": int(peak_stats["effective_plain_cells"]),
			"peaks": peaks.size(),
			"peak_influence_cells": int(peak_stats["influence_cells"]),
			"weight_high_cells": int(step["high_cells"]),
			"weight_low_cells": int(step["low_cells"]),
			"max_neighbor_delta": float(step["max_delta"]),
			"boundary_max_delta": float(step["boundary_max_delta"]),
		}}


# ---------------- ① 宏观分区 ----------------

## 分区三步：种子布点（layout rng）→ 归属/合并 → 地貌指派/核心/权重/邻接
## （region rng 只进指派——布点与指派通道隔离的锚面）。
static func partition(map: MapDataClass, rng_layout: RandomNumberGenerator,
		rng_region: RandomNumberGenerator, cfg: Dictionary) -> Dictionary:
	var cell_n := map.cell_count()
	var want := clampi(int(cfg["region_count"]), 2, 16)
	# 布点：候选格 rng 洗牌后贪心收取（间距 ≥ spacing）；收不够 → 间距减半重试
	# （小图自动降档——「区域数随地图尺寸确定，不机械套用」，提案 :63）
	var ids := []
	ids.resize(cell_n)
	for i in cell_n:
		ids[i] = i
	var seeds: Array[int] = []
	var spacing := maxi(2, int(round(sqrt(float(cell_n) / float(want)) * 0.9)))
	while true:
		var shuffled := _shuffle_ints(rng_layout, ids)
		seeds = []
		for cid in shuffled:
			if seeds.size() >= want:
				break
			var ok := true
			var cell := _cell_of_id(map, cid)
			for s in seeds:
				if Hex.distance(cell, _cell_of_id(map, s)) < spacing:
					ok = false
					break
			if ok:
				seeds.append(cid)
		if seeds.size() >= want or spacing <= 2:
			break
		spacing = maxi(2, spacing / 2)
	if seeds.size() > want:
		seeds = seeds.slice(0, want)
	if seeds.is_empty():
		return {"ok": false, "error": "零种子（0 格图？）"}

	# 归属：多种子 BFS（种子序 = 收取序；先到先得——确定性）
	var owner := PackedInt32Array()
	owner.resize(cell_n)
	for i in cell_n:
		owner[i] = -1
	var queue: Array = []
	for si in seeds.size():
		owner[seeds[si]] = si
		queue.append(seeds[si])
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for nb in _neighbor_ids(map, cur):
			if owner[nb] == -1:
				owner[nb] = owner[cur]
				queue.append(nb)
	var live_regions := {}
	for si in seeds.size():
		live_regions[si] = true

	# 合并小区域：最小者（并列取最小 id）并入共享边最多的邻域（并列取最小 id）；
	# 保底 ≥2 区不合并成 1（≥2 格图）
	var min_core := maxi(1, int(cfg["region_min_core_cells"]))
	while live_regions.size() > 2:
		var sizes := {}
		for i in cell_n:
			var o: int = owner[i]
			if o >= 0:
				sizes[o] = int(sizes.get(o, 0)) + 1
		var smallest := -1
		for o in live_regions:
			if int(sizes.get(o, 0)) < min_core and (smallest == -1 \
					or int(sizes.get(o, 0)) < int(sizes.get(smallest, 0))):
				smallest = o
		if smallest == -1:
			break  # 全部达标
		var neighbor_votes := {}
		for i in cell_n:
			if owner[i] != smallest:
				continue
			for nb in _neighbor_ids(map, i):
				var o2: int = owner[nb]
				if o2 >= 0 and o2 != smallest and live_regions.has(o2):
					neighbor_votes[o2] = int(neighbor_votes.get(o2, 0)) + 1
		var best := -1
		for o2 in neighbor_votes:
			if best == -1 or int(neighbor_votes[o2]) > int(neighbor_votes[best]):
				best = o2
		if best == -1:
			break  # 无邻可并（孤立区——保留，交给核心回退）
		for i in cell_n:
			if owner[i] == smallest:
				owner[i] = best
		live_regions.erase(smallest)
	# 重排 id：旧区索引按「最小成员格 id」升序 → 新 id 0..n-1（与 rng 收取序解耦
	# 的稳定编号——合并/未合并两种形态同一编号规则）
	var min_cell := {}
	for i in cell_n:
		var o: int = owner[i]
		if o >= 0 and (not min_cell.has(o) or i < int(min_cell[o])):
			min_cell[o] = i
	var old_indices: Array = min_cell.keys()
	old_indices.sort_custom(func(a: int, b: int) -> bool:
		return int(min_cell[a]) < int(min_cell[b]))
	var remap := {}
	for new_id in old_indices.size():
		remap[int(old_indices[new_id])] = new_id
	for i in cell_n:
		var o: int = owner[i]
		owner[i] = int(remap[o]) if o >= 0 else -1
	var region_n := old_indices.size()

	# 地貌指派（region rng）：区序洗牌后交替指派——两类主导必都在（≥2 区）
	var region_ids_list := []
	for new_id in region_n:
		region_ids_list.append(new_id)
	var shuffled_regions := _shuffle_ints(rng_region, region_ids_list)
	var landform := {}
	var first_mountains := rng_region.randf() < 0.5
	for k in shuffled_regions.size():
		var mountains_now := (k % 2 == 0) == first_mountains
		landform[shuffled_regions[k]] = WorldDataClass.TerrainRegion.DominantLandform.MOUNTAINS \
			if mountains_now else WorldDataClass.TerrainRegion.DominantLandform.PLAINS

	# 过渡半径（特征尺寸 = sqrt(格数/区数)；档来自模板比例——提案 :132）
	var char_size := sqrt(float(cell_n) / float(maxi(region_n, 1)))
	var transition_radius := clampi(int(round(float(cfg["region_transition_width"]) * char_size)), 2, 16)

	# 核心格：区内距最近异区格 > 过渡半径（BFS 距离场；空核心回退区最深格）
	var cores := {}
	var core_cell_count := 0
	for rid in region_n:
		var core := _core_of_region(map, owner, rid, transition_radius)
		cores[rid] = core
		core_cell_count += core.size()

	# 连续权重场：w_r = 1/(1+(d_r/T)²) 归一（d_r = 距 r 核心的六边形距离）
	var region_dist := {}
	for rid in region_n:
		region_dist[rid] = _bfs_distance_from_set(map, cores[rid])
	var weight_mountains := PackedFloat32Array()
	weight_mountains.resize(cell_n)
	var cell_region_out: Array[int] = []
	cell_region_out.resize(cell_n)
	for i in cell_n:
		var dists := []
		var vals := []
		var total := 0.0
		for rid in region_n:
			var d: int = region_dist[rid][i]
			var w := 1.0 / (1.0 + pow(float(d) / float(transition_radius), 2.0))
			dists.append(rid)
			vals.append(w)
			total += w
		if total <= 0.0:
			weight_mountains[i] = 0.0
			cell_region_out[i] = 0
			continue
		var best_rid := 0
		var best_w := -1.0
		var mountain_w := 0.0
		for k in dists.size():
			var w_norm: float = vals[k] / total
			if w_norm > best_w:
				best_w = w_norm
				best_rid = int(dists[k])
			if int(landform[dists[k]]) == WorldDataClass.TerrainRegion.DominantLandform.MOUNTAINS:
				mountain_w += w_norm
		weight_mountains[i] = mountain_w
		cell_region_out[i] = best_rid

	# 区域实体 + 邻接表（Voronoi 归属面上相邻格异区 → 互列；升序——区域的空间
	# 邻接是分区几何事实，与格级 argmax 归属（cell_region_out）分层表达）
	var regions_out: Array[WorldDataClass.TerrainRegion] = []
	var adjacency := {}
	var adjacency_pairs := 0
	for rid in region_n:
		adjacency[rid] = {}
	for i in cell_n:
		for nb in _neighbor_ids(map, i):
			var a: int = owner[i]
			var b: int = owner[nb]
			if a >= 0 and b >= 0 and a != b and not adjacency[a].has(b):
				adjacency[a][b] = true
				adjacency[b][a] = true
				adjacency_pairs += 1
	var mountain_region_count := 0
	for rid in region_n:
		var rg := WorldDataClass.TerrainRegion.new()
		rg.region_id = rid
		rg.dominant_landform = int(landform[rid])
		rg.core_cells.assign(cores[rid])
		rg.core_cells.sort()
		var adj_list: Array[int] = []
		for other in adjacency[rid]:
			adj_list.append(int(other))
		adj_list.sort()
		rg.adjacency = adj_list
		regions_out.append(rg)
		if rg.dominant_landform == WorldDataClass.TerrainRegion.DominantLandform.MOUNTAINS:
			mountain_region_count += 1
	return {"ok": true, "error": "", "regions": regions_out,
		"cell_region": cell_region_out, "weight_mountains": weight_mountains,
		"transition_radius": transition_radius, "core_cell_count": core_cell_count,
		"adjacency_pairs": adjacency_pairs, "mountain_region_count": mountain_region_count}


## 区域核心格：区内格距最近异区格（六边形 BFS 距离）> 过渡半径者；空核心回退
## 「区内最深格」（距异区最远，并列取最小 id——分区事实至少有核心，数据合同
## 空核心非法）。返回升序 cell id 列表。
static func _core_of_region(map: MapDataClass, owner: PackedInt32Array, rid: int,
		transition_radius: int) -> Array[int]:
	var foreign_sources: Array[int] = []
	var cell_n := map.cell_count()
	for i in cell_n:
		if int(owner[i]) != rid:
			foreign_sources.append(i)
	var d_foreign := _bfs_distance_from_set(map, foreign_sources)
	var core: Array[int] = []
	for i in cell_n:
		if int(owner[i]) == rid and int(d_foreign[i]) > transition_radius:
			core.append(i)
	if core.is_empty():
		# 回退：区内距任一异区格最近距离最大者（最深格；并列取最小 id）
		var best := -1
		var best_d := -1
		for i in cell_n:
			if int(owner[i]) != rid:
				continue
			var d: int = d_foreign[i]
			if d > best_d:
				best_d = d
				best = i
		if best >= 0:
			core.append(best)
	core.sort()
	return core


# ---------------- ② 地貌骨架 ----------------

## 群山区骨架：每区 ≤ mountain_range_count 条主山系（锚点 = 核心格 rng 抽取 +
## 区内最远核心格——走向横贯区域）+ 支脉（自主脊间隔抽取、向离脊方向生长）+
## 宽谷（脊侧横向带 = 谷底格集 + 骨架下切核）。平原区不产骨架对象。
## 返回骨架对象三表 + skeleton_height（群山骨架连续场，全区定义、经 mw 加权）。
static func build_skeleton(map: MapDataClass, regions: Array,
		cell_region: Array[int], rng_mountain: RandomNumberGenerator,
		cfg: Dictionary) -> Dictionary:
	var transition_radius := maxi(2, int(cfg["transition_radius"]))
	var ridge_width := maxi(2, int(round(float(transition_radius) * RIDGE_WIDTH_SCALE)))
	var valley_span := maxi(2, int(round(float(transition_radius) * VALLEY_SPAN_SCALE)))
	var ranges: Array[WorldDataClass.MountainRangeData] = []
	var branches: Array[WorldDataClass.RidgeBranchData] = []
	var valleys: Array[WorldDataClass.ValleyData] = []
	var range_skeleton_cells: Array = []  # 每条山系的 (cell → strength) 源强表
	var next_range_id := 0
	var next_branch_id := 0
	var next_valley_id := 0
	for rg in regions:
		var region: WorldDataClass.TerrainRegion = rg
		if region.dominant_landform != WorldDataClass.TerrainRegion.DominantLandform.MOUNTAINS:
			continue
		var cores: Array[int] = region.core_cells
		if cores.is_empty():
			continue
		var made_for_region := 0
		var attempts := 0
		while made_for_region < int(cfg["mountain_range_count"]) and attempts < int(cfg["mountain_range_count"]) * 3:
			attempts += 1
			var anchor_a: int = cores[rng_mountain.randi_range(0, cores.size() - 1)]
			# 锚 B = 距 A 世界距离最远的核心格（走向横贯；并列取最小 id——确定性）
			var anchor_b := -1
			var best_d := -1.0
			var wa := Hex.axial_to_world(_cell_of_id(map, anchor_a), 1.0)
			for cid in cores:
				if cid == anchor_a:
					continue
				var wb := Hex.axial_to_world(_cell_of_id(map, cid), 1.0)
				var d2 := wa.distance_squared_to(wb)
				if d2 > best_d:
					best_d = d2
					anchor_b = cid
			if anchor_b < 0:
				continue  # 单格核心——无走向可言（退化区跳过）
			var spine := _walk_spine(map, cell_region, region.region_id, anchor_a, anchor_b)
			if spine.is_empty():
				continue
			# 主脊纵向强度：两端衰减到地板（终止/降低——提案 :96，不被硬切断）
			var strengths := {}
			var n := spine.size()
			for i in n:
				var t := float(i) / float(maxi(n - 1, 1))
				strengths[spine[i]] = SPINE_TAPER_FLOOR \
					+ (1.0 - SPINE_TAPER_FLOOR) * pow(maxf(0.0, 1.0 - pow(2.0 * t - 1.0, 2.0)), 0.35)
			# 支脉：主脊中段间隔抽取根部，向「离主脊最远」方向生长
			var branch_budget := mini(int(cfg["mountain_branch_count"]), maxi(0, (n - 2) / 2))
			var spine_set := {}
			for cid in spine:
				spine_set[cid] = true
			var roots_taken := {}
			for b in branch_budget:
				var root_idx := -1
				for try_n in 6:
					var idx := rng_mountain.randi_range(1, n - 2)
					if not roots_taken.has(idx):
						root_idx = idx
						break
				if root_idx < 0:
					continue
				roots_taken[root_idx] = true
				var branch_cells := _walk_branch(map, cell_region, region.region_id,
					spine[root_idx], spine_set,
					clampi(int(round(float(transition_radius) * 0.8)), 2, 6))
				if branch_cells.is_empty():
					continue
				# 支脉强度只作用于 j≥1 的支脉格——根格（cells[0]）属主脊，强度由主脊
				# 锥形给出不得覆写（覆写会在每个支脉根部留单格 ~50% 脊线凹口——骨架
				# 场取「最近源」值，邻脊贡献补不上；与「脊线永不被硬切断」自我合同及
				# 提案 :96 冲突，复审修）。支脉首格即降到支脉档 = 主脊/支脉高度层次的
				# 显式台阶（支脉矮于主脊，提案 :77）。
				for j in range(1, branch_cells.size()):
					strengths[branch_cells[j]] = SPINE_TAPER_FLOOR \
						+ (BRANCH_STRENGTH_SCALE - SPINE_TAPER_FLOOR) \
						* (1.0 - float(j) / float(branch_cells.size()))
				var br := WorldDataClass.RidgeBranchData.new()
				br.branch_id = next_branch_id
				next_branch_id += 1
				br.range_id = next_range_id
				br.cells = branch_cells
				branches.append(br)
			var mr := WorldDataClass.MountainRangeData.new()
			mr.range_id = next_range_id
			mr.region_id = region.region_id
			mr.spine_cells = spine
			ranges.append(mr)
			range_skeleton_cells.append(strengths)
			next_range_id += 1
			made_for_region += 1

	# 骨架场：逐山系多种子 BFS（距最近源格的距离 + 源强度随波携带）→
	# ridge = 源强度 × falloff；宽谷 = (width, width+span] 带内（限本区）谷底格集
	var cell_n := map.cell_count()
	var skeleton_height := PackedFloat32Array()
	skeleton_height.resize(cell_n)
	var valley_cell_count := 0
	var carve := PackedFloat32Array()
	carve.resize(cell_n)
	for ri in ranges.size():
		var strengths: Dictionary = range_skeleton_cells[ri]
		var sources: Array[int] = []
		sources.assign(strengths.keys())
		sources.sort()
		var field := _bfs_distance_and_value_from_sources(map, sources,
			func(cid: int) -> float: return float(strengths.get(cid, 0.0)))
		var vl := WorldDataClass.ValleyData.new()
		vl.valley_id = next_valley_id
		next_valley_id += 1
		vl.range_id = ranges[ri].range_id
		var valley_cells: Array[int] = []
		for i in cell_n:
			var d: int = field["dist"][i]
			var src_strength: float = field["value"][i]
			var ridge: float = src_strength * _ridge_falloff(d, ridge_width)
			if ridge > float(skeleton_height[i]):
				skeleton_height[i] = ridge
			if d > ridge_width and d <= ridge_width + valley_span \
					and cell_region[i] == ranges[ri].region_id:
				valley_cells.append(i)
				var kv := 1.0 - float(d - ridge_width) / float(valley_span)
				if kv > float(carve[i]):
					carve[i] = kv
		if not valley_cells.is_empty():
			valley_cells.sort()
			vl.cells = valley_cells
			valleys.append(vl)
			valley_cell_count += valley_cells.size()
	# 区域抬升 + 宽谷下切（骨架高度 = 抬升 + max 脊核 × (1 − 下切)）
	for i in cell_n:
		skeleton_height[i] = MOUNTAIN_BASE_UPLIFT \
			+ float(skeleton_height[i]) * (1.0 - VALLEY_CARVE * float(carve[i]))
	return {"ok": true, "error": "", "ranges": ranges, "branches": branches,
		"valleys": valleys, "skeleton_height": skeleton_height,
		"valley_cell_count": valley_cell_count}


## 主脊行走：A→B 贪心（每步取指向 B 的六边形距离不增的区内未访邻居——距离
## 下降优先，并列取固定 6 向序首个；无路 = 区域不连通，返回空）。有序、不重复、
## 相邻连续——确定性由邻居固定序保证。
static func _walk_spine(map: MapDataClass, cell_region: Array[int], rid: int,
		a: int, b: int) -> Array[int]:
	var cell_b := _cell_of_id(map, b)
	var spine: Array[int] = [a]
	var visited := {a: true}
	var cur := a
	var guard_n := map.cell_count() + 2
	while cur != b and spine.size() < guard_n:
		var next_cell := -1
		var next_dist := Hex.distance(_cell_of_id(map, cur), cell_b)
		for nb in _neighbor_ids(map, cur):
			if visited.has(nb) or cell_region[nb] != rid:
				continue
			var nd := Hex.distance(_cell_of_id(map, nb), cell_b)
			if nd < next_dist or (nd == next_dist and next_cell < 0):
				next_cell = nb
				next_dist = nd
		if next_cell < 0:
			return []  # 不连通——本区放弃该山系
		spine.append(next_cell)
		visited[next_cell] = true
		cur = next_cell
	if cur != b:
		return []  # 侧移兜圈未达 B（guard 截断）——放弃
	if spine.size() < 3:
		return []  # 退化短脊无走向可言
	return spine


## 支脉行走：自根部每步取「距主脊格集最远」的区内未用邻居（并列取固定 6 向序
## 首个），长度预算 max_len；首格即根部（根在主脊上——RidgeBranchData 数据合同
## 的形状面）。无可用邻居即止（短支脉合法）。
static func _walk_branch(map: MapDataClass, cell_region: Array[int], rid: int,
		root: int, spine_set: Dictionary, max_len: int) -> Array[int]:
	var out: Array[int] = [root]
	var used := {root: true}
	var cur := root
	for step in max_len - 1:
		var next_cell := -1
		var best_d := -1
		for nb in _neighbor_ids(map, cur):
			if used.has(nb) or spine_set.has(nb) or cell_region[nb] != rid:
				continue
			var d := _min_distance_to_set(map, nb, spine_set)
			if d > best_d:
				best_d = d
				next_cell = nb
		if next_cell < 0:
			break
		out.append(next_cell)
		used[next_cell] = true
		cur = next_cell
	if out.size() < 2:
		return []
	return out


# ---------------- ④ 孤峰地标（S4）----------------

## 孤峰最小间距（峰间/避让主山系/出生落点避让共用同一距离口径——提案 :78
## 「限制与其他孤峰、主山系、起始落点的距离」的三面同距；ceil(半径 × 倍数)，
## 提案 :131「相对于峰体半径的最小间距」）。纯函数（tests/管线共用——管线
## settlement 阶段的落点避让面取同一值）。
static func peak_min_spacing(radius: int, scale: float) -> int:
	return maxi(radius, int(ceil(float(maxi(radius, 1)) * maxf(scale, 1.0))))


## 圆锥轮廓横向衰减（峰高增益核）：falloff = clamp(1 − d/(r+1), 0, 1)²——顶点 1、
## d ≥ r+1 归零（锥底平滑接地无硬台）；平方 = 岩峰尖顶 + 山脚零坡度接平原。
## 手算 oracle：d=0 → 1；d=r → (1/(r+1))²；d=r+1 → 0。
static func cone_falloff(dist: int, radius: int) -> float:
	var r := maxi(radius, 1)
	var t := clampf(1.0 - float(dist) / float(r + 1), 0.0, 1.0)
	return t * t


## 孤峰布点（S4 纯函数；随机消耗 = isolated_peak 通道的唯一消耗点）。约束四件
## （提案 :78-82/:120/:131，全部由构造保证——S5 校验器与 tests 逐峰复查）：
##   预算   Σ 影响格数（距中心 ≤ 半径的界内格）≤ ⌊有效平原格数 × budget_ratio⌋；
##   间距   峰间 / 峰到一切脊线·支脉格 ≥ peak_min_spacing；
##   避让   候选中心须为陆格且全影响盘落同一 argmax 区域（盘不跨分区边界——
##          分区边界无阶跃的 S3 验收面不被锥体破坏）；
##   归属   主山系内部突出峰不自动入本表（候选池结构性排除骨架近邻——骨架峰
##          只属 MountainRangeData 对象，提案 :79 对象归属判定）。
## 有效平原 = 群山权重 ≤ EFFECTIVE_PLAIN_WEIGHT_MAX 的陆格（预算分母兼候选池）。
## 小图预算不足 → 零峰（合法态，提案 :82）。返回 {"ok", "error",
##   "peaks"（cell_id 升序、peak_id 顺排 0..n-1——与 rng 收取序解耦的稳定编号）,
##   "stats": {effective_plain_cells, budget_cells, influence_cells}}。
static func place_isolated_peaks(map: MapDataClass, mixed_heights: PackedFloat32Array,
		mix_min: float, mix_max: float, weight_mountains: PackedFloat32Array,
		cell_region: Array[int], skeleton: Dictionary,
		rng_peak: RandomNumberGenerator, cfg: Dictionary) -> Dictionary:
	var cell_n := map.cell_count()
	var radius := maxi(1, int(cfg["peak_influence_radius"]))
	var spacing := peak_min_spacing(radius, float(cfg["peak_spacing_radius_scale"]))
	var gain := float(clampi(int(cfg["peak_height"]), 1, 1000)) / 1000.0
	var h_range := mix_max - mix_min
	# 有效平原（预算分母兼候选池：平原主导档 ∧ 陆格——水格上的孤峰是伪地标）
	var plain_land: Array[int] = []
	for i in cell_n:
		if float(weight_mountains[i]) <= EFFECTIVE_PLAIN_WEIGHT_MAX \
				and float(mixed_heights[i]) >= mix_min + float(cfg["sea_level"]) * h_range:
			plain_land.append(i)
	var budget_cells := int(floor(float(plain_land.size()) * maxf(float(cfg["peak_area_budget_ratio"]), 0.0)))
	if plain_land.is_empty() or budget_cells <= 0 or gain <= 0.0:
		return {"ok": true, "error": "", "peaks": [],
			"stats": {"effective_plain_cells": plain_land.size(),
				"budget_cells": budget_cells, "influence_cells": 0}}
	# 骨架格距离场（峰→主山系间距的查表面：多源 BFS——无障碍六边形图上 = 环距）
	var skeleton_sources: Array[int] = []
	for mr in skeleton["ranges"]:
		for cid in (mr as WorldDataClass.MountainRangeData).spine_cells:
			skeleton_sources.append(cid)
	for br in skeleton["branches"]:
		for cid in (br as WorldDataClass.RidgeBranchData).cells:
			skeleton_sources.append(cid)
	var d_skeleton := _bfs_distance_from_set(map, skeleton_sources)
	# 分区边界距离场（逐区域：源 = 异区格——全影响盘同区的查表面）
	var region_ids := {}
	for rid in cell_region:
		region_ids[rid] = true
	var d_foreign := {}
	for rid in region_ids:
		var foreign: Array[int] = []
		for i in cell_n:
			if cell_region[i] != int(rid):
				foreign.append(i)
		d_foreign[int(rid)] = _bfs_distance_from_set(map, foreign)
	# 候选池：有效平原 ∧ 距骨架 ≥ 间距 ∧ 全影响盘（含锥尾 r+1）同 argmax 区域 ∧
	# **峰体完整落图内**（影响盘全界内——圆锥不被地图边界截断：半座孤峰是残缺
	# 地标，且影响面积 = 完整盘 3r(r+1)+1 进预算计量，不含裁剪盘）∧ **间距盘落
	# 有效平原内**（距中心 ≤ 间距的格全为平原陆格——「数量由有效平原面积/最小
	# 间距/构图位置决定」的间距面：峰的让位球须由平原自身容纳；小图/窄平原装
	# 不下间距盘 → 自然零峰，提案 :82「小地图可以没有孤峰」的结构化表达）
	var plain_set := {}
	for cid in plain_land:
		plain_set[cid] = true
	var disc_of_radius := _disc_offsets(radius)
	var disc_of_spacing := _disc_offsets(spacing)
	var candidates: Array[int] = []
	for cid in plain_land:
		if int(d_skeleton[cid]) < spacing:
			continue
		if int(d_foreign[cell_region[cid]][cid]) < radius + 2:
			continue
		var cell := _cell_of_id(map, cid)
		var fits := true
		for delta in disc_of_radius:
			if not map.has_cell(cell + delta):
				fits = false
				break
		if not fits:
			continue
		for delta in disc_of_spacing:
			var other := cell + delta
			if not map.has_cell(other) or not plain_set.has(map.index_of(other)):
				fits = false
				break
		if not fits:
			continue
		candidates.append(cid)
	var shuffled := _shuffle_ints(rng_peak, candidates)
	var picked: Array[int] = []
	var influence_total := 0
	for cid in shuffled:
		if influence_total >= budget_cells:
			break  # 预算尽（剩余不足一格盘也停——下一峰至少 1 格）
		var cell := _cell_of_id(map, cid)
		var spaced := true
		for p in picked:
			if Hex.distance(cell, _cell_of_id(map, p)) < spacing:
				spaced = false
				break
		if not spaced:
			continue
		var footprint := 0
		for other in map.cells():
			if Hex.distance(cell, other) <= radius:
				footprint += 1
		if influence_total + footprint > budget_cells:
			continue  # 本峰放不下（不截断搜索——后面可能有更贴边的窄盘）
		picked.append(cid)
		influence_total += footprint
	picked.sort()
	var peaks: Array[WorldDataClass.IsolatedPeakData] = []
	for pid in picked.size():
		var pk := WorldDataClass.IsolatedPeakData.new()
		pk.peak_id = pid
		pk.cell_id = picked[pid]
		pk.influence_radius = radius
		pk.peak_height = int(round(gain * 1000.0))
		pk.shape = WorldDataClass.IsolatedPeakData.Shape.CONE
		peaks.append(pk)
	return {"ok": true, "error": "", "peaks": peaks,
		"stats": {"effective_plain_cells": plain_land.size(),
			"budget_cells": budget_cells, "influence_cells": influence_total}}


# ---------------- 纯函数小件（tests 独立锚的面）----------------

## 反距离权重核：w = 1/(1+(d/T)²)，逐项归一（Σ=1；T ≥1）。手算 oracle 可锚
##（d=[0,1] T=1：raw [1, 1/2] → 归一 [2/3, 1/3]）。
static func inverse_distance_weights(dists: Array[int], transition_radius: int) -> Array[float]:
	var t := maxi(1, transition_radius)
	var raw: Array[float] = []
	var total := 0.0
	for d in dists:
		var w := 1.0 / (1.0 + pow(float(d) / float(t), 2.0))
		raw.append(w)
		total += w
	var out: Array[float] = []
	for w in raw:
		out.append(w / total if total > 0.0 else 1.0 / float(maxi(dists.size(), 1)))
	return out


## 六边形盘偏移集（axial delta，环距 ≤ radius 全体；含 (0,0)；size = 3r(r+1)+1
## ——影响盘/间距盘枚举的共用件，r=1 → 中心+六邻 7 项）。顺序固定（q 升序、
## r 次之——确定性）。
static func _disc_offsets(radius: int) -> Array[Vector2i]:
	var r := maxi(0, radius)
	var out: Array[Vector2i] = []
	for dq in range(-r, r + 1):
		var lo := maxi(-r, -r - dq)
		var hi := mini(r, r - dq)
		for dr in range(lo, hi + 1):
			out.append(Vector2i(dq, dr))
	return out


## 脊线横向衰减：falloff = clamp(1 − d/width, 0, 1)²（d=0 → 1、d≥width → 0——
## 山肩平滑归零，无硬边界）。
static func _ridge_falloff(dist: int, width: int) -> float:
	var w := maxi(1, width)
	var t := clampf(1.0 - float(dist) / float(w), 0.0, 1.0)
	return t * t


# ---------------- 内部 ----------------

## 细节场（第三连续场）：高频小起伏，独立 seed 偏移；本图值域归一（分母 0 → 0.5）。
static func _detail_field(map: MapDataClass, seed_value: int, base_frequency: float) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value + DETAIL_FIELD_SEED_OFFSET
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = maxf(0.0001, base_frequency * DETAIL_FREQUENCY_SCALE)
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = DETAIL_OCTAVES
	var cells := map.cells()
	var raw := PackedFloat32Array()
	raw.resize(cells.size())
	var d_min := INF
	var d_max := -INF
	for i in cells.size():
		var w := Hex.axial_to_world(cells[i], 1.0)
		var v := float(noise.get_noise_2d(w.x, w.z))
		raw[i] = v
		d_min = minf(d_min, v)
		d_max = maxf(d_max, v)
	var out := PackedFloat32Array()
	out.resize(cells.size())
	var range_d := d_max - d_min
	for i in cells.size():
		out[i] = (float(raw[i]) - d_min) / range_d if range_d > 0.0 else 0.5
	return out


## 邻差统计：全图相邻格连续高度差的最大值 + 「异区相邻对」子集最大值
##（过渡带无阶跃的留证；机器断言面在 tests 对量化图独立复核）。
static func _neighbor_step_stats(map: MapDataClass, heights: PackedFloat32Array,
		cell_region: Array[int]) -> Dictionary:
	var max_delta := 0.0
	var boundary_max_delta := 0.0
	var high_cells := 0
	var low_cells := 0
	var cells := map.cells()
	for i in cells.size():
		if float(heights[i]) >= 0.7:
			high_cells += 1
		if float(heights[i]) <= 0.3:
			low_cells += 1
		for nb in map.neighbors_existing(cells[i]):
			var j := map.index_of(nb)
			if j <= i:
				continue  # 无向边只查一次
			var delta := absf(float(heights[i]) - float(heights[j]))
			max_delta = maxf(max_delta, delta)
			if cell_region[i] != cell_region[j]:
				boundary_max_delta = maxf(boundary_max_delta, delta)
	return {"max_delta": max_delta, "boundary_max_delta": boundary_max_delta,
		"high_cells": high_cells, "low_cells": low_cells}


## 格 id 的界内邻居 id 列表（固定 6 向序——确定性）。
static func _neighbor_ids(map: MapDataClass, cid: int) -> Array[int]:
	var cell := _cell_of_id(map, cid)
	var out: Array[int] = []
	for d in 6:
		var nb := Hex.neighbor(cell, d)
		if map.has_cell(nb):
			out.append(map.index_of(nb))
	return out


## 多源 BFS 距离场（源格集 → 全图最短六边形距离；非可达格 = 大值）。
static func _bfs_distance_from_set(map: MapDataClass, sources: Array[int]) -> PackedInt32Array:
	var cell_n := map.cell_count()
	var dist := PackedInt32Array()
	dist.resize(cell_n)
	for i in cell_n:
		dist[i] = 1 << 26  # 哨兵大值（不可达）
	var queue: Array = []
	for s in sources:
		if s >= 0 and s < cell_n and dist[s] != 0:
			dist[s] = 0
			queue.append(s)
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for nb in _neighbor_ids(map, cur):
			if dist[nb] > dist[cur] + 1:
				dist[nb] = dist[cur] + 1
				queue.append(nb)
	return dist


## 多源 BFS 距离 + 源值场（每格携带最近源的 value——山系强度随波传播；
## 并列距离取先到者：源升序 + 邻居固定序 ⇒ 确定性）。
static func _bfs_distance_and_value_from_sources(map: MapDataClass, sources: Array[int],
		value_of: Callable) -> Dictionary:
	var cell_n := map.cell_count()
	var dist := PackedInt32Array()
	dist.resize(cell_n)
	var value := PackedFloat32Array()
	value.resize(cell_n)
	for i in cell_n:
		dist[i] = 1 << 26
	var queue: Array = []
	for s in sources:
		if s >= 0 and s < cell_n and dist[s] != 0:
			dist[s] = 0
			value[s] = float(value_of.call(s))
			queue.append(s)
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for nb in _neighbor_ids(map, cur):
			if dist[nb] > dist[cur] + 1:
				dist[nb] = dist[cur] + 1
				value[nb] = value[cur]
				queue.append(nb)
	return {"dist": dist, "value": value}


## 格到格集的最小六边形距离（支脉走向用；集空 → 1<<26）。
static func _min_distance_to_set(map: MapDataClass, cid: int, set: Dictionary) -> int:
	var best := 1 << 26
	var cell := _cell_of_id(map, cid)
	for other in set:
		var d := Hex.distance(cell, _cell_of_id(map, int(other)))
		if d < best:
			best = d
	return best


## cell id → axial 格（行主序反解——world_data._cell_of_id 同式）。
static func _cell_of_id(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))


## rng 驱动 Fisher-Yates（Array.shuffle 用全局 RNG——通道纪律禁用；返回新数组）。
static func _shuffle_ints(rng: RandomNumberGenerator, src: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(src)
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out
