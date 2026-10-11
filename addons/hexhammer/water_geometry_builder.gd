## water_geometry_builder.gd — 水面第二 mesh 构建器（M1a T3 WATER-02/03；
##   执行方案 docs/M1a-terrain-T2-T5-execution-plan.md §4 WATER-02 ②/WATER-03 ③⑤ +
##   ADR-14 格边河流 docs/02-architecture.md:207-227）
## 职责：沿 WorldData 河段边序列展开**水面条带** + 共享角点**角点补面**（接缝）
##   + 水体成员格**水面扇** + 成员间**带面** + 岸线**裙边**——独立第二 mesh
##   （Catlike Part 6「水面独立 mesh」纪律的格边移植；河床下切在 HexTerrainBuilder
##   边带侧，本文件只管水面）。纯逻辑类：RefCounted、零场景节点（ADR-2，沿
##   hex_terrain_builder.gd 先例）；场景挂载在 scripts/ui/map_view.gd（view 层
##   ——删 scripts/ui/** 后 tests 全绿）。
## 合同（翻案须先改执行方案 §4 对应卡与 tests/test_water_geometry.gd，不动架构）：
## - **水面不进碰撞/拾取层**（WATER-02 ③）：本产物只产出 mesh+faces 元数据，
##   view 挂载零碰撞体、不进 LAYER_TERRAIN——「水层不截获地形拾取」由结构保证
##   （chunk_pick_data 只读地形 builder 的 chunk 信息，永不含本 mesh 面片）；
## - 水面 y = (water_level − 0.5) × elevation_step——**半档错位**（Catlike Part 6
##   (level−0.5)×step 防与河床/岸共面 + 本作档位化错位先例 hex_highlight.gd
##   LIFT_TIER_STEP 档位表：水面错半档、不取地表 lift 档，与路面/格线不同面系，
##   hex_highlight.gd 档位表已登记）；河口对账：终点边河面 y == 水体水面 y 由
##   同公式同 level 保证（WATER-03 ④ 校验器的几何面）；
## - 河面条带沿整条边全长（s ∈ [0,1] 端点到端点——修订记录三之 1：~~沿边切向
##   中段 t∈[0.4,0.6]~~ 禁止，每边只切 20% 长度不成河）；跨河占连接带中段
##   w = 1 − 2×RIVER_BANK_FRACTION（**恒宽**：不随 flow_level 变——首版河宽口径，
##   flow_level 兑现走水面材质参数层（沿流向 UV 的流速/色深分档），§2.2 同口径）；
## - 每有河 link 恰一水面条带（quad = 2 三角，全图计数断言锚）；**共享角点出角点
##   补面**（kind="water_corner"，WATER-02 ①「多条连续边在共享角点做河床/水面/
##   岸带接缝」的水面侧；河床侧 = 地形 builder _emit_corner_fill 河畔角）：角点
##   三边中**恰一边有水面则水到此为止**（河源/湖岸死端的合法终止），**≥2 边有
##   水面则补角**——各边水面在角点内三角（角点三格的内顶点围成）边界上的「到达
##   段」并集围成的凸环做质心扇形（条带×条带 = 河流转角楔、带×带 = 湖内角、
##   带×裙 = 湖岸角、条带×带 = 河口角……同一规则覆盖）；到达段端点与各发射面
##   **同表达式派生**（条带段 = _strip_quad 同参、带段 = 两端成员内顶点、裙段 =
##   成员顶点+0.5·bridge——接缝顶点逐位一致）；补面恒落在角点内三角内——与
##   条带（连接带 u∈[bank,1−bank]）/水面扇（成员格内六边形）/带面（成员边
##   u∈[0,1]）/裙边（岸边带 u∈[0,0.5]·成员侧）的域互不相交（不重复水面）；
## - **水体连续水面（WATER-03 ③「整水体统一 water_level×step − 半档错位」）**：
##   同体相邻成员格的连接带出**整段带面**（kind="water_band"，u∈[0,1] 两端 =
##   两成员格内边——与两侧水面扇同 inner_vertex 表达逐位一致；沿边镜像配对
##   同条带终点延展），归属 = link 两端格稳定 ID 较小者（防双侧重复发射）；
##   异体水-水邻接（两不同水位水体贴边——无 fixture 覆盖的病理态）两侧各出
##   半带裙边至带中段相接，水位各随本体；
## - 河口接缝（WATER-03 ④）：终点边条带向水体成员侧**延至该格内边**（跨带 u=1），
##   与水体水面扇（内六边形）边缘顶点同一全局参数（HexMath.inner_vertex）——
##   「终点边河面条带终点顶点 = 水体水面边缘顶点」的机器表达；成员侧顶点沿边
##   **镜像配对**（owner 顶点 d ↔ 成员格顶点 dm+1、d+1 ↔ dm——bridge 恒等式 +
##   端序翻转，配反 = 扭四边形/孔洞）；有河的岸边不重复出裙边（水面不重叠，
##   条带认领该边）；
## - 悬崖岸裙边（WATER-03 ⑤，Catlike「悬崖岸也有隐藏在地形下的裙边」）：岸线边
##   （水陆共享边）水面从成员格内边向陆侧延伸至连接带中段（= 崖壁脚/岸坡与水面
##   平面交线一带；顶点从格心参数反推、y 钳到水面高）——Δ1 岸坡的水线恰在带
##   中段、Δ≥cliff_threshold 的崖壁脚即带中段，同一几何覆盖缓岸与崖岸；
## - chunk 无关铁律：全部顶点由 link/cell + HexMath 全局参数唯一路径现算
##   （inner_vertex / bridge_xz / 显式分数插值），归属规则与地形 builder 同源
##   （边带/条带/带面 = link 两端格稳定 ID 较小者、水面扇/裙边 = 成员格自身、
##   角点补面 = 角点三格最小 ID 格——角落归属同比较器）——跨 chunk 三种划分
##   逐位一致（tests/test_water_geometry.gd 锚）；
## - 绕序：raw 顶点俯视逆时针 + 渲染索引 (base, base+2, base+1) 翻转为 Godot
##   正面（hex_terrain_builder.gd「绕序双层口径」同款；**全部面种类同口径**——
##   条带/裙带曾按交叉序发射（raw 顺时针 = 索引背面，俯视被 CULL_BACK 剔除），
##   2026-10-12 T3 评审修复统一为逆时针环；法线恒 +Y（水平面），角点补面水位差
##   斜面例外（现算 cross——「瀑布唇」面）；
## - 参数非法（size/step ≤0、solid ∉ (0,1)、chunk ≤0、material 非 Material）→
##   null（显式失败，无隐式兜底）；**world 数据自身合法性由 WorldData.validate
##   把关**（本 builder 信任已验世界——河口/水位矛盾在数据层已拒）。
class_name WaterGeometryBuilder
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")

## 每侧岸带占连接带比例（河床/水面跨河宽 w = 1 − 2×本值 ≈ 0.6 带宽 ≈ 0.21·size）。
## **卡内拍板项**（WATER-02：跨河宽 w 与岸带/阶地分割比例 spike 后定构建参数默认
## 值）——hex_terrain_builder.gd 河床下切与本文件水面条带共用本常量（跨河几何
## 参数唯一计算点，两侧 u 端点不齐 = 水面悬出河床/藏进岸里）。
const RIVER_BANK_FRACTION := 0.2

## 默认水面色（低饱和深蓝绿、半透明——grimdark 大地色调下的冷色水体）
const DEFAULT_COLOR := Color(0.13, 0.22, 0.28, 0.72)

# ---------------- 材质工厂 ----------------

## 水面材质：半透明 + 无光照（色稳定；流动感属后续 shader/材质参数层）+ 深度测试
## 保持开启（沿 hex_highlight.gd「不靠关深度测试掩盖穿山」纪律——水面被地形正确
## 遮挡）+ CULL_BACK（索引三角俯视顺时针 = Godot 正面，F-1 修复同款）。
static func make_water_material(color: Color = DEFAULT_COLOR) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	return mat


## 水面 y = (water_level − 0.5) × elevation_step（半档错位——见类头注）。
## 河面/湖面/河口共用（河口两侧 y 相等 = 同公式同 level 的直接推论）。
static func water_surface_y(water_level: int, elevation_step := 1.0) -> float:
	return (float(water_level) - 0.5) * elevation_step

# ---------------- 构建入口 ----------------

## 整图分块构建。返回 {"chunks": Array[chunk 字典], "chunk_rects": Array[Rect2i],
##   "material": Material（echo）, "size"/"elevation_step"/"solid_factor": float}。
## chunk 字典 = {"chunk": Rect2i, "mesh": ArrayMesh（单 surface）,
##   "faces": Array[Dictionary]（与三角一一对应：kind="water_strip"（河面条带，
##   另带 link/cell/dir）|"water_body"（水体水面扇，cell/water_body_id）|
##   "water_skirt"（岸线裙边，cell/dir/water_body_id）|"water_band"（成员间带面，
##   cell/dir/link/water_body_id）|"water_corner"（角点补面，cell=角点归属格/
##   dir=角点顶点号，另带 links=参与角点的边）),
##   "face_counts": {water_strip, water_body, water_skirt, water_band, water_corner},
##   "vertex_count": 3×面数}。
## 参数非法 / material 非 Material / world 为空 → null；无河无水体的空 world →
## 全空 chunk mesh（合法态，face_counts 全 0——调用方据此走无水分支）。
static func build_map(map: MapDataClass, world: WorldDataClass, chunk_cols := 10,
		chunk_rows := 10, material: Material = null, size := 1.0,
		elevation_step := 1.0, solid_factor := 0.8) -> Variant:
	if world == null or not (material is Material):
		return null
	if size <= 0.0 or elevation_step <= 0.0 or solid_factor <= 0.0 or solid_factor >= 1.0:
		return null
	if chunk_cols <= 0 or chunk_rows <= 0:
		return null
	var chunks: Array = []
	var rects := _chunk_rects(map.width, map.height, chunk_cols, chunk_rows)
	for rect in rects:
		var built: Variant = build_chunk(map, world, rect, material, size,
			elevation_step, solid_factor)
		if built == null:
			return null
		chunks.append(built)
	return {
		"chunks": chunks,
		"chunk_rects": rects,
		"material": material,
		"size": size,
		"elevation_step": elevation_step,
		"solid_factor": solid_factor,
	}


## 单 chunk 构建：水面扇 + 带面/裙边（成员格归属；带面按 link 较小格归属）+
## 河面条带（link 两端稳定 ID 较小格在本 chunk——与地形边带同归属规则）+
## 角点补面（角点三格最小 ID 格在本 chunk——与地形角落同归属规则）。
## 空矩形（无格）→ null。
static func build_chunk(map: MapDataClass, world: WorldDataClass, chunk: Rect2i,
		material: Material, size := 1.0, elevation_step := 1.0,
		solid_factor := 0.8) -> Variant:
	if world == null or not (material is Material):
		return null
	if size <= 0.0 or elevation_step <= 0.0 or solid_factor <= 0.0 or solid_factor >= 1.0:
		return null
	var cells := _chunk_cells(map, chunk)
	if cells.is_empty():
		return null
	var in_chunk := {}
	for cell in cells:
		in_chunk[cell] = true
	var river_idx := world.river_edge_index()
	var membership := world.water_membership()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	var faces: Array[Dictionary] = []
	var counts := {"water_strip": 0, "water_body": 0, "water_skirt": 0,
		"water_band": 0, "water_corner": 0}
	var vi := 0
	# ① 水体水面扇 + 带面/裙边（成员格归属；同体成员边带面归 link 较小格，
	#    有河边让位给条带——不重叠水面）
	for b in world.water_bodies:
		var y_w := water_surface_y(b.water_level, elevation_step)
		for cid in b.member_cells:
			var cell := _cell_of_id(map, cid)
			if not in_chunk.has(cell):
				continue
			vi = _emit_fan(st, vi, faces, counts, cell, y_w, size, solid_factor,
				b.water_body_id)
			vi = _emit_body_edges(st, vi, faces, counts, map, cell, y_w, size,
				solid_factor, b, membership, river_idx)
	# ② 河面条带（每有河 link 恰一 quad；终点边向水体成员侧延至内边 = 河口接缝）
	for r in world.rivers:
		for k in r.edges.size():
			var link := r.edges[k]
			var owner := _cell_of_id(map, link.x)
			if not in_chunk.has(owner):
				continue
			var is_terminal := k == r.edges.size() - 1
			var y_w := water_surface_y(r.water_levels[k], elevation_step)
			vi = _emit_strip(st, vi, faces, counts, map, link, owner, y_w,
				r.water_body_id if is_terminal else WorldDataClass.ID_NONE,
				size, solid_factor, membership)
	# ③ 角点补面（共享角点接缝——水面侧统一规则）：任何角点 ≥2 条边有水面即补
	#   （水权收集为世界级现算——角点归属格可能在任意 chunk，按归属过滤发射）。
	var claims := _corner_claims(map, world, membership, river_idx, size,
		elevation_step, solid_factor)
	for cid_v in claims:
		var cid := int(cid_v)
		var corner_cell := _cell_of_id(map, cid / 6)
		if not in_chunk.has(corner_cell):
			continue
		vi = _emit_corner_fill(st, vi, faces, counts, map, cid,
			claims[cid_v] as Array, size, solid_factor)
	var mesh := ArrayMesh.new()
	if faces.size() > 0:
		st.commit(mesh)  # 空面 chunk 不 commit（SurfaceTool 空提交不产 surface——调用方以 surface 数判空）
	return {"chunk": chunk, "mesh": mesh, "faces": faces,
		"face_counts": counts.duplicate(), "vertex_count": faces.size() * 3}

# ---------------- 发射 ----------------

## 条带四角唯一计算点（发射与角点补面水权共用——接缝顶点同函数同参数派生 =
## 逐位一致；两处各自重算会引入表达式漂移，是接缝裂缝的典型来源）：
## link = (min,max)，owner = link.x 格、d = owner→对端方向；near/far = 跨带
## u ∈ [bank, 1−bank] 两侧线（near = owner 侧岸缘、far = 对端侧岸缘）；
## v1 端 = owner 顶点 d 角、v2 端 = 顶点 d+1 角（cid_1/cid_2 = 对应稳定角点 ID，
## 补面水权据此选边端）；四点 y 压到 y_w（水面恒水平）。终点边（terminal_body ≠
## ID_NONE）向成员侧延至该格内边：成员侧顶点直接取 inner_vertex(成员格, …)——
## 与水体水面扇同一表达式（bridge 恒等式有 1 ulp 差，「接缝顶点同一全局参数
## 派生逐位一致」要求同式派生），且沿边**镜像配对**（owner 顶点 d ↔ 成员格顶点
## dm+1、d+1 ↔ dm——同跨线的两端从两岸看端序翻转；配反 = 条带扭四边形，
## 域内采样出现孔/重复覆盖）。
static func _strip_quad(map: MapDataClass, link: Vector2i, y_w: float,
		terminal_body: int, membership: Dictionary, size: float,
		solid_factor: float) -> Dictionary:
	var owner := _cell_of_id(map, link.x)
	var other := _cell_of_id(map, link.y)
	var d := Hex.dir_between(owner, other)
	var br := Hex.bridge_xz(owner, d, size, solid_factor)
	var v1 := Hex.inner_vertex(owner, d, size, solid_factor)
	var v2 := Hex.inner_vertex(owner, d + 1, size, solid_factor)
	var bank := RIVER_BANK_FRACTION
	var near_u := bank
	var far_u := 1.0 - bank
	var near_1 := v1.lerp(v1 + Vector3(br.x, 0.0, br.y), near_u)
	var near_2 := v2.lerp(v2 + Vector3(br.x, 0.0, br.y), near_u)
	var far_1 := v1.lerp(v1 + Vector3(br.x, 0.0, br.y), far_u)
	var far_2 := v2.lerp(v2 + Vector3(br.x, 0.0, br.y), far_u)
	if terminal_body != WorldDataClass.ID_NONE:
		var owner_is_member := membership.has(link.x) \
			and (membership[link.x] as WorldDataClass.WaterBodyData).water_body_id == terminal_body
		var other_is_member := membership.has(link.y) \
			and (membership[link.y] as WorldDataClass.WaterBodyData).water_body_id == terminal_body
		if other_is_member:
			# 成员在对岸：far 线延到成员格内边（u=1）。镜像配对——v1 端 ↔ 成员格
			# 顶点 dm+1、v2 端 ↔ dm（bridge 恒等式 + 端序翻转）
			var dm := Hex.dir_between(other, owner)
			far_u = 1.0
			far_1 = Hex.inner_vertex(other, dm + 1, size, solid_factor, y_w)
			far_2 = Hex.inner_vertex(other, dm, size, solid_factor, y_w)
		elif owner_is_member:
			# 成员在 owner 侧：near 线即成员格内边（u=0）——v1/v2 本身就是内边端点
			# （dm == d，无需镜像）
			near_u = 0.0
			near_1 = Hex.inner_vertex(owner, d, size, solid_factor, y_w)
			near_2 = Hex.inner_vertex(owner, d + 1, size, solid_factor, y_w)
	near_1.y = y_w
	near_2.y = y_w
	far_1.y = y_w
	far_2.y = y_w
	return {"owner": owner, "d": d,
		"near_1": near_1, "near_2": near_2, "far_1": far_1, "far_2": far_2,
		"near_u": near_u, "far_u": far_u,
		"cid_1": WorldDataClass.corner_id_of(map, owner, d),
		"cid_2": WorldDataClass.corner_id_of(map, owner, d + 1)}


## 水面条带（quad 2 三角）：几何由 _strip_quad 唯一计算。raw 绕序俯视逆时针
## （cross.y > 0，环 near_1 → far_1 → far_2 → near_2；v1 端 v 参数 = 0）。
## UV：u = 跨河参数（材质横向）、v = 沿边参数（流向——滚动/分档的参数源）。
static func _emit_strip(st: SurfaceTool, vi: int, out_faces: Array[Dictionary],
		counts: Dictionary, map: MapDataClass, link: Vector2i, owner: Vector2i,
		y_w: float, terminal_body: int, size: float, solid_factor: float,
		membership: Dictionary) -> int:
	var q := _strip_quad(map, link, y_w, terminal_body, membership, size, solid_factor)
	var near_1: Vector3 = q["near_1"]
	var near_2: Vector3 = q["near_2"]
	var far_1: Vector3 = q["far_1"]
	var far_2: Vector3 = q["far_2"]
	var near_u: float = q["near_u"]
	var far_u: float = q["far_u"]
	var meta := {"kind": "water_strip", "cell": owner, "dir": int(q["d"]), "link": link}
	vi = _emit_face(st, vi, near_1, far_1, far_2, size,
		Vector2(near_u, 0.0), Vector2(far_u, 0.0), Vector2(far_u, 1.0))
	vi = _emit_face(st, vi, near_1, far_2, near_2, size,
		Vector2(near_u, 0.0), Vector2(far_u, 1.0), Vector2(near_u, 1.0))
	out_faces.append(meta.duplicate())
	out_faces.append(meta.duplicate())
	counts["water_strip"] = int(counts["water_strip"]) + 2
	return vi


## 角点水权收集（世界级现算，chunk 无关——角点归属格与各边归属格互相独立，
## 须全图拼齐再按归属发射）：每条「有水面」的边在其两端角点登记**到达段**
##（段两端点 = 该水面在角点内三角边界上的到达点，与各发射面同表达式派生——
## 逐位一致）。三类：
## - 河面条带段：_strip_quad 同参现算（含终点延展段——u 端点随成员侧延展）；
## - 同体成员边带段：两端成员格内顶点（带面发射侧同式；link 较小格登记一次，
##   防双侧重复）；
## - 岸边裙段：成员顶点 → +0.5·bridge（裙面外缘同式）。异体水-水边（两不同
##   水位水体贴边）两侧各登记各段——两半段分踞三角边两端，补面环退化即跳过
##（两侧裙边已拼满整条带，无角点可补）。
static func _corner_claims(map: MapDataClass, world: WorldDataClass,
		membership: Dictionary, river_idx: Dictionary, size: float,
		elevation_step: float, solid_factor: float) -> Dictionary:
	var out := {}
	# ① 河面条带段（每 link 两端角各一）
	for r in world.rivers:
		for k in r.edges.size():
			var link := r.edges[k]
			var term := r.water_body_id if k == r.edges.size() - 1 else WorldDataClass.ID_NONE
			var q := _strip_quad(map, link,
				water_surface_y(r.water_levels[k], elevation_step),
				term, membership, size, solid_factor)
			_add_claim(out, int(q["cid_1"]), link, q["near_1"], q["far_1"])
			_add_claim(out, int(q["cid_2"]), link, q["near_2"], q["far_2"])
	# ② 水体边段（带/裙）
	for b in world.water_bodies:
		var y_b := water_surface_y(b.water_level, elevation_step)
		for cid in b.member_cells:
			var cell := _cell_of_id(map, cid)
			for d in 6:
				var nb := Hex.neighbor(cell, d)
				if not map.has_cell(nb):
					continue
				var nb_id := map.index_of(nb)
				var lk := WorldDataClass.link_id_of(cid, nb_id)
				if river_idx.has(lk):
					continue  # 有河边：条带认领（①已登记其段）
				var nb_body: WorldDataClass.WaterBodyData = membership.get(nb_id)
				if nb_body != null and nb_body.water_body_id == b.water_body_id:
					# 同体成员边：带段（link 较小格登记——镜像配对与带面发射同式）
					if nb_id < cid:
						continue
					var dm := Hex.opposite_dir(d)
					_add_claim(out, WorldDataClass.corner_id_of(map, cell, d), lk,
						Hex.inner_vertex(cell, d, size, solid_factor, y_b),
						Hex.inner_vertex(nb, dm + 1, size, solid_factor, y_b))
					_add_claim(out, WorldDataClass.corner_id_of(map, cell, d + 1), lk,
						Hex.inner_vertex(cell, d + 1, size, solid_factor, y_b),
						Hex.inner_vertex(nb, dm, size, solid_factor, y_b))
				else:
					# 岸边（或异体边）裙段：成员顶点 → +0.5·bridge（裙面外缘同式）
					var br := Hex.bridge_xz(cell, d, size, solid_factor)
					var half := Vector3(br.x * 0.5, 0.0, br.y * 0.5)
					var w1 := Hex.inner_vertex(cell, d, size, solid_factor, y_b)
					var w2 := Hex.inner_vertex(cell, d + 1, size, solid_factor, y_b)
					_add_claim(out, WorldDataClass.corner_id_of(map, cell, d), lk,
						w1, w1 + half)
					_add_claim(out, WorldDataClass.corner_id_of(map, cell, d + 1), lk,
						w2, w2 + half)
	return out


static func _add_claim(out: Dictionary, cid: int, link: Vector2i,
		p0: Vector3, p1: Vector3) -> void:
	if not out.has(cid):
		out[cid] = [] as Array
	(out[cid] as Array).append({"link": link, "p0": p0, "p1": p1})


## 角点补面（共享角点接缝——水面侧；河床侧 = 地形 builder 河畔角）：角点水权
## <2 段 = 水到此为止（河源/湖岸死端合法终止，不补）；≥2 段 = 全部到达段端点
## 去重成环、质心扇形发射。环点全在角点内三角边界上 → 补面 ⊂ 内三角——与
## 条带/扇/带/裙的域不交（不露洞、不重复水面的机器表达）。**质心扇而非凸包
## 收边**：环上共线的到达段端点（如条带 u=0.2 点落在「角点顶点→u=0.8 点」
## 弦上）必须留为顶点——收边会吞点成 T 型结（边中点悬空）且丢逐位一致锚；
## 质心在凸环内部，扇形三角恒正面积。多段水位不同（河口/瀑布唇/异体角）时
## 扇面为斜面，法线现算。归属 = 角点三格最小 ID 格（cid/6 反解——corner_id_of
## 最小表示的编码位），meta.dir = 该格顶点号（cid%6）。
static func _emit_corner_fill(st: SurfaceTool, vi: int, out_faces: Array[Dictionary],
		counts: Dictionary, map: MapDataClass, cid: int, corner_claims: Array,
		size: float, solid_factor: float) -> int:
	if corner_claims.size() < 2:
		return vi
	var pts: Array = []
	var links: Array = []
	for c in corner_claims:
		pts.append(c["p0"])
		pts.append(c["p1"])
		if not links.has(c["link"]):
			links.append(c["link"])
	var ring := _claim_ring(pts)
	if ring.size() < 3:
		return vi  # 退化（如异体边两半段共线——两侧裙边已拼满整带）
	var area := 0.0
	for i in ring.size():
		var j := (i + 1) % ring.size()
		area += ring[i].x * ring[j].z - ring[j].x * ring[i].z
	if absf(area) < 1e-9:
		return vi  # 共线退化环（面积 ~0）
	var center := Vector3.ZERO
	for p in ring:
		center += p
	center /= float(ring.size())
	var meta := {"kind": "water_corner", "cell": _cell_of_id(map, cid / 6),
		"dir": cid % 6, "links": links}
	for i in ring.size():
		var j := (i + 1) % ring.size()
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[j]
		# 斜面（水位差）法线现算；等水位时 = +Y（环 raw 逆时针 + 质心在内 → cross.y > 0）
		var n := (a - center).cross(b - center).normalized()
		vi = _emit_face(st, vi, center, a, b, size,
			_uv_planar(center, size), _uv_planar(a, size), _uv_planar(b, size), n)
		out_faces.append(meta.duplicate())
	counts["water_corner"] = int(counts["water_corner"]) + ring.size()
	return vi


## 到达段端点成环（去重 + 质心角序；**保留共线点**——见 _emit_corner_fill 注）。
## 去重用 == 精确：同一 (格,顶点,水位) 的 inner_vertex / lerp 派生逐位同值。
## 角相等并列（与质心共线的两点）以距离破平——确定性钉死。出向恒 raw 俯视
## 逆时针（环 shoelace（x,z 标准向）> 0 时反转——cross.y>0 口径的换算）。
static func _claim_ring(pts: Array) -> Array[Vector3]:
	var uniq: Array[Vector3] = []
	for p in pts:
		var dup := false
		for q in uniq:
			if p == q:
				dup = true
				break
		if not dup:
			uniq.append(p)
	if uniq.size() < 3:
		return uniq
	var center := Vector3.ZERO
	for p in uniq:
		center += p
	center /= float(uniq.size())
	uniq.sort_custom(func(a: Vector3, b: Vector3):
		var aa := atan2(a.z - center.z, a.x - center.x)
		var ba := atan2(b.z - center.z, b.x - center.x)
		if aa == ba:
			return a.distance_squared_to(center) > b.distance_squared_to(center)
		return aa > ba)
	var area := 0.0
	for i in uniq.size():
		var j := (i + 1) % uniq.size()
		area += uniq[i].x * uniq[j].z - uniq[j].x * uniq[i].z
	if area > 0.0:
		uniq.reverse()
	return uniq


## 水体水面扇（成员格内六边形 = 与地形顶面同一全局参数 HexMath.inner_vertex——
## 河口接缝顶点逐位一致的参数面）：格心 + 六内顶点，恒 y_w，法线 +Y。
static func _emit_fan(st: SurfaceTool, vi: int, out_faces: Array[Dictionary],
		counts: Dictionary, cell: Vector2i, y_w: float, size: float,
		solid_factor: float, body_id: int) -> int:
	var center := Hex.axial_to_world(cell, size, y_w)
	var meta := {"kind": "water_body", "cell": cell, "water_body_id": body_id}
	for k in 6:
		var a := Hex.inner_vertex(cell, k, size, solid_factor, y_w)
		var b := Hex.inner_vertex(cell, (k + 1) % 6, size, solid_factor, y_w)
		vi = _emit_face(st, vi, center, a, b, size,
			Vector2(0.5, 0.5), _uv_planar(a, size), _uv_planar(b, size))
		out_faces.append(meta.duplicate())
		counts["water_body"] = int(counts["water_body"]) + 1
	return vi


## 水体边面（成员格 cell 的每个邻向 d 分派）：同体成员邻 → **整段带面**
##（kind="water_band"，u∈[0,1]：本格内边 → 对端成员格内边——WATER-03 ③「整
## 水体统一水面」的连接带落地；修复前此处误判「两扇已在内边相接」跳过——两内
## 六边形实隔整条连接带，多格水体成孤岛，2026-10-12 二轮评审 high）；带面归属 =
## link 两端格稳定 ID 较小者（与边带/条带同归属规则，防双侧重复发射）；对端
## 顶点**沿边镜像配对**（cell 顶点 d ↔ 对端格顶点 dm+1、d+1 ↔ dm——bridge 恒等
## 式 + 端序翻转，与条带终点延展同口径），且直接取 inner_vertex(对端格, …)——
## 与对端水面扇边缘同表达式逐位一致。非同体邻（陆格或异体水格）→ **裙边**
##（WATER-03 ⑤：水面从成员格内边 u=0 向外侧延至连接带中段 +0.5·bridge =
## 崖壁脚/岸坡水线一带；异体水-水边两侧各出半带裙边至中段相接，水位各随本体）。
## 有河的岸边不重复出裙边（河面条带已认领该边水面——不重叠）。
static func _emit_body_edges(st: SurfaceTool, vi: int, out_faces: Array[Dictionary],
		counts: Dictionary, map: MapDataClass, cell: Vector2i, y_w: float,
		size: float, solid_factor: float, b: WorldDataClass.WaterBodyData,
		membership: Dictionary, river_idx: Dictionary) -> int:
	for d in 6:
		var nb := Hex.neighbor(cell, d)
		if not map.has_cell(nb):
			continue
		var nb_id := map.index_of(nb)
		var link := WorldDataClass.link_id_of(map.index_of(cell), nb_id)
		if river_idx.has(link):
			continue  # 有河岸边：条带认领（河口接缝边含在内）
		var nb_body: WorldDataClass.WaterBodyData = membership.get(nb_id)
		if nb_body != null and nb_body.water_body_id == b.water_body_id:
			# 同体成员边：整段带面（对端 ID 较小 → 归对端发射）
			if nb_id < map.index_of(cell):
				continue
			var dm := Hex.opposite_dir(d)
			var w1 := Hex.inner_vertex(cell, d, size, solid_factor, y_w)
			var w2 := Hex.inner_vertex(cell, d + 1, size, solid_factor, y_w)
			var e1 := Hex.inner_vertex(nb, dm + 1, size, solid_factor, y_w)
			var e2 := Hex.inner_vertex(nb, dm, size, solid_factor, y_w)
			var bmeta := {"kind": "water_band", "cell": cell, "dir": d,
				"link": link, "water_body_id": b.water_body_id}
			# raw 俯视逆时针环 w1 → e1 → e2 → w2（v1→跨→v2——与条带同绕序口径）
			vi = _emit_face(st, vi, w1, e1, e2, size,
				_uv_planar(w1, size), _uv_planar(e1, size), _uv_planar(e2, size))
			vi = _emit_face(st, vi, w1, e2, w2, size,
				_uv_planar(w1, size), _uv_planar(e2, size), _uv_planar(w2, size))
			out_faces.append(bmeta.duplicate())
			out_faces.append(bmeta.duplicate())
			counts["water_band"] = int(counts["water_band"]) + 2
			continue
		var br := Hex.bridge_xz(cell, d, size, solid_factor)
		var half := Vector3(br.x * 0.5, 0.0, br.y * 0.5)
		var w1 := Hex.inner_vertex(cell, d, size, solid_factor, y_w)
		var w2 := Hex.inner_vertex(cell, d + 1, size, solid_factor, y_w)
		var s1 := w1 + half
		var s2 := w2 + half
		var meta := {"kind": "water_skirt", "cell": cell, "dir": d,
			"water_body_id": b.water_body_id}
		# raw 俯视逆时针环 w1 → s1 → s2 → w2（v1→跨→v2——与条带同绕序口径）
		vi = _emit_face(st, vi, w1, s1, s2, size,
			_uv_planar(w1, size), _uv_planar(s1, size), _uv_planar(s2, size))
		vi = _emit_face(st, vi, w1, s2, w2, size,
			_uv_planar(w1, size), _uv_planar(s2, size), _uv_planar(w2, size))
		out_faces.append(meta.duplicate())
		out_faces.append(meta.duplicate())
		counts["water_skirt"] = int(counts["water_skirt"]) + 2
	return vi

# ---------------- 内部 ----------------

## 单三角发射（水面水平面法线恒 +Y；角点楔形水位差斜面由调用方现算传入——
## 沿 hex_terrain_builder.gd 面法线显式先例。raw 顶点俯视逆时针 + 索引翻转
## Godot 正面——绕序双层口径；faces 序 = 三角序）。
static func _emit_face(st: SurfaceTool, base: int, a: Vector3, b: Vector3, c: Vector3,
		_size: float, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2,
		n: Vector3 = Vector3.UP) -> int:
	st.set_normal(n)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_uv(uv_c)
	st.add_vertex(c)
	st.add_index(base)
	st.add_index(base + 2)
	st.add_index(base + 1)
	return base + 3


## 水平面 UV（与地形 _uv_planar 同式：世界平面映射——水体整面无缝连续平铺）。
static func _uv_planar(p: Vector3, size: float) -> Vector2:
	return Vector2(p.x / (2.0 * size), -p.z / (2.0 * size))


## 行主序 chunk 矩形（与 HexTerrainBuilder.chunk_rects_for 同算法——为避免与地形
## builder 互相 preload 成环（builder 引本文件 RIVER_BANK_FRACTION），此处本地实现；
## 行为逐位一致由 tests/test_water_geometry.gd 的划分对照锚）。
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


## chunk 矩形内的格子（行主序；与 HexTerrainBuilder.chunk_cells 同算法，本地实现
## 同上理由）。
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


## cell 稳定 ID → axial 格（行主序反解，WorldData._cell_of_id 同式——局部实现免
## 访问私有）。
static func _cell_of_id(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))
