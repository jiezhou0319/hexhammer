## make_fixed_maps.gd — 固定测试图落盘工具（M1a-T9 → M1a T3 手工河数据化 → T4
##   手工路+桥数据化；docs/04-tasks-m1.md M1a-T9 + 执行方案 §4 WATER-01 ③「RIVER_*
##   常量改产 WorldData.rivers；渡口 passable hack 退场」+ §5 ROAD-01/02「手工路 +
##   跨河桥 CrossingData 认领」）
## 「手工固定图」的落字：本脚本不用任何噪声/随机——全部地貌由显式几何特征
## （圆盘/圆环/贪心角点走）按设计图意图写死，重跑逐字节一致（digest 恒定）。
## 产物（提交入库）：
##   resources/maps/fixed/playable_60x40.json            格子表（MapData.to_dict 字段集）
##   resources/maps/fixed/playable_60x40.meta.json       digest/连通性/特征清单（无 seed——固定图）
##   resources/maps/fixed/playable_60x40.summary.txt     逐格摘要全文（可 diff）
##   resources/maps/fixed/playable_60x40.world.json      世界事实（T3 起：格边河 + 河口小湖；
##                                                        T4 起：东西横路 + 跨河桥）
## 用法（一次性/翻案重跑；改地貌后须同步更新 tests/test_map_source.gd 的 digest 锚）：
##   "E:/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless \
##     --path hexhammer --script res://tools/make_fixed_maps.gd
## 退出码：连通性不达标/六地形未全露出/世界校验不过/写入失败 → 1（不产出半成品）；正常 → 0。
## 设计意图（60×40，odd-r offset；T4 三档连接 + 六地形全露出的目检底图）：
##   · 基底：草 0 / 高程 1；
##   · 西南台地（悬崖演示）：r≤6.3 全 4 层、直落基底 1 层 → 外环 |Δ3| 陡面（cliff），
##     顶心 r≤2.2 露岩 2；
##   · 东南梯山（斜坡演示）：4/3/2 三层同心环 → 环间 |Δ1| 斜坡（slope），顶心露岩；
##   · 东北湖：r≤5.0 水 3（高程 0、不可通行）+ r≤7.0 沙 4 岸环——**格语义水体**
##     （WaterBodyData：湖、water_level 1、terminal）；
##   · 中部河（T3 数据化）：正弦走向 RIVER_* 常量 → 贪心角点走产**格边河**边序列
##     （RiverReachData：两侧格保持草地/高程 1/passable——边语义水体，ADR-14；
##     河床 0、水面 profile 恒 1）+ 河口小湖（终点边对账水体）；~~水道格 + 渡口
##     passable hack~~ 已退场（T3 起河在边上不占格；T4 起跨河通行由 CrossingData
##     认领——本图东西横路跨正弦河，~~FORD_ROWS 渡口~~ 无后继）；
##   · 东西横路 + 跨河桥（T4 数据化）：ROAD_COL_FROM..TO 东西横路（RoadData）在
##     行扫描的首个合法行跨河（两岸等高、恰一有河边、非源/终点边、非急弯边
##     ——ROAD-02 放置规则的固定图示范），CrossingData 认领该边（河在下路在上）；
##   · 林斑三处（只点缀草地上）+ 湖南岸泥滩（不覆盖水）；
##   · 等高平连（flat）：基底草地带随处可取。
extends SceneTree

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapConnectivity := preload("res://scripts/content/map_connectivity.gd")
const MapIO := preload("res://scripts/content/map_io.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const RiverFix := preload("res://tools/river_fixtures.gd")

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
const LAKE_CENTER := Vector2i(48, 8)       # 东北湖 + 沙岸（格语义水体）
const LAKE_R := 5.0
const LAKE_SHORE_R := 7.0
const RIVER_BASE_COL := 26                 # 正弦河（T3 起产格边河 WorldData.rivers）
const RIVER_AMPLITUDE := 4.0
const RIVER_PERIOD := 0.30
const RIVER_START_ROW := 1                 # 源边所在行（北端）
const FOREST_DISCS := [Vector2i(22, 20), Vector2i(52, 20), Vector2i(8, 34)]
const FOREST_RADII := [4.2, 3.4, 3.0]
const MUD_CENTER := Vector2i(46, 14)       # 湖南岸泥滩
const MUD_R := 2.6
# 河段/河口湖标高（int 同纲）：河床 0、水面恒 1（= 河口湖 water_level——对账逐位）
const RIVER_BED_LEVEL := 0
const RIVER_WATER_LEVEL := 1
# 东西横路（T4 ROAD-01/02 手工数据化）：列区间取「西避台地、东避梯山」的走廊；
# 跨河行 = 行扫描首个合法行（两岸等高 + 恰一有河边 + 非源/终点边 + 非急弯边
# ——确定性：行升序首个满足者，重跑同选）
const ROAD_COL_FROM := 18
const ROAD_COL_TO := 34
const ROAD_ROW_SCAN_FROM := 5
const ROAD_ROW_SCAN_TO := 30
# 地形 id（与 TerrainMaterialLibrary.DEFAULT_PALETTE 槽位同源）
const T_GRASS := 0
const T_MUD := 1
const T_ROCK := 2
const T_WATER := 3
const T_SAND := 4
const T_FOREST := 5

func _init() -> void:
	var map := _build()
	var world := _build_world(map)
	var report := MapConnectivity.check(map)
	print("[固定图] 连通性：", MapConnectivity.summary_of(report))
	if not report["ok"]:
		print("[固定图] !!! 连通性不达标（断路/孤岛），不落盘——检查水体设计")
		quit(1)
		return
	var world_err := world.validate(map, T_WATER)
	if world_err != "":
		print("[固定图] !!! 世界事实校验失败：", world_err)
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
			"edge_river_with_mouth_lake", "forest_patches", "mud_flat", "rock_outcrops",
			"cross_river_road_with_bridge",
		],
		"note": "hand-authored (no noise/random) by tools/make_fixed_maps.gd; "
			+ "JSON carries MapData.to_dict field set — same set as future M2 MapDef .tres; "
			+ "river = edge-sequence WorldData (ADR-14, T3 WATER-01); "
			+ "road/bridge = cells + CrossingData claim (T4 ROAD-01/02)",
	}
	var summary_path := MapIO.FIXED_MAP_PATH.get_base_dir().path_join("playable_60x40.summary.txt")
	var world_path := MapIO.world_path_for(MapIO.FIXED_MAP_PATH)
	var e1 := MapIO.write_map(map, MapIO.FIXED_MAP_PATH)
	var e2 := MapIO.write_meta(meta, MapIO.FIXED_MAP_META_PATH)
	var e3 := MapIO.write_summary(map, summary_path)
	var e4 := MapIO.write_world(world, world_path)
	if e1 != OK or e2 != OK or e3 != OK or e4 != OK:
		print("[固定图] !!! 落盘失败：map=", e1, " meta=", e2, " summary=", e3, " world=", e4)
		quit(1)
		return
	print("[固定图] 已落盘：")
	print("  ", MapIO.FIXED_MAP_PATH)
	print("  ", MapIO.FIXED_MAP_META_PATH)
	print("  ", summary_path)
	print("  ", world_path)
	print("[固定图] digest = ", map.digest())
	quit(0)


## 手工地貌构建（显式特征叠涂，后涂覆盖先涂：基底 → 山地 → 湖 → 河口小湖 → 植被点缀；
##   河本身不涂格——格边河在边上、两侧格保持草地（ADR-14；~~正弦水道格 + 渡口~~ 退场））
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
	# 5. 河口小湖（格语义水体）：终点边成员侧格 + 其邻格（对岸格除外——河口边恒
	#    单侧成员）涂水；河本体不涂（边语义水体，两侧格保持陆地）
	var mouth := _mouth_members_and_bank(map)
	for cid in mouth["members"]:
		map.set_elevation(RiverFix.cell_of_id(map, cid), 0)
		map.set_terrain(RiverFix.cell_of_id(map, cid), T_WATER)
		map.set_passable(RiverFix.cell_of_id(map, cid), false)
	# 6. 林斑（只点缀在草地上，不覆盖水/岩/沙）
	for i in FOREST_DISCS.size():
		_disc_terrain(map, FOREST_DISCS[i], FOREST_RADII[i], T_FOREST, [T_GRASS], true)
	# 7. 湖南岸泥滩（不覆盖水）
	_disc_terrain(map, MUD_CENTER, MUD_R, T_MUD, [T_WATER])
	return map


## 世界事实（T3 WATER-01 ③ + T4 ROAD-01/02 手工图数据化）：
##   · 河 = 贪心角点走产边序列（RIVER_* 正弦作目标列——「常量先例改产边序列」；
##     确定性：同图同链）+ 恒水位 profile 1 + 床 0；
##   · 河口湖 = 终点边成员侧水体（WaterBodyData：LAKE、water_level 1 = 终点边
##     水位（河口对账逐位）、terminal、inlet = [终点边]）；
##   · 东北湖 = 第二水体（id 1）：LAKE、water_level 1、terminal、无 inlet
##     （无河汇入——inlet_links 恒空是合法态：inlet 对账只查「声明必有河」，
##     不查「湖必有河」）；
##   · 东西横路 + 跨河桥（T4）：RoadData（等高行格序列）+ CrossingData 认领跨河
##     边（河在下路在上）；
##   · link 表 = 河边序列 + 道路相邻对的引用面（river_reach_id/road_id 对账）。
func _build_world(map: MapDataClass) -> WorldDataClass:
	var world := WorldDataClass.empty()
	var links := RiverFix.all_links(map)
	var chain := _river_chain(map, links)
	var mouth := _mouth_members_and_bank(map)
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = chain
	reach.flow_level = 1
	reach.water_levels = []
	for i in chain.size():
		reach.water_levels.append(RIVER_WATER_LEVEL)
	reach.bed_level = RIVER_BED_LEVEL
	reach.water_body_id = 0
	world.rivers.append(reach)
	var body := WorldDataClass.WaterBodyData.new()
	body.water_body_id = 0
	body.kind = WorldDataClass.WaterBodyData.Kind.LAKE
	body.water_level = RIVER_WATER_LEVEL
	body.member_cells = (mouth["members"] as Array).duplicate()
	body.member_cells.sort()
	body.inlet_links = [chain[chain.size() - 1]]
	body.outlet_links = []
	body.terminal = true
	world.water_bodies.append(body)
	var lake := WorldDataClass.WaterBodyData.new()
	lake.water_body_id = 1
	lake.kind = WorldDataClass.WaterBodyData.Kind.LAKE
	lake.water_level = RIVER_WATER_LEVEL
	lake.member_cells = []
	for cell in _disc_cells(map, LAKE_CENTER, LAKE_R):
		lake.member_cells.append(map.index_of(cell))
	lake.member_cells.sort()
	lake.inlet_links = []
	lake.outlet_links = []
	lake.terminal = true
	world.water_bodies.append(lake)
	# 东西横路 + 跨河桥（T4 ROAD-01/02 手工数据化）：行扫描首个合法行（确定性）
	var road_fix := _road_and_crossing(map, world.rivers[0])
	if road_fix.is_empty():
		print("[固定图] !!! 行扫描未找到合法跨河行（两岸等高/恰一有河边/非源终点/非急弯）")
		quit(1)
		return
	var road := WorldDataClass.RoadData.new()
	road.road_id = 0
	road.cells = road_fix["cells"]
	road.is_loop = false
	road.road_class = 0
	road.connects_pois = []
	world.roads.append(road)
	var crossing := WorldDataClass.CrossingData.new()
	crossing.crossing_id = 0
	crossing.kind = WorldDataClass.CrossingData.Kind.BRIDGE
	crossing.river_edge = road_fix["river_link"]
	crossing.bank_a = road_fix["river_link"].x
	crossing.bank_b = road_fix["river_link"].y
	world.crossings.append(crossing)
	# link 表 = 河边序列 + 道路相邻对的引用面（river_reach_id/road_id 双向对账，
	# 草案 §4；跨河边同时挂河与路 = crossing 认领的合法共存，§2.3 反转）
	for e in chain:
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = e
		lk.river_reach_id = 0
		if e == crossing.river_edge:
			lk.road_id = 0  # 河+路共存于同一条 link——被 CrossingData 认领（拍板⑤）
		world.links.append(lk)
	for i in road.cells.size() - 1:
		var pair := WorldDataClass.link_id_of(road.cells[i], road.cells[i + 1])
		if pair == crossing.river_edge:
			continue  # 跨河边已随河边条目挂 road_id
		var lk2 := WorldDataClass.NeighborLinkData.new()
		lk2.link_id = pair
		lk2.road_id = 0
		world.links.append(lk2)
	world.links.sort_custom(func(a: WorldDataClass.NeighborLinkData,
			b: WorldDataClass.NeighborLinkData) -> bool:
		return a.link_id.x < b.link_id.x \
			or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y))
	print("[固定图] 横路：行 %d 列 %d..%d（%d 格）跨河边 %s（急弯/源终点边排除后首个合法行）" \
		% [int(road_fix["row"]), ROAD_COL_FROM, ROAD_COL_TO, road.cells.size(),
			str(crossing.river_edge)])
	world.meta["engine_version"] = String(Engine.get_version_info()["string"])
	return world


## 东西横路的跨河行扫描（确定性：行升序首个满足者）。合法行 = 区间格全通行、
## 高程全等（桥两岸 Δ0）、相邻对中**恰一**有河边、该边非河段首尾边（源/终点
## 不设桥——ROAD-02 放置规则②）、且其两侧各 ±1 步无急弯（急弯判据 = edge[k] 与
## edge[k+2] 不平行，拍板⑩走向几何版；候选偏好非硬约束——固定图取示范口径）。
## 返回 {"row": int, "cells": Array[int], "river_link": Vector2i}；无合法行 → {}。
func _road_and_crossing(map: MapDataClass, reach: WorldDataClass.RiverReachData) -> Dictionary:
	var chain := reach.edges
	for row in range(ROAD_ROW_SCAN_FROM, ROAD_ROW_SCAN_TO + 1):
		var cells: Array[int] = []
		var elevations := {}
		var all_ok := true
		for col in range(ROAD_COL_FROM, ROAD_COL_TO + 1):
			var cell := Hex.axial_of(Vector2i(col, row))
			if not map.has_cell(cell) or not map.is_passable(cell):
				all_ok = false
				break
			cells.append(map.index_of(cell))
			elevations[map.elevation_at(cell)] = true
		if not all_ok or elevations.size() != 1:
			continue
		# 相邻对中的有河边（正弦河近南北向 → 跨河行穿恰一水平有河边）
		var river_links: Array[int] = []
		for i in cells.size() - 1:
			var k := chain.find(WorldDataClass.link_id_of(cells[i], cells[i + 1]))
			if k >= 0:
				river_links.append(k)
		if river_links.size() != 1:
			continue
		var idx: int = river_links[0]
		if idx == 0 or idx == chain.size() - 1:
			continue  # 源/终点边不设桥（ROAD-02 放置规则②：急弯/端点排除）
		var sharp := false
		for k in range(idx - 2, idx + 2):
			if WorldDataClass.river_bend_is_sharp(map, reach, k):
				sharp = true
				break
		if sharp:
			continue
		return {"row": row, "cells": cells, "river_link": chain[idx]}
	return {}


## 河边序列（确定性贪心角点走）：源边 = 起始行正弦列左右两格的水平边；每步
##   在延续边中取「南向 z − |x − 正弦目标列|」最大（并列取 link_id 小）。
func _river_chain(map: MapDataClass, links: Array[Vector2i]) -> Array[Vector2i]:
	var col := _river_col(RIVER_START_ROW)
	var a := map.index_of(Hex.axial_of(Vector2i(col - 1, RIVER_START_ROW)))
	var b := map.index_of(Hex.axial_of(Vector2i(col, RIVER_START_ROW)))
	var start := WorldDataClass.link_id_of(a, b)
	return RiverFix.greedy_chain(map, links, start, MAP_H * 2,
		func(row: int) -> float: return float(_river_col(row)))


## 河口（终点边）成员侧与对岸格：成员 = 终点边 link.x 格 + 其界内邻格（对岸
##   link.y 格除外——河口边恰一端成员，WATER-03 岸边口径）；确定性：链尾取
##   贪心走自然终点。返回 {"members": Array[int], "bank": int}。
## 注意：本函数在 _build（涂格）与 _build_world（水体数据）各调一次、同参同果
##   （纯函数读链——两侧不齐 = 河口对账失败，validate 兜底）。
func _mouth_members_and_bank(map: MapDataClass) -> Dictionary:
	var links := RiverFix.all_links(map)
	var chain := _river_chain(map, links)
	var term: Vector2i = chain[chain.size() - 1]
	var member := term.x
	var bank := term.y
	var members: Array[int] = [member]
	var member_cell := RiverFix.cell_of_id(map, member)
	for d in 6:
		var nb := Hex.neighbor(member_cell, d)
		if not map.has_cell(nb):
			continue
		var nb_id := map.index_of(nb)
		if nb_id == bank:
			continue
		if not members.has(nb_id):
			members.append(nb_id)
	members.sort()
	return {"members": members, "bank": bank}


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
