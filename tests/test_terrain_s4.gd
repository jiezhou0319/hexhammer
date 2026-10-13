## test_terrain_s4.gd — T6 S4 孤峰对象 + 选择性侵蚀单测（执行方案
##   docs/M1a-terrain-T6-stylized-execution-plan.md §6 + 提案
##   docs/evidence/风格化地图生成方案_群山平原与派系适配_修订版.md
##   §群山与孤峰的不同职责 :73-82 / §选择性侵蚀 :100-109 / §首期调参起点 :131）
## 拆分登记（沿 S1「整世界重测试拆分/缓存」授权）：S4 的 60×40 完整形态
##   （孤峰 + 侵蚀）整世界用例单文件承载——test_world_pipeline.gd 保持契约锚
##   （阶段序/通道集/版本号/诊断计数）+ 快速小图面，本文件吃重运行时
##   （60×40 单次全管线 ~3s；单文件运行时须留 90s 看门狗 ≥2× 余量的 S1 口径）。
## 覆盖锚（T6 §6 验收逐条）：
##   - 孤峰逐峰检查违规数为零（峰间/避让主山系/避让出生落点三面间距 +
##     影响面积预算 ≤ 有效平原 × 比例——提案验收表「孤峰稀疏性」:270，
##     期望值由 HexMath 原语独立推导，不复制生成器实现）；
##   - 小图零孤峰 = 合法态（提案 :82；24×16 间距盘装不进平原的结构化结果）；
##   - 侵蚀关闭 = 阶段跳过（不触碰连续高度）+ dual_noise 路线守卫（regions
##     专属——erosion_enabled=true 对双噪声路线零漂移）；
##   - 侵蚀机制生效（开/关两态量化高程有差）+ 水陆分区与连通分量逐格不变
##     （复查「连通」的构造保证：只刻不堆 + 极值格不侵蚀 + 海面阈守护）；
##   - 复查回退留痕：post_violations 恒 0、减弱/回退计数落诊断（确定性记录，
##     不换 seed 掩盖——提案 :109）；
##   - 通道隔离：isolated_peak 只动峰布点（分区/骨架/格级事实逐字节不变）、
##     erosion 开态只进侵蚀阶段（composition 诊断逐字一致）、关态零消耗；
##   - TerrainErosion/TerrainComposition 纯函数手算 oracle（强度档/沟壑通道/
##     刻蚀/下限钳/回退减半与清零/圆锥核/最小间距换算）。
## oracle 原则：期望距离/预算/档位全部手算或 HexMath 原语独立推导；同 seed
##   确定性面沿用 test_world_pipeline.gd 的 regions 路线锚（本文件不重复跑 3 次
##   全管线——拆分后断言面不缩水、运行面不重复）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapConnectivity := preload("res://scripts/content/map_connectivity.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const WorldTemplateClass := preload("res://scripts/core/data/world_template.gd")
const WorldPipeline := preload("res://scripts/content/world_pipeline.gd")
const Comp := preload("res://scripts/content/terrain_composition.gd")
const Erosion := preload("res://scripts/content/terrain_erosion.gd")

const T_WATER := 3

## regions 完整形态模板（60×40——孤峰非零、侵蚀开；S4 样本图）
func _full() -> WorldTemplateClass:
	return WorldTemplateClass.make_regions()

## regions 小图模板（24×16——零孤峰合法态样本）
func _small() -> WorldTemplateClass:
	var t := WorldTemplateClass.make_regions()
	t.width = 24
	t.height = 16
	return t

func _cell(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))

func _stage_of(stages: Array, name: String) -> Dictionary:
	for d in stages:
		if String(d["stage"]) == name:
			return d
	return {}

# ================= 孤峰逐峰检查（提案验收表「孤峰稀疏性」）=================

func test_s4_peaks_per_peak_constraints_60x40() -> void:
	# 峰间距 / 避让主山系 / 避让出生落点 / 影响面积预算——生成后逐峰复查，
	# 违规数为零；含全量 WorldData.validate（数据层结构面复核）
	var w := WorldPipeline.generate_world(_full(), 7)
	expect(w["ok"], "60×40 完整形态生成应成功：%s" % str(w.get("error", "")))
	if not w["ok"]:
		return
	var map: MapDataClass = w["map"]
	var world: WorldDataClass = w["world"]
	var peaks := world.isolated_peaks
	expect(not peaks.is_empty(), "60×40 应产出孤峰（有效平原充足——非零面锚）")
	expect_eq(world.validate(map, T_WATER), "", "含孤峰世界全量校验合法")
	var t := _full()
	var spacing := Comp.peak_min_spacing(t.peak_influence_radius, t.peak_spacing_radius_scale)
	# 预算分母独立推导：有效平原 = 群山权重 ≤ EFFECTIVE_PLAIN_WEIGHT_MAX 的陆格
	var effective_plain := 0
	for i in map.cell_count():
		if float(world.cell_mountain_weights[i]) / 1000.0 <= Comp.EFFECTIVE_PLAIN_WEIGHT_MAX \
				and map.elevation_at(_cell(map, i)) > 0:
			effective_plain += 1
	var budget := int(floor(float(effective_plain) * t.peak_area_budget_ratio))
	var skeleton_set := {}
	for mr in world.mountain_ranges:
		for cid in mr.spine_cells:
			skeleton_set[cid] = true
	for br in world.ridge_branches:
		for cid in br.cells:
			skeleton_set[cid] = true
	var anchors: Array[int] = []
	for p in world.pois:
		if p.kind == WorldDataClass.POIData.Kind.SETTLEMENT:
			anchors.append(p.cell_id)
	# 逐峰单遍扫全图（峰数 × 格数——间距三面与影响盘同遍算出）
	var influence_total := 0
	for pk in peaks:
		var center := _cell(map, pk.cell_id)
		for other in peaks:
			if other.peak_id >= pk.peak_id:
				continue  # 峰对只查一次
			expect(Hex.distance(center, _cell(map, other.cell_id)) >= spacing,
				"峰 %d↔%d 间距 ≥ %d（峰间避让）" % [pk.peak_id, other.peak_id, spacing])
		var footprint := 0
		for i in map.cell_count():
			var d := Hex.distance(center, _cell(map, i))
			if d <= pk.influence_radius:
				footprint += 1
			if skeleton_set.has(i):
				expect(d >= spacing,
					"峰 %d 距骨架格 %d = %d ≥ %d（避让主山系——主山系内部突出峰不自动算孤峰的对象归属面）" \
						% [pk.peak_id, i, d, spacing])
			if anchors.has(i):
				expect(d >= spacing,
					"峰 %d 距出生落点 %d = %d ≥ %d（避让出生落点，提案 :78）" \
						% [pk.peak_id, i, d, spacing])
		influence_total += footprint
	expect(influence_total <= budget,
		"孤峰总影响面积 %d ≤ 预算 %d（有效平原 %d × %s，提案 :131）" \
			% [influence_total, budget, effective_plain, str(t.peak_area_budget_ratio)])
	# composition 诊断结构化键（逐峰复查的取数面——「摘要串 + 结构化键」先例）
	var comp: Dictionary = _stage_of(w["stages"], "composition")
	expect(int(comp["isolated_peak_count"]) == peaks.size(),
		"composition 诊断 isolated_peak_count 与事实一致（got %d want %d）" \
			% [int(comp["isolated_peak_count"]), peaks.size()])
	# 侵蚀诊断留痕（复查回退的确定性记录面）
	var ero: Dictionary = _stage_of(w["stages"], "erosion")
	expect(not ero.get("skipped", false), "完整形态 erosion 阶段实做")
	expect_eq(int(ero["post_violations"]), 0, "侵蚀后复查零违例（确定性减弱/回退收敛）")
	expect(int(ero["weakened_cells"]) >= 0 and int(ero["rollback_cells"]) >= 0,
		"减弱/回退计数在诊断留痕（非负 int）")

func test_s4_zero_peaks_small_map_legal() -> void:
	# 小图零孤峰 = 合法态（提案 :82「小地图可以没有孤峰」——间距盘装不进小图
	# 平原的结构化结果，非配置特例）；零峰世界校验仍合法
	var w := WorldPipeline.generate_world(_small(), 7)
	expect(w["ok"], "小图 regions 生成应成功")
	if not w["ok"]:
		return
	expect((w["world"] as WorldDataClass).isolated_peaks.is_empty(),
		"24×16 小图零孤峰（合法态锚）")
	expect_eq((w["world"] as WorldDataClass).validate(w["map"], T_WATER), "",
		"零孤峰世界校验合法")

# ================= 侵蚀开关：回退锚 / 路线守卫 / 水陆分区不变量 =================

func test_s4_erosion_toggle_partition_and_route_guard() -> void:
	# 回退锚：erosion_enabled=false → 阶段跳过（不触碰连续高度）；开/关两态
	# 量化高程有差（机制生效——空转报警）而水陆分区与连通分量逐格不变
	#（复查「连通」的构造保证）；dual_noise + 侵蚀开 = 路线跳过且逐格一致
	var t_off := _full()
	t_off.erosion_enabled = false
	var a := WorldPipeline.generate_world(t_off, 7)
	var b := WorldPipeline.generate_world(_full(), 7)
	expect(a["ok"] and b["ok"], "侵蚀开/关两跑应成功")
	if not (a["ok"] and b["ok"]):
		return
	var ero_off: Dictionary = _stage_of(a["stages"], "erosion")
	expect(ero_off.get("skipped", false), "侵蚀关 → erosion 阶段 skipped")
	expect(String(ero_off.get("reason", "")).contains("未启用"),
		"侵蚀关跳过原因具名模板开关（got %s）" % str(ero_off.get("reason", "")))
	var am: MapDataClass = a["map"]
	var bm: MapDataClass = b["map"]
	var elev_diff := 0
	var water_diff := 0
	for cell in am.cells():
		if am.elevation_at(cell) != bm.elevation_at(cell):
			elev_diff += 1
		if am.is_passable(cell) != bm.is_passable(cell):
			water_diff += 1
	expect(elev_diff > 0, "侵蚀开态改变量化高程（%d 格——机制生效，空转报警）" % elev_diff)
	expect_eq(water_diff, 0, "水陆分区逐格不变（侵蚀不造新水/不填旧水——只刻不堆 + 极值格不动 + 海面阈守护）")
	var conn_a := MapConnectivity.check(am)
	var conn_b := MapConnectivity.check(bm)
	expect_eq(conn_b["component_count"], conn_a["component_count"],
		"连通分量数不变（陆格集相同 ⇒ 分量恒同——复查「连通」的机器面）")
	expect_eq(conn_b["passable_total"], conn_a["passable_total"], "通行格总数不变")
	# dual_noise 路线守卫：erosion_enabled 对双噪声路线零漂移（24×16 快档——
	# 路线跳过与尺寸无关；dual_noise 生成远快于 regions）
	var d1 := WorldTemplateClass.new()
	d1.width = 24
	d1.height = 16
	var d2 := WorldTemplateClass.new()
	d2.width = 24
	d2.height = 16
	d2.erosion_enabled = true
	var ra := WorldPipeline.generate_world(d1, 7)
	var rb := WorldPipeline.generate_world(d2, 7)
	expect(ra["ok"] and rb["ok"], "dual_noise 两跑应成功")
	if ra["ok"] and rb["ok"]:
		var ero2: Dictionary = _stage_of(rb["stages"], "erosion")
		expect(ero2.get("skipped", false), "dual_noise + 侵蚀开 → erosion 路线跳过")
		expect(String(ero2.get("reason", "")).contains("regions"),
			"路线跳过原因具名 regions 专属（got %s）" % str(ero2.get("reason", "")))
		expect_eq((rb["map"] as MapDataClass).digest(), (ra["map"] as MapDataClass).digest(),
			"dual_noise + 侵蚀开 = 与关逐格一致（不产伪消耗）")

# ================= 通道隔离（isolated_peak 只动峰 / erosion 只进侵蚀阶段）=================

func test_s4_isolated_peak_channel_moves_only_peaks() -> void:
	# 60×40 有孤峰图上 override → 分区/骨架/格级事实逐字节不变、孤峰事实可变
	#（机制生效——失效报警）；小图零孤峰 = override 零变化（合法态特例，
	# test_world_pipeline.gd 的 channels 锚另面）
	var t := _full()
	var base := WorldPipeline.generate_world(t, 7)
	expect(base["ok"], "基线生成应成功")
	if not base["ok"]:
		return
	var base_world: WorldDataClass = base["world"]
	expect(not base_world.isolated_peaks.is_empty(), "样本图须有孤峰（本锚非空面）")
	var changed := false
	for alt in [11, 22, 33]:
		var r := WorldPipeline.generate_world(t, 7, {"isolated_peak": alt})
		if not r["ok"]:
			continue
		var rw: WorldDataClass = r["world"]
		expect_eq(JSON.stringify(rw.to_dict()["terrain_regions"]),
			JSON.stringify(base_world.to_dict()["terrain_regions"]),
			"改 isolated_peak 通道不影响分区事实（四步通道隔离）")
		expect_eq(JSON.stringify(rw.to_dict()["mountain_ranges"]),
			JSON.stringify(base_world.to_dict()["mountain_ranges"]),
			"改 isolated_peak 通道不影响主山系/支脉事实")
		expect_eq(JSON.stringify(rw.to_dict()["cell_regions"]),
			JSON.stringify(base_world.to_dict()["cell_regions"]),
			"改 isolated_peak 通道不影响格级归属/权重")
		if JSON.stringify(rw.to_dict()["isolated_peaks"]) \
				!= JSON.stringify(base_world.to_dict()["isolated_peaks"]):
			changed = true
			break
	expect(changed, "改 isolated_peak 通道应能改变孤峰布点（通道消耗面生效——失效报警）")

func test_s4_erosion_channel_isolation() -> void:
	# erosion 通道消耗面 = 沟壑场 seed：开态 override → composition 诊断逐字一致
	#（上游不受侵蚀通道影响）+ 量化图可变；关态 override → 全产物逐字节一致
	#（关态零消耗）。首段兼做侵蚀确定性锚：同 seed 双跑 → 侵蚀诊断逐字一致 +
	# world_digest/map digest 一致（WORLD-01 确定性锚的 S4 完整形态面；24×16
	# 三跑面在 test_world_pipeline.gd 的 regions 确定性锚——erosion 阶段在其中
	# 同样实跑）
	var t := _full()
	var base := WorldPipeline.generate_world(t, 7)
	expect(base["ok"], "基线应成功")
	if not base["ok"]:
		return
	var base2 := WorldPipeline.generate_world(t, 7)
	expect(base2["ok"], "确定性复核跑应成功")
	if base2["ok"]:
		expect_eq((base2["map"] as MapDataClass).digest(), (base["map"] as MapDataClass).digest(),
			"同 seed 双跑量化图一致（侵蚀确定性——map digest）")
		expect_eq((base2["world"] as WorldDataClass).meta["world_digest"],
			(base["world"] as WorldDataClass).meta["world_digest"],
			"同 seed 双跑世界事实一致（侵蚀确定性——world digest）")
		expect_eq(str(_stage_of(base2["stages"], "erosion")),
			str(_stage_of(base["stages"], "erosion")),
			"同 seed 双跑侵蚀诊断逐字一致（carved/weaken/rollback 计数确定——侵蚀确定性留痕面）")
	var changed := false
	for alt in [11, 22, 33]:
		var r := WorldPipeline.generate_world(t, 7, {"erosion": alt})
		if not r["ok"]:
			continue
		expect_eq(str(_stage_of(r["stages"], "composition")),
			str(_stage_of(base["stages"], "composition")),
			"改 erosion 通道不影响 composition 诊断（通道只进侵蚀阶段）")
		if (r["map"] as MapDataClass).digest() != (base["map"] as MapDataClass).digest():
			changed = true
			break
	expect(changed, "侵蚀开态改 erosion 通道应能改变量化图（沟壑图样更替——机制生效）")
	# 关态零消耗（24×16 快档——关态跳过与尺寸无关）
	var t0 := _small()
	t0.erosion_enabled = false
	var x := WorldPipeline.generate_world(t0, 7)
	var y := WorldPipeline.generate_world(t0, 7, {"erosion": 424242})
	expect(x["ok"] and y["ok"], "关态两跑应成功")
	if x["ok"] and y["ok"]:
		expect_eq((y["map"] as MapDataClass).digest(), (x["map"] as MapDataClass).digest(),
			"侵蚀关态改 erosion 通道零产物变化（关态零消耗锚）")
		expect_eq((y["world"] as WorldDataClass).meta["world_digest"],
			(x["world"] as WorldDataClass).meta["world_digest"],
			"侵蚀关态世界事实一致")

# ================= TerrainErosion 纯函数手算 oracle =================

func test_s4_erosion_units_hand_computed() -> void:
	# 档位/通道/刻蚀/下限/回退五面——独立于噪声场的确定性面
	var map := MapDataClass.new(4, 1)
	# gully_channel：0.5 断档、上半带线性、上下界钳制
	expect_almost_eq(Erosion.gully_channel(0.5), 0.0, 1e-9, "通道 0.5 → 0（下半带零刻蚀）")
	expect_almost_eq(Erosion.gully_channel(0.75), 0.5, 1e-9, "通道 0.75 → 0.5")
	expect_almost_eq(Erosion.gully_channel(1.0), 1.0, 1e-9, "通道 1 → 1")
	expect_almost_eq(Erosion.gully_channel(0.25), 0.0, 1e-9, "通道 0.25 → 0（钳下界）")
	expect_almost_eq(Erosion.gully_channel(2.0), 1.0, 1e-9, "通道越界钳上界")
	# carve_field：4×1 高度 [0,0.2,0.2,0.4] → 坡 [0,0.2,0.2,0.2]；
	# 强度 [0.5,0.5,0,0]、gully 全 1 → d = [0, -0.1, 0, 0]
	var heights := PackedFloat32Array([0.0, 0.2, 0.2, 0.4])
	var strengths := PackedFloat32Array([0.5, 0.5, 0.0, 0.0])
	var gully := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	var d := Erosion.carve_field(map, heights, strengths, gully)
	expect_almost_eq(d[1], -0.1, 1e-6, "刻蚀 = -强度×通道×坡（0.5×1×0.2；float32 场容差）")
	expect_almost_eq(d[2], 0.0, 1e-9, "强度 0 格零刻蚀")
	expect(d[0] <= 0.0 and d[3] <= 0.0, "刻蚀恒非正（只刻不堆）")
	# resolve_rollback：差分预算 0.15，d=[-0.2,0] → 违例对两端各减半一轮收敛
	#（Jacobi 口径：违例对的两侧格都是违例格——差分是边的性质，两侧同责同修）
	var floors := PackedFloat32Array()
	floors.resize(4)
	floors.fill(-10.0)
	var resolved := Erosion.resolve_rollback(map, PackedFloat32Array([-0.2, 0.0, 0.0, 0.0]),
		floors, heights, 0.15)
	var rd: PackedFloat32Array = resolved["delta"]
	expect_almost_eq(rd[0], -0.1, 1e-6, "差分 0.2 > 预算 0.15 → 减半一轮 → -0.1（确定性减弱）")
	expect_almost_eq(rd[1], 0.0, 1e-9, "零刻蚀格减半仍零（对端同修不改值）")
	expect_eq(int(resolved["stats"]["weakened_cells"]), 2, "减弱留痕 2 格（违例对两端）")
	expect_eq(int(resolved["stats"]["post_violations"]), 0, "复查零违例")
	# 预算更紧（0.04）：减半三轮 -0.025 后收敛
	var resolved2 := Erosion.resolve_rollback(map, PackedFloat32Array([-0.2, 0.0, 0.0, 0.0]),
		floors, heights, 0.04)
	var rd2: PackedFloat32Array = resolved2["delta"]
	expect_almost_eq(rd2[0], -0.025, 1e-6, "紧预算三轮减半 -0.025（|d| ≤ 预算即收敛）")
	# 极紧预算（0.01）：减半轮尽仍违 → 整格回退 0（确定性回退规则）
	var resolved3 := Erosion.resolve_rollback(map, PackedFloat32Array([-0.2, 0.0, 0.0, 0.0]),
		floors, heights, 0.01)
	var rd3: PackedFloat32Array = resolved3["delta"]
	expect_almost_eq(rd3[0], 0.0, 1e-9, "减半轮尽仍违 → 整格回退 0（不换 seed 掩盖）")
	expect_eq(int(resolved3["stats"]["rollback_cells"]), 2, "回退留痕 2 格（违例对两端）")
	# 下限钳：floor 只负向绑定——陆格（h=0.2）floor 0.15 → d ≥ −0.05；
	# floor 在格上方（水格位）不抬升（侵蚀只刻不堆红线）
	var floors2 := PackedFloat32Array([-10.0, 0.15, -10.0, -10.0])
	var resolved4 := Erosion.resolve_rollback(map, PackedFloat32Array([0.0, -0.2, 0.0, 0.0]),
		floors2, heights, 0.15)
	var rd4: PackedFloat32Array = resolved4["delta"]
	expect_almost_eq(rd4[1], -0.05, 1e-6, "陆格 floor 0.15 钳 d ≥ 0.15−0.2 = −0.05（不刻破下限）")
	var floors3 := PackedFloat32Array()
	floors3.resize(4)
	floors3.fill(0.5)
	var resolved5 := Erosion.resolve_rollback(map, PackedFloat32Array([0.0, 0.0, 0.0, 0.0]),
		floors3, heights, 0.15)
	var rd5: PackedFloat32Array = resolved5["delta"]
	for v in rd5:
		expect_almost_eq(v, 0.0, 1e-9, "全零刻蚀 + 高 floor → 全零（floor 在格上方不抬升——水格不被钳出海面）")

func test_s4_erosion_strength_tiers_oracle() -> void:
	# 区域强度档（提案 :104-107 落码面）：群山/过渡/平原三档 + 谷底与海岸上限
	#（min 语义）+ 水格/极值格恒 0。手造 WorldData + 高度场（无生成器）
	var map := MapDataClass.new(6, 1)
	var world := WorldDataClass.empty()
	var rg := WorldDataClass.TerrainRegion.new()
	rg.region_id = 0
	rg.dominant_landform = WorldDataClass.TerrainRegion.DominantLandform.MOUNTAINS
	rg.core_cells.append(0)
	world.terrain_regions.append(rg)
	var vl := WorldDataClass.ValleyData.new()
	vl.valley_id = 0
	vl.range_id = 0
	vl.cells.append(2)
	world.valleys.append(vl)
	# 权重千分：[800, 500, 800, 100, 800, 800]（过渡 500 / 平原 100 / 谷底在 2）
	world.cell_mountain_weights = [800, 500, 800, 100, 800, 800]
	# 高度：min 0 / max 0.875（float32 可精确表示——极值判定按位比较的前提）；
	# sea 0.3 → sea_floor 0.2625；col4 = 0.875（极值 → 强度 0）
	var heights := PackedFloat32Array([0.0, 0.4, 0.4, 0.4, 0.875, 0.28])
	var s := Erosion.strengths_for(map, heights, 0.0, 0.875, world, {
		"sea_level": 0.3, "mountain_slope": 0.3, "valley": 0.06,
		"plain": 0.0, "transition": 0.12, "coast": 0.1})
	var eps := 1e-6  # 强度场存 float32（PackedFloat32Array）——容差按 float32 精度
	expect_almost_eq(float(s[0]), 0.0, eps, "水格（h=0 < sea_floor）强度 0")
	expect_almost_eq(float(s[1]), 0.12, eps, "过渡带（mw=500‰）→ transition 档")
	expect_almost_eq(float(s[2]), 0.06, eps, "谷底格取 min(山档 0.3, 谷 0.06)——宽谷限蚀")
	expect_almost_eq(float(s[3]), 0.0, eps, "平原档默认关（提案 :106）")
	expect_almost_eq(float(s[4]), 0.0, eps, "全图极值格恒 0（归一化分母不变的前提）")
	expect_almost_eq(float(s[5]), 0.1, eps, "贴海岸格（n=0.32 ≤ sea+0.05）取 min(山档, 海岸 0.1)")

func test_s4_cone_falloff_and_spacing_oracle() -> void:
	# 圆锥轮廓核 + 最小间距换算的手算 oracle（TerrainComposition 纯函数面）
	expect_almost_eq(Comp.cone_falloff(0, 2), 1.0, 1e-9, "锥顶 1")
	expect_almost_eq(Comp.cone_falloff(2, 2), 1.0 / 9.0, 1e-9, "d=r → (1/(r+1))² = 1/9")
	expect_almost_eq(Comp.cone_falloff(3, 2), 0.0, 1e-9, "d=r+1 → 0（锥底平滑接地）")
	expect_almost_eq(Comp.cone_falloff(1, 2), 4.0 / 9.0, 1e-9, "d=1 → (1−1/3)² = 4/9")
	expect_eq(Comp.peak_min_spacing(2, 2.0), 4, "间距 = ceil(半径 × 倍数)（默认档 2×2.0 → 4）")
	expect_eq(Comp.peak_min_spacing(3, 1.2), 4, "ceil(3.6) = 4")
	expect_eq(Comp.peak_min_spacing(2, 0.5), 2, "倍数 <1 收钳到半径（间距不小于影响半径）")
