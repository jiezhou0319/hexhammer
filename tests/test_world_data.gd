## test_world_data.gd — T2 LAND-01 §2.5 四件单测（WorldData 容器 + NeighborLinkData
##   + 校验器 + 序列化；执行方案 §2.5 / §0 铁律 1，数据合同草案 §3/§4/§11/§12.3）
## 覆盖锚（§2.5 原文逐条）：
##   - 序列化往返 + **Vector2i 显式 [x,y] 转换层**（§2.2 实测坑：直写 JSON.stringify
##     落成 "(3, 17)" 字符串不可还原——测试断言落盘 JSON 文本不含该形状且往返无损）；
##   - 旧图零迁移：缺 .world.json → empty() 合法（无河无路无 POI 的合法态）；
##   - NeighborLinkData：link_id=(min,max) 规范化、两端互为界内邻居校验、
##     主键唯一/规范序、引用可解析（T2 实体未解锁 → 非 ID_NONE 即非法）；
##   - 零回写 MapData（草案 §11 全局项：validate/to_dict 前后 summary/digest/mods
##     逐字节不变）；
##   - 未解锁集合（rivers/…）恒空且 from_dict 拒绝非空（不产伪字段也不假解析）。
## oracle 原则：期望邻接关系由 MapData/HexMath 原语独立推导（index_of / dir_between /
##   axial_of），不复制 WorldData 内部比较器；JSON 往返走真实文件（user:// 临时件）。
extends "res://tests/test_case.gd"

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapIO := preload("res://scripts/content/map_io.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")

## 测试图：3×2 = 6 格（index_of 0..5；含跨行邻居——odd-r 偏移真实口径）
const MAP_W := 3
const MAP_H := 2

# ================= link_id 规范化 =================

func test_link_id_of_canonical_min_max() -> void:
	expect_eq(WorldDataClass.link_id_of(5, 2), Vector2i(2, 5), "(5,2) → (min,max) = (2,5)")
	expect_eq(WorldDataClass.link_id_of(2, 5), Vector2i(2, 5), "(2,5) 原序不变")
	expect_eq(WorldDataClass.link_id_of(0, 0), WorldDataClass.NO_LINK, "同格 → NO_LINK（自身无邻接）")
	expect_eq(WorldDataClass.link_id_of(-1, 3), WorldDataClass.NO_LINK, "负 cell_id → NO_LINK（哨兵）")
	expect_eq(WorldDataClass.link_id_of(3, -1), WorldDataClass.NO_LINK, "负 cell_id（反序）→ NO_LINK")

# ================= 校验器：邻接 / 界内 / 规范序 / 引用 =================

## 相邻对样本（axial 邻接由 Hex.dir_between 独立核对，不复制 WorldData 判定）
func _sample_map() -> MapDataClass:
	return MapDataClass.new(MAP_W, MAP_H)

func _adjacent_pair_ids(map: MapDataClass) -> Array:
	for a in map.cells():
		for b in map.cells():
			if a != b and Hex.dir_between(a, b) >= 0:
				return [map.index_of(a), map.index_of(b)]
	return []

func test_validate_accepts_mutual_neighbor_links() -> void:
	var map := _sample_map()
	var pair := _adjacent_pair_ids(map)
	expect(pair.size() == 2, "样本图必含相邻对")
	var w := WorldDataClass.empty()
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = WorldDataClass.link_id_of(pair[0], pair[1])
	w.links.append(lk)
	expect_eq(w.validate(map), "", "互为界内邻居的 link 合法")

func test_validate_rejects_non_neighbor_and_out_of_map() -> void:
	var map := _sample_map()
	# 非邻居对：0 与 5（3×2 图中 (0,0) 与 (2,1) 不相邻——由 dir_between 独立验证前提）
	var a := Hex.axial_of(Vector2i(0, 0))
	var b := Hex.axial_of(Vector2i(2, 1))
	expect(Hex.dir_between(a, b) < 0, "构造前提：两格不互为邻居")
	var w := WorldDataClass.empty()
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = WorldDataClass.link_id_of(map.index_of(a), map.index_of(b))
	w.links.append(lk)
	expect(w.validate(map) != "", "非邻居对的 link 非法")

func test_validate_rejects_out_of_map_id() -> void:
	var map := _sample_map()
	var w := WorldDataClass.empty()
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = Vector2i(0, map.cell_count())  # 界外格 id
	w.links.append(lk)
	expect(w.validate(map) != "", "界外格 id 的 link 非法（不存在邻格不产生连接）")

func test_validate_rejects_duplicate_and_unsorted() -> void:
	var map := _sample_map()
	var pair := _adjacent_pair_ids(map)
	# 重复主键
	var w1 := WorldDataClass.empty()
	for i in 2:
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = WorldDataClass.link_id_of(pair[0], pair[1])
		w1.links.append(lk)
	expect(w1.validate(map) != "", "重复 link_id 非法（主键唯一）")
	# 非规范序：取图内两条合法 link，按降序排列（各自单独合法，整体破序）
	var ids := _two_link_ids_descending(map)
	expect(ids.size() == 4, "构造前提：图内存在两条可降序排列的合法 link")
	if ids.size() == 4:
		var w2 := WorldDataClass.empty()
		for i in 2:
			var lk2 := WorldDataClass.NeighborLinkData.new()
			lk2.link_id = Vector2i(ids[i * 2], ids[i * 2 + 1])
			w2.links.append(lk2)
		expect(w2.validate(map) != "", "降序 links 非法（规范序 = link_id 升序）")
		# 对照：同两条 link 升序排列 → 合法（错误归因于序而非内容）
		var w3 := WorldDataClass.empty()
		for i in 2:
			var lk3 := WorldDataClass.NeighborLinkData.new()
			lk3.link_id = Vector2i(ids[(1 - i) * 2], ids[(1 - i) * 2 + 1])
			w3.links.append(lk3)
		expect_eq(w3.validate(map), "", "同两条 link 升序 → 合法（破序才是非法原因）")

## 图内两条合法 link 的 link_id，返回降序 [大.x, 大.y, 小.x, 小.y]（各自邻接由
## Hex.dir_between 独立核对）。
func _two_link_ids_descending(map: MapDataClass) -> Array:
	var lids: Array = []
	for a in map.cells():
		for b in map.cells():
			if a == b or Hex.dir_between(a, b) < 0:
				continue
			var lid := WorldDataClass.link_id_of(map.index_of(a), map.index_of(b))
			if not lids.has(lid):
				lids.append(lid)
	if lids.size() < 2:
		return []
	lids.sort()  # 升序（Vector2i 字典序）；取末两位降序排列
	var hi: Vector2i = lids[lids.size() - 1]
	var lo: Vector2i = lids[lids.size() - 2]
	return [hi.x, hi.y, lo.x, lo.y]

func test_validate_rejects_unresolved_references() -> void:
	var map := _sample_map()
	var pair := _adjacent_pair_ids(map)
	var w := WorldDataClass.empty()
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = WorldDataClass.link_id_of(pair[0], pair[1])
	lk.road_id = 7
	w.links.append(lk)
	var msg := w.validate(map)
	expect(msg != "", "T2 道路实体未解锁：road_id≠ID_NONE 非法（引用不可解析）")
	expect(String(msg).contains("road_id"), "错误串指向具体字段（最小诊断输出）")
	lk.road_id = WorldDataClass.ID_NONE
	lk.river_reach_id = 3
	expect(w.validate(map) != "", "T3 河段实体未解锁：river_reach_id≠ID_NONE 非法")

# ================= 序列化：Vector2i 显式 [x,y] 转换层 + JSON 往返 =================

func test_to_dict_link_id_is_explicit_xy_array() -> void:
	var w := WorldDataClass.empty()
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = Vector2i(3, 17)
	w.links.append(lk)
	var d := w.to_dict()
	var entry: Dictionary = d["links"][0]
	expect(entry["link_id"] is Array, "link_id 落盘形状 = 数组（非 Vector2i 直写）")
	expect_eq((entry["link_id"] as Array).size(), 2, "数组长度 2")
	expect_eq(entry["link_id"], [3, 17], "形状 = [x, y] 显式转换层（§2.2）")
	var text := JSON.stringify(d)
	expect(not text.contains("(3, 17)"), "JSON 文本不得含 \"(3, 17)\" 字符串形状（引擎实测坑）")
	# 数组形状（Godot JSON 紧凑/缩进两种间距形态都认——不锚排版细节）
	expect(text.contains("[3,17]") or text.contains("[3, 17]"),
		"JSON 文本含 [3,17] 数组形状（显式 [x,y] 转换层落盘）")

func test_json_file_roundtrip_preserves_links() -> void:
	var map := _sample_map()
	var w := WorldDataClass.empty()
	var pair := _adjacent_pair_ids(map)
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = WorldDataClass.link_id_of(pair[0], pair[1])
	w.links.append(lk)
	var path := "user://test_world_roundtrip.world.json"
	expect_eq(MapIO.write_world(w, path), OK, "世界伴生文件写入成功")
	var back: Variant = MapIO.read_world(path)
	expect(back is WorldDataClass, "读回为 WorldData（JSON 往返无损）")
	if back is WorldDataClass:
		var b: WorldDataClass = back
		expect_eq(b.to_dict(), w.to_dict(), "往返 to_dict 逐位一致（含 meta/空集合）")
		expect_eq(b.links.size(), 1, "link 数保持")
		expect_eq(b.links[0].link_id, lk.link_id, "link_id 重建一致")
		expect_eq(b.validate(map), "", "读回世界仍过校验（保存→重载同验）")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_from_dict_rejects_bad_shapes() -> void:
	var good := WorldDataClass.empty().to_dict()
	# 版本不符
	var v2 := good.duplicate(true)
	v2["schema_version"] = 2
	expect(WorldDataClass.from_dict(v2) == null, "schema_version 不符 → null")
	# link_id 形状：长度 ≠ 2 / 非整数 / 负分量 / x≥y
	for bad_id in [[3], [3, 17, 5], [3.5, 17], [-1, 17], [17, 3]]:
		var d := good.duplicate(true)
		(d["links"] as Array).append({
			"link_id": bad_id, "road_id": WorldDataClass.ID_NONE,
			"river_reach_id": WorldDataClass.ID_NONE})
		expect(WorldDataClass.from_dict(d) == null,
			"link_id %s 非法形状 → null（无隐式兜底）" % str(bad_id))
	# 字段缺失
	var missing := good.duplicate(true)
	(missing["links"] as Array).append({"link_id": [3, 17]})
	expect(WorldDataClass.from_dict(missing) == null, "link 条目缺字段 → null")
	# JSON float 形状整数可还原（3.0 → 3）
	var floated := good.duplicate(true)
	(floated["links"] as Array).append({
		"link_id": [3.0, 17.0], "road_id": WorldDataClass.ID_NONE,
		"river_reach_id": WorldDataClass.ID_NONE})
	var parsed: Variant = WorldDataClass.from_dict(floated)
	expect(parsed is WorldDataClass, "JSON 数值形状（3.0）可还原（MapData 同款兼容）")

func test_from_dict_rejects_unlocked_collections_and_bad_meta() -> void:
	var good := WorldDataClass.empty().to_dict()
	var rivers := good.duplicate(true)
	rivers["rivers"] = [{"anything": 1}]
	expect(WorldDataClass.from_dict(rivers) == null,
		"rivers 非空 → null（T3 前未解锁——不产伪字段也不假解析）")
	var meta_bad := good.duplicate(true)
	(meta_bad["meta"] as Dictionary)["seed"] = "seven"
	expect(WorldDataClass.from_dict(meta_bad) == null, "meta.seed 非整数 → null")
	var meta_missing := good.duplicate(true)
	(meta_missing["meta"] as Dictionary).erase("attempt_count")
	expect(WorldDataClass.from_dict(meta_missing) == null, "meta 缺 §10 字段 → null")

# ================= 旧图零迁移 + 零回写 =================

func test_missing_world_file_returns_empty_legal() -> void:
	var path := "user://definitely_missing_7f3a.world.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var w: Variant = MapIO.read_world(path)
	expect(w is WorldDataClass, "缺伴生文件 → WorldData.empty()（不报错、不重新随机生成）")
	if w is WorldDataClass:
		var e: WorldDataClass = w
		expect_eq(e.to_dict(), WorldDataClass.empty().to_dict(), "缺文件 = empty() 同形状")
		expect_eq(e.links.size(), 0, "无 link（无河无路无 POI 的合法态——§2.2）")
		expect_eq(e.validate(_sample_map()), "", "empty() 对任意图合法")

func test_empty_world_file_returns_empty_legal() -> void:
	# 头注合同「文件缺失/为空 → empty()」的空文件分支（T2 评审修复：此前空文本
	# 经 read_json 返回 null，注释与行为不符）。坏 JSON 仍 null（无数据 ≠ 坏数据，
	# 两分支不得混同——见下）
	var path := "user://test_empty_world_5c1.world.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	expect(f != null, "空世界文件可创建（测试前置）")
	if f == null:
		return
	f.close()
	var w: Variant = MapIO.read_world(path)
	expect(w is WorldDataClass, "空伴生文件 → WorldData.empty()（无数据 ≠ 坏数据）")
	if w is WorldDataClass:
		expect_eq((w as WorldDataClass).to_dict(), WorldDataClass.empty().to_dict(),
			"空文件 = empty() 同形状")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var bad := "user://test_bad_world_5c1.world.json"
	var fb := FileAccess.open(bad, FileAccess.WRITE)
	if fb != null:
		fb.store_string("{not json")
		fb.close()
	expect(MapIO.read_world(bad) == null, "坏 JSON → null（解析失败不冒充空世界）")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad))

func test_world_data_zero_writeback_to_map() -> void:
	var map := _sample_map()
	var before_summary := map.summary()
	var before_digest := map.digest()
	var before_dict := map.to_dict()
	var w := WorldDataClass.empty()
	var pair := _adjacent_pair_ids(map)
	var lk := WorldDataClass.NeighborLinkData.new()
	lk.link_id = WorldDataClass.link_id_of(pair[0], pair[1])
	w.links.append(lk)
	var msg := w.validate(map)  # 只读校验（结构性保证——本测试锚定其行为面）
	var _ignored := w.to_dict()
	expect_eq(map.summary(), before_summary, "validate/to_dict 后 summary 逐字节不变（零回写）")
	expect_eq(map.digest(), before_digest, "digest 不变")
	expect_eq(map.to_dict(), before_dict, "to_dict 不变（含 mods——WorldData 永不写入）")
	expect_eq(map.mods.size(), 0, "mods 保持空（草案 §4/mods 铁律）")
