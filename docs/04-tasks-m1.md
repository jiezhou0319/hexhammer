# 04 · 任务拆分（M1 批次 = M1a 地形地基 + M1b 内核证伪 · 2026-10-09 重写）

> **状态：已重写（2026-10-09，随 03 v2；skirmish/WeGo 时代批次全部作废）。**
> 旧批次可复用件的去向：事件对象化→M1b-T11；存档/读档→M2；CI→M1b-T14；
> 骰子可视化→M3（将领施法线）；T9 回放已废（不做玩家回放）。
>
> 粒度标准：一条任务 = 一个明确交付，附验收。可直接变成 issue。
> **时间概念已移除（2026-10-09 主创拍板，评审 P1-4 收口）**：~~"半天/一天/两天"粒度
> 与 1.5/3/6 有效工时估时口径、周数折算~~——只拆任务、不定工期；进度以验收清单为准
> （03「范围优先级与设计债门」）。
> 标注：🟦 可并行（互不依赖）；🔒 有前置；⭐ 关键路径。

## M1a · 地形地基（详见 03 v2）

> **任务细化（2026-10-09，依据 [hexhammer-m1a-map-implementation-research.md](hexhammer-m1a-map-implementation-research.md)
> ——外部调研：Red Blob 六边形数学 / Catlike Coding 高程与分块教程 / 老李游戏学院
> godot_hex_map（Godot 4.6 MIT，静读未运行）。下列各任务内"细化"条目为该调研的
> 实施建议落字；原范围与 03 验收不变。**

**开工前三个微决策（2026-10-09 登记，同日主创拍板确认=调研推荐默认；翻案须明说
并回改本表对应测试用例，不动架构）**：
1. **悬崖样式**：默认 = **Catlike 式陡连接面**（非严格垂直墙）——几何与点击归属简单；
   垂直墙留表现层升级（需另补墙面位置与点击归属规则）。
2. **站立/高亮范围**：默认 = 棋子站**格心内顶面**、高亮只覆盖内顶面
   （斜坡连接带不站人、不高亮）。
3. **边界点击归属**：默认 = 顶面归本格；斜坡按局部 XZ **最近逻辑格心**、距离相等
   按棋盘固定 ID 决胜；悬崖归**高地侧**。

### M1a-T1 ⭐ hex 数学（零恢复重写）
- `addons/hexhammer/`：axial 坐标 / 6 邻居 / 距离 / 顶点与朝向，纯静态函数
- **细化——先定约定再写码**：pointy-top、XZ 地面 + Y 高程、方向编号 0~5 写死、
  外形 = row/column 矩形（内部算法用 axial，存储/边界用明确行列转换）；
  cube 第三轴按 `s = −q−r` 现算
- 验收：邻居/距离/边界判定单测全绿（headless）；**细化新增**：邻居反向对称、距离
  对称、坐标往返（axial↔世界）、**负坐标与 rounding**（cube rounding 须修正最大
  误差轴，不许两轴各自四舍五入——Red Blob 口径）

### M1a-T2 ⭐🔒(T1) 地图数据层
- `MapData`（运行时类；M2 落盘为 `MapDef` .tres——两名一物，03 §M2-8，评审 G7 统一）：
  尺寸 / 地形类型 / **高程（int 分层）** / 通行性；
  **修正扩展位**（`mods: Dictionary` 空字段，数值 M3 才挂）
- **细化**：数据层不持有任何场景节点；`MapDef` 留 `schema_version`；格子遍历顺序
  固定（地图摘要可比较——T9 复现验收的载体）
- 验收：60×40 生成/序列化/按 axial 存取单测；扩展位存在但不参与任何结算；
  **细化新增**：序列化往返逐格一致；地图外形与外沿边界规则（不存在邻格不得生成
  悬空连接）显式测试

### M1a-T3 ⭐🔒(T2) 平地网格渲染（先打通管线）
- 每格顶面 hex mesh 拼合 + 材质槽（类型→材质，色块起步）+ 地图场景挂载
- **细化——chunk 制而非每格一个场景节点**：SurfaceTool 起步（顶点/法线/UV/颜色
  收集），三角化正确后再议 ArrayMesh 直填；先用小图（如 10×10 chunk）打通再上
  60×40；每 chunk 按少量地形类型组织 surface，不每格一个 surface
- 验收：60×40 平地渲染流畅；换类型即换色（材质槽生效）；**细化新增**：小图阶段
  核对顶点顺序/法线/UV/相邻 chunk 接缝无错位；若用顶点色显示地形，材质须开
  `vertex_color_use_as_albedo`（默认 false）

### M1a-T4 ⭐🔒(T3) 高程分层与连续连接
- 高程差生成**悬崖面/斜坡几何**，邻格无缝拼合（Civ6 式连续联动网格）
- **细化——拆三步纯几何**：① 顶面（格心 + 六内顶点三角扇，首版平整不扰动）；
  ② 边带（等高平连 / 差一级斜坡 / 更大高差陡面——按微决策 1）；③ 角落（相邻
  三格高程组合**独立补洞**——两两边带拼合不保证角落自然封闭，Catlike §3 结构）
- **细化——归属规则防重复面**：共享边由两格稳定 ID 较小者生成；共享角以三格 ID
  为唯一 key 定单个生成者；chunk 可读邻块格子数据（chunk 边界 ≠ 地图边界）；
  接缝顶点从同一全局格心/边参数计算，不在两个 chunk 内各自扰动
- 验收：随机高程图无破面/无 z-fighting；高差处连接符合设计图示意；**细化新增：
  交汇组合测试矩阵**——0/0/0、0/0/1、0/1/1、0/1/2、0/0/2 等三格组合各 ≥1 测；
  跨 chunk 接缝与地图外沿各 1 测

### M1a-T5 ⭐🔒(T4) 拾取链路
- 屏幕射线 → 对地形 mesh 物理 raycast → 世界坐标 → axial（无平地简化）
- **细化**：射线 mask 只查地形层（棋子/高亮/装饰不得截获）；查询在物理回调内做
  （其他时机物理空间可能被锁定）；命中先转**地图根局部坐标**再转浮点 axial +
  rounding；静态碰撞用 `ConcavePolygonShape3D`——`face_index` 仅对该形状有效，
  若做 face→格子增强表须按自提交碰撞三角形顺序建映射并小场景校验
- 验收：含高程差的格子点选正确率 100%（自动用例：每格中心反投影校验）；
  **细化新增**：斜坡/悬崖/三格角落按微决策 3 的归属规则各配正反用例；地图根
  节点整体平移后拾取仍正确（局部坐标转换回归测）

### M1a-T6 🟦🔒(T4) 策略相机
- 固定俯角、平移（边缘/拖拽）/缩放/边界钳制；axial↔世界映射放 view 层辅助模块
- **细化**：边界语义二选一写死（钳"相机焦点"还是"整个可见范围"）；拖拽走固定
  参考平面/稳定锚点（防跨高程镜头跳动）；参考工程相机随缩放插值俯角的逻辑
  **不抄**（本作固定俯角）
- 验收：全图可达、不出界；缩放档位顺手（主创实操确认）；**细化新增**：最大/最小
  缩放极值、四角+中心焦点边界各有测试

### M1a-T7 🔒(T5) 高亮系统
- 每格半透明高亮 mesh；API：`highlight(cells) / clear()`，支持路径描线
- **细化**：高亮节点缓存复用、按**集合差异**切换（鼠标移动不重建地形 mesh）；
  首版贴合内顶面（微决策 2）；透明材质的深度/排序在远近缩放与相邻重叠下测试，
  不靠"关深度测试"掩盖穿山
- 验收：任意集合高亮/取消无感知延迟（为 M1b 移动范围预铺）；**细化新增**：
  hover/选择/清空/切换四态各 1 测；高亮不闪、不穿山

### M1a-T8 🟦 材质槽体系 + 美术并行验证分支
- 材质资源化（类型→材质映射表）+ **试验场景分支**：同接口即换贴图即所见
- **细化**：UV 约定现在就定（顶面/侧面映射、UV 尺寸）——否则"换贴图不改主线"
  不成立；法线硬边策略（平顶/陡壁平滑与否）显式定；边界混色/Texture2DArray/
  自定义 shader 属后续升级任务，不混入本条
- 验收：分支上换贴图/纹理直接看效果，主线代码零改动；合并路径演练一次

### M1a-T9 🟦🔒(T2) 地图来源
- 固定测试图（手工 .tres）+ 简单随机生成脚本（尺寸/类型/高程分布参数化）
- **细化——生成管线**：低频噪声（FastNoiseLite）→ 量化整数高程 → 地形分类 →
  连通性检查（不做每格独立随机）；部分 cellular 噪声输出可超 ±1，勿假定界外；
  存 seed/参数/生成器版本 + 格子表摘要（同 seed 复现限定在固定生成器与引擎配置下）；
  失败图（断路/孤岛）落盘保留作回归样例
- 验收：一键出可玩测试图；随机图种子可复现；**细化新增**：同配置同 seed 格子摘要
  逐格一致；连通性检查可跑、失败图可保存

**实施顺序与最小垂直切片（细化，2026-10-09）**：学习顺序 = Red Blob 数学六章 →
SurfaceTool 画单格/7 格 → Catlike 高程章节对照中文工程做边带+角落（核心学习关口）→
小图接拾取/相机/高亮 → chunk 与跨块测试 → 扩 60×40 → 最后随机图与换贴图实验；
**最小垂直切片 = 一个 chunk + 少量固定格 + 三档高程 + 平/坡/陡连接 + 格心可点选 +
可高亮 + 固定俯角相机**——切片通过后再扩全图，不降 60×40 终验。

**M1a 收尾**：验收清单（03）逐项跑 + `docs/retro/M1a.md` 五行复盘。

### M1a+ · 渐进式地形世界提案（2026-10-10 登记；同日主创拍板五项，见下）

> 全文见 [M1a-terrain-world-proposal.md](M1a-terrain-world-proposal.md)（外部方案，
> 对照 HEAD `825f30a` 现状写就——现状两条事实判断已核实：边带确按归属格单材质
> 绘制、生成器确有高程+湿度双通道）。本节只登记**采纳建议与第一批卡**；方案
> 不自动改写 03 已定范围——下列任何一项开工前须主创按方案文末「需要主创确认
> 的决策」清单拍板（河流拓扑/视觉风格/世界模板/玩法规则/目标硬件/排期取舍）。
> **优先级不变**：M1b 证伪关口仍按 03 证伪对冲注执行，本节卡片属"表现层短切片"
> ——只可顺延、不得阻塞 M1b-T1 开工决策。
>
> **2026-10-10 主创拍板（决策清单六项之五 + 排期主干）**：① 排期主干选
> **C——继续地形线 T2**；② 河流拓扑 = **格边河流**（[02](02-architecture.md)
> ADR-14；数据合同草案 §5/§8 转正时按格边重议）；③ 视觉风格 = **阶地棋盘感为
> 默认**——高差小走梯田/小斜坡、高差大走悬崖陡坡（**反转**提案"坡默认、阶地做
> style 开关"建议；T2 的 Must 据此定为阶地）；④ 首个世界模板 = **不造气候、
> 只有地形**（气候/生态生成阶段与 biome 相关字段从 T5 范围剔除）；⑤ 目标硬件
> 指标 = **暂不做指标要求**（性能护栏指标悬置；Forward+ 探针证据照常留档）；
> ⑥ 排期取舍 = **不考虑排期**（与 03「时间概念移除」一致）。地形玩法规则项
> 仍沿 M3 决策门（T6 前拍）。

**T0 对账（方案 T0 大部分已随外审修复闭环）**：GATE-01 统一测试入口 = 门禁 v2
（`tools/run_tests.gd` 子进程隔离 + SCRIPT ERROR 检出 + `runner_fixtures/` 变异自检，
`0f58e3a`）；几何护栏（绕序锚引擎语义/裂缝/z-fighting）与资源护栏（干净克隆全绿，
F-2 修复 `a7b7b85`）均已落。**T0 唯一剩余 = GATE-02 渲染证据**：入库 render probe +
固定图/规定相机的像素统计与截图留档（Forward+ 未测标注）——与 retro/M1a.md 主观门
清单第 7 项同源，可同批走。

**第一批卡（登记非排期；完成即登记证据，不进 M1 验收口径）**：

| ID | 卡 | 验收（方案 Given/When/Then 摘要） | 完成登记（2026-10-10 收尾登记员追加） |
|---|---|---|---|
| GATE-02 | 固定图+相机渲染证据 | 旧固定图规定相机渲染，存构建/设备/像素统计与截图；Forward+ 未测明确标注 | **2026-10-10 完成**：`tools/render_probe.gd` 实跑 Forward+（地形 410725px / 高亮 765px / 描线 230px 全超阈值，PROBE OK exit=0，两次运行计数逐位一致）；证据 = `docs/evidence/m1a/render_probe_{terrain,highlight,path}_forwardplus_1280x720.png` + `render_probe_stats_forwardplus_1280x720.txt`  terrain_style_slots_default.tres）；门禁 169 用例 / 0 失败；**2026-10-11 外审 S-1 勘误**：该轮实跑实为 `--rendering-method gl_compatibility`/llvmpipe，「Forward+ 实测」表述失真（探针标注读工程配置非运行时）——修复与证据重出 = 准备批 GATE-EVIDENCE |
| BLEND-01 | 相邻两格颜色权重（过渡合同首证） | 草-泥边带：两端对应纯色、中点权重各 0.5、权重和为 1，格心保持纯色 | **2026-10-10 完成**：`tests/test_hex_terrain_blend.gd`（15 用例）；门禁 184 用例 / 0 失败 + 三个 scene_check 全绿；详情见下方已交付证据段 |
| BLEND-02 | 三格交汇 + 跨 chunk 过渡 | 草-泥-岩共享角跨 chunk：三方权重正确、shared position 一致、无裂缝无重复角面 | **2026-10-10 完成**：`tests/test_hex_terrain_blend_corner.gd`（9 用例）；门禁 193 用例 / 0 失败 + 三个 scene_check 全绿；详情见下方已交付证据段 |
| BLEND-03 | 纹理可替换不改世界事实 | 同图两套 style：逻辑摘要与可达性不变、材质效果不同、索引/face 映射不变 | **2026-10-10 完成**：`tests/test_terrain_style.gd`（9 用例）；门禁 202 用例 / 0 失败 + 三个 scene_check 全绿；详情见下方已交付证据段 |

**已交付证据（完成即登记；不进 M1 验收口径）**：

- **BLEND-01（2026-10-10 交付）**：权重/色板/映射纯逻辑合同 =
  `addons/hexhammer/hex_terrain_blend.gd`（edge_weights/is_valid_weights/blend_color/
  palette_from_materials/make_blend_material）；构建入口 = `hex_terrain_builder.gd`
  `build_map_blend`/`build_chunk_blend`（顶点 COLOR 承载权重、沿用 raw 顶点/渲染索引
  双层口径；几何/UV/法线/索引/faces 与 fallback 材质槽路线**逐位一致**、fallback
  零改动——测试锚定）；headless 锚 = `tests/test_hex_terrain_blend.gd`（15 用例：
  端点 (1,0)/(0,1)、中点 (0.5,0.5)、和恒 1、色板往返、草-泥两端纯色 + 格心纯色、
  三类边带、角落端点规则、碰撞汤/face 表逐位等价、确定性、非法输入显式失败）；
  目检载体 = `scenes/blend_sandbox.tscn`（F6；6×4 草-泥固定图，检查器 render_style
  切 BLEND/SLOTS 同图对照，拾取+高亮照常挂接）。门禁 = 184 用例 / 0 失败（exit 0）
  + 三个 scene_check（picking/highlight/camera）各自 exit 0。「中点 0.5 不加中点
  顶点」「8-bit 顶点色量化容差」等取舍见 docs/notes/m1aplus-blend-01.md 与
  docs/retro/M1a-plus.md。

- **BLEND-02（2026-10-10 交付）**：三格权重合同 = `hex_terrain_blend.gd`
  `corner_weights`（重心参数 (u,v) → (归属格,N(k),N(k−1)) 权重）/`is_valid_weights3`
  （有限、非负（−eps 浮点零点窗口）、和恒 1）/`blend_color3`（两格同色角逐通道
  退化为边带合同——「角混三种」的最大=3、常见=2 同一合同覆盖）；角面 mesh 顶点 =
  合同单位权重锚点（p1=(1,0,0)、p2=(0,1,0)、p3=(0,0,1)，发射序与 BLEND-01 落地
  规则同构——几何/COLOR **零行为变化**，builder 仅注记指回合同，face 表/碰撞合同
  不动）；面内三色过渡 = 顶点 COLOR 线性插值（重心 = 1/3 均权）；headless 锚 =
  `tests/test_hex_terrain_blend_corner.gd`（9 用例：合同锚点/合同域密集不变量/
  非法拒绝/重心均值+边带退化一致性；草-泥-岩共享角三方顶点色 + 重心等价链路 +
  重心几何 = p1+(bridge_j+bridge_{j−1})/3 + 三格视角 shared position 跨路径对账；
  **跨 chunk** = 同图三种划分（单 chunk / 行切 trio 跨 2 块 / 每格一 chunk trio
  分属 3 块）角面位置+顶点色逐位一致、角面由归属块生成、全图物理角 key 恰一面
  ×每划分；**无裂缝** = 每格一 chunk（25 块）焊接流形（每边 1/2 面引用、无重复
  面 key、边界边 = 期望外沿、法线朝上）；拾取 = 跨块划分 blend↔fallback 碰撞汤/
  face 表逐位一致 + 角面 resolve 归属三格之一）；目检载体 =
  `scenes/blend_corner_sandbox.tscn`（F6；6×5 草-泥-岩固定图、chunk 按行切 6×1
  使三格交汇角跨缝，render_style 切 BLEND/SLOTS 对照，拾取+高亮照常挂接）。
  门禁 = 193 用例 / 0 失败（exit 0）+ 三个 scene_check 各自 exit 0。浮点取舍
  （float32 权重 1/3 量化 1e-6 窗口、u+v=1 边界 −eps 零点窗口、mesh↔mesh 跨划分
  逐位精确）见 docs/notes/m1aplus-blend-02.md 与 docs/retro/M1a-plus.md。

- **BLEND-03（2026-10-10 交付）**：style 配置载体 = `scripts/core/data/
  terrain_style.gd`（TerrainStyle Resource，T8 材质槽同款资源化先例：mode ∈
  {SLOTS 色块, BLEND 过渡} + material_library 两路线共同外观来源 + blend_material
  顶点色导管；`inputs_for` 纯解析只对图内被用到的 id 预检，缺库/缺槽/缺导管
  显式失败不静默换路线）；入库两套 .tres = `resources/terrain/styles/
  terrain_style_slots_default.tres`（默认色块）与 `terrain_style_blend_default.tres`
  （混合过渡）+ 代码内对账基准 make_default_slots/blend；换装入口 =
  `map_view.gd build_with_style`（按 mode 分发到既有 build/build_blend，builder
  **零改动**）；headless 锚 = `tests/test_terrain_style.gd`（9 用例：同 seed
  双实例 Given 守卫（seed 7301/12×8 含水含 6 地形连通 ok）；换 style 前后
  summary 逐字节/to_dict/mods 空 = 规则面零变化；ARRAY_INDEX/顶点/UV/faces/
  碰撞汤/face 表跨 chunk 逐位一致；MapConnectivity 报告整体一致；SLOTS ≥2
  库材质实例全不开顶点色 vs BLEND 单一导管材质开顶点色、跨地形边带端点异色
  = 材质实例确不同）；目检载体 = `scenes/style_sandbox.tscn`（F6；检查器把
  terrain_style 换 .tres 即同图换装，拾取+高亮照常挂接）。取舍（预检只看图内
  id、「材质效果不同」headless 锚到材质实例+顶点色通道、像素级差异归 GATE-02）
  见 docs/notes/m1aplus-blend-03.md 与 docs/retro/M1a-plus.md。门禁 = 202 用例 /
  0 失败（exit 0）+ 三个 scene_check（picking 6/0、highlight 31/0、camera 11/0）
  各自 exit 0。

**数据合同冻结建议（T2/T3 开工前置，只登记不实现）**：穿格河流 1入1出
（RiverReach/WaterBody/Road/Crossing 字段集）、NeighborLinkData 的 link_id 约定、
WorldData 与 MapData 并存（不塞 `mods`）——见方案「核心设计与数据边界」节；
~~**河流穿格 vs 格边为 ADR 级决策**，T3 前须回 02 立 ADR~~（已解：2026-10-10 02 ADR-14 = **格边河流**；草案 §5/§8 重议蓝本 = 执行方案 §2、已全部拍板）。

  **2026-10-10 完成（草案交付）**：`docs/M1a-terrain-data-contract-draft.md`——纯文档、
  零代码改动（WorldData + 七实体逐字段表与初版禁止项；兼容性总纲按现行实现静态实读
  对照、未做运行时实验；RiverReachData 1入1出结构钉死）。「草案非拍板」效力声明不变：
  ~~穿格 vs 格边仍为 ADR 级悬置决策，T3 前须回 02 立 ADR（现行最新 ADR-13）~~
  （已过时——02 ADR-14 已立格边 2026-10-10；草案 §5/§8 重议蓝本 = 执行方案 §2、
  §2.6 全部拍板）。

  **2026-10-10 完成（T2–T5 执行方案交付）**：数据合同草案 §5/§8 **按 ADR-14 格边
  重议案** + T2–T5 十三卡逐卡执行案 + Azgaar 势力范围前瞻案（五份外部调研多源对照；
  非拍板文档，卡内须主创拍板项各卡自带、合同重议案待确认三项列其 §2.6）。全文见
  [M1a-terrain-T2-T5-execution-plan.md](M1a-terrain-T2-T5-execution-plan.md)。

**主创拍板第二~五批登记指针（2026-10-11）**：T2–T5 执行方案的四批追加拍板（第二批
④~⑧：河网路线/桥语义/格线归属/Azgaar 重构；第三批⑨~⑪：§2.6 关闭；第四批⑫：
定位口径；第五批⑬~⑮：外审三件套处置）**登记权威 = 执行方案头部拍板登记**
（[M1a-terrain-T2-T5-execution-plan.md](M1a-terrain-T2-T5-execution-plan.md)），
04 不重复落字。

**准备批 + LAND-S 登记（2026-10-11 拍板⑮新增；下一批范围 = 准备批四卡 + LAND-S，
十四卡不同时启动）**：

| ID | 卡 | 验收（执行方案 §0.5/§3 摘要） | 完成登记 |
|---|---|---|---|
| PLAN-ALIGN | 文档权威对齐（02/04/草案/提案/执行方案五方） | 每条生效数据规则只有一个权威版本；被替代口径全部划线标注 | **2026-10-11 完成**：02 ADR-14 排水前置废除注；04 三处「ADR 悬置」过时口径划线 + GATE-02 登记行 S-1 勘误注；草案头部排水映射废除注 + 转正蓝本指针；提案头部取代注 + 卡表行级差异注；README 环境行改 `E:\Godot` 4.7.2（恢复 + 门禁 202 用例/0 失败复现，exit 0——环境硬前置同批达标） |
| GATE-EVIDENCE | 渲染证据修复（S-1/S-2/S-4） | 探针渲染器标注取运行时；SLOTS/BLEND 同图差分 >0；BLEND+贴图库报缺 | **2026-10-11 完成**：S-1 = render_probe.gd 标识改 `RenderingServer.get_current_rendering_method()`、统计双行（实际运行时/工程配置）、删「Forward+ 实测」硬编码；S-4 = 新增 CHECK-4（默认 BLEND style 同图重渲 + 与 SLOTS 帧差分，阈值 200 起步）；S-2 = terrain_style.gd problems_for 对 BLEND+albedo_texture 报缺、inputs_for 拒绝 + 单测 test_blend_texture_library_explicitly_rejected；**本机真 GPU 实测**（Vulkan 1.4.349 / AMD RX 7700 XT / Forward+）探针 4/4 全过 exit 0，证据重出 = docs/evidence/m1a/ 四图（terrain/highlight/path/**blend 新增**）+ 统计 txt（渲染器/设备/尺寸全留档） |
| GATE-PORTABILITY | runner 收尾（S-3） | fixture_hang 零引擎 ERROR；故障注入全表仍全拦 | **2026-10-11 完成**：run_tests.gd v3.1——timed_out 分支不再查退出码（记 -1，根除 Linux 引擎 ERROR）、三态口径进头注；门禁 13 文件 / **203 用例** / 0 失败 exit 0（+1 = S-2 新测试），故障注入全表仍全拦（runtime 错误/零断言/NaN/有参/崩溃/死循环） |
| GATE-ENTRY | 统一门禁入口（导入→单测→场景→探针） | 全链退出码正确聚合；无图形环境报「未验证」 | **2026-10-11 完成**：tools/gate_all.gd——单命令五步链 + 探针（`-- --with-probe` 或桌面环境触发，否则显式报「未验证」≠全绿）；**全链实测 6/6 PASS exit 0**（导入/单测 203/0/拾取/高亮/相机/真 GPU 探针 4/4）；图形失败计入总失败（不被单测绿覆盖） |
| LAND-S | 七格测试场（T2-SPIKE 附卡） | 平/坡/阶地/真崖及混合角全覆盖目检 + 步数默认值拍板记录 | **2026-10-11 完成**：`tools/land_spike_probe.gd`（实验几何 spike：terrace 水平均分 + Catlike 竖直剖面 v_step=1/ceil(steps/2)、真崖 = 共享崖线 t=0.5 同 XZ 墙顶/墙底 + 高低裙边 Δ≥3——**不进 addons 合同**）+ `tools/land_spike_fixtures.gd`（测试锚固定小图 fixture：七格 e=[1,2,3,2,1,0] Δ 全档 0-3 + 断面 Δ2/Δ3，make_fixed_maps 特征常量先例，LAND-01 矩阵图/LAND-02 沙盒可复用同一布局）；证据 = `docs/evidence/m1a/land_spike/` 六图 + summary（overview_steps5/3、section_d2_steps5/3、section_d3_ar100/150；真 GPU forward_plus 实跑，两次健全跑哈希逐位一致 = 可复现）；探针结构 CHECK 两道闸（非背景像素 ≥12000 + 断面列跨度 ≥0.30×帧高，按健全帧实测校准）+ 负向变异自检 1 次（yaw 临时改 90° 复现退化被拦 exit 1）；断面相机初版沿边切向正对致证据废片（台阶压 ~15px 细线、真崖侧视退化不可见——像素列审计实证）→ 改低位斜视偏航 38°/俯角 20°（文件头修订条写明理由）；**无新单测**（卡表测试锚明文：spike 产物 = 目检结论 + profile 默认值拍板记录）——门禁实跑：--import exit 0、run_tests 13 文件 / **203 用例** / 0 失败 exit 0（与基线持平，只增不减满足）、gate_all 全链 6/6 含真渲染探针 4/4；拍板素材齐、待主创目检（卡内拍板项 = spike 后与 LAND-02 合并拍）：① 步数默认 5 vs 3（spike 结论 = 5，Catlike 原档）、② cliff 纵横比 ×1.0 vs ×1.5（竖直夸张系数；横轴连接带宽 ≈0.35·size 为合同常量）——均属 LandformProfile 默认值（LAND-02 落地进 §8.1），翻案只改默认值零返工；遗留 low：沙盒未落 .tscn（档对比 = 并列出图 + 候选档常量，非可切换交互件——执行方案 :272「沿 blend_sandbox 先例」未全落）、out/hexhammer-doc-ambiguity-2026-10-11.md 过路件不随本批提交（处置归主创） |

**T2 阶地批登记（2026-10-11 完成；LAND-01/02/03 + GRID-01 四卡——T2 全卡收官，
无河无路世界完整可玩可渲染）**：

| ID | 卡 | 验收（执行方案 §3 摘要） | 完成登记 |
|---|---|---|---|
| LAND-01 | 连接矩阵与 WorldData 落地 | 高程组合及方向旋转穷举矩阵，平/坡/崖全部闭合并可见；§2.5 四件落地（首物） | **2026-10-11 完成**：§2.5 四件 = `scripts/core/data/world_data.gd`（容器 + NeighborLinkData `link_id=(min,max)` + 校验器 + 固定键序序列化；rivers 等未解锁集合恒空、from_dict 拒绝非空）+ `scripts/content/map_io.gd` 增 `.world.json` 第四伴生（缺失→empty()）+ `tests/test_world_data.gd` **12 用例**（Vector2i 显式 [x,y] 转换层：断言落盘 JSON 无 "(3, 17)" 字符串形状、user:// 真文件往返、零回写 MapData）；classify_edge 四分类（flat / slope / terrace(Δ∈[2,threshold)) / cliff(Δ≥threshold=3)，修订记录一口径）threshold 参数化；矩阵图 = `tools/land_matrix_fixtures.gd`（特征常量区、零随机、间距防串扰自检）Δ0..max(3,threshold)×方向 0..5 全对 + 角 (min,mid,max) 等价类全集（默认 20 类、threshold=4 扩 35 类含值域随档扩，修订记录三之 8），兼作 LAND-02/03 fixture 与探针 CHECK 图 |
| LAND-02 | 阶地与 cliff 交汇 | 同高程端点不移位；阶地-崖角不漏缝；关闭阶地可退回旧坡 | **2026-10-11 完成**：terrace_lerp/terrace_vfrac 按方案原式（v_step=1/ceil(steps/2)，修订记录三之 3）；步数-Δ 绑定 = 每爬一级一组、组边界环恰落高程整数层（测试锚）；阶地环带面数 = 2·n·steps 解析预言逐边核对；真垂直崖 = 共享崖线 XZ(t=0.5) + 同 XZ 墙顶/墙底 + 高低裙边（断言墙顶/墙底 XZ 逐位一致 + 恰 2 竖直面 + 面数 6 + edge_type=cliff_wall）；角落情形分派 = **边界环 3D 耳切三角化**（方案只要求沿 SSF/SCS/CCS 结构枚举——简单扇形在锚点自身侧 tread 段产生零面积裂缝、纯 XZ 耳切在双崖角死锁，3D 耳切以 XZ 退化耳=竖直鳍面统一覆盖等高/阶地扇/坍缩扇/崖×阶地混合角；边界段恰用一次、角面数恒=环点数−2 解析预言）；blend 承接 = 每新顶点 COLOR 由同一 edge_weights(t)/corner_weights(u,v) 显式求值；`scripts/core/data/landform_profile.gd` 独立 Resource（terrace_enabled 默认开 / terrace_steps 默认 5 / cliff_vertical 默认开 / cliff_threshold 默认 3，`resources/terrain/landform_profile_default.tres` + 代码对账）；回退锚 = 全关 profile 与不传 profile 的 mesh 数组 + faces 元数据逐位一致；blend 头注（不设中点顶点→限定回材质级表现切片）与 tests/test_hex_terrain_blend 面数/Δ2 标签锚同步改；矩阵图全量焊接流形锚 = 重复面 0 / 边引用≤2 / 开边⊆基线外沿（位置级对照）/ 全顶点有限 / 绕序 y≥0（竖直面 |cy|≤1e-6 阈 = 坐标 170 处 float32 噪声 ~1e-5 的安全档）；测试 = `tests/test_landform_terraces.gd` **16 用例** + test_hex_terrain_elevation/materials 锚同步改（用例数不减） |
| LAND-03 | geometry→picking→highlight 合同 | 每类新面拥有稳定候选格，真实 raycast 与归属一致；高亮贴合新表面不埋入阶地 | **2026-10-11 完成**：faces 保持 top/edge/corner、edge_type 细化 terrace/cliff_wall；resolve_face **零分支**（pick_edge_band/pick_corner 仅加 threshold 默认参）——terrace riser 归最近格心+ID 决胜、cliff_wall 归高地侧；corner spread≥threshold→最高格、spread=2 阶地形角→最近格心；threshold 经 chunk_pick_data/resolve_hit/resolve_face/map_picker.setup 全链接线（评审 medium 项，有回归锚）；高亮贴合 = **footprint 口径**（每格顶面恒平 = cell_surface_anchor 合同、扇 y 恒高于覆盖位置地表、riser/崖壁/角面顶点不入 inner hexagon XZ 内部，1e-3 距离余量隔跨视角 float 噪声）；face 表/碰撞汤逐索引对应在新面数下保持；测试 = `tests/test_land_picking_highlight.gd` **5 用例** + test_hex_picking/test_hex_picking_ray 锚按四分类同步改（用例数不减）；`tools/picking_scene_check.gd` 扩 F/G 真实 raycast 用例 |
| GRID-01 | 格线层（拍板⑦新增：格线层归 T2） | 全部格子细描边、贴各自格面高度、可整体关闭；跨 chunk 一致 | **2026-10-11 完成**：`addons/hexhammer/hex_grid_line_builder.gd` 沿 NeighborLink 边 + 地图外缘边发射、每物理边恰一 strip（内部边归稳定 ID 小格、外缘归本格，计数 = 6N−内部边数 oracle）；贴面高度 = 两侧较高侧 y + lift_for_tier(TIER_GRID_LINE)（hex_highlight 档位表登记 tier2=0.04，预留 tier3+ 给 ROAD-01/WATER-02，半档描线 0.035 之下不冲突）；TerrainStyle 扩 grid_line 参数组（enabled 默认开 / 色 / α0.28 / 宽 0.012，非法参数 problems_for 报缺）；关 = inputs_for 不出键、地形 mesh 逐位回基线；格线 mesh 无 COLOR 不参与 blend 色板、不进拾取层；跨 chunk 三种划分逐位一致；测试 = `tests/test_hex_grid_line.gd` **6 用例**；`tools/render_probe.gd` 新增 CHECK-6 |

**T2 批门禁与证据（本会话实跑）**：`--import` exit 0；run_tests = **17 文件 /
242 用例 / 0 失败** exit 0（基线 13 文件/203 → +4 文件 +39 用例只增不减；新四件
12+16+5+6 = 39，均沿 tests/test_case.gd 基类、oracle 独立拼装——方案公式 +
HexMath 全局参数重推，不复制实现）；gate_all 全链 6/6 PASS exit 0 含真渲染探针
render_probe **6/6**（forward_plus 真渲染：CHECK-6 格线差分 5632px>300、
CHECK-T2 阶地/真崖矩阵图差分 1380px>500、基线可见 74180px——证据 =
`docs/evidence/m1a/render_probe_stats_forwardplus_1280x720.txt`（CHECK-6/T2 行）
+ blend 帧图同刻重出）；picking_scene_check **8 用例/0 失败** exit 0（新增
F 阶地 Δ2 最近格心+edge_type=terrace、G 崖壁 Δ3 高地侧+cliff_wall+水平射线正中
竖直墙的真实 raycast 用例）。评审：七条上轮问题全部实证修复（两 high：阶地 blend
逐点权重探针 60/60 吻合、崖墙朝向双归属恒朝低侧；medium：threshold 全链接线带
回归锚），门禁独立复跑 245/0 一致——**通过**。一次性冒烟脚本 smoke_land.gd 已删
（验证结论并入正式测试）；spike 件 land_spike_probe.gd 未动（只借公式口径）。
**未尽事项**：① m1a_sandbox 未接默认 profile（观感验证走 render_probe/
land_spike，接线属后续表现层选择）；② 矩阵图未落 resources/maps/fixed 伴生
.json（fixture 纯代码件沿 land_spike_fixtures 先例，需 .json 工件时由
make_fixed_maps 扩展）；③ LAND-S 步数默认（5 vs 3）与 cliff 纵横比拍板仍悬
——本批按默认 5/×1.0 落档；④ repo 根 out/ 外部产物（会话前已存在）未触碰
不入本批。**遗留 low（评审登记）**：仓库根 `nul` 垃圾文件（72B shell 报错重定向
误写，未跟踪不入本批，入库前应删——Windows 保留名须 `\\?\` 路径删）；「渲染探针
证据早于修复约 28 分钟」一项**已随终跑闭合**（评审时证据 22:51:44 早于修复
23:19-23:27、像素中性已实证；终跑 gate_all 含探针 23:42:54 重出证据，晚于全部
修复文件 mtime，现档与终代码同刻）。

**T3 水系批登记（2026-10-11 完成 + 2026-10-12 评审修复；WATER-01/02/03 三卡——
数据面（河段/水体/校验器/序列化）+ 几何面（河床下切/水面第二 mesh/岸线裙边）+
固定图数据化）**：

| ID | 卡 | 验收（执行方案 §4 摘要） | 完成登记 |
|---|---|---|---|
| WATER-01 | 格边河段数据面 | 边序列连续（共角点）、角点级无环、单调不升、床<水位、有终点；Vector2i [x,y] 落盘；缺 .world.json → empty() | **2026-10-11 完成**：`WorldData` RiverReachData（edges/water_levels 逐段 profile/bed_level/flow_level/water_body_id）+ 校验器四条（RIVER_CYCLE 角点级 = corner_id_of 稳定角点 ID + 双端延伸链行走、RIVER_LEVEL_RISE、RIVER_BED、NO_RIVER_OUTLET 终点∈inlet 对账）；fixture 生成器 `tools/river_fixtures.gd`（around_cell_chain 弯样/角点环拒绝样 + greedy_chain 确定性贪心走廊——几何共角点判定与校验器 ID 判定两路互证）；测试 = `tests/test_water_rivers.gd`（弯/走廊/源/终点/上坡/环/断链/非法邻格拒绝 + 序列化往返） |
| WATER-02 | 河床/水面/河岸三层几何 | 跨 chunk 三层锚点一致；不露洞、不重复水面；水层不截获拾取；河床沿整条边全长（修订记录三之 1） | **2026-10-11 完成 + 2026-10-12 评审修复**：河床 = `hex_terrain_builder.gd` `_emit_river_band`（有河 link 边带整段下切「岸坡→床→岸坡」剖面，kind="riverbed"，6 面/边；河畔角走 `_emit_corner_fill` 下切侧折线）；水面 = `addons/hexhammer/water_geometry_builder.gd` 独立第二 mesh（条带 u∈[bank,1−bank] 恒宽 + **角点楔形 water_corner（评审 high 修复：同一 reach 共角点边对恰一楔、凸包扇形剖分、端段与条带同 `_strip_quad` 同参派生逐位一致、归属=角点三格最小 ID 格）** + 水面扇 + 悬崖岸裙边）；水面 y=(level−0.5)×step 半档错位；**评审修复连带两缺陷**：终点边成员侧延展沿边镜像配对（配反=扭四边形域内孔/重复）+ 条带/裙带 raw 绕序统一俯视逆时针（修复前俯视背面被 CULL_BACK 剔——水面实际不可见，探针 9508→10503px 实证增量）；拾取 = 水面零碰撞体不进 LAYER_TERRAIN、riverbed 归属两侧最近格心+ID 决胜（`hex_picking.gd`）；场景挂载 `map_view.gd _mount_water`（view 层零碰撞体）；测试 = `tests/test_water_geometry.gd`（河床整边全长/边带优先于分类/焊接流形/跨 chunk 三划分逐位一致/**角点楔形逐位焊接 + 全链中心线·角点对角线·终点延展域采样恰一 patch（不露洞不重复）+ raw 绕序锚**/blend 兼容/拾取合同） |
| WATER-03 | 湖/海/岸线/河口 | 同湖水位一致；源流到声明出口；河口无悬空水面；terminal 语义 | **2026-10-11 完成 + 2026-10-12 补 SEA outlet 校验 + 同日二轮补连续水面**：WaterBodyData（SEA/LAKE、member_cells、inlet/outlet 边口径、terminal）+ 校验器（WATER_MOUTH_LEVEL 河口水位对账/WATER_TERMINAL 过路湖须 outlet/**WATER_SEA_OUTLET 海 outlet 恒空（2026-10-12 补——草案 §6 约束进校验器）**/WATER_OUTLET_LEVEL 湖出口不高于溢流口/WATER_MEMBER_TERRAIN 成员地形对账显式启用）；**连续水面（二轮 high 修复）= 同体成员边整段带面 water_band + 角点补面泛化**（见下方二轮修复段）；岸线 = shore_links_of（水陆共享边集合，裙边/校验两处复用）；河口接缝 = 终点条带延至成员格内边、与水面扇边缘同参数逐位一致（两侧成员镜像各锚）；悬崖岸裙边（水面向陆侧延至带中段=崖壁脚）；固定图 = `make_fixed_maps.gd` 正弦河改产 WorldData.rivers 贪心链 + 河口湖/东北湖水体 + `playable_60x40.world.json` 第四伴生；测试 = `tests/test_water_bodies.gd`（岸线 oracle/水位结构/出口水位/terminal 家族/SEA outlet 拒绝/序列化往返）+ test_water_geometry.gd 湖面连续锚 |

**T3 批门禁与证据（本会话实跑，2026-10-12 两轮修复后终态）**：`--import` exit 0；
run_tests = **20 文件 / 285 用例 / 0 失败** exit 0（T2 后 17/242 → T3 批 +3 文件
+39 用例 → 一轮评审修复 +3 用例 → 二轮评审修复 +1 用例，只增不减；三新件均沿
tests/test_case.gd 基类、oracle 独立拼装——跨河参数/接缝顶点由测试内独立
lerp/inner_vertex 重推）；picking_scene_check **10 用例/0 失败** exit 0（新增 H0：
水面第二 mesh 挂载进场景零碰撞体——「射线穿水」引擎级证据含水面层本体，一轮
medium 修复；H 河床归属 |Δh|=4 高岸不截胡）；render_probe **7/7 PASS** exit 0
（真 GPU forward_plus：CHECK-W 水面差分 14610px>3000——两轮修复后重出：9508
（首报）→ 10503（角点接缝 + 绕序）→ 14610（湖面带面 + 角点补面），证据 =
`docs/evidence/m1a/render_probe_stats_forwardplus_1280x720.txt` + 四帧图同刻更新）。

**T3 二轮评审修复（2026-10-12 同日）**：high = 湖/海水面成员间断裂——`_emit_skirts`
水-水内边 skip 的「两扇已在内边相接」为假前提（两内六边形实隔整条连接带 ≈
0.35·size，多格水体成孤岛六边形，评审探针 2×2 湖 5/5 成员对中点 0 覆盖、固定图
东北湖 206/206）→ 修复 = **同体成员边整段带面**（water_band，u∈[0,1] 两端 =
成员格内边、沿边镜像配对、归属 = link 两端较小格、与两侧水面扇 inner_vertex
同三元组逐位一致）+ **角点补面泛化**（water_corner 从「reach 共角点边对楔形」
推广为「角点 ≥2 条边有水面即补」：水权收集（条带段/带段/裙段，世界级现算）
→ 到达段端点成环保留共线点 → 质心扇形——不吞点防 T 型结、条带×条带 = 河转角、
带×带 = 湖内角、带×裙 = 湖岸角同一规则覆盖；异体水-水边两侧半带裙边相接留作
病理态显式行为）；修复后评审同口径探针 5/5 + 2/2（三成员角质心）恰一 patch；
新测试锚 `test_lake_surface_continuous_across_members`（带面存在/归属/四角与
两侧扇 == 共享/成员对中点+带中线+三成员角质心恰一 patch）。low = 仓库根
`nul`/`out/` 垃圾**已删**（out/ 内为 2026-10-11 外审歧义清单——结论已随 PLAN-ALIGN
并档，沿「外审件过路即弃」先例；工作树未跟踪项只剩 T3 交付件）。
**遗留 low（评审登记）**：异体水-水邻接（两不同水位水体贴边——v1 无 fixture
覆盖的病理态）两侧各出半带裙边至带中段相接、角点补面环退化跳过，行径无测试锚
（头注 `addons/hexhammer/water_geometry_builder.gd:38-39` 自认；`_emit_corner_fill`
退化分支 :381-388 ring<3/面积 ~0 跳过；`tests/test_water_geometry.gd` 无异体
水体用例）——属 v1 已知留白而非缺陷，异体水-水图首次进 fixture 时须补恰一
patch/裙边相接锚再动。

**T4 手工道路与桥批登记（2026-10-12 完成；ROAD-01/02/03 三卡——数据面
（RoadData/CrossingData/校验器/双向对账）+ 几何面（路面第二 mesh 格心网络/
桥面五段剖面/碰撞汤拾取）+ 生成期连通查询 + 固定图路桥数据化；自动路网已随
修订记录三之 6 上移 T5 WORLD-05，本批零 T5 依赖）**：

| ID | 卡 | 验收（执行方案 §5 摘要） | 完成登记 |
|---|---|---|---|
| ROAD-01 | 道路图与路口 | 相邻双向一致；端点/直路/转弯/三叉/更多路口同一 data contract；非法高差按配置拒绝（初版 road_class 恒 0） | **2026-10-12 完成**：RoadData 落 `scripts/core/data/world_data.gd`（cells 有序格序列 / is_loop 闭合边同进对账 / road_class 值域单点恒 0——from_dict+validate 双拒绝 / connects_pois T5 前恒空）+ link.road_id ↔ roads 相邻对**双向对账**（LINK_ROAD_MISMATCH 两向：link 声明无实体、实体相邻对缺 link 均拒）；路口 = 多路共享格、共享 link = ROAD_LINK_REUSE 拒绝；Δ≥2 拒绝按生成配置参数化（validate 第三参 max_road_delta=−1 不查——§7「阈值在生成配置不进数据/有配置才拒」；被 crossing 认领的河 link 跳过、归桥址校验管辖）；几何 = `addons/hexhammer/road_geometry_builder.gd` 纯逻辑类——格心网络构型通式（每格按 6 邻道路方向子集发射格心→内边扇区+连接带条带、min-ID 边归属；宽度调制 = 相邻 ±1 方向全宽/孤悬收窄，Catlike Part 7 通式字面移植）；lift 档位表登记 tier3 路面 0.05 / tier4 桥面 0.06（`hex_highlight.gd`——档位表扩档统一登记防冲突）；TerrainStyle 扩 road_material（与 water_material 同批口径；桥面材质首版不进槽、走 make_bridge_material 工厂默认——方案只要求一槽）；测试 = `tests/test_roads.gd` **9 用例**（形状 fixture 同合同/双向对账/三叉四叉共享格不共享 link/63 子集+14 旋转等价类/结构拒绝/值域/Δ 有配置才拒/序列化往返/零回写/固定图路桥）+ `tests/test_road_geometry.gd` **8 用例**之路面锚（面数解析预言 6\|D\| 全配置/宽度调制/格心扇区坐标 oracle/Δ1 贴坡/三划分 chunk 逐位一致/参数非法） |
| ROAD-02 | 横切河道的桥 | 桥端落在两岸合法锚点；道路确实横切河槽而非纵向覆盖；跨越边在查询中对应桥 | **2026-10-12 完成**：CrossingData 按 §2.3 重写表（river_edge 单边、有河才有桥 CROSSING_NO_RIVER；bank_a/b == link 两端格 canonical、BRIDGE_ENDPOINT_INVALID 拒错；Kind.BRIDGE 唯一合法值——FERRY 枚举存在但 from_dict+validate 双拒绝；一 link 至多一 crossing CROSSING_DUP；桥必被路跨接 CROSSING_NO_ROAD = 两岸都有路的机器表达）；横切机器定义 = 未认领跨接 RIVER_FORD_FORBIDDEN 禁渡、与 BRIDGE_ENDPOINT_INVALID 分开报（锚 = 两错误码互斥断言）；桥址首版 = 桥头（bank Δ ≤ max_bridge_bank_delta 配置）+ 净空（max 两岸高程 ≥ 河水位），净跨单边恒定、坡度由桥头 Δ 覆盖——不得整桥抬高留悬空桥头；急弯判据 `river_bend_is_sharp`（edge[k] 与 edge[k+2] 切向点积平行性，拍板⑩走向几何版；k<0 或 k+2 越界 = 非急弯，首尾边界专测）；桥几何五段剖面 = 两岸平台段（桥头落地 y=本岸+lift4 无悬空，测试逐位断言）→ 接坡段（Δ>0 爬升）→ 中段跨水（y=max(两岸)+lift4，与水面条带同 RIVER_BANK_FRACTION 参数对齐）；长轴⊥河 abs(dot(t,n))≤1e-6 测试独立拼装断言（修订记录三之 2）；桥面碰撞汤 deck_collision/deck_face_table（逐面 (a,c,b) Godot 正面）+ `hex_picking.gd` resolve_face 新 bridge_deck 分支（候选 = bank 两格、最近格心+ID 决胜）+ `map_view.gd` 挂载（路面零碰撞、桥面挂 LAYER_TERRAIN）；测试 = `tests/test_bridges.gd` **6 用例**（两岸==link 端格+认领表/禁渡与桥端错误分开报/结构拒绝四件/FERRY+净空/急弯判据几何 oracle+首尾边界/序列化）+ test_road_geometry.gd 之桥面锚（桥面⊥河+桥头落地+中段跨水/桥面碰撞汤+归属） |
| ROAD-03 | 生成期连通查询（重定义，修订记录三之 6：原「聚落道路骨架」整卡上移 T5 WORLD-05） | 无桥不能过阻挡河边、有合法桥可过；失败具名到河段；手工 fixture 驱动（零 T5 依赖） | **2026-10-12 完成**：`scripts/content/map_generation_connectivity.gd` 单一入口——edge_open（格 passable × 有河 link 无认领 = 禁渡 × 认领表）/ reachable_set（blocked_river 指向具体 link+reach——错误指向河段）/ required_connected，供 T5 WORLD-05/WORLD-04 共用（「最终边级通行图」落点即此）；手工 fixture 驱动（行 0 起贯穿贪心河+同侧过滤聚落，零 T5 依赖）；测试 = `tests/test_generation_connectivity.gd` **6 用例**（边原子四态/无桥失败指向河段+手工聚落/有桥通过/双口径湖墙/无河等价 MapConnectivity/只读+确定性） |

**T4 批门禁与证据（本会话实跑）**：`--import` exit 0；run_tests = **24 文件 /
314 用例 / 0 失败** exit 0——⚠ 基线实况与执行方案成文口径不符：仓库当前基线
实测 20 文件/285 用例（T2/T3 批已落地，非 13 文件/203），本批按「只增不减」
执行 +4 文件 +29 用例（test_roads 9 + test_bridges 6 + test_road_geometry 8 +
test_generation_connectivity 6，均沿 tests/test_case.gd 基类、oracle 独立拼装）
全绿；锚更新 test_world_data.gd（road_id 对账锚 + pois 单锁）+ test_water_rivers.gd
（roads 形状层拒绝锚）；picking_scene_check **11 用例/0 失败** exit 0（扩 I 阶段
桥面真实 raycast：桥面先于河床命中 / kind=bridge_deck / bank 两格归属）；
highlight_scene_check **31/31** exit 0；render_probe **8/8 PASS** exit 0（真 GPU
forward_plus：CHECK-5 路面/桥面层差分实测 517px、按「余量 ≥3×」定档 150——
证据 = `docs/evidence/m1a/render_probe_stats_forwardplus_1280x720.txt`）；
gate_all 全链 6/6 PASS exit 0（导入/单测+故障自检/拾取/高亮/相机/真渲染探针）。
固定图 = `make_fixed_maps.gd` 东西横路（行 5 列 18..34）+ 跨河桥（边 (324,325)，
行扫描 = 等高行/恰一有河边/非源终点/非急弯——放置规则的固定图示范）；map
digest 不变（仅 .world.json/.meta.json 更新，test_map_source digest 锚不动）；
FORD_ROWS 代码零残留（grep 复核——仅 make_fixed_maps.gd:28 头注划线记史）。
**首版取舍（头注登记）**：① 桥面材质不进 style 槽（走 make_bridge_material
工厂默认，方案只要求 road_material 一槽）；② 沙盒未接线 world/路面层（沿
T3 沙盒不加载水的先例，证据走探针+scene check）；③ map_picker 未动（生产
拾取的桥面体注册随 T5 沙盒接线时接入，避免无人消费的死代码）。**已知非本批
问题（如实报告）**：camera_scene_check C1/C2（缩放收敛容差）在本机 9/11——
已用 `git archive HEAD` 原始快照（未经本批改动）同机复跑、失败数值逐位一致
（got 62.81/17.14），证明为既有的机器/时序状态；本批未触碰相机栈（git status
佐证），沙盒不加载 world、路层不挂。**评审结论**：三卡实现与证据链全部独立
复现（门禁 314/0、拾取 11/11 含桥面真 raycast、探针 8/8 含 CHECK-5、固定图
工具重跑逐字节一致、全部卡表测试锚在场且真跑、认领/禁渡/湖墙/chunk 无关合同
均实证成立）——**通过**，仅四处口径级弱点随遗留 low 登记。

**遗留 low（评审登记，四处）**：① 桥面长轴⊥河断言结构恒真——n/t 均由
HexMath 原语计算、不读 built mesh（探针 T1：6 方向 dot 全为构造零；T3 宽度
写反时 ⊥ 仍过、桥头落地角点断言 FAIL；T2 built mesh 主方向 |dot|=0.995——
builder 实际正确），「走向写反」实际由同测试的桥头落地角点断言间接抓住、
中段（接坡/跨水点）横向错位无断言覆盖（`tests/test_road_geometry.gd:300-305`）；
② 卡表「数据合同影响」承诺的草案 §8 整节格边重写与 §7 禁令格边重述未随卡
执行——草案仍为穿格口径、§7 禁令引用不存在的 RiverReachData.cell_id 字段
（格边化前残句），`world_data.gd` 头注引用「草案 §7/§8」成悬空引用（权威链
经执行方案 §2.3 仍可解析、语义无歧义；草案最后提交 = f799822/T3，其头注自认
「§8 待 T4 按执行方案 §2.3 重写」未发生——`docs/M1a-terrain-data-contract-draft.md`
:243-247、§8）；③ 数据层接受在格语义水体（湖格 passable=false）上修路（探针
validate 返回空串——footprint 冲突校验属 T5 WORLD-03，计划未在 T4 禁此；连通
查询不受影响、读 passable，信息性记录——`scripts/core/data/world_data.gd`
:664-745）；④ 桥面碰撞体层号硬编码字面量 1（`scripts/ui/map_view.gd:199` 仅
注释口头引用 HexPicking.LAYER_TERRAIN=1），与 picking_scene_check 的
`1 << (LAYER_TERRAIN − 1)` 同一事实两处字面重复，层号变更时 view 侧静默漂移。

**T5-A 世界管线与河网生成批登记（2026-10-12 完成；WORLD-01/02 两卡——世界管线
九阶段化（模板/具名通道/阶段诊断/行为不变双锚）+ 河口反向生长河网生成；批号
T5-A = WORLD-01/02 先行，WORLD-03/04/05 属后续批）**：

| ID | 卡 | 验收（执行方案 §6 摘要） | 完成登记 |
|---|---|---|---|
| WORLD-01 | 模板和阶段化生成 | 每阶段独立摘要、版本与错误；关闭一个尚未实现能力不产生伪字段（提案 :282 验收原文） | **2026-10-12 完成**：① `scripts/content/world_pipeline.gd` 九阶段固定序（config→geography→quantize→hydrology→settlement→allegiance→roads→playability→presentation，STAGES 合同序测试锚定），每阶段独立纯函数 `stage(state, rng_channel)->{ok,error,diagnostics}`、跨阶段数据经显式 GenState；逐阶段诊断含 stage/version/summary（可 diff——Azgaar「无阶段诊断产物」反面教训的补丁），未解锁段（settlement=WORLD-03/allegiance=WORLD-03/roads=WORLD-05）skipped+reason——「关闭一个尚未实现能力不产生伪字段」；② MapGenerator 重构为门面：generate(params)=WorldPipeline.generate_legacy，meta 键集与 v1 逐键一致；**行为不变双锚** = 重构前实录 7 张基线 digest（seed 7/8/42/777/20261012 simplex + 777 cellular + 植被变体，会话内探针重构后逐一复现）+ 永久锚 `tests/test_world_pipeline.gd` 单遍 oracle（04 M1a-T9 细化四步直读，含 0.60/0.70 阈值）逐格对照两 seed；③ WorldTemplate Resource（`scripts/core/data/world_template.gd` + `resources/world/templates/` default/legacy 两 .tres，TerrainStyle 资源化先例；代码默认 make_default/make_legacy 与 .tres 同源有测试锚）：geography/dimensions 数值经 apply_to_params(seed) 投影为 MapGenParams（运行时唯一参数载体，无双事实源）；scenario/infrastructure 开关置 true 由 config 阶段具名拒绝（冲突串全列不产半图，Kind.FERRY「枚举存在 ≠ 能力开放」同款）；locked/preferred 约束名 v1 只承载不消费（消费随 WORLD-04 修复循环）；④ 具名随机通道五路 geography/hydrology/poi/roads/decoration（root+写死质数偏移 101/211/307/401/503，与植被场偏移 1013 错开）；hydrology 通道是 v1 唯一离散随机消耗点（河口挑选）；「改 decoration 不影响 hydrology 摘要」测试锚（含反向确证 override 机制生效）；⑤ 湿度通道改名「植被/地表掩码」（修订记录三之 7）：MOISTURE_*→VEGETATION_*、moisture_frequency→vegetation_frequency（序列化键 + CLI mfreq→vfreq 同步）、seed 偏移值 1013 原样继承（输出不漂移）；林/泥分类在用有测试锚（sea=0.4/vfreq=0.4 实测林 324/泥 112 格，只锚 >0+确定性不锚绝对数）；⑥ 海岸距离 BFS/无局部极小不进管线（修订记录三之 5），高程唯一来源 = 双噪声+量化（头注显式落字）；⑦ GENERATOR_VERSION 1→2（真源驻 WorldPipeline、MapGenerator 再导出保持历史引用面）；WorldData 新增 `world_digest(map)`（SHA-256，只覆盖世界事实不含 meta，to_dict 固定键序保证确定性）；测试 = `tests/test_world_pipeline.gd` **13 用例**（九阶段序/通道独立 seed/阶段诊断可 diff/同 seed 3 次 world_digest/跳过阶段空集合/decoration 通道独立/配置冲突全列/非法模板参数/版本=2 落 meta/模板 .tres 同源/植被掩码通道在用/单遍 oracle 行为不变/世界 meta 字段与 digest 敏感面） |
| WORLD-02 | 河网生成（河口反向生长；拍板④⑥重定义——原「排水/湿度/生态生成」） | 无环、合法出口、量化后二次验证（提案 :283 验收原文保留）；河网整体形状「水往海流」逻辑自洽（拍板④主创原话要义） | **2026-10-12 完成**：`scripts/content/river_network_generator.gd` 河口反向生长（x/1723 思路格边化，首版 = 彼此不汇合简单链——汇流随拍板⑨第二版开）算法三件：① 水体声明：水格六邻连通分量 → WaterBodyData，贴图界=SEA/内陆=LAKE，成员水位不齐 = WATER_BODY_LEVEL 具名失败（不静默重塑整图高程）；② 河口选择：岸边候选 + 岸侧格最小六边形环距间距约束（Azgaar burgs 间距同族）+ 角点全局预留查重，rng 挑序 = 生成器唯一随机源（hydrology 通道）；③ 反向生长：**已用边+已访问角点跨链全局永不再入候选**（无环须角点级——边不复用 ≠ 不复用角点，修订记录三之 4；角点预留跨链 → 河间不汇合不交叉）；候选偏好低高程（量化高程直接驱动）**且同时验证**出口/河床深度/水位/两岸容纳——双岸陆地且 min(岸高)−1≥当前水位 → 新水位 = min(岸高)−1（上溯不减 = 构造单调，禁上坡双保险：WATER-01 校验器仍断言），河口边 = 水体 water_level；停止三态具名 no_candidate/budget/map_edge 入 stats；**只读合同**：不写 MapData 任何字段（生成前后 summary 逐字节一致——测试锚）；flow_level 固定取模板值（不依赖汇流，修订记录三之 5）；产出直接落 reach.edges（growth 序反转为源→终点合同序）；量化后二次验证 = hydrology 阶段全量 WorldData.validate（post_quantum_valid 诊断）。测试 = `tests/test_river_network_generator.gd` **14 用例**（全量 validate/角点级无环独立复核+跨链不交叉+几何互证/同 seed 确定性/源汇可枚举+河口对账/水位单调低于双岸+bed/双岸陆地/flow_level 固定自配置/预算停止/抵图界停止 4×1 确定样本/无候选停止 3×3 孤岛确定样本/只读不改图/河口间距/SEA-LAKE 声明/水位不齐具名失败/cfg 缺键具名失败） |

**T5-A 批门禁与证据（本会话实跑）**：`--import` exit 0；run_tests = **26 文件 /
341 用例 / 0 失败** exit 0（基线实况 24 文件/314 用例/0 失败——T4 批登记即 314，
任务描述中「13 文件/203 用例」为陈旧数据；本批 +2 文件 +27 用例只增不减，均沿
tests/test_case.gd 基类、oracle 独立拼装；锚更新 test_map_source.gd 1 处参数键名
moisture_frequency→vegetation_frequency）；输出中 2 处 SCRIPT ERROR 为 runner
变异自检 fixture_runtime_error.gd 的预期拦截转发（非本批回归）；gate_all 全链
**5/5 PASS** exit 0（干净导入/单测+故障自检/拾取 **11 用例/0 失败**/高亮/相机三
scene_check）+ 渲染探针真渲染实跑 **8/8 CHECK PASS** exit 0（实际渲染器
forward_plus 运行时取值，S-1 口径；证据 =
`docs/evidence/m1a/render_probe_stats_forwardplus_1280x720.txt`——像素统计逐位
一致、仅时间戳行更新）。本批无新渲染面/面型，方案未为本批定义新探针 CHECK
（§8.3 的 CHECK-4/5 属 T3/T4 已存在、WORLD-04 才要求银行样图过探针），故
scene_check/探针以实跑取证而非硬造新 CHECK。**关键取舍（首版档）**：① 生长
偏好参数（高程权重/长度预算/河间距）为卡内拍板项「spike 后定」，本版默认
river_count=3/max_edges=24/spacing=6 为首版实现档（模板可调）；默认 seed=7 的河
偏短（4-10 边、全部 no_candidate 停止——被角点预留与双岸验证困住）属参数口味非
合同缺陷；② 默认参数下生成河水位 profile 恒 0（沿岸高程全 1 → min(岸高)−1=0）
——水位口径 = 逐段 profile 字段与单调合同均已满足，「逐段可变」在河爬上更高
双岸时自然出现；③ first_pass_valid 在连通性失败 seed 上为 false——断路图是合法
产物（v1 同口径），重试/修复循环属 WORLD-04；④ 旧 .meta.json 内 params 键
moisture_frequency 与新 to_dict 键不再互读（GENERATOR_VERSION+1 显式登记该
改名；grep 证实仓库内无任何 from_dict 消费旧键的路径）。**评审结论**：WORLD-01/
02 独立复核**通过**——门禁自跑 341/0、删 scripts/ui 后复跑仍 341/0、卡表测试锚
全部真实存在，反例探针（v1 单遍等价 ×5 组参数、河网角点度 ≤2 且无跨链共享 ×8
seed、水系开关同 map digest、岛图具名停止且不改图、同 seed 三跑/模板同源/三通道
override 独立）全部 0 失败，仅 2 处 low 级注释/口径噪声（见下）。

**遗留 low（评审登记，两处）**：① 门面头注段数口径不准——
`scripts/content/map_generator.gd:6-7`「噪声地理骨架 + 量化 + 可玩校验三段实做，
其余六段按模板跳过」：legacy 路径实际**实跑 4 段**（config/geography/quantize/
playability）、**跳过 5 段**（hydrology/settlement/allegiance/roads/presentation）
，config 段并不跳过；`world_pipeline.gd:13-15` 同句同病（沿袭卡表「三阶段」说
法）——实况见 world_pipeline.gd:72-82 STAGES 九段 + _run_stage(:203-226) 四实做/
五跳过，test_stage_diagnostics_shape_and_diffable 断言 skipped_count==4（非 5 非
6）；② `docs/evidence/m1a/render_probe_stats_forwardplus_1280x720.txt:2` 本批夹带
一处与 T5-A 无关的证据文件时间戳重写（git diff 全文唯一差异 = 时间戳行
2026-10-11T20:39:57 → 22:06:19，1 insertion 1 deletion；评审时记 21:45:02，终跑
gate_all 探针重出后再移）——批次边界噪声，像素统计逐位一致无实质影响。

**边界声明（照抄方案自身口径）**：T5 完整世界生成挂 M3 门（或主创另立地形里程碑）；
T6 规则深化沿 03 M3 决策门；M2 资源定稿前 POI 用 role 占位。指标数值（交付率/帧时
间等）全为候选目标，T0 基线实测前不构成承诺。

---

## M1b · RTwP 内核证伪（详见 03 v2）

> 范围对账（2026-10-09，评审 S8）：03 §M1b 范围 1~14 ↔ 本文 T1~T15
> （范围 5 = T5+T6、12 = T13、13 = T14、14 = T15）。

### M1b-T1 ⭐ 脉冲时钟与驱动
- 全局时钟（1x=2s 测试值）/ 变速档 / 暂停（原子性：单次结算完成后生效）；
  headless 固定步进驱动（测试口径）
- 验收：暂停/变速/恢复单测；headless 与实时两种驱动共用同一逻辑层

### M1b-T2 ⭐🔒(T1) 双充能轴
- 移动费/攻击费独立充能、首攻半费、移动期间攻轴冻结、无指令空转消耗
- 验收：四条规则各 ≥1 单测（用 10 §2 双费表测试值）

### M1b-T3 ⭐🔒(T1,T2) 指令系统
- 移动/攻击/撤退/自动还手开关；实时生效、随时改令、无锁定窗口；
  攻击指令目标在射程外 = **移动攻击**（自动接近、期间攻轴冻结，进射程后转入攻击，
  06 §2.3，2026-10-09 拍板）
- 验收：改令立即改变后续行为；撤退=远离最近敌的移动指令，单测；
  移动攻击全程轴行为单测（接近期间攻轴冻结、进射程后充攻轴）

### M1b-T4 🔒(T3) 寻路与移动执行
- 路径规划（通行性硬约束 + 代价函数接口；**地形/高程修正值本期恒 0**——挂 M1a-T2
  `mods` 扩展位、M3 拍板后才填，2026-10-09 评审 C7 厘清）+ 每次充能满前进 1 格
- 验收：绕障/最短路单测；移动中改目标重规划

### M1b-T5 ⭐ 战斗管线
- 07 v6 公式 + 增减伤钳制 [0.2,4.0] + 浮动/命中/暴击/反击率四掷（可复现种子）；
  反击系数乘区（10 §3 测试值）
- 验收：与 `damage_calc.html` 同参数结果一致（对表测试）；同 seed 重放一致

### M1b-T6 ⭐🔒(T5) 即时反击 + 反击率
- 被打立即反击（不耗攻轴、射程=自身射程、能力位）+ **反击率掷骰**（近战高/远程低；
  触发后当前率 −5%、每脉冲 +1% 恢复，10 §3 测试值）；
  **反击不递归**（反击伤害不构成"被打"、不触发再反击）、阵亡不反击
  （06 §3.2，2026-10-09 拍板）；~~离开敌邻格 → 每个相邻敌一下普通反击~~
  （过路费体系移除，2026-10-09 主创拍板，见 06 §3.3）
- 验收：反击规则各 1 测；反击率衰减/恢复曲线单测（固定种子）；
  反击不递归与阵亡不反击边界各 1 测；被 2~3 敌围攻时反击频率明显滑落
  （主观可感即可、不量化——主创 2026-10-09 口径，评审 P1-10 收口；
  −5%/+1% 等数值随模拟与体验调，不做纸面深析）

### M1b-T7 🔒(T4,T5) 冲锋 tag
- 骑枪移动 ≥2 格后的主动攻击 → 立即结算 ×2（不等攻击费，同四掷口径）；
  **接敌判定 = 攻击指令逻辑、目标唯一**：近战 = 移动指令指向敌所占格即攻击、
  远程 = 指定目标直接结算；途经敌邻格不触发、不打一片（06 §3.4，2026-10-09 拍板）；
  **冲锋=首攻**：消耗首攻半费权益，攻轴从当前值起正常充能、下一刀全额费
  （06 §3.4，2026-10-09 拍板）
- 验收：触发/不触发边界各 1 测（含"途经敌邻格不触发"边界）；冲锋后攻轴衔接单测
  （首攻权益消耗、技能施加 tag 同口径）

### M1b-T8 🔒 战斗前哨：确定性包围士气
- 每脉冲**先算**：相邻敌 4/5/6 面三档减益 → −10%/−15%/−25% 攻防（10 §4 测试值；
  2026-10-09 评审 C4 统一三档）
- 验收：4/5/6 面/解除四态单测；结算顺序（先士气后行动）单测

### M1b-T9 ⭐🔒(T1~T8) 结算顺序集成
- 士气 → 行动（势力序玩家先 → 棋子 ID 序）→ 反击即时 → 账期桩
- 验收：**3 势力同脉冲争抢**确定性单测；headless 同 seed 整局重放逐事件一致

### M1b-T10 🟦 棋子 3D 原语 + 状态条
- 胶囊/方块按兵种区分 + 朝向控制 + 血条/充能黄条（视野内敌棋同显）
- 验收：挂接 M1a 拾取/高亮；30 棋子帧率无压力

### M1b-T11 ⭐ 事件对象化（ADR-7）
- 结算产出事件流（移动/攻击/反击/冲锋/士气变化/阵亡——**六类**；
  ~~过路费~~ 事件随体系移除删去，2026-10-09）；
  UI 只消费事件，不直接读结算内部
- 验收：上述六类事件各 ≥1 单测，且公共信封五字段齐备（`tick`/`type`/`faction_id`/
  `unit_id`/`payload`，ADR-7 最小契约）；消费端遇未知 `type` 不炸（容忍性 1 测，
  为 M3 技能/M5 音效事件预留）；删 `scripts/ui/**` 测试全绿

### M1b-T12 🟦🔒(T3,T5) 随机合法 AI ×2
- 合法指令随机生成（有目标打、能动动、不非法）；与玩家同一指令系统
- 验收：整场无非法指令；headless 100 局无死锁

### M1b-T13 ⭐🔒(T9,T12) 自战统计工具（= 模拟器 v7）
- 复用引擎 headless 跑沙盒：胜率（**按势力先后手分组**——06 §2.2 偏置登记的
  监控口径，2026-10-09 增）/ 时长分布 / 互砍致死脉冲数 / 拉锯账期数 /
  4 面以上包围事件数·局（为 06 §3.6 包围阈值复检供数，评审 P2-7）报表；
  **v7 为新建文件**（如 `tools/combat_sim_v7.gd`），不覆盖旧 v6.1——旧文件已加
  归档头、两份模拟器并存时以本条口径区分（评审 P2-5）
- 验收：出报表并与 10 §2 派生锚对表（互砍 ≈40~48 脉冲、拉锯 1~2.5 账期——
  锚为主动刀口径、**待本工具首报回填重算**，见 10 §2 注，2026-10-09）；
  `tools/combat_sim.gd` 旧回合口径归档保留
- **增量交付（2026-10-09 增，评审 S5）**：T5 管线落地后即出"双兵种互砍"最小报表
  先对 10 §2 互砍锚，随 T6~T9 扩到全量——判断工具不等关键路径末端，
  下方"定期跑报表"自 T5 后生效

### M1b-T14 🟦 CI 恢复
- Gitee CI：`--headless --import` + 测试套跑绿为合入门禁
- 验收：故意提交红测试被 CI 拦截

### M1b-T15 🟦🔒(T9) 最简快照（防呆项，缩范围砍序末端；2026-10-09 增，评审 S7）
- `BattleState` 全量 `to_dict()/from_dict()`（含双充能轴、反击率当前值等运行态
  **与 RNG 内部状态**——续跑一致性与 03 §M2-7 正式口径同源，RNG 快照成本仅一个
  流状态/游标；2026-10-09 复审 N1 对齐，~~"RNG 不快照"~~ 作废）
- 验收：dump→restore 往返一致单测；中断续跑演练一次

**M1b 收尾**：03 v2 验收清单逐项跑（含主观门）+ `docs/retro/M1b.md`；
若主观门不过 → 回 00 重议时间模型，地形层保留。

---

## 实施顺序与砍序（只定顺序、不估时——2026-10-09 主创拍板，评审 P1-4 收口）

> ~~产能基线/周数折算~~ 时间概念已移除（03「范围优先级与设计债门」）；
> 本节只保留任务依赖链与缩范围时的砍序。

```
M1a  T1 → T2 → T3 → T4 → T5 ─┬→ T7 → 收尾
     T8/T9 并行 ─────────────┴→ T6 并行
M1b  T1 → T2 → T3 → T4 ─┐
     T5 → T6 → T7/T8 → T9 ─┤→ T10~T12/T15 并行 → T13 → T14 → 收尾
```

- 关键路径 M1a：T1→T2→T3→T4→T5；缩范围砍序（与 03 砍段次序对齐，2026-10-09 评审 S3）：
  T8 美术分支 → T9 随机生成（保固定测试图）→ T4 高程降两档 → T6 手感项（保边界钳制）
- 关键路径 M1b：T1→T2→T3→T5→T6→T9→T13；需缩范围时的任务级砍序（统一口径，
  2026-10-09——原 03"快照首砍"与 04"先缓 T14"两说随时间概念移除合并为一条链）：
  **T14 延后（CI 至收尾）→ T10 减配（状态条最简）→ T15 砍（最简快照，砍后中断续跑
  由 headless 同 seed 重跑替代）**；**T12 双 AI 不可砍**——"3 势力争抢"是证伪验收项
  （03 §M1b 验收 3），砍它 = 击穿本期定义（~~原"降 T12 为单 AI（验收口径同步降）"~~
  作废，评审 S3）
- 双费表/反击/士气/时钟全部按 10 测试版起步，开发中定期跑 T13 报表回写 10

## M2+ 粗粒度占位（到里程碑前再细拆）

- M2：资源终表 / 招募队列 / 账期结算 / 附属建筑 / 胜利条件 / 平推 AI / 存档 / 地图数据化（8 个任务族）
- M3：迷雾 / 地图精调 / 地形数值修正 / 将领养成（前置 P0-将领-1）/ 施法 / 美术二代（6 个）
- M4：AI L1/L2 / 节律 / 旋钮 / 自战回归（4 个）
- M5：音效 / 教学 / 本地化 / export / modding 文档 / IP 自查（6 个）
