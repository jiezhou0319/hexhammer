## test_world_suitability.gd — T6 S6 第一刀「派系适宜度与候选落点」单测
##   （scripts/core/data/suitability_profile.gd + scripts/content/suitability_generator.gd
##   + 管线 suitability 阶段；docs/M1a-terrain-T6-stylized-execution-plan.md §8
##   + 提案 docs/evidence/风格化地图生成方案_群山平原与派系适配_修订版.md
##   §派系适配 :136-166（两阶段选址/默认关系/失败与回退）与 §验收 :273「派系候选」）
## 覆盖锚（提案验收表「派系候选」行 + T6 §8 验收面）：
##   - **硬条件不过无候选、具名原因**（提案 :162/:273：不放宽硬条件仍称合格 =
##     伪合格）：面积（AREA_BELOW_MIN）/通达（NO_REGION_ACCESS——单区域连通
##     片全拒，关闭该项即恢复）/水（NO_WATER_IN_RANGE——无水图全拒）三码逐码
##     fixture；零候选不是阶段失败（空候选 + 拒绝原因 = 合法产出）；
##   - **通行性独立字段锚**（复审闭合面）：硬条件全部按 map.is_passable 结算
##     （锚排除/面积盘/通达走廊三面——map_data.gd「通行性不随地形/高程自动
##     推导」合同 + map_connectivity.gd「悬崖 = 不可通行陆格」预告，防悬崖
##     落地后 elevation>0 代理把不可通行格静默计为合格）；管线事实自检
##     post_fact_valid（阶段内全量 validate——hydrology post_quantum 先例，
##     适宜度是 hydrology 门后产事实的第一个事实族）；
##   - **评分独立手算 oracle**：三项加权归一千分分——纯地貌偏好档（weight_landform
##     单权 → 分 = 1000×(1−|w−affinity|)）与纯水档（weight_water 单权 → 分 =
##     1000×(1−(d−1)/range)，d = Hex.distance 到水源——水源 BFS 场 = 六边形格图
##     距离的独立核对）；山地/平原 profile 在同一图上偏好方向相反（提案 :144/:145）；
##   - **间距与上限独立 oracle**（T6 §8「候选间距规则有独立 oracle」）：同分图
##     上选取 = cell_id 升序贪心 + 两两 Hex.distance ≥ min_spacing + max_candidates
##     截断——测试侧重算贪心序对照，不抄生成器实现；
##   - **确定性**：同输入两次求值逐字一致；管线同 seed world_digest 一致；
##   - **通道隔离/零干扰**（提案 :276「只改派系显示时同样成立」）：suitability
##     开/关两态 map digest 与全部分期事实（rivers/pois/states/roads/…）一致
##     ——零随机消耗（poi 通道不消耗）+ 只读地形/水系事实的双面锚；
##   - **资源同源**：两个内置 profile .tres 与代码工厂 to_dict 一致（TerrainStyle
##     「.tres 与代码默认同源」纪律）+ validate 硬边界与模板配置面拒绝锚；
##   - 管线集成：regions 路线出两 profile 事实 + WorldData.validate 过；dual_noise/
##     默认模板跳过（faction_suitability 恒空 + 跳过原因具名）。
## 非目标锚（后续批次，此处只登记不测）：聚落阶段 profile 接线、开局保证模式。
## oracle 原则：期望值全部手算或由 HexMath 原语独立推导（Hex.distance），不复制
##   生成器内部比较器/贪心实现的结构（间距 oracle 用独立重算的贪心序对照）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapGenParamsClass := preload("res://scripts/content/map_gen_params.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const WorldTemplateClass := preload("res://scripts/core/data/world_template.gd")
const WorldPipeline := preload("res://scripts/content/world_pipeline.gd")
const SuitGen := preload("res://scripts/content/suitability_generator.gd")
const Profile := preload("res://scripts/core/data/suitability_profile.gd")

const T_GRASS := 0
const T_WATER := 3


func _cell_of(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))


## 基座 fixture：12×8 全陆图（elev 1）+ 两区事实（左半 region 0 / 右半 region 1
## ——陆地连通片跨两区 ⇒ 通达恒过；权重场由调用方定制）。
func _basic_fixture(weights_by_col: Callable) -> Array:
	var map := MapDataClass.new(12, 8)
	var world := WorldDataClass.empty()
	var r0 := WorldDataClass.TerrainRegion.new()
	r0.region_id = 0
	r0.dominant_landform = WorldDataClass.TerrainRegion.DominantLandform.MOUNTAINS
	r0.adjacency = [1]
	var r1 := WorldDataClass.TerrainRegion.new()
	r1.region_id = 1
	r1.dominant_landform = WorldDataClass.TerrainRegion.DominantLandform.PLAINS
	r1.adjacency = [0]
	for row in 8:
		for col in 6:
			r0.core_cells.append(row * 12 + col)
			r1.core_cells.append(row * 12 + 6 + col)
	world.terrain_regions = [r0, r1]
	for row in 8:
		for col in 12:
			world.cell_regions.append(0 if col < 6 else 1)
			world.cell_mountain_weights.append(int(weights_by_col.call(col)))
	for cell in map.cells():
		map.set_elevation(cell, 1)
		map.set_terrain(cell, T_GRASS)
	return [map, world]


## 定制 profile（字段逐项给全——避免依赖默认值漂移；数值 = 测试意图本身）。
func _profile(pid: String, affinity: float, wl: float, we: float, ww: float,
		min_area: int, radius: int, access: bool, water: bool, wrange: int,
		spacing: int, maxc: int) -> Profile:
	var p := Profile.new()
	p.profile_id = pid
	p.landform_affinity = affinity
	p.weight_landform = wl
	p.weight_expansion = we
	p.weight_water = ww
	p.min_area_cells = min_area
	p.district_radius = radius
	p.require_access = access
	p.require_water = water
	p.water_range = wrange
	p.min_spacing = spacing
	p.max_candidates = maxc
	return p


func _set_water(map: MapDataClass, col: int, row: int) -> void:
	var cell := Hex.axial_of(Vector2i(col, row))
	map.set_elevation(cell, 0)
	map.set_terrain(cell, T_WATER)
	map.set_passable(cell, false)


func _reason_count(fs: WorldDataClass.FactionSuitability, code: String) -> int:
	for rr in fs.rejection_reasons:
		if String(rr["code"]) == code:
			return int(rr["count"])
	return 0


# ================= 资源同源与硬边界 =================

func test_builtin_profiles_tres_match_code_factories() -> void:
	# TerrainStyle 纪律：.tres 与代码默认同源（防漂移——.tres 是 authored 面）
	var mtn := Profile.load_at(Profile.MOUNTAIN_PATH)
	expect(mtn != null, "山地偏好 profile .tres 应可加载")
	if mtn != null:
		expect_eq(mtn.to_dict(), Profile.make_mountain().to_dict(),
			"山地偏好 .tres 与 make_mountain 同源")
		expect_eq(mtn.validate(), "", "山地偏好 profile 合法")
		expect_eq(mtn.profile_id, "mountain_preferring", "profile_id 与派系名解耦（地貌偏好命名）")
	var pln := Profile.load_at(Profile.PLAIN_PATH)
	expect(pln != null, "平原偏好 profile .tres 应可加载")
	if pln != null:
		expect_eq(pln.to_dict(), Profile.make_plain().to_dict(),
			"平原偏好 .tres 与 make_plain 同源")
		expect_eq(pln.validate(), "", "平原偏好 profile 合法")
		expect_eq(pln.profile_id, "plain_preferring", "profile_id 与派系名解耦")
	if mtn != null and pln != null:
		expect(mtn.landform_affinity > pln.landform_affinity,
			"山地偏好锚点 > 平原偏好锚点（两类偏好方向相反——提案 :144/:145）")


func test_profile_validate_hard_bounds() -> void:
	var cases: Array = [
		[func(p: Profile) -> void: p.profile_id = "", "profile_id"],
		[func(p: Profile) -> void: p.landform_affinity = 1.5, "landform_affinity"],
		[func(p: Profile) -> void: p.weight_landform = -0.1, "weight_landform"],
		[func(p: Profile) -> void:
			p.weight_landform = 0.0; p.weight_expansion = 0.0; p.weight_water = 0.0, "权重全零"],
		[func(p: Profile) -> void: p.min_area_cells = 0, "min_area_cells"],
		[func(p: Profile) -> void: p.district_radius = 5, "district_radius"],
		[func(p: Profile) -> void: p.water_range = 0, "water_range"],
		[func(p: Profile) -> void: p.max_candidates = 0, "max_candidates"],
	]
	for case in cases:
		var p := Profile.make_mountain()
		(case[0] as Callable).call(p)
		expect(p.validate() != "" and String(p.validate()).contains(case[1]),
			"非法 %s 应具名拒绝（got %s）" % [case[1], p.validate()])
	expect(Profile.make_mountain().validate() == "", "内置山地 profile 合法")
	expect(Profile.make_plain().validate() == "", "内置平原 profile 合法")


# ================= 硬条件：不过无候选、具名原因 =================

func test_hard_area_below_min_rejects_all_with_named_reason() -> void:
	# 面积硬条件：min_area 大于全图任何盘 → 零候选 + AREA_BELOW_MIN 全计
	#（97 = 96 陆格全拒；水格不参评不计因）——「不产伪合格」的面积面
	var fixture := _basic_fixture(func(_col: int) -> int: return 500)
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	_set_water(map, 11, 7)
	var p := _profile("p", 0.5, 1.0, 0.0, 0.0, 97, 2, false, false, 3, 0, 4)
	var fs := SuitGen.evaluate_profile_standalone(map, world, p, T_WATER)
	expect_eq(fs.candidate_sites.size(), 0, "面积不过 → 零候选（不产伪合格）")
	expect_eq(fs.qualified_count, 0, "合格数 0")
	expect_eq(_reason_count(fs, "AREA_BELOW_MIN"), 95, "95 陆格全计 AREA_BELOW_MIN（96−水 1）")
	expect_eq(fs.rejection_reasons.size(), 1, "只列实际发生的原因（面积是首查码）")


func test_hard_access_single_region_rejects_and_toggle_restores() -> void:
	# 通达硬条件：单区域图（cell_regions 全 0）→ 全拒 NO_REGION_ACCESS；
	# require_access=false → 同图恢复出候选（硬条件开关面，不放宽而伪装）
	var fixture := _basic_fixture(func(_col: int) -> int: return 500)
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	for i in world.cell_regions.size():
		world.cell_regions[i] = 0
	_set_water(map, 0, 0)
	var p_on := _profile("p", 0.5, 1.0, 0.0, 0.0, 1, 1, true, false, 3, 0, 64)
	var fs_on := SuitGen.evaluate_profile_standalone(map, world, p_on, T_WATER)
	expect_eq(fs_on.candidate_sites.size(), 0, "单区域连通 → 零候选（通达硬条件）")
	expect(_reason_count(fs_on, "NO_REGION_ACCESS") > 0, "NO_REGION_ACCESS 具名计数")
	var p_off := _profile("p", 0.5, 1.0, 0.0, 0.0, 1, 1, false, false, 3, 0, 64)
	var fs_off := SuitGen.evaluate_profile_standalone(map, world, p_off, T_WATER)
	expect(fs_off.candidate_sites.size() > 0, "关闭通达硬条件 → 同图恢复候选（开关面）")


func test_hard_water_out_of_range_rejects_dry_map() -> void:
	# 水硬条件：无水图（无水地形格、无河）→ 全拒 NO_WATER_IN_RANGE；
	# 放一格水且量程盖住 → 恢复候选（前两码不触发——固定评估序的间接锚）
	var fixture := _basic_fixture(func(_col: int) -> int: return 500)
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var p := _profile("p", 0.5, 1.0, 0.0, 0.0, 1, 1, false, true, 3, 0, 64)
	var fs_dry := SuitGen.evaluate_profile_standalone(map, world, p, T_WATER)
	expect_eq(fs_dry.candidate_sites.size(), 0, "无水图 → 零候选（水硬条件）")
	expect_eq(_reason_count(fs_dry, "NO_WATER_IN_RANGE"), 96, "96 陆格全拒（无水源 → BFS 全不可达）")
	_set_water(map, 0, 0)
	var fs_wet := SuitGen.evaluate_profile_standalone(map, world, p, T_WATER)
	expect(fs_wet.candidate_sites.size() > 0, "有水且量程内 → 恢复候选")
	expect(_reason_count(fs_wet, "NO_WATER_IN_RANGE") > 0,
		"远水格仍拒（距 (0,0) >3 环的格拒——量程是环距不是布尔）")


func test_impassable_land_cells_excluded_by_hard_conditions() -> void:
	# 通行性独立字段锚（map_data.gd「不随地形/高程自动推导」合同 + map_connectivity
	# 「悬崖 = 不可通行陆格」预告——硬条件须按 is_passable 结算，不可用 elevation>0
	# 代理：否则悬崖落地后不可通行格会被静默计为合格候选）。三面：
	# ①锚排除+合格计数；②面积盘不计不可通行格；③通达 BFS 不穿不可通行格
	var fixture := _basic_fixture(func(_col: int) -> int: return 500)
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	# ① 不可通行陆格不作候选锚：同分图首选 cell 0（并列 cell_id 升序），把 0 号格
	# 设为不可通行陆格（elevation 保持 1）→ 首选后移、合格数 95
	map.set_passable(_cell_of(map, 0), false)
	var p := _profile("p", 0.5, 1.0, 0.0, 0.0, 1, 1, false, false, 3, 0, 1)
	var fs := SuitGen.evaluate_profile_standalone(map, world, p, T_WATER)
	expect_eq(fs.candidate_sites.size(), 1, "首选唯一（上限 1）")
	if fs.candidate_sites.size() == 1:
		expect(fs.candidate_sites[0].cell_id != 0, "不可通行陆格不作候选锚（首选后移）")
		expect(map.is_passable(_cell_of(map, fs.candidate_sites[0].cell_id)),
			"候选锚必为通行格")
	expect_eq(fs.qualified_count, 95, "合格数 = 95（96−1 不可通行格不参评）")
	# ② 面积盘不计不可通行格：min_area=96（全图）+ 1 不可通行格 → 95 个通行锚
	# 全部 AREA_BELOW_MIN（盘内通行格至多 95）
	var p_area := _profile("pa", 0.5, 1.0, 0.0, 0.0, 96, 2, false, false, 3, 0, 1)
	var fs_area := SuitGen.evaluate_profile_standalone(map, world, p_area, T_WATER)
	expect_eq(fs_area.candidate_sites.size(), 0, "面积下限 96 不可达（不可通行格不计入盘）")
	expect_eq(_reason_count(fs_area, "AREA_BELOW_MIN"), 95, "95 通行锚全拒 AREA_BELOW_MIN")
	# ③ 通达 BFS 不穿不可通行格：两整列设为不可通行陆格 → 通行图左右断开、
	# 各片单区域 → 全拒 NO_REGION_ACCESS；恢复一走廊格 → 跨区通路恢复
	var fixture2 := _basic_fixture(func(_col: int) -> int: return 500)
	var map2: MapDataClass = fixture2[0]
	var world2: WorldDataClass = fixture2[1]
	for row in 8:
		for col in [5, 6]:
			map2.set_passable(Hex.axial_of(Vector2i(col, row)), false)
	var p_access := _profile("pc", 0.5, 1.0, 0.0, 0.0, 1, 1, true, false, 3, 0, 1)
	var fs_wall := SuitGen.evaluate_profile_standalone(map2, world2, p_access, T_WATER)
	expect_eq(fs_wall.candidate_sites.size(), 0, "不可通行墙断开跨区通路 → 零候选")
	expect(_reason_count(fs_wall, "NO_REGION_ACCESS") > 0,
		"通达具名拒绝（BFS 按 is_passable 结算——不可通行墙两侧各单区域）")
	map2.set_passable(Hex.axial_of(Vector2i(5, 4)), true)  # 开两格走廊（奇偶行邻接
	map2.set_passable(Hex.axial_of(Vector2i(6, 4)), true)  # 须穿两列墙：(4,4)→(5,4)→(6,4)→(7,4)）
	var fs_corridor := SuitGen.evaluate_profile_standalone(map2, world2, p_access, T_WATER)
	expect(fs_corridor.candidate_sites.size() > 0,
		"恢复走廊格 → 跨区通路恢复（通行片重新跨两区）")


# ================= 评分独立手算 oracle =================

func test_score_landform_only_hand_computed() -> void:
	# 纯地貌偏好档（weight_landform=1 单权）：分 = 1000×(1−|w−affinity|)
	# 左半 mw=900、右半 mw=100；affinity=0.85 → 左 950 / 右 250（手算）
	var fixture := _basic_fixture(func(col: int) -> int: return 900 if col < 6 else 100)
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var p := _profile("p", 0.85, 1.0, 0.0, 0.0, 1, 1, false, false, 3, 0, 2)
	var fs := SuitGen.evaluate_profile_standalone(map, world, p, T_WATER)
	expect_eq(fs.candidate_sites.size(), 2, "上限 2（同分并列 cell_id 升序）")
	if fs.candidate_sites.size() == 2:
		expect_eq(fs.candidate_sites[0].cell_id, 0, "最高分并列取 cell_id 最小（左半首格）")
		expect_eq(fs.candidate_sites[0].score, 950, "mw=900/affinity=0.85 → 1000×0.95=950（手算）")
	# 反向锚：affinity=0.1 → 右半（mw=100）满偏好 1000、首候选右半首格
	var plain_fs := SuitGen.evaluate_profile_standalone(map, world,
		_profile("r", 0.1, 1.0, 0.0, 0.0, 1, 1, false, false, 3, 0, 1), T_WATER)
	if plain_fs.candidate_sites.size() == 1:
		expect_eq(plain_fs.candidate_sites[0].cell_id, 6, "affinity=0.1 → 右半首格最高（mw=100→1−|0.1−0.1|=1.0）")
		expect_eq(plain_fs.candidate_sites[0].score, 1000, "右半满偏好分 1000（手算）")


func test_score_water_only_hand_computed() -> void:
	# 纯水档（weight_water=1 单权）：水源 BFS 场 = 六边形格图距离（无障碍全格图
	# ⇒ Hex.distance 独立核对）；d=1 → 1000、d=3（range=3）→ 1000×(1−2/3)=333
	var fixture := _basic_fixture(func(_col: int) -> int: return 500)
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	_set_water(map, 0, 0)
	var p := _profile("p", 0.5, 0.0, 0.0, 1.0, 1, 1, false, true, 3, 0, 8)
	var fs := SuitGen.evaluate_profile_standalone(map, world, p, T_WATER)
	var anchor := Hex.axial_of(Vector2i(0, 0))
	var top: WorldDataClass.CandidateSite = fs.candidate_sites[0] if not fs.candidate_sites.is_empty() else null
	expect(top != null, "应有候选（临水格满水项）")
	if top != null:
		expect_eq(Hex.distance(anchor, _cell_of(map, top.cell_id)), 1,
			"最高分 = 距水源 1 环的格（水项 = 1.0 满分）")
		expect_eq(top.score, 1000, "d=1 → 1000×(1−0/3)=1000（手算）")
	# d=3 的格：分 = 333（1000×(1−2/3) 四舍五入）——距水源恰 3 环的合格格核对
	var found_d3 := false
	for cell in map.cells():
		if map.elevation_at(cell) == 0 or Hex.distance(anchor, cell) != 3:
			continue
		var q := SuitGen.evaluate_profile_standalone(map, world,
			_profile("one", 0.5, 0.0, 0.0, 1.0, 1, 1, false, true, 3, 0, 64), T_WATER)
		for cs in q.candidate_sites:
			if _cell_of(map, cs.cell_id) == cell:
				expect_eq(cs.score, 333, "d=3/range=3 → 1000×(1/3)=333（手算）")
				found_d3 = true
				break
		break  # 只核首个 d=3 格
	expect(found_d3, "d=3 样本应入候选集（量程盖住——Hex.distance 独立核对通过）")


func test_two_builtin_profiles_prefer_opposite_landforms() -> void:
	# 山地/平原内置 profile 在同一分区图上偏好方向相反（提案 :144/:145 的机器面）；
	# 两侧各放一格水（两侧都有量程内合格格——水是两 profile 共同硬条件）
	var fixture := _basic_fixture(func(col: int) -> int: return 900 if col < 6 else 100)
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	_set_water(map, 0, 0)
	_set_water(map, 11, 7)
	var mtn := SuitGen.evaluate_profile_standalone(map, world, Profile.make_mountain(), T_WATER)
	var pln := SuitGen.evaluate_profile_standalone(map, world, Profile.make_plain(), T_WATER)
	expect(not mtn.candidate_sites.is_empty(), "山地偏好有候选")
	expect(not pln.candidate_sites.is_empty(), "平原偏好有候选")
	if not mtn.candidate_sites.is_empty() and not pln.candidate_sites.is_empty():
		var mtn_cell := mtn.candidate_sites[0].cell_id
		var pln_cell := pln.candidate_sites[0].cell_id
		expect(world.cell_mountain_weights[mtn_cell] >= 700,
			"山地偏好首候选在群山权重 ≥700 侧（got mw=%d）" % world.cell_mountain_weights[mtn_cell])
		expect(world.cell_mountain_weights[pln_cell] <= 300,
			"平原偏好首候选在群山权重 ≤300 侧（got mw=%d）" % world.cell_mountain_weights[pln_cell])


# ================= 间距与上限独立 oracle =================

func test_spacing_and_cap_matches_independent_greedy_oracle() -> void:
	# 同分图（全陆同权重、无水关、无通达关）→ 选取 = cell_id 升序贪心 + 两两环距
	# ≥ min_spacing + max_candidates 截断。测试侧独立重算贪心序对照（不抄实现）
	var fixture := _basic_fixture(func(_col: int) -> int: return 500)
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var p := _profile("p", 0.5, 1.0, 0.0, 0.0, 1, 1, false, false, 3, 4, 3)
	var fs := SuitGen.evaluate_profile_standalone(map, world, p, T_WATER)
	# 独立 oracle：行主序贪心（同分 ⇒ 分数并列按 cell_id 升序 = 行主序贪心同构）
	var want: Array[int] = []
	for i in map.cell_count():
		if map.elevation_at(_cell_of(map, i)) == 0:
			continue
		if want.size() >= 3:
			break
		var ok_dist := true
		for t in want:
			if Hex.distance(_cell_of(map, i), _cell_of(map, t)) < 4:
				ok_dist = false
				break
		if ok_dist:
			want.append(i)
	expect_eq(fs.candidate_sites.size(), want.size(), "候选数 = 独立贪心 oracle（%d）" % want.size())
	expect_eq(fs.candidate_sites.size(), 3, "上限 3 截断（max_candidates）")
	for k in want.size():
		if k < fs.candidate_sites.size():
			expect_eq(fs.candidate_sites[k].cell_id, want[k],
				"候选 %d = 独立贪心序（间距/并列/上限共同决定）" % k)
	# 间距不变量直证：两两环距 ≥ 4
	for a in fs.candidate_sites.size():
		for b in range(a + 1, fs.candidate_sites.size()):
			expect(Hex.distance(_cell_of(map, fs.candidate_sites[a].cell_id),
				_cell_of(map, fs.candidate_sites[b].cell_id)) >= 4,
				"候选两两环距 ≥ min_spacing=4")
	# 被间距让位的合格格计入 qualified_count（间距只筛候选不拒合格）
	expect(fs.qualified_count > fs.candidate_sites.size(),
		"合格数 > 候选数（间距/上限让位的格仍计合格——qualified=%d）" % fs.qualified_count)


# ================= 确定性与零干扰 =================

func test_generator_deterministic_same_inputs() -> void:
	var fixture := _basic_fixture(func(col: int) -> int: return 900 if col < 6 else 100)
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	_set_water(map, 11, 0)
	var r1 := SuitGen.evaluate_profiles(map, world,
		[Profile.make_mountain(), Profile.make_plain()], {"water_terrain_id": T_WATER})
	var r2 := SuitGen.evaluate_profiles(map, world,
		[Profile.make_mountain(), Profile.make_plain()], {"water_terrain_id": T_WATER})
	expect(r1["ok"] and r2["ok"], "两次求值应成功")
	var facts1: Array = r1["results"]
	var facts2: Array = r2["results"]
	expect_eq(facts1.size(), facts2.size(), "两次 profile 数一致")
	for k in facts1.size():
		var a: WorldDataClass.FactionSuitability = facts1[k]
		var b: WorldDataClass.FactionSuitability = facts2[k]
		expect_eq(_fs_str(a), _fs_str(b), "profile %s 两次求值逐字一致（确定性）" % a.profile_id)


func _fs_str(fs: WorldDataClass.FactionSuitability) -> String:
	var sites := []
	for cs in fs.candidate_sites:
		sites.append([cs.cell_id, cs.score])
	return JSON.stringify({"profile_id": fs.profile_id, "sites": sites,
		"qualified": fs.qualified_count, "rejections": fs.rejection_reasons})


func test_pipeline_suitability_stage_isolated_from_other_facts() -> void:
	# 通道隔离/零干扰双面（提案 :276 + T6 §8 验收）：同 seed 开/关 suitability——
	# map digest 与全部既有世界事实一致（零随机消耗：poi 通道不被消耗 ⇒ 聚落/
	# 势力/道路事实不变；地形阶段不读 profile ⇒ 地形不变）；faction_suitability
	# 是唯一差异面
	var t_on := WorldTemplateClass.make_regions()
	t_on.width = 24
	t_on.height = 16
	var t_off := WorldTemplateClass.make_regions()
	t_off.width = 24
	t_off.height = 16
	t_off.suitability_enabled = false
	var on := WorldPipeline.generate_world(t_on, 7)
	var off := WorldPipeline.generate_world(t_off, 7)
	expect(on["ok"] and off["ok"], "两态生成应成功")
	if not (on["ok"] and off["ok"]):
		return
	expect_eq((on["map"] as MapDataClass).digest(), (off["map"] as MapDataClass).digest(),
		"map digest 两态一致（地形不读 profile——提案 :140）")
	var on_world: WorldDataClass = on["world"]
	var off_world: WorldDataClass = off["world"]
	for key in ["rivers", "water_bodies", "pois", "states", "roads", "crossings",
			"links", "cell_owners", "terrain_regions", "mountain_ranges",
			"ridge_branches", "valleys", "isolated_peaks", "cell_regions",
			"cell_mountain_weights"]:
		expect_eq(JSON.stringify(on_world.to_dict()[key]), JSON.stringify(off_world.to_dict()[key]),
			"事实 %s 两态一致（零干扰）" % key)
	expect_eq(on_world.faction_suitability.size(), 2, "开态两 profile 事实")
	expect_eq(off_world.faction_suitability.size(), 0, "关态零事实（空集合合法）")


func test_pipeline_regions_facts_shape_and_preference_direction() -> void:
	var t := WorldTemplateClass.make_regions()
	t.width = 24
	t.height = 16
	var r := WorldPipeline.generate_world(t, 7)
	expect(r["ok"], "regions 路线生成应成功（24×16 seed 7）")
	if not r["ok"]:
		return
	var world: WorldDataClass = r["world"]
	var map: MapDataClass = r["map"]
	expect_eq(world.faction_suitability.size(), 2, "两内置 profile 事实（模板清单序）")
	expect_eq(world.faction_suitability[0].profile_id, "mountain_preferring", "槽 0 山地偏好")
	expect_eq(world.faction_suitability[1].profile_id, "plain_preferring", "槽 1 平原偏好")
	var mtn := world.faction_suitability[0]
	var pln := world.faction_suitability[1]
	expect(world.validate(map, T_WATER) == "", "世界事实校验合法（含适宜度面）")
	# 管线事实自检（复审闭合面：适宜度是 hydrology 二次验证之后产事实的第一个
	# 事实族——阶段内全量 validate 自检，hydrology post_quantum 先例）
	var suit_diag: Variant = null
	for d in r["stages"]:
		if String(d["stage"]) == "suitability":
			suit_diag = d
	expect(suit_diag != null and suit_diag.get("post_fact_valid", false) == true,
		"suitability 诊断带 post_fact_valid=true（事实自检通过——生成期门禁面）")
	for fs in [mtn, pln]:
		# 合格候选全部满足硬条件（提案 :273）：陆格 + 间距不变量 + 分数值域
		for cs in fs.candidate_sites:
			expect(map.elevation_at(_cell_of(map, cs.cell_id)) > 0,
				"候选 %d 是通行陆格（硬条件不放宽）" % cs.cell_id)
			expect(cs.score >= 0 and cs.score <= 1000, "分数千分值域")
		for a in fs.candidate_sites.size():
			for b in range(a + 1, fs.candidate_sites.size()):
				expect(Hex.distance(_cell_of(map, fs.candidate_sites[a].cell_id),
					_cell_of(map, fs.candidate_sites[b].cell_id)) >= 6,
					"profile %s 候选两两环距 ≥ min_spacing=6" % fs.profile_id)
		expect(fs.qualified_count >= fs.candidate_sites.size(), "合格数 ≥ 候选数")
	if not mtn.candidate_sites.is_empty() and not pln.candidate_sites.is_empty():
		expect(world.cell_mountain_weights[mtn.candidate_sites[0].cell_id]
				>= world.cell_mountain_weights[pln.candidate_sites[0].cell_id],
			"山地偏好首候选群山权重 ≥ 平原偏好首候选（生成图上的偏好方向）")
	# 确定性：同 seed 重跑 world_digest 一致（3 次）
	var digests := []
	for i in 3:
		var rr := WorldPipeline.generate_world(t, 7)
		if rr["ok"]:
			digests.append(String(rr["world"].meta["world_digest"]))
	expect(digests.size() == 3 and digests[0] == digests[1] and digests[1] == digests[2],
		"world_digest 三次一致（suitability 阶段确定性）")


# ================= 管线跳过态与配置面 =================

func test_dual_noise_default_skips_and_legacy_empty() -> void:
	var t := WorldTemplateClass.new()
	t.width = 24
	t.height = 16
	var w := WorldPipeline.generate_world(t, 7)
	expect(w["ok"], "默认模板生成应成功")
	if w["ok"]:
		expect((w["world"] as WorldDataClass).faction_suitability.is_empty(),
			"dual_noise 默认模板 faction_suitability 恒空（不产伪字段）")
		var diag: Variant = null
		for d in w["stages"]:
			if String(d["stage"]) == "suitability":
				diag = d
		expect(diag != null and diag.get("skipped", false), "suitability 阶段 skipped 诊断")
		expect(String(diag.get("reason", "")).contains("未启用"),
			"跳过原因具名「未启用」（got %s）" % str(diag.get("reason", "")))
	# legacy 退化特例：faction_suitability 恒空 + 跳过（legacy 零漂移面）
	var p := MapGenParamsClass.new()
	p.seed = 7
	var legacy := WorldPipeline.generate_legacy(p)
	expect(legacy["ok"], "legacy 生成应成功")
	if legacy["ok"]:
		expect((legacy["world"] as WorldDataClass).faction_suitability.is_empty(),
			"legacy faction_suitability 恒空（逐格输出零漂移的一部分）")


func test_zero_candidates_is_not_stage_failure() -> void:
	# 无合格候选 = 合法产出不是阶段失败（默认模式，提案 :162）；阶段诊断带
	# profile_results 计数（「没有候选时输出原因」的结构化面）
	var t := WorldTemplateClass.make_regions()
	t.width = 24
	t.height = 16
	var impossible := Profile.make_mountain()
	impossible.min_area_cells = 100000  # 物理不可达面积（validate 无上界 = 合法配置）
	t.suitability_profiles = [impossible]
	var r := WorldPipeline.generate_world(t, 7)
	expect(r["ok"], "零候选不应失败管线（明确原因而非伪合格——提案 :162）")
	if r["ok"]:
		var world: WorldDataClass = r["world"]
		expect_eq(world.faction_suitability.size(), 1, "profile 事实仍在（跑了但无一合格）")
		var fs := world.faction_suitability[0]
		expect_eq(fs.candidate_sites.size(), 0, "零候选")
		expect_eq(fs.qualified_count, 0, "零合格")
		expect(_reason_count(fs, "AREA_BELOW_MIN") > 0, "AREA_BELOW_MIN 原因具名")
		var diag: Variant = null
		for d in r["stages"]:
			if String(d["stage"]) == "suitability":
				diag = d
		var results: Array = diag["profile_results"]
		expect_eq(results.size(), 1, "诊断 profile_results 逐 profile 计数")
		expect_eq(int(results[0]["candidates"]), 0, "诊断候选计数 0")
		expect_eq(int(results[0]["qualified"]), 0, "诊断合格计数 0")
		expect((results[0]["rejections"] as Dictionary).has("AREA_BELOW_MIN"),
			"诊断拒绝计数具名")


func test_config_rejects_enabled_without_profiles() -> void:
	var t := WorldTemplateClass.make_regions()
	t.suitability_profiles = []
	var r := WorldPipeline.generate_world(t, 7)
	expect(not r["ok"], "启用适宜度但 profile 清单空 = 配置失败（不产半图）")
	expect(String(r["error"]).contains("suitability"),
		"配置错误具名（got %s）" % str(r["error"]).substr(0, 120))
	# duplicate profile_id 拒绝
	var t2 := WorldTemplateClass.make_regions()
	t2.width = 24
	t2.height = 16
	t2.suitability_profiles = [Profile.make_mountain(), Profile.make_mountain()]
	var r2 := WorldPipeline.generate_world(t2, 7)
	expect(not r2["ok"], "profile_id 重复 = 配置失败")
	expect(String(r2["error"]).contains("重复"), "重复具名（got %s）" % str(r2["error"]).substr(0, 120))
