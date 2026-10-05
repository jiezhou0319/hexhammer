## 六边形数学工具（尖顶 pointy-top，axial 坐标 q/r）。
## 全项目统一用 Vector2i(q, r) 表示一个格子，纯静态函数、零依赖，可单测。
class_name Hex
extends RefCounted

## 尖顶六边形的 6 个邻居方向：E, NE, NW, W, SW, SE
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]

## axial -> 像素中心（pointy-top）。size 为外接圆半径。
static func to_pixel(hex: Vector2i, size: float) -> Vector2:
	var x := size * sqrt(3.0) * (float(hex.x) + float(hex.y) / 2.0)
	var y := size * 1.5 * float(hex.y)
	return Vector2(x, y)

## 像素 -> axial（cube rounding 取整）
static func from_pixel(p: Vector2, size: float) -> Vector2i:
	var qf := (sqrt(3.0) / 3.0 * p.x - 1.0 / 3.0 * p.y) / size
	var rf := (2.0 / 3.0 * p.y) / size
	return _cube_round(qf, rf)

static func _cube_round(qf: float, rf: float) -> Vector2i:
	var sf := -qf - rf
	var q := roundi(qf)
	var r := roundi(rf)
	var s := roundi(sf)
	var dq := absf(q - qf)
	var dr := absf(r - rf)
	var ds := absf(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(q, r)

## 六格距离（战锤里的"寸"就映射到这个）
static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := absi(a.x - b.x)
	var dr := absi(a.y - b.y)
	return (dq + absi(a.x + a.y - b.x - b.y) + dr) / 2

static func neighbors(hex: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRECTIONS:
		out.append(hex + d)
	return out

static func are_neighbors(a: Vector2i, b: Vector2i) -> bool:
	return distance(a, b) == 1

## offset(odd-r，奇数行右移) -> axial，用于按行列生成矩形大地图
static func offset_to_axial(col: int, row: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(col - (row - (row & 1)) / 2, row)

## axial -> offset(odd-r)
static func axial_to_offset(hex: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(hex.x + (hex.y - (hex.y & 1)) / 2, hex.y)

## 尖顶六边形第 i 个顶点（绘制用）
static func corner(center: Vector2, size: float, i: int) -> Vector2:
	var a := deg_to_rad(60.0 * i - 30.0)
	return center + Vector2(cos(a), sin(a)) * size
