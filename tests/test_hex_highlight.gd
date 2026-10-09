## test_hex_highlight.gd — M1a-T7 高亮系统单测（headless；被测对象 =
##   addons/hexhammer/hex_highlight.gd 纯逻辑层——「删 scripts/ui/** 后 tests 全绿」
##   口径下不感知 scripts/ui/highlight_layer.gd 节点层）。
## 逐条覆盖 04 任务卡 M1a-T7「验收 + 细化新增」的可自动化部分：
##   - 四态各 1 测：hover（单格切换）/ 选择（多格集合）/ 清空（含幂等）/ 切换
##     （集合差异）；
##   - 集合差异切换断言：变更前后只对差异格增删（added/removed = 精确差集、
##     互不相交、交集格全程在集；同集合重设 → 零差异）；
##   - 深度测试保持开启的断言：高亮/描线材质 no_depth_test=false + 透明度语义
##     （不靠关深度测试掩盖穿山——材质面的可执行锚点）；
##   - 贴合内顶面（微决策 2）：扇形顶点与 HexMath.inner_vertex 同参数源逐位对表、
##     只含内六边形顶点（无连接带顶点）、y=0 平面（lift 由放置层表达）；
##   - 路径描线接口：折线点（格心+内顶面 y）/ 界外显式失败 / 条带 mesh 段几何
##     （宽度、端点延伸、y 贴合、绕序朝上）/ 非法输入 null。
## 「高亮/取消无感知延迟、不闪」为主创目测项；节点缓存复用与「切换不重建地形
##   mesh」的节点侧证据见 tools/highlight_scene_check.gd（独立命令）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const HL := preload("res://addons/hexhammer/hex_highlight.gd")

const SIZE := 1.0
const SOLID := 0.8
const STEP := 1.0
const LIFT := HL.DEFAULT_LIFT
const EPS := 1e-6

# ================= 四态：hover / 选择 / 清空 / 切换 =================

func test_hover_state_single_cell() -> void:
	# hover 态：单格高亮，鼠标移到下一格 → 旧格出集、新格入集（单格集合切换）
	var s := HL.State.new()
	var a := Hex.axial_of(Vector2i(2, 2))
	var b := Hex.neighbor(a, 0)
	var d1: Dictionary = s.set_cells([a])
	expect_eq((d1["added"] as Array).size(), 1, "hover 首格：added = 1")
	expect((d1["added"] as Array).has(a), "hover 首格：added 含 a")
	expect_eq((d1["removed"] as Array).size(), 0, "hover 首格：removed 空")
	expect(s.has_cell(a), "hover 首格：a 在集")
	expect_eq(s.cell_count(), 1, "hover 首格：集合大小 1")
	var d2: Dictionary = s.set_cells([b])
	expect_eq((d2["added"] as Array).size(), 1, "hover 移格：added = 1（只新格）")
	expect((d2["added"] as Array).has(b), "hover 移格：added 含 b")
	expect_eq((d2["removed"] as Array).size(), 1, "hover 移格：removed = 1（只旧格）")
	expect((d2["removed"] as Array).has(a), "hover 移格：removed 含 a")
	expect(s.has_cell(b) and not s.has_cell(a), "hover 移格后：b 在集、a 出集")
	expect_eq(s.cell_count(), 1, "hover 态集合大小恒 1")

func test_selection_state_multi_cell() -> void:
	# 选择态：多格集合（如移动范围/编队）一次入集，无残留
	var s := HL.State.new()
	var a := Hex.axial_of(Vector2i(1, 1))
	var cells: Array = [a]
	for d in 6:
		cells.append(Hex.neighbor(a, d))
	var diff: Dictionary = s.set_cells(cells)
	expect_eq((diff["added"] as Array).size(), 7, "选择 7 格：added = 7")
	expect_eq((diff["removed"] as Array).size(), 0, "选择态从空集来：removed 空")
	expect_eq(s.cell_count(), 7, "选择态集合大小 7")
	for c in cells:
		expect(s.has_cell(c), "选择态：成员在集（%s）" % str(c))
	expect_eq((s.cells() as Array).size(), 7, "cells() 快照大小一致")
	# 重复成员输入去重（集合语义，不因重复入数组而翻倍/产生差异）
	var single := HL.State.new()
	single.set_cells([a])
	var dup: Dictionary = single.set_cells([a, a, a])
	expect_eq((dup["added"] as Array).size(), 0, "重复成员：无新增")
	expect_eq((dup["removed"] as Array).size(), 0, "重复成员：无移除（去重后同集合）")
	expect_eq(single.cell_count(), 1, "重复成员：集合大小仍 1（不因重复翻倍）")

func test_clear_state_empties_and_idempotent() -> void:
	# 清空态：全量 removed、集合归零；再清 → 零差异（幂等，不重复操作节点）
	var s := HL.State.new()
	var a := Hex.axial_of(Vector2i(2, 2))
	var b := Hex.neighbor(a, 1)
	var c := Hex.neighbor(a, 4)
	s.set_cells([a, b, c])
	var d1: Dictionary = s.clear_cells()
	expect_eq((d1["removed"] as Array).size(), 3, "清空：removed = 全量 3")
	expect_eq((d1["added"] as Array).size(), 0, "清空：added 恒空")
	expect_eq(s.cell_count(), 0, "清空后集合空")
	expect(not s.has_cell(a) and not s.has_cell(b) and not s.has_cell(c), "清空后成员全出集")
	var d2: Dictionary = s.clear_cells()
	expect_eq((d2["removed"] as Array).size(), 0, "空集再清：removed 空（幂等）")
	expect_eq((d2["added"] as Array).size(), 0, "空集再清：added 空")

func test_switch_state_by_set_difference() -> void:
	# 切换态 + 集合差异断言（04 M1a-T7 细化「变更前后只对差异格增删」）：
	# S1={a,b,c,d} → S2={b,d,e,f}：added={e,f}、removed={a,c}、交集 {b,d} 全程在集
	var s := HL.State.new()
	var a := Hex.axial_of(Vector2i(2, 2))
	var b := Hex.neighbor(a, 0)
	var c := Hex.neighbor(a, 2)
	var d := Hex.neighbor(a, 4)
	var e := Hex.neighbor(a, 1)
	var f := Hex.neighbor(a, 3)
	s.set_cells([a, b, c, d])
	var diff: Dictionary = s.set_cells([b, d, e, f])
	var added: Array = diff["added"]
	var removed: Array = diff["removed"]
	expect(_same_set(added, [e, f]), "切换：added = 精确差集 S2−S1 = {e,f}（got %s）" % str(added))
	expect(_same_set(removed, [a, c]), "切换：removed = 精确差集 S1−S2 = {a,c}（got %s）" % str(removed))
	expect_eq(added.size(), 2, "切换：added 恰 2 格")
	expect_eq(removed.size(), 2, "切换：removed 恰 2 格")
	for x in added:
		expect(not removed.has(x), "切换：added∩removed = ∅（%s）" % str(x))
	# 交集格全程在集（差异切换不动它们——「未变格不折腾」的集合面）
	expect(s.has_cell(b) and s.has_cell(d), "切换后交集格 {b,d} 仍在集")
	expect(_same_set(s.cells(), [b, d, e, f]), "切换后集合 = S2")
	# 同集合重设 → 零差异（鼠标停住不动：无任何增删）
	var again: Dictionary = s.set_cells([b, d, e, f])
	expect_eq((again["added"] as Array).size(), 0, "同集合重设：added 空")
	expect_eq((again["removed"] as Array).size(), 0, "同集合重设：removed 空")
	# 顺序无关：成员序不同的同集合仍是零差异
	var reorder: Dictionary = s.set_cells([f, b, d, e])
	expect_eq((reorder["added"] as Array).size(), 0, "同集合换序：added 空（集合语义）")

# ================= 深度测试保持开启（材质断言锚）=================

func test_material_depth_test_stays_on() -> void:
	# 04 M1a-T7「不靠『关深度测试』掩盖穿山」：高亮/描线材质一律深度测试开启。
	# 半透明由 TRANSPARENCY_ALPHA 承载（深度照测、被地形正确遮挡），
	# 描线不透明（TRANSPARENCY_DISABLED）。
	var m := HL.highlight_material()
	expect_eq(m.no_depth_test, false, "高亮材质：深度测试保持开启（no_depth_test=false）")
	expect_eq(m.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "高亮材质：alpha 透明通道")
	expect(m.albedo_color.a > 0.0 and m.albedo_color.a < 1.0,
		"高亮材质：半透明（默认色 alpha ∈ (0,1)，got %s）" % str(m.albedo_color.a))
	var custom := HL.highlight_material(Color(0.2, 0.4, 0.9, 0.77))
	expect_eq(custom.albedo_color, Color(0.2, 0.4, 0.9, 0.77), "自定义色透传")
	expect_eq(custom.no_depth_test, false, "自定义高亮材质：深度测试同样开启")
	var pm := HL.path_material()
	expect_eq(pm.no_depth_test, false, "描线材质：深度测试保持开启")
	expect_eq(pm.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "描线材质：不透明")

# ================= 贴合内顶面（微决策 2）=================

func test_fan_mesh_matches_inner_top_face() -> void:
	# 扇形 = 格心 + 六内顶点（仅内顶面——无斜坡/悬崖连接带顶点；微决策 2）；
	# 局部形状与 HexMath.inner_vertex 同参数源逐位一致（多格验证形状与格无关）；
	# y=0 平面（lift 由放置层表达——几何与放置分离）；绕序 cross 朝上（T4 顶面口径）。
	var mesh := HL.inner_fan_mesh(SIZE, SOLID)
	expect_eq(mesh.get_surface_count(), 1, "扇形 mesh：单 surface")
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	expect_eq(verts.size(), 7, "扇形顶点 = 格心 + 6 内顶点（无连接带顶点）")
	expect_eq(idx.size(), 18, "扇形三角 = 6 × 3 索引")
	expect_almost_eq(verts[0].length(), 0.0, EPS, "顶点 0 = 格心原点")
	for i in 6:
		expect_almost_eq(verts[1 + i].y, 0.0, EPS, "扇形 y=0 平面（lift 在放置层，i=%d）" % i)
	# 与 T4 顶面同参数源：多格上 inner_vertex(全局) − 格心 == inner_vertex_local
	for cell in [Hex.axial_of(Vector2i(0, 0)), Hex.axial_of(Vector2i(3, 2)), Hex.axial_of(Vector2i(7, 5))]:
		var center := Hex.axial_to_world(cell, SIZE)
		for i in 6:
			var want := Hex.inner_vertex(cell, i, SIZE, SOLID, 0.0) - center
			expect_almost_eq(verts[1 + i].distance_to(want), 0.0, EPS,
				"内顶点对表（%s i=%d）：mesh 局部 = inner_vertex − 格心" % [str(cell), i])
	# 绕序：每三角 cross(B−A, C−A).y > 0（T4 顶面 (格心, inner_k, inner_k+1) 口径）
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		expect((b - a).cross(c - a).y > 0.0, "扇形三角绕序朝上（t=%d）" % t)

func test_anchor_follows_elevation_and_lift() -> void:
	# 放置面：anchor = 格心 xz + 高程×步长 + lift（混合高程含负层与 0..3 层对表）
	var m := _pattern_map(6, 5)
	var nonzero := 0
	for cell in m.cells():
		var want := Hex.axial_to_world(cell, SIZE)
		var got := HL.cell_anchor(m, cell, SIZE, STEP, LIFT)
		expect_almost_eq(got.x, want.x, EPS, "anchor.x = 格心（%s）" % str(cell))
		expect_almost_eq(got.z, want.z, EPS, "anchor.z = 格心（%s）" % str(cell))
		expect_almost_eq(got.y, float(m.elevation_at(cell)) * STEP + LIFT, EPS,
			"anchor.y = 内顶面 + lift（%s h=%d）" % [str(cell), m.elevation_at(cell)])
		if m.elevation_at(cell) != 0:
			nonzero += 1
	expect(nonzero > 0, "测试图含非零高程（对表有信息量）")
	expect_almost_eq(HL.cell_top_y(m, Hex.axial_of(Vector2i(0, 0)), STEP, 0.0),
		float(m.elevation_at(Hex.axial_of(Vector2i(0, 0)))) * STEP, EPS,
		"cell_top_y：lift=0 时 = 纯内顶面高")

# ================= lift 档位：共面治理（「不闪」的几何面）=================

func test_lift_tiers_separate_coplanar_surfaces() -> void:
	# 跨层同格双扇面 / 描线带×途经格扇面 = 几何重叠面，唯一治理 = lift 错档不共面：
	#   - 档位等差：lift_for_tier(t) = DEFAULT_LIFT + t × LIFT_TIER_STEP，两两互异；
	#   - 描线 extra = 半档（非 step 整数倍）→ 任何层的描线 lift 永不落在任何
	#     整档扇面 lift 上（带×扇全组合不共面——含「tier0 描线 × tier2 扇面」类
	#     跨层交叠）；
	#   - 描线高于本层扇面（extra > 0，压在上面可见）。
	expect_almost_eq(HL.lift_for_tier(0), HL.DEFAULT_LIFT, EPS, "tier 0 = 基准档")
	expect_almost_eq(HL.lift_for_tier(1), HL.DEFAULT_LIFT + HL.LIFT_TIER_STEP, EPS,
		"tier 1 = 基准 + 一档（跨层错开量）")
	expect_almost_eq(HL.lift_for_tier(3), HL.DEFAULT_LIFT + 3.0 * HL.LIFT_TIER_STEP, EPS,
		"高档位等差外推")
	for t in 5:
		for k in 5:
			if t != k:
				expect(absf(HL.lift_for_tier(t) - HL.lift_for_tier(k)) >= HL.LIFT_TIER_STEP - EPS,
					"档位两两错开 ≥ 一档（tier %d vs %d）" % [t, k])
	expect(HL.DEFAULT_PATH_LIFT_EXTRA > 0.0, "描线 extra > 0（描线压过本层扇面可见）")
	var ratio: float = HL.DEFAULT_PATH_LIFT_EXTRA / HL.LIFT_TIER_STEP
	expect(absf(ratio - roundf(ratio)) > 0.01,
		"描线 extra 为半档（%s ≠ step 整数倍，got 比值 %s）" % [str(HL.DEFAULT_PATH_LIFT_EXTRA), str(ratio)])
	# 半档性质直接枚举：任何层的描线 lift 不等于任何整档扇面 lift
	for t in 6:
		for k in 6:
			expect(absf(HL.lift_for_tier(t) + HL.DEFAULT_PATH_LIFT_EXTRA - HL.lift_for_tier(k)) > 1e-9,
				"tier %d 描线 lift 不落在 tier %d 扇面档上（带×扇不共面）" % [t, k])

# ================= 路径描线接口（M1b 预铺）=================

func test_path_polyline_and_strip_mesh() -> void:
	# 折线：途经格心 + 各格内顶面 y；界外 → 空数组（显式失败不静默截断）
	var m := _pattern_map(6, 5)
	var a := Hex.axial_of(Vector2i(1, 2))
	var path: Array = [a, Hex.neighbor(a, 0), Hex.neighbor(Hex.neighbor(a, 0), 5)]
	var pts := HL.path_points(path, m, SIZE, STEP, LIFT)
	expect_eq(pts.size(), 3, "折线点数 = 途经格数")
	for i in path.size():
		var cell: Vector2i = path[i]
		var want := HL.cell_anchor(m, cell, SIZE, STEP, LIFT)
		expect_almost_eq(pts[i].distance_to(want), 0.0, EPS,
			"折线点 = 格 anchor（%s）" % str(cell))
	var bad := HL.path_points([a, Vector2i(99, -99)], m, SIZE, STEP, LIFT)
	expect_eq(bad.size(), 0, "界外格混入 → 空折线（显式失败）")
	expect_eq(HL.path_points([], m, SIZE, STEP, LIFT).size(), 0, "空输入 → 空折线")
	# 条带 mesh：n−1 段 × 2 三角（非索引逐面顶点 = 6×段）；段几何性质：
	# a/b 端顶点对中点 = 端点 ± 段向延伸、宽度 = |a1−a0|、y 贴各自格顶、绕序朝上
	var width := 0.18
	var built: Variant = HL.path_strip_mesh(pts, width)
	expect(built is ArrayMesh, "条带 mesh 构建成功")
	if not (built is ArrayMesh):
		return
	var arrays := (built as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var segs := pts.size() - 1
	expect_eq(verts.size(), segs * 6, "条带顶点 = 段数 × 6（2 三角逐面顶点）")
	for s in segs:
		var p0: Vector3 = pts[s]
		var p1: Vector3 = pts[s + 1]
		var flat := Vector2(p1.x - p0.x, p1.z - p0.z)  # 独立推导用水平投影（实现口径）
		var fdir := Vector3(flat.x, 0.0, flat.y).normalized()
		var ext: float = minf(width * 0.5, flat.length() * 0.5)
		var base := s * 6
		var a0 := verts[base]      # 三角1 (a0,a1,b1)
		var a1 := verts[base + 1]
		var b1 := verts[base + 2]
		var b0 := verts[base + 5]  # 三角2 (a0,b1,b0)
		expect_almost_eq(((a0 + a1) / 2.0).distance_to(p0 - fdir * ext), 0.0, 1e-5,
			"段 %d：a 端中点 = 起点水平外延 min(半宽, 半段长)" % s)
		expect_almost_eq(((b0 + b1) / 2.0).distance_to(p1 + fdir * ext), 0.0, 1e-5,
			"段 %d：b 端中点 = 终点水平外延" % s)
		expect_almost_eq((a1 - a0).length(), width, 1e-5, "段 %d：带宽 = width" % s)
		expect_almost_eq(a0.y, p0.y, EPS, "段 %d：a 端 y = 起点格顶+lift（延伸恒水平）" % s)
		expect_almost_eq(a1.y, p0.y, EPS, "段 %d：a 端对侧 y 同高（侧向恒水平）" % s)
		expect_almost_eq(b0.y, p1.y, EPS, "段 %d：b 端 y = 终点格顶+lift" % s)
		expect((a1 - a0).cross(b1 - a0).y > 0.0, "段 %d：三角1 绕序朝上" % s)
		expect((b1 - a0).cross(b0 - a0).y > 0.0, "段 %d：三角2 绕序朝上" % s)
	# 非法输入：点数 < 2 / 宽度 ≤ 0 → null（显式失败）
	expect(HL.path_strip_mesh(PackedVector3Array(), width) == null, "0 点 → null")
	expect(HL.path_strip_mesh(PackedVector3Array([Vector3.ZERO]), width) == null, "1 点 → null")
	expect(HL.path_strip_mesh(pts, 0.0) == null, "宽度 0 → null")

# ---- 辅助 ----

func _pattern_map(w: int, h: int) -> MapDataClass:
	var m := MapDataClass.new(w, h)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_elevation(cell, (cr.x * 2 + cr.y * 3) % 5 - 2)  # −2..2 含负层
	return m

func _same_set(x: Array, y: Array) -> bool:
	if x.size() != y.size():
		return false
	for e in x:
		if not y.has(e):
			return false
	return true
