## hex_highlight.gd — 高亮系统纯逻辑层（M1a-T7；docs/04-tasks-m1.md M1a-T7 + 调研文档
##   「相机、高亮和随机地图」节 + 2026-10-09 微决策 2）
## 分层（对齐 hex_picking.gd / hex_camera.gd 先例）：
## - 本文件 = 纯逻辑/资源层：材质工厂、内顶面扇 mesh、格锚点、路径描线几何、
##   集合状态机（差异计算）。零场景节点（ADR-2；StandardMaterial3D/ArrayMesh 是
##   Resource 非场景节点——T4 builder 产材质先例）。场景挂载在
##   scripts/ui/highlight_layer.gd（view 层，可整体删除——「删 scripts/ui/** 后
##   tests 全绿」的可执行口径，02 §3）。
## 微决策 2（2026-10-09 拍板）：高亮只覆盖**内顶面**（solid_factor 内六边形），
##   斜坡连接带不站人、不高亮——扇形与 T4 顶面同一全局参数源（HexMath.vertex_xz /
##   axial_to_world 现算，非另套公式），y 仅加 lift 抬升防 z-fighting（lift 由
##   节点 y 提供，mesh 本体 y=0 平面——几何与放置分离，形状可全层共享）。
## 深度纪律（04 M1a-T7 细化）：透明材质**保持深度测试开启**（no_depth_test=false），
##   高亮被地形正确遮挡（不穿山）；不靠关闭深度测试掩盖排序问题。共面治理：
##   同层不同格的扇面互不重叠（各占本格内顶面）天然无歧义；**跨层同格双扇面、
##   描线带×途经格扇面**几何重叠——一律以 lift 档位错开（lift_for_tier 档距
##   LIFT_TIER_STEP；描线带另加半档 DEFAULT_PATH_LIFT_EXTRA，永不落在任何整档上），
##   不共面即无深度缝合纹/闪（「远近缩放下不闪」的几何面）。
## 复用纪律（04 M1a-T7 细化）：扇形逐格相同（局部坐标）→ 全层共享 1 个 ArrayMesh +
##   每格 1 个 MeshInstance3D（y=格顶+lift）；集合切换走 State 差异（只对差异格
##   增删）——鼠标移动不重建地形 mesh、不动未变格的节点。
## 路径描线（04 M1a-T7「支持路径描线」，为 M1b 移动范围/路径预铺）：折线点 = 途经格
##   心 + 各格顶面 y + lift；条带 mesh = 每段一矩形（两端各延伸 min(半宽, 半段长)
##   转角搭接），侧向恒水平垂直于段向；发射顶点序 = 俯视顺时针（Godot 正面，
##   F-1 修复 2026-10-10；法线仍按几何序现算朝上——见 _emit_quad 注）。
## 依赖方向：本文件 → hex_math.gd（T1）/ map_data.gd（T2），只读不反向。
class_name HexHighlight
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")

## 高亮面相对内顶面的 y 抬升（世界单位；防 z-fighting。size=1 时 2% 格径，
## 远大于深度缓冲在该视距下的分辨率、远小于一格高程步长——不产生可见悬浮）
const DEFAULT_LIFT := 0.02
## 层间 lift 档距：同格多层面（如 hover 层 × 选择层）各错一档，消除跨层同格
## 共面 z-fighting（几何重叠 + 精确同 y = 远近缩放下的缝合纹/闪源）
const LIFT_TIER_STEP := 0.01
## 描线带相对本层扇面的额外抬升 = **1.5 档**（半档：0.015 不是 LIFT_TIER_STEP 的
## 整数倍 → 任何层的描线 lift 永不落在任何整档扇面 lift 上，带×扇全组合不共面；
## 见 tests/test_hex_highlight.gd test_lift_tiers_separate_coplanar_surfaces）
const DEFAULT_PATH_LIFT_EXTRA := 0.015
## 默认高亮色（半透明琥珀；alpha ∈ (0,1) —— 透明由 TRANSPARENCY_ALPHA 承载）
const DEFAULT_COLOR := Color(1.0, 0.83, 0.25, 0.42)
## 默认描线色（不透明橙——线窄无需透明，不透明还省一次透明批次）
const DEFAULT_PATH_COLOR := Color(1.0, 0.55, 0.15, 1.0)
## 默认描线宽度系数（宽 = 系数 × size）
const DEFAULT_PATH_WIDTH_FACTOR := 0.18

# ---------------- 材质工厂 ----------------

## 高亮材质：半透明 + 无光照（色稳定不受日光角度影响）+ **深度测试保持开启**。
## no_depth_test=false 是 04 M1a-T7「不靠关深度测试掩盖穿山」的落点
##（tests/test_hex_highlight.gd 断言锚定；翻案须先改 04 对应验收）。
static func highlight_material(color: Color = DEFAULT_COLOR) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false  # 显式保持默认（默认即 false；写出 = 断言锚点）
	mat.cull_mode = BaseMaterial3D.CULL_BACK  # 索引三角 = 俯视顺时针（Godot 正面），CULL_BACK 下俯视可见（F-1 修复）
	return mat


## 描线材质：不透明 + 无光照 + 深度测试同样保持开启（穿山纪律与高亮面一致）。
static func path_material(color: Color = DEFAULT_PATH_COLOR) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	return mat

# ---------------- 内顶面扇形（微决策 2：只盖内顶面）----------------

## 内顶点 i 的**局部**偏移（原点 = 格心、y=0 平面）：顶点相对格心偏移 × solid_factor。
## 与 HexMath.inner_vertex 同一参数源（vertex_xz / axial_to_world 现算相减），
## 逐位一致由 tests/test_hex_highlight.gd 对表锚定——「贴合内顶面」的形状面。
static func inner_vertex_local(i: int, size := 1.0, solid_factor := 0.8) -> Vector3:
	var center := Hex.axial_to_world(Vector2i.ZERO, size)
	var v := Hex.vertex_xz(Vector2i.ZERO, i, size)
	return Vector3((v.x - center.x) * solid_factor, 0.0, (v.y - center.z) * solid_factor)


## 内顶面扇形 mesh（局部坐标）：顶点 0 = 格心原点、1..6 = 内顶点；6 三角索引扇。
## 索引序 = (0, 1+(k+1)%6, 1+k)：索引三角俯视**顺时针** = Godot 正面（F-1 修复，
## 2026-10-10；raw 顶点序仍为 T4 几何口径 (格心, inner_k, inner_{k+1})——对表测试锚 raw）。
## 形状与格无关（高程由节点 y 表达）→ 全层共享单实例（复用纪律的几何面）。
static func inner_fan_mesh(size := 1.0, solid_factor := 0.8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3.ZERO)
	for i in 6:
		st.set_normal(Vector3.UP)
		st.add_vertex(inner_vertex_local(i, size, solid_factor))
	for k in 6:
		st.add_index(0)
		st.add_index(1 + (k + 1) % 6)
		st.add_index(1 + k)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh

# ---------------- 格锚点（贴合内顶面的放置面）----------------

## 档位化层 lift：tier 0 = 基准档（选择/范围集层），tier 1 = 瞬时反馈层（hover），
## 更高档留给后续叠层（M1b 移动范围 × 路径预览等）。同场景多层各取不同档
## ——跨层同格扇面即错开 LIFT_TIER_STEP，不共面（见类头注「共面治理」）。
static func lift_for_tier(tier: int) -> float:
	return DEFAULT_LIFT + float(tier) * LIFT_TIER_STEP

## 格内顶面世界 y = 高程 × 步长 + lift（lift 抬升防 z-fighting，见 DEFAULT_LIFT 注）。
static func cell_top_y(map: MapDataClass, cell: Vector2i,
		elevation_step := 1.0, lift := DEFAULT_LIFT) -> float:
	return float(map.elevation_at(cell)) * elevation_step + lift


## 高亮节点放置位（世界坐标）：格心 xz + 内顶面 y。mesh 顶点已是局部形状 →
## 节点 position 即本值（view 层挂地图根下、局部零偏移，同 MapView 挂载约定）。
## 界外格 elevation_at 为哨兵 → 返回值无意义；调用方（view 层）先 has_cell 过滤。
static func cell_anchor(map: MapDataClass, cell: Vector2i,
		size := 1.0, elevation_step := 1.0, lift := DEFAULT_LIFT) -> Vector3:
	var c := Hex.axial_to_world(cell, size)
	return Vector3(c.x, cell_top_y(map, cell, elevation_step, lift), c.z)

# ---------------- 路径描线（M1b 移动范围/路径预铺）----------------

## 路径折线点：途经格心 + 各格内顶面 y。cells 任一格界外 / 空 → 空数组
##（显式失败，调用方判空；不静默截断半条路径）。单格 → 单点（无线段）。
static func path_points(cells: Array, map: MapDataClass,
		size := 1.0, elevation_step := 1.0, lift := DEFAULT_LIFT) -> PackedVector3Array:
	var out := PackedVector3Array()
	if cells.is_empty():
		return out
	for c in cells:
		if not (c is Vector2i) or not map.has_cell(c):
			return PackedVector3Array()
		var anchor := cell_anchor(map, c, size, elevation_step, lift)
		out.append(anchor)
	return out


## 折线 → 贴地带状 mesh：每段 1 矩形（2 三角），段两端各沿**水平投影段向**
## 延伸 min(半宽, 半段长)（转角搭接；恒水平 → 端点 y 精确贴合途经格顶面）；
## 侧向 = (−dz, 0, dx) 归一 × 半宽（恒垂直于段向、恒水平）；绕序 cross 朝上
##（T4 口径）；法线 = 面法线现算（斜坡段倾斜）。
## points < 2 / width ≤ 0 / 水平投影零长段全跳过 → null（显式失败）。
static func path_strip_mesh(points: PackedVector3Array, width := 0.18) -> Variant:
	if points.size() < 2 or width <= 0.0:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var flat := Vector2(b.x - a.x, b.z - a.z)
		if flat.length() < 1e-9:
			continue  # 水平重合段（同格重复等）跳过，不产退化三角
		var fdir := Vector3(flat.x, 0.0, flat.y).normalized()
		var side := Vector3(-fdir.z, 0.0, fdir.x) * (width * 0.5)
		var ext: float = minf(width * 0.5, flat.length() * 0.5)
		var a0 := a - fdir * ext - side
		var a1 := a - fdir * ext + side
		var b0 := b + fdir * ext - side
		var b1 := b + fdir * ext + side
		_emit_quad(st, a0, a1, b1, b0)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	if mesh.get_surface_count() == 0:
		return null
	return mesh


## 单矩形 2 三角。**发射顶点序 = (a0,b1,a1)+(a0,b0,b1)：俯视顺时针 = Godot 正面**
##（F-1 修复，2026-10-10）；法线仍按几何序 (a0,a1,b1)/(a0,b1,b0) 现算（朝上侧，
## flat shading——法线描述面朝向，发射序决定剔除面，两者解耦）。
static func _emit_quad(st: SurfaceTool, a0: Vector3, a1: Vector3, b1: Vector3, b0: Vector3) -> void:
	var n1 := _face_normal(a0, a1, b1)
	var n2 := _face_normal(a0, b1, b0)
	st.set_normal(n1)
	st.add_vertex(a0)
	st.add_vertex(b1)
	st.add_vertex(a1)
	st.set_normal(n2)
	st.add_vertex(a0)
	st.add_vertex(b0)
	st.add_vertex(b1)


## 面法线（flat shading；T4 同款实现）。
static func _face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (b - a).cross(c - a).normalized()

# ---------------- 集合状态机（差异切换的驱动核）----------------

## 高亮集合状态机：维护当前高亮格集合，set_cells 返回**集合差异**
##（{"added", "removed"}，均 Array[Vector2i]）——view 层据差异只对增删格动节点
##（04 M1a-T7 细化「按集合差异切换（鼠标移动不重建地形 mesh）」的逻辑面；
## 节点侧证据见 tools/highlight_scene_check.gd）。
## 顺序口径：added 按新集合给定序、removed 按旧集合留存序——顺序无合同意义，
## 需确定性比较的调用方按集合比较（tests 同口径）。
## 纯 RefCounted、零节点（ADR-2）；hover/选择/清空/切换四态的对象面。
class State:
	extends RefCounted

	var _active: Dictionary = {}  # Vector2i → true（插入序 = 首次进入集合的给定序）

	## 切换集合：返回与旧集合的差异。空数组 = 清空（等价 clear_cells）。
	## 非 Vector2i 元素忽略（防御；view 层过滤后调用则不存在）。
	func set_cells(cells: Array) -> Dictionary:
		var want := {}
		for c in cells:
			if c is Vector2i:
				want[c] = true
		var added: Array[Vector2i] = []
		var removed: Array[Vector2i] = []
		for c in want:
			var cell: Vector2i = c
			if not _active.has(cell):
				added.append(cell)
		for c in _active:
			var cell: Vector2i = c
			if not want.has(cell):
				removed.append(cell)
		_active = want
		return {"added": added, "removed": removed}

	## 清空：返回全量 removed（added 恒空）。空集再清 → 两者皆空（幂等）。
	func clear_cells() -> Dictionary:
		var removed := cells()
		_active.clear()
		var added: Array[Vector2i] = []
		return {"added": added, "removed": removed}

	func has_cell(cell: Vector2i) -> bool:
		return _active.has(cell)

	func cell_count() -> int:
		return _active.size()

	## 当前集合快照（插入序；顺序无合同意义，比较按集合）。
	func cells() -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for c in _active:
			var cell: Vector2i = c
			out.append(cell)
		return out
