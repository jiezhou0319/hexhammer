## 六边形数学核心（axial 坐标，pointy-top）
## 依据 docs/02 ADR-1：所有游戏逻辑坐标一律走本文件静态函数，禁止直接做算术。
## 参照 redblobgames.com/grids/hexagons 标准实现。
class_name Hex
extends RefCounted

## pointy-top 六邻居方向：E, NE, NW, W, SW, SE（axial dq/dr）
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0),   # E
	Vector2i(1, -1),  # NE
	Vector2i(0, -1),  # NW
	Vector2i(-1, 0),  # W
	Vector2i(-1, 1),  # SW
	Vector2i(0, 1),   # SE
]

## 六边形外接圆半径（世界单位），与瓦片模型尺寸对齐后只改这里
const HEX_SIZE := 1.0


static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(DIRS.map(func(d: Vector2i) -> Vector2i: return cell + d))
	return out


## 轴距离：两格间最少步数
static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	var dy := -dq - dr
	return (absi(dq) + absi(dr) + absi(dy)) / 2


## 以 center 为圆心、半径 radius 的环（radius=0 返回 [center]）
static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius <= 0:
		return [center]
	var out: Array[Vector2i] = []
	var cell := center + DIRS[4] * radius  # 从西南角起步
	for i in 6:
		var dir: Vector2i = DIRS[i]
		for j in radius:
			out.append(cell)
			cell += dir
	return out


## 半径内全部格（含中心），大地图视野/区域效果用
static func spiral(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in radius + 1:
		out.append_array(ring(center, r))
	return out


## axial → 世界坐标（pointy-top）：格中心落点
static func axial_to_world(cell: Vector2i, hex_size: float = HEX_SIZE) -> Vector3:
	var x := hex_size * (sqrt(3.0) * float(cell.x) + sqrt(3.0) / 2.0 * float(cell.y))
	var z := hex_size * 1.5 * float(cell.y)
	return Vector3(x, 0.0, z)


## 世界坐标 → 最近格（cube 取整）
static func world_to_axial(pos: Vector3, hex_size: float = HEX_SIZE) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * pos.x - 1.0 / 3.0 * pos.z) / hex_size
	var r := (2.0 / 3.0 * pos.z) / hex_size
	return cube_round_to_axial(q, r)


static func cube_round_to_axial(qf: float, rf: float) -> Vector2i:
	var xf := qf
	var zf := rf
	var yf := -xf - zf
	var x := roundi(xf)
	var y := roundi(yf)
	var z := roundi(zf)
	var dx := absf(xf - float(x))
	var dy := absf(yf - float(y))
	var dz := absf(zf - float(z))
	if dx > dy and dx > dz:
		x = -y - z
	elif dy > dz:
		y = -x - z
	return Vector2i(x, z)


## 两格间的直线格序列（含端点；cube 空间插值 + 取整）
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	if a == b:
		return [a]
	var n := distance(a, b)
	var out: Array[Vector2i] = []
	for i in n + 1:
		var t := float(i) / float(n)
		var lerp := Vector2(a) * (1.0 - t) + Vector2(b) * t
		out.append(cube_round_to_axial(lerp.x, lerp.y))
	return out


## odd-r offset（战棋地图行列，奇数行右移）↔ axial，仅地图生成与显示时转换
static func oddr_to_axial(col: int, row: int) -> Vector2i:
	@warning_ignore("integer_division")
	var q := col - (row - (row & 1)) / 2
	return Vector2i(q, row)


static func axial_to_oddr(cell: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	var col := cell.x + (cell.y - (cell.y & 1)) / 2
	return Vector2i(col, cell.y)
