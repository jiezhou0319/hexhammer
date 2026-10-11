## hex_terrain_builder.gd — 连续高程地形网格几何构建（M1a-T3 平地 → M1a-T4 高程分层与
##   连续连接；docs/04-tasks-m1.md M1a-T4 + 调研文档「连续高程网格：用顶面、边带、角落拆开」
##   / Catlike §3 结构移植）
## 约定与决策（翻案须先改 04 对应验收，不动架构）：
## - 纯逻辑类：RefCounted、零场景节点（ADR-2）；产出 ArrayMesh + 元数据 Dictionary。
##   场景挂载在 scripts/ui/map_view.gd（view 层）——删 scripts/ui/** 不影响本文件与
##   tests/（02 §3「删 ui 后测试全绿」的可执行表达）。
## - 依赖方向：本文件 → hex_math.gd（T1）+ map_data.gd（T2），只读不反向。
## - 三步纯几何（04 M1a-T4 细化 → M1a T2 阶地扩展，逐格）：
##   ① 顶面：格心 + 六内顶点三角扇（首版平整不扰动；微决策 2：站立/高亮只盖内顶面）；
##   ② 边带：A.inner_d / A.inner_{d+1} 平移 bridge_d 展开——有河 link（T3 WATER-02 ①，
##     传 world 时）整段下切「岸坡→河床→岸坡」剖面（跨河宽 w 占连接带中段、
##     沿边全长连续 s∈[0,1]——修订记录三之 1：~~切向中段 t∈[0.4,0.6]~~ 禁止；
##     kind="riverbed"）；无河走四分类 flat(Δ0)/slope(Δ1)/terrace(Δ∈[2,threshold))/
##     cliff(Δ≥threshold，默认 3)。**不传 profile（或全关）= 现基线单斜面两级三角**
##     （微决策 1 的 80° 陡面保留为回退档）；**传 LandformProfile**（T2 起默认档）：
##     terrace 档 = terrace_lerp 剖面细分环带（LAND-02 ①②，步数-Δ 绑定 = 每爬一级
##     一组）、cliff 档 = 共享崖线 XZ 上同 XZ 墙顶/墙底 + 高低裙边（真垂直墙，
##     修订记录三之 3）；
##   ③ 角落：顶点 k 相邻三格（cell、dir k 邻、dir k−1 邻）补洞——基线路径 = 单三角
##     (inner_k, inner_k+bridge_{k-1}, inner_k+bridge_k)；profile 路径 = 情形分派
##     （三格等高 = 现平三角 / 两低一高 = 阶地扇 / 含 cliff = 坍缩扇——Catlike Part 3
##     corner 结构转译，LAND-02 ④）：以三边带各自的侧边折线拼边界环，对环做 3D 耳切
##     三角化（XZ 退化耳 = 竖直鳍面——双崖角的天然竖直区域），边界点与边带细分环
##     逐位同源（同一全局参数现算 → 焊接流形）；河畔角（三边任一有河，T3）同路径
##     ——侧折线带下切剖面（[岸顶, 床@bank, 床@1−bank, 岸顶]），河床跨角点连续。
## - 归属规则（防重复面；04 M1a-T4 细化）：
##   · 共享边带：两格稳定 ID（MapData.index_of，行主序存储下标）较小者生成；
##   · 共享角落：顶点 k 三格中 ID 最小者生成（三格 ID 即唯一 key）；
##   · chunk 只生成"归属权在本 chunk 内"的几何——归属判断用全局 index_of，chunk 天然
##     可读邻块格子数据（chunk 边界 ≠ 地图边界：跨块边带/角落由归属块生成，本块跳过）；
##   · 接缝顶点从同一全局参数计算：HexMath.inner_vertex / bridge_xz（全局格心现算），
##     每条几何唯一生成路径 → 跨 chunk 顶点逐位一致，不存在两路扰动。
## - 边界规则（T2 口径在几何面的落实）：边带邻居或角落三格任一界外 → 不生成该连接
##   （无悬空面）；地图外沿 = 内六边形锯齿边缘、无侧壁（外沿侧壁属表现层升级，不在本任务）。
## - 逐面 emit（flat shading）：每三角独立 3 顶点 + 显式递增索引，faces 序 = 三角序
##   （为 T5 拾取的 face_index→格映射预留直接对应）。法线 = 面法线现算
##   （顶面恒 +Y；边带/角落 = cross 归一——绕序保证 y 分量 ≥ 0；**真垂直墙/角落竖直
##   鳍面的法线 y = 0**（面竖直），T2 起不再承诺严格 > 0，测试对竖直面改查水平朝向）。
## - 绕序双层口径（2026-10-10 F-1 修复，Fable 审查）：
##   · raw 顶点 soup 保持几何序 cross(B−A,C−A).y > 0（俯视逆时针，全方向旋转对称）：
##     顶面 (格心, inner_k, inner_{k+1})；边带 (v1,v3,v4)+(v1,v4,v2)；角落 (p1,p3,p2)
##     ——碰撞汤翻转（hex_picking.chunk_collision_faces 直读 raw 顶点）与 faces 元数据
##     （face_index 映射）都锚定 raw 序，**不变**；
##   · 渲染**索引**逐三角翻转为 (base, base+2, base+1)：索引三角 = 俯视**顺时针**
##     = Godot 正面（引擎口径：front face = clockwise winding）——默认 CULL_BACK 下
##     俯视可见。法线/UV 仍随 raw 顶点走（描述面朝向与纹理，与剔除面无关）。
## - 法线硬边策略（M1a-T8 显式定死）：**全 flat shading、全硬边**——每三角独立 3 顶点 +
##   面法线，不焊接顶点、不做任何平滑（平顶/陡壁的硬边是低模策略地形的目标可读性；
##   平滑法线=顶点焊接+按面分类平滑组，属表现层后续升级，翻案须回改 04 与测试锚）。
## - UV 约定（M1a-T8 定死——「换贴图不改主线」的接口前提，否则美术无从对表；
##   细则与取舍全文见 docs/notes/m1a-t8-art-branch.md，翻案须同步改
##   tests/test_hex_terrain_materials.gd 的 UV 锚）：
##   · 尺寸：1 纹理重复 [0,1]² = 2R×2R 世界方形（R = size 外接圆半径）；
##     整体缩放属材质参数（uv1_scale），不动 mesh；
##   · 水平面（顶面 / 平连边带 / 等高角落）：世界平面映射 u = x/2R、v = −z/2R
##     ——平地整图无缝连续平铺（换贴图即所见的基础）；
##   · 侧面（|Δh|≥1 边带，斜坡/陡面/短坡/崖壁）：u = XZ 沿边切向投影/2R（HexMath.
##     edge_tangent_world，每方向 u 轴随边向）、v = −y/2R——竖向纹理随高程走
##     （Δ1 半纹、Δ2 恰一整纹；对真竖直墙纵横比正确）。T2 阶地面选型（LAND-02 ⑦）：
##     平台（tread/崖壁裙边）走 _uv_planar、短坡与竖直墙走 _uv_side_edge——约定
##     公式不改，只多两档逐面选型；
##   · 非等高角落（补洞小三角）：u = x/2R（平面 u）、v = −y/2R——u 与两侧边带
##     轴不连续、相邻方向边带 u 轴相差 60°：登记为已接受代价（选无缝平铺贴图
##     时不显眼；边界混色/Texture2DArray/三平面映射属后续升级，04 M1a-T8 明示不做）。
## - 材质槽 = 地形类型 → 材质映射表（M1a-T8 资源化）：调用方传 {terrain_id: Material}
##   平面表（.tres 载体 = TerrainMaterialLibrary，scripts/core/data/；主线默认表 =
##   resources/terrain/terrain_materials_default.tres 色块起步）；边带/角落归属生成者
##   的地形 surface。不用顶点色 → 材质不开 vertex_color_use_as_albedo（04 M1a-T3 细化）。
##   表缺图内地形 id / 表值非 Material / elevation_step ≤0 / solid_factor ∉ (0,1)
##   → 显式失败（null）。
## - 色板权重混合 style（M1a+ BLEND-01 边带两格权重 / BLEND-02 角落三格权重，
##   2026-10-10；04 §M1a+ 表现层短切片——与上面材质槽 style 并存，后者保留为
##   fallback）：build_map_blend / build_chunk_blend 以 palette = {terrain_id: Color}
##   驱动，把过渡权重写进 mesh 顶点 COLOR——边带端点 = 端点所在格纯色（owner 侧
##   (1,0)、邻侧 (0,1)）、带内 = GPU 线性插值（中点 0.5/0.5 由权重合同锚定，见
##   hex_terrain_blend.gd）；顶面全顶点 = 本格纯色（中心主地形纯度）；角落顶点 =
##   三格权重合同（corner_weights）的单位权重锚点——p1=归属格 (1,0,0)、p2=N(k) 侧
##   (0,1,0)、p3=N(k−1) 侧 (0,0,1)，面内三色过渡 = 线性插值（重心 = (1/3,1/3,1/3)
##   权重混合，和恒 1；跨 chunk 角面锚点仍从同一全局参数计算——权重/颜色不随
##   chunk 划分改变，锚见 tests/test_hex_terrain_blend_corner.gd）。
##   **几何/UV/法线/索引/faces 元数据与
##   fallback 逐位一致**（同一 _build_surface 路径，只多 COLOR 通道——face 表/碰撞
##   合同零改动，测试锚定）；surface 仍按地形分组，材质统一用调用方传入的
##   blend_material（顶点色 albedo 导管，官方工厂 = HexTerrainBlend.make_blend_material）。
##   权重/色板是独立渲染数据，不进规则/逻辑层（提案「材质升级的最小安全路径」）。
##   **T2 阶地扩展（LAND-02 ⑤，§8.1 blend 合同扩档）**：几何级细分顶点（阶地环/
##   崖壁/角扇）合法——「mesh 侧不设中点顶点」限定回**材质级表现切片**（端点纯色 +
##   GPU 插值的中点等价论证仍以平边带为限）；几何细分下每个新顶点 COLOR 由同一
##   edge_weights(t) / corner_weights(u,v) 显式求值（有限、非负、和 1 逐点保持），
##   锚见 tests/test_landform_terraces.gd。
## - 元数据：{"chunk": Rect2i, "mesh": ArrayMesh, "surfaces": [{"terrain": int,
##   "cells": Array[Vector2i]（该地形格，chunk 行主序）, "faces": Array[Dictionary]
##   （与 mesh 三角一一对应：kind="top"|"edge"|"corner"|"riverbed"（T3 有河下切
##   边带，WATER-02）、cell=归属格、dir=顶面扇区 k/边带方向 d/角落顶点 k、
##   edge/corner 外 edge 面另带 edge_type ∈ flat/slope/terrace/cliff（陡面
##   quad）/cliff_wall（真垂直墙带，T2 起））, "face_counts": {top,edge,corner,
##   riverbed}, "vertex_count": 3×面数, "index_count": 3×面数}]}（blend style 同
##   schema——blend 下 "terrain" 只是分组键，渲染材质统一为 blend_material，见上条）。
class_name HexTerrainBuilder
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const LandformProfileClass := preload("res://scripts/core/data/landform_profile.gd")
const BlendLib := preload("res://addons/hexhammer/hex_terrain_blend.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
# 仅为跨河几何常量 RIVER_BANK_FRACTION（水面/河床共用唯一计算点）；水面第二 mesh
# 属 WaterGeometryBuilder（独立类，本文件不 preload 其类型之外的依赖）
const WaterGeom := preload("res://addons/hexhammer/water_geometry_builder.gd")

## 默认内六边形缩进（Catlike 同款 0.8：连接带宽 = (1−solid)·√3·size ≈ 0.35·size）
const DEFAULT_SOLID_FACTOR := 0.8
## 默认每层高程的世界高度（相对 size=1 的格：一层 ≈ 内切圆半径 0.87 的 1.15 倍）
const DEFAULT_ELEVATION_STEP := 1.0
## 默认 cliff 分档阈值（LAND-01 ①：cliff = Δ≥3 走真垂直崖、阶地档 = Δ2；阈值属
## 构建参数/几何 profile，不进 MapData——§2.5「高差分档阈值不进 MapData」）
const DEFAULT_CLIFF_THRESHOLD := 3

## 边带分类（LAND-01 ① 四分类；拾取归属复用同分类——cliff 档归高地侧）
const EDGE_FLAT := "flat"      # 等高平连（|Δh| = 0）
const EDGE_SLOPE := "slope"    # 差一级斜坡（|Δh| = 1，单斜面——阶地不涉此档）
const EDGE_TERRACE := "terrace"  # 阶地档（|Δh| ∈ [2, cliff_threshold)，terrace_lerp 剖面）
const EDGE_CLIFF := "cliff"    # 崖档（|Δh| ≥ cliff_threshold）
## 崖档面级标签：真垂直墙几何（cliff_vertical 开）的边带面用本值；陡面 quad 回退档
## 仍用 EDGE_CLIFF——面级 edge_type 描述几何而非分类（LAND-03 ① 细化）
const EDGE_CLIFF_WALL := "cliff_wall"
## 河床面 kind（T3 WATER-02 ①③：有河 link 的边带整段下切成「岸坡→河床→岸坡」
## 剖面，全部面 kind="riverbed"——拾取候选 = 两侧两格最近格心 + ID 决胜
## （hex_picking.gd）；跨河几何参数 w = 1 − 2×WaterGeom.RIVER_BANK_FRACTION）
const FACE_RIVERBED := "riverbed"

# ---------------- chunk 划分 ----------------

## 行主序产出覆盖全图的 chunk 矩形（右/下越界裁剪，无重叠无遗漏）。
## 图尺寸或 chunk 尺寸 ≤0 → 空数组（调用方据此显式失败，不静默出半张图）。
static func chunk_rects_for(map_width: int, map_height: int, chunk_cols: int, chunk_rows: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	if map_width <= 0 or map_height <= 0 or chunk_cols <= 0 or chunk_rows <= 0:
		return out
	var col0 := 0
	while col0 < map_width:
		var row0 := 0
		while row0 < map_height:
			out.append(Rect2i(
				col0, row0,
				mini(chunk_cols, map_width - col0),
				mini(chunk_rows, map_height - row0),
			))
			row0 += chunk_rows
		col0 += chunk_cols
	return out


## chunk 矩形内的格子（行主序；矩形与图求交）。注意：几何生成读全图数据（邻块可读），
## 本函数只圈定"归属权候选格"——跨界边带/角落是否归本块由全局稳定 ID 判定。
static func chunk_cells(map: MapDataClass, chunk: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in range(chunk.position.y, chunk.position.y + chunk.size.y):
		if row < 0 or row >= map.height:
			continue
		for col in range(chunk.position.x, chunk.position.x + chunk.size.x):
			if col < 0 or col >= map.width:
				continue
			out.append(Hex.axial_of(Vector2i(col, row)))
	return out

# ---------------- 边带分类 ----------------

## 高差 → 连接类型（LAND-01 ① 四分类：|Δh|=0 Flat、=1 Slope、[2,threshold) Terrace、
## ≥threshold Cliff，默认 threshold=3——修订记录一：cliff = Δ≥threshold（非 >））。
## 阈值参数化：profile 调档（如 4）时矩阵/拾取/几何同档扩（LAND-01 ②「上界恒
## ≥ cliff_threshold」；hex_picking 同函数泛化——拾取归属随分类切换）。
static func classify_edge(delta_elevation: int,
		cliff_threshold := DEFAULT_CLIFF_THRESHOLD) -> String:
	var d := absi(delta_elevation)
	if d == 0:
		return EDGE_FLAT
	if d == 1:
		return EDGE_SLOPE
	if d < cliff_threshold:
		return EDGE_TERRACE
	return EDGE_CLIFF

# ---------------- 阶地剖面（Catlike Part 3 TerraceLerp 移植，LAND-02 ①）----------------

## 一组 steps 步内的竖直归一化剖面：j=0..steps → 0, v_step·{0,1,1,2,2,…}（int 除法
## (j+1)/2 向零取整 = 竖直仅奇数步动）；v_step = 1/ceil(steps/2)
## （= Catlike verticalTerraceStepSize = 1/(terracesPerSlope+1)——5 步时 1/3、
## 3 步时 1/2，两档均为对称阶地；修订记录三之 3 修正项）。
## 5 步序列：0, 1/3, 1/3, 2/3, 2/3, 1（2 平台 + 3 短坡）；3 步：0, 1/2, 1/2, 1。
static func terrace_vfrac(step: int, steps: int) -> float:
	var v_step := 1.0 / ceilf(float(steps) / 2.0)
	return float((step + 1) / 2) * v_step


## TerraceLerp（LAND-02 ① 原式）：水平 a.lerp(b, step/steps) 均分 + 竖直按
## terrace_vfrac 剖面——端点 step=0/steps 恰为 a/b（同高程端点不移位的公式保证）。
static func terrace_lerp(a: Vector3, b: Vector3, step: int, steps: int) -> Vector3:
	var out := a.lerp(b, float(step) / float(steps))
	out.y = lerpf(a.y, b.y, terrace_vfrac(step, steps))
	return out

# ---------------- 构建入口 ----------------

## 整图分块构建。materials = 地形 id → Material 映射表（TerrainMaterialLibrary.materials
##   的 .tres 载体见 scripts/core/data/terrain_material_library.gd；测试/工具可自建表）。
##   profile = LandformProfile（T2 几何档，可空）：null / 全关 = 现基线几何（退回档）；
##   非法档（steps<2 / threshold<2）→ null。world = WorldData（T3 水系，可空）：
##   非 null 时有河 link 的边带按下切剖面发射（kind="riverbed"）；world 数据自身
##   合法性由 WorldData.validate 把关（本 builder 信任已验世界）。
##   返回 {"chunks": Array[chunk 字典],
##   "chunk_rects": Array[Rect2i],
##   "materials": {被用到的 terrain id → 表内共享材质实例}（echo 输入表，不合成新材质）,
##   "size": float, "elevation_step": float, "solid_factor": float, "profile": profile（echo）,
##   "world": world（echo，null 或引用）}；
## 任一地形 id 缺表 / 表值非 Material / 参数非法 → null（先全图预检后建，不做一半丢弃）。
static func build_map(map: MapDataClass, chunk_cols := 10, chunk_rows := 10,
		materials: Dictionary = {}, size := 1.0,
		elevation_step := DEFAULT_ELEVATION_STEP,
		solid_factor := DEFAULT_SOLID_FACTOR,
		profile: LandformProfileClass = null,
		world: WorldDataClass = null) -> Variant:
	if elevation_step <= 0.0 or solid_factor <= 0.0 or solid_factor >= 1.0 or size <= 0.0:
		return null
	if profile != null and not profile.is_valid():
		return null
	# chunk 参数显式拒绝（2026-10-10 接口硬化）：此前 chunk_rects_for 对 ≤0 返回
	# 空数组，本函数照走循环产出 chunks=0 的 Dictionary——「空成功」会被调用层
	# 当构建成功（T1~T4 复核反例：build_map(map, 0, 10)）。空图是否可构建属
	# view 层契约另议，不在本条范围。
	if chunk_cols <= 0 or chunk_rows <= 0:
		return null
	if not _material_table_valid(map, materials):
		return null
	var used := {}
	for cell in map.cells():
		used[map.terrain_at(cell)] = true
	var shared := {}
	for tid in used:
		shared[tid] = materials[tid]
	var chunks: Array = []
	var rects := chunk_rects_for(map.width, map.height, chunk_cols, chunk_rows)
	for rect in rects:
		var built: Variant = build_chunk(map, rect, shared, size, elevation_step, solid_factor, profile, world)
		if built == null:
			return null
		chunks.append(built)
	return {
		"chunks": chunks,
		"chunk_rects": rects,
		"materials": shared,
		"size": size,
		"elevation_step": elevation_step,
		"solid_factor": solid_factor,
		"profile": profile,
		"world": world,
	}


## 单 chunk 构建。materials 须含 chunk 内全部地形 id（build_map 已过滤共享表；直调自备，
## 缺 id / 表值非 Material / 空矩形（无格）/ 参数非法 / profile 非法 → null）。
static func build_chunk(map: MapDataClass, chunk: Rect2i, materials: Dictionary,
		size := 1.0, elevation_step := DEFAULT_ELEVATION_STEP,
		solid_factor := DEFAULT_SOLID_FACTOR,
		profile: LandformProfileClass = null,
		world: WorldDataClass = null) -> Variant:
	if elevation_step <= 0.0 or solid_factor <= 0.0 or solid_factor >= 1.0 or size <= 0.0:
		return null
	if profile != null and not profile.is_valid():
		return null
	var cells := chunk_cells(map, chunk)
	if cells.is_empty():
		return null
	# 有河边索引一次成形（world 可空 = 无河，恒走常规边带）
	var river_idx := world.river_edge_index() if world != null else {}
	# 按地形分组（组内保持 chunk 行主序；surface 序 = 类型首次出现序——T3 口径沿用）
	var groups := {}
	var order: Array[int] = []
	for cell in cells:
		var tid := map.terrain_at(cell)
		if tid == MapDataClass.TERRAIN_NONE or not (materials.has(tid) and materials[tid] is Material):
			return null
		if not groups.has(tid):
			groups[tid] = [] as Array[Vector2i]
			order.append(tid)
		(groups[tid] as Array[Vector2i]).append(cell)
	var mesh := ArrayMesh.new()
	var surfaces: Array = []
	for tid in order:
		surfaces.append(_build_surface(map, tid, groups[tid], materials[tid], size,
			elevation_step, solid_factor, mesh, {}, profile, river_idx))
	return {"chunk": chunk, "mesh": mesh, "surfaces": surfaces}


# ---------------- 色板权重混合构建（M1a+ BLEND-01）----------------

## 整图分块构建（blend style）。palette = 地形 id → Color（建议来源 =
## HexTerrainBlend.palette_from_materials(TerrainMaterialLibrary.materials)——与
## fallback 共用同一 .tres，换表即两风格同时换观感）；blend_material = 顶点色 albedo
## 导管（官方工厂 HexTerrainBlend.make_blend_material；builder 只认 Material，
## 顶点色语义由调用方保证）。
## 返回 {"chunks": Array[chunk 字典]（schema 同 build_map，材质统一 blend_material）,
##   "chunk_rects": Array[Rect2i], "palette": {被用到的 terrain id → Color}（echo 输入
##   色板，不合成新色）, "blend_material": Material（echo）, "style": "blend",
##   "size"/"elevation_step"/"solid_factor": float}；
## 色板缺图内地形 id / 色值非 Color / 通道非有限或负 / blend_material 非 Material /
## 参数非法 → null（先全图预检后建，不做一半丢弃——与 build_map 同纪律）。
static func build_map_blend(map: MapDataClass, palette: Dictionary, chunk_cols := 10,
		chunk_rows := 10, blend_material: Material = null, size := 1.0,
		elevation_step := DEFAULT_ELEVATION_STEP,
		solid_factor := DEFAULT_SOLID_FACTOR,
		profile: LandformProfileClass = null,
		world: WorldDataClass = null) -> Variant:
	if elevation_step <= 0.0 or solid_factor <= 0.0 or solid_factor >= 1.0 or size <= 0.0:
		return null
	if chunk_cols <= 0 or chunk_rows <= 0:
		return null
	if not (blend_material is Material):
		return null
	if profile != null and not profile.is_valid():
		return null
	if not _palette_table_valid(map, palette):
		return null
	var used := {}
	for cell in map.cells():
		used[map.terrain_at(cell)] = true
	var echo := {}
	for tid in used:
		echo[tid] = palette[tid]
	var chunks: Array = []
	var rects := chunk_rects_for(map.width, map.height, chunk_cols, chunk_rows)
	for rect in rects:
		var built: Variant = build_chunk_blend(map, rect, palette, blend_material, size,
			elevation_step, solid_factor, profile, world)
		if built == null:
			return null
		chunks.append(built)
	return {
		"chunks": chunks,
		"chunk_rects": rects,
		"palette": echo,
		"blend_material": blend_material,
		"style": "blend",
		"size": size,
		"elevation_step": elevation_step,
		"solid_factor": solid_factor,
		"profile": profile,
		"world": world,
	}


## 单 chunk 构建（blend style）。palette 须含图内全部地形 id（全图预检——邻块格
## 数据可读，色板覆盖与 chunk 边界无关）；blend_material 非 Material / 空矩形（无格）/
## 参数非法 / profile 非法 → null。几何/UV/索引/faces 与 build_chunk 逐位一致，仅多顶点 COLOR。
static func build_chunk_blend(map: MapDataClass, chunk: Rect2i, palette: Dictionary,
		blend_material: Material, size := 1.0, elevation_step := DEFAULT_ELEVATION_STEP,
		solid_factor := DEFAULT_SOLID_FACTOR,
		profile: LandformProfileClass = null,
		world: WorldDataClass = null) -> Variant:
	if elevation_step <= 0.0 or solid_factor <= 0.0 or solid_factor >= 1.0 or size <= 0.0:
		return null
	if not (blend_material is Material):
		return null
	if profile != null and not profile.is_valid():
		return null
	if not _palette_table_valid(map, palette):
		return null
	var cells := chunk_cells(map, chunk)
	if cells.is_empty():
		return null
	var river_idx := world.river_edge_index() if world != null else {}
	# 按地形分组（与 build_chunk 同口径：组内 chunk 行主序、surface 序 = 首现序——
	# 保证 blend 与 fallback 的 faces 序逐位一致，face 表合同不随 style 改变）
	var groups := {}
	var order: Array[int] = []
	for cell in cells:
		var tid := map.terrain_at(cell)
		if not groups.has(tid):
			groups[tid] = [] as Array[Vector2i]
			order.append(tid)
		(groups[tid] as Array[Vector2i]).append(cell)
	var mesh := ArrayMesh.new()
	var surfaces: Array = []
	for tid in order:
		surfaces.append(_build_surface(map, tid, groups[tid], blend_material, size,
			elevation_step, solid_factor, mesh, palette, profile, river_idx))
	return {"chunk": chunk, "mesh": mesh, "surfaces": surfaces}


# ---------------- 单 surface（一种地形类型的全部归属几何） ----------------

## chunk 内同地形格的顶面 + 归属边带 + 归属角落，逐面 emit 到共享 mesh 的新 surface。
## palette 非空 = blend style（M1a+ BLEND-01）：逐面附顶点 COLOR（端点=所在格纯色，
## 权重合同见 hex_terrain_blend.gd）；material 此时 = 共享 blend_material。
## palette 为空 = fallback 材质槽路线（原行为零改动——不设 COLOR 通道）。
## profile（T2 几何档，LAND-02）：null / terrace 与 cliff_vertical 全关 = 现基线
## 单斜面 + 单三角角落（回退档，逐位一致由 tests/test_landform_terraces.gd 锚）；
## 任一开 = 阶地环带 / 真垂直崖壁 / 角落情形分派（发射公式见各 _emit_* 注）。
## river_idx（T3 WATER-02 ①，可空 dict）：有河 link → 边带整段下切剖面
## （kind="riverbed"，_emit_river_band）；河畔角走角扇分派（侧折线带下切剖面——
## 多条连续边在共享角点接缝，修订记录三之 1）。
static func _build_surface(map: MapDataClass, terrain_id: int, group: Array[Vector2i],
		material: Material, size: float, elevation_step: float, solid_factor: float,
		mesh: ArrayMesh, palette: Dictionary = {},
		profile: LandformProfileClass = null, river_idx: Dictionary = {}) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	var blend := not palette.is_empty()
	var c_owner := Color.BLACK  # blend 下 = 本地形纯色（palette 已全图预检，查不落空）
	if blend:
		c_owner = palette[terrain_id]
	# 几何档派生开关：全关 = 基线路径（零改动分支），任一开 = T2 路径
	var terrace_on := profile != null and profile.terrace_enabled
	var wall_on := profile != null and profile.cliff_vertical
	var threshold: int = profile.cliff_threshold if profile != null else DEFAULT_CLIFF_THRESHOLD
	var faces: Array[Dictionary] = []
	var top_count := 0
	var edge_count := 0
	var corner_count := 0
	var riverbed_count := 0
	var vi := 0  # surface 内顶点游标（faces 序 = 三角序 = 顶点序）
	for cell in group:
		var id := map.index_of(cell)
		var h := _y_of(map, cell, elevation_step)
		var center := Hex.axial_to_world(cell, size)
		center.y = h
		# ① 顶面：格心 + 六内顶点三角扇（每格恒 6 面；首版平整不扰动；水平面 → 平面 UV）
		#   blend：全顶点 = 本格纯色（中心主地形纯度——格心不参与混合）
		for k in 6:
			var a := center
			var b := Hex.inner_vertex(cell, k, size, solid_factor, h)
			var c := Hex.inner_vertex(cell, (k + 1) % 6, size, solid_factor, h)
			vi = _emit_face(st, vi, a, b, c, Vector3.UP,
				_uv_planar(a, size), _uv_planar(b, size), _uv_planar(c, size),
				_cols(c_owner, c_owner, c_owner) if blend else null)
			faces.append({"kind": "top", "cell": cell, "dir": k})
			top_count += 1
		# ② 边带：共享边由两格稳定 ID 较小者生成（界外邻格 → 不生成，无悬空连接）。
		#   分档派发（LAND-01 ①/LAND-02 ②③ + WATER-02 ①）：有河 link → 下切剖面
		#   （river_idx 优先于一切分类——河的几何合同独立于高差档）；无河再走
		#   flat/slope = 基线 quad（两档不受 profile 影响，逐位回基线）；terrace 档
		#   （profile 开）= 阶地环带；cliff 档 = 真垂直崖壁（cliff_vertical 开）或
		#   基线陡面 quad（关）。
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not map.has_cell(nb):
				continue
			var nb_id := map.index_of(nb)
			if nb_id < id:
				continue
			var lid := WorldDataClass.link_id_of(id, nb_id)
			var etype := classify_edge(map.elevation_at(cell) - map.elevation_at(nb), threshold)
			var hnb := _y_of(map, nb, elevation_step)
			var br := Hex.bridge_xz(cell, d, size, solid_factor)
			var v1 := Hex.inner_vertex(cell, d, size, solid_factor, h)
			var v2 := Hex.inner_vertex(cell, (d + 1) % 6, size, solid_factor, h)
			var v3 := v1 + Vector3(br.x, 0.0, br.y)
			var v4 := v2 + Vector3(br.x, 0.0, br.y)
			v3.y = hnb
			v4.y = hnb
			var c_nb := Color.BLACK  # blend 下 = 邻格纯色
			if blend:
				c_nb = palette[map.terrain_at(nb)]
			var faces_before := faces.size()
			if river_idx.has(lid):
				vi = _emit_river_band(st, vi, faces, v1, v2, v3, v4,
					float(map.elevation_at(cell)) * elevation_step,
					float(map.elevation_at(nb)) * elevation_step,
					int(river_idx[lid]["bed"]) * elevation_step,
					Hex.edge_tangent_world(d), size,
					c_owner, c_nb, blend,
					{"kind": FACE_RIVERBED, "cell": cell, "dir": d})
			elif terrace_on and etype == EDGE_TERRACE:
				vi = _emit_terrace_band(st, vi, faces, v1, v2, v3, v4,
					map.elevation_at(cell), map.elevation_at(nb), elevation_step,
					profile.terrace_steps, Hex.edge_tangent_world(d), size,
					c_owner, c_nb, blend,
					{"kind": "edge", "cell": cell, "dir": d, "edge_type": EDGE_TERRACE})
			elif wall_on and etype == EDGE_CLIFF:
				vi = _emit_cliff_wall(st, vi, faces, v1, v2, v3, v4, size,
					Hex.edge_tangent_world(d),
					c_owner, c_nb, blend,
					{"kind": "edge", "cell": cell, "dir": d, "edge_type": EDGE_CLIFF_WALL})
			else:
				# 基线 quad（含 flat/slope、回退档全部分类）——UV 随分类：平连 = 水平面
				#（与顶面同一世界平面映射）；斜坡/阶地/陡面 = 侧面（u 沿边切向、v 跟高程）
				var n1 := _face_normal(v1, v3, v4)
				var n2 := _face_normal(v1, v4, v2)
				if etype == EDGE_FLAT:
					vi = _emit_face(st, vi, v1, v3, v4, n1,
						_uv_planar(v1, size), _uv_planar(v3, size), _uv_planar(v4, size),
						_cols(c_owner, c_nb, c_nb) if blend else null)
					vi = _emit_face(st, vi, v1, v4, v2, n2,
						_uv_planar(v1, size), _uv_planar(v4, size), _uv_planar(v2, size),
						_cols(c_owner, c_nb, c_owner) if blend else null)
				else:
					var tangent := Hex.edge_tangent_world(d)
					vi = _emit_face(st, vi, v1, v3, v4, n1,
						_uv_side_edge(v1, tangent, size), _uv_side_edge(v3, tangent, size),
						_uv_side_edge(v4, tangent, size),
						_cols(c_owner, c_nb, c_nb) if blend else null)
					vi = _emit_face(st, vi, v1, v4, v2, n2,
						_uv_side_edge(v1, tangent, size), _uv_side_edge(v4, tangent, size),
						_uv_side_edge(v2, tangent, size),
						_cols(c_owner, c_nb, c_owner) if blend else null)
				faces.append({"kind": "edge", "cell": cell, "dir": d, "edge_type": etype})
				faces.append({"kind": "edge", "cell": cell, "dir": d, "edge_type": etype})
			if river_idx.has(lid):
				# 有河边带面 kind="riverbed"（非 "edge"）——计数键与 faces kind 一致：
				# edge 只数常规边带、riverbed 数下切剖面（T3 起扩键）
				riverbed_count += faces.size() - faces_before
			else:
				edge_count += faces.size() - faces_before
		# ③ 角落：顶点 k 三格 ID 最小者生成补洞（三格任一界外 → 不生成）。
		#   河畔角（三边任一有河）= 角扇分派（侧折线带下切剖面——跨角点接缝，
		#   WATER-02 ①）；否则 profile 关（回退档）= 基线单三角；profile 开 = 情形分派。
		for k in 6:
			var nb_k := Hex.neighbor(cell, k)
			var nb_k1 := Hex.neighbor(cell, k - 1)  # 方向 k−1（neighbor 内部 wrapi）
			if not map.has_cell(nb_k) or not map.has_cell(nb_k1):
				continue
			if map.index_of(nb_k) < id or map.index_of(nb_k1) < id:
				continue
			var br_k := Hex.bridge_xz(cell, k, size, solid_factor)
			var br_k1 := Hex.bridge_xz(cell, k - 1, size, solid_factor)
			var p1 := Hex.inner_vertex(cell, k, size, solid_factor, h)
			var p2 := p1 + Vector3(br_k.x, 0.0, br_k.y)   # dir k 邻格侧端点
			var p3 := p1 + Vector3(br_k1.x, 0.0, br_k1.y)  # dir k−1 邻格侧端点
			p2.y = _y_of(map, nb_k, elevation_step)
			p3.y = _y_of(map, nb_k1, elevation_step)
			var c_nbk := Color.BLACK  # blend 下 = N(k) 侧 / N(k−1) 侧端点纯色
			var c_nbk1 := Color.BLACK
			if blend:
				c_nbk = palette[map.terrain_at(nb_k)]
				c_nbk1 = palette[map.terrain_at(nb_k1)]
			var faces_before := faces.size()
			var river_corner := river_idx.has(WorldDataClass.link_id_of(id, map.index_of(nb_k))) \
				or river_idx.has(WorldDataClass.link_id_of(id, map.index_of(nb_k1))) \
				or river_idx.has(WorldDataClass.link_id_of(map.index_of(nb_k), map.index_of(nb_k1)))
			if terrace_on or wall_on or river_corner:
				vi = _emit_corner_fill(st, vi, faces, p1, p2, p3,
					map.elevation_at(cell), map.elevation_at(nb_k), map.elevation_at(nb_k1),
					elevation_step, size, terrace_on, wall_on, threshold,
					profile.terrace_steps if terrace_on else 0,
					map, cell, nb_k, nb_k1,
					c_owner, c_nbk, c_nbk1, blend, {"kind": "corner", "cell": cell, "dir": k},
					river_idx)
			else:
				# 基线角落（回退档）：三格等高 = 平面 UV；否则 = 侧面（u 平面、v 跟高程）
				var n := _face_normal(p1, p3, p2)
				if map.elevation_at(cell) == map.elevation_at(nb_k) and map.elevation_at(cell) == map.elevation_at(nb_k1):
					vi = _emit_face(st, vi, p1, p3, p2, n,
						_uv_planar(p1, size), _uv_planar(p3, size), _uv_planar(p2, size),
						_cols(c_owner, c_nbk1, c_nbk) if blend else null)
				else:
					vi = _emit_face(st, vi, p1, p3, p2, n,
						_uv_side_corner(p1, size), _uv_side_corner(p3, size), _uv_side_corner(p2, size),
						_cols(c_owner, c_nbk1, c_nbk) if blend else null)
				faces.append({"kind": "corner", "cell": cell, "dir": k})
			corner_count += faces.size() - faces_before
	st.commit(mesh)
	return {
		"terrain": terrain_id,
		"cells": group,
		"faces": faces,
		"face_counts": {"top": top_count, "edge": edge_count, "corner": corner_count,
			"riverbed": riverbed_count},
		"vertex_count": faces.size() * 3,
		"index_count": faces.size() * 3,
	}

# ---------------- 阶地 / 真垂直崖 / 角落分派发射（T2 几何档；LAND-02）----------------

## 阶地环带竖直剖面（LAND-02 ① 步数-Δ 绑定的唯一计算点——边带与角扇共用，保证
## 焊接流形）：环 S（S=0..n·steps，n = |Δelevation|），组序 g = S/steps、组内步
## j = S%steps；竖直归一化 = (g + terrace_vfrac(j, steps)) / n。
## 组边界环（S = k·steps）竖直 = k/n → y 恰落在高程整数层（平台对齐整数层的机器表达）；
## 端点 S=0 / S=total = 两端原高程（同高程端点不移位）。
static func terrace_ring_vfrac(s: int, n: int, steps: int) -> float:
	var g := s / steps
	var j := s % steps
	return (float(g) + terrace_vfrac(j, steps)) / float(n)


## 阶地环带发射（LAND-02 ②）：v1..v3（= v1+bridge）之间按步插值成中间环（每环两点：
## _lerp_xz(v1, v3, t) 水平 + 阶地剖面竖直），相邻环 = 四边形两级三角（沿基线
## :363-378 发射模式扩）。UV 逐四边形选型（LAND-02 ⑦）：tread（环对等高）= 平面、
## riser = 侧面。blend：每环顶点 COLOR = edge_weights(t) 显式求值（LAND-02 ⑤——
## 权重合同不变、求值点变多；t=0/1 端点 = (1,0)/(0,1) 纯色，与基线端点规则逐位一致）。
## 环点与 _band_side_polyline 同一表达式（角扇边界 = 边带侧边折线，焊接流形的
## 参数面保证）。
static func _emit_terrace_band(st: SurfaceTool, vi: int, out_faces: Array[Dictionary],
		v1: Vector3, v2: Vector3, v3: Vector3, v4: Vector3,
		ea: int, eb: int, elevation_step: float,
		steps: int, tangent: Vector3, size: float,
		c_owner: Color, c_nb: Color, blend: bool, face_meta: Dictionary) -> int:
	var n := absi(ea - eb)
	var total := n * steps
	# 竖直沿 **owner→nb 方向**插值（ea→eb）：vf 升 0→1 对应 owner 高程→nb 高程——
	# owner 为高侧时剖面 descending（lo→hi 单向插值会把剖面镜像，端点错挂）
	var y0 := float(ea) * elevation_step
	var y1 := float(eb) * elevation_step
	var r1s: Array[Vector3] = []
	var r2s: Array[Vector3] = []
	for s in total + 1:
		var t := float(s) / float(total)
		var y := lerpf(y0, y1, terrace_ring_vfrac(s, n, steps))
		var r1 := _lerp_xz(v1, v3, t)
		r1.y = y
		var r2 := _lerp_xz(v2, v4, t)
		r2.y = y
		r1s.append(r1)
		r2s.append(r2)
	for s in total:
		var a1: Vector3 = r1s[s]
		var a2: Vector3 = r2s[s]
		var b1: Vector3 = r1s[s + 1]
		var b2: Vector3 = r2s[s + 1]
		var tread := absf(b1.y - a1.y) <= 1e-9  # 环对等高 = 平台（组内平台/组边界）
		var n1 := _face_normal(a1, b1, b2)
		var n2 := _face_normal(a1, b2, a2)
		# blend 色（LAND-02 ⑤）：每顶点 COLOR = edge_weights(t) 在**该顶点所在环的
		# 参数**处显式求值——面 0 (a1,b1,b2) = t_s/t_{s+1}/t_{s+1}、面 1 (a1,b2,a2) =
		# t_s/t_{s+1}/t_s（a2 与 a1 同在环 s 侧线：同物理点跨相邻面同色，无色缝；
		# t=0/1 端 = owner/nb 纯色 (1,0)/(0,1)，与基线端点规则逐位一致）
		var cols0: Variant = null
		var cols1: Variant = null
		if blend:
			var ca := _edge_color(c_owner, c_nb, float(s) / float(total))
			var cb := _edge_color(c_owner, c_nb, float(s + 1) / float(total))
			cols0 = _cols(ca, cb, cb)
			cols1 = _cols(ca, cb, ca)
		if tread:
			vi = _emit_face(st, vi, a1, b1, b2, n1,
				_uv_planar(a1, size), _uv_planar(b1, size), _uv_planar(b2, size),
				cols0)
			vi = _emit_face(st, vi, a1, b2, a2, n2,
				_uv_planar(a1, size), _uv_planar(b2, size), _uv_planar(a2, size),
				cols1)
		else:
			vi = _emit_face(st, vi, a1, b1, b2, n1,
				_uv_side_edge(a1, tangent, size), _uv_side_edge(b1, tangent, size),
				_uv_side_edge(b2, tangent, size),
				cols0)
			vi = _emit_face(st, vi, a1, b2, a2, n2,
				_uv_side_edge(a1, tangent, size), _uv_side_edge(b2, tangent, size),
				_uv_side_edge(a2, tangent, size),
				cols1)
		out_faces.append(face_meta.duplicate())
		out_faces.append(face_meta.duplicate())
	return vi


## edge_weights(t) → 颜色（同一权重函数显式求值，hex_terrain_blend.gd 合同；
## 不内联 (1−t) 重推——「由同一函数显式求值」的字面要求）。
static func _edge_color(c_owner: Color, c_nb: Color, t: float) -> Color:
	var w := BlendLib.edge_weights(t)
	return c_owner * w.x + c_nb * w.y


## 真垂直崖壁发射（LAND-02 ③，修订记录三之 3：cliff 边带 v1/v2 与 v3/v4 的 XZ 相差
## 一个 bridge，四点直连 = 现 80° 陡面非竖直墙 → 先选共享崖线 XZ（带中点，t=0.5），
## 再立同 XZ 的墙顶/墙底顶点）：高侧裙边（h_hi 平面）+ 竖直墙（墙顶/墙底同 XZ）+
## 低侧裙边（h_lo 平面），各 2 三角。墙顶/墙底 XZ 逐位一致（同 m1/m2 派生）——
## 「真垂直断言」的机器表达（tests/test_landform_terraces.gd 锚）。
## blend：裙边外缘 = 所在格纯色（t=0/1）、墙顶/墙底/裙边内缘 = edge_weights(0.5) 混合。
## UV：裙边 = 平面、墙 = 侧面（u 沿边切向、v 跟高程——竖直墙纵横比正确）。
static func _emit_cliff_wall(st: SurfaceTool, vi: int, out_faces: Array[Dictionary],
		v1: Vector3, v2: Vector3, v3: Vector3, v4: Vector3, size: float,
		tangent: Vector3,
		c_owner: Color, c_nb: Color, blend: bool, face_meta: Dictionary) -> int:
	var h_hi := maxf(v1.y, v3.y)
	var h_lo := minf(v1.y, v3.y)
	# 共享崖线 XZ：两格内边的中点线（v1→v3 与 v2→v4 的中点，t=0.5——chunk 无关：
	# 从同一全局参数现算，两侧 chunk 必得同值；_lerp_xz = 折线同源表达式）
	var m1 := _lerp_xz(v1, v3, 0.5)
	var m2 := _lerp_xz(v2, v4, 0.5)
	var wt1 := Vector3(m1.x, h_hi, m1.z)
	var wt2 := Vector3(m2.x, h_hi, m2.z)
	var wb1 := Vector3(m1.x, h_lo, m1.z)
	var wb2 := Vector3(m2.x, h_lo, m2.z)
	# 高/低侧端点（按高程定向，与 owner 归属无关——墙几何只看两端高程）
	var hi1 := v3 if v3.y >= v1.y else v1
	var hi2 := v4 if v4.y >= v2.y else v2
	var lo1 := v1 if v3.y >= v1.y else v3
	var lo2 := v2 if v4.y >= v2.y else v4
	# blend 色：外缘纯色（hi 侧端 = 高格、lo 侧端 = 低格——端点所在格规则）；
	# 墙线点 = 0.5 权重混合（edge_weights(0.5)）
	var c_hi := c_nb if v3.y >= v1.y else c_owner
	var c_lo := c_owner if v3.y >= v1.y else c_nb
	var c_wall: Variant = null
	if blend:
		c_wall = _cols(
			_edge_color(c_owner, c_nb, 0.5), _edge_color(c_owner, c_nb, 0.5),
			_edge_color(c_owner, c_nb, 0.5))
	# 高侧裙边（hi1,hi2 → wt2,wt1；h_hi 平面 → 平面 UV）。绕序守卫：owner 高/低
	# 两种朝向下裙边四边形的手性相反（hi 端在内边的左/右端互换）——按 cross.y
	# 符号现判翻转（裙边恒水平面，cy 符号确定；墙/角竖直面另走竖直口径）
	var n_a := _face_normal(hi1, hi2, wt2)
	var n_b := _face_normal(hi1, wt2, wt1)
	if (hi2 - hi1).cross(wt2 - hi1).y < 0.0:
		n_a = _face_normal(hi1, wt2, hi2)
		n_b = _face_normal(hi1, wt1, wt2)
		vi = _emit_face(st, vi, hi1, wt2, hi2, n_a,
			_uv_planar(hi1, size), _uv_planar(wt2, size), _uv_planar(hi2, size),
			_cols(c_hi, _edge_color(c_owner, c_nb, 0.5), c_hi) if blend else null)
		vi = _emit_face(st, vi, hi1, wt1, wt2, n_b,
			_uv_planar(hi1, size), _uv_planar(wt1, size), _uv_planar(wt2, size),
			_cols(c_hi, _edge_color(c_owner, c_nb, 0.5), _edge_color(c_owner, c_nb, 0.5)) if blend else null)
	else:
		vi = _emit_face(st, vi, hi1, hi2, wt2, n_a,
			_uv_planar(hi1, size), _uv_planar(hi2, size), _uv_planar(wt2, size),
			_cols(c_hi, c_hi, _edge_color(c_owner, c_nb, 0.5)) if blend else null)
		vi = _emit_face(st, vi, hi1, wt2, wt1, n_b,
			_uv_planar(hi1, size), _uv_planar(wt2, size), _uv_planar(wt1, size),
			_cols(c_hi, _edge_color(c_owner, c_nb, 0.5), _edge_color(c_owner, c_nb, 0.5)) if blend else null)
	# 竖直墙（wt1,wt2 → wb2,wb1；法线水平（cross.y = 0）——竖直面口径，见类头注）。
	# 朝向守卫（T2 评审修复 2026-10-11）：owner 高/低两种归属下墙 quad 的 raw 手性
	# 相反——owner 为高侧时 cross 指向高地格，可见侧（= RAW cross 侧，头注绕序
	# 双层口径）落在高侧、低侧玩家看崖壁被背面剔除（见洞）。按水平 cross 与
	# 「墙心→低侧裙边中点」点积现判，反向时交换两列（wt1↔wt2、wb1↔wb2 = 环序
	# 反转）——墙面恒朝低侧可见（与角竖直鳍面离心朝外同一「外向可见」纪律；
	# 高侧视角被 h_hi 裙边平台覆盖，墙背不可见是正确遮挡）。
	var wq1 := wt1
	var wq2 := wt2
	var wq3 := wb1
	var wq4 := wb2
	var wn := (wt2 - wt1).cross(wb2 - wt1)
	var wn_horiz := Vector3(wn.x, 0.0, wn.z)
	var wall_mid := (wt1 + wt2) * 0.5
	var lo_mid := (lo1 + lo2) * 0.5
	if wn_horiz.length() > 1e-9 \
			and wn_horiz.dot(Vector3(lo_mid.x - wall_mid.x, 0.0, lo_mid.z - wall_mid.z)) < 0.0:
		wq1 = wt2
		wq2 = wt1
		wq3 = wb2
		wq4 = wb1
	var n_c := _face_normal(wq1, wq2, wq4)
	var n_d := _face_normal(wq1, wq4, wq3)
	vi = _emit_face(st, vi, wq1, wq2, wq4, n_c,
		_uv_side_edge(wq1, tangent, size), _uv_side_edge(wq2, tangent, size),
		_uv_side_edge(wq4, tangent, size), c_wall)
	vi = _emit_face(st, vi, wq1, wq4, wq3, n_d,
		_uv_side_edge(wq1, tangent, size), _uv_side_edge(wq4, tangent, size),
		_uv_side_edge(wq3, tangent, size), c_wall)
	# 低侧裙边（wb1,wb2 → lo2,lo1；h_lo 平面 → 平面 UV；同上绕序守卫）
	var n_e := _face_normal(wb1, wb2, lo2)
	var n_f := _face_normal(wb1, lo2, lo1)
	if (wb2 - wb1).cross(lo2 - wb1).y < 0.0:
		n_e = _face_normal(wb1, lo2, wb2)
		n_f = _face_normal(wb1, lo1, lo2)
		vi = _emit_face(st, vi, wb1, lo2, wb2, n_e,
			_uv_planar(wb1, size), _uv_planar(lo2, size), _uv_planar(wb2, size),
			_cols(_edge_color(c_owner, c_nb, 0.5), c_lo, _edge_color(c_owner, c_nb, 0.5)) if blend else null)
		vi = _emit_face(st, vi, wb1, lo1, lo2, n_f,
			_uv_planar(wb1, size), _uv_planar(lo1, size), _uv_planar(lo2, size),
			_cols(_edge_color(c_owner, c_nb, 0.5), c_lo, c_lo) if blend else null)
	else:
		vi = _emit_face(st, vi, wb1, wb2, lo2, n_e,
			_uv_planar(wb1, size), _uv_planar(wb2, size), _uv_planar(lo2, size),
			_cols(_edge_color(c_owner, c_nb, 0.5), _edge_color(c_owner, c_nb, 0.5), c_lo) if blend else null)
		vi = _emit_face(st, vi, wb1, lo2, lo1, n_f,
			_uv_planar(wb1, size), _uv_planar(lo2, size), _uv_planar(lo1, size),
			_cols(_edge_color(c_owner, c_nb, 0.5), c_lo, c_lo) if blend else null)
	for i in 6:
		out_faces.append(face_meta.duplicate())
	return vi


## 有河边带发射（T3 WATER-02 ①）：整条边连续的下切剖面——跨带方向 u：
##   [0, bank] 岸坡 A（y_A → bed）→ [bank, 1−bank] 河床（恒 bed）→ [1−bank, 1]
##   岸坡 B（bed → y_B），各 2 三角共 6 面（kind="riverbed"，拾取候选 = 两侧两格，
##   hex_picking.gd）。跨河宽 w = 1 − 2×WaterGeom.RIVER_BANK_FRACTION（与水面
##   条带同常量——水面悬出/缩进河床即两侧 u 端点不齐，唯一计算点防漂移）；
##   沿边 s ∈ [0,1] 全长（v1/v2 → v3/v4 端点即边全长端点——修订记录三之 1）。
## 河床顶点 m/n = v + bridge×{bank, 1−bank}（_lerp_xz 同源表达式——与河畔角侧
##   折线逐位一致，焊接流形）；角点接缝由 _emit_corner_fill 的河畔角路径承担。
## UV：河床 = 平面（水平面）；岸坡 = 侧面（u 沿边切向、v 跟高程——与阶地短坡
##   同约定；岸侧与床等高时退化平面）。blend：逐顶点 edge_weights(u) 显式求值
##   （LAND-02 ⑤ 合同——u=0/1 端 = (1,0)/(0,1) 纯色，与常规边带端点规则一致）。
static func _emit_river_band(st: SurfaceTool, vi: int, out_faces: Array[Dictionary],
		v1: Vector3, v2: Vector3, v3: Vector3, v4: Vector3,
		y_a: float, y_b: float, y_bed: float,
		tangent: Vector3, size: float,
		c_owner: Color, c_nb: Color, blend: bool, face_meta: Dictionary) -> int:
	var bank := WaterGeom.RIVER_BANK_FRACTION
	# 岸坡 A 内缘 / 岸坡 B 内缘（m/n 线，河床两沿）：XZ = v 线 + bridge×{bank,1−bank}
	var m1 := _lerp_xz(v1, v3, bank)
	var m2 := _lerp_xz(v2, v4, bank)
	var n1 := _lerp_xz(v1, v3, 1.0 - bank)
	var n2 := _lerp_xz(v2, v4, 1.0 - bank)
	m1.y = y_bed
	m2.y = y_bed
	n1.y = y_bed
	n2.y = y_bed
	# 岸坡 A（v1,v2 → m2,m1；等高侧（y == bed）退化为水平面 → 平面 UV）
	var flat_a := absf(y_a - y_bed) <= 1e-9
	var uv_a1 := _uv_planar(v1, size) if flat_a else _uv_side_edge(v1, tangent, size)
	var uv_a2 := _uv_planar(v2, size) if flat_a else _uv_side_edge(v2, tangent, size)
	var uv_am1 := _uv_planar(m1, size) if flat_a else _uv_side_edge(m1, tangent, size)
	var uv_am2 := _uv_planar(m2, size) if flat_a else _uv_side_edge(m2, tangent, size)
	var n_a1 := _face_normal(v1, m1, m2)
	var n_a2 := _face_normal(v1, m2, v2)
	vi = _emit_face(st, vi, v1, m1, m2, n_a1, uv_a1, uv_am1, uv_am2,
		_cols(_edge_color(c_owner, c_nb, 0.0), _edge_color(c_owner, c_nb, bank),
			_edge_color(c_owner, c_nb, bank)) if blend else null)
	vi = _emit_face(st, vi, v1, m2, v2, n_a2, uv_a1, uv_am2, uv_a2,
		_cols(_edge_color(c_owner, c_nb, 0.0), _edge_color(c_owner, c_nb, bank),
			_edge_color(c_owner, c_nb, 0.0)) if blend else null)
	# 河床（m1,m2 → n2,n1；恒水平面 → 平面 UV）
	var n_b1 := _face_normal(m1, n1, n2)
	var n_b2 := _face_normal(m1, n2, m2)
	vi = _emit_face(st, vi, m1, n1, n2, n_b1,
		_uv_planar(m1, size), _uv_planar(n1, size), _uv_planar(n2, size),
		_cols(_edge_color(c_owner, c_nb, bank), _edge_color(c_owner, c_nb, 1.0 - bank),
			_edge_color(c_owner, c_nb, 1.0 - bank)) if blend else null)
	vi = _emit_face(st, vi, m1, n2, m2, n_b2,
		_uv_planar(m1, size), _uv_planar(n2, size), _uv_planar(m2, size),
		_cols(_edge_color(c_owner, c_nb, bank), _edge_color(c_owner, c_nb, 1.0 - bank),
			_edge_color(c_owner, c_nb, bank)) if blend else null)
	# 岸坡 B（n1,n2 → v4,v3；等高侧同退化）
	var flat_b := absf(y_b - y_bed) <= 1e-9
	var uv_n1 := _uv_planar(n1, size) if flat_b else _uv_side_edge(n1, tangent, size)
	var uv_n2 := _uv_planar(n2, size) if flat_b else _uv_side_edge(n2, tangent, size)
	var uv_v3 := _uv_planar(v3, size) if flat_b else _uv_side_edge(v3, tangent, size)
	var uv_v4 := _uv_planar(v4, size) if flat_b else _uv_side_edge(v4, tangent, size)
	var n_c1 := _face_normal(n1, v3, v4)
	var n_c2 := _face_normal(n1, v4, n2)
	vi = _emit_face(st, vi, n1, v3, v4, n_c1, uv_n1, uv_v3, uv_v4,
		_cols(_edge_color(c_owner, c_nb, 1.0 - bank), _edge_color(c_owner, c_nb, 1.0),
			_edge_color(c_owner, c_nb, 1.0)) if blend else null)
	vi = _emit_face(st, vi, n1, v4, n2, n_c2, uv_n1, uv_v4, uv_n2,
		_cols(_edge_color(c_owner, c_nb, 1.0 - bank), _edge_color(c_owner, c_nb, 1.0),
			_edge_color(c_owner, c_nb, 1.0 - bank)) if blend else null)
	for i in 6:
		out_faces.append(face_meta.duplicate())
	return vi


## 两点间水平插值（XZ lerp、y 由调用方覆盖）——阶地环点与角扇边界折线的**唯一
## 表达式**（同一函数同一入参 → 逐位一致；跨视角 1 ulp 差由既有焊接口径覆盖）。
static func _lerp_xz(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(b, t)


## 边带侧边折线（角扇的边界，与带发射同一环公式 → 焊接逐位一致）：
## **规范方向 = owner 侧 → nb 侧**（与带发射的 v1→v3 同向——折线与侧边环点逐位
## 同源；调用方需要反向时自行 reverse，reverse 不改点位）。p_owner/p_nb = 侧边
## 两端点（XZ 精确、y = 各端高程）；返回 owner→nb 途经点列（含端点）。
## flat/slope/回退档 = 单段；terrace 档 = 全部环点；cliff 竖直墙档 =
## [p_owner, 裙边→墙线点, 墙线点, p_nb]（owner 高侧先墙顶后墙底）；
## **有河档（T3 WATER-02 ①）= [p_owner, 床@bank, 床@1−bank, p_nb]**——与
## _emit_river_band 的 m/n 点同一表达式（跨角点河床连续的焊接面）。
static func _band_side_polyline(p_owner: Vector3, p_nb: Vector3, e_owner: int, e_nb: int,
		elevation_step: float, terrace_on: bool, wall_on: bool, threshold: int,
		steps: int, river_bed: Variant = null) -> Array[Vector3]:
	if river_bed != null:
		var bank := WaterGeom.RIVER_BANK_FRACTION
		var y_bed := float(river_bed) * elevation_step
		var m := _lerp_xz(p_owner, p_nb, bank)
		var n := _lerp_xz(p_owner, p_nb, 1.0 - bank)
		m.y = y_bed
		n.y = y_bed
		return [p_owner, m, n, p_nb]
	var etype := classify_edge(e_owner - e_nb, threshold)
	if etype == EDGE_FLAT or etype == EDGE_SLOPE:
		return [p_owner, p_nb]
	if etype == EDGE_TERRACE and terrace_on:
		var n := absi(e_owner - e_nb)
		var total := n * steps
		# 竖直沿 owner→nb 方向插值（与 _emit_terrace_band 同式——端点 y = 各端高程）
		var y0 := float(e_owner) * elevation_step
		var y1 := float(e_nb) * elevation_step
		var out: Array[Vector3] = []
		for s in total + 1:
			var t := float(s) / float(total)
			var p := _lerp_xz(p_owner, p_nb, t)
			p.y = lerpf(y0, y1, terrace_ring_vfrac(s, n, steps))
			out.append(p)
		return out
	if etype == EDGE_CLIFF and wall_on:
		var h_hi := maxf(p_owner.y, p_nb.y)
		var h_lo := minf(p_owner.y, p_nb.y)
		var m := _lerp_xz(p_owner, p_nb, 0.5)
		var wt := Vector3(m.x, h_hi, m.z)
		var wb := Vector3(m.x, h_lo, m.z)
		if p_owner.y >= p_nb.y:
			return [p_owner, wt, wb, p_nb]
		return [p_owner, wb, wt, p_nb]
	return [p_owner, p_nb]  # 回退档（profile 关）：单段


## 两格间 link 的河床标高（有河 → bed int；无河 → null）——角扇侧折线下切剖面的
## 参数源（river_idx = WorldData.river_edge_index() 的条目）。
static func _river_bed_of(river_idx: Dictionary, map: MapDataClass,
		a: Vector2i, b: Vector2i) -> Variant:
	var lid := WorldDataClass.link_id_of(map.index_of(a), map.index_of(b))
	if river_idx.has(lid):
		return river_idx[lid]["bed"]
	return null


## 数组反转（不改点位——折线反向遍历的确定性表达）。
static func _reversed(points: Array[Vector3]) -> Array[Vector3]:
	var out := points.duplicate()
	out.reverse()
	return out


## 角落情形分派发射（LAND-02 ④，Catlike Part 3 corner 结构转译）：
## 以三边带各自的侧边折线（owner→nb 规范向、与带发射逐位同源）拼成边界环
##（俯视 CCW = [p1, p3, p2] 基线绕序展开），对环做 **3D 耳切三角化**（XZ 投影恒为
## 弱凸三角形、边界带共线串）：耳合法性 = 3D 面积 > eps 且（XZ 非退化时）严格凸
## 且空；**XZ 退化耳 = 竖直鳍面**（y 有差的共线串——双崖角等天然竖直区域的唯一
## 填充，零 XZ 面积故不与任何 XZ 耳重叠）。效果：边界段恰用一次（焊接流形）、
## 非竖直三角绕序恒 CCW（cross.y > 0）、面数恒 = 环点数 − 2（解析预言锚）。
## 情形分派体现在边界折线形状上：三格等高 = 三点环退化为单平三角；两低一高 =
## 阶地扇（耳切自然成阶）；含 cliff = 坍缩扇（墙线点在环上被耳吞并）——含崖×
## 阶地混合角同一算法覆盖（各侧折线由该边带自身分档决定）。
## blend：每个顶点 COLOR = corner_weights(u,v) 在该点仿射参数处显式求值
##（p1=(0,0)、p2=(1,0)、p3=(0,1)；侧边点 = 两侧格权重——与边带环色同一合同）。
## UV：三角内三顶点等高 = 平面映射；否则 = 侧面（u 平面、v 跟高程——T8 约定）。
static func _emit_corner_fill(st: SurfaceTool, vi: int, out_faces: Array[Dictionary],
		p1: Vector3, p2: Vector3, p3: Vector3, eo: int, ek: int, ek1: int,
		elevation_step: float, size: float, terrace_on: bool, wall_on: bool,
		threshold: int, steps: int, map: MapDataClass, cell: Vector2i,
		nb_k: Vector2i, nb_k1: Vector2i,
		c_owner: Color, c_nbk: Color, c_nbk1: Color, blend: bool,
		face_meta: Dictionary, river_idx: Dictionary = {}) -> int:
	# 边界环（俯视 CCW）：p1 →(OB 侧) p3 →(AB 侧) p2 →(OA 侧) p1；各段折线按
	# **owner→nb 规范方向**计算（与带发射逐位同源），再按环向 reverse：
	#   · OA/OB 的 owner = 本角归属格（三格最小 ID——带发射同一归属，规范向 p1 出发）；
	#   · AB 的 owner = min(A,B)，环向须 p3→p2，owner=A 时反向。
	# 河畔角（T3）：有河侧折线走下切剖面（[岸顶, 床@bank, 床@1−bank, 岸顶]）——
	# 床点与 _emit_river_band 的 m/n 同表达式，跨角点河床连续（焊接流形）。
	var side_ob := _band_side_polyline(p1, p3, eo, ek1, elevation_step,
		terrace_on, wall_on, threshold, steps,
		_river_bed_of(river_idx, map, cell, nb_k1))
	var ab_owner_is_a := map.index_of(nb_k) < map.index_of(nb_k1)
	var side_ab_canon := _band_side_polyline(p2, p3, ek, ek1, elevation_step,
			terrace_on, wall_on, threshold, steps,
			_river_bed_of(river_idx, map, nb_k, nb_k1)) if ab_owner_is_a \
		else _band_side_polyline(p3, p2, ek1, ek, elevation_step,
			terrace_on, wall_on, threshold, steps,
			_river_bed_of(river_idx, map, nb_k, nb_k1))
	var side_ab := side_ab_canon if not ab_owner_is_a else _reversed(side_ab_canon)
	var side_oa := _reversed(_band_side_polyline(p1, p2, eo, ek, elevation_step,
		terrace_on, wall_on, threshold, steps,
		_river_bed_of(river_idx, map, cell, nb_k)))
	var loop: Array[Vector3] = []
	loop.append_array(side_ob)
	loop.append_array(side_ab.slice(1))          # 跳过 p3（OB 已含）
	loop.append_array(side_oa.slice(1, side_oa.size() - 1))  # 跳过 p2 与 p1
	# 耳切（确定性：每次从头扫描取首个合法耳）：环点全部来自同一全局参数 →
	# 跨 chunk 逐位一致；面数恒 = loop.size() − 2（测试的解析预言锚）。耳合法性：
	#   · 3D 面积 > eps（共线且同高的串点不可裁——留给邻耳吞并）；
	#   · XZ 非退化耳（area2 > eps）：须 CCW 且空（无他点入耳/压边）→ cross.y > 0；
	#   · XZ 退化耳（q 在邻点连线上、y 有差）：**竖直鳍面耳**——双崖角等天然竖直
	#     区域的唯一填充（零 XZ 面积，不与任何 XZ 耳重叠）；法线离心水平朝向。
	var poly := loop.duplicate()
	var ctr_xz := _corner_centroid_xz(p1, p2, p3)
	while poly.size() > 3:
		var clipped := false
		for i in poly.size():
			var pa: Vector3 = poly[(i + poly.size() - 1) % poly.size()]
			var pq: Vector3 = poly[i]
			var pb: Vector3 = poly[(i + 1) % poly.size()]
			if (pb - pa).cross(pq - pa).length() < 1e-9:
				continue  # 3D 退化（共线串同高点）
			if _xz_area2(pa, pq, pb) > 1e-7:
				if _ear_blocked(poly, pa, pq, pb):
					continue
				vi = _emit_corner_tri(st, vi, out_faces, pa, pq, pb,
					p1, p2, p3, size, ctr_xz, c_owner, c_nbk, c_nbk1, blend, face_meta)
			else:
				vi = _emit_corner_tri(st, vi, out_faces, pa, pq, pb,
					p1, p2, p3, size, ctr_xz, c_owner, c_nbk, c_nbk1, blend, face_meta)
			poly.remove_at(i)
			clipped = true
			break
		if not clipped:
			# 理论不可达（3D 非退化环恒有可裁耳）；防御性上报而非死循环
			push_error("[角落填充] 耳切死锁（环 %d 点）——边界折线构造异常 cell=%s k=%d e=(%d,%d,%d) loop=%s" \
				% [poly.size(), str(cell), int(face_meta["dir"]), eo, ek, ek1, str(poly)])
			break
	vi = _emit_corner_tri(st, vi, out_faces, poly[0], poly[1], poly[2],
		p1, p2, p3, size, ctr_xz, c_owner, c_nbk, c_nbk1, blend, face_meta)
	return vi


## 角区三格心 XZ 均值（竖直鳍面耳的法线朝向参考：离心 = 朝角区外）。
static func _corner_centroid_xz(p1: Vector3, p2: Vector3, p3: Vector3) -> Vector2:
	return Vector2((p1.x + p2.x + p3.x) / 3.0, (p1.z + p2.z + p3.z) / 3.0)


## 单个角落三角：XZ 非退化（耳切 CCW 保证）→ cross.y > 0 原序发射；XZ 退化
##（竖直鳍面/最终三角退化情形）→ 法线离心水平朝向（必要时交换后两顶点）。
static func _emit_corner_tri(st: SurfaceTool, vi: int, out_faces: Array[Dictionary],
		a: Vector3, b: Vector3, c: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		size: float, ctr_xz: Vector2,
		c_owner: Color, c_nbk: Color, c_nbk1: Color, blend: bool,
		face_meta: Dictionary) -> int:
	var ny := (b - a).cross(c - a).y
	# 竖直面判定阈值 1e-6：XZ 共线点的浮点噪声 ~1e-9·坐标量级（1e-9 阈会把真竖直
	# 面误判成微负绕序）；真实非竖直面 cross.y ≥ ~0.05（角区三角面积量级），隔两个
	# 数量级。竖直面：水平法线背离角区心（与崖墙面朝低侧同一「外向可见」口径）
	if absf(ny) <= 1e-6:
		var mid := (a + b + c) / 3.0
		var nrm := (b - a).cross(c - a).normalized()
		var horiz := Vector3(nrm.x, 0.0, nrm.z)
		if horiz.length() > 1e-9 \
				and horiz.dot(Vector3(mid.x - ctr_xz.x, 0.0, mid.z - ctr_xz.y)) < 0.0:
			var t := b
			b = c
			c = t
	var n := _face_normal(a, b, c)
	var flat_tri := absf(a.y - b.y) <= 1e-9 and absf(b.y - c.y) <= 1e-9
	if flat_tri:
		vi = _emit_face(st, vi, a, b, c, n,
			_uv_planar(a, size), _uv_planar(b, size), _uv_planar(c, size),
			_corner_tri_cols(a, b, c, p1, p2, p3, c_owner, c_nbk, c_nbk1, blend))
	else:
		vi = _emit_face(st, vi, a, b, c, n,
			_uv_side_corner(a, size), _uv_side_corner(b, size), _uv_side_corner(c, size),
			_corner_tri_cols(a, b, c, p1, p2, p3, c_owner, c_nbk, c_nbk1, blend))
	out_faces.append(face_meta.duplicate())
	return vi


## 三点 XZ 有向面积 ×2（**与 3D cross.y 同号**：俯视逆时针为正——XZ 平面从 +Y 看
## 是左手系，2D 叉积 ab.x·ac.y − ab.y·ac.x 恰与 cross.y 反号，此处直接用 cross.y
## 分量公式）——耳凸性/共线判定的几何基。
static func _xz_area2(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ub := b.x - a.x
	var vb := b.z - a.z
	var uc := c.x - a.x
	var vc := c.z - a.z
	return vb * uc - ub * vc


## 耳是否被其他环点阻挡（点严格在耳内或任一边开段上 → 阻挡；共线串点在弦上时
## 该耳不可裁——先裁别处，环收缩后自然可裁）。容差 1e-7 与 _xz_area2 同级。
static func _ear_blocked(poly: Array[Vector3], a: Vector3, q: Vector3, b: Vector3) -> bool:
	for p in poly:
		if p == a or p == q or p == b:
			continue
		if _xz_area2(a, q, b) * _xz_area2(a, q, p) > 0.0 \
				and _xz_area2(q, b, a) * _xz_area2(q, b, p) > 0.0 \
				and _xz_area2(b, a, q) * _xz_area2(b, a, p) > 0.0:
			return true  # 严格在耳内（凸多边形耳内无点——防御共线退化外的病态）
		for seg in [[a, q], [q, b], [b, a]]:
			if _on_open_segment(p, seg[0], seg[1]):
				return true
	return false


## 点 p 是否在开线段 (s, e) 上（不含端点；容差与 _xz_area2 同级）。
static func _on_open_segment(p: Vector3, s: Vector3, e: Vector3) -> bool:
	var sp := Vector2(p.x - s.x, p.z - s.z)
	var se := Vector2(e.x - s.x, e.z - s.z)
	var len2 := se.length_squared()
	if len2 < 1e-18:
		return false
	var t := sp.dot(se) / len2
	if t <= 1e-9 or t >= 1.0 - 1e-9:
		return false
	var proj := s + Vector3(se.x * t, 0.0, se.y * t)
	return Vector2(p.x - proj.x, p.z - proj.z).length() <= 1e-6


## 角落顶点色（blend）：顶点在角区仿射参数域的位置 → corner_weights(u,v) 显式求值
##（LAND-02 ⑤）。参数域：p1=(0,0)、p2=(1,0)（u 轴）、p3=(0,1)（v 轴）——XZ 仿射
## 求解（环点全部在域边界上，u,v ∈ [0,1] 且 u+v ≤ 1）。
static func _corner_tri_cols(a: Vector3, b: Vector3, c: Vector3,
		p1: Vector3, p2: Vector3, p3: Vector3,
		c_owner: Color, c_nbk: Color, c_nbk1: Color, blend: bool) -> Variant:
	if not blend:
		return null
	var e1 := Vector2(p2.x - p1.x, p2.z - p1.z)
	var e2 := Vector2(p3.x - p1.x, p3.z - p1.z)
	var ca := _corner_color(a, e1, e2, p1, c_owner, c_nbk, c_nbk1)
	var cb := _corner_color(b, e1, e2, p1, c_owner, c_nbk, c_nbk1)
	var cc := _corner_color(c, e1, e2, p1, c_owner, c_nbk, c_nbk1)
	return _cols(ca, cb, cc)


static func _corner_color(p: Vector3, e1: Vector2, e2: Vector2, p1: Vector3,
		c_owner: Color, c_nbk: Color, c_nbk1: Color) -> Color:
	var d := Vector2(p.x - p1.x, p.z - p1.z)
	var den := e1.x * e2.y - e1.y * e2.x
	var u := (d.x * e2.y - d.y * e2.x) / den
	var v := (e1.x * d.y - e1.y * d.x) / den
	var w := BlendLib.corner_weights(u, v)
	return c_owner * w.x + c_nbk * w.y + c_nbk1 * w.z



# ---------------- 内部 ----------------

## 格高程 → 世界 y（int 分层 × 步长；可为负）。
static func _y_of(map: MapDataClass, cell: Vector2i, elevation_step: float) -> float:
	return float(map.elevation_at(cell)) * elevation_step


## 单三角：法线显式（面法线 = flat shading 硬边口径）+ 调用方算好的逐顶点 UV
## + 顶点 + 递增显式索引（base = 调用方维护的顶点游标；返回更新后的游标）。
## faces 序 = 三角序（本函数只 emit，面记录由调用方追加——两者严格同步）。
## UV 由调用方按面分类选取（平面/侧面公式见下方 _uv_*——T8 约定的唯一计算点，
## 不在两处各算）。
## cols 非空（PackedColorArray 恰 3 项）= blend style 附顶点 COLOR（BLEND-01：
## 端点纯色 → 带内线性插值；null/空 = fallback 不设 COLOR 通道——同一发射路径，
## 保证两 style 几何逐位一致）。
## 索引序 = (base, base+2, base+1)：索引三角俯视**顺时针** = Godot 正面（F-1 修复，
## 2026-10-10）；raw 顶点序保持几何逆时针（碰撞/face 表口径，见类头注「绕序双层口径」）。
static func _emit_face(st: SurfaceTool, base: int, a: Vector3, b: Vector3, c: Vector3,
		n: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2,
		cols: Variant = null) -> int:
	var pc: PackedColorArray = cols if cols is PackedColorArray else PackedColorArray()
	var pts: Array[Vector3] = [a, b, c]
	var uvs: Array[Vector2] = [uv_a, uv_b, uv_c]
	for i in 3:
		if pc.size() == 3:
			st.set_color(pc[i])
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	st.add_index(base)
	st.add_index(base + 2)
	st.add_index(base + 1)
	return base + 3


## 三色顶点组（blend style 的 _emit_face cols 参数构造——集中一处，调用点免散装数组）。
static func _cols(ca: Color, cb: Color, cc: Color) -> PackedColorArray:
	var out := PackedColorArray()
	out.append(ca)
	out.append(cb)
	out.append(cc)
	return out


## 水平面 UV（顶面/平连边带/等高角落）：世界平面映射 u = x/2R、v = −z/2R
##（T8 约定；平地整图无缝连续平铺——与归属格无关，跨 chunk 自然连续）。
static func _uv_planar(p: Vector3, size: float) -> Vector2:
	return Vector2(p.x / (2.0 * size), -p.z / (2.0 * size))


## 侧面 UV（|Δh|≥1 边带）：u = XZ 沿边切向投影/2R（tangent = HexMath.edge_tangent_world，
## 每方向随边向）、v = −y/2R（竖向纹理随高程走：Δ1 半纹、Δ2 恰一整纹）。
static func _uv_side_edge(p: Vector3, tangent: Vector3, size: float) -> Vector2:
	return Vector2((p.x * tangent.x + p.z * tangent.z) / (2.0 * size), -p.y / (2.0 * size))


## 侧面 UV（非等高角落补洞三角）：u = 平面 u = x/2R、v = −y/2R（与两侧边带 u 轴
## 不连续——已接受代价，见类头注与 docs/notes/m1a-t8-art-branch.md）。
static func _uv_side_corner(p: Vector3, size: float) -> Vector2:
	return Vector2(p.x / (2.0 * size), -p.y / (2.0 * size))


## 面法线（flat shading；绕序保证 cross 模 > 0——三角 xz 投影恒有正面积，归一安全）。
static func _face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (b - a).cross(c - a).normalized()


## 全图材质表预检：图内任一格地形 id 缺槽 / 槽值非 Material → false
##（「无隐式兜底」——不做缺槽补色、不静默跳格）。
static func _material_table_valid(map: MapDataClass, materials: Variant) -> bool:
	if not (materials is Dictionary):
		return false
	var table: Dictionary = materials
	for cell in map.cells():
		var tid := map.terrain_at(cell)
		if tid == MapDataClass.TERRAIN_NONE or not table.has(tid):
			return false
		if not (table[tid] is Material):
			return false
	return true


## 全图色板预检（blend style）：图内任一格地形 id 缺槽 / 槽值非 Color / 任一通道
## 非有限或为负 → false（与材质表同纪律——无缺槽补色、无静默跳格；色板约定
## alpha=1，混色含 alpha 通道，见 hex_terrain_blend.gd 头注）。
static func _palette_table_valid(map: MapDataClass, palette: Variant) -> bool:
	if not (palette is Dictionary):
		return false
	var table: Dictionary = palette
	for cell in map.cells():
		var tid := map.terrain_at(cell)
		if tid == MapDataClass.TERRAIN_NONE or not table.has(tid):
			return false
		if not _color_entry_valid(table[tid]):
			return false
	return true


## 单色板槽合法性：Color 且 RGBA 通道全部有限、非负（上界不设——HDR 过亮是
## 合法美术选择；负通道无意义，拒）。
static func _color_entry_valid(v: Variant) -> bool:
	if not (v is Color):
		return false
	var col: Color = v
	return is_finite(col.r) and is_finite(col.g) and is_finite(col.b) and is_finite(col.a) \
		and col.r >= 0.0 and col.g >= 0.0 and col.b >= 0.0 and col.a >= 0.0
