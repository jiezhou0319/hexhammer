## map_generator.gd — 随机地图生成器（M1a-T9；docs/04-tasks-m1.md M1a-T9 细化
##   「低频噪声（FastNoiseLite）→ 量化整数高程 → 地形分类 → 连通性检查
##   （不做每格独立随机）」+ M1a 实现调研「相机、高亮和随机地图」）
## 管线（四步，全确定性——同 seed+同参数+同引擎构建 → 逐格同图）：
##   1. 低频噪声采样：FastNoiseLite（高度场 = params.noise_type/frequency/octaves；
##      湿度场 = simplex 第二通道，seed 偏移 MOISTURE_SEED_OFFSET）；
##      采样点 = 格心世界 XZ（HexMath.axial_to_world，空间连贯随六边形几何走）。
##   2. 量化整数高程：先对全图采样取 min/max 归一化到 [0,1]，再按
##      sea_level / elevation_levels 量化——**归一化而非假定 ±1 界内**：
##      部分 cellular 噪声输出可超 ±1（04 M1a-T9 细化明示），任何噪声类型一律
##      以本图实际值域归一，不依赖文档承诺的输出范围。
##   3. 地形分类（内容层常量表，翻口味 = 改本表 + GENERATOR_VERSION+1）：
##      水（n < sea_level）→ 3 水/高程 0/不可通行；
##      陆地层 = 1..elevation_levels：顶档 → 2 岩；第 1 档 → 4 沙（干）/1 泥（湿）；
##      中档 → 0 草，湿度高 → 5 林。
##   4. 连通性检查：MapConnectivity.check（断路/孤岛进 meta.connectivity）。
## 复现口径：meta 落 seed/参数/生成器版本/引擎版本 + 格子表摘要（digest）；
##   **同 seed 复现限定在固定生成器版本与引擎配置下**（FastNoiseLite 实现随引擎
##   版本可能变化，不承诺跨版本永不漂移——meta.reproducibility_note 落字）。
## 地形→通行性映射在此显式落表（内容层职责，MapData 不做自动推导）：仅水不可通行。
## 纯逻辑类：RefCounted、零场景节点（ADR-2；删 scripts/ui/** 不影响本文件与 tests/）。
class_name MapGenerator
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapGenParamsClass := preload("res://scripts/content/map_gen_params.gd")
const MapConnectivityClass := preload("res://scripts/content/map_connectivity.gd")

## 生成器版本：管线步骤、分类表、参数语义任一变更时 +1（meta 落盘，复现口径的锚）。
const GENERATOR_VERSION := 1

## 湿度场 seed 偏移（与高度场同 seed 时错开通道；写死常量保证复现）
const MOISTURE_SEED_OFFSET := 1013

## 湿度场固定配置（不参数化：植被动动脉，口味项收进生成器版本管理）
const MOISTURE_NOISE_TYPE := FastNoiseLite.TYPE_SIMPLEX
const MOISTURE_OCTAVES := 2

## 地形 id（与 TerrainMaterialLibrary.DEFAULT_PALETTE 槽位同源；语义由内容层定义）
const TERRAIN_GRASS := 0
const TERRAIN_MUD := 1
const TERRAIN_ROCK := 2
const TERRAIN_WATER := 3
const TERRAIN_SAND := 4
const TERRAIN_FOREST := 5

## 地形分类湿度阈值（归一化湿度；分类表变更 = GENERATOR_VERSION+1）
const MOISTURE_FOREST_THRESHOLD := 0.60  # 中档陆地：湿度高于此 → 林替草
const MOISTURE_MUD_THRESHOLD := 0.70     # 第 1 档陆地：湿度高于此 → 泥替沙

## 生成一张随机图。params = MapGenParams。
## 返回 { "ok": bool, "error": String（ok 时为 ""）,
##        "map": MapData（ok 时非空）, "meta": Dictionary（ok 时非空）,
##        "connectivity": Dictionary（MapConnectivity.check 报告，ok 时非空）}。
## 参数非法 → ok=false + error 原因（无隐式兜底；不产出半张图）。
static func generate(params: MapGenParamsClass) -> Dictionary:
	var err := params.validate()
	if err != "":
		return {"ok": false, "error": "参数非法：%s" % err, "map": null, "meta": {}, "connectivity": {}}

	var height_noise := FastNoiseLite.new()
	height_noise.seed = params.seed
	height_noise.noise_type = params.noise_type
	height_noise.frequency = params.frequency
	height_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	height_noise.fractal_octaves = params.fractal_octaves

	var moisture_noise := FastNoiseLite.new()
	moisture_noise.seed = params.seed + MOISTURE_SEED_OFFSET
	moisture_noise.noise_type = MOISTURE_NOISE_TYPE
	moisture_noise.frequency = params.moisture_frequency
	moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	moisture_noise.fractal_octaves = MOISTURE_OCTAVES

	var map := MapDataClass.new(params.width, params.height)
	var cells := map.cells()

	# 步骤 1+2 前半：全图采样两通道原始值（顺序 = MapData 固定遍历序 → 确定性）
	var heights := PackedFloat32Array()
	var moistures := PackedFloat32Array()
	heights.resize(cells.size())
	moistures.resize(cells.size())
	var h_min := INF
	var h_max := -INF
	var m_min := INF
	var m_max := -INF
	for i in cells.size():
		var w := Hex.axial_to_world(cells[i], 1.0)
		var h := float(height_noise.get_noise_2d(w.x, w.z))
		var mv := float(moisture_noise.get_noise_2d(w.x, w.z))
		heights[i] = h
		moistures[i] = mv
		h_min = minf(h_min, h)
		h_max = maxf(h_max, h)
		m_min = minf(m_min, mv)
		m_max = maxf(m_max, mv)
	# 归一化分母为零（噪声恒定输出，理论罕见）：全部取中值 0.5——行为确定、
	# 图退化为全水/全陆由 sea_level 决定，不构成隐性随机
	var h_range := h_max - h_min
	var m_range := m_max - m_min

	# 步骤 2 后半 + 步骤 3：归一化 → 量化整数高程 → 地形分类 → 写入
	var write_failures := 0
	for i in cells.size():
		var cell := cells[i]
		var n := (float(heights[i]) - h_min) / h_range if h_range > 0.0 else 0.5
		var level := 0
		var terrain := TERRAIN_WATER
		var passable := false
		if n >= params.sea_level:
			var t := (n - params.sea_level) / (1.0 - params.sea_level)
			level = clampi(int(t * float(params.elevation_levels)), 0, params.elevation_levels - 1) + 1
			var m := (float(moistures[i]) - m_min) / m_range if m_range > 0.0 else 0.5
			terrain = _classify_terrain(level, params.elevation_levels, m)
			passable = true
		if not map.set_elevation(cell, level):
			write_failures += 1
		if not map.set_terrain(cell, terrain):
			write_failures += 1
		if not map.set_passable(cell, passable):
			write_failures += 1
	if write_failures > 0:
		return {"ok": false, "error": "写入失败 %d 次（界内格写入不应失败，生成器 bug）"
			% write_failures, "map": null, "meta": {}, "connectivity": {}}

	# 步骤 4：连通性检查（断路/孤岛不改图，只进报告与 meta）
	var connectivity := MapConnectivityClass.check(map)

	var meta := {
		"kind": "random",
		"generator_version": GENERATOR_VERSION,
		"params": params.to_dict(),
		"digest": map.digest(),
		"engine_version": String(Engine.get_version_info()["string"]),
		"reproducibility_note": "same seed+params reproduces only with generator_version %d "
			% GENERATOR_VERSION + "on the same engine build (FastNoiseLite output may change "
			+ "across Godot versions)",
		"connectivity": MapConnectivityClass.summary_of(connectivity),
		"terrain_counts": _value_counts(map, "terrain"),
		"elevation_counts": _value_counts(map, "elevation"),
	}
	return {"ok": true, "error": "", "map": map, "meta": meta, "connectivity": connectivity}


## 地形分类表（内容层口味；变更 = GENERATOR_VERSION+1）：
## 顶档 → 岩；第 1 档 → 沙/泥（湿度）；中档 → 草/林（湿度）。
static func _classify_terrain(level: int, levels: int, moisture: float) -> int:
	if level >= levels:
		return TERRAIN_ROCK
	if level == 1:
		return TERRAIN_MUD if moisture > MOISTURE_MUD_THRESHOLD else TERRAIN_SAND
	return TERRAIN_FOREST if moisture > MOISTURE_FOREST_THRESHOLD else TERRAIN_GRASS


static func _value_counts(map: MapDataClass, field: String) -> Dictionary:
	var counts := {}
	for cell in map.cells():
		var v: int = map.terrain_at(cell) if field == "terrain" else map.elevation_at(cell)
		counts[v] = int(counts.get(v, 0)) + 1
	return counts
