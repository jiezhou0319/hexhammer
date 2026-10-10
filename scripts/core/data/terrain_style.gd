## terrain_style.gd — 地形渲染 style 配置载体（M1a+ BLEND-03；docs/04-tasks-m1.md
##   §M1a+ 第一批卡「纹理可替换，不改世界事实」+ docs/M1a-terrain-world-proposal.md
##   「换美术者」用户故事 /「表现升级不改变尚未拍板的移动费、伤害与视野规则」）
## 职责：把「这张图怎么画」钉成一个资源（.tres，检查器可换——沿用 M1a-T8
##   TerrainMaterialLibrary 的资源化先例）：mode 选材质槽（色块）或色板权重混合
##   （过渡）路线，material_library 是两条路线共同的外观来源——**换 .tres / 换库
##   = 换观感，世界事实（MapData）与拾取/face 表零接触**。BLEND-03 的验收口径：
##   同图换 style → MapData.summary() 逐字节一致、mesh ARRAY_INDEX 与 face 表逐位
##   一致、连通性一致、材质实例确不同（headless 锚 = tests/test_terrain_style.gd）。
## 约定（翻案须先改 04 §M1a+ 与 tests/test_terrain_style.gd，不动架构）：
## - mode ∈ {SLOTS, BLEND}：
##   · SLOTS = 旧单材质 fallback（HexTerrainBuilder.build_map 材质槽路线，
##     边带/角落按归属格单材质硬切——保留为可一键退回的对照档）；
##   · BLEND = 色板权重混合（build_map_blend 顶点 COLOR 路线，M1a+ BLEND-01/02
##     的过渡合同）；palette 从 material_library 提取（palette_from_materials 同源
##     口径：逐槽取 StandardMaterial3D.albedo_color）——与 fallback 共用同一库，
##     换库即两风格同时换观感（BLEND-01 已落的数据路径，本类只把它收进 style）。
## - blend_material：BLEND 模式的顶点色 albedo 导管（官方工厂 =
##   HexTerrainBlend.make_blend_material，.tres 里烘焙为其产物属性；自定义 shader
##   读 COLOR 同样合法——builder 只认 Material，语义由调用方保证）。SLOTS 模式
##   忽略本字段（留 null 合法）；BLEND 模式缺失 → 解析显式失败（顶点色导管是
##   合同一部分，BLEND-01 已锚）。
## - 解析面（inputs_for）：style + 图 → 构建输入，**只对图内被用到的地形 id 做
##   预检/取值**（与 builder「先全图预检后建」同口径；库里多余的槽不挡图——
##   未用到的非 StandardMaterial3D 槽不构成失败，BLEND 色板提取按用到的 id 逐个提）。
##   SLOTS → {"mode":"slots", "materials":{用到的 id: Material}}；
##   BLEND → {"mode":"blend", "palette":{用到的 id: Color}, "blend_material": Material}。
##   非法（库缺失/缺槽/槽值类型不符/BLEND 缺导管）→ null（无隐式兜底，不静默换路线）。
## - 纯 Resource：零场景节点（ADR-2）；不写 MapData、不参与任何结算/查询/摘要
##   （表现层数据，提案「世界事实/游戏规则/表现三层分离」的表现层）。
## 维护方式（ADR-3 编辑器原生编辑）：双击 .tres 在检查器换 mode/库/导管材质即可；
## 代码内默认（make_default_slots/make_default_blend）与 .tres 同源，tests 锚定
## 两者口径一致（防漂移，与 TerrainMaterialLibrary.build_default 同纪律）。
class_name TerrainStyle
extends Resource

const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const TerrainMaterialLibraryClass := preload("res://scripts/core/data/terrain_material_library.gd")
const HexTerrainBlendClass := preload("res://addons/hexhammer/hex_terrain_blend.gd")

## 色块默认 style（.tres）路径——SLOTS 模式 + 主线默认材质库
const SLOTS_DEFAULT_PATH := "res://resources/terrain/styles/terrain_style_slots_default.tres"

## 混合过渡默认 style（.tres）路径——BLEND 模式 + 主线默认材质库 + 官方导管材质
const BLEND_DEFAULT_PATH := "res://resources/terrain/styles/terrain_style_blend_default.tres"

## 渲染路线（与 HexTerrainBuilder 双入口一一对应）
enum Mode {
	SLOTS,  # 材质槽路线（build_map；边带按归属格单材质——对照/退回档）
	BLEND,  # 色板权重混合路线（build_map_blend；顶点 COLOR 过渡，M1a+ BLEND-01/02）
}

@export var mode: Mode = Mode.BLEND
## 材质槽/色板共同来源（两风格同源；换库 = 两风格同时换观感）
@export var material_library: TerrainMaterialLibraryClass
## BLEND 模式的顶点色 albedo 导管（SLOTS 模式忽略；BLEND 缺失 → 解析失败）
@export var blend_material: Material


## 载入 style .tres；路径不存在 / 类型不符 → null（显式失败，调用方判空）。
static func load_at(path: String) -> TerrainStyle:
	var res: Variant = load(path)
	if res is TerrainStyle:
		return res as TerrainStyle
	return null


## 载入色块默认 style（缺失/损坏 → null）。
static func load_default_slots() -> TerrainStyle:
	return load_at(SLOTS_DEFAULT_PATH)


## 载入混合过渡默认 style（缺失/损坏 → null）。
static func load_default_blend() -> TerrainStyle:
	return load_at(BLEND_DEFAULT_PATH)


## 代码内默认色块 style（.tres 的再生成/对账基准——tests 锚定两者口径一致）：
## SLOTS + 主线默认材质库（blend_material 留空 = SLOTS 忽略）。
static func make_default_slots() -> TerrainStyle:
	var s := new()
	s.mode = Mode.SLOTS
	s.material_library = TerrainMaterialLibraryClass.load_default()
	return s


## 代码内默认混合过渡 style（对账基准）：BLEND + 主线默认材质库 + 官方导管材质。
static func make_default_blend() -> TerrainStyle:
	var s := new()
	s.mode = Mode.BLEND
	s.material_library = TerrainMaterialLibraryClass.load_default()
	s.blend_material = HexTerrainBlendClass.make_blend_material()
	return s


# ---------------- 解析（style + 图 → 构建输入） ----------------

## 图内被用到的地形 id 集合（行主序首现序——与 builder 预检同遍历口径）。
func used_terrain_ids(map: MapDataClass) -> Array[int]:
	var out: Array[int] = []
	for cell in map.cells():
		var tid := map.terrain_at(cell)
		if tid != MapDataClass.TERRAIN_NONE and not out.has(tid):
			out.append(tid)
	return out


## style 对这张图是否可解析的人读问题清单（空数组 = 可解析）。
## 与 inputs_for 同一判定口径——本方法给人看（沙盒/工具显式报缺），inputs_for
## 给管线兜底（沿用 TerrainMaterialLibrary.missing_ids 的双保险分工）。
func problems_for(map: MapDataClass) -> Array[String]:
	var out: Array[String] = []
	if material_library == null:
		out.append("材质库未设置（material_library = null）")
		return out
	if mode == Mode.BLEND and blend_material == null:
		out.append("BLEND 模式缺 blend_material（顶点色导管是合同一部分）")
	for tid in used_terrain_ids(map):
		var mat: Variant = material_library.material_for(tid)
		if mat == null:
			out.append("地形 id %d 缺材质槽（或槽值非 Material）" % tid)
		elif mode == Mode.BLEND and not (mat is StandardMaterial3D):
			out.append("BLEND 模式：地形 id %d 非 StandardMaterial3D（取不到 albedo_color 色板）" % tid)
	return out


## 解析成构建输入（MapView.build_with_style 消费；键集见类头注）。
## 任一问题（problems_for 非空）→ null——不静默换路线、不补默认材质。
func inputs_for(map: MapDataClass) -> Variant:
	if not problems_for(map).is_empty():
		return null
	var used := used_terrain_ids(map)
	if mode == Mode.BLEND:
		var palette := {}
		for tid in used:
			# problems_for 已保证槽值是 StandardMaterial3D（用到的 id 才提——
			# 库里未用到的非标准槽不挡图）
			palette[tid] = (material_library.material_for(tid) as StandardMaterial3D).albedo_color
		return {
			"mode": "blend",
			"palette": palette,
			"blend_material": blend_material,
		}
	var materials := {}
	for tid in used:
		materials[tid] = material_library.material_for(tid)
	return {
		"mode": "slots",
		"materials": materials,
	}


## 人读标签（沙盒/日志用）：mode + 库/导管来源。
func label() -> String:
	if mode == Mode.BLEND:
		return "BLEND（色板权重混合，M1a+ BLEND-01/02 过渡合同）"
	return "SLOTS（材质槽色块——旧单材质 fallback 对照档）"
