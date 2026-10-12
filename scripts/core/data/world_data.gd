## world_data.gd — 世界事实层容器 + 邻接边索引 + 河段/水体/道路/桥/POI/势力归属
##   （M1a T2 首物 → T3 水系 → T4 道路桥 → T5 聚落势力解锁；执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §2.5 + §2.2/§2.3/§2.4（格边重议已拍，
##   §2.6 全关）+ §4 WATER-01/03 + §5 ROAD-01/02 + §6 WORLD-03/05 + §7 + 数据合同
##   草案 docs/M1a-terrain-data-contract-draft.md §3~§12）
## 职责：格子数据（MapData）旁边的**第四伴生文件 `<name>.world.json`** 载体——
##   NeighborLinkData 邻接边表（link_id = (min,max) 格稳定 ID 对）+ RiverReachData
##   格边河段（§2.2 重写表：河 = 共享边有序序列，ADR-14）+ WaterBodyData 湖/海
##   （格语义水体，WATER-03 转正）+ RoadData 道路（§7 转正，ROAD-01：格心有序
##   序列 + link.road_id 对账）+ CrossingData 桥（§8 格边重写表，ROAD-02：认领
##   语义——「路是格中心与格中心之间，河是单纯沿着边，他俩只会交叉，交叉时就是
##   桥」，拍板⑤）+ POIData 聚落/出生区/资源点（§9 转正，WORLD-03：role 占位、
##   资源经济数值不编造）+ 势力归属（StateData + 格级 cell_owners——拍板⑧：
##   归属作为生成产物进数据，「生成的世界长什么样」进数据、「怎么玩」不进；
##   ~~势力归属禁入数据层~~ 穿格期旧口径已废）+ 校验器 + 序列化（固定键序）。
## 合同（翻案须先改草案对应节与 tests/test_world_data.gd / test_water_*.gd /
##   test_roads.gd / test_bridges.gd，不动架构）：
## - 旧图零迁移（§2.2）：伴生文件缺失/为空 → empty()（无河无路无 POI 的合法态），
##   不报错、不重新随机生成——MapData 的 dict 与 SCHEMA_VERSION=1 零改动；
## - **Vector2i（link_id）不得直接交给 JSON.stringify**（引擎 4.7.2 实测坑：落成
##   字符串 "(3, 17)" 不可还原，草案 §2.2）——落盘形状 = to_dict 内显式转 [x, y]
##   两元 int 数组（MapIO.to_jsonable 显式形状转换先例）；from_dict 由数组重建，
##   长度 ≠ 2 / 非整数 / 负分量 → null（无隐式兜底）；
## - classify_edge 保持几何派生现算**不入表**（草案 §4 禁止项维持）；高差分档阈值
##   属构建参数/几何 profile（LandformProfile），不进 MapData 也不进本表；
## - 主键自包含：link_id / reach_id / water_body_id 即主键；集合唯一性/规范序
##   （link_id、reach_id、water_body_id 升序；member_cells 行主序）由校验器查；
## - 河段四条校验（WATER-01 ②）：无环（**角点级**——边不复用 ≠ 无环，两条不同边可
##   经同一角点成环/自交，修订记录三之 4：稳定角点 ID + 已访问集合）、有终点（终点
##   边 ∈ 声明水体 inlet_links，NO_RIVER_OUTLET）、water_levels 沿边序列单调不升
##   （Catlike 禁上坡的数据化；水位口径 = **逐段 profile** 而非全河单 scalar，§2.2）、
##   bed_level < 逐段 water_level；
## - 水体校验（WATER-03）：同湖水位一致（body 单 water_level 字段结构性成立）+
##   河口对账（reach 终点边水位 == 水体 water_level，接缝几何逐位一致的水面口径）+
##   湖出口不高于溢流口（自本湖源出的 reach 首段水位 ≤ 本体 water_level）+
##   terminal 语义（海恒 true；海 outlet 恒空——不适用出水口；过路湖 false 必须
##   有 outlet）+ 河口边 = 岸边
##   （恰一端为成员格——水面接缝的机器前提）；成员格 terrain 对账按调用方传入的
##   water_terrain_id 显式启用（-1 = 跳过——水体地形 id 属内容层约定，核心数据层
##   不硬编码，草案 §6「校验不是回写」）；
## - **湖/河双口径（有意设计，§2.2 禁令行）**：湖/海 = 格语义水体（占格、terrain/
##   passable 结算面在格上，本表只加 water_level/inlet/outlet 标高与拓扑）；河 = 边
##   语义水体（水在边上、两侧格保持陆地地形与 passable——reach 永不回写 MapData）；
## - **道路合同（ROAD-01，草案 §7 转正）**：RoadData.cells 有序格序列（相邻两格
##   互为界内邻居 = 一条 link；单路内格不重复 → link 不复用）；路口 = 多路共享格
##   （重数合法，共享 **格** 而非 link——link.road_id 单值，两路跨接同一条 link 由
##   对账拒绝）；road_class 值域单点恒 0（能力关闭的显式表达，≠0 → from_dict 与
##   validate 双拒绝）；connects_pois T5 前恒空（POI 实体未解锁，非空即拒）；
##   link.road_id 与 roads.cells 相邻对**双向对账**（§4：本 link 两端恰为序列相邻
##   两格——与 river_reach_id 对账同构）；**Δ≥n 修路拒绝的阈值来自生成配置不进
##   数据**（validate 只在 max_road_delta ≥ 0 时校验——「有配置才拒」；被 crossing
##   认领的河 link 跳过：桥面高差由桥址校验管辖，ROAD-02 ③）；
## - **桥合同（ROAD-02，§2.3 格边重写表 + §2.4 连带对账）**：crossing = {有河
##   link，河在下、路在上} 的**认领关系**——格边口径下桥不占额外 link，跨接即该
##   link 本身（~~bridge_cell/traversable_edges 两条 link~~ 穿格版作废）；river_edge
##   = 被跨的有河 link（初版单边）、bank_a/bank_b == 该 link 两端格（两岸格，规范
##   序 bank_a=river_edge.x/bank_b=river_edge.y——字段保留为草案形状、校验钉死与
##   link 端点一致）；Kind.BRIDGE 唯一合法值（Kind.FERRY 枚举预留**不开**——
##   from_dict/validate 双拒绝，枚举存在 ≠ 能力开放）；一 link 至多一 crossing
##   （格边版桥锚定单 link——穿格版「方向所有权去重」结构性退化自动满足）；
##   **横切机器定义（§2.3 重写版）**：道路相邻对构成的有河 link 被 crossing 认领 =
##   合法横切 / 未认领的有河 link 出现在任何道路序列 = RIVER_FORD_FORBIDDEN 禁渡
##   拒绝（与 BRIDGE_ENDPOINT_INVALID 分开报）；桥无路跨接（两岸都有路的机器表达）
##   = CROSSING_NO_ROAD 拒绝；桥址合法性首版 = 桥头（bank Δ ≤ max_bridge_bank_delta，
##   生成配置口径同道路）+ 净空（max(bank 高程) ≥ 河水位——桥面中段 y = max+lift
##   恒于水面之上的数据面前提），违例 = BRIDGE_ENDPOINT_INVALID（草案 §11 错误码）；
## - **POI 合同（草案 §9 转正，WORLD-03）**：kind 三值（SETTLEMENT/SPAWN_ZONE/
##   RESOURCE）；footprint 行主序规范序、含锚定格、不重复；**形状随 kind 钉死**——
##   SPAWN_ZONE = 中心 + 六邻恰 7 格（拍板⑩ 主城七格落兵区；界内可通行是
##   WORLD-04 校验面 NO_VALID_SPAWN，数据层只钉形状与界内），聚落/资源 = [锚定格]
##   单格（多格聚落后续开）；role = String 占位载体（数据层不解释不定值域，仅要求
##   非空——无 role 的 POI 无意义）；资源经济数值字段一概不存在（M2 门）；阵营
##   归属/俘虏/占领语义不进（scenario 层——§9 禁止项对规则语义维持）；
## - **势力归属合同（拍板⑧ + §6 WORLD-03）**：StateData（state_id 主键、
##   capital_poi_id → SETTLEMENT 对账、expansionism 扩张参数档）+ **格级 owner 表**
##   cell_owners（落卡载体选定：格级 owner 集合 + StateData 主城清单；国界 = 跳变边
##   由 border_links_of 派生**不落盘**——§6 ③）；值域 = {-1 中立/水} ∪ state_id
##   ——水格恒 -1（§7「水格传播成本不归属」），陆格可显式中立（值域事实——
##   无主中立带的**有无未拍板**（§6 WORLD-03 卡内拍板项），中立带配置参数
##   未实现：生成器默认全覆盖，唯不可达陆格落显式中立）；states 空 ⇒
##   cell_owners 须空或全 -1
##   （POI/归属空集合合法 = 归属层关的回退态，§6 风险与回退行）；
## - WorldData 零回写 MapData（含 mods——草案 §11 全局项；测试锚定 summary 不变）；
## - 纯数据类：RefCounted、零场景节点、不 preload 任何场景（ADR-2；删 scripts/ui/**
##   后 tests 全绿）。锚点绝对坐标不落盘（§2.3）：边锚 = 两格心连线与共享边交点，
##   由 HexMath 全局参数唯一路径现算。
class_name WorldData
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")

## 数据结构版本（WorldData 独立伴生文件自计数——MapData.SCHEMA_VERSION 不动，§2.2）
const SCHEMA_VERSION := 1

## 一切 id 引用哨兵（负值——TERRAIN_NONE/-1 先例；cell_id 恒非负故不混淆）
const ID_NONE := -1

## link 哨兵（x=min(cell_id)、y=max(cell_id)；负分量 = 哨兵——合法 link 恒 0≤x<y）
const NO_LINK := Vector2i(-1, -1)

## 邻接边对象（草案 §4 + 执行方案 §2.4 重议后口径）：邻接边的**索引面**——回答
## 「这条边上有什么」。link 表只存 road_id / river_reach_id 引用（§2.4：初版不存
## 任何流向字段，与 reach.edges 序零冗余——终态流向事实 = 序本身即上游→下游）；
## 不承载地形/高差/连接类型（禁止项）。
class NeighborLinkData:
	extends RefCounted

	## 主键：x = min(两端 cell_id)、y = max(两端 cell_id)，恒 0 ≤ x < y；
	## 两端格须互为界内邻居（WorldData.validate 查——不存在邻格不产生连接）
	var link_id := NO_LINK

	## 本边被哪条道路占用（无向）；ID_NONE = 无路。T4 起与 roads.cells 相邻对双向
	## 对账（§4：本 link 两端恰为该道路格序列中的相邻两格；单值字段 = 一 link 至多
	## 一路，两路跨接同一条 link 由对账拒绝）
	var road_id: int = ID_NONE

	## 本边有河水时所属河段（RiverReachData 主键引用）；ID_NONE = 无河。
	## 与 reach.edges 双向对账（§4：本 link 两端恰为该河段边序列中的边）
	var river_reach_id: int = ID_NONE


## 河段（草案 §5 格边重写表全量，执行方案 §2.2；ADR-14）：河 = 六边形**共享边的
## 有序序列**（edges[0] = 源边、edges[last] = 终点边/河口），两端格互为河岸且
## **保持陆地地形**（河的通行影响走规则层 M3，渲染只下切连接带中段）。
## 『1入1出』的等价表达 = 边图上每条内部边恰有一前驱与一后继（链结构，拍板⑨：
## 数据层零冗余，入/出边概念只存在于生成期）；汇流（多前驱）初版校验器拒绝、
## 结构留口子第二版开。
class RiverReachData:
	extends RefCounted

	## 主键（河段表 reach_id 升序为规范序）
	var reach_id: int = ID_NONE

	## 有序边序列：每项 = link_id=(min,max)（沿 M1a-T4 归属先例）；相邻边须共角点
	## （序列连续）；全序列角点不复用（无环 = 角点级判定，修订记录三之 4）
	var edges: Array[Vector2i] = []

	## 流量等级（int ≥1）；等级→河宽/流速映射属表现参数不进数据（§2.2：
	## 首版固定等级或不依赖汇流的分档，Strahler 随汇流第二版）
	var flow_level: int = 1

	## 逐段水面标高 profile（与 edges 逐项对齐；沿序列**单调不升**——Catlike 禁上坡
	## 的数据化；§2.2：勿退化成单 scalar——逐段可变是本字段的验收口径）
	var water_levels: Array[int] = []

	## 河床离散标高（恒 < 逐段 water_level——河床容纳校验下界）；同纲 int 分层
	var bed_level: int = 0

	## 终点段汇入的水体（WaterBodyData 主键引用）：终点边 ∈ 该水体 inlet_links、
	## 终点边水位 == 该水体 water_level（河口对账）；不可解析/非 terminal → 非法
	var water_body_id: int = ID_NONE


## 水体（草案 §6 转正，WATER-03）：湖/海 = **格语义**水体（成员格 terrain=水、
## passable=false 结算面在 MapData 上，本实体只加水面标高/出入水口/终点声明）。
## 岸线 = 水格与陆格共享边集合（member 与非 member 之间的 link——校验器同口径判定，
## 渲染/国界两处复用）。
class WaterBodyData:
	extends RefCounted

	## 水体类型（枚举值大写先例；序列化按 int 落盘）
	enum Kind { SEA, LAKE }

	## 主键（水体表 water_body_id 升序为规范序）
	var water_body_id: int = ID_NONE

	## Kind.SEA / Kind.LAKE（初版两值）
	var kind: int = Kind.LAKE

	## 水面离散标高；**同一水体成员水位恒一致**（单字段结构性成立）；与汇入 reach
	## 的终点边水位对账（河口水面 y 逐位相等的数据面前提）
	var water_level: int = 0

	## 成员格 cell_id 列表，行主序规范序（= 升序，摘要可比较）；全图不重复、
	## 不同水体不共享格
	var member_cells: Array[int] = []

	## 入水口（河水汇入本水体的边，边口径——§2.4 改写）：与全部河段终点对账
	## （某 reach 终点 = 本体 ⇔ 其 water_body_id = 本 id）；每项须为本水体**岸边**
	## （恰一端为成员格——河口接缝的几何前提）
	var inlet_links: Array[Vector2i] = []

	## 出水口（湖溢流口；海不适用恒空）：须为岸边；自本湖源出的河段首段水位
	## 不得高于本水体 water_level（「湖出口不高于溢流口」）
	var outlet_links: Array[Vector2i] = []

	## 合法终点声明：河流是否允许以本水体为终点（海恒 true；湖 true = 终点湖、
	## false = 过路湖必须有 outlet——校验器查）
	var terminal := true


## 道路（草案 §7 转正，ROAD-01）：格中心网络的有序格序列——道路是**格与格之间**
## 的连接（拍板⑤语义正典），与沿边的河只会在共享 link 上交叉（交叉即桥，
## CrossingData 认领）。路口 = 多路共享 cell（共享格合法、共享 link 非法）。
class RoadData:
	extends RefCounted

	## 主键（道路表 road_id 升序为规范序）
	var road_id: int = ID_NONE

	## 有序格序列（cell_id，行主序稳定 ID）：相邻两格须互为界内邻居（构成 link）；
	## 单路内格不重复（重复格 = link 复用，拒绝）；is_loop 时首尾格另须相邻（环
	## 闭合边同样进对账/Δ/禁渡检查）
	var cells: Array[int] = []

	## 环路标记（可选回路的形状面，草案 §7 字段；闭合边 = cells[last]→cells[0]）
	var is_loop := false

	## 道路等级：**值域单点恒 0**（能力关闭的显式表达——分级路网属后续版本；
	## ≠0 由 from_dict 与 validate 双拒绝，序列化锚定）
	var road_class := 0

	## 连接的 POI 主键列表（草案 §7 字段）；POI 实体属 T5，本版恒空（非空即拒——
	## 「没有能力就没有数据」）
	var connects_pois: Array[int] = []


## 桥/渡口（草案 §8 格边重写表全量，ROAD-02；ADR-14 + 拍板⑤认领语义反转）：
## crossing = 「有河 link 上、河在下路在上」的认领关系——格边口径下桥不占额外
## link，跨接即该 link 本身；跨河可达的唯一查询入口 = CrossingData 认领表
## （crossing_index，ROAD-02 验收原文；生成期连通查询 map_generation_connectivity.gd
## 消费）。~~bridge_cell / river_cells / traversable_edges~~ 穿格版字段全部作废。
class CrossingData:
	extends RefCounted

	## 跨河结构类型：BRIDGE 唯一合法值；FERRY 预留**不开**（枚举存在 ≠ 能力开放
	## ——from_dict/validate 双拒绝，草案 §8 禁止项原文）
	enum Kind { BRIDGE, FERRY }

	## 主键（桥表 crossing_id 升序为规范序）
	var crossing_id: int = ID_NONE

	## Kind.BRIDGE（初版单值）
	var kind: int = Kind.BRIDGE

	## 被跨的有河 link（初版单边；宽河多边列表第二版）——须 ∈ 某河段 edges
	## （有河才有桥，CROSSING_NO_RIVER 拒绝无河边）
	var river_edge: Vector2i = NO_LINK

	## 两岸格 = river_edge 两端格（规范序 bank_a = river_edge.x、bank_b = river_edge.y
	## ——字段为草案形状保留，校验钉死与 link 端点一致，天然互异且均陆地地形）
	var bank_a: int = ID_NONE
	var bank_b: int = ID_NONE


## POI（草案 §9 转正，WORLD-03）：聚落 / 出生候选区 / 资源点的占位实体——
## 资源经济数值由 M2 决定（字段不存在），role 是模板与场景层引用的占位标签
## （数据层不解释）。出生区 footprint = 中心 + 六邻（半径 1 的七格落兵区，
## 拍板⑩「主城七格落兵区=中心+六邻」——POIData SPAWN_ZONE footprint 原文形态）。
class POIData:
	extends RefCounted

	## POI 类型（三值；序列化按 int 落盘）
	enum Kind { SETTLEMENT, SPAWN_ZONE, RESOURCE }

	## 主键（POI 表 poi_id 升序为规范序）
	var poi_id: int = ID_NONE

	## Kind.SETTLEMENT / Kind.SPAWN_ZONE / Kind.RESOURCE
	var kind: int = Kind.SETTLEMENT

	## 锚定格（界内；SPAWN_ZONE 锚 = 出生中心、SETTLEMENT 锚 = 主城格）
	var cell_id: int = ID_NONE

	## 占位 footprint（行主序规范序、含锚定格、不重复）：SPAWN_ZONE = 中心+六邻
	## 恰 7 格；聚落/资源 = [cell_id] 单格（§9 初版值域）
	var footprint_cells: Array[int] = []

	## 目标角色标签（如 player_capital / ai_capital / core_resource）——占位载体，
	## 语义由世界模板与场景层引用，数据层不解释（仅要求非空）
	var role := ""


## 势力（§6 WORLD-03 + §7 states 改造案，拍板⑧进数据）：生成产物侧的最小实体——
## 主城引用 + 扩张参数档；「怎么玩」（跨河防守 buff/征服/经济）不进（§9 禁止项）。
class StateData:
	extends RefCounted

	## 主键（states 表 state_id 升序为规范序；生成器 0 起 = 玩家 0 + AI 1..，拍板⑪）
	var state_id: int = ID_NONE

	## 主城 POI 引用（对账：可解析且 kind == SETTLEMENT；不同 state 不共享主城）
	var capital_poi_id: int = ID_NONE

	## 扩张参数档（Azgaar expansionism 的地形版保留位——「山地势力不下平原」类
	## 个性 = 扩张参数差异，§7 文化层裁剪行；进入成本 = cellCost/expansionism）
	var expansionism := 1


## 邻接边表（link_id 升序为规范序——摘要可比较的前提，草案 §2.1）
var links: Array[NeighborLinkData] = []

## 河段表（T3 WATER-01 解锁；reach_id 升序规范序）
var rivers: Array[RiverReachData] = []

## 水体表（T3 WATER-03 解锁；water_body_id 升序规范序）
var water_bodies: Array[WaterBodyData] = []

## 道路表（T4 ROAD-01 解锁；road_id 升序规范序）
var roads: Array[RoadData] = []

## 桥表（T4 ROAD-02 解锁；crossing_id 升序规范序）
var crossings: Array[CrossingData] = []

## POI 表（T5 WORLD-03 解锁；poi_id 升序规范序）
var pois: Array[POIData] = []

## 势力表（T5 WORLD-03 拍板⑧解锁；state_id 升序规范序）
var states: Array[StateData] = []

## 格级 owner 表（与格子表同长、行主序对齐；-1 = 中立/水，否则 state_id）。
## 国界不落盘——border_links_of 由本表派生（跳变边集合，§6 ③）
var cell_owners: Array[int] = []

## WorldMeta（草案 §10 字段集的占位形状；attempt/repair/first_pass 落码进 WORLD-04）。
## 手工固定图默认口径：seed=0、generator_version=0、rules_version=0（视觉模式）、
## attempt_count=1、repair_count=0、first_pass_valid=true。
var meta: Dictionary = {
	"schema_version": SCHEMA_VERSION,
	"seed": 0,
	"generator_version": 0,
	"rules_version": 0,
	"engine_version": "",
	"config_digest": "",
	"world_digest": "",
	"attempt_count": 1,
	"repair_count": 0,
	"first_pass_valid": true,
}

## 旧图口径：全空集合 + 默认 meta——「缺 .world.json = 无河无路无 POI」的合法态。
static func empty() -> WorldData:
	return new()

## link 规范化：a/b 两端 cell_id → (min, max)；同格 / 任一负值 → NO_LINK（哨兵）。
static func link_id_of(a: int, b: int) -> Vector2i:
	if a == b or a < 0 or b < 0:
		return NO_LINK
	return Vector2i(mini(a, b), maxi(a, b))

# ---------------- 主键查询（渲染/测试只读面）----------------

## reach_id → 河段（不存在 → null；线性查——T3 规模下单表 ≤ 数十条，不做索引）。
func river_reach_by_id(reach_id: int) -> RiverReachData:
	for r in rivers:
		if r.reach_id == reach_id:
			return r
	return null


## water_body_id → 水体（不存在 → null）。
func water_body_by_id(body_id: int) -> WaterBodyData:
	for b in water_bodies:
		if b.water_body_id == body_id:
			return b
	return null


## road_id → 道路（不存在 → null；线性查——T4 手工路网规模下不做索引）。
func road_by_id(road_id: int) -> RoadData:
	for r in roads:
		if r.road_id == road_id:
			return r
	return null


## crossing_id → 桥（不存在 → null）。
func crossing_by_id(crossing_id: int) -> CrossingData:
	for c in crossings:
		if c.crossing_id == crossing_id:
			return c
	return null


## 桥认领表（link_id → CrossingData，ROAD-02「跨河可达的唯一查询入口」）：
## 生成期连通查询（map_generation_connectivity.gd）与 T5 WORLD-05 桥址搜索共用。
## 一 link 至多一 crossing 由 validate 保证（构造期无冲突）。
func crossing_index() -> Dictionary:
	var out := {}
	for c in crossings:
		out[c.river_edge] = c
	return out


## 急弯判据（ROAD-02 ②，拍板⑩走向几何版——无转弯语义）：河段边序列第 k 步处
## 急弯 ⇔ edge[k] 与 edge[k+2] **不平行**（平行 = 平缓走廊、不平行 = 急弯）；
## **首尾索引边界**：k < 0 或 k+2 ≥ edges.size() 即非急弯（序列首尾勿漏——单边/
## 两边序列无从判定走向）。桥址候选（生成侧 WORLD-05）据此排除急弯边；判据与
## 河段端点边排除（源/终点不设桥）同属候选偏好、非桥址合法性硬约束（ROAD-02 ③）。
## 平行判定 = 两条边切向的单位点积绝对值 ≥ 1−PARALLEL_EPS（切向取自任一端格的
## dir_between——两端格推导差一个符号，取绝对值即无向平行）。
const PARALLEL_EPS := 1e-6

static func river_bend_is_sharp(map: MapDataClass, reach: RiverReachData, k: int) -> bool:
	if k < 0 or k + 2 >= reach.edges.size():
		return false  # 首尾索引边界：越界即非急弯
	var t1: Variant = _edge_tangent_of(map, reach.edges[k])
	var t2: Variant = _edge_tangent_of(map, reach.edges[k + 2])
	if not (t1 is Vector3) or not (t2 is Vector3):
		return false  # 非法边（越界/非邻居）——形状由 validate 拒，此处保守非急弯
	var v1: Vector3 = t1
	var v2: Vector3 = t2
	return absf(v1.dot(v2)) < 1.0 - PARALLEL_EPS


## link 两端格 → 该共享边的切向单位向量（HexMath.edge_tangent_world，世界 XZ 平面；
## 两端格不互为邻居 → null）。
static func _edge_tangent_of(map: MapDataClass, link: Vector2i) -> Variant:
	var a := _cell_of_id(map, link.x)
	var b := _cell_of_id(map, link.y)
	var d := Hex.dir_between(a, b)
	if d < 0:
		return null
	return Hex.edge_tangent_world(d)


## 有河边索引（link_id → {"reach": int, "water": int, "bed": int}）：地形河床下切与
## 水面条带共用的唯一查询面（WaterGeometryBuilder / HexTerrainBuilder / 测试）。
## 同一 link 双 reach 归属由 validate 拒绝（构造期无冲突）。
func river_edge_index() -> Dictionary:
	var out := {}
	for r in rivers:
		for k in r.edges.size():
			out[r.edges[k]] = {"reach": r.reach_id,
				"water": r.water_levels[k], "bed": r.bed_level}
	return out


## 水体成员索引（cell_id → WaterBodyData；不同水体共享格由 validate 拒绝）。
func water_membership() -> Dictionary:
	var out := {}
	for b in water_bodies:
		for cid in b.member_cells:
			out[cid] = b
	return out


## 岸线（WATER-03 ②）：水体与陆地的共享边集合——成员格每个界内非成员邻居各出
## 一条 link，升序规范序。岸线渲染（裙边）/校验器岸边口径/边界画法（§7 同构）
## 三处复用同一几何事实；独立于 MapData.terrain（对账用 terrain、岸线用成员集——
## 两个口径由 WATER_MEMBER_TERRAIN 校验绑定）。
static func shore_links_of(map: MapDataClass, b: WaterBodyData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cid in b.member_cells:
		var cell := _cell_of_id(map, cid)
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not map.has_cell(nb):
				continue
			var nb_id := map.index_of(nb)
			if b.member_cells.has(nb_id):
				continue
			var lk := link_id_of(cid, nb_id)
			if not out.has(lk):
				out.append(lk)
	out.sort()
	return out

# ---------------- 聚落/势力查询（WORLD-03 只读面）----------------

## poi_id → POI（不存在 → null；线性查——T5 规模 ≤ 数十）。
func poi_by_id(poi_id: int) -> POIData:
	for p in pois:
		if p.poi_id == poi_id:
			return p
	return null


## state_id → 势力（不存在 → null）。
func state_by_id(state_id: int) -> StateData:
	for s in states:
		if s.state_id == state_id:
			return s
	return null


## 指定 kind 的 POI 列表（poi_id 升序——表序即规范序）。
func pois_of_kind(kind: int) -> Array[POIData]:
	var out: Array[POIData] = []
	for p in pois:
		if p.kind == kind:
			out.append(p)
	return out


## 有河 link 两岸格集合（cell_id → true）：河岸锚点格——格边口径下「河床占格」的
## 格级代理（河床在连接带、不占格；出生/资源 footprint 冲突校验与 WORLD-05 桥址
## 候选两岸共用本口径，§6 WORLD-03 ⑤ footprint 冲突面）。
func river_flank_cells() -> Dictionary:
	var out := {}
	for r in rivers:
		for e in r.edges:
			out[e.x] = true
			out[e.y] = true
	return out


## 全部道路格集合（cell_id → true；多路共享格 = 路口合法，字典天然去重）。
func road_cells() -> Dictionary:
	var out := {}
	for r in roads:
		for cid in r.cells:
			out[cid] = true
	return out


## 国界 = owner 跳变边集合（§6 WORLD-03 ③ + §7 边界绘制行）：相邻两格 owner 均
## ≥0 且互异 → 共享格边即国界边，升序规范序。**派生不落盘**（生成产物进数据、
## 表现派生阶段按端点缝折线）；有河 link 两侧 owner 互异时天然入界 = 河界
## （§7「有河 link 天然河界」）。独立于 links 表（无河世界 links 可为空——全图
## 邻接遍历与满 link 表逐位一致）。
static func border_links_of(map: MapDataClass, world: WorldData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var owners := world.cell_owners
	if owners.is_empty():
		return out
	for cell in map.cells():
		var a := map.index_of(cell)
		var oa := owners[a]
		if oa < 0:
			continue
		for d in 6:
			var nb := Hex.neighbor(cell, d)
			if not map.has_cell(nb):
				continue
			var b := map.index_of(nb)
			# 只取 a<b 侧避免双向重复（link 规范序同式）
			if b < a:
				continue
			var ob := owners[b]
			if ob >= 0 and ob != oa:
				out.append(link_id_of(a, b))
	out.sort()
	return out

# ---------------- 世界事实摘要（T5 WORLD-01 同 seed 复现验收的载体）----------------

## 世界事实摘要 = SHA-256 hex：覆盖 MapData 格子表 + 本表全部事实集合（links/
## rivers/water_bodies/roads/crossings/pois），**刻意不含 meta**——meta 落本摘要
## （自引无意义），也刻意不含生成耗时类诊断（草案 §10 禁止项：摘要只锚世界事实）。
## 确定性前提：to_dict 固定键序 + MapData.summary 固定遍历序 → 同世界（不论写入
## 顺序）逐字节一致、任一事实变更即变（与 MapData.digest 同纪律，T5 WORLD-01
## 测试锚「同 seed 同模板跑 3 次 world_digest 一致」的落点）。
func world_digest(map: MapDataClass) -> String:
	var facts := to_dict()
	facts.erase("meta")
	var payload := "world|v%d|%s|%s" % [SCHEMA_VERSION, map.summary(), JSON.stringify(facts)]
	return payload.sha256_text()

# ---------------- 校验器（草案 §11：T3 面 = link 表 + 河段四条 + 水体 + 双向对账）----------------

## 校验入口：""=合法；原因串指向具体 link/reach/body/road/crossing/约束（最小诊断
## 输出）。water_terrain_id ≥ 0 时启用成员格 terrain 对账（草案 §6「成员应
## TERRAIN_WATER」——校验不是回写；水体地形 id 属内容层约定 3 号槽，核心层不
## 硬编码，-1 = 跳过）。**max_road_delta / max_bridge_bank_delta = 生成配置口径的
## 高差阈值（Δ>max 拒绝），-1 = 无配置不查**（§7 禁止项「阈值在生成配置不进
## 数据」——数据层只校验「有配置才拒」，ROAD-01 ③/ROAD-02 ③）。
## 零回写 MapData：本函数只读（结构性保证，测试锚定 summary 不变）。
func validate(map: MapDataClass, water_terrain_id := -1,
		max_road_delta := -1, max_bridge_bank_delta := -1) -> String:
	var river_claim := {}  # link 表声明：link_id → river_reach_id
	var prev := NO_LINK
	for i in links.size():
		var lk := links[i]
		var lid := lk.link_id
		if lid.x < 0 or lid.x >= lid.y:
			return "links[%d] link_id 非规范（须 0≤x<y，got %s）" % [i, str(lid)]
		# 严格升序同时覆盖「重复主键」（相等即不升序——错误串两者兼顾）
		if prev != NO_LINK and not _link_less(prev, lid):
			return "links[%d] 破坏规范序（须按 link_id 严格升序——含主键重复；got %s after %s）" \
				% [i, str(lid), str(prev)]
		prev = lid
		if lid.y >= map.cell_count():
			return "links[%d] link_id 指向界外格（%s，图共 %d 格）" % [i, str(lid), map.cell_count()]
		var ca := _cell_of_id(map, lid.x)
		var cb := _cell_of_id(map, lid.y)
		if not map.has_cell(ca) or not map.has_cell(cb) or Hex.dir_between(ca, cb) < 0:
			return "links[%d] 两端格不互为界内邻居（%s：%s / %s）" % [i, str(lid), str(ca), str(cb)]
		if lk.road_id != ID_NONE and lk.road_id < 0:
			return "links[%d] road_id=%d 非法（负值）" % [i, lk.road_id]
		if lk.river_reach_id != ID_NONE:
			if lk.river_reach_id < 0:
				return "links[%d] river_reach_id=%d 非法（负值）" % [i, lk.river_reach_id]
			river_claim[lid] = lk.river_reach_id
	var river_err := _validate_rivers(map)
	if river_err != "":
		return river_err
	var body_err := _validate_water_bodies(map, water_terrain_id)
	if body_err != "":
		return body_err
	var crossing_err := _validate_crossings(map, max_bridge_bank_delta)
	if crossing_err != "":
		return crossing_err
	var road_err := _validate_roads(map, max_road_delta)
	if road_err != "":
		return road_err
	var recon_err := _validate_reconciliation(map, river_claim)
	if recon_err != "":
		return recon_err
	return _validate_settlement(map)


## 河段四条 + 结构完整性（WATER-01 ②；角点级无环 = 修订记录三之 4）。
## 返回 river_edge_owner（link_id → reach_id）供对账段复用（null = 已出错）。
func _validate_rivers(map: MapDataClass) -> String:
	var prev_id := ID_NONE
	for ri in rivers.size():
		var r := rivers[ri]
		if r.reach_id < 0:
			return "rivers[%d] reach_id=%d 非法（负主键）" % [ri, r.reach_id]
		if prev_id != ID_NONE and r.reach_id <= prev_id:
			return "rivers[%d] 破坏规范序（须按 reach_id 严格升序——含主键重复；got %d after %d）" \
				% [ri, r.reach_id, prev_id]
		prev_id = r.reach_id
		if r.edges.is_empty():
			return "rivers[%d]（reach %d）边序列为空（河段至少一条边）" % [ri, r.reach_id]
		if r.water_levels.size() != r.edges.size():
			return "rivers[%d]（reach %d）water_levels 长度 %d ≠ edges 长度 %d（逐段 profile 逐项对齐）" \
				% [ri, r.reach_id, r.water_levels.size(), r.edges.size()]
		if r.flow_level < 1:
			return "rivers[%d]（reach %d）flow_level=%d 非法（≥1，§2.2）" % [ri, r.reach_id, r.flow_level]
		# 边序列结构 + 角点级无环：物理角点用稳定 ID（三格表示取最小 index_of·6+顶点），
		# 与生成路径无关——「边不复用 ≠ 无环」的补口（两条不同边可经同一角点绕回成环）。
		# 链行走 = 双端延伸：边序列是**无向路径**，下一条边可接在链的任一端
		#（贪心走/手写序列都不保证方向），两端各自生长；闭合成环或触访已用角点
		# 即 RIVER_CYCLE，接不上两端即序列不连续。
		var visited_corners := {}
		var head_corner := -1
		var tail_corner := -1
		for k in r.edges.size():
			var e := r.edges[k]
			if e.x < 0 or e.x >= e.y:
				return "rivers[%d]（reach %d）edges[%d]=%s 非规范（须 0≤x<y 的 link_id）" \
					% [ri, r.reach_id, k, str(e)]
			if e.y >= map.cell_count():
				return "rivers[%d]（reach %d）edges[%d]=%s 指向界外格（图共 %d 格）" \
					% [ri, r.reach_id, k, str(e), map.cell_count()]
			var ca := _cell_of_id(map, e.x)
			var cb := _cell_of_id(map, e.y)
			var d := Hex.dir_between(ca, cb)
			if not map.has_cell(ca) or not map.has_cell(cb) or d < 0:
				return "rivers[%d]（reach %d）edges[%d]=%s 两端格不互为界内邻居（非法邻格）" \
					% [ri, r.reach_id, k, str(e)]
			var c1 := corner_id_of(map, ca, d)
			var c2 := corner_id_of(map, ca, d + 1)
			if head_corner < 0:
				head_corner = c1
				tail_corner = c2
				visited_corners[c1] = true
				visited_corners[c2] = true
				continue
			# 接尾端 / 接首端（无向路径两端生长）；接不上任一端 → 不连续
			var fresh := -1
			if c1 == tail_corner or c2 == tail_corner:
				fresh = c2 if c1 == tail_corner else c1
				tail_corner = fresh
			elif c1 == head_corner or c2 == head_corner:
				fresh = c2 if c1 == head_corner else c1
				head_corner = fresh
			else:
				# 触访非端点的已用角点 = 自交（成环的变体）；完全无接触 = 断链
				for c in [c1, c2]:
					if visited_corners.has(c):
						return "RIVER_CYCLE：rivers[%d]（reach %d）edges[%d] 触访链中角点 %d（角点级判定——边不复用 ≠ 无环）" \
							% [ri, r.reach_id, k, c]
				return "rivers[%d]（reach %d）edges[%d] 与既有链不共角点（序列不连续）" \
					% [ri, r.reach_id, k]
			if visited_corners.has(fresh):
				return "RIVER_CYCLE：rivers[%d]（reach %d）角点 %d 二次到访（角点级判定——边不复用 ≠ 无环）" \
					% [ri, r.reach_id, fresh]
			visited_corners[fresh] = true
		# 单调不升（逐段 profile）+ bed < water（逐段）
		for k in r.water_levels.size():
			if k > 0 and r.water_levels[k] > r.water_levels[k - 1]:
				return "RIVER_LEVEL_RISE：rivers[%d]（reach %d）edges[%d] 水位 %d > 前段 %d（沿边序列单调不升）" \
					% [ri, r.reach_id, k, r.water_levels[k], r.water_levels[k - 1]]
			if r.bed_level >= r.water_levels[k]:
				return "RIVER_BED：rivers[%d]（reach %d）bed_level=%d 须 < 逐段 water_level（edges[%d] 水位 %d）" \
					% [ri, r.reach_id, r.bed_level, k, r.water_levels[k]]
	return ""


## 水体面（WATER-03）：主键/规范序/kind/terminal/成员/岸线边形状。
func _validate_water_bodies(map: MapDataClass, water_terrain_id: int) -> String:
	var prev_id := ID_NONE
	var membership := {}
	for bi in water_bodies.size():
		var b := water_bodies[bi]
		if b.water_body_id < 0:
			return "water_bodies[%d] water_body_id=%d 非法（负主键）" % [bi, b.water_body_id]
		if prev_id != ID_NONE and b.water_body_id <= prev_id:
			return "water_bodies[%d] 破坏规范序（须按 water_body_id 严格升序——含主键重复）" % bi
		prev_id = b.water_body_id
		if b.kind != WaterBodyData.Kind.SEA and b.kind != WaterBodyData.Kind.LAKE:
			return "water_bodies[%d]（body %d）kind=%d 非法（Kind.SEA/LAKE 两值）" \
				% [bi, b.water_body_id, b.kind]
		if b.kind == WaterBodyData.Kind.SEA and not b.terminal:
			return "water_bodies[%d]（body %d）海 terminal 恒 true（草案 §6 原文）" % [bi, b.water_body_id]
		if b.kind == WaterBodyData.Kind.SEA and not b.outlet_links.is_empty():
			return "WATER_SEA_OUTLET：water_bodies[%d]（body %d）海 outlet_links 恒空（草案 §6 原文——海不适用出水口）" % [bi, b.water_body_id]
		if not b.terminal and b.outlet_links.is_empty():
			return "WATER_TERMINAL：water_bodies[%d]（body %d）过路湖（terminal=false）必须有 outlet" \
				% [bi, b.water_body_id]
		if b.member_cells.is_empty():
			return "water_bodies[%d]（body %d）member_cells 为空（水体至少一格）" % [bi, b.water_body_id]
		var prev_cell := ID_NONE
		for ci in b.member_cells.size():
			var cid := b.member_cells[ci]
			if cid < 0 or cid >= map.cell_count():
				return "water_bodies[%d]（body %d）member_cells[%d]=%d 指向界外格" \
					% [bi, b.water_body_id, ci, cid]
			if prev_cell != ID_NONE and cid <= prev_cell:
				return "water_bodies[%d]（body %d）member_cells 破坏行主序规范序（含重复格 %d）" \
					% [bi, b.water_body_id, cid]
			prev_cell = cid
			if membership.has(cid):
				return "water_bodies[%d]（body %d）成员格 %d 与水体 %d 共享（不同水体不共享格）" \
					% [bi, b.water_body_id, cid, (membership[cid] as WaterBodyData).water_body_id]
			membership[cid] = b
			if water_terrain_id >= 0 and map.terrain_at(_cell_of_id(map, cid)) != water_terrain_id:
				return "WATER_MEMBER_TERRAIN：water_bodies[%d]（body %d）成员格 %d terrain=%d ≠ 水地形 %d（对账不是回写）" \
					% [bi, b.water_body_id, cid, map.terrain_at(_cell_of_id(map, cid)), water_terrain_id]
		for group in [["inlet_links", b.inlet_links], ["outlet_links", b.outlet_links]]:
			var gname := String(group[0])
			var arr: Array[Vector2i] = group[1]
			var seen := {}
			for li in arr.size():
				var lk := arr[li]
				var shape_err := _shore_link_check(map, b, lk)
				if shape_err != "":
					return "water_bodies[%d]（body %d）%s[%d] %s" % [bi, b.water_body_id, gname, li, shape_err]
				if seen.has(lk):
					return "water_bodies[%d]（body %d）%s 重复边 %s" % [bi, b.water_body_id, gname, str(lk)]
				seen[lk] = true
	return ""


## 岸边（岸线）边形状检查：合法 link + 界内 + 邻居 + **恰一端为成员格**——
## 岸线 = 水陆共享边集合（WATER-03 ②）；入/出水口与河口边共用本口径
## （河口接缝几何：终点边一侧是水面边缘、一侧是陆地，两侧全水 = 内部边接不上缝）。
func _shore_link_check(map: MapDataClass, b: WaterBodyData, lk: Vector2i) -> String:
	if lk.x < 0 or lk.x >= lk.y:
		return "%s 非规范（须 0≤x<y）" % str(lk)
	if lk.y >= map.cell_count():
		return "%s 指向界外格" % str(lk)
	var ca := _cell_of_id(map, lk.x)
	var cb := _cell_of_id(map, lk.y)
	if Hex.dir_between(ca, cb) < 0:
		return "%s 两端格不互为界内邻居" % str(lk)
	var in_a := _body_has_member(b, lk.x)
	var in_b := _body_has_member(b, lk.y)
	if in_a == in_b:
		return "%s 须为岸边（恰一端为成员格；got 成员=%s/%s）" % [str(lk), str(in_a), str(in_b)]
	return ""


func _body_has_member(b: WaterBodyData, cell_id: int) -> bool:
	# member_cells 已验升序——二分不必要，线性足够（水体成员 ≤ 千级）
	return b.member_cells.has(cell_id)


## 桥面（ROAD-02 ②③）：主键/规范序/kind（FERRY 拒绝开启）/两岸格形状（==
## river_edge 两端格）/一 link 至多一 crossing/river_edge 有河/桥址合法性（桥头
## Δ 与净空——生成配置口径，-1 不查）。river_edge「有河」按河段表投影判定
## （river_edge_index）；link.river_reach_id ↔ reach.edges 的对账在
## _validate_reconciliation（与桥无关的河对账面，不在此重复）。
func _validate_crossings(map: MapDataClass, max_bridge_bank_delta: int) -> String:
	var river_idx := river_edge_index()
	var claimed := {}
	var prev_id := ID_NONE
	for ci in crossings.size():
		var c := crossings[ci]
		if c.crossing_id < 0:
			return "crossings[%d] crossing_id=%d 非法（负主键）" % [ci, c.crossing_id]
		if prev_id != ID_NONE and c.crossing_id <= prev_id:
			return "crossings[%d] 破坏规范序（须按 crossing_id 严格升序——含主键重复）" % ci
		prev_id = c.crossing_id
		if c.kind == CrossingData.Kind.FERRY:
			return "CROSSING_FERRY：crossings[%d]（id %d）Kind.FERRY 预留不开（草案 §8 禁止项——枚举存在 ≠ 能力开放）" \
				% [ci, c.crossing_id]
		if c.kind != CrossingData.Kind.BRIDGE:
			return "crossings[%d]（id %d）kind=%d 非法（Kind.BRIDGE 唯一合法值）" \
				% [ci, c.crossing_id, c.kind]
		var e := c.river_edge
		if e.x < 0 or e.x >= e.y or e.y >= map.cell_count():
			return "crossings[%d]（id %d）river_edge=%s 非规范（须 0≤x<y 的界内 link）" \
				% [ci, c.crossing_id, str(e)]
		var ca := _cell_of_id(map, e.x)
		var cb := _cell_of_id(map, e.y)
		if Hex.dir_between(ca, cb) < 0:
			return "crossings[%d]（id %d）river_edge=%s 两端格不互为界内邻居" \
				% [ci, c.crossing_id, str(e)]
		if c.bank_a != e.x or c.bank_b != e.y:
			return "BRIDGE_ENDPOINT_INVALID：crossings[%d]（id %d）两岸格 (%d,%d) ≠ river_edge 两端格 (%d,%d)" \
				% [ci, c.crossing_id, c.bank_a, c.bank_b, e.x, e.y]
		if not river_idx.has(e):
			return "CROSSING_NO_RIVER：crossings[%d]（id %d）river_edge=%s 不属于任何河段（有河才有桥）" \
				% [ci, c.crossing_id, str(e)]
		if claimed.has(e):
			return "CROSSING_DUP：边 %s 同时被 crossing %d 与 %d 认领（一 link 至多一 crossing）" \
				% [str(e), int(claimed[e]), c.crossing_id]
		claimed[e] = c.crossing_id
		# 桥址合法性首版 = 桥头/净空（ROAD-02 ③：净跨单边恒定、坡度由桥头 Δ 覆盖，
		# 「相隔两边平行」降为候选偏好非硬约束）——桥头 Δ 超配置 = 整桥抬高必留
		# 悬空桥头，拒绝该桥址（不接坡不留悬空；几何侧 3 段接坡见 RoadGeometryBuilder）
		var ea := map.elevation_at(ca)
		var eb := map.elevation_at(cb)
		if max_bridge_bank_delta >= 0 and absi(ea - eb) > max_bridge_bank_delta:
			return "BRIDGE_ENDPOINT_INVALID：crossing %d 两岸格 (%d,%d) 高差 |%d−%d|=%d > 配置 %d（接坡超限——拒绝该桥址，不留悬空桥头）" \
				% [c.crossing_id, c.bank_a, c.bank_b, ea, eb, absi(ea - eb), max_bridge_bank_delta]
		# 净空：桥面中段 y = max(两岸)×step + lift 须恒于水面 (level−0.5)×step 之上——
		# 离散纲下 max(两岸高程) ≥ 河水位是充分条件（逐位几何断言在桥几何测试锚）
		if maxi(ea, eb) < int(river_idx[e]["water"]):
			return "BRIDGE_ENDPOINT_INVALID：crossing %d 桥面净空不足（max 两岸高程 %d < 河水位 %d——桥面将不高于水面）" \
				% [c.crossing_id, maxi(ea, eb), int(river_idx[e]["water"])]
	return ""


## 道路面（ROAD-01 ①③ + ROAD-02 ②横切机器定义）：主键/规范序/值域（road_class
## 单点、connects_pois 恒空）/cells 结构（界内/相邻/不重复/is_loop 闭合）/Δ 生成
## 配置拒绝/禁渡（有河 link 未认领 = RIVER_FORD_FORBIDDEN，与 BRIDGE_ENDPOINT_
## INVALID 分开报）/桥服务对账（两岸都有路）/link↔road 双向对账（§4，与河对账
## 同构）。被 crossing 认领的 link 跳过 Δ 检查——桥面高差由桥址校验管辖。
func _validate_roads(map: MapDataClass, max_road_delta: int) -> String:
	var river_idx := river_edge_index()
	var claims := crossing_index()
	var road_links := {}  # 全部道路相邻对投影：link → road_id
	var served := {}     # 被道路实际跨接的认领边（两岸都有路的机器表达）
	var prev_id := ID_NONE
	for ri in roads.size():
		var r := roads[ri]
		if r.road_id < 0:
			return "roads[%d] road_id=%d 非法（负主键）" % [ri, r.road_id]
		if prev_id != ID_NONE and r.road_id <= prev_id:
			return "roads[%d] 破坏规范序（须按 road_id 严格升序——含主键重复）" % ri
		prev_id = r.road_id
		if r.road_class != 0:
			return "ROAD_CLASS：roads[%d]（road %d）road_class=%d ≠ 0（值域单点——能力关闭的显式表达）" \
				% [ri, r.road_id, r.road_class]
		if not r.connects_pois.is_empty():
			return "ROAD_POI：roads[%d]（road %d）connects_pois 非空（POI 实体属 T5——没有能力就没有数据）" \
				% [ri, r.road_id]
		var min_cells := 3 if r.is_loop else 2
		if r.cells.size() < min_cells:
			return "roads[%d]（road %d）cells 至少 %d 格（%s）" % [ri, r.road_id, min_cells,
				"环路 ≥3（2 格环 = 同一 link 往返复用）" if r.is_loop else "非环 ≥2（端点路也有首尾两格）"]
		var seen := {}
		for k in r.cells.size():
			var cid := r.cells[k]
			if cid < 0 or cid >= map.cell_count():
				return "roads[%d]（road %d）cells[%d]=%d 指向界外格（图共 %d 格）" \
					% [ri, r.road_id, k, cid, map.cell_count()]
			if seen.has(cid):
				return "roads[%d]（road %d）cells 重复格 %d（单路内格不重复——link 不复用）" \
					% [ri, r.road_id, cid]
			seen[cid] = true
		# 相邻对枚举：非环 k = 0..size−2；环路含闭合对 cells[last]→cells[0]
		#（闭合边同样进 Δ/禁渡/对账检查）
		var pair_last := r.cells.size() - 1 if r.is_loop else r.cells.size() - 2
		for k in pair_last + 1:
			var a := r.cells[k]
			var b := r.cells[0] if k == r.cells.size() - 1 else r.cells[k + 1]
			var cell_a := _cell_of_id(map, a)
			var cell_b := _cell_of_id(map, b)
			if Hex.dir_between(cell_a, cell_b) < 0:
				return "roads[%d]（road %d）cells[%d]→cells[%d]（%s→%s）不互为界内邻居（道路相邻格）" \
					% [ri, r.road_id, k, (k + 1) % r.cells.size(), str(cell_a), str(cell_b)]
			var link := link_id_of(a, b)
			if road_links.has(link):
				return "ROAD_LINK_REUSE：边 %s 同时属于 road %d 与 %d（一 link 至多一路——共享格成路口、共享 link 非法）" \
					% [str(link), int(road_links[link]), r.road_id]
			road_links[link] = r.road_id
			if claims.has(link):
				served[link] = true
				continue  # 桥面：Δ 由桥址校验管辖（ROAD-02 ③），禁渡不适用（已认领）
			if max_road_delta >= 0:
				var delta := absi(map.elevation_at(cell_a) - map.elevation_at(cell_b))
				if delta > max_road_delta:
					return "ROAD_DELTA：roads[%d]（road %d）cells[%d]→cells[%d] 高差 %d > 配置 %d（Δ 超限修路按生成配置拒绝）" \
						% [ri, r.road_id, k, (k + 1) % r.cells.size(), delta, max_road_delta]
			if river_idx.has(link):
				return "RIVER_FORD_FORBIDDEN：roads[%d]（road %d）cells[%d]→cells[%d] 跨有河边 %s（reach %d）未被 crossing 认领——禁渡拒绝（横切机器定义 §2.3；禁渡与桥端无效是两类错误，分开报）" \
					% [ri, r.road_id, k, (k + 1) % r.cells.size(), str(link),
						int(river_idx[link]["reach"])]
	# 桥服务对账：每座桥的认领边必被某条道路实际跨接（两岸都有路——Catlike 放置
	# 规则①的格边转译，横切定义自动含）
	for c in crossings:
		if not served.has(c.river_edge):
			return "CROSSING_NO_ROAD：crossing %d 认领边 %s 无任何道路相邻对跨接（两岸都有路才设桥）" \
				% [c.crossing_id, str(c.river_edge)]
	# link ↔ road 双向对账（草案 §4：link 表 road_id 与 roads 相邻对零冗余互证）
	var road_claim := {}
	for lk in links:
		if lk.road_id != ID_NONE:
			road_claim[lk.link_id] = lk.road_id
	for e in road_links:
		var claimed: Variant = road_claim.get(e, ID_NONE)
		if int(claimed) != int(road_links[e]):
			return "LINK_ROAD_MISMATCH：road %d 的相邻对 %s 在 link 表缺失或 road_id≠%d（got %s）——双向对账" \
				% [int(road_links[e]), str(e), int(road_links[e]), str(claimed)]
	for e in road_claim:
		if not road_links.has(e):
			return "LINK_ROAD_MISMATCH：link %s 声明有路（road %d）但无任何道路相邻对含此边" \
				% [str(e), int(road_claim[e])]
	return ""


## 对账段：河段↔水体（终点/水位/河口边）、水体↔河段（inlet 镜像）、湖出口水位、
## link↔reach 双向。
func _validate_reconciliation(map: MapDataClass, river_claim: Dictionary) -> String:
	# ① 河段 → 水体（终点对账 + 河口水位/岸边口径）
	var river_edge_owner := {}
	for ri in rivers.size():
		var r := rivers[ri]
		for e in r.edges:
			if river_edge_owner.has(e):
				return "RIVER_EDGE_REUSE：边 %s 同时属于 reach %d 与 %d（每有河 link 恰一归属）" \
					% [str(e), (river_edge_owner[e] as int), r.reach_id]
			river_edge_owner[e] = r.reach_id
		var b := water_body_by_id(r.water_body_id)
		if b == null:
			return "NO_RIVER_OUTLET：rivers[%d]（reach %d）water_body_id=%d 引用不可解析（v1 每河必汇入声明水体）" \
				% [ri, r.reach_id, r.water_body_id]
		if not b.terminal:
			return "NO_RIVER_OUTLET：rivers[%d]（reach %d）终点水体 %d 非 terminal" % [ri, r.reach_id, b.water_body_id]
		var term := r.edges[r.edges.size() - 1]
		if not b.inlet_links.has(term):
			return "NO_RIVER_OUTLET：rivers[%d]（reach %d）终点边 %s ∉ 水体 %d 的 inlet_links（双向对账）" \
				% [ri, r.reach_id, str(term), b.water_body_id]
		var term_level := r.water_levels[r.water_levels.size() - 1]
		if term_level != b.water_level:
			return "WATER_MOUTH_LEVEL：rivers[%d]（reach %d）终点边水位 %d ≠ 水体 %d 水面 %d（河口对账——接缝 y 逐位一致的数据面）" \
				% [ri, r.reach_id, term_level, b.water_body_id, b.water_level]
		var shore_err := _shore_link_check(map, b, term)
		if shore_err != "":
			return "rivers[%d]（reach %d）终点边（河口）%s" % [ri, r.reach_id, shore_err]
	# ② 水体 → 河段（inlet 镜像：每条 inlet 必有 reach 终点对上且指向本水体）
	for b in water_bodies:
		for lk in b.inlet_links:
			var matched := false
			for r in rivers:
				if r.water_body_id == b.water_body_id \
						and r.edges[r.edges.size() - 1] == lk:
					matched = true
					break
			if not matched:
				return "WATER_INLET：水体 %d 的 inlet %s 无河段终点对账（双向对账的镜像侧）" \
					% [b.water_body_id, str(lk)]
	# ③ 湖出口不高于溢流口：自本湖源出的河段（首边 ∈ outlet_links）首段水位 ≤ 本体水位
	for b in water_bodies:
		for lk in b.outlet_links:
			for r in rivers:
				if r.edges[0] == lk:
					if r.water_levels[0] > b.water_level:
						return "WATER_OUTLET_LEVEL：水体 %d 出口 %s 源出的 reach %d 首段水位 %d > 本体 %d（湖出口不高于溢流口）" \
							% [b.water_body_id, str(lk), r.reach_id, r.water_levels[0], b.water_level]
	# ④ link ↔ reach 双向对账（草案 §4：link 表 river_reach_id 与 reach.edges 零冗余互证）
	for e in river_edge_owner:
		var owner: int = river_edge_owner[e]
		var claimed: Variant = river_claim.get(e, ID_NONE)
		if int(claimed) != owner:
			return "LINK_RIVER_MISMATCH：reach %d 的边 %s 在 link 表缺失或 river_reach_id≠%d（got %s）——双向对账" \
				% [owner, str(e), owner, str(claimed)]
	for e in river_claim:
		if not river_edge_owner.has(e):
			return "LINK_RIVER_MISMATCH：link %s 声明有河（reach %d）但无任何 reach.edges 含此边" \
				% [str(e), int(river_claim[e])]
	return ""


## 聚落/势力面（WORLD-03，草案 §9 转正 + 拍板⑧归属合同）：POI 形状/规范序/footprint
## 随 kind 钉死、主城对账、cell_owners 值域与水格恒中立。footprint 的通行性/设施
## 冲突（河岸锚点格/桥端/道路/他方出生区）与资源可达属 WORLD-04 校验器面
## （world_validator.gd——数据层只钉形状与引用，可玩性判定在校验器）。
func _validate_settlement(map: MapDataClass) -> String:
	# ---- POI：主键/规范序/kind/footprint 形状 ----
	var prev_id := ID_NONE
	var spawn_footprints := {}  # SPAWN_ZONE footprint 并查重（他方出生区重叠在此查——
	# 数据层可判的重叠面；与设施的冲突在校验器）
	for pi in pois.size():
		var p := pois[pi]
		if p.poi_id < 0:
			return "pois[%d] poi_id=%d 非法（负主键）" % [pi, p.poi_id]
		if prev_id != ID_NONE and p.poi_id <= prev_id:
			return "pois[%d] 破坏规范序（须按 poi_id 严格升序——含主键重复；got %d after %d）" \
				% [pi, p.poi_id, prev_id]
		prev_id = p.poi_id
		if p.kind != POIData.Kind.SETTLEMENT and p.kind != POIData.Kind.SPAWN_ZONE \
				and p.kind != POIData.Kind.RESOURCE:
			return "pois[%d]（poi %d）kind=%d 非法（SETTLEMENT/SPAWN_ZONE/RESOURCE 三值，§9）" \
				% [pi, p.poi_id, p.kind]
		if p.role.is_empty():
			return "pois[%d]（poi %d）role 为空（占位载体也须非空——无 role 的 POI 无意义）" \
				% [pi, p.poi_id]
		if p.cell_id < 0 or p.cell_id >= map.cell_count():
			return "pois[%d]（poi %d）cell_id=%d 指向界外格（图共 %d 格）" \
				% [pi, p.poi_id, p.cell_id, map.cell_count()]
		if p.footprint_cells.is_empty():
			return "pois[%d]（poi %d）footprint 为空（至少含锚定格，§9）" % [pi, p.poi_id]
		var prev_cell := ID_NONE
		for ci in p.footprint_cells.size():
			var cid := p.footprint_cells[ci]
			if cid < 0 or cid >= map.cell_count():
				return "pois[%d]（poi %d）footprint[%d]=%d 指向界外格" % [pi, p.poi_id, ci, cid]
			if prev_cell != ID_NONE and cid <= prev_cell:
				return "pois[%d]（poi %d）footprint 破坏行主序规范序（含重复格 %d）" \
					% [pi, p.poi_id, cid]
			prev_cell = cid
		if not p.footprint_cells.has(p.cell_id):
			return "pois[%d]（poi %d）footprint 须含锚定格 %d（行主序规范序——升序含锚，§9）" \
				% [pi, p.poi_id, p.cell_id]
		if p.kind == POIData.Kind.SPAWN_ZONE:
			# 形状钉死：中心 + 六邻恰 7 格（拍板⑩；第 2..7 项须恰为锚定格的六个邻居
			# ——界内已由 footprint 界内查保证，此处查集合等价）
			if p.footprint_cells.size() != 7:
				return "POI_SHAPE：pois[%d]（poi %d）SPAWN_ZONE footprint %d 格 ≠ 7（中心+六邻，拍板⑩）" \
					% [pi, p.poi_id, p.footprint_cells.size()]
			var want := {p.cell_id: true}
			var anchor := _cell_of_id(map, p.cell_id)
			for d in 6:
				want[map.index_of(Hex.neighbor(anchor, d))] = true
			for cid in p.footprint_cells:
				if not want.has(cid):
					return "POI_SHAPE：pois[%d]（poi %d）SPAWN_ZONE footprint 含非「中心+六邻」格 %d" \
						% [pi, p.poi_id, cid]
			for cid in want:
				if not p.footprint_cells.has(cid):
					return "POI_SHAPE：pois[%d]（poi %d）SPAWN_ZONE footprint 缺「中心+六邻」格 %d" \
						% [pi, p.poi_id, cid]
			for cid in p.footprint_cells:
				if spawn_footprints.has(cid) and spawn_footprints[cid] != p.poi_id:
					return "POI_SHAPE：pois[%d]（poi %d）出生区 footprint 格 %d 与 poi %d 重叠（他方出生区，WORLD-03 ⑤）" \
						% [pi, p.poi_id, cid, int(spawn_footprints[cid])]
				spawn_footprints[cid] = p.poi_id
		else:
			if p.footprint_cells.size() != 1 or p.footprint_cells[0] != p.cell_id:
				return "POI_SHAPE：pois[%d]（poi %d）聚落/资源 footprint 须 = [锚定格] 单格（§9 初版值域）" \
					% [pi, p.poi_id]
	# ---- states：主键/规范序/主城对账 ----
	var s_prev := ID_NONE
	var capital_seen := {}
	for si in states.size():
		var s := states[si]
		if s.state_id < 0:
			return "states[%d] state_id=%d 非法（负主键）" % [si, s.state_id]
		if s_prev != ID_NONE and s.state_id <= s_prev:
			return "states[%d] 破坏规范序（须按 state_id 严格升序——含主键重复）" % si
		s_prev = s.state_id
		if s.expansionism < 1:
			return "states[%d]（state %d）expansionism=%d 非法（≥1——成本分母为 0 无意义）" \
				% [si, s.state_id, s.expansionism]
		var cap := poi_by_id(s.capital_poi_id)
		if cap == null:
			return "STATE_CAPITAL：states[%d]（state %d）capital_poi_id=%d 引用不可解析" \
				% [si, s.state_id, s.capital_poi_id]
		if cap.kind != POIData.Kind.SETTLEMENT:
			return "STATE_CAPITAL：states[%d]（state %d）主城 poi %d kind ≠ SETTLEMENT" \
				% [si, s.state_id, s.capital_poi_id]
		if capital_seen.has(s.capital_poi_id):
			return "STATE_CAPITAL：poi %d 同时为 state %d 与 %d 的主城（不同 state 不共享主城）" \
				% [s.capital_poi_id, int(capital_seen[s.capital_poi_id]), s.state_id]
		capital_seen[s.capital_poi_id] = s.state_id
	# ---- cell_owners：长度/值域/水格恒中立/空 states 语义 ----
	if not cell_owners.is_empty():
		if states.is_empty():
			for cid in cell_owners.size():
				if cell_owners[cid] != ID_NONE:
					return "OWNER_NO_STATE：cell_owners[%d]=%d 但 states 为空（无势力世界 owner 须恒 -1——归属层关的回退态）" \
						% [cid, cell_owners[cid]]
		if cell_owners.size() != map.cell_count():
			return "OWNER_LENGTH：cell_owners 长度 %d ≠ 格子数 %d（行主序逐格对齐）" \
				% [cell_owners.size(), map.cell_count()]
		for cid in cell_owners.size():
			var o := cell_owners[cid]
			if o == ID_NONE:
				continue
			if o < 0 or state_by_id(o) == null:
				return "OWNER_REF：cell_owners[%d]=%d 引用不存在的 state（值域 = {-1} ∪ state_id）" % [cid, o]
			# 水格恒 -1（§7「水格传播成本不归属」；水恒 elevation 0 是量化链不变量）
			if map.elevation_at(_cell_of_id(map, cid)) == 0:
				return "OWNER_WATER：水格 %d owner=%d ≠ -1（水格传播成本不归属——势力不拥有水）" % [cid, o]
	return ""


## 稳定角点 ID（修订记录三之 4）：物理角点 (cell, vertex) 的三个格表示——
## (c,k) = (N_k(c), (k+4)%6) = (N_{k−1}(c), (k+2)%6)（顶点角 30°−60°·i 的三角推得）——
## 取**界内**表示的最小 index_of·6+顶点。任一表示出发同值（与生成路径无关）；
## 地图边界角点仅 2 格界内亦不退化（两角点顶点号必不同，不冲突）。
static func corner_id_of(map: MapDataClass, cell: Vector2i, vertex: int) -> int:
	var v := wrapi(vertex, 0, 6)
	var best := -1
	for rep in [
		[cell, v],
		[Hex.neighbor(cell, v), wrapi(v + 4, 0, 6)],
		[Hex.neighbor(cell, v - 1), wrapi(v + 2, 0, 6)],
	]:
		var c: Vector2i = rep[0]
		if not map.has_cell(c):
			continue
		var id := map.index_of(c) * 6 + int(rep[1])
		if best < 0 or id < best:
			best = id
	return best

# ---------------- 序列化（固定键序——摘要可比较；Vector2i 显式 [x,y] 转换层）----------------

## to_dict 形状（JSON 落盘经 MapIO.write_world）：
##   {"schema_version": 1,
##    "links": [{"link_id": [x, y], "road_id": int, "river_reach_id": int}, …]，
##    "rivers": [{"reach_id": int, "edges": [[x, y], …], "flow_level": int,
##      "water_levels": [int, …], "bed_level": int, "water_body_id": int}, …]，
##    "water_bodies": [{"water_body_id": int, "kind": int, "water_level": int,
##      "member_cells": [int, …], "inlet_links": [[x, y], …],
##      "outlet_links": [[x, y], …], "terminal": bool}, …]，
##    "roads": [{"road_id": int, "cells": [int, …], "is_loop": bool,
##      "road_class": int, "connects_pois": []}, …]，
##    "crossings": [{"crossing_id": int, "kind": int, "river_edge": [x, y],
##      "bank_a": int, "bank_b": int}, …]，
##    "pois": [{"poi_id": int, "kind": int, "cell_id": int,
##      "footprint_cells": [int, …], "role": String}, …]，
##    "states": [{"state_id": int, "capital_poi_id": int, "expansionism": int}, …]，
##    "cell_owners": [int, …]（行长 = 格子数；缺省空数组 = 旧图零迁移），
##    "meta": {§10 字段集}}
##   全部 Vector2i 显式转 [x, y] 数组（引擎直写 JSON.stringify 落成 "(3, 17)" 字符串
##   不可还原，草案 §2.2 实测坑）。states/cell_owners 缺键 = 旧图合法空（零迁移），
##   pois 键自 T2 起恒在（恒空数组）。
func to_dict() -> Dictionary:
	var out_links: Array = []
	for lk in links:
		out_links.append({
			"link_id": [lk.link_id.x, lk.link_id.y],
			"road_id": lk.road_id,
			"river_reach_id": lk.river_reach_id,
		})
	var out_rivers: Array = []
	for r in rivers:
		var edges: Array = []
		for e in r.edges:
			edges.append([e.x, e.y])
		out_rivers.append({
			"reach_id": r.reach_id,
			"edges": edges,
			"flow_level": r.flow_level,
			"water_levels": r.water_levels.duplicate(),
			"bed_level": r.bed_level,
			"water_body_id": r.water_body_id,
		})
	var out_bodies: Array = []
	for b in water_bodies:
		var inlets: Array = []
		for lk in b.inlet_links:
			inlets.append([lk.x, lk.y])
		var outlets: Array = []
		for lk in b.outlet_links:
			outlets.append([lk.x, lk.y])
		out_bodies.append({
			"water_body_id": b.water_body_id,
			"kind": b.kind,
			"water_level": b.water_level,
			"member_cells": b.member_cells.duplicate(),
			"inlet_links": inlets,
			"outlet_links": outlets,
			"terminal": b.terminal,
		})
	var out_roads: Array = []
	for r in roads:
		out_roads.append({
			"road_id": r.road_id,
			"cells": r.cells.duplicate(),
			"is_loop": r.is_loop,
			"road_class": r.road_class,
			"connects_pois": r.connects_pois.duplicate(),
		})
	var out_crossings: Array = []
	for c in crossings:
		out_crossings.append({
			"crossing_id": c.crossing_id,
			"kind": c.kind,
			"river_edge": [c.river_edge.x, c.river_edge.y],
			"bank_a": c.bank_a,
			"bank_b": c.bank_b,
		})
	var out_pois: Array = []
	for p in pois:
		out_pois.append({
			"poi_id": p.poi_id,
			"kind": p.kind,
			"cell_id": p.cell_id,
			"footprint_cells": p.footprint_cells.duplicate(),
			"role": p.role,
		})
	var out_states: Array = []
	for s in states:
		out_states.append({
			"state_id": s.state_id,
			"capital_poi_id": s.capital_poi_id,
			"expansionism": s.expansionism,
		})
	return {
		"schema_version": SCHEMA_VERSION,
		"links": out_links,
		"rivers": out_rivers,
		"water_bodies": out_bodies,
		"roads": out_roads,
		"crossings": out_crossings,
		"pois": out_pois,
		"states": out_states,
		"cell_owners": cell_owners.duplicate(),
		"meta": meta.duplicate(true),
	}


## 版本不符 / 字段缺失 / 形状非法（link_id/edges/river_edge 等长度≠2、非整数、负
## 分量、x≥y；water_levels 与 edges 长度不齐；road_class≠0、crossings kind≠BRIDGE
## 等值域单点字段）/ meta 非字典 → null
## （调用方显式判空，无隐式兜底）。兼容 JSON 数值形状（整数以 float 3.0 出现亦可
## 还原——MapData._is_integral_number 同款）。拓扑/对账语义由 validate 查（分层：
## from_dict 管形状，validate 管世界事实一致性）。pois 自 T5 WORLD-03 起解析非空
## 集合；states/cell_owners 缺键 = 旧图合法空（零迁移，§2.2——与 pois 恒空时代的
## 旧 .world.json 兼容）。
static func from_dict(data: Dictionary) -> WorldData:
	if not data.has_all(["schema_version", "links", "rivers", "water_bodies",
			"roads", "crossings", "pois", "meta"]):
		return null
	if not _is_int(data["schema_version"]) or int(data["schema_version"]) != SCHEMA_VERSION:
		return null
	if not (data["links"] is Array) or not (data["meta"] is Dictionary):
		return null
	# POI 已随 T5 WORLD-03 解锁（role 占位、无经济数值字段——形状层查键集）
	if not (data["pois"] is Array):
		return null
	for needed in ["rivers", "water_bodies", "roads", "crossings"]:
		if not (data[needed] is Array):
			return null
	var out := empty()
	for i in (data["links"] as Array).size():
		var entry: Variant = (data["links"] as Array)[i]
		if not (entry is Dictionary):
			return null
		var d: Dictionary = entry
		if not d.has_all(["link_id", "road_id", "river_reach_id"]):
			return null
		var lid: Variant = _link_id_from(d["link_id"])
		if lid == null:
			return null
		if not _is_int(d["road_id"]) or not _is_int(d["river_reach_id"]):
			return null
		var road_id := int(d["road_id"])
		var reach_id := int(d["river_reach_id"])
		if road_id < ID_NONE or reach_id < ID_NONE:
			return null
		var lk := NeighborLinkData.new()
		lk.link_id = lid
		lk.road_id = road_id
		lk.river_reach_id = reach_id
		out.links.append(lk)
	var rivers_err := _rivers_from_dict(data["rivers"], out)
	if rivers_err:
		return null
	var bodies_err := _bodies_from_dict(data["water_bodies"], out)
	if bodies_err:
		return null
	var roads_err := _roads_from_dict(data["roads"], out)
	if roads_err:
		return null
	var crossings_err := _crossings_from_dict(data["crossings"], out)
	if crossings_err:
		return null
	var pois_err := _pois_from_dict(data["pois"], out)
	if pois_err:
		return null
	# states/cell_owners：缺键 = 旧图合法空（零迁移——T4 时代 .world.json 无此二键）
	if data.has("states"):
		var states_err := _states_from_dict(data["states"], out)
		if states_err:
			return null
	if data.has("cell_owners"):
		if not (data["cell_owners"] is Array):
			return null
		for ov in (data["cell_owners"] as Array):
			if not _is_int(ov) or int(ov) < -1:
				return null
			out.cell_owners.append(int(ov))
	var m := (data["meta"] as Dictionary)
	for k in ["schema_version", "seed", "generator_version", "rules_version",
			"attempt_count", "repair_count"]:
		if not m.has(k) or not _is_int(m[k]):
			return null
	if not m.has("first_pass_valid") or not (m["first_pass_valid"] is bool):
		return null
	for k in ["engine_version", "config_digest", "world_digest"]:
		if not m.has(k) or not (m[k] is String):
			return null
	# meta 规范化重建：整值字段收敛回 int（JSON 往返整数呈 3.0 形状——_is_int 已验
	# 整值性，此处统一类型，保证 to_dict 往返逐位一致）+ 固定键序（摘要可比较）
	var meta := {
		"schema_version": int(m["schema_version"]),
		"seed": int(m["seed"]),
		"generator_version": int(m["generator_version"]),
		"rules_version": int(m["rules_version"]),
		"engine_version": String(m["engine_version"]),
		"config_digest": String(m["config_digest"]),
		"world_digest": String(m["world_digest"]),
		"attempt_count": int(m["attempt_count"]),
		"repair_count": int(m["repair_count"]),
		"first_pass_valid": bool(m["first_pass_valid"]),
	}
	out.meta = meta
	return out


## rivers 数组 → RiverReachData（形状校验：edges/water_levels 逐项 [x,y]/int、
## 长度对齐、主键非负、flow_level ≥1、bed/water_body_id 整数）。
static func _rivers_from_dict(src: Variant, out: WorldData) -> bool:
	if not (src is Array):
		return true
	for entry in (src as Array):
		if not (entry is Dictionary):
			return true
		var d: Dictionary = entry
		if not d.has_all(["reach_id", "edges", "flow_level", "water_levels",
				"bed_level", "water_body_id"]):
			return true
		for k in ["reach_id", "flow_level", "bed_level", "water_body_id"]:
			if not _is_int(d[k]):
				return true
		if int(d["reach_id"]) < 0 or int(d["flow_level"]) < 1 \
				or int(d["water_body_id"]) < ID_NONE:
			return true
		if not (d["edges"] is Array) or not (d["water_levels"] is Array):
			return true
		if (d["edges"] as Array).size() == 0 \
				or (d["edges"] as Array).size() != (d["water_levels"] as Array).size():
			return true
		var r := RiverReachData.new()
		r.reach_id = int(d["reach_id"])
		r.flow_level = int(d["flow_level"])
		r.bed_level = int(d["bed_level"])
		r.water_body_id = int(d["water_body_id"])
		for ev in (d["edges"] as Array):
			var e: Variant = _link_id_from(ev)
			if e == null:
				return true
			r.edges.append(e)
		for wv in (d["water_levels"] as Array):
			if not _is_int(wv):
				return true
			r.water_levels.append(int(wv))
		out.rivers.append(r)
	return false


## water_bodies 数组 → WaterBodyData（形状校验同纪律）。
static func _bodies_from_dict(src: Variant, out: WorldData) -> bool:
	if not (src is Array):
		return true
	for entry in (src as Array):
		if not (entry is Dictionary):
			return true
		var d: Dictionary = entry
		if not d.has_all(["water_body_id", "kind", "water_level", "member_cells",
				"inlet_links", "outlet_links", "terminal"]):
			return true
		for k in ["water_body_id", "kind", "water_level"]:
			if not _is_int(d[k]):
				return true
		if int(d["water_body_id"]) < 0:
			return true
		if not (d["member_cells"] is Array) or not (d["inlet_links"] is Array) \
				or not (d["outlet_links"] is Array) or not (d["terminal"] is bool):
			return true
		var b := WaterBodyData.new()
		b.water_body_id = int(d["water_body_id"])
		b.kind = int(d["kind"])
		b.water_level = int(d["water_level"])
		b.terminal = bool(d["terminal"])
		for cv in (d["member_cells"] as Array):
			if not _is_int(cv) or int(cv) < 0:
				return true
			b.member_cells.append(int(cv))
		for key in ["inlet_links", "outlet_links"]:
			for lv in (d[key] as Array):
				var lk: Variant = _link_id_from(lv)
				if lk == null:
					return true
				if key == "inlet_links":
					b.inlet_links.append(lk)
				else:
					b.outlet_links.append(lk)
		out.water_bodies.append(b)
	return false


## roads 数组 → RoadData（形状校验：cells 全非负 int、is_loop bool、road_class
## **值域单点 == 0**、connects_pois 恒空——值域检查在形状层（flow_level ≥1 同款
## 先例），语义层 validate 不再复议）。
static func _roads_from_dict(src: Variant, out: WorldData) -> bool:
	if not (src is Array):
		return true
	for entry in (src as Array):
		if not (entry is Dictionary):
			return true
		var d: Dictionary = entry
		if not d.has_all(["road_id", "cells", "is_loop", "road_class", "connects_pois"]):
			return true
		for k in ["road_id", "road_class"]:
			if not _is_int(d[k]):
				return true
		if int(d["road_id"]) < 0 or int(d["road_class"]) != 0:
			return true
		if not (d["cells"] is Array) or not (d["is_loop"] is bool) \
				or not (d["connects_pois"] is Array):
			return true
		if not (d["connects_pois"] as Array).is_empty():
			return true  # POI 实体属 T5——没有能力就没有数据
		var r := RoadData.new()
		r.road_id = int(d["road_id"])
		r.is_loop = bool(d["is_loop"])
		r.road_class = int(d["road_class"])
		for cv in (d["cells"] as Array):
			if not _is_int(cv) or int(cv) < 0:
				return true
			r.cells.append(int(cv))
		out.roads.append(r)
	return false


## crossings 数组 → CrossingData（形状校验：kind **值域单点 == Kind.BRIDGE**——
## FERRY 预留不开，形状层即拒；river_edge 显式 [x,y] 转换层；bank 非负 int）。
static func _crossings_from_dict(src: Variant, out: WorldData) -> bool:
	if not (src is Array):
		return true
	for entry in (src as Array):
		if not (entry is Dictionary):
			return true
		var d: Dictionary = entry
		if not d.has_all(["crossing_id", "kind", "river_edge", "bank_a", "bank_b"]):
			return true
		for k in ["crossing_id", "kind", "bank_a", "bank_b"]:
			if not _is_int(d[k]):
				return true
		if int(d["crossing_id"]) < 0 or int(d["bank_a"]) < 0 or int(d["bank_b"]) < 0:
			return true
		if int(d["kind"]) != CrossingData.Kind.BRIDGE:
			return true  # Kind.BRIDGE 唯一合法值（FERRY 拒绝开启）
		var e: Variant = _link_id_from(d["river_edge"])
		if e == null:
			return true
		var c := CrossingData.new()
		c.crossing_id = int(d["crossing_id"])
		c.kind = int(d["kind"])
		c.river_edge = e
		c.bank_a = int(d["bank_a"])
		c.bank_b = int(d["bank_b"])
		out.crossings.append(c)
	return false


## pois 数组 → POIData（形状校验：kind 三值、footprint 非空非负 int 数组、
## role 非空 String——行主序/含锚定格/七格形状属 validate 语义层）。
static func _pois_from_dict(src: Variant, out: WorldData) -> bool:
	if not (src is Array):
		return true
	for entry in (src as Array):
		if not (entry is Dictionary):
			return true
		var d: Dictionary = entry
		if not d.has_all(["poi_id", "kind", "cell_id", "footprint_cells", "role"]):
			return true
		for k in ["poi_id", "kind", "cell_id"]:
			if not _is_int(d[k]):
				return true
		if int(d["poi_id"]) < 0 or int(d["cell_id"]) < 0:
			return true
		if not (d["footprint_cells"] is Array) or not (d["role"] is String):
			return true
		if (d["role"] as String).is_empty():
			return true
		var p := POIData.new()
		p.poi_id = int(d["poi_id"])
		p.kind = int(d["kind"])
		p.cell_id = int(d["cell_id"])
		p.role = String(d["role"])
		for cv in (d["footprint_cells"] as Array):
			if not _is_int(cv) or int(cv) < 0:
				return true
			p.footprint_cells.append(int(cv))
		out.pois.append(p)
	return false


## states 数组 → StateData（形状校验：主键/主城引用/expansionism 均整数且非负——
## capital 可解析性与唯一性属 validate 对账层）。
static func _states_from_dict(src: Variant, out: WorldData) -> bool:
	if not (src is Array):
		return true
	for entry in (src as Array):
		if not (entry is Dictionary):
			return true
		var d: Dictionary = entry
		if not d.has_all(["state_id", "capital_poi_id", "expansionism"]):
			return true
		for k in ["state_id", "capital_poi_id", "expansionism"]:
			if not _is_int(d[k]):
				return true
		if int(d["state_id"]) < 0 or int(d["capital_poi_id"]) < 0 \
				or int(d["expansionism"]) < 1:
			return true
		var s := StateData.new()
		s.state_id = int(d["state_id"])
		s.capital_poi_id = int(d["capital_poi_id"])
		s.expansionism = int(d["expansionism"])
		out.states.append(s)
	return false

# ---------------- 内部 ----------------

## cell 稳定 ID → axial 格（行主序反解：col = id % width、row = id / width）。
static func _cell_of_id(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))

## link_id 字典序（x 优先、y 次之——规范序比较器）。
static func _link_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)

## 数值且为有限整值（int，或无小数部分的有限 float——JSON 往返后整数呈 3.0 形状；
## bool 排除——GDScript `is int` 对 bool 为真，MapData 同款纪律）。
static func _is_int(v: Variant) -> bool:
	if v is bool:
		return false
	if v is int:
		return true
	if v is float:
		return is_finite(v) and int(v) == v
	return false

## [x, y] 数组 → Vector2i（显式转换层的还原侧）：非数组 / 长度 ≠ 2 / 元素非整数 /
## 负分量 / x≥y → null。
static func _link_id_from(v: Variant) -> Variant:
	if not (v is Array):
		return null
	var arr := v as Array
	if arr.size() != 2 or not _is_int(arr[0]) or not _is_int(arr[1]):
		return null
	var x := int(arr[0])
	var y := int(arr[1])
	if x < 0 or y < 0 or x >= y:
		return null
	return Vector2i(x, y)
