## highlight_scene_check.gd — M1a-T7 高亮引擎级小场景校验（独立工具，非门禁）
## 用法（与门禁命令分开执行；节点树行为 headless 同步可查，跑帧仅为树就绪）：
##   "C:/Users/zerat/godot_tmp/Godot_v4.7.2-stable_win64_console.exe" --headless \
##     --path hexhammer --script res://tools/highlight_scene_check.gd
## 为什么独立：门禁 run_tests.gd 在 SceneTree._init 内同步执行并 quit；节点层
##   （scripts/ui/highlight_layer.gd）按分层纪律不进 tests/（「删 scripts/ui/**
##   后 tests 全绿」，02 §3）——节点侧证据在本工具给出（对齐 tools/
##   picking_scene_check.gd 先例：纯逻辑数学证明在 tests/，引擎/节点行为在这里）。
## 校验内容（04 M1a-T7 细化的节点面证据）：
##   A. highlight(cells)：恰为集合大小个高亮节点、visible、position = 内顶面+lift
##     （微决策 2）、全节点共享同一 fan mesh 资源与同一材质（实例复用）；
##   B. 集合差异切换：节点零新建零销毁（缓存复用——child 数不变）、只差异格
##     visible 翻转、未变格不动；**地形 chunk MeshInstance3D.mesh 资源 id 不变、
##     地形节点数不变**（鼠标移动不重建地形 mesh）；
##   C. clear()：全部隐藏、节点保留（缓存不销毁）；再高亮同格零新建；
##   D. 路径描线：show_path 建单描线节点（贴地带 mesh）、同路径重复调用不换
##     mesh 资源（不重画）、clear_path 隐藏；
##   E. 高亮层子树无 CollisionObject3D（拾取射线恒不被高亮截获——mask 纪律的
##     节点面）；材质深度测试保持开启（no_depth_test=false）。
##   F. lift 档位错开（共面治理）：跨层同格双扇面 y 错一档、描线带 y = 本层
##     扇面 + 半档 extra（带×扇/跨层交叠不共面——远近缩放下无缝合纹/闪）。
## 退出码：全部通过 0，任一失败 1。
extends SceneTree

func _init() -> void:
	print("[高亮小场景校验] init（deferred 启动，等待主循环）")
	_boot.call_deferred()

func _boot() -> void:
	if root.world_3d == null:
		root.world_3d = World3D.new()
	var checker := Checker.new()
	root.add_child(checker)

## 校验节点：一帧树就绪后同步执行全部检查（高亮不依赖物理空间，无需物理帧）
class Checker extends Node:
	const Hex := preload("res://addons/hexhammer/hex_math.gd")
	const MapDataClass := preload("res://scripts/core/data/map_data.gd")
	const Builder := preload("res://addons/hexhammer/hex_terrain_builder.gd")
	const HL := preload("res://addons/hexhammer/hex_highlight.gd")
	const MapViewClass := preload("res://scripts/ui/map_view.gd")
	const HighlightLayerClass := preload("res://scripts/ui/highlight_layer.gd")

	const SIZE := 1.0
	const STEP := 1.0
	const SOLID := 0.8

	var pass_count := 0
	var fail_count := 0

	func _ready() -> void:
		_run()

	func _process(_delta: float) -> void:
		# _run 在 _ready 同帧完成；此帧仅让树走一次后退出
		_finish()

	func _check(cond: bool, label: String) -> void:
		if cond:
			pass_count += 1
			print("[高亮小场景校验] PASS %s" % label)
		else:
			fail_count += 1
			print("[高亮小场景校验] FAIL %s" % label)

	func _finish() -> void:
		set_process(false)
		print("[高亮小场景校验] === %d 通过 / %d 失败 ===" % [pass_count, fail_count])
		get_tree().quit(1 if fail_count > 0 else 0)

	# ---------------- 场景 ----------------

	func _build_scene() -> Array:
		var map := MapDataClass.new(6, 5)
		for cell in map.cells():
			var cr := Hex.offset_of(cell)
			map.set_elevation(cell, (cr.x * 2 + cr.y * 3) % 5 - 2)
		var view: MapViewClass = MapViewClass.new()
		view.name = "MapView"
		get_tree().root.add_child(view)
		var ok := view.build(map, 10, 10, {}, SIZE, STEP, SOLID)
		if not ok:
			_check(false, "场景构建（MapView.build）")
			return [null, null]
		var layer: HighlightLayerClass = HighlightLayerClass.new()
		layer.name = "HighlightLayer"
		view.add_child(layer)
		var lok: bool = layer.setup(map, SIZE, STEP, SOLID)
		return [view, layer]

	## 当前高亮节点（本层直接子节点中名以 HL_ 开头者）
	func _hl_children(layer) -> Array:
		var out: Array = []
		for c in layer.get_children():
			if String(c.name).begins_with("HL_"):
				out.append(c)
		return out

	func _visible_set(layer) -> Dictionary:
		var out := {}
		for c in _hl_children(layer):
			if c.visible:
				out[String(c.name)] = true
		return out

	func _names(cells: Array) -> Dictionary:
		var out := {}
		for c in cells:
			out["HL_%d_%d" % [c.x, c.y]] = true
		return out

	# ---------------- 检查 ----------------

	func _run() -> void:
		var built := _build_scene()
		var view = built[0]
		var layer = built[1]
		if view == null or layer == null:
			_finish()
			set_process(false)
			return
		var map: MapDataClass = layer.map

		# 地形 mesh 指纹（B 的「不重建地形」断言用）
		var terrain_mesh_ids: Array = []
		for cn in view.chunk_nodes:
			terrain_mesh_ids.append((cn.mesh as Mesh).get_instance_id())
		var terrain_node_count: int = view.chunk_nodes.size()

		# ---- A. highlight：节点数 = 集合大小、位姿与共享资源 ----
		var a := Hex.axial_of(Vector2i(2, 2))
		var b := Hex.neighbor(a, 0)
		var c := Hex.neighbor(a, 2)
		var d := Hex.neighbor(a, 4)
		var e := Hex.neighbor(a, 1)
		var f := Hex.neighbor(a, 3)
		layer.highlight([a, b, c])
		var nodes := _hl_children(layer)
		_check(nodes.size() == 3, "A1. 高亮节点数 = 集合大小（3）")
		var all_visible := true
		var anchored := true
		var shared_mesh := true
		var shared_mat := true
		var first_mesh: Mesh = null
		var first_mat: Material = null
		for n in nodes:
			all_visible = all_visible and n.visible
			# 名字 HL_q_r 解析回格（探针侧独立解析，不依赖层内部字典）
			var parts := String(n.name).substr(3).split("_")
			var cell := Vector2i(int(parts[0]), int(parts[1]))
			var anchor := HL.cell_anchor(map, cell, SIZE, STEP)
			anchored = anchored and n.position.distance_to(anchor) < 1e-6
			if first_mesh == null:
				first_mesh = n.mesh
				first_mat = n.material_override
			else:
				shared_mesh = shared_mesh and n.mesh == first_mesh
				shared_mat = shared_mat and n.material_override == first_mat
		_check(all_visible, "A2. 高亮节点全部 visible")
		_check(anchored, "A3. 节点 position = 内顶面 + lift（微决策 2 贴合）")
		_check(shared_mesh, "A4. 全节点共享同一 fan mesh 资源（形状复用）")
		_check(shared_mat, "A5. 全节点共享同一材质实例")
		_check(first_mat != null and not (first_mat as StandardMaterial3D).no_depth_test,
			"A6. 材质深度测试保持开启（不靠关深度测试掩盖穿山）")
		_check(first_mesh is ArrayMesh and (first_mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 7,
			"A7. 扇形 mesh = 格心 + 6 内顶点（只盖内顶面）")

		# ---- B. 差异切换：已缓存节点不销毁重建、只差异格翻转、地形不动 ----
		var cached_ids: Array = []
		for n in _hl_children(layer):
			cached_ids.append(n.get_instance_id())
		layer.highlight([b, d, e, f])  # S1={a,b,c} → S2={b,d,e,f}（d/e/f 首亮）
		var after := _hl_children(layer)
		_check(after.size() == 6, "B1. 新格首亮恰新建 3 节点（缓存累计 6，不整体重建）")
		var ids_kept := true
		for cid in cached_ids:
			var found := false
			for n in after:
				if n.get_instance_id() == cid:
					found = true
					break
			ids_kept = ids_kept and found
		_check(ids_kept, "B1b. 已缓存节点 instance_id 全保留（差异切换不销毁重建）")
		var want_visible := _names([b, d, e, f])
		_check(_visible_set(layer) == want_visible,
			"B2. 切换后恰差异格可见（a/c 隐藏、d/e/f 显示、b 不动）")
		# 已全缓存集合再切换（鼠标在已高亮区移动）：零新建零销毁
		var count_before := _hl_children(layer).size()
		var ids_before: Array = []
		for n in _hl_children(layer):
			ids_before.append(n.get_instance_id())
		layer.highlight([a, b, c])
		var reuse := _hl_children(layer)
		var zero_new := reuse.size() == count_before
		for n in reuse:
			zero_new = zero_new and ids_before.has(n.get_instance_id())
		_check(zero_new, "B2b. 已缓存集合切换零新建零销毁（鼠标移动不重建节点）")
		layer.highlight([b, d, e, f])
		var terrain_same := true
		for i in terrain_node_count:
			var cn: MeshInstance3D = view.chunk_nodes[i]
			terrain_same = terrain_same and (cn.mesh as Mesh).get_instance_id() == terrain_mesh_ids[i]
		_check(terrain_same, "B3. 地形 chunk mesh 资源不变（切换不重建地形）")
		_check(view.chunk_nodes.size() == terrain_node_count, "B4. 地形节点数不变")

		# ---- C. clear：全隐藏、节点保留；再高亮零新建 ----
		layer.clear()
		_check(_visible_set(layer).is_empty(), "C1. clear 后无可见高亮节点")
		_check(_hl_children(layer).size() == 6, "C2. clear 后节点保留在缓存（不销毁）")
		layer.highlight([a])
		_check(_hl_children(layer).size() == 6, "C3. 缓存格再高亮零新建（复用）")
		_check(_visible_set(layer) == _names([a]), "C4. 再高亮后仅目标格可见")
		layer.clear()

		# ---- D. 路径描线 ----
		var shown: bool = layer.show_path([a, b, e])
		_check(shown, "D1. show_path 三格路径成功")
		var path_node: MeshInstance3D = layer.get_node_or_null("PathStrip") as MeshInstance3D
		_check(path_node != null and path_node.visible, "D2. 描线节点存在且可见")
		var path_mesh_id: int = (path_node.mesh as Mesh).get_instance_id() if path_node != null else 0
		var shown_again: bool = layer.show_path([a, b, e])
		var path_mesh_id2: int = 0
		var pn2: MeshInstance3D = layer.get_node_or_null("PathStrip") as MeshInstance3D
		if pn2 != null:
			path_mesh_id2 = (pn2.mesh as Mesh).get_instance_id()
		_check(shown_again and path_mesh_id == path_mesh_id2, "D3. 同路径重复调用不重建 mesh（防闪烁节流）")
		_check(pn2 != null and (pn2.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 2 * 6,
			"D4. 条带 mesh = (格数−1) 段 × 6 顶点（2 格间段）")
		var ok_single: bool = layer.show_path([a])
		_check(not ok_single and not (layer.get_node_or_null("PathStrip") as MeshInstance3D).visible,
			"D5. 单格路径 → false 且描线隐藏（<2 界内格）")
		_check(layer.show_path([a, Vector2i(999, -999)]) == false, "D6. 界外格路径 → false（防御跳过）")
		layer.show_path([a, b, e])
		layer.clear_path()
		_check(not (layer.get_node_or_null("PathStrip") as MeshInstance3D).visible, "D7. clear_path 隐藏描线")

		# ---- E. 高亮层无碰撞体（拾取不截获的节点面）----
		var has_collider := false
		var stack: Array = [layer]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is CollisionObject3D:
				has_collider = true
			for ch in n.get_children():
				stack.append(ch)
		_check(not has_collider, "E. 高亮层子树无 CollisionObject3D（拾取射线恒不被截获）")

		# ---- F. lift 档位错开（跨层同格/带×扇共面治理——「不闪」的节点面）----
		layer.highlight([a])
		var hl_a: MeshInstance3D = layer.get_node_or_null("HL_%d_%d" % [a.x, a.y]) as MeshInstance3D
		var hover_layer: HighlightLayerClass = HighlightLayerClass.new()
		hover_layer.name = "HoverHighlightCheck"
		view.add_child(hover_layer)
		var hok: bool = hover_layer.setup(map, SIZE, STEP, SOLID,
			HL.DEFAULT_COLOR, HL.DEFAULT_PATH_COLOR, -1.0, HL.lift_for_tier(1))
		hover_layer.highlight([a])
		var hover_a: MeshInstance3D = hover_layer.get_node_or_null("HL_%d_%d" % [a.x, a.y]) as MeshInstance3D
		_check(hok and hover_a != null and hl_a != null
			and absf(hover_a.position.y - hl_a.position.y - HL.LIFT_TIER_STEP) < 1e-6,
			"F1. 跨层同格双扇面 y 错开一档（不共面，无 z-fighting 缝合纹）")
		layer.show_path([a, b, e])
		var strip: MeshInstance3D = layer.get_node_or_null("PathStrip") as MeshInstance3D
		var strip_ok := strip != null and strip.visible
		var strip_y := 0.0
		if strip_ok:
			var sverts: PackedVector3Array = (strip.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			strip_y = sverts[0].y  # 段 0 a 端顶点 y = 首格 anchor y（延伸恒水平，见纯逻辑测）
		_check(strip_ok and absf(strip_y - hl_a.position.y - HL.DEFAULT_PATH_LIFT_EXTRA) < 1e-6,
			"F2. 描线带 y = 本层扇面 + 半档 extra（带×扇不共面且描线压过扇面可见）")
		_check(absf(hover_a.position.y - strip_y) > 1e-9 and absf(hover_a.position.y - strip_y) < 0.05,
			"F3. tier1 扇面与 tier0 描线不共面（半档错开）且仍在贴地量级")
