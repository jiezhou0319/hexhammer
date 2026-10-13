## test_world_pipeline.gd — T5 WORLD-01 模板和阶段化生成单测（执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-01；主创拍板⑧ Azgaar 管线
##   骨架去气候改造 + 拍板①双噪声唯一路线 + 修订记录三之 5/7）+ T6 S3 regions
##   并列路线锚（docs/M1a-terrain-T6-stylized-execution-plan.md §5——v5 合同
##   变更的同步测试更新见下方「T6 S3 合同变更登记」）
## 覆盖锚（卡表「测试锚」逐条）：
##   - 每阶段独立摘要可 diff（阶段输出规范序摘要 + 阶段版本号；同 seed 两次跑
##     逐阶段诊断 dict 逐字一致）；
##   - 关闭未实现能力不产伪字段：跳过阶段的 WorldData 对应集合为空（empty
##     集合合法锚——退化特例与模板关停两面）；
##   - 同 seed 同模板同引擎构建 → world_digest 一致（跑 3 次）；
##   - 配置冲突显式失败：冲突原因串全列不产半图；
##   - 具名通道独立性：改 decoration 通道不影响 hydrology 输出摘要
##     （「新增一棵树不消耗前面阶段 RNG」，提案随机性纪律）；
##   - 附加面：阶段序固定 + 阶段版本表齐备；GENERATOR_VERSION 锚（复现锚显式
##     登记）；模板 .tres 与代码默认同源（TerrainStyle 同纪律）；植被/地表
##     掩码通道保留且林/泥分类在用（修订记录三之 7——按字面删通道会抽掉现有
##     分类）；MapGenerator 退化特例行为不变 = 独立拼装单遍 oracle 逐格对照
##     （04 M1a-T9 细化的四步直读，不复制管线实现）；T5 完整管线（WORLD-03/05
##     阶段实做 + validation 报告键 + 通道独立性扩面 + locked 格式门 +
##     generation_ms_by_stage 诊断通道 + roads 通道消耗面）；
##   - **T6 S3 regions 路线锚**：确定性（同 seed 同模板 world_digest 3 次一致）、
##     四新通道隔离（layout/region/mountain 分步生效 + isolated_peak 零消耗）、
##     分区结构（两类主导都在/邻接对称/权重千分界/格级归属值域）、过渡带无阶跃
##     （量化图上异区相邻对 Δ ≤ 2 + composition 诊断键）、dual_noise 零漂移
##     （composition 跳过诊断 + regions 参数不选中即不影响产物）、legacy 退化
##     特例逐格不变（独立 oracle，锚不放宽）。
## **T6 S3 合同变更登记（2026-10-13，v5）**——按新合同显式更新既有断言（未删测试）：
##   - 阶段序：九阶段 → **十阶段**（composition 插入 geography 与 quantize 之间），
##     test_stage_order_nine_stages_fixed 更名 test_stage_order_ten_stages_fixed；
##   - 通道集：五通道 → 九通道（追加 layout/region/mountain/isolated_peak 于表尾，
##     既有通道偏移不重排不漂移）；
##   - 默认模板诊断：skipped 段 1 → 2（presentation 恒跳过 + dual_noise 路线下
##     composition 跳过）；
##   - GENERATOR_VERSION：4 → 5（v5 = regions 路线首落 + 新通道 + 新事实集合；
##     dual_noise/legacy 逐格输出不变的登记面）。
## **T6 S4 合同变更登记（2026-10-13，v6）**——按新合同显式更新既有断言（未删测试）：
##   - 阶段序：十阶段 → **十一阶段**（erosion 插入 composition 与 quantize 之间
##     ——提案 :46-57 主线序「连续高度 → 选择性侵蚀 → 六边形投影」），ten→eleven
##     更名；composition 阶段版本 1→2（孤峰地标第四项）、erosion v1 首落；
##   - 通道集：九通道 → 十通道（追加 erosion 于表尾；偏移沿质数序列 911）；
##   - 默认模板诊断：skipped 段 2 → 3（+ dual_noise 路线下 erosion 路线跳过）；
##   - GENERATOR_VERSION：5 → 6（v6 = 孤峰对象 + 选择性侵蚀 + erosion 通道 +
##     WorldData.isolated_peaks + 聚落避让孤峰影响域；dual_noise/legacy 逐格输出
##     不变的登记面）；
##   - test_regions_route_channels_isolated 的 isolated_peak 断言改义：S3 的「override
##     零产物变化」仅在零孤峰图（小图合法态）继续成立；有孤峰图上改峰布点
##     （分区/骨架事实不变的通道分步锚——S4 合同）。
## **T6 S5 合同变更登记（2026-10-13，v7）**——按新合同显式更新既有断言（未删测试）：
##   - GENERATOR_VERSION：6 → 7（v7 = playability v3 区域验收面：模板 regions
##     验收子组 → WorldValidator 区域检查码 REGION_DOMINANCE/CONNECTIVITY/
##     BOUNDARY_STEP/MOUNTAIN_VALLEY/PEAK_AREA_BUDGET + region_metrics 结构化
##     诊断——**dual_noise/legacy 逐格输出与校验报告零漂移**（区域事实恒空 →
##     区域检查零触发）的登记面）；config_digest 键集随模板 S5 验收组扩容；
##   - playability 阶段版本 2 → 3（阶段算法细粒度锚，test_stage_order 断言扩）。
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

func test_stage_order_eleven_stages_fixed() -> void:
	# Azgaar 去气候十一阶段（拍板⑧ + T6 v5 增 composition + v6 增 erosion）：配置→
	# 地理→地貌构图（regions 路线）→选择性侵蚀（S4）→量化→河网水体→聚落→势力→
	# 道路→可玩校验→表现派生——执行顺序即依赖图，顺序是合同
	#（~~十阶段~~ T6 S4 合同变更登记，见文件头注）
	var want: Array[String] = ["config", "geography", "composition", "erosion",
		"quantize", "hydrology", "settlement", "allegiance", "roads", "playability",
		"presentation"]
	expect_eq(WorldPipeline.STAGES, want, "十一阶段固定序（v6：erosion 插入 composition 与 quantize 之间——连续域侵蚀先于量化投影，提案 :46-57）")
	for stage_name in want:
		expect(WorldPipeline.STAGE_VERSIONS.has(stage_name), "阶段版本表缺 %s" % stage_name)
		expect(int(WorldPipeline.STAGE_VERSIONS[stage_name]) >= 1, "阶段 %s 版本 ≥1" % stage_name)
	expect_eq(int(WorldPipeline.STAGE_VERSIONS["composition"]), 2,
		"composition v2（S4 孤峰地标第四项——阶段算法变更的细粒度锚）")
	expect_eq(int(WorldPipeline.STAGE_VERSIONS["erosion"]), 1, "erosion v1（S4 首落）")
	expect_eq(int(WorldPipeline.STAGE_VERSIONS["playability"]), 3,
		"playability v3（S5 区域验收面接入——模板 regions 验收组 → 区域检查码 + region_metrics 诊断）")

func test_named_channels_independent_seeds() -> void:
	# 十具名通道（geography/hydrology/poi/roads/decoration + T6 追加 layout/region/
	# mountain/isolated_peak + S4 追加 erosion 表尾不重排；biome 通道删除——拍板④）
	expect_eq(WorldPipeline.CHANNELS, ["geography", "hydrology", "poi", "roads",
		"decoration", "layout", "region", "mountain", "isolated_peak", "erosion"],
		"具名通道集合（提案随机性纪律 + T6 四通道 + S4 erosion 追加表尾）")
	# 偏移互异且与植被场偏移 1013、细节场偏移 2027、沟壑场偏移 3011 错开
	#（两层随机不串流；值写死保证复现）
	var seen := {}
	for ch in WorldPipeline.CHANNELS:
		var s := WorldPipeline.channel_seed(7, ch)
		expect(s != -1, "通道 %s 应有偏移" % ch)
		expect(not seen.has(s), "通道 seed 撞车（偏移不互异：%s）" % ch)
		seen[s] = true
		expect(s != 7 + 1013, "通道 %s 与植被场偏移串流" % ch)
		expect(s != 7 + 2027, "通道 %s 与细节场偏移串流（T6 regions 细节场）" % ch)
		expect(s != 7 + 3011, "通道 %s 与沟壑场偏移串流（T6 S4 沟壑场）" % ch)
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
	expect_eq(stages.size(), 11, "诊断数 = 十一阶段（v6）")
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
	# 默认模板 = dual_noise 路线（默认值不变 = 现有模板行为零漂移）：恒跳过段 =
	# 表现派生 + dual_noise 路线下的 composition + dual_noise 路线下的 erosion
	#（~~2~~ T6 S4 合同变更登记，见头注）
	expect_eq(skipped_count, 3, "未选用/未解锁阶段数（presentation + dual_noise 下 composition/erosion）")
	var comp_diag: Variant = _stage_of(stages, "composition")
	expect(comp_diag != null and comp_diag.get("skipped", false),
		"dual_noise 默认模板 composition 跳过（不产伪字段——regions 事实集合恒空）")
	expect(String(comp_diag.get("reason", "")).contains("dual_noise"),
		"composition 跳过原因具名路线（got %s）" % str(comp_diag.get("reason", "")))
	var ero_diag: Variant = _stage_of(stages, "erosion")
	expect(ero_diag != null and ero_diag.get("skipped", false),
		"dual_noise 默认模板 erosion 跳过（regions 路线专属——不产伪字段）")
	expect(String(ero_diag.get("reason", "")).contains("regions"),
		"erosion 跳过原因具名路线（got %s）" % str(ero_diag.get("reason", "")))
	var hydro: Variant = _stage_of(stages, "hydrology")
	expect(hydro != null and not hydro.get("skipped", false), "默认模板水系阶段实做")
	expect(hydro != null and hydro.get("post_quantum_valid", false) == true,
		"量化后二次验证保留（WORLD-02 ⑤）")
	for stage_name in ["settlement", "allegiance", "roads"]:
		var s: Variant = _stage_of(stages, stage_name)
		expect(s != null and not s.get("skipped", false), "默认模板 %s 阶段实做（T5 完整管线）" % stage_name)
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
	# 面 2：九阶段入口 + 模板关停水系（聚落/势力/道路仍开——无河世界合法态）
	var t := WorldTemplateClass.new()
	t.hydrology_enabled = false
	var w := WorldPipeline.generate_world(t, 7)
	expect(w["ok"], "模板关停水系应成功（无河世界合法态）")
	if w["ok"]:
		var world2: WorldDataClass = w["world"]
		expect(world2.rivers.is_empty() and world2.water_bodies.is_empty(),
			"关停水系 → rivers/water_bodies 空")
		expect(not world2.pois.is_empty() and not world2.states.is_empty(),
			"关停水系不关停聚落/势力（阶段独立开关）")
		var hydro: Variant = _stage_of(w["stages"], "hydrology")
		expect(hydro != null and hydro["skipped"], "水系阶段 skipped 诊断（不产伪字段）")
		expect_eq(world2.validate(w["map"], T_WATER), "", "无河世界校验合法")

# ================= T5 完整管线（阶段产物 + 校验报告 + 通道独立性扩面）=================

func test_full_pipeline_produces_settlement_allegiance_roads() -> void:
	var t := WorldTemplateClass.new()
	t.width = 24
	t.height = 16
	var w := WorldPipeline.generate_world(t, 7)
	expect(w["ok"], "小图九阶段生成应成功：%s" % str(w.get("error", "")))
	if not w["ok"]:
		return
	var world: WorldDataClass = w["world"]
	expect(world.pois.size() == 9, "POI = 3 主城 + 3 出生区 + 3 资源")
	expect(world.states.size() == 3, "3 势力（拍板⑪）")
	expect_eq(world.cell_owners.size(), 24 * 16, "格级 owner 表全长")
	expect(world.roads.size() >= 1, "道路骨架产出（MST）")
	expect(w.has("validation"), "结果携带结构化校验报告（WORLD-04 面）")
	expect(w["validation"]["ok"], "生成即过校验：%s" % str(
		(w["validation"]["errors"] as Array)[0]["code"] if not w["validation"]["ok"] else ""))
	# 同 seed 通道独立性扩面：改 roads/decoration 通道不影响聚落产物（poi 事实）
	var alt := WorldPipeline.generate_world(t, 7, {"roads": 99999, "decoration": 88888})
	expect(alt["ok"], "通道覆盖跑应成功")
	if alt["ok"]:
		expect_eq(JSON.stringify((alt["world"] as WorldDataClass).to_dict()["pois"]),
			JSON.stringify(world.to_dict()["pois"]),
			"改 roads/decoration 通道不影响聚落事实（通道独立性——道路阶段只消耗改道并列，不上溯聚落）")
		expect_eq(str((alt["world"] as WorldDataClass).cell_owners), str(world.cell_owners),
			"归属分布不受 roads/decoration 通道影响")

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

# ================= roads 通道消耗面（v4：等成本改道——roads_reconnect 载体）=================

func test_roads_channel_changes_road_facts_and_stays_off_upstream() -> void:
	# 反向确证（沿 decoration 测试同构）：改 roads 通道 seed → 等成本并列取舍变 →
	# 道路/桥事实应可变（若任何 override 都不改产物 = roads 通道无消费者——
	# roads_reconnect 修复重跑退化为同输入空转，机制失效报警）；同时上游事实
	# （河网/聚落/格子表）必须逐字节不变（通道独立性保持）
	var t := WorldTemplateClass.new()
	t.width = 24
	t.height = 16
	var base := WorldPipeline.generate_world(t, 7)
	expect(base["ok"], "基线生成应成功")
	if not base["ok"]:
		return
	var base_world: WorldDataClass = base["world"]
	var base_roads := JSON.stringify(base_world.to_dict()["roads"])
	var base_cross := JSON.stringify(base_world.to_dict()["crossings"])
	var roads_changed := false
	for alt_seed in [11, 22, 33]:
		var h := WorldPipeline.generate_world(t, 7, {"roads": alt_seed})
		if not h["ok"]:
			continue
		var hw: WorldDataClass = h["world"]
		if JSON.stringify(hw.to_dict()["roads"]) != base_roads \
				or JSON.stringify(hw.to_dict()["crossings"]) != base_cross:
			roads_changed = true
			# 上游面逐字节不变（改道只动道路阶段）
			expect_eq(JSON.stringify(hw.to_dict()["rivers"]),
				JSON.stringify(base_world.to_dict()["rivers"]),
				"改 roads 通道不影响河段事实")
			expect_eq(JSON.stringify(hw.to_dict()["pois"]),
				JSON.stringify(base_world.to_dict()["pois"]),
				"改 roads 通道不影响 POI 事实")
			expect_eq((h["map"] as MapDataClass).digest(),
				(base["map"] as MapDataClass).digest(),
				"改 roads 通道不影响地理/量化产物（map digest）")
			break
	expect(roads_changed,
		"改 roads 通道 seed 应能改变道路/桥事实（等成本改道消耗面——roads_reconnect 修复载体在起作用）")

# ================= 逐阶段耗时诊断（generation_ms_by_stage，§8.4）=================

func test_generation_ms_by_stage_diagnostic_channel() -> void:
	# WORLD-04 数据合同影响行落码：逐阶段耗时走诊断通道（结果键
	# generation_ms_by_stage），不进 WorldMeta（§10 禁止项——生成耗时类不落
	# 世界事实）；legacy 产物不带此键（键集与旧单遍版一致的行为不变锚）
	var w := WorldPipeline.generate_world(WorldTemplateClass.new(), 7)
	expect(w["ok"], "生成应成功")
	if not w["ok"]:
		return
	expect(w.has("generation_ms_by_stage"), "结果携带逐阶段耗时键（诊断通道）")
	var ms: Dictionary = w["generation_ms_by_stage"]
	for stage_name in WorldPipeline.STAGES:
		expect(ms.has(stage_name), "逐阶段耗时不缺 %s" % stage_name)
		expect(int(ms[stage_name]) >= 0, "阶段 %s 耗时为非负 int ms" % stage_name)
	expect(not (w["world"].meta as Dictionary).has("generation_ms_by_stage"),
		"生成耗时禁入 WorldMeta（§10 禁止项——摘要只锚世界事实）")
	# 阶段诊断 dict 不混入耗时（同 seed stages 可 diff 锚的保持面）
	for d in w["stages"]:
		expect(not (d as Dictionary).has("ms") and not (d as Dictionary).has("generation_ms"),
			"阶段诊断 dict 不携带耗时键（可 diff 锚保持）")
	var legacy := MapGenerator.generate(MapGenParamsClass.new())
	expect(legacy["ok"], "legacy 生成应成功")
	if legacy["ok"]:
		expect(not (legacy as Dictionary).has("generation_ms_by_stage"),
			"legacy 键集不含逐阶段耗时（与旧单遍 map_generator 键集一致）")

# ================= 配置冲突显式失败（原因串全列不产半图）=================

func test_config_conflicts_all_listed_no_half_map() -> void:
	# T5 完整管线后配置冲突面 = 阶段依赖序（势力/道路消费聚落产物——Azgaar
	# 「执行顺序即依赖图」的配置面）；~~开而未解锁~~ UNLOCKED_STAGES 门已随
	# WORLD-03/05 落地拆除（翻案同步改测试纪律）
	var t := WorldTemplateClass.new()
	t.settlement_enabled = false
	t.allegiance_enabled = true
	t.roads_enabled = true
	var w := WorldPipeline.generate_world(t, 7)
	expect(not w["ok"], "依赖倒置应显式失败")
	var err := String(w["error"])
	for stage_name in ["allegiance", "roads"]:
		expect(err.contains(stage_name), "冲突串应全列依赖阶段 %s（got %s）" % [stage_name, err])
	expect(w["map"] == null, "冲突不得产出半图（config 段失败 map=null）")
	expect(w["world"] == null, "冲突不得产出半世界")
	# 配置段失败也可定位（阶段诊断在）
	var stages: Array = w["stages"]
	expect(stages.size() >= 1 and String(stages[0]["stage"]) == "config", "失败诊断首段 = config")

func test_config_rejects_bad_locked_format() -> void:
	# locked v1 格式 = "cell:<非负 int>"（WORLD-04 修复循环消费面）；其他前缀显式拒
	var t := WorldTemplateClass.new()
	t.locked = ["reach:0"]
	var w := WorldPipeline.generate_world(t, 7)
	expect(not w["ok"], "非法 locked 前缀应配置失败")
	expect(String(w["error"]).contains("locked"), "失败串指向 locked（got %s）" % w["error"])
	var t2 := WorldTemplateClass.new()
	t2.locked = ["cell:12"]
	expect_eq(WorldPipeline.generate_world(t2, 7)["ok"], true, "合法 locked 条目通过")
	expect_eq(t2.locked_cells(), [12], "locked_cells 解析（修复注入面）")

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
	expect_eq(MapGenerator.GENERATOR_VERSION, 7,
		"GENERATOR_VERSION=7（T6 S5 区域验收面：playability v3 消费模板 regions 验收子组 → 区域检查码五枚 + region_metrics 结构化诊断——dual_noise/legacy 逐格输出与校验报告零漂移（区域事实恒空），复现锚显式登记）")
	expect_eq(WorldPipeline.GENERATOR_VERSION, MapGenerator.GENERATOR_VERSION,
		"版本真源驻管线，门面再导出（单一事实源）")
	var legacy := MapGenerator.generate(MapGenParamsClass.new())
	if legacy["ok"]:
		expect_eq(legacy["meta"]["generator_version"], 7, "legacy meta 落 v7")
	var w := WorldPipeline.generate_world(WorldTemplateClass.new(), 7)
	if w["ok"]:
		expect_eq(w["world"].meta["generator_version"], 7, "世界 meta 落 v7")

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
		expect_eq(legacy_res.terrain_route, "dual_noise", "legacy 模板钉死 dual_noise（T6 拍板③——不接 regions 路线）")
	# regions 模板（T6 S3+S4）：.tres 与 make_regions 同源 + 路线开关/参数组落位
	var regions_res := WorldTemplateClass.load_regions()
	expect(regions_res != null, "regions 模板 .tres 应可加载")
	if regions_res != null:
		expect_eq(regions_res.to_dict(), WorldTemplateClass.make_regions().to_dict(),
			"regions .tres 与代码默认同源（S4 起调值变更须两处同步）")
		expect_eq(regions_res.terrain_route, "regions", "regions 模板选 regions 路线")
		expect(regions_res.erosion_enabled, "regions 模板侵蚀开（S4 起调——完整形态）")
		expect(regions_res.peak_area_budget_ratio > 0.0, "regions 模板孤峰预算在档（提案 :131 五厘起调）")
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

# ================= T6 S3 regions 路线（v5 新增锚）=================

const Comp := preload("res://scripts/content/terrain_composition.gd")

## regions 测试图（24×16 小图——通道隔离/结构断言用；确定性面另有大图锚）
func _regions_template_small() -> WorldTemplateClass:
	var t := WorldTemplateClass.make_regions()
	t.width = 24
	t.height = 16
	return t

func test_regions_route_deterministic_same_seed_3_runs() -> void:
	# WORLD-01 确定性锚的 regions 面：同 seed 同模板 → world_digest / map digest /
	# 逐阶段诊断 3 次一致（含 composition 摘要与结构化键）
	var digests: Array[String] = []
	var stages_str := ""
	for i in 3:
		var w := WorldPipeline.generate_world(_regions_template_small(), 7)
		expect(w["ok"], "regions 路线第 %d 次生成应成功：%s" % [i, str(w.get("error", ""))])
		if not w["ok"]:
			return
		digests.append(String(w["world"].meta["world_digest"]))
		if i == 0:
			stages_str = str(w["stages"])
		else:
			expect_eq(str(w["stages"]), stages_str, "regions 逐阶段诊断一致（composition 摘要可 diff）")
	expect_eq(digests[0], digests[1], "regions world_digest 一致（run 1 vs 2）")
	expect_eq(digests[1], digests[2], "regions world_digest 一致（run 2 vs 3）")

func test_regions_route_composition_stage_and_facts() -> void:
	# composition 阶段实做面：诊断结构（非 skipped + 结构化边界键）+ 世界事实六集合
	# 非空 + WorldData.validate 全量通过（数据层合同在管线产物上的复核）
	var w := WorldPipeline.generate_world(_regions_template_small(), 7)
	expect(w["ok"], "regions 路线生成应成功")
	if not w["ok"]:
		return
	var world: WorldDataClass = w["world"]
	var comp: Variant = _stage_of(w["stages"], "composition")
	expect(comp != null and not comp.get("skipped", false), "regions 模板 composition 实做")
	expect(comp != null and comp.get("boundary_max_delta", -1.0) >= 0.0,
		"composition 诊断携带 boundary_max_delta 结构化键（无阶跃留证面）")
	expect(world.terrain_regions.size() >= 2, "分区 ≥2 区域（模板硬边界保证两类主导）")
	expect(not world.mountain_ranges.is_empty(), "主山系产出（群山区骨架）")
	expect(not world.ridge_branches.is_empty(), "支脉产出")
	expect(not world.cell_regions.is_empty() and world.cell_regions.size() == 24 * 16,
		"格级归属表全长")
	expect_eq(world.validate(w["map"], T_WATER), "", "regions 世界全量校验合法（分区/骨架/格级事实）")

func test_regions_route_structure_adjacency_weights() -> void:
	# 分区结构锚（提案 §宏观分区：空间连贯 + 邻接记录 + 连续权重场）：
	# 两类主导都在且有可观面积、邻接对称、权重千分界、格级归属值域
	var w := WorldPipeline.generate_world(_regions_template_small(), 7)
	expect(w["ok"], "生成应成功")
	if not w["ok"]:
		return
	var world: WorldDataClass = w["world"]
	var mountain_regions := 0
	var plain_regions := 0
	for rg in world.terrain_regions:
		if rg.dominant_landform == WorldDataClass.TerrainRegion.DominantLandform.MOUNTAINS:
			mountain_regions += 1
		else:
			plain_regions += 1
	expect(mountain_regions >= 1 and plain_regions >= 1,
		"两类主导地貌都在（群山 %d / 平原 %d——提案首期两类）" % [mountain_regions, plain_regions])
	for rg in world.terrain_regions:
		expect(not rg.core_cells.is_empty(), "region %d 核心非空（分区事实至少有核心）" % rg.region_id)
		for aid in rg.adjacency:
			var other := world.region_by_id(aid)
			expect(other != null, "region %d 邻接 %d 可解析" % [rg.region_id, aid])
			if other != null:
				expect(other.adjacency.has(rg.region_id),
					"邻接对称：region %d 列 %d，后者须回列（提案 :63）" % [rg.region_id, aid])
	# 权重场：千分界内 + 大片两档主导（mw≥0.7 与 mw≤0.3 都有可观格数——
	# 「宏观可读性」目标的机器面：大片群山区与平原区同时在场）
	var hi := 0
	var lo := 0
	var valid_ids := {}
	for rg in world.terrain_regions:
		valid_ids[rg.region_id] = true
	for i in world.cell_mountain_weights.size():
		var wv: int = world.cell_mountain_weights[i]
		expect(wv >= 0 and wv <= 1000, "权重千分界 0..1000（got %d @%d）" % [wv, i])
		if wv >= 700:
			hi += 1
		if wv <= 300:
			lo += 1
		expect(world.cell_regions[i] >= 0 and valid_ids.has(world.cell_regions[i]),
			"格级归属值域 = region_id（got %d @%d）" % [world.cell_regions[i], i])
	expect(hi >= 20, "大片群山主导区在场（mw≥0.7 共 %d 格）" % hi)
	expect(lo >= 20, "大片平原主导区在场（mw≤0.3 共 %d 格）" % lo)

func test_regions_route_no_boundary_step() -> void:
	# 过渡带无阶跃（提案验收表「边界过渡」:271 的连续层前置检查）：
	# 量化图上**异区相邻对**（cell_region 不同）的高程差 ≤ 2（elevation_levels=4
	# 下 Δ3 = 全幅跳变 = 阶跃；山区内 Δ2 属地貌起伏合法档）+ composition 诊断
	# boundary_max_delta ≤ 全图 max_neighbor_delta（边界不比内部更陡）
	var w := WorldPipeline.generate_world(_regions_template_small(), 7)
	expect(w["ok"], "生成应成功")
	if not w["ok"]:
		return
	var map: MapDataClass = w["map"]
	var world: WorldDataClass = w["world"]
	var worst := 0
	var checked := 0
	for cell in map.cells():
		var i := map.index_of(cell)
		for nb in map.neighbors_existing(cell):
			var j := map.index_of(nb)
			if j <= i:
				continue
			if world.cell_regions[i] == world.cell_regions[j]:
				continue
			checked += 1
			worst = maxi(worst, absi(map.elevation_at(cell) - map.elevation_at(nb)))
	expect(checked > 0, "异区相邻对应存在（分区边界非空）")
	expect(worst <= 2, "分区边界无阶跃（异区相邻对最大 Δ=%d ≤ 2——区域编号不制造高度断缝）" % worst)
	var comp: Variant = _stage_of(w["stages"], "composition")
	expect(float(comp["boundary_max_delta"]) <= float(comp["max_neighbor_delta"]) + 1e-6,
		"连续场诊断：边界最大邻差不大于全图最大邻差（got %s / %s）"
			% [str(comp["boundary_max_delta"]), str(comp["max_neighbor_delta"])])
	expect(float(comp["boundary_max_delta"]) < 0.5,
		"连续场边界邻差有界（got %s——混合场在过渡带连续）" % str(comp["boundary_max_delta"]))

func test_regions_route_channels_isolated() -> void:
	# T6 四新通道 + S4 erosion 通道的分步隔离锚（提案 :221 八通道 + T6 §2.3）：
	# - isolated_peak：只动孤峰布点（分区/骨架/格级事实不变——S4 合同；小图
	#   零孤峰 = override 零变化的合法态特例）；
	# - mountain：只动骨架（regions 事实不变、cell_regions/weights 不变）；
	# - region：只动地貌指派（布点/核心格不变——core_cells 逐字节一致）；
	# - layout：动布点（分区几何可变）。
	# erosion 通道的隔离锚见 test_s4_erosion_channel_isolation（侵蚀只在开态消费）。
	var t := _regions_template_small()
	var base := WorldPipeline.generate_world(t, 7)
	expect(base["ok"], "基线生成应成功")
	if not base["ok"]:
		return
	var base_world: WorldDataClass = base["world"]
	# isolated_peak（小图 = 零孤峰合法态：override 零产物变化——S3 锚在 S4 语义
	# 下的合法特例；有孤峰图上的「只动峰」面在 60×40 大图锚 test_s4_peaks_* 覆盖）
	expect(base_world.isolated_peaks.is_empty(), "24×16 小图零孤峰（间距盘装不进小图平原——提案 :82 合法态）")
	var iso := WorldPipeline.generate_world(t, 7, {"isolated_peak": 99999})
	expect(iso["ok"], "isolated_peak override 跑应成功")
	if iso["ok"]:
		expect_eq((iso["world"] as WorldDataClass).meta["world_digest"],
			base_world.meta["world_digest"],
			"零孤峰图上改 isolated_peak 通道零产物变化（合法态特例——通道隔离保持）")
	# mountain：分区事实不变、骨架可变
	var mtn_changed := false
	for alt in [11, 22, 33]:
		var m := WorldPipeline.generate_world(t, 7, {"mountain": alt})
		if not m["ok"]:
			continue
		var mw: WorldDataClass = m["world"]
		expect_eq(JSON.stringify(mw.to_dict()["terrain_regions"]),
			JSON.stringify(base_world.to_dict()["terrain_regions"]),
			"改 mountain 通道不影响分区事实（三步通道隔离：骨架通道不回溯分区）")
		expect_eq(JSON.stringify(mw.to_dict()["cell_regions"]),
			JSON.stringify(base_world.to_dict()["cell_regions"]),
			"改 mountain 通道不影响格级归属/权重")
		if JSON.stringify(mw.to_dict()["mountain_ranges"]) \
				!= JSON.stringify(base_world.to_dict()["mountain_ranges"]):
			mtn_changed = true
			break
	expect(mtn_changed, "改 mountain 通道应能改变骨架（override 机制在骨架面生效——失效报警）")
	# region：布点/核心不变、地貌指派可变（core_cells 逐字节一致的结构面）
	var reg_changed := false
	for alt in [11, 22, 33]:
		var rr := WorldPipeline.generate_world(t, 7, {"region": alt})
		if not rr["ok"]:
			continue
		var rw: WorldDataClass = rr["world"]
		var base_cores := []
		for rg in base_world.terrain_regions:
			base_cores.append(rg.core_cells)
		var now_cores := []
		for rg in rw.terrain_regions:
			now_cores.append(rg.core_cells)
		expect_eq(JSON.stringify(now_cores), JSON.stringify(base_cores),
			"改 region 通道不影响布点/核心格（layout 通道独立——分区几何不动）")
		var base_lf := []
		for rg in base_world.terrain_regions:
			base_lf.append(rg.dominant_landform)
		var now_lf := []
		for rg in rw.terrain_regions:
			now_lf.append(rg.dominant_landform)
		if str(now_lf) != str(base_lf) or JSON.stringify(rw.to_dict()["cell_mountain_weights"]) \
				!= JSON.stringify(base_world.to_dict()["cell_mountain_weights"]):
			reg_changed = true
			break
	expect(reg_changed, "改 region 通道应能改变地貌指派/权重场（指派面生效——失效报警）")

func test_dual_noise_route_ignores_regions_params() -> void:
	# 并列路线正交性锚：不选 regions = 与双噪声路线同输出（regions/孤峰/侵蚀
	# 参数组全不消费——S4 组扩面后复核）
	var a := WorldTemplateClass.new()
	var b := WorldTemplateClass.new()
	b.region_count = 9
	b.region_min_core_cells = 200
	b.region_transition_width = 0.9
	b.mountain_range_count = 7
	b.mountain_branch_count = 8
	b.peak_area_budget_ratio = 0.5
	b.peak_influence_radius = 5
	b.peak_height = 900
	b.peak_spacing_radius_scale = 3.0
	b.erosion_enabled = true
	b.erosion_mountain_slope = 0.9
	b.erosion_valley = 0.5
	b.erosion_plain = 0.4
	b.erosion_transition = 0.6
	b.erosion_coast = 0.3
	b.erosion_max_step = 0.9
	b.erosion_plain_relief_budget = 0.5
	var ra := WorldPipeline.generate_world(a, 7)
	var rb := WorldPipeline.generate_world(b, 7)
	expect(ra["ok"] and rb["ok"], "两次生成应成功")
	if not (ra["ok"] and rb["ok"]):
		return
	expect_eq((rb["map"] as MapDataClass).digest(), (ra["map"] as MapDataClass).digest(),
		"dual_noise 路线不读 regions/孤峰/侵蚀参数（正交性——默认值不变 = 现有行为零漂移）")
	expect_eq(JSON.stringify((rb["world"] as WorldDataClass).to_dict()["terrain_regions"]),
		"[]", "dual_noise 路线分区事实恒空（不产伪字段）")
	expect((rb["world"] as WorldDataClass).isolated_peaks.is_empty(),
		"dual_noise 路线孤峰事实恒空（不产伪字段——S4）")

func test_regions_route_legacy_face_unchanged() -> void:
	# 拍板③ legacy 锚：模板 schema 扩展（terrain_route + regions 组）后，
	# generate_legacy 逐格输出与独立单遍 oracle 仍逐格一致（本文件 oracle 的
	# regions 扩容面复核——legacy 模板钉死 dual_noise、composition 跳过）
	var p := MapGenParamsClass.new()
	p.seed = 7
	var r := WorldPipeline.generate_legacy(p)
	expect(r["ok"], "legacy 生成应成功")
	if not r["ok"]:
		return
	var oracle := _oracle_single_pass(p)
	var map: MapDataClass = r["map"]
	for cell in oracle.cells():
		expect_eq(map.elevation_at(cell), oracle.elevation_at(cell),
			"legacy 高程逐格一致 %s（v5 后置复核）" % cell)

func test_composition_inverse_distance_weights_oracle() -> void:
	# 纯函数 oracle（TerrainComposition.inverse_distance_weights 手算锚）：
	# w = 1/(1+(d/T)²) 逐项归一。d=[0,1] T=1 → raw [1, 0.5] → [2/3, 1/3]；
	# d=[2,2] → 对称 [0.5, 0.5]；d=[0,3] T=1 → raw [1, 0.1] → [10/11, 1/11]
	var a: Array[float] = Comp.inverse_distance_weights(_ints([0, 1]), 1)
	expect_almost_eq(a[0], 2.0 / 3.0, 1e-9, "反距离权重 [0,1] T=1 → 首项 2/3")
	expect_almost_eq(a[1], 1.0 / 3.0, 1e-9, "反距离权重 [0,1] T=1 → 次项 1/3")
	var b: Array[float] = Comp.inverse_distance_weights(_ints([2, 2]), 1)
	expect_almost_eq(b[0], 0.5, 1e-9, "等距对称 → 均分 0.5")
	expect_almost_eq(b[1], 0.5, 1e-9, "等距对称 → 均分 0.5")
	var c: Array[float] = Comp.inverse_distance_weights(_ints([0, 3]), 1)
	expect_almost_eq(c[0], 10.0 / 11.0, 1e-9, "[0,3] T=1 → 10/11")
	expect_almost_eq(c[1], 1.0 / 11.0, 1e-9, "[0,3] T=1 → 1/11")
	# 归一化恒等：Σ=1（任意距离表）
	for dists in [[0, 1, 2], [1, 5, 9, 14], [0, 0, 4]]:
		var ws: Array[float] = Comp.inverse_distance_weights(_ints(dists), 3)
		var total := 0.0
		for wv in ws:
			total += wv
			expect(wv >= 0.0 and wv <= 1.0, "权重项 ∈ [0,1]")
		expect_almost_eq(total, 1.0, 1e-9, "权重归一 Σ=1（%s）" % str(dists))

## int 列表 → Array[int]（字面量传参的显式类型面——预载脚本 typed 形参不收窄）
func _ints(src: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(src)
	return out

