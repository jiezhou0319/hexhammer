## test_roads.gd — T4 ROAD-01 道路图与路口单测（执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §5 ROAD-01 + §2.3/§2.4 横切对账 +
##   数据合同草案 §7（已转正））
## 覆盖锚（卡表「测试锚」逐条）：
##   - 相邻双向一致：link.road_id 从道路序列投影两侧查询同值（双向对账）；
##   - 端点/直路/转弯/三叉/四叉 fixture 同一 data contract；构型等价类穷举锚
##     （6 邻方向子集 64 − 旋转等价类 = **14 个 necklaces 含空集**——Catlike
##     GetRoadInterpolators 14 构型通式的本作转译口径）；
##   - 非法高差拒绝：阈值来自生成配置（数据层只校验「有配置才拒」——
##     max_road_delta=-1 时 Δ 大也合法）；
##   - 序列化往返 + road_class≠0 拒绝（值域单点锚）；
##   - 零回写 MapData；固定图数据化面（东西横路 + link 引用面）。
## oracle 原则：期望邻接/方向子集由 MapData/HexMath 原语独立推导（index_of /
##   dir_between / neighbors），不复制 WorldData 内部比较器；旋转等价类计数由
##   测试侧独立枚举（规范化最小旋转代表），不调用实现侧任何函数。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapIO := preload("res://scripts/content/map_io.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")

const MAP_W := 11
const MAP_H := 8

# ================= fixture 构造 =================

## 测试基图：全草/高程 1/可通行（路面与高程无关——Δ 检查单独构造）
func _base_map() -> MapDataClass:
	return MapDataClass.new(MAP_W, MAP_H)


## 世界 + 一条 cells 格序列道路（link 表自动投影 + 升序规范序）。
## cells 传 axial 格序列（调用方拼形状），返回 WorldData（road_id=0）。
func _world_with_road(map: MapDataClass, path_cells: Array[Vector2i]) -> WorldDataClass:
	var w := WorldDataClass.empty()
	var road := WorldDataClass.RoadData.new()
	road.road_id = 0
	for cell in path_cells:
		road.cells.append(map.index_of(cell))
	w.roads.append(road)
	for i in road.cells.size() - 1:
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = WorldDataClass.link_id_of(road.cells[i], road.cells[i + 1])
		lk.road_id = 0
		w.links.append(lk)
	w.links.sort_custom(func(a: WorldDataClass.NeighborLinkData,
			b: WorldDataClass.NeighborLinkData) -> bool:
		return a.link_id.x < b.link_id.x or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y))
	return w


## 多路世界（路口 = 多路共享 cell）：每条路 2 格（中心格 → 方向 d 邻格）。
## 返回 {"world": WorldData, "center": Vector2i}。
func _junction_world(map: MapDataClass, center: Vector2i,
		dirs: Array[int]) -> Dictionary:
	var w := WorldDataClass.empty()
	for i in dirs.size():
		var road := WorldDataClass.RoadData.new()
		road.road_id = i
		road.cells = [map.index_of(center), map.index_of(Hex.neighbor(center, dirs[i]))]
		w.roads.append(road)
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = WorldDataClass.link_id_of(road.cells[0], road.cells[1])
		lk.road_id = road.road_id
		w.links.append(lk)
	w.links.sort_custom(func(a: WorldDataClass.NeighborLinkData,
			b: WorldDataClass.NeighborLinkData) -> bool:
		return a.link_id.x < b.link_id.x or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y))
	return {"world": w, "center": center}

# ================= 形状 fixture：端点/直路/转弯（同一 data contract）=================

func test_endpoint_straight_bend_same_contract() -> void:
	var map := _base_map()
	# 端点 = 2 格；直路 = 4 格同向；转弯 = 3 格折 60°——三形状同一合同全部合法
	var endpoint := _world_with_road(map, [Hex.axial_of(Vector2i(1, 1)), Hex.neighbor(Hex.axial_of(Vector2i(1, 1)), 0)])
	expect_eq(endpoint.validate(map), "", "端点路（2 格）合法")
	var base := Hex.axial_of(Vector2i(2, 3))
	var straight: Array[Vector2i] = [base, Hex.neighbor(base, 0),
		Hex.neighbor(Hex.neighbor(base, 0), 0), Hex.neighbor(Hex.neighbor(Hex.neighbor(base, 0), 0), 0)]
	var w_straight := _world_with_road(map, straight)
	expect_eq(w_straight.validate(map), "", "直路（4 格同向）合法")
	var bend: Array[Vector2i] = [base, Hex.neighbor(base, 0), Hex.neighbor(Hex.neighbor(base, 0), 1)]
	var w_bend := _world_with_road(map, bend)
	expect_eq(w_bend.validate(map), "", "弯路（3 格折 60°）合法")
	# link.road_id 双向对账：从序列投影出的每条 link，从两侧任一格查询同值
	#（link_id_of 交换律 = 双向一致；同时校验 link 表条目 road_id == 道路 id）
	for i in straight.size() - 1:
		var a := straight[i]
		var b := straight[i + 1]
		var from_a := WorldDataClass.link_id_of(map.index_of(a), map.index_of(b))
		var from_b := WorldDataClass.link_id_of(map.index_of(b), map.index_of(a))
		expect_eq(from_a, from_b, "link_id 规范化与查询方向无关（双向一致）i=%d" % i)
		var found := false
		for lk in w_straight.links:
			if lk.link_id == from_a:
				found = true
				expect_eq(lk.road_id, 0, "两侧查询同值：link.road_id = 道路 0（双向对账）i=%d" % i)
		expect(found, "相邻对 %s→%s 在 link 表有条目（投影完整）i=%d" % [str(a), str(b), i])

func test_junction_three_way_four_way_share_cell_not_link() -> void:
	# 三叉/四叉 = 多路共享中心格（重数合法）；共享 **link**（两路跨接同一边）非法
	var map := _base_map()
	var center := Hex.axial_of(Vector2i(4, 3))
	for set in [[0, 2, 4], [0, 1, 3, 4]]:
		var dirs: Array[int] = []
		for d in set:
			dirs.append(d)
		var fix := _junction_world(map, center, dirs)
		var w: WorldDataClass = fix["world"]
		expect_eq(w.validate(map), "", "多路共享格成路口合法（方向子集 %s）" % str(dirs))
	# 两路跨接同一条 link → ROAD_LINK_REUSE（link.road_id 单值）
	var clash_dirs: Array[int] = [0, 3]
	var clash := _junction_world(map, center, clash_dirs)
	# 第二条路改走同一条边（center→东邻被 road 0 占用）
	var dup := WorldDataClass.RoadData.new()
	dup.road_id = 9
	dup.cells = clash["world"].roads[0].cells.duplicate()
	clash["world"].roads.append(dup)
	var msg := (clash["world"] as WorldDataClass).validate(map)
	expect(msg.contains("ROAD_LINK_REUSE"), "两路共享同一条 link 被拒（got：%s）" % msg)

func test_config_enumeration_and_14_rotation_classes() -> void:
	# 构型等价类穷举锚：6 邻方向子集 64 个 → 旋转等价类 14（含空集 = Catlike
	# 14 构型通式的转译口径）；每个非空子集 = 中心格多条 2 格路，同一 data
	# contract 全部合法。等价类计数由测试侧独立枚举（最小旋转代表）。
	var classes := {}  # 规范代表（mask 的最小旋转值）→ true
	var valid_count := 0
	for mask in 64:
		var dirs: Array[int] = []
		for d in 6:
			if mask & (1 << d) != 0:
				dirs.append(d)
		var canon := mask
		for rot in 6:
			var rotated := 0
			for d in 6:
				if mask & (1 << d) != 0:
					rotated |= 1 << ((d + rot) % 6)
			canon = mini(canon, rotated)
		classes[canon] = true
		if dirs.is_empty():
			continue
		var map := _base_map()
		var center := Hex.axial_of(Vector2i(4, 3))
		var fix := _junction_world(map, center, dirs)
		var w: WorldDataClass = fix["world"]
		var msg := w.validate(map)
		expect_eq(msg, "", "方向子集 %s（mask %d）同合同合法" % [str(dirs), mask])
		valid_count += 1
	expect_eq(classes.size(), 14, "64 子集旋转归并 = 14 等价类（Catlike 14 构型通式口径）")
	expect_eq(valid_count, 63, "非空子集 63 个全部枚举")

func test_road_rejects_structural_violations() -> void:
	var map := _base_map()
	# 断路：相邻两格不互为邻居（跨两格）
	var a := Hex.axial_of(Vector2i(1, 1))
	var far := Hex.neighbor(Hex.neighbor(a, 0), 0)
	var w1 := _world_with_road(map, [a, far])
	var m1 := w1.validate(map)
	expect(m1.contains("界内邻居"), "非邻居相邻对被拒（got：%s）" % m1)
	# 重复格（单路内格不重复）——手工建 link 表只挂一条（重复格的拒绝面在
	# roads 层，勿让 link 重复先炸：_world_with_road 会按相邻对重复投影）
	var b := Hex.axial_of(Vector2i(2, 3))
	var w2 := WorldDataClass.empty()
	var dup_road := WorldDataClass.RoadData.new()
	dup_road.road_id = 0
	dup_road.cells = [map.index_of(b), map.index_of(Hex.neighbor(b, 0)), map.index_of(b)]
	w2.roads.append(dup_road)
	var dup_lk := WorldDataClass.NeighborLinkData.new()
	dup_lk.link_id = WorldDataClass.link_id_of(dup_road.cells[0], dup_road.cells[1])
	dup_lk.road_id = 0
	w2.links.append(dup_lk)
	var m2 := w2.validate(map)
	expect(m2.contains("重复格"), "重复格被拒（link 不复用，got：%s）" % m2)
	# 环路：3 格闭环合法（闭合边同样进对账）；闭合不了的 is_loop 非法
	var ring: Array[Vector2i] = [b, Hex.neighbor(b, 0), Hex.neighbor(Hex.neighbor(b, 0), 4)]
	# b→E→SW 邻——三点两两相邻成环（第三边闭合 b↔SW 邻：dir_between 验证前提）
	expect(Hex.dir_between(ring[0], ring[2]) >= 0, "构造前提：环第三边相邻")
	var w3 := _world_with_road(map, ring)
	w3.roads[0].is_loop = true
	w3.links.append(_link_entry(map, ring[2], ring[0], 0))
	w3.links.sort_custom(_order)
	expect_eq(w3.validate(map), "", "3 格环路合法（闭合边进对账）")
	var w4 := _world_with_road(map, ring)
	w4.roads[0].is_loop = true
	var m4 := w4.validate(map)
	expect(m4.contains("界内邻居") or m4.contains("LINK_ROAD_MISMATCH"),
		"未闭合/缺闭合边对账的环路被拒（got：%s）" % m4)

func _link_entry(map: MapDataClass, a: Vector2i, b: Vector2i, road_id: int) -> WorldDataClass.NeighborLinkData:
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = WorldDataClass.link_id_of(map.index_of(a), map.index_of(b))
	lk.road_id = road_id
	return lk

func _order(a: WorldDataClass.NeighborLinkData, b: WorldDataClass.NeighborLinkData) -> bool:
	return a.link_id.x < b.link_id.x or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y)

func test_road_rejects_class_and_pois_value_domain() -> void:
	var map := _base_map()
	var a := Hex.axial_of(Vector2i(2, 3))
	var w := _world_with_road(map, [a, Hex.neighbor(a, 0)])
	w.roads[0].road_class = 1
	var msg := w.validate(map)
	expect(msg.contains("ROAD_CLASS"), "road_class≠0 被拒（值域单点，got：%s）" % msg)
	var w2 := _world_with_road(map, [a, Hex.neighbor(a, 0)])
	w2.roads[0].connects_pois = [0]
	expect(w2.validate(map).contains("ROAD_POI"), "connects_pois 非空被拒（POI 属 T5）")

func test_road_delta_rejected_only_with_config() -> void:
	# 「有配置才拒」：Δ2 相邻对无配置（-1）合法；max_road_delta=1 拒；被 crossing
	# 认领的河 link 跳过（桥面高差归桥址校验管辖——桥部分见 test_bridges）
	var map := _base_map()
	var a := Hex.axial_of(Vector2i(2, 3))
	var b := Hex.neighbor(a, 0)
	map.set_elevation(a, 1)  # 基高程显式（默认 0——Δ 断言的前提由本行钉死）
	map.set_elevation(b, 3)  # Δ2
	var w := _world_with_road(map, [a, b])
	expect_eq(w.validate(map), "", "无配置（max=-1）Δ2 修路合法（阈值属生成配置不进数据）")
	var msg := w.validate(map, -1, 1)
	expect(msg.contains("ROAD_DELTA"), "max_road_delta=1 时 Δ2 被拒（got：%s）" % msg)
	var with_wide_config := w.validate(map, -1, 2)
	expect_eq(with_wide_config, "", "max_road_delta=2 时 Δ2 合法（阈值边界含等号）")

func test_road_serialization_roundtrip() -> void:
	var map := _base_map()
	var a := Hex.axial_of(Vector2i(2, 3))
	var cells: Array[Vector2i] = [a, Hex.neighbor(a, 0), Hex.neighbor(Hex.neighbor(a, 0), 1)]
	var w := _world_with_road(map, cells)
	var d := w.to_dict()
	expect((d["roads"] as Array).size() == 1, "落盘道路 1 条")
	var entry: Dictionary = (d["roads"] as Array)[0]
	expect(entry["cells"] is Array, "cells 落盘形状 = int 数组")
	expect_eq(entry["is_loop"], false, "is_loop 落盘 bool")
	var path := "user://test_roads_rt.world.json"
	expect_eq(MapIO.write_world(w, path), OK, "世界伴生文件写入成功")
	var back: Variant = MapIO.read_world(path)
	expect(back is WorldDataClass, "读回 WorldData")
	if back is WorldDataClass:
		var b: WorldDataClass = back
		expect_eq(b.to_dict(), w.to_dict(), "往返 to_dict 逐位一致")
		expect_eq(b.roads[0].cells, w.roads[0].cells, "cells 重建一致")
		expect_eq(b.validate(map), "", "读回世界仍过校验")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# 值域单点锚：road_class≠0 / 非空 connects_pois → from_dict null
	var good := w.to_dict()
	for patch in [{"road_class": 2}, {"connects_pois": [3]}]:
		var dd := good.duplicate(true)
		for k in patch:
			((dd["roads"] as Array)[0] as Dictionary)[k] = patch[k]
		expect(WorldDataClass.from_dict(dd) == null,
			"%s 非法 → null（值域单点/未解锁在形状层拒）" % str(patch))
	# cells 形状：负值/非整数 → null
	for bad_cells in [[-1, 5], [1.5, 5]]:
		var dd := good.duplicate(true)
		((dd["roads"] as Array)[0] as Dictionary)["cells"] = bad_cells
		expect(WorldDataClass.from_dict(dd) == null,
			"cells %s → null（无隐式兜底）" % str(bad_cells))

func test_road_zero_writeback_to_map() -> void:
	var map := _base_map()
	var a := Hex.axial_of(Vector2i(2, 3))
	var before := map.summary()
	var w := _world_with_road(map, [a, Hex.neighbor(a, 0)])
	var _ignored := w.validate(map)
	var _ignored2 := w.to_dict()
	expect_eq(map.summary(), before, "validate/to_dict 前后 summary 逐字节不变（零回写）")
	expect_eq(map.mods.size(), 0, "mods 保持空")

# ================= 固定图数据化面（ROAD-01 ③ + ROAD-02 固定图桥）=================

func test_fixed_map_road_and_bridge_present() -> void:
	var map := MapIO.read_map(MapIO.FIXED_MAP_PATH)
	expect(map != null, "固定图应可加载")
	if map == null:
		return
	var world: Variant = MapIO.read_world(MapIO.world_path_for(MapIO.FIXED_MAP_PATH))
	expect(world is WorldDataClass, "固定图世界伴生文件应可加载")
	if not (world is WorldDataClass):
		return
	var w: WorldDataClass = world
	expect(w.roads.size() >= 1, "固定图至少一条路（东西横路）")
	expect(w.crossings.size() >= 1, "固定图至少一座桥（跨正弦河）")
	# 水体 terrain 对账（3 号槽）+ 严格示范配置（max_road_delta=1 / 桥头 Δ≤1）——
	# 横路等高行与 Δ0 平桥在严格档下也过（行扫描口径的固定图面）
	expect_eq(w.validate(map, 3, 1, 1), "", "固定图世界过全量校验（含路/桥对账与严格 Δ 配置）")
	if w.roads.is_empty() or w.crossings.is_empty():
		return
	# 横路投影完整：每相邻对在 link 表有 road_id=0 条目（双向对账的固定图面）
	var road := w.roads[0]
	for i in road.cells.size() - 1:
		var link := WorldDataClass.link_id_of(road.cells[i], road.cells[i + 1])
		var found := false
		for lk in w.links:
			if lk.link_id == link:
				found = lk.road_id == 0
		expect(found, "横路相邻对 %s 有 road_id=0 条目 i=%d" % [str(link), i])
	# 桥：两岸 = 跨河边两端格、两岸都在道路序列中（两岸都有路）
	var c := w.crossings[0]
	expect_eq(c.kind, WorldDataClass.CrossingData.Kind.BRIDGE, "固定图桥 kind=BRIDGE")
	expect(c.bank_a == c.river_edge.x and c.bank_b == c.river_edge.y,
		"两岸格 == river_edge 两端格")
	expect(road.cells.has(c.bank_a) and road.cells.has(c.bank_b), "两岸格均在横路序列中（两岸都有路）")
	expect_eq(map.elevation_at(Hex.axial_of(Vector2i(c.bank_a % map.width, c.bank_a / map.width))),
		map.elevation_at(Hex.axial_of(Vector2i(c.bank_b % map.width, c.bank_b / map.width))),
		"固定图桥两岸等高（Δ0 平桥——行扫描口径）")
