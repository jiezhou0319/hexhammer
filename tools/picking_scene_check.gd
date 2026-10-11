## picking_scene_check.gd — M1a-T5 拾取引擎级小场景校验（独立工具，非门禁）
## 用法（须跑真物理帧，与门禁命令分开执行）：
##   "C:/Users/zerat/godot_tmp/Godot_v4.7.2-stable_win64_console.exe" --headless \
##     --path hexhammer --script res://tools/picking_scene_check.gd
## 为什么独立：门禁 run_tests.gd 在 SceneTree._init 内同步执行并 quit，主循环从不
##   迭代、物理空间永不被 step（Godot 4.7.2 脚本 API 无 space_step/sync/
##   flush_queries；手动物理空间直查恒空——2026-10-09 探测确认）。引擎级
##   face_index / mask / 节点平移行为只能跑帧验证 → 本工具 call_deferred 启动、
##   在 _physics_process（物理回调）内直查——与生产代码 scripts/ui/map_picker.gd
##   同一时机纪律。
## 校验内容（04 M1a-T5 验收的引擎侧证据；几何/规则本身的数学证明在 tests/）：
##   A. face→格子增强表：5×5 混合高程图，每格直下射线——引擎返回 face_index 命中
##      face 表「kind=top 且 cell=目标格」条目（= 自提交碰撞三角形顺序与引擎
##      face_index 语义一致，ConcavePolygonShape3D）+ 归属正确；
##   B. 斜坡归属：3×1 对图 |Δh|=1：t=0.45/0.55 最近格心、t=0.5 平局 → ID 小者；
##   C. 悬崖归属：3×1 对图 |Δh|=3：三个 t 全归高地侧；
##   D. 射线 mask：棋子层（LAYER_PICKABLE）悬空箱体不截获地形拾取；mask 含该层
##      时被截获（正反对照）；
##   E. 地图根整体平移：root.position=T 后世界射线拾取仍正确（to_local 转换）。
##   F. 阶地面归属（T2 LAND-03：新面型真实 raycast 用例）：3×1 对图 |Δh|=2 +
##      LandformProfile（阶地环带）：t=0.45/0.55 最近格心 + 命中面 edge_type=terrace；
##   G. 崖壁归属（T2 LAND-03）：|Δh|=3 + profile（真垂直墙）：直下射线归高地侧 +
##      命中面 edge_type=cliff_wall + **水平射线正中竖直墙**（墙顶/墙底同 XZ 的
##      竖直面——直下射线打不到的面，专项命中）。
##   H. 河床归属（T3 WATER-02 ③：新面型真实 raycast 用例）：3×3 图单边河
##      （|Δh|=4 悬崖高岸 × 河）：t=0.45/0.5 命中 kind=riverbed 且归**最近格心**
##      （平局 ID 决胜）——高侧不截胡（riverbed 无高程档，区别于 cliff 规则）；
##      水面第二 mesh **挂载进场景**（沿 map_view._mount_water 同构：MeshInstance3D、
##      零碰撞体）后射线「穿水」直落河床——水层不截获地形拾取的引擎级证据含
##      水面层本体（将来挂载侧误给水面加 LAYER_TERRAIN 碰撞体 → 射线先中水面、
##      face 表查无此碰撞体 → 本检查变红）。
## 场景切换纪律：每阶段「释旧+建新」后隔 ≥2 个物理帧再查（同帧切换旧碰撞体
##   尚在空间中且 XZ 与新场景重叠，必串扰）。
## 退出码：全部通过 0，任一失败 1。
extends SceneTree

func _init() -> void:
	print("[拾取小场景校验] init（deferred 启动，等待主循环）")
	_boot.call_deferred()  # 等主循环启动（root/物理世界就绪）

func _boot() -> void:
	print("[拾取小场景校验] boot：root=%s" % str(root != null))
	if root.world_3d == null:
		root.world_3d = World3D.new()
	var checker := Checker.new()
	root.add_child(checker)

## 校验节点：物理回调内直查（与 map_picker.gd 同纪律）
class Checker extends Node:
	const Hex := preload("res://addons/hexhammer/hex_math.gd")
	const MapDataClass := preload("res://scripts/core/data/map_data.gd")
	const Lib := preload("res://scripts/core/data/terrain_material_library.gd")
	const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
	const Picking := preload("res://addons/hexhammer/hex_picking.gd")
	const ProfileClass := preload("res://scripts/core/data/landform_profile.gd")
	const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
	const WaterB := preload("res://addons/hexhammer/water_geometry_builder.gd")

	const SIZE := 1.0
	const SOLID := 0.8
	const SETTLE_FRAMES := 2  # 建场景/改变换 → 可查询 的间隔物理帧

	var phase := -1
	var settle := 0
	var ticks := 0
	var pass_count := 0
	var fail_count := 0
	var map: MapDataClass = null
	var map_root: Node3D = null
	var tables := {}  # body instance_id → face 表
	var water_nodes: Array[MeshInstance3D] = []  # 水面 mesh（H 场景——零碰撞体）

	const WATCHDOG_FRAMES := 600  # 卡死保险：超帧强制失败退出

	func _ready() -> void:
		print("[拾取小场景校验] checker ready")
		_stage_build_a()

	func _physics_process(_delta: float) -> void:
		ticks += 1
		if ticks > WATCHDOG_FRAMES:
			print("[拾取小场景校验] FAIL 看门狗超时（phase=%d settle=%d）" % [phase, settle])
			get_tree().quit(1)
			return
		if settle > 0:
			settle -= 1
			return
		match phase:
			0:  # A 查完 → 换 B 场景
				_run_check_a()
				_stage_build_pair(1)
			1:  # B 查完 → 换 C 场景
				_run_pair_checks(1, "B. 斜坡归属（|Δh|=1：最近格心 / 平局 ID 决胜）")
				_stage_build_pair(3)
			2:  # C 查完 → 加棋子层箱体（D 用同场景）
				_run_pair_checks(3, "C. 悬崖归属（|Δh|=3：高地侧）")
				_add_impostor()
			3:
				_run_check_d()
				map_root.position = Vector3(37.5, -12.25, 8.0)  # E：地图根整体平移
				phase = 4
				settle = SETTLE_FRAMES
			4:
				_run_check_e()
				_stage_build_pair(2, ProfileClass.make_default())  # F：阶地档（T2）
			5:  # F 查完 → 换 G 场景
				_run_check_f()
				_stage_build_pair(3, ProfileClass.make_default())  # G：真垂直崖档（T2）
			6:  # G 查完 → 换 H 场景（T3 河床）
				_run_check_g()
				_stage_build_river()
			7:
				_run_check_h()
				_finish()

	# ---------------- 场景阶段 ----------------

	func _teardown() -> void:
		if map_root != null:
			map_root.queue_free()  # 本帧末出树；隔帧后物理空间不再含旧碰撞体
			map_root = null
		tables.clear()
		water_nodes.clear()  # 水面节点随 map_root 释放（本检查只存引用）

	func _attach_bodies(build: Dictionary) -> void:
		map_root = Node3D.new()
		map_root.name = "MapRoot"
		get_tree().root.add_child(map_root)
		for chunk_info in build["chunks"]:
			var pd: Dictionary = Picking.chunk_pick_data(chunk_info)
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(pd["collision_faces"])
			var body := StaticBody3D.new()
			body.collision_layer = 1 << (Picking.LAYER_TERRAIN - 1)
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			map_root.add_child(body)  # 局部零偏移：世界变换随地图根
			tables[body.get_instance_id()] = pd["face_table"]

	func _stage_build_a() -> void:
		_teardown()
		map = MapDataClass.new(5, 5)
		for cell in map.cells():
			var cr := Hex.offset_of(cell)
			map.set_elevation(cell, (cr.x * 2 + cr.y * 3) % 5 - 2)
		var r: Variant = Builder.build_map(map, 10, 10, _mats(), SIZE, 1.0, SOLID)
		if not (r is Dictionary):
			_hard_fail("A 场景构建失败")
			return
		_attach_bodies(r as Dictionary)
		phase = 0
		settle = SETTLE_FRAMES

	func _stage_build_pair(delta: int, profile: ProfileClass = null) -> void:
		_teardown()
		map = MapDataClass.new(3, 1)
		var a := Hex.axial_of(Vector2i(1, 0))
		map.set_elevation(Hex.neighbor(a, 0), delta)
		var r: Variant = Builder.build_map(map, 10, 10, _mats(), SIZE, 1.0, SOLID, profile)
		if not (r is Dictionary):
			_hard_fail("对图场景构建失败（delta=%d）" % delta)
			return
		_attach_bodies(r as Dictionary)
		phase = _pair_phase(delta, profile)
		settle = SETTLE_FRAMES

	## 对图场景的 phase 派发：基线档 1/2；T2 profile 档 5（阶地 Δ2）/6（崖壁 Δ3）
	func _pair_phase(delta: int, profile: ProfileClass) -> int:
		if profile != null:
			return 5 if delta == 2 else 6
		return 1 if delta == 1 else 2

	## 单类型材质表（M1a-T8 起 builder 只认 {terrain_id: Material}）
	func _mats() -> Dictionary:
		return Lib.materials_from_colors({0: Color(0.5, 0.5, 0.5)})

	func _hard_fail(label: String) -> void:
		print("[拾取小场景校验] FAIL %s" % label)
		get_tree().quit(1)
		set_physics_process(false)

	# ---------------- 直查（物理回调内；mask/局部转换与 map_picker.gd 同构）----------------

	func _pick(origin: Vector3, dir: Vector3, mask: int) -> Variant:
		var space := map_root.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir.normalized() * 500.0, mask)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {"miss": true}
		var table: Array = tables.get(hit["collider_id"], [])
		var cell: Variant = Picking.resolve_hit(
			map_root.to_local(hit["position"]), int(hit["face_index"]), table, map, SIZE)
		return {"miss": false, "hit": hit, "cell": cell}

	func _pick_down(x: float, z: float, mask: int = Picking.MASK_TERRAIN_ONLY) -> Variant:
		return _pick(Vector3(x, 30.0, z), Vector3(0.0, -1.0, 0.0), mask)

	func _check(cond: bool, label: String) -> void:
		if cond:
			pass_count += 1
			print("[拾取小场景校验] PASS %s" % label)
		else:
			fail_count += 1
			print("[拾取小场景校验] FAIL %s" % label)

	# ---------------- 检查 ----------------

	func _run_check_a() -> void:
		var ok := true
		for cell in map.cells():
			var c := Hex.axial_to_world(cell, SIZE)
			var res: Variant = _pick_down(c.x, c.z)
			if res["miss"]:
				ok = false
				print("[拾取小场景校验] FAIL A：格心直下未命中 %s" % str(cell))
				continue
			var hit: Dictionary = res["hit"]
			var table: Array = tables.get(hit["collider_id"], [])
			var fi := int(hit["face_index"])
			if fi < 0 or fi >= table.size():
				ok = false
				print("[拾取小场景校验] FAIL A：face_index 越界 %d（表长 %d）%s" % [fi, table.size(), str(cell)])
				continue
			var face: Dictionary = table[fi]
			if String(face["kind"]) != "top" or face["cell"] != cell:
				ok = false
				print("[拾取小场景校验] FAIL A：face_index→表项不符（%s ≠ top/%s）%s"
					% [str(face), str(cell), str(cell)])
				continue
			if res["cell"] != cell:
				ok = false
				print("[拾取小场景校验] FAIL A：归属不符 %s → %s" % [str(cell), str(res["cell"])])
		_check(ok, "A. face→格映射（引擎 face_index = 自提交碰撞三角形顺序）+ 5×5 全格反投影")

	func _run_pair_checks(delta: int, label: String) -> void:
		var a := Hex.axial_of(Vector2i(1, 0))
		var b := Hex.neighbor(a, 0)
		var ca := Hex.axial_to_world(a, SIZE)
		var cb := Hex.axial_to_world(b, SIZE)
		var ok := true
		for t in [0.45, 0.5, 0.55]:
			var tt: float = t
			var x := ca.x + (cb.x - ca.x) * tt
			var z := ca.z + (cb.z - ca.z) * tt
			var res: Variant = _pick_down(x, z)
			if res["miss"]:
				ok = false
				print("[拾取小场景校验] FAIL %s：t=%s 未命中" % [label, str(tt)])
				continue
			var want: Variant
			if delta >= 2:
				want = b  # 悬崖：高地侧（XZ 更近低格也不截胡）
			elif tt < 0.5:
				want = a
			elif tt > 0.5:
				want = b
			else:
				want = a if map.index_of(a) < map.index_of(b) else b  # 平局 ID 决胜
			if res["cell"] != want:
				ok = false
				print("[拾取小场景校验] FAIL %s：t=%s got=%s want=%s"
					% [label, str(tt), str(res["cell"]), str(want)])
		_check(ok, label)

	func _add_impostor() -> void:
		# 棋子层悬空箱体：罩住目标格上空（mask 不含该层时不得截获）
		var target := Hex.axial_of(Vector2i(1, 0))
		var tc := Hex.axial_to_world(target, SIZE, 0.0)
		var impostor := StaticBody3D.new()
		impostor.collision_layer = 1 << (Picking.LAYER_PICKABLE - 1)
		impostor.position = Vector3(tc.x, tc.y + 2.5, tc.z)
		var box := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(3.0, 0.4, 3.0)
		box.shape = box_shape
		impostor.add_child(box)
		map_root.add_child(impostor)
		phase = 3
		settle = SETTLE_FRAMES

	func _run_check_d() -> void:
		var target := Hex.axial_of(Vector2i(1, 0))
		var tc := Hex.axial_to_world(target, SIZE, 0.0)
		var d1: Variant = _pick_down(tc.x, tc.z, Picking.MASK_TERRAIN_ONLY)
		_check(not d1["miss"] and d1["cell"] == target,
			"D1. mask=地形层：棋子层箱体不得截获（拾取仍归地形格）")
		var d2: Variant = _pick_down(tc.x, tc.z,
			Picking.MASK_TERRAIN_ONLY | (1 << (Picking.LAYER_PICKABLE - 1)))
		_check(d2["miss"] or d2["cell"] == null,
			"D2. mask 含棋子层：箱体截获 → 非地形面 → miss（无静默兜底）")

	func _run_check_e() -> void:
		# 当前场景 = 3×1 对图（|Δh|=3），root 已平移 (37.5,-12.25,8)
		var ok := true
		for cell in map.cells():
			var c := Hex.axial_to_world(cell, SIZE, float(map.elevation_at(cell)))
			var world := c + map_root.position
			var res: Variant = _pick(Vector3(world.x, world.y + 25.0, world.z),
				Vector3(0.0, -1.0, 0.0), Picking.MASK_TERRAIN_ONLY)
			if res["miss"] or res["cell"] != cell:
				ok = false
				var got: Variant = (res as Dictionary).get("cell", "miss")
				print("[拾取小场景校验] FAIL E：平移后 %s got=%s" % [str(cell), str(got)])
		_check(ok, "E. 地图根整体平移后拾取仍正确（to_local 转换）")

	# ---------------- T2 新面型真实 raycast（LAND-03 ④ 扩用例）----------------

	func _run_check_f() -> void:
		# F. 阶地档（Δ2 + profile）：直下射线命中阶地环带面 → 最近格心；面型 terrace
		var a := Hex.axial_of(Vector2i(1, 0))
		var b := Hex.neighbor(a, 0)
		var ca := Hex.axial_to_world(a, SIZE)
		var cb := Hex.axial_to_world(b, SIZE)
		var ok := true
		for t in [0.45, 0.55]:
			var tt: float = t
			var x := ca.x + (cb.x - ca.x) * tt
			var z := ca.z + (cb.z - ca.z) * tt
			var res: Variant = _pick_down(x, z)
			if res["miss"]:
				ok = false
				print("[拾取小场景校验] FAIL F：t=%s 未命中（阶地环带面缺口？）" % str(tt))
				continue
			var hit: Dictionary = res["hit"]
			var table: Array = tables.get(hit["collider_id"], [])
			var fi := int(hit["face_index"])
			if fi < 0 or fi >= table.size():
				ok = false
				continue
			var face: Dictionary = table[fi]
			var want: Vector2i = a if tt < 0.5 else b  # 阶地 riser = 最近格心（T2 泛化）
			if String(face.get("edge_type", "")) != Builder.EDGE_TERRACE:
				ok = false
				print("[拾取小场景校验] FAIL F：t=%s 命中面非 terrace（got %s）" % [str(tt), str(face)])
			if res["cell"] != want:
				ok = false
				print("[拾取小场景校验] FAIL F：t=%s got=%s want=%s（最近格心）" % [str(tt), str(res["cell"]), str(want)])
		_check(ok, "F. 阶地面归属（|Δh|=2 + profile：最近格心 / edge_type=terrace）")

	func _run_check_g() -> void:
		# G. 真垂直崖档（Δ3 + profile）：直下射线归高地侧 + cliff_wall 面型；
		#    水平射线正中竖直墙（直下打不到的面——墙顶/墙底同 XZ 的竖直面专项）
		var a := Hex.axial_of(Vector2i(1, 0))
		var b := Hex.neighbor(a, 0)
		var ca := Hex.axial_to_world(a, SIZE)
		var cb := Hex.axial_to_world(b, SIZE)
		var ok := true
		for t in [0.45, 0.55]:
			var tt: float = t
			var x := ca.x + (cb.x - ca.x) * tt
			var z := ca.z + (cb.z - ca.z) * tt
			var res: Variant = _pick_down(x, z)
			if res["miss"]:
				ok = false
				continue
			var hit: Dictionary = res["hit"]
			var table: Array = tables.get(hit["collider_id"], [])
			var face: Dictionary = table[int(hit["face_index"])]
			if String(face.get("edge_type", "")) != Builder.EDGE_CLIFF_WALL:
				ok = false
				print("[拾取小场景校验] FAIL G：t=%s 命中面非 cliff_wall（got %s）" % [str(tt), str(face)])
			if res["cell"] != b:
				ok = false
				print("[拾取小场景校验] FAIL G：t=%s 直下射线 got=%s want=%s（高地侧）" % [str(tt), str(res["cell"]), str(b)])
		# 水平射线：从低格上空朝墙（墙立于带中点 XZ，跨 y 0..3——y=1.5 高度正中）
		var mid := (ca + cb) * 0.5
		var origin := Vector3(ca.x, 1.5, ca.z)
		var dir := Vector3(mid.x - ca.x, 0.0, mid.z - ca.z).normalized()
		var wall_res: Variant = _pick(origin, dir, Picking.MASK_TERRAIN_ONLY)
		if wall_res["miss"]:
			ok = false
			print("[拾取小场景校验] FAIL G：水平射线未命中竖直墙（墙顶/墙底 XZ 错位？）")
		else:
			var whit: Dictionary = wall_res["hit"]
			var wtable: Array = tables.get(whit["collider_id"], [])
			var wface: Dictionary = wtable[int(whit["face_index"])]
			var vertical := absf(whit["normal"].y) < 0.01
			if String(wface.get("edge_type", "")) != Builder.EDGE_CLIFF_WALL or not vertical:
				ok = false
				print("[拾取小场景校验] FAIL G：水平射线命中非竖直 cliff_wall（got %s normal=%s）" % [str(wface), str(whit["normal"])])
			if wall_res["cell"] != b:
				ok = false
				print("[拾取小场景校验] FAIL G：墙面命中 got=%s want=%s（高地侧）" % [str(wall_res["cell"]), str(b)])
		_check(ok, "G. 崖壁归属（|Δh|=3 + profile：高地侧 / cliff_wall / 水平射线正中竖直墙）")

	func _finish() -> void:
		set_physics_process(false)
		print("[拾取小场景校验] === %d 通过 / %d 失败 ===" % [pass_count, fail_count])
		get_tree().quit(1 if fail_count > 0 else 0)

	# ---------------- T3 河床真实 raycast（WATER-02 ③ 扩用例）----------------

	## H 场景：3×3 图单边河——a=(1,1) 与东邻 b 之间的 link 为河；b 抬 4
	## （悬崖高岸 × 河：河床归属不归高侧）；a 侧为河口湖成员（终点边 = 该边，
	## 单边链源=终点；成员格结算面 = 高程 0 + 不可通行，terrain 保持 0 号槽
	## ——材质表只认 0，水色渲染属水面第二 mesh，与地形槽无关）。
	func _stage_build_river() -> void:
		_teardown()
		map = MapDataClass.new(3, 3)
		for cell in map.cells():
			map.set_elevation(cell, 1)
		var a := Hex.axial_of(Vector2i(1, 1))
		var b := Hex.neighbor(a, 0)
		map.set_elevation(b, 4)
		var world := WorldDataClass.empty()
		var term := WorldDataClass.link_id_of(map.index_of(a), map.index_of(b))
		var members: Array[int] = [term.x]
		var mcell := Hex.axial_of(Vector2i(term.x % map.width, term.x / map.width))
		for d in 6:
			var nb := Hex.neighbor(mcell, d)
			if map.has_cell(nb) and map.index_of(nb) != term.y and not members.has(map.index_of(nb)):
				members.append(map.index_of(nb))
		for cid in members:
			var c := Hex.axial_of(Vector2i(cid % map.width, cid / map.width))
			map.set_elevation(c, 0)
			map.set_passable(c, false)
		members.sort()
		var reach := WorldDataClass.RiverReachData.new()
		reach.reach_id = 0
		reach.edges = [term]
		reach.water_levels = [1]
		reach.bed_level = 0
		reach.water_body_id = 0
		world.rivers.append(reach)
		var body := WorldDataClass.WaterBodyData.new()
		body.water_body_id = 0
		body.water_level = 1
		body.member_cells = members
		body.inlet_links = [term]
		body.terminal = true
		world.water_bodies.append(body)
		var lk := WorldDataClass.NeighborLinkData.new()
		lk.link_id = term
		lk.river_reach_id = 0
		world.links.append(lk)
		var verr := world.validate(map)  # terrain 对账跳过（-1 口径：成员保持 0 号槽）
		if verr != "":
			_hard_fail("H 场景世界非法：%s" % verr)
			return
		var r: Variant = Builder.build_map(map, 10, 10, _mats(), SIZE, 1.0, SOLID,
			null, world)
		if not (r is Dictionary):
			_hard_fail("H 场景构建失败（河床下切）")
			return
		_attach_bodies(r as Dictionary)
		# 水面第二 mesh 挂载（map_view._mount_water 同构：全局坐标顶点、节点零偏移、
		# **零碰撞体**）——「射线穿水」的引擎级证据必须含水面层本体在场景中
		var wb: Variant = WaterB.build_map(map, world, 10, 10,
			WaterB.make_water_material(), SIZE, 1.0, SOLID)
		if not (wb is Dictionary):
			_hard_fail("H 场景水面构建失败")
			return
		for chunk_info in (wb as Dictionary)["chunks"]:
			var cd: Dictionary = chunk_info
			if (cd["mesh"] as ArrayMesh).get_surface_count() == 0:
				continue
			var wnode := MeshInstance3D.new()
			wnode.name = "Water_c%d_r%d" % [(cd["chunk"] as Rect2i).position.x,
				(cd["chunk"] as Rect2i).position.y]
			wnode.mesh = cd["mesh"]
			map_root.add_child(wnode)
			water_nodes.append(wnode)
		phase = 7
		settle = SETTLE_FRAMES

	func _run_check_h() -> void:
		# 射线穿水（水面已挂载、零碰撞体）直落河床：t=0.45/0.5/0.55 命中 kind=riverbed；
		# 归属 = 最近格心 + ID 决胜——b 为悬崖高岸（Δ4）也不截胡（无高程档）。
		# 前置 H0：水面节点非空——将来挂载侧若给水面加 LAYER_TERRAIN 碰撞体，
		# 射线先中水面 → tables 查无该 collider → 面表越界/miss → 本检查红
		_check(water_nodes.size() > 0,
			"H0. 水面第二 mesh 已挂载（零碰撞体——穿水证据含水面层本体）")
		var a := Hex.axial_of(Vector2i(1, 1))
		var b := Hex.neighbor(a, 0)
		var ca := Hex.axial_to_world(a, SIZE)
		var cb := Hex.axial_to_world(b, SIZE)
		var ok := true
		for t in [0.45, 0.5, 0.55]:
			var tt: float = t
			var x := ca.x + (cb.x - ca.x) * tt
			var z := ca.z + (cb.z - ca.z) * tt
			var res: Variant = _pick_down(x, z)
			if res["miss"]:
				ok = false
				print("[拾取小场景校验] FAIL H：t=%s 未命中（河床面缺口？）" % str(tt))
				continue
			var hit: Dictionary = res["hit"]
			var table: Array = tables.get(hit["collider_id"], [])
			var fi := int(hit["face_index"])
			if fi < 0 or fi >= table.size():
				ok = false
				continue
			var face: Dictionary = table[fi]
			if String(face["kind"]) != Builder.FACE_RIVERBED:
				ok = false
				print("[拾取小场景校验] FAIL H：t=%s 命中面非 riverbed（got %s）" % [str(tt), str(face)])
			var want: Vector2i
			if tt < 0.5:
				want = a
			elif tt > 0.5:
				want = b
			else:
				want = a if map.index_of(a) < map.index_of(b) else b  # 平局 ID 决胜
			if res["cell"] != want:
				ok = false
				print("[拾取小场景校验] FAIL H：t=%s got=%s want=%s（最近格心；高侧 Δ4 不截胡）"
					% [str(tt), str(res["cell"]), str(want)])
		_check(ok, "H. 河床归属（|Δh|=4 高岸 × 河：最近格心 + ID 决胜 / kind=riverbed / 射线穿水）")
