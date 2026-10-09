## test_map_source.gd — M1a-T9 地图来源单测（固定测试图 + 随机生成器 + 连通性检查 + 工件 IO）
## 逐条覆盖 04 任务卡 M1a-T9「验收 + 细化新增」：
##   一键出可玩测试图（固定图加载即达可玩口径 + 默认参数随机图连通通过）；
##   随机图种子可复现；同配置同 seed 格子摘要逐格一致（T2 summary 为载体）；
##   连通性检查可跑、失败图可保存并被回归用例引用（fixtures 目录全量回归）；
##   生成管线「低频噪声 → 量化整数高程 → 地形分类 → 连通性检查」的结构证据
##   （量化值域、水陆单调性、低频成片非逐格独立随机、cellular 超界噪声可归一）。
## oracle 原则：连通性/分量的期望值由手工小图独立手算；随机图不做绝对 digest 锚
##   （复现承诺限定在固定生成器+引擎构建内，锚死引擎噪声输出反而误报）——
##   固定图为手工 authored（无噪声），digest 绝对锚安全。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapGenerator := preload("res://scripts/content/map_generator.gd")
const MapGenParamsClass := preload("res://scripts/content/map_gen_params.gd")
const MapConnectivity := preload("res://scripts/content/map_connectivity.gd")
const MapIO := preload("res://scripts/content/map_io.gd")

## 固定图 digest 锚（tools/make_fixed_maps.gd 落盘时打印；改地貌须同步更新本锚）
const FIXED_DIGEST := "cf67af4ff63efba878a6ba2d48a7226be62db084e6c979fc8e194a583ad1a771"
## 默认参数（seed=7）低频成片的实证下限：扫描实测最大水块 38（iid 逐格随机 ≈ 2~5）
const MIN_LARGEST_WATER_BLOB := 20

# ================= 固定测试图（可加载资源 + 可玩口径） =================

func test_fixed_map_loads_with_digest_anchor() -> void:
	var map := MapIO.read_map(MapIO.FIXED_MAP_PATH)
	expect(map != null, "固定测试图应可加载：%s" % MapIO.FIXED_MAP_PATH)
	if map == null:
		return
	expect_eq(map.width, 60, "固定图宽 = 60 列")
	expect_eq(map.height, 40, "固定图高 = 40 行")
	expect_eq(map.cell_count(), 2400, "固定图格数 = 2400")
	expect_eq(map.digest(), FIXED_DIGEST, "固定图 digest 锚（改地貌须同步本锚与落盘工具）")

func test_fixed_map_playable() -> void:
	# 「一键出可玩测试图」的固定图面：加载即达可玩口径——连通 + 材质表可全覆盖
	var map := MapIO.read_map(MapIO.FIXED_MAP_PATH)
	expect(map != null, "固定图应可加载")
	if map == null:
		return
	var report := MapConnectivity.check(map)
	expect(report["ok"], "固定图通行格应连成一片（可玩）")
	expect_eq(report["component_count"], 1, "固定图连通分量 = 1")
	var terrains := {}
	var elevations := {}
	var water := 0
	for cell in map.cells():
		var t: int = map.terrain_at(cell)
		var e: int = map.elevation_at(cell)
		terrains[t] = true
		elevations[e] = true
		expect(t >= 0 and t <= 5, "地形 id 应落在默认材质表槽位 0..5：%d" % t)
		expect(e >= 0 and e <= 4, "高程应在设计值域 0..4：%d" % e)
		if t == 3:
			water += 1
			expect(not map.is_passable(cell), "水格应不可通行 %s" % cell)
			expect_eq(e, 0, "水格高程 = 0 %s" % cell)
	expect_eq(terrains.size(), 6, "六类地形应全露出（材质/换贴图目检底图）")
	expect(elevations.has(0) and elevations.has(4), "高程 0（水）与 4（台地）应都在")
	expect(water > 0, "固定图应含水格（不可通行面非空）")
	expect(water < 2400, "固定图应含陆格")

func test_fixed_map_covers_all_edge_classes() -> void:
	# T4 三档连接在固定图上各 ≥1（「高差处连接符合设计图示意」的固定图回归锚）
	var map := MapIO.read_map(MapIO.FIXED_MAP_PATH)
	expect(map != null, "固定图应可加载")
	if map == null:
		return
	var counts := _edge_class_counts(map)
	expect(counts.get(Builder.EDGE_FLAT, 0) > 0, "固定图应含等高平连")
	expect(counts.get(Builder.EDGE_SLOPE, 0) > 0, "固定图应含一级斜坡")
	expect(counts.get(Builder.EDGE_CLIFF, 0) > 0, "固定图应含大高差陡面")

func test_fixed_map_meta_consistent() -> void:
	var map := MapIO.read_map(MapIO.FIXED_MAP_PATH)
	expect(map != null, "固定图应可加载")
	var meta: Variant = MapIO.read_meta(MapIO.FIXED_MAP_META_PATH)
	expect(meta != null, "固定图 meta 应可加载")
	if map == null or meta == null:
		return
	expect(meta.has("kind") and meta["kind"] == "fixed", "meta.kind = fixed（无 seed——固定图）")
	expect_eq(meta["digest"], map.digest(), "meta.digest 与图一致")
	expect(meta.has("connectivity") and meta["connectivity"]["ok"], "meta 记录连通通过")
	expect(not meta.has("params"), "固定图 meta 不携带随机参数")

# ================= 随机生成器（种子复现 + 管线结构） =================

func test_random_same_seed_same_summary_per_cell() -> void:
	# 细化新增验收主条：同配置同 seed → 格子摘要逐格一致（T2 summary 载体）
	var a := _gen_with_seed(7)
	var b := _gen_with_seed(7)
	if a == null or b == null:
		return
	expect_eq(b.summary(), a.summary(), "同 seed 同参数 → 逐格摘要一致")
	expect_eq(b.digest(), a.digest(), "同 seed 同参数 → digest 一致")
	# 逐格抽查（summary 相等已蕴含；再显式对表三个代表格）
	for cr in [Vector2i(0, 0), Vector2i(30, 20), Vector2i(59, 39)]:
		var cell := Hex.axial_of(cr)
		expect_eq(b.terrain_at(cell), a.terrain_at(cell), "同 seed 地形逐格一致 %s" % cell)
		expect_eq(b.elevation_at(cell), a.elevation_at(cell), "同 seed 高程逐格一致 %s" % cell)
		expect_eq(b.is_passable(cell), a.is_passable(cell), "同 seed 通行逐格一致 %s" % cell)

func test_random_no_hidden_state_between_runs() -> void:
	# 生成顺序无关：seed7 → seed8 → seed7，末图与首图一致（无跨次残留状态）
	var first := _gen_with_seed(7)
	_gen_with_seed(8)
	var again := _gen_with_seed(7)
	if first == null or again == null:
		return
	expect_eq(again.digest(), first.digest(), "穿插他 seed 后同 seed 再生成应逐格一致")

func test_random_different_seed_differs() -> void:
	var a := _gen_with_seed(7)
	var b := _gen_with_seed(8)
	if a == null or b == null:
		return
	expect(a.digest() != b.digest(), "不同 seed → digest 不同")

func test_random_meta_carries_repro_fields() -> void:
	# 「存 seed/参数/生成器版本 + 格子表摘要」：meta 字段完备性
	var p := MapGenParamsClass.new()
	p.seed = 42
	var result := MapGenerator.generate(p)
	expect(result["ok"], "生成应成功")
	if not result["ok"]:
		return
	var meta: Dictionary = result["meta"]
	var map = result["map"]
	expect_eq(meta["generator_version"], MapGenerator.GENERATOR_VERSION, "meta 落生成器版本")
	expect_eq(meta["params"], p.to_dict(), "meta 落全部参数（seed 在内）")
	expect_eq(meta["digest"], map.digest(), "meta 落格子表摘要（digest）")
	expect(String(meta["engine_version"]).length() > 0, "meta 落引擎版本（复现限定口径备查）")
	expect(String(meta["reproducibility_note"]).length() > 0, "meta 落复现限定说明")
	for k in ["ok", "passable_total", "component_count", "largest_size", "largest_fraction"]:
		expect(meta["connectivity"].has(k), "meta.connectivity 缺字段 %s" % k)
	expect(meta.has("terrain_counts") and meta.has("elevation_counts"), "meta 落分布统计")

func test_random_sea_level_monotonic_water() -> void:
	# 归一化阈值单调性：sea 0.45 的水格集 ⊇ sea 0.15 的水格集（同 seed 同归一化值）
	var lo := _gen_with_sea(7, 0.15)
	var hi := _gen_with_sea(7, 0.45)
	if lo == null or hi == null:
		return
	var lo_water := 0
	var hi_water := 0
	for cell in lo.cells():
		if not lo.is_passable(cell):
			lo_water += 1
	for cell in hi.cells():
		if not hi.is_passable(cell):
			hi_water += 1
	expect(lo_water > 0 and hi_water > 0, "两档海面都应出水")
	expect(hi_water > lo_water, "海面抬高 → 水格严格增多（got %d → %d）" % [lo_water, hi_water])
	for cell in lo.cells():
		if not lo.is_passable(cell):
			expect(not hi.is_passable(cell), "低海面的水格在高海面必须仍是水 %s" % cell)

func test_random_elevation_quantized_in_range() -> void:
	var p := MapGenParamsClass.new()
	var result := MapGenerator.generate(p)
	expect(result["ok"], "默认参数生成应成功")
	if not result["ok"]:
		return
	var map = result["map"]
	var used := {}
	for cell in map.cells():
		var e: int = map.elevation_at(cell)
		expect(e >= 0 and e <= p.elevation_levels, "高程应 ∈ [0, levels=%d]：%d"
			% [p.elevation_levels, e])
		used[e] = true
		if not map.is_passable(cell):
			expect_eq(e, 0, "水格高程恒 0 %s" % cell)
		else:
			expect(e >= 1, "陆地高程 ≥ 1 %s" % cell)
	expect(used.size() >= 3, "默认参数应至少用到 3 个高程档（got %d）" % used.size())

func test_random_default_params_yield_playable_map() -> void:
	# 「一键出可玩测试图」的随机面：默认参数（seed=7 为扫描出的通过值）即出连通图；
	# 默认值被改坏（默认 seed 连通不过）时此锚报警
	var p := MapGenParamsClass.new()
	var result := MapGenerator.generate(p)
	expect(result["ok"], "默认参数生成应成功")
	if not result["ok"]:
		return
	var map = result["map"]
	var report := MapConnectivity.check(map)
	expect(report["ok"], "默认参数应出连通可玩图（默认 seed 需重扫：%s）" % MapConnectivity.summary_of(report))
	for cell in map.cells():
		var t: int = map.terrain_at(cell)
		expect(t >= 0 and t <= 5, "地形 id 应落在默认材质表槽位 0..5：%d" % t)

func test_random_low_frequency_blobs_not_per_cell_random() -> void:
	# 「不做每格独立随机」的结构证据：低频噪声 → 水体成片（iid 随机最大块 ≈ 2~5，
	# 实测默认 seed 最大水块 38；下限 20 = 强分离面）
	var map := _gen_with_seed(7)
	if map == null:
		return
	expect(_largest_water_blob(map) >= MIN_LARGEST_WATER_BLOB,
		"水体应大片连绵（最大块 %d < %d——退化成逐格随机？）"
		% [_largest_water_blob(map), MIN_LARGEST_WATER_BLOB])

func test_random_cellular_noise_normalized() -> void:
	# 部分 cellular 噪声输出可超 ±1（04 M1a-T9 细化）：归一化管线必须吃得下——
	# 生成成功 + 值域合法 + 同 seed 复现 + 与 simplex 输出不同（确实换了形态）
	var p := MapGenParamsClass.new()
	p.seed = 777
	p.noise_type = FastNoiseLite.TYPE_CELLULAR
	var r1 := MapGenerator.generate(p)
	expect(r1["ok"], "cellular 噪声应可生成（超 ±1 输出由归一化兜住）")
	var r2 := MapGenerator.generate(p)
	expect(r2["ok"], "cellular 噪声第二次生成应成功")
	if not (r1["ok"] and r2["ok"]):
		return
	expect_eq(r2["map"].digest(), r1["map"].digest(), "cellular 同 seed 复现一致")
	var ps := MapGenParamsClass.new()
	ps.seed = 777
	var rs := MapGenerator.generate(ps)
	expect(rs["ok"], "simplex 对照生成应成功")
	if rs["ok"]:
		expect(r1["map"].digest() != rs["map"].digest(), "cellular 与 simplex 同 seed 应产出不同图")
	var map = r1["map"]
	for cell in map.cells():
		var e: int = map.elevation_at(cell)
		expect(e >= 0 and e <= p.elevation_levels, "cellular 高程值域合法：%d" % e)

func test_random_params_validation_rejected() -> void:
	var cases := [
		{"width": 0}, {"height": -1}, {"width": 999999},
		{"sea_level": 1.0}, {"sea_level": -0.1},
		{"elevation_levels": 0}, {"elevation_levels": 999},
		{"frequency": 0.0}, {"fractal_octaves": 0},
		{"moisture_frequency": -1.0}, {"noise_type": 42},
	]
	for patch in cases:
		var p := MapGenParamsClass.new()
		for k in patch:
			p.set(k, patch[k])
		expect(p.validate() != "", "非法参数应被校验拒绝：%s" % patch)
		var result := MapGenerator.generate(p)
		expect(not result["ok"], "非法参数生成应失败：%s" % patch)
		expect(String(result["error"]).length() > 0, "失败应携带原因：%s" % patch)
		expect(result["map"] == null, "失败不得产出半张图：%s" % patch)

# ================= 连通性检查（可跑 + 语义） =================

func test_connectivity_single_blob_ok() -> void:
	var m := MapDataClass.new(5, 5)
	var report := MapConnectivity.check(m)
	expect(report["ok"], "全通行图应通过")
	expect_eq(report["passable_total"], 25, "通行格总数 = 25")
	expect_eq(report["component_count"], 1, "分量数 = 1")
	expect_eq(report["largest_size"], 25, "最大片 = 25")
	expect_almost_eq(float(report["largest_fraction"]), 1.0, 1e-9, "最大片占比 = 1")

func test_connectivity_water_column_splits() -> void:
	# 手算 oracle：5×5 图 col2 全水 → 左右各 10 格通行、两分量、最大片占比 0.5
	var m := MapDataClass.new(5, 5)
	for cell in m.cells():
		if Hex.offset_of(cell).x == 2:
			m.set_terrain(cell, 3)
			m.set_passable(cell, false)
	var report := MapConnectivity.check(m)
	expect(not report["ok"], "断路图应不通过")
	expect_eq(report["passable_total"], 20, "通行格 = 20")
	expect_eq(report["component_count"], 2, "分量数 = 2")
	expect_eq(report["largest_size"], 10, "最大片 = 10")
	expect_almost_eq(float(report["largest_fraction"]), 0.5, 1e-9, "最大片占比 = 0.5")
	expect(report["components"].size() == 2, "分量明细应落报告")
	expect_eq(report["isolated_cells"].size(), 0, "无孤立单格")

func test_connectivity_min_fraction_param() -> void:
	var m := _split_map()
	var strict := MapConnectivity.check(m, 1.0)
	expect(not strict["ok"], "严格口径（占比 1.0）：断路图不通过")
	var loose := MapConnectivity.check(m, 0.45)
	expect(loose["ok"], "放宽口径（0.45）：两片各有 0.5 应通过")
	var mid := MapConnectivity.check(m, 0.6)
	expect(not mid["ok"], "放宽口径（0.6）：最大片 0.5 不通过")

func test_connectivity_all_impassable_and_empty_fail() -> void:
	var all_water := MapDataClass.new(4, 4)
	for cell in all_water.cells():
		all_water.set_passable(cell, false)
	var report := MapConnectivity.check(all_water)
	expect(not report["ok"], "全不可通行图应不通过（无可玩格）")
	expect_eq(report["passable_total"], 0, "通行格 = 0")
	expect_eq(report["component_count"], 0, "分量数 = 0")
	expect_eq(float(report["largest_fraction"]), 0.0, "占比 = 0（除零守护）")
	var empty := MapConnectivity.check(MapDataClass.new(0, 0))
	expect(not empty["ok"], "空图应不通过")

func test_connectivity_single_cell_map_ok() -> void:
	var m := MapDataClass.new(1, 1)
	var report := MapConnectivity.check(m)
	expect(report["ok"], "1×1 通行图应通过")
	expect_eq(report["largest_size"], 1, "最大片 = 1")

func test_connectivity_reports_isolated_cell() -> void:
	# 3×3 全水 + 中心通 → 单格「孤岛」：判定口径只看通行片连通占比 → 单分量占比
	# 1.0 即 ok=true（可玩的退化图）；孤岛语义落在 isolated_cells 调试/留证面，
	# 真·孤岛破产图 = 分量 >1 的断路图（见 water_column 用例）
	var m := MapDataClass.new(3, 3)
	for cell in m.cells():
		m.set_passable(cell, false)
	var center := Hex.axial_of(Vector2i(1, 1))
	m.set_passable(center, true)
	var report := MapConnectivity.check(m)
	expect(report["ok"], "单分量占比 1.0 → ok（判据只看通行片连通占比）")
	expect_eq(report["passable_total"], 1, "通行格 = 1")
	expect_eq(report["isolated_cells"].size(), 1, "孤岛格应进 isolated_cells（留证面）")
	expect(report["isolated_cells"].has(center), "孤岛格 = 中心格")

func test_connectivity_report_deterministic() -> void:
	var m := _split_map()
	var r1 := MapConnectivity.check(m)
	var r2 := MapConnectivity.check(m)
	expect_eq(str(r1["components"]), str(r2["components"]), "同图两次检查分量明细一致")
	expect_eq(r1["largest_size"], r2["largest_size"], "指标一致")

# ================= 工件 IO + 失败图回归样例 =================

func test_failed_fixtures_retained_and_regressed() -> void:
	# 失败图（断路/孤岛）留档的执行口径：目录非空（保留被强制）+ 每张都是真失败图 +
	# meta 与图一致（重生成时 fixtures 全量过检——谁塞了通过图进来谁暴露）
	var dir := MapIO.FAILED_FIXTURE_DIR
	var files := DirAccess.get_files_at(dir)
	var checked := 0
	for f in files:
		if not f.ends_with(".json") or f.ends_with(".meta.json"):
			continue
		var map := MapIO.read_map(dir.path_join(f))
		expect(map != null, "失败样例应可加载：%s" % f)
		if map == null:
			continue
		var report := MapConnectivity.check(map)
		expect(not report["ok"], "失败样例必须连通不通过：%s（got %s）"
			% [f, MapConnectivity.summary_of(report)])
		var meta: Variant = MapIO.read_meta(dir.path_join(f).replace(".json", ".meta.json"))
		expect(meta != null, "失败样例应伴生 meta：%s" % f)
		if meta != null:
			expect(not meta["connectivity"]["ok"], "meta 记录的判定 = 失败：%s" % f)
			expect_eq(meta["digest"], map.digest(), "meta.digest 与图一致：%s" % f)
		checked += 1
	expect(checked > 0, "失败样例目录不应为空（回归样例被删 = 验收破坏）：%s" % dir)

func test_failed_map_save_roundtrip() -> void:
	# 「失败图可保存」的机制面：断路图 → MapIO 落盘 → 读回 → 仍是断路图、digest 不变
	var m := _split_map()
	var base := "user://t9_map_source_roundtrip/fail"
	expect_eq(MapIO.write_map(m, base + ".json"), OK, "写图应成功")
	expect_eq(MapIO.write_meta({"kind": "test-fail", "digest": m.digest()}, base + ".meta.json"), OK, "写 meta 应成功")
	expect_eq(MapIO.write_summary(m, base + ".summary.txt"), OK, "写摘要应成功")
	var back := MapIO.read_map(base + ".json")
	expect(back != null, "读回应成功")
	if back == null:
		return
	expect_eq(back.digest(), m.digest(), "落盘往返 digest 不变")
	expect_eq(back.summary(), m.summary(), "落盘往返逐格摘要一致")
	expect(not MapConnectivity.check(back)["ok"], "读回仍是断路图")
	var meta: Variant = MapIO.read_meta(base + ".meta.json")
	expect(meta != null and meta["digest"] == back.digest(), "meta 往返一致")
	var summary_text := FileAccess.get_file_as_string(base + ".summary.txt")
	expect_eq(summary_text, m.summary(), "摘要文件内容 = summary() 全文")

func test_map_io_missing_files_return_null() -> void:
	var missing := "user://t9_map_source_roundtrip/no_such_file.json"
	expect(MapIO.read_map(missing) == null, "缺文件 read_map → null")
	expect(MapIO.read_json(missing) == null, "缺文件 read_json → null")
	expect(MapIO.read_meta(missing) == null, "缺文件 read_meta → null")

func test_params_from_dict_roundtrip() -> void:
	var p := MapGenParamsClass.new()
	p.seed = 99
	p.sea_level = 0.31
	var back: Variant = MapGenParamsClass.from_dict(p.to_dict())
	expect(back != null, "参数 dict 往返应成功")
	if back != null:
		expect_eq(back.to_dict(), p.to_dict(), "往返参数一致")
	var truncated := p.to_dict()
	truncated.erase("sea_level")
	expect(MapGenParamsClass.from_dict(truncated) == null, "缺键应拒")
	var invalid := p.to_dict()
	invalid["width"] = 0
	expect(MapGenParamsClass.from_dict(invalid) == null, "值非法应拒（经 validate）")
	var fractional := p.to_dict()
	fractional["elevation_levels"] = 2.5
	expect(MapGenParamsClass.from_dict(fractional) == null, "整数字段带小数应拒")

# ---- 辅助 ----

## 生成并取图（返回类型显式标注——引擎把「从 Variant 推断」按错误处理，勿用 := 裸接）
func _gen_with_seed(seed_val: int) -> MapDataClass:
	var p := MapGenParamsClass.new()
	p.seed = seed_val
	var result := MapGenerator.generate(p)
	expect(result["ok"], "生成应成功（seed=%d）" % seed_val)
	if not result["ok"]:
		return null
	var map: MapDataClass = result["map"]
	return map


func _gen_with_sea(seed_val: int, sea: float) -> MapDataClass:
	var p := MapGenParamsClass.new()
	p.seed = seed_val
	p.sea_level = sea
	var result := MapGenerator.generate(p)
	expect(result["ok"], "生成应成功（seed=%d sea=%s）" % [seed_val, str(sea)])
	if not result["ok"]:
		return null
	var map: MapDataClass = result["map"]
	return map


## 5×5 断路图：col2 全水 → 左右各 10 格通行、两分量各占比 0.5
func _split_map() -> MapDataClass:
	var m := MapDataClass.new(5, 5)
	for cell in m.cells():
		if Hex.offset_of(cell).x == 2:
			m.set_terrain(cell, 3)
			m.set_passable(cell, false)
	return m


## 连接分类分布（与 m1a_sandbox._edge_class_counts 同口径：每条无向边只数一次）
func _edge_class_counts(map) -> Dictionary:
	var counts := {}
	for cell in map.cells():
		for d in 3:
			var nb := Hex.neighbor(cell, d)
			if map.has_cell(nb):
				var t := Builder.classify_edge(map.elevation_at(cell) - map.elevation_at(nb))
				counts[t] = int(counts.get(t, 0)) + 1
	return counts


## 最大水面连通块（「低频成片」的度量；水 = 不可通行格）
func _largest_water_blob(map) -> int:
	var visited := {}
	var largest := 0
	for start in map.cells():
		if map.is_passable(start) or visited.has(start):
			continue
		var size := 0
		var queue: Array = [start]
		visited[start] = true
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_front()
			size += 1
			for nb in map.neighbors_existing(cell):
				if not map.is_passable(nb) and not visited.has(nb):
					visited[nb] = true
					queue.append(nb)
		largest = maxi(largest, size)
	return largest
