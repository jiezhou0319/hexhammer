## road_geometry_builder.gd — 道路/桥面几何构建器（M1a T4 ROAD-01 ②③ +
##   ROAD-02 ③；执行方案 docs/M1a-terrain-T2-T5-execution-plan.md §5 +
##   Catlike Part 7 道路构型通式 / Part 11 桥放置规则的六边形+格边转译，拍板⑫
##   「只取地形技法」）
## 职责：沿 WorldData 道路格序列展开**贴地路面条带**（路面第二 mesh 层）+ 跨河
##   CrossingData 的**桥面条带**——纯逻辑类：RefCounted、零场景节点（ADR-2，沿
##   hex_terrain_builder.gd / water_geometry_builder.gd 先例）；场景挂载在
##   scripts/ui/map_view.gd（view 层——删 scripts/ui/** 后 tests 全绿）。
## 合同（翻案须先改执行方案 §5 对应卡与 tests/test_road_geometry.gd，不动架构）：
## - **格中心网络**（拍板⑤语义正典：路是格中心与格中心之间）：每格按其**道路
##   方向子集** D ⊆ {0..5}\∅（6 邻内哪些方向有路 link）发射「格心→内边」的路面
##   扇区——**构型通式**：一个公式覆盖全部 2^6−1=63 个方向子集（旋转等价类 14 =
##   Catlike GetRoadInterpolators 14 构型的本作转译），端点/直路/转弯/三叉/四叉
##   同一 data contract；宽度调制 = 格心端按**相邻方向（d±1）有无路**取全宽/窄宽
##   （相邻有路 = 转弯加宽抹平角缝、孤悬端收窄——Catlike「按相邻方向有无路调
##   宽度参数」的字面移植；对向（d+3）不算相邻）；内边端恒全宽（与对岸条带同宽
##   跨连接带拼接无缝）；
## - **连接带条带**：每条**有路 link** 恰一带（归属 = link 两端格稳定 ID 较小者，
##   沿地形 builder 边带归属先例）——从 owner 内边中点跨到对端内边中点，y =
##   两侧格面各自 y + 路面 lift（Δ0 平带 / Δ1 斜带贴坡；Δ≥2 由校验器按生成配置
##   拒绝、builder 信任已验世界）。路面走格心平台+连接带 = **贴地条带**（Catlike
##   Part 7 decal 思想的换载体移植：Godot 无 decal 队列 → 独立 lift 档 mesh），
##   阶地在边带细分不抢顶点（ROAD-01 ③：路面只贴顶面/连接带表面，不改地形 mesh）；
## - **桥面（ROAD-02 ③，修订记录三之 2 走向修正）**：桥面长轴 = **跨岸方向 n**
##   （两岸格心连线，XZ 平面）⊥ 河流方向 t（edge_tangent）——格边单 link 桥下
##   n = dir_unit_world(dir_between(bank_a, bank_b))，与 edge_tangent_world 同向
##   旋转 90°，abs(dot(t,n)) 结构性为 0（测试仍独立拼装断言）；**五段剖面**：
##   两岸平台段（各格心→内边，y = 本岸顶面 + 桥面 lift——**桥头落地、无悬空**）
##   → 两岸接坡段（内边→跨带 u=RIVER_BANK_FRACTION 处，y 爬到 max(两岸)+桥面
##   lift——高差接坡；Δ=0 时退化为平桥）→ 中段跨水（u∈[bank,1−bank] 与水面
##   条带同参数对齐——河在下、路在上）；高差超配置的桥址由 WorldData.validate
##   拒绝（BRIDGE_ENDPOINT_INVALID），本 builder 信任已验世界；
## - **不进地形碰撞/拾取层**（沿水面层先例）：路面条带零碰撞体；**桥面单独
##   提供碰撞汤**（deck_collision/deck_face_table——桥面进碰撞则先于河床命中，
##   面候选 = bank 两格，ROAD-02 ④；view/scene_check 据此建 LAYER_TERRAIN 体，
##   路面条带不建——路面贴本格顶面，穿面命中的地形面归属同格，无需另建）；
## - chunk 无关铁律：全部顶点由 cell/link + HexMath 全局参数唯一路径现算
##   （axial_to_world / inner_vertex / edge_tangent_world），归属比较用全局
##   index_of——跨 chunk 三种划分逐位一致（tests 锚）；绕序 = raw 俯视逆时针 +
##   渲染索引 (base, base+2, base+1) 翻转 Godot 正面（沿 hex_terrain_builder.gd
##   「绕序双层口径」；碰撞汤逐面翻转为 (a,c,b)——chunk_collision_faces 同款）；
## - 参数非法（size/step ≤0、solid ∉ (0,1)、chunk ≤0、材质非 Material、world
##   为空）→ null（显式失败，无隐式兜底）；无路世界 → 全空 chunk mesh（合法态，
##   face_counts 全 0——调用方据此走无路分支）。
class_name RoadGeometryBuilder
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const HexHighlightLib := preload("res://addons/hexhammer/hex_highlight.gd")
# 仅为跨河几何常量 RIVER_BANK_FRACTION（桥面中段与水面条带同参数对齐——两侧
# u 端点不齐 = 桥面悬出水面/压进岸坡）；沿 hex_terrain_builder.gd 引水几何常量先例
const WaterGeom := preload("res://addons/hexhammer/water_geometry_builder.gd")

## 默认路面半宽（× size）：全宽 0.42·size ≈ 连接带宽 0.35·size 同量级偏宽——
## 远相机（探针 h=64）下可读、近景不糊格。观感档调整走 style 材质/后续参数化
const DEFAULT_HALF_WIDTH := 0.21
## 孤悬端（相邻方向无路）的格心端宽度系数（Catlike 通式的「无邻收窄」档）
const LONE_END_WIDTH_FACTOR := 0.6
## 默认路面色（暖土色——grimdark 低饱和大地色调下的路痕）
const DEFAULT_ROAD_COLOR := Color(0.42, 0.36, 0.27, 1.0)
## 默认桥面色（灰褐石面——与路面同族略深，桥=人工结构的视觉区分）
const DEFAULT_BRIDGE_COLOR := Color(0.33, 0.30, 0.27, 1.0)

# ---------------- 材质工厂 ----------------

## 路面材质：不透明 + 无光照（色稳定）+ 深度测试保持开启（穿山纪律同
## hex_highlight——不靠关深度测试掩盖排序问题）+ CULL_BACK（索引三角俯视
## 顺时针 = Godot 正面，F-1 修复同款）。
static func make_road_material(color: Color = DEFAULT_ROAD_COLOR) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	return mat


## 桥面材质（与路面同工厂口径、独立默认色——首版取舍：桥面色不进 TerrainStyle
## 槽位，ROAD-01 只登记 road_material 一槽；换档位属后续 style 扩展）。
static func make_bridge_material(color: Color = DEFAULT_BRIDGE_COLOR) -> StandardMaterial3D:
	return make_road_material(color)


## 构型通式的宽度调制（Catlike「按相邻方向有无路调宽度参数」的唯一计算点，
## 测试直接锚定）：方向 dir 的格心端半宽系数 = 1.0（相邻 d±1 有路——转弯加宽）
## / LONE_END_WIDTH_FACTOR（孤悬端收窄；对向 d+3 不算相邻——直路中段两半条带
## 在格心拼接为全宽直带，无需加宽）。
static func center_width_factor(dir: int, road_dirs: Array[int]) -> float:
	var d := wrapi(dir, 0, 6)
	if road_dirs.has(wrapi(d - 1, 0, 6)) or road_dirs.has(wrapi(d + 1, 0, 6)):
		return 1.0
	return LONE_END_WIDTH_FACTOR

# ---------------- 构建入口 ----------------

## 整图分块构建。road_material = 路面条带材质（style 值或官方工厂）；
## bridge_material = 桥面材质。返回 {"chunks": Array[chunk 字典],
## "chunk_rects": Array[Rect2i], "road_material"/"bridge_material": Material（echo）,
## "size"/"elevation_step"/"solid_factor"/"half_width": float}。
## chunk 字典 = {"chunk": Rect2i, "mesh": ArrayMesh（surface 0 = 路面、surface 1 =
## 桥面，空组不 commit）, "faces": Array[Dictionary]（与三角一一对应，序 = 表面
## 构建序先路面后桥面：kind="road"（格心扇区，cell/dir）|"road_band"（连接带条带，
## cell=owner/dir/link）|"bridge_deck"（桥面，link/bank_a/bank 两格 Vector2i/
## crossing_id）), "face_counts": {road, road_band, bridge_deck},
## "vertex_count": 3×面数, "deck_collision": PackedVector3Array（桥面三角汤，
## 逐面 (a,c,b) 翻转 = Godot 正面，与 deck_face_table 逐索引对应——桥面拾取的
## 碰撞面）, "deck_face_table": Array[Dictionary]（桥面 face 子表）}。
static func build_map(map: MapDataClass, world: WorldDataClass, chunk_cols := 10,
		chunk_rows := 10, road_material: Material = null, size := 1.0,
		elevation_step := 1.0, solid_factor := 0.8,
		bridge_material: Material = null,
		half_width := DEFAULT_HALF_WIDTH) -> Variant:
	if world == null or not (road_material is Material):
		return null
	if size <= 0.0 or elevation_step <= 0.0 or solid_factor <= 0.0 or solid_factor >= 1.0:
		return null
	if chunk_cols <= 0 or chunk_rows <= 0 or half_width <= 0.0:
		return null
	# 桥面材质缺省 = 官方工厂（路面/桥面两槽，view 只须传路面槽——style 侧口径）
	var bridge_mat: Material = bridge_material if bridge_material is Material \
		else make_bridge_material()
	var chunks: Array = []
	var rects := _chunk_rects(map.width, map.height, chunk_cols, chunk_rows)
	for rect in rects:
		chunks.append(build_chunk(map, world, rect, road_material, size,
			elevation_step, solid_factor, bridge_mat, half_width))
	return {
		"chunks": chunks,
		"chunk_rects": rects,
		"road_material": road_material,
		"bridge_material": bridge_mat,
		"size": size,
		"elevation_step": elevation_step,
		"solid_factor": solid_factor,
		"half_width": half_width,
	}


## 单 chunk 构建：本块格的路面扇区（格归属）+ 归属 link 的连接带条带/桥面
##（边归属 = 两端格稳定 ID 较小者在本块——与地形边带/水面条带同归属纪律）。
## 空矩形（无格）→ 空结果（路面层允许空 chunk，沿格线层先例——非「半张图」歧义）。
static func build_chunk(map: MapDataClass, world: WorldDataClass, chunk: Rect2i,
		road_material: Material, size := 1.0, elevation_step := 1.0,
		solid_factor := 0.8, bridge_material: Material = null,
		half_width := DEFAULT_HALF_WIDTH) -> Dictionary:
	var road_links := {}  # link → road_id（link 表 = 道路投影的引用面，validate 已对账）
	for lk in world.links:
		if lk.road_id != WorldDataClass.ID_NONE:
			road_links[lk.link_id] = lk.road_id
	var claims := world.crossing_index()  # 桥认领表（一次性成形，循环内不重算）
	var cells := _chunk_cells(map, chunk)
	var lift_road := HexHighlightLib.lift_for_tier(HexHighlightLib.TIER_ROAD)
	var lift_deck := HexHighlightLib.lift_for_tier(HexHighlightLib.TIER_BRIDGE_DECK)
	var counts := {"road": 0, "road_band": 0, "bridge_deck": 0}

	# ---- surface 0：路面扇区（每格每道路方向 2 三角）----
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(road_material)
	var faces: Array[Dictionary] = []
	var vi := 0
	for cell in cells:
		var id := map.index_of(cell)
		var dirs := _road_dirs_of(map, road_links, cell, id)
		if dirs.is_empty():
			continue
		var y := float(map.elevation_at(cell)) * elevation_step + lift_road
		for d in dirs:
			vi = _emit_platform_strip(st, vi, faces, counts, cell, d, dirs,
				y, size, solid_factor, half_width)
	# ---- surface 0 续：连接带条带（边归属；先带后桥两遍发射——faces 序 =
	#      surface 拼接序的合同面：surface 0 = 路面（扇区+带）、surface 1 = 桥面）----
	for cell in cells:
		var id := map.index_of(cell)
		var y := float(map.elevation_at(cell)) * elevation_step
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not map.has_cell(nb):
				continue
			var nb_id := map.index_of(nb)
			if nb_id < id:
				continue  # 边归属：两端 ID 较小者生成（跨界由归属块发射）
			var link := WorldDataClass.link_id_of(id, nb_id)
			if not road_links.has(link) or claims.has(link):
				continue  # 非路边 / 桥面认领边（对端段处理，见下）——不发贴地条带
			var faces_before := faces.size()
			vi = _emit_band_strip(st, vi, faces, map, cell, nb, d, y,
				size, solid_factor, elevation_step, half_width, lift_road)
			counts["road_band"] = int(counts["road_band"]) + (faces.size() - faces_before)
	# ---- surface 1：桥面（五段剖面；桥面材质独立槽）----
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	st2.set_material(bridge_material if bridge_material is Material else road_material)
	var deck_faces: Array[Dictionary] = []
	var deck_soup := PackedVector3Array()
	for cell in cells:
		var id := map.index_of(cell)
		var y := float(map.elevation_at(cell)) * elevation_step
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not map.has_cell(nb):
				continue
			var nb_id := map.index_of(nb)
			if nb_id < id:
				continue
			var link := WorldDataClass.link_id_of(id, nb_id)
			if not road_links.has(link) or not claims.has(link):
				continue  # 非路边 / 未被认领（贴地带已在上一遍发射）
			var faces_before := faces.size()
			vi = _emit_bridge_deck(st2, vi, faces, deck_faces, deck_soup,
				map, claims, link, cell, nb, y, size, solid_factor,
				elevation_step, half_width, lift_deck)
			counts["bridge_deck"] = int(counts["bridge_deck"]) + (faces.size() - faces_before)
	var mesh := ArrayMesh.new()
	if int(counts["road"]) + int(counts["road_band"]) > 0:
		st.commit(mesh)
	if int(counts["bridge_deck"]) > 0:
		st2.commit(mesh)  # 空组不 commit（SurfaceTool 空提交不产 surface）
	return {"chunk": chunk, "mesh": mesh, "faces": faces,
		"face_counts": counts.duplicate(), "vertex_count": faces.size() * 3,
		"deck_collision": deck_soup, "deck_face_table": deck_faces}


## cell 的道路方向子集（D）：6 邻中哪些方向的 link 有路。方向序 0..5 固定——
## 构型等价类（旋转）测试据此独立对表。
static func _road_dirs_of(map: MapDataClass, road_links: Dictionary,
		cell: Vector2i, cell_id: int) -> Array[int]:
	var out: Array[int] = []
	for d in 6:
		var nb := Hex.neighbor(cell, d)
		if not map.has_cell(nb):
			continue
		if road_links.has(WorldDataClass.link_id_of(cell_id, map.index_of(nb))):
			out.append(d)
	return out


## 路面扇区（格心→内边条带，2 三角）：两端半宽 = 格心端按通式调制 / 内边端全宽
## （与对岸条带同宽跨带拼接）；y 恒 = 本格顶面 + 路面 lift（平台水平面，法线 +Y）。
## raw 绕序俯视逆时针（c1→e1→e2 / c1→e2→c2 两三角，同带条带环向）。
static func _emit_platform_strip(st: SurfaceTool, vi: int, out_faces: Array[Dictionary],
		counts: Dictionary, cell: Vector2i, d: int, dirs: Array[int],
		y: float, size: float, solid_factor: float, half_width: float) -> int:
	var t := Hex.edge_tangent_world(d)
	var center := Hex.axial_to_world(cell, size)
	var v1 := Hex.inner_vertex(cell, d, size, solid_factor)
	var v2 := Hex.inner_vertex(cell, (d + 1) % 6, size, solid_factor)
	var edge_mid := (v1 + v2) * 0.5
	var w_c := half_width * size * center_width_factor(d, dirs)
	var w_e := half_width * size
	var c1 := Vector3(center.x + t.x * w_c, y, center.z + t.z * w_c)
	var c2 := Vector3(center.x - t.x * w_c, y, center.z - t.z * w_c)
	var e1 := Vector3(edge_mid.x + t.x * w_e, y, edge_mid.z + t.z * w_e)
	var e2 := Vector3(edge_mid.x - t.x * w_e, y, edge_mid.z - t.z * w_e)
	var meta := {"kind": "road", "cell": cell, "dir": d}
	vi = _emit_tri(st, vi, c1, e1, e2, size, meta, out_faces)
	vi = _emit_tri(st, vi, c1, e2, c2, size, meta, out_faces)
	counts["road"] = int(counts["road"]) + 2
	return vi


## 连接带条带（owner 内边中点 → 对端内边中点，2 三角）：y = 两侧格面各自 y +
## 路面 lift——Δ0 平带 / Δ1 斜带贴坡（带面 = 平行四边形，窄条带四角取边界线
## 端点即贴面；Δ≥2 由校验器按配置拒绝）。owner→nb 规范向（与地形边带 v1→v3 同向）。
static func _emit_band_strip(st: SurfaceTool, vi: int, out_faces: Array[Dictionary],
		map: MapDataClass, owner: Vector2i, nb: Vector2i, d: int, y_owner: float,
		size: float, solid_factor: float, elevation_step: float,
		half_width: float, lift: float) -> int:
	var t := Hex.edge_tangent_world(d)
	var a1 := Hex.inner_vertex(owner, d, size, solid_factor)
	var a2 := Hex.inner_vertex(owner, (d + 1) % 6, size, solid_factor)
	var dm := Hex.opposite_dir(d)
	var b1 := Hex.inner_vertex(nb, dm + 1, size, solid_factor)
	var b2 := Hex.inner_vertex(nb, dm, size, solid_factor)
	var pa := (a1 + a2) * 0.5
	var pb := (b1 + b2) * 0.5
	var w := half_width * size
	pa.y = y_owner + lift
	pb.y = float(map.elevation_at(nb)) * elevation_step + lift
	var p1 := Vector3(pa.x + t.x * w, pa.y, pa.z + t.z * w)
	var p2 := Vector3(pa.x - t.x * w, pa.y, pa.z - t.z * w)
	var q1 := Vector3(pb.x + t.x * w, pb.y, pb.z + t.z * w)
	var q2 := Vector3(pb.x - t.x * w, pb.y, pb.z - t.z * w)
	var link := WorldDataClass.link_id_of(map.index_of(owner), map.index_of(nb))
	var meta := {"kind": "road_band", "cell": owner, "dir": d, "link": link}
	# raw 绕序俯视逆时针：p1(+t) → q1(+t) → q2(−t) → p2(−t)
	vi = _emit_tri(st, vi, p1, q1, q2, size, meta, out_faces)
	vi = _emit_tri(st, vi, p1, q2, p2, size, meta, out_faces)
	return vi


## 桥面（五段剖面 = 两岸平台段 ×2 + 接坡段 ×2 + 跨水中段；每段 2 三角共 10 面）：
## 长轴 n = 两岸格心连线（跨岸方向）；跨带参数 u ∈ [0,1] = bank_a 内边 → bank_b
## 内边（与地形边带/水面条带同带），中段 u ∈ [bank, 1−bank] 与水面条带同参数对齐。
## y 剖面：a 平台段恒 y_a+lift（**桥头落地**）；接坡段线性爬到 mid；中段恒
## mid = max(两岸 y)+lift（**中段跨水**）；b 侧对称。Δ=0 时全段退化为平桥。
## 桥面同时累计 deck_collision/deck_face_table（桥面拾取候选 = bank 两格）。
static func _emit_bridge_deck(st: SurfaceTool, vi: int, out_faces: Array[Dictionary],
		deck_faces: Array[Dictionary], deck_soup: PackedVector3Array,
		map: MapDataClass, claims: Dictionary, link: Vector2i,
		bank_a: Vector2i, bank_b: Vector2i, y_a_raw: float, size: float,
		solid_factor: float, elevation_step: float, half_width: float,
		lift: float) -> int:
	var crossing: WorldDataClass.CrossingData = claims[link]
	var d := Hex.dir_between(bank_a, bank_b)
	var t := Hex.edge_tangent_world(d)  # ⊥ n（edge_tangent = dir_unit 旋转 90°）
	var w := half_width * size
	var y_a := y_a_raw + lift
	var y_b := float(map.elevation_at(bank_b)) * elevation_step + lift
	var y_mid := maxf(y_a, y_b)
	# 中心线六点：a 格心 → a 内边中点(u=0) → u=bank → u=1−bank → b 内边中点(u=1) → b 格心
	var ca := Hex.axial_to_world(bank_a, size)
	var ia1 := Hex.inner_vertex(bank_a, d, size, solid_factor)
	var ia2 := Hex.inner_vertex(bank_a, (d + 1) % 6, size, solid_factor)
	var pa := (ia1 + ia2) * 0.5
	var dm := Hex.opposite_dir(d)
	var ib1 := Hex.inner_vertex(bank_b, dm + 1, size, solid_factor)
	var ib2 := Hex.inner_vertex(bank_b, dm, size, solid_factor)
	var pb := (ib1 + ib2) * 0.5
	var bank_frac := WaterGeom.RIVER_BANK_FRACTION
	var p := [ca, pa, pa.lerp(pb, bank_frac), pa.lerp(pb, 1.0 - bank_frac), pb,
		Hex.axial_to_world(bank_b, size)]
	var ys := [y_a, y_a, y_mid, y_mid, y_b, y_b]
	var meta := {"kind": "bridge_deck", "link": link, "crossing_id": crossing.crossing_id,
		"bank_a": bank_a, "bank_b": bank_b}
	for s in 5:
		var m1 := Vector3(p[s].x + t.x * w, ys[s], p[s].z + t.z * w)
		var m2 := Vector3(p[s].x - t.x * w, ys[s], p[s].z - t.z * w)
		var n1 := Vector3(p[s + 1].x + t.x * w, ys[s + 1], p[s + 1].z + t.z * w)
		var n2 := Vector3(p[s + 1].x - t.x * w, ys[s + 1], p[s + 1].z - t.z * w)
		vi = _emit_deck_tri(st, vi, m1, n1, n2, size, meta, out_faces, deck_faces, deck_soup)
		vi = _emit_deck_tri(st, vi, m1, n2, m2, size, meta, out_faces, deck_faces, deck_soup)
	return vi


## 单三角发射（路面/条带/桥面共用）：法线按 y 差退化（等高 +Y / 斜面现算 cross），
## raw 俯视逆时针 + 索引 (base, base+2, base+1) 翻转 Godot 正面；faces 序 = 三角序。
## UV = 世界平面映射（T8 约定 u=x/2R、v=−z/2R——路面/桥面按地形同口径平铺）。
static func _emit_tri(st: SurfaceTool, base: int, a: Vector3, b: Vector3, c: Vector3,
		size: float, meta: Dictionary, out_faces: Array[Dictionary]) -> int:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-18:
		n = Vector3.UP  # 退化防御（共线三点不出现于本层几何——防御性兜底）
	else:
		n = n.normalized()
	for p in [a, b, c]:
		st.set_normal(n)
		st.set_uv(_uv_planar(p, size))
		st.add_vertex(p)
	st.add_index(base)
	st.add_index(base + 2)
	st.add_index(base + 1)
	out_faces.append(meta.duplicate())
	return base + 3


## 桥面单三角：同 _emit_tri + 碰撞汤/face 子表累计（deck_soup 逐面 (a,c,b) 翻转 =
## Godot 正面口径——chunk_collision_faces 同款，ConcavePolygonShape3D 射线实测
## 同口径）。
static func _emit_deck_tri(st: SurfaceTool, base: int, a: Vector3, b: Vector3, c: Vector3,
		size: float, meta: Dictionary, out_faces: Array[Dictionary],
		deck_faces: Array[Dictionary], deck_soup: PackedVector3Array) -> int:
	var base_after := _emit_tri(st, base, a, b, c, size, meta, out_faces)
	deck_faces.append(meta.duplicate())
	deck_soup.append(a)
	deck_soup.append(c)
	deck_soup.append(b)
	return base_after


## 水平面 UV（世界平面映射——与地形/水面同式；路面贴图连续平铺的参数面）。
static func _uv_planar(p: Vector3, size: float) -> Vector2:
	return Vector2(p.x / (2.0 * size), -p.z / (2.0 * size))

# ---------------- 内部 ----------------

## 行主序 chunk 矩形（与 HexTerrainBuilder.chunk_rects_for 同算法——本地实现免
## preload 成环，行为逐位一致由 tests 划分对照锚；WaterGeometryBuilder 同理由）。
static func _chunk_rects(map_width: int, map_height: int, chunk_cols: int,
		chunk_rows: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var col0 := 0
	while col0 < map_width:
		var row0 := 0
		while row0 < map_height:
			out.append(Rect2i(col0, row0,
				mini(chunk_cols, map_width - col0),
				mini(chunk_rows, map_height - row0)))
			row0 += chunk_rows
		col0 += chunk_cols
	return out


## chunk 矩形内的格子（行主序；同上本地实现）。
static func _chunk_cells(map: MapDataClass, chunk: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in range(chunk.position.y, chunk.position.y + chunk.size.y):
		if row < 0 or row >= map.height:
			continue
		for col in range(chunk.position.x, chunk.position.x + chunk.size.x):
			if col < 0 or col >= map.width:
				continue
			out.append(Hex.axial_of(Vector2i(col, row)))
	return out
