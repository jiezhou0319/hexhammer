# M1a 地形 T2–T5 执行方案（数据合同格边重议 + 十三卡执行案）

> **定位**：`docs/M1a-terrain-world-proposal.md`（下称提案）T2–T5 十三张任务卡的逐卡执行
> 方案 + 数据合同草案 §5/§8 格边重议案。**本方案属非拍板文档**——卡内一切标注
> 「须主创拍板」的事项不得默认通过；已拍板项（04 §M1a+ 2026-10-10 主创拍板①~⑥、
> 02 ADR-14）原样遵守，本文不重开。
>
> **上承**：提案（docs/M1a-terrain-world-proposal.md）· 04 §M1a+（docs/04-tasks-m1.md
> :129-153 拍板与第一批卡登记）· 02 ADR-14 格边河流（docs/02-architecture.md
> :207-227；ADR-13 紧邻其上）· 数据合同草案（docs/M1a-terrain-data-contract-draft.md，§5/§8 自署
> :19-24 作废待重议）· 内容管线（docs/12-terrain-content-pipeline.md，效力同调研类、
> 未共创审）。
>
> **调研来源**（五份，均为 2026-10-10 外部调研核读）：Catlike Hex Map 系列（27 部，
> Part 3/6/7/8/11/23/26 正文已核）、Red Blob（polygon-map-generation / mapgen4 /
> x/1723 河网）、Azgaar Fantasy Map Generator（源码级深读）、WFC hex-map（16k 字
> 全文）、dual grid（BorisTheBrave quarter-tile autotiling）。URL 逐条见 §1。
>
> **环境注（2026-10-10 本机实查）**：Godot 4.7.2 二进制缺失——`E:/Godot` 仅存
> 4.6.2、`C:/Users/zerat/godot_tmp/` 不存在、PATH 无 `godot`。**不能用 4.6.2 先跑**：
> 门禁与 4.7 锁死（4.6.2 下 map_data.gd 的 INT32_MAX/INT32_MIN 解析失败，盘点
> 记载），且 202 用例 / 0 失败基线是在 **4.7.2** 上建立的（04 §M1a+ BLEND-03 登记
> 行的门禁即跑于 4.7.2；仓库代码自身也按 4.7.2 API 记载——hex_picking.gd:29
> 「4.7.2 脚本 API 无 space_step」）。**恢复行动**：获取 Godot 4.7.x stable win64
> 二进制置于固定路径并使 `godot` 可从命令行调用（具体路径/方式由环境维护者定，
> 本方案不指定）；**达标判据** = 全量 `tools/run_tests.gd` 复现 202 用例 / 0 失败
> （exit 0）。本文全部仓库行号引用为静态实读核对，未执行任何测试或探针。
>
> **主创拍板登记（2026-10-11，对本文三项）**：① **地理骨架不做抬升/下挖**——
> Catlike frontier 候选**排除**，地理骨架唯一路线 = 现有 FastNoiseLite 双通道
> （§1/WORLD-01 相应行已改）；② **格边河流玩法语义确认**：河流沿格子边 → 阻碍的
> 是**格与格之间**的移动（挂边不挂格），由此产生**跨河防守 buff** 的设计空间，
> 桥 = 跨河通行结构（CrossingData.traversable 认领）——ADR-14 的玩法动机落字，
> 具体数值/机制沿 M3 决策门（RULE-01 过河/桥规则）；③ **崖壁暂保留真垂直**
> （LAND-02 现设计维持），软化/风格化取向后续再研究（style 域）。
> §2.6 四项**仍未拍板**，不得默认通过。

---

## §0 结论先行

**执行总序**：数据合同格边重议（§2，随 T2 开工首物落地 WorldData 四件）→ T2 阶地
高程 → T3 水系 → T4 道路桥 → T5 世界生成。段间只有「前置链」没有「合并交付」——
每段独立可交付：交付即 04 §M1a+ 登记 + 门禁全绿 + 探针证据留档，任何一段可止步于
自身验收而不欠下游债（无河世界 / 无路世界 / 无 POI 世界均为合法态，对应 WorldData
空集合 = `empty()`）。

| 段 | 开工前置 | 独立交付物（止步即完整） |
|---|---|---|
| **§2 合同重议** | 主创确认 §2.6 四项（格边 reach 等价表达 / crossing 认领语义 / WORLD-02 归属 / 直行-转弯重释） | 草案 §5/§8 重写稿 + 头部效力块改「已按 ADR-14 转正」+ 04 登记 |
| **T2 阶地** | Godot 4.7.x 恢复 + §2.5 WorldData 四件落地（LAND-01 内含）——**不依赖 §2.6 任何项，拍板悬置期间可先行动工**（见 §2.6 头部） | 阶地几何 + 连接矩阵穷举 + 新面型拾取/高亮合同；无河无路世界完整可玩可渲染 |
| **T3 水系** | T2 NeighborLinkData 落地（边表）+ 排水映射手工版（建议案 A，随 §2.6③ 拍板）——**若主创否决案 A**：排水映射作为 ADR-14 前置仍不可缺，fallback = T3 卡内自带最小手工排水表（WATER-01 校验器输入，不依赖 WORLD-02 自动骨架）或 T3 整段顺延至拍板后——两种出路均不阻塞 M1b（§9） | 格边河数据 + 校验器 + 河床/水面/岸线三层 mesh；无路世界完整 |
| **T4 道路桥** | T3 reach/water_body 解锁 + §8 重议成果（CrossingData） | 道路/桥数据 + 几何 + 聚落骨架生成侧；无 POI 世界完整 |
| **T5 世界生成** | T3/T4 全部 + 模板参数重定（openDecisions） | 阶段化管线 + 可玩校验 + seed 银行工具 |

**两条跨段铁律**（细节见 §8）：
1. **数据合同先行**：草案 §12.3（:345-349）原文——T2 开工时 `WorldData` 容器 +
   `NeighborLinkData` + 校验器 + 单测四件首落；`Vector2i` 序列化显式 `[x,y]` 转换层
   必须进测试锚（§2.2 实测坑：直写 `JSON.stringify` 落成 `"(3, 17)"` 字符串不可
   还原，草案 :83-90）。旧图零迁移：缺 `.world.json` → `empty()` 合法。
2. **每段交付保持「删 scripts/ui/** 后 tests 全绿」**（ADR-2 纯逻辑纪律，沿
   hex_terrain_builder.gd:5-7 头注先例）；探针只加证据不改渲染代码。

**拍板遵守声明**（六项各配一句内容，均出自 04 §M1a+ :129-139）：①排期主干选
**C——继续地形线**（本批 T2-T5 即该主干延伸）；②河流拓扑=**格边河流**（已立 02
ADR-14，本方案 §2/§4 全部以其名义展开）；③**阶地棋盘感默认**（T2 Must=阶地）；
④**不造气候**（T5 无气候/生态阶段、biome 字段剔除）；⑤**性能指标悬置**（只留数字
档案不设阈值）；⑥**不考虑排期**。⑥+① 的合并推论：本批十三卡只可顺延、**不得阻塞
M1b-T1 开工决策**。

---

## §1 多源对照总表

五源定位一句话：**Catlike 作几何/编辑器基线（阶地/岸线/道路构型），Red Blob 作生成
主参照（排水/分层管线），Azgaar 贡献阶段化校验/seed 纪律/势力范围机制（前瞻），WFC
与 dual grid 只落装饰层**。两者时机口径统一为：**dual grid 本身是纯函数掩码技术、
无时点约束，何时进主线取决于格线层归属拍板（openDecisions）**——若格线层归入 T2
则随 T2 落贴图美化层（§8.2），否则与 WFC 同挂世界模板定型后的装饰层（WORLD-01 后）。

| 关切 | Catlike（catlikecoding.com/unity/tutorials/hex-map/） | Red Blob | Azgaar | WFC / dual grid | 本作口径（拍板/ADR 依据） | 取/舍理由 |
|---|---|---|---|---|---|---|
| 阶地几何 | Part 3（/part-3/）：整数高程 + GetEdgeType 三分类 + 5 步 TerraceLerp + corner 十余种情形分派 | — | — | — | **取**：TerraceLerp / 边分类 / corner 分派直接映射 GDScript（拍板③，LAND-01/02） | 与 MapData int 高程（map_data.gd:12-13）同构；corner 分派补本作角落仅两分支的现状缺口 |
| 河流拓扑 | Part 6（/part-6/）：**穿格河**（否决沿边河；入/出方向、禁上坡、不分叉合并） | x/1723（redblobgames.com/x/1723-procedural-river-growing/）：河口反向生长河网；polygon-map-generation：下坡箭头+无局部极小 | river-generator：flux 沿落差汇流（降水驱动） | — | **ADR-14 格边**（02:208-227）：河=共享边有序序列；数据模型弃 Catlike 穿格，只移植三条纪律——禁上坡（→水面单调校验）、水面独立 mesh、河床下切标高 | 结构性冲突（调研自标重要勘误）：Catlike 河床落共享边带中段、水面跨格中心连，不可移植到格边；Red Blob x/1724 反推高程已被原作者证伪、禁作主生成器（仅诊断复核轴；x/1724 = redblobgames.com/x/1724-elevation-from-rivers/，见 Red Blob 调研条，非本文新增信源） |
| 道路几何 | Part 7（/part-7/）：每格 6 布尔 roads[] 镜像写邻格 + GetRoadInterpolators 14 构型通式 + decal 贴地 | — | routes-generator：连通度加成 | — | **取通式思想弃数据模型**：RoadData 有序格序列 + NeighborLinkData.road_id 索引（草案 §7 基本不动直接转正）；Godot 无 decal 队列 → 独立 lift 档 mesh 贴地 | 本作道路是格中心网络非沿边带；构型通式（按相邻方向有无路调宽度）移植为「每格按道路方向子集选路面扇区构型」 |
| 桥 | Part 11（/part-11/）：渲染期派生、无独立数据字段、预制体承载 | — | — | — | **一等实体 CrossingData**（桥=跨河可达的唯一查询入口）；取三条放置规则（两岸都有路/急弯端点不设/方向所有权去重） | 本作桥是拓扑事实非装饰；格边口径下大幅简化（river_edge 两侧格即两岸、跨接即该 link 本身） |
| 水位/岸线 | Part 8（/part-8/）：整数水位不自动传播 + 逐顶点干湿岸线判定 + 水下 0.6/岸上 0.8 角半径 | — | — | — | **声明+校验**（WaterBodyData.water_level + 校验器对账），把 Catlike 运行时约定升为数据合同 | 本作纪律更强：同湖水位一致、湖出口不高于溢流口均可 headless 锚定 |
| 顶点扰动 | Part 4（/part-4/）：可平铺噪声纹理采样 ±4、边界顶点不扰动防裂缝 | — | — | — | **首版不扰动**（builder :10 头注「首版平整不扰动」）；grimdark 低模是否扰动属后续 style 决策 | 确定性纪律（同 seed 同图）优先；若后开，噪声纹理换确定性 position→offset 纯函数（FastNoiseLite），两条纪律（同位置恒同值/边界不扰动）通用 |
| 陆地生成 | Part 23（/part-23/）：search-frontier 抬升/下挖 + 陆量预算 + Random.state 保存恢复 | mapgen4（redblobgames.com/maps/mapgen4/）：分层生成+人工约束+改后重算下游 | 线性管线「执行顺序即依赖图」——**可定位性是正面纪律、无阶段诊断产物是反面教训**（两面对 WORLD-04 各有取材，见该卡） | hex-map-wfc（felixturner.github.io/hex-map-wfc/article/）：900 状态/格、19 网格分治、4100 格 ~20s | **模板化阶段管线**：~~Catlike frontier 仅作地理骨架候选算法之一（与现双噪声路线并列，WORLD-01）~~ **2026-10-11 拍板：不做抬升/下挖，frontier 排除——地理骨架唯一路线 = 现双噪声**；WFC 只作装饰层二级生成器 | WFC 全局约束弱（无「河必须从 A 到 B」表达）+ 成本高（~20s 一次生成，2026-10-11 复核原文实数；调研档另记 8-60s 与原文不符，弃用），作主生成器拖慢同 seed 迭代；Azgaar 线性序失败不产出阶段摘要、错误不指向对象——本作每阶段独立摘要即补此缺口 |
| chunk 纪律 | 原系列全量重建（重制版 chunk 化，仅目录级） | — | — | — | **chunk 划分无关性铁律**（全局 index_of 归属 + inner_vertex/bridge_xz 全局唯一参数，hex_terrain_builder.gd:15-21 头注 + hex_math.gd:184-196 bridge 头注） | 本作纪律更强且已代码化；Catlike Burst 并行对 60×40 规模非必需（拍板⑤） |
| 崖壁 | 崖=两顶点直连陡面（无墙面结构） | — | — | — | **真垂直崖壁自研**（LAND-02）：墙顶线/墙底线=现成参数点，Catlike 只供阶地-崖角 boundary triangle 坍缩思路 | 本作要求超出（LAND-02 验收：真竖直墙 + 墙顶/墙底连接 + 点击归属）；现状 80° 陡面为过渡态（builder :45-47 头注自认） |
| 材质混合 | Part 14：顶点色 TerraceLerp 混合 + 纹理权重三 UV | — | — | dual grid（boristhebrave.com/2023/05/31/quarter-tile-autotiling/）：错位半格 4-bit 掩码 16→6 变体 | **顶点 COLOR 纯权重 + palette 查表**（BLEND-01/02 已落地）；dual grid 只落 12 号文档 T0 贴图变体索引（§8.2） | Catlike 权重含地形索引走三 UV 是为防插值出不存在的地形；本作纯权重 + 查表已规避，无需三 UV |
| 势力范围 | — | — | states-generator：多源 Dijkstra 成本场 + normalize 多数滤波 + 顶点链边界；burgs：适居度+quadtree 间距 | — | **§7 前瞻案**：机制全挂 WORLD-03 概念预留 + M3 门，T2-T5 十三卡验收不含 | 3 势力纯 PvE + 占点经济（军队挂占点非人口）+ 无省层；气候依赖逐项绕开（拍板④执行口径） |
| 校验/seed | 无 | 反面教材：mapgen4 2023-04 改动后旧 seed 不再复现 | 阶段化校验纪律 + lock/ErasePipeline 局部重生成 | 自带种子化可复现 | **WORLD-04**：GENERATOR_VERSION 锁定（map_generator.gd:31 先例）+ 具名随机通道 + 世界管线独立计数 + 失败图入库（map_io.gd:26 FAILED_FIXTURE_DIR 先例） | Azgaar 复现性破坏是 seed 纪律的反面教训；指标数值（100/100 等）为候选目标非承诺（拍板⑤） |

---

## §2 数据合同格边重议案（T2 开工首物 + T3 开工门）

ADR-14（02:208-227）已定拓扑：河 = 六边形**共享边的有序序列**，两侧格互为河岸，
同图不混用穿格语义。本节对草案 §5/§8 给出字段级重写要点；重议通过后草案头部效力块
改「已按 ADR-14 转正」+ 04 §M1a+ 登记证据（草案 §12 转正清单 :340-349 原路径不变）。

### 2.1 重议总则

- 只重议 §5（RiverReachData）与 §8（CrossingData）两节 + §2.4 连带对账面；其余实体
  （WorldData 容器 / NeighborLinkData / WaterBodyData / RoadData / POIData / WorldMeta）
  按草案「其余实体基本不动」转正（草案 §12 :340）。
- 废弃口径划线示例：~~reach 主键 cell_id、一格最多一段河~~→reach 主键 reach_id、
  成员 = 边序列；~~bridge_cell（桥所在格必须是某河段格）~~→桥 = 跨格边河流的两侧
  陆路连接，无「桥所在格」。
- 全部锚点沿边序列由 HexMath 全局参数派生、**不落盘坐标**（草案 §2.3 纪律维持）。

### 2.2 §5 RiverReachData 字段级重写

| 草案字段（穿格，作废） | 格边重写（本方案建议） | 备注 |
|---|---|---|
| `cell_id`（主键；一格最多一段河） | `reach_id: int`（主键）；`edges: Array[Vector2i]`（有序边序列，每项 = link_id=(min,max) 沿 M1a-T4 归属先例） | 河段=边序列而非格序列；两端格恒陆地地形不变 |
| `incoming`（入边列表，初版 ≤1）/`outgoing`（出边，恒 ≤1） | 删除入/出边字段——**『1入1出』的边序列等价表达** = 边图上每条内部边恰有一个前驱边与一个后继边（链结构），端点边为源/汇；汇流预留 = 允许多前驱的结构可表达（第二版再开，初版校验器拒绝） | 等价表达与汇流预留字段**须主创确认**（§2.6①）；草案 :176-177 预留口径维持 |
| `flow_level` | 保留（int ≥1，等级→河宽属表现参数不进数据） | Strahler 数映射候选（WORLD-02） |
| `water_level` | 保留；**『沿河单调不升』校验对象由格序列改为边序列**（逐边 water_level 非增） | Catlike 禁上坡纪律的数据化 |
| `bed_level` | 保留；恒 `< water_level` | 河床容纳校验下界 |
| `water_body_id`（终点对账） | 保留；对账改边口径：终点边 ∈ 该水体 `inlet_links` | 与 §6 互为镜像（双向对账） |
| （锚点派生：入边中点/出边中点/格心） | 沿边序列派生：每条边的锚 = 两格心连线与共享边的交点（唯一路径，HexMath 现算） | 不落盘 |
| （禁令『渲染河道不得把河流格整格设为水体禁行』） | 格边语义重述：**两侧格保持陆地地形与自身 passable 语义**——河的通行影响走规则层（M3 门；**2026-10-11 拍板：玩法语义 = 河阻碍的是格间移动，跨河防守 buff 为既定设计方向，桥 = 跨河通行结构**——具体数值沿 M3/RULE-01），渲染河床只下切连接带中段 | ADR-14「只定拓扑不定规则」；**与湖/海的双口径对照（有意设计、非疏漏）**：湖/海 = **格语义**水体（水体占格：terrain=TERRAIN_WATER + passable=false 结算面，map_generator.gd:105-113 现状，WATER-03 转正不改水格 passable——水位进 WaterBodyData、通行语义仍在格上）；河 = **边语义**水体（水在边上、格仍是陆地）。后果对齐：寻路（M1b-T4 通行性硬约束读 MapData.passable）天然把湖格当墙、对河不置一词——跨河走 CrossingData.traversable（T4）或 M3 规则；拾取上湖面命中归水格顶面（水面不进拾取层）、河面命中归河床两侧格（WATER-02 归属合同）——两套语义各自闭合，互不改写 |

### 2.3 §8 CrossingData 字段级重写

| 草案字段（穿格，作废） | 格边重写（本方案建议） | 备注 |
|---|---|---|
| `bridge_cell`（=某河段格） | 删除——桥无「所在格」 | 桥=跨格边河流的两侧陆路连接（ADR-14 原话） |
| `bank_a`/`bank_b`（与 bridge_cell 互为邻居、均非河段格） | `river_edge: Vector2i`（被跨的有河 link，初版单边；宽河多边列表第二版）+ `bank_a`/`bank_b` = **该 link 两端格**（即两岸格） | 天然互异、均陆地地形——比穿格版『均非河段格』干净，无需额外校验绕路 |
| `river_cells`（覆盖水域=河段格列表） | 删除（覆盖水域 = river_edge 本身，格边口径无额外覆盖面） | — |
| `traversable_edges`（两条 link：bank_a↔bridge_cell、bridge_cell↔bank_b） | 重定义：**crossing = {link, 河在下、路在上} 的认领关系**——格边口径下桥不占额外 link，跨接即该 link 本身；`traversable` 查询走 CrossingData 认领表 | 跨河可达的唯一查询入口（ROAD-02 验收原文） |
| 『横切的机器定义』（两条 link 与河段入/出边不重合=横切） | 重写：**道路 cells 序列中出现相邻两格构成的 link ∈ 有河边集合且被 crossing 认领 → 合法横切；未被认领的有河 link 出现在任何道路序列 → 非法（禁渡）** | 『横切而非顺河』= 车流跨过河 link 而非沿河岸格序列蹭边 |
| Kind.BRIDGE 唯一合法值、渡口 Kind.FERRY 预留不开、桥不是移动费数据源 | 口径不变 | 草案禁止项原文 |

**核心反转（须主创确认，§2.6②）**：草案 §4 禁令「同一 link 上有河和路不得推导出
需要桥」在格边口径下语义重述为——**「同一 link 有河和路 ⇒ 必须被 CrossingData 认领
（=桥），否则非法」**：格边下河与路共享同一物理 link，「共存」从禁止态反转为须认领
的合法态，方向与穿格版相反，属本重议案的核心改写点。

### 2.4 连带对账面（随 §5/§8 同批改口径）

| 草案位置 | 穿格口径（改） | 格边口径（改后） |
|---|---|---|
| §4 NeighborLinkData.river_from/river_to（=流出/流入格，『河水从 A 穿过共享边流入 B』） | 有河时 = 该边上下游拓扑（建议由排水映射 edge→next_edge 提供） | link 表只存 `river_reach_id` 引用，**初版不存任何流向字段（与 reach.edges 零冗余）**；**不再表达穿格**。两层权威关系：终态事实 = `reach.edges` 的**序列顺序**（序本身即上游→下游）；生成期流向 = 排水映射 edge→next_edge（生成中间产物，不落盘）；link 层的 from/to 边字段仅在第二版汇流开启时再议（一 link 多前驱、单值序列表达不足，届时才需要在 link 层冗余存边级流向） |
| §6 WaterBodyData.inlet_links/outlet_links | 终点对账锚经 water_body_id + 汇入边 river_to 端格 | 改纯边口径：reach 终点边 ∈ inlet_links（双向对账）；字段名不变、语义改边 |
| §7『禁止道路纵向覆盖河槽』 | 『道路格序列不得含有河 link 跨接，除非被 crossing 认领』 | 与 §2.3 横切定义同一句话。**完备性论证**：穿格版禁纵覆是因为路带会盖住河段格的河床（同格冲突）；格边版河床在边带中段、路带在格心平台，**沿河岸走的道路几何上不与河槽相交**（不触碰任何河 link）——「顺河路」因此合法、无需禁止，原禁令在格边口径下不残留独立非法类别。提案验收「横切而非纵向覆盖」的机器判定落点 = **正向横切判定**：道路序列含被 crossing 认领的河 link 跨接 = 横切；不含河 link = 与河无涉（含顺河路，合法）；含而未认领 = 禁渡拒绝（§2.3）——后半句「非纵向覆盖」由几何分离自动成立、无独立断言 |
| §4『同一 link 有河和路』禁令 | 见 §2.3 反转 | — |
| §9/§10/§11 | 字段不动；WorldMeta 的 attempt_count/repair_count/first_pass_valid 落码进 WORLD-04；温度/生态字段移除或降可选（拍板④） | — |

### 2.5 T2 先行落地四件（非重议，属 LAND-01 首物）

草案 §12.3（:345-349）原文落地：`WorldData` 容器（第四伴生文件 `.world.json`）+
`NeighborLinkData`（link_id=(min,max)，两端互为界内邻居校验）+ 校验器 + 单测，落
`addons/hexhammer` 或 `scripts/core/data` 纯逻辑层。**序列化往返与 Vector2i 显式
[x,y] 转换层必须进测试锚**（§2.2 实测坑）。SCHEMA_VERSION=1 不动（WorldData 走
独立伴生文件）；classify_edge 保持几何派生现算不入表（§4 禁止项维持）；高差分档
阈值属构建参数/几何 profile 不进 MapData。

### 2.6 须主创拍板项（重议通过门）

**拍板流程与清单权威**（与 04 §M1a+ 既有拍板流程同构）：由主创对下列事项在 04
落字（本方案只列项不定案）；**执行以本节清单为准**（§0 段表为其摘要）。**拍板
悬置期间的可动工范围**：§2.5 四件与 T2 阶地三卡（LAND-01/02/03）不依赖本节任何
项——WorldData 容器与 NeighborLinkData 基础字段（link_id/(min,max)/road_id/
reach_id 引用）与 §5/§8 重议无关，阶地几何只动 classify_edge 分档与边带细分，
可先行动工；WATER-01 落卡前必须确认 ①④、ROAD-02 落卡前必须确认 ②、WORLD-02
卡范围由 ③ 定——这三张卡在拍板前只可做 spike、不可定数据结构。

1. **『1入1出』边序列等价表达 + 汇流预留字段**（§2.2）——结构选择，定错则校验器返工。
2. **CrossingData 认领语义反转**（§2.3）——格边口径的核心改写，与穿格版方向相反。
3. **WORLD-02 存续与归属**（openDecisions 第一条）：本方案建议**案 A** = 排水映射
   最小版（手工表 + 校验器）随 T3 前置落地，自动排水骨架（连续高程→downstream→
   洼地处理）留 WORLD-02 且范围只剩排水——与 ADR-14 前置时序一致。
4. **『直行/转弯』的格边重释**（WATER-01 验收措辞的判别基础）：格边路径相邻两边
   共享一个六边形顶点（顶点处三边互成 120°），单步转向恒 ±60°——建议定义
   「左转/右转」= 单步转向符号、「直行」= 连续两步转向符号相反（单步无净直行）。
   该重释是本方案提出的建议（提案原措辞为穿格口径），随 ① 同批确认后方可落
   fixture 判据。

---

## §3 T2 阶地高程（拍板③：阶地棋盘感默认，Must=阶地）

技法主源：**Catlike Part 3**（https://catlikecoding.com/unity/tutorials/hex-map/part-3/）。
通用纪律：全部新顶点从 `HexMath.inner_vertex`/`bridge_xz` 全局参数现算（chunk 无关性
铁律，hex_math.gd:184-196）；每段交付前 LAND-01 矩阵图全量过一遍焊接流形检查。

### LAND-01 连接矩阵与 WorldData 落地

| 项 | 内容 |
|---|---|
| **目标** | 穷举 edge/corner 高程连接矩阵，作为 T2 地貌升级完备清单（提案 :273 验收原文：「0/1/2/3 的局部高程组合及方向旋转覆盖；平/坡/崖全部闭合并可见」） |
| **现状** | classify_edge 仅三值 flat/slope/cliff（hex_terrain_builder.gd:89-92 常量、:131-138 实现），Δ2 与 Δ5 同为 cliff 同几何；slope/cliff 共用单四边形两级三角（:362-378）；角落仅等高/非等高两分支（:410-417）；无边/角独立数据结构（归属隐式 index_of，:346-348/:395）；高程组合穷举矩阵不存在 |
| **技法移植设计** | ① classify_edge 扩为 flat(Δ0) / slope(Δ1) / terrace(Δ2..Δ(cliff_threshold−1)) / cliff(**Δ≥cliff_threshold** 走直壁，默认 cliff_threshold=3 → 崖=Δ≥3、阶地仅 Δ2)——阈值进构建参数与几何 profile（§8.1），不进 MapData；② 穷举矩阵：边 = Δ0..Δ3 × 方向 0..5 旋转覆盖，**穷举上界恒 ≥ cliff_threshold（默认档下 Δ3 即崖样本，验收「平/坡/崖全部闭合并可见」由 Δ0/Δ1/Δ3 覆盖、Δ2 阶地为 LAND-02 前置；profile 调档如 cliff_threshold=4 时矩阵同步扩至 Δ4，上界 = max(3, cliff_threshold)）**；角 = 三格高程 (0/1/2/3)³ 按 (min,mid,max) 差值等价类归并（max−min=3 即崖角样本）；③ §2.5 四件落地（首物）；④ 矩阵产出物 = tools/make_fixed_maps.gd 特征常量区（:35-53）先例的固定小图，穷举全部局部组合，兼作 LAND-02/03 公共 fixture（含 cliff_wall 面）与 render_probe 新 CHECK 图 |
| **数据合同影响** | 草案 §3/§4 转正落地；SCHEMA_VERSION=1 不动；无须回 02 立 ADR（几何风格已由拍板③落 04） |
| **测试锚** | 连接矩阵穷举：每组合焊接流形闭合（沿 tests/test_hex_terrain_blend_corner.gd 跨 chunk 无裂缝先例）+ 每物理边/角恰一生成者；每档面数 = 解析式预言（terrace 步数 k → 面数公式独立拼装 oracle，沿 tests/test_hex_terrain_elevation.gd:17-19 期望几何独立拼装原则）；WorldData/NeighborLinkData 序列化往返 + Vector2i [x,y] 转换 + 旧图空 WorldData 合法；主键唯一/引用可解析/零回写 MapData（草案 §11 逐项） |
| **风险与回退** | 面数膨胀（阶地 ≈×2.5）牵动碰撞汤/face 表——留 face_counts 数字档案不设阈值（拍板⑤）；角等价类归并出错→穷举测试兜底；回退 = 分档表退回三分类常量即恢复现行为 |
| **卡内拍板项** | 无（分档阈值属构建参数，spike 后定默认值即可） |

### LAND-02 阶地与 cliff 交汇

| 项 | 内容 |
|---|---|
| **目标** | 同高程端点不移位；阶地-崖角不漏缝；关闭阶地可退回旧坡（提案 :274 验收原文；拍板③定 T2 Must=阶地） |
| **现状** | slope = 单斜面两级三角（builder :369-378）；cliff 同几何仅坡度陡（:45-47 头注自认 80° 陡面非墙面结构）；Catlike corner 情形分派完全缺失；blend 合同钉死「mesh 侧不设中点顶点」（hex_terrain_blend.gd:13-16——当时是表现层切片约束）；TerrainStyle 只有材质级双 mode（terrain_style.gd:47-52）盖不住几何差异 |
| **技法移植设计** | ① **TerraceLerp 移植**（Catlike Part 3 同构）：`static func terrace_lerp(a: Vector3, b: Vector3, step: int, steps: int) -> Vector3`——水平 `a.lerp(b, float(step) / float(steps))`、竖直 `lerpf(a.y, b.y, float((step + 1) / 2) * v_step)` 其中 `v_step := 1.0 / ceilf(steps / 2.0)`（竖直步进 = 1/(平台数+1)，即 Catlike 原式 verticalTerraceStepSize = 1/(terracesPerSlope+1)——5 步时 1/3；GDScript int 除法 (step+1)/2 向零取整 = 竖直仅奇数步动。5 步序列 0,1/3,1/3,2/3,2/3,1 = 2 平台+3 短坡；3 步候选 0,1/2,1/2,1 = 1 平台+2 短坡——两档均为对称阶地）；本作连接带宽 = (1−solid)·√3·size ≈ 0.35·size（solid 0.8，builder :84-85），Catlike 5 步在此宽度可读性须 spike 定（候选 3 步；步数 = profile 参数）。**步数与 Δ 档的绑定规则（设计建议，spike 验证）**：`terrace_steps` 定义为**每爬升一级**的步数——Δn 边带 = n 组阶地串联（组内用同一 terrace_lerp 公式爬 1 级，组间共享平台且平台恰落在高程整数层上，与 corner 分派的边界点坍缩对齐）——默认档（cliff_threshold=3）仅 Δ2 = 2 组；profile 调档 threshold=4 时 Δ3 = 3 组，LAND-01 矩阵扩 Δ4 用例同步覆盖多组情形；面数预言公式随之 = n × 每组环数 × 2 三角；② **边带细分发射**：v1..v3（= v1+bridge）之间按步插值成中间环（每环两点：`v1 + bridge*t` 水平 + floor-lerp 竖直），相邻环 = 四边形两级三角，沿 :363-378 发射模式扩；③ **真垂直崖壁**：cliff 边带 v1/v2 取高地侧 y、v3/v4 取低地侧 y 直壁四边形 + 墙顶线（=高地侧内边）/墙底线（=低地侧内边）与阶地的 **boundary triangle 坍缩**（Catlike TriangulateBoundaryTriangle 思路：坡侧阶地朝崖壁上的插值边界点坍缩成扇形）——均为现成参数点无新锚点（**2026-10-11 拍板：崖壁暂保留真垂直，软化/风格化取向后续再研究——style 域**）；④ **corner 情形分派**：先按三格最低者旋转定向再分派（三格等高=现平三角 / 两低一高=阶地扇 / 含 cliff=坍缩扇），十余种情形沿 Catlike SSF/SCS/CCS 结构枚举；⑤ **blend 承接**：阶地细分顶点 COLOR 由同一 `edge_weights(t)`/`corner_weights(u,v)`（hex_terrain_blend.gd:39/:59）显式求值——权重函数不变、求值点变多，有限非负和 1 在每新顶点保持；**BLEND-01「不设中点顶点」条款限定回材质级表现切片**，几何级细分合法但须同步改 hex_terrain_blend.gd 头注与 tests/test_hex_terrain_blend.gd 面数锚（「翻案须同步改测试」纪律）；⑥ **退回开关**：terrace_enabled/terrace_steps/cliff_vertical 进几何 profile（§8.1）；关闭 = 与现基线 mesh 逐位一致；⑦ **UV 选型**：平台走 _uv_planar（:476-477）、短坡/崖壁走 _uv_side_edge（:482-483，T8 约定公式不改只多两档逐面选型） |
| **数据合同影响** | 动 04（M1a-T4「首版单斜面」口径翻案 + M1a-T8 UV 约定补阶地/崖壁面型条目）不动 02；blend 合同扩展回改头注与面数锚；04 落「几何级 profile ≠ 材质级 style」不变量分档字（§8.1）；数据合同零改动 |
| **测试锚** | 同高程端点不移位 = 平边几何与现基线逐位一致（回退档全 mesh 逐位对照 = 新基线锚）；阶地-崖角不漏缝 = LAND-01 矩阵图焊接流形 + 无非有限顶点 + 重复面为零；blend 阶地新顶点权重逐点 is_valid_weights/3 通过 + 端点 (1,0)/(0,1) 不变；UV 新面型锚沿 tests/test_hex_terrain_materials.gd 五个 test_uv_* 先例扩；换几何 profile 不改世界事实 = MapData.summary/digest/连通性跨档一致（mesh 允许变——不变量分档显式登记） |
| **风险与回退** | 角情形分派完备性——LAND-01 矩阵兜底（漏一档即测试红）；面数×2.5 构建耗时——留档不设阈值；5 步不可读→spike 降 3 步；回退 = terrace_enabled=false 逐位回现基线（本卡验收明文「关闭阶地可退回旧坡」） |
| **卡内拍板项** | 阶地步数默认值（3 vs 5，spike 后定）；grimdark 垂直夸张的 cliff 纵横比取向（docs/12:23-33 定调参考）——均属 profile 默认值，可先 spike 后拍 |

### LAND-03 geometry→picking→highlight 合同

| 项 | 内容 |
|---|---|
| **目标** | 每类新面拥有稳定候选格，真实 raycast 与归属一致；高亮贴合新表面，不埋入阶地（提案 :275 验收原文） |
| **现状** | faces kind 仅 top/edge/corner 三值（builder :333/:379-380/:418）；resolve_face 三分支路由（hex_picking.gd:114-122）；cliff 归高地侧（:126-134）；高亮 cell_top_y = elevation×step+lift 假定完整平顶面（hex_highlight.gd:115）——阶地下格心平台不动则锚点公式幸存，但「高亮贴合新表面」未经验证 |
| **技法移植设计** | ① 面记录最小扩：阶地面保持 kind="edge" + edge_type 细化（terrace/cliff_wall）——resolve_face **不加分支**（edge 口径沿用最近格心+ID 决胜，hex_picking.gd:7-18 微决策 3 口径直接泛化），只有 cliff_wall 沿现规则归高地侧，改动面最小；每类新面天然有稳定候选格（边带两格/角落三格）；② CellSurfaceSampler 最小版：纯逻辑函数 `cell_surface_anchor(map, cell) = 格心 + elevation×step`——因拍板不做顶面扰动（Catlike Part 4 竖直抖动不采），格面恒平、锚点公式不变；本卡实际交付 = 该假设的显式合同 + 高亮 lift 档位对阶地 riser 的安全差断言；③ 桥面/河床新 kind（T3/T4 进）预留：_emit_face→faces 序 = 三角序合同自动覆盖新面型（builder :24-25 头注），碰撞汤随之增长；④ tools/picking_scene_check.gd 扩阶地面真实 raycast 用例；⑤ 高亮 lift 档位表（hex_highlight.gd:38-39/:111-112）不动，断言扇面 y > max(该格全部归属面 y) |
| **数据合同影响** | 纯几何/拾取层无数据合同变化；归属规则在阶地面上的适用性按 hex_picking.gd:18 先例在 04 登记解释性落字；新面型继续走 chunk_pick_data（:88-95）同构合同 |
| **测试锚** | 每类新面（platform/riser/cliff_wall）真实 raycast 与 resolve_face 归属一致（picking_scene_check 扩用例 + tests/test_hex_picking.gd face 表对齐锚扩新面型）；face_index 越界→null 合同在新面数下保持；高亮贴合断言（扇 y 高于该格所有归属面最高点）；碰撞汤/face 表逐索引对应在新面数下保持 |
| **风险与回退** | 面数增长拖慢碰撞汤构建（ConcavePolygonShape3D 线性）——留档观察；riser 侧壁拾取归属争议（玩家点台阶侧壁想选谁）——沿用最近格心口径 + 04 落字，争议后可翻案；回退 = 关阶地即回三面型基线 |
| **卡内拍板项** | 无（riser 归属争议登记为解释性落字，翻案走 04 流程） |

---

## §4 T3 水系（ADR-14 格边河流）

技法主源：**Catlike Part 6/8**（https://catlikecoding.com/unity/tutorials/hex-map/part-6/、
part-8/，拓扑与纪律借鉴、穿格几何不移植——ADR-14 后果条原文）+ **Red Blob x/1723**
（河口反向生长，生成侧第二验证轴，WORLD-02 用）。段前置：§2 重议通过 + 边表落地
（T2 LAND-01）+ 排水映射手工版（§2.6③ 案 A）。

### WATER-01 单河数据与验证器

| 项 | 内容 |
|---|---|
| **目标** | 1 入 1 出、直行/左右转/源/终点可枚举；上坡、循环、非法邻格明确拒绝（提案 :276 验收原文；穿格措辞随 §2.2 格边重议落卡——「直行/转弯」的格边重释建议见 §2.6④：格边路径相邻两边**共享一个六边形顶点**、该顶点处三条格边互成 120°，故单步转向恒 ±60°——「左转/右转」= 单步转向符号；「直行」= 连续两步转向符号**相反**（左 60°+右 60° 净直行，六边形单步不存在净直行）） |
| **现状** | 格边河零实现：MapData 仅 terrain/elevation/passable 三语义（map_data.gd:57-59）；无 water_level/bed_level；草案 §5 整节作废待重议（:19-24 头注）；ADR-14 两前置（稳定边/角图 + 排水映射）均无代码；固定图正弦河 = 写死格序列 + FORD_ROWS 渡口改 passable（make_fixed_maps.gd:45-49），非数据化河段 |
| **技法移植设计** | ① RiverReachData 落地（§2.2 重写字段全表）；② 校验器四条：无环（边图 DFS → RIVER_CYCLE）、有终点（终点边邻接声明水体 → NO_RIVER_OUTLET）、water_level 沿边序列单调不升（Catlike 禁上坡的数据化）、bed_level < water_level；③ 手工图数据化：make_fixed_maps 的 RIVER_BASE_COL/AMPLITUDE/PERIOD 常量先例改产 WorldData.rivers 边序列 + 湖 LAKE_CENTER 圆盘产 WaterBodyData；渡口 passable hack 退场（渡口 = CrossingData 预留，T4 才开）；④ 排水映射手工表：edge→next_edge（无环有终点）作为 water_level 单调的生成侧来源 |
| **数据合同影响** | 草案 §5 整节按格边重写 + §4 river_from/to 语义重述（§2.4）；转正后头部效力块改「已按 ADR-14 转正」+ 04 登记；无新 ADR |
| **测试锚** | 单河 fixture 枚举：直行（≥3 边、相邻步转向符号交替）/左转（连续同号两步）/右转同构/源（单端点边）/终点（汇入水体边）边序列各一（沿 make_fixed_maps 手工图先例落 tests/fixtures，判据按 §2.6④ 重释）；拒绝锚：上坡（单调违例）/循环/非法邻格（link 两端非邻居）；序列化往返 + Vector2i [x,y] + 缺 .world.json → empty()（旧图零迁移）；终点对账：终点边 ∈ 声明水体 inlet_links（双向） |
| **风险与回退** | 边序列表达与汇流预留结构冲突（多前驱边）——初版校验器拒绝第二版开；『1入1出』等价表达未经确认即落码→重议返工（挂 §2.6①）；回退 = WorldData.rivers 空集合合法，渲染/查询走无河分支 |
| **卡内拍板项** | §2.6①（等价表达与汇流预留）+ §2.6④（直行/转弯重释）——落卡前必须确认 |

### WATER-02 河床/水面/河岸三层几何

| 项 | 内容 |
|---|---|
| **目标** | 跨 chunk 三者锚点一致；不露洞、不重叠重复水面；水层不截获地形拾取（提案 :277 验收原文）；须解决与高程连接带的共享边几何共存与归属（ADR-14 后果条） |
| **现状** | 无水面 mesh、无河床概念：水体 = terrain id 3 色块 + passable=false（map_generator.gd 步骤 3）；builder 边带独占共享边（:341-381）——河画在同一物理边无共存协议；无半透明水面材质；高亮 lift 档位表可取新档 |
| **技法移植设计** | ① **共存协议**：河床 = 该边连接带几何沿边切向（HexMath.edge_tangent_world，hex_math.gd:55-60）的**中段**（如 t∈[0.4,0.6]，与 Catlike 边带 5 段取中段同思路）顶点 y 压到 bed_level×step——两岸格 elevation 不动只下切连接带；与阶地的**参数轴**正交（阶地细分沿垂直边方向参数、河床中段沿边切向参数），但**参数正交 ≠ 顶点集合不交**——两族细分点共享同一条边带的顶点预算，坡-河-崖角处会相遇（见风险栏，矩阵图兜底），具体分割比例（河床中段 t 区间 vs 阶地平台区间）正是为避开重叠区而 spike 的对象；② **水面 = 独立第二 mesh**：WaterGeometryBuilder 新纯逻辑类（沿 HexTerrainBuilder 先例产 ArrayMesh + faces 元数据同构），沿边序列展开条带，y = water_level×step **减半档错位**（Catlike (level−0.5)×step 防共面 + 本作 LIFT_TIER_STEP 档位化先例 hex_highlight.gd:38-39）；沿流向 UV（Catlike Part 6 V 沿流向推进供滚动）作为水面材质参数源。**首版河宽口径**：河床/水面几何恒沿边连接带（宽 ≈ 0.35·size，**不随 flow_level 变**——几何统一是有意取舍，保 chunk 无关与面数稳定）；flow_level 的画面兑现 = 水面**材质参数层**（沿流向 UV 的流速/色深按 flow_level 分档）+ 岸带宽窄（渲染参数），不改 mesh 几何——宽河多边列表第二版开之前，大小河几何同宽、差异只在材质表现，与 §2.2「等级→河宽属表现参数不进数据」同口径；③ **拾取归属**：水面不建碰撞体/不进 LAYER_TERRAIN（hex_picking.gd:42-47 层纪律）→「水层不截获地形拾取」天然满足；射线穿水命中下切河床/地形面，河床面 kind="riverbed" 候选 = 边两侧两格（最近格心+ID 决胜沿用）——「点击水面后的逻辑结果由河床归属合同决定」（提案原文）的可执行表达；④ **材质**：TerrainStyle 扩 water_material 字段（半透明 StandardMaterial3D）——水不进 blend 色板（palette 约定 alpha=1，hex_terrain_blend.gd:28-30），岸线过渡走水材质自身参数；⑤ **跨 chunk**：全部锚点由 link_id + HexMath 全局参数现算（边锚 = 两格心连线与共享边交点，唯一路径派生不落盘） |
| **数据合同影响** | 新增渲染层不进世界事实数据；新 builder 属 addons 纯逻辑（ADR-2）；河床下切改地形边带几何 → faces 表扩 kind（riverbed）+ 归属规则解释性落字进 04；「水层不进 LAYER_TERRAIN」在 04 落字 |
| **测试锚** | 跨 chunk 三层锚点一致：同图三种 chunk 划分（单块/行切/每格一块——BLEND-02 划分矩阵先例）河床+水面+岸锚点逐位一致；不露洞 = 含河图焊接流形（每物理边恰一连接面、无非有限顶点）；无重复水面 = 每有河 link 恰一水面面片（全图计数断言）；水面不在碰撞汤 = chunk_pick_data 不含水层面片 + picking_scene_check 真实 raycast 穿水命中地形；blend 兼容 = 河图 blend 与 fallback 地形几何逐位一致（水面层独立不参与）；render_probe 加 CHECK-4 水面差分像素阈值（§8.3） |
| **风险与回退** | 河床×阶地×崖壁三方顶点冲突（坡-河-崖角）——LAND-01 矩阵图扩河用例兜底；透明水面排序/深度——探针只留证据不设阈值（拍板⑤）；回退 = 渲染开关关水面/河床 → 数据仍在、画面回色块水体（现状合法态） |
| **卡内拍板项** | 河床中段分割比例（spike 后定构建参数默认值） |

### WATER-03 湖/海/岸线/河口

| 项 | 内容 |
|---|---|
| **目标** | 同湖水位一致；源流最终到声明出口；河口接水体无悬空水面（提案 :278 验收原文） |
| **现状** | 无 WaterBodyData：湖 = 固定图圆盘 terrain=水（make_fixed_maps.gd:41-44）、海 = 生成图 n<sea_level；水位无显式字段（水格 elevation=0 隐式约定）；无岸线几何；草案 §6 基本可沿格边微调转正（:203-217） |
| **技法移植设计** | ① WaterBodyData 转正：kind SEA/LAKE、water_level（int 同纲）、member_cells、inlet_links/outlet_links 改边口径、terminal；② **岸线 = 水格与陆格共享边的集合**（格边口径下岸线天然是「干湿跳变边」——与 §7 边界画法同构，一次定义两处复用）；岸带渲染初版 = 水材质参数/顶点色，岸泡沫等属 12 号文档 T0 贴图管线承接不进本卡；③ 水面标高：整水体统一 water_level×step − 半档错位（WATER-02 同口径）；「同湖水位一致」= 校验器断言 +「湖出口不高于溢流口」（outlet 边水位 ≤ 本体）；④ **河口对账 + 几何接缝**：reach 终点边河水面 y == 邻接水体水面 y（校验）+ 终点边河面条带终点顶点 = 水体水面边缘顶点（同一全局参数派生）——「无悬空水面」的机器表达；⑤ 悬崖岸：Catlike「悬崖岸也有隐藏在地形下的裙边」思路——岸线边两侧高差大时水面向陆侧延伸至崖壁脚（顶点从邻格中心反推并钳到水面高） |
| **数据合同影响** | 草案 §6 转正（字段微调：inlet/outlet 边口径、member_cells 对账维持）；生成器水格 elevation 语义明确：水格 elevation = 床、WaterBodyData.water_level 独立标高（草案 §2.1「标高一律同离散纲」既定）；无新 ADR |
| **测试锚** | 同湖水位一致：校验器拒绝成员水位不符 fixture；源流到声明出口：沿边序列追到 inlet 边 ∈ 水体（+WATER-01 终点对账互为镜像）；河口无悬空水面：终点边河面 y == 水体水面 y 逐位断言 + 接缝顶点逐位一致；湖成员格 terrain 对账（成员应 TERRAIN_WATER，草案 §6 原文）；terminal 语义：海恒 true、过路湖 false 必须有 outlet 的校验用例 |
| **风险与回退** | 水位与高程纲冲突（量化后河水上坡）——量化后重验归 WORLD-02/校验器；水体大时 member_cells 序列化体积——行主序连续区间压缩（转正时定）；回退 = 水体渲染退回 terrain 色块（现状合法态），数据合同仍生效 |
| **卡内拍板项** | 无（member_cells 压缩格式转正时随草案定） |

---

## §5 T4 道路桥

技法主源：**Catlike Part 7/11**（https://catlikecoding.com/unity/tutorials/hex-map/part-7/、
part-11/，构型通式与桥放置规则移植；数据模型取本作草案 §7/§8 重议稿）+ **Azgaar
routes-generator** 连通加成思路（ROAD-03，多源融合第一处 Azgaar 取材）。

### ROAD-01 道路图与路口

| 项 | 内容 |
|---|---|
| **目标** | 相邻双向一致；端点/直路/转弯/三叉/更多路口符合同一 data contract；非法高差按配置拒绝（提案 :279 验收原文；初版 road_class 恒 0） |
| **现状** | 零实现：无 RoadData、无 link.road_id 索引、无 RoadGeometryBuilder；MapConnectivity 无高程/地形修正（map_connectivity.gd:4-6 头注「高程差在本期不阻碍移动」）；高亮 path_strip_mesh 条带几何可复用为路面先例 |
| **技法移植设计** | ① RoadData 转正：cells 有序格序列、is_loop、road_class 恒 0（值域单点 = 能力关闭显式表达）、connects_pois；NeighborLinkData.road_id 索引（T2 已有 link 表加字段对账：本 link 两端恰为序列相邻两格）；路口 = 多路共享 cell 重数（端点/直路/转弯/三叉同一合同覆盖，草案 §7 原设计）；② **几何**：RoadGeometryBuilder 新纯逻辑类——格中心网络：每格按其道路方向子集（6 邻内哪些有路）选路面扇区构型（方向子集等价类归并，Catlike GetRoadInterpolators 14 构型通式思路：按相邻方向有无路调宽度参数）；路面 = 格心向有路方向内边拉伸的贴地条带（复用高亮 path_strip_mesh 条带几何思路 + 独立 lift 档防与高亮共面——LIFT_TIER_STEP 档位表取新档）；Godot 无 Unity decal 队列，贴地 = 独立半档抬升 mesh（Catlike Part 7 decal 思路的换载体移植）；③ **阶地共存**：路面走格心平台（顶面），阶地在边带——不抢顶点；Δ≥2 修路被校验器按配置拒绝（阈值在生成配置不进数据，草案 §7 禁止项原文）；④ TerrainStyle 扩 road_material（独立 Resource 槽，与 water_material 同批） |
| **数据合同影响** | 草案 §7 转正 + §4 road_id 对账落地；无新 ADR；MapConnectivity 现口径不动（道路可达性验证的 TraversalPolicy 口径属 M3） |
| **测试锚** | 相邻双向一致：link.road_id 从道路序列投影两侧查询同值（双向对账）；端点/直路/转弯/三叉/四叉 fixture 同一 data contract（构型等价类穷举锚，6 邻方向子集 64 减等价类）；非法高差拒绝：阈值来自生成配置（数据层只校验「有配置才拒」）；序列化往返 + road_class≠0 拒绝（值域单点锚）；render_probe 加 CHECK-5 道路差分阈值（§8.3） |
| **风险与回退** | 构型组合数——等价类表 + 穷举 fixture 兜底；路面 lift 与高亮层抢档位——档位表扩档统一登记；回退 = roads 空集合合法，渲染走无路分支 |
| **卡内拍板项** | 无 |

### ROAD-02 横切河道的桥

| 项 | 内容 |
|---|---|
| **目标** | 桥端落在两岸合法锚点；道路确实横切河槽而非纵向覆盖；跨越边在查询中对应桥（提案 :280 验收原文；『横切的机器定义』随 §2.3 格边重议改写） |
| **现状** | 零实现；渡口雏形 = 固定图 FORD_ROWS 两处沙渡口恢复 passable（make_fixed_maps.gd:47-49 实读）——非 Crossing 实体；草案 §8 穿格口径（五字段 + 横切机器定义）整体作废待重议 |
| **技法移植设计** | ① CrossingData 落地（§2.3 重写字段全表）：river_edge = 被跨的有河 link（初版单边）、bank_a/bank_b = link 两端格、traversable = 认领表（跨河可达唯一查询入口）；② **横切机器定义**（§2.3 重写版）：有河 link 上道路 + crossing = 合法 / 无 crossing 的有河 link 道路跨接 = 拒绝（BRIDGE_ENDPOINT_INVALID 与禁渡拒绝分开报）；③ **桥几何**：跨该 link 的条带面（两岸格顶面之间、y = max(两岸 y)+独立 lift 档），沿 edge_tangent 横跨；桥塔/护栏属 12 号文档 T3 结构物资产位（首发清单已含桥，docs/12:138 通用 T3×2），初版程序几何资产化后换（Catlike Part 11 预制体思路 → Godot 独立 mesh）；**取 Catlike 三条放置规则并作格边转译**——①两岸都有路才设 = bank_a/bank_b 两格均在道路序列中（横切定义自动含）且生成侧桥址筛选要求对岸已有路网连接；②急弯/端点不设 = 桥址候选排除河在该边处急弯的边（按 §2.6④ 重释：连续同号转向 = 急弯）与 reach.edges 首尾边（源/终点）；③方向所有权去重 = 穿格版需去重因两岸多方向可各自生成桥，格边版桥锚定单 link、一 link 至多一 crossing——**该规则结构性退化、自动满足**；④ **桥面拾取**：桥面进碰撞则先于河床命中——面候选 = bank 两格；⑤ Kind.FERRY 预留不开（枚举存在 ≠ 能力开放） |
| **数据合同影响** | 草案 §8 整节按格边重写（字段大简）；§4/§7 禁令格边重述（§2.4）；无新 ADR（ADR-14 覆盖） |
| **测试锚** | 桥端合法锚点：bank_a/bank_b == river_edge 两端格断言；横切判定两用例（合法横切 / 禁渡拒绝分开报错）；「同 link 河和路不得无认领共存」校验器用例；traversable_edges 查询返回桥连接（跨河可达唯一入口）；Kind.FERRY 拒绝开启；桥面真实 raycast 归属 bank 两格（picking_scene_check 扩） |
| **风险与回退** | 同 link 河+桥渲染分层（河面在下/桥面在上，y 已分层 + 透明深度顺序）——探针留证；格边横切定义是重议建议未经主创确认——落卡前须过 §2.6②；回退 = 无桥状态合法，必需连接过不了河 → 明确失败（ROAD-03 口径） |
| **卡内拍板项** | §2.6②（认领语义反转）——落卡前必须确认 |

### ROAD-03 聚落道路骨架与绕行

| 项 | 内容 |
|---|---|
| **目标** | 必需聚落全部连接；禁桥时无法连接则返回失败；可选回路不能突破硬约束（提案 :281 验收原文） |
| **现状** | 无 POI（聚落不存在——WORLD-03 未做）；无路径权重口径（TraversalPolicy 属 M3、草案 §1.2 明确不定义）；MapConnectivity 是唯一可达性工具且无高程/地形修正 |
| **技法移植设计** | 技法来源 = **Azgaar routes-generator 连通加成思路 + 提案「道路与聚落的可执行合同」节**。① **骨架算法**：候选聚落对 → 生成器内部路径成本（高差分级 + 绕水 + 河界加成——Azgaar getHeightCost 地形版结构沿用：平原低费/丘陵中费/山高费/水极高费）→ 聚落图上最小连接骨架（MST）→ 按配置加少量可选回路（is_loop 字段已有）；② **过河处置**：唯一连接需过河时先搜合法桥址（候选 = 河段边有限集：两岸格 + 有河 link + 高差合法），找到建 CrossingData 再定线；找不到 → 明确失败或放弃候选聚落（提案明示两条合法出路，不静默删河/压山伪造达标）；③ **加路后重验**：出生区 footprint/桥端/必需目标可达性全量重跑（复用 WORLD-04 校验器，规则未启用按平地通行口径——草案 §11）；④ 路径权重是生成器内部口径不进数据（§7 禁止项原文） |
| **数据合同影响** | 无新实体；生成器内部路径权重不落世界事实；CrossingData 生成侧写入（消费 §8 重议成果）；TraversalPolicy 仍不定义（M3 门） |
| **测试锚** | 必需聚落全连通：骨架生成后 ROAD_NETWORK_DISCONNECTED 必须为零；禁桥失败明确：错误串指向具体聚落对与河段（最小诊断输出锚）；可选回路不破硬约束：加回路后可达性/footprint 冲突全量重验；修复/定线不动 locked 约束（模板锁定区先验） |
| **风险与回退** | 桥址搜索与定线互相依赖——固定顺序：先骨架拓扑定过河点、再桥址校验、再定线；回路加坏破硬约束——每次加路后全量重验；回退 = 放弃候选聚落（提案明示合法） |
| **卡内拍板项** | 无（成本表数值属生成配置，模板重定时统一定） |

---

## §6 T5 世界生成（拍板④：不造气候、只有地形）

技法主源：**Red Blob mapgen4**（https://www.redblobgames.com/maps/mapgen4/，分层
生成+人工约束+改后重算下游）作生成主参照；**polygon-map-generation**
（https://www-cs-students.stanford.edu/~amitp/game-programming/polygon-map-generation/，
下坡流/无局部极小）与 **x/1723**（https://www.redblobgames.com/x/1723-procedural-river-growing/
河口反向生长）作排水轴；**Catlike Part 23**（https://catlikecoding.com/unity/tutorials/hex-map/part-23/
search-frontier 抬升/下挖）~~仅作地理骨架候选算法~~ **已排除（2026-10-11 拍板：
不做抬升/下挖，地理骨架唯一路线 = 现双噪声）**；**Azgaar** 阶段化校验/seed 纪律
（generation-pipeline.ts 线性序无阶段诊断产物 = 反面教训——线性序本身的可定位性是
正面纪律、WORLD-04 沿用；lock/ErasePipeline = 前瞻）；
**WFC**（https://felixturner.github.io/hex-map-wfc/article/）作装饰层二级生成器
（模板定型后）。T5 完整世界生成挂 M3 门或主创另立地形里程碑（04 边界声明）。

### WORLD-01 模板和阶段化生成

| 项 | 内容 |
|---|---|
| **目标** | 每阶段独立摘要、版本与错误；关闭一个尚未实现能力不产生伪字段（提案 :282 验收原文） |
| **现状** | MapGenerator.generate 单遍直线代码：双噪声采样 → 归一化 → 量化高程+分类 → 连通检查（map_generator.gd:60-143），无阶段化骨架/阶段诊断/生成尝试-修复循环（失败只 ok=false）；无模板配置层（MapGenParams 仅噪声参数）；GENERATOR_VERSION=1 是复现锚（:31） |
| **技法移植设计** | ① **阶段序列按拍板④去气候重排（九阶段）**：配置校验 → 地理骨架 → 地貌整形（量化）→ 排水骨架 → 流量水系 → 聚落资源 → 道路过河 → 可玩校验 → 表现派生（气候/生态阶段删除）；每阶段 = 独立纯函数 `stage(input, rng_channel) -> {output, diagnostics}`，WorldPipeline 编排器持可插拔阶段序列——MapGenerator 现单遍代码重构为第一阶段序列的退化特例（噪声地理骨架 + 量化 + 连通检查三阶段）；② **地理骨架（2026-10-11 拍板：不做抬升/下挖，单路线）**：现有 FastNoiseLite 双通道；~~Catlike frontier 抬升下挖候选~~ 已排除；Red Blob「高程=到海岸距离 BFS + 无局部极小保证」作高程后处理约束（排水骨架输入保障）；③ **模板**：WorldTemplate Resource（.tres，TerrainStyle 资源化先例）——template_id/dimensions/地理/水系/基础设施/scenario/presentation 参数组 + locked/preferred 约束（提案 yaml 结构去气候后重定，openDecisions）；mapgen4「先要素、用户改、重算下游」留作 M3 编辑能力；④ **具名随机通道**：root seed + 具名偏移（MOISTURE_SEED_OFFSET 先例，map_generator.gd:35）扩 geography/hydrology/poi/roads/decoration（biome 通道删除）——「新增一棵树不消耗前面阶段 RNG」（提案随机性纪律） |
| **数据合同影响** | GENERATOR_VERSION +1（管线变更，:31 复现锚纪律）；草案 §10 WorldMeta 转正（温度/生态字段移除或降可选——拍板④）；新增模板 Resource 层（生成器配置不进世界事实，草案 §1.2 边界维持）；无新 ADR |
| **测试锚** | 每阶段独立摘要可 diff（阶段输出规范序摘要 + 阶段版本号）；关闭未实现能力不产伪字段：跳过阶段的 WorldData 对应集合为空（empty 集合合法锚）；同 seed 同模板同引擎构建 → world_digest 一致（跑 3 次）；配置冲突显式失败：冲突原因串全列不产半图；具名通道独立性：改 decoration 通道不影响 hydrology 输出摘要 |
| **风险与回退** | 阶段间状态耦合（排水要连续高程、量化后要重验）——跨阶段数据结构设计是最大不确定性，建议 spike 先行；模板参数未重定即开工 → 返工（openDecisions：温带河谷模板剩余参数须 T5 前重定+批量校准）；回退 = 旧单遍管线以 GENERATOR_VERSION 隔离保留，模板可选 legacy 路线 |
| **卡内拍板项** | 模板参数组重定（openDecisions 明列，须 T5 前拍）；~~地理骨架默认路线（双噪声 vs frontier）~~ **已拍板（2026-10-11）：不做抬升/下挖，双噪声唯一路线** |

### WORLD-02 排水骨架（原「排水/湿度/生态生成」——湿度/生态已被拍板④剔除）

| 项 | 内容 |
|---|---|
| **目标** | 无环、合法出口、量化后二次验证（提案 :283 验收原文；~~生态分布与模板范围相符~~一条随拍板④出范围待重定改写） |
| **现状** | 无连续高程（WorldFields 未实现——草案 §1.2 明确不在草案范围）；无排水映射（ADR-14 前置之二）；无洼地处理；湿度/生态部分已出范围，排水因格边河升为 T3 前置——存续待拍板（§2.6③） |
| **技法移植设计** | 建议**案 A**（§2.6③）：排水映射最小版（手工表 + 校验器：edge→next_edge 无环有终点）随 T3 前置落地；本卡范围只剩自动骨架——① 自动骨架：连续高程场（**生成中间产物不落盘**，避免新数据合同实体）→ downstream 表——**排水载体 = 边**（与手工版同口径：edge→next_edge；『每格 downstream』仅作派生中间量——格 → 取其最低出边，落表仍以边为准；同高程平台用稳定排序或排水 rank 消循环——提案原文）→ 洼地三分法（声明湖 / 受限填洼开槽 / 返回失败）；量化后二次验证：离散高程上重走边序列验证水面单调与河床容纳（提案「量化后必须重验」原文）；② **交叉验证轴**：生成后可用 Red Blob x/1723 河口反向生长复核高程一致性（诊断用非主生成器——姊妹篇 x/1724 由河网反推高程已被原作者证伪，禁作主生成器；URL 见 §1 河流拓扑行）；③ Strahler 数（分叉两侧同级 +1 否则取 max，后序遍历）→ flow_level 河宽分级映射（Red Blob 河网篇取材） |
| **数据合同影响** | 存续与归属待主创拍板（§2.6③）；排水映射建议为生成中间产物不落世界事实（落成 reach 边序列即终态）；量化后重验进校验器（水面单调，与 WATER-01 锚共享） |
| **测试锚** | 无环 + 合法出口（RIVER_CYCLE/NO_RIVER_OUTLET 在自动产出的边序列上）；量化后二次验证：离散高程上水面单调重验（非只在连续场上验证——提案明示）；洼地三分法各路径 fixture：成湖/填洼/失败；同 seed 排水图一致（确定性） |
| **风险与回退** | 连续→离散量化破坏排水结构（重验失败率高）——局部挖槽策略与失败率留诊断；WorldFields 是否实体化——建议中间产物不落盘；回退 = 手工排水表（T3 前置版）始终合法 |
| **卡内拍板项** | §2.6③（存续与归属）——卡范围由此定 |

### WORLD-03 出生/资源/城址分配

| 项 | 内容 |
|---|---|
| **目标** | 3 组合法出生区；核心资源在允许预算内可达；不占桥端/河床/道路禁用区域（提案 :284 验收原文） |
| **现状** | POIData 纯文档（草案 §9）；失败回归图只锚连通性、无 POI 可达性失败样例；出生/资源/城址分配逻辑不存在；「三组」是适配提案非承诺（提案 :49 自署） |
| **技法移植设计** | 技法来源 = **Azgaar burg 放置的气候绕开版**（深读 adaptationNotes 给出公式：删 habitability 项后 cells.s = 高程评分 −(h−50)/5 + 河流 flux 加成 + 海岸类型加成，三项本就不依赖群系）+ quadtree 间距 → **六边形环距版**。① 适居度：纯地形评分（高程带 + 河流加成 + 海岸加成），阈值沿 Azgaar 高度结构（h<20 水 / 44+ 丘 / 67+ 山 → 本作 int 离散高程分档映射）；② 主城/出生区：3 势力主城 = 适居度前列带偏置随机抽取（placeCenter biased(0,max,5) 模式）+ 强制最小六边形环距（HexMath.distance，首都间距 (W+H)/2/3 的距离版）；每城 7 格落兵区 = 中心+六邻（半径 1，恰好 POIData SPAWN_ZONE footprint 原文形态）；出生候选区间最小环距 = 「3 组合法出生区」的机器表达；③ 资源点：role 占位（M2 前不编造产出/储量/成本——exclusions 明列）+ 预算/距离目标在模板配置不进实体；④ footprint 冲突校验：不与河段边两岸锚点格、桥端格、道路格重叠（§9 已列）；⑤ 失败样例入库：沿 FAILED_FIXTURE_DIR 先例（map_io.gd:26） |
| **数据合同影响** | 草案 §9 POIData 转正（字段不动）；势力归属仍禁入数据层（scenario 层，§9 禁止项维持）；factionProspect 全部机制挂本卡与 M3 门（§7） |
| **测试锚** | 3 组合法出生区：footprint 七格界内可通行 + 组间最小环距断言（NO_VALID_SPAWN fixture 反例入库）；核心资源可达：从各出生区到必需资源点可达（规则未启用按平地口径——草案 §11）；footprint 冲突：与河/桥/道路重叠 fixture 拒绝（错误指向具体 cell）；适居度确定性：同 seed 同分布（不依赖运行时 hash 序——提案随机性纪律） |
| **风险与回退** | 公平性指标悬置（拍板⑤）——参考公平性偏差 ≤25% 是候选目标不作验收；三组出生区是适配提案非承诺——按 1 玩家+2 AI 实际设计校准；回退 = POI 空集合合法（无 POI 世界可渲染可游玩） |
| **卡内拍板项** | 三组出生区按 1 玩家+2 AI 的实际适配确认（提案自署非承诺） |

### WORLD-04 校验、有限修复与 seed 银行

| 项 | 内容 |
|---|---|
| **目标** | 100 个发布 seed 按模板与尺寸验收；不合格图入库，修复不动锁定约束，最多 4 次尝试（提案 :285 验收原文；100/100、≥95% 为候选目标非实测承诺） |
| **现状** | 校验 = MapConnectivity 连通一项；生成失败只 ok=false 无重试无修复；错误不指向 cell/link；无 seed 银行；失败图入库通道已有（FAILED_FIXTURE_DIR + test_map_source 引用先例） |
| **技法移植设计** | 技法来源 = **Azgaar 双面取材**：线性管线「执行顺序即依赖图」的**可定位性**正面沿用（哪一步坏了可定位——诊断的前提）；其**无阶段诊断产物**（失败不产出阶段摘要、错误不指向对象）是反面教训——本作每阶段独立摘要/逐对象错误即补丁。加 **提案门禁矩阵/最小诊断输出 + seed 纪律**（Azgaar 2023-04 复现性破坏反面教训 → GENERATOR_VERSION 锁定 + 世界管线独立计数）。① WorldValidator = WorldData.validate(map)：草案 §11 错误码清单直接落码（NO_VALID_SPAWN/RESOURCE_UNREACHABLE/RIVER_CYCLE/NO_RIVER_OUTLET/BRIDGE_ENDPOINT_INVALID/ROAD_NETWORK_DISCONNECTED/LOCKED_CONSTRAINT_CONFLICT）——错误 {code, cell_ids, link_ids, constraint_id, explanation} 指向具体对象；② 有限修复：最多 4 次 attempt（验收原文），每次只动非 locked 约束的修复动作（重画河段/重连道路/换出生候选带），每次后全量重验；attempt_count/repair_count/first_pass_valid 落 WorldMeta；③ seed 银行：按模板 × 尺寸分组的固定 seed 清单 + 批跑验收工具（tools/ 沿 make_fixed_maps/generate_map 先例）；发布银行与探索性新 seed 分开统计；④ 渲染证据联动：银行样图走 render_probe 差分留档（Forward+ 通道，Compatibility/Mobile 标未测——GATE-02 先例） |
| **数据合同影响** | 草案 §11 校验器转正 + §10 WorldMeta 的 attempt_count/repair_count/first_pass_valid 落码；ValidationReport 为诊断通道不进 WorldMeta（§10 禁止项维持，generation_ms_by_stage 走诊断通道）；无新 ADR |
| **测试锚** | 错误指向具体 cell/link：每个错误码至少一个 fixture 断言 explanation 含定位；修复不动 locked：锁定区修复前后逐位一致；attempt 上限：第 5 次尝试拒绝；失败图入库：银行跑失败样例落 FAILED_FIXTURE_DIR + .world.json 伴生（可加载复验）；确定性：银行 seed 重跑 world_digest 一致（3 次） |
| **风险与回退** | 修复动作互相打架（修河破坏路）——固定修复顺序 + 每次全量重验兜底；批跑耗时——提交级只跑 smoke seeds、完整银行跑定期回归（提案提交级别口径）；回退 = 校验失败即明确失败（不伪造达标——提案红线） |
| **卡内拍板项** | 无（指标数值悬置，批跑工具照做、数字留档不设门——拍板⑤） |

---

## §7 Azgaar 势力范围改造案（前瞻；全部未拍板，挂 WORLD-03 与 M3 门）

> 效力声明：本节机制与数值**全部未拍板**，不进 T2-T5 十三卡验收；T2-T5 只按各卡
> 预留数据位（POIData SPAWN_ZONE footprint、river_edge、locked/preferred）。来源 =
> Azgaar 源码深读（states-generator.ts / provinces-generator.ts / burgs-generator.ts /
> draw-borders.ts 等，URL 见 §1 表与调研档）。气候依赖逐项绕开 = 拍板④（不造气候）
> 在势力侧的执行口径。

| 方面 | Azgaar 做法 | 六边形+格边+3 势力 PvE+占点经济改造 | 门 |
|---|---|---|---|
| 边界绘制 | Voronoi 顶点链两阶段行走（draw-borders.ts getVerticesLine 沿「顶点两侧分属两方」成链） | **更简单**：相邻两 hex 势力不同 → 共享格边即边界边；收集全部跳变边（NeighborLinkData 遍历）按端点（格子顶点，HexMath 全局派生）缝合折线——不需要顶点链算法。ADR-14 格边河直接作「河界」：过河成本高（对标 getRiverCost 20-100 按流量）+ 有河 link 为天然边界线。3 势力无省时只画一层国界（省层整体砍——整套 provinces 541 行） | WORLD-03（数据位）+ M3（机制） |
| 势力生长 | expandStates：各首都格入队多源 Dijkstra，totalCost = 距离项 + cellCost/expansionism（五项：文化/人口/群系/地形/河流海岸），growthRate 预算，同格归更低总成本者，水格传播成本不归属 | 保留骨架替换输入：邻接换 HexMath.neighbor 六邻；成本表砍成**纯地形项**（水面/山/丘陵/平原 + 河界加成，沿用其高度阈值结构 h<20 水、44+ 丘、67+ 山 → int 离散分档映射；数值档见「气候依赖绕开」行 ③ 源码实读）；expansionism 给 3 势力各配一档；normalize() 多数滤波（某陆格 ≥2 个邻格属他国**且敌对邻格 ≥ 己方邻格**则改判，burg 格与首都邻格豁免）低成本消灭斑噪声，**建议原样保留** | M3；地形玩法规则（河流禁渡/涉渡）同挂 M3（ADR-14 只定拓扑不定规则） |
| 文化层裁剪 | cultures 铺底（cultureCost ±9/100、文化中心 td/bd 评分） | **整体裁掉**：3 势力纯 PvE 不需要文化铺底；势力「类型」扩张风格差异保留为差异化参数——仅保留 getHeightCost/getTypeCost 类型分支即可复刻「山地势力不下平原、海洋势力跨海便宜」个性 | M3；与 06/08 阵营设计联动 |
| burg→占点放置 | burgs：适居度排序 + quadtree 最小间距 + 不够则重来并收缩间距；首都间距 (W+H)/2/国家数 | **该抄的算法**：六边形版 = 按格分排序、以六边形环距（HexMath.distance）做最小间距；首都 = 3 势力主城，间距取 (W+H)/2/3 距离版，适居度前列带偏置随机抽取（biased(0,max,5) 模式）；每城 7 格落兵区 = hex 及 6 邻（半径 1），天然对应「首都格不可被覆盖」+ 首都邻格不被清洗两条保护；WORLD-03 三组出生候选区 = 同一间距约束的候选带版本，POIData SPAWN_ZONE footprint 即数据形态 | WORLD-03（占点放置进卡）；产出/征兵数值挂 M2 |
| 经济差异 | 军队/税收全挂人口（military base=pop/100） | **经济挂占点**：「每格 pop 派兵」改「每占点产出配额」——产出表 ≈ 占点等级 × 所在格地形修正（nomadic/wetland/highland 加成矩阵换地形版）；routes 的连通度加成（connectivityRate）值得保留：占点间道路连通提升产出，给玩家经营路网动机（与 ROAD-03 骨架衔接） | M2（资源经济定稿）与 M3 双门 |
| 气候依赖绕开 | 群系是气候总代理（温度×湿度查表） | 依赖全可追溯到「每格一张 habitability/cost 表」：① 群系表 → 高程带地形表（其自带阈值即自成体系）；② 适居度 = 高程评分（−(h−50)/5 已有）+ 河流 flux 加成（独立计分）+ 海岸类型加成（独立计分）——三项本就不依赖群系，删 habitability 后公式自洽；③ biomeCost → 地形通行成本表，**数值取 Azgaar 源码实读**（2026-10-11 raw.githubusercontent.com 复核 states-generator.ts getHeightCost）：states 版 = 海 h<20=1000（Naval 300 / Nomadic 10000）、丘 h≥44=300、山 h≥67=2200、平原 20≤h<44=0、原生群系优惠 10（getBiomeCost）→ 本作映射为「本土地形带优惠 10」；~~平原 10/丘 30/山 200/水 1000~~（调研档简写与 states 源码不符，实为 provinces 版数值——平原 h≥20=10 / 丘 h≥50=30 / 山 h≥70=100 / 浅海 100，两档分列引用）；④ 温度引用直接删或全图默认可航；⑤ 兵种三档 → 高程带+水邻接分档；⑥ 河流反向依赖：本作河是格边显式输入非降水产物——河参与评分与成本，降水环节整体删除。若 M3 想要气候味道：Azgaar 温度/降水生成器极轻（纯标量场）可作可选层后加而不动势力管线 | 拍板④已定方向；落地挂 M3 |
| M3 前瞻 | lock 机制（重生成保留锁定实体）+ ErasePipeline（改后只重跑下游）；pole of inaccessibility（每国距边界最远格放标签）；growthRate 随阶段放大 | ① lock + 只重跑下游 = 「世界推进/养成不丢进度」现成模式：锁定玩家已占区域与占点，重生成其余（与 WORLD-01 locked/preferred 同一机制，生成侧已留位）；② 国名标签 = 跳变边 BFS 最远格，实现便宜；③ 势力随章节扩张 = 预算随阶段放大 | M3 门全未拍板，只作概念预留 |

**Azgaar 高度阈值 → 本作 int 高程换算注**（「分档映射」的落地方向，2026-10-11 实读
本作量化链）：本作 elevation 值域 = {0(水), 1..levels(陆)}（`elevation_levels` 默认 4、
值域 1..64，map_gen_params.gd:29-30/:48；`sea_level` 默认 0.25，:47）；量化式 =
陆格 `level = clampi(int((n − sea_level)/(1 − sea_level) × levels), 0, levels−1) + 1`
（map_generator.gd:111-112），水恒 0。Azgaar h∈[0,100] 换算 = n=h/100 过同一链：
默认参数下 **h<25 → level 0**（水；与 Azgaar 阈值 20 不精确对齐——模板重定时按需
对齐 sea_level）、**h=44 → level 2、h=67 → level 3、h=100 → level 4**，即 44+ 丘 ≈
level≥2、67+ 山 ≈ level≥3（默认 4 档近似落位；要阈值恰落档界可调 elevation_levels，
如 6 档）。分档数值全部未拍板、随模板重定。

---

## §8 跨切项

### 8.1 几何级 profile 与材质级 style 的不变量分档（T2 起生效）

现状 TerrainStyle 只有材质级双 mode（SLOTS/BLEND，terrain_style.gd:47-52），不变量 =
换 style 索引/face 表逐位一致（BLEND-03 已锚）。T2 阶地是**几何级**差异，mesh 必须允许
变——须在 04 明确两档不变量：

| 档 | 载体 | 不变量（换档时逐位一致） | 允许变 |
|---|---|---|---|
| 材质级 style | TerrainStyle（.tres） | mesh ARRAY_INDEX、faces、碰撞汤、MapData.summary/digest、连通性 | 材质实例、顶点 COLOR |
| 几何级 profile | LandformProfile（建议独立 Resource；或 TerrainStyle 加 geometry 组——提案 yaml landform_profile 字段先例） | MapData.summary、world_digest、连通性 | mesh/face 表/碰撞汤 |

几何 profile 字段建议：terrace_enabled / terrace_steps / cliff_vertical / cliff_threshold
（分档阈值）。**blend 权重合同同步扩档**：BLEND-01「mesh 侧不设中点顶点」限定回材质级
表现切片（hex_terrain_blend.gd:13-16 头注同步改），几何任务的阶地细分顶点合法、但每
新顶点权重必须由 edge_weights/corner_weights 同一函数显式求值（有限非负和 1 在每点
保持）——tests/test_hex_terrain_blend.gd 面数锚同步改（「翻案须同步改测试」纪律）。

### 8.2 与 docs/12 内容物管线衔接（全部待共创审、未拍板）

| 衔接点 | 内容 | 时机 |
|---|---|---|
| T0 贴图 splat 升级 | 「海拔×坡度×湿度混合」的**湿度输入随拍板④删气候须改为高程带+确定性噪声 mask**（12:91） | 12 共创审时改口径 |
| 格线层参考件 | notes/spike-1007-salvage §1.1 归属未定（openDecisions）——若进 T2，dual grid 掩码选变体**只落贴图美化层**：数据格（格心地形归属）→ 渲染采样点（格角/格边中点=三角对偶格顶点）的 4-bit 掩码索引替代手工过渡贴图表；纯函数作用于已有地形数据，不改 mesh 拓扑、不进生成随机源（确定性纪律不破）。**与 §1 开头句的关系**：§1「模板定型后」指 dual grid 与 WFC 同挂装饰层的**默认归置**；本条「若进 T2」指格线层若被拍板归入 T2 时的提前启用——以格线层归属拍板（openDecisions）为准，两处不矛盾 | openDecisions 拍板后 |
| 散布系统 | hash(格子坐标+盐) 确定性散布（12:92），与河流/道路/桥端/出生 footprint 的避让约束在 T4/T5 生成侧对齐 | T5 |
| 桥资产位 | 首发 T3×2 含桥（12:138）——ROAD-02 程序几何的资产化后手 | T4 后 |
| grimdark 五条美术语言 | 低饱和大地色/山更尖峭垂直夸张/巨物地标（12:23-33）直接指导阶地步数、崖壁纵横比、水面材质选型与 render_probe 目检口径 | T2 起持续 |

### 8.3 沙盒与 render_probe 证据扩展

每段配固定图沙盒（blend_sandbox/blend_corner_sandbox/style_sandbox.tscn 先例）+
`tools/render_probe.gd` 阈值常量区（:72-88，沿「实测首报后余量 ≥3× 定档」规则）扩：
**CHECK-4** T3 水面差分像素阈值、**CHECK-5** T4 道路/桥差分阈值。三个 scene_check
（picking/highlight/camera）引擎级小场景随新面型扩展：picking 对阶地 riser/河床/桥面、
highlight 对贴合。探针**不进 headless 套件、只加证据不改渲染代码**；探针无法替代目检
（grimdark 口径的目检走沙盒 F6）。

### 8.4 性能护栏：指标悬置、证据照跑（拍板⑤）

不设阈值，但每段交付留数字档案：faces face_counts 已在 builder 元数据（:425-427），
阶地约 ×2.5、水面/路面各加独立 mesh——逐段登记面数/顶点数 + render_probe 像素统计；
T5 生成耗时按阶段记录（generation_ms_by_stage 归 ValidationReport 诊断通道，**不进
WorldMeta**——草案 §10 禁止项）。

---

## §9 边界重申（照抄既有拍板，本文不重开）

- **不阻塞 M1b**：本批 T2-T5 十三卡属表现层短切片（04 §M1a+ 边界），只可顺延、
  不得阻塞 M1b-T1 开工决策（拍板⑥+①）；每段交付保持「删 scripts/ui/** 后 tests
  全绿」纯逻辑纪律（ADR-2）。
- **T6 与 M3 门**：RULE-01/02、地形玩法规则（河流禁渡/涉渡、桥作用、道路成本、
  坡地限制）、TraversalPolicy、地形数值修正（07 待定项挂 mods、M1b 期间恒 0）、
  势力范围机制（§7 全部）、性能指标解冻——均沿 M3 决策门，不在本方案范围。
- **M2 边界**：资源产出/储量/成本数值不进字段集，POI 只用 role 占位；阵营归属/
  俘虏/占领语义在 scenario 层不在数据层。
- **性能指标悬置**（拍板⑤）：提案全部指标数值（合格世界交付率 100/100、≥95%、
  帧时间 p95≤16.7ms、生成 p95≤3s 等）均为候选目标非承诺，不进本方案验收；
  headless 全绿不得推出性能结论；Forward+ 探针证据照常留档。
- **环境硬前置**：Godot 4.7.2 恢复（本机现状见头部环境注）——T2 开工第一步 =
  恢复运行环境并全量 `tools/run_tests.gd` 对照 202 用例 / 0 失败基线。

---

*本文引用行号均为 2026-10-10 静态实读核对（addons/hexhammer 六文件、scripts/core
与 scripts/content 相关文件、docs/01-13 与两份 M1a 方案文档；2026-10-11 二/三轮
修订增核 map_gen_params.gd 与 map_generator.gd 量化链）；未执行测试/探针（Godot
4.7.2 缺失）。外部调研来源与 URL 见 §1；差距分析底稿的五份调研为唯一外部信源，
本文未新增调研档之外的信源——文中 x/1724、x/1723 等姊妹篇 URL 均出自 Red Blob
调研条目（调研档自带），非另查。*

**修订记录（2026-10-11，复核五条逐条处置）**：

1. LAND-01 分档边界与穷举矩阵自洽化（成立照改）：~~cliff(Δ>cliff_threshold)~~
   → cliff(Δ≥cliff_threshold，默认 3)；矩阵穷举上界恒 ≥ cliff_threshold，默认档
   Δ3 即崖样本——原写法下矩阵图恒无崖面，验收「平/坡/崖全部闭合并可见」不可达。
2. WATER-01「直行/转弯」重释改正（成立照改）：~~相邻边夹角分类 60°/120°~~
   （六边形边图上 60°/120° 是同一构型的互补量法、不构成两个类别，单步亦无直行）
   → 单步转向恒 ±60°、「直行」= 连续两步转向符号相反；该重释升格为 §2.6④ 拍板项
   并同步 fixture 判据，不再作已定口径呈现。
3. terrace_lerp 竖直系数修正（成立照改）：~~(step+1)/2 × 0.5~~（terrracesPerSlope=1
   的系数错配，产出 3 平台+2 短坡的不对称阶地）→ v_step = 1/ceil(steps/2)（=
   Catlike 原式 verticalTerraceStepSize=1/(terracesPerSlope+1)，5 步时 1/3，两档
   均为对称阶地）。
4. WFC 耗时修正（成立照改，2026-10-11 WebFetch 复核
   felixturner.github.io/hex-map-wfc/article/ 原文）：~~8-60s~~（调研档记法，原文
   无此区间）→ 4100 格 ~20s（原文自述"generated in ~20 seconds" / "~20s to build
   all grids"）；900 状态/格、19 网格分治两项与原文相符未动。
5. §7 成本数值修正（成立照改，2026-10-11 复核 raw.githubusercontent.com
   Azgaar master states-generator.ts）：~~平原 10/丘 30/山 200/水 1000~~（调研档
   混合简写）→ states 版 getHeightCost 实读：海 h<20=1000、丘 h≥44=300、山
   h≥67=2200、平原 20≤h<44=0、原生群系 10；「平原 10/丘 30/山 100」确认为
   provinces 版数值、分列引用。同批补全 normalize() 的「敌对邻格 ≥ 己方邻格」
   条件（原漏）。

**修订记录二（2026-10-11，独立读者意见逐条处置——只改表述与论证，不动结构与口径）**：

- unclear 七条：①拍板①②补内容注释（§0 遵守声明六项各配一句）；②WORLD-02 排水
  载体明确为边（「每格 downstream」降为派生中间量）；③补阶地步数-Δ 绑定规则
  （每爬一级一组、组间平台对齐高程整数层——设计建议，spike 验证）；④补 Azgaar
  阈值→本作 int 高程换算注（§7 表后，量化链实读 map_gen_params.gd:47-48 /
  map_generator.gd:111-112）；⑤dual grid 时机两处统一为「以格线层归属拍板为准」
  （§1 开头句 + §8.2 互指）；⑥湖/河双口径通行语义点破为有意设计（格语义水体 vs
  边语义水体，各自闭合，§2.2 禁令行）；⑦reach/link 流向权威写明（reach.edges 序
  顺序即流向、link 层初版零冗余、汇流开启再议，§2.4 表）。
- unsupported 七条：①§0 段表三项→四项（随上轮 §2.6④ 升格同步）；②Azgaar 线性
  管线定性调和（反面=无诊断产物、正面=可定位性，§1/§6 段首/WORLD-04 三处统一）；
  ③WATER-02「正交不抢顶点」改为「参数轴正交 ≠ 顶点集不交」并指向风险栏兜底；
  ④x/1724 论据补 URL 并在尾注澄清其属 Red Blob 调研条；⑤顺河禁令完备性论证补全
  （格边下顺河路几何不触河槽故合法、「纵覆」无独立非法类别、验收句机器判定落点
  =正向横切判定，§2.4 表）；⑥桥三规则格边判据转译（急弯=连续同号转向、端点=
  reach 首尾边、方向所有权去重结构性退化，ROAD-02）；⑦§0 段表 T3 行补案 A 否决
  时 fallback（T3 卡内自带最小手工表或整段顺延，均不阻塞 M1b）。
- wouldAsk 三条：①§2.6 头部补拍板流程（主创 04 落字）、清单权威（以 §2.6 为准）、
  悬置期间可动工范围（T2 三卡 + §2.5 四件不依赖任何拍板项）；②头部环境注扩写
  （4.6.2 不可用因 INT32 解析失败、202 基线建于 4.7.2、恢复达标判据=门禁复现）；
  ③WATER-02 补首版河宽口径（几何恒宽、flow_level 兑现在材质参数层，第二版宽河
  前大小河画面差异只在材质表现）。
