## 3D 地基演示场景（表现层 only · 程序化占位版）：
## 六边形地形铺设 + 数据驱动单位摆放 + 点选/移动范围/移动动画。
## 交互链路：鼠标 → 射线 → Hex.world_to_axial → 高亮/BFS 范围 → Tween 移动。
## 2026-10-07 起 KayKit 资产彻底移除（docs/11 §1）：瓦片/装饰/单位全部程序化占位，
## 逐格哈希抖动预演"确定性散布"；地形系统（docs/11）落地后由其渲染层取代本场景。
## 引擎层（BattleEngine/命令模式）就位后，本脚本的"移动"改为发命令，渲染只听事件。
extends Node3D

const MAP_COLS := 10
const MAP_ROWS := 8
## 格中心距 = 1 世界单位（尺度约定沿用，docs/11 §5 资产规格按此对接）
const TILE_SPACING := 1.0

## 占位配色：grimdark 低饱和基调雏形（docs/11 §1）
const GRASS := Color(0.24, 0.32, 0.18)
const WATER := Color(0.12, 0.20, 0.28)
const STONE := Color(0.38, 0.37, 0.35)
const STEEL := Color(0.32, 0.33, 0.36)
const TRUNK := Color(0.24, 0.19, 0.14)
const LEAF := Color(0.14, 0.22, 0.13)

const FACTION_COLORS := [Color(0.25, 0.45, 0.95), Color(0.9, 0.25, 0.2)]
const SELECT_COLOR := Color(1.0, 0.85, 0.25)

## [profile 路径, 列, 行, 阵营(0 蓝 / 1 红)]
const UNIT_SETUP := [
	["res://resources/units/sword_shield.tres", 1, 2, 0],
	["res://resources/units/spearman.tres", 2, 3, 0],
	["res://resources/units/mage.tres", 1, 4, 0],
	["res://resources/units/archer.tres", 2, 5, 0],
	["res://resources/units/lancer.tres", 8, 5, 1],
]

var hex_radius := TILE_SPACING / sqrt(3.0)
var units := {}  # Vector2i axial -> Node3D
var selected: Node3D = null
var selected_cell := Vector2i.ZERO
var _reach_overlay: MeshInstance3D = null


func _ready() -> void:
	_setup_environment()
	_build_map()
	_spawn_units()
	$CameraRig.position = Hex.axial_to_world(
		Hex.oddr_to_axial(MAP_COLS / 2, MAP_ROWS / 2), hex_radius)


func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.52, 0.82)
	sky_mat.sky_horizon_color = Color(0.78, 0.84, 0.9)
	sky_mat.ground_bottom_color = Color(0.35, 0.4, 0.35)
	sky_mat.ground_horizon_color = Color(0.78, 0.84, 0.9)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.84, 0.9)
	env.fog_density = 0.008
	$WorldEnvironment.environment = env
	# 低角度暖色斜阳（docs/11 §1 美术纲领：从第一天进管线）
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 155.0, 0.0)
	sun.light_color = Color(1.0, 0.87, 0.72)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	# 自动化验收钩子：godot --path . -- --auto-shot=<绝对路径>
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--auto-shot="):
			_auto_shot(arg.substr("--auto-shot=".length()))


func _auto_shot(path: String) -> void:
	await get_tree().create_timer(2.5).timeout
	for cell in units:
		var u: Node3D = units[cell]
		var profile: UnitProfile = u.get_meta("profile")
		print("UNIT %s @%s pos=%s children=%d" % [profile.id, cell, u.global_position, u.get_child_count()])
	if "--close-shot" in OS.get_cmdline_user_args():
		$CameraRig.position = Vector3(2.2, 0, 4.2)
		$CameraRig.test_zoom(7.5)
		await get_tree().create_timer(0.5).timeout
	if "--with-select" in OS.get_cmdline_user_args():
		_select_unit(units.keys()[0])
		await get_tree().create_timer(0.6).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("AUTO_SHOT_SAVED ", path)
	get_tree().quit()


## 确定性伪随机（散布系统雏形：同输入永远同输出，docs/11 §5）
func _hash01(a: int, b: int, salt: int) -> float:
	var h := (a * 374761393 + b * 668265263 + salt * 1274126177) % 100003
	return float(h) / 100003.0


func _tint(base: Color, delta: float) -> Color:
	return base.lightened(delta) if delta >= 0.0 else base.darkened(-delta)


# ── 程序化图元（占位装饰通用件） ───────────────────────


func _prim(mesh: PrimitiveMesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	return mi


func _cyl(r: float, h: float, seg := 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = seg
	return m


func _cone(r: float, h: float, seg := 8) -> CylinderMesh:
	# Godot 无 ConeMesh：顶半径归零的圆柱即锥
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.radial_segments = seg
	return m


# ── 地图 ──────────────────────────────────────────────


func _build_map() -> void:
	add_child(_make_ground_slab())   # 垫底板：斜视边缘不穿帮
	add_child(_make_terrain_mesh())  # 连续地形面：一张网格、无边缝、无体块
	add_child(_make_grid_lines())    # 格线叠加层：画在地上的逻辑分区，可随时撤
	_add_tower(0, 1, FACTION_COLORS[0])
	_add_tower(MAP_COLS - 1, MAP_ROWS - 2, FACTION_COLORS[1])
	_add_flag(0, 3, FACTION_COLORS[0])
	_add_flag(MAP_COLS - 1, 4, FACTION_COLORS[1])
	for pos in [[4, 5], [6, 2], [5, 6]]:
		_add_trees(pos[0], pos[1])


func _is_water(col: int, row: int) -> bool:
	# 演示用：右下角一片水
	return col >= 8 and row >= 5


## 连续地形面：整图一张 mesh，格子仅是面上的着色分区（文明6 式）。
## 相邻格的边顶点坐标完全一致 → 物理无缝；逐格色调抖动给出格子感。
## ArrayMesh 手动组装（顶点色直写 COLOR 数组，不经 SurfaceTool）。
func _make_terrain_mesh() -> MeshInstance3D:
	const WATER_Y := -0.07
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for row in MAP_ROWS:
		for col in MAP_COLS:
			var water := _is_water(col, row)
			var c2 := Hex.axial_to_world(Hex.oddr_to_axial(col, row), hex_radius)
			var y := WATER_Y if water else 0.0
			var c_center := _tint(WATER if water else GRASS,
				_hash01(col, row, 7) * 0.08 - 0.04)
			var c_edge := c_center.darkened(0.07)  # 轻微边缘压暗 → 淡格界
			var base := verts.size()
			verts.append(Vector3(c2.x, y, c2.z))
			cols.append(c_center)
			norms.append(Vector3.UP)
			var ring: Array[Vector3] = []
			for k in 6:
				var a := deg_to_rad(30.0 + 60.0 * k)  # pointy-top 顶点角
				ring.append(Vector3(c2.x + cos(a) * hex_radius, y,
					c2.z + sin(a) * hex_radius))
				verts.append(ring[k])
				cols.append(c_edge)
				norms.append(Vector3.UP)
			# 中心扇形（ring 递增为俯视顺时针 → k+1 在前保法线朝上）
			for k in 6:
				idx.append(base)
				idx.append(base + 1 + (k + 1) % 6)
				idx.append(base + 1 + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mi.material_override = mat
	return mi


## 垫底板：地图边缘斜视时不透出天空（正式地形系统会换成裙边+高度）
func _make_ground_slab() -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2((MAP_COLS + 3) * TILE_SPACING,
		(MAP_ROWS + 3) * TILE_SPACING * 0.8)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var center := Hex.axial_to_world(
		Hex.oddr_to_axial(MAP_COLS / 2, MAP_ROWS / 2), hex_radius)
	mi.position = Vector3(center.x, -0.16, center.z)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.09, 0.08)
	mat.roughness = 1.0
	mi.material_override = mat
	return mi


## 格线层：全部格子的细描边，贴各自格面高度（水格沉、陆格浮）
func _make_grid_lines() -> MeshInstance3D:
	const LIFT := 0.01      # 抬离地表面，避免深度冲突
	const EDGE_W := 0.012   # 线宽
	var line_c := Color(0.02, 0.02, 0.02, 0.28)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in MAP_ROWS:
		for col in MAP_COLS:
			var c2 := Hex.axial_to_world(Hex.oddr_to_axial(col, row), hex_radius)
			var y := (-0.07 if _is_water(col, row) else 0.0) + LIFT
			var ring: Array[Vector3] = []
			for k in 6:
				var a := deg_to_rad(30.0 + 60.0 * k)
				ring.append(Vector3(c2.x + cos(a) * hex_radius, y,
					c2.z + sin(a) * hex_radius))
			for k in 6:
				var p1 := ring[k]
				var p2 := ring[(k + 1) % 6]
				var outward := ((p1 + p2) / 2.0 - Vector3(c2.x, y, c2.z)).normalized()
				var q1 := p1 - outward * EDGE_W
				var q2 := p2 - outward * EDGE_W
				st.add_vertex(p1)
				st.add_vertex(p2)
				st.add_vertex(q2)
				st.add_vertex(p1)
				st.add_vertex(q2)
				st.add_vertex(q1)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = line_c
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi


func _add_trees(col: int, row: int) -> void:
	var center := Hex.axial_to_world(Hex.oddr_to_axial(col, row), hex_radius)
	for i in 3:
		var ang := _hash01(col * 3 + i, row, 11) * TAU
		var rad := 0.18 + _hash01(col, row * 3 + i, 13) * 0.22
		var tree := Node3D.new()
		tree.position = center + Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
		tree.rotation.y = _hash01(col + i, row + i, 17) * TAU
		tree.scale = Vector3.ONE * (0.8 + _hash01(col - i, row + i, 19) * 0.5)
		tree.add_child(_prim(_cyl(0.03, 0.2, 6), Vector3(0, 0.1, 0), TRUNK))
		tree.add_child(_prim(_cone(0.16, 0.52), Vector3(0, 0.42, 0),
			_tint(LEAF, _hash01(col + i, row, 29) * 0.1 - 0.05)))
		add_child(tree)


func _add_tower(col: int, row: int, color: Color) -> void:
	var node := Node3D.new()
	node.position = Hex.axial_to_world(Hex.oddr_to_axial(col, row), hex_radius)
	node.add_child(_prim(_cyl(0.24, 0.5), Vector3(0, 0.25, 0), STONE))
	node.add_child(_prim(_cone(0.30, 0.26), Vector3(0, 0.63, 0),
		color.darkened(0.4)))
	add_child(node)


func _add_flag(col: int, row: int, color: Color) -> void:
	var node := Node3D.new()
	node.position = Hex.axial_to_world(Hex.oddr_to_axial(col, row), hex_radius)
	node.add_child(_prim(_cyl(0.012, 0.42, 6), Vector3(0, 0.21, 0), STONE))
	var cloth := BoxMesh.new()
	cloth.size = Vector3(0.14, 0.09, 0.015)
	var banner := _prim(cloth, Vector3(0.07, 0.36, 0), color)
	var mat := banner.material_override as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = color * 0.3
	node.add_child(banner)
	add_child(node)


# ── 单位 ──────────────────────────────────────────────


func _spawn_units() -> void:
	for setup in UNIT_SETUP:
		var profile: UnitProfile = load(setup[0])
		var cell := Hex.oddr_to_axial(setup[1], setup[2])
		var unit := _make_unit(profile, cell, setup[3])
		units[cell] = unit
		add_child(unit)


func _make_unit(profile: UnitProfile, cell: Vector2i, faction: int) -> Node3D:
	var unit := Node3D.new()
	unit.name = str(profile.id)
	unit.position = Hex.axial_to_world(cell, hex_radius)
	# 棋子底座（阵营色视觉语言）
	unit.add_child(_make_base(FACTION_COLORS[faction]))
	# 占位身躯：胶囊体（正式管线换 UnitProfile.model 的 PackedScene）
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.34
	var body := _prim(mesh, Vector3(0, 0.2, 0),
		_tint(STEEL, _hash01(cell.x, cell.y, 23) * 0.06 - 0.03))
	body.rotation.y = PI if faction == 1 else 0.0
	unit.add_child(body)
	unit.set_meta("profile", profile)
	unit.set_meta("faction", faction)
	unit.set_meta("cell", cell)
	return unit


func _make_base(color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.34
	mesh.bottom_radius = 0.34
	mesh.height = 0.06
	mesh.radial_segments = 24
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = 0.03
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.35
	mi.material_override = mat
	mi.name = "BaseRing"
	return mi


func _paint_base(unit: Node3D, color: Color) -> void:
	var base := unit.get_node_or_null("BaseRing") as MeshInstance3D
	if base != null:
		var mat := base.material_override as StandardMaterial3D
		mat.albedo_color = color
		mat.emission = color * 0.35


# ── 交互 ──────────────────────────────────────────────


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_handle_left_click(event.position)
			MOUSE_BUTTON_RIGHT:
				_clear_selection()


func _handle_left_click(screen_pos: Vector2) -> void:
	var cell := _pick_cell(screen_pos)
	if cell == Vector2i(9999, 9999):
		return
	if selected != null and cell in _reachable(selected_cell):
		_move_selected(cell)
		return
	if units.has(cell):
		_select_unit(cell)
	else:
		_clear_selection()


func _pick_cell(screen_pos: Vector2) -> Vector2i:
	var cam := get_viewport().get_camera_3d()
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.001:
		return Vector2i(9999, 9999)
	var t := -origin.y / dir.y
	if t < 0.0:
		return Vector2i(9999, 9999)
	return Hex.world_to_axial(origin + dir * t, hex_radius)


func _reachable(cell: Vector2i) -> Array:
	# demo 版：速度内的空格；正式版由引擎层寻路（含地形/占用/ZOC）
	var profile: UnitProfile = selected.get_meta("profile")
	var out := []
	for c in Hex.spiral(cell, profile.speed):
		if c != cell and not units.has(c) and not _is_water_oddr(c):
			out.append(c)
	return out


func _is_water_oddr(axial: Vector2i) -> bool:
	var oddr := Hex.axial_to_oddr(axial)
	return _is_water(oddr.x, oddr.y)


func _select_unit(cell: Vector2i) -> void:
	_clear_selection()
	selected = units[cell]
	selected_cell = cell
	_paint_base(selected, SELECT_COLOR)
	_reach_overlay = _spawn_reach_overlay(_reachable(cell))
	add_child(_reach_overlay)
	# 底座呼吸：选中态的心跳感
	var ring := selected.get_node_or_null("BaseRing") as MeshInstance3D
	if ring != null:
		var tw := create_tween().set_loops()
		tw.tween_property(ring, "scale", Vector3(1.14, 1.0, 1.14), 0.5)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(ring, "scale", Vector3.ONE, 0.5)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		selected.set_meta("breath", tw)


func _clear_selection() -> void:
	if selected != null:
		var faction: int = selected.get_meta("faction")
		_paint_base(selected, FACTION_COLORS[faction])
		if selected.has_meta("breath"):
			(selected.get_meta("breath") as Tween).kill()
			(selected.get_node_or_null("BaseRing") as MeshInstance3D).scale = Vector3.ONE
	selected = null
	if _reach_overlay != null:
		_reach_overlay.queue_free()
		_reach_overlay = null


## 可达范围覆盖层：金色六边形描边 + 极淡填充（合并单 mesh、不受光照）
func _spawn_reach_overlay(cells: Array) -> MeshInstance3D:
	const H := 0.06          # 覆盖层高度（瓦片顶面之上）
	const SHRINK := 0.94     # 内缩比，不压瓦片边缘
	const EDGE_W := 0.05     # 描边宽度
	var line_c := Color(1.0, 0.82, 0.25, 0.95)
	var fill_c := Color(1.0, 0.82, 0.25, 0.13)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in cells:
		var c := Hex.axial_to_world(cell, hex_radius)
		var ring_pts: Array[Vector3] = []
		for k in 6:
			var a := deg_to_rad(30.0 + 60.0 * k)  # pointy-top 顶点角
			ring_pts.append(c + Vector3(cos(a), 0.0, sin(a)) * hex_radius * SHRINK)
		# 填充：中心扇形 6 三角
		for k in 6:
			st.set_color(fill_c)
			st.add_vertex(c + Vector3.UP * H)
			st.add_vertex(ring_pts[k] + Vector3.UP * H)
			st.add_vertex(ring_pts[(k + 1) % 6] + Vector3.UP * H)
		# 描边：内外圈夹出宽度的四边形条
		for k in 6:
			var p1 := ring_pts[k]
			var p2 := ring_pts[(k + 1) % 6]
			var outward := ((p1 + p2) / 2.0 - c).normalized()
			var q1 := p1 - outward * EDGE_W
			var q2 := p2 - outward * EDGE_W
			st.set_color(line_c)
			st.add_vertex(p1 + Vector3.UP * H)
			st.add_vertex(p2 + Vector3.UP * H)
			st.add_vertex(q2 + Vector3.UP * H)
			st.add_vertex(p1 + Vector3.UP * H)
			st.add_vertex(q2 + Vector3.UP * H)
			st.add_vertex(q1 + Vector3.UP * H)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi


func _move_selected(target: Vector2i) -> void:
	var unit := selected
	var from: Vector2i = unit.get_meta("cell")
	_clear_selection()
	units.erase(from)
	units[target] = unit
	unit.set_meta("cell", target)
	# 逐格走（Hex.line 直线序列；正式版换引擎层寻路路径）
	var path := Hex.line(from, target)
	var tween := create_tween()
	for i in range(1, path.size()):
		tween.tween_property(unit, "position",
			Hex.axial_to_world(path[i], hex_radius), 0.16)
