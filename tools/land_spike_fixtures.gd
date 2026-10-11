## land_spike_fixtures.gd — LAND-S 固定小图 fixture（T2-SPIKE 附卡，2026-10-11；
##   执行方案 §3 LAND-S 测试锚原文：「测试场图 = make_fixed_maps 特征常量区先例的
##   固定小图（可复用为 LAND-01 矩阵图子集/子域）」）
## 职责：只定义 spike 测试场的格子布局（axial → 高程），特征常量写死、零随机
##   （tools/make_fixed_maps.gd:35-53 特征常量区先例）。布局独立成件后，LAND-01
##   矩阵图 / LAND-02 沙盒可直接 preload 取同一布局——复用不再停留在探针内私有
##   字典（2026-10-11 评审修复批抽件）。
## 合同：纯数据件、纯静态函数、零场景节点（ADR-2 同构）；不含 mesh/几何逻辑——
##   实验几何留在 land_spike_probe.gd 内，spike 件不进 addons/hexhammer 合同
##   （纪律同该文件头注）。
## 布局设计（执行方案 §3 LAND-S 技法移植设计「高程组合刻意铺」）：
##   · 七格俯视：中心 e0 + 六邻 e=[1,2,3,2,1,0]——绕中心 Δ 依次 1/2/3/2/1/0，
##     平(Δ0)/坡(Δ1)/阶地(Δ2)/真崖(Δ3) 四档全露；相邻邻格高差另覆盖混合角组合
##     （如 e2 邻 e3 的角 = 0/2/3 三格汇聚）——混合角目检口径 = 三边带汇聚，
##     角落补面属 LAND-01/LAND-02（取舍见 land_spike_probe.gd 头注）。
##   · 两格断面：中心 e0 + 方向 SECTION_DIR 邻格 eΔ——单边侧视直读台阶剖面/崖墙；
##     Δ2 = 阶地档、Δ3 = 真崖档（cliff_threshold 默认 3，执行方案 LAND-01 ①）。
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")

## 七格俯视图的高程铺法（特征常量先例：写死勿随机；序 = 方向 0..5 的邻格高程）
const OVERVIEW_NEIGHBOR_E := [1, 2, 3, 2, 1, 0]
## 断面图取边方向（六方向几何同构，写死方向 2；高程差由 section_cells 的入参给）
const SECTION_DIR := 2
## 断面档（cliff_threshold 默认 3 的两档直读样本：阶地 Δ2 / 真崖 Δ3）
const SECTION_TERRACE_DELTA := 2
const SECTION_CLIFF_DELTA := 3

## 七格俯视布局（返回新字典，调用方可自由改；中心恒 e0）
static func overview_cells() -> Dictionary:
	var cells := {Vector2i(0, 0): 0}
	for d in OVERVIEW_NEIGHBOR_E.size():
		cells[Hex.neighbor(Vector2i(0, 0), d)] = OVERVIEW_NEIGHBOR_E[d]
	return cells

## 两格断面布局（中心 e0 + 方向 SECTION_DIR 邻格 e=delta）。纯数据件不做入参
## 合同校验（delta ≤ 0 无意义），调用方自查——沿 make_fixed_maps「工具件无守卫」口径。
static func section_cells(delta: int) -> Dictionary:
	return {Vector2i(0, 0): 0, Hex.neighbor(Vector2i(0, 0), SECTION_DIR): delta}
