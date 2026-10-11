## test_world_pipeline.gd — T5 WORLD-01 模板和阶段化生成单测（执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-01；主创拍板⑧ Azgaar 管线
##   骨架去气候改造 + 拍板①双噪声唯一路线 + 修订记录三之 5/7）
## 覆盖锚（卡表「测试锚」逐条）：
##   - 每阶段独立摘要可 diff（阶段输出规范序摘要 + 阶段版本号；同 seed 两次跑
##     逐阶段诊断 dict 逐字一致）；
##   - 关闭未实现能力不产伪字段：跳过阶段的 WorldData 对应集合为空（empty
##     集合合法锚——退化特例与模板关停两面）；
##   - 同 seed 同模板同引擎构建 → world_digest 一致（跑 3 次）；
##   - 配置冲突显式失败：冲突原因串全列不产半图；
##   - 具名通道独立性：改 decoration 通道不影响 hydrology 输出摘要
##     （「新增一棵树不消耗前面阶段 RNG」，提案随机性纪律）；
##   - 附加面：九阶段序固定 + 阶段版本表齐备；GENERATOR_VERSION=2（管线变更
##     显式登记）；模板 .tres 与代码默认同源（TerrainStyle 同纪律）；植被/地表
##     掩码通道保留且林/泥分类在用（修订记录三之 7——按字面删通道会抽掉现有
##     分类）；MapGenerator 退化特例行为不变 = 独立拼装单遍 oracle 逐格对照
##     （04 M1a-T9 细化的四步直读，不复制管线实现）。
## oracle 原则：单遍 oracle 在本文件内独立实现（噪声接线/归一化/量化/分类阈值
##   0.60/0.70 按 04 M1a-T9 细化文字重写）；世界摘要直接调 WorldData.world_digest
##   （数据层合同，tests/test_world_data.gd 另锚）；期望通道集/阶段序为字面常量。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapGenerator := preload("res://scripts/content/map_generator.gd")
const MapGenParamsClass := preload("res://scripts/content/map_gen_params.gd")
const MapConnectivity := preload("res://scripts/content/map_connectivity.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const WorldTemplateClass := preload("res://scripts/core/data/world_template.gd")
const WorldPipeline := preload("res://scripts/content/world_pipeline.gd")

## 与生成器分离的 oracle 分类阈值（04 M1a-T9 细化口径重写——值变 = 管线翻案，
## 本测试与生成器须同步改 = 翻案须同步改测试纪律）
const ORACLE_FOREST_THRESHOLD := 0.60
const ORACLE_MUD_THRESHOLD := 0.70
const T_WATER := 3
const T_ROCK := 2
const T_MUD := 1
const T_SAND := 4
const T_FOREST := 5

# ================= 九阶段序 + 阶段版本 + 具名通道（WORLD-01 ①④）=================

func test_stage_order_nine_stages_fixed() -> void:
	# Azgaar 去气候九阶段（拍板⑧）：配置→地理→量化→河网水体→聚落→势力→道路→
	# 可玩校验→表现派生——执行顺序即依赖图，顺序是合同
	var want: Array[String] = ["config", "geography", "quantize", "hydrology",
		"settlement", "allegiance", "roads", "playability", "presentation"]
	expect_eq(WorldPipeline.STAGES, want, "九阶段固定序（Azgaar 去气候改造，§6 ①）")
	for stage_name in want:
		expect(WorldPipeline.STAGE_VERSIONS.has(stage_name), "阶段版本表缺 %s" % stage_name)
		expect(int(WorldPipeline.STAGE_VERSIONS[stage_name]) >= 1, "阶段 %s 版本 ≥1" % stage_name)

func test_named_channels_independent_seeds() -> void:
	# 五具名通道（geography/hydrology/poi/roads/decoration；biome 通道删除——拍板④）
	expect_eq(WorldPipeline.CHANNELS, ["geography", "hydrology", "poi", "roads", "decoration"],
		"具名通道集合（提案随机性纪律）")
	# 偏移互异且与植被场偏移 1013 错开（两层随机不串流；值写死保证复现）
	var seen := {}
	for ch in WorldPipeline.CHANNELS:
		var s := WorldPipeline.channel_seed(7, ch)
		expect(s != -1, "通道 %s 应有偏移" % ch)
		expect(not seen.has(s), "通道 seed 撞车（偏移不互异：%s）" % ch)
		seen[s] = true
		expect(s != 7 + 1013, "通道 %s 与植被场偏移串流" % ch)
	# 同通道同 root 恒同值；override 整值替换；未知通道名显式哨兵
	expect_eq(WorldPipeline.channel_seed(42, "hydrology"), WorldPipeline.channel_seed(42, "hydrology"),
		"通道 seed 确定")
	expect_eq(WorldPipeline.channel_seed(42, "decoration", {"decoration": 999}), 999,
		"override 命中即整值替换（通道独立性测试的抓手）")
	expect_eq(WorldPipeline.channel_seed(42, "no_such"), -1, "未知通道 → -1 哨兵")

# ================= 逐阶段诊断（独立摘要可 diff）=================

func test_stage_diagnostics_shape_and_diffable() -> void:
	var w := WorldPipeline.generate_world(WorldTemplateClass.new(), 7)
	expect(w["ok"], "九阶段全开面生成应成功")
	if not w["ok"]:
		return
	var stages: Array = w["stages"]
	expect_eq(stages.size(), 9, "诊断数 = 九阶段")
	var skipped_count := 0
	for d in stages:
		var diag: Dictionary = d
		expect(diag.has("stage") and diag.has("version") and diag.has("summary"),
			"阶段诊断缺规范字段：%s" % str(diag.keys()))
		expect(String(diag["summary"]).length() > 0, "阶段 %s 摘要非空（可 diff 前提）" % diag["stage"])
		if diag.get("skipped", false):
			skipped_count += 1
			expect(String(diag.get("reason", "")).length() > 0,
				"跳过段 %s 须带原因（空集合合法的显式面）" % diag["stage"])
	# WORLD-03/05 未解锁：聚落/势力/道路/表现派生四段跳过；水系默认开 → 5 段实做
	expect_eq(skipped_count, 4, "未解锁阶段数（settlement/allegiance/roads/presentation）")
	var hydro: Variant = _stage_of(stages, "hydrology")
	expect(hydro != null and not hydro.get("skipped", false), "默认模板水系阶段实做")
	expect(hydro != null and hydro.get("post_quantum_valid", false) == true,
		"量化后二次验证保留（WORLD-02 ⑤）")
	# 可 diff：同 seed 两次跑逐阶段诊断 dict 逐字一致
	var w2 := WorldPipeline.generate_world(WorldTemplateClass.new(), 7)
	expect_eq(str(w2["stages"]), str(stages), "同 seed 两次跑逐阶段诊断一致（阶段摘要可 diff）")

# ================= 同 seed 同模板 → world_digest 一致（跑 3 次）=================

func test_same_seed_same_template_world_digest_3_runs() -> void:
	var digests: Array[String] = []
	var map_digests: Array[String] = []
	for i in 3:
		var w := WorldPipeline.generate_world(WorldTemplateClass.new(), 7)
		expect(w["ok"], "第 %d 次生成应成功" % i)
		if not w["ok"]:
			return
		digests.append(String(w["world"].meta["world_digest"]))
		map_digests.append((w["map"] as MapDataClass).digest())
	expect_eq(digests[0], digests[1], "world_digest 一致（run 1 vs 2）")
	expect_eq(digests[1], digests[2], "world_digest 一致（run 2 vs 3）")
	expect_eq(map_digests[0], map_digests[2], "格子表 digest 三次一致")

# ================= 跳过阶段 → 空集合合法 =================

func test_skipped_stages_leave_collections_empty() -> void:
	# 面 1：MapGenerator 退化特例（无模板——一切可选阶段跳过）
	var p := MapGenParamsClass.new()
	var legacy := MapGenerator.generate(p)
	expect(legacy["ok"], "退化特例生成应成功")
	if legacy["ok"]:
		var world: WorldDataClass = legacy["world"]
		expect(world.rivers.is_empty() and world.water_bodies.is_empty()
			and world.links.is_empty() and world.roads.is_empty()
			and world.crossings.is_empty() and world.pois.is_empty(),
			"退化特例 WorldData 全空集合（关闭未实现能力不产伪字段）")
		expect_eq(world.validate(legacy["map"], T_WATER), "", "空世界校验合法")
	# 面 2：九阶段入口 + 模板关停水系
	var t := WorldTemplateClass.new()
	t.hydrology_enabled = false
	var w := WorldPipeline.generate_world(t, 7)
	expect(w["ok"], "模板关停水系应成功（无河世界合法态）")
	if w["ok"]:
		var world2: WorldDataClass = w["world"]
		expect(world2.rivers.is_empty() and world2.water_bodies.is_empty(),
			"关停水系 → rivers/water_bodies 空")
		var hydro: Variant = _stage_of(w["stages"], "hydrology")
		expect(hydro != null and hydro["skipped"], "水系阶段 skipped 诊断（不产伪字段）")
		expect_eq(world2.validate(w["map"], T_WATER), "", "无河世界校验合法")

# ================= 具名通道独立性（改 decoration 不影响 hydrology）=================

func test_decoration_channel_does_not_touch_hydrology() -> void:
	var base := WorldPipeline.generate_world(WorldTemplateClass.new(), 7)
	var deco := WorldPipeline.generate_world(WorldTemplateClass.new(), 7, {"decoration": 99999})
	expect(base["ok"] and deco["ok"], "两次生成应成功")
	if not (base["ok"] and deco["ok"]):
		return
	var base_world: WorldDataClass = base["world"]
	var deco_world: WorldDataClass = deco["world"]
	# 「新增一棵树不消耗前面阶段 RNG」：decoration 通道改 seed，hydrology 产物
	# （河段/水体边序列——世界事实侧摘要）必须逐字节不变
	expect_eq(JSON.stringify(deco_world.to_dict()["rivers"]),
		JSON.stringify(base_world.to_dict()["rivers"]),
		"改 decoration 通道不影响河段摘要（通道独立性锚）")
	expect_eq(JSON.stringify(deco_world.to_dict()["water_bodies"]),
		JSON.stringify(base_world.to_dict()["water_bodies"]),
		"改 decoration 通道不影响水体摘要")
	expect_eq((deco["map"] as MapDataClass).digest(), (base["map"] as MapDataClass).digest(),
		"改 decoration 通道不影响地理/量化产物（map digest）")
	# 反向确证通道机制本身在工作：改 hydrology 通道 seed → 河口挑选序变 → 河网应可
	# 不同（若任何 override 都不改产物，独立性锚将失去分辨力——机制失效报警）
	var hydro_changed := false
	var base_rivers := JSON.stringify(base_world.to_dict()["rivers"])
	for alt in [11, 22, 33]:
		var h := WorldPipeline.generate_world(WorldTemplateClass.new(), 7, {"hydrology": alt})
		if h["ok"] and JSON.stringify((h["world"] as WorldDataClass).to_dict()["rivers"]) != base_rivers:
			hydro_changed = true
			break
	expect(hydro_changed, "改 hydrology 通道 seed 应能改变河网（override 机制生效）")

# ================= 配置冲突显式失败（原因串全列不产半图）=================

func test_config_conflicts_all_listed_no_half_map() -> void:
	var t := WorldTemplateClass.new()
	t.settlement_enabled = true
	t.allegiance_enabled = true
	t.roads_enabled = true
	var w := WorldPipeline.generate_world(t, 7)
	expect(not w["ok"], "开而未解锁应显式失败")
	var err := String(w["error"])
	for stage_name in ["settlement", "allegiance", "roads"]:
		expect(err.contains(stage_name), "冲突串应全列未解锁阶段 %s（got %s）" % [stage_name, err])
	expect(w["map"] == null, "冲突不得产出半图（map=null）")
	expect(w["world"] == null, "冲突不得产出半世界")
	# 配置段失败也可定位（阶段诊断在）
	var stages: Array = w["stages"]
	expect(stages.size() >= 1 and String(stages[0]["stage"]) == "config", "失败诊断首段 = config")

func test_config_invalid_template_params_fail() -> void:
	var t := WorldTemplateClass.new()
	t.width = 0  # 越界（MapGenParams 硬边界经 apply_to_params 同源查）
	var w := WorldPipeline.generate_world(t, 7)
	expect(not w["ok"], "模板尺寸越界应失败")
	expect(String(w["error"]).contains("width"), "失败串指向 width（got %s）" % w["error"])
	var t2 := WorldTemplateClass.new()
	t2.river_flow_level = 0  # 模板专属边界
	var w2 := WorldPipeline.generate_world(t2, 7)
	expect(not w2["ok"], "flow_level=0 应失败（§2.2 ≥1）")
	expect(String(w2["error"]).contains("river_flow_level"), "失败串指向 river_flow_level")

# ================= 版本与模板资源（同源锚）=================

func test_generator_version_bumped_and_in_meta() -> void:
	expect_eq(MapGenerator.GENERATOR_VERSION, 2,
		"GENERATOR_VERSION=2（WORLD-01 管线化 + 植被/地表掩码改名——复现锚显式登记）")
	expect_eq(WorldPipeline.GENERATOR_VERSION, MapGenerator.GENERATOR_VERSION,
		"版本真源驻管线，门面再导出（单一事实源）")
	var legacy := MapGenerator.generate(MapGenParamsClass.new())
	if legacy["ok"]:
		expect_eq(legacy["meta"]["generator_version"], 2, "legacy meta 落 v2")
	var w := WorldPipeline.generate_world(WorldTemplateClass.new(), 7)
	if w["ok"]:
		expect_eq(w["world"].meta["generator_version"], 2, "世界 meta 落 v2")

func test_template_tres_matches_code_defaults() -> void:
	# TerrainStyle 纪律：.tres 与代码默认同源（防漂移——.tres 是 authored 面）
	var default_res := WorldTemplateClass.load_default()
	expect(default_res != null, "默认模板 .tres 应可加载")
	if default_res != null:
		expect_eq(default_res.to_dict(), WorldTemplateClass.make_default().to_dict(),
			"默认 .tres 与代码默认同源")
		expect(default_res.hydrology_enabled, "默认模板水系开")
	var legacy_res := WorldTemplateClass.load_legacy()
	expect(legacy_res != null, "legacy 模板 .tres 应可加载")
	if legacy_res != null:
		expect_eq(legacy_res.to_dict(), WorldTemplateClass.make_legacy().to_dict(),
			"legacy .tres 与代码默认同源")
		expect(not legacy_res.hydrology_enabled, "legacy 模板水系关（退化特例）")
	# 缺文件路径不在此锚（load 对缺文件的引擎 ERROR 噪声会污染门禁日志——
	# 「非预期引擎 ERROR = 异常」口径；null 双态合同沿 MapIO.read_json 先例另测）

# ================= 植被/地表掩码通道保留（修订记录三之 7）=================

func test_vegetation_mask_channel_alive_in_classification() -> void:
	# 通道改名的验收面：林/泥地表分类仍在消费该通道（基线实测 sea=0.4/vfreq=0.4
	# seed=7 → 林 324 格/泥 112 格；此处锚「在用 + 确定」不锚绝对数——绝对数属
	# 生成器版本口径，anchor 漂移会误报）
	var counts := _veg_probe_counts()
	expect(int(counts.get(T_FOREST, 0)) > 0, "林格应出现（植被/地表掩码分类在用）")
	expect(int(counts.get(T_MUD, 0)) > 0, "泥格应出现（第 1 档掩码分类在用）")
	var counts2 := _veg_probe_counts()
	expect_eq(str(counts2), str(counts), "同参数两次掩码分类一致（通道确定性）")

func _veg_probe_counts() -> Dictionary:
	var p := MapGenParamsClass.new()
	p.seed = 7
	p.sea_level = 0.4
	p.vegetation_frequency = 0.4
	var r := MapGenerator.generate(p)
	if not r["ok"]:
		fail("植被探针生成失败：%s" % r["error"])
		return {}
	return r["meta"]["terrain_counts"]

# ================= MapGenerator 退化特例行为不变（独立 oracle）=================

func test_legacy_pipeline_matches_single_pass_oracle() -> void:
	# 04 M1a-T9 细化的四步直读（本测试内独立拼装，不调管线内部函数）：
	# 低频噪声采样 → 全图归一化 → 量化高程+分类 → 逐格对照
	for seed_value in [7, 42]:
		var p := MapGenParamsClass.new()
		p.seed = seed_value
		var r := MapGenerator.generate(p)
		expect(r["ok"], "seed=%d 生成应成功" % seed_value)
		if not r["ok"]:
			continue
		var map: MapDataClass = r["map"]
		var oracle := _oracle_single_pass(p)
		for cell in oracle.cells():
			expect_eq(map.terrain_at(cell), oracle.terrain_at(cell),
				"seed=%d 地形逐格一致 %s（退化特例 = 单遍行为）" % [seed_value, cell])
			expect_eq(map.elevation_at(cell), oracle.elevation_at(cell),
				"seed=%d 高程逐格一致 %s" % [seed_value, cell])
			expect_eq(map.is_passable(cell), oracle.is_passable(cell),
				"seed=%d 通行逐格一致 %s" % [seed_value, cell])

## 单遍 oracle：与生成器同参数接线（FastNoiseLite 双通道：高度场 seed、植被场
## seed+1013——修订记录三之 7 改名不改值）+ 手写归一化/量化/分类。
func _oracle_single_pass(p: MapGenParamsClass) -> MapDataClass:
	var height_noise := FastNoiseLite.new()
	height_noise.seed = p.seed
	height_noise.noise_type = p.noise_type
	height_noise.frequency = p.frequency
	height_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	height_noise.fractal_octaves = p.fractal_octaves
	var veg_noise := FastNoiseLite.new()
	veg_noise.seed = p.seed + 1013
	veg_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	veg_noise.frequency = p.vegetation_frequency
	veg_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	veg_noise.fractal_octaves = 2
	var out := MapDataClass.new(p.width, p.height)
	var cells := out.cells()
	var heights := PackedFloat32Array()
	var masks := PackedFloat32Array()
	heights.resize(cells.size())
	masks.resize(cells.size())
	var h_min := INF
	var h_max := -INF
	var m_min := INF
	var m_max := -INF
	for i in cells.size():
		var w := Hex.axial_to_world(cells[i], 1.0)
		var h := float(height_noise.get_noise_2d(w.x, w.z))
		var mv := float(veg_noise.get_noise_2d(w.x, w.z))
		heights[i] = h
		masks[i] = mv
		h_min = minf(h_min, h)
		h_max = maxf(h_max, h)
		m_min = minf(m_min, mv)
		m_max = maxf(m_max, mv)
	var h_range := h_max - h_min
	var m_range := m_max - m_min
	for i in cells.size():
		var cell := cells[i]
		var n := (heights[i] - h_min) / h_range if h_range > 0.0 else 0.5
		if n < p.sea_level:
			# 水格 = 地形 3 号水槽/高程 0/不可通行（MapData 默认值是草地可通行，
			# 不可裸跳过——oracle 显式落水格三件套）
			out.set_terrain(cell, 3)
			out.set_passable(cell, false)
			continue
		var t := (n - p.sea_level) / (1.0 - p.sea_level)
		var level := clampi(int(t * float(p.elevation_levels)), 0, p.elevation_levels - 1) + 1
		var m := (masks[i] - m_min) / m_range if m_range > 0.0 else 0.5
		var terrain := T_ROCK
		if level < p.elevation_levels:
			if level == 1:
				terrain = T_MUD if m > ORACLE_MUD_THRESHOLD else T_SAND
			else:
				terrain = T_FOREST if m > ORACLE_FOREST_THRESHOLD else 0
		out.set_elevation(cell, level)
		out.set_terrain(cell, terrain)
		out.set_passable(cell, true)
	return out

# ================= 世界 meta（§10 字段集 + world_digest 契约）=================

func test_world_meta_fields_and_digest_contract() -> void:
	var w := WorldPipeline.generate_world(WorldTemplateClass.new(), 7)
	expect(w["ok"], "生成应成功")
	if not w["ok"]:
		return
	var world: WorldDataClass = w["world"]
	var map: MapDataClass = w["map"]
	for k in ["schema_version", "seed", "generator_version", "rules_version",
			"engine_version", "config_digest", "world_digest",
			"attempt_count", "repair_count", "first_pass_valid"]:
		expect(world.meta.has(k), "世界 meta 缺 §10 字段 %s" % k)
	expect_eq(world.meta["seed"], 7, "meta 落 root seed")
	expect(String(world.meta["config_digest"]).length() > 0, "config_digest 非空（模板+参数投影）")
	# world_digest 契约：同世界同值；事实变更即变（敏感面）
	expect_eq(String(world.meta["world_digest"]), world.world_digest(map),
		"meta.world_digest 与重算一致")
	# 事实变更 → 摘要变（敏感面）：从_dict 往返需要 meta 键在场（形状合同），
	# world_digest 本身不读 meta（数据层合同）——故此处保留 meta 只动河段事实
	var facts := world.to_dict()
	var rivers_facts: Array = facts["rivers"]
	if rivers_facts.size() > 0:
		var r0: Dictionary = rivers_facts[0]
		r0["flow_level"] = int(r0["flow_level"]) + 1
		var mutated: Variant = WorldDataClass.from_dict(facts)
		expect(mutated != null, "改动后的世界仍可解析（合法形状）")
		if mutated != null:
			expect((mutated as WorldDataClass).world_digest(map) != world.world_digest(map),
				"河段事实变更 → world_digest 变（摘要敏感面）")

# ---- 辅助 ----

func _stage_of(stages: Array, name: String) -> Variant:
	for d in stages:
		if String(d["stage"]) == name:
			return d
	return null
