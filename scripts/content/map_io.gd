## map_io.gd — 地图工件落盘/读取（M1a-T9；docs/04-tasks-m1.md M1a-T9「固定测试图 +
##   失败图落盘保留作回归样例」+ docs/02-architecture.md §4「resources/ ← 数据（…maps…）」）
## 载体口径：**JSON**（MapData.to_dict 的字段集与 schema_version——T2 冻结的
##   M2 MapDef .tres 同字段集；from_dict 兼容 JSON 数值形状（整数呈 3.0 亦可还原），
##   故 JSON 往返零损失，M2 落 MapDef .tres 时同一字段集直接换 Resource 序列化，
##   本类的读写路径即迁移路径）。每张图三个伴生文件：
##   <name>.json（格子表）+ <name>.meta.json（seed/参数/生成器版本/digest/连通性）
##   + <name>.summary.txt（T2 逐格摘要全文，可 diff 的人读面）。
## 固定路径常量 = 工具（tools/generate_map.gd、tools/make_fixed_maps.gd）与
##   tests/test_map_source.gd 共用的唯一口径（改路径 = 三处同改，靠测试锚住）。
## 纯函数：RefCounted、零场景节点（ADR-2）；读写失败显式返回（null/Error，无隐式兜底）。
class_name MapIO
extends RefCounted

const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")

## 固定测试图（手工固定，tools/make_fixed_maps.gd 落盘；沙盒默认加载 → 一键可玩）
const FIXED_MAP_PATH := "res://resources/maps/fixed/playable_60x40.json"
const FIXED_MAP_META_PATH := "res://resources/maps/fixed/playable_60x40.meta.json"

## 随机图常规输出目录（一次性产物，不入测试口径）
const GENERATED_DIR := "res://resources/maps/generated"

## 失败图（断路/孤岛）回归样例目录——**提交入库**，tests/test_map_source.gd 引用；
## tools/generate_map.gd 生成失败图时默认落此（保留作回归样例是任务卡交付项）
const FAILED_FIXTURE_DIR := "res://tests/fixtures/maps/failed"


# ---------------- 地图（格子表） ----------------

## 地图 → <path>.json；目录缺失自动创建。返回 Error（OK = 成功）。
## 注意：写入前经 to_jsonable 转形状——JSON.stringify 会把 PackedByteArray 序列化
## 成字符串 "[1, 1, …]"（4.7.2 实测坑；PackedInt32Array 无此问题，统一转 Array
## 保持一致）。mods 按原样写入（当前恒空字典；M2 MapDef .tres 化后本载体退役）。
static func write_map(map: MapDataClass, path: String) -> int:
	return write_json(to_jsonable(map.to_dict()), path)


## to_dict 字段集 → JSON 可序列化形状（键序 = to_dict 固定序）。
static func to_jsonable(d: Dictionary) -> Dictionary:
	return {
		"schema_version": d["schema_version"],
		"width": d["width"],
		"height": d["height"],
		"terrain": Array(d["terrain"]),
		"elevation": Array(d["elevation"]),
		"passable": Array(d["passable"]),
		"mods": d["mods"],
	}


## <path>.json → MapData；文件缺失/JSON 非法/字段不符 → null（调用方显式判空）。
static func read_map(path: String) -> MapDataClass:
	var data: Variant = read_json(path)
	if not (data is Dictionary):
		return null
	var dict: Dictionary = data
	return MapDataClass.from_dict(dict)


# ---------------- 元数据 / 摘要伴生文件 ----------------

static func write_meta(meta: Dictionary, path: String) -> int:
	return write_json(meta, path)


## 元数据 → Dictionary；文件缺失/解析失败/顶层非 dict → null（Variant 双态，
## 与 MapData.from_dict 同口径——内置 Dictionary 不可空，不能直接标注返回类型）。
static func read_meta(path: String) -> Variant:
	return read_json(path)


## 逐格摘要全文落盘（T2 summary()；同图恒同文——复现验收的可 diff 面）。
static func write_summary(map: MapDataClass, path: String) -> int:
	var dir_err := _ensure_dir(path)
	if dir_err != OK:
		return dir_err
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FAILED
	f.store_string(map.summary())
	return OK

# ---------------- 世界事实层（第四伴生 .world.json，T2 LAND-01 §2.5）----------------

## 地图路径 → 世界伴生文件路径（<name>.json → <name>.world.json——三伴生先例旁的
## 第四件）。固定图常量形态：playable_60x40.world.json。
static func world_path_for(map_path: String) -> String:
	return map_path.trim_suffix(".json") + ".world.json"

## WorldData → <path>.world.json（WorldData.to_dict 已做 Vector2i→[x,y] 显式转换，
## 落盘形状对 JSON 直接可序列化）。返回 Error（OK = 成功）。
static func write_world(world: WorldDataClass, path: String) -> int:
	return write_json(world.to_dict(), path)

## <path>.world.json → WorldData。**文件缺失/为空 → WorldData.empty()**（旧图零
## 迁移：缺伴生 = 无河无路无 POI 的合法态，不报错、不重新随机生成——§2.2；
## 空文件同口径：无数据 ≠ 坏数据，不与解析失败混同）；文件存在但解析失败/
## 字段非法 → null（显式判空，与 read_map 同口径）。
static func read_world(path: String) -> WorldDataClass:
	if not FileAccess.file_exists(path):
		return WorldDataClass.empty()
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		# 空文本不能走 read_json 的 null 双态（会与「解析失败」混同）——合同区分
		# 三态：缺失/空 = 合法空世界，坏 JSON/字段非法 = null（T2 评审修复）
		return WorldDataClass.empty()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	return WorldDataClass.from_dict(parsed)


# ---------------- 通用 JSON ----------------

static func write_json(data: Dictionary, path: String) -> int:
	var dir_err := _ensure_dir(path)
	if dir_err != OK:
		return dir_err
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FAILED
	f.store_string(JSON.stringify(data, "\t"))
	return OK


## 任意 JSON → Dictionary；文件缺失/解析失败/顶层非 dict → null（Variant 双态：
## 内置 Dictionary 不可空——与 MapData.from_dict 的「null=非法」同口径）。
static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return null


## 路径所在目录缺失则创建（res:// 与 user:// 均可；已存在 = OK）。
static func _ensure_dir(path: String) -> int:
	var dir := path.get_base_dir()
	if dir.is_empty() or DirAccess.dir_exists_absolute(dir):
		return OK
	return DirAccess.make_dir_recursive_absolute(dir)
