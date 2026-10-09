## terrain_material_library.gd — 地形材质槽映射表（M1a-T8；docs/04-tasks-m1.md M1a-T8 +
##   docs/02-architecture.md ADR-3「内容数据用 Godot Resource」+ M1a 实现调研
##   「Mesh、分块与材质：先可读，再优化」——「类型到材质：terrain_id → Material.tres」）
## 职责：terrain_id → Material 的资源化载体（.tres），是渲染管线材质槽的唯一来源——
##   **换贴图/换色 = 换/改本表资源，主线代码（builder/MapView/场景脚本）零改动**
##   （04 M1a-T8 验收「分支上换贴图/纹理直接看效果，主线代码零改动」的接口面；
##   几何不变性由 tests/test_hex_terrain_materials.gd 的换表不变量锚定）。
## 约定（与 hex_terrain_builder.gd 头注同源；翻案须同步改测试锚，不动架构）：
## - materials 键 = MapData 地形 id（int，非负；语义由内容层定），值 = Material；
##   builder 侧只认 {int: Material} 平面表——本类 .materials 直接透传即可；
## - 主线默认表 = resources/terrain/terrain_materials_default.tres（色块起步：
##   6 类型 StandardMaterial3D，颜色 = DEFAULT_PALETTE——测试锚定 .tres 与代码同源）；
## - 贴图试验表 = resources/terrain/terrain_materials_textured_trial.tres（M1a-T8
##   美术并行验证分支的产物示例：art_tests 草贴图 albedo_texture + tint 混色，
##   使用说明与合并路径见 docs/notes/m1a-t8-art-branch.md）；
## - 色块材质不开 vertex_color_use_as_albedo（builder 无顶点色路线，04 M1a-T3 细化）；
## - 纯 Resource：零场景节点（ADR-2；删 scripts/ui/** 不影响本文件与 tests/）。
## 维护方式（ADR-3 编辑器原生编辑）：双击 .tres 在检查器改材质/贴图/颜色即可，
## 无需重跑生成脚本；DEFAULT_PALETTE 变更时以 build_default() + ResourceSaver 再存
## 一次 .tres（tests 会锚定两者逐类型同色，防止口径漂移）。
class_name TerrainMaterialLibrary
extends Resource

const MapDataClass := preload("res://scripts/core/data/map_data.gd")

## 主线默认色块库（.tres）路径
const DEFAULT_PATH := "res://resources/terrain/terrain_materials_default.tres"

## 贴图试验库（.tres）路径——美术并行验证分支的产物示例
const TRIAL_TEXTURED_PATH := "res://resources/terrain/terrain_materials_textured_trial.tres"

## 默认色板（色块起步的占位语义；与 terrain_materials_default.tres 同源，
## tests/test_hex_terrain_materials.gd 锚定一致——「类型→含义」仍由内容层定）
const DEFAULT_PALETTE := {
	0: Color(0.36, 0.54, 0.30),  # 草
	1: Color(0.55, 0.45, 0.30),  # 泥
	2: Color(0.52, 0.52, 0.56),  # 岩
	3: Color(0.25, 0.40, 0.60),  # 水
	4: Color(0.78, 0.70, 0.45),  # 沙
	5: Color(0.20, 0.38, 0.22),  # 林
}

## 材质槽表：地形 id → Material（builder 的材质槽唯一来源；值非法由消费侧拒绝）
@export var materials: Dictionary[int, Material] = {}


## 载入 .tres 库；路径不存在 / 类型不符 → null（显式失败，调用方判空，无静默兜底）。
static func load_at(path: String) -> TerrainMaterialLibrary:
	var res: Variant = load(path)
	if res is TerrainMaterialLibrary:
		return res as TerrainMaterialLibrary
	return null


## 载入主线默认色块库（缺失/损坏 → null）。
static func load_default() -> TerrainMaterialLibrary:
	return load_at(DEFAULT_PATH)


## 槽查询：缺槽 / 值非法 → null（不抛错、不兜底——「无隐式兜底」口径）。
func material_for(terrain_id: int) -> Material:
	var v: Variant = materials.get(terrain_id, null)
	if v is Material:
		return v as Material
	return null


func has_material(terrain_id: int) -> bool:
	return material_for(terrain_id) != null


## 图内被用到而本表缺材质的地形 id 清单（空数组 = 覆盖完整；顺序按图内首现）。
## 供 view 层/工具在构建前显式报缺（builder 侧另有同口径硬校验，双保险不冗余：
## 一个给人看、一个给管线兜底）。
func missing_ids(map: MapDataClass) -> Array[int]:
	var out: Array[int] = []
	for cell in map.cells():
		var tid := map.terrain_at(cell)
		if tid != MapDataClass.TERRAIN_NONE and not out.has(tid) and not has_material(tid):
			out.append(tid)
	return out


## 色块材质（色块起步口径；无顶点色路线 → 不开 vertex_color_use_as_albedo）。
static func make_color_block(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## 色表 → 材质表（{int: Color} → {int: Material}）：测试/工具自建槽表的便捷入口
## （主线管线不再从颜色合成材质——builder 只认现成 Material 表）。
static func materials_from_colors(colors: Dictionary) -> Dictionary:
	var out := {}
	for tid in colors:
		out[tid] = make_color_block(colors[tid])
	return out


## 代码内默认库：与 DEFAULT_PALETTE 同源（.tres 的再生成/对账基准——
## tests 锚定 load_default() 与本函数逐类型同色）。
static func build_default() -> TerrainMaterialLibrary:
	var lib := new()
	for tid in DEFAULT_PALETTE:
		lib.materials[tid] = make_color_block(DEFAULT_PALETTE[tid])
	return lib
