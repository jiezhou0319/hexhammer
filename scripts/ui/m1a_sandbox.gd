## m1a_sandbox.gd — M1a 沙盒场景脚本（T3 起供主创目检；04 M1a-T3「60×40 平地渲染流畅」）
## 用法：编辑器打开 scenes/m1a_sandbox.tscn → 运行当前场景（F6）。
## 项目约定**无主场景**（project.godot 不设 run/main_scene）——不要为本沙盒改变该约定。
## 内容：确定性公式铺 6 类地形色块（目检用占位生成，不是 T9 生成器）→
##   HexTerrainBuilder 产 chunk mesh → MapView 挂载（每 chunk 一个 MeshInstance3D）。
## 相机/灯为场景内固定摆位（固定俯角；正式策略相机 rig 属 M1a-T6）。
## 改尺寸/分块：选中根节点在检查器改导出参数后重跑场景即可。
extends Node3D

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const MapViewClass := preload("res://scripts/ui/map_view.gd")

@export var map_width := 60
@export var map_height := 40
@export var chunk_cols := 10
@export var chunk_rows := 10

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var map := MapDataClass.new(map_width, map_height)
	_fill_pattern(map)
	var view: MapViewClass = MapViewClass.new()
	view.name = "MapView"
	add_child(view)
	var ok := view.build(map, chunk_cols, chunk_rows)
	var elapsed := Time.get_ticks_msec() - t0
	if not ok:
		print("[M1a 沙盒] 构建失败：色表缺图内地形 id（检查 _fill_pattern 与默认色板）")
		return
	var chunks: Array = view.build_info["chunks"]
	var tris := 0
	var surfaces := 0
	for c in chunks:
		for s in c["surfaces"]:
			tris += s["index_count"] / 3
			surfaces += 1
	print("[M1a 沙盒] %d×%d 平地：%d chunk / %d surface / %d 三角形 / 构建+挂载 %d ms"
		% [map_width, map_height, chunks.size(), surfaces, tris, elapsed])
	print("[M1a 沙盒] 地形分布：", _type_counts(map))

## 目检地貌（确定性公式；水 3 正弦河 + 沙 4 岸 / 岩 2 / 林 5 / 泥 1 / 草 0 底）
func _fill_pattern(map) -> void:
	for cell in map.cells():
		var cr := Hex.offset_of(cell)
		var col := cr.x
		var row := cr.y
		var river := absf(float(col) - (18.0 + 8.0 * sin(float(row) * 0.22)))
		var terrain := 0
		if river < 1.7:
			terrain = 3
		elif river < 3.4:
			terrain = 4
		elif _dist2(col, row, 46, 11) < 52.0:
			terrain = 2
		elif _dist2(col, row, 13, 27) < 40.0:
			terrain = 5
		elif _dist2(col, row, 31, 33) < 26.0:
			terrain = 1
		map.set_terrain(cell, terrain)

func _dist2(col: int, row: int, cx: int, cy: int) -> float:
	var dx := float(col - cx)
	var dy := float(row - cy)
	return dx * dx + dy * dy

func _type_counts(map) -> Dictionary:
	var counts := {}
	for cell in map.cells():
		var t: int = map.terrain_at(cell)
		counts[t] = int(counts.get(t, 0)) + 1
	return counts
