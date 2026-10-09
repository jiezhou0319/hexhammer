## hex_camera.gd — 策略相机纯逻辑层（M1a-T6；docs/04-tasks-m1.md M1a-T6 +
##   docs/02-architecture.md ADR-13「策略相机控制器（axial ↔ 世界坐标映射放 view 层
##   辅助模块）」+ M1a 实现调研「相机、高亮和随机地图」节）
## 分工（沿 T5 先例——hex_picking.gd 口径）：本文件 = view 层辅助模块的**可测纯逻辑
##   部分**，纯函数/纯状态、零场景节点（ADR-2；「删 scripts/ui/** 后 tests 全绿」的
##   分层验收由此成立——tests 只依赖本文件，不感知 scripts/ui/strategy_camera.gd）；
##   输入处理与节点变换应用 = scripts/ui/strategy_camera.gd（CameraRig，不可 headless 测）。
## 三个拍板写死的约定（04 M1a-T6 细化「二选一写死」；翻案须明说并回改
##   tests/test_hex_camera.gd 对应用例，不动架构）：
## 1. **边界语义 = 钳「相机焦点」**（不是钳「整个可见范围」）：焦点（世界 XZ）钳制在
##   地图可玩区包围盒（全部格子外沿顶点 AABB，可 +padding）内。理由：
##   ① 04 验收的测试口径即「四角+中心**焦点**边界」；② 拉远至可见范围大于全图时，
##   钳可见范围会退化（焦点恒锁图心、不可平移），钳焦点保证任意缩放档位下全图可达
##   （四角焦点可达），且钳制域与视口宽高比解耦——headless 纯函数测试无需视口参数；
##   ③ 拉远时图外空处可见属背景/雾的表现职责，不进钳制语义（「不出界」按焦点口径执行）。
## 2. **固定俯角**：pitch（默认 55° = T3 沙盒固定摆位口径）恒定、与缩放档位无关——
##   参考工程 hex_map_camera「随缩放把俯角 −90°→−45° 插值」的逻辑**明确不抄**；
##   camera_offset 按 (水平后向·cosθ + 上·sinθ)·d 构造，俯角不变量由构造保证
##   （tests 逐档锚定，即该排除项的回归锚）。
## 3. **拖拽走固定参考平面**：拖拽锚点/命中一律与 y = plane_y（默认 0 = 地图基准面）
##   的水平无限平面求交（drag_plane_xz），**不与地形 mesh 求交**——跨高程拖拽镜头
##   不跳（任务卡「防跨高程镜头跳动」的落字）。
## axial ↔ 世界映射：只透传 HexMath（T1 唯一参数源；「axial→世界只动 x/z、y 由高程
##   层叠加」——本层 y 恒不参与格子换算）。相机焦点 = 世界 XZ 平面点（Vector2(x, z)）；
##   y 语义 = 固定参考平面高度 plane_y（相机注视点与拖拽锚点共用同一平面）。
## 依赖方向：本文件 → hex_math.gd（T1）/ map_data.gd（T2，仅 map_focus_bounds 读尺寸），
##   只读不反向；不依赖任何场景节点。
class_name HexCamera
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")

## 固定俯角（度）。55 = T3 沙盒固定摆位口径（rotation_degrees.x = −55）；
## 手感可调——但「俯角随缩放插值」永不引入（约定 2）。
const DEFAULT_PITCH_DEG := 55.0

## 固定偏航（度）。0 = 相机在焦点南侧、朝北看（屏幕右 = +x 东）；M1a 无旋转控制。
const DEFAULT_YAW_DEG := 0.0

## 默认缩放档位表（焦点→相机世界距离，升序 = 由近到远）。60×40 / size=1 图的起步
## 值；档位数与距离都可直接换表（「缩放档位顺手」= 04 M1a-T6 主创实操确认项）。
const DEFAULT_ZOOM_DISTANCES := [18.0, 26.0, 36.0, 48.0, 62.0, 78.0]

## 「无边界」钳制域（±1e9）：测试/未设地图时的钳制不动语义。
const UNBOUNDED := Rect2(Vector2(-1e9, -1e9), Vector2(2e9, 2e9))

## 拖拽平面求交的「平行」判定阈值（|dir.y| 低于此值视为与水平面无交）。
const PLANE_PARALLEL_EPS := 1e-9

## 相机焦点（世界 XZ；钳制对象——边界语义见类头注约定 1）
var focus := Vector2.ZERO
## 当前缩放档（0 = 最近档；zoom_distances.size()−1 = 最远档）
var zoom_index := 0
## 缩放档位表（升序；构造时空表回退 DEFAULT_ZOOM_DISTANCES）
var zoom_distances: Array[float] = []
## 焦点钳制域（世界 XZ AABB；map_focus_bounds 产出）
var focus_bounds := UNBOUNDED
## 俯角/偏航（度；固定，不随缩放变化——约定 2）
var pitch_deg := DEFAULT_PITCH_DEG
var yaw_deg := DEFAULT_YAW_DEG
## 固定参考平面高度（拖拽锚点与相机注视点共用 y；约定 3）
var plane_y := 0.0
## 格子尺寸（axial↔世界映射透传给 HexMath 的 size）
var hex_size := 1.0


## start_index < 0（默认）= 取档位表中位；构造焦点即钳制（无非法初始态）。
func _init(distances: Array = DEFAULT_ZOOM_DISTANCES, bounds := UNBOUNDED,
		start_focus := Vector2.ZERO, start_index := -1) -> void:
	zoom_distances.append_array(
		distances if distances.size() > 0 else DEFAULT_ZOOM_DISTANCES)
	focus_bounds = bounds
	zoom_index = clampi(
		start_index if start_index >= 0 else zoom_distances.size() / 2,
		0, zoom_distances.size() - 1)
	focus = clamp_focus_xz(start_focus, focus_bounds)

# ---------------- 缩放（离散档位；极值钳制）----------------

## 当前档位的世界距离（焦点→相机）
func distance() -> float:
	return zoom_distances[zoom_index]


## 拉近一档（最近档再拉近不动）；返回钳制后的档位
func zoom_in() -> int:
	zoom_index = maxi(zoom_index - 1, 0)
	return zoom_index


## 拉远一档（最远档再拉远不动）；返回钳制后的档位
func zoom_out() -> int:
	zoom_index = mini(zoom_index + 1, zoom_distances.size() - 1)
	return zoom_index


## 直接设档（越界钳到极值档）；返回钳制后的档位
func set_zoom_index(index: int) -> int:
	zoom_index = clampi(index, 0, zoom_distances.size() - 1)
	return zoom_index

# ---------------- 焦点（钳制 = 边界语义约定 1）----------------

## 设焦点（世界 XZ；钳制后生效并存储）。返回钳制后的焦点。
func set_focus_world(xz: Vector2) -> Vector2:
	focus = clamp_focus_xz(xz, focus_bounds)
	return focus


## 按世界位移平移焦点（钳制）。返回钳制后的焦点。
func pan_world(delta_xz: Vector2) -> Vector2:
	return set_focus_world(focus + delta_xz)


## 焦点落到格子（cell → 世界 XZ，经 T1 全局公式；钳制）
func focus_on_cell(cell: Vector2i) -> Vector2:
	return set_focus_world(cell_focus_xz(cell, hex_size))


## 焦点当前所在格（世界 XZ → axial，经 T1 cube rounding）
func focus_cell() -> Vector2i:
	return focus_to_cell(focus, hex_size)

# ---------------- 纯静态：钳制 / 相机位姿 / 参考平面 ----------------

## 焦点钳制原语：XZ 分量各自 clampf（边界值含端点——「四角焦点可达」的落字）。
static func clamp_focus_xz(xz: Vector2, bounds: Rect2) -> Vector2:
	return Vector2(
		clampf(xz.x, bounds.position.x, bounds.position.x + bounds.size.x),
		clampf(xz.y, bounds.position.y, bounds.position.y + bounds.size.y))


## 相机偏移（焦点 → 相机位置）= (水平后向·cosθ + 上·sinθ)·distance；
## 水平后向由 yaw 定（0 = +z 南）。俯角与 distance 无关（约定 2 的构造保证）。
static func camera_offset(distance: float, pitch_deg: float,
		yaw_deg: float = DEFAULT_YAW_DEG) -> Vector3:
	var p := deg_to_rad(pitch_deg)
	var y := deg_to_rad(yaw_deg)
	var back := Vector3(sin(y), 0.0, cos(y))
	return (back * cos(p) + Vector3.UP * sin(p)) * distance


## 相机世界位置 = 注视点（focus_xz, plane_y）+ camera_offset。
static func camera_position(focus_xz: Vector2, plane_y: float, distance: float,
		pitch_deg: float, yaw_deg: float = DEFAULT_YAW_DEG) -> Vector3:
	var target := Vector3(focus_xz.x, plane_y, focus_xz.y)
	return target + camera_offset(distance, pitch_deg, yaw_deg)


## 拖拽固定参考平面求交（约定 3）：射线与 y = plane_y 水平无限平面 → 命中 XZ；
## 平行（|dir.y| ≈ 0）/ 背向（t ≤ 0，含起点在平面下方再向下）→ null
##（显式失败无静默兜底，调用方按无锚处理）。dir 不要求归一化。
static func drag_plane_xz(ray_origin: Vector3, ray_dir: Vector3,
		plane_y := 0.0) -> Variant:
	if absf(ray_dir.y) < PLANE_PARALLEL_EPS:
		return null
	var t := (plane_y - ray_origin.y) / ray_dir.y
	if t <= 0.0:
		return null
	return Vector2(ray_origin.x + ray_dir.x * t, ray_origin.z + ray_dir.z * t)

# ---------------- 纯静态：地图钳制域 ----------------

## 地图可玩区包围盒（焦点钳制域）：全部格子外沿顶点（HexMath.vertex_xz——T4
## 「接缝顶点从同一全局格心/边参数计算」的同一参数源）AABB，再四边外扩 padding。
## 空图 → 退化 Rect2（零尺寸；调用方保证非空图，setup 侧显式拒绝）。
static func map_focus_bounds(map: MapDataClass, size := 1.0, padding := 0.0) -> Rect2:
	var rect := Rect2()
	var first := true
	for cell in map.cells():
		for i in 6:
			var v: Vector2 = Hex.vertex_xz(cell, i, size)
			if first:
				rect = Rect2(v, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(v)
	return rect.grow(padding)

# ---------------- 纯静态：axial ↔ 世界（view 层相机辅助口径）----------------

## 格心世界 XZ（y 不参与——T1「axial→世界只动 x/z」；唯一参数源 HexMath，本层透传）。
static func cell_focus_xz(cell: Vector2i, size := 1.0) -> Vector2:
	var w := Hex.axial_to_world(cell, size)
	return Vector2(w.x, w.z)


## 世界 XZ → 格（HexMath.world_to_axial：cube rounding 修正最大误差轴；
## y 恒填 0——高程不参与格子换算）。
static func focus_to_cell(xz: Vector2, size := 1.0) -> Vector2i:
	return Hex.world_to_axial(Vector3(xz.x, 0.0, xz.y), size)
