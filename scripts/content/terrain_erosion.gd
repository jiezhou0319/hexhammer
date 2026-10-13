## terrain_erosion.gd — 选择性侵蚀与复查回退生成器（T6 S4；执行方案
##   docs/M1a-terrain-T6-stylized-execution-plan.md §6 + 提案
##   docs/evidence/风格化地图生成方案_群山平原与派系适配_修订版.md
##   §选择性侵蚀 :100-109）
## 职责：regions 路线 erosion 阶段的全部算法面——作用于**连续高度**（composition
##   产物、quantize 投影前，可改变量化结果；提案 :102 主线序「连续高度 → 选择性
##   侵蚀 → 六边形投影」的中间步）。只承担外观细化、不提供权威河流（提案 :102
##   ——水系仍走 hydrology 阶段河口反向生长，消费侵蚀后的最终事实）。
## 算法三件（每件纯函数、tests 独立锚）：
##   ① 区域强度场 strengths_for——按区域类型分强度（提案 :104-107）：群山坡面
##     （mw ≥700‰）强 / 宽谷谷底格取 min(档强度, 谷档)（限制割裂、维护可用
##     面积）/ 平原（mw ≤300‰）默认关 / 过渡带（300‰<mw<700‰）单独档 /
##     海岸带（贴海陆格）取 min(档强度, 海岸档)（保护轮廓）；水格与全图极值格
##     恒 0（极值格不侵蚀 = 归一化分母不变的构造前提，见 ③ 不变量）；
##   ② 刻蚀场 carve_field——d = −强度 × 沟壑通道 × 坡度（只刻不堆：侵蚀单调
##     下切；沟壑通道 = 独立高频噪声场 (gully−0.5)⁺·2 的上半带——沟壑成枝网
##     而非全面刷低；坡度 = 连续场最大邻差——侵蚀集中在坡面，平地自动近零）；
##   ③ 复查回退 resolve_rollback（提案 :109「侵蚀后重新检查起伏、坡度和连通性，
##     破坏区域约束时按确定性规则减弱局部侵蚀或回退局部结果，不用换整张地图
##     seed 掩盖问题」——确定性规则三面）：
##     起伏  平原格下限 = 侵蚀前平原最低 − 平原起伏预算（侵蚀后平原区起伏较
##           侵蚀前最多增长预算值）；
##     水陆  陆格下限 = 侵蚀前海面阈（侵蚀不得制造新水格——水陆分区与连通
##           分量逐格不变的构造保证：刻蚀只降高度、极值格不动 ⇒ 归一化分母
##           不变 ⇒ 陆格不会跌破海面；「连通性复查」的机器等价面）；
##     坡度  侵蚀差分邻差预算：相邻格侵蚀量之差 > max_step = 侵蚀自身制造的
##           台阶（强度档边界/沟壑壁），先确定性减半（≤3 轮）仍违则整格回退
##           （迭代至零违例——Jacobi 并行口径，与遍历序无关）。
## 随机通道纪律：沟壑场 seed = erosion 通道 seed + EROSION_FIELD_SEED_OFFSET
##   （通道 seed 经 WorldPipeline.channel_seed 派生——override erosion 通道即换
##   沟壑图样，是本阶段的通道消耗面；rng 对象本身不消耗，geography 阶段「通道
##   传入仅为签名统一」同款先例）。偏移 3011 与植被场 1013、细节场 2027、全部
##   通道偏移 101..911 互异错开（两层随机不串流）。
## 全部数值参数 = **未验证起调值**（模板 erosion 子组传入；T6 方案 §10）。
## 纯逻辑类：RefCounted、零场景节点、只读 MapData/WorldData、不改入参
##   （返回新 heights 数组；ADR-2）。
class_name TerrainErosion
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")

# ---- 沟壑场固定配置（写死保证复现——TerrainComposition.DETAIL_* 同纪律）----

## 沟壑场 seed 偏移（与植被 1013 / 细节 2027 / 通道 101..911 互异）
const EROSION_FIELD_SEED_OFFSET := 3011
## 沟壑场频率 = erosion 通道 seed 派生后 × 基础场频率 × 此倍率（沟壑 = 最细档
## ——高于细节场 4.0，外观刻蚀的横向尺度）
const EROSION_FREQUENCY_SCALE := 8.0
## 沟壑场 FBM 倍频数（枝网感 2 档足够——沟壑不承担构图）
const EROSION_OCTAVES := 2

# ---- 区域强度档阈（千分整数——与 region/skeleton 视图 700/300 两档同阈）----

## 群山坡面档：mw ≥ 此值（‰）
const WEIGHT_MOUNTAIN_SLOPE_MIN := 700
## 平原档：mw ≤ 此值（‰）；之间 = 过渡带档
const WEIGHT_PLAIN_MAX := 300
## 海岸带宽度（归一化高度超出海面阈的部分——贴海陆格判档）
const COAST_BAND := 0.05

# ---- 复查回退固定参数（写死保证复现；预算值随模板）----

## 减弱轮数上限（每轮对违例格侵蚀量减半；超出仍未过 → 整格回退）
const WEAKEN_ROUNDS := 3
## 回退轮数上限（整格清零迭代至零违例——构造上 ≤2~3 轮收敛，上限是护栏）
const ROLLBACK_MAX_ROUNDS := 8
## 侵蚀差分预算比较容差（浮点边界防抖）
const STEP_EPS := 1e-9

# ---------------- 入口 ----------------

## erosion 阶段唯一入口。入参：
##   map/world   载体与世界事实（cell_mountain_weights/valleys——强度档数据源）
##   heights     composition 混合场（含孤峰第四项）
##   h_min/h_max 该场极值（陆格判档 = 归一化 n ≥ sea_level）
##   cfg         模板 erosion 子组 + {"sea_level", "gully_seed", "base_frequency"}
## 返回 {"ok", "error", "heights"（新 PackedFloat32Array——不改入参）,
##   "stats"：{carved_cells / weakened_cells / rollback_cells / post_violations
##     （复查留痕：确定性减弱/回退的计数面，诊断通道不进世界事实）/ max_delta
##     （侵蚀后连续场最大邻差）/ land_cells}}
static func erode(map: MapDataClass, heights: PackedFloat32Array,
		h_min: float, h_max: float, world: WorldDataClass, cfg: Dictionary) -> Dictionary:
	var cell_n := map.cell_count()
	if heights.size() != cell_n:
		return {"ok": false, "error": "连续高度场长度 %d ≠ 格数 %d（composition 产物损坏）" \
			% [heights.size(), cell_n]}
	var strengths := strengths_for(map, heights, h_min, h_max, world, {
		"sea_level": float(cfg["sea_level"]),
		"mountain_slope": float(cfg["erosion_mountain_slope"]),
		"valley": float(cfg["erosion_valley"]),
		"plain": float(cfg["erosion_plain"]),
		"transition": float(cfg["erosion_transition"]),
		"coast": float(cfg["erosion_coast"]),
	})
	var gully := _gully_field(map, int(cfg["gully_seed"]), float(cfg["base_frequency"]))
	var delta := carve_field(map, heights, strengths, gully)
	var floors := carve_floors(map, heights, h_min, h_max, world, {
		"sea_level": float(cfg["sea_level"]),
		"plain_relief_budget": float(cfg["erosion_plain_relief_budget"]),
	})
	var resolved := resolve_rollback(map, delta, floors, heights, float(cfg["erosion_max_step"]))
	var out := PackedFloat32Array()
	out.resize(cell_n)
	# 海面阈守护（float32 落盘界）：陆格终值抬到 sea_floor 之上一个 float32 ulp
	# 档——下限钳在 float64 算出的恰海面值经 PackedFloat32Array 存取可四舍五入
	# 到阈下一个 ulp，量化 n ≥ sea_level 判水（水陆分区不变量的浮点面封口）；
	# 提抬量 ~1e-7 连续单位，远低于一切量化档分辨率
	var sea := float(cfg["sea_level"])
	var sea_floor := h_min + sea * (h_max - h_min)
	var sea_guard := sea_floor + absf(sea_floor) * 2e-7 + 1e-9
	var carved := 0
	for i in cell_n:
		var v := float(heights[i]) + float(resolved["delta"][i])
		if float(heights[i]) >= sea_floor and v < sea_guard:
			v = sea_guard
		out[i] = v
		if float(resolved["delta"][i]) < 0.0:
			carved += 1
	var stats: Dictionary = resolved["stats"]
	stats["carved_cells"] = carved
	stats["land_cells"] = _land_cell_count(heights, h_min, h_max, sea)
	stats["max_delta"] = _post_max_neighbor_delta(map, out)
	return {"ok": true, "error": "", "heights": out, "stats": stats}


# ---------------- ① 区域强度场 ----------------

## 区域强度场（提案 :104-107 的分档落码）：水格 0；陆格按 mw 档（群山/过渡/
## 平原），谷底格与贴海格取 min(档, 谷/海岸上限)——「限制」「保护」语义 = 只降
## 不升；全图极值格（h == h_min / h == h_max）恒 0——归一化分母不变的前提
## （极值被侵蚀 ⇒ 全图归一化漂移 ⇒ 水陆分区失守，见 resolve_rollback 不变量）。
## 纯函数（tests 手算锚：档位/上限/极值排除三面）。
static func strengths_for(map: MapDataClass, heights: PackedFloat32Array,
		h_min: float, h_max: float, world: WorldDataClass, cfg: Dictionary) -> PackedFloat32Array:
	var cell_n := map.cell_count()
	var h_range := h_max - h_min
	var sea := float(cfg["sea_level"])
	var valley_cells := {}
	for vl in world.valleys:
		for cid in vl.cells:
			valley_cells[cid] = true
	var weights := world.cell_mountain_weights
	var out := PackedFloat32Array()
	out.resize(cell_n)
	for i in cell_n:
		var h := float(heights[i])
		if h <= h_min or h >= h_max:
			continue  # 极值格不侵蚀（h_range=0 全图常数 → 全部极值 → 零侵蚀）
		if h < h_min + sea * h_range:
			continue  # 水格不侵蚀（陆地外观刻蚀不碰水下）
		var strength := float(cfg["plain"])
		var w := int(weights[i]) if i < weights.size() else 0
		if w >= WEIGHT_MOUNTAIN_SLOPE_MIN:
			strength = float(cfg["mountain_slope"])
		elif w > WEIGHT_PLAIN_MAX:
			strength = float(cfg["transition"])
		var n := (h - h_min) / h_range if h_range > 0.0 else 0.5
		if n <= sea + COAST_BAND:
			strength = minf(strength, float(cfg["coast"]))
		if valley_cells.has(i):
			strength = minf(strength, float(cfg["valley"]))
		out[i] = strength
	return out


# ---------------- ② 刻蚀场 ----------------

## 沟壑通道值（gully ∈ [0,1] → 通道 ∈ [0,1]）：下半带 0、上半带线性拉伸——
## 沟壑只占约半幅（枝网感）；纯函数（tests 手算锚：0.5 断档）。
static func gully_channel(gully_value: float) -> float:
	return clampf((gully_value - 0.5) * 2.0, 0.0, 1.0)


## 刻蚀场：d[i] = −强度 × 沟壑通道 × 坡度（≤0 恒成立——只刻不堆）。坡度 =
## 连续场最大界内邻差（侵蚀集中在坡面的机器表达）。纯函数（tests 手算锚）。
static func carve_field(map: MapDataClass, heights: PackedFloat32Array,
		strengths: PackedFloat32Array, gully: PackedFloat32Array) -> PackedFloat32Array:
	var cell_n := map.cell_count()
	var slope := PackedFloat32Array()
	slope.resize(cell_n)
	var cells := map.cells()
	for i in cell_n:
		var s := 0.0
		for nb in map.neighbors_existing(cells[i]):
			s = maxf(s, absf(float(heights[i]) - float(heights[map.index_of(nb)])))
		slope[i] = s
	var out := PackedFloat32Array()
	out.resize(cell_n)
	for i in cell_n:
		out[i] = -float(strengths[i]) * gully_channel(float(gully[i])) * float(slope[i])
	return out


# ---------------- ③ 复查回退 ----------------

## 刻蚀下限场（复查判据的下限面）：陆格 ≥ 侵蚀前海面阈（不造新水——水陆分区
## 与连通分量逐格不变的构造前提）；平原陆格再 ≥ 侵蚀前平原最低 − 起伏预算
## （平原区起伏较侵蚀前最多增长预算）。纯函数（tests 手算锚）。
static func carve_floors(map: MapDataClass, heights: PackedFloat32Array,
		h_min: float, h_max: float, world: WorldDataClass, cfg: Dictionary) -> PackedFloat32Array:
	var cell_n := map.cell_count()
	var h_range := h_max - h_min
	var sea_floor := h_min + float(cfg["sea_level"]) * h_range
	var weights := world.cell_mountain_weights
	var plain_min := INF
	for i in cell_n:
		if float(heights[i]) >= sea_floor and i < weights.size() \
				and int(weights[i]) <= WEIGHT_PLAIN_MAX:
			plain_min = minf(plain_min, float(heights[i]))
	var out := PackedFloat32Array()
	out.resize(cell_n)
	for i in cell_n:
		var floor_v := sea_floor
		if float(heights[i]) >= sea_floor and plain_min < INF and i < weights.size() \
				and int(weights[i]) <= WEIGHT_PLAIN_MAX:
			floor_v = maxf(floor_v, plain_min - float(cfg["plain_relief_budget"]))
		out[i] = floor_v
	return out


## 复查回退（提案 :109 的确定性规则）：先把下限钳进 delta（floor 对负向刻蚀
## 单调收紧——减半/清零只抬高度，钳后不会再度跌破）；再对侵蚀差分违例
## （相邻格 |Δd| > max_step）做 Jacobi 并行减弱（每轮减半，≤WEAKEN_ROUNDS）
## 与回退（整格清零，迭代至零违例）。返回 {"delta", "stats"：{weakened_cells,
## rollback_cells, post_violations}}——减弱/回退的确定性留痕（诊断通道）。
## 纯函数（tests 手算锚：减半次数/清零/收敛）。
static func resolve_rollback(map: MapDataClass, delta: PackedFloat32Array,
		floors: PackedFloat32Array, heights: PackedFloat32Array,
		max_step: float) -> Dictionary:
	var cell_n := map.cell_count()
	var d := PackedFloat32Array()
	d.resize(cell_n)
	for i in cell_n:
		var v := float(delta[i])
		# 下限钳：floor 以 delta 表达时只在 floor 低于当前高度时绑定（负向限刻）；
		# min(0,·) 防抬升——水格（floor 在其上方）不得被「钳」出海面成为陆格
		# （侵蚀只刻不堆的红线，也是水陆分区不变量的前提）
		var floor_d := minf(0.0, float(floors[i]) - float(heights[i]))
		if v < floor_d:
			v = floor_d
		d[i] = v
	var weakened := {}
	var rolled := {}
	for round_n in WEAKEN_ROUNDS:
		var violators := _step_violators(map, d, max_step)
		if violators.is_empty():
			break
		for i in violators:
			d[i] *= 0.5
			weakened[i] = true
	var rollback_rounds := 0
	while rollback_rounds < ROLLBACK_MAX_ROUNDS:
		var violators := _step_violators(map, d, max_step)
		if violators.is_empty():
			break
		for i in violators:
			d[i] = 0.0
			rolled[i] = true
		rollback_rounds += 1
	return {"delta": d, "stats": {
		"weakened_cells": weakened.size(),
		"rollback_cells": rolled.size(),
		"post_violations": _step_violators(map, d, max_step).size(),
	}}


# ---------------- 内部 ----------------

## 侵蚀差分违例格集（Jacobi 口径：对当前 d 全图并行判定，与遍历序无关——
## 确定性）。违例 = 存在界内邻居使 |d[i] − d[nb]| > max_step + 容差。
static func _step_violators(map: MapDataClass, d: PackedFloat32Array,
		max_step: float) -> Array[int]:
	var out: Array[int] = []
	var cells := map.cells()
	for i in cells.size():
		var bad := false
		for nb in map.neighbors_existing(cells[i]):
			if absf(float(d[i]) - float(d[map.index_of(nb)])) > max_step + STEP_EPS:
				bad = true
				break
		if bad:
			out.append(i)
	return out


## 沟壑场（第四连续场）：高频枝网噪声，seed = erosion 通道 seed + 固定偏移；
## 本图值域归一（分母 0 → 0.5）。
static func _gully_field(map: MapDataClass, gully_seed: int, base_frequency: float) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = gully_seed + EROSION_FIELD_SEED_OFFSET
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = maxf(0.0001, base_frequency * EROSION_FREQUENCY_SCALE)
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = EROSION_OCTAVES
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


## 陆格计数（n ≥ sea_level——侵蚀前后水陆分区不变锚的计量面）。
static func _land_cell_count(heights: PackedFloat32Array, h_min: float,
		h_max: float, sea_level: float) -> int:
	var h_range := h_max - h_min
	var count := 0
	for v in heights:
		if h_range <= 0.0 or float(v) >= h_min + sea_level * h_range:
			count += 1
	return count


## 侵蚀后连续场最大邻差（坡度复查的留证面——机器断言在 tests）。
static func _post_max_neighbor_delta(map: MapDataClass, heights: PackedFloat32Array) -> float:
	var max_delta := 0.0
	var cells := map.cells()
	for i in cells.size():
		for nb in map.neighbors_existing(cells[i]):
			var j := map.index_of(nb)
			if j <= i:
				continue
			max_delta = maxf(max_delta, absf(float(heights[i]) - float(heights[j])))
	return max_delta
