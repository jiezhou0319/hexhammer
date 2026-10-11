## world_data.gd — 世界事实层容器 + 邻接边索引（M1a T2 首物；执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §2.5 + 数据合同草案
##   docs/M1a-terrain-data-contract-draft.md §3/§4/§11/§12.3）
## 职责：格子数据（MapData）旁边的**第四伴生文件 `<name>.world.json`** 载体——
##   NeighborLinkData 邻接边表（link_id = (min,max) 格稳定 ID 对）+ 校验器 +
##   序列化（固定键序）。河/路/桥/POI 集合属 T3/T4/T5 逐实体解锁，本版**恒空**
##   （「关闭一个尚未实现能力不产生伪字段」的镜像：没有能力就没有数据——
##   from_dict 对非空未解锁集合显式拒绝，不做半吊子解析）。
## 合同（翻案须先改草案对应节与 tests/test_world_data.gd，不动架构）：
## - 旧图零迁移（§2.2）：伴生文件缺失/为空 → empty()（无河无路无 POI 的合法态），
##   不报错、不重新随机生成——MapData 的 dict 与 SCHEMA_VERSION=1 零改动；
## - **Vector2i（link_id）不得直接交给 JSON.stringify**（引擎 4.7.2 实测坑：落成
##   字符串 "(3, 17)" 不可还原，草案 §2.2）——落盘形状 = to_dict 内显式转 [x, y]
##   两元 int 数组（MapIO.to_jsonable 显式形状转换先例）；from_dict 由数组重建，
##   长度 ≠ 2 / 非整数 / 负分量 → null（无隐式兜底）；
## - classify_edge 保持几何派生现算**不入表**（草案 §4 禁止项维持）；高差分档阈值
##   属构建参数/几何 profile（LandformProfile），不进 MapData 也不进本表；
## - 主键自包含：link_id 即主键；集合唯一性/规范序（link_id 升序）由校验器查；
## - WorldData 零回写 MapData（含 mods——草案 §11 全局项；测试锚定 summary 不变）；
## - 纯数据类：RefCounted、零场景节点、不 preload 任何场景（ADR-2；删 scripts/ui/**
##   后 tests 全绿）。锚点绝对坐标不落盘（§2.3）：边锚 = 两格心连线与共享边交点，
##   由 HexMath 全局参数唯一路径现算。
class_name WorldData
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")

## 数据结构版本（WorldData 独立伴生文件自计数——MapData.SCHEMA_VERSION 不动，§2.2）
const SCHEMA_VERSION := 1

## 一切 id 引用哨兵（负值——TERRAIN_NONE/-1 先例；cell_id 恒非负故不混淆）
const ID_NONE := -1

## link 哨兵（x=min(cell_id)、y=max(cell_id)；负分量 = 哨兵——合法 link 恒 0≤x<y）
const NO_LINK := Vector2i(-1, -1)

## 邻接边对象（草案 §4 + 执行方案 §2.4 重议后口径）：邻接边的**索引面**——回答
## 「这条边上有什么」。link 表只存 road_id / river_reach_id 引用（§2.4：初版不存
## 任何流向字段，与 reach.edges 序零冗余）；不承载地形/高差/连接类型（禁止项）。
class NeighborLinkData:
	extends RefCounted

	## 主键：x = min(两端 cell_id)、y = max(两端 cell_id)，恒 0 ≤ x < y；
	## 两端格须互为界内邻居（WorldData.validate 查——不存在邻格不产生连接）
	var link_id := NO_LINK

	## 本边被哪条道路占用（无向）；ID_NONE = 无路。T4 前恒 ID_NONE（引用不可解析即非法）
	var road_id: int = ID_NONE

	## 本边有河水时所属河段（RiverReachData 主键引用）；ID_NONE = 无河。
	## T3 前恒 ID_NONE（§2.4：终态流向事实 = reach.edges 的序列顺序，link 层零冗余）
	var river_reach_id: int = ID_NONE


## 邻接边表（link_id 升序为规范序——摘要可比较的前提，草案 §2.1）
var links: Array[NeighborLinkData] = []

## 以下五集合 + meta 的实体定义属 T3（河/水体）→ T4（路/桥）→ T5（POI）逐卡解锁
## （草案 §12.4）；本版恒空数组——from_dict 对非空显式拒绝（不产伪字段也不假解析）。
var rivers: Array = []
var water_bodies: Array = []
var roads: Array = []
var crossings: Array = []
var pois: Array = []

## WorldMeta（草案 §10 字段集的占位形状；attempt/repair/first_pass 落码进 WORLD-04）。
## 手工固定图默认口径：seed=0、generator_version=0、rules_version=0（视觉模式）、
## attempt_count=1、repair_count=0、first_pass_valid=true。
var meta: Dictionary = {
	"schema_version": SCHEMA_VERSION,
	"seed": 0,
	"generator_version": 0,
	"rules_version": 0,
	"engine_version": "",
	"config_digest": "",
	"world_digest": "",
	"attempt_count": 1,
	"repair_count": 0,
	"first_pass_valid": true,
}

## 旧图口径：全空集合 + 默认 meta——「缺 .world.json = 无河无路无 POI」的合法态。
static func empty() -> WorldData:
	return new()

## link 规范化：a/b 两端 cell_id → (min, max)；同格 / 任一负值 → NO_LINK（哨兵）。
static func link_id_of(a: int, b: int) -> Vector2i:
	if a == b or a < 0 or b < 0:
		return NO_LINK
	return Vector2i(mini(a, b), maxi(a, b))

# ---------------- 校验器（草案 §11 的 T2 面：link 表 + 全局项）----------------

## 校验入口：""=合法；原因串指向具体 link/约束（最小诊断输出）。T2 面 =
##   ① 规范序（links 按 link_id 升序）；② link_id 唯一且规范（0≤x<y）；
##   ③ 两端格界内且互为邻居（不存在的邻格不产生连接——M1a-T2 边界规则延伸）；
##   ④ road_id / river_reach_id 引用可解析——T2 实体未解锁，非 ID_NONE 即不可解析。
## 零回写 MapData：本函数只读（结构性保证，测试锚定 summary 不变）。
func validate(map: MapDataClass) -> String:
	var prev := NO_LINK
	for i in links.size():
		var lk := links[i]
		var lid := lk.link_id
		if lid.x < 0 or lid.x >= lid.y:
			return "links[%d] link_id 非规范（须 0≤x<y，got %s）" % [i, str(lid)]
		# 严格升序同时覆盖「重复主键」（相等即不升序——错误串两者兼顾）
		if prev != NO_LINK and not _link_less(prev, lid):
			return "links[%d] 破坏规范序（须按 link_id 严格升序——含主键重复；got %s after %s）" \
				% [i, str(lid), str(prev)]
		prev = lid
		if lid.y >= map.cell_count():
			return "links[%d] link_id 指向界外格（%s，图共 %d 格）" % [i, str(lid), map.cell_count()]
		var ca := _cell_of_id(map, lid.x)
		var cb := _cell_of_id(map, lid.y)
		if not map.has_cell(ca) or not map.has_cell(cb) or Hex.dir_between(ca, cb) < 0:
			return "links[%d] 两端格不互为界内邻居（%s：%s / %s）" % [i, str(lid), str(ca), str(cb)]
		if lk.road_id != ID_NONE:
			return "links[%d] road_id=%d 引用不可解析（T4 前道路实体未解锁，恒 ID_NONE）" % [i, lk.road_id]
		if lk.river_reach_id != ID_NONE:
			return "links[%d] river_reach_id=%d 引用不可解析（T3 前河段实体未解锁，恒 ID_NONE）" % [i, lk.river_reach_id]
	return ""

# ---------------- 序列化（固定键序——摘要可比较；Vector2i 显式 [x,y] 转换层）----------------

## to_dict 形状（JSON 落盘经 MapIO.write_world）：
##   {"schema_version": 1, "links": [{"link_id": [x, y], "road_id": int,
##     "river_reach_id": int}, …]（序 = links 数组序，规范序下同主键升序）,
##    "rivers": [], "water_bodies": [], "roads": [], "crossings": [], "pois": [],
##    "meta": {§10 字段集}}——link_id **显式转 [x, y] 数组**（Vector2i 直写
##   JSON.stringify 落成 "(3, 17)" 字符串不可还原，草案 §2.2 实测坑）。
func to_dict() -> Dictionary:
	var out_links: Array = []
	for lk in links:
		out_links.append({
			"link_id": [lk.link_id.x, lk.link_id.y],
			"road_id": lk.road_id,
			"river_reach_id": lk.river_reach_id,
		})
	return {
		"schema_version": SCHEMA_VERSION,
		"links": out_links,
		"rivers": [],
		"water_bodies": [],
		"roads": [],
		"crossings": [],
		"pois": [],
		"meta": meta.duplicate(true),
	}

## 版本不符 / 字段缺失 / link_id 形状非法（长度≠2/非整数/负分量/x≥y）/ 引用非整数 /
## 未解锁集合非空 / meta 非字典 → null（调用方显式判空，无隐式兜底）。
## 兼容 JSON 数值形状（整数以 float 3.0 出现亦可还原——MapData._is_integral_number 同款）。
static func from_dict(data: Dictionary) -> WorldData:
	if not data.has_all(["schema_version", "links", "rivers", "water_bodies",
			"roads", "crossings", "pois", "meta"]):
		return null
	if not _is_int(data["schema_version"]) or int(data["schema_version"]) != SCHEMA_VERSION:
		return null
	if not (data["links"] is Array) or not (data["meta"] is Dictionary):
		return null
	for locked in ["rivers", "water_bodies", "roads", "crossings", "pois"]:
		if not (data[locked] is Array):
			return null
		if not (data[locked] as Array).is_empty():
			return null  # 能力未解锁（T3/T4/T5 逐实体开）——不产伪字段也不假解析
	var out := empty()
	for i in (data["links"] as Array).size():
		var entry: Variant = (data["links"] as Array)[i]
		if not (entry is Dictionary):
			return null
		var d: Dictionary = entry
		if not d.has_all(["link_id", "road_id", "river_reach_id"]):
			return null
		var lid: Variant = _link_id_from(d["link_id"])
		if lid == null:
			return null
		if not _is_int(d["road_id"]) or not _is_int(d["river_reach_id"]):
			return null
		var road_id := int(d["road_id"])
		var reach_id := int(d["river_reach_id"])
		if road_id < ID_NONE or reach_id < ID_NONE:
			return null
		var lk := NeighborLinkData.new()
		lk.link_id = lid
		lk.road_id = road_id
		lk.river_reach_id = reach_id
		out.links.append(lk)
	var m := (data["meta"] as Dictionary)
	for k in ["schema_version", "seed", "generator_version", "rules_version",
			"attempt_count", "repair_count"]:
		if not m.has(k) or not _is_int(m[k]):
			return null
	if not m.has("first_pass_valid") or not (m["first_pass_valid"] is bool):
		return null
	for k in ["engine_version", "config_digest", "world_digest"]:
		if not m.has(k) or not (m[k] is String):
			return null
	# meta 规范化重建：整值字段收敛回 int（JSON 往返整数呈 3.0 形状——_is_int 已验
	# 整值性，此处统一类型，保证 to_dict 往返逐位一致）+ 固定键序（摘要可比较）
	var meta := {
		"schema_version": int(m["schema_version"]),
		"seed": int(m["seed"]),
		"generator_version": int(m["generator_version"]),
		"rules_version": int(m["rules_version"]),
		"engine_version": String(m["engine_version"]),
		"config_digest": String(m["config_digest"]),
		"world_digest": String(m["world_digest"]),
		"attempt_count": int(m["attempt_count"]),
		"repair_count": int(m["repair_count"]),
		"first_pass_valid": bool(m["first_pass_valid"]),
	}
	out.meta = meta
	return out

# ---------------- 内部 ----------------

## cell 稳定 ID → axial 格（行主序反解：col = id % width、row = id / width）。
static func _cell_of_id(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))

## link_id 字典序（x 优先、y 次之——规范序比较器）。
static func _link_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)

## 数值且为有限整值（int，或无小数部分的有限 float——JSON 往返后整数呈 3.0 形状；
## bool 排除——GDScript `is int` 对 bool 为真，MapData 同款纪律）。
static func _is_int(v: Variant) -> bool:
	if v is bool:
		return false
	if v is int:
		return true
	if v is float:
		return is_finite(v) and int(v) == v
	return false

## [x, y] 数组 → Vector2i（显式转换层的还原侧）：非数组 / 长度 ≠ 2 / 元素非整数 /
## 负分量 / x≥y → null。
static func _link_id_from(v: Variant) -> Variant:
	if not (v is Array):
		return null
	var arr := v as Array
	if arr.size() != 2 or not _is_int(arr[0]) or not _is_int(arr[1]):
		return null
	var x := int(arr[0])
	var y := int(arr[1])
	if x < 0 or y < 0 or x >= y:
		return null
	return Vector2i(x, y)
