## test_terrain_view_data.gd — T6 S2 前置「调试预览」数据面单测（tools/terrain_view_data.gd）
## 覆盖（沿 tools/land_matrix_fixtures.gd「纯逻辑件 + tests 逐行为锚定」先例）：
##   - height/slope/passability 三实做视图的归一化口径：手工小图独立手算 oracle
##     （值、色、退化态、图序 = cells() 固定遍历序）；
##   - passability 与 MapConnectivity.check 的对账（分量数/口径复读、不二算）+
##     分级着色（大小降序秩、并列首发现序决胜——确定性锚）；
##   - region/skeleton 挂点「显式未实现」合同（implemented=false + 具名原因，
##     不冒充——提案「关闭尚未实现能力不产生伪字段」锚）；
##   - derive() 分派（实做路由到位 / 挂点 / 未知名显式拒绝）。
## oracle 原则：全部期望值手算（无生成器、无随机）；同图两次派生一致（纯函数确定性）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapConnectivity := preload("res://scripts/content/map_connectivity.gd")
const Views := preload("res://tools/terrain_view_data.gd")

# ================= 视图清单与挂点合同 =================

func test_view_order_contains_five_with_two_hooks() -> void:
	expect_eq(Views.VIEW_ORDER, ["height", "slope", "passability", "region", "skeleton"],
		"视图固定序 = 提案 :236 五视图（region/skeleton 为挂点）")
	expect_eq(Views.IMPLEMENTED_VIEWS, ["height", "slope", "passability"],
		"实做视图恰三（region/skeleton 依赖 S3/S4 数据未落地）")
	for v in Views.VIEW_ORDER:
		expect(Views.IMPLEMENTED_VIEWS.has(v) or ["region", "skeleton"].has(v),
			"视图名只允许已知五者：%s" % v)

func test_region_skeleton_stubs_explicitly_unimplemented() -> void:
	# 「未实做时显式报未实现，不冒充」的机器锚：挂点返回 implemented=false +
	# 具名原因（防后续有人把挂点悄悄填成恒绿假数据）
	var map := MapDataClass.new(2, 2)
	var region: Dictionary = Views.region_view(map)
	expect_eq(region["view"], "region", "region 视图名回显")
	expect_eq(region["implemented"], false, "region 挂点必须显式未实现")
	expect(String(region["reason"]).contains("未实现"), "region 原因须具名「未实现」：%s"
		% str(region["reason"]))
	var skeleton: Dictionary = Views.skeleton_view(map)
	expect_eq(skeleton["view"], "skeleton", "skeleton 视图名回显")
	expect_eq(skeleton["implemented"], false, "skeleton 挂点必须显式未实现")
	expect(String(skeleton["reason"]).contains("未实现"), "skeleton 原因须具名「未实现」：%s"
		% str(skeleton["reason"]))

# ================= 高度灰度 =================

func test_height_view_normalization_hand_computed() -> void:
	# 手算 oracle：4×1 行图高程 [0,1,3,4] → min=0 max=4 range=4 → 灰 [0, 0.25, 0.75, 1]
	var map := MapDataClass.new(4, 1)
	for col in 4:
		map.set_elevation(Hex.axial_of(Vector2i(col, 0)), [0, 1, 3, 4][col])
	var data := Views.height_view(map)
	expect_eq(data["implemented"], true, "height 恒实做")
	expect_eq(data["min_elevation"], 0, "min = 0")
	expect_eq(data["max_elevation"], 4, "max = 4")
	expect_eq(data["range"], 4, "range = 4")
	var want := [0.0, 0.25, 0.75, 1.0]
	var values: PackedFloat32Array = data["values"]
	expect_eq(values.size(), 4, "values 与格数同长")
	for i in 4:
		expect_almost_eq(values[i], want[i], 1e-6, "灰度归一 %d" % i)
	var colors: PackedColorArray = data["colors"]
	for i in 4:
		var c: Color = colors[i]
		expect_almost_eq(c.r, want[i], 1e-6, "色 R = 灰度值 %d" % i)
		expect(c.r == c.g and c.g == c.b, "灰度色三通道相等 %d" % i)

func test_height_view_uniform_field_is_half_gray() -> void:
	# 常数场退化态：range=0 → 恒 0.5（统一中灰显式态——区别于「未渲染」）
	var map := MapDataClass.new(3, 2)
	for cell in map.cells():
		map.set_elevation(cell, 2)
	var data := Views.height_view(map)
	expect_eq(data["range"], 0, "常数场 range = 0")
	for v in data["values"]:
		expect_almost_eq(v, 0.5, 1e-6, "常数场灰度恒 0.5")
	for c in data["colors"]:
		expect_almost_eq(c.r, 0.5, 1e-6, "常数场色恒中灰")

func test_height_view_monotonic_in_elevation() -> void:
	# 单调性：高程不降 → 灰度不降（含水 0 档参与归一）
	var map := MapDataClass.new(6, 2)
	var cells := map.cells()
	for i in cells.size():
		map.set_elevation(cells[i], i % 5)
	var data := Views.height_view(map)
	var values: PackedFloat32Array = data["values"]
	for i in cells.size():
		for j in cells.size():
			var ei: int = map.elevation_at(cells[i])
			var ej: int = map.elevation_at(cells[j])
			if ei < ej:
				expect(values[i] <= values[j] + 1e-6, "高程低者灰度不高于高者（%d<%d）" % [ei, ej])
			elif ei == ej:
				expect_almost_eq(values[i], values[j], 1e-6, "同高程同灰度")

func test_height_view_deterministic_and_order_is_cells() -> void:
	var map := MapDataClass.new(4, 3)
	var cells := map.cells()
	for i in cells.size():
		map.set_elevation(cells[i], (i * 7) % 5)
	var a := Views.height_view(map)
	var b := Views.height_view(map)
	expect_eq(a["values"], b["values"], "纯函数：同图两次派生一致")
	expect_eq(str(a["colors"]), str(b["colors"]), "色一致")
	# 图序 = cells() 固定遍历序（渲染面与测试面同一口径）
	expect_eq((a["values"] as PackedFloat32Array).size(), map.cell_count(), "长度 = 格数")

# ================= 坡度 =================

func test_slope_view_hand_computed_step_edges() -> void:
	# 手算 oracle：4×1 行图高程 [0,0,2,2]（行 0 各格只东西相邻）：
	# 邻差 col0|0-0|=0、col1 max(|0-0|,|0-2|)=2、col2 max(|2-0|,|2-2|)=2、col3|2-2|=0
	# → max_slope=2 → 灰 [0,1,1,0]
	var map := MapDataClass.new(4, 1)
	for col in 4:
		map.set_elevation(Hex.axial_of(Vector2i(col, 0)), [0, 0, 2, 2][col])
	var data := Views.slope_view(map)
	expect_eq(data["max_slope"], 2, "max_slope = 2")
	var want := [0.0, 1.0, 1.0, 0.0]
	var values: PackedFloat32Array = data["values"]
	for i in 4:
		expect_almost_eq(values[i], want[i], 1e-6, "坡度灰 %d" % i)

func test_slope_view_flat_map_all_dark() -> void:
	# 全平退化态：max_slope=0 → 恒 0.0（无坡 = 最暗——与 height 常数场 0.5 显式区分）
	var map := MapDataClass.new(3, 3)
	for cell in map.cells():
		map.set_elevation(cell, 1)
	var data := Views.slope_view(map)
	expect_eq(data["max_slope"], 0, "全平 max_slope = 0")
	for v in data["values"]:
		expect_almost_eq(v, 0.0, 1e-6, "全平坡度灰恒 0")
	for c in data["colors"]:
		expect_almost_eq(c.r, 0.0, 1e-6, "全平色恒纯黑（数据面最暗）")

func test_slope_view_single_cell_no_neighbors() -> void:
	# 1×1 图无邻居 → 坡 0（空邻集的显式退化，不越界）
	var map := MapDataClass.new(1, 1)
	var data := Views.slope_view(map)
	expect_eq(data["max_slope"], 0, "1×1 无邻居 max_slope = 0")
	expect_almost_eq((data["values"] as PackedFloat32Array)[0], 0.0, 1e-6, "1×1 灰 = 0")

func test_slope_view_uses_existing_neighbors_only() -> void:
	# 边界格只用界内邻居：2×1 图高程 [0,3] → 两格坡均 3（各自唯一邻居）
	var map := MapDataClass.new(2, 1)
	map.set_elevation(Hex.axial_of(Vector2i(0, 0)), 0)
	map.set_elevation(Hex.axial_of(Vector2i(1, 0)), 3)
	var data := Views.slope_view(map)
	expect_eq(data["max_slope"], 3, "2×1 互为唯一邻居 → 坡 3")
	var values: PackedFloat32Array = data["values"]
	expect_almost_eq(values[0], 1.0, 1e-6, "col0 灰 = 1")
	expect_almost_eq(values[1], 1.0, 1e-6, "col1 灰 = 1")

# ================= 可用通行连通片（MapConnectivity 口径 + 分级着色）=================

func test_passability_view_matches_connectivity_report() -> void:
	# 对账锚：分量数/最大片/占比/通行总数 = MapConnectivity.check 原值（复读不二算）
	var map := _split_map()
	var report := MapConnectivity.check(map)
	var data := Views.passability_view(map)
	expect_eq(data["passable_total"], report["passable_total"], "通行格总数对账")
	expect_eq(data["component_count"], report["component_count"], "分量数对账")
	expect_eq(data["largest_size"], report["largest_size"], "最大片对账")
	expect_almost_eq(float(data["largest_fraction"]), float(report["largest_fraction"]), 1e-9,
		"最大片占比对账")
	expect_eq(data["ok"], report["ok"], "判定对账")
	expect_eq(data["isolated_count"], (report["isolated_cells"] as Array).size(), "孤岛计数对账")

func test_passability_view_split_map_two_ranks() -> void:
	# 手算 oracle：5×5 图 col2 全水 → 左右各 10 格；左片先发现（行主序）→ 秩 0 亮灰，
	# 右片秩 1；水格 = IMPASSABLE_COLOR；ranks 与色板一致
	var map := _split_map()
	var data := Views.passability_view(map)
	expect_eq(data["component_count"], 2, "两片")
	var sizes: Array = data["component_sizes"]
	expect_eq(sizes, [10, 10], "分级序 = 大小降序（并列保持发现序）")
	var colors: PackedColorArray = data["colors"]
	var ranks: PackedInt32Array = data["ranks"]
	var cells := map.cells()
	for i in cells.size():
		var col := Hex.offset_of(cells[i]).x
		if col == 2:
			expect(colors[i].is_equal_approx(Views.IMPASSABLE_COLOR), "水格 = 不可通行色 %s" % cells[i])
			expect_eq(ranks[i], -1, "水格秩 = -1 %s" % cells[i])
		elif col < 2:
			expect(colors[i].is_equal_approx(Views.component_color(0)), "左片 = 秩 0 亮灰 %s" % cells[i])
			expect_eq(ranks[i], 0, "左片秩 0 %s" % cells[i])
		else:
			expect(colors[i].is_equal_approx(Views.component_color(1)), "右片 = 秩 1 %s" % cells[i])
			expect_eq(ranks[i], 1, "右片秩 1 %s" % cells[i])

func test_passability_view_size_ranking_dominates_discovery() -> void:
	# 大小降序优先于发现序：6×1 图 col3 水 → 左 3 格（先发现）右 2 格（后发现），
	# 但左片大 → 秩 0；右片小 → 秩 1（红）——「分级」按大小不按左右
	var map := MapDataClass.new(6, 1)
	map.set_passable(Hex.axial_of(Vector2i(3, 0)), false)
	var data := Views.passability_view(map)
	expect_eq(data["component_sizes"], [3, 2], "分级序 [3,2]")
	var colors: PackedColorArray = data["colors"]
	var ranks: PackedInt32Array = data["ranks"]
	var cells := map.cells()
	for i in cells.size():
		var col := Hex.offset_of(cells[i]).x
		if col == 3:
			expect_eq(ranks[i], -1, "水格秩 -1")
		elif col < 3:
			expect_eq(ranks[i], 0, "左片（大）秩 0")
			expect(colors[i].is_equal_approx(Views.component_color(0)), "左片亮灰")
		else:
			expect_eq(ranks[i], 1, "右片（小）秩 1")
			expect(colors[i].is_equal_approx(Views.component_color(1)), "右片色板第 2 项")

func test_passability_view_tie_break_by_discovery_order() -> void:
	# 并列大小决胜：5×5 图 col1/col3 全水 → 三片各 5 格；发现序 col0 → col2 → col4
	# → 秩 0/1/2（确定性：同图恒同色，可作回归锚）
	var map := MapDataClass.new(5, 5)
	for cell in map.cells():
		var col := Hex.offset_of(cell).x
		if col == 1 or col == 3:
			map.set_passable(cell, false)
	var data := Views.passability_view(map)
	expect_eq(data["component_count"], 3, "三片")
	expect_eq(data["component_sizes"], [5, 5, 5], "各 5 格")
	var again := Views.passability_view(map)
	expect_eq(str(again["colors"]), str(data["colors"]), "并列色序确定（两次派生一致）")
	var colors: PackedColorArray = data["colors"]
	var cells := map.cells()
	for i in cells.size():
		var col := Hex.offset_of(cells[i]).x
		var want_rank := col / 2  # col0→0、col2→1、col4→2；水格单独判
		if col == 1 or col == 3:
			expect(colors[i].is_equal_approx(Views.IMPASSABLE_COLOR), "水格不可通行色")
		else:
			expect(colors[i].is_equal_approx(Views.component_color(want_rank)),
				"并列按发现序定秩：col%d → 秩 %d" % [col, want_rank])

func test_passability_view_all_impassable_and_single_cell() -> void:
	var all_water := MapDataClass.new(3, 3)
	for cell in all_water.cells():
		all_water.set_passable(cell, false)
	var data := Views.passability_view(all_water)
	expect_eq(data["component_count"], 0, "全不可通行 → 零分量")
	expect_eq(data["passable_total"], 0, "通行格 0")
	for c in data["colors"]:
		expect(c.is_equal_approx(Views.IMPASSABLE_COLOR), "全图不可通行色")
	for r in data["ranks"]:
		expect_eq(r, -1, "全图秩 -1")
	var single := MapDataClass.new(1, 1)
	var sdata := Views.passability_view(single)
	expect_eq(sdata["component_count"], 1, "1×1 通行 → 单分量")
	expect_eq((sdata["ranks"] as PackedInt32Array)[0], 0, "1×1 秩 0")
	expect((sdata["colors"] as PackedColorArray)[0].is_equal_approx(Views.component_color(0)),
		"1×1 = 亮灰基准色")

func test_passability_palette_first_entry_is_neutral_gray() -> void:
	# 色板结构锚：首项三通道相等（最大片中性亮灰基准）；后 7 项与首项可分辨
	var palette: Array = Views.COMPONENT_PALETTE
	expect(palette.size() >= 4, "色板 ≥ 4 项（最大片 + 至少 3 个分辨色）")
	var first: Color = palette[0]
	expect(first.r == first.g and first.g == first.b, "首项 = 中性灰（无色相倾向）")
	for i in range(1, palette.size()):
		var c: Color = palette[i]
		expect(not c.is_equal_approx(first), "色板 %d 与最大片基准可分辨" % i)

# ================= derive 分派 =================

func test_derive_dispatches_and_rejects_unknown() -> void:
	var map := MapDataClass.new(2, 2)
	var direct := Views.height_view(map)
	var via := Views.derive("height", map)
	expect_eq(via["values"], direct["values"], "derive('height') 路由到 height_view")
	expect_eq(Views.derive("slope", map)["implemented"], true, "derive('slope') 实做")
	expect_eq(Views.derive("passability", map)["implemented"], true, "derive('passability') 实做")
	for hook in ["region", "skeleton"]:
		var d := Views.derive(hook, map)
		expect_eq(d["implemented"], false, "derive('%s') = 挂点未实现" % hook)
	var bad := Views.derive("nope", map)
	expect_eq(bad["implemented"], false, "未知名不实做")
	expect(String(bad["reason"]).contains("未知视图"), "未知名原因具名")

# ---- 辅助 ----

## 5×5 断路图：col2 全水（tests/test_map_source.gd 同款 oracle 图）
func _split_map() -> MapDataClass:
	var m := MapDataClass.new(5, 5)
	for cell in m.cells():
		if Hex.offset_of(cell).x == 2:
			m.set_terrain(cell, 3)
			m.set_passable(cell, false)
	return m
