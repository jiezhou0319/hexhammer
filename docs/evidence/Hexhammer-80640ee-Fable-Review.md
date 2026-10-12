# Hexhammer 80640ee 代码评审（Fable）——世界逻辑增量（8c54da0..80640ee）

> 源码锚：所有行号指向 immutable blob `https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/<path>#L<n>`（HEAD 80640ee，10 commits / 146 files / +33k）。
> 口径：只读审查 `/home/user/workspace/hexhammer-review-80640ee`；全部反例在独立副本 `/tmp/hh_fable2` 跑出（探针脚本留档 `/home/user/workspace/fable806-probes/`，日志 `fable806-sweep-probe.log` / `fable806-validator-probe.log` / `fable806-boundary-probe.log`）。引擎 Godot 4.7.2 headless（本机仅 Compatibility/llvmpipe，非 Forward+）。
> 分工：主审负责 clean import / 384 suite / seed 银行 / gate_all / scene_check / render 与几何；本报告聚焦 world_data / world_pipeline / world_validator / river_network_generator / road_network_generator / settlement_generator 的算法正确性、确定性、失败-修复语义、保存加载与生成期通行。主审实证的集成缺陷在 §4 以「主审复现」标注。
> 分级：**高** = 默认配置可复现、影响交付承诺；**中** = 实证缺陷但需特定配置/手工数据；**低/观察** = 口径/注释/规划。RTwP 战斗与气候不实现属主创决定，不计缺陷；presentation 阶段国界 mesh 未解锁属明示范围外。

---

## 0. 结论一页

| 范围 | 结论 |
|---|---|
| WORLD-01 管线 / 模板 / 通道 | 结构可信；修复循环三动作中 `hydrology_redraw` 在默认管线实际不可达、`roads_reconnect` 对非并列类失败空转（S-2） |
| WORLD-02 河网生成 | 生成器输出合法且确定；但**数据层校验器不查跨河角点共享与边序列方向**，「汇流首版由校验器拒绝」「edges[0]=源边」两条合同只在生成器侧成立，加载的 `.world.json` 不受保护（S-3、S-4） |
| WORLD-03 聚落/势力 | 适居度/出生区/归属生成逻辑自洽；`resource_budget=0` 边界与校验器文档互相矛盾、必失败（S-6） |
| WORLD-04 校验/修复/银行 | 银行 11/11 真实；但默认模板 24×16 扫 80 seed 有 2 个失败，且 4 次 attempt 错误**逐字相同**（修复空转）；路网连通校验把「路口相接」判为断路（S-1、S-2、S-5） |
| WORLD-05 自动路网 | **默认配置可复现的逻辑缺陷**：任一聚落对不可达即整段失败，即便 MST 不需要该对（seed 50@24×16）；`max_road_delta=-1`（模板 validate 明示合法）使所有边被拒、必失败（S-1、S-6） |
| 保存/加载 | to_dict/from_dict 往返 digest 一致；形状层拒绝面齐全；`meta.world_digest` 不在加载/校验面核对（观察） |

**不夸大**：以上没有一项会让 384 suite 变红或让银行 11 seed 失败；它们是「验收声明 vs 实际合同」的缺口与边界 bug。`docs/04-tasks-m1.md` 对 WORLD-04 写明「100/100、≥95% 为候选目标非实测承诺」，本报告按该口径给出实测：24×16 默认模板 seed 1..80 = 78/80 首过（97.5%），60×40 seed 1..60 = 60/60 首过。

---

## 1. 已证实缺陷（默认模板特定种子、手工数据或边界配置）

### S-1【高】路网生成器：任一聚落对不可达即整段失败，即便 MST 并不需要该对；默认模板 24×16 seed 50 复现

- 位置：[`road_network_generator.gd#L126-L147`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/road_network_generator.gd#L126-L147)。`blocked` 收集**所有** `pair_cost == INF` 的聚落对（L128-130），tier2 重算后仍 INF 就 `return _disconnected_fail`（L145-147）——这发生在 Kruskal（L148-167）之前，没有先判断「剩余可达对能否把 n 个聚落连成一棵树」。
- 复现（`fable806-sweep-probe.log`，默认模板 `WorldTemplate.make_default()` 改 24×16，`generate_validated(t, 50)`）：
  ```
  FAIL seed=50 stage=roads attempts=4 actions=[roads_reconnect ×3] identical_errors=true
  err=路网生成失败：ROAD_NETWORK_DISCONNECTED：必需聚落对（格 34 ↔ 69，poi 2/4）无法连接——阻挡为地形（高差/禁入面），无河段涉入
  DIAG2 seed=50: pair 0-1 cost 109 / pair 0-2 cost 43 / pair 1-2 cost tier1=inf tier2=inf tier2_no_forbidden=146
  ```
  三聚落在格级与边级（Δ≤1、禁渡）全部两两可达；对 (poi2,poi4) 之所以 INF 是因为**第三方出生区 footprint / 资源格被列入禁入面**（[`#L91-L105`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/road_network_generator.gd#L91-L105)）堵住了唯一 Δ≤1 通道；而 MST 只需 (0,2)+(0,1)（成本 43+109），完全不需要 (1,2)。
- 影响：默认配置下「必需聚落全部连接」可满足却被判失败；修复循环随后选 `roads_reconnect`（见 S-2）4 次空转，整张图进失败库。24×16 组 80 seed 中此类 1 例；60×40 60 seed 未见（大图通道多）。
- 修复：把 L138-147 的「逐对失败即返」改为「tier2 重算后仍 INF 的对直接不入 `edges`」，Kruskal 结束后若 `mst_pairs.size() < n-1` 再对**未并入的分量对**调用 `_disconnected_fail`；错误串同时列出禁入面来源（第三方 zone/资源格 id），不要笼统写「阻挡为地形」。
- 测试：三聚落 fixture，令 C 的 7 格出生区横在 A–B 唯一 Δ≤1 通道上、但 A–C、B–C 可达；断言 `generate()["ok"]==true`、`trunk==2`、`WorldValidator(require_road_network).ok`。

### S-2【中】修复循环对地形/禁入面类失败选 `roads_reconnect`，4 次 attempt 错误逐字相同（空转）；`hydrology_redraw` 在默认管线不可达

- 位置：[`world_pipeline.gd#L263-L271`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/world_pipeline.gd#L263-L271)（阶段硬失败 `roads` → 恒 `roads_reconnect`）、[`#L303-L316`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/world_pipeline.gd#L303-L316)（只 bump roads 通道）；roads 通道唯一消耗点是等成本并列改道 [`road_network_generator.gd#L343-L346`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/road_network_generator.gd#L343-L346)——改道不能改变可达性，对 INF 对无效。
- 复现：seed 50（S-1）与 seed 59（24×16 默认）均 `identical_errors=true`：
  ```
  FAIL seed=59 stage=roads attempts=4 actions=[roads_reconnect ×3] identical_errors=true
  DIAG seed=59: poi0(28) 与 poi2/poi4 格级连通=false（独立陆块），Δ 不限+河全开仍 inf
  ```
  seed 59 是真正的陆块分离（聚落被放在不连通的陆地上），唯一有效修复是 `settlement_repick`（poi 通道），但动作表恒选 roads。
- 另：`_repair_action_for` 的 `hydrology_redraw` 分支（[`#L276-L281`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/world_pipeline.gd#L276-L281)）只在 playability 报出 `RIVER_*/WATER_*/WORLD_DATA_INVALID` 时触发；生成器产出的河网在 hydrology 阶段已全量 validate（[`#L638`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/world_pipeline.gd#L638)），失败即阶段硬失败 → `_stage_repair_action("hydrology")`。两条路径在默认管线均无实例；卡表「修复动作三件」实际只有 `settlement_repick` 有效。
- 影响：失败 seed 的 4 次 attempt 是纯重复计算（60×40 约 1.3 s/次），且「修复不动 locked」在这类失败上无从验证。`test_repair_success_meta_and_first_pass` 只锚 NO_VALID_SPAWN→settlement_repick 路径。
- 修复：`_disconnected_fail` 返回结构化原因（`"cause": "terrain"|"forbidden"|"river"`），管线按原因选动作：terrain/forbidden → `settlement_repick`，river → 先 `roads_reconnect`（tier2）再 `settlement_repick`；并在 `generate_validated` 内检测连续两次 attempt 错误串/世界摘要相同即提前终止（避免空转占满 4 次）。
- 测试：对 seed 59@24×16 断言 `repair_actions` 含 `settlement_repick`；对任意失败断言 `attempts_trace` 中相邻两次的 `error` 不完全相同或循环提前退出。

### S-3【中】数据层校验器不查**跨 reach 角点共享**：两条河在角点相接/汇流形态通过 `WorldData.validate` 与 `WorldValidator`

- 位置：[`world_data.gd#L628-L672`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/core/data/world_data.gd#L628-L672)（`visited_corners` 是**单 reach 局部**变量，逐 reach 重置）；跨 reach 只查边复用 [`#L913-L920`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/core/data/world_data.gd#L913-L920)（`RIVER_EDGE_REUSE`）。而类头 [`#L126-L128`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/core/data/world_data.gd#L126-L128) 与 04 §WORLD-02 登记「汇流（多前驱）初版校验器拒绝」。
- 复现（`fable806-validator-probe.log` V1，8×6 平地图 + 生成器长出的 reach0，再手工加 reach1 自 reach0 的内部角点 66 出发到岸边）：
  ```
  V1 reach1=[(11,20),(11,19),(10,11),(3,10)] 源角点 66 = reach0 edges[0]/[1] 的共享内部角点
     → WorldData.validate='' WorldValidator.ok=true   角点交集 reach0∩reach1 = [66]
  ```
  这正是提案「别默认没有重复边等于无环」要防的形态：两条边链在一个物理角点相接（T 形/汇流/交叉的最小表达），边级零复用，校验器全绿。
- 影响：生成器（[`river_network_generator.gd#L70-L71`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/river_network_generator.gd#L70-L71) 全局 `used_corners`）自己不会产出，但 `.world.json` 手工/外部产物、以及未来「汇流第二版」开启前，数据层对此零防护；水面条带几何在共享角点处会重叠（WaterGeometryBuilder 逐边独立发射）。`test_acyclic_corner_level_independent_and_cross_reach` 只验证生成器输出，不验证校验器拒绝。
- 修复：把 `visited_corners` 提升为 `_validate_rivers` 级全局字典（reach 间共享），命中他 reach 角点报 `RIVER_CONFLUENCE`（与 RIVER_CYCLE 分码——日后汇流开启时只需放开此码）。
- 测试：以 V1 构造为 fixture，断言 `validate()` 以 `RIVER_CONFLUENCE` 开头、`WorldValidator` 码表含该码。

### S-4【中】`reach.edges` 的「源→河口合同序」不被校验：乱序序列通过校验、落盘重载仍绿，急弯判据随之漂移

- 位置：[`world_data.gd#L653-L660`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/core/data/world_data.gd#L653-L660)（链行走允许「接首端」，注释明说「边序列是无向路径……哪端是上游不保证」），与字段合同 [`#L135-L137`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/core/data/world_data.gd#L135-L137)「edges[0]=源边、edges[last]=终点边、相邻边须共角点（序列连续）」矛盾。
- 复现（V2/V6）：reach0 原序 `[(11,12),(12,20),(12,21),(12,13),(5,12)]`，交换前两项后 `validate=''`；写成 dict 乱序后 `from_dict` 非 null、`validate=''`。`river_bend_is_sharp` 原序 `[T,T,T,F,F]`、乱序 `[T,F,T,F,F]`——同一条河的桥址偏好集（[`road_network_generator.gd#L270-L279`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/road_network_generator.gd#L270-L279)）与 `water_levels` 单调判定（按索引）都依赖「索引序 = 流向序」。湖出口校验 `r.edges[0] == lk`（[`#L954`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/core/data/world_data.gd#L954)）同理。
- 影响：中低——生成器产出恒有序；但合同口径「数据层零冗余、序即流向」在加载面不成立，后续消费者（Strahler/汇流、渲染流向箭头）若信任序列会被手工/损坏文件误导。
- 修复：校验器只允许「接尾端」生长（`edges[k]` 必与 `edges[k-1]` 共角点且新角点为 fresh），接首端即报「序列不连续/方向倒置」；若有意保留无向容忍，请改合同文字并在 `from_dict` 规范化为单一方向。
- 测试：乱序 fixture 断言拒绝；原序通过。

### S-5【中】`WorldValidator` 路网连通只按「同一条 road.cells 含两个聚落锚」并查集，经**非聚落路口**相接的路网被判 `ROAD_NETWORK_DISCONNECTED`

- 位置：[`world_validator.gd#L156-L192`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/world_validator.gd#L156-L192)：L165-174 对每条 road 只收集 `idx_of_anchor` 命中的格并 union，普通共享格（路口，`world_data.gd#L193-L195` 明确合法）不参与连通。
- 复现（V3，9×5 平地、A=(2,0)、B=(2,8)）：单路 A→B `ok=true`；同一物理路网拆成 road0=A..X、road1=X..B（X=(2,4) 路口，`WorldData.validate=''`）→ `ok=false`，`必需聚落未全连通：2 个聚落分裂为 2 个道路连通分量 [[18],[26]]`。
- 影响：当前生成器每条路都是锚到锚（第三方锚在禁入面内），所以银行/测试不会触发；但 (a) 手工 fixture / 任何按路口拆路的产物被误判；(b) 它恰好掩盖了 S-1 的正确解法——「B 路接到 A–C 路的路口」这种合法网络会被校验器判断路（V4 末行：手工路网 `WorldData.validate=''` 而 `WorldValidator.ok=false`）。
- 修复：按**格**做并查集（所有 road.cells 两两相邻对 union；锚格天然入集），再取各聚落锚所在根；注释 L156 与实现同步。
- 测试：V3 两路拆分 fixture 断言 `ok=true`。

### S-6【中】边界配置：模板 `validate()` 放行的值在生成期必失败（口径三处不一致）

1. `max_road_delta = -1`：模板 [`world_template.gd#L217-L218`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/core/data/world_template.gd#L217-L218) 写「-1 = 不查」，校验器确实不查，但 Dijkstra [`road_network_generator.gd#L326-L328`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/road_network_generator.gd#L326-L328) `delta > -1` 对每条边为真 → 零边可走。复现 B1：`template.validate=''`，seed 7 直跑 `ROAD_NETWORK_DISCONNECTED……阻挡为地形`。（`max_bridge_bank_delta=-1` 在 L259 有 `>= 0 and` 守卫，B3 通过——同文件两处写法不一致。）
2. `resource_budget = 0`：模板 [`#L204-L205`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/core/data/world_template.gd#L204-L205) 与校验器 [`world_validator.gd#L19-L20`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/world_validator.gd#L19-L20) 都写「0 = 不查预算只查可达」，但生成器 [`settlement_generator.gd#L362`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/settlement_generator.gd#L362) 把 0 当硬环距（只剩主城格本身，而主城格已在 `used_foot`）。复现 B2：`NO_RESOURCE_SITE：势力主城 65 周围（可达 ∧ 环距 ≤ 0 ∧ 零冲突）无可行资源点位`，且 `resource_count=3` 默认 >0 必触发。
3. `locked = ["cell:999999"]`（越界格 id）：模板 validate 放行（B5），`locked_cells()` 不查界内；管线不报错（B5 ok=true）——无害但应与「reach 级锁显式拒绝」同纪律在 validate 拒绝。
- 修复：Dijkstra 加 `max_road_delta >= 0 and` 守卫；生成器对 `budget<=0` 跳过环距过滤（或模板把 0 定义为非法并改默认文案）；locked 条目在 `validate()` 查 `< width*height`（validate 已知尺寸）。
- 测试：三组边界各一用例（模板 validate 结果与管线结果一致）。

---

## 2. 实证观察（非默认、或口径问题）

### O-1【低】`WorldValidator` 未覆盖「资源点占道路格 / 落入出生区」；`WorldData.validate` 不查主城格 owner
- 复现 V5：资源 POI 格在 road.cells 内、或在他人 SPAWN_ZONE footprint 内，两层校验均 `ok=true`。生成器侧在放置时排除（[`settlement_generator.gd#L364-L366`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/settlement_generator.gd#L364-L366)、路网侧 [`road_network_generator.gd#L99-L101`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/road_network_generator.gd#L99-L101)），所以是「生成器守、校验器不守」——与 WORLD-03 验收「不占桥端/河床/道路禁用区域」的校验面不对称。V6 另证：state0 主城格 owner 改为 1，`validate=''`、`WorldValidator.ok=true`（[`world_data.gd#L1064-L1082`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/core/data/world_data.gd#L1064-L1082) 只查值域/水格）。
- 建议：POI_FOOTPRINT_CONFLICT 扩到 RESOURCE kind（道路/桥端/河岸/他方 zone）；`STATE_CAPITAL` 增查 `cell_owners[capital] == state_id`。

### O-2【低】保存/加载：往返 digest 一致（V6），形状层拒绝面齐全；`meta.world_digest` 不被核对
- V6：`write_world→read_world` 非 null、`world_digest` 相等、validate 空；`cell_owners` 长度错 → `OWNER_LENGTH` 正确拒；`meta` 缺键 → null。`meta.world_digest` 改为 `deadbeef` 后仍可加载且校验绿——摘要只写不读（§10「摘要只锚世界事实」允许，但银行「可加载复验」若要防篡改/错配，应在 `MapIO.read_world` 旁提供 `verify_digest(map, world)`）。
- 已登记遗留：`worldfail_no_valid_spawn_4x4.meta.json` 的 `generator_version=3`（04 文档已自述）。

### O-3【低】`grow_states` 一标签多源 Dijkstra（主审静态提示）
- [`settlement_generator.gd#L424-L464`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/settlement_generator.gd#L424-L464) 每格只保留一个 (dist, owner)，成本随扩张方 `expansionism` 不同——这不是「逐势力独立最短路取 min」，而是 Azgaar 式**竞争生长**（扩张只能经本方已占格）。04 §T5-B 完成边界已明示「竞争生长语义……曾按独立最短路实现致 28 格差异，已纠正」，且 `test_state_growth_matches_brute_force_oracle` 用带标记暴力松弛对齐。按文档承诺这是设计语义而非缺陷；但注释 L396「并列成本取小 state_id」不准确——并列由**堆弹出序**决定（先松弛者胜，`nd < dist[v]` 严格），同输入确定但不保证小 state_id。建议改注释或在 `nd == dist[v] and ou < owner[v]` 时改判以兑现文字。

### O-4【低】`_disconnected_fail` 归因与实情脱钩
- [`road_network_generator.gd#L441-L473`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/road_network_generator.gd#L441-L473) 的 BFS 不带 `forbidden`/`max_road_delta`/`used_links`，只能分「河 / 非河」；S-1 的真实原因（第三方 footprint 禁入）与 V4 走廊场景（`used_links` 禁复用：11×13 两格走廊三聚落，`ok=false` 而边级 A↔C、B↔C 均可达、手工路口网络 `WorldData.validate=''`）都被笼统报「阻挡为地形」。V4 同时说明 MST 落路阶段 [`#L176-L186`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/road_network_generator.gd#L176-L186) 在 `used_links` 下的第二条干线若必须复用第一条的 link（单桥址/单格走廊）会硬失败，而「汇入既有路的路口」是合法解——与 S-5 一起修（允许目标为「已落路网任一格」而不只是对端锚）。

### O-5【低】`hydrology` 阶段不接收 `locked_cells`
- [`world_pipeline.gd#L610-L617`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/world_pipeline.gd#L610-L617) cfg 无 locked；若 `hydrology_redraw` 日后真被触发，新河岸可落在锁定 footprint 上，随后 `_spawn_feasible` 复核会报「锁定格事实被破坏——修复器 bug」（[`settlement_generator.gd#L228-L230`](https://github.com/jiezhou0319/hexhammer/blob/80640ee23e0c9db6ab0968ea7ca0488223aa62dd/scripts/content/settlement_generator.gd#L228-L230)）。目前因 S-2 所述该路径不可达，属前置风险。

### O-6【观察】测试锚脆弱点
- `test_repair_success_meta_and_first_pass` 钉死 8×5 seed 7 `attempts=4`，任何 poi 通道消耗变化都会翻红（文档已自述「漂移 = GENERATOR_VERSION 变更」，可接受但请在用例注释写明预期漂移处理）。
- `test_mst_connects_all_settlements_zero_disconnected` 的并查集 oracle `_settlements_connected` 与被测校验器同构（同样按锚并查），无法发现 S-5。

---

## 3. 验收声明对照（docs/04-tasks-m1.md T5-A/T5-B）

| 声明 | 实测 |
|---|---|
| WORLD-02「角点级无环……跨链不汇合不交叉」 | 生成器 ✔；**校验器不查跨链角点**（S-3） |
| WORLD-02「edges = 源→终点合同序」 | 生成器 ✔；校验器接受乱序（S-4） |
| WORLD-04「失败动作按固定顺序选通道（河→聚落→道路）」 | 河路径不可达、道路路径对地形失败空转（S-2） |
| WORLD-04「100 个发布 seed……≥95% 候选目标」 | 24×16：78/80 首过；60×40：60/60 首过；2 失败中 1 例是 S-1 逻辑缺陷（可修）、1 例陆块分离（应改修复动作） |
| WORLD-05「必需聚落全部连接；禁桥时无法连接则返回失败」 | 可连接却失败（S-1 默认、V4 特殊配置）；失败归因笼统（O-4） |
| WORLD-03「不占桥端/河床/道路禁用区域」 | 出生区校验 ✔；资源点只在生成器守（O-1） |
| 模板「-1 = 不查 / 0 = 不查预算」 | 两处在生成器侧必失败（S-6） |

---

## 4. 主审实证并入（标注「主审复现」，细节以主审日志为准）

- **【高·集成】桥面不可拾取（主审复现，`/home/user/workspace/review806-integration.log`）**：固定图 1 crossing，`MapView.build_with_style(world)` 与 `MapPicker.setup` 均 true，桥面中心射线原始命中 `DeckCollision_c20_r0`（y≈1.06），但 `picker._tables` 无该 body id，`pick_world_ray` 返回 null——`MapView._mount_road` 建了 deck body，`MapPicker.setup` 只登记 terrain chunk 表，不登记路面/桥面；picking scene_check 11 绿是因为工具自注册独立 table，不走生产 picker。
- **【中·验收口径】银行样图水面差分 2 px（主审复现）**：Compatibility 下固定图 8/8（水 14657 px）；默认 60×40 银行样图 8/8 但 CHECK-W 水面差分仅 2 px、阈值 0。样图 JSON 实读：3 河长 4/3/5，32 水体全 `water_level=0`，第一河 `water_levels=[1,1,1,0]` 其余 0；水面 y=−0.5·step 被水格顶面 y=0 遮住（render_probe 自注）。这是「默认自动世界水面」的验收阻断（T3 水面构建器与 T5 生成水位的跨批错配），不能视为已修；04 已登记为后续卡。样图无桥，故银行渲染不能单独证明桥可见。
- **【低·环境】`test_world_pipeline` 20 s 子进程预算**：主审 gate_all/runner 两轮均在该文件超时（29 文件 367 用例 1 失败），单跑 17/0 耗 24.4 s；临时副本调预算 60 s 后 29 文件 384/0 exit 0、hang 故障仍 3 s 拦截——属环境耗时与预算失配，非断言 bug，建议 runner 预算随文件可配或拆分该 suite。
- **【观察·范围】**：`m1a_sandbox.gd` 仍以旧地图 `view.build` 入口、无 world/profile/style；`WorldPipeline` presentation 恒 skip、国界 mesh 未做——均为主创明示未解锁，不计缺陷；主审合成渲染图 `/home/user/workspace/Hexhammer-80640ee-Composite-World.png` 为临时拼装总景、非已集成 UI。

---

## 5. 修复优先级建议

1. S-1（Kruskal 前不因单对 INF 失败）+ O-4 归因结构化 —— 一次改动，直接提高默认交付率并让 S-2 的动作选择有依据。
2. S-2 动作选择按原因 + 空转提前终止。
3. S-5 校验器按格并查集（同时解锁 S-1 的「路口汇入」解法）。
4. S-3/S-4 校验器跨 reach 角点 + 方向序（加载面合同补齐）。
5. S-6 三处边界口径统一。
6. O-1/O-2/O-3 注释与扩码。

## 6. 复现命令（独立副本）

```
cp -r hexhammer-review-80640ee /tmp/hh_fable2 && cp fable806-probes/*.gd /tmp/hh_fable2/tools/
G=godot-bin/Godot_v4.7.2-stable_linux.x86_64
$G --headless --path /tmp/hh_fable2 --script res://tools/fable_probe_sweep.gd -- sweep 24 16 1 80
$G --headless --path /tmp/hh_fable2 --script res://tools/fable_probe_sweep.gd -- diag2 24 16 50
$G --headless --path /tmp/hh_fable2 --script res://tools/fable_probe_sweep.gd -- diag 24 16 59
$G --headless --path /tmp/hh_fable2 --script res://tools/fable_probe_sweep.gd -- boundary
$G --headless --path /tmp/hh_fable2 --script res://tools/fable_probe_validator.gd
```
