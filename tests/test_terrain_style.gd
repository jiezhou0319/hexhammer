## test_terrain_style.gd — M1a+ BLEND-03 单测（纹理可替换，不改世界事实）
## 覆盖 docs/04-tasks-m1.md §M1a+ BLEND-03 验收（Given/When/Then）的 headless 锚：
##   Given = 同一张图（同 seed 两次生成，summary 逐字节一致的 Given 守卫）+ 两套
##   style .tres（SLOTS 默认色块 / BLEND 混合过渡——TerrainStyle 资源载体，检查器可换）；
##   When = 换 style 构建（style.inputs_for → build_map / build_map_blend 同一挂载面）；
##   Then = ① MapData.summary() 逐字节一致（含 mods/通行性零变化——to_dict 往返对账）；
##   ② mesh ARRAY_INDEX 与 face 表（faces 元数据 + Picking.chunk_face_table/碰撞汤）
##   逐位一致；③ MapConnectivity.check 结果一致；④ 材质实例确不同（SLOTS 逐地形
##   库实例 ≥2 种、全不开顶点色；BLEND 单一共享导管材质、开顶点色、与 SLOTS 材质
##   无同一实例）+ 渲染数据差异可锚（blend 有逐顶点 COLOR 且跨界边带端点异色、
##   SLOTS 无 COLOR 通道）。
## oracle 原则：逻辑摘要/连通性期望全部由 MapData/MapConnectivity 独立产出对账，
##   不复制 style/builder 实现；同图由 MapGenerator 同 seed 双实例锚定（生成器
##   确定性是 test_map_source 的锚，这里只做 Given 守卫）；材质「效果不同」在
##   headless 锚材质实例与顶点色通道（像素级差异 = 沙盒目检面，GATE-02 范畴）。
## 色比较口径（沿用 test_hex_terrain_blend.gd，2026-10-10 实测）：mesh 顶点色按
##   8-bit 归一化存储 → 与色板纯色比较用 1/255 容差； Dictionary/Array/Packed*
##   逐位比较用 expect_eq（值语义深比较）。
extends "res://tests/test_case.gd"

const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const Lib := preload("res://scripts/core/data/terrain_material_library.gd")
const StyleClass := preload("res://scripts/core/data/terrain_style.gd")
const Gen := preload("res://scripts/content/map_generator.gd")
const ParamsClass := preload("res://scripts/content/map_gen_params.gd")
const Conn := preload("res://scripts/content/map_connectivity.gd")
const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
const Blend := preload("res://addons/hexhammer/hex_terrain_blend.gd")
const Picking := preload("res://addons/hexhammer/hex_picking.gd")

## 固定图源（2026-10-10 扫描实证：seed 7301 / 12×8 = 6 种地形、76/96 可通行
## （含水=不可通行格）、连通 ok 单分量——有水域有多地形，可达性检查有实质内容）
const MAP_SEED := 7301
const MAP_W := 12
const MAP_H := 8
## 跨 chunk 口径（12×8 / 5×3 → 8 块；不变量在多块下成立才有意义）
const CHUNK_COLS := 5
const CHUNK_ROWS := 3

# ================= style 资源载体（.tres 两套 + 代码默认对账） =================

func test_style_tres_defaults_loaded_and_anchored() -> void:
	var slots: Variant = StyleClass.load_default_slots()
	expect(slots is StyleClass, "SLOTS 默认 .tres 可载入（%s）" % StyleClass.SLOTS_DEFAULT_PATH)
	var bl: Variant = StyleClass.load_default_blend()
	expect(bl is StyleClass, "BLEND 默认 .tres 可载入（%s）" % StyleClass.BLEND_DEFAULT_PATH)
	if not (slots is StyleClass) or not (bl is StyleClass):
		return
	expect_eq(slots.mode, StyleClass.Mode.SLOTS, "SLOTS .tres mode = SLOTS（默认色块档）")
	expect_eq(bl.mode, StyleClass.Mode.BLEND, "BLEND .tres mode = BLEND（混合过渡档）")
	expect(slots.material_library != null, "SLOTS .tres 挂主线默认材质库")
	expect(bl.material_library != null, "BLEND .tres 挂主线默认材质库（两风格同源——换库即同换观感）")
	expect(slots.blend_material == null, "SLOTS 档不需要导管材质（blend_material 空 = 合法忽略）")
	# BLEND 导管材质 = 官方工厂口径（make_blend_material 的可检查属性全集）
	var bm: Material = bl.blend_material
	expect(bm is StandardMaterial3D, "BLEND .tres 导管材质为 StandardMaterial3D")
	if bm is StandardMaterial3D:
		var sm := bm as StandardMaterial3D
		expect_eq(sm.vertex_color_use_as_albedo, true, "导管开顶点色 albedo（顶点 COLOR 可见的前提）")
		expect_eq(sm.albedo_color, Color(1.0, 1.0, 1.0, 1.0), "导管白 albedo（不污染顶点色）")
		expect_eq(sm.roughness, 1.0, "导管 roughness = 官方工厂口径")
		expect_eq(sm.metallic, 0.0, "导管 metallic = 官方工厂口径")
	# 色板来源对账：库提色板 = DEFAULT_PALETTE（与 TerrainMaterialLibrary 同源锚）
	var palette: Variant = Blend.palette_from_materials(bl.material_library.materials)
	expect(palette is Dictionary, "BLEND 库可提色板（全 StandardMaterial3D）")
	if palette is Dictionary:
		expect_eq(palette, Lib.DEFAULT_PALETTE, "色板 = 主线默认色板（.tres 与代码同源）")
	# 代码内默认（对账基准）与 .tres 口径一致（防漂移，build_default 同纪律）
	var code_bl := StyleClass.make_default_blend()
	expect_eq(code_bl.mode, bl.mode, "make_default_blend 与 .tres 同 mode")
	var code_slots := StyleClass.make_default_slots()
	expect_eq(code_slots.mode, slots.mode, "make_default_slots 与 .tres 同 mode")
	expect_eq(Blend.palette_from_materials(code_bl.material_library.materials), Lib.DEFAULT_PALETTE,
		"make_default_blend 色板 = 默认色板")

func test_inputs_for_resolves_both_modes() -> void:
	var map := _gen_map()
	if map == null:
		return
	var used := {}
	for cell in map.cells():
		used[map.terrain_at(cell)] = true
	var slots: Variant = StyleClass.load_default_slots()
	var bl: Variant = StyleClass.load_default_blend()
	if not (slots is StyleClass) or not (bl is StyleClass):
		fail("默认 style .tres 载入失败（前置）")
		return
	var in_slots: Variant = slots.inputs_for(map)
	expect(in_slots is Dictionary, "SLOTS style 可解析")
	var in_bl: Variant = bl.inputs_for(map)
	expect(in_bl is Dictionary, "BLEND style 可解析")
	if not (in_slots is Dictionary) or not (in_bl is Dictionary):
		return
	var ds: Dictionary = in_slots
	var db: Dictionary = in_bl
	expect_eq(ds["mode"], "slots", "SLOTS 输入带 mode 标记")
	expect_eq(db["mode"], "blend", "BLEND 输入带 mode 标记")
	# materials/palette 恰覆盖被用到的 id、值 = 库实例/albedo（不合成新资源）
	expect_eq((ds["materials"] as Dictionary).size(), used.size(),
		"SLOTS materials 恰覆盖图内地形 id（got %d want %d）" % [ds["materials"].size(), used.size()])
	expect_eq((db["palette"] as Dictionary).size(), used.size(),
		"BLEND palette 恰覆盖图内地形 id")
	for tid in used:
		expect(ds["materials"][tid] == slots.material_library.material_for(tid),
			"SLOTS 材质 = 库内该 id 实例（echo，不合成）type %s" % str(tid))
		var want: Color = (slots.material_library.material_for(tid) as StandardMaterial3D).albedo_color
		expect_eq(db["palette"][tid], want, "BLEND 色板 = 库内 albedo_color type %s" % str(tid))
	expect(db["blend_material"] == bl.blend_material, "BLEND 导管材质 echo 同一实例")

func test_inputs_for_rejects_broken_styles() -> void:
	var map := _gen_map()
	if map == null:
		return
	# ① 库缺失
	var s1 := StyleClass.new()
	s1.mode = StyleClass.Mode.BLEND
	var p1: Array = s1.problems_for(map)
	expect(s1.inputs_for(map) == null, "库缺失 → 解析失败（无隐式兜底）")
	expect(p1.size() == 1 and String(p1[0]).contains("材质库"), "人读问题清单指出库缺失（got %s）" % str(p1))
	# ② 库缺图内地形 id
	var s2 := StyleClass.new()
	s2.mode = StyleClass.Mode.SLOTS
	s2.material_library = Lib.new()
	s2.material_library.materials = {0: Lib.make_color_block(Color(0.3, 0.5, 0.3))}
	expect(s2.inputs_for(map) == null, "库缺图内 id → 解析失败")
	expect(String(s2.problems_for(map)[0]).contains("缺材质槽"), "问题清单指出缺槽")
	# ③ BLEND 缺导管
	var s3 := StyleClass.new()
	s3.mode = StyleClass.Mode.BLEND
	s3.material_library = Lib.build_default()
	expect(s3.inputs_for(map) == null, "BLEND 缺 blend_material → 解析失败（导管是合同一部分）")
	expect(String(s3.problems_for(map)[0]).contains("blend_material"), "问题清单指出缺导管")
	# ④ BLEND 遇非 StandardMaterial3D 槽（用到的 id）
	var s4 := StyleClass.new()
	s4.mode = StyleClass.Mode.BLEND
	s4.material_library = Lib.new()
	s4.material_library.materials = {
		0: Lib.make_color_block(Color(0.3, 0.5, 0.3)),
		1: Lib.make_color_block(Color(0.5, 0.4, 0.3)),
		2: Lib.make_color_block(Color(0.5, 0.5, 0.55)),
		3: Lib.make_color_block(Color(0.25, 0.4, 0.6)),
		4: Lib.make_color_block(Color(0.78, 0.7, 0.45)),
		5: ShaderMaterial.new(),  # 林 = 图内用到 → 提不到 albedo_color
	}
	s4.blend_material = Blend.make_blend_material()
	expect(s4.inputs_for(map) == null, "BLEND 遇非 StandardMaterial3D 槽（用到的 id）→ 解析失败")
	# ⑤ 未用到的 id 不挡图（预检只看图内 id——库多余槽是合法美术状态）
	var tiny := MapDataClass.new(2, 1)
	tiny.set_terrain(MapDataClass.Hex.axial_of(Vector2i(0, 0)), 0)
	tiny.set_terrain(MapDataClass.Hex.axial_of(Vector2i(1, 0)), 1)
	var s5 := StyleClass.new()
	s5.mode = StyleClass.Mode.BLEND
	s5.material_library = Lib.new()
	s5.material_library.materials = {
		0: Lib.make_color_block(Color(0.3, 0.5, 0.3)),
		1: Lib.make_color_block(Color(0.5, 0.4, 0.3)),
		5: ShaderMaterial.new(),  # 图内未用到 → 不挡
	}
	s5.blend_material = Blend.make_blend_material()
	var r5: Variant = s5.inputs_for(tiny)
	expect(r5 is Dictionary, "未用到的非标准槽不挡图（预检只看图内 id）")
	if r5 is Dictionary:
		expect_eq((r5["palette"] as Dictionary).size(), 2, "小图色板恰覆盖 {0,1}")

# ================= Given 守卫：同 seed → 同图 =================

func test_same_seed_generates_identical_map() -> void:
	var a := _gen_map()
	var b := _gen_map()
	if a == null or b == null:
		return
	expect_eq(a.summary(), b.summary(), "同 seed 两次生成 summary 逐字节一致（Given：同一张图）")
	expect_eq(a.digest(), b.digest(), "digest 一致")
	expect_eq(a.to_dict(), b.to_dict(), "to_dict 往返一致（含 mods——生成器不写扩展位）")

# ================= Then ①：逻辑摘要与规则面零变化 =================

func test_style_swap_summary_mods_passability_unchanged() -> void:
	var a := _gen_map()
	var b := _gen_map()  # 同 seed 双实例：A 走 SLOTS、B 走 BLEND（同图换装）
	if a == null or b == null:
		return
	var summary_before := a.summary()
	var dict_before := a.to_dict()
	var slots: Variant = StyleClass.load_default_slots()
	var bl: Variant = StyleClass.load_default_blend()
	if not (slots is StyleClass) or not (bl is StyleClass):
		fail("默认 style .tres 载入失败（前置）")
		return
	var rs: Variant = _build_with_style(a, slots)
	var rb: Variant = _build_with_style(b, bl)
	if rs == null or rb == null:
		return
	expect_eq(a.summary(), summary_before, "SLOTS 构建后 summary 逐字节不变（世界事实不被表现层触碰）")
	expect_eq(b.summary(), summary_before, "BLEND 构建后 summary 逐字节不变（同图两 style 同值）")
	expect_eq(a.to_dict(), dict_before, "SLOTS 构建后 to_dict 不变（地形/高程/通行位逐格一致）")
	expect_eq(b.to_dict(), dict_before, "BLEND 构建后 to_dict 不变")
	expect_eq(a.mods.size(), 0, "mods 扩展位保持空（规则语义零变化——移动费 M3 前不存在、不得被表现层预写）")
	expect_eq(b.mods.size(), 0, "BLEND 侧 mods 同样保持空")

# ================= Then ②：索引与 face 映射逐位不变 =================

func test_style_swap_index_and_face_tables_bit_identical() -> void:
	var a := _gen_map()
	var b := _gen_map()
	if a == null or b == null:
		return
	var slots: Variant = StyleClass.load_default_slots()
	var bl: Variant = StyleClass.load_default_blend()
	if not (slots is StyleClass) or not (bl is StyleClass):
		fail("默认 style .tres 载入失败（前置）")
		return
	var rs: Variant = _build_with_style(a, slots)
	var rb: Variant = _build_with_style(b, bl)
	if rs == null or rb == null:
		return
	expect_eq(rs["chunk_rects"], rb["chunk_rects"], "chunk 划分一致（style 不改分块）")
	var ca: Array = rs["chunks"]
	var cb: Array = rb["chunks"]
	expect_eq(ca.size(), cb.size(), "chunk 数一致")
	for ci in ca.size():
		var xa: Dictionary = ca[ci]
		var xb: Dictionary = cb[ci]
		expect_eq(xa["chunk"], xb["chunk"], "chunk 矩形一致（%d）" % ci)
		var ma: ArrayMesh = xa["mesh"]
		var mb: ArrayMesh = xb["mesh"]
		expect_eq(ma.get_surface_count(), mb.get_surface_count(), "surface 数一致（chunk %d）" % ci)
		for si in ma.get_surface_count():
			var aa: Array = ma.surface_get_arrays(si)
			var ab: Array = mb.surface_get_arrays(si)
			expect_eq(aa[Mesh.ARRAY_INDEX], ab[Mesh.ARRAY_INDEX],
				"ARRAY_INDEX 逐位一致（%d/%d）——换 style 不动渲染索引" % [ci, si])
			expect_eq(aa[Mesh.ARRAY_VERTEX], ab[Mesh.ARRAY_VERTEX], "顶点逐位一致（%d/%d）" % [ci, si])
			expect_eq(aa[Mesh.ARRAY_NORMAL], ab[Mesh.ARRAY_NORMAL], "法线逐位一致（%d/%d）" % [ci, si])
			expect_eq(aa[Mesh.ARRAY_TEX_UV], ab[Mesh.ARRAY_TEX_UV], "UV 逐位一致（%d/%d）" % [ci, si])
			expect_eq(xa["surfaces"][si]["faces"], xb["surfaces"][si]["faces"],
				"faces 元数据逐位一致（%d/%d）——face→格映射不随 style 改变" % [ci, si])
			expect_eq(xa["surfaces"][si]["face_counts"], xb["surfaces"][si]["face_counts"],
				"面分类计数一致（%d/%d）" % [ci, si])
		# 拾取合同（引擎消费面）：碰撞汤与增强表逐位一致
		expect_eq(Picking.chunk_collision_faces(xa), Picking.chunk_collision_faces(xb),
			"碰撞三角形汤逐位一致（chunk %d）" % ci)
		expect_eq(Picking.chunk_face_table(xa), Picking.chunk_face_table(xb),
			"face→格映射表逐位一致（chunk %d）" % ci)

# ================= Then ③：可达性一致 =================

func test_style_swap_connectivity_identical() -> void:
	var a := _gen_map()
	var b := _gen_map()
	if a == null or b == null:
		return
	var slots: Variant = StyleClass.load_default_slots()
	var bl: Variant = StyleClass.load_default_blend()
	if not (slots is StyleClass) or not (bl is StyleClass):
		fail("默认 style .tres 载入失败（前置）")
		return
	if _build_with_style(a, slots) == null or _build_with_style(b, bl) == null:
		return
	var ra: Dictionary = Conn.check(a)
	var rb: Dictionary = Conn.check(b)
	expect_eq(ra, rb, "MapConnectivity.check 报告整体一致（含分量全表——可达性不随 style 改变）")
	expect_eq(ra["ok"], true, "固定图源连通 ok（种子扫描实证，见文件头注）")
	expect_eq(ra["component_count"], 1, "单连通分量（有实质内容的可达性对账）")
	expect(int(ra["passable_total"]) < a.cell_count(),
		"图含水（不可通行格 > 0）——通行位参与摘要/可达性对账，非全通行退化图")

# ================= Then ④：材质实例确不同 + 渲染数据差异可锚 =================

func test_materials_and_color_channel_differ_across_styles() -> void:
	var a := _gen_map()
	var b := _gen_map()
	if a == null or b == null:
		return
	var slots: Variant = StyleClass.load_default_slots()
	var bl: Variant = StyleClass.load_default_blend()
	if not (slots is StyleClass) or not (bl is StyleClass):
		fail("默认 style .tres 载入失败（前置）")
		return
	var rs: Variant = _build_with_style(a, slots)
	var rb: Variant = _build_with_style(b, bl)
	if rs == null or rb == null:
		return
	# SLOTS：逐地形库实例（≥2 种）、全不开顶点色（默认色块口径）
	var distinct := {}
	for ci in (rs["chunks"] as Array).size():
		var cd: Dictionary = rs["chunks"][ci]
		var mesh: ArrayMesh = cd["mesh"]
		for si in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(si)
			distinct[mat.get_instance_id()] = true
			expect(mat == slots.material_library.material_for(cd["surfaces"][si]["terrain"]),
				"SLOTS surface 材质 = 库内该地形实例（%d/%d）" % [ci, si])
			if mat is StandardMaterial3D:
				expect_eq((mat as StandardMaterial3D).vertex_color_use_as_albedo, false,
					"SLOTS 色块材质不开顶点色 albedo（%d/%d）" % [ci, si])
	expect(distinct.size() >= 2, "SLOTS 用到 ≥2 种材质实例（多地形图，got %d）" % distinct.size())
	# BLEND：单一共享导管材质、开顶点色、与 SLOTS 材质无同一实例
	var conduit: Material = bl.blend_material
	var conduit_ids := {}
	for ci in (rb["chunks"] as Array).size():
		var cd: Dictionary = rb["chunks"][ci]
		var mesh: ArrayMesh = cd["mesh"]
		for si in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(si)
			expect(mat == conduit, "BLEND surface 材质统一 = style.blend_material（%d/%d）" % [ci, si])
			conduit_ids[mat.get_instance_id()] = true
	expect_eq(conduit_ids.size(), 1, "BLEND 全图单一材质实例（got %d）" % conduit_ids.size())
	expect(not distinct.has(conduit.get_instance_id()), "导管材质与 SLOTS 材质无同一实例（材质实例确不同）")
	expect(conduit is StandardMaterial3D and (conduit as StandardMaterial3D).vertex_color_use_as_albedo,
		"导管材质开顶点色 albedo（与 SLOTS 的渲染差异面之一）")
	# 渲染数据差异可锚：BLEND 逐顶点 COLOR 齐备且跨界边带端点异色；SLOTS 无 COLOR 通道
	var cross_face_checked := false
	for ci in (rb["chunks"] as Array).size():
		var cd: Dictionary = rb["chunks"][ci]
		var mesh: ArrayMesh = cd["mesh"]
		for si in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(si)
			var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var faces: Array = cd["surfaces"][si]["faces"]
			expect_eq(cols.size(), faces.size() * 3, "BLEND COLOR 逐顶点齐备（%d/%d）" % [ci, si])
			if cross_face_checked:
				continue
			for fi in faces.size():
				if String(faces[fi]["kind"]) != "edge":
					continue
				var owner: Vector2i = faces[fi]["cell"]
				var nb := MapDataClass.Hex.neighbor(owner, int(faces[fi]["dir"]))
				if b.terrain_at(owner) == b.terrain_at(nb):
					continue
				cross_face_checked = true
				expect(cols[fi * 3] != cols[fi * 3 + 1],
					"跨界边带端点异色（owner 纯色 vs 邻格纯色——BLEND 渲染差异的顶点数据面）")
				break
	expect(cross_face_checked, "找到跨地形边带面（多地形图必然存在）")
	for ci in (rs["chunks"] as Array).size():
		var cd: Dictionary = rs["chunks"][ci]
		var mesh: ArrayMesh = cd["mesh"]
		for si in mesh.get_surface_count():
			expect_eq(_color_count(mesh.surface_get_arrays(si)), 0,
				"SLOTS 无 COLOR 通道（%d/%d）——两 style 渲染数据确不同" % [ci, si])

func test_style_layer_pure_no_nodes() -> void:
	var inst: Variant = StyleClass.new()
	expect(inst is Resource, "TerrainStyle 实例为 Resource（ADR-2：配置资源化，T8 先例）")
	expect(not (inst is Node), "TerrainStyle 不得为 Node")
	var map := _gen_map()
	if map == null:
		return
	for st in [StyleClass.make_default_slots(), StyleClass.make_default_blend()]:
		var inputs: Variant = (st as StyleClass).inputs_for(map)
		expect(inputs is Dictionary, "代码默认 style 可解析")
		if inputs is Dictionary:
			_walk_no_nodes(inputs, 0)
	var built: Variant = Builder.build_map_blend(map,
		Blend.palette_from_materials(Lib.build_default().materials), 10, 10,
		Blend.make_blend_material())
	expect(built is Dictionary, "blend 构建成功（回归）")
	if built is Dictionary:
		_walk_no_nodes(built, 0)

# ---- 辅助 ----

## 同 seed 固定图源（12×8 / seed 7301；生成失败 → expect 记失败并返回 null）。
func _gen_map() -> MapDataClass:
	var p := ParamsClass.new()
	p.seed = MAP_SEED
	p.width = MAP_W
	p.height = MAP_H
	var r: Dictionary = Gen.generate(p)
	expect_eq(r["ok"], true, "固定图源生成 ok（seed %d）" % MAP_SEED)
	if bool(r["ok"]):
		return r["map"]
	return null


## style → 构建结果（BLEND-03 的 When：inputs_for → builder 双入口；失败 → null
## 并记 expect）。与 MapView.build_with_style 同一分发口径（view 层不可进 tests/，
## 分发等价性由沙盒冒烟 + 两入口既有测试锚定）。
func _build_with_style(map: MapDataClass, style: StyleClass) -> Variant:
	var inputs: Variant = style.inputs_for(map)
	expect(inputs is Dictionary, "style 可解析（%s）" % style.label())
	if not (inputs is Dictionary):
		return null
	var d: Dictionary = inputs
	if d["mode"] == "blend":
		return Builder.build_map_blend(map, d["palette"], CHUNK_COLS, CHUNK_ROWS,
			d["blend_material"])
	return Builder.build_map(map, CHUNK_COLS, CHUNK_ROWS, d["materials"])


## surface 数组的 COLOR 顶点数（缺通道时引擎回空容器——按实际类型取数，fallback = 0）。
func _color_count(arrays: Array) -> int:
	var v: Variant = arrays[Mesh.ARRAY_COLOR]
	if v is PackedColorArray:
		return (v as PackedColorArray).size()
	return 0


## 递归检查结果不含任何 Node（材质/mesh 均为 Resource；沿用 blend 测试口径）。
func _walk_no_nodes(v: Variant, depth: int) -> void:
	if v == null or depth > 8:
		return
	if v is Node:
		fail("结果含 Node：%s" % str(v))
	elif v is Dictionary:
		for x in (v as Dictionary).values():
			_walk_no_nodes(x, depth + 1)
	elif v is Array:
		for x in v:
			_walk_no_nodes(x, depth + 1)
