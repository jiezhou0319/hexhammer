## hex_terrain_blend.gd — 相邻地形材质过渡的纯逻辑合同（M1a+ BLEND-01 边带两格权重 /
##   BLEND-02 角落三格权重；docs/04-tasks-m1.md §M1a+ 第一批卡 +
##   docs/M1a-terrain-world-proposal.md「材质过渡」/「材质升级的最小安全路径」）
## 职责：把「边带两地形权重 / 角落三地形权重」从渲染实现里拆出来，钉成可 headless
##   锚定的数据合同——权重函数、权重合法性、色板→颜色映射、{terrain_id: Material}→
##   色板提取、blend 通道材质工厂。mesh 构建入口在 hex_terrain_builder.gd 的 *_blend
##   系列（顶点 COLOR 承载权重结果，沿用 raw 顶点/渲染索引双层口径，
##   几何/UV/索引/face 表零改动——测试锚定）。
## 约定（翻案须先改 04 §M1a+ 与 tests/test_hex_terrain_blend.gd，不动架构）：
## - 边带参数 t ∈ [0,1]：0 = 归属格内边（owner 权重 1）、1 = 邻格内边（owner 权重 0）；
##   端点权重 (1,0)/(0,1)、中点 (0.5,0.5)、任意 t 权重和恒 1（有限、非负）——提案
##   「只有混合权重插值，并满足有限、非负且和为 1」的可测表达；
## - mesh 侧**不设中点顶点**（细分边带会改面数 → 动 face 表/碰撞合同，表现层切片
##   不许——04 §M1a+ BLEND-01 实现要点 5）：端点写纯色，带内过渡 = 顶点 COLOR 的
##   GPU 线性插值；边带为仿射参数（v3 = v1 + bridge），线性插值在几何中点恰为
##   0.5 权重混合——测试用 blend_color 链路锚定该等价（不依赖跑帧）；
## - 中心主地形纯度（提案业务目标「避免一张地图全变成泥色」）：顶面（格心扇面）
##   全部顶点 = 本格纯色，不参与任何混合；角落三角顶点 = 三格权重合同
##   （corner_weights，M1a+ BLEND-02）的单位权重锚点——p1=归属格 (1,0,0)、
##   p2=N(k) 侧 (0,1,0)、p3=N(k−1) 侧 (0,0,1)，面内三色过渡 = 顶点 COLOR 线性插值
##   （重心 = (1/3,1/3,1/3) 权重混合；两格同色角自动退化为边带合同口径）；
## - 三格角落最多混合三种地形（提案「每三角形最多三种地形索引」的最小落地 =
##   色板权重版）：角面顶点按相邻三格权重混合、权重和恒 1——跨 chunk 时角面
##   锚点仍从同一全局参数计算（T4 归属规则不动，权重/颜色不随 chunk 划分改变；锚见
##   tests/test_hex_terrain_blend_corner.gd）；
## - 权重/色板是**独立渲染数据**：不写进 MapData/寻路/战斗等规则与逻辑层
##   （提案「表现升级不改变尚未拍板的移动费、伤害与视野规则」）；
## - 色板（palette = {terrain_id: Color}）约定 alpha=1（混合含 alpha 通道，opaque
##   地形不透明度不吃权重）；本文件纯静态函数、零场景节点（ADR-2；删 scripts/ui/**
##   不影响本文件与 tests/）。
class_name HexTerrainBlend
extends RefCounted

# ---------------- 权重合同 ----------------

## 边带权重：t = 0（归属格内边）→ (1, 0)；t = 1（邻格内边）→ (0, 1)；
## 返回 (owner 权重, 邻格权重)。t 的渲染合同域为 [0,1]（域外线性外推不构成合同，
## 由 is_valid_weights 侧拒绝——函数本身保持纯线性、无隐藏钳制）。
static func edge_weights(t: float) -> Vector2:
	return Vector2(1.0 - t, t)


## 权重合法性（提案口径：有限、非负、和为 1）。eps 默认 1e-6（浮点求和的合理窗口）。
static func is_valid_weights(w: Vector2, eps := 1e-6) -> bool:
	return is_finite(w.x) and is_finite(w.y) and w.x >= 0.0 and w.y >= 0.0 \
		and absf(w.x + w.y - 1.0) <= eps

# ---------------- 三格权重合同（M1a+ BLEND-02；三格交汇与跨 chunk 过渡） ----------------

## 角落三格权重（重心参数）：角面三角形 = p1 + u·bridge_k + v·bridge_{k−1} 的仿射
## 参数域（p1 = 归属格内顶点、p2 = p1+bridge_k（N(k) 侧端点）、p3 = p1+bridge_{k−1}
## （N(k−1) 侧端点））。u = 朝 N(k) 侧参数、v = 朝 N(k−1) 侧参数；返回
## (归属格权重, N(k) 权重, N(k−1) 权重)。锚点：p1 → (1,0,0)、p2 → (0,1,0)、
## p3 → (0,0,1)、角面重心 (u=v=1/3) → (1/3,1/3,1/3)。合同域 =
## {(u,v)：u,v ≥ 0 且 u+v ≤ 1}（域外线性外推不构成合同，由 is_valid_weights3 侧
## 拒绝——与 edge_weights 同纪律，函数保持纯线性、无隐藏钳制）。
## 与两格合同的关系：任两格同色时三格混合逐通道退化为 blend_color（边带口径）——
## 「角混三种」的最大=3、常见=2 由同一合同覆盖（测试锚定）。
static func corner_weights(u: float, v: float) -> Vector3:
	return Vector3(1.0 - u - v, u, v)


## 三格权重合法性（与两格合同同一口径：有限、非负、和为 1）。非负项带 −eps
## 浮点零点窗口：u+v=1 边界上 1−u−v 有 ≤1 ulp 的负舍入（如 u=0.9,v=0.1 →
## −2.8e-17，float32 存储后仍为负）——与「和为 1」的 eps 窗口同一浮点口径，
## 合同语义仍是数学非负（真负权重 ≫ eps 照拒，见测试拒绝锚）。
static func is_valid_weights3(w: Vector3, eps := 1e-6) -> bool:
	return is_finite(w.x) and is_finite(w.y) and is_finite(w.z) \
		and w.x >= -eps and w.y >= -eps and w.z >= -eps \
		and absf(w.x + w.y + w.z - 1.0) <= eps


## 三格混合色：(归属格, N(k), N(k−1)) 权重 w 下的逐通道加权和（含 alpha；色板约定
## alpha=1 → 混合后仍 1）。单位权重 → 对应格纯色（角面顶点即合同单位权重锚点）、
## (1/3,1/3,1/3) → 三纯色均值——也是 mesh 角面「顶点纯色 → 面内线性插值」的同一
## 映射（测试用它锚重心等价，与 BLEND-01 的 blend_color 中点链路同构）。
static func blend_color3(c_owner: Color, c_nbk: Color, c_nbk1: Color, w: Vector3) -> Color:
	return c_owner * w.x + c_nbk * w.y + c_nbk1 * w.z

# ---------------- 色板 → 颜色映射 ----------------

## 混合色：owner 权重 w 下的逐通道混合（含 alpha；色板约定 alpha=1 → 混合后仍 1）。
## w=1 → owner 纯色、w=0 → 邻格纯色、w=0.5 → 两纯色均值——与边带端点/中点权重
## 一一对应，也是 mesh 端点纯色 → 带内线性插值的同一映射（测试用它锚中点等价）。
static func blend_color(color_owner: Color, color_neighbor: Color, weight_owner: float) -> Color:
	return color_owner * weight_owner + color_neighbor * (1.0 - weight_owner)


## {terrain_id: Material（StandardMaterial3D）} → {terrain_id: Color}：blend 色板的
## 常规来源——与 fallback 材质槽共用同一 .tres 库（TerrainMaterialLibrary），
## 换表即两风格同时换观感。任一槽值非 StandardMaterial3D（取不到 albedo_color，
## 如自定义 ShaderMaterial）→ null（显式失败，无静默兜底）。
static func palette_from_materials(materials: Dictionary) -> Variant:
	var out := {}
	for tid in materials:
		var m: Variant = materials[tid]
		if not (m is StandardMaterial3D):
			return null
		out[tid] = (m as StandardMaterial3D).albedo_color
	return out

# ---------------- blend 通道材质 ----------------

## blend 通道材质（顶点色 albedo 的已知良好导管）：白 albedo × 顶点 COLOR。
## 材质须开 vertex_color_use_as_albedo 才能看到过渡——本工厂是该口径的官方来源；
## builder 只要求 blend_material 为 Material，自带自定义 shader 读 COLOR 同样合法
## （语义由调用方保证，builder 不校验 shader 内部——「无隐式兜底」不给假保证）。
static func make_blend_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat
