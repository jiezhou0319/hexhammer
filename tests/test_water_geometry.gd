## test_water_geometry.gd — T3 WATER-02/03 几何单测（执行方案 §4 WATER-02/
##   WATER-03「测试锚」+ 修订记录三之 1：河床/水面沿整条边连续——双参数 s/w）
## 覆盖锚：
##   - 河床沿整条边全长连续：有河 link 的边带 = 恰 6 面 kind=riverbed（岸坡 2×2 +
##     床 2），**无 t∈[0.4,0.6] 中段切片**（被否决旧稿禁止出现）；床面顶点 y 恒
##     bed_level×step、跨河占连接带中段 [bank, 1−bank]（独立 lerp oracle）；
##     带端点 = 两岸内边原顶点逐位不动（角点焊接面）；
##   - 河边带优先于高程分类（river+cliff / river+terrace 组合同走河床剖面——
##     坡-河-崖角顶点冲突的兜底锚）；
##   - 含河图焊接流形：每物理边恰一连接面（面数解析式）/ 无重复三角 / 边引用 ≤2 /
##     全顶点有限（外沿开边 ⊆ 基线外沿的逐位检查沿 LAND-01 矩阵先例未在此复制
##     ——本锚以「每物理边恰一 + 无重复」覆盖连接面唯一性）；
##   - 跨 chunk 三种划分（单块/行切/每格一块）河床 + 水面顶点逐位一致；
##   - 水面 = 独立第二 mesh：每有河 link 恰一水面面片（quad 2 三角，全图计数）；
##     y = (water_level − 0.5)×step 半档错位；
##   - 水面连续性（WATER-02 ① 共享角点接缝——T3 评审修复锚）：每对连续边所在
##     角点有补面（water_corner）、补面顶点与两邻条带角点端段**逐位一致**
##     （== 精确）；不露洞不重复 = 全链中心线/角点对角线/终点延展域采样每点
##     恰一水面 patch 包含；终点延展沿边镜像配对（扭四边形 = 域内采样出孔/
##     重复——敏感锚）；
##   - 湖/海连续水面（WATER-03 ③——2026-10-12 二轮评审修复锚）：同体相邻成员
##     格连接带出整段带面（water_band，u∈[0,1]），带面顶点与两侧水面扇边缘
##     逐位一致（==）；成员对共享边中点/带中线/三成员角内三角质心采样恰一
##     patch（修复前成员间隔整条连接带成孤岛）；绕序 raw 俯视逆时针
##     （cross.y > 0，全部面种类——条带/裙边曾反向被剔）；
##   - 河口接缝：终点边条带成员侧顶点 = 水体水面扇边缘顶点（同一全局参数派生
##     逐位一致）；
##   - 水面不在碰撞汤：chunk_pick_data 面表不含 water_* 面（riverbed 在）；
##     河床拾取归属 = 两侧两格最近格心 + ID 决胜（resolve_face 纯逻辑面）；
##   - 岸线裙边：非河边岸线出裙边（含悬崖岸——水面向陆侧延伸至带中段，
##     y 钳水面高）；blend 兼容（河图 blend 与 fallback 地形几何逐位一致）。
## oracle 原则：跨河宽度/接缝顶点由测试内独立 lerp/inner_vertex 计算期望值，
##   不复制 builder 内部发射函数；面数 = 解析式独立拼装。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const WaterB := preload("res://addons/hexhammer/water_geometry_builder.gd")
const Picking := preload("res://addons/hexhammer/hex_picking.gd")
const ProfileClass := preload("res://scripts/core/data/landform_profile.gd")
const RiverFix := preload("res://tools/river_fixtures.gd")
const BlendLib := preload("res://addons/hexhammer/hex_terrain_blend.gd")

const MAP_W := 12
const MAP_H := 8
const T_GRASS := 0
const T_ROCK := 2
const T_WATER := 3
const SIZE := 1.0
const SOLID := 0.8
const STEP := 1.0

# ================= fixture（river × cliff × terrace 混合图）=================

## 混合图：基底草 1；河 = 绕 (4,3) 四条边（水平 [2,2,2,1]、床 0）——边 0 叠
## cliff(Δ3)、边 1 叠 terrace(Δ2)（高程抬在河口小湖涂格范围**之外**的东侧邻格：
## 河口湖在终点边成员侧 = 西北向，不触碰 N0/N1）；河口小湖在终点边成员侧；
## 东北第二湖（裙边/扇用，(8,3)=3 为其悬崖岸邻格）。
## 返回 [map, world, chain]。
func _mixed_fixture() -> Array:
	var map := MapDataClass.new(MAP_W, MAP_H)
	var x := Hex.axial_of(Vector2i(4, 3))
	map.set_elevation(Hex.neighbor(x, 0), 4)  # 边 0：|Δ3| cliff × river（东侧——河口不触）
	map.set_elevation(Hex.neighbor(x, 1), 3)  # 边 1：|Δ2| terrace × river（东北侧——河口不触）
	map.set_elevation(Hex.axial_of(Vector2i(8, 3)), 3)  # 第二湖悬崖岸样本
	var chain := RiverFix.around_cell_chain(map, x, 4)
	var term: Vector2i = chain[chain.size() - 1]
	var members: Array[int] = [term.x]
	var mcell := RiverFix.cell_of_id(map, term.x)
	for d in 6:
		var nb := Hex.neighbor(mcell, d)
		if map.has_cell(nb) and map.index_of(nb) != term.y and not members.has(map.index_of(nb)):
			members.append(map.index_of(nb))
	for cid in members:
		var c := RiverFix.cell_of_id(map, cid)
		map.set_elevation(c, 0)
		map.set_terrain(c, T_WATER)
		map.set_passable(c, false)
	members.sort()
	# 河口湖涂格不覆写 cliff/terrace 样本高程（东侧远离西北向河口——构造前提由
	# test_river_band_overrides_terrain_classes 的 delta≥2 断言间接保证：该测试
	# 逐边核对 |Δ|，涂格覆写高程会使 delta 落 0/1 而红）
	# 第二湖（3×2 块）——(8,3)=3 为其悬崖岸邻格
	var lake_cells: Array[int] = []
	for cr in [Vector2i(8, 4), Vector2i(9, 4), Vector2i(8, 5), Vector2i(9, 5), Vector2i(9, 3)]:
		var c := Hex.axial_of(cr)
		map.set_elevation(c, 0)
		map.set_terrain(c, T_WATER)
		map.set_passable(c, false)
		lake_cells.append(map.index_of(c))
	lake_cells.sort()
	var world := WorldDataClass.empty()
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = chain
	reach.water_levels = [2, 2, 2, 1]
	reach.bed_level = 0
	reach.water_body_id = 0
	world.rivers.append(reach)
	var mouth := WorldDataClass.WaterBodyData.new()
	mouth.water_body_id = 0
	mouth.water_level = 1
	mouth.member_cells = members
	mouth.inlet_links = [term]
	mouth.terminal = true
	world.water_bodies.append(mouth)
	var lake := WorldDataClass.WaterBodyData.new()
	lake.water_body_id = 1
	lake.water_level = 1
	lake.member_cells = lake_cells
	lake.terminal = true
	world.water_bodies.append(lake)
	for e in chain:
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = e
		lk.river_reach_id = 0
		world.links.append(lk)
	world.links.sort_custom(func(a: WorldDataClass.NeighborLinkData,
			b: WorldDataClass.NeighborLinkData) -> bool:
		return a.link_id.x < b.link_id.x \
			or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y))
	return [map, world, chain]

## link → [归属格（link.x=min id）, 归属格→对端方向]（归属规则与边带同源——
## 测试侧独立推导）。
func _edge_owner_dir(map: MapDataClass, link: Vector2i) -> Array:
	var owner := RiverFix.cell_of_id(map, link.x)
	var other := RiverFix.cell_of_id(map, link.y)
	return [owner, Hex.dir_between(owner, other)]

func _mats() -> Dictionary:
	var mats := {}
	for t in 6:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.5, 0.5, 0.5)
		mats[t] = m
	return mats

func _build(map: MapDataClass, world: WorldDataClass,
		profile: ProfileClass = null, cc := 6, cr := 4) -> Dictionary:
	var built: Variant = Builder.build_map(map, cc, cr, _mats(), SIZE, STEP, SOLID,
		profile, world)
	if not (built is Dictionary):
		fail("地形构建失败（前置）")
		return {}
	return built

## 全部面记录 + 逐面顶点（faces 序 = 三角序 = 顶点序，builder 合同）。
func _faces_with_verts(build: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ch in build["chunks"]:
		var mesh: ArrayMesh = ch["mesh"]
		for si in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var faces: Array = ch["surfaces"][si]["faces"]
			for t in faces.size():
				var f: Dictionary = faces[t]
				out.append({
					"meta": f,
					"v0": verts[t * 3],
					"v1": verts[t * 3 + 1],
					"v2": verts[t * 3 + 2],
				})
	return out

func _water_build(map: MapDataClass, world: WorldDataClass, cc := 6, cr := 4) -> Dictionary:
	var built: Variant = WaterB.build_map(map, world, cc, cr,
		WaterB.make_water_material(), SIZE, STEP, SOLID)
	if not (built is Dictionary):
		fail("水面构建失败（前置）")
		return {}
	return built

func _water_faces_with_verts(wbuild: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ch in wbuild["chunks"]:
		var mesh: ArrayMesh = ch["mesh"]
		if mesh.get_surface_count() == 0:
			continue  # 无水面几何的 chunk（空面不产 surface——builder 合同）
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var faces: Array = ch["faces"]
		for t in faces.size():
			out.append({
				"meta": faces[t],
				"v0": verts[t * 3],
				"v1": verts[t * 3 + 1],
				"v2": verts[t * 3 + 2],
			})
	return out

# ================= 河床边带（WATER-02 ①：整条边连续 + 双参数 s/w）=================

func test_riverbed_band_full_length_constant_width_and_endpoints() -> void:
	var fixture := _mixed_fixture()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var chain: Array[Vector2i] = fixture[2]
	var build := _build(map, world, ProfileClass.make_default())
	if build.is_empty():
		return
	var faces := _faces_with_verts(build)
	# 每有河 link 恰 6 面 kind=riverbed（岸坡 A 2 + 床 2 + 岸坡 B 2——整条边连续
	# 剖面，无中段 20% 切片：被否决旧稿 t∈[0.4,0.6] 在此形状下不可能出现）
	var by_edge := {}
	for f in faces:
		var m: Dictionary = f["meta"]
		if m["kind"] != Builder.FACE_RIVERBED:
			continue
		var key := "%s|%d" % [str(m["cell"]), int(m["dir"])]
		if not by_edge.has(key):
			by_edge[key] = []
		(by_edge[key] as Array).append(f)
	expect_eq(by_edge.size(), chain.size(), "河边带归属数 = 边数（每 link 一归属）")
	for key in by_edge:
		expect_eq((by_edge[key] as Array).size(), 6, "每有河 link 恰 6 面河床剖面 %s" % key)
	# 形状 oracle：取边 1（river × terrace：岸 A=x elev 1、岸 B=N1 elev 3）——
	# 端点不动 + 床沿 [bank, 1−bank] 独立 lerp
	var od := _edge_owner_dir(map, (chain[1] as Vector2i))
	var owner: Vector2i = od[0]
	var d: int = od[1]
	var key2 := "%s|%d" % [str(owner), d]
	expect(by_edge.has(key2), "构造前提：找到边 1 的面组（%s）" % key2)
	if by_edge.has(key2):
		var verts := _flat_verts(by_edge[key2])
		var bank := WaterB.RIVER_BANK_FRACTION
		var y_a := float(map.elevation_at(owner)) * STEP
		var nb := Hex.neighbor(owner, d)
		var y_b := float(map.elevation_at(nb)) * STEP
		var y_bed := 0.0
		# 独立 oracle：剖面关键点（岸 A 内边两端 v1/v2；床沿 m1/n1 = v1→v3 的
		# bank/1−bank 水平插值；岸 B 内边端点 = 对岸格内边原参数——对应关系：
		# owner 顶点 d ↔ nb 顶点 opp+1、owner 顶点 d+1 ↔ nb 顶点 opp（沿边镜像序））
		var v1 := Hex.inner_vertex(owner, d, SIZE, SOLID, y_a)
		var v2 := Hex.inner_vertex(owner, d + 1, SIZE, SOLID, y_a)
		var v3 := Hex.inner_vertex(nb, Hex.opposite_dir(d) + 1, SIZE, SOLID, y_b)
		var v4 := Hex.inner_vertex(nb, Hex.opposite_dir(d), SIZE, SOLID, y_b)
		var m1 := v1.lerp(v3, bank)
		var n1 := v1.lerp(v3, 1.0 - bank)
		m1.y = y_bed
		n1.y = y_bed
		for want in [v1, v2, m1, n1, v3, v4]:
			expect(_has_vertex(verts, want), "河床剖面含关键顶点 %s（端点不动/床沿 oracle）" % str(want))
		# 床顶点 y 恒 bed_level×step；岸端点 y = 各岸高程（同高程端点不移位）
		for v in verts:
			expect(_almost_zero(v.y - y_bed) or _almost_zero(v.y - y_a) or _almost_zero(v.y - y_b),
				"河边带顶点 y ∈ {床, 岸A, 岸B}（got %s）" % str(v.y))

func _flat_verts(fs: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for f in fs:
		out.append(f["v0"])
		out.append(f["v1"])
		out.append(f["v2"])
	return out

func _has_vertex(verts: Array[Vector3], want: Vector3) -> bool:
	for v in verts:
		if v.distance_to(want) < 1e-6:
			return true
	return false

func _almost_zero(v: float) -> bool:
	return absf(v) < 1e-6

func test_river_band_overrides_terrain_classes() -> void:
	# 河 × cliff / 河 × terrace：河边带优先于高程分类——同走河床剖面（kind 全
	# riverbed、无 edge 面）；坡-河-崖角的顶点冲突由角扇耳切兜底（流形锚在下方）
	var fixture := _mixed_fixture()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var chain: Array[Vector2i] = fixture[2]
	var build := _build(map, world, ProfileClass.make_default())
	if build.is_empty():
		return
	var faces := _faces_with_verts(build)
	var x := Hex.axial_of(Vector2i(4, 3))
	for k in [0, 1]:
		var link: Vector2i = chain[k]
		var od := _edge_owner_dir(map, link)
		var owner_key := "%s|%d" % [str(od[0]), int(od[1])]
		var riverbed_n := 0
		var edge_n := 0
		for f in faces:
			var m: Dictionary = f["meta"]
			var key := "%s|%d" % [str(m["cell"]), int(m.get("dir", -1))]
			if key != owner_key:
				continue
			if m["kind"] == Builder.FACE_RIVERBED:
				riverbed_n += 1
			elif m["kind"] == "edge":
				edge_n += 1
		var delta := absi(map.elevation_at(x) - map.elevation_at(Hex.neighbor(x, k)))
		expect(delta >= 2, "构造前提：边 %d 为阶地/崖档（Δ%d）" % [k, delta])
		expect_eq(riverbed_n, 6, "河 × 高档边：全部 6 面 = riverbed（k=%d Δ%d）" % [k, delta])
		expect_eq(edge_n, 0, "河 × 高档边：无常规 edge 面（河床剖面优先）k=%d" % k)

func test_welded_manifold_river_map() -> void:
	# 含河图焊接流形：每物理边恰一连接面（面数解析式）+ 无重复三角 + 边引用 ≤2 +
	# 全顶点有限。（外沿开边 ⊆ 基线外沿的逐位检查沿 LAND-01 矩阵先例，不在此
	# 复制——本锚覆盖「每物理边恰一连接面、无非有限顶点」两句）
	var fixture := _mixed_fixture()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var profile := ProfileClass.make_default()
	var build := _build(map, world, profile)
	if build.is_empty():
		return
	var faces := _faces_with_verts(build)
	var river_idx := world.river_edge_index()
	# ① 每物理边恰一连接面 + 面数解析式（river 6 / terrace 2·Δ·steps / cliff 6 / else 2）
	var counts := {}
	for f in faces:
		var m: Dictionary = f["meta"]
		if m["kind"] != "edge" and m["kind"] != Builder.FACE_RIVERBED:
			continue
		var key := "%s|%d" % [str(m["cell"]), int(m["dir"])]
		counts[key] = int(counts.get(key, 0)) + 1
	var checked := 0
	for cell in map.cells():
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not map.has_cell(nb) or map.index_of(nb) < map.index_of(cell):
				continue
			var key := "%s|%d" % [str(cell), d]
			var want := 2
			if river_idx.has(WorldDataClass.link_id_of(map.index_of(cell), map.index_of(nb))):
				want = 6
			else:
				var delta := absi(map.elevation_at(cell) - map.elevation_at(nb))
				var et := Builder.classify_edge(map.elevation_at(cell) - map.elevation_at(nb),
					profile.cliff_threshold)
				if et == Builder.EDGE_TERRACE:
					want = delta * profile.terrace_steps * 2
				elif et == Builder.EDGE_CLIFF:
					want = 6 if profile.cliff_vertical else 2
			expect_eq(int(counts.get(key, 0)), want,
				"每物理边恰一连接面（面数解析式）%s（got %d want %d）"
				% [key, int(counts.get(key, 0)), want])
			checked += 1
	expect(checked > 200, "覆盖足够多的物理边（got %d）" % checked)
	# ② 无重复三角 / 边引用 ≤2 / 全顶点有限（焊接 key = 量化坐标）
	var all_verts: Array[Vector3] = []
	for f in faces:
		all_verts.append(f["v0"])
		all_verts.append(f["v1"])
		all_verts.append(f["v2"])
	for v in all_verts:
		expect(is_finite(v.x) and is_finite(v.y) and is_finite(v.z), "无非有限顶点")
	var ids := _weld(all_verts)
	var seen_tris := {}
	var edge_ref := {}
	for fi in faces.size():
		var triple: Array[int] = [ids[fi * 3], ids[fi * 3 + 1], ids[fi * 3 + 2]]
		triple.sort()
		var tkey := "%d|%d|%d" % [triple[0], triple[1], triple[2]]
		expect(not seen_tris.has(tkey), "重复三角 %s" % tkey)
		seen_tris[tkey] = true
		_bump(edge_ref, ids[fi * 3], ids[fi * 3 + 1])
		_bump(edge_ref, ids[fi * 3 + 1], ids[fi * 3 + 2])
		_bump(edge_ref, ids[fi * 3 + 2], ids[fi * 3])
	var over := 0
	for k in edge_ref:
		if int(edge_ref[k]) > 2:
			over += 1
	expect_eq(over, 0, "边引用 >2 的焊接边 = 0（无三面共边）")

func _weld(verts: Array[Vector3]) -> Array[int]:
	# 量化焊接（1e-5 网格——同物理点跨表达式差 ≤ 1ulp，不同点距离 ≥ 0.05）
	var key_of := {}
	var ids: Array[int] = []
	for v in verts:
		var key := "%d|%d|%d" % [int(round(v.x * 1e5)), int(round(v.y * 1e5)), int(round(v.z * 1e5))]
		if not key_of.has(key):
			key_of[key] = key_of.size()
		ids.append(key_of[key])
	return ids

func _bump(d: Dictionary, a: int, b: int) -> void:
	if a == b:
		return
	var k := "%d_%d" % [mini(a, b), maxi(a, b)]
	d[k] = int(d.get(k, 0)) + 1

# ================= 水面第二 mesh（WATER-02 ②）=================

func test_water_strip_one_quad_per_link_half_level_y() -> void:
	var fixture := _mixed_fixture()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var wbuild := _water_build(map, world)
	if wbuild.is_empty():
		return
	var faces := _water_faces_with_verts(wbuild)
	# 每有河 link 恰一水面面片（quad = 2 三角；全图计数断言）
	var by_link := {}
	var strip_total := 0
	for f in faces:
		var m: Dictionary = f["meta"]
		if m["kind"] != "water_strip":
			continue
		strip_total += 1
		var lk: Vector2i = m["link"]
		if not by_link.has(lk):
			by_link[lk] = 0
		by_link[lk] = int(by_link[lk]) + 1
	var river_edge_count := 0
	for r in world.rivers:
		river_edge_count += r.edges.size()
	expect_eq(strip_total, river_edge_count * 2,
		"全图水面面片数 = 2×河边数（每 link 恰一 quad）（got %d want %d）"
		% [strip_total, river_edge_count * 2])
	for lk in by_link:
		expect_eq(int(by_link[lk]), 2, "每有河 link 恰一水面面片 %s" % str(lk))
	# y = (water_level − 0.5)×step（半档错位——逐段 profile 各边各值）
	var levels := world.river_edge_index()
	for f in faces:
		var m: Dictionary = f["meta"]
		if m["kind"] != "water_strip":
			continue
		var want_y := WaterB.water_surface_y(int(levels[m["link"]]["water"]), STEP)
		for key in ["v0", "v1", "v2"]:
			expect_almost_eq(float(f[key].y), want_y, 1e-9,
				"水面 y = (level−0.5)×step（半档错位）link %s" % str(m["link"]))

func test_mouth_seam_vertices_bit_identical() -> void:
	# 河口接缝：终点边条带成员侧顶点 = 水体水面扇（内六边形）边缘顶点——
	# 同一全局参数派生、**逐位一致**（== 精确比较，非容差）
	var fixture := _mixed_fixture()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var wbuild := _water_build(map, world)
	if wbuild.is_empty():
		return
	var faces := _water_faces_with_verts(wbuild)
	var term: Vector2i = world.rivers[0].edges[world.rivers[0].edges.size() - 1]
	var body := world.water_body_by_id(world.rivers[0].water_body_id)
	# 终点边成员格与朝向（独立推导）
	var member_id := term.x if body.member_cells.has(term.x) else term.y
	var bank_id := term.y if member_id == term.x else term.x
	var member := RiverFix.cell_of_id(map, member_id)
	var d := Hex.dir_between(member, RiverFix.cell_of_id(map, bank_id))
	var y_w := WaterB.water_surface_y(body.water_level, STEP)
	var w1 := Hex.inner_vertex(member, d, SIZE, SOLID, y_w)
	var w2 := Hex.inner_vertex(member, d + 1, SIZE, SOLID, y_w)
	# 条带成员侧两顶点（== 精确）
	var hit := 0
	for f in faces:
		var m: Dictionary = f["meta"]
		if m["kind"] != "water_strip" or m["link"] != term:
			continue
		for key in ["v0", "v1", "v2"]:
			if f[key] == w1 or f[key] == w2:
				hit += 1
	expect(hit >= 2, "终点边条带成员侧顶点与成员格内边**逐位一致**（hit %d/2）" % hit)
	# 水面扇边缘同两顶点（== 精确——同一参数源）
	var fan_hit := 0
	for f in faces:
		var m: Dictionary = f["meta"]
		if m["kind"] != "water_body" or m["cell"] != member:
			continue
		for key in ["v0", "v1", "v2"]:
			if f[key] == w1 or f[key] == w2:
				fan_hit += 1
	expect(fan_hit >= 2, "成员格水面扇边缘含同两顶点（hit %d/2）——接缝两侧同源" % fan_hit)

func test_mouth_seam_far_side_member() -> void:
	# 镜像分支：成员格在**对端侧**（term.y）——条带向对端内边延展，同样与水面扇
	# 边缘逐位一致（两侧对称各锚一次，防单侧实现的假绿）
	var map := MapDataClass.new(MAP_W, MAP_H)
	var x := Hex.axial_of(Vector2i(4, 3))
	var chain := RiverFix.around_cell_chain(map, x, 1)
	var term: Vector2i = chain[0]
	# 成员 = term.y（对端）：涂 term.y 侧格（+邻格，排除 term.x）
	var member_id := term.y
	var bank_id := term.x
	var members: Array[int] = [member_id]
	var mcell := RiverFix.cell_of_id(map, member_id)
	for d in 6:
		var nb := Hex.neighbor(mcell, d)
		if map.has_cell(nb) and map.index_of(nb) != bank_id and not members.has(map.index_of(nb)):
			members.append(map.index_of(nb))
	for cid in members:
		var c := RiverFix.cell_of_id(map, cid)
		map.set_elevation(c, 0)
		map.set_terrain(c, T_WATER)
		map.set_passable(c, false)
	members.sort()
	var world := WorldDataClass.empty()
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = chain
	reach.water_levels = [1]
	reach.bed_level = 0
	reach.water_body_id = 0
	world.rivers.append(reach)
	var body := WorldDataClass.WaterBodyData.new()
	body.water_body_id = 0
	body.water_level = 1
	body.member_cells = members
	body.inlet_links = [term]
	body.terminal = true
	world.water_bodies.append(body)
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = term
	lk.river_reach_id = 0
	world.links.append(lk)
	expect_eq(world.validate(map, T_WATER), "", "镜像 fixture 合法（前置）")
	var wbuild := _water_build(map, world)
	if wbuild.is_empty():
		return
	var faces := _water_faces_with_verts(wbuild)
	var member := RiverFix.cell_of_id(map, member_id)
	var d_from_member := Hex.dir_between(member, RiverFix.cell_of_id(map, bank_id))
	var y_w := WaterB.water_surface_y(1, STEP)
	var w1 := Hex.inner_vertex(member, d_from_member, SIZE, SOLID, y_w)
	var w2 := Hex.inner_vertex(member, d_from_member + 1, SIZE, SOLID, y_w)
	var hit := 0
	for f in faces:
		var m: Dictionary = f["meta"]
		if m["kind"] != "water_strip" or m["link"] != term:
			continue
		for key in ["v0", "v1", "v2"]:
			if f[key] == w1 or f[key] == w2:
				hit += 1
	expect(hit >= 2, "对端侧成员：终点条带对端顶点 = 成员格内边**逐位一致**（hit %d/2）" % hit)

func test_water_skirt_on_shore_edges_including_cliff() -> void:
	# 岸线裙边（WATER-03 ⑤）：非有河岸线每边一裙边 quad（水面向陆侧延伸至带
	# 中段 = 崖壁脚）；悬崖岸与缓坡岸同一几何覆盖；y 钳水面高。
	var fixture := _mixed_fixture()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var wbuild := _water_build(map, world)
	if wbuild.is_empty():
		return
	var faces := _water_faces_with_verts(wbuild)
	var river_edges := world.river_edge_index()
	# 裙边按 link 分组（每边 2 三角 = 一 quad）；oracle 对整组联合断言
	#（单三角只含外缘两点之一——逐面断言会假失败）
	var skirt_by_link := {}
	for f in faces:
		var m: Dictionary = f["meta"]
		if m["kind"] != "water_skirt":
			continue
		var cell: Vector2i = m["cell"]
		var d: int = m["dir"]
		var lk := WorldDataClass.link_id_of(map.index_of(cell), map.index_of(Hex.neighbor(cell, d)))
		if not skirt_by_link.has(lk):
			skirt_by_link[lk] = {"faces": [], "cell": cell, "dir": d,
				"body": m["water_body_id"]}
		(skirt_by_link[lk]["faces"] as Array).append(f)
	# 期望：全部水体的非有河岸线（每边恰一裙边）
	var want := 0
	for b in world.water_bodies:
		for lk in WorldDataClass.shore_links_of(map, b):
			if not river_edges.has(lk):
				want += 1
	expect(want > 0, "存在非河岸线（裙边面非空）")
	expect_eq(skirt_by_link.size(), want,
		"裙边数 = 全水体非有河岸线数（不重叠不缺）（got %d want %d）" % [skirt_by_link.size(), want])
	for lk in skirt_by_link:
		var entry: Dictionary = skirt_by_link[lk]
		var cell: Vector2i = entry["cell"]
		var d: int = entry["dir"]
		var body := world.water_body_by_id(int(entry["body"]))
		var br := Hex.bridge_xz(cell, d, SIZE, SOLID)
		var y_w := WaterB.water_surface_y(body.water_level, STEP)
		var half := Vector3(br.x * 0.5, 0.0, br.y * 0.5)
		var i1 := Hex.inner_vertex(cell, d, SIZE, SOLID, y_w)
		var i2 := Hex.inner_vertex(cell, d + 1, SIZE, SOLID, y_w)
		var s1 := i1 + half
		var s2 := i2 + half
		var found_s1 := false
		var found_s2 := false
		for f in entry["faces"]:
			for key in ["v0", "v1", "v2"]:
				if f[key] == s1:
					found_s1 = true
				if f[key] == s2:
					found_s2 = true
		expect(found_s1 and found_s2,
			"裙边外缘 = 内边+0.5·bridge（带中段/崖壁脚）%s d%d" % [str(cell), d])
	# 悬崖岸样本：(8,3) 高程 3 的格邻湖——其岸边必有裙边（悬崖岸水面向陆侧
	# 延伸至崖壁脚，不因高差缺裙）
	var cliff_cell := Hex.axial_of(Vector2i(8, 3))
	expect_eq(map.elevation_at(cliff_cell), 3, "构造前提：悬崖岸格高程 3")
	var lake := world.water_body_by_id(1)
	var cliff_shore := false
	for lk in WorldDataClass.shore_links_of(map, lake):
		if lk.x == map.index_of(cliff_cell) or lk.y == map.index_of(cliff_cell):
			cliff_shore = true
			expect(skirt_by_link.has(lk), "悬崖岸线边出裙边（Catlike 裙边思路）%s" % str(lk))
	expect(cliff_shore, "构造前提：悬崖格确为第二湖岸")

# ================= 水面连续性（WATER-02 ①：共享角点接缝，T3 评审修复）=================

## 走廊样 fixture（贪心链 9 边：南向连续两步走向相反 = edge[k] ∥ edge[k+2] 的
## 走廊自然产出——弯/直转角混合，60°/120° 角点楔形全覆盖）；河口湖在终点边
## owner 侧（成员 = term.x + 邻格，与 _mixed_fixture 同构造口径）。
func _corridor_fixture() -> Array:
	var map := MapDataClass.new(12, 9)
	var links := RiverFix.all_links(map)
	var seed_cell := Hex.axial_of(Vector2i(5, 1))
	var start := WorldDataClass.link_id_of(map.index_of(seed_cell),
		map.index_of(Hex.neighbor(seed_cell, 5)))
	var chain := RiverFix.greedy_chain(map, links, start, 8,
		func(_row: int) -> float: return 5.0)
	var term: Vector2i = chain[chain.size() - 1]
	var members: Array[int] = [term.x]
	var mcell := RiverFix.cell_of_id(map, term.x)
	for d in 6:
		var nb := Hex.neighbor(mcell, d)
		if map.has_cell(nb) and map.index_of(nb) != term.y and not members.has(map.index_of(nb)):
			members.append(map.index_of(nb))
	for cid in members:
		var c := RiverFix.cell_of_id(map, cid)
		map.set_elevation(c, 0)
		map.set_terrain(c, T_WATER)
		map.set_passable(c, false)
	members.sort()
	var world := WorldDataClass.empty()
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = chain
	reach.water_levels = []
	for i in chain.size():
		reach.water_levels.append(2)
	reach.bed_level = 0
	reach.water_body_id = 0
	world.rivers.append(reach)
	var mouth := WorldDataClass.WaterBodyData.new()
	mouth.water_body_id = 0
	mouth.water_level = 2
	mouth.member_cells = members
	mouth.inlet_links = [term]
	mouth.terminal = true
	world.water_bodies.append(mouth)
	for e in chain:
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = e
		lk.river_reach_id = 0
		world.links.append(lk)
	world.links.sort_custom(func(a: WorldDataClass.NeighborLinkData,
			b: WorldDataClass.NeighborLinkData) -> bool:
		return a.link_id.x < b.link_id.x \
			or (a.link_id.x == b.link_id.x and a.link_id.y < b.link_id.y))
	return [map, world, chain]

## 对端成员单边 fixture（成员 = term.y 侧——other_is_member 延展分支：条带向
## 对端格内边延至 u=1，成员侧顶点沿边镜像配对；配反 = 扭四边形，域内采样出
## 孔/重复——敏感样本，与 test_mouth_seam_far_side_member 同形状独立拼装）。
func _far_member_fixture() -> Array:
	var map := MapDataClass.new(MAP_W, MAP_H)
	var x := Hex.axial_of(Vector2i(4, 3))
	var chain := RiverFix.around_cell_chain(map, x, 1)
	var term: Vector2i = chain[0]
	var members: Array[int] = [term.y]
	var mcell := RiverFix.cell_of_id(map, term.y)
	for d in 6:
		var nb := Hex.neighbor(mcell, d)
		if map.has_cell(nb) and map.index_of(nb) != term.x and not members.has(map.index_of(nb)):
			members.append(map.index_of(nb))
	for cid in members:
		var c := RiverFix.cell_of_id(map, cid)
		map.set_elevation(c, 0)
		map.set_terrain(c, T_WATER)
		map.set_passable(c, false)
	members.sort()
	var world := WorldDataClass.empty()
	var reach := WorldDataClass.RiverReachData.new()
	reach.reach_id = 0
	reach.edges = chain
	reach.water_levels = [1]
	reach.bed_level = 0
	reach.water_body_id = 0
	world.rivers.append(reach)
	var body := WorldDataClass.WaterBodyData.new()
	body.water_body_id = 0
	body.water_level = 1
	body.member_cells = members
	body.inlet_links = [term]
	body.terminal = true
	world.water_bodies.append(body)
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = term
	lk.river_reach_id = 0
	world.links.append(lk)
	return [map, world, chain]

## 独立 oracle：link 条带在角点 cid 端的端段两点（合同 = 跨带 [bank, 1−bank]；
## 终点边成员在 owner 侧时 near 线即成员格内边 u=0——段 = [0, 1−bank]）。
## y 压到该边水面高（与 builder 同口径，比较用整 Vector3 ==）。
func _oracle_corner_segment(map: MapDataClass, link: Vector2i, cid: int,
		terminal_owner_member: bool, y_w: float) -> Array[Vector3]:
	var owner := RiverFix.cell_of_id(map, link.x)
	var d := Hex.dir_between(owner, RiverFix.cell_of_id(map, link.y))
	var br := Hex.bridge_xz(owner, d, SIZE, SOLID)
	var vend := Hex.inner_vertex(owner, d, SIZE, SOLID, 0.0)
	if WorldDataClass.corner_id_of(map, owner, d) != cid:
		vend = Hex.inner_vertex(owner, d + 1, SIZE, SOLID, 0.0)
	var u_lo := WaterB.RIVER_BANK_FRACTION
	var u_hi := 1.0 - WaterB.RIVER_BANK_FRACTION
	if terminal_owner_member:
		u_lo = 0.0
	var out: Array[Vector3] = []
	for uv in [u_lo, u_hi]:
		var u := float(uv)
		var p := vend.lerp(vend + Vector3(br.x, 0.0, br.y), u)
		p.y = y_w
		out.append(p)
	return out

## 测试侧共享角点（独立于 builder：枚举两边端角点 ID 求交——corner_id_of 是
## 数据层公开稳定角点身份，非 builder 内部）。
func _shared_corner(map: MapDataClass, a: Vector2i, b: Vector2i) -> int:
	var ca := RiverFix.cell_of_id(map, a.x)
	var da := Hex.dir_between(ca, RiverFix.cell_of_id(map, a.y))
	var ends_a := [WorldDataClass.corner_id_of(map, ca, da),
		WorldDataClass.corner_id_of(map, ca, da + 1)]
	var cb := RiverFix.cell_of_id(map, b.x)
	var db := Hex.dir_between(cb, RiverFix.cell_of_id(map, b.y))
	for v in [db, db + 1]:
		var cid := WorldDataClass.corner_id_of(map, cb, v)
		if ends_a.has(cid):
			return cid
	return -1

func _pair_key(a: Vector2i, b: Vector2i) -> String:
	var lo := a if a < b else b
	var hi := b if a < b else a
	return "%s|%s" % [str(lo), str(hi)]

func _faces_have_vert_exact(fs: Array, p: Vector3) -> bool:
	for f in fs:
		for key in ["v0", "v1", "v2"]:
			if f[key] == p:
				return true
	return false

func _strip_faces_of(faces: Array, link: Vector2i) -> Array:
	var out := []
	for f in faces:
		var m: Dictionary = f["meta"]
		if m["kind"] == "water_strip" and m["link"] == link:
			out.append(f)
	return out

func test_water_corner_wedge_watertight_bit_identical() -> void:
	# 共享角点接缝（统一角点补面）：每对连续河边所在角点有补面（meta.links 同时
	# 含两边）；补面顶点与两邻条带角点端段**逐位一致**（== 精确——焊接流形，
	# 同函数同参数派生；补面环保留共线段端点、质心扇形不吞点——T 型结防回归）；
	# 归属 = 角点三格最小 ID 格（corner_id_of 反解——与地形角落同比较器）；
	# 补面 y ∈ 角点参与各方水面高（河边水位 + 角点邻接水体水位——河口/湖岸角
	# 混合水权的斜面）。
	var fixture := _mixed_fixture()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var chain: Array[Vector2i] = fixture[2]
	var wbuild := _water_build(map, world)
	if wbuild.is_empty():
		return
	var faces := _water_faces_with_verts(wbuild)
	var fill_by_pair := {}
	var corner_face_count := 0
	for f in faces:
		var m: Dictionary = f["meta"]
		if m["kind"] != "water_corner":
			continue
		corner_face_count += 1
		var mlinks: Array = m["links"]
		for i in mlinks.size():
			for j in range(i + 1, mlinks.size()):
				var key := _pair_key(mlinks[i], mlinks[j])
				if not fill_by_pair.has(key):
					fill_by_pair[key] = []
				(fill_by_pair[key] as Array).append(f)
	# 角点补面数 ≥ 连续边对数（河口湖/第二湖的带×裙角同出补面——统一规则的
	# 自然增量；逐对存在性由下方分组锚定）
	expect(corner_face_count >= (chain.size() - 1),
		"角点补面数 ≥ 连续河边对数（got %d want ≥%d）" % [corner_face_count, chain.size() - 1])
	var levels := world.river_edge_index()
	var membership := world.water_membership()
	for k in chain.size() - 1:
		var la: Vector2i = chain[k]
		var lb: Vector2i = chain[k + 1]
		var key := _pair_key(la, lb)
		expect(fill_by_pair.has(key), "连续边对 %d（%s|%s）有角点补面" % [k, str(la), str(lb)])
		if not fill_by_pair.has(key):
			continue
		var cid := _shared_corner(map, la, lb)
		expect(cid >= 0, "对 %d 共享角点存在（前置——链连续性）" % k)
		if cid < 0:
			continue
		# 归属 = 角点最小 ID 格 + 该格顶点号
		var m0: Dictionary = (fill_by_pair[key] as Array)[0]["meta"]
		expect_eq(m0["cell"], RiverFix.cell_of_id(map, cid / 6),
			"补面归属 = 角点三格最小 ID 格 对%d" % k)
		expect_eq(int(m0["dir"]), cid % 6, "补面 dir = 归属格角点号 对%d" % k)
		# 端段 oracle：每点同时出现在补面与对应条带（== 精确——接缝焊接）
		for link_v in [la, lb]:
			var link: Vector2i = link_v
			var term_owner_member := link == chain[chain.size() - 1]
			var seg := _oracle_corner_segment(map, link, cid, term_owner_member,
				WaterB.water_surface_y(int(levels[link]["water"]), STEP))
			for p in seg:
				expect(_faces_have_vert_exact(fill_by_pair[key] as Array, p),
					"补面含端段点 %s（== 精确）对%d" % [str(p), k])
				expect(_faces_have_vert_exact(_strip_faces_of(faces, link), p),
					"条带含同端段点 %s（== 精确——两侧同点）对%d" % [str(p), k])
		# 补面 y ∈ 角点参与各方水面高（河边水位 ∪ 角点三格邻接水体水位）
		var y_set := [WaterB.water_surface_y(int(levels[la]["water"]), STEP),
			WaterB.water_surface_y(int(levels[lb]["water"]), STEP)]
		for cell_v in [RiverFix.cell_of_id(map, la.x), RiverFix.cell_of_id(map, la.y),
				RiverFix.cell_of_id(map, lb.x), RiverFix.cell_of_id(map, lb.y)]:
			var body: WorldDataClass.WaterBodyData = membership.get(map.index_of(cell_v))
			if body != null:
				var y_body := WaterB.water_surface_y(body.water_level, STEP)
				if not y_set.has(y_body):
					y_set.append(y_body)
		for f in (fill_by_pair[key] as Array):
			# 环顶点（v1/v2——到达段端点）y ∈ 各方水面高；质心（v0，水位差角的
			# 插值高度）介于两端水位之间
			for vk in ["v1", "v2"]:
				var vy: float = f[vk].y
				var ok := false
				for y_w in y_set:
					if _almost_zero(vy - y_w):
						ok = true
				expect(ok, "补面环顶点 y ∈ 角点各方水面高（got %s want %s）对%d"
					% [str(vy), str(y_set), k])
			var yc: float = f["v0"].y
			expect(yc >= y_set.min() - 1e-6 and yc <= y_set.max() + 1e-6,
				"补面质心 y 介于各方水位间（got %s set %s）对%d" % [str(yc), str(y_set), k])

## 采样点被多少个**不同水面 patch**（face meta 去重——quad 的两个三角/楔形扇
## 剖分共享同一 meta）覆盖：恰 1 = 不露洞不重复；0 = 露洞；≥2 = 重复水面。
## 按面计数会把落在三角剖分对角线上的采样双计（同 patch 两三角边界含式各含
## 一侧）——patch 口径才是「重复水面」的语义。
func _cover_patches(faces: Array, p: Vector3) -> int:
	var seen := {}
	for f in faces:
		if _in_tri_xz(p, f["v0"], f["v1"], f["v2"]):
			seen[f["meta"]] = true
	return seen.size()

func _in_tri_xz(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var d1 := _side_xz(p, a, b)
	var d2 := _side_xz(p, b, c)
	var d3 := _side_xz(p, c, a)
	var has_neg := d1 < -1e-7 or d2 < -1e-7 or d3 < -1e-7
	var has_pos := d1 > 1e-7 or d2 > 1e-7 or d3 > 1e-7
	return not (has_neg and has_pos)

func _side_xz(p: Vector3, a: Vector3, b: Vector3) -> float:
	return (b.x - a.x) * (p.z - a.z) - (b.z - a.z) * (p.x - a.x)

## 单 fixture 水面走带：每边中心线 3 采样（s=0.15/0.45/0.85、u=0.5——避开条带
## 三角剖分对角线 u=bank+(1−2bank)·s）+ 每角点对角线 3 采样（两端段中点连线
## t=0.2/0.5/0.8）——每采样恰被一个水面面包含（0 = 露洞、≥2 = 重复水面）。
func _expect_water_walk(map: MapDataClass, world: WorldDataClass,
		chain: Array[Vector2i], faces: Array, label: String) -> void:
	var levels := world.river_edge_index()
	for li in chain.size():
		var link: Vector2i = chain[li]
		var owner := RiverFix.cell_of_id(map, link.x)
		var d := Hex.dir_between(owner, RiverFix.cell_of_id(map, link.y))
		var br := Hex.bridge_xz(owner, d, SIZE, SOLID)
		var v1 := Hex.inner_vertex(owner, d, SIZE, SOLID, 0.0)
		var v2 := Hex.inner_vertex(owner, d + 1, SIZE, SOLID, 0.0)
		for s in [0.15, 0.45, 0.85]:
			var p: Vector3 = v1.lerp(v2, float(s)) + Vector3(br.x, 0.0, br.y) * 0.5
			expect_eq(_cover_patches(faces, p), 1,
				"%s 边%d 中心线 s=%s 恰一 patch（0=露洞 / ≥2=重复水面）" % [label, li, str(s)])
	for k in chain.size() - 1:
		var la: Vector2i = chain[k]
		var lb: Vector2i = chain[k + 1]
		var cid := _shared_corner(map, la, lb)
		expect(cid >= 0, "%s 对%d 共享角点存在（前置）" % [label, k])
		if cid < 0:
			continue
		var mids: Array[Vector3] = []
		for link_v in [la, lb]:
			var link: Vector2i = link_v
			var term_owner_member := link == chain[chain.size() - 1]
			var seg := _oracle_corner_segment(map, link, cid, term_owner_member,
				WaterB.water_surface_y(int(levels[link]["water"]), STEP))
			mids.append((seg[0] + seg[1]) * 0.5)
		for t in [0.2, 0.5, 0.8]:
			var p := mids[0].lerp(mids[1], float(t))
			expect_eq(_cover_patches(faces, p), 1,
				"%s 对%d 角点对角线 t=%s 恰一 patch（楔形接缝连续）" % [label, k, str(t)])

func test_water_surface_continuous_no_hole_no_overlap() -> void:
	# 「不露洞、不重复水面」（提案 :277 验收）：全链中心线 + 角点对角线 + 终点
	# 延展域采样逐点恰一面。三 fixture：弯样（around_cell 4 边）/ 走廊样（贪心
	# 9 边——60°/120° 转角混合）/ 对端成员单边（延展镜像配对敏感——扭四边形时
	# 域内出孔/重复）。
	var fixture := _mixed_fixture()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var chain: Array[Vector2i] = fixture[2]
	var wbuild := _water_build(map, world)
	if wbuild.is_empty():
		return
	expect_eq(world.validate(map, T_WATER), "", "弯样 fixture 合法（前置）")
	_expect_water_walk(map, world, chain, _water_faces_with_verts(wbuild), "弯样")

	var corridor := _corridor_fixture()
	var cmap: MapDataClass = corridor[0]
	var cworld: WorldDataClass = corridor[1]
	var cchain: Array[Vector2i] = corridor[2]
	expect(cchain.size() >= 8, "走廊样链足够长（got %d）" % cchain.size())
	expect_eq(cworld.validate(cmap, T_WATER), "", "走廊样 fixture 合法（前置）")
	var cbuild := _water_build(cmap, cworld, 12, 9)
	if cbuild.is_empty():
		return
	_expect_water_walk(cmap, cworld, cchain, _water_faces_with_verts(cbuild), "走廊样")

	var far := _far_member_fixture()
	var fmap: MapDataClass = far[0]
	var fworld: WorldDataClass = far[1]
	var fterm: Vector2i = (far[2] as Array[Vector2i])[0]
	expect_eq(fworld.validate(fmap, T_WATER), "", "对端成员 fixture 合法（前置）")
	var fbuild := _water_build(fmap, fworld)
	if fbuild.is_empty():
		return
	var ffaces := _water_faces_with_verts(fbuild)
	var fowner := RiverFix.cell_of_id(fmap, fterm.x)
	var fd := Hex.dir_between(fowner, RiverFix.cell_of_id(fmap, fterm.y))
	var fbr := Hex.bridge_xz(fowner, fd, SIZE, SOLID)
	var fv1 := Hex.inner_vertex(fowner, fd, SIZE, SOLID, 0.0)
	var fv2 := Hex.inner_vertex(fowner, fd + 1, SIZE, SOLID, 0.0)
	for s in [0.2, 0.5, 0.8]:
		for u in [0.3, 0.5, 0.7, 0.9]:
			var p: Vector3 = fv1.lerp(fv2, float(s)) + Vector3(fbr.x, 0.0, fbr.y) * float(u)
			expect_eq(_cover_patches(ffaces, p), 1,
				"终点延展（对端成员）域内 s=%s u=%s 恰一 patch（扭四边形 = 出孔/重复）"
				% [str(s), str(u)])

func test_lake_surface_continuous_across_members() -> void:
	# 湖/海连续水面（WATER-03 ③「整水体统一 water_level×step − 半档错位」——
	# 2026-10-12 二轮评审 high 修复锚）：同体相邻成员格连接带出**整段带面**
	#（water_band，u∈[0,1] 两端 = 两成员格内边）；带面顶点与两侧水面扇边缘
	# **逐位一致**（== 精确——inner_vertex 同 (格,顶点,水位) 三元组派生）；
	# 带面归属 = link 两端较小格；成员对共享边中点/带中线/三成员角内三角质心
	# 采样恰一 patch（修复前成员间隔整条连接带成孤岛——中点 0 覆盖）。
	var fixture := _mixed_fixture()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var wbuild := _water_build(map, world)
	if wbuild.is_empty():
		return
	var faces := _water_faces_with_verts(wbuild)
	var membership := world.water_membership()
	var pair_total := 0
	var corner_total := 0
	for b in world.water_bodies:
		var y_b := WaterB.water_surface_y(b.water_level, STEP)
		for cid in b.member_cells:
			var cell := RiverFix.cell_of_id(map, cid)
			for d in 6:
				var nb := Hex.neighbor(cell, d)
				if not map.has_cell(nb) or map.index_of(nb) < cid:
					continue
				var nb_body: WorldDataClass.WaterBodyData = membership.get(map.index_of(nb))
				if nb_body == null or nb_body.water_body_id != b.water_body_id:
					continue
				pair_total += 1
				var lk := WorldDataClass.link_id_of(cid, map.index_of(nb))
				# ① 带面存在（按 link 分组恰一 quad = 2 三角）+ 归属 = 较小格
				var band_faces := []
				for f in faces:
					var m: Dictionary = f["meta"]
					if m["kind"] == "water_band" and m["link"] == lk:
						band_faces.append(f)
				expect_eq(band_faces.size(), 2,
					"成员对 %s 恰一带面 quad（got %d）" % [str(lk), band_faces.size()])
				if band_faces.is_empty():
					continue
				var bm: Dictionary = band_faces[0]["meta"]
				expect_eq(bm["cell"], cell, "带面归属 = link 两端较小格 %s" % str(lk))
				expect_eq(int(bm["water_body_id"]), b.water_body_id, "带面水体归属 %s" % str(lk))
				# ② 带面四角 = 两成员内边顶点（镜像配对 oracle）与两侧水面扇 == 共享
				var dm := Hex.opposite_dir(d)
				var w1 := Hex.inner_vertex(cell, d, SIZE, SOLID, y_b)
				var w2 := Hex.inner_vertex(cell, d + 1, SIZE, SOLID, y_b)
				var e1 := Hex.inner_vertex(nb, dm + 1, SIZE, SOLID, y_b)
				var e2 := Hex.inner_vertex(nb, dm, SIZE, SOLID, y_b)
				for p in [w1, w2, e1, e2]:
					expect(_faces_have_vert_exact(band_faces, p),
						"带面含内边顶点 %s（== 精确）%s" % [str(p), str(lk)])
				var fan_a := _fan_faces_of(faces, cell)
				var fan_b := _fan_faces_of(faces, nb)
				for p in [w1, w2]:
					expect(_faces_have_vert_exact(fan_a, p),
						"本格水面扇含同点 %s（== 精确——接缝焊接）%s" % [str(p), str(lk)])
				for p in [e1, e2]:
					expect(_faces_have_vert_exact(fan_b, p),
						"对端格水面扇含同点 %s（== 精确——接缝焊接）%s" % [str(p), str(lk)])
				# ③ 覆盖采样：成员对共享边中点（评审探针口径）+ 带中线 s 三点
				var ca := Hex.axial_to_world(cell, SIZE)
				var cb := Hex.axial_to_world(nb, SIZE)
				expect_eq(_cover_patches(faces,
					Vector3((ca.x + cb.x) * 0.5, 0.0, (ca.z + cb.z) * 0.5)), 1,
					"成员对共享边中点恰一 patch（修复前孤岛断裂）%s" % str(lk))
				var br := Hex.bridge_xz(cell, d, SIZE, SOLID)
				for s in [0.15, 0.5, 0.85]:
					var p: Vector3 = w1.lerp(w2, float(s)) + Vector3(br.x, 0.0, br.y) * 0.5
					expect_eq(_cover_patches(faces, p), 1,
						"带中线 s=%s 恰一 patch %s" % [str(s), str(lk)])
			# ④ 三成员角：角内三角质心恰一 patch 且为 water_corner（修复前 0 覆盖）
			for k in 6:
				var nk := Hex.neighbor(cell, k)
				var nk1 := Hex.neighbor(cell, k - 1)
				if not map.has_cell(nk) or not map.has_cell(nk1):
					continue
				if map.index_of(nk) < cid or map.index_of(nk1) < cid:
					continue
				var bk: WorldDataClass.WaterBodyData = membership.get(map.index_of(nk))
				var bk1: WorldDataClass.WaterBodyData = membership.get(map.index_of(nk1))
				if bk == null or bk1 == null \
						or bk.water_body_id != b.water_body_id or bk1.water_body_id != b.water_body_id:
					continue
				corner_total += 1
				var v0 := Hex.inner_vertex(cell, k, SIZE, SOLID, y_b)
				var v1 := Hex.inner_vertex(nk, (k + 4) % 6, SIZE, SOLID, y_b)
				var v2 := Hex.inner_vertex(nk1, (k + 2) % 6, SIZE, SOLID, y_b)
				var centroid := (v0 + v1 + v2) / 3.0
				var covered := []
				for f in faces:
					if _in_tri_xz(centroid, f["v0"], f["v1"], f["v2"]):
						covered.append((f["meta"] as Dictionary)["kind"])
				expect(covered.has("water_corner"),
					"三成员角内三角质心由角点补面覆盖（got kinds=%s）cell=%s k=%d"
					% [str(covered), str(cell), k])
	expect(pair_total >= 5, "构造前提：成员对足够多（got %d）" % pair_total)
	expect(corner_total >= 2, "构造前提：三成员角足够多（got %d）" % corner_total)

func _fan_faces_of(faces: Array, cell: Vector2i) -> Array:
	var out := []
	for f in faces:
		var m: Dictionary = f["meta"]
		if m["kind"] == "water_body" and m["cell"] == cell:
			out.append(f)
	return out

func test_water_faces_raw_ccw_winding() -> void:
	# 绕序双层口径 raw 侧：全部水面面（条带/扇/裙/角楔）cross.y > 0（俯视逆时针）
	# ——渲染索引翻转后 = Godot 正面，CULL_BACK 下俯视可见。条带/裙边曾按交叉序
	# 发射（raw 顺时针 = 索引背面，俯视被剔——水面实际不可见），本锚防回归。
	var fixture := _mixed_fixture()
	var wbuild := _water_build(fixture[0], fixture[1])
	if wbuild.is_empty():
		return
	var faces := _water_faces_with_verts(wbuild)
	expect(faces.size() > 50, "构造前提：面数足够（got %d）" % faces.size())
	var kinds := {}
	for f in faces:
		var a: Vector3 = f["v0"]
		var b: Vector3 = f["v1"]
		var c: Vector3 = f["v2"]
		var cy: float = (b - a).cross(c - a).y
		if cy <= 1e-9:
			fail("水面面 raw 绕序非逆时针（kind=%s cross.y=%s）"
				% [str((f["meta"] as Dictionary)["kind"]), str(cy)])
		kinds[(f["meta"] as Dictionary)["kind"]] = true
	for k in ["water_strip", "water_body", "water_skirt", "water_band", "water_corner"]:
		expect(kinds.has(k), "五种水面面齐全（缺 %s）" % k)

# ================= 跨 chunk 无关铁律 =================


func test_chunk_partition_invariance_riverbed_and_water() -> void:
	# 同图三种 chunk 划分（单块 / 6×4 / 每格一块——BLEND-02 划分矩阵先例）：
	# 河床面 + 水面全部顶点逐位一致（全局参数唯一路径派生的可执行验证）
	var fixture := _mixed_fixture()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var profile := ProfileClass.make_default()
	var terr_by_part := {}
	var water_by_part := {}
	for parts in [[MAP_W, MAP_H], [6, 4], [1, 1]]:
		var tb := _build(map, world, profile, parts[0], parts[1])
		var wb := _water_build(map, world, parts[0], parts[1])
		if tb.is_empty() or wb.is_empty():
			return
		terr_by_part[str(parts)] = _sorted_riverbed_verts(tb)
		water_by_part[str(parts)] = _sorted_water_verts(wb)
	expect_eq(terr_by_part[str([MAP_W, MAP_H])], terr_by_part[str([6, 4])],
		"河床顶点：单块 vs 6×4 逐位一致")
	expect_eq(terr_by_part[str([MAP_W, MAP_H])], terr_by_part[str([1, 1])],
		"河床顶点：单块 vs 每格一块 逐位一致")
	expect_eq(water_by_part[str([MAP_W, MAP_H])], water_by_part[str([6, 4])],
		"水面顶点：单块 vs 6×4 逐位一致")
	expect_eq(water_by_part[str([MAP_W, MAP_H])], water_by_part[str([1, 1])],
		"水面顶点：单块 vs 每格一块 逐位一致")

func _sorted_riverbed_verts(build: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for f in _faces_with_verts(build):
		if (f["meta"] as Dictionary)["kind"] == Builder.FACE_RIVERBED:
			out.append(f["v0"])
			out.append(f["v1"])
			out.append(f["v2"])
	out.sort()
	return out

func _sorted_water_verts(wbuild: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for f in _water_faces_with_verts(wbuild):
		out.append(f["v0"])
		out.append(f["v1"])
		out.append(f["v2"])
	out.sort()
	return out

# ================= blend 兼容 + 拾取层合同 =================

func test_blend_fallback_geometry_identical_with_river() -> void:
	# 河图 blend 与 fallback 地形几何逐位一致（水面层独立不参与——blend 色板
	# 只染地形顶点色；BLEND-01 合同在河床面上的延展）
	var fixture := _mixed_fixture()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var profile := ProfileClass.make_default()
	var fb: Variant = Builder.build_map(map, 6, 4, _mats(), SIZE, STEP, SOLID, profile, world)
	var palette := {}
	var base_color := Color(0.5, 0.5, 0.5)
	for t in 6:
		palette[t] = base_color
	var bl: Variant = Builder.build_map_blend(map, palette, 6, 4,
		BlendLib.make_blend_material(), SIZE, STEP, SOLID, profile, world)
	if not (fb is Dictionary) or not (bl is Dictionary):
		fail("构建失败（前置）")
		return
	var fbc: Dictionary = fb
	var blc: Dictionary = bl
	expect_eq(fbc["chunks"].size(), blc["chunks"].size(), "chunk 数一致")
	for ci in (fbc["chunks"] as Array).size():
		var fa: Dictionary = (fbc["chunks"] as Array)[ci]
		var ba: Dictionary = (blc["chunks"] as Array)[ci]
		var fm: ArrayMesh = fa["mesh"]
		var bm: ArrayMesh = ba["mesh"]
		expect_eq(fm.get_surface_count(), bm.get_surface_count(), "surface 数一致 c%d" % ci)
		for si in fm.get_surface_count():
			var farr := fm.surface_get_arrays(si)
			var barr := bm.surface_get_arrays(si)
			expect_eq(farr[Mesh.ARRAY_VERTEX], barr[Mesh.ARRAY_VERTEX],
				"几何逐位一致（VERTEX）c%d s%d" % [ci, si])
			expect_eq(farr[Mesh.ARRAY_INDEX], barr[Mesh.ARRAY_INDEX],
				"索引逐位一致（INDEX）c%d s%d" % [ci, si])
			expect_eq(fa["surfaces"][si]["faces"], ba["surfaces"][si]["faces"],
				"face 表逐位一致 c%d s%d" % [ci, si])

func test_water_not_in_pick_layers_and_riverbed_resolution() -> void:
	# 水面不在碰撞汤：chunk_pick_data 面表不含 water_* 面（水面 mesh 独立、零碰撞
	# 体——结构保证的可见面）；riverbed 面在表内且归属 = 两侧两格最近格心+ID 决胜
	var fixture := _mixed_fixture()
	var map: MapDataClass = fixture[0]
	var world: WorldDataClass = fixture[1]
	var build := _build(map, world, null)
	if build.is_empty():
		return
	var kinds := {}
	var riverbed_face: Dictionary = {}
	for ch in (build["chunks"] as Array):
		var pd := Picking.chunk_pick_data(ch)
		expect_eq((pd["collision_faces"] as PackedVector3Array).size(),
			(pd["face_table"] as Array).size() * 3,
			"碰撞汤 = 3×面表（逐索引对应合同）")
		for f in pd["face_table"]:
			kinds[f["kind"]] = true
			if f["kind"] == Builder.FACE_RIVERBED and riverbed_face.is_empty():
				riverbed_face = f
	for k in kinds:
		expect(not String(k).begins_with("water_"),
			"碰撞面表不含水面面片（水面不截获地形拾取）got kind=%s" % k)
	expect(kinds.has(Builder.FACE_RIVERBED), "河床面在面表（点击水面命中河床）")
	expect(not kinds.is_empty(), "面表非空")
	# 河床归属：最近格心 + ID 决胜（无高程档——不归高地侧）
	if riverbed_face.is_empty():
		fail("未找到 riverbed 面（前置）")
		return
	var owner: Vector2i = riverbed_face["cell"]
	var d: int = riverbed_face["dir"]
	var nb := Hex.neighbor(owner, d)
	var ca := Hex.axial_to_world(owner, SIZE)
	var cb := Hex.axial_to_world(nb, SIZE)
	var near_owner := Vector3(ca.x + (cb.x - ca.x) * 0.1, 0.0, ca.z + (cb.z - ca.z) * 0.1)
	expect_eq(Picking.resolve_face(near_owner, riverbed_face, map, SIZE), owner,
		"河床面归属：近 owner 格心 → owner")
	var near_nb := Vector3(ca.x + (cb.x - ca.x) * 0.9, 0.0, ca.z + (cb.z - ca.z) * 0.9)
	expect_eq(Picking.resolve_face(near_nb, riverbed_face, map, SIZE), nb,
		"河床面归属：近对岸格心 → 对岸")
	var mid := Vector3((ca.x + cb.x) * 0.5, 0.0, (ca.z + cb.z) * 0.5)
	var want_tie := owner if map.index_of(owner) < map.index_of(nb) else nb
	expect_eq(Picking.resolve_face(mid, riverbed_face, map, SIZE), want_tie,
		"河床面归属：带中平局 → 稳定 ID 较小者（决胜与 T4 同比较器）")
