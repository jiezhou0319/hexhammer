## test_map_data.gd — M1a-T2 地图数据层单测
## 逐条覆盖 04 任务卡 M1a-T2「验收 + 细化新增」：
##   60×40 生成/按 axial 存取；序列化往返逐格一致；扩展位存在但不参与任何结算；
##   地图外形与外沿边界规则（不存在的邻格不得产生悬空连接）显式测试。
## 另覆盖细化交付项：格子遍历顺序固定 + 可比较逐格摘要（T9 复现验收的载体）、
##   格子稳定 ID（T4 边/角归属比较器）、schema_version 字段约定（M2 MapDef 同口径）。
## oracle 原则：外形/邻接的期望值一律由 T1 HexMath（in_bounds/axial_of/neighbor）独立
##   重算对账，不复制 MapData 内部实现——两套来源不一致即为 bug。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")

# ================= 60×40 生成与默认值 =================

func test_60x40_creation_and_defaults() -> void:
	var m := MapDataClass.new(60, 40)
	expect_eq(m.width, 60, "宽 = 60 列")
	expect_eq(m.height, 40, "高 = 40 行")
	expect_eq(m.cell_count(), 2400, "格数 = 2400")
	var cells := m.cells()
	expect_eq(cells.size(), 2400, "遍历格数 = 2400")
	for cell in cells:
		expect_eq(m.terrain_at(cell), 0, "默认地形 0")
		expect_eq(m.elevation_at(cell), 0, "默认高程 0")
		expect(m.is_passable(cell), "默认可通行")
	expect_eq(m.mods, {}, "默认 mods 为空字典")

func test_dims_clamped_nonnegative() -> void:
	var a := MapDataClass.new(0, 0)
	expect_eq(a.cell_count(), 0, "0×0 图无格")
	expect_eq(a.cells().size(), 0, "0×0 遍历为空")
	var b := MapDataClass.new(-3, 5)
	expect_eq(b.width, 0, "负尺寸钳为 0")
	expect_eq(b.height, 5, "正尺寸保留")
	expect_eq(b.cell_count(), 0, "钳后无格")

# ================= 按 axial 存取（60×40） =================

func test_axial_read_write_60x40() -> void:
	var m := MapDataClass.new(60, 40)
	for cell in m.cells():
		var col_row := Hex.offset_of(cell)
		expect(m.set_terrain(cell, (col_row.x * 7 + col_row.y * 3) % 13), "set_terrain 应成功")
		expect(m.set_elevation(cell, (col_row.x + col_row.y) % 9 - 4), "set_elevation 应成功")
		expect(m.set_passable(cell, (col_row.x + col_row.y) % 3 != 0), "set_passable 应成功")
	# 重读校验：同一 axial 处写入/读回一致（40 行图含负 q 格：row39 时 q 最小 −19）
	for cell in m.cells():
		var col_row := Hex.offset_of(cell)
		expect_eq(m.terrain_at(cell), (col_row.x * 7 + col_row.y * 3) % 13,
			"axial 存取地形不一致 %s" % cell)
		expect_eq(m.elevation_at(cell), (col_row.x + col_row.y) % 9 - 4,
			"axial 存取高程不一致（含负层）%s" % cell)
		expect_eq(m.is_passable(cell), (col_row.x + col_row.y) % 3 != 0,
			"axial 存取通行性不一致 %s" % cell)
	# 负 q 格显式锚（odd-r 奇数行右移 → q = col − floor(row/2)）
	var neg_cell := Hex.axial_of(Vector2i(0, 39))
	expect(neg_cell.x < 0, "40 行图应存在负 q 格")
	expect_eq(neg_cell, Vector2i(-19, 39), "row39 col0 的 axial 锚")
	# 覆写：后写胜前写
	var c := Hex.axial_of(Vector2i(59, 39))
	expect(m.set_elevation(c, 7), "覆写应成功")
	expect_eq(m.elevation_at(c), 7, "覆写后读回新值")

func test_passability_independent_of_terrain_and_elevation() -> void:
	var m := MapDataClass.new(6, 5)
	var c := Hex.axial_of(Vector2i(2, 2))
	m.set_terrain(c, 5)
	m.set_elevation(c, 9)
	expect(m.is_passable(c), "改地形/高程不得自动改通行性（映射是内容层职责）")
	m.set_passable(c, false)
	expect_eq(m.terrain_at(c), 5, "改通行性不得动地形")
	expect_eq(m.elevation_at(c), 9, "改通行性不得动高程")
	expect(not m.is_passable(c), "通行性开关生效")

func test_set_terrain_rejects_negative_id() -> void:
	var m := MapDataClass.new(4, 3)
	expect(not m.set_terrain(Vector2i(0, 0), -1), "负地形 id 应被拒绝（哨兵保留）")
	expect_eq(m.terrain_at(Vector2i(0, 0)), 0, "拒绝后原值不变")

# ================= 地图外形（矩形、无缺格无折叠） =================

func test_shape_rect_exact_coverage_60x40() -> void:
	var w := 60
	var h := 40
	var m := MapDataClass.new(w, h)
	var seen := {}
	for cell in m.cells():
		expect(not seen.has(cell), "矩形格折叠重复 %s" % cell)
		seen[cell] = true
		expect(m.has_cell(cell), "cells() 成员应界内 %s" % cell)
	expect_eq(seen.size(), w * h, "互异格数 = 2400")
	# oracle：以 HexMath.in_bounds 全窗口扫描出的界内集合，应恰等于 cells() 集合
	var oracle := {}
	for row in range(-2, h + 2):
		for col in range(-2, w + 2):
			var cell := Hex.axial_of(Vector2i(col, row))
			if Hex.in_bounds(cell, w, h):
				oracle[cell] = true
	expect_eq(oracle.size(), w * h, "oracle 界内格数 = 2400")
	for cell in oracle:
		expect(seen.has(cell), "oracle 界内格不在 cells() 中 %s" % cell)

# ================= 遍历顺序固定 + 稳定 ID =================

func test_traversal_order_row_major_fixed() -> void:
	var m := MapDataClass.new(60, 40)
	var cells := m.cells()
	expect_eq(cells.size(), 2400, "遍历长度")
	var i := 0
	for row in 40:
		for col in 60:
			expect_eq(cells[i], Hex.axial_of(Vector2i(col, row)),
				"遍历序应为行主序（col 内层）idx=%d" % i)
			i += 1
	expect_eq(cells[0], Vector2i(0, 0), "首格 = 原点")
	expect_eq(cells[2399], Hex.axial_of(Vector2i(59, 39)), "末格 = col59,row39")

func test_index_of_bijection_60x40() -> void:
	var m := MapDataClass.new(60, 40)
	var seen := {}
	for cell in m.cells():
		var idx := m.index_of(cell)
		expect(idx >= 0 and idx < 2400, "稳定 ID 应落在 [0,2400) %s" % cell)
		expect(not seen.has(idx), "稳定 ID 重复 %s" % cell)
		seen[idx] = true
	expect_eq(seen.size(), 2400, "稳定 ID 与格一一对应")

# ================= 邻接 / 外沿边界规则（不产生悬空连接） =================

func test_neighbors_match_in_bounds_oracle() -> void:
	var w := 12
	var h := 9
	var m := MapDataClass.new(w, h)
	for cell in m.cells():
		var got := m.neighbors_existing(cell)
		var want: Array[Vector2i] = []
		for dir in 6:
			var n := Hex.neighbor(cell, dir)
			if Hex.in_bounds(n, w, h):
				want.append(n)
		expect_eq(got, want, "邻居集合与 in_bounds oracle 不一致 %s" % cell)
		for n in got:
			expect(m.neighbors_existing(n).has(cell), "邻接不对称 %s→%s" % [cell, n])

func test_no_dangling_connections_beyond_edge_60x40() -> void:
	# 细化新增：地图外沿边界规则——不存在的邻格不得产生悬空连接（数据层表达 =
	# 任何格的界内邻居集合不含界外格；界外格自身查询全闭合，见 out_of_bounds 契约测）。
	var m := MapDataClass.new(60, 40)
	var in_map := {}
	for cell in m.cells():
		in_map[cell] = true
	var edge_count := 0
	for cell in m.cells():
		var ns := m.neighbors_existing(cell)
		if ns.size() < 6:
			edge_count += 1
		for n in ns:
			expect(in_map.has(n), "悬空连接：%s 的邻居 %s 不在图内" % [cell, n])
			expect(m.has_cell(n), "悬空连接：%s 的邻居 %s 判非界内" % [cell, n])
	expect(edge_count > 180, "60×40 外沿（邻居不足 6 的格）应远多于 180，got=%d" % edge_count)

func test_corner_neighbor_anchors_60x40() -> void:
	# odd-r 矩形四角界内邻居（几何锚，防外形约定漂移；由 HexMath 独立手算写死）：
	# 左上 (col0,row0) 偶行 → E、SE 共 2；右上 (col59,row0) → W、SW、SE 共 3；
	# 左下 (col0,row39) 奇行 → E、NE、NW 共 3；右下 (col59,row39) → NW、W 共 2。
	var m := MapDataClass.new(60, 40)
	var want_tl: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	expect_eq(m.neighbors_existing(Hex.axial_of(Vector2i(0, 0))), want_tl, "左上角锚")
	var want_tr: Array[Vector2i] = [
		Hex.axial_of(Vector2i(58, 0)),
		Hex.axial_of(Vector2i(58, 1)),
		Hex.axial_of(Vector2i(59, 1)),
	]
	expect_eq(m.neighbors_existing(Hex.axial_of(Vector2i(59, 0))), want_tr, "右上角锚")
	var want_bl: Array[Vector2i] = [
		Vector2i(-18, 39),  # E
		Vector2i(-18, 38),  # NE
		Vector2i(-19, 38),  # NW
	]
	expect_eq(m.neighbors_existing(Hex.axial_of(Vector2i(0, 39))), want_bl, "左下角锚")
	var want_br: Array[Vector2i] = [
		Vector2i(40, 38),  # NW（dir2 先于 W 的 dir3）
		Vector2i(39, 39),  # W
	]
	expect_eq(m.neighbors_existing(Hex.axial_of(Vector2i(59, 39))), want_br, "右下角锚")

func test_has_neighbor_contract() -> void:
	var m := MapDataClass.new(5, 4)
	for cell in m.cells():
		for dir in 6:
			var n := Hex.neighbor(cell, dir)
			expect_eq(m.has_neighbor(cell, dir), m.has_cell(n),
				"has_neighbor 应等于「邻居界内」%s dir%d" % [cell, dir])
	expect(not m.has_neighbor(Hex.axial_of(Vector2i(-1, 0)), 0), "界外格自身无邻居")
	var one := MapDataClass.new(1, 1)
	for dir in 6:
		expect(not one.has_neighbor(Vector2i(0, 0), dir), "1×1 图无任何方向邻居")
	expect_eq(one.neighbors_existing(Vector2i(0, 0)).size(), 0, "1×1 图邻居列表为空")

func test_out_of_bounds_contract() -> void:
	# 界外查询契约：不存在的格子查询全闭合（无悬空连接的查询面）
	var w := 4
	var h := 3
	var m := MapDataClass.new(w, h)
	var outside: Array[Vector2i] = []
	for row in range(-2, h + 2):
		for col in range(-2, w + 2):
			var inside: bool = col >= 0 and col < w and row >= 0 and row < h
			if not inside:
				outside.append(Hex.axial_of(Vector2i(col, row)))
	expect(outside.size() > 0, "界外样本非空")
	for cell in outside:
		expect(not m.has_cell(cell), "界外被判界内 %s" % cell)
		expect_eq(m.index_of(cell), -1, "界外稳定 ID 应为 −1 %s" % cell)
		expect_eq(m.terrain_at(cell), MapDataClass.TERRAIN_NONE, "界外地形哨兵 %s" % cell)
		expect_eq(m.elevation_at(cell), MapDataClass.ELEVATION_NONE, "界外高程哨兵 %s" % cell)
		expect(not m.is_passable(cell), "界外不可通行（无连接的结算面）%s" % cell)
		expect_eq(m.neighbors_existing(cell).size(), 0, "界外格无邻居 %s" % cell)
	# 界外写入：返回 false、不扩容不生效
	var n0 := m.cell_count()
	for cell in [Hex.axial_of(Vector2i(-1, 0)), Hex.axial_of(Vector2i(w, h)), Vector2i(999, 999)]:
		expect(not m.set_terrain(cell, 5), "界外写地形应拒绝 %s" % cell)
		expect(not m.set_elevation(cell, 5), "界外写高程应拒绝 %s" % cell)
		expect(not m.set_passable(cell, false), "界外写通行性应拒绝 %s" % cell)
	expect_eq(m.cell_count(), n0, "界外写入不得扩容")
	expect_eq(m.terrain_at(Hex.axial_of(Vector2i(0, 0))), 0, "界外写入不得影响界内")

# ================= 序列化往返（逐格一致） =================

func test_serialization_roundtrip_per_cell_60x40() -> void:
	var m := MapDataClass.new(60, 40)
	_fill_random(m, 20261009)
	m.mods = {"note": "扩展位随序列化保存", "future_mod": {"cost": [1, 2, 3]}}
	var d := m.to_dict()
	expect_eq(int(d["schema_version"]), 1, "to_dict 携带 schema_version=1")
	expect_eq(int(d["width"]), 60, "to_dict 宽")
	expect_eq(int(d["height"]), 40, "to_dict 高")
	expect_eq((d["terrain"] as PackedInt32Array).size(), 2400, "to_dict 地形数组尺寸")
	var back := MapDataClass.from_dict(d)
	expect(back != null, "from_dict 应成功")
	if back == null:
		return
	var cells := m.cells()
	expect_eq(back.cells().size(), cells.size(), "往返遍历长度一致")
	for cell in cells:  # 逐格一致（细化新增验收）
		expect_eq(back.terrain_at(cell), m.terrain_at(cell), "往返地形不一致 %s" % cell)
		expect_eq(back.elevation_at(cell), m.elevation_at(cell), "往返高程不一致 %s" % cell)
		expect_eq(back.is_passable(cell), m.is_passable(cell), "往返通行性不一致 %s" % cell)
	expect_eq(back.width, 60, "往返宽")
	expect_eq(back.height, 40, "往返高")
	expect_eq(back.mods, m.mods, "mods 原样往返")
	expect_eq(back.summary(), m.summary(), "往返摘要逐字节一致")
	expect_eq(back.digest(), m.digest(), "往返 digest 一致")

func test_from_dict_rejects_invalid() -> void:
	var gm := MapDataClass.new(60, 40)
	_fill_random(gm, 7)
	var good := gm.to_dict()

	var v1 := good.duplicate(true)
	v1["schema_version"] = 2
	expect(MapDataClass.from_dict(v1) == null, "版本不符应拒")

	var v2 := good.duplicate(true)
	v2.erase("mods")
	expect(MapDataClass.from_dict(v2) == null, "缺字段应拒")

	var v3 := good.duplicate(true)
	v3["elevation"] = PackedInt32Array([0, 0, 0])
	expect(MapDataClass.from_dict(v3) == null, "数组尺寸不符应拒")

	var v4 := good.duplicate(true)
	var bad_pass: Array = []
	bad_pass.resize(2400)
	bad_pass.fill(1)
	bad_pass[1234] = 2
	v4["passable"] = bad_pass
	expect(MapDataClass.from_dict(v4) == null, "通行位非 0/1 应拒")

	var v5 := good.duplicate(true)
	var bad_terrain: Array = []
	bad_terrain.resize(2400)
	bad_terrain.fill(1)
	bad_terrain[7] = -1
	v5["terrain"] = bad_terrain
	expect(MapDataClass.from_dict(v5) == null, "负地形 id 应拒（哨兵不落盘）")

	var v6 := good.duplicate(true)
	v6["terrain"] = "not-an-array"
	expect(MapDataClass.from_dict(v6) == null, "数组类型不符应拒")

	var v7 := good.duplicate(true)
	v7["width"] = -1
	expect(MapDataClass.from_dict(v7) == null, "负尺寸应拒")

	var v8 := good.duplicate(true)
	v8["mods"] = "not-a-dict"
	expect(MapDataClass.from_dict(v8) == null, "mods 非 Dictionary 应拒")

	var v9 := good.duplicate(true)
	v9["schema_version"] = "1"
	expect(MapDataClass.from_dict(v9) == null, "版本非数值应拒")

func test_from_dict_accepts_json_shaped_numbers() -> void:
	# JSON 往返后整数变 float（3 → 3.0）——from_dict 须接受（M2 存档管线友好）
	var m := MapDataClass.new(3, 2)
	m.set_terrain(Hex.axial_of(Vector2i(1, 0)), 4)
	m.set_elevation(Hex.axial_of(Vector2i(2, 1)), -2)
	var t: Array = []
	var e: Array = []
	var p: Array = []
	for cell in m.cells():
		t.append(float(m.terrain_at(cell)))
		e.append(float(m.elevation_at(cell)))
		p.append(1.0 if m.is_passable(cell) else 0.0)
	var json_like := {
		"schema_version": 1.0,
		"width": 3.0,
		"height": 2.0,
		"terrain": t,
		"elevation": e,
		"passable": p,
		"mods": {},
	}
	var back := MapDataClass.from_dict(json_like)
	expect(back != null, "JSON 形状（float 数值）应可还原")
	if back == null:
		return
	expect_eq(back.summary(), m.summary(), "JSON 往返摘要一致")

# ================= mods 扩展位（存在、但不参与任何结算） =================

func test_mods_exist_but_not_in_any_settlement() -> void:
	# 同数据两图、其一塞满杂值 mods：一切查询与摘要必须与空 mods 的图完全一致
	var a := MapDataClass.new(60, 40)
	var b := MapDataClass.new(60, 40)
	_fill_random(a, 99)
	_fill_random(b, 99)
	b.mods = {
		"terrain_mod": {"plains_move_cost": 0.75},
		"cell_mods": {Vector2i(3, 4): {"defense": 2}},
		"junk": [1, "two", {"three": 3.5}],
	}
	expect_eq(b.mods.size(), 3, "扩展位字段存在且可写入")
	expect_eq(a.summary(), b.summary(), "摘要不得受 mods 影响")
	expect_eq(a.digest(), b.digest(), "digest 不得受 mods 影响")
	for cell in a.cells():
		expect_eq(b.terrain_at(cell), a.terrain_at(cell), "地形查询不得受 mods 影响 %s" % cell)
		expect_eq(b.elevation_at(cell), a.elevation_at(cell), "高程查询不得受 mods 影响 %s" % cell)
		expect_eq(b.is_passable(cell), a.is_passable(cell), "通行查询不得受 mods 影响 %s" % cell)
		expect_eq(b.neighbors_existing(cell), a.neighbors_existing(cell), "邻接查询不得受 mods 影响 %s" % cell)
	# 存在性另一面：序列化原样保存（不丢），但依旧不进摘要
	var back := MapDataClass.from_dict(b.to_dict())
	expect(back != null, "带 mods 的图应可序列化")
	if back == null:
		return
	expect_eq(back.mods, b.mods, "mods 随序列化往返")
	expect_eq(back.digest(), a.digest(), "往返后 digest 仍不受 mods 影响")

func test_mods_default_empty() -> void:
	var m := MapDataClass.new(4, 4)
	expect_eq(m.mods, {}, "新图 mods 默认空（04 M1a-T2「空字段」）")
	var d := m.to_dict()
	expect(d.has("mods"), "to_dict 应包含 mods 键（字段位保留）")
	expect_eq(d["mods"], {}, "默认序列化 mods 为空")

# ================= 摘要：固定遍历序 → 可比较 =================

func test_summary_write_order_independent() -> void:
	# 同一份数据按相反顺序写入两张图：摘要必须逐字节一致（读序固定、写序无关）
	var m1 := MapDataClass.new(60, 40)
	var m2 := MapDataClass.new(60, 40)
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var cells := m1.cells()
	var values := {}
	for cell in cells:
		values[cell] = [rng.randi_range(0, 6), rng.randi_range(-4, 4), rng.randf() > 0.2]
	for cell in cells:
		var vals: Array = values[cell]
		m1.set_terrain(cell, vals[0])
		m1.set_elevation(cell, vals[1])
		m1.set_passable(cell, vals[2])
	for i in range(cells.size() - 1, -1, -1):
		var cell: Vector2i = cells[i]
		var vals: Array = values[cell]
		m2.set_terrain(cell, vals[0])
		m2.set_elevation(cell, vals[1])
		m2.set_passable(cell, vals[2])
	expect_eq(m2.summary(), m1.summary(), "写入顺序不得影响摘要")
	expect_eq(m2.digest(), m1.digest(), "写入顺序不得影响 digest")

func test_summary_changes_on_any_core_field() -> void:
	var base := MapDataClass.new(60, 40)
	_fill_random(base, 2026)
	var s0 := base.summary()
	var d0 := base.digest()
	var c1 := Hex.axial_of(Vector2i(10, 10))
	base.set_elevation(c1, base.elevation_at(c1) + 1)
	expect(base.summary() != s0, "高程变更应改变摘要")
	expect(base.digest() != d0, "高程变更应改变 digest")
	var c2 := Hex.axial_of(Vector2i(30, 20))
	base.set_passable(c2, not base.is_passable(c2))
	expect(base.summary() != s0, "通行性变更应改变摘要")
	var c3 := Hex.axial_of(Vector2i(5, 5))
	base.set_terrain(c3, (base.terrain_at(c3) + 1) % 7)
	expect(base.summary() != s0, "地形变更应改变摘要")

func test_summary_literal_anchor() -> void:
	# 摘要格式锚（版本升格时此锚随格式显式更新，勿静默改格式）：
	# "hexmap|v<版本>|<宽>x<高>" + 逐格 ";q,r:地形/高程/通行"（行主序）
	var m := MapDataClass.new(2, 1)
	m.set_elevation(Hex.axial_of(Vector2i(0, 0)), -2)
	m.set_terrain(Hex.axial_of(Vector2i(1, 0)), 3)
	m.set_passable(Hex.axial_of(Vector2i(1, 0)), false)
	expect_eq(m.summary(), "hexmap|v1|2x1;0,0:0/-2/1;1,0:3/0/0", "摘要格式锚")
	expect_eq(m.digest().length(), 64, "digest = sha256 hex（64 字符）")

func test_summary_deterministic_across_instances() -> void:
	var x1 := MapDataClass.new(60, 40)
	var x2 := MapDataClass.new(60, 40)
	_fill_random(x1, 4242)
	_fill_random(x2, 4242)
	expect_eq(x1.digest(), x2.digest(), "同种子同构造 → digest 一致")
	var y1 := MapDataClass.new(60, 40)
	var y2 := MapDataClass.new(60, 40)
	_fill_random(y1, 1)
	_fill_random(y2, 2)
	expect(y1.digest() != y2.digest(), "不同种子 → digest 不同")

# ================= 数据层纯度（不持有场景节点） =================

func test_data_layer_holds_no_scene_nodes() -> void:
	var m := MapDataClass.new(4, 4)
	expect(m is RefCounted, "MapData 应为 RefCounted（ADR-2）")
	# 经 Variant 装载做运行时检查（静态类型上恒假的 is 会被编译器拒绝；
	# 本断言防的是未来把基类改成 Node 的回归）
	var as_variant: Variant = m
	expect(not (as_variant is Node), "MapData 不得是 Node")
	expect(not (as_variant is Resource), "运行时类不预绑 Resource（.tres 化是 M2 MapDef 的事）")
	for v in m.to_dict().values():
		expect(not (v is Node), "序列化值不得含节点")

# ---- 辅助 ----

## 固定 seed 填充 60×40 随机图（同 seed → 同数据；遍历固定行主序，确定性可控）。
## 填充模式而非返回值模式：调用处 MapDataClass.new() 可静态推断类型，
## 不依赖全局 class_name 注册时序（tests/test_case.gd 头注约定同源）。
func _fill_random(m, seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for cell in m.cells():
		m.set_terrain(cell, rng.randi_range(0, 6))
		m.set_elevation(cell, rng.randi_range(-4, 4))
		m.set_passable(cell, rng.randf() > 0.2)
