# M1a+ 地形世界数据合同（草案）

> **效力：草案（2026-10-10 起草）——非拍板。** 本文件不构成对 04 §M1a+/03 已定范围
> 的改写，不是实现指令，也未动任何代码（纯文档任务）。字段集依据
> [M1a-terrain-world-proposal.md](M1a-terrain-world-proposal.md)「核心设计与数据边界」
> 节（**未拍板提案**）起草，登记来源 = [04-tasks-m1.md](04-tasks-m1.md) §M1a+
> 「数据合同冻结建议（T2/T3 开工前置，只登记不实现）」。
>
> **河流拓扑（穿格 vs 格边）是 ADR 级决策**：本草案全文默认**穿格**口径，仅因方案
> 如此建议（Catlike 同款；方案「河流坐标约定必须先选定」节）。主创改判格边河流 →
> §5 RiverReachData 与 §8 CrossingData 的字段集**整体重议**（格边河须另补稳定
> 顶点/角图与排水映射），且同一地图不得混用两种河流语义。
> 任何一项进代码前须过方案文末「需要主创确认的决策」清单；**河流拓扑项阻塞 T3，
> T3 开工前须回 [02-architecture.md](02-architecture.md) 立 ADR**（现行最新为
> ADR-13，新 ADR 编号届时顺延）。决策清单六项：河流拓扑（阻 T3）/ 视觉风格
>（阻 T2 深化）/ 首个世界模板（阻 T5）/ 地形玩法（阻 T6，非 T1）/ 目标硬件与
> 渲染器（阻性能验收）/ 排期取舍（阻扩范围）。

---

## 0. 本草案要解决什么

方案「核心设计与数据边界」节给出九类数据的职责一句话表；本草案把它落成
**逐字段定义**（字段名/类型/约束/初版口径/初版禁止项），作为 T2（地貌升级）与
T3（水系切片）开工前的数据合同底稿。三类分离口径照抄方案：**世界事实**
（是什么、在哪里、如何连接）/ **游戏规则**（能否穿越、多少费用）/ **表现**
（怎么画、如何装饰）——本草案只覆盖世界事实层；规则与表现不得从对方反推
（尤其不能从河水渲染反推通行性）。

## 1. 范围与边界

### 1.1 定义（本草案覆盖）

- `WorldData` 容器与七个成员实体：`NeighborLinkData`、`RiverReachData`、
  `WaterBodyData`、`RoadData`、`CrossingData`、`POIData`、`WorldMeta`；
- 各实体初版禁止项（§3~§10 逐节列出，§11 汇总到校验器要点）；
- 与现有 `MapData` / 生成器 / 落盘管线的兼容口径（§2）。

### 1.2 不定义（范围外，防止越权）

- **`WorldFields`**（连续生成高程/湿度/温度/生态区）：方案归 T5，不在本草案；
- **`TraversalPolicy`**（规则层接口）：方案归 M3 拍板，本草案只定"数据侧不承载
  任何规则语义"的边界，不定接口；
- **任何数值**：移动费、伤害、视野、资源产出/成本一概不进字段集
  （方案非目标「不在美术提交中偷偷改变移动费、伤害、LOS 或视野」）；
- **世界模板 schema**（`temperate_river_valley` 的 YAML 形态）：那是生成器配置
  层，非世界事实数据；`WorldMeta` 只承载其摘要（§10）；
- **实现**：本草案不附任何 .gd 文件；§12 才是转正路径。

## 2. 与现有实现的兼容性总纲（并存，不塞 `mods`）

### 2.1 MapData 一字不动

方案口径：现有 `MapData` 保持为兼容的核心格子数据，`WorldData` 建在**旁边**；
不把河流、道路、资源和气候塞进通用 `mods`；旧地图缺失的新字段默认为
"无河、无路、无 POI"，**不是**加载时重新随机生成。对照现有实现逐条核实：

| 兼容点 | 现有实现事实（2026-10-10 核实） | 本草案口径 |
|---|---|---|
| 格子稳定 ID | `MapData.index_of`（`scripts/core/data/map_data.gd`）= 行主序存储下标 `row*width+col`，类注释明言"index 即格子稳定 ID"，T4 共享边/角归属比较器已用它 | 全部实体引用格子一律用此 ID（`cell_id: int`），**不另立 ID 体系**；`link_id=(min,max)` 的 min/max 即两个 `index_of` 值 |
| `mods` 铁律 | `map_data.gd` 类头注：任何结算、查询、摘要不得读 `mods`，只有序列化原样保存 | WorldData 实体**永不写入** `mods`——塞进去等于造永远不可读的死数据，恰是方案禁止项 |
| 序列化白名单 | `MapData.from_dict` 必需键 = `to_dict` 七键（`schema_version/width/height/terrain/elevation/passable/mods`）；多余键忽略，向前兼容由 `SCHEMA_VERSION` 把关 | WorldData 走**独立伴生文件**（§2.2），MapData 的 dict 与 `SCHEMA_VERSION=1` 零改动；旧图不因新数据出现"版本不符"而被拒 |
| 生成器 meta 命名 | `scripts/content/map_generator.gd` 的 meta 键：`generator_version/params/digest/engine_version/reproducibility_note/connectivity/...`；`GENERATOR_VERSION=1` 常量先例 | `WorldMeta` 字段命名对齐（§10）：`generator_version`/`engine_version` 直承，`config_digest`/`world_digest` 与现有格子摘要 `digest` 显式区分 |
| 摘要可比较 | `MapData.summary()` 固定遍历序、`digest()` SHA-256 | WorldData 各实体序列化同样定义**固定键序**（元素按主键升序），保证同图同摘要——确定性复现率指标（方案验收表）的数据面载体 |
| 离散高程纲 | `MapData` 高程 = int 分层（可为负），世界 y = 高程 × `elevation_step`（builder 现算） | `water_level`/`bed_level` 等**标高一律同离散纲**（int 分层，同图同 `elevation_step` 换算）；连续高程属 WorldFields（T5），不进本草案 |

### 2.2 载体与伴生文件（旧图 = 无河无路无 POI）

沿用 `scripts/content/map_io.gd` 的伴生文件先例（每张图三件：
`<name>.json` 格子表 + `<name>.meta.json` 元数据 + `<name>.summary.txt` 摘要）：

- 新增第四伴生 **`<name>.world.json`**（WorldData 容器的 `to_dict` 形状）；
- **读取侧兼容**：该文件缺失/为空 → 返回**空 WorldData**（无河、无路、无 POI、
  无 crossing），不报错、不重新随机生成——这就是"旧图缺字段 = 无河无路无 POI"
  的可执行表达。全部现有固定图/生成图/失败回归样例**零迁移**即可继续加载；
- **`Vector2i`（link_id）不得直接交给 `JSON.stringify`**：引擎 4.7.2 会把它序列化
  成字符串 `"(3, 17)"`（本草案 2026-10-10 实测复核：`JSON.stringify({"link":
  Vector2i(3, 17)})` → `{"link":"(3, 17)"}`，`JSON.parse_string` 回读 typeof=4
  = String，不可还原）；与 `map_io.gd` 头注登记的 `PackedByteArray` → `"[1, 1, …]"`
  同族坑。落盘形状 = **`to_dict` 内显式转 `[x, y]` 两元 int 数组**
  （`MapIO.to_jsonable` 的显式形状转换先例；实测该形状往返无损），
  `from_dict` 由数组重建 `Vector2i`；长度 ≠ 2 / 元素非整数 / 越 int32 →
  null（MapData 元素校验同款纪律，无隐式兜底）；
- M2 `MapDef` .tres 化时（04 M1a-T2"两名一物"口径）WorldData 是否并入同一
  Resource 由 M2 任务定，本草案只冻结字段集与键序。

### 2.3 命名与风格约定（对齐现有代码惯例）

以下约定从现有代码提炼，实体定义（§3~§10）全部遵守：

- 类名 `PascalCase` + 语义后缀（`MapData` 先例 → `*Data`）；纯 `RefCounted`、
  零场景节点（ADR-2；"删 `scripts/ui/**` 后 tests 全绿"口径）；
- 字段 `snake_case`；常量 `SCREAMING_SNAKE`（`SCHEMA_VERSION` 先例）；
- **哨兵用负值**（`TERRAIN_NONE=-1`、`ELEVATION_NONE` 先例）→ 本草案：
  `ID_NONE := -1`（一切 id 引用哨兵）、`NO_LINK := Vector2i(-1, -1)`
  （link 哨兵——负分量天然非法，因 cell_id 恒非负）；
- 枚举值大写（`TerrainStyle.Mode.SLOTS/BLEND` 先例）→ `Kind.SEA/LAKE`、
  `Kind.BRIDGE` 等；
- 校验函数返回 `""`（合法）/原因串（`MapGenParams.validate` 先例）；
  `from_dict` 非法 → `null`（调用方显式判空）；
- 锚点**绝对坐标不落盘**：`hex_terrain_builder.gd` 类头注"接缝顶点从同一全局
  格心/边参数计算，不在两个 chunk 内各自扰动"先例 + 方案"河段与桥端锚点应从
  世界数据计算，不让两个 chunk 分别随机生成"——实体只存拓扑引用与离散标高，
  几何锚点由 HexMath 全局参数**唯一路径派生**。

## 3. WorldData 容器（首次需要 T2）

世界事实层的一等容器；持有七个成员集合 + 校验入口。**建议形态**（示意，非交付代码）：

```gdscript
class_name WorldData
extends RefCounted

const SCHEMA_VERSION := 1
const ID_NONE := -1
const NO_LINK := Vector2i(-1, -1)  # x=min(cell_id), y=max(cell_id)；负分量=哨兵

var links: Array[NeighborLinkData]        # 邻接边对象表（link_id 升序为规范序）
var rivers: Array[RiverReachData]         # 河段表（cell_id 升序为规范序）
var water_bodies: Array[WaterBodyData]    # 水体表（water_body_id 升序）
var roads: Array[RoadData]                # 道路表（road_id 升序）
var crossings: Array[CrossingData]        # 过河设施表（crossing_id 升序）
var pois: Array[POIData]                  # 兴趣点表（poi_id 升序）
var meta: WorldMeta

func validate(map: MapData) -> String            # ""=合法（§11 校验器要点）
func link_id_of(a: int, b: int) -> Vector2i      # (min,max) 规范化；同格/负值→NO_LINK
func to_dict() -> Dictionary                     # 固定键序（摘要可比较的前提）
static func from_dict(data: Dictionary) -> WorldData   # 版本不符/非法 → null
static func empty() -> WorldData                 # 旧图口径：全空集合 + 空 meta
```

- 主键自包含：每个实体自带 id 字段（如 `water_body_id`），集合唯一性由校验器查
  （重复主键 = 非法）——错误报告（方案「最小诊断输出」）可直接引用元素 id；
- `empty()` 是**旧图的合法状态**，不是错误：渲染/查询层据此走"无河无路无 POI"
  分支（方案"关闭一个尚未实现能力不产生伪字段"的镜像——没有能力就没有数据，
  而不是补空壳数据）；
- WorldData 不 import 任何场景节点、不持有 mesh/材质引用；渲染各层
  （`WaterGeometryBuilder`/`RoadGeometryBuilder` 等，方案「渲染、拾取与更新方案」）
  只读它。

## 4. NeighborLinkData（首次需要 T2/T3）

方案定义：相邻格之间的稳定 link_id=`(min(cell_id),max(cell_id))`；道路为无向，
river flow 另存 from/to。职责 = 邻接边的**索引面**：回答"这条边上有什么"。

| 字段 | 类型 | 约束与语义 | 初版口径 |
|---|---|---|---|
| `link_id` | `Vector2i` | `x = min(a,b)`、`y = max(a,b)`（a/b = 两端 `cell_id`）；恒 `0 ≤ x < y`；两端格须互为界内邻居（`MapData.neighbors_existing` 校验）——不存在的邻格不产生连接（M1a-T2 边界规则延伸到边表） | 即主键；与集合 key 一致 |
| `road_id` | `int` | 本边被哪条道路占用（无向）；`ID_NONE` = 无路；须与 `RoadData.cells` 对账：本 link 两端恰为该道路序列中相邻两格 | 初版可全 `ID_NONE`（T4 才有路） |
| `river_from` | `int` | 本边有河水时 = 流出格 `cell_id`；无河 = `ID_NONE`；有河时须为 link 两端之一，且 `river_from != river_to` | 与 `RiverReachData.outgoing` 双向对账 |
| `river_to` | `int` | 同上，流入格 `cell_id`；无河时与 `river_from` 同为 `ID_NONE` | 与 `RiverReachData.incoming` 双向对账 |

**初版禁止项**：
- 不承载地形/高差/连接类型——`classify_edge`（builder）属几何派生，现算不入表；
- 同一 link 的河水只有一个方向（`from`/`to` 单向对，不存在双向河道）；
- **"同一 link 上有河和路"不得推导出"需要桥"**（方案原文：那可能是顺河方向的
  重叠而非横切河道；桥判定见 §8）。

## 5. RiverReachData（首次需要 T3；**穿格口径——ADR 未立，见文档头**）

方案定义：incoming 列表、最多一个 outgoing、流量等级、河床/水面锚点、所属水系；
预留汇流而不提前开放。穿格约定下**一段 reach = 一格内的河段**（河水从本格穿过
共享边流入邻格），主键 = `cell_id`（一格最多一段河）。

| 字段 | 类型 | 约束与语义 | 初版口径 |
|---|---|---|---|
| `cell_id` | `int` | reach 所在格 = 主键；全图唯一（同格第二段河非法）；格子保持**陆地地形**（见禁止项） | 手工主河/支流均如此锚定 |
| `incoming` | `Array[Vector2i]` | 入边 link_id 列表（河水从这些边流入本格）；每项须合法 link 且 `river_to == cell_id` | **初版长度 ≤ 1**（WATER-01"1 入 1 出"）；列表形态为汇流（2 入 1 出）预留，第二版才开放 |
| `outgoing` | `Vector2i` | 出边 link_id（河水流出本格）；`NO_LINK` = 本段是终点（汇入水体，见 `water_body_id`）；有值时须 `river_from == cell_id` | 恒 ≤ 1（无字段可塞第二个——分叉/三角洲**结构上**做不了） |
| `flow_level` | `int` | 流量等级（主河/支流分级）；`≥ 1`；等级→河宽/流速映射属表现参数，不进数据 | 手工图按模板指定 |
| `water_level` | `int` | 水面离散标高（与 `MapData` 高程同纲）；沿河单调不上升（量化后重验，方案「水系的可执行合同」）；共享连接两端 reach 的水面锚点标高必须一致 | 湖/海邻接段须与水体 `water_level` 一致 |
| `bed_level` | `int` | 河床离散标高；恒 `< water_level`（河床容纳校验的下界） | 几何河床形状由全局参数派生，只存标高 |
| `river_system_id` | `int` | 所属水系（同一条河的干/支流同值）；编号口径 = 生成器/模板职责，数据只保证引用存在 | 手工图可为单值 |
| `water_body_id` | `int` | **终点段汇入的水体**（`WaterBodyData` 主键引用）：`outgoing == NO_LINK`（终点段）时必须有值，所指水体须存在且 `terminal == true`，且 `outgoing` 边的 `river_to` 端格须 ∈ 该水体 `member_cells`（河水确从本段汇入）；非终点段（`outgoing != NO_LINK`）必须为 `ID_NONE`——结构互斥，两个方向都非法 | 与 `WaterBodyData.inlet_links` 双向对账（§6） |

- **河床/水面锚点**（方案字段原文）的落法：锚点**位置**（入边中点、出边中点、
  格心）由 `cell_id` + link 方向经 HexMath 全局参数**唯一路径派生**，不落盘坐标
  （§2.3）；数据承载的是锚点的**标高合同**（`water_level`/`bed_level` 两字段）
  ——同一共享边两侧 chunk 各自派生位置必然逐位一致（builder 接缝先例）。
- 终点语义由结构表达：`outgoing == NO_LINK` 的 reach 是终点段，其归着水体由
  `water_body_id` 显式引用（校验器查所指水体 `terminal == true`，且汇入边
  `river_to` 端 ∈ 该水体 `member_cells`，见字段表）——
  方案"海/湖出口由数据声明，不要求全部入海"。

**初版禁止项**：
- `incoming.size() > 1` 非法（汇流预留不开）；任何形式的出流分叉非法；
- **渲染河道不得把河流格整格设为水体禁行**——reach 不回写 `MapData` 的
  `passable`/`terrain`/`mods`；穿河可达性由 `TraversalPolicy` + `CrossingData`
  回答（M3 拍板前"视觉模式"）；
- 河流与道路交叉只允许通过专门 crossing 解决（§8）；初版禁止道路纵向覆盖河槽
  （重合格必须有 crossing 认领，见 §7 禁止项）；
- 水深/流速/河宽/瀑布形态 = 表现参数，不是本实体的字段。

## 6. WaterBodyData（首次需要 T3）

方案定义：海/湖类型、水面标高、成员格、入/出水口、合法终点声明。

| 字段 | 类型 | 约束与语义 | 初版口径 |
|---|---|---|---|
| `water_body_id` | `int` | 主键；全容器唯一 | — |
| `kind` | `int`（枚举 `Kind`） | `Kind.SEA` / `Kind.LAKE` | 初版两值 |
| `water_level` | `int` | 水面离散标高；**同一水体成员水位恒一致**（方案拓扑护栏"同一湖体水位一致"） | 与邻接 reach 的 `water_level` 对账 |
| `member_cells` | `Array[int]` | 成员格 `cell_id` 列表，行主序规范序（摘要可比较）；全图不重复、不同水体不共享格 | 与 `MapData` 对账：成员格 `terrain` 应为水（TERRAIN_WATER 口径）——这是**校验**不是回写（生成器建立对应，校验器拒绝对不上的图） |
| `inlet_links` | `Array[Vector2i]` | 入水口（河水汇入本水体的边）；与全部 `RiverReachData` 终点对账（某 reach 终点 = 本体 ⇔ 其 `water_body_id` = 本 id） | 对账不上的图非法 |
| `outlet_links` | `Array[Vector2i]` | 出水口（湖溢流口/海不适用恒空）；出口水位不得高于本水体 `water_level`（方案"湖出口不高于允许的溢流口"） | 数量上限初版不设（方案未定），校验只查单调 |
| `terminal` | `bool` | 合法终点声明：河流是否允许以本水体为终点（海恒 true；湖 true = 终点湖、false = 过路湖必须有出口） | 手工图显式声明 |

**初版禁止项**：不做动态水位/潮汐/季节（非目标"不做真实流体"）；成员格语义
变化（如湖填成陆地）= 编辑操作走 WorldData 重建，不提供增量字段。

## 7. RoadData（首次需要 T4）

方案定义：道路图、路线段、等级和聚落连接；不直接保存兵种移动费。道路 = 格中心
网络（与河流同构），一条道路 = 无重复格的有序路线段。

| 字段 | 类型 | 约束与语义 | 初版口径 |
|---|---|---|---|
| `road_id` | `int` | 主键；全容器唯一；被 `NeighborLinkData.road_id` 引用 | — |
| `cells` | `Array[int]` | 路线段 = 有序 `cell_id` 序列；相邻元素互为界内邻居（校验）；格不重复；端点 = 首末元素（端点/直路/转弯由序列形状天然表达） | — |
| `is_loop` | `bool` | 回路标记；true 时首末格亦须互为邻居（可选回路，方案 `add_optional_road_loops`） | 默认 false |
| `road_class` | `int` | 道路等级；**恒 0**（单一级别）——等级差异化是 T4 Could，开启时须重过 ROAD-01 验收 | 0 = 唯一级别（值域单点 = 能力关闭的显式表达，非伪字段） |
| `connects_pois` | `Array[int]` | 本道路连接的 POI id 列表；须与 `POIData` 对账且 = 该 POI 的锚定格或 footprint 格 | 先连接实际聚落，不随机画线（方案「道路与聚落的可执行合同」） |

- "道路图"= `RoadData` 序列 + `NeighborLinkData.road_id` 索引的合成面：双向一致
  由 link 的无向性保证（ROAD-01"相邻双向一致"的数据面）；
- **路口**：多条道路共享同一 `cell_id` 即路口（端点/三叉/更多叉由共享格的重数
  表达）——同一 data contract 覆盖全部路口形态（ROAD-01 验收原文），不设专门
  路口实体。

**初版禁止项**：
- **不保存任何移动费/路径权重**（方案原文"不直接保存兵种移动费"；路径权重
  表达绕山/绕水/建设偏好，是生成器内部口径，不落世界事实）；
- 初版禁止道路纵向覆盖河槽：`cells` 与任一 `RiverReachData.cell_id` 重合的格，
  必须被某 `CrossingData` 认领为横切（§8），否则整图非法——路线改走岸边或
  重新寻路，不静默放行；
- 不做玩家修路/收费/维修经济（非目标"完整建造游戏"）；
- 相邻格高差超配置拒绝（ROAD-01）是**校验器约束**，阈值在生成配置里、不进数据。

## 8. CrossingData（首次需要 T4；穿格口径——同 §5 注）

方案定义：桥/渡口锚点、连接哪两侧陆路、依赖哪段河道、实际可穿越边；初版只做桥。
桥的判定（方案原文）：道路折线从一侧河岸进入、**横切**河道后到达另一侧；桥对象
记录两岸和覆盖水域，**不能以两条网络共享 link_id 代替相交检测**。

| 字段 | 类型 | 约束与语义 | 初版口径 |
|---|---|---|---|
| `crossing_id` | `int` | 主键；全容器唯一 | — |
| `kind` | `int`（枚举 `Kind`） | `Kind.BRIDGE`（初版唯一合法值；`Kind.FERRY` 预留不开） | 只做桥 |
| `bridge_cell` | `int` | 桥所在格 = 被横切的河段格；必须是某 `RiverReachData.cell_id` | 桥端锚点位置由两岸格 + 河道流向全局参数派生（§2.3），不落盘坐标 |
| `bank_a` / `bank_b` | `int` | 两侧陆路格（道路从 bank_a 经 bridge_cell 到 bank_b）；各自与 `bridge_cell` 互为邻居、彼此不同、均非河段格 | 两岸锚点即道路折线的进/出点 |
| `river_cells` | `Array[int]` | 覆盖水域 = 桥下河段格列表（多格宽河道全列）；每格必须是 `RiverReachData.cell_id` | 与 `bridge_cell` 同属一条河 |
| `traversable_edges` | `Array[Vector2i]` | 实际可穿越边 link 列表（`TraversalPolicy` 的唯一数据入口——"跨河可达"从此处查询，不从渲染判断） | 初版 = `{bank_a↔bridge_cell, bridge_cell↔bank_b}` 两条 link |

**横切的机器定义**（写入校验器，替代"目测像横切"）：过桥路径的边
（`bank_a→bridge_cell`、`bridge_cell→bank_b` 两条 link）与 `bridge_cell` 河段的
`incoming`/`outgoing` link **不得重合**——车流方向不沿河水方向，即"横切而非
顺河"（方案"那可能是顺河方向的重叠，而非横切河道"的可判定表达）。

**初版禁止项**：
- 渡口（`Kind.FERRY`）预留值不开——枚举里的存在 ≠ 能力开放；
- 桥不是移动费数据源（过桥成本 M3 拍板，`rules_version=0` 期间一切规则效果关闭）；
- **禁止**用"道路 link 与河流 link 相同"当桥用（无 crossing 对象的重合 =
  §7 禁止项的非法图）。

## 9. POIData（首次需要 T5）

方案定义：聚落、出生候选区、资源点、预留 footprint 和目标角色；资源经济数值由
M2 决定。

| 字段 | 类型 | 约束与语义 | 初版口径 |
|---|---|---|---|
| `poi_id` | `int` | 主键；全容器唯一 | — |
| `kind` | `int`（枚举 `Kind`） | `Kind.SETTLEMENT`（聚落）/ `Kind.SPAWN_ZONE`（出生候选区）/ `Kind.RESOURCE`（资源点） | 三值 |
| `cell_id` | `int` | 锚定格；界内 | — |
| `footprint_cells` | `Array[int]` | 占位 footprint（行主序规范序、含锚定格、不重复）；**初版值域**：聚落/资源 = `[cell_id]` 单格；出生区 = 中心 + 六邻（方案模板 `spawn_footprint: center_plus_six_neighbors`）——footprint 格须界内、可通行（出生区有效率指标的校验面） | 多格聚落后续开 |
| `role` | `String` | 目标角色标签（如主城/出生候选/核心资源）；语义由世界模板与场景层引用，数据层不解释、不定值域 | **占位载体**（04 §M1a+ 边界声明"M2 资源定稿前 POI 用 role 占位"） |

**footprint 冲突约束**（WORLD-03 校验面）：footprint 格不得与河段格、桥端格
（`bank_a/bank_b`）、道路格重叠。

**初版禁止项**：
- **不编造资源经济数值**——产出/储量/成本字段一概不存在（M2 定稿后再议，
  方案"T5 用 POI role 和占位资源预算验证地图结构，不编造正式产出或成本"）；
- 不定义阵营归属/俘虏/占领语义（scenario 层，T5 模板 + M2+ 规则）；
- 资源预算/距离目标在模板配置里，不进实体字段。

## 10. WorldMeta（首次需要 T0/T5）

方案定义：seed、生成器/规则/schema/引擎构建版本、配置摘要、逻辑摘要、尝试与
修复记录。命名对齐现有生成器 meta（`map_generator.gd`）与方案「最小诊断输出」。

| 字段 | 类型 | 约束与语义 | 初版口径 |
|---|---|---|---|
| `schema_version` | `int` | = `WorldData.SCHEMA_VERSION`；`from_dict` 拒绝版本不符 | 1 |
| `seed` | `int` | root seed；具名随机通道（geography/hydrology/biome/poi/roads/decoration）由 root seed + 具名偏移常量派生（`MOISTURE_SEED_OFFSET` 先例），**派生值不落盘** | 手工图可为 0（非生成产物） |
| `generator_version` | `int` | 世界生成器版本（`MapGenerator.GENERATOR_VERSION` 同款常量先例，世界管线独立计数） | 0 = 手工固定图 |
| `rules_version` | `int` | 规则/TraversalPolicy 版本；**恒 0 = 地形效果未启用（视觉模式）**——UI/沙盒须能据此显式标注 | 0（M3 拍板后才变） |
| `engine_version` | `String` | 引擎构建串（`Engine.get_version_info()["string"]` 同源） | — |
| `config_digest` | `String` | 配置摘要（模板 id + 参数集的稳定哈希）；与现有 `meta.params` 分工：params 落全量、digest 供比对 | 手工图 = 模板指纹 |
| `world_digest` | `String` | **世界逻辑摘要** = MapData 格子摘要 + WorldData 七集合规范序摘要的复合哈希；确定性复现率指标（方案验收表"同配置重跑世界逻辑摘要一致"）的数据面 | 与 `MapData.digest`（纯格子）显式区分 |
| `attempt_count` | `int` | 生成尝试次数（含失败） | 手工图 = 1 |
| `repair_count` | `int` | 有限修复次数 | 手工图 = 0 |
| `first_pass_valid` | `bool` | 首次生成即合格（不靠重试） | 手工图 = true |

**初版禁止项**：不含渲染 profile/帧统计（那是 `WorldValidationReport` 的
`render_profile/frame_p95_ms`，属诊断报告非世界事实）；不含 seed 银行/设备信息
（诊断报告字段，另走报告通道）。

## 11. 校验器要点（数据/拓扑门，方案门禁矩阵第一行）

`WorldData.validate(map) -> String`（""=合法；原因串须指向具体 cell/link/约束，
方案错误码先包括 `NO_VALID_SPAWN`、`RESOURCE_UNREACHABLE`、`RIVER_CYCLE`、
`NO_RIVER_OUTLET`、`BRIDGE_ENDPOINT_INVALID`、`ROAD_NETWORK_DISCONNECTED`、
`LOCKED_CONSTRAINT_CONFLICT`）。按节汇总：

- **全局**：主键唯一；全部 id/link 引用可解析且指向界内格；`from_dict` 对
  版本不符/字段缺失/NaN/非整数/越 int32 一律拒绝（MapData 元素校验同款纪律）；
  WorldData 零回写 MapData（含 `mods`）。
- **link 表**：两端互为界内邻居（不存在邻格不产生连接）；`river_from/to`
  与 reach 表双向对账；`road_id` 与道路序列对账。
- **河流**：无环（`RIVER_CYCLE`）、有终点且终点水体 `terminal=true`
  （`NO_RIVER_OUTLET`）；沿河 `water_level` 单调不升；`bed_level < water_level`；
  同格唯一 reach；`incoming ≤ 1`。
- **道路**：序列相邻合法；必需聚落全连通（`ROAD_NETWORK_DISCONNECTED`）；
  与河重合格必须有 crossing 认领；footprint 冲突检查。
- **桥**：两岸/桥端锚点合法（`BRIDGE_ENDPOINT_INVALID`）；横切判定（§8 机器
  定义）；`traversable_edges` 与两端 link 一致。
- **POI**：出生 footprint 七格界内可通行（`NO_VALID_SPAWN`）；必需资源可达
  （`RESOURCE_UNREACHABLE`，用实际启用的 TraversalPolicy 验证——规则未启用时
  按平地通行口径）。

## 12. 转正检查清单（本草案 → 可开工合同）

1. 主创过方案文末「需要主创确认的决策」清单，**河流拓扑项拍板**并在 02 立 ADR
   （穿格 → 本草案 §5/§8 原样转正；格边 → 两节重议，其余实体基本不动）；
2. ADR 立后：本文件头部效力块改「已按 ADR-NN 转正」+ 04 §M1a+ 登记证据；
3. T2 开工时：`WorldData` 容器 + `NeighborLinkData` + 校验器 + 单测落地
   （`addons/hexhammer` 或 `scripts/core/data` 纯逻辑层、`tests/test_*.gd`
   headless 锚——沿用全仓先例；**序列化往返与 Vector2i 显式转换层
   （§2.2）必须进测试锚**，防止直写 stringify 落成 `"(x, y)"` 字符串），
   旧图/固定图零迁移跑通门禁；
4. T3 起逐实体解锁：reach/water_body（T3）→ road/crossing（T4）→ poi（T5）；
   每解锁一个实体，其"初版禁止项"表同步进校验器与测试锚。

---

*起草核对记录（2026-10-10）：字段集逐一对照方案「核心设计与数据边界」节九行
数据表与「河流坐标约定必须先选定」「水系的可执行合同」「道路与聚落的可执行
合同」「最小诊断输出」节；兼容性对照 `scripts/core/data/map_data.gd`（index_of/
mods 铁律/to_dict/from_dict/summary）、`scripts/content/map_generator.gd`
（meta 命名/GENERATOR_VERSION/MOISTURE_SEED_OFFSET）、
`scripts/content/map_io.gd`（伴生文件）、`scripts/content/map_gen_params.gd`
（validate 先例）现行实现；命名风格对照 `MapData`/`TerrainStyle.Mode`/
`TERRAIN_NONE` 哨兵先例。本文件为纯文档交付，未改任何代码；门禁基线
2026-10-10 实测 202 用例 / 0 失败（`tools/run_tests.gd`，exit 0）。*

*修订（2026-10-10 独立复查后两条）：① §5 字段表补 `water_body_id`——终点
对账语义（§5 终点段/§6 `inlet_links`）此前引用该字段而字段表未定义；② §2.2
改正 Vector2i 的 JSON 事实并规定显式转换层——原文"在 JSON 中呈 [x, y] 两元
数组"与引擎实测不符（直写 stringify 落成字符串 `"(3, 17)"`、不可往返），
§12 转正清单同步加序列化往返测试锚。修订后门禁复跑仍 202 用例 / 0 失败。*
