## make_fixed_maps.gd — 固定测试图落盘工具（M1a-T9；docs/04-tasks-m1.md M1a-T9
##   「固定测试图（手工 .tres）」——.tres 正式口径是 M2 MapDef（03 §M2-8、评审 G7
##   「两名一物」），M1a 以 JSON 载 MapData.to_dict 同字段集先行落盘，见 map_io.gd 头注）
## 「手工固定图」的落字：本脚本不用任何噪声/随机——全部地貌由显式几何特征
##   （圆盘/圆环/正弦河道）按设计图意图写死，重跑逐字节一致（digest 恒定）。
## 产物（提交入库）：
##   resources/maps/fixed/playable_60x40.json      格子表（MapData.to_dict 字段集）
##   resources/maps/fixed/playable_60x40.meta.json digest/连通性/特征清单（无 seed——固定图）
##   resources/maps/fixed/playable_60x40.summary.txt 逐格摘要全文（可 diff）
## 用法（一次性/翻案重跑；改地貌后须同步更新 tests/test_map_source.gd 的 digest 锚）：
##   "C:/Users/zerat/godot_tmp/Godot_v4.7.2-stable_win64_console.exe" --headless \
##     --path hexhammer --script res://tools/make_fixed_maps.gd
## 退出码：连通性不达标/六地形未全露出/写入失败 → 1（不产出半成品）；正常 → 0。
## 设计意图（60×40，odd-r offset；T4 三档连接 + 六地形全露出的目检底图）：
##   · 基底：草 0 / 高程 1；
##   · 西南台地（悬崖演示）：r≤6.3 全 4 层、直落基底 1 层 → 外环 |Δ3| 陡面（cliff），
##     顶心 r≤2.2 露岩 2；
##   · 东南梯山（斜坡演示）：4/3/2 三层同心环 → 环间 |Δ1| 斜坡（slope），顶心露岩；
##   · 东北湖：r≤5.0 水 3（高程 0、不可通行）+ r≤7.0 沙 4 岸环；
##   · 中部正弦河（col = 26+4·sin(0.3·row)）纵贯南北：单宽水道 + row12/row27 两处
##     沙质渡口（去掉渡口即断路——「连通性检查」的活例子；河每行恰一格、行间
##     |Δcol|≤1 → 水链连通且无缝可漏）；
##   · 林斑三处（只点缀草地上）+ 湖南岸泥滩（不覆盖水）；
##   · 等高平连（flat）：基底草地带随处可取。
extends SceneTree

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapConnectivity := preload("res://scripts/content/map_connectivity.gd")
const MapIO := preload("res://scripts/content/map_io.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")

const MAP_W := 60
const MAP_H := 40
# 特征参数（写死；调地貌 = 改这里 + 重跑 + 更新测试 digest 锚）
const PLATEAU_CENTER := Vector2i(14, 26)   # 西南台地（cliff 演示）
const PLATEAU_R := 6.3
const PLATEAU_ROCK_R := 2.2
const HILL_CENTER := Vector2i(44, 28)      # 东南梯山（slope 演示）
const HILL_R_TOP := 2.6
const HILL_R_MID := 5.0
const HILL_R_LOW := 7.6
const LAKE_CENTER := Vector2i(48, 8)       # 东北湖 + 沙岸
const LAKE_R := 5.0
const LAKE_SHORE_R := 7.0
const RIVER_BASE_COL := 26                 # 正弦河
const RIVER_AMPLITUDE := 4.0
const RIVER_PERIOD := 0.30
const FORD_ROWS := [12, 27]                # 沙质渡口（断路与否的开关）
const FOREST_DISCS := [Vector2i(22, 20), Vector2i(52, 20), Vector2i(8, 34)]
const FOREST_RADII := [4.2, 3.4, 3.0]
const MUD_CENTER := Vector2i(46, 14)       # 湖南岸泥滩
const MUD_R := 2.6
# 地形 id（与 TerrainMaterialLibrary.DEFAULT_PALETTE 槽位同源）
const T_GRASS := 0
const T_MUD := 1
const T_ROCK := 2
const T_WATER := 3
const T_SAND := 4
const T_FOREST := 5

func _init() -> void:
	var map := _build()
	var report := MapConnectivity.check(map)
	print("[固定图] 连通性：", MapConnectivity.summary_of(report))
	if not report["ok"]:
		print("[固定图] !!! 连通性不达标（断路/孤岛），不落盘——检查渡口/岸环设计")
		quit(1)
		return
	var terrain_counts := _terrain_counts(map)
	var elevation_counts := _elevation_counts(map)
	var edge_counts := _edge_class_counts(map)
	print("[固定图] 地形分布：", terrain_counts)
	print("[固定图] 高程分布：", elevation_counts)
	print("[固定图] 连接分布：", edge_counts)
	if terrain_counts.size() < 6:
		print("[固定图] !!! 六类地形未全露出（当前 ", terrain_counts.size(), "）——特征设计缺露")
		quit(1)
		return
	var meta := {
		"kind": "fixed",
		"schema_version": MapDataClass.SCHEMA_VERSION,
		"digest": map.digest(),
		"connectivity": MapConnectivity.summary_of(report),
		"terrain_counts": terrain_counts,
		"elevation_counts": elevation_counts,
		"edge_class_counts": edge_counts,
		"features": [
			"cliff_ring_plateau", "terraced_hill", "lake_with_sand_shore",
			"sine_river_with_two_fords", "forest_patches", "mud_flat", "rock_outcrops",
		],
		"note": "hand-authored (no noise/random) by tools/make_fixed_maps.gd; "
			+ "JSON carries MapData.to_dict field set — same set as future M2 MapDef .tres",
	}
	var summary_path := MapIO.FIXED_MAP_PATH.get_base_dir().path_join("playable_60x40.summary.txt")
	var e1 := MapIO.write_map(map, MapIO.FIXED_MAP_PATH)
	var e2 := MapIO.write_meta(meta, MapIO.FIXED_MAP_META_PATH)
	var e3 := MapIO.write_summary(map, summary_path)
	if e1 != OK or e2 != OK or e3 != OK:
		print("[固定图] !!! 落盘失败：map=", e1, " meta=", e2, " summary=", e3)
		quit(1)
		return
	print("[固定图] 已落盘：")
	print("  ", MapIO.FIXED_MAP_PATH)
	print("  ", MapIO.FIXED_MAP_META_PATH)
	print("  ", summary_path)
	print("[固定图] digest = ", map.digest())
	quit(0)


## 手工地貌构建（显式特征叠涂，后涂覆盖先涂：基底 → 山地 → 水 → 渡口 → 植被点缀）
func _build() -> MapDataClass:
	var map := MapDataClass.new(MAP_W, MAP_H)
	# 1. 基底：草 / 高程 1
	for cell in map.cells():
		map.set_elevation(cell, 1)
		map.set_terrain(cell, T_GRASS)
	# 2. 西南台地：r≤6.3 全 4 层（外沿直落基底 → cliff）；顶心露岩
	_disc_elev(map, PLATEAU_CENTER, PLATEAU_R, 4)
	_disc_terrain(map, PLATEAU_CENTER, PLATEAU_ROCK_R, T_ROCK)
	# 3. 东南梯山：2/3/4 三层同心环（环间 |Δ1| slope）；顶心露岩
	_disc_elev(map, HILL_CENTER, HILL_R_LOW, 2)
	_disc_elev(map, HILL_CENTER, HILL_R_MID, 3)
	_disc_elev(map, HILL_CENTER, HILL_R_TOP, 4)
	_disc_terrain(map, HILL_CENTER, HILL_R_TOP, T_ROCK)
	# 4. 东北湖：水（高程 0、不可通行）+ 沙岸环（不覆盖水）
	_disc_water(map, LAKE_CENTER, LAKE_R)
	_disc_terrain(map, LAKE_CENTER, LAKE_SHORE_R, T_SAND, [T_WATER])
	# 5. 正弦河（纵贯南北，单宽水道）
	for row in MAP_H:
		var cell := Hex.axial_of(Vector2i(_river_col(row), row))
		if map.has_cell(cell):
			map.set_elevation(cell, 0)
			map.set_terrain(cell, T_WATER)
			map.set_passable(cell, false)
	# 6. 渡口：水道上恢复通行（沙 / 高程 1）——东西两岸的连接点
	for row in FORD_ROWS:
		var cell := Hex.axial_of(Vector2i(_river_col(row), row))
		if map.has_cell(cell):
			map.set_elevation(cell, 1)
			map.set_terrain(cell, T_SAND)
			map.set_passable(cell, true)
	# 7. 林斑（只点缀在草地上，不覆盖水/岩/沙）
	for i in FOREST_DISCS.size():
		_disc_terrain(map, FOREST_DISCS[i], FOREST_RADII[i], T_FOREST, [T_GRASS], true)
	# 8. 湖南岸泥滩（不覆盖水）
	_disc_terrain(map, MUD_CENTER, MUD_R, T_MUD, [T_WATER])
	return map


func _river_col(row: int) -> int:
	return RIVER_BASE_COL + int(round(RIVER_AMPLITUDE * sin(float(row) * RIVER_PERIOD)))


## 圆盘涂高程：col/row 距 center ≤ radius 的界内格统一设高程层
func _disc_elev(map: MapDataClass, center: Vector2i, radius: float, level: int) -> void:
	for cell in _disc_cells(map, center, radius):
		map.set_elevation(cell, level)


## 圆盘涂地形：skip_terrains = 现地形命中即跳过的守卫表（护水/护岩用）；
## only_in_terrains = true 时反向——只有现地形 ∈ skip_terrains 才涂（护草种林用）。
func _disc_terrain(map: MapDataClass, center: Vector2i, radius: float, terrain: int,
		guard_terrains: Array = [], only_in_guard := false) -> void:
	for cell in _disc_cells(map, center, radius):
		var hit: bool = guard_terrains.has(map.terrain_at(cell))
		if hit == only_in_guard:
			map.set_terrain(cell, terrain)


## 圆盘水体：高程 0 + 水地形 + 不可通行
func _disc_water(map: MapDataClass, center: Vector2i, radius: float) -> void:
	for cell in _disc_cells(map, center, radius):
		map.set_elevation(cell, 0)
		map.set_terrain(cell, T_WATER)
		map.set_passable(cell, false)


## 圆盘覆盖的界内格（offset col/row 距离口径；行主序固定输出）
func _disc_cells(map: MapDataClass, center: Vector2i, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r2 := radius * radius
	for row in range(center.y - int(ceil(radius)) - 1, center.y + int(ceil(radius)) + 2):
		for col in range(center.x - int(ceil(radius)) - 1, center.x + int(ceil(radius)) + 2):
			var cell := Hex.axial_of(Vector2i(col, row))
			if map.has_cell(cell):
				var dx := float(col - center.x)
				var dy := float(row - center.y)
				if dx * dx + dy * dy <= r2:
					out.append(cell)
	return out


func _terrain_counts(map: MapDataClass) -> Dictionary:
	var counts := {}
	for cell in map.cells():
		var t: int = map.terrain_at(cell)
		counts[t] = int(counts.get(t, 0)) + 1
	return counts


func _elevation_counts(map: MapDataClass) -> Dictionary:
	var counts := {}
	for cell in map.cells():
		var e: int = map.elevation_at(cell)
		counts[e] = int(counts.get(e, 0)) + 1
	return counts


## 连接分类分布（与 m1a_sandbox._edge_class_counts 同口径：每条无向边只数一次）
func _edge_class_counts(map: MapDataClass) -> Dictionary:
	var counts := {}
	for cell in map.cells():
		for d in 3:
			var nb := Hex.neighbor(cell, d)
			if map.has_cell(nb):
				var t := Builder.classify_edge(map.elevation_at(cell) - map.elevation_at(nb))
				counts[t] = int(counts.get(t, 0)) + 1
	return counts
