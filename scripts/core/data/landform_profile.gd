## landform_profile.gd — 几何级地貌档配置载体（M1a T2 阶地高程；执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §3 LAND-02 ⑥ + §8.1 不变量分档）
## 职责：把「这张图的地貌长什么几何形状」钉成一个资源（.tres 可换，TerrainStyle
##   资源化先例）——阶地开关/步数、真垂直崖开关、崖分档阈值。**几何级 ≠ 材质级**：
##   换 TerrainStyle（材质档）mesh 逐位不变；换 LandformProfile（几何档）mesh/face
##   表/碰撞汤**允许变**，不变量退为「MapData.summary / world_digest / 连通性
##   逐位一致」（§8.1 分档表——04 落「几何级 profile ≠ 材质级 style」不变量分档字）。
## 合同（翻案须先改 04 与 tests/test_landform_terraces.gd，不动架构）：
## - terrace_enabled：阶地开关。Δ∈[2, cliff_threshold) 的边带按 terrace_lerp
##   剖面细分（LAND-02 ①）；false = 该档退回单斜面两级三角（现基线几何）。
## - terrace_steps：**每爬升一级**的阶地步数（步数-Δ 绑定：Δn 边带 = n 组串联，
##   组间边界环恰落在高程整数层——LAND-02 ①/修订记录二 ③）。默认 5 = Catlike
##   Part 3 原档；LAND-S spike 候选 3/5 待主创目检拍板，改默认值零返工（本档只改数字）。
## - cliff_vertical：真垂直崖开关。Δ≥cliff_threshold 的边带 = 共享崖线 XZ 上
##   同 XZ 墙顶/墙底 + 高低平台裙边（修订记录三之 3——四点直连只是 80° 陡面，
##   非竖直墙）；false = 退回现 80° 陡面（过渡态，builder 头注自认）。
## - cliff_threshold：cliff 分档阈值（LAND-01 ①：cliff = Δ≥threshold，默认 3；
##   阈值属构建参数/几何 profile，不进 MapData——§2.5「高差分档阈值不进 MapData」）。
## - 退回开关（LAND-02 ⑥）：terrace_enabled=false 且 cliff_vertical=false 时，
##   **几何（mesh 数组）与不传 profile（null）逐位一致**——同一基线发射分支，
##   UV 只分 Δ0/非Δ0、不随阈值变；faces 元数据的 edge_type 标签仅在
##   cliff_threshold ≠ 默认 3 时于档位边界切换（Δ∈[3,threshold) 边记 terrace
##   而基线记 cliff——分类随阈值切换是 LAND-01 ② 的行为，非违约）。默认阈值下
##   mesh 与 faces 元数据均逐位一致——tests/test_landform_terraces.gd 的回退锚
##   两侧对照（null / 全关 profile），非默认阈值档另有几何一致 + 标签切换锚。
## - 纯 Resource：零场景节点（ADR-2）；不写 MapData、不参与任何结算/查询/摘要
##   （表现层数据——「换档不改世界事实」的 §8.1 不变量由测试锚定）。
## 维护方式（ADR-3 编辑器原生编辑）：双击 .tres 在检查器改档；代码内默认
##   make_default() 与 .tres 同源（TerrainStyle.make_default_* 同纪律）。
class_name LandformProfile
extends Resource

## 默认档 .tres 路径（主线默认 = 阶地开 + 真崖开 + 阈值 3——拍板③「阶地棋盘感
## 默认」+ 拍板「崖壁暂保留真垂直」）
const DEFAULT_PATH := "res://resources/terrain/landform_profile_default.tres"

## Catlike Part 3 原档步数（5 步剖面 = 2 平台 + 3 短坡；LAND-S spike 候选 3 并列，
## 默认值拍板前不动）
const DEFAULT_TERRACE_STEPS := 5
## 执行方案 LAND-01 ① 默认分档：Δ≥3 走真垂直崖、阶地仅 Δ2
const DEFAULT_CLIFF_THRESHOLD := 3

## 阶地开关（Δ∈[2, threshold) 边带细分；false = 单斜面回退）
@export var terrace_enabled := true
## 每爬升一级的阶地步数（Δn = n 组串联；≥2——steps=1 退化为单斜面、无阶地语义）
@export var terrace_steps: int = DEFAULT_TERRACE_STEPS
## 真垂直崖开关（Δ≥threshold 边带 = 墙顶/墙底同 XZ 的竖直墙 + 裙边；false = 80° 陡面）
@export var cliff_vertical := true
## cliff 分档阈值（cliff = Δ≥threshold；≥2——=2 时阶地档为空集，档位无意义）
@export var cliff_threshold: int = DEFAULT_CLIFF_THRESHOLD


## 载入 .tres 档；路径不存在 / 类型不符 → null（显式失败，调用方判空）。
static func load_at(path: String) -> LandformProfile:
	var res: Variant = load(path)
	if res is LandformProfile:
		return res as LandformProfile
	return null


## 载入主线默认档（缺失/损坏 → null）。
static func load_default() -> LandformProfile:
	return load_at(DEFAULT_PATH)


## 代码内默认档（.tres 的再生成/对账基准——tests 锚定两者口径一致，防漂移）。
static func make_default() -> LandformProfile:
	var p := new()
	p.terrace_enabled = true
	p.terrace_steps = DEFAULT_TERRACE_STEPS
	p.cliff_vertical = true
	p.cliff_threshold = DEFAULT_CLIFF_THRESHOLD
	return p


## 人读问题清单（空 = 合法档）。与 is_valid 同一判定口径——本方法给沙盒/工具
## 显式报缺，builder 用 is_valid 兜底（TerrainStyle.problems_for 双保险分工先例）。
func problems() -> Array[String]:
	var out: Array[String] = []
	if terrace_steps < 2:
		out.append("terrace_steps < 2（步数 1 退化为单斜面，无阶地语义——LAND-02 ①）")
	if cliff_threshold < 2:
		out.append("cliff_threshold < 2（=2 时阶地档 [2,threshold) 为空集，分档无意义——LAND-01 ①）")
	return out


func is_valid() -> bool:
	return problems().is_empty()


## 人读标签（沙盒/日志用）。
func label() -> String:
	return "阶地 %s（步数 %d）/ 真崖 %s / 阈值 %d" % [
		"开" if terrace_enabled else "关", terrace_steps,
		"开" if cliff_vertical else "关", cliff_threshold]
