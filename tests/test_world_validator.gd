## test_world_validator.gd — T5 WORLD-04 校验、有限修复与 seed 银行单测
##   （执行方案 docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-04 + 数据合同
##   草案 §11 错误码清单 + 提案门禁矩阵/最小诊断输出 + seed 纪律）
##   + T6 S5 区域验收面（docs/M1a-terrain-T6-stylized-execution-plan.md §7 +
##   提案 §区域限制 :111-134 / §验收与评估 :265-276——区域检查码五枚逐码
##   fixture、region_metrics 手算 oracle、阈值「有配置才判」门、生成图通过
##   样本与可 diff 诊断、regions 银行组三档二十 seed 形状与跑完口径）
## 覆盖锚（卡表「测试锚」逐条）：
##   - 错误指向具体 cell/link：**每个错误码至少一个 fixture 断言 explanation 含
##     定位**（§11 七码 + 扩格码 + T6 S5 区域五码逐个落）；
##   - 修复不动 locked：锁定区修复前后逐位一致（owner 锚定/锚定 POI 原样重发/
##     道路禁入三面 + attempts_trace 双世界对照）；
##   - attempt 上限：第 5 次尝试拒绝（4×4 物理不可行样本恒 4 次即止）；
##   - 失败图入库：银行跑失败样例落 FAILED_FIXTURE_DIR/world + .world.json 伴生
##     （可加载复验）；
##   - 确定性：银行 seed 重跑 world_digest 一致（3 次）；
##   - 成功世界保存→重载仍过同样校验；
##   - 初始 owner 与运行时征服状态分离（重生成不覆盖存档进度）；
##   - **T6 S5**：区域检查码逐码违规 fixture（explanation 含不合格区域编号/越阶
##     对格/峰中心——提案 :267）、合格 fixture 零违规 + region_metrics 手算
##     oracle、区域检查仅凭 opts 阈值开通（ROAD-01「有配置才判」）、生成图
##     （60×40 seed 7）区域验收零违规 + playability 诊断 region_metrics 同 seed
##     逐字可 diff + dual_noise 不落键（不产伪字段）、regions 银行组三档二十
##     seed + smoke 跑完计数口径（退出码语义不变的数据面）。
## oracle 原则：错误定位断言 = 手工 fixture（期望的 cell/poi id 由构造侧给出）；
## 修复/银行断言 = 世界事实摘要（to_dict/world_digest——不复制实现内部状态）；
## 区域指标断言 = 构造侧手算占比/片数/盘径（不抄 region_metrics 实现）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const WorldTemplateClass := preload("res://scripts/core/data/world_template.gd")
const WorldPipeline := preload("res://scripts/content/world_pipeline.gd")
const WorldValidator := preload("res://scripts/content/world_validator.gd")
const MapIOClass := preload("res://scripts/content/map_io.gd")
const RiverFix := preload("res://tools/river_fixtures.gd")
const SeedBank := preload("res://tools/seed_bank.gd")

const T_GRASS := 0
const T_WATER := 3

func _cell_of(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))

## 全陆小图（12×8：高程 1/可通行——POI/路网 fixture 底图）
func _land_map() -> MapDataClass:
	var map := MapDataClass.new(12, 8)
	for cell in map.cells():
		map.set_elevation(cell, 1)
		map.set_terrain(cell, T_GRASS)
	return map
	# passable 默认全 1（MapData._init 填充）——无需显式

## SETTLEMENT+SPAWN_ZONE 一对（锚 = offset 坐标）。
func _add_spawn_pair(world: WorldDataClass, map: MapDataClass, at: Vector2i) -> void:
	var anchor := map.index_of(Hex.axial_of(at))
	var p := WorldDataClass.POIData.new()
	p.poi_id = world.pois.size()
	p.kind = WorldDataClass.POIData.Kind.SETTLEMENT
	p.cell_id = anchor
	p.footprint_cells = [anchor]
	p.role = "capital"
	world.pois.append(p)
	var z := WorldDataClass.POIData.new()
	z.poi_id = world.pois.size()
	z.kind = WorldDataClass.POIData.Kind.SPAWN_ZONE
	z.cell_id = anchor
	z.footprint_cells = [anchor]
	for d in 6:
		z.footprint_cells.append(map.index_of(Hex.neighbor(Hex.axial_of(at), d)))
	z.footprint_cells.sort()
	z.role = "spawn_zone"
	world.pois.append(z)

func _add_resource(world: WorldDataClass, map: MapDataClass, at: Vector2i) -> void:
	var cid := map.index_of(Hex.axial_of(at))
	var p := WorldDataClass.POIData.new()
	p.poi_id = world.pois.size()
	p.kind = WorldDataClass.POIData.Kind.RESOURCE
	p.cell_id = cid
	p.footprint_cells = [cid]
	p.role = "core_resource"
	world.pois.append(p)

func _first_error(report: Dictionary) -> Dictionary:
	return (report["errors"] as Array)[0]

func _codes_of(report: Dictionary) -> Array:
	var out: Array = []
	for e in report["errors"]:
		out.append(e["code"])
	return out

# ================= 错误形状 + 码表 =================

func test_report_shape_and_error_code_list() -> void:
	var map := _land_map()
	var world := WorldDataClass.empty()
	var report := WorldValidator.validate_report(map, world, {})
	expect(report["ok"], "空世界零错误")
	expect_eq((report["errors"] as Array).size(), 0, "errors 空数组")
	# §11 七码「先包括」清单在册（+ 本校验器两个结构性扩格码）
	for code in ["NO_VALID_SPAWN", "RESOURCE_UNREACHABLE", "RIVER_CYCLE",
			"NO_RIVER_OUTLET", "BRIDGE_ENDPOINT_INVALID", "ROAD_NETWORK_DISCONNECTED",
			"LOCKED_CONSTRAINT_CONFLICT"]:
		expect(WorldValidator.ERROR_CODES.has(code), "§11 错误码 %s 在册" % code)
	# T6 S5 区域验收五码在册（扩格码清单的可枚举面）
	for code in ["REGION_DOMINANCE", "REGION_CONNECTIVITY", "REGION_BOUNDARY_STEP",
			"MOUNTAIN_VALLEY", "PEAK_AREA_BUDGET"]:
		expect(WorldValidator.ERROR_CODES.has(code), "T6 S5 区域错误码 %s 在册" % code)
	# 错误对象固定五键（{code, cell_ids, link_ids, constraint_id, explanation}）
	var map2 := _land_map()
	var world2 := WorldDataClass.empty()
	_add_spawn_pair(world2, map2, Vector2i(5, 3))
	var bad := map2.index_of(Hex.axial_of(Vector2i(6, 3)))
	map2.set_elevation(Hex.axial_of(Vector2i(6, 3)), 0)
	map2.set_passable(Hex.axial_of(Vector2i(6, 3)), false)
	var report2 := WorldValidator.validate_report(map2, world2, {})
	expect(not report2["ok"], "不可通行 footprint 应报错")
	if report2["ok"]:
		return
	for e in report2["errors"]:
		var keys := (e as Dictionary).keys()
		keys.sort()
		expect_eq(str(keys), str(["cell_ids", "code", "constraint_id", "explanation", "link_ids"]),
			"错误对象固定五键")

# ================= 逐码 fixture（explanation 含定位）=================

func test_no_valid_spawn_points_at_impassable_cell() -> void:
	var map := _land_map()
	var world := WorldDataClass.empty()
	_add_spawn_pair(world, map, Vector2i(5, 3))
	var bad := map.index_of(Hex.axial_of(Vector2i(6, 3)))
	map.set_elevation(Hex.axial_of(Vector2i(6, 3)), 0)
	map.set_passable(Hex.axial_of(Vector2i(6, 3)), false)
	var report := WorldValidator.validate_report(map, world, {})
	expect(not report["ok"], "出生 footprint 含不可通行格 → 报错")
	var hit := false
	for e in report["errors"]:
		if e["code"] == "NO_VALID_SPAWN":
			hit = true
			expect((e["cell_ids"] as Array).has(bad),
				"NO_VALID_SPAWN cell_ids 指向不可通行格 %d" % bad)
			expect(str(e["explanation"]).contains(str(bad)),
				"explanation 含格定位：%s" % e["explanation"])
	expect(hit, "NO_VALID_SPAWN 错误在列")

func test_resource_unreachable_points_at_poi_and_cell() -> void:
	var map := _land_map()
	var world := WorldDataClass.empty()
	_add_spawn_pair(world, map, Vector2i(2, 2))
	_add_resource(world, map, Vector2i(9, 5))
	# 资源点环水（六邻全水 = 平地口径不可达——湖格当墙）
	var res := Hex.axial_of(Vector2i(9, 5))
	for d in 6:
		var nb := Hex.neighbor(res, d)
		map.set_elevation(nb, 0)
		map.set_terrain(nb, T_WATER)
		map.set_passable(nb, false)
	var report := WorldValidator.validate_report(map, world, {})
	expect(not report["ok"], "孤岛资源应报 RESOURCE_UNREACHABLE")
	var hit := false
	for e in report["errors"]:
		if e["code"] == "RESOURCE_UNREACHABLE":
			hit = true
			var res_id := map.index_of(res)
			expect((e["cell_ids"] as Array).has(res_id),
				"cell_ids 指向资源格 %d" % res_id)
			expect(str(e["explanation"]).contains("poi 2"),
				"explanation 含 poi id 定位（资源 = poi 2——出生对占 0/1）：%s" % e["explanation"])
	expect(hit, "RESOURCE_UNREACHABLE 错误在列")

func test_river_cycle_reported_with_reach_location() -> void:
	# 角点级环样本（绕单格六边——沿 test_water_rivers 同族 fixture）
	var map := _land_map()
	var x := Hex.axial_of(Vector2i(5, 3))
	var ring := RiverFix.around_cell_chain(map, x, 6)
	var world := WorldDataClass.empty()
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = ring
	reach.water_levels = [1, 1, 1, 1, 1, 1]
	reach.bed_level = 0
	world.rivers.append(reach)
	var report := WorldValidator.validate_report(map, world, {})
	expect(not report["ok"], "环样本应报错")
	var err := _first_error(report)
	expect_eq(err["code"], "RIVER_CYCLE", "错误码 = RIVER_CYCLE（环先于对账检出）")
	expect(str(err["explanation"]).contains("reach 0"),
		"explanation 含 reach 定位：%s" % err["explanation"])

func test_no_river_outlet_reported_with_reach_location() -> void:
	var map := _land_map()
	var chain := RiverFix.around_cell_chain(map, Hex.axial_of(Vector2i(4, 3)), 3)
	var world := WorldDataClass.empty()
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = chain
	reach.water_levels = [1, 1, 1]
	reach.bed_level = 0
	reach.water_body_id = 5  # 不可解析引用（无水体表）
	world.rivers.append(reach)
	var report := WorldValidator.validate_report(map, world, {})
	expect(not report["ok"], "无出口河应报错")
	var err := _first_error(report)
	expect_eq(err["code"], "NO_RIVER_OUTLET", "错误码 = NO_RIVER_OUTLET")
	expect(str(err["explanation"]).contains("reach 0"),
		"explanation 含 reach 定位：%s" % err["explanation"])

func test_bridge_endpoint_invalid_reported_with_crossing_location() -> void:
	# 合法河 + 水体 + 桥头 Δ 超限（max_bridge_bank_delta=0、两岸高差 1）
	var map := _land_map()
	var world := WorldDataClass.empty()
	var chain := RiverFix.around_cell_chain(map, Hex.axial_of(Vector2i(4, 3)), 2)
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = chain
	reach.water_levels = [0, 0]
	reach.bed_level = -1
	reach.water_body_id = 0
	world.rivers.append(reach)
	var body := WorldDataClass.WaterBodyData.new()
	body.water_body_id = 0
	body.kind = WorldDataClass.WaterBodyData.Kind.LAKE
	body.water_level = 0
	body.member_cells = [chain[chain.size() - 1].x]
	body.inlet_links = [chain[chain.size() - 1]]
	body.terminal = true
	world.water_bodies.append(body)
	map.set_elevation(_cell_of(map, chain[0].y), 2)  # 桥头 Δ = 1 > 0
	var c := WorldDataClass.CrossingData.new()
	c.crossing_id = 0
	c.river_edge = chain[0]
	c.bank_a = chain[0].x
	c.bank_b = chain[0].y
	world.crossings.append(c)
	var report := WorldValidator.validate_report(map, world, {
		"max_bridge_bank_delta": 0,
	})
	expect(not report["ok"], "桥头 Δ 超限应报错")
	var hit := false
	for e in report["errors"]:
		if e["code"] == "BRIDGE_ENDPOINT_INVALID":
			hit = true
			expect(str(e["explanation"]).contains("crossing 0"),
				"explanation 含 crossing 定位：%s" % e["explanation"])
			expect(str(e["explanation"]).contains(str(chain[0].x))
				and str(e["explanation"]).contains(str(chain[0].y)),
				"explanation 含两岸格定位")
	expect(hit, "BRIDGE_ENDPOINT_INVALID 错误在列")

func test_road_network_disconnected_points_at_settlements() -> void:
	var map := _land_map()
	var world := WorldDataClass.empty()
	_add_spawn_pair(world, map, Vector2i(2, 3))
	_add_spawn_pair(world, map, Vector2i(8, 3))
	_add_spawn_pair(world, map, Vector2i(5, 6))
	# 一条路只连前两个聚落（第三聚落孤悬）
	var road := WorldDataClass.RoadData.new()
	road.road_id = 0
	road.cells = [
		map.index_of(Hex.axial_of(Vector2i(2, 3))),
		map.index_of(Hex.axial_of(Vector2i(3, 3))),
		map.index_of(Hex.axial_of(Vector2i(4, 3))),
		map.index_of(Hex.axial_of(Vector2i(5, 3))),
		map.index_of(Hex.axial_of(Vector2i(6, 3))),
		map.index_of(Hex.axial_of(Vector2i(7, 3))),
		map.index_of(Hex.axial_of(Vector2i(8, 3))),
	]
	world.roads.append(road)
	for i in road.cells.size() - 1:
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = WorldDataClass.link_id_of(road.cells[i], road.cells[i + 1])
		lk.road_id = 0
		world.links.append(lk)
	var report := WorldValidator.validate_report(map, world, {
		"require_road_network": true,
	})
	expect(not report["ok"], "三聚落二连应报 ROAD_NETWORK_DISCONNECTED")
	var hit := false
	var lone := map.index_of(Hex.axial_of(Vector2i(5, 6)))
	for e in report["errors"]:
		if e["code"] == "ROAD_NETWORK_DISCONNECTED":
			hit = true
			expect((e["cell_ids"] as Array).has(lone),
				"cell_ids 含孤悬聚落格 %d" % lone)
			expect(str(e["explanation"]).contains("2 个道路连通分量"),
				"explanation 含分量明细定位：%s" % str(e["explanation"]).substr(0, 140))
	expect(hit, "ROAD_NETWORK_DISCONNECTED 错误在列")

func test_locked_constraint_conflict_points_at_cell_and_road() -> void:
	var map := _land_map()
	var world := WorldDataClass.empty()
	var road := WorldDataClass.RoadData.new()
	road.road_id = 3
	road.cells = [map.index_of(Hex.axial_of(Vector2i(4, 3))),
		map.index_of(Hex.axial_of(Vector2i(5, 3)))]
	world.roads.append(road)
	var locked := road.cells[0]
	var report := WorldValidator.validate_report(map, world, {
		"locked_cells": [locked],
	})
	expect(not report["ok"], "道路占锁定格应报 LOCKED_CONSTRAINT_CONFLICT")
	var hit := false
	for e in report["errors"]:
		if e["code"] == "LOCKED_CONSTRAINT_CONFLICT":
			hit = true
			expect_eq(e["constraint_id"], "cell:%d" % locked,
				"constraint_id 指向锁定约束（cell:N）")
			expect((e["cell_ids"] as Array).has(locked), "cell_ids 指向锁定格")
			expect(str(e["explanation"]).contains("道路 3")
				and str(e["explanation"]).contains(str(locked)),
				"explanation 含道路与格定位：%s" % e["explanation"])
	expect(hit, "LOCKED_CONSTRAINT_CONFLICT 错误在列")

func test_poi_footprint_conflict_points_at_cell() -> void:
	# 出生区 footprint 触河岸锚点格（格边口径「河床占格」的格级代理）：
	# 锚与东邻之间的单边河——两端（锚 + 东邻）都是河岸锚点格且都在 footprint 内
	var map := _land_map()
	var world := WorldDataClass.empty()
	_add_spawn_pair(world, map, Vector2i(5, 3))
	var anchor := Hex.axial_of(Vector2i(5, 3))
	var nb := Hex.neighbor(anchor, 0)
	var edge := WorldDataClass.link_id_of(map.index_of(anchor), map.index_of(nb))
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = [edge]  # 单边链（源边——WATER-01 fixture 族合法形状）
	reach.water_levels = [0]
	reach.bed_level = -1
	world.rivers.append(reach)
	var flank := map.index_of(nb)
	var anchor_id := map.index_of(anchor)
	var report := WorldValidator.validate_report(map, world, {})
	expect(not report["ok"], "footprint 触河岸应报 POI_FOOTPRINT_CONFLICT")
	var hit := false
	for e in report["errors"]:
		if e["code"] == "POI_FOOTPRINT_CONFLICT":
			hit = true
			# 错误指向河边任一岸格（升序 footprint 首个命中——锚或东邻皆合法定位）
			var ids: Array = e["cell_ids"]
			expect(ids.has(flank) or ids.has(anchor_id),
				"cell_ids 指向冲突格（岸边 ∈ {%d,%d}）" % [anchor_id, flank])
			var located := false
			for cid in ids:
				if str(e["explanation"]).contains(str(cid)):
					located = true
			expect(located, "explanation 含格定位：%s" % e["explanation"])
	expect(hit, "POI_FOOTPRINT_CONFLICT 错误在列")

# ================= 修复循环（attempt 上限 / 成功路径 / meta）=================

func test_attempt_cap_fifth_attempt_rejected() -> void:
	# 4×4 物理不可行（零内点 → 出生候选恒空）：4 次 attempt 即止、第 5 次拒绝
	var t := WorldTemplateClass.new()
	t.width = 4
	t.height = 4
	var r := WorldPipeline.generate_validated(t, 7)
	expect(not r["ok"], "物理不可行应明确失败（不伪造达标）")
	expect_eq((r["attempts_trace"] as Array).size(), 4,
		"尝试数 = 4（第 5 次尝试拒绝——WORLD-04 ② 上限）")
	expect((r["repair_actions"] as Array).size() >= 1, "修复动作序列非空")
	for a in r["repair_actions"]:
		expect(["hydrology_redraw", "settlement_repick", "roads_reconnect"].has(a),
			"修复动作 ∈ 卡表三件（got %s）" % a)
	expect(str(r["error"]).contains("第 5 次尝试拒绝") or str(r["error"]).contains("上限"),
		"失败串言明上限拒绝：%s" % str(r["error"]).substr(0, 120))
	# 失败产物仍是世界（部分事实留证——失败样例入库的数据面）
	expect(r["map"] != null and r["world"] != null, "失败留部分产物（不产半图仅指配置失败）")

func test_repair_success_meta_and_first_pass() -> void:
	# 8×5 微图 seed 7：直跑出生区排列失败，修复循环「换出生候选带」三次重抽后
	# 第 4 次 attempt 成功——attempt/repair/first_pass 落 WorldMeta（§10）。
	# attempts=4 是本图确定性结果（生成器版本纪律：漂移 = GENERATOR_VERSION 变更）
	var t := WorldTemplateClass.new()
	t.width = 8
	t.height = 5
	var r := WorldPipeline.generate_validated(t, 7)
	expect(r["ok"], "8×5 微图经修复循环应成功（出生带重抽）：%s" % str(r.get("error", "")).substr(0, 140))
	if not r["ok"]:
		return
	var meta: Dictionary = r["world"].meta
	expect_eq(int(meta["attempt_count"]), 4, "attempt_count = 4（三次 settlement_repick 后成功）")
	expect_eq(int(meta["repair_count"]), 3, "repair_count = 3（每次修复恰一次重跑）")
	expect_eq(bool(meta["first_pass_valid"]), false, "first_pass_valid = false（重试后成功）")
	expect_eq(meta["generator_version"], WorldPipeline.GENERATOR_VERSION,
		"meta 落生成器版本（复现锚）")
	# 修复动作序列 = 卡表三件之「换出生候选带」（NO_VALID_SPAWN → settlement_repick）
	var actions: Array = r["repair_actions"]
	expect_eq(actions.size(), 3, "修复动作数 = 3")
	for a in actions:
		expect_eq(a, "settlement_repick", "修复动作 = 换出生候选带（got %s）" % a)

func test_repair_locked_region_bit_identical() -> void:
	# 修复不动 locked（锚定注入原语面）：无锁世界 A → 锁定 A 的出生锚格 →
	# bump poi 通道重跑（修复循环同款注入）→ B：锁定格 owner 逐位一致、
	# 锚定出生区原样重发（同格同 footprint 同 role 同 id）、道路/新 POI 不入锁定格
	var t := WorldTemplateClass.new()
	t.width = 24
	t.height = 16
	var a := WorldPipeline.generate_world(t, 7)
	expect(a["ok"], "无锁基线应成功")
	if not a["ok"]:
		return
	var wa: WorldDataClass = a["world"]
	var zones := wa.pois_of_kind(WorldDataClass.POIData.Kind.SPAWN_ZONE)
	expect(zones.size() == 3, "3 出生区")
	if zones.size() != 3:
		return
	# 锁定 = 出生锚（主城格）：锚是路网必经端点（validator 豁免锚格），但锚的
	# 归属/POI 事实必须逐位保持——修复后重抽其余槽
	var locked_cells: Array[int] = [zones[0].cell_id]
	var owner_pins := {}
	for cid in locked_cells:
		owner_pins[cid] = wa.cell_owners[cid]
	# 槽序号锚定（spawn_anchor_slots = {槽: 锚格}——settlement_generator 按槽落位，
	# role/poi_id 由槽序号派生；与 world_pipeline._repair_ctx_of 组装面同构）
	var ctx := {"locked_cells": locked_cells, "owner_pins": owner_pins,
		"pinned": {"spawn_anchor_slots": {0: zones[0].cell_id}, "resource_cells": []}}
	var b := WorldPipeline.generate_world(t, 7,
		{"poi": WorldPipeline.channel_seed(7, "poi") + 7919}, ctx)
	expect(b["ok"], "锁定重跑应成功：%s" % str(b.get("error", "")).substr(0, 140))
	if not b["ok"]:
		return
	var wb: WorldDataClass = b["world"]
	for cid in locked_cells:
		expect_eq(wb.cell_owners[cid], wa.cell_owners[cid],
			"锁定格 %d owner 修复前后逐位一致（owner_pins 锚定）" % cid)
	# 锚定出生区原样重发（槽位保持）
	var zb := wb.pois_of_kind(WorldDataClass.POIData.Kind.SPAWN_ZONE)
	var found: WorldDataClass.POIData = null
	for z in zb:
		if z.cell_id == zones[0].cell_id:
			found = z
	expect(found != null, "锚定出生区仍在（同格重发）")
	if found != null:
		expect_eq(str(found.footprint_cells), str(zones[0].footprint_cells),
			"锚定出生区 footprint 原样（槽位保持）")
		expect_eq(found.role, zones[0].role, "锚定出生区 role 原样")
		expect_eq(found.poi_id, zones[0].poi_id, "锚定出生区 poi_id 保持")
	# 道路禁入锁定格（唯一豁免 = 主城锚——路网必经端点；本测试锁的恰是锚，
	# 故断言面改走 validator：LOCKED_CONSTRAINT_CONFLICT 为零）
	var report := WorldValidator.validate_report(b["map"], wb, {
		"locked_cells": locked_cells, "require_road_network": true,
		"max_road_delta": 1, "max_bridge_bank_delta": 2,
	})
	expect(report["ok"], "锁定约束校验零错误（got %s）"
		% str(_first_error(report)["code"] if not report["ok"] else ""))
	# 通道 bump 生效面：非锚定槽确实重抽了（否则锚定机制失去分辨力）
	var za_ids := []
	for z in zones:
		za_ids.append(z.cell_id)
	var moved := false
	for z in zb:
		if z.cell_id == zones[0].cell_id:
			continue
		if not za_ids.has(z.cell_id):
			moved = true
	expect(moved, "非锚定出生槽经 bump 重抽（修复注入在起作用——机制分辨力）")

func test_repair_pin_nonfirst_slot_keeps_role_and_id() -> void:
	# 非首槽锚定反例（评审 counterexample_pin.gd 转正）：锁定 zones[1]（槽 1 =
	# AI 主城）+ poi 通道 bump 重跑——修复前锚定槽被压到 si=0，poi_id 3→0、
	# role ai_capital→player_capital（主城阵营翻转）；修复后槽位/格/poi_id/role
	# 逐位保持，非锚定槽照常重抽
	var t := WorldTemplateClass.new()
	t.width = 24
	t.height = 16
	var a := WorldPipeline.generate_world(t, 7)
	expect(a["ok"], "无锁基线应成功")
	if not a["ok"]:
		return
	var wa: WorldDataClass = a["world"]
	var zones := wa.pois_of_kind(WorldDataClass.POIData.Kind.SPAWN_ZONE)
	var settlements := wa.pois_of_kind(WorldDataClass.POIData.Kind.SETTLEMENT)
	expect(zones.size() == 3 and settlements.size() == 3, "3 出生槽齐备")
	if zones.size() != 3 or settlements.size() != 3:
		return
	expect_eq(settlements[1].role, "ai_capital", "基线槽 1 = AI 主城（拍板⑪）")
	var locked_cells: Array[int] = [zones[1].cell_id]
	var owner_pins := {}
	for cid in locked_cells:
		owner_pins[cid] = wa.cell_owners[cid]
	var ctx := {"locked_cells": locked_cells, "owner_pins": owner_pins,
		"pinned": {"spawn_anchor_slots": {1: zones[1].cell_id}, "resource_cells": []}}
	var b := WorldPipeline.generate_world(t, 7,
		{"poi": WorldPipeline.channel_seed(7, "poi") + 7919}, ctx)
	expect(b["ok"], "锁定槽 1 重跑应成功：%s" % str(b.get("error", "")).substr(0, 140))
	if not b["ok"]:
		return
	var wb: WorldDataClass = b["world"]
	# 锚定槽原样重发：SPAWN_ZONE 与 SETTLEMENT 的格/poi_id/role 全保持（poi_id
	# 由槽序号派生 = 槽位保持的直接面）
	var zone_hit: WorldDataClass.POIData = null
	var settle_hit: WorldDataClass.POIData = null
	for p in wb.pois:
		if p.cell_id == zones[1].cell_id and p.kind == WorldDataClass.POIData.Kind.SPAWN_ZONE:
			zone_hit = p
		if p.cell_id == zones[1].cell_id and p.kind == WorldDataClass.POIData.Kind.SETTLEMENT:
			settle_hit = p
	expect(zone_hit != null, "锚定 SPAWN_ZONE 同格重发")
	if zone_hit != null:
		expect_eq(zone_hit.poi_id, zones[1].poi_id, "锚定 SPAWN_ZONE poi_id 保持（槽位不漂）")
		expect_eq(zone_hit.role, zones[1].role, "锚定 SPAWN_ZONE role 保持")
	expect(settle_hit != null, "锚定 SETTLEMENT 同格重发")
	if settle_hit != null:
		expect_eq(settle_hit.poi_id, settlements[1].poi_id,
			"锚定 SETTLEMENT poi_id 保持（基线 %d——修复前反例翻成 0）" % settlements[1].poi_id)
		expect_eq(settle_hit.role, "ai_capital",
			"锚定 SETTLEMENT role 保持 ai_capital（修复前反例翻成 player_capital）")
	# 槽 0（玩家）仍是玩家主城——锚定非首槽不得挤占首槽语义
	var zb := wb.pois_of_kind(WorldDataClass.POIData.Kind.SPAWN_ZONE)
	var sb := wb.pois_of_kind(WorldDataClass.POIData.Kind.SETTLEMENT)
	expect_eq(sb[0].role, "player_capital", "槽 0 仍 = 玩家主城（槽序不被锚定挤占）")
	expect_eq(zb.size(), 3, "重跑仍 3 出生槽")
	for cid in locked_cells:
		expect_eq(wb.cell_owners[cid], wa.cell_owners[cid], "锁定格 owner 锚定保持")

# ================= 失败样例入库（银行失败面）=================

func test_failure_fixture_dir_schema_and_world_companion() -> void:
	# 入库样例目录（FAILED_FIXTURE_DIR/world）：非空 + 每例三件套可加载复验
	var dir := MapIOClass.FAILED_FIXTURE_DIR + "/world"
	var files := DirAccess.get_files_at(dir)
	var checked := 0
	for f in files:
		if not f.ends_with(".json") or f.ends_with(".meta.json") \
				or f.ends_with(".world.json"):
			continue
		var map := MapIOClass.read_map(dir.path_join(f))
		expect(map != null, "失败样例图可加载：%s" % f)
		var stem := f.trim_suffix(".json")
		var world := MapIOClass.read_world(dir.path_join(stem + ".world.json"))
		expect(world != null, "失败样例 .world.json 伴生可解析：%s" % f)
		var meta: Variant = MapIOClass.read_meta(dir.path_join(stem + ".meta.json"))
		expect(meta != null, "失败样例伴生 meta：%s" % f)
		if meta != null:
			expect_eq((meta as Dictionary)["digest"], map.digest(),
				"meta.digest 与图一致：%s" % f)
			expect(bool((meta as Dictionary).has("error")), "meta 记录失败原因：%s" % f)
		checked += 1
	expect(checked > 0, "世界失败样例目录非空（NO_VALID_SPAWN 反例入库被保留）")

# ================= seed 银行（smoke 批跑 + 确定性 + 保存重载）=================

func test_bank_smoke_run_passes_and_records_first_pass() -> void:
	var report := SeedBank.run_bank("smoke", "default_terraces@24x16")
	expect_eq(int(report["failed"]), 0, "银行 smoke 24×16 组零失败（got %s）"
		% str(report["lines"]))
	expect_eq(int(report["passed"]), 3, "smoke 份额 = 3 seed")
	expect(int(report["first_pass"]) > 0, "首过计数单独记（防重试隐藏质量）")

func test_bank_seed_rerun_world_digest_stable_3_runs() -> void:
	var t := WorldTemplateClass.new()
	t.width = 24
	t.height = 16
	var digests: Array[String] = []
	for i in 3:
		var r := WorldPipeline.generate_validated(t, 42)
		expect(r["ok"], "银行 seed 42 第 %d 次应成功" % i)
		if not r["ok"]:
			return
		digests.append(String(r["world"].meta["world_digest"]))
	expect_eq(digests[0], digests[1], "world_digest 一致（run 1 vs 2）")
	expect_eq(digests[1], digests[2], "world_digest 一致（run 2 vs 3）")

func test_success_world_save_reload_validates_same() -> void:
	var t := WorldTemplateClass.new()
	t.width = 24
	t.height = 16
	var r := WorldPipeline.generate_validated(t, 7)
	expect(r["ok"], "生成应成功")
	if not r["ok"]:
		return
	var opts := {"water_terrain_id": T_WATER, "max_road_delta": 1,
		"max_bridge_bank_delta": 2, "require_road_network": true,
		"resource_budget": 10}
	expect(r["validation"]["ok"], "生成侧校验通过")
	var base := "user://t5_bank_roundtrip/sample"
	expect_eq(MapIOClass.write_map(r["map"], base + ".json"), OK, "落盘图")
	expect_eq(MapIOClass.write_world(r["world"], base + ".world.json"), OK, "落盘世界")
	var map_back := MapIOClass.read_map(base + ".json")
	var world_back := MapIOClass.read_world(base + ".world.json")
	expect(map_back != null and world_back != null, "读回成功")
	if map_back == null or world_back == null:
		return
	expect_eq(world_back.world_digest(map_back), r["world"].world_digest(r["map"]),
		"保存→重载 world_digest 不变（世界事实零损失）")
	var report := WorldValidator.validate_report(map_back, world_back, opts)
	expect(report["ok"], "重载世界仍过同样校验（got %s）"
		% str(_first_error(report)["code"] if not report["ok"] else ""))

# ================= 初始 owner 与运行时征服状态分离 =================

func test_initial_owner_separated_from_runtime_conquest() -> void:
	# 表现派生口径（修订记录三）：cell_owners = 生成产物的**初始**归属快照——
	# 重生成产新世界对象，不触碰任何既有「存档进度」（运行时征服态属 M1b+ 运行层）
	var t := WorldTemplateClass.new()
	t.width = 24
	t.height = 16
	var a := WorldPipeline.generate_validated(t, 7)
	expect(a["ok"], "生成 A 应成功")
	if not a["ok"]:
		return
	var wa: WorldDataClass = a["world"]
	# 模拟运行时征服进度（M1b+ 存档面）：从 A 派生的独立 dict—— conquered_overlay
	var conquered_overlay := {}
	for i in wa.cell_owners.size():
		conquered_overlay[i] = wa.cell_owners[i]
	conquered_overlay[0] = 99  # 假想运行时改判（不属于任何初始势力）
	var before := str(conquered_overlay)
	# 同 seed 重生成：产新世界对象 B；A 与 overlay 均不被改写
	var b := WorldPipeline.generate_validated(t, 7)
	expect(b["ok"], "生成 B 应成功")
	if not b["ok"]:
		return
	var wb: WorldDataClass = b["world"]
	expect(wb != wa, "重生成 = 新世界对象（初始归属是快照非共享态）")
	expect_eq(str(conquered_overlay), before, "运行时征服进度不被重生成覆盖（存档面隔离）")
	expect_eq(wb.cell_owners[0], wa.cell_owners[0], "初始 owner 与运行时改判分离（B 仍 = 初始值）")
	expect_eq(str(wb.cell_owners), str(wa.cell_owners), "同 seed 初始归属一致（确定性）")
	# 数据面：世界事实无运行时征服字段（conquest 不进 WorldData——scenario/规则层）
	var keys := wa.to_dict().keys()
	keys.sort()
	expect(not str(keys).contains("conquer"), "WorldData 无征服字段（规则语义不进数据）")

# ================= T6 S5 区域验收（提案 §区域限制 :111-134 + §验收与评估 :265-276）=================
## fixture 底图：12×8 三带分区（列 0-5 群山区 region 0 / 列 6-11 平原区 region 1，
## 全图皆核心——过渡带 0 格的极简形态；分类档 = 模板起调值 mcw0.7/pcw0.3/
## elev_min0.5×levels4 → 山地类 = mw≥700∧elev≥2、平原类 = mw≤300∧陆）。
## 合格形态：r0 山地类 36/48=0.75（行 0-1 谷地带 elev1 让出 12 格）、
## r1 平原类 42/48=0.875（列 11 行 0-5 水 6 格）；边界 Δ=1；谷地 8 格有通路；
## 零孤峰。全部数字手算 oracle（期望值由构造侧给出，不抄实现）。
const REGION_OPTS := {
	"mountains_core_ratio_min": 0.60, "mountains_core_ratio_max": 0.80,
	"plains_core_ratio_min": 0.70, "plains_core_ratio_max": 0.90,
	"region_mountain_class_weight": 0.70, "region_mountain_class_elev_min": 0.50,
	"region_plain_class_weight": 0.30, "elevation_levels": 4,
	"region_largest_component_ratio": 0.60, "region_boundary_max_step": 2,
	"region_min_valley_cells": 4, "peak_area_budget_ratio": 0.05,
}

func _cell_at(map: MapDataClass, col: int, row: int) -> Vector2i:
	return Hex.axial_of(Vector2i(col, row))

func _water_at(map: MapDataClass, col: int, row: int) -> void:
	map.set_elevation(_cell_at(map, col, row), 0)
	map.set_terrain(_cell_at(map, col, row), T_WATER)
	map.set_passable(_cell_at(map, col, row), false)

## 区域 fixture（合格基座）：分区事实 + 骨架 + 格级场 + 谷地（行 0-1 列 0-3）。
func _region_fixture_valid() -> Dictionary:
	var map := _land_map()
	var world := WorldDataClass.empty()
	var r0 := WorldDataClass.TerrainRegion.new()
	r0.region_id = 0
	r0.dominant_landform = WorldDataClass.TerrainRegion.DominantLandform.MOUNTAINS
	for row in 8:
		for col in 6:
			r0.core_cells.append(row * 12 + col)
	r0.adjacency = [1]
	var r1 := WorldDataClass.TerrainRegion.new()
	r1.region_id = 1
	r1.dominant_landform = WorldDataClass.TerrainRegion.DominantLandform.PLAINS
	for row in 8:
		for col in range(6, 12):
			r1.core_cells.append(row * 12 + col)
	r1.adjacency = [0]
	world.terrain_regions = [r0, r1]
	var range0 := WorldDataClass.MountainRangeData.new()
	range0.range_id = 0
	range0.region_id = 0
	range0.spine_cells = [4 * 12 + 2, 4 * 12 + 3]
	world.mountain_ranges = [range0]
	var valley0 := WorldDataClass.ValleyData.new()
	valley0.valley_id = 0
	valley0.range_id = 0
	for row in 2:
		for col in 4:
			valley0.cells.append(row * 12 + col)
	world.valleys = [valley0]
	world.cell_regions = []
	world.cell_mountain_weights = []
	for row in 8:
		for col in 12:
			world.cell_regions.append(0 if col < 6 else 1)
			world.cell_mountain_weights.append(900 if col < 6 else 100)
	# 高程：r0 行 2-7 elev2（山地类 36 格）、行 0-1 elev1（谷地带）；r1 elev1
	#（平原类 42 格）+ 列 11 行 0-5 水（6 格）
	for row in 8:
		for col in 6:
			map.set_elevation(_cell_at(map, col, row), 1 if row < 2 else 2)
		for col2 in range(6, 12):
			map.set_elevation(_cell_at(map, col2, row), 1)
	for row2 in 6:
		_water_at(map, 11, row2)
	return {"map": map, "world": world}

func test_region_fixture_valid_zero_violations_and_metrics_oracle() -> void:
	# 合格图零违规 + region_metrics 手算 oracle（占比/连通片/谷地/过渡带/边界）
	var f := _region_fixture_valid()
	expect_eq(f["world"].validate(f["map"], -1, -1, -1), "",
		"fixture 结构合法（分区/骨架/格级事实过 WorldData.validate——区域判罚不混入结构噪声）")
	var report := WorldValidator.validate_report(f["map"], f["world"], REGION_OPTS)
	expect(report["ok"], "合格 fixture 零违规（got %s）"
		% str(_first_error(report)["explanation"] if not report["ok"] else ""))
	var m := WorldValidator.region_metrics(f["map"], f["world"], REGION_OPTS)
	expect_eq(int(m["region_count"]), 2, "两区域")
	var rm0: Dictionary = (m["regions"] as Array)[0]
	var rm1: Dictionary = (m["regions"] as Array)[1]
	expect_eq(str(rm0["landform"]), "mountains", "r0 = 群山区")
	expect_eq(str(rm1["landform"]), "plains", "r1 = 平原区")
	expect_eq(float(rm0["dominant_ratio"]), 0.75, "r0 山地类占比 = 36/48（手算 oracle）")
	expect_eq(float(rm1["dominant_ratio"]), 0.875, "r1 平原类占比 = 42/48（手算 oracle）")
	expect_eq(int(rm0["largest_component"]), 48, "r0 全核心一片（48 格连通）")
	expect_eq(float(rm0["largest_ratio"]), 1.0, "r0 最大可用连通片占比 = 1")
	expect_eq(int(rm1["largest_component"]), 42, "r1 通行 42 格一片（水 6 格剔除）")
	expect_eq(int(rm0["valley_usable"]), 8, "r0 可用谷地 = 8 格")
	expect(bool(rm0["valley_outlet"]), "r0 谷地有对外通路（行 0-1 带东行抵平原区）")
	expect_eq(int((m["transition"] as Dictionary)["cells"]), 0, "过渡带 0 格（极简形态——带内统计面在，值为零）")
	expect_eq(int((m["peaks"] as Dictionary)["effective_plain_cells"]), 42,
		"有效平原 = 42（mw≤300 ∧ 陆）")
	expect_eq(int((m["boundary"] as Dictionary)["boundary_max_elev_delta"]), 1,
		"异区相邻对最大 Δ = 1（elev2|elev1 边界）")
	expect(int((m["boundary"] as Dictionary)["boundary_pairs"]) > 0, "分区边界对存在")

func test_region_dominance_violation_reports_region_id() -> void:
	# 违规图（占比出区间两个方向）：行 2-3 再降 12 格 elev1 → 24/48=0.5 < 0.60；
	# 反向：行 0-1 全抬 elev2 → 48/48=1.0 > 0.80——explanation 恒含不合格区域编号
	#（提案 :267「输出不合格区域编号」）
	var low := _region_fixture_valid()
	for row in range(2, 4):
		for col in 6:
			(low["map"] as MapDataClass).set_elevation(_cell_at(low["map"], col, row), 1)
	var report := WorldValidator.validate_report(low["map"], low["world"], REGION_OPTS)
	expect(not report["ok"], "占比跌破下限应报 REGION_DOMINANCE")
	var hit := false
	for e in report["errors"]:
		if e["code"] == "REGION_DOMINANCE":
			hit = true
			expect_eq(e["constraint_id"], "region:0", "constraint_id 指向不合格区域")
			expect(str(e["explanation"]).contains("区域 0"),
				"explanation 含区域编号（got %s）" % e["explanation"])
			expect(str(e["explanation"]).contains("0.5"),
				"explanation 含实测占比（got %s）" % e["explanation"])
	expect(hit, "REGION_DOMINANCE 错误在列（下限方向）")
	var high := _region_fixture_valid()
	for row in 2:
		for col in 6:
			(high["map"] as MapDataClass).set_elevation(_cell_at(high["map"], col, row), 2)
	var report2 := WorldValidator.validate_report(high["map"], high["world"], REGION_OPTS)
	var hit2 := false
	for e in report2["errors"]:
		if e["code"] == "REGION_DOMINANCE":
			hit2 = true
			expect(str(e["explanation"]).contains("区域 0"),
				"上限方向 explanation 亦含区域编号")
	expect(hit2, "REGION_DOMINANCE 错误在列（上限方向：1.0 > 0.80）")

func test_region_connectivity_violation_points_at_fragmented_core() -> void:
	# 违规图：平原区核心被水柱切开——列 8 全列水 → 通行 34 格分裂为 16（列 6-7）
	# 与 18（列 9-10 + 列 11 行 6-7 尾巴）两片，最大片 18/34≈0.53 < 0.60
	#（平原完整性硬约束，提案 :268）
	var f := _region_fixture_valid()
	for row in 8:
		_water_at(f["map"], 8, row)
	var report := WorldValidator.validate_report(f["map"], f["world"], REGION_OPTS)
	expect(not report["ok"], "核心切碎应报 REGION_CONNECTIVITY")
	var hit := false
	for e in report["errors"]:
		if e["code"] == "REGION_CONNECTIVITY":
			hit = true
			expect_eq(e["constraint_id"], "region:1", "constraint_id 指向碎片化区域")
			expect(str(e["explanation"]).contains("区域 1"),
				"explanation 含区域编号（got %s）" % e["explanation"])
	expect(hit, "REGION_CONNECTIVITY 错误在列")
	var m := WorldValidator.region_metrics(f["map"], f["world"], REGION_OPTS)
	var rm1: Dictionary = (m["regions"] as Array)[1]
	expect_eq(int(rm1["passable_components"]), 2, "平原核心 2 个通行连通片（16/18 手算 oracle）")
	expect_eq(int(rm1["largest_component"]), 18, "最大片 = 18 格")

func test_region_boundary_step_violation_points_at_pair() -> void:
	# 违规图：边界对高程断缝——(5,4) 抬 elev4，邻格 (6,4) elev1 → 异区相邻对
	# Δ=3 > 2（「无区域编号导致的高度断缝」，提案 :271）
	var f := _region_fixture_valid()
	(f["map"] as MapDataClass).set_elevation(_cell_at(f["map"], 5, 4), 4)
	var report := WorldValidator.validate_report(f["map"], f["world"], REGION_OPTS)
	expect(not report["ok"], "边界断缝应报 REGION_BOUNDARY_STEP")
	var hit := false
	var cell54 := 4 * 12 + 5
	for e in report["errors"]:
		if e["code"] == "REGION_BOUNDARY_STEP":
			hit = true
			expect((e["cell_ids"] as Array).has(cell54),
				"cell_ids 指向越阶对格 %d（got %s）" % [cell54, str(e["cell_ids"])])
			expect(str(e["explanation"]).contains("3"),
				"explanation 含实测 Δ（got %s）" % e["explanation"])
	expect(hit, "REGION_BOUNDARY_STEP 错误在列")

func test_mountain_valley_violations_area_and_outlet() -> void:
	# 违规图 A（谷地面积）：宽谷表清空 → 可用谷地 0 < 4（山地可用性，提案 :272）
	var fa := _region_fixture_valid()
	(fa["world"] as WorldDataClass).valleys = []
	var report_a := WorldValidator.validate_report(fa["map"], fa["world"], REGION_OPTS)
	var hit_a := false
	for e in report_a["errors"]:
		if e["code"] == "MOUNTAIN_VALLEY":
			hit_a = true
			expect(str(e["explanation"]).contains("谷地面积不足"),
				"面积方向 explanation 具名（got %s）" % e["explanation"])
			expect_eq(e["constraint_id"], "region:0", "constraint_id 指向群山区")
	expect(hit_a, "MOUNTAIN_VALLEY 错误在列（面积不足方向）")
	# 违规图 B（对外通路）：谷地改行 2 列 0-3（4 格），全部界内邻居灌水围死——
	# BFS 出不去异区格（通路是布尔硬约束：region_min_valley_cells=0 也仍查）
	var fb := _region_fixture_valid()
	var world_b: WorldDataClass = fb["world"]
	var valley_b := WorldDataClass.ValleyData.new()
	valley_b.valley_id = 0
	valley_b.range_id = 0
	for col in 4:
		valley_b.cells.append(2 * 12 + col)
	world_b.valleys = [valley_b]
	var map_b: MapDataClass = fb["map"]
	var valley_set := {}
	for cid in valley_b.cells:
		valley_set[cid] = true
	for cid in valley_b.cells:
		for nb in map_b.neighbors_existing(_cell_of(map_b, cid)):
			if not valley_set.has(map_b.index_of(nb)):
				_water_axial(map_b, nb)
	var report_b := WorldValidator.validate_report(map_b, world_b,
		{"region_min_valley_cells": 0, "elevation_levels": 4})
	var hit_b := false
	for e in report_b["errors"]:
		if e["code"] == "MOUNTAIN_VALLEY":
			hit_b = true
			expect(str(e["explanation"]).contains("对外通路"),
				"通路方向 explanation 具名（got %s）" % e["explanation"])
	expect(hit_b, "MOUNTAIN_VALLEY 错误在列（无对外通路方向；下限 0 = 面积不查通路仍查）")

func _water_axial(map: MapDataClass, cell: Vector2i) -> void:
	map.set_elevation(cell, 0)
	map.set_terrain(cell, T_WATER)
	map.set_passable(cell, false)

func test_peak_area_budget_violation_points_at_peaks() -> void:
	# 违规图：孤峰（中心 (8,4) 半径 2 → 影响盘 19 格）> ⌊有效平原 42 × 0.05⌋ = 2
	#（孤峰稀疏性硬约束，提案 :270/:131）
	var f := _region_fixture_valid()
	var world: WorldDataClass = f["world"]
	var pk := WorldDataClass.IsolatedPeakData.new()
	pk.peak_id = 0
	pk.cell_id = 4 * 12 + 8
	pk.influence_radius = 2
	pk.peak_height = 550
	world.isolated_peaks = [pk]
	var report := WorldValidator.validate_report(f["map"], world, REGION_OPTS)
	expect(not report["ok"], "超预算应报 PEAK_AREA_BUDGET")
	var hit := false
	for e in report["errors"]:
		if e["code"] == "PEAK_AREA_BUDGET":
			hit = true
			expect_eq(e["constraint_id"], "peaks:budget", "constraint_id 指向预算约束")
			expect((e["cell_ids"] as Array).has(pk.cell_id),
				"cell_ids 指向峰中心 %d" % pk.cell_id)
			expect(str(e["explanation"]).contains("19"),
				"explanation 含影响格数（got %s）" % e["explanation"])
	expect(hit, "PEAK_AREA_BUDGET 错误在列")
	var m := WorldValidator.region_metrics(f["map"], world, REGION_OPTS)
	expect_eq(int((m["peaks"] as Dictionary)["influence_cells"]), 19,
		"影响盘 = 19 格（六边形盘 3r(r+1)+1 手算 oracle）")

func test_region_checks_gated_on_threshold_opts() -> void:
	# 「有配置才判」（沿 ROAD-01 先例）：违规图 + opts 不带区域阈值 = 零区域错误
	#——管线外调用（手工图校验/旧测试面）不受新检查面影响
	var low := _region_fixture_valid()
	for row in range(2, 4):
		for col in 6:
			(low["map"] as MapDataClass).set_elevation(_cell_at(low["map"], col, row), 1)
	var report := WorldValidator.validate_report(low["map"], low["world"], {})
	expect(report["ok"], "opts 空集 = 区域检查零触发（got %s）"
		% str(_first_error(report)["code"] if not report["ok"] else ""))
	for e in report["errors"]:
		expect(not String(e["code"]).begins_with("REGION_")
			and String(e["code"]) != "MOUNTAIN_VALLEY"
			and String(e["code"]) != "PEAK_AREA_BUDGET",
			"区域族错误不应出现（got %s）" % e["code"])
	# 部分阈值 = 只判该面：只给连通下限 → 仅 REGION_CONNECTIVITY 可命中
	var f2 := _region_fixture_valid()
	for row in 8:
		_water_at(f2["map"], 8, row)
	var report2 := WorldValidator.validate_report(f2["map"], f2["world"],
		{"region_largest_component_ratio": 0.60})
	var hit2 := false
	for e in report2["errors"]:
		if String(e["code"]) == "REGION_CONNECTIVITY":
			hit2 = true
	expect(hit2, "单阈值 opts 只开通该面（连通面独立生效）")

func test_regions_generated_map_zero_violations_metrics_diffable() -> void:
	# 生成图通过面（60×40 seed 7 = 起调阈值下的通过样本——确定性面，漂移 =
	# GENERATOR_VERSION 变更须同步改本断言）+ playability 诊断 region_metrics
	# 结构化键 + 同 seed 两次跑逐字一致（占比/连通片/谷地面积可 diff）
	var t := WorldTemplateClass.make_regions()
	t.width = 60
	t.height = 40
	var r := WorldPipeline.generate_validated(t, 7)
	expect(r["ok"], "60×40 regions seed 7 应通过全量校验（含区域验收面）：%s"
		% str(r.get("error", "")).substr(0, 140))
	if not r["ok"]:
		return
	expect_eq((r["validation"]["errors"] as Array).size(), 0,
		"生成世界区域验收零违规（首过样本——阈值 = 未验证起调值）")
	var w1 := WorldPipeline.generate_world(t, 7)
	var w2 := WorldPipeline.generate_world(t, 7)
	expect(w1["ok"] and w2["ok"], "两次直跑应成功")
	if not (w1["ok"] and w2["ok"]):
		return
	expect_eq(str(w1["stages"]), str(w2["stages"]),
		"同 seed 两次跑逐阶段诊断一致（region_metrics 可 diff）")
	var play: Variant = null
	for d in (w1["stages"] as Array):
		if String((d as Dictionary)["stage"]) == "playability":
			play = d
	expect(play != null and (play as Dictionary).has("region_metrics"),
		"regions 路线 playability 诊断携带 region_metrics 结构化键")
	if play != null and (play as Dictionary).has("region_metrics"):
		var rm: Dictionary = (play as Dictionary)["region_metrics"]
		expect_eq(int(rm["region_count"]), 4, "60×40 regions = 4 区域")
		expect((rm["regions"] as Array).size() == 4, "逐区域指标在列")
		expect((rm["transition"] as Dictionary)["cells"] > 0, "过渡带单独统计非空")
	# dual_noise 路线：区域事实恒空 → 诊断不落 region_metrics 键（不产伪字段）
	var t2 := WorldTemplateClass.new()
	t2.width = 24
	t2.height = 16
	var w3 := WorldPipeline.generate_world(t2, 7)
	expect(w3["ok"], "dual_noise 直跑应成功")
	if w3["ok"]:
		var play3: Variant = null
		for d in (w3["stages"] as Array):
			if String((d as Dictionary)["stage"]) == "playability":
				play3 = d
		expect(play3 != null and not (play3 as Dictionary).has("region_metrics"),
			"dual_noise playability 不落 region_metrics 键（区域事实为空 = 不产伪字段）")

func test_bank_regions_group_smoke_runs_and_exit_semantics_kept() -> void:
	# regions 模板银行组（T6 S5 三档 × 二十 seed 的 smoke 份额）：跑完口径 =
	# passed+failed 计满 seed 数（失败 seed 是合法产物并已留证——退出码只反映
	# 「跑完」，strict 才把失败率当异常；本断言面 = run_bank 数据口径不变）
	var report := SeedBank.run_bank("smoke", "regions_mountains@24x16")
	expect_eq(int(report["passed"]) + int(report["failed"]), 3,
		"smoke 份额 = 3 seed 全部跑完计数（模板载入失败会只计 1——工厂面在此兼测；got %s"
		% str(report["lines"]))
	var group_line := ""
	for line in report["lines"]:
		if String(line).contains("regions_mountains@24x16："):
			group_line = String(line)
	expect(group_line != "", "组汇总行在（质量看报告不设门——拍板⑤）")
	# 银行清单形状：三档 20 seed（提案 :263）
	var regions_seeds := 0
	var tiers := []
	for group_name in SeedBank.BANK:
		if not String(group_name).begins_with("regions_mountains@"):
			continue
		tiers.append(group_name)
		regions_seeds += (SeedBank.BANK[group_name]["seeds"] as Array).size()
	expect_eq(regions_seeds, 20, "regions 银行 20 个固定 seed（提案 :263）")
	expect_eq(tiers.size(), 3, "小/中/大三档（§10 默认答案①——第三档大图组补齐）")
