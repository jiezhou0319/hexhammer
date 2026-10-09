## test_hex_picking_ray.gd — M1a-T5 拾取链路单测 · 射线可测层
## 【为什么是软件射线而不是引擎 intersect_ray】04 M1a-T5 细化要求「物理查询在
## headless 下可测则测」；实测（2026-10-09，Godot 4.7.2）：冻结测试口径
## run_tests.gd 在 SceneTree._init 内同步执行并 quit——主循环从不迭代，物理空间
## 永不被 step（脚本 API 无 space_step/sync/flush_queries，手动物理空间直查射线
## 恒空，探测记录见任务交付说明）。故本文件以「同一份自提交碰撞三角形汤上的纯
## 软件 Möller–Trumbore 求交」作为可测层，覆盖全链路：
##   射线 → 最近命中（含正面剔除，对齐 intersect_ray 默认 hit_back_faces=false）
##   → 命中三角索引（= face_index 语义）→ face 表 → 微决策 3 归属规则 → 格子。
## 引擎级 face_index/mask/平移行为由 tools/picking_scene_check.gd 小场景校验
##（跑真物理帧，独立命令，见其头注）。
## 覆盖（04 M1a-T5 验收 + 细化新增）：
##   - 每格中心反投影：小图全量（直下 + 55° 斜射线，含高程图遮挡正例）；60×40
##     抽样（直下，网格桶加速）；
##   - 斜坡/悬崖/三格角落归属正反用例（射线命中连接面/角落面后走规则）；
##   - 地图根整体平移后拾取仍正确（世界射线 → 世界三角形求交 → 局部转换回归）；
##   - 图外射线 → miss（无静默兜底格）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const Picking := preload("res://addons/hexhammer/hex_picking.gd")

const SIZE := 1.0
const SOLID := 0.8
const STEP := 1.0
const MT_EPS := 1e-8

# ================= 每格中心反投影：小图全量 =================

func test_small_map_all_cells_straight_down() -> void:
	# 6×5 混合高程（含负层与三档连接）：每格中心直下射线 → 本格
	var m := _pattern_map(6, 5)
	var scene := _scene(_build_ok(m))
	var sampled := 0
	for cell in m.cells():
		var c := Hex.axial_to_world(cell, SIZE, float(m.elevation_at(cell)) * STEP)
		var got: Variant = _pick_local(scene, m, Vector3(c.x, 20.0, c.z), Vector3(c.x, -20.0, c.z))
		expect_eq(got, cell, "格心直下反投影 %s（h=%d）" % [str(cell), m.elevation_at(cell)])
		sampled += 1
	expect_eq(sampled, 30, "小图全量 = 30 格")

func test_small_flat_map_all_cells_tilted_rays() -> void:
	# 平图 5×5：55° 俯角斜射线（沙盒相机口径）逐格命中本格
	var m := MapDataClass.new(5, 5)
	var scene := _scene(_build_ok(m))
	var sampled := 0
	for cell in m.cells():
		var from_south := Hex.offset_of(cell).y >= 2  # 下半从南打、上半从北打（避开穿图遮挡歧义）
		var got: Variant = _pick_tilted(scene, m, cell, from_south)
		expect_eq(got, cell, "平图格心 55° 斜射线反投影 %s" % str(cell))
		sampled += 1
	expect_eq(sampled, 25, "平图全量 = 25 格")

func test_elevated_tilted_rays_with_occlusion() -> void:
	# 3×1：a=(1,0) h=0、b=(2,0) h=2（东邻台地）。55° 斜射线（同 _pick_tilted 口径）：
	# 西侧打入（背后无地形）→ 直视 a 顶面；东侧打入（越过 b 上空）→ 必先命中 b
	#（陡面或顶面，均归 b）——遮挡语义正例：真实拾取不跳格
	var m := MapDataClass.new(3, 1)
	var a := Hex.axial_of(Vector2i(1, 0))
	var b := Hex.neighbor(a, 0)
	m.set_elevation(b, 2)
	var scene := _scene(_build_ok(m))
	var ca := Hex.axial_to_world(a, SIZE, 0.0)
	var identity := Transform3D(Basis(), Vector3.ZERO)
	var west := Vector3(ca.x - 5.6, 8.0, ca.z)
	expect_eq(_pick_world(scene, m, west, ca + (ca - west).normalized() * 0.5, identity), a,
		"西来斜射线：低格直视 → a")
	var east := Vector3(ca.x + 5.6, 8.0, ca.z)
	expect_eq(_pick_world(scene, m, east, ca + (ca - east).normalized() * 0.5, identity), b,
		"东来斜射线：台地 b 遮挡（陡面/顶面先中）→ b")
	# 对照：无遮挡侧不得被高邻格劫走
	expect_eq(_pick_world(scene, m, west, ca + (ca - west).normalized() * 0.5, identity) != b, true,
		"反例：西来射线不得归 b")

# ================= 斜坡 / 悬崖 / 角落：归属正反（射线层）=================

func test_slope_band_via_ray() -> void:
	# a h=0 / b=N(a,0) h=1：t=0.45 → a、t=0.55 → b、t=0.5 → ID 小者；
	# 命中面 kind 必为 edge 且候选恰为 {a,b}
	var m := MapDataClass.new(5, 5)
	var a := Hex.axial_of(Vector2i(2, 2))
	var b := Hex.neighbor(a, 0)
	m.set_elevation(b, 1)
	var scene := _scene(_build_ok(m))
	for t in [0.45, 0.5, 0.55]:
		var tt: float = t
		var p := _lerp_centers(a, b, tt)
		var res := _pick_local_raw(scene, m, Vector3(p.x, 20.0, p.z), Vector3(p.x, -20.0, p.z))
		expect(not res.is_empty(), "斜坡带 t=%s 应命中" % str(tt))
		if res.is_empty():
			continue
		var face: Dictionary = scene["faces"][res["index"]]
		expect_eq(String(face["kind"]), "edge", "斜坡命中面 kind=edge（t=%s）" % str(tt))
		var got: Variant = Picking.resolve_face(res["position"], face, m, SIZE)
		var want: Vector2i = a if tt < 0.5 else (b if tt > 0.5 else _smaller_id(m, a, b))
		expect_eq(got, want, "斜坡归属：t=%s → %s" % [str(tt), str(want)])
		# 反例：结果不得逃出边带候选
		expect(got == a or got == b, "斜坡归属 ∈ {a,b}")

func test_cliff_band_via_ray() -> void:
	# a h=0 / b h=3：三个 t 全归 b（高地侧）；近低格侧（t=0.45）反例不得归 a
	var m := MapDataClass.new(5, 5)
	var a := Hex.axial_of(Vector2i(2, 2))
	var b := Hex.neighbor(a, 0)
	m.set_elevation(b, 3)
	var scene := _scene(_build_ok(m))
	for t in [0.45, 0.5, 0.55]:
		var tt: float = t
		var p := _lerp_centers(a, b, tt)
		var res := _pick_local_raw(scene, m, Vector3(p.x, 20.0, p.z), Vector3(p.x, -20.0, p.z))
		expect(not res.is_empty(), "陡面 t=%s 应命中（Catlike 式陡连接面非垂直墙，XZ 带内可直下命中）" % str(tt))
		if res.is_empty():
			continue
		var face: Dictionary = scene["faces"][res["index"]]
		expect_eq(String(face["kind"]), "edge", "陡面命中面 kind=edge（t=%s）" % str(tt))
		var got: Variant = Picking.resolve_face(res["position"], face, m, SIZE)
		expect_eq(got, b, "悬崖归高地侧（t=%s，XZ 更近 a 也不截胡）" % str(tt))
		expect(got != a, "悬崖反例：低格 a 不得截获（t=%s）" % str(tt))

func test_corner_via_ray() -> void:
	# 三格角落组合：悬崖形（max−min≥2）→ 最高格；斜坡形 → 最近格心（测试侧独立推导）
	var combos := [[0, 0, 2], [0, 1, 2], [0, 2, 1], [0, 1, 1], [0, 0, 1]]
	for combo in combos:
		var ha: int = combo[0]
		var hb: int = combo[1]
		var hc: int = combo[2]
		var m := MapDataClass.new(5, 5)
		var a := Hex.axial_of(Vector2i(1, 1))
		var b := Hex.neighbor(a, 2)
		var c := Hex.neighbor(a, 1)
		m.set_elevation(a, ha)
		m.set_elevation(b, hb)
		m.set_elevation(c, hc)
		var oc := _owner_and_corner(m, a, b, c)
		var owner: Vector2i = oc[0]
		var j: int = oc[1]
		expect(j >= 0, "角编号可推导（%d/%d/%d）" % [ha, hb, hc])
		if j < 0:
			continue
		var p := _corner_centroid(owner, j)
		var scene := _scene(_build_ok(m))
		var res := _pick_local_raw(scene, m, Vector3(p.x, 20.0, p.z), Vector3(p.x, -20.0, p.z))
		expect(not res.is_empty(), "角落重心直下应命中（%d/%d/%d）" % [ha, hb, hc])
		if res.is_empty():
			continue
		var face: Dictionary = scene["faces"][res["index"]]
		expect_eq(String(face["kind"]), "corner", "角落命中面 kind=corner（%d/%d/%d）" % [ha, hb, hc])
		var trio: Array[Vector2i] = [a, b, c]
		var cand := Picking.corner_cells(face["cell"], int(face["dir"]))
		expect(_same_set(cand, trio), "角落面候选 = 物理三格（%d/%d/%d）" % [ha, hb, hc])
		var got: Variant = Picking.resolve_face(res["position"], face, m, SIZE)
		# oracle：与 pick_corner 同规格独立推导（最高/并列ID；否则最近心+ID）
		var want := trio[0]
		var hi := m.elevation_at(trio[0])
		var lo := hi
		for cell in trio:
			hi = maxi(hi, m.elevation_at(cell))
			lo = mini(lo, m.elevation_at(cell))
		if hi - lo >= 2:
			for cell in trio:
				if m.elevation_at(cell) > m.elevation_at(want) \
						or (m.elevation_at(cell) == m.elevation_at(want) and m.index_of(cell) < m.index_of(want)):
					want = cell
		else:
			var best_d := INF
			for cell in trio:
				var ctr := Hex.axial_to_world(cell, SIZE)
				var d := Vector2(p.x - ctr.x, p.z - ctr.z).length()
				if d < best_d - 1e-6:
					best_d = d
					want = cell
				elif absf(d - best_d) <= 1e-6 and m.index_of(cell) < m.index_of(want):
					best_d = mini(d, best_d)
					want = cell
		expect_eq(got, want, "角落归属（%d/%d/%d）→ %s" % [ha, hb, hc, str(want)])

# ================= 地图根整体平移（世界射线 → 局部转换回归）=================

func test_translation_regression_all_cells() -> void:
	# 混合高程 5×5：地形整体平移 T（世界三角形 = 局部 + T），世界坐标射线打
	# world(格心+T)，命中点经 T.affine_inverse() 转回局部再解析 → 仍归本格
	var m := _pattern_map(5, 5)
	var build := _build_ok(m)
	for t in [Vector3(37.5, -12.25, 8.0), Vector3(-13.0, 4.0, 21.0)]:
		var tv: Vector3 = t
		var scene := _scene(build, tv)
		var to_local := Transform3D(Basis(), tv).affine_inverse()
		var hits := 0
		for cell in m.cells():
			var c := Hex.axial_to_world(cell, SIZE, float(m.elevation_at(cell)) * STEP)
			var world := c + tv
			var res := _pick_world_raw(scene, Vector3(world.x, 20.0 + tv.y, world.z),
				Vector3(world.x, -20.0 + tv.y, world.z))
			expect(not res.is_empty(), "平移后格心直下应命中 T=%s %s" % [str(tv), str(cell)])
			if res.is_empty():
				continue
			var face: Dictionary = scene["faces"][res["index"]]
			var got: Variant = Picking.resolve_face(to_local * (res["position"] as Vector3), face, m, SIZE)
			expect_eq(got, cell, "平移后拾取仍正确 T=%s %s" % [str(tv), str(cell)])
			hits += 1
		expect_eq(hits, 25, "平移场景全量命中 T=%s" % str(tv))

# ================= 60×40 抽样反投影（网格桶加速）=================

func test_sampling_60x40() -> void:
	# 固定种子随机高程 0..4（与 T4 随机图同参数口径）：三档连接齐备为前提；
	# 抽样 col%3==0 且 row%2==0（20×20=400 格）直下反投影
	var m := MapDataClass.new(60, 40)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261009
	for cell in m.cells():
		m.set_elevation(cell, rng.randi_range(0, 4))
	var class_counts := {}
	for cell in m.cells():
		for d in 3:
			var nb := Hex.neighbor(cell, d)
			if m.has_cell(nb):
				class_counts[Builder.classify_edge(m.elevation_at(cell) - m.elevation_at(nb))] = true
	for t in [Builder.EDGE_FLAT, Builder.EDGE_SLOPE, Builder.EDGE_CLIFF]:
		expect(class_counts.has(t), "抽样图须含三档连接（%s）" % t)
	var scene := _scene(_build_ok(m))
	var grid := _make_grid(scene["tris"])
	var faces: Array = scene["faces"]
	var sampled := 0
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		if cr.x % 3 != 0 or cr.y % 2 != 0:
			continue
		var c := Hex.axial_to_world(cell, SIZE, float(m.elevation_at(cell)) * STEP)
		var hit := _ray_down_grid(grid, c.x, c.z, 20.0, -20.0)
		expect(not hit.is_empty(), "60×40 抽样命中 %s" % str(cell))
		if hit.is_empty():
			continue
		var face: Dictionary = faces[hit["index"]]
		var got: Variant = Picking.resolve_face(hit["position"], face, m, SIZE)
		expect_eq(got, cell, "60×40 抽样反投影 %s（h=%d）" % [str(cell), m.elevation_at(cell)])
		sampled += 1
	expect(sampled >= 380, "抽样规模 ≥ 380（got %d）" % sampled)
	expect_eq(sampled, 400, "抽样规模 = 400（20 列 × 20 行）")

# ================= 图外 miss =================

func test_ray_outside_map_misses() -> void:
	var m := _pattern_map(4, 3)
	var scene := _scene(_build_ok(m))
	for p in [Vector3(-50.0, 20.0, -50.0), Vector3(500.0, 20.0, 500.0), Vector3(0.0, 50.0, -9.0)]:
		var pv: Vector3 = p
		var res := _pick_local_raw(scene, m, Vector3(pv.x, pv.y, pv.z), Vector3(pv.x, pv.y - 40.0, pv.z))
		expect(res.is_empty(), "图外直下射线不得命中（%s）" % str(pv))

# ================= 软件 raycast（可测层核心；对齐引擎 intersect_ray 语义）=================

## Möller–Trumbore 单三角：**正面口径对齐引擎实测**——Godot（渲染与
## ConcavePolygonShape3D 射线同约定）正面 = 顺时针绕序（从可见侧看），
## 即 face normal = −cross(B−A,C−A)；射线从可见侧入射 ⇔ det = edge1·(dir×edge2)
## < −eps（等价于 cross(B−A,C−A) 沿射线方向）。碰撞 soup 已按 (a,c,b) 翻转提交
##（hex_picking.gd chunk_collision_faces），本求交按同口径剔除背面
##（= 引擎 intersect_ray 默认 hit_back_faces=false）。
func _mt_hit(a: Vector3, b: Vector3, c: Vector3, from: Vector3, to: Vector3) -> float:
	var edge1 := b - a
	var edge2 := c - a
	var dir := to - from
	var pvec := dir.cross(edge2)
	var det := edge1.dot(pvec)
	if det > -MT_EPS:
		return -1.0  # 背面/平行（引擎正面 = 顺时针：det 须显著为负）
	var inv := 1.0 / det
	var tvec := from - a
	var u := tvec.dot(pvec) * inv
	if u < 0.0 or u > 1.0:
		return -1.0
	var qvec := tvec.cross(edge1)
	var v := dir.dot(qvec) * inv
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var t := edge2.dot(qvec) * inv  # dir 未归一化 → t ∈ (0,1]
	if t <= MT_EPS or t > 1.0:
		return -1.0
	return t


## 最近命中：返回 {"t","index","position"}；indices 为空 = 全扫描
func _ray_nearest(tris: Array, from: Vector3, to: Vector3, indices: Array = []) -> Dictionary:
	var best_t := INF
	var best_i := -1
	if indices.is_empty():
		for i in tris.size():
			var t := _mt_hit(tris[i]["a"], tris[i]["b"], tris[i]["c"], from, to)
			if t > 0.0 and t < best_t:
				best_t = t
				best_i = i
	else:
		for idx in indices:
			var i: int = idx
			var t := _mt_hit(tris[i]["a"], tris[i]["b"], tris[i]["c"], from, to)
			if t > 0.0 and t < best_t:
				best_t = t
				best_i = i
	if best_i < 0:
		return {}
	return {"t": best_t, "index": best_i,
		"position": from + (to - from) * best_t}

# ---- 场景组装（自提交碰撞三角形汤 → 可射线查询结构）----

## 全图三角 + face 表（同序拼接：faces[i] ↔ tris[i]，即自提交碰撞三角形顺序）；
## offset ≠ 0 时顶点变换到世界（平移场景），face 表不变。
func _scene(r: Dictionary, offset := Vector3.ZERO) -> Dictionary:
	var tris: Array = []
	var faces: Array = []
	for chunk_info in r["chunks"]:
		var cd: Dictionary = chunk_info
		var pd: Dictionary = Picking.chunk_pick_data(cd)
		var soup: PackedVector3Array = pd["collision_faces"]
		var table: Array = pd["face_table"]
		for i in soup.size() / 3:
			tris.append({
				"a": soup[i * 3] + offset,
				"b": soup[i * 3 + 1] + offset,
				"c": soup[i * 3 + 2] + offset,
			})
		faces.append_array(table)
	return {"tris": tris, "faces": faces}

## 直下射线拾取（局部场景）：miss → null；hit → face 表 + 规则 → 格
func _pick_local(scene: Dictionary, m, from: Vector3, to: Vector3) -> Variant:
	return _pick_world(scene, m, from, to, Transform3D(Basis(), Vector3.ZERO))

## 直下射线原始命中（不做规则解析，供用例自取 face/index）
func _pick_local_raw(scene: Dictionary, m, from: Vector3, to: Vector3) -> Dictionary:
	return _ray_nearest(scene["tris"], from, to)

func _pick_world_raw(scene: Dictionary, from: Vector3, to: Vector3) -> Dictionary:
	return _ray_nearest(scene["tris"], from, to)

func _pick_world(scene: Dictionary, m, from: Vector3, to: Vector3, to_local: Transform3D) -> Variant:
	var hit := _ray_nearest(scene["tris"], from, to)
	if hit.is_empty():
		return null
	var face: Dictionary = scene["faces"][hit["index"]]
	return Picking.resolve_face(to_local * (hit["position"] as Vector3), face, m, SIZE)

## 55° 俯角斜射线（沙盒相机口径；cot55° ≈ 0.700 → 水平 5.6 / 垂直 8.0）：
## origin = 格心上方 8.0 + 南（或北）5.6，射线**延长越过格心 0.5**（避免 t=1.0
## 边界的浮点拒判——命中仍为格心顶面，t 严格内点）
func _pick_tilted(scene: Dictionary, m, cell: Vector2i, from_south: bool) -> Variant:
	var target := Hex.axial_to_world(cell, SIZE, float(m.elevation_at(cell)) * STEP)
	var dz := 5.6 if from_south else -5.6
	var from := Vector3(target.x, target.y + 8.0, target.z + dz)
	var dir := (target - from).normalized()
	return _pick_world(scene, m, from, target + dir * 0.5, Transform3D(Basis(), Vector3.ZERO))

# ---- 60×40 抽样加速：XZ 均匀网格桶（直下射线只查命中点所在桶）----

func _make_grid(tris: Array, cell := 2.0) -> Dictionary:
	var buckets := {}
	for i in tris.size():
		var t: Dictionary = tris[i]
		var a: Vector3 = t["a"]
		var b: Vector3 = t["b"]
		var c: Vector3 = t["c"]
		var k0 := Vector2i(int(floor(minf(a.x, minf(b.x, c.x)) / cell)),
			int(floor(minf(a.z, minf(b.z, c.z)) / cell)))
		var k1 := Vector2i(int(floor(maxf(a.x, maxf(b.x, c.x)) / cell)),
			int(floor(maxf(a.z, maxf(b.z, c.z)) / cell)))
		for gx in range(k0.x, k1.x + 1):
			for gz in range(k0.y, k1.y + 1):
				var key := Vector2i(gx, gz)
				if not buckets.has(key):
					buckets[key] = [] as Array[int]
				(buckets[key] as Array[int]).append(i)
	return {"cell": cell, "buckets": buckets, "tris": tris}

func _ray_down_grid(grid: Dictionary, x: float, z: float, top: float, bottom: float) -> Dictionary:
	var key := Vector2i(int(floor(x / grid["cell"])), int(floor(z / grid["cell"])))
	var buckets: Dictionary = grid["buckets"]
	if not buckets.has(key):
		return {}
	return _ray_nearest(grid["tris"], Vector3(x, top, z), Vector3(x, bottom, z), buckets[key])

# ---- 辅助 ----

func _pattern_map(w: int, h: int) -> MapDataClass:
	var m := MapDataClass.new(w, h)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		m.set_elevation(cell, (cr.x * 2 + cr.y * 3) % 5 - 2)  # −2..2 含负层与三档连接
	return m

func _build_ok(m, chunk_cols := 10, chunk_rows := 10) -> Dictionary:
	var r: Variant = Builder.build_map(m, chunk_cols, chunk_rows, {}, SIZE, STEP, SOLID)
	expect(r is Dictionary, "build_map 应成功（返回 Dictionary）")
	if r is Dictionary:
		return r as Dictionary
	return {"chunks": [], "chunk_rects": [], "materials": {}}

func _lerp_centers(a: Vector2i, b: Vector2i, t: float) -> Vector3:
	var ca := Hex.axial_to_world(a, SIZE)
	var cb := Hex.axial_to_world(b, SIZE)
	return ca + (cb - ca) * t

func _smaller_id(m, a: Vector2i, b: Vector2i) -> Vector2i:
	return a if m.index_of(a) < m.index_of(b) else b

func _owner_and_corner(m, a: Vector2i, b: Vector2i, c: Vector2i) -> Array:
	var trio: Array[Vector2i] = [a, b, c]
	var owner := trio[0]
	for cell in trio:
		if m.index_of(cell) < m.index_of(owner):
			owner = cell
	var others: Array[Vector2i] = []
	for cell in trio:
		if cell != owner:
			others.append(cell)
	for j in 6:
		if others.has(Hex.neighbor(owner, j)) and others.has(Hex.neighbor(owner, j - 1)):
			return [owner, j]
	return [Vector2i(), -1]

func _corner_centroid(owner: Vector2i, j: int) -> Vector3:
	var p1 := Hex.inner_vertex(owner, j, SIZE, SOLID, 0.0)
	var br_j := Hex.bridge_xz(owner, j, SIZE, SOLID)
	var br_j1 := Hex.bridge_xz(owner, j - 1, SIZE, SOLID)
	var p2 := p1 + Vector3(br_j.x, 0.0, br_j.y)
	var p3 := p1 + Vector3(br_j1.x, 0.0, br_j1.y)
	return (p1 + p2 + p3) / 3.0

func _same_set(x: Array, y: Array) -> bool:
	if x.size() != y.size():
		return false
	for e in x:
		if not y.has(e):
			return false
	return true
