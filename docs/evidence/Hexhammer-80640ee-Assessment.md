# Hexhammer 最新修改评估

基线：`80640ee23e0c9db6ab0968ea7ca0488223aa62dd`，对比上一轮 `8c54da0`。本轮新增内容已从颜色过渡扩展到阶地、水系、道路桥与初始世界生成，不再是仅有规划；但完整可交互地形世界尚不宜无条件验收。

本报告结合只读源码审查、Claude Fable 5.1 独立评审和主审引擎实验。未修改或推送仓库；调试脚本、超时对照和补充组合渲染都在独立审查副本中执行，不算项目修复。

## 总体判断

**方向和实现推进都有明显进步，主要短板已转为跨层集成与验收强度。** 建议保留当前架构，停止扩大功能范围，先完成“生成 → 保存 → 加载 → 表现 → 拾取 → 校验”的一条可交互闭环。

最新登记确实包含 T2 的阶地/真崖/格线、T3 格边水系、T4 道路桥，以及 T5 聚落、初始势力、路网和 seed 银行，见[任务登记](https://github.com/jiezhou0319/hexhammer/blob/80640ee/docs/04-tasks-m1.md)。但“已写出代码”和“完整体验已验收”应分开：生成样图水面几乎被遮挡，桥的实际拾取接线遗漏，且原版门禁在本环境中仍会超时。

这里的高优先级问题指阻断相应交付验收，不是已证实的安全漏洞，也不表示整个项目不能启动。原有场景、许多纯逻辑用例和生成银行已经能正常运行。

## 代码质量

### 值得保留的部分

- **分层与合同**：地形、水、路分别构建，表现配置与几何 profile 分开；世界生成阶段显式传递状态，避免隐藏全局随机源，见[MapView](https://github.com/jiezhou0319/hexhammer/blob/80640ee/scripts/ui/map_view.gd)与[WorldPipeline](https://github.com/jiezhou0319/hexhammer/blob/80640ee/scripts/content/world_pipeline.gd)。
- **真正的阶段实现**：聚落、势力与道路已从占位阶段转为实际调用，自动道路在聚落之后生成，解决了上一轮阶段倒置，见[管线阶段分派](https://github.com/jiezhou0319/hexhammer/blob/80640ee/scripts/content/world_pipeline.gd#L433-L453)。
- **故障隔离**：单文件子进程、超时、故障样本，以及统一入口已经存在；杀进程后不再查询其退出码，见[runner](https://github.com/jiezhou0319/hexhammer/blob/80640ee/tools/run_tests.gd#L147-L165)。
- **证据口径**：探针改用实际运行时渲染器，区分工程配置与实际后端，并新增 BLEND、格线、水面、道路及阶地检查，见[渲染探针](https://github.com/jiezhou0319/hexhammer/blob/80640ee/tools/render_probe.gd)。
- **颜色能力边界**：BLEND 遇到带 albedo_texture 的库会明确拒绝，而不是静默丢贴图；这修正了上一轮问题，见[TerrainStyle 校验](https://github.com/jiezhou0319/hexhammer/blob/80640ee/scripts/core/data/terrain_style.gd#L152-L168)。

### 维护风险

当前维护压力不在基础 hex 数学，而在越来越大的世界合同和跨层接线。WorldData 约 1550 行、WorldPipeline 约 891 行、地形构建器约 1205 行；这些长度本身不是缺陷，但数据记录、编解码、拓扑查询、校验与修复策略集中，容易出现“各模块都正确、组合却漏接”的问题。

建议在完成闭环后做小步拆分，而不是现在推倒重构。优先抽出共享的拓扑索引、世界编解码与结构校验；保持 API 和已有不变量测试，避免因为文件拆分又改变世界事实或面序。

保留确定性与失败诊断的设计，但要让校验器尽量独立于生成器。默认银行全过只能证明这些样本满足当前校验，不能代替更广的种子探索、恶意数据输入和实际交互验证。

## 内容和实际完成情况

当前可准确描述为“初始地形世界核心能力已落码”。不能再说河流道路完全没有实现，也不能直接说完整游戏世界已完成。

| 内容 | 实现情况与验收边界 |
|---|---|
| 阶地、真崖、格线 | 有实际几何和测试，探针有相应证据；原 M1a 沙盒尚未默认接入新 profile，见[任务登记](https://github.com/jiezhou0319/hexhammer/blob/80640ee/docs/04-tasks-m1.md)。 |
| 手工格边水系 | 河床、水面、岸线、河口已有实现，固定图水面实测明显可见；自动生成水体与表现高度合同仍不一致，见[探针记录与阈值](https://github.com/jiezhou0319/hexhammer/blob/80640ee/tools/render_probe.gd#L118-L135)。 |
| 道路与桥 | 几何、桥认领和桥碰撞已实现；生产 MapPicker 没有注册桥碰撞面表，见[桥挂载](https://github.com/jiezhou0319/hexhammer/blob/80640ee/scripts/ui/map_view.gd#L197-L212)及[拾取登记](https://github.com/jiezhou0319/hexhammer/blob/80640ee/scripts/ui/map_picker.gd#L63-L84)。 |
| 聚落、出生与资源点 | 已进入生成阶段；是初始点位和 footprint 能力，不应理解成资源产出、建筑、征兵和经济系统已完成，见[WORLD-03 登记](https://github.com/jiezhou0319/hexhammer/blob/80640ee/docs/04-tasks-m1.md#L426-L434)。 |
| 初始势力与国界 | owner 和跳变边数据已就绪；presentation 仍显式跳过，国界线 mesh 尚待交付，见[阶段分派](https://github.com/jiezhou0319/hexhammer/blob/80640ee/scripts/content/world_pipeline.gd#L446-L453)。 |
| 自动世界生成 | 管线、模板、有限修复、路网和 seed 银行都有代码；默认固定银行有限，不能由其全过外推全部配置都稳定，见[任务登记](https://github.com/jiezhou0319/hexhammer/blob/80640ee/docs/04-tasks-m1.md#L433-L448)。 |
| 可交互完整预览 | 原沙盒仍调用旧 build，未传 world/profile；工具验证能力领先于默认交互入口，见[MapView 默认参数](https://github.com/jiezhou0319/hexhammer/blob/80640ee/scripts/ui/map_view.gd#L41-L57)。 |

补充组合截图展示了默认 BLEND、几何 profile 与银行世界一起构建的结果。图中的蓝色区域仍能由旧地形色块表示水域；“独立水面层被遮挡”不等于“地图上完全看不到蓝色水域”，二者不可混淆。

从这张审查截图看，棋盘式阶地与道路轮廓已经有辨识度，但当前仍更像技术验证配色，而非完整的世界美术。黄色岸带与灰色地块的视觉权重较高，细河段、聚落及势力信息没有形成同等清晰的信息层级；这属于表现完善建议，不应反过来判定底层生成逻辑未实现。先接通可交互预览和水面，再围绕远景识图、近景岸线与内容点位标记逐项改善，会比现在重做整套地形架构更稳妥。

## 本轮独立验证

以下为本次 Godot 4.7.2、Linux 审查环境的实验记录。真实渲染使用 Compatibility、Mesa llvmpipe 软件渲染；本轮不包含 Forward+、目标 GPU、帧率或完整操作手感验收。

| 检查 | 原版结果 | 解释 |
|---|---|---|
| 首次导入 | exit 0 | 新工作树导入成功。 |
| 正常 runner | 29 文件 / 367 用例 / 1 失败，exit 1 | `test_world_pipeline.gd` 超过固定 20000ms，17 个用例未能完成汇总。 |
| 统一入口 gate_all | exit 1 | 再次被同一超时阻止；导入与三个场景通过，图形步骤明确未请求。 |
| world_pipeline 单文件直跑 | 17 用例 / 0 失败，exit 0 | 本次直跑约 24.44 秒，不应误称为逻辑断言失败。 |
| 临时副本将单文件预算改为 60 秒 | 29 文件 / 384 用例 / 0 失败，exit 0 | 仅验证预算失配，不算原版门禁已通过；故障 hang 仍按 3 秒拦截。 |
| 拾取 / 相机 / 高亮场景 | 11 / 11 / 31 项通过，各 exit 0 | 拾取小场景不等于生产 MapPicker 的完整集成。 |
| full seed 银行，strict=true | 11 通过 / 0 失败，11 次首过，exit 0 | 只覆盖当前 60×40 六个与 24×16 五个 seed。 |
| Fable 扩展 seed 扫描 | 24×16 的 seed 1–80：78 首过、2 失败；60×40 的 seed 1–60：60 首过 | 有限样本统计，不是普遍合格率；小图失败包括可连接却误报和真正陆块分离两类。 |
| 固定图原版渲染探针 | 8/8，exit 0 | 水面差分 14657px；道路/桥面差分 640px。 |
| 60×40 银行样图原版探针 | 8/8，exit 0 | 水面差分仅 2px，银行阈值为 0；不能据此认定水面有效可见。 |
| 补充组合渲染 | 构建与探针完成，exit 0 | 同时使用 BLEND、默认 profile 与 world，水层差分仍仅 4px。 |
| 生产桥拾取回归脚本 | exit 1，缺陷复现 | 原始射线命中桥，MapPicker 返回 null。 |

故障自检中的预期 SCRIPT ERROR/FAIL 行不是正常测试失败。临时增加预算后的 384/0，也不能覆盖原版统一入口实际 exit 1 的事实。

## 必须优先收尾的问题

### 高优先级：路网要求所有聚落对可达，错误地强于连成树的合同

Fable 在默认模板、24×16、seed 50 复现：三聚落的候选连接成本分别为 109、43、INF。前两条已经足够形成最小生成树，但代码在 Kruskal 之前遇到任一 INF 就直接返回 `ROAD_NETWORK_DISCONNECTED`，见[提前失败分支](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/road_network_generator.gd#L126-L167)。主审独立复跑诊断，确认两个有效连接存在，而且先落第一条路后第二条仍可达。

这是默认参数下特定种子可触发的算法缺陷，不是每张默认地图都失败。应跳过不可达的候选对，先对可达图求生成树，只有最终不能覆盖所有必需聚落时才报告断连；不要把“全部聚落连通”提高为“每一对都必须有独立可用直连路径”。

### 中优先级：修复动作空转与数据校验合同缺口

Fable 的 seed 50 和 59 均连续四次产生相同失败；其中 seed 59 是真正的陆块分离，却仍只重试道路通道，不能改变聚落所在陆块，见[修复动作选择](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/world_pipeline.gd#L263-L316)。建议返回结构化失败原因，区分道路偏好、禁入面、陆块分离和河流阻挡，再选择重新选址或重连，并检测无变化重试。

独立反例还证实：河流校验接受跨 reach 角点相接及乱序边链；道路连通校验会将经普通路口相接的合法网络误判为断路；模板放行的 `max_road_delta=-1`、`resource_budget=0` 与生成器含义不一致。它们主要涉及手工输入或边界配置，不应说成默认生成每次都会失败；详细复现、源码链接和测试建议见随附 Fable 报告。

### 高优先级：桥在实际拾取链路中命中后变成 miss

MapView 创建 DeckCollision 并将其放到地形拾取层，但 MapPicker.setup 只注册 terrain chunks 的 body ID 与 face_table。命中桥后查不到面表，解析结果变为 null，见[桥碰撞创建](https://github.com/jiezhou0319/hexhammer/blob/80640ee/scripts/ui/map_view.gd#L197-L212)与[MapPicker 登记和命中解析](https://github.com/jiezhou0319/hexhammer/blob/80640ee/scripts/ui/map_picker.gd#L63-L116)。

使用入库固定图与实际 MapView→MapPicker 路径，主审得到：

```text
BUILD=true
PICKER_SETUP=true
CROSSINGS=1 DECK_BODIES=1
BANKS=(22,5)/(23,5)
RAW_HIT=DeckCollision_c20_r0  FACE=5  y=1.060001
PICKER_REGISTERED_HIT=false
PICKER_RESULT=null
BRIDGE_MAPPING_DEFECT=true
```

建议提供统一碰撞注册合同：由视图输出 body 与 face_table 的配对，picker 登记所有允许命中的表。明确谁创建、谁删除桥体，避免修复时重复创建或清理遗漏；不能简单关闭桥碰撞掩盖接线问题。

新增集成测试必须走真实 MapView 和 MapPicker，包含桥中段、两岸、根节点平移，以及重建后旧体移除。现有小场景独立登记了桥面表，因此能通过而没有发现这处生产接线遗漏。

### 高优先级：生成世界的独立水面被地形遮住，验收阈值退化

默认银行样图中水体 level 为 0，水面公式是 `(level−0.5)×step`，而水体成员格地形顶面仍为 0；本轮原版开关水层仅产生 2px 差分，补充组合渲染为 4px。这一问题在源码注释中已有登记，却通过将银行水面阈值降为 0 放行，见[探针 L125–135](https://github.com/jiezhou0319/hexhammer/blob/80640ee/tools/render_probe.gd#L125-L135)。

这不是要求恢复硬件性能指标，而是基础表现正确性。应统一水位、成员格底面与河床的垂直协议，确保水面处于可见的合法区间；不要靠关闭深度测试，也不要把任意噪声像素作为验收依据。

建议补默认生成模板的近景水体/河口/河段检查，使用已知水域 ROI 与开关差分，并将“节点存在”和“水面可见”分成两项。固定图 authored 水位能显示，不能替代自动生成数据的验证。

### 中优先级：门禁超时预算与新增整世界测试不匹配

runner 保留单文件 20 秒上限，但本次 world_pipeline 单文件正常完成需约 24.44 秒；原版 runner 和 gate_all 均因此退出 1，见[固定预算](https://github.com/jiezhou0319/hexhammer/blob/80640ee/tools/run_tests.gd#L36-L42)。临时改为 60 秒后 384 个断言用例全部通过，证明这次失败不能简单归因于功能正确性。

建议将预算配置化，并拆分轻量单测与整世界回归。缓存同配置的纯测试 fixture、减少不必要的重复生成；仍保留硬超时与短故障样本，不采用无期限等待。

### 完成范围：还缺一条默认可交互的完整入口

WorldPipeline 的 presentation 仍显式跳过，国界线 mesh 尚未交付；默认交互沙盒也未统一加载 world、style 和 profile，见[表现阶段](https://github.com/jiezhou0319/hexhammer/blob/80640ee/scripts/content/world_pipeline.gd#L450-L453)。这应记录为集成和表现待交付，而不是说聚落/势力逻辑没有实现。

建议增加独立 world preview，不必破坏旧基线沙盒。至少能切 seed/模板，加载保存后的世界，看到聚落/出生/资源标记与 owner/国界，并在地形、河岸和桥上进行真实拾取。

## 测试门禁评价

门禁比前轮明显更成熟，但仍属于“组件测试强于端到端验收”。最具体的证据是：11 项拾取小场景通过，却漏掉实际 picker 桥面登记；银行探针 8/8，却允许水层仅贡献 2 个像素。

另外，统一入口并未包含 seed 银行，默认 headless 模式也明确不跑图形探针，见[gate_all](https://github.com/jiezhou0319/hexhammer/blob/80640ee/tools/gate_all.gd)。建议把验收分层，避免用户只看到 GATE OK 就误认完整世界已验收：

- **组件层**：纯逻辑、几何合同、编解码与故障自检。
- **集成层**：真实 View/Picker、加载重建、各表现层组合。
- **内容层**：发布 seed 银行与另行记录的探索 seed；不把 11 个固定 seed 外推成普遍合格率。
- **视觉层**：实际后端、合成总景和关键局部 ROI；未验证必须独立标识。

源码还保留 HDR 输入被量化钳制、alpha/导管语义由调用方保证的宽松边界。它们目前是较低优先级合同与诊断问题，不应与已复现的桥面 miss 混为同一级别。

## 建议的下一步

建议当前进入“闭环收尾批”，不新增汇流、生态、WFC 或更多世界生成算法。先修路网连通判定与无效重试，同时完成水面高度合同和桥面注册；随后补数据校验合同、测试预算与真实集成回归，最后接完整 world preview，再扩大种子和参数覆盖。

重新验收时要求：原版配置门禁能在目标环境稳定完成，默认生成世界水面明显可见，桥点击正确归两岸，保存重载后结果不变，完整预览能显示初始 owner 与内容点位。达成这些后，才更适合表述为“地形世界初版闭环完成”，随后再衔接 RTwP 内核与规则。
