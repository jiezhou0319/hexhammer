## hex_grid_line_builder.gd — 逻辑分区格线层纯逻辑几何（M1a T2 GRID-01；执行方案
##   §3 GRID-01 + 拍板⑦「格线层归 T2」；参考件 = notes/spike-1007-salvage §1.1
##   的目检结论——线宽 0.012、α 0.28、UNSHADED+双面，本件沿观感档、几何本作化）
## 职责与合同（翻案须先改 04 与 tests/test_hex_grid_line.gd，不动架构）：
## - **沿 NeighborLink 边发射 + 地图外缘边**（修订记录三之 8：仅遍历内部
##   NeighborLink 只描内部边——「全部格子细描边」须含界外无邻格的外缘边，否则
##   地图边界格缺边）：每物理边**恰一**描边带（内部边归稳定 ID 较小格、外缘边归
##   该格自身——沿 builder 边带归属先例）；跨界无缝、chunk 无关铁律自动满足
##   （strip 顶点从 HexMath.vertex_xz 全局参数现算，唯一生成路径）；
## - 贴面高度 = 两侧格面**较高侧** y + lift_for_tier(TIER_GRID_LINE) 新档
##   （hex_highlight.gd 档位表统一登记；**高侧贴面是可选视觉策略，不得宣称对低侧
##   表面恒贴面**——低侧连接带上空走线为已知取舍）；strip 恒水平 → y 恒高于两侧
##   任意地形面，不共面（无 z-fighting）；
## - 线几何 = 六边形真边界（外顶点 d→d+1 连线）上的细条带（宽 width、侧向 =
##   dir_unit_world(d)，垂直边线水平展开）——spike 版「逐格独立描六边边」改为每
##   物理边一次发射（逐格描边 = 同一物理边两条带共面，z-fighting 源）；
## - faces 元数据同构：{"kind": "grid", "cell": 归属格, "dir": d, "rim": bool}×2
##   （每 strip 两三角）；**不进拾取层**（view 层只挂 MeshInstance3D 不建碰撞体——
##   格线不得截获地形拾取）；不参与 blend 色板（无 COLOR 通道，独立材质）；
## - 关格线 = 无本层（TerrainStyle.grid_line_enabled=false → inputs_for 不出
##   grid_line 键 → view 不建节点）——地形 mesh 与无格线基线逐位一致（回退锚：
##   格线是独立 mesh 层，不触碰地形构建路径）；
## - 纯逻辑类：RefCounted、零场景节点（ADR-2）；依赖 → hex_math / map_data /
##   hex_terrain_builder（chunk 划分复用）/ hex_highlight（lift 档位表）只读。
##   材质工厂 UNSHADED + 半透明 + 双面 + 深度测试保持开启（spike 参考件口径；
##   穿山纪律同 hex_highlight——不靠关深度测试掩盖排序问题）。
class_name HexGridLineBuilder
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const HexHighlightLib := preload("res://addons/hexhammer/hex_highlight.gd")

## 默认线宽（世界单位；spike 参考件目检档 0.012。绝对值口径不随 size 缩放——
## 调观感档改 TerrainStyle.grid_line_width，本常量仅缺省）
const DEFAULT_WIDTH := 0.012

# ---------------- 构建入口 ----------------

## 整图分块构建。material = 格线材质（make_material 产物或自定义 Material）；
## material 非 Material / width ≤ 0 / size / elevation_step ≤ 0 / chunk 参数 ≤ 0
## → null（显式失败，无隐式兜底）。返回 {"chunks": Array[chunk 字典],
## "chunk_rects": Array[Rect2i], "lift": float, "width": float}；chunk 字典 =
## {"chunk": Rect2i, "mesh": ArrayMesh, "faces": Array[Dictionary]
## （与 mesh 三角一一对应）, "strip_count": int}。
static func build_map(map: MapDataClass, chunk_cols := 10, chunk_rows := 10,
		material: Material = null, size := 1.0, elevation_step := 1.0,
		width := DEFAULT_WIDTH) -> Variant:
	if not (material is Material) or width <= 0.0 or size <= 0.0 or elevation_step <= 0.0:
		return null
	if chunk_cols <= 0 or chunk_rows <= 0:
		return null
	var lift := HexHighlightLib.lift_for_tier(HexHighlightLib.TIER_GRID_LINE)
	var rects := Builder.chunk_rects_for(map.width, map.height, chunk_cols, chunk_rows)
	var chunks: Array = []
	for rect in rects:
		chunks.append(_build_chunk(map, rect, material, size, elevation_step, width, lift))
	return {
		"chunks": chunks,
		"chunk_rects": rects,
		"lift": lift,
		"width": width,
	}


## 单 chunk：归属格在本块的物理边各一 strip（归属 = 内部边两格稳定 ID 较小者 /
## 外缘边本格——跨 chunk 由归属块生成，本块跳过；与 builder 边带同一归属纪律）。
## 空矩形（无格）→ 空结果（格线层允许空 chunk——地形层空矩形判 null 是构建失败
## 口径，本层无「半张图」歧义）。
static func _build_chunk(map: MapDataClass, chunk: Rect2i, material: Material,
		size: float, elevation_step: float, width: float, lift: float) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	var faces: Array[Dictionary] = []
	var vi := 0
	var strip_count := 0
	for cell in Builder.chunk_cells(map, chunk):
		var id := map.index_of(cell)
		var h := float(map.elevation_at(cell)) * elevation_step
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			var rim := not map.has_cell(nb)
			if not rim and map.index_of(nb) < id:
				continue
			# 贴面高度 = 两侧格面较高侧 y + 格线档 lift（高侧贴面策略，见类头注）
			var hnb := h if rim else float(map.elevation_at(nb)) * elevation_step
			var y := maxf(h, hnb) + lift
			# 六边形真边界线（外顶点 d→d+1）± 半宽侧向展开（侧向 = 方向 d 单位向量，
			# 垂直边线水平）——strip 恒水平面
			var e1 := Hex.vertex_xz(cell, d, size)
			var e2 := Hex.vertex_xz(cell, (d + 1) % 6, size)
			var u := Hex.dir_unit_world(d) * (width * 0.5)
			var a := Vector3(e1.x - u.x, y, e1.y - u.z)
			var b := Vector3(e1.x + u.x, y, e1.y + u.z)
			var c := Vector3(e2.x + u.x, y, e2.y + u.z)
			var e := Vector3(e2.x - u.x, y, e2.y - u.z)
			vi = _emit_tri(st, vi, a, b, c)
			vi = _emit_tri(st, vi, a, c, e)
			var meta := {"kind": "grid", "cell": cell, "dir": d, "rim": rim}
			faces.append(meta.duplicate())
			faces.append(meta.duplicate())
			strip_count += 1
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return {"chunk": chunk, "mesh": mesh, "faces": faces, "strip_count": strip_count}

# ---------------- 材质工厂 ----------------

## 格线材质（spike 参考件口径：UNSHADED——色稳定不受日光角度影响；半透明 α；
## 双面——细条带任何倾角可见；深度测试保持开启——穿山纪律）。
static func make_material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	return mat

# ---------------- 内部 ----------------

## 单三角：法线恒 +Y（strip 水平）+ raw 几何序俯视 CCW + 渲染索引翻转为 Godot
## 正面（hex_terrain_builder._emit_face 同口径，无 UV/COLOR——格线独立材质不参与
## blend 色板与地形 UV 约定）。
static func _emit_tri(st: SurfaceTool, base: int, a: Vector3, b: Vector3, c: Vector3) -> int:
	for p in [a, b, c]:
		st.set_normal(Vector3.UP)
		st.add_vertex(p)
	st.add_index(base)
	st.add_index(base + 2)
	st.add_index(base + 1)
	return base + 3
