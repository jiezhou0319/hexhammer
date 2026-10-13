## test_river_network_generator.gd — T5 WORLD-02 河口反向生长河网生成单测
##   （执行方案 docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-02 + 主创拍板
##   第二批④「河口反向生长」+ 修订记录三之 4/5）
## 覆盖锚（卡表「测试锚」逐条）：
##   - 无环/合法出口（构造保证 + 校验器双断言）：角点级无环独立复核（非相邻
##     边共享角点 = 角点重访 = 环——与 WorldData 校验器行走算法独立的两路互证）
##     + 全量 WorldData.validate（WATER-01 校验器断言侧）+ 跨链角点不共享
##     （河间不汇合/不交叉——简单链的「彼此不汇合」面）；
##   - 同 seed 同河网（确定性）：同 map 同 cfg 同 rng → 产出逐字节一致；
##   - 源/汇可枚举（与 WATER-01 fixture 同族）：edges[0]=源边/edges[last]=河口水口
##     均为合法界内 link，终点边 ∈ 声明水体 inlet_links（对账）；
##   - 水位构造单调 + 离散高程重验：逐段 profile 单调不升（独立逐段复查）、
##     河口水位 == 水体 water_level、逐段水位 < 双岸高程（两岸容纳）、
##     bed < 逐段水位；量化后二次验证 = 管线水系阶段 post_quantum_valid
##     （tests/test_world_pipeline.gd 锚）+ 本文件全量 validate；
##   - 停止条件具名：预算尽（budget）/ 抵图界（map_edge）/ 无合法候选
##     （no_candidate）各一确定样本；生成器只读（生成前后 map.summary 逐字节
##     一致——不静默重塑整图高程）；
##   - 水体声明：贴图界分量 SEA / 内陆分量 LAKE / 成员水位不齐具名失败；
##   - 多河河口最小六边形环距约束（Azgaar burgs 间距同族）；
##   - T6 S4 对账面：hydrology 输出不受 erosion 通道影响（生成器输入面不含
##     侵蚀通道；同量化图必得同 hydrology 诊断——通道隔离锚，见文件尾块）。
## oracle 原则：角点同一性用 WorldData.corner_id_of（数据层稳定 ID 公开合同，
##   tests/test_world_data.gd 另锚）+ RiverFixtures 几何共角点判定双路互证；
##   期望单调性/容纳/间距由 HexMath/MapData 原语独立推导，不复制生成器实现。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapGenerator := preload("res://scripts/content/map_generator.gd")
const MapGenParamsClass := preload("res://scripts/content/map_gen_params.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const RiverGen := preload("res://scripts/content/river_network_generator.gd")
const RiverFix := preload("res://tools/river_fixtures.gd")

const T_GRASS := 0
const T_WATER := 3

# ================= 标准样本（量化图上生成）=================

## 默认参数 seed=7 量化图（60×40，含水海）——MapGenerator 退化特例即量化前
## 三阶段（tests/test_world_pipeline.gd 已锚确定性）。
func _quantized_map() -> MapDataClass:
	var p := MapGenParamsClass.new()
	p.seed = 7
	var r := MapGenerator.generate(p)
	expect(r["ok"], "量化图生成应成功")
	if not r["ok"]:
		return null
	var map: MapDataClass = r["map"]
	return map


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _cfg(overrides := {}) -> Dictionary:
	var cfg := {
		"river_count": 3,
		"river_max_edges": 24,
		"min_mouth_spacing": 6,
		"river_flow_level": 1,
		"water_terrain_id": T_WATER,
	}
	for k in overrides:
		cfg[k] = overrides[k]
	return cfg


## 生成器产出 → WorldData 组装（类型化集合元素级搬运——组装本身走公开 API）。
func _world_of(result: Dictionary) -> WorldDataClass:
	var world := WorldDataClass.empty()
	for r in result["rivers"]:
		world.rivers.append(r)
	for b in result["water_bodies"]:
		world.water_bodies.append(b)
	for lk in result["links"]:
		world.links.append(lk)
	return world


func _generate_on(map: MapDataClass, cfg: Dictionary, rng_seed := 5) -> Dictionary:
	return RiverGen.generate(map, _rng(rng_seed), cfg)

# ================= 校验器双断言之「校验器侧」+ 结构独立复核 =================

func test_generated_rivers_pass_full_validation() -> void:
	# 构造保证 + WATER-01 校验器断言 = 双保险（方案 ①）：全量 validate 含角点级
	# 无环/水位单调/bed 容纳/河口对账/link 双向对账
	var map := _quantized_map()
	if map == null:
		return
	var result := _generate_on(map, _cfg())
	expect(result["ok"], "生成应成功：%s" % result["error"])
	if not result["ok"]:
		return
	expect(int(result["stats"]["reaches"]) > 0, "默认样本应产出河（60×40 含水海）")
	var world := _world_of(result)
	expect_eq(world.validate(map, T_WATER), "", "生成河网全量校验通过（校验器断言侧）")

func test_acyclic_corner_level_independent_and_cross_reach() -> void:
	# 独立复核（不走校验器行走算法）：reach 内**非相邻**边共享角点 = 角点重访
	# = 环（修订记录三之 4——边不复用 ≠ 无环）；跨 reach 角点共享 = 河间交叉
	# （简单链「彼此不汇合」的完整面）
	var map := _quantized_map()
	if map == null:
		return
	var result := _generate_on(map, _cfg())
	if not result["ok"]:
		fail("生成失败：%s" % result["error"])
		return
	var cross_corners := {}
	for r in result["rivers"]:
		var reach: WorldDataClass.RiverReachData = r
		# 逐边角点 ID（两端格 + dir 派生——WorldData 公开合同）
		var edge_corners: Array = []
		var reach_corner_set := {}  # 本链角点去重集（相邻边共享角点是链内合法重言）
		for e in reach.edges:
			var a := RiverFix.cell_of_id(map, e.x)
			var d := Hex.dir_between(a, RiverFix.cell_of_id(map, e.y))
			edge_corners.append([
				WorldDataClass.corner_id_of(map, a, d),
				WorldDataClass.corner_id_of(map, a, d + 1),
			])
			for cid in edge_corners[edge_corners.size() - 1]:
				reach_corner_set[cid] = true
		for i in edge_corners.size():
			for j in range(i + 1, edge_corners.size()):
				var shared := false
				for c1 in edge_corners[i]:
					if edge_corners[j].has(c1):
						shared = true
				if j == i + 1:
					expect(shared, "相邻边须共角点（序列连续）reach %d：e%d/e%d"
						% [reach.reach_id, i, j])
				else:
					expect(not shared, "非相邻边共享角点 = 角点级环 reach %d：e%d/e%d"
						% [reach.reach_id, i, j])
		# 跨链：本链去重后的角点集不与他链相交（河间不汇合/不交叉）
		for cid in reach_corner_set:
			expect(not cross_corners.has(cid),
				"角点 %d 被两条 reach 共享（河间交叉）" % cid)
			cross_corners[cid] = reach.reach_id
		# 几何互证（RiverFixtures 世界坐标路径——与 corner_id_of 两路独立）：
		# 相邻边在世界坐标上共角点
		for i in range(reach.edges.size() - 1):
			expect(RiverFix.links_share_corner(map, reach.edges[i], reach.edges[i + 1]),
				"几何共角点互证 reach %d：e%d/e%d" % [reach.reach_id, i, i + 1])

func test_same_seed_same_network_deterministic() -> void:
	var map := _quantized_map()
	if map == null:
		return
	var a := _generate_on(map, _cfg(), 5)
	var b := _generate_on(map, _cfg(), 5)
	expect(a["ok"] and b["ok"], "两次生成应成功")
	if not (a["ok"] and b["ok"]):
		return
	expect_eq(JSON.stringify(_world_of(b).to_dict()), JSON.stringify(_world_of(a).to_dict()),
		"同 map 同 cfg 同 rng seed → 河网逐字节一致（确定性）")
	expect_eq(str(b["stats"]), str(a["stats"]), "停止原因/河口统计一致")

# ================= 源/汇可枚举 + 河口对账 =================

func test_source_and_terminal_enumerable_with_inlet_reconciliation() -> void:
	var map := _quantized_map()
	if map == null:
		return
	var result := _generate_on(map, _cfg())
	if not result["ok"]:
		fail("生成失败：%s" % result["error"])
		return
	var world := _world_of(result)
	for r in world.rivers:
		var source: Vector2i = r.edges[0]
		var terminal: Vector2i = r.edges[r.edges.size() - 1]
		# 源/终点边 = 合法界内 link（两端互为界内邻居）
		for e in [source, terminal]:
			var ca := RiverFix.cell_of_id(map, e.x)
			var cb := RiverFix.cell_of_id(map, e.y)
			expect(map.has_cell(ca) and map.has_cell(cb) and Hex.dir_between(ca, cb) >= 0,
				"reach %d 端点边 %s 应为合法界内 link" % [r.reach_id, e])
		# 终点边 ∈ 声明水体 inlet_links + 河口水位 == 水体水位 + 恰一端为成员
		var body := world.water_body_by_id(r.water_body_id)
		expect(body != null, "reach %d 汇入水体可解析" % r.reach_id)
		if body == null:
			continue
		expect(body.inlet_links.has(terminal),
			"reach %d 终点边 ∈ 水体 %d inlet_links（双向对账）" % [r.reach_id, body.water_body_id])
		expect_eq(r.water_levels[r.water_levels.size() - 1], body.water_level,
			"reach %d 河口水位 == 水体水位" % r.reach_id)
		var in_a := body.member_cells.has(terminal.x)
		var in_b := body.member_cells.has(terminal.y)
		expect(in_a != in_b, "reach %d 河口边恰一端为成员格（岸边口径）" % r.reach_id)
		var member_id := terminal.x if in_a else terminal.y
		expect_eq(map.terrain_at(RiverFix.cell_of_id(map, member_id)), T_WATER,
			"reach %d 河口成员侧格为水格" % r.reach_id)

# ================= 水位构造单调 + 两岸容纳 + 河床 =================

func test_water_levels_monotone_below_banks_and_bed() -> void:
	var map := _quantized_map()
	if map == null:
		return
	var result := _generate_on(map, _cfg())
	if not result["ok"]:
		fail("生成失败：%s" % result["error"])
		return
	var world := _world_of(result)
	expect(world.rivers.size() > 0, "样本须有河（单调/容纳断言的对象）")
	for r in world.rivers:
		# 单调不升（沿 edges 序 = 上游→下游；Catlike 禁上坡的独立逐段复查）
		for k in range(r.water_levels.size() - 1):
			expect(r.water_levels[k + 1] <= r.water_levels[k],
				"reach %d 水位沿序列单调不升：edges[%d] %d → edges[%d] %d"
				% [r.reach_id, k, r.water_levels[k], k + 1, r.water_levels[k + 1]])
		# 逐段：水位 < 双岸高程（两岸容纳）+ 双岸陆地 + bed < 水位。
		# **终点边（河口边）除外**：岸边口径 = 恰一端为水体成员格（WATER-03），
		# 水位 == 水体水位、对账在 test_source_and_terminal ——「两岸」只对上游边成立
		for k in range(r.edges.size() - 1):
			var e: Vector2i = r.edges[k]
			var ea := map.elevation_at(RiverFix.cell_of_id(map, e.x))
			var eb := map.elevation_at(RiverFix.cell_of_id(map, e.y))
			expect(r.water_levels[k] < ea and r.water_levels[k] < eb,
				"reach %d edges[%d] 水位 %d 须低于双岸（%d/%d）"
				% [r.reach_id, k, r.water_levels[k], ea, eb])
			expect(map.is_passable(RiverFix.cell_of_id(map, e.x))
				and map.terrain_at(RiverFix.cell_of_id(map, e.x)) != T_WATER
				and map.is_passable(RiverFix.cell_of_id(map, e.y))
				and map.terrain_at(RiverFix.cell_of_id(map, e.y)) != T_WATER,
				"reach %d edges[%d] 双岸均为陆地（河是边语义水体）" % [r.reach_id, k])
			expect(r.bed_level < r.water_levels[k],
				"reach %d bed %d < 逐段水位（edges[%d]=%d）"
				% [r.reach_id, r.bed_level, k, r.water_levels[k]])

func test_flow_level_fixed_from_config() -> void:
	# 首版固定等级、不依赖汇流分档（修订记录三之 5——简单链无汇流，Strahler
	# 随汇流第二版）：flow_level == cfg 值（取 2 证明确来自配置而非硬编码）
	var map := _quantized_map()
	if map == null:
		return
	var result := _generate_on(map, _cfg({"river_flow_level": 2}))
	if not result["ok"]:
		fail("生成失败：%s" % result["error"])
		return
	for r in result["rivers"]:
		var reach: WorldDataClass.RiverReachData = r
		expect_eq(reach.flow_level, 2, "flow_level 固定取配置值（不依赖汇流）")

# ================= 停止条件具名（budget / map_edge / no_candidate）=================

func test_budget_stops_chain() -> void:
	var map := _quantized_map()
	if map == null:
		return
	var result := _generate_on(map, _cfg({"river_max_edges": 3}))
	if not result["ok"]:
		fail("生成失败：%s" % result["error"])
		return
	for r in result["rivers"]:
		var reach: WorldDataClass.RiverReachData = r
		expect(reach.edges.size() <= 3, "预算 3 → 链长 ≤3（reach %d got %d）"
			% [reach.reach_id, reach.edges.size()])
	var stops: Dictionary = result["stats"]["stop_reasons"]
	expect(int(stops[RiverGen.STOP_BUDGET]) >= 1,
		"60×40 图上预算 3 应有链撞预算（stop_reasons=%s）" % str(stops))
	var world := _world_of(result)
	expect_eq(world.validate(map, T_WATER), "", "缩短后的河网仍全量合法（缩短是合法出路）")

func test_map_edge_stop_on_one_row_map() -> void:
	# 4×1 图、唯一陆格 (1,0)：河口角点的延续边全部出界 → 抵图界 = 源（确定样本）
	var map := MapDataClass.new(4, 1)
	for cell in map.cells():
		var is_land := Hex.offset_of(cell).x == 1
		map.set_terrain(cell, T_GRASS if is_land else T_WATER)
		map.set_elevation(cell, 1 if is_land else 0)
		map.set_passable(cell, is_land)
	var result := _generate_on(map, _cfg({"min_mouth_spacing": 1}))
	expect(result["ok"], "单行图生成应成功")
	if not result["ok"]:
		return
	var stats: Dictionary = result["stats"]
	expect_eq(int(stats["reaches"]), 1, "间距 1 → 两河口锚同格，仅接纳 1 河")
	expect_eq(int(stats["stop_reasons"][RiverGen.STOP_MAP_EDGE]), 1,
		"唯一陆格的河口上游端顶在图界（抵图界 = 源）")
	var world := _world_of(result)
	expect_eq(world.validate(map, T_WATER), "", "图界源河仍合法")
	if world.rivers.size() == 1:
		expect_eq(world.rivers[0].edges.size(), 1, "无界内延续 → 链长 1（缩短合法）")

func test_no_candidate_stop_on_island_map() -> void:
	# 3×3 图、中心陆格四面环水：界内延续边存在但双岸验证全拒（第三格恒水）→
	# 无合法候选（与 map_edge 的区分样本）
	var map := MapDataClass.new(3, 3)
	for cell in map.cells():
		var cr := Hex.offset_of(cell)
		var is_land := cr.x == 1 and cr.y == 1
		map.set_terrain(cell, T_GRASS if is_land else T_WATER)
		map.set_elevation(cell, 1 if is_land else 0)
		map.set_passable(cell, is_land)
	var result := _generate_on(map, _cfg({"min_mouth_spacing": 6}))
	expect(result["ok"], "孤岛图生成应成功")
	if not result["ok"]:
		return
	var stats: Dictionary = result["stats"]
	expect_eq(int(stats["reaches"]), 1, "六河口锚同格 → 仅 1 河")
	expect_eq(int(stats["stop_reasons"][RiverGen.STOP_NO_CANDIDATE]), 1,
		"界内延续全被两岸验证拒 → 无合法候选（具名停止，不静默重塑高程）")
	var world := _world_of(result)
	expect_eq(world.validate(map, T_WATER), "", "单边河仍合法（源 = 河口边的退化链）")

func test_generator_never_mutates_map() -> void:
	# 只读合同：生成前后 summary 逐字节一致（高程唯一来源 = 双噪声 + 量化——
	# 生成器无权改图，修订记录三之 5）
	var map := _quantized_map()
	if map == null:
		return
	var before := map.summary()
	var result := _generate_on(map, _cfg())
	expect(result["ok"], "生成应成功")
	expect_eq(map.summary(), before, "生成器只读 MapData（不静默重塑整图高程）")

# ================= 多河河口间距约束 =================

func test_mouth_spacing_enforced() -> void:
	var map := _quantized_map()
	if map == null:
		return
	var result := _generate_on(map, _cfg({"min_mouth_spacing": 12, "river_count": 4}))
	if not result["ok"]:
		fail("生成失败：%s" % result["error"])
		return
	var mouths: Array = result["stats"]["mouths"]
	expect(mouths.size() >= 2, "60×40 图间距 12 应容多河口（got %d）" % mouths.size())
	expect_eq(mouths.size(), int(result["stats"]["reaches"]), "河口数 = 链数")
	# 间距锚 = 河口的陆侧端格（生成器同口径的独立重推：非水端）
	var anchors: Array[Vector2i] = []
	for m in mouths:
		var link: Vector2i = m
		var ca := RiverFix.cell_of_id(map, link.x)
		var cb := RiverFix.cell_of_id(map, link.y)
		var anchor := ca if map.terrain_at(ca) != T_WATER else cb
		anchors.append(anchor)
	for i in anchors.size():
		for j in range(i + 1, anchors.size()):
			expect(Hex.distance(anchors[i], anchors[j]) >= 12,
				"河口锚 %s/%s 环距 ≥ 间距 12（got %d）"
				% [anchors[i], anchors[j], Hex.distance(anchors[i], anchors[j])])

# ================= 水体声明（SEA/LAKE/成员水位）=================

func test_water_bodies_declared_sea_and_lake() -> void:
	# 手工图：row0 水（贴图界 → SEA）+ 内陆 2×2 水块（LAKE）——连通分量口径的
	# 独立手算 oracle；river_count=0 = 无河世界（水体声明仍产出）
	var map := MapDataClass.new(8, 8)
	for cell in map.cells():
		var cr := Hex.offset_of(cell)
		var is_water := cr.y == 0 or (cr.x >= 3 and cr.x <= 4 and cr.y >= 4 and cr.y <= 5)
		map.set_terrain(cell, T_WATER if is_water else T_GRASS)
		map.set_elevation(cell, 0 if is_water else 1)
		map.set_passable(cell, not is_water)
	var result := _generate_on(map, _cfg({"river_count": 0}))
	expect(result["ok"], "无河世界生成应成功")
	if not result["ok"]:
		return
	var stats: Dictionary = result["stats"]
	expect_eq(int(stats["bodies"]), 2, "两水体（海 + 内陆湖）")
	expect_eq(int(stats["sea"]), 1, "贴图界分量 = SEA")
	expect_eq(int(stats["lake"]), 1, "内陆分量 = LAKE")
	expect_eq(int(stats["reaches"]), 0, "river_count=0 → 无河（合法态）")
	var world := _world_of(result)
	expect_eq(world.validate(map, T_WATER), "", "纯水体世界（无河）全量合法")
	for b in world.water_bodies:
		var body: WorldDataClass.WaterBodyData = b
		expect_eq(body.water_level, 0, "水体 %d 水位 = 量化水床 0" % body.water_body_id)
		expect_eq(body.member_cells.size(), 4 if body.kind == WorldDataClass.WaterBodyData.Kind.LAKE else 8,
			"水体 %d 成员数手算对账" % body.water_body_id)
		for cid in body.member_cells:
			expect_eq(map.terrain_at(RiverFix.cell_of_id(map, cid)), T_WATER,
				"水体 %d 成员格全为水格" % body.water_body_id)

func test_water_level_mismatch_named_failure() -> void:
	# 成员水位不齐 → 具名失败（WATER_BODY_LEVEL——量化口径破坏；不静默改图）
	var map := MapDataClass.new(2, 2)
	for cell in map.cells():
		map.set_terrain(cell, T_WATER)
		map.set_passable(cell, false)
	map.set_elevation(RiverFix.cell_of_id(map, 0), 2)  # 其余默认 0 → 不齐
	var result := _generate_on(map, _cfg())
	expect(not result["ok"], "成员水位不齐应失败")
	expect(String(result["error"]).contains("WATER_BODY_LEVEL"),
		"失败应具名 WATER_BODY_LEVEL（got %s）" % result["error"])

func test_cfg_missing_key_named_failure() -> void:
	var map := MapDataClass.new(4, 4)
	var cfg := _cfg()
	cfg.erase("river_flow_level")
	var result := RiverGen.generate(map, _rng(5), cfg)
	expect(not result["ok"], "配置缺键应失败")
	expect(String(result["error"]).contains("缺键"), "失败串指明缺键（got %s）" % result["error"])

# ================= T6 S4：hydrology 输出与侵蚀通道的对账面 =================

func test_hydrology_unaffected_by_erosion_channel_when_map_unchanged() -> void:
	# 通道隔离锚（T6 §6 验收「hydrology 阶段输出摘要不受 erosion 通道影响」）：
	# 河网生成器的输入面 = (量化图, hydrology 通道 rng, cfg)——erosion 通道不在
	# 其中（RiverGen.CFG_KEYS 无该键）；管线面上同量化图（侵蚀关 = erosion 通道
	# 零消耗 → map 恒同）必得同 hydrology 诊断。侵蚀开态下图可变 → 河网随之变
	# 是「下游消费最终事实」的既定语义（提案 :223），不属本锚。
	expect(not RiverGen.CFG_KEYS.has("erosion"),
		"河网生成器配置键不含 erosion（生成器不认侵蚀通道——结构面）")
	var WPC := preload("res://scripts/content/world_pipeline.gd")
	var WTC := preload("res://scripts/core/data/world_template.gd")
	var t := WTC.make_regions()
	t.erosion_enabled = false
	var base: Dictionary = WPC.generate_world(t, 7)
	var alt: Dictionary = WPC.generate_world(t, 7, {"erosion": 424242})
	expect(base["ok"] and alt["ok"], "侵蚀关两跑应成功")
	if not (base["ok"] and alt["ok"]):
		return
	var base_map: MapDataClass = base["map"]
	var alt_map: MapDataClass = alt["map"]
	expect_eq(alt_map.digest(), base_map.digest(),
		"侵蚀关态改 erosion 通道 → 量化图逐字节一致（erosion 通道零消耗前提）")
	var base_hydro := {}
	var alt_hydro := {}
	for d0 in base["stages"]:
		if String(d0["stage"]) == "hydrology":
			base_hydro = d0
	for d1 in alt["stages"]:
		if String(d1["stage"]) == "hydrology":
			alt_hydro = d1
	expect_eq(str(alt_hydro), str(base_hydro),
		"同量化图必得同 hydrology 诊断（河网输出不受 erosion 通道影响——通道隔离锚）")
	# 反向确证（分辨力）：生成器对同图同 cfg 同 rng 仍确定（既有确定性锚的
	# erosion-adjacent 复核——侵蚀产物图上重跑两次逐字节一致；经 to_dict 落
	# 可比形状——RefCounter 直 stringify 不可比）
	var r1 := RiverGen.generate(base_map, _rng(9), _cfg())
	var r2 := RiverGen.generate(base_map, _rng(9), _cfg())
	expect_eq(JSON.stringify(_world_of(r1).to_dict()["rivers"]),
		JSON.stringify(_world_of(r2).to_dict()["rivers"]),
		"同图同 rng 重跑河网一致（生成器只读图与通道——确定性保持）")
