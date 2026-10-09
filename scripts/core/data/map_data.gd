## map_data.gd — 地图数据层（M1a-T2；docs/04-tasks-m1.md M1a-T2 + docs/02-architecture.md §1/§3/§4 + M1a 实现调研「推荐的最小架构」）
## 约定与边界（与 T1 hex_math.gd 同源；翻案须先改 04 对应验收，不动架构）：
## - 外形 = row/column 矩形（60×40 = 60 列 × 40 行），odd-r offset 作存储坐标系；
##   对外 API 一律 axial（ADR-1：坐标算术必须走 HexMath，本类不自算邻居/边界）。
## - 存储 = 行主序平铺数组（index = row*width+col）；index 即「格子稳定 ID」
##   （T4「共享边由两格稳定 ID 较小者生成 / 共享角以三格 ID 为 key」的比较器即本值）。
## - 遍历顺序固定（唯一口径）：for row in height: for col in width: axial_of(col,row)。
##   summary() 逐格摘要按此序输出——同图（不论写入顺序）逐字节一致（T9 复现验收的载体）。
## - 默认值：新图全格 terrain=0 / elevation=0 / passable=true；0 号地形语义由内容层定义。
## - 高程（int 分层）：值域 = int32 全域（可为负，T9 噪声量化产出负层合法）；越界写入
##   显式拒绝（返回 false、原值不变）——数据层不钳制、更不静默截断，生成器负责量化到值域内。
## - 边界规则（04 M1a-T2 细化）：不存在的邻格不产生任何连接——neighbors_existing 只吐
##   界内格；界外查询契约：is_passable=false（不可通行 = 无连接的结算面）、
##   terrain_at=TERRAIN_NONE、elevation_at=ELEVATION_NONE（哨兵，见各常量注释）。
## - mods 修正扩展位（04 M1a-T2「空字段」/M1b-T4「本期恒 0」）：内部结构 M3 拍板；
##   铁律 = 任何结算、查询、摘要（summary/digest）不得读取本字段——只有序列化原样保存它。
## - schema_version：数据结构版本（字段布局或摘要格式变更时 +1；from_dict 拒绝版本不符）。
##   两名一物：运行时 MapData ↔ M2 落盘 MapDef .tres（04 M1a-T2 / 03 §M2-8、评审 G7）。
##   本任务只冻结字段集与版本约定，to_dict/from_dict 是当下的往返载体，
##   M2 的 MapDef Resource 以同一字段集、同一版本口径落盘（.tres 正式序列化不在本任务）。
## - 纯数据类：RefCounted、零场景节点、不 preload 任何场景/节点（ADR-2；
##   「删 scripts/ui/** 后 tests 全绿」口径下本类与测试均不感知表现层）。
class_name MapData
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")

## 数据结构版本：字段布局或摘要格式变更时 +1；from_dict 拒绝版本不符的数据。
const SCHEMA_VERSION := 1

## 地形 id 哨兵（界外/无效格）。合法地形 id ∈ [0, INT32_MAX]——set_terrain 与 from_dict
## 均拒绝越界值，保证哨兵永不与真实数据混淆。
const TERRAIN_NONE := -1

## 高程哨兵（界外/无效格）= −2^62。合法高程 = int32 值域内的分层等级（可为负），
## set_elevation 与 from_dict 均拒绝越界值——int32 平铺存储永远产生不了本哨兵，
## 界内格值域也进不了哨兵，不会与真实数据混淆。
const ELEVATION_NONE := -4611686018427387904

var width: int = 0   # 列数（odd-r offset col 维度）
var height: int = 0  # 行数

## 修正扩展位：默认空。任何结算/查询/摘要不读它（见类头注「铁律」）；
## 唯一被允许的消费者 = to_dict/from_dict（原样保存）。
var mods: Dictionary = {}

var _terrain: PackedInt32Array    # 地形 id（非负）
var _elevation: PackedInt32Array  # 高程分层（int，可为负）
var _passable: PackedByteArray    # 0/1


func _init(map_width := 0, map_height := 0) -> void:
	width = maxi(map_width, 0)
	height = maxi(map_height, 0)
	var n := width * height
	_terrain.resize(n)
	_elevation.resize(n)
	_passable.resize(n)
	_passable.fill(1)  # 默认全格可通行；不可通行是显式标记（水体/深渊等）


# ---------------- 尺寸 / 外形 ----------------

func cell_count() -> int:
	return width * height


func has_cell(cell: Vector2i) -> bool:
	return Hex.in_bounds(cell, width, height)


## 格子稳定 ID = 行主序存储下标；界外 → -1。
## T4 共享边/共享角归属比较器直接用返回值（04 M1a-T4 细化「稳定 ID」）。
func index_of(cell: Vector2i) -> int:
	var col_row := Hex.offset_of(cell)
	if col_row.x < 0 or col_row.x >= width or col_row.y < 0 or col_row.y >= height:
		return -1
	return col_row.y * width + col_row.x


## 固定遍历顺序（一切依赖顺序的输出的唯一口径，勿另行排序）：
## for row in height: for col in width: axial_of(col,row)——返回 Array[Vector2i]。
func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.resize(width * height)
	var i := 0
	for row in height:
		for col in width:
			out[i] = Hex.axial_of(Vector2i(col, row))
			i += 1
	return out


# ---------------- 邻接 / 外沿边界规则 ----------------

## cell 的 dir 向邻居是否存在（两格皆界内才存在；cell 自身界外 → false）。
func has_neighbor(cell: Vector2i, dir: int) -> bool:
	return has_cell(cell) and has_cell(Hex.neighbor(cell, dir))


## 仅界内邻居，按方向 0~5 固定序返回；界外格返回空数组——不存在的邻格不产生连接。
func neighbors_existing(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not has_cell(cell):
		return out
	for dir in 6:
		var n := Hex.neighbor(cell, dir)
		if has_cell(n):
			out.append(n)
	return out


# ---------------- 逐格数据（axial 存取） ----------------

func terrain_at(cell: Vector2i) -> int:
	var i := index_of(cell)
	return _terrain[i] if i >= 0 else TERRAIN_NONE


func elevation_at(cell: Vector2i) -> int:
	var i := index_of(cell)
	return _elevation[i] if i >= 0 else ELEVATION_NONE


## 界外格恒为 false——「不可通行」即外沿无连接的结算面（M1b 寻路的硬约束由此取值）。
func is_passable(cell: Vector2i) -> bool:
	var i := index_of(cell)
	return i >= 0 and _passable[i] != 0


## 地形 id ∈ [0, INT32_MAX]（负值保留给 TERRAIN_NONE 哨兵；越界 int64 拒绝——int32 落库
## 静默截断即改值）；界外写入同样 → false、不生效。
func set_terrain(cell: Vector2i, terrain_id: int) -> bool:
	if terrain_id < 0 or terrain_id > INT32_MAX:
		return false
	var i := index_of(cell)
	if i < 0:
		return false
	_terrain[i] = terrain_id
	return true


## 高程分层（int，可为负，值域 = int32 全域；越界拒绝——数据层不钳制、不静默截断，
## 量化到值域内由生成器负责）；界外写入 → false、不生效。
## 通行性独立于此（见 set_passable）。
func set_elevation(cell: Vector2i, level: int) -> bool:
	if level < INT32_MIN or level > INT32_MAX:
		return false
	var i := index_of(cell)
	if i < 0:
		return false
	_elevation[i] = level
	return true


## 通行性是独立字段：不随地形/高程自动推导（地形→通行性映射是内容层职责，M2+）。
func set_passable(cell: Vector2i, value: bool) -> bool:
	var i := index_of(cell)
	if i < 0:
		return false
	_passable[i] = 1 if value else 0
	return true


# ---------------- 序列化（M2 MapDef .tres 的字段集与版本口径在此冻结） ----------------

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"width": width,
		"height": height,
		"terrain": _terrain.duplicate(),
		"elevation": _elevation.duplicate(),
		"passable": _passable.duplicate(),
		"mods": mods.duplicate(true),
	}


## 版本不符 / 字段缺失 / 尺寸不匹配 / 元素非法（含超 int32 值域的 int64——落库即截断改值，
## 与小数/NaN 同罪）→ null（调用方显式判空，无隐式兜底）。
## 兼容 JSON 形状的数值（整数以 float 3.0 出现亦可还原，M2 存档管线友好）；
## 多余键忽略（向前兼容由 SCHEMA_VERSION 把关，不靠键白名单收紧）。
static func from_dict(data: Dictionary) -> MapData:
	var required := ["schema_version", "width", "height", "terrain", "elevation", "passable", "mods"]
	if not data.has_all(required):
		return null
	for k in ["schema_version", "width", "height"]:
		if not _is_integral_number(data[k]):
			return null
	if int(data["schema_version"]) != SCHEMA_VERSION:
		return null
	var w := int(data["width"])
	var h := int(data["height"])
	if w < 0 or h < 0:
		return null
	var n := w * h
	if not (data["mods"] is Dictionary):
		return null
	# 显式 Variant 接住「null=非法 / 数组=成功」双态（内置类型不可空，不能直接标注
	# PackedInt32Array）；null 判定后经 as 收窄赋值。勿改回 := ——本引擎把
	# inference_on_variant 警告按错误处理，从 Variant 返回值推断会编译失败。
	var t: Variant = _to_int32s(data["terrain"], n, false)
	var e: Variant = _to_int32s(data["elevation"], n, true)
	var p: Variant = _to_bytes01(data["passable"], n)
	if t == null or e == null or p == null:
		return null
	var m := MapData.new(w, h)
	m._terrain = t as PackedInt32Array
	m._elevation = e as PackedInt32Array
	m._passable = p as PackedByteArray
	m.mods = (data["mods"] as Dictionary).duplicate(true)
	return m


# ---------------- 地图摘要（T9 复现验收的载体） ----------------

## 逐格摘要（可比较）：固定遍历序，格式 =
##   "hexmap|v<SCHEMA_VERSION>|<宽>x<高>" + 逐格 ";q,r:地形/高程/通行"（通行 1/0）。
## 同一张图不论写入顺序，摘要逐字节一致；任意一格核心数据变更即改变。
## 刻意不含 mods——「扩展位不参与任何结算（含可比较输出）」的可执行表达；
## mods 的保存走 to_dict，不走摘要。
func summary() -> String:
	var parts := PackedStringArray()
	parts.append("hexmap|v%d|%dx%d" % [SCHEMA_VERSION, width, height])
	for cell in cells():
		var p := 1 if is_passable(cell) else 0
		parts.append("%d,%d:%d/%d/%d" % [cell.x, cell.y, terrain_at(cell), elevation_at(cell), p])
	return ";".join(parts)


## 短摘要 = summary() 的 SHA-256 hex（64 字符）：同图相等、核心数据不同则不等。
func digest() -> String:
	return summary().sha256_text()


# ---------------- 内部：序列化元素校验 ----------------

## 数值且为有限整值：int，或无小数部分的有限 float（JSON 往返后整数呈 3.0 形状）。
## bool 在 GDScript 中 `is int` 为真，须先排除；小数/NaN/inf/非数值一律 false
## ——非法元素显式拒绝，不做静默截断（无隐式兜底契约的元素面）。
static func _is_integral_number(v: Variant) -> bool:
	if v is bool:
		return false
	if v is int:
		return true
	if v is float:
		return is_finite(v) and int(v) == v
	return false


## 数值序列 → PackedInt32Array；类型/尺寸非法、元素超 int32 值域（落库即截断改值）
## 或（allow_negative=false 时）出现负值 → null。
static func _to_int32s(v: Variant, expected: int, allow_negative: bool) -> Variant:
	var out := PackedInt32Array()
	if v is PackedInt32Array:
		out = v
	elif v is Array:
		for x in v:
			if not _is_integral_number(x):
				return null
			var xi := int(x)
			if xi < INT32_MIN or xi > INT32_MAX:
				return null
			out.append(xi)
	else:
		return null
	if out.size() != expected:
		return null
	if not allow_negative:
		for x in out:
			if x < 0:
				return null
	return out


## 通行位序列（每元素必须 0/1）→ PackedByteArray；类型/尺寸/值非法 → null。
static func _to_bytes01(v: Variant, expected: int) -> Variant:
	var out := PackedByteArray()
	if v is PackedByteArray:
		out = v
	elif v is Array:
		for x in v:
			if not _is_integral_number(x):
				return null
			var b := int(x)
			if b != 0 and b != 1:
				return null
			out.append(b)
	else:
		return null
	if out.size() != expected:
		return null
	for b in out:
		if b > 1:
			return null
	return out
