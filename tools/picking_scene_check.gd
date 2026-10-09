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
	const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
	const Picking := preload("res://addons/hexhammer/hex_picking.gd")

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
				_finish()

	# ---------------- 场景阶段 ----------------

	func _teardown() -> void:
		if map_root != null:
			map_root.queue_free()  # 本帧末出树；隔帧后物理空间不再含旧碰撞体
			map_root = null
		tables.clear()

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
		var r: Variant = Builder.build_map(map, 10, 10, {}, SIZE, 1.0, SOLID)
		if not (r is Dictionary):
			_hard_fail("A 场景构建失败")
			return
		_attach_bodies(r as Dictionary)
		phase = 0
		settle = SETTLE_FRAMES

	func _stage_build_pair(delta: int) -> void:
		_teardown()
		map = MapDataClass.new(3, 1)
		var a := Hex.axial_of(Vector2i(1, 0))
		map.set_elevation(Hex.neighbor(a, 0), delta)
		var r: Variant = Builder.build_map(map, 10, 10, {}, SIZE, 1.0, SOLID)
		if not (r is Dictionary):
			_hard_fail("对图场景构建失败（delta=%d）" % delta)
			return
		_attach_bodies(r as Dictionary)
		phase = delta_to_phase(delta)
		settle = SETTLE_FRAMES

	func delta_to_phase(delta: int) -> int:
		return 1 if delta == 1 else 2

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

	func _finish() -> void:
		set_physics_process(false)
		print("[拾取小场景校验] === %d 通过 / %d 失败 ===" % [pass_count, fail_count])
		get_tree().quit(1 if fail_count > 0 else 0)
