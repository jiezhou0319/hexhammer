## art_trial.gd — M1a-T8 材质槽「换贴图即所见」试验场景（美术并行验证分支的
##   主线侧接口演示；docs/04-tasks-m1.md M1a-T8 + docs/notes/m1a-t8-art-branch.md）
## 用法：编辑器打开 scenes/art_trial.tscn → 运行当前场景（F6）。
##   按键 1 = 主线默认色块库（terrain_materials_default.tres）
##   按键 2 = 贴图试验库（terrain_materials_textured_trial.tres，art_tests 草贴图）
##   ——同一 MapView.build 接口、只换材质表资源重建：几何/UV/索引逐位不变
##   （tests/test_hex_terrain_materials.gd 的换表不变量锚定），此即
##   「分支上换贴图/纹理直接看效果，主线代码零改动」的运行时形态。
## 目检点（主创，04 M1a-T8 验收的目测项载体）：
##   - 按 2：顶面草纹无缝连续平铺（世界平面 UV：贴图跨格流动、无镜像接缝）；
##   - 斜坡（Δ1）竖向半幅纹、陡壁（Δ2）恰一整幅纹（侧面 v = −y/2R 约定）；
##   - 泥 = 草贴图 × 棕 tint、岩 = 另一张草裁片 × 冷 tint（同表混用贴图/色块/乘色）；
##   - 按 1 回色块库：主线观感与 T3~T7 时代一致（只换回表，不动代码）。
## 地貌（确定性公式）：12×8、草0/泥1/岩2、西→东阶梯 0/1/2 层 + 南侧直落 0 层
##   ——平顶/平连/斜坡/陡面四类面齐备（侧面 UV 各有目检对象）。
## 场景灯/环境固定摆位（同 m1a_sandbox）；相机 = 固定斜视（本场景只验材质，
## 不挂拾取/高亮/策略相机——那是 m1a_sandbox 的事；相机位姿可在 _ready 微调）。
## view 层纪律：本文件属 scripts/ui/**，可被整体删除——tests/ 不感知本文件。
extends Node3D

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const TerrainMaterialLibraryClass := preload("res://scripts/core/data/terrain_material_library.gd")
const MapViewClass := preload("res://scripts/ui/map_view.gd")

const MAP_W := 12
const MAP_H := 8

var _map: MapDataClass = null
var _view: MapViewClass = null
var _libs: Dictionary = {}  # 按键码 → TerrainMaterialLibrary（懒加载缓存）


func _ready() -> void:
	_map = _make_trial_map()
	_view = MapViewClass.new()
	_view.name = "MapView"
	add_child(_view)
	_setup_camera()
	# 默认开局即贴图试验库（本场景的展示对象）；按 1 可切回主线色块库对照
	_switch_library(KEY_2)
	print("[T8 试验] 12×8 阶梯图已就绪：按 1 = 色块库（主线默认）/ 按 2 = 贴图试验库")
	print("[T8 试验] 目检：顶面草纹整图连续平铺；斜坡半纹/陡壁一整纹（侧面 UV v=−y/2R）")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_1 or key == KEY_2:
			_switch_library(key)


## 换库 = 同接口重建（MapView.build 只吃 {terrain_id: Material} 表——库是 .tres 载体）。
func _switch_library(key: int) -> void:
	if not _libs.has(key):
		var path: String = TerrainMaterialLibraryClass.DEFAULT_PATH if key == KEY_1 \
			else TerrainMaterialLibraryClass.TRIAL_TEXTURED_PATH
		var lib := TerrainMaterialLibraryClass.load_at(path)
		if lib == null:
			print("[T8 试验] 材质库载入失败：", path)
			return
		var missing: Array[int] = lib.missing_ids(_map)
		if not missing.is_empty():
			print("[T8 试验] 材质表缺图内地形 id：", missing)
			return
		_libs[key] = lib
	var lib: TerrainMaterialLibraryClass = _libs[key]
	var ok := _view.build(_map, 6, 4, lib.materials, 1.0, 1.0)
	print("[T8 试验] 已切库：", lib.resource_path, " → 构建", "成功" if ok else "失败")


## 试验地貌：西段草 0 层 → 中段泥 1 层 → 东段岩 2 层（两条 Δ1 斜坡带）；
## 南侧两行整体压回 0 层 → 与北侧 2 层台地成 Δ2 陡壁（侧面 UV 目检对象）。
func _make_trial_map() -> MapDataClass:
	var m := MapDataClass.new(MAP_W, MAP_H)
	for cell in m.cells():
		var cr := Hex.offset_of(cell)
		var col := cr.x
		var row := cr.y
		var h := 0
		if col >= 4 and col <= 7:
			h = 1
		elif col >= 8:
			h = 2
		if row >= 6:
			h = 0
		m.set_elevation(cell, h)
		m.set_terrain(cell, h)  # 0 草 / 1 泥 / 2 岩——层位即类型，边界即换材质处
	return m


## 固定斜视相机：覆盖全图中心、能同时看到顶面与南侧陡壁（位姿可按需微调）。
func _setup_camera() -> void:
	var center := Vector3.ZERO
	for cell in _map.cells():
		center += Hex.axial_to_world(cell, 1.0)
	center /= float(_map.cell_count())
	var cam := Camera3D.new()
	cam.name = "TrialCamera"
	cam.fov = 60.0
	cam.near = 0.1
	cam.far = 200.0
	var dir := Vector3(0.28, 0.72, 0.63).normalized()
	cam.position = center + dir * 24.0
	add_child(cam)  # 先入树再 look_at（Node3D.look_at 要求节点已在场景树内）
	cam.look_at(center, Vector3.UP)
	cam.current = true
