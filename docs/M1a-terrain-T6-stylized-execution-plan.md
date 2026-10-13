# M1a 地形 T6 执行方案（风格化地形：群山、平原与派系适配——S0 拍板登记与分期计划）

> **定位**：`docs/evidence/风格化地图生成方案_群山平原与派系适配_修订版.md`
> （下称「风格化提案」，2026-10-12 随 `9ab55bc` 只读登记，当时标注「提案含取代
> 拍板①事项待主创决议」）经主创 2026-10-13 拍板**按分期施工采纳**后的执行方案。
> **S0 = 本文档**：登记拍板、把提案 §实施分期 拆成本批次八个阶段（S0–S7）、
> 给提案 §尚待确认 四项本批次默认答案——docs-only，本阶段不写代码。
>
> **上承**：风格化提案 · [M1a-terrain-T2-T5-execution-plan.md](M1a-terrain-T2-T5-execution-plan.md)
> （下称 T2-T5 方案——已完工批次的合同与纪律基线，其头部已加取代注，见下）·
> 数据合同草案 [M1a-terrain-data-contract-draft.md](M1a-terrain-data-contract-draft.md)
> （§1.2「生成器配置不进世界事实」边界沿用）· [04-tasks-m1.md](04-tasks-m1.md)
> §M1a+（拍板登记流程权威）· 外审两份
> （[docs/evidence/Hexhammer-80640ee-Assessment.md](evidence/Hexhammer-80640ee-Assessment.md)、
> [docs/evidence/Hexhammer-80640ee-Fable-Review.md](evidence/Hexhammer-80640ee-Fable-Review.md)，
> S1 的证据来源）。
>
> **主创拍板登记（2026-10-13，对风格化提案）**：
> 「风格化地图生成方案（docs/evidence/风格化地图生成方案_群山平原与派系适配_修订版.md）
> 按分期施工采纳；地形生成新增 regions 模板路线作为并列路线，取代此前『双噪声
> 唯一路线』的排他表述；legacy 退化特例逐格输出不变」。
>
> 拍板三点含义（执行展开）：
> ① **采纳 = 分期施工**——本计划 §3–§9 的 S1–S7 即提案 §实施分期（:227-258）的
>   落位拆分，映射表见 §1；提案「非目标」清单（:28-34）整批继承（§2.6）。
> ② **regions 模板路线 = 并列路线**——`WorldPipeline` 的 geography 阶段新增由
>   世界模板选择的 regions 骨架路线（宏观分区 → 区域内部骨架 → 连续高度 →
>   权重混合），与现有 FastNoiseLite 双噪声路线**并列**；双噪声路线保留且行为
>   不变。T2-T5 方案 2026-10-11 首批拍板①中「地理骨架唯一路线 = 双噪声」的
>   **排他表述作废**（其头部已按 M1a-terrain-world-proposal.md 的 PLAN-ALIGN
>   先例加取代注）；该拍板的其余内容——**不做抬升/下挖、Catlike frontier 排除
>   ——维持权威**：regions 路线的骨架是「分区 + 对象化山系/宽谷/盆地 + 连续权重
>   场混合」，不是 search-frontier 逐格抬升/下挖，两者不冲突。
> ③ **legacy 锚 = 逐格不变**——`WorldPipeline.generate_legacy`
>   （scripts/content/world_pipeline.gd:178）与 `world_template_legacy.tres` 路线
>   的逐格输出**字节级不变**：legacy 模板钉死双噪声路线、不接 regions 参数；
>   tests/test_world_pipeline.gd 独立 oracle 锚与 tests/test_map_source.gd 复现锚
>   不放宽（沿 world_pipeline.gd:14-17 头注既登记的行为不变合同）。
>
> **命名澄清（防撞名）**：本文体系「T6」= **地形执行线批次号**（承接
> M1a-terrain-T2-T5-execution-plan 的 T2–T5 序列），指风格化地形批。它与
> 04-tasks-m1.md:79 的任务卡「M1a-T6 策略相机」（已完工）及
> M1a-terrain-world-proposal.md:259 路线表「T6 规则与内容深化」**不是同一对象**
> ——后者的 M3 决策门归属不变，本文档体系内一律以「M3 决策门」指称规则深化，
> 不再使用裸「T6」指规则批。
>
> **纪律声明（整批有效）**：阶段化纯函数、具名随机通道隔离、
> GENERATOR_VERSION / STAGE_VERSIONS / SCHEMA_VERSION 版本纪律、中文头注讲
> 「为什么」、tests/ 逐行为锚定（新行为必带新测试；禁止删测试或放宽既有断言，
> 按新合同显式更新断言除外且须在头注登记）——全部沿 T2-T5 方案已落码先例；
> 不 git commit / push（工作流统一做）；不碰 temp_reports/ 与
> resources/maps/generated/。

---

## §0 S0：本文档（拍板登记与执行计划）

| 项 | 内容 |
|---|---|
| **范围** | 只做三件 docs 件：① 本执行计划（拍板登记 + S1–S7 分期 + §尚待确认默认答案）；② T2-T5 方案头部加取代注（PLAN-ALIGN 先例）；③ 提案 §实施分期 → 八阶段映射落字。不改任何源码、模板、测试与门禁 |
| **关键文件** | 本文档；docs/evidence/风格化地图生成方案_群山平原与派系适配_修订版.md（提案原文）；docs/M1a-terrain-T2-T5-execution-plan.md（取代注落点）；docs/M1a-terrain-world-proposal.md:8-11（取代注格式先例）；docs/04-tasks-m1.md §M1a+（拍板流程权威） |
| **验收** | 文档自洽（本文 ↔ T2-T5 方案取代注 ↔ 提案三向互指一致、无悬空引用）；本文引用的全部仓库路径真实存在（S0 自查脚本逐路径验证，结果登记于本批 StageResult）；提案 §实施分期 各条目在 §1 映射表全覆盖、无遗漏无越界 |
| **非目标** | 不实现任何阶段的代码；不改门禁口径；不预先替 S3–S7 做设计拍板（各阶段落卡时再定细节）；不动 resources/maps/generated/ |

---

## §1 分期总表（S0–S7）

提案 §实施分期分三段（构图原型 P0 :229-239 / 玩法合法性 P0 :241-248 / 派系与
内容接入 P1 :250-258），外加 §验收与评估（:261-280）与两件批次前置（S0 拍板
登记、S1 门禁慢机适配——后者出自外审证据）。
八阶段映射与顺序如下——**段间只有前置链没有合并交付**（沿 T2-T5 方案 §0 总序
纪律）：

| 阶段 | 一句话范围 | 提案对应 | 前置 |
|---|---|---|---|
| **S0** | 本文档：拍板登记与执行计划 | —（施工前置） | 无 |
| **S1** | 门禁慢机适配：runner 超时预算按文件可配 + 整世界重测试拆分/缓存 | —（施工前置；外审 Assessment 中优先级「门禁超时预算与新增整世界测试不匹配」:115-119、Fable Review 低·环境「test_world_pipeline 20s 子进程预算」:137） | S0 |
| **S2** | 预览工具：区域/骨架/高度/坡度/可用连通片五视图 + 同 seed 同相机三对照 | 构图原型 P0「调试预览」「固定对照」（:236-237）+ 山地/平原偏好候选临时标注（:239） | S1 |
| **S3** | 分区骨架：regions 模板路线落码（宏观分区 + 山系/宽谷/盆地/平原骨架 + 连续高度与权重混合 + 量化衔接） | 构图原型 P0「宏观区域」「地貌骨架」「连续高度」（:233-235） | S1、S2 |
| **S4** | 孤峰侵蚀：孤峰对象（显式中心/半径/峰高/形状 + 间距/预算/避让）+ 选择性侵蚀与复查回退 | 构图原型 P0 孤峰项（:235、:74-82）+「选择性侵蚀」节（:100-109） | S3 |
| **S5** | 区域验收 + 银行：WorldValidator 区域指标/错误码 + seed 银行扩 regions 组 × 三档 | 玩法合法性 P0「区域验收」「可控修复」（:245-246）+ §验收与评估 表（:265-276） | S3、S4 |
| **S6** | 派系适宜度：与派系名解耦的偏好配置 + 两阶段选址 + 开局保证入口（默认关） | 派系与内容接入 P1「偏好配置」「候选选址」「开局保证」（:254-256）+ §派系适配（:136-166） | S5 |
| **S7** | 视觉验收：灰度统一相机人工评审 + 性能基线留档 | §验收与评估「结构风格单独做人工评审」+ 性能基线（:278-280） | S5（S6 可并行收口） |

**顺序依据**：S1 在先——T6 每阶段都会新增整世界测试，先修「慢机预算失配」否则
门禁在慢机上不可复现（外审两份同证）；S2 在 S3 先——预览与对照是 S3 起每阶段的
证据通道（沿 render_probe「只加证据」纪律）；S5 在 S6 先——提案「地形先成形、
派系后选址」（:16）的机器化表达即「区域验收通过后才接入适宜度」。

**映射完备性注**：玩法合法性 P0 的「合法水系」（:244）与「一致性」（:247）不是
新阶段——前者 = T3/T5 已交付能力（WATER-01~03 / WORLD-02 河网与校验），regions
路线作为 geography 上游替换不触碰（S3 非目标明示），水系合法性随 S5 银行批跑
复验；后者 = 现有不变量面（scene_check 三件 + 探针 + world_digest 确定性锚），
由 §2.5 整批承接。派系与内容接入 P1 的「表现扩展」（:257，建筑/植被/材质）不属
本批（S7 非目标明示）。

---

## §2 总则（整批合同）

### 2.1 regions 并列路线的机器表达

- **模板选路线**：`WorldTemplate`（scripts/core/data/world_template.gd）扩
  geography 路线选择字段（如 `geography_route: "dual_noise" | "regions"`——命名
  落卡时定）；`make_legacy()` / `world_template_legacy.tres` 钉死 `"dual_noise"`
  且不带 regions 参数组——legacy 逐格输出字节级不变（拍板③）。沿 WORLD-01
  回退设计先例（T2-T5 方案 §6：「旧单遍管线以 GENERATOR_VERSION 隔离保留，
  模板可选 legacy 路线」）。
- **阶段插入**：regions 路线 = geography 阶段内的双路线分派 + 连续域新子步
  （分区 → 骨架 → 权重混合）；侵蚀（S4）作为 geography 与 quantize 之间的新
  阶段（提案 :46-57 主线序：连续高度 → 选择性侵蚀 → 六边形投影；本作量化即
  投影，map_generator 量化链不动）。新阶段/子步全部进 `STAGE_VERSIONS`
  （world_pipeline.gd:101-104）新键，独立版本号。
- **数据结构**：提案 §数据与确定性合同（:181-219）的 TerrainRegion /
  TerrainSkeleton / FactionSuitability 等按「名称可与现有工程适配」授权落
  `world_data.gd`（沿 POIData/StateData 扩容先例）；WorldData.SCHEMA_VERSION=1
  维持（world_data.gd:94）——新集合**缺键合法**（旧图零迁移，沿 pois/states/
  cell_owners 先例），变更登记走 GENERATOR_VERSION 与模板版本。GenerationReport
  的 region_metrics/constraint_violations 走诊断通道不进 WorldMeta（沿 §8.4
  「generation_ms_by_stage 归 ValidationReport 诊断」纪律）。

### 2.2 版本纪律

- regions 路线首落（S3）= **GENERATOR_VERSION+1**（world_pipeline.gd:58，现值
  4 → 5）：管线面变更（geography 双路线分派 + 新通道 + 新实体）。此后各阶段
  算法变更逐次 +1；阶段级细粒度锚走 STAGE_VERSIONS。
- **SCHEMA_VERSION 不动**（1）：MapData.SCHEMA_VERSION（map_data.gd:29）与
  WorldData.SCHEMA_VERSION（world_data.gd:94）均维持——新数据全走「缺键合法 +
  伴生文件」既定通道，无破坏性迁移。

### 2.3 具名随机通道对齐

提案八通道（layout/region/mountain/isolated_peak/erosion/hydrology/settlement/
road，:221）对现有五通道（geography/hydrology/poi/roads/decoration，
world_pipeline.gd:106-113）：**hydrology / settlement（现 poi 承载聚落落点）/
road（现 roads）复用既有通道不重复开**；新增 region（含提案 layout 构图职责，
S3 落卡时定是否拆分）、mountain（骨架，S3）、isolated_peak 与 erosion（S4）。
新通道沿 `CHANNEL_SEED_OFFSETS` 先例取**与既有五值互异的写死偏移**、追加在表尾
——不重排既有通道（通道输出不漂移）；「新增一个装饰对象不改变整张地形」的
通道独立性锚（tests/test_world_pipeline.gd 既有面）随各阶段扩用例。

### 2.4 legacy 铁律（整批）

`generate_legacy` / `world_template_legacy` 逐格输出字节级不变（拍板③）：任何
阶段触碰 geography/量化链时，legacy 路线回归锚（tests/test_world_pipeline.gd
独立 oracle + tests/test_map_source.gd 复现）必须全绿且断言不放宽。

### 2.5 验收证据通道

沿 T2-T5 已建成的三层：单测（tests/，新行为新锚）→ 场景检查三件
（tools/picking_scene_check.gd 等）→ 渲染探针（tools/render_probe.gd，新 CHECK
沿「实测首报后余量 ≥3× 定档」规则）。S2 预览工具是第四层（数据面摘要 + 对照
截图），**只加证据不改渲染代码**。

### 2.6 继承的非目标（提案 :28-34 整批有效）

真实地质模拟 / 整块单一地形硬切分 / 永久派系领土 / 完整派系玩法（数值、兵种、
经济、战争——M3 门）/ 全面重写（不同时迁移全部水系、道路、存档与表现模块）。
另沿 T2-T5 §9：性能指标悬置（拍板⑤）、不阻塞 M1b。

---

## §3 S1 门禁慢机适配

| 项 | 内容 |
|---|---|
| **范围** | ① runner 子进程超时预算**按文件可配**：`tools/run_tests.gd` 现全局单档 `CHILD_TIMEOUT_MS := 20000`（run_tests.gd:40），慢机上 test_world_pipeline 超预算误报（Fable Review :137：单跑 17/0 耗 24.4s，临时调 60s 后 29 文件 384/0 exit 0）——沿 runner 自身 fixture 表「timeout_ms 按文件指定档」既有机制（run_tests.gd:50-56）扩到真实测试文件表；**默认档不变**（快机行为零变化）。② 整世界重测试拆分/缓存：沿 Assessment :119 建议「缓存同配置的纯测试 fixture、减少不必要的重复生成；仍保留硬超时与短故障样本」——test_world_pipeline 重生成部分抽缓存 fixture 或拆轻量/重档两文件，断言面不缩水（拆分后用例总数 ≥ 现状）。③ 门禁口径零改动：gate_all 五步顺序、聚合逻辑、三态口径、「图形检查失败不得被单测成功覆盖」全部不动 |
| **关键文件** | tools/run_tests.gd（预算表 + 聚合）；tools/run_one.gd（子进程 runner——退出码/报告协议不动）；tools/runner_fixtures/（hang 短档故障样本——3s 拦截锚不得放宽）；tools/gate_all.gd（只跑不改）；tests/test_world_pipeline.gd（拆分/缓存对象）；docs/evidence/Hexhammer-80640ee-Assessment.md:115-119 与 docs/evidence/Hexhammer-80640ee-Fable-Review.md:137（证据来源） |
| **验收** | 全量 `tools/run_tests.gd` 在慢机档 0 失败复现（预算上调路径生效）；不配任何覆盖时输出与现基线逐项一致（默认档回归锚）；runner_fixtures 变异自检全拦（hang 样本仍短档拦截、fixture_hang 零引擎 ERROR）；本阶段**不改任何既有断言**（「按新合同显式更新断言」不适用——无合同变更） |
| **非目标** | 不改门禁判定语义与聚合口径；不优化生成器/测试自身性能（那是各阶段的事）；不删测试不并文件缩减用例；不动 resources/maps/generated/ 与 temp_reports/ |

---

## §4 S2 预览工具

| 项 | 内容 |
|---|---|
| **范围** | ① 数据面调试摘要工具（tools/ 新建 headless 脚本，沿 tools/generate_map.gd CLI 先例）：给定模板 + seed，输出**五视图**规范序摘要——区域（分区/主导地貌/权重）、骨架（山系/宽谷/盆地/孤峰）、高度（连续场统计 + 量化档分布）、坡度、可用连通片——各视图可 diff（沿「阶段输出规范序摘要」纪律）。② **固定对照**（提案 :237）：同 seed 同相机三对照截图留档——旧版（双噪声）/ 分区骨架版（S3 起）/ 分区骨架 + 侵蚀版（S4 起），落 docs/evidence/m1a/（沿 render_probe_* 命名与「渲染器标识取运行时值」S-1 口径）。③ 偏好候选临时标注（提案 :239）：预览中标出「山地偏好候选」「平原偏好候选」并**在输出中说明临时规则**——正式化归 S6，本阶段只留标注通道 |
| **关键文件** | 新建 tools/region_preview.gd（命名落卡时定；沿 tools/generate_map.gd 参数化先例）；tools/render_probe.gd（对照帧扩展点——新 CHECK 沿既有编号规则避让）；tools/seed_bank.gd（批跑与样图落盘先例）；scripts/ui/map_view.gd（构建入口，只读复用）；scenes/m1a_sandbox.tscn（沙盒先例）；docs/evidence/m1a/（留档目录） |
| **验收** | 五视图摘要同 seed 确定性（两次运行逐字节一致）；三对照截图落档且统计 txt 含实际渲染器；预览工具不进 headless 套件、不改任何渲染代码（探针纪律）；S3 未落地前区域/骨架视图对双噪声路线输出「无区域数据」显式态（不产伪字段——沿「关闭一个尚未实现能力不产生伪字段」锚） |
| **非目标** | 不做交互式编辑器/改图能力（mapgen4「先要素、用户改、重算下游」留 M3）；不做植被/装饰/建筑表现；预览不是验收替代（区域验收机器面在 S5、人工面在 S7） |

---

## §5 S3 分区骨架（regions 模板路线核心）

| 项 | 内容 |
|---|---|
| **范围** | ① `WorldTemplate` 扩 regions 参数组 + geography 路线选择（§2.1）；地貌分类阈值进模板（§10 默认答案②）。② regions 路线三步落码（每步纯函数 + 独立诊断）：**宏观分区**（少量空间连贯区域 + 邻接表；区域数随地图尺寸与最小可用区域面积确定——小图不机械套用大图数量，提案 :63）、**区域内部骨架**（群山主导区 = 有方向主山系/支脉/宽谷/盆地/山口；平原主导区 = 大片低起伏 + 缓丘/河谷；首期仅两类主导 + 过渡带，提案 :65-71）、**连续高度与权重混合**（区域边界连续权重场、权重归一化；提案 :86-98 设计表达式的前三项——基础大陆高度 + 区域权重 × 骨架 + 振幅受限细节；**孤峰地标项本阶段留空实现 = 恒零贡献，零孤峰合法态**，S4 填）。③ 主山系终止/降低/延伸规则与宽谷出口过渡（提案 :96——防边界被切断的山脊）。④ 新实体进 world_data.gd（§2.1）+ 新通道 region/mountain（§2.3）。⑤ GENERATOR_VERSION+1（§2.2） |
| **关键文件** | scripts/content/world_pipeline.gd（geography 阶段 :542 起双路线分派；GENERATOR_VERSION :58；STAGE_VERSIONS :101；CHANNELS/偏移 :106-113；generate_legacy :178 不动）；scripts/core/data/world_template.gd（参数组扩容；make_legacy :146 钉死双噪声）；scripts/core/data/world_data.gd（TerrainRegion/TerrainSkeleton 适配实体，缺键合法）；resources/world/templates/world_template_default.tres 与 world_template_legacy.tres（regions 参数组落位/钉死）；scripts/content/map_generator.gd（兼容导出面）；tests/test_world_pipeline.gd（legacy oracle + 新路线确定性/通道独立性锚）；tests/test_world_data.gd（新实体序列化往返 + 旧图零迁移锚）；tools/region_preview.gd（S2 新建件——视图消费方） |
| **验收** | legacy 路线：generate_legacy 同 seed 逐格输出与现基线**字节级一致**（拍板③，既有锚不放宽）；regions 路线：同 seed 同模板同引擎构建 world_digest 一致（跑 3 次，沿 WORLD-01 锚）；区域数/邻接对称性/权重归一化（有限非负和 1）有独立拼装 oracle 测试；模板不选 regions = 与双噪声路线同输出（并列路线的正交性锚）；改 region 通道不影响 hydrology 输出摘要（通道隔离锚）；过渡带无分区编号导致的高度断缝（提案验收表「边界过渡」:271 的连续层前置检查）；S2 五视图中区域/骨架两视图出数 |
| **非目标** | 不做孤峰与侵蚀（S4）；不做区域验收机器面（S5）；不做海域开口/高原/赤岩台地/岛链（提案 :71 明示后续扩展）；不做派系适宜度（S6）；不改水系/聚落/道路阶段（regions 只换 geography 上游，下游沿既有九阶段合同消费） |

---

## §6 S4 孤峰侵蚀

| 项 | 内容 |
|---|---|
| **范围** | ① **孤峰对象**（提案 :74-82）：显式中心/影响半径/峰高/形状；约束 = 与其他孤峰、主山系、起始落点的最小间距 + 影响面积预算（起调 ≤ 有效平原面积 5%，未验证起调值）；数量由有效平原面积/最小间距/构图位置决定，**小图可零座**；主山系内部突出峰不自动计作孤峰（按对象归属判定）。② **孤峰几何首版 = 圆锥/岩峰轮廓**（§10 默认答案④）。③ **选择性侵蚀**（提案 :100-109）：按区域类型分强度（群山坡面沟壑明显 / 宽谷盆地受限 / 平原弱侵蚀或关闭 / 过渡带与海岸单独控制）；侵蚀后重新检查起伏/坡度/连通性，破坏区域约束时**按确定性规则减弱局部侵蚀或回退局部结果，不换 seed 掩盖**。④ 孤峰地标项接入 S3 高度表达式第四项；新通道 isolated_peak/erosion（§2.3）；侵蚀作为 geography→quantize 间新阶段进 STAGE_VERSIONS（§2.1）。⑤ **侵蚀只承担外观细化，不提供权威河流**（提案 :102——水系仍走 hydrology 阶段 WORLD-02 河口反向生长，不受侵蚀通道影响） |
| **关键文件** | scripts/content/world_pipeline.gd（新阶段 + 通道 + 高度表达式第四项）；scripts/core/data/world_data.gd（TerrainSkeleton.isolated_peaks 实体）；tests/test_world_pipeline.gd（确定性/通道隔离/回退锚）；tests/test_river_network_generator.gd（hydrology 输出不受侵蚀通道影响的对账面——沿其「只读不改图」锚家族扩）；tools/render_probe.gd（侵蚀差分 CHECK 预留位）；tools/region_preview.gd（S2 新建件——孤峰视图消费） |
| **验收** | 孤峰逐峰检查违规数为零（间距/预算/避让——提案验收表「孤峰稀疏性」:270），可因地图过小生成零座（零孤峰 = 合法态锚）；侵蚀关闭 = 与 S3 输出逐格一致（回退锚）；侵蚀后区域约束复查触发时有确定性减弱/回退记录（诊断通道留痕，不换 seed）；同 seed 确定性（world_digest 一致 3 次）；hydrology 阶段输出摘要不受 erosion 通道影响（通道隔离锚） |
| **非目标** | 不做遗迹/资源/战略地标关联（提案 :287 后续再议）；不做真实地质演化；宽河多边列表/汇流等第二版项不提前；不做侵蚀参数寻优（数值 = 未验证起调值，S5/S7 观测后调） |

---

## §7 S5 区域验收 + 银行

| 项 | 内容 |
|---|---|
| **范围** | ① `WorldValidator` 扩**区域验收面**：region_metrics（地貌占比——**按区域核心范围统计、过渡带单独统计**（提案 :123）、最大可用连通片、谷地/山口与对外通路、孤峰影响面积）+ 新错误码/不合格区域编号输出（沿 {code, cell_ids, explanation} 结构化错误先例）。验收表机器面落卡：区域主导性/群山结构/平原完整性/孤峰稀疏性/边界过渡/山地可用性（提案 :265-272）。② **seed 银行扩组**：regions 模板组 × **小/中/大三档**（§10 默认答案①——现状银行两组 default_terraces@24x16 / @60x40，S5 补第三档大图组，档值未验证起调值）；固定 seed 清单沿「发布银行/探索性分开统计 + smoke 提交级份额」既定结构。③ 失败样例入库（FAILED_FIXTURE_DIR/world/ 先例）+ 银行样图渲染证据（render_probe --map 入口）。④ **可控修复**（提案 :246-247、:160-165）：regions 路线的修复动作接入 generate_validated 有限修复循环（最多 4 attempt、只动非 locked、每次后全量重验——WORLD-04 既定合同，只加动作不改循环） |
| **关键文件** | scripts/content/world_validator.gd（区域指标 + 错误码）；tools/seed_bank.gd（BANK 表扩组 + 三档）；scripts/content/map_io.gd（FAILED_FIXTURE_DIR 通道）；resources/maps/bank/（样图落位）；tests/test_world_validator.gd（区域验收 fixture 锚）；tests/test_world_pipeline.gd（修复循环回归）；tools/render_probe.gd（样图证据） |
| **验收** | 区域指标 fixture 断言（占比范围/连通片/通路——**阈值来自模板配置**，数据层只校验「有配置才判」沿 ROAD-01 先例）；不合格输出含区域编号（提案 :267「输出不合格区域编号」）；银行扩组批跑报告生成（质量看报告不设门——拍板⑤，沿 seed_bank 头注「退出码只反映跑完」）；修复不动 locked（锁定区修复前后逐位一致锚）；银行 seed 重跑 world_digest 一致（3 次） |
| **非目标** | 性能指标不设门（生成耗时只留档——S7）；不做派系候选验收（S6）；修复不做无限重试/换主 seed（提案 :164 红线）；20 seed/三档为提案建议实验值（未验证起调值），不是达标承诺 |

---

## §8 S6 派系适宜度

> **第一刀完成登记（2026-10-13，施工批次）**：本阶段已按「只做适宜度与候选」
> 交付前四件——① 适宜度 profile 资源化（`SuitabilityProfile` Resource +
> `resources/world/suitability/` 两内置 .tres：mountain_preferring /
> plain_preferring，提案 :144/:145 矮人/人类示例的解耦读法）；② 两阶段选址
> 纯函数（`SuitabilityGenerator`：硬筛选拒绝具名 AREA_BELOW_MIN /
> NO_REGION_ACCESS / NO_WATER_IN_RANGE → 评分（地貌偏好 + 可扩展空间 + 水）
> → 间距贪心与上限，产出 `WorldData.faction_suitability` 事实
> {profile_id, candidate_sites, qualified_count, rejection_reasons}，缺键合法
> SCHEMA_VERSION=1 维持）；③ 预览 suitability 视图（TerrainViewData 第六视图
> ——提案 :239 两类偏好候选标注的正式版，S2 临时标注通道就此取代）；④
> GENERATOR_VERSION v8 + suitability v1 阶段 + 模板 suitability 组（regions
> 模板启用、default/legacy 钉死关闭 = 零漂移）。**剩余两件 = 后续批次非目标**：
> 范围⑤ 聚落阶段 profile 接线（SettlementGenerator 适居度公式不动，候选表
> 暂无下游消费者——本刀只产事实）与范围④ 开局保证模式（配置入口亦未开——
> 「开启须进 config_hash」的要求随该批次落字）。
>
> **考古勘误（2026-10-13，独立复审处置——提交消息与内容不符，以本登记为准）**：
> 上方「第一刀完成登记」的**代码载体与相关提交消息的自称不符**，后续考古**不得
> 以那两枚提交消息为交付证据**（本仓以提交消息作交付登记的证据链，故在此显式
> 勘误；沿 PLAN-ALIGN 取代注先例——已推送历史不重写，文档侧更正）：
> ① **登记先行于代码**：本登记文本随 4c8cce3（17:11，自称 S0「docs-only 不写
>   代码」）入库，而 S6 代码 19:22/20:04 才提交——登记落字时指向的是**未提交的
>   工作树状态**（a31e7ec 消息中「未提交 S6 件」一语可互证），按提交序考古会
>   误读 4c8cce3 为「代码已在树」。
> ② **a31e7ec（19:22，自称「S4 交付物核验……均已随 87a1fcd 在树」）实携行为
>   变更**：GENERATOR_VERSION 7→9（含 v9「锥体不移动归一化锚点」复审修——
>   terrain_composition.gd/world_pipeline.gd 及其测试）**与 suitability 阶段的
>   全部管线接线**（STAGES/通道/模板消费面），消息标题均未登记；且该提交树
>   **不自洽**——world_pipeline.gd 已 preload
>   `res://scripts/content/suitability_generator.gd` 而该文件此提交尚不存在
>   （干净检出即解析失败），故其消息中「全量 32 文件 458/0 复跑」只能是对脏
>   工作树的运行，不是对该提交树的复验。**不能把 a31e7ec 读作零改动复验**。
> ③ **d165379（20:04，自称「S5 交付物核验……均已随 c38d910 在树」）实携 S6
>   第一刀全部新件**（suitability_generator.gd / suitability_profile.gd /
>   resources/world/suitability/ 两 .tres / tests/test_world_suitability.gd /
>   world_data·world_template·三模板·预览工具改动），消息仅在括注提
>   「generator_version 7→9 为在树 v8/v9 之自然迁移」。**S6 自洽树自 d165379
>   起**；其消息所报「全量 32 文件 460/0+银行 smoke exit 0」的时点证据链
>   弱（阶段门禁当时未跑），可复核口径 = d165379 之后在干净树上的复跑（见④）。
> ④ **可复核证据（2026-10-13 复验刀，d165379 树上实跑）**：`tools/run_tests.gd`
>   全量 **32 文件 / 460 用例 / 0 失败 exit 0**（含变异自检全拦、legacy oracle
>   与通道隔离锚）；`tools/seed_bank.gd mode=smoke` **exit 0**（regions 组
>   3/9，首错 REGION_DOMINANCE——S5 既有质量信号；银行样图复生成 git 零差异）；
>   suitability 视图银行样图 map 模式真渲染冒烟 **Forward+ exit 0**（两 profile
>   各 4 候选 / 1122 合格、拒绝计数具名；证据
>   docs/evidence/t6/terrain_debug_*regions_mountains_60x40_sample*）。S6 交付
>   成立与否以本条与本登记为准，不以 a31e7ec/d165379 消息为准。

| 项 | 内容 |
|---|---|
| **范围** | ① **偏好配置与派系名解耦**（提案 :146、:254）：适宜度 profile 配置（profile_id + 偏好项——地貌偏好/可扩展空间/水资源/资源条件/战略位置），**不把派系名称写进基础地貌生成代码**（提案红线 :146）；配置进模板/独立 Resource（生成器配置不进世界事实——草案 §1.2 边界）。② **两阶段选址**（提案 :150-156）：硬筛选（面积/通达/水/资源必需项全合格才入候选集）→ 适宜度评分 → 间距规则共同决定落点——「高风格分不得覆盖不可用条件」。③ **FactionSuitability 数据面**：profile_id/candidate_sites/rejection_reasons（world_data.gd 扩容，缺键合法）。④ **开局保证模式 = 配置入口默认关**（§10 默认答案③）：开启须进 config_hash（提案 :158「必须进入配置哈希，不能悄悄修改默认地形」）；本批次不实现保证模式的修复循环（拓宽谷地/补山口等留后）。⑤ 与现有 settlement 阶段衔接：适居度筛选扩为 profile 驱动（现 −(h−50)/5 高程带 + 河/海岸加成结构保留为默认 profile），势力归属/出生区锚（WORLD-03）不重开 |
| **关键文件** | scripts/content/settlement_generator.gd（适居度 → profile 驱动扩容）；scripts/core/data/world_data.gd（FactionSuitability）；scripts/core/data/world_template.gd（配置入口 + config_hash 面）；tests/test_world_settlement.gd（现锚不放宽 + 新锚）；tests/test_world_pipeline.gd（随机隔离锚） |
| **验收** | 合格候选全部满足硬条件、无候选输出原因不返回伪合格（提案 :273）；**改派系显示/名单配置不改基础地形与水系校验值**（提案「随机隔离」:276——随机隔离锚）；开局保证默认关 = 行为与 S5 完全一致（关态回退锚）；候选间距规则有独立 oracle；rejection_reasons 落诊断可枚举 |
| **非目标** | 不做派系数值/兵种/经济/战争（提案非目标 + M3 门）；不预先永久划区（「矮人偏山」只是适合度不是归属）；不做开局保证修复循环；最小可用面积/候选数量/资源需求的最终数值仍待玩法确认——本批只落配置位不杜撰平衡值（提案 :166） |

---

## §9 S7 视觉验收

| 项 | 内容 |
|---|---|
| **范围** | ① **结构风格人工评审**（提案 :278）：关闭颜色/派系/装饰，统一灰度 + 统一相机逐 seed 观察——能否辨认群山、宽谷、平原、孤峰；记录未通过 seed 与具体问题（「不能用颜色漂亮代替地形结构成立」）。② **性能基线留档**（提案 :280）：生成时间/峰值内存/各阶段开销（诊断通道），**先基线后预算、本批不设阈值**（拍板⑤ + T2-T5 §8.4 口径）。③ 银行样图渲染证据补全（三档各组）+ 评审结论落字（docs/evidence/m1a/ 留档 + 04 §M1a+ 完成登记，沿 LAND-S「目检结论 + 拍板记录」先例） |
| **关键文件** | tools/render_probe.gd（灰度帧 + 银行样图 --map 入口）；tools/seed_bank.gd（三档样图源）；resources/terrain/styles/terrain_style_slots_default.tres（灰度对照 style 的基底）；docs/evidence/m1a/（留档）；docs/04-tasks-m1.md（完成登记位） |
| **验收** | 全部银行 seed（三档各组 smoke 份额起步）灰度图 + 统计落档，渲染器标注取运行时值；未通过 seed 有具体问题描述（不接受「不好看」级笼统结论）；性能数字档案含各阶段开销分解；评审结论与后续调参项登记进 04（沿 LAND-S 先例：结论 + 待拍默认值） |
| **非目标** | 不做美术资产/植被/建筑/材质强化（提案 P1「表现扩展」不属本批）；识图率不预编目标（沿 §8.4「先收集误判再调视觉」）；不做性能优化与阈值设定（基线之后另批） |

---

## §10 提案 §尚待确认四项的本批次默认答案（全部「未验证起调值」）

提案 §尚待确认（:282-287）四项按主创授权在本计划给默认答案如下。**「未验证
起调值」= 不是已验证结果、不是最终平衡承诺**；翻案须明说（沿 04 §M1a+ 拍板
流程），调参不构成合同变更（走模板/生成器版本管理）：

| 项 | 提案原文关切（负责人/阻塞点） | 本批次默认答案 |
|---|---|---|
| **地图尺度** | 不同尺寸格数与最低有效区域大小（项目负责人，接入前阻塞，:284） | **沿 seed 银行三档**：小/中/大三档（现状银行两组 default_terraces@24x16 与 @60x40——tools/seed_bank.gd BANK 表，S5 补第三档大图组）。三档具体格数与最低有效区域面积 = 未验证起调值，S5 落组时按「区域数随地图尺寸与最小可用区域面积确定」（提案 :63）校准 |
| **地貌分类阈值** | 坡度/起伏/可用地块的分类阈值需统一（地形实现负责人，自动验收前阻塞，:285） | **首版自定并进模板**：分类阈值作为 WorldTemplate regions 参数组字段（生成器配置不进世界事实——草案 §1.2 边界）；数值 = 未验证起调值，变更走 GENERATOR_VERSION/模板版本；提案「首期调参起点」（:127-133：群山核心 60%~80%、平原核心 70%~90%、孤峰预算 5%、过渡宽度 10%~20%）同为起调参考非承诺——「山地占比不足保证群山风格」仍需主山系/峰簇结构检查（提案 :134 自警） |
| **派系开局规则** | 是否保证每局都有矮人与人类，及候选面积/数量/间距/资源需求（玩法负责人，派系接入前阻塞，:286） | **开局保证默认关**：默认走「地形先成形、派系后选址」，无合格候选返回明确失败原因（不放宽硬条件后仍称合格）；开局保证模式只留配置入口，开启须进 config_hash（S6 范围④）。候选面积/数量/间距/资源需求最终数值仍待玩法确认，本批只落配置位——全部未验证起调值 |
| **孤峰风格** | 首期可只做少量圆锥/岩峰轮廓，后续再决定是否关联遗迹/资源/战略地标（美术与玩法负责人，非阻塞，:287） | **首版做圆锥/岩峰轮廓**：少量显式轮廓地标（S4 范围②），形态与主山系区分（提案 :120 软目标）；轮廓参数（峰高/半径/坡度剖面）= 未验证起调值；地标关联后续再议 |

---

## §11 边界重申（照抄既有拍板与提案红线，本文不重开）

- **M1b 不阻塞**（拍板⑥+①沿袭）：本批 S1–S7 属地形表现/生成线切片，只可顺延；
  每阶段交付保持「删 scripts/ui/** 后 tests 全绿」（ADR-2）。
- **M3 门不越界**：地形玩法规则（河流禁渡/涉渡、桥作用、道路成本、坡地限制、
  跨河防守 buff 数值）、TraversalPolicy、性能指标解冻——不在本批范围；本批
  「T6」与规则深化无关（头部命名澄清）。
- **提案红线整批有效**：修复耗尽返回失败报告不无限重试不换主 seed（:164）；
  「标为群山」本身不能算生成了群山（:123）；视觉沟槽不能充当水系验收（:274）；
  派系名单变化不得改变基础高度（:140）。
- **不动清单**：temp_reports/、resources/maps/generated/、门禁判定口径、
  legacy 路线逐格输出。

---

*本文为 S0 产物（docs-only）：引用行号均为 2026-10-13 静态实读核对（提案全文、
T2-T5 方案、world_pipeline.gd/world_template.gd/world_data.gd/run_tests.gd/
seed_bank.gd/gate_all.gd/render_probe.gd 头注与常量区、外审两份、04 §M1a+）；
未执行测试/探针（本阶段不写代码）。新建路径（tools/region_preview.gd 等）均为
后续阶段拟建项，已在正文以「新建/拟建」标明——除此之外引用路径均已逐一验证
存在。*

*修订注（2026-10-13，S6 复验刀）：本文非纯 S0 快照——§8「第一刀完成登记」与
「考古勘误」为 S6 施工/复审批次后补（交付载体与提交消息的出入见该勘误块），
引用行号系各批次落字时点核对。*
