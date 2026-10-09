## hex_math.gd — 六边形数学（M1a-T1，docs/04 M1a + M1a 实现调研）
## 约定（2026-10-09 拍板；翻案须明说并回改 04 对应测试用例，不动架构）：
## - pointy-top、XZ 地面 + Y 高程：+x=东、+z=南、+y=上；axial→世界只动 x/z，
##   y 由高程层叠加（本层透传，不参与格子换算）。
## - axial (q, r) 存 Vector2i；cube 第三轴 s = −q−r 一律现算、不存储。
## - 方向编号 0~5 写死（Red Blob pointy-top 顺序）：
##     0=东(+1,0)  1=东北(+1,−1)  2=西北(0,−1)  3=西(−1,0)  4=西南(−1,+1)  5=东南(0,+1)
##   反向 = (i+3)%6；六方向向量总和为零。
##   方向 i 的格心连线世界角 = −60°·i（atan2(z,x)；方向表在 XZ 平面按数学负向排布）。
## - 外形 = row/column 矩形：odd-r offset（奇数行向 +x 偏半格）作存储/边界坐标系；
##   内部算法一律 axial，进出存储时显式转换（offset_of / axial_of）。
## - 世界映射（size = 外接圆半径；格心间距 √3·size；内切圆半径 √3/2·size）：
##     x = size·(√3·q + √3/2·r)    z = size·(3/2)·r
## - 顶点 i 角度 = 30° − 60°·i（atan2(z,x) 口径）：顶点 2 在正北、顶点 5 在正南
##   （pointy 沿 ±z、东西为平边）；顶点 i 与 i+1 的连线 = 方向 i 的边界平边
##   （边 i 中点方向 = −60°·i = 方向 i 的格心方向 —— T4 边带几何据此展开）。
## - 纯静态函数、零场景节点依赖（ADR-2；删 scripts/ui/** 不影响本文件与测试）。
class_name HexMath
extends RefCounted

static var SQRT3 := sqrt(3.0)  # 外接圆半径口径下的格心间距系数

## 方向步向量（写死约定，勿改序——改动 = 翻案 04 微决策，须同步改测试）
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0),   # 0 东
	Vector2i(1, -1),  # 1 东北（−z = 北）
	Vector2i(0, -1),  # 2 西北
	Vector2i(-1, 0),  # 3 西
	Vector2i(-1, 1),  # 4 西南
	Vector2i(0, 1),   # 5 东南（+z = 南）
]

# ---------------- 方向 ----------------

static func dir_step(dir: int) -> Vector2i:
	return DIRS[wrapi(dir, 0, 6)]

static func opposite_dir(dir: int) -> int:
	return (dir + 3) % 6

## 方向 i 的格心连线角度（atan2(z,x)：0=东；方向表按数学负向排布，故为 −60°·i）
static func dir_angle_rad(dir: int) -> float:
	return deg_to_rad(-60.0 * float(wrapi(dir, 0, 6)))

## 方向 i 在世界 XZ 平面的单位向量（朝向/边法向用）
static func dir_unit_world(dir: int) -> Vector3:
	var a := dir_angle_rad(dir)
	return Vector3(cos(a), 0.0, sin(a))


## 方向 i 的边界平边切向（世界 XZ 单位向量；M1a-T8 侧面 UV 的 u 轴参数源）：
## 边 i = 顶点 i 与 i+1 的连线（中点朝方向 i），沿本切向展开。
## 口径写死 = dir_unit_world(i) 绕 +Y 旋转 90°（(x,z) → (−z,x)）：方向 0（东）的
## 边切向 = +z（南）。翻案须同步改 tests/test_hex_terrain_materials.gd 的侧面 UV 锚。
static func edge_tangent_world(dir: int) -> Vector3:
	var u := dir_unit_world(dir)
	return Vector3(-u.z, 0.0, u.x)

# ---------------- 邻居 ----------------

static func neighbor(cell: Vector2i, dir: int) -> Vector2i:
	return cell + dir_step(dir)

static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.resize(6)
	for i in 6:
		out[i] = cell + DIRS[i]
	return out

## a→b 的方向编号；非相邻（含自身）返回 -1（朝向、边归属两用）
static func dir_between(a: Vector2i, b: Vector2i) -> int:
	var d := b - a
	for i in 6:
		if DIRS[i] == d:
			return i
	return -1

# ---------------- 距离（cube 公式，s 现算） ----------------

static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := absi(a.x - b.x)
	var dr := absi(a.y - b.y)
	var ds := absi((a.x + a.y) - (b.x + b.y))  # s = −q−r，差取反不变号
	return (dq + dr + ds) / 2

static func to_cube(cell: Vector2i) -> Vector3i:
	return Vector3i(cell.x, cell.y, -cell.x - cell.y)

static func cube_distance(a: Vector3i, b: Vector3i) -> int:
	return (absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)) / 2

# ---------------- 矩形地图（odd-r offset：col/row 存储） ----------------

## axial → odd-r offset (col, row)；奇数行向 +x 偏半格。
## (r − (r&1))/2 == floor(r/2)，对负数同样成立（GDScript 负数 &1 与补码语义一致）。
static func offset_of(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x + (cell.y - (cell.y & 1)) / 2, cell.y)

static func axial_of(col_row: Vector2i) -> Vector2i:
	var row := col_row.y
	return Vector2i(col_row.x - (row - (row & 1)) / 2, row)

## 矩形边界判定：width=列数、height=行数（60×40 = 60 列 × 40 行）。
## 不存在的邻格即界外——边界规则由调用方据此拒绝悬空连接（04 M1a-T2 细化）。
static func in_bounds(cell: Vector2i, width: int, height: int) -> bool:
	var col_row := offset_of(cell)
	return col_row.x >= 0 and col_row.x < width and col_row.y >= 0 and col_row.y < height

# ---------------- axial ↔ 世界（XZ 地面，y 透传） ----------------

## 格心世界坐标（y 由高程层给定，默认 0）
static func axial_to_world(cell: Vector2i, size := 1.0, y := 0.0) -> Vector3:
	var q := float(cell.x)
	var r := float(cell.y)
	return Vector3(
		size * (SQRT3 * q + SQRT3 * 0.5 * r),
		y,
		size * 1.5 * r,
	)

## 世界点 → 浮点 axial（未取整）
static func world_to_axial_f(world: Vector3, size := 1.0) -> Vector2:
	var x := world.x / size
	var z := world.z / size
	return Vector2(SQRT3 / 3.0 * x - z / 3.0, 2.0 / 3.0 * z)

## 世界点 → 格子（cube rounding，见 round_axial）
static func world_to_axial(world: Vector3, size := 1.0) -> Vector2i:
	return round_axial(world_to_axial_f(world, size))

## cube rounding（Red Blob 口径）：q/r/s 三轴各自 round 后修正误差最大轴，
## 保证 q+r+s=0。严禁只对 q、r 两轴各自四舍五入——会得到非法 cube 或错格
## （反例见 tests/test_hex_math.gd: test_round_axial_fixes_max_error_axis）。
static func round_axial(f: Vector2) -> Vector2i:
	var rq := int(round(f.x))
	var rr := int(round(f.y))
	var rs := int(round(-f.x - f.y))  # s 现算
	var dq := absf(f.x - float(rq))
	var dr := absf(f.y - float(rr))
	var ds := absf(-f.x - f.y - float(rs))
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	else:
		rs = -rq - rr
	return Vector2i(rq, rr)

# ---------------- 顶点（pointy-top：南北尖、东西平边） ----------------

## 格子顶点 i 的世界 XZ（Vector2 的 y 分量 = 世界 z）；i 越界按 6 取模。
## 顶点角 = 30° − 60°·i（顶点 2 正北、顶点 5 正南，pointy 沿 ±z）；
## 顶点距格心 = size（外接圆半径）；相邻顶点距 = size（边长 = 外接圆半径）；
## 顶点 i 与 i+1 连成方向 i 的边界平边（中点方向 = −60°·i）。
static func vertex_xz(cell: Vector2i, i: int, size := 1.0) -> Vector2:
	var center := axial_to_world(cell, size)
	var a := deg_to_rad(30.0 - 60.0 * float(wrapi(i, 0, 6)))
	return Vector2(center.x + size * cos(a), center.z + size * sin(a))

## 顶点 i 的世界坐标（y 由高程层给定，默认 0）
static func cell_vertex(cell: Vector2i, i: int, size := 1.0, y := 0.0) -> Vector3:
	var v := vertex_xz(cell, i, size)
	return Vector3(v.x, y, v.y)

# ---------------- 高程连接几何参数（M1a-T4；全局唯一参数源） ----------------

## 内顶点（solid corner，Catlike 口径）：顶点 i 向格心缩进 solid_factor ∈ (0,1)——
## 六个内顶点围成"内六边形"= 可站立顶面（微决策 2：棋子站格心内顶面、高亮只盖内顶面），
## 外圈留作连接带。T4 全部几何（顶面/边带/角落）顶点从本函数与 bridge_xz 组合，
## y 由高程层给定（= elevation × elevation_step，由构建器现算，本层不管高程）。
static func inner_vertex(cell: Vector2i, i: int, size := 1.0, solid_factor := 0.8, y := 0.0) -> Vector3:
	var center := axial_to_world(cell, size)
	var v := vertex_xz(cell, wrapi(i, 0, 6), size)
	return Vector3(
		center.x + (v.x - center.x) * solid_factor,
		y,
		center.z + (v.y - center.z) * solid_factor,
	)


## 边桥向量（bridge）：cell 的方向 dir 内边 → 邻格对应内边的位移 = 格心位移 × (1−solid_factor)
##（推导：B.inner_j = B_c + solid·(V−B_c)、A.inner_d = A_c + solid·(V−A_c)、V = 共享外顶点
##   ⇒ B.inner_j − A.inner_d = (B_c−A_c)·(1−solid)——恰好横跨两内六边形之间的连接带）。
## y 恒 0（高程差由边带两端各自 y 表达，不进 bridge）。从两个全局格心坐标相减现算：
## T4「接缝顶点从同一全局格心/边参数计算，不在两个 chunk 内各自扰动」的参数源
## （边带/角落顶点 = 内顶点 + bridge，全图唯一计算路径）。
## 注意：Catlike 原教实现是"每格各画半条桥、外沿共享边处对接"；本作按任务卡归属规则
## 改为"整条边带由稳定 ID 较小者一次生成"，故桥向量取全程（×blend 而非 ×blend/2）。
static func bridge_xz(cell: Vector2i, dir: int, size := 1.0, solid_factor := 0.8) -> Vector2:
	var a := axial_to_world(cell, size)
	var b := axial_to_world(neighbor(cell, wrapi(dir, 0, 6)), size)
	return Vector2((b.x - a.x) * (1.0 - solid_factor), (b.z - a.z) * (1.0 - solid_factor))
