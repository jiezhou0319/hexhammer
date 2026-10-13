## test_world_data.gd — T2 LAND-01 §2.5 四件单测（WorldData 容器 + NeighborLinkData
##   + 校验器 + 序列化；执行方案 §2.5 / §0 铁律 1，数据合同草案 §3/§4/§11/§12.3）
## 覆盖锚（§2.5 原文逐条）：
##   - 序列化往返 + **Vector2i 显式 [x,y] 转换层**（§2.2 实测坑：直写 JSON.stringify
##     落成 "(3, 17)" 字符串不可还原——测试断言落盘 JSON 文本不含该形状且往返无损）；
##   - 旧图零迁移：缺 .world.json → empty() 合法（无河无路无 POI 的合法态）；
##   - NeighborLinkData：link_id=(min,max) 规范化、两端互为界内邻居校验、
##     主键唯一/规范序、引用可解析（road_id T4 起与 roads 对账、river_reach_id
##     T3 起与 reach 对账——河/路/桥实体面见 tests/test_water_rivers.gd /
##     test_water_bodies.gd / test_roads.gd / test_bridges.gd）；
##   - 零回写 MapData（草案 §11 全局项：validate/to_dict 前后 summary/digest/mods
##     逐字节不变）；
##   - POI/势力归属（T5 WORLD-03 解锁，拍板⑧）：POIData 形状随 kind 钉死
##     （SPAWN_ZONE 七格 = 中心+六邻；聚落/资源单格）、states 主城对账、
##     cell_owners 值域/水格恒中立、国界跳变边派生（border_links_of）——
##     往返/旧图零迁移/拒绝锚同前四件纪律（行为面见 tests/test_world_settlement.gd）；
##   - 地貌分区/骨架事实（T6 S3 解锁）：TerrainRegion（landform 两值/核心格
##     行主序/跨区不共享/邻接对称）、MountainRangeData/RidgeBranchData（有序
##     脊线 = 界内相邻连续不重复、支脉根在父脊、山系挂群山区）、ValleyData
##     （格集升序）、cell_regions/cell_mountain_weights（全长/值域/与区域表
##     对账）——往返/旧图零迁移（缺六键 = T5 时代合法空）/拒绝锚同前四件纪律
##     （生成行为面见 tests/test_world_pipeline.gd 的 T6 regions 块）；
##   - 孤峰事实（T6 S4 解锁）：IsolatedPeakData（中心界内/影响半径 ≥1/峰高
##     千分 1..1000/形状值域单点 CONE——枚举存在 ≠ 能力开放）、peak_by_id
##     查询面、无分区不得有孤峰（PEAK_NO_REGIONS）——往返/旧图零迁移（缺
##     isolated_peaks 键 = S3 时代合法空）/拒绝锚同前四件纪律。
## oracle 原则：期望邻接关系由 MapData/HexMath 原语独立推导（index_of / dir_between /
##   axial_of），不复制 WorldData 内部比较器；JSON 往返走真实文件（user:// 临时件）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapIO := preload("res://scripts/content/map_io.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")

## 测试图：3×2 = 6 格（index_of 0..5；含跨行邻居——odd-r 偏移真实口径）
const MAP_W := 3
const MAP_H := 2

# ================= link_id 规范化 =================

func test_link_id_of_canonical_min_max() -> void:
	expect_eq(WorldDataClass.link_id_of(5, 2), Vector2i(2, 5), "(5,2) → (min,max) = (2,5)")
	expect_eq(WorldDataClass.link_id_of(2, 5), Vector2i(2, 5), "(2,5) 原序不变")
	expect_eq(WorldDataClass.link_id_of(0, 0), WorldDataClass.NO_LINK, "同格 → NO_LINK（自身无邻接）")
	expect_eq(WorldDataClass.link_id_of(-1, 3), WorldDataClass.NO_LINK, "负 cell_id → NO_LINK（哨兵）")
	expect_eq(WorldDataClass.link_id_of(3, -1), WorldDataClass.NO_LINK, "负 cell_id（反序）→ NO_LINK")

# ================= 校验器：邻接 / 界内 / 规范序 / 引用 =================

## 相邻对样本（axial 邻接由 Hex.dir_between 独立核对，不复制 WorldData 判定）
func _sample_map() -> MapDataClass:
	return MapDataClass.new(MAP_W, MAP_H)

func _adjacent_pair_ids(map: MapDataClass) -> Array:
	for a in map.cells():
		for b in map.cells():
			if a != b and Hex.dir_between(a, b) >= 0:
				return [map.index_of(a), map.index_of(b)]
	return []

func test_validate_accepts_mutual_neighbor_links() -> void:
	var map := _sample_map()
	var pair := _adjacent_pair_ids(map)
	expect(pair.size() == 2, "样本图必含相邻对")
	var w := WorldDataClass.empty()
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = WorldDataClass.link_id_of(pair[0], pair[1])
	w.links.append(lk)
	expect_eq(w.validate(map), "", "互为界内邻居的 link 合法")

func test_validate_rejects_non_neighbor_and_out_of_map() -> void:
	var map := _sample_map()
	# 非邻居对：0 与 5（3×2 图中 (0,0) 与 (2,1) 不相邻——由 dir_between 独立验证前提）
	var a := Hex.axial_of(Vector2i(0, 0))
	var b := Hex.axial_of(Vector2i(2, 1))
	expect(Hex.dir_between(a, b) < 0, "构造前提：两格不互为邻居")
	var w := WorldDataClass.empty()
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = WorldDataClass.link_id_of(map.index_of(a), map.index_of(b))
	w.links.append(lk)
	expect(w.validate(map) != "", "非邻居对的 link 非法")

func test_validate_rejects_out_of_map_id() -> void:
	var map := _sample_map()
	var w := WorldDataClass.empty()
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = Vector2i(0, map.cell_count())  # 界外格 id
	w.links.append(lk)
	expect(w.validate(map) != "", "界外格 id 的 link 非法（不存在邻格不产生连接）")

func test_validate_rejects_duplicate_and_unsorted() -> void:
	var map := _sample_map()
	var pair := _adjacent_pair_ids(map)
	# 重复主键
	var w1 := WorldDataClass.empty()
	for i in 2:
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = WorldDataClass.link_id_of(pair[0], pair[1])
		w1.links.append(lk)
	expect(w1.validate(map) != "", "重复 link_id 非法（主键唯一）")
	# 非规范序：取图内两条合法 link，按降序排列（各自单独合法，整体破序）
	var ids := _two_link_ids_descending(map)
	expect(ids.size() == 4, "构造前提：图内存在两条可降序排列的合法 link")
	if ids.size() == 4:
		var w2 := WorldDataClass.empty()
		for i in 2:
			var lk2 := WorldDataClass.NeighborLinkData.new()
			lk2.link_id = Vector2i(ids[i * 2], ids[i * 2 + 1])
			w2.links.append(lk2)
		expect(w2.validate(map) != "", "降序 links 非法（规范序 = link_id 升序）")
		# 对照：同两条 link 升序排列 → 合法（错误归因于序而非内容）
		var w3 := WorldDataClass.empty()
		for i in 2:
			var lk3 := WorldDataClass.NeighborLinkData.new()
			lk3.link_id = Vector2i(ids[(1 - i) * 2], ids[(1 - i) * 2 + 1])
			w3.links.append(lk3)
		expect_eq(w3.validate(map), "", "同两条 link 升序 → 合法（破序才是非法原因）")

## 图内两条合法 link 的 link_id，返回降序 [大.x, 大.y, 小.x, 小.y]（各自邻接由
## Hex.dir_between 独立核对）。
func _two_link_ids_descending(map: MapDataClass) -> Array:
	var lids: Array = []
	for a in map.cells():
		for b in map.cells():
			if a == b or Hex.dir_between(a, b) < 0:
				continue
			var lid := WorldDataClass.link_id_of(map.index_of(a), map.index_of(b))
			if not lids.has(lid):
				lids.append(lid)
	if lids.size() < 2:
		return []
	lids.sort()  # 升序（Vector2i 字典序）；取末两位降序排列
	var hi: Vector2i = lids[lids.size() - 1]
	var lo: Vector2i = lids[lids.size() - 2]
	return [hi.x, hi.y, lo.x, lo.y]

func test_validate_rejects_unresolved_references() -> void:
	var map := _sample_map()
	var pair := _adjacent_pair_ids(map)
	var w := WorldDataClass.empty()
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = WorldDataClass.link_id_of(pair[0], pair[1])
	lk.road_id = 7
	w.links.append(lk)
	var msg := w.validate(map)
	expect(msg != "", "link 声明 road_id=7 但无任何道路实体：非法（T4 解锁 ≠ 放行——对账才合法）")
	expect(String(msg).contains("LINK_ROAD_MISMATCH"), "错误码指向 link↔road 对账（T4 起）")
	# T3 起河段解锁：river_reach_id 非 ID_NONE 时须指向存在的 reach（双向对账）
	lk.road_id = WorldDataClass.ID_NONE
	lk.river_reach_id = 3
	var msg2 := w.validate(map)
	expect(msg2 != "", "river_reach_id 指向不存在的 reach：非法（T3 解锁 ≠ 放行）")
	expect(String(msg2).contains("LINK_RIVER_MISMATCH"), "错误码指向 link↔reach 对账")

# ================= 序列化：Vector2i 显式 [x,y] 转换层 + JSON 往返 =================

func test_to_dict_link_id_is_explicit_xy_array() -> void:
	var w := WorldDataClass.empty()
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = Vector2i(3, 17)
	w.links.append(lk)
	var d := w.to_dict()
	var entry: Dictionary = d["links"][0]
	expect(entry["link_id"] is Array, "link_id 落盘形状 = 数组（非 Vector2i 直写）")
	expect_eq((entry["link_id"] as Array).size(), 2, "数组长度 2")
	expect_eq(entry["link_id"], [3, 17], "形状 = [x, y] 显式转换层（§2.2）")
	var text := JSON.stringify(d)
	expect(not text.contains("(3, 17)"), "JSON 文本不得含 \"(3, 17)\" 字符串形状（引擎实测坑）")
	# 数组形状（Godot JSON 紧凑/缩进两种间距形态都认——不锚排版细节）
	expect(text.contains("[3,17]") or text.contains("[3, 17]"),
		"JSON 文本含 [3,17] 数组形状（显式 [x,y] 转换层落盘）")

func test_json_file_roundtrip_preserves_links() -> void:
	var map := _sample_map()
	var w := WorldDataClass.empty()
	var pair := _adjacent_pair_ids(map)
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = WorldDataClass.link_id_of(pair[0], pair[1])
	w.links.append(lk)
	var path := "user://test_world_roundtrip.world.json"
	expect_eq(MapIO.write_world(w, path), OK, "世界伴生文件写入成功")
	var back: Variant = MapIO.read_world(path)
	expect(back is WorldDataClass, "读回为 WorldData（JSON 往返无损）")
	if back is WorldDataClass:
		var b: WorldDataClass = back
		expect_eq(b.to_dict(), w.to_dict(), "往返 to_dict 逐位一致（含 meta/空集合）")
		expect_eq(b.links.size(), 1, "link 数保持")
		expect_eq(b.links[0].link_id, lk.link_id, "link_id 重建一致")
		expect_eq(b.validate(map), "", "读回世界仍过校验（保存→重载同验）")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_from_dict_rejects_bad_shapes() -> void:
	var good := WorldDataClass.empty().to_dict()
	# 版本不符
	var v2 := good.duplicate(true)
	v2["schema_version"] = 2
	expect(WorldDataClass.from_dict(v2) == null, "schema_version 不符 → null")
	# link_id 形状：长度 ≠ 2 / 非整数 / 负分量 / x≥y
	for bad_id in [[3], [3, 17, 5], [3.5, 17], [-1, 17], [17, 3]]:
		var d := good.duplicate(true)
		(d["links"] as Array).append({
			"link_id": bad_id, "road_id": WorldDataClass.ID_NONE,
			"river_reach_id": WorldDataClass.ID_NONE})
		expect(WorldDataClass.from_dict(d) == null,
			"link_id %s 非法形状 → null（无隐式兜底）" % str(bad_id))
	# 字段缺失
	var missing := good.duplicate(true)
	(missing["links"] as Array).append({"link_id": [3, 17]})
	expect(WorldDataClass.from_dict(missing) == null, "link 条目缺字段 → null")
	# JSON float 形状整数可还原（3.0 → 3）
	var floated := good.duplicate(true)
	(floated["links"] as Array).append({
		"link_id": [3.0, 17.0], "road_id": WorldDataClass.ID_NONE,
		"river_reach_id": WorldDataClass.ID_NONE})
	var parsed: Variant = WorldDataClass.from_dict(floated)
	expect(parsed is WorldDataClass, "JSON 数值形状（3.0）可还原（MapData 同款兼容）")

func test_from_dict_rejects_unlocked_collections_and_bad_meta() -> void:
	var good := WorldDataClass.empty().to_dict()
	# POI 已随 T5 WORLD-03 解锁：非空**合法形状**可解析（拍板⑧ 归属进数据）；
	# 条目缺字段仍拒（形状层拒绝，无隐式兜底）
	var d := good.duplicate(true)
	d["pois"] = [{"anything": 1}]
	expect(WorldDataClass.from_dict(d) == null,
		"pois 条目缺字段 → null（形状层拒绝，不产伪字段也不假解析）")
	var bad_states := good.duplicate(true)
	bad_states["states"] = [{"any": 1}]
	expect(WorldDataClass.from_dict(bad_states) == null, "states 条目缺字段 → null")
	var bad_owners := good.duplicate(true)
	bad_owners["cell_owners"] = [-2]
	expect(WorldDataClass.from_dict(bad_owners) == null,
		"cell_owners 值 < -1 → null（值域 {-1} ∪ state_id）")
	for bad in [["roads", [{"any": 1}]], ["crossings", [{"any": 1}]]]:
		var dd := good.duplicate(true)
		dd[bad[0]] = bad[1]
		expect(WorldDataClass.from_dict(dd) == null,
			"%s 条目缺字段 → null（形状层拒绝，无隐式兜底）" % bad[0])
	var meta_bad := good.duplicate(true)
	(meta_bad["meta"] as Dictionary)["seed"] = "seven"
	expect(WorldDataClass.from_dict(meta_bad) == null, "meta.seed 非整数 → null")
	var meta_missing := good.duplicate(true)
	(meta_missing["meta"] as Dictionary).erase("attempt_count")
	expect(WorldDataClass.from_dict(meta_missing) == null, "meta 缺 §10 字段 → null")

# ================= POI / 势力归属（T5 WORLD-03 解锁，拍板⑧）=================

## 5×4 全陆图 + POI/state/owner 合法最小世界（锚 = (2,1)：六邻全界内）
func _settlement_world() -> Array:
	var map := MapDataClass.new(5, 4)
	for cell in map.cells():
		map.set_elevation(cell, 1)
	var world := WorldDataClass.empty()
	var anchor := map.index_of(Hex.axial_of(Vector2i(2, 1)))
	var settlement := WorldDataClass.POIData.new()
	settlement.poi_id = 0
	settlement.kind = WorldDataClass.POIData.Kind.SETTLEMENT
	settlement.cell_id = anchor
	settlement.footprint_cells = [anchor]
	settlement.role = "player_capital"
	world.pois.append(settlement)
	var zone := WorldDataClass.POIData.new()
	zone.poi_id = 1
	zone.kind = WorldDataClass.POIData.Kind.SPAWN_ZONE
	zone.cell_id = anchor
	zone.footprint_cells = [anchor]
	for d in 6:
		zone.footprint_cells.append(map.index_of(Hex.neighbor(Hex.axial_of(Vector2i(2, 1)), d)))
	zone.footprint_cells.sort()
	zone.role = "spawn_zone"
	world.pois.append(zone)
	var state := WorldDataClass.StateData.new()
	state.state_id = 0
	state.capital_poi_id = 0
	state.expansionism = 5
	world.states.append(state)
	world.cell_owners = []
	for i in map.cell_count():
		world.cell_owners.append(0)
	return [map, world]


func test_settlement_roundtrip_and_old_world_compat() -> void:
	var pair := _settlement_world()
	var map: MapDataClass = pair[0]
	var world: WorldDataClass = pair[1]
	expect_eq(world.validate(map), "", "最小势力世界合法")
	# to_dict 键序扩展：pois/states/cell_owners 在册
	var facts := world.to_dict()
	expect((facts["pois"] as Array).size() == 2, "pois 序列化非空（解锁）")
	expect((facts["states"] as Array).size() == 1, "states 序列化")
	expect_eq((facts["cell_owners"] as Array).size(), map.cell_count(), "cell_owners 全长")
	# JSON 往返（真实文件——Vector2i 之类本测试无新增，键序面沿既有锚）
	var path := "user://t5_world_data_poi.world.json"
	expect_eq(MapIO.write_world(world, path), OK, "落盘")
	var back := MapIO.read_world(path)
	expect(back != null, "读回")
	if back != null:
		expect_eq(back.to_dict(), facts, "POI/势力序列化往返逐字节一致")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# 旧图零迁移：T4 时代形状（无 states/cell_owners 键）仍可解析 = 合法空
	var old_shape := WorldDataClass.empty().to_dict()
	old_shape.erase("states")
	old_shape.erase("cell_owners")
	var parsed: Variant = WorldDataClass.from_dict(old_shape)
	expect(parsed is WorldDataClass, "缺 states/cell_owners 键 = 旧图合法空（零迁移）")

func test_poi_shape_rules_rejected() -> void:
	# SPAWN_ZONE 形状钉死：非「中心+六邻」七格 → POI_SHAPE（逐子样独立重建
	# fixture——世界对象可变，跨子样共享会串味）
	var pair1 := _settlement_world()
	var w1: WorldDataClass = pair1[1]
	w1.pois[1].footprint_cells = [w1.pois[1].cell_id]  # 单格出生区
	expect(w1.validate(pair1[0]).contains("POI_SHAPE"),
		"SPAWN_ZONE 单格 → POI_SHAPE（拍板⑩ 中心+六邻恰 7 格）")
	var pair2 := _settlement_world()
	var w2: WorldDataClass = pair2[1]
	w2.pois[1].footprint_cells.remove_at(3)  # 六邻缺一（或恰删锚定格——升序位不定）
	var verdict2 := w2.validate(pair2[0])
	expect(verdict2 != "" and (verdict2.contains("POI_SHAPE") or verdict2.contains("锚定格")),
		"六邻缺一 → 形状拒绝（POI_SHAPE 或缺锚定格，按删位分流）：got %s" % verdict2)
	var pair3 := _settlement_world()
	var w3: WorldDataClass = pair3[1]
	w3.pois[0].footprint_cells = w3.pois[1].footprint_cells.duplicate()
	expect(w3.validate(pair3[0]).contains("POI_SHAPE"),
		"聚落多格 footprint → POI_SHAPE（§9 初版值域）")
	var pair4 := _settlement_world()
	(pair4[1] as WorldDataClass).pois[0].role = ""
	expect((pair4[1] as WorldDataClass).validate(pair4[0]).contains("role"),
		"role 空 → 拒（占位载体须非空）")
	var pair5 := _settlement_world()
	var w5: WorldDataClass = pair5[1]
	var fp: Array[int] = w5.pois[1].footprint_cells.duplicate()
	fp.erase(w5.pois[1].cell_id)
	w5.pois[1].footprint_cells = fp
	expect(w5.validate(pair5[0]).contains("锚定格"), "footprint 缺锚定格 → 拒（§9）")

func test_state_and_owner_invariants_rejected() -> void:
	# 主城对账：capital_poi_id 指向 SPAWN_ZONE → STATE_CAPITAL
	var p1 := _settlement_world()
	(p1[1] as WorldDataClass).states[0].capital_poi_id = 1
	expect((p1[1] as WorldDataClass).validate(p1[0]).contains("STATE_CAPITAL"),
		"主城指向非 SETTLEMENT → 拒")
	# expansionism < 1 → 拒
	var p2 := _settlement_world()
	(p2[1] as WorldDataClass).states[0].expansionism = 0
	expect((p2[1] as WorldDataClass).validate(p2[0]).contains("expansionism"),
		"expansionism 0 → 拒（分母无效）")
	# owner 引用不存在的 state → OWNER_REF
	var p3 := _settlement_world()
	(p3[1] as WorldDataClass).cell_owners[0] = 7
	expect((p3[1] as WorldDataClass).validate(p3[0]).contains("OWNER_REF"),
		"owner 指向不存在 state → 拒")
	# 水格恒 -1：把格 0 压成水（elevation 0）但 owner 仍 0 → OWNER_WATER
	var p4 := _settlement_world()
	(p4[0] as MapDataClass).set_elevation(Hex.axial_of(Vector2i(0, 0)), 0)
	expect((p4[1] as WorldDataClass).validate(p4[0]).contains("OWNER_WATER"),
		"水格 owner ≠ -1 → 拒（水格传播成本不归属）")
	# 空 states + 非 -1 owner → OWNER_NO_STATE；空 states + 全 -1 → 合法（回退态）
	var p5 := _settlement_world()
	(p5[1] as WorldDataClass).states = []
	expect((p5[1] as WorldDataClass).validate(p5[0]).contains("OWNER_NO_STATE"),
		"states 空而 owner 非 -1 → 拒（回退态口径）")
	var p6 := _settlement_world()
	var w6: WorldDataClass = p6[1]
	w6.states = []
	for i in w6.cell_owners.size():
		w6.cell_owners[i] = WorldDataClass.ID_NONE
	expect_eq(w6.validate(p6[0]), "", "states 空且 owner 全 -1 → 合法（POI/归属空集合合法态）")

func test_border_links_derived_from_owner_jumps() -> void:
	# 5×4 图：0..2 行属 state 0、3 行属 state 1 → 跳变边恰在行 2|3 交界；
	# 独立 oracle：全图邻接对两侧 owner 互异集合
	var map := MapDataClass.new(5, 4)
	for cell in map.cells():
		map.set_elevation(cell, 1)
	var world := WorldDataClass.empty()
	var s0 := WorldDataClass.StateData.new()
	s0.state_id = 0
	s0.capital_poi_id = 0
	world.states.append(s0)
	var s1 := WorldDataClass.StateData.new()
	s1.state_id = 1
	s1.capital_poi_id = 0
	world.states.append(s1)
	world.cell_owners = []
	for i in map.cell_count():
		world.cell_owners.append(0 if i < 15 else 1)
	# 主城对账需要 SETTLEMENT poi——本测面只派生国界，validate 面由前测覆盖
	var borders := WorldDataClass.border_links_of(map, world)
	expect(borders.size() > 0, "行 2|3 交界存在跳变边")
	var oracle: Array[Vector2i] = []
	for cell in map.cells():
		var a := map.index_of(cell)
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not map.has_cell(nb):
				continue
			var b := map.index_of(nb)
			if b < a:
				continue
			if world.cell_owners[a] != world.cell_owners[b]:
				oracle.append(WorldDataClass.link_id_of(a, b))
	oracle.sort()
	expect_eq(str(borders), str(oracle), "国界 = 独立 oracle 跳变边集合（派生不落盘）")
	# 有河 link 天然河界：国界边与河边无冲突（集合可交——河界只是跳变边的子型）
	expect_eq(WorldDataClass.border_links_of(map, WorldDataClass.empty()).size(), 0,
		"空归属 → 空国界（归属层关）")

# ================= 旧图零迁移 + 零回写 =================

func test_missing_world_file_returns_empty_legal() -> void:
	var path := "user://definitely_missing_7f3a.world.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var w: Variant = MapIO.read_world(path)
	expect(w is WorldDataClass, "缺伴生文件 → WorldData.empty()（不报错、不重新随机生成）")
	if w is WorldDataClass:
		var e: WorldDataClass = w
		expect_eq(e.to_dict(), WorldDataClass.empty().to_dict(), "缺文件 = empty() 同形状")
		expect_eq(e.links.size(), 0, "无 link（无河无路无 POI 的合法态——§2.2）")
		expect_eq(e.validate(_sample_map()), "", "empty() 对任意图合法")

func test_empty_world_file_returns_empty_legal() -> void:
	# 头注合同「文件缺失/为空 → empty()」的空文件分支（T2 评审修复：此前空文本
	# 经 read_json 返回 null，注释与行为不符）。坏 JSON 仍 null（无数据 ≠ 坏数据，
	# 两分支不得混同——见下）
	var path := "user://test_empty_world_5c1.world.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	expect(f != null, "空世界文件可创建（测试前置）")
	if f == null:
		return
	f.close()
	var w: Variant = MapIO.read_world(path)
	expect(w is WorldDataClass, "空伴生文件 → WorldData.empty()（无数据 ≠ 坏数据）")
	if w is WorldDataClass:
		expect_eq((w as WorldDataClass).to_dict(), WorldDataClass.empty().to_dict(),
			"空文件 = empty() 同形状")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var bad := "user://test_bad_world_5c1.world.json"
	var fb := FileAccess.open(bad, FileAccess.WRITE)
	if fb != null:
		fb.store_string("{not json")
		fb.close()
	expect(MapIO.read_world(bad) == null, "坏 JSON → null（解析失败不冒充空世界）")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad))

func test_world_data_zero_writeback_to_map() -> void:
	var map := _sample_map()
	var before_summary := map.summary()
	var before_digest := map.digest()
	var before_dict := map.to_dict()
	var w := WorldDataClass.empty()
	var pair := _adjacent_pair_ids(map)
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = WorldDataClass.link_id_of(pair[0], pair[1])
	w.links.append(lk)
	var msg := w.validate(map)  # 只读校验（结构性保证——本测试锚定其行为面）
	var _ignored := w.to_dict()
	expect_eq(map.summary(), before_summary, "validate/to_dict 后 summary 逐字节不变（零回写）")
	expect_eq(map.digest(), before_digest, "digest 不变")
	expect_eq(map.to_dict(), before_dict, "to_dict 不变（含 mods——WorldData 永不写入）")
	expect_eq(map.mods.size(), 0, "mods 保持空（草案 §4/mods 铁律）")


# ================= T6 S3：地貌分区/骨架事实 =================

## 分区世界 fixture：6×4 = 24 格，2 区（左 2 列群山 / 右侧平原——odd-r 真实口径），
## 1 条主山系（左区内 3 格脊线）+ 1 支脉（根在脊上）+ 1 宽谷（脊侧带）+
## 格级归属/权重全长。手造 fixture（无生成器——数据层合同的手算面）。
func _regions_world() -> Array:
	var map := MapDataClass.new(6, 4)
	var world := WorldDataClass.empty()
	var rg0 := WorldDataClass.TerrainRegion.new()
	rg0.region_id = 0
	rg0.dominant_landform = WorldDataClass.TerrainRegion.DominantLandform.MOUNTAINS
	rg0.core_cells = [0, 1, 6, 7, 12, 13]
	rg0.adjacency = [1]
	var rg1 := WorldDataClass.TerrainRegion.new()
	rg1.region_id = 1
	rg1.dominant_landform = WorldDataClass.TerrainRegion.DominantLandform.PLAINS
	rg1.core_cells = [4, 5, 10, 11, 16, 17]
	rg1.adjacency = [0]
	world.terrain_regions.append(rg0)
	world.terrain_regions.append(rg1)
	var mr := WorldDataClass.MountainRangeData.new()
	mr.range_id = 0
	mr.region_id = 0
	mr.spine_cells.append(0)
	mr.spine_cells.append(1)
	mr.spine_cells.append(2)
	world.mountain_ranges.append(mr)
	var br := WorldDataClass.RidgeBranchData.new()
	br.branch_id = 0
	br.range_id = 0
	br.cells.append(1)
	br.cells.append(7)
	world.ridge_branches.append(br)
	var vl := WorldDataClass.ValleyData.new()
	vl.valley_id = 0
	vl.range_id = 0
	vl.cells.append(3)
	vl.cells.append(8)
	vl.cells.append(9)
	world.valleys.append(vl)
	var cell_regions: Array[int] = []
	var weights: Array[int] = []
	for i in map.cell_count():
		cell_regions.append(0 if i % 6 < 3 else 1)
		weights.append(900 if i % 6 < 3 else 100)
	world.cell_regions = cell_regions
	world.cell_mountain_weights = weights
	return [map, world]

func test_regions_facts_roundtrip_and_old_world_compat() -> void:
	var pair := _regions_world()
	var map: MapDataClass = pair[0]
	var world: WorldDataClass = pair[1]
	expect_eq(world.validate(map), "", "最小分区世界合法")
	var facts := world.to_dict()
	expect((facts["terrain_regions"] as Array).size() == 2, "分区序列化非空")
	expect((facts["mountain_ranges"] as Array).size() == 1, "主山系序列化")
	expect((facts["ridge_branches"] as Array).size() == 1, "支脉序列化")
	expect((facts["valleys"] as Array).size() == 1, "宽谷序列化")
	expect_eq((facts["cell_regions"] as Array).size(), map.cell_count(), "cell_regions 全长")
	expect_eq((facts["cell_mountain_weights"] as Array).size(), map.cell_count(), "权重场全长")
	# JSON 文件往返（真实落盘——MapIO.write_world 通道）
	var path := "user://t6_world_data_regions.world.json"
	expect_eq(MapIO.write_world(world, path), OK, "落盘")
	var back := MapIO.read_world(path)
	expect(back != null, "读回")
	if back != null:
		expect_eq(back.to_dict(), facts, "分区/骨架序列化往返逐字节一致")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# 旧图零迁移：T5 时代形状（无六键）仍可解析 = 合法空
	var old_shape := WorldDataClass.empty().to_dict()
	for k in ["terrain_regions", "mountain_ranges", "ridge_branches", "valleys",
			"cell_regions", "cell_mountain_weights"]:
		old_shape.erase(k)
	var parsed: Variant = WorldDataClass.from_dict(old_shape)
	expect(parsed is WorldDataClass, "缺六键 = 旧图合法空（零迁移，SCHEMA_VERSION=1 维持）")

func test_regions_facts_shape_rules_rejected() -> void:
	# landform 越界枚举 → REGION_LANDFORM
	var p1 := _regions_world()
	(p1[1] as WorldDataClass).terrain_regions[0].dominant_landform = 7
	expect((p1[1] as WorldDataClass).validate(p1[0]).contains("REGION_LANDFORM"),
		"landform 越界 → 拒（首期两值）")
	# 邻接不对称 → REGION_ADJACENCY
	var p2 := _regions_world()
	(p2[1] as WorldDataClass).terrain_regions[1].adjacency = []
	expect((p2[1] as WorldDataClass).validate(p2[0]).contains("REGION_ADJACENCY"),
		"邻接单边 → 拒（a 列 b ⇔ b 列 a）")
	# 跨区共享核心格 → REGION_CORE_OVERLAP
	var p3 := _regions_world()
	var w3: WorldDataClass = p3[1]
	w3.terrain_regions[1].core_cells = w3.terrain_regions[0].core_cells.duplicate()
	expect(w3.validate(p3[0]).contains("REGION_CORE_OVERLAP"),
		"核心格跨区共享 → 拒")
	# 主山系挂平原区 → RANGE_REGION
	var p4 := _regions_world()
	(p4[1] as WorldDataClass).mountain_ranges[0].region_id = 1
	expect((p4[1] as WorldDataClass).validate(p4[0]).contains("RANGE_REGION"),
		"山系挂平原区 → 拒（平原不承载主山系）")
	# 脊线断裂（非相邻序列）→ spine 相邻连续拒绝
	var p5 := _regions_world()
	(p5[1] as WorldDataClass).mountain_ranges[0].spine_cells = [0, 2, 1]
	expect((p5[1] as WorldDataClass).validate(p5[0]).contains("互为界内邻居"),
		"脊线非相邻序 → 拒（有序序列须相邻连续）")
	# 支脉根不在父脊 → BRANCH_ROOT
	var p6 := _regions_world()
	(p6[1] as WorldDataClass).ridge_branches[0].cells = [5, 11]
	expect((p6[1] as WorldDataClass).validate(p6[0]).contains("BRANCH_ROOT"),
		"支脉根不在父脊 → 拒")
	# 无分区但有骨架 → SKELETON_NO_REGIONS
	var p7 := _regions_world()
	var w7: WorldDataClass = p7[1]
	w7.terrain_regions = []
	w7.cell_regions = []
	w7.cell_mountain_weights = []
	expect(w7.validate(p7[0]).contains("SKELETON_NO_REGIONS"),
		"区域表空而骨架非空 → 拒（没有能力就没有数据）")
	# 格级长度失配 → REGION_CELL_LENGTH
	var p8 := _regions_world()
	(p8[1] as WorldDataClass).cell_regions.remove_at(0)
	expect((p8[1] as WorldDataClass).validate(p8[0]).contains("REGION_CELL_LENGTH"),
		"cell_regions 长度失配 → 拒（行主序逐格对齐）")
	# 权重越界（千分界）→ REGION_WEIGHT_RANGE
	var p9 := _regions_world()
	var w9: WorldDataClass = p9[1]
	w9.cell_mountain_weights[0] = 1001
	expect(w9.validate(p9[0]).contains("REGION_WEIGHT_RANGE"),
		"权重 1001 越界 → 拒（千分整数 0..1000）")
	# 格级归属引用不存在的区域 → REGION_CELL_REF
	var p10 := _regions_world()
	var w10: WorldDataClass = p10[1]
	w10.cell_regions[0] = 9
	expect(w10.validate(p10[0]).contains("REGION_CELL_REF"),
		"归属引用不存在区域 → 拒")

func test_regions_facts_from_dict_shape_gates() -> void:
	# from_dict 形状层（与 validate 语义层分离的纪律）：坏形状 → null 不冒充
	var good := (_regions_world()[1] as WorldDataClass).to_dict()
	var bad_lf := good.duplicate(true)
	(bad_lf["terrain_regions"] as Array)[0]["dominant_landform"] = 5
	expect(WorldDataClass.from_dict(bad_lf) == null, "landform 非两值 → from_dict 拒")
	var bad_w := good.duplicate(true)
	(bad_w["cell_mountain_weights"] as Array)[0] = -1
	expect(WorldDataClass.from_dict(bad_w) == null, "权重负值 → from_dict 拒")
	var bad_rv := good.duplicate(true)
	(bad_rv["cell_regions"] as Array)[0] = -2
	expect(WorldDataClass.from_dict(bad_rv) == null, "归属 < -1 → from_dict 拒")
	var bad_core := good.duplicate(true)
	(bad_core["terrain_regions"] as Array)[0]["core_cells"] = []
	expect(WorldDataClass.from_dict(bad_core) == null, "空核心 → from_dict 拒（伪区域）")
	var bad_spine := good.duplicate(true)
	(bad_spine["mountain_ranges"] as Array)[0]["spine_cells"] = [0]
	expect(WorldDataClass.from_dict(bad_spine) == null, "单格脊线 → from_dict 拒（<2）")

# ================= T6 S4：孤峰事实（isolated_peaks）=================

## 孤峰 fixture：在分区世界（_regions_world 同款）上加两座孤峰——中心在右侧
## 平原区（cell 16/17 列），半径 2/1、峰高 550/300、形状 CONE（首版值域单点）。
func _peaks_world() -> Array:
	var pair := _regions_world()
	var world: WorldDataClass = pair[1]
	var pk0 := WorldDataClass.IsolatedPeakData.new()
	pk0.peak_id = 0
	pk0.cell_id = 16
	pk0.influence_radius = 2
	pk0.peak_height = 550
	pk0.shape = WorldDataClass.IsolatedPeakData.Shape.CONE
	var pk1 := WorldDataClass.IsolatedPeakData.new()
	pk1.peak_id = 1
	pk1.cell_id = 17
	pk1.influence_radius = 1
	pk1.peak_height = 300
	pk1.shape = WorldDataClass.IsolatedPeakData.Shape.CONE
	world.isolated_peaks.append(pk0)
	world.isolated_peaks.append(pk1)
	return pair

func test_peaks_roundtrip_and_old_world_compat() -> void:
	var pair := _peaks_world()
	var map: MapDataClass = pair[0]
	var world: WorldDataClass = pair[1]
	expect_eq(world.validate(map), "", "含孤峰分区世界合法")
	var facts := world.to_dict()
	var peaks: Array = facts["isolated_peaks"]
	expect_eq(peaks.size(), 2, "孤峰序列化两条")
	expect_eq(peaks[0]["peak_id"], 0, "首峰主键")
	expect_eq(peaks[0]["influence_radius"], 2, "影响半径落盘")
	expect_eq(peaks[0]["peak_height"], 550, "峰高千分整数落盘")
	expect_eq(peaks[0]["shape"], WorldDataClass.IsolatedPeakData.Shape.CONE, "形状 CONE 落盘")
	# JSON 文件往返（MapIO.write_world 通道）
	var path := "user://t6_world_data_peaks.world.json"
	expect_eq(MapIO.write_world(world, path), OK, "落盘")
	var back := MapIO.read_world(path)
	expect(back != null, "读回")
	if back != null:
		expect_eq(back.to_dict(), facts, "孤峰序列化往返逐字节一致")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# 旧图零迁移：S3 时代形状（无 isolated_peaks 键）仍可解析 = 合法空
	var old_shape := (_regions_world()[1] as WorldDataClass).to_dict()
	old_shape.erase("isolated_peaks")
	var parsed: Variant = WorldDataClass.from_dict(old_shape)
	expect(parsed is WorldDataClass, "缺 isolated_peaks 键 = 旧图合法空（零迁移）")
	if parsed is WorldDataClass:
		expect((parsed as WorldDataClass).isolated_peaks.is_empty(), "旧图孤峰表空")
	# 查询面：peak_by_id 命中/不命中
	expect(world.peak_by_id(1) != null and world.peak_by_id(1).cell_id == 17,
		"peak_by_id 可解析")
	expect(world.peak_by_id(99) == null, "peak_by_id 不存在 → null")

func test_peaks_shape_rules_rejected() -> void:
	# 半径 0 → PEAK_RADIUS（零半径无影响面）
	var p1 := _peaks_world()
	(p1[1] as WorldDataClass).isolated_peaks[0].influence_radius = 0
	expect((p1[1] as WorldDataClass).validate(p1[0]).contains("PEAK_RADIUS"),
		"半径 0 → 拒")
	# 峰高越界（0 / 1001）→ PEAK_HEIGHT
	var p2 := _peaks_world()
	(p2[1] as WorldDataClass).isolated_peaks[0].peak_height = 0
	expect((p2[1] as WorldDataClass).validate(p2[0]).contains("PEAK_HEIGHT"),
		"峰高 0 → 拒（千分整数 1..1000）")
	var p3 := _peaks_world()
	(p3[1] as WorldDataClass).isolated_peaks[0].peak_height = 1001
	expect((p3[1] as WorldDataClass).validate(p3[0]).contains("PEAK_HEIGHT"),
		"峰高 1001 → 拒")
	# 形状非首版枚举 → PEAK_SHAPE（枚举存在 ≠ 能力开放）
	var p4 := _peaks_world()
	(p4[1] as WorldDataClass).isolated_peaks[0].shape = 5
	expect((p4[1] as WorldDataClass).validate(p4[0]).contains("PEAK_SHAPE"),
		"shape 越界 → 拒（首版值域单点 CONE）")
	# 界外中心 → PEAK_CELL
	var p5 := _peaks_world()
	(p5[1] as WorldDataClass).isolated_peaks[0].cell_id = 999
	expect((p5[1] as WorldDataClass).validate(p5[0]).contains("PEAK_CELL"),
		"中心格界外 → 拒")
	# 主键降序 → 规范序拒
	var p6 := _peaks_world()
	(p6[1] as WorldDataClass).isolated_peaks[0].peak_id = 5
	expect((p6[1] as WorldDataClass).validate(p6[0]).contains("规范序"),
		"主键非升序 → 拒（peak_id 升序规范序）")
	# 无分区但有孤峰 → PEAK_NO_REGIONS（没有能力就没有数据）
	var p7 := _peaks_world()
	var w7: WorldDataClass = p7[1]
	w7.terrain_regions = []
	w7.cell_regions = []
	w7.cell_mountain_weights = []
	w7.mountain_ranges = []
	w7.ridge_branches = []
	w7.valleys = []
	expect(w7.validate(p7[0]).contains("PEAK_NO_REGIONS"),
		"区域表空而孤峰非空 → 拒（孤峰是 regions 路线事实）")

func test_peaks_from_dict_shape_gates() -> void:
	# from_dict 形状层：坏形状 → null 不冒充（值域单点字段形状层即拒——
	# CrossingData.Kind.FERRY 同款纪律）
	var good := (_peaks_world()[1] as WorldDataClass).to_dict()
	var bad_shape := good.duplicate(true)
	(bad_shape["isolated_peaks"] as Array)[0]["shape"] = 1
	expect(WorldDataClass.from_dict(bad_shape) == null, "shape 非 CONE → from_dict 拒")
	var bad_radius := good.duplicate(true)
	(bad_radius["isolated_peaks"] as Array)[0]["influence_radius"] = 0
	expect(WorldDataClass.from_dict(bad_radius) == null, "半径 0 → from_dict 拒")
	var bad_height := good.duplicate(true)
	(bad_height["isolated_peaks"] as Array)[0]["peak_height"] = 0
	expect(WorldDataClass.from_dict(bad_height) == null, "峰高 0 → from_dict 拒")
	var bad_missing := good.duplicate(true)
	(bad_missing["isolated_peaks"] as Array)[0].erase("peak_height")
	expect(WorldDataClass.from_dict(bad_missing) == null, "缺 peak_height 键 → from_dict 拒")
