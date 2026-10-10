## test_hex_terrain_blend_corner.gd — M1a+ BLEND-02 单测（三格交汇与跨 chunk 过渡）
## 覆盖 docs/04-tasks-m1.md §M1a+ BLEND-02 验收（Given/When/Then）的 headless 锚：
##   - 三格权重合同（纯逻辑，hex_terrain_blend.gd）：角面重心参数 (u,v) →
##     (归属格, N(k), N(k−1)) 权重；锚点 p1/p2/p3 = 单位权重、重心 (1/3,1/3,1/3)、
##     和恒 1（有限、非负；合同域密集采样 + 非法权重拒绝）；两格同色角退化 =
##     边带合同（blend_color3(c,c,d,w) == blend_color(c,d,w.x+w.y)——「角混三种」
##     的最大=3、常见=2 由同一合同覆盖）；
##   - 卡片场景（草-泥-岩共享角，单 chunk）：角面恰一面、归属 = 三格稳定 ID 最小者、
##     三方顶点色 = 三格纯色（合同单位权重锚点）、面内重心 = 三纯色均权 1/3
##     （端点纯色线性插值链路锚定，与 BLEND-01 中点等价同构）、重心几何 =
##     p1 + (bridge_j + bridge_{j−1})/3、shared position 三格视角跨路径对账（1e-5）；
##   - 跨 chunk：同一物理角在「单 chunk / 行切两 chunk（trio 跨块）/ 每格一 chunk
##     （trio 分属三块）」三种划分下位置 + 顶点色逐位一致；角面由归属块生成
##     （跨块读邻块格数据）；全图物理角 key 恰一面（无重复角面）× 每划分；
##   - 无裂缝：每格一 chunk（最极端跨块）blend 构建的焊接流形——每边恰 1/2 面引用、
##     无重复面 key、1 面边界边 = 期望外沿、法线全朝上（沿用 test_hex_terrain_
##     elevation.gd 口径，平地版）；
##   - 拾取不受影响：跨块划分下 blend ↔ fallback 碰撞汤/face 表逐位一致 + 角面
##     resolve_face 归属 = 三格之一。
## oracle 原则：几何期望一律由 HexMath（inner_vertex/bridge_xz）独立拼装对账；归属格
##   与角编号由「三格稳定 ID 最小 / 邻居集合匹配」独立推导，不复制 builder 归属实现；
##   面数/角数由 MapData 邻接原语组合计数。
## 色比较口径（沿用 test_hex_terrain_blend.gd，2026-10-10 实测）：mesh 顶点色按
##   8-bit 归一化存储 → 与色板纯色比较用 1/255 容差（_expect_color_eq8）；mesh↔mesh
##   （同管线两次产出，含不同 chunk 划分）逐位精确比较。
## 焊接口径：WELD_EPS = 1e-3 聚类（最近不同物理点距 ≈ (1−solid)·size ≥ 0.1，安全
##   余量两个数量级）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Lib := preload("res://scripts/core/data/terrain_material_library.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const Blend := preload("res://addons/hexhammer/hex_terrain_blend.gd")
const Picking := preload("res://addons/hexhammer/hex_picking.gd")

const SIZE := 1.0
const SOLID := 0.8  # = Builder.DEFAULT_SOLID_FACTOR（默认路径 oracle 参数）
const WELD_EPS := 1e-3
const CROSS_PATH_EPS := 1e-5

# ================= 三格权重合同（纯逻辑） =================

func test_corner_weights_anchor_points() -> void:
	expect_eq(Blend.corner_weights(0.0, 0.0), Vector3(1.0, 0.0, 0.0),
		"p1（归属格端点）→ 归属格权重 1（单位权重锚点）")
	expect_eq(Blend.corner_weights(1.0, 0.0), Vector3(0.0, 1.0, 0.0),
		"p2（N(k) 侧端点）→ N(k) 权重 1")
	expect_eq(Blend.corner_weights(0.0, 1.0), Vector3(0.0, 0.0, 1.0),
		"p3（N(k−1) 侧端点）→ N(k−1) 权重 1")
	var wc := Blend.corner_weights(1.0 / 3.0, 1.0 / 3.0)
	expect_almost_eq(wc.x, 1.0 / 3.0, 1e-6, "角面重心 → 归属格权重 1/3")
	expect_almost_eq(wc.y, 1.0 / 3.0, 1e-6, "角面重心 → N(k) 权重 1/3")
	expect_almost_eq(wc.z, 1.0 / 3.0, 1e-6, "角面重心 → N(k−1) 权重 1/3")
	for w in [Blend.corner_weights(0.0, 0.0), Blend.corner_weights(1.0, 0.0),
			Blend.corner_weights(0.0, 1.0), wc]:
		expect(Blend.is_valid_weights3(w), "锚点权重合法（有限、非负、和为 1）%s" % str(w))

func test_corner_weights_dense_invariants() -> void:
	# Vector3 分量为 float32：(1−u−v)+u+v 的和有 ~1e-8 舍入；u+v=1 边界上
	# 1−u−v 有 ≤1 ulp 负舍入（如 u=0.9,v=0.1 → −2.8e-17）——非负断言带 1e-9
	# 浮点零点窗口、和断言与 is_valid_weights3 同 1e-6 窗口，合同语义仍是
	# 「非负、和恒 1」（见 hex_terrain_blend.gd is_valid_weights3 注）
	for i in 21:
		for j in 21 - i:
			var u := float(i) / 20.0
			var v := float(j) / 20.0
			var w := Blend.corner_weights(u, v)
			expect_almost_eq(w.x + w.y + w.z, 1.0, 1e-6,
				"权重和恒 1（u=%s v=%s）" % [str(u), str(v)])
			expect(w.x >= -1e-9 and w.y >= 0.0 and w.z >= 0.0,
				"权重非负（浮点零点窗口 1e-9；u=%s v=%s）" % [str(u), str(v)])
			expect(Blend.is_valid_weights3(w),
				"合同域（u,v ≥ 0、u+v ≤ 1）内权重全部合法（u=%s v=%s）" % [str(u), str(v)])

func test_is_valid_weights3_rejects_invalid() -> void:
	expect(Blend.is_valid_weights3(Vector3(-0.1, 0.6, 0.5)) == false, "负权重拒绝")
	expect(Blend.is_valid_weights3(Vector3(0.5, 0.4, 0.2)) == false, "和 ≠ 1 拒绝")
	expect(Blend.is_valid_weights3(Vector3(NAN, 0.5, 0.5)) == false, "NaN 拒绝")
	expect(Blend.is_valid_weights3(Vector3(1.0, INF, 0.0)) == false, "无穷拒绝")
	expect(Blend.is_valid_weights3(Vector3(0.5, 0.25, 0.25)), "一般合法权重通过")
	expect(Blend.is_valid_weights3(Vector3(0.0, 0.0, 1.0)), "单位权重合法（p3 锚点）")

func test_blend_color3_anchors_and_edge_consistency() -> void:
	var grass: Color = Lib.DEFAULT_PALETTE[0]
	var mud: Color = Lib.DEFAULT_PALETTE[1]
	var rock: Color = Lib.DEFAULT_PALETTE[2]
	expect_eq(Blend.blend_color3(grass, mud, rock, Vector3(1.0, 0.0, 0.0)), grass,
		"单位权重 → 归属格纯色")
	expect_eq(Blend.blend_color3(grass, mud, rock, Vector3(0.0, 1.0, 0.0)), mud,
		"单位权重 → N(k) 纯色")
	expect_eq(Blend.blend_color3(grass, mud, rock, Vector3(0.0, 0.0, 1.0)), rock,
		"单位权重 → N(k−1) 纯色")
	var wc := Blend.corner_weights(1.0 / 3.0, 1.0 / 3.0)
	var cent := Blend.blend_color3(grass, mud, rock, wc)
	# 容差 1e-6：Vector3 权重分量为 float32（1/3 不可精确表示 → ~1e-8 量化差），
	# 与 is_valid_weights3 的和窗口同口径（BLEND-01 中点 1e-9 精确是因为 0.5 可精确表示）
	expect_almost_eq(cent.r, (grass.r + mud.r + rock.r) / 3.0, 1e-6, "重心 r = 三纯色均值")
	expect_almost_eq(cent.g, (grass.g + mud.g + rock.g) / 3.0, 1e-6, "重心 g = 三纯色均值")
	expect_almost_eq(cent.b, (grass.b + mud.b + rock.b) / 3.0, 1e-6, "重心 b = 三纯色均值")
	# 退化一致性（「最多三种」的两色面）：两格同色时三格合同 = 两格边带合同
	expect_eq(Blend.blend_color3(grass, grass, mud, wc),
		Blend.blend_color(grass, mud, wc.x + wc.y),
		"两格同色：blend_color3(c,c,d,w) = blend_color(c,d,w.x+w.y)（角退化为边）")
	expect_eq(Blend.blend_color3(grass, mud, grass, wc),
		Blend.blend_color(grass, mud, wc.x + wc.z),
		"另两格同色组合同样退化（c,d,c）")

# ================= 卡片场景：草-泥-岩共享角（单 chunk 权重/位置锚） =================

func test_grass_mud_rock_corner_weights_and_positions() -> void:
	var ctx := _build_grass_mud_rock_map()
	var m: MapDataClass = ctx["map"]
	var trio: Array = [ctx["a"], ctx["b"], ctx["c"]]
	var r := _blend_ok(m, _palette(), 10, 10)  # 单 chunk：先锚几何/权重本身
	if r.is_empty():
		return
	expect_eq((r["chunks"] as Array).size(), 1, "5×5 / 10×10 = 单 chunk")
	var hit := _find_corner_face(r, trio)
	expect(not hit.is_empty(), "目标物理角存在角面（草-泥-岩三格共享角）")
	if hit.is_empty():
		return
	var f: Dictionary = hit["rec"]
	# 归属与角编号独立推导（不复制 builder 枚举）：三格稳定 ID 最小者 + 邻居集合匹配
	var owner := _owner_of(m, trio)
	var others: Array = []
	for x in trio:
		if x != owner:
			others.append(x)
	var j := _vertex_facing(owner, others)
	expect(j >= 0, "owner 视角角编号可推导")
	if j < 0:
		return
	expect_eq(f["cell"], owner, "角面归属 = 三格稳定 ID 最小者")
	expect_eq(int(f["dir"]), j, "角编号 = owner 视角面向另两格的顶点")
	var nb_k := Hex.neighbor(owner, j)
	var nb_k1 := Hex.neighbor(owner, j - 1)
	expect_eq(_distinct_terrains(m, trio), 3, "卡片场景：三格恰三种地形（草/泥/岩）")
	# 三方权重（mesh 顶点色 = 合同单位权重锚点；发射序 (p1,p3,p2)）
	var mesh: ArrayMesh = r["chunks"][hit["chunk"]]["mesh"]
	var arrays: Array = mesh.surface_get_arrays(hit["surface"])
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var fi: int = hit["face"]
	var palette := _palette()
	var c_owner: Color = palette[m.terrain_at(owner)]
	var c_nbk: Color = palette[m.terrain_at(nb_k)]
	var c_nbk1: Color = palette[m.terrain_at(nb_k1)]
	_expect_color_eq8(cols[fi * 3], c_owner, "p1 = 归属格纯色（权重 (1,0,0)）")
	_expect_color_eq8(cols[fi * 3 + 1], c_nbk1, "p3 = N(k−1) 侧所在格纯色（权重 (0,0,1)）")
	_expect_color_eq8(cols[fi * 3 + 2], c_nbk, "p2 = N(k) 侧所在格纯色（权重 (0,1,0)）")
	# 合同链路：顶点纯色 + 线性插值 → 任意 (u,v) 三方权重混合；重心锚 = 三纯色均权
	var wc := Blend.corner_weights(1.0 / 3.0, 1.0 / 3.0)
	expect(Blend.is_valid_weights3(wc), "重心权重合法（和为 1）")
	var realized := Blend.blend_color3(cols[fi * 3], cols[fi * 3 + 2], cols[fi * 3 + 1], wc)
	_expect_color_eq8(realized, Blend.blend_color3(c_owner, c_nbk, c_nbk1, wc),
		"角面内线性插值在几何重心 = 1/3 均权三色混合（三方权重正确）")
	# 位置 oracle（与 builder 同路径构造 → 逐位，平地 y=0）：p1 = owner.inner_j、
	# p2/p3 = p1 + bridge（拼装方式与 builder 相同——同路径逐位口径，见文件头注）
	var p1: Vector3 = verts[fi * 3]
	var p3: Vector3 = verts[fi * 3 + 1]
	var p2: Vector3 = verts[fi * 3 + 2]
	var p1_want := Hex.inner_vertex(owner, j, SIZE, SOLID, 0.0)
	var br_j := Hex.bridge_xz(owner, j, SIZE, SOLID)
	var br_j1 := Hex.bridge_xz(owner, j - 1, SIZE, SOLID)
	var p2_want := p1_want + Vector3(br_j.x, 0.0, br_j.y)
	var p3_want := p1_want + Vector3(br_j1.x, 0.0, br_j1.y)
	expect_eq(p1, p1_want, "p1 = owner.inner_j（全局公式逐位）")
	expect_eq(p2, p2_want, "p2 = p1 + bridge_j（N(k) 侧端点，逐位）")
	expect_eq(p3, p3_want, "p3 = p1 + bridge_{j−1}（N(k−1) 侧端点，逐位）")
	# 重心几何 ↔ 权重参数同一仿射（跨路径容差：mesh float32 顶点 vs float64 公式）
	var centroid := (p1 + p2 + p3) / 3.0
	_expect_vec3_eq_eps(centroid - p1,
		Vector3(br_j.x + br_j1.x, 0.0, br_j.y + br_j1.y) / 3.0, CROSS_PATH_EPS,
		"角面重心 = p1 + (bridge_j + bridge_{j−1})/3（重心参数 u=v=1/3 的几何对应）")
	# shared position 一致（三格视角跨路径对账）：每格自己视角的同一物理内顶点
	for cell in trio:
		var rest: Array = []
		for x in trio:
			if x != cell:
				rest.append(x)
		var jx := _vertex_facing(cell, rest)
		expect(jx >= 0, "三格视角角编号均可推导 %s" % str(cell))
		if jx < 0:
			continue
		var expect_pt := Hex.inner_vertex(cell, jx, SIZE, SOLID, 0.0)
		var best := 1e9
		for v in [p1, p2, p3]:
			best = minf(best, (v as Vector3).distance_to(expect_pt))
		expect(best <= CROSS_PATH_EPS,
			"角面顶点 = %s 视角同一物理点（shared position 一致）" % str(cell))

# ================= 跨 chunk：shared position / 权重跨划分一致 + 无重复角面 =================

func test_corner_shared_position_and_colors_across_chunks() -> void:
	var ctx := _build_grass_mud_rock_map()
	var m: MapDataClass = ctx["map"]
	var trio: Array = [ctx["a"], ctx["b"], ctx["c"]]
	var palette := _palette()
	var mat := Blend.make_blend_material()
	# 三种划分：单 chunk（对照档）/ 行切（trio 跨 2 块）/ 每格一 chunk（trio 分属 3 块）
	var layouts := [
		{"cc": 10, "cr": 10, "label": "单chunk"},
		{"cc": 5, "cr": 1, "label": "行切两chunk"},
		{"cc": 1, "cr": 1, "label": "每格一chunk"},
	]
	var first: Dictionary = {}
	for lay in layouts:
		var r: Variant = Builder.build_map_blend(m, palette, int(lay["cc"]), int(lay["cr"]), mat)
		expect(r is Dictionary, "blend 构建应成功（%s）" % lay["label"])
		if not (r is Dictionary):
			return
		var rd: Dictionary = r
		var hit := _find_corner_face(rd, trio)
		expect(not hit.is_empty(), "目标角面存在（%s）" % lay["label"])
		if hit.is_empty():
			return
		# Given 守卫：trio 是否横跨 chunk（单 chunk 档应同块、跨块档 ≥2 块）
		var rects: Array = rd["chunk_rects"]
		var span := {}
		for cell in trio:
			span[_rect_of(rects, cell)] = true
		if lay["label"] == "单chunk":
			expect_eq(span.size(), 1, "单 chunk 划分下 trio 同块（对照档）")
		else:
			expect(span.size() >= 2,
				"trio 横跨 ≥2 个 chunk（%s，实际 %d 块）" % [lay["label"], span.size()])
		# 角面由归属格所在 chunk 生成（归属块读邻块格数据——T4 归属规则跨块不动）
		var owner := _owner_of(m, trio)
		expect_eq(rd["chunks"][hit["chunk"]]["chunk"], _rect_of(rects, owner),
			"角面生成 chunk = 归属格所在 chunk（%s）" % lay["label"])
		# 位置 + 顶点色快照 → 与首档逐位比对（mesh↔mesh 精确口径）
		var arrays: Array = (rd["chunks"][hit["chunk"]]["mesh"] as ArrayMesh) \
			.surface_get_arrays(hit["surface"])
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var fi: int = hit["face"]
		var snap := {
			"v": [verts[fi * 3], verts[fi * 3 + 1], verts[fi * 3 + 2]],
			"c": [cols[fi * 3], cols[fi * 3 + 1], cols[fi * 3 + 2]],
		}
		if first.is_empty():
			first = snap
		else:
			expect_eq(snap["v"], first["v"],
				"角面顶点跨划分逐位一致（shared position 一致）%s" % lay["label"])
			expect_eq(snap["c"], first["c"],
				"角面顶点色跨划分逐位一致（三方权重不随 chunk 划分改变）%s" % lay["label"])
		# 无重复角面：全图每个物理角 key 恰一面（× 每划分）+ 总数 = oracle
		_expect_inventory_unique(rd, m)

func test_extreme_cross_chunk_blend_no_cracks() -> void:
	# 无裂缝：每格一 chunk（5×5 = 25 块，全部边带/角面都是跨块几何）的 blend 构建
	# 过焊接流形不变量——沿用 test_hex_terrain_elevation.gd 口径（平地版）
	var ctx := _build_grass_mud_rock_map()
	var m: MapDataClass = ctx["map"]
	var r := _blend_ok(m, _palette(), 1, 1)
	if r.is_empty():
		return
	expect_eq((r["chunks"] as Array).size(), 25, "5×5 / 1×1 = 25 chunk（每格一块）")
	_expect_flat_manifold(_collect_faces(r), m, "每格一chunk blend")

# ================= 两色角退化（「最多三种」的最大=3、常见=2） =================

func test_two_terrain_corner_degenerates_to_edge_contract() -> void:
	var m := MapDataClass.new(4, 3)
	for cell in m.cells():
		m.set_terrain(cell, 0)
	var a := Hex.axial_of(Vector2i(1, 1))
	m.set_terrain(Hex.neighbor(a, 1), 1)  # 仅一格泥 → a 的 k=1 角 = 草-草-泥
	var palette := {0: Lib.DEFAULT_PALETTE[0], 1: Lib.DEFAULT_PALETTE[1]}
	var r := _blend_ok(m, palette, 10, 10)
	if r.is_empty():
		return
	var trio: Array = [a, Hex.neighbor(a, 1), Hex.neighbor(a, 0)]
	var hit := _find_corner_face(r, trio)
	expect(not hit.is_empty(), "草-草-泥角面存在")
	if hit.is_empty():
		return
	var owner := _owner_of(m, trio)
	var others: Array = []
	for x in trio:
		if x != owner:
			others.append(x)
	var j := _vertex_facing(owner, others)
	expect(j >= 0, "owner 视角角编号可推导（两色角）")
	if j < 0:
		return
	var nb_k := Hex.neighbor(owner, j)
	var nb_k1 := Hex.neighbor(owner, j - 1)
	var arrays: Array = (r["chunks"][hit["chunk"]]["mesh"] as ArrayMesh) \
		.surface_get_arrays(hit["surface"])
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var fi: int = hit["face"]
	# 顶点仍按角色纯色（两顶点同色 = 同一地形在两格）
	_expect_color_eq8(cols[fi * 3], palette[m.terrain_at(owner)], "两色角 p1 = 归属格纯色")
	_expect_color_eq8(cols[fi * 3 + 1], palette[m.terrain_at(nb_k1)], "两色角 p3 = N(k−1) 侧纯色")
	_expect_color_eq8(cols[fi * 3 + 2], palette[m.terrain_at(nb_k)], "两色角 p2 = N(k) 侧纯色")
	# 按地形聚合权重（角色序 = corner_weights 分量序）：恰两种地形、和恒 1
	var wc := Blend.corner_weights(1.0 / 3.0, 1.0 / 3.0)
	var roles: Array = [owner, nb_k, nb_k1]
	var w_by_terrain := {}
	for i in 3:
		var tid := m.terrain_at(roles[i])
		w_by_terrain[tid] = float(w_by_terrain.get(tid, 0.0)) + wc[i]
	expect_eq(w_by_terrain.size(), 2, "两色角：恰两种地形")
	var total := 0.0
	var shared_color := Color.BLACK
	var odd_color := Color.BLACK
	for tid in w_by_terrain:
		var w_t: float = w_by_terrain[tid]
		total += w_t
		var is_two_thirds := absf(w_t - 2.0 / 3.0) <= 1e-6
		expect(is_two_thirds or absf(w_t - 1.0 / 3.0) <= 1e-6,
			"两色角地形权重 = 1/3 或 2/3（got %s）" % str(w_t))
		if is_two_thirds:
			shared_color = palette[tid]
		else:
			odd_color = palette[tid]
	expect_almost_eq(total, 1.0, 1e-6, "按地形聚合权重和恒 1")
	# 重心实插值 = 边带合同链路（blend_color(共色, 独色, 2/3)）
	var realized := Blend.blend_color3(cols[fi * 3], cols[fi * 3 + 2], cols[fi * 3 + 1], wc)
	_expect_color_eq8(realized, Blend.blend_color(shared_color, odd_color, 2.0 / 3.0),
		"两色角重心 = blend_color(共色, 独色, 2/3)——三格合同退化为边带合同")

# ================= 拾取不受影响（跨块划分） =================

func test_corner_blend_picking_contract_intact() -> void:
	var ctx := _build_grass_mud_rock_map()
	var m: MapDataClass = ctx["map"]
	var palette := _palette()
	var bl: Variant = Builder.build_map_blend(m, palette, 5, 1, Blend.make_blend_material())
	var fb: Variant = Builder.build_map(m, 5, 1, Lib.materials_from_colors(palette))
	expect(bl is Dictionary and fb is Dictionary, "两 style 跨块划分（5×1）均可构建")
	if not (bl is Dictionary) or not (fb is Dictionary):
		return
	# 碰撞汤/face 表逐位一致（全 chunk——拾取合同不随 style/划分改变）
	for ci in ((bl as Dictionary)["chunks"] as Array).size():
		expect_eq(Picking.chunk_collision_faces((bl as Dictionary)["chunks"][ci]),
			Picking.chunk_collision_faces((fb as Dictionary)["chunks"][ci]),
			"碰撞三角形汤逐位一致（chunk %d）" % ci)
		expect_eq(Picking.chunk_face_table((bl as Dictionary)["chunks"][ci]),
			Picking.chunk_face_table((fb as Dictionary)["chunks"][ci]),
			"face→格映射表逐位一致（chunk %d）" % ci)
	# 角面归属解析：命中角落面 → 三格之一（权重/划分不影响归属规则）
	var trio: Array = [ctx["a"], ctx["b"], ctx["c"]]
	var hit := _find_corner_face(bl as Dictionary, trio)
	expect(not hit.is_empty(), "目标角面存在（跨块 blend 构建）")
	if hit.is_empty():
		return
	var arrays: Array = ((bl as Dictionary)["chunks"][hit["chunk"]]["mesh"] as ArrayMesh) \
		.surface_get_arrays(hit["surface"])
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var fi: int = hit["face"]
	var centroid := (verts[fi * 3] + verts[fi * 3 + 1] + verts[fi * 3 + 2]) / 3.0
	var picked: Variant = Picking.resolve_face(centroid, hit["rec"], m)
	expect(picked is Vector2i and trio.has(picked),
		"角落面解析归属 = 三格之一（got %s）" % str(picked))

# ---- 卡片场景与公共辅助 ----

## 卡片地图：5×5 确定性混类型底 + 目标角三格显式设为 草/泥/岩。
## 目标角 = a=offset(1,1) 的正北顶点（k=2）：三格 = a(泥)、b=N(a,2)(草)、c=N(a,1)(岩)。
func _build_grass_mud_rock_map() -> Dictionary:
	var m := MapDataClass.new(5, 5)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_terrain(cell, (cr.x * 3 + cr.y * 5) % 3)
	var a := Hex.axial_of(Vector2i(1, 1))
	var b := Hex.neighbor(a, 2)
	var c := Hex.neighbor(a, 1)
	m.set_terrain(a, 1)  # 泥
	m.set_terrain(b, 0)  # 草
	m.set_terrain(c, 2)  # 岩
	return {"map": m, "a": a, "b": b, "c": c}

func _palette() -> Dictionary:
	return {0: Lib.DEFAULT_PALETTE[0], 1: Lib.DEFAULT_PALETTE[1], 2: Lib.DEFAULT_PALETTE[2]}

## build_map_blend 断言成功并返回 Dictionary；失败返回空字典（后续断言优雅失败）。
func _blend_ok(m, palette: Dictionary, chunk_cols: int, chunk_rows: int) -> Dictionary:
	var r: Variant = Builder.build_map_blend(m, palette, chunk_cols, chunk_rows,
		Blend.make_blend_material())
	expect(r is Dictionary, "build_map_blend 应成功（划分 %d×%d）" % [chunk_cols, chunk_rows])
	if r is Dictionary:
		return r as Dictionary
	return {}

## 三格稳定 ID 最小者（归属 oracle——不复制 builder 实现）。
func _owner_of(m, trio: Array) -> Vector2i:
	var owner: Vector2i = trio[0]
	for cell in trio:
		if m.index_of(cell) < m.index_of(owner):
			owner = cell
	return owner

## cell 的哪个顶点 k 恰面向"邻居对 others"（N(cell,k)、N(cell,k−1) 集合相等）。
func _vertex_facing(cell: Vector2i, others: Array) -> int:
	for cand in 6:
		var n1 := Hex.neighbor(cell, cand)
		var n2 := Hex.neighbor(cell, cand - 1)
		if _same_set([n1, n2], others):
			return cand
	return -1

func _same_set(x: Array, y: Array) -> bool:
	if x.size() != y.size():
		return false
	for e in x:
		if not y.has(e):
			return false
	return true

func _distinct_terrains(m, trio: Array) -> int:
	var seen := {}
	for cell in trio:
		seen[m.terrain_at(cell)] = true
	return seen.size()

## 物理角 key（三格 axial 排序——归属无关的物理标识；沿用 builder/elevation 测试口径）。
func _corner_key(cell: Vector2i, k: int) -> String:
	var ids := ["%d,%d" % [cell.x, cell.y]]
	for nb in [Hex.neighbor(cell, k), Hex.neighbor(cell, k - 1)]:
		ids.append("%d,%d" % [nb.x, nb.y])
	ids.sort()
	return "c|" + "|".join(ids)

func _corner_key_of(trio: Array) -> String:
	var ids := []
	for cell in trio:
		ids.append("%d,%d" % [cell.x, cell.y])
	ids.sort()
	return "c|" + "|".join(ids)

## 全 chunk 搜索目标物理角的角面；返回 {"chunk","surface","face","rec"} 或空字典。
func _find_corner_face(r: Dictionary, trio: Array) -> Dictionary:
	var want := _corner_key_of(trio)
	for ci in (r["chunks"] as Array).size():
		var cd: Dictionary = r["chunks"][ci]
		for si in (cd["surfaces"] as Array).size():
			var faces: Array = cd["surfaces"][si]["faces"]
			for fi in faces.size():
				var f: Dictionary = faces[fi]
				if f["kind"] == "corner" and _corner_key(f["cell"], int(f["dir"])) == want:
					return {"chunk": ci, "surface": si, "face": fi, "rec": f}
	return {}

func _rect_of(rects: Array, cell: Vector2i) -> Rect2i:
	var off := Hex.offset_of(cell)
	for rect in rects:
		if (rect as Rect2i).has_point(off):
			return rect
	return Rect2i()

## 全图物理角/边恰好一次（含跨 chunk——归属规则防重复面）+ 总数 = oracle。
func _expect_inventory_unique(r: Dictionary, m) -> void:
	var corner_count := {}
	var edge_count := {}
	for f in _collect_faces(r):
		if f["kind"] == "corner":
			var ck := _corner_key(f["cell"], int(f["dir"]))
			corner_count[ck] = int(corner_count.get(ck, 0)) + 1
		elif f["kind"] == "edge":
			var ek := _edge_key(f["cell"], int(f["dir"]))
			edge_count[ek] = int(edge_count.get(ek, 0)) + 1
	expect_eq(corner_count.size(), _interior_corner_count(m), "物理角总数 = oracle（无缺角）")
	for ck in corner_count:
		expect_eq(corner_count[ck], 1, "每个物理角恰一角落面（无重复角面）%s" % ck)
	expect_eq(edge_count.size(), _interior_edge_count(m), "物理边总数 = oracle")
	for ek in edge_count:
		expect_eq(edge_count[ek], 2, "每条内部边恰一 quad（2 面）%s" % ek)

func _edge_key(cell: Vector2i, dir: int) -> String:
	var b := Hex.neighbor(cell, dir)
	var pa := cell
	var pb := b
	if pb.x < pa.x or (pb.x == pa.x and pb.y < pa.y):
		var t := pa
		pa = pb
		pb = t
	return "e|%d,%d|%d,%d" % [pa.x, pa.y, pb.x, pb.y]

func _interior_edge_count(m) -> int:
	var n := 0
	for cell in m.cells():
		for d in 3:
			if m.has_cell(Hex.neighbor(cell, d)):
				n += 1
	return n

func _interior_corner_count(m) -> int:
	var n := 0
	for cell in m.cells():
		for k in 6:
			if m.has_cell(Hex.neighbor(cell, k)) and m.has_cell(Hex.neighbor(cell, k - 1)):
				n += 1
	return n / 3

# ---- 焊接流形（无裂缝；沿用 test_hex_terrain_elevation.gd 口径，平地版）----

## 全局面记录（含顶点，faces 序 = 三角序）。
func _collect_faces(r: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ci in (r["chunks"] as Array).size():
		var cd: Dictionary = r["chunks"][ci]
		var mesh: ArrayMesh = cd["mesh"]
		for si in (cd["surfaces"] as Array).size():
			var sd: Dictionary = cd["surfaces"][si]
			var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var faces: Array = sd["faces"]
			for fi in faces.size():
				var f: Dictionary = faces[fi]
				out.append({
					"chunk": ci, "surface": si, "face": fi,
					"kind": f["kind"], "cell": f["cell"], "dir": f["dir"],
					"v0": verts[fi * 3], "v1": verts[fi * 3 + 1], "v2": verts[fi * 3 + 2],
				})
	return out

## 平地焊接流形不变量：① 面数 = oracle；② 无重复面 key（重复角面/边带的直发症状）；
## ③ 每条焊接边恰 1/2 面引用（裂缝 = 中断边 / 重复 = >2 引用）；④ 1 面边界边 =
## 期望外沿（顶面外沿 + 缺角暴露的边带侧边）；⑤ 全部面法线 y > 0。
func _expect_flat_manifold(faces: Array[Dictionary], m, label: String) -> void:
	var top := 0
	var edge := 0
	var corner := 0
	for f in faces:
		match String(f["kind"]):
			"top": top += 1
			"edge": edge += 1
			"corner": corner += 1
	expect_eq(top, m.cell_count() * 6, "%s：顶面 = 6×格数" % label)
	expect_eq(edge, _interior_edge_count(m) * 2, "%s：边带面 = 2×内部边 oracle" % label)
	expect_eq(corner, _interior_corner_count(m), "%s：角落面 = 内部角 oracle" % label)
	var verts := _flat_verts(faces)
	var boundary_expected := _expected_boundary_edges_flat(m)
	for e in boundary_expected:
		verts.append(e[0])
		verts.append(e[1])
	var ids := _weld(verts)
	var n := faces.size()
	var seen_tris := {}
	for fi in n:
		var triple: Array[int] = [ids[fi * 3], ids[fi * 3 + 1], ids[fi * 3 + 2]]
		triple.sort()
		var key := "%d|%d|%d" % [triple[0], triple[1], triple[2]]
		expect(not seen_tris.has(key), "%s：重复面 key（同一焊接三角形出现两次）%s" % [label, key])
		seen_tris[key] = true
	var edge_counts := {}
	for fi in n:
		var a: int = ids[fi * 3]
		var b: int = ids[fi * 3 + 1]
		var c: int = ids[fi * 3 + 2]
		_bump_edge(edge_counts, a, b)
		_bump_edge(edge_counts, b, c)
		_bump_edge(edge_counts, c, a)
	for key in edge_counts:
		expect(int(edge_counts[key]) <= 2, "%s：边被 >2 面引用（重复面）%s = %d" % [label, key, edge_counts[key]])
		expect(int(edge_counts[key]) >= 1, "%s：边引用为 0 %s" % [label, key])
	var actual_boundary := {}
	for key in edge_counts:
		if int(edge_counts[key]) == 1:
			actual_boundary[key] = true
	var expected_boundary := {}
	for i in boundary_expected.size():
		var base: int = n * 3 + i * 2
		var k := "%d_%d" % [mini(ids[base], ids[base + 1]), maxi(ids[base], ids[base + 1])]
		expected_boundary[k] = true
		expect(actual_boundary.has(k), "%s：期望外沿边未被恰好 1 面引用（边 #%d）" % [label, i])
	var only_actual := 0
	for key in actual_boundary:
		if not expected_boundary.has(key):
			only_actual += 1
			fail("%s：出现未预期的 1 面边（破面/缺角）weld key %s" % [label, key])
	expect_eq(only_actual, 0, "%s：1 面边集合 ⊆ 期望外沿" % label)
	for f in faces:
		expect((f["v1"] - f["v0"]).cross(f["v2"] - f["v0"]).y > 0.0,
			"%s：面法线 y > 0（无翻转）%s" % [label, str(f["cell"])])

func _flat_verts(faces: Array[Dictionary]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.resize(faces.size() * 3)
	for fi in faces.size():
		out[fi * 3] = faces[fi]["v0"]
		out[fi * 3 + 1] = faces[fi]["v1"]
		out[fi * 3 + 2] = faces[fi]["v2"]
	return out

## 期望外沿边（平地 y=0）：① 无邻居方向的顶面外沿边；② 邻居存在但相邻角缺失时
## 暴露的边带侧边。任意格视角枚举（同一物理边两侧各数一次，焊接后按 key 去重）。
func _expected_boundary_edges_flat(m) -> Array:
	var out: Array = []
	for cell in m.cells():
		for d in 6:
			var v1 := Hex.inner_vertex(cell, d, SIZE, SOLID, 0.0)
			var v2 := Hex.inner_vertex(cell, (d + 1) % 6, SIZE, SOLID, 0.0)
			var nb := Hex.neighbor(cell, d)
			if not m.has_cell(nb):
				out.append([v1, v2])
				continue
			var br := Hex.bridge_xz(cell, d, SIZE, SOLID)
			if not m.has_cell(Hex.neighbor(cell, d - 1)):
				out.append([v1, v1 + Vector3(br.x, 0.0, br.y)])
			if not m.has_cell(Hex.neighbor(cell, d + 1)):
				out.append([v2, v2 + Vector3(br.x, 0.0, br.y)])
	return out

func _bump_edge(counts: Dictionary, u: int, v: int) -> void:
	var key := "%d_%d" % [mini(u, v), maxi(u, v)]
	counts[key] = int(counts.get(key, 0)) + 1

## 空间哈希聚类焊接（WELD_EPS 半径；最近不同物理点距 ≈ 0.1——无错误合并风险）。
func _weld(verts: Array[Vector3]) -> Array[int]:
	var ids: Array[int] = []
	ids.resize(verts.size())
	var grid := {}
	var centers: Array[Vector3] = []
	for i in verts.size():
		var p: Vector3 = verts[i]
		var cid := _find_cluster(grid, centers, p)
		if cid < 0:
			cid = centers.size()
			centers.append(p)
			var key := Vector3i(int(floor(p.x / WELD_EPS)), int(floor(p.y / WELD_EPS)), int(floor(p.z / WELD_EPS)))
			if not grid.has(key):
				grid[key] = []
			(grid[key] as Array).append(cid)
		ids[i] = cid
	return ids

func _find_cluster(grid: Dictionary, centers: Array[Vector3], p: Vector3) -> int:
	var cx := int(floor(p.x / WELD_EPS))
	var cy := int(floor(p.y / WELD_EPS))
	var cz := int(floor(p.z / WELD_EPS))
	for dx in 3:
		for dy in 3:
			for dz in 3:
				var key := Vector3i(cx + dx - 1, cy + dy - 1, cz + dz - 1)
				if grid.has(key):
					for cid in grid[key]:
						if centers[cid].distance_to(p) <= WELD_EPS:
							return cid
	return -1

# ---- 比较口径（沿用 test_hex_terrain_blend.gd）----

## mesh 顶点色 vs 期望色（8-bit 量化容差，见文件头注）。
func _expect_color_eq8(got: Color, want: Color, msg: String) -> void:
	_checks += 1
	var eps := 1.0 / 255.0 + 1e-4
	if absf(got.r - want.r) > eps or absf(got.g - want.g) > eps \
			or absf(got.b - want.b) > eps or absf(got.a - want.a) > eps:
		_fails.append("%s：got=%s want=%s（8-bit 量化容差 %s）" % [msg, str(got), str(want), str(eps)])

## Vector3 容差比对（欧氏距离）。
func _expect_vec3_eq_eps(a: Vector3, b: Vector3, eps: float, msg: String) -> void:
	_checks += 1
	if a.distance_to(b) > eps:
		_fails.append("%s：got=%s want=%s eps=%s" % [msg, str(a), str(b), str(eps)])
