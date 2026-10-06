# 02 · 架构设计与决策记录（ADR）

> **状态：待审（2026-10-06 自 docs/archive 恢复，不再视为冻结件）**
> 当前**唯一已认可**的是 `docs/00-vision.md` v4 的总体思路；本文件其余内容**尚未敲定**，
> 未标注处一律视为"沿用候选"而非定稿。与 00 的冲突已在文内标出。
>
> 每个重大决策：背景 → 备选 → 选择与理由 → 后果。改架构先改这里。

## 1. 分层总图

```
┌─────────────────────────────────────────────────────┐
│ 表现层  scripts/ui  + scenes                         │
│   渲染 / 相机 / 输入 / HUD —— 只发命令、只听事件      │
├─────────────────────────────────────────────────────┤
│ 命令层  scripts/core/command                         │
│   Move/Charge/Shoot/EndPhase…（玩家、AI、回放、      │
│   网络共用同一入口）                                  │
├─────────────────────────────────────────────────────┤
│ 引擎层  scripts/core/battle_engine + turn            │
│   校验 → 执行 → 产出事件流 → 推进回合                 │
├─────────────────────────────────────────────────────┤
│ 规则层  scripts/core/rules（纯函数）                  │
│   命中/致伤/豁免/士气 —— 无状态，可独立跑万次模拟     │
├─────────────────────────────────────────────────────┤
│ 领域层  scripts/core/hex + state + data              │
│   六边形数学 / 战场快照 / .tres 数据模型              │
└─────────────────────────────────────────────────────┘
        依赖方向只能向下。UI 不知道引擎内部，引擎不知道 UI 存在。
```

**数据流（一次玩家操作）**：

```
鼠标点击 → InputController 组装 Command
  → BattleEngine.execute（校验+改 BattleState+产出事件）
  → 信号 logged/state_changed/battle_over
  → Renderer.queue_redraw / HUD 更新
```

## 2. 决策记录

### ADR-1 六边形坐标系：axial (q,r) 存 `Vector2i`，pointy-top
- 备选：cube (x,y,z 三元组)、offset (col,row) 直接存
- 选 axial：距离/邻居/寻路全 O(1) 简洁；offset 仅在地图生成与显示时转换（`Hex.offset_to_axial`）
- 后果：所有代码禁止直接对坐标做算术游戏逻辑，必须走 `Hex` 静态函数——坐标变换 bug 集中在一个文件
- 佐证：godot-hexgrid、Wesnoth 同样以 axial/cube 为内部坐标

### ADR-2 逻辑层不继承 Node（RefCounted + 纯函数）
- 备选：一切皆 Node 场景树（Godot 直觉写法）
- 选纯逻辑：① headless 单测/批量模拟不需要场景树；② 战斗可以瞬间解算完（AI/回放），动画是事后呈现；③ 避免 Node 生命周期耦合状态
- 后果：引擎信号经 Godot `signal` 机制发（RefCounted 支持信号），View 直接 connect —— 已验证可行

### ADR-3 内容数据用 Godot Resource（.tres），不自定义格式
- 备选：JSON/YAML + 自写解析（Wesnoth WML 路线）
- 选 .tres：编辑器原生编辑+类型检查+嵌套引用；GDScript `preload` 类型安全
- 后果：modding 玩家门槛比 JSON 高——缓解：M3 提供"JSON → .tres 导入器"或迁移到 JSON（届时再看，数据模型类不变，只换序列化）

### ADR-4 命令模式作为唯一变更入口
- 所有 BattleState 变更必须经 `Command → BattleEngine.apply_*`，引擎外不允许直改 state（测试代码豁免）
- 这一个约定同时解决：AI 复用（产出命令即可）、回放（记录命令序列+RNG seed 重放）、悔棋（命令可逆化，M3）、异步网络（命令序列化传输）
- 后果：新增玩家操作 = 新命令类 + 引擎 apply 原语，两处小改

### ADR-5 骰子集中注入（BattleRNG + seed）
- 规则代码禁止散落 `randi()`；同 seed 同战局 → 回放/测试确定性（Tessera 同思路）
- 后果：多人热座无问题；真网络对战需 lockstep 命令+seed 同步（远期，接口已留）

### ADR-6 特殊规则 = 数据挂载 + 效果注册表
- `SpecialRule.rule_id` → 引擎内效果表分发（现：frenzy/fear）
- 新规则= 新 .tres + 注册表一个 case，不改 UnitProfile/引擎主干
- 后果：规则间交互（frenzy×fear）要在注册表内显式处理，防止隐式耦合——M2 若规则 >10 条，重构为小型 ECS（组件=规则实例）

### ADR-7 事件流尚未结构化（当前为 String 日志）—— M1 重构为事件对象
- 当前 `logged(text)` 只是给 HUD 看的字符串
- M1 起产出结构化 `BattleEvent`（RefCounted 子类：DiceRolled/WoundApplied/UnitFled…），
  日志文本、动画、音效、统计都从事件流派生——这是回放与表现解耦的关键一步

### ADR-8 UI 层可抛弃、分两代
- 第一代（现有）：程序绘制色块，验证交互逻辑，零美术
- 第二代（M2）：`TileMapLayer`（原生六边形 tile）+ 单位场景 + Tween 动画，数据接口不变
- 后果：不追求第一代 UI 的"好看"，禁止在第一代上叠加视觉债

### ADR-9 版本与工程纪律
- Godot 4.3+ 特性集（向上兼容运行）；GDScript（不上 C#，见 00 支柱 4：单机发布体积与依赖）
- 测试：现有零依赖 runner；CI（M1 引入）：`godot --headless --import` + 跑测试，Git 提交前本地必跑
- 分支：main 常绿；功能分支短命；每个任务 = 测试先行或随附测试

### ADR-10 ⛔【已废止 2026-10-06】棋子粒度：部队级（将 + 兵数）——2026-10-05 v2 变更
> **废止理由**：与 `docs/00-vision.md` v4 支柱 3"棋子即兵"冲突——一枚棋子即一个独立
> 作战单位，无带兵结构、无编制、无兵数条；`TroopType / RegimentState / Lord` 三件套作废。
> 以下全文仅存历史，粒度决策待按"棋子即兵"重写（连同 §5 处置表）。
> 当前无代码迁移成本：`scripts/`、`tests/` 已在 2026-10-06 删除。
- **背景**：玩家要大地图、多派系、大军团，且操作不因规模崩溃。
- **备选**：① 单模型大军（Wesnoth 式）——操作量随规模线性爆炸，80 棋子/回合的微操不可持续；
  ② 团级 WFB 原味（rank&file 摆模型）——规则量 4~5 倍且与"大规模"互相拖累；
  ③ **部队级（选中）**：棋子=Regiment（将领+兵种+兵数），参照三国志 11 / HOMM。
- **领域模型变更**：
  - `UnitProfile` → `TroopType`（兵种模板：攻/防/T/Ld/速度/克制/特技）
  - `UnitState` → `RegimentState`（兵种引用、兵数 current/max、将领槽、经验、士气状态）
  - 新增 `Lord`（将领：Profile 属性/技能/装备 + State 存活/俘虏/位置绑定）
  - 解算粒度：一次交战 = 攻防骰按兵数抽象（如 attack_dice = clamp(兵数/N, 1, M) + 将领加成），
    具体口径 M1-T2 定并进 autobattle 校准
- **后果**：现有 demo 的"一棋子=一模型"数据要迁移（见 §5 处置表）；战场规模上限由
  棋子数（≤~150）而非模型数决定，寻路/渲染/操作全部可控。

### ADR-11 交战自驱：接触自动开打，玩家不下"攻击"指令
> **v4 对齐注（2026-10-06）**：方向与 `docs/00` 支柱 2 一致（玩家不点"攻击"、交火自动跑完）。
> 待定：解算时点须并入 WeGo 脉冲结算（规划下意图 → 脉冲移动 → 伤害轮），"每回合边界"这一
> 表述需重锚；"被远程射自动承受不还手"等细节同样待定。
- **规则**：部队移动进入敌相邻格（或宣告冲锋）→ 进入交战状态；此后**每回合边界自动解算一轮**
  攻防（先手按冲锋/速度），直到一方崩溃/被歼；被远程射自动承受不还手（射程外），被近战
  攻击自动还击。玩家可下的命令：移动/冲锋/撤退/技能——没有"攻击"按钮。
- **理由**：这是"大规模不微操"的核心；三国志 11 与 Dominions 验证过的手感；
  同时让回合边界（已有显式回合机）成为唯一解算时点，杜绝状态不一致。
- **后果**：回合机在 faction 回合开始时触发"交战结算"步骤（排在移动前）；
  事件流（ADR-7）成为战斗呈现的唯一来源——自动解算的每颗骰子都要进事件流供 HUD/回放消费。

## 3. 模块边界与"公私有"约定

| 模块 | 对外承诺（稳定接口） | 内部实现（可随意改） |
| --- | --- | --- |
| `core/hex` | Hex 静态函数、HexMap 查询、pathfinding | Voronoi 生成、内部 dict 结构 |
| `core/rules` | CombatResolver/Psychology 纯函数签名 | 内部日志组织 |
| `core/state` | BattleState 的只读查询（unit_at/living_units…） | 双索引表实现 |
| `core/engine` | apply_* 返回错误串、三个信号 | 内部所有 `_` 方法 |
| `ui` | 无（消费方） | 一切 |

**验收口径**：`scripts/ui/**` 删掉后，`tests/` 仍全绿——这是"逻辑与表现分离"的可执行定义。

## 4. 目标目录（M2 完成时）

```
addons/hexhammer/        ← hex 数学+寻路 addon 化（对齐 godot-hexgrid 惯例）
scripts/core/            ← 战锤规则域（data/rules/state/turn/command/engine）
scripts/content/         ← 战役/名单/地图等上层内容系统
scripts/ui/              ← 第二代 UI
resources/               ← 数据（units/weapons/rules/factions/maps/armies）
scenarios/               ← 剧本：地图+双方名单+胜负条件（.tres）
tests/
docs/
tools/                   ← 批量自战模拟器（平衡性验证，Tessera 思路）
```

## 5. 现有 spike 代码的处置决定（按 v2 粒度更新）

> **待重写（2026-10-06）**：本表按"部队级（将+兵数）"粒度写，与"棋子即兵"冲突；
> 且 spike 代码（`scripts/`、`tests/`、`scenes/`）已于 2026-10-06 删除，本表已无处置对象。
> 保留仅作参考：记录当时"保留 / 重构 / 抛弃"的分类依据。

| 保留不动 | 重构（M1） | 抛弃（M2 起） |
| --- | --- | --- |
| `core/hex/**`（六边形数学地图寻路——粒度无关）、`core/turn/**`、`command/**`、`core/rules/rng+psychology`、测试基建 | `battle_engine.gd`（事件对象化+自动交战结算）、`combat_resolver.gd`（部队级汇总解算）、`data/unit_profile.gd`→`troop_type.gd`、`state/unit_state.gd`→`regiment_state.gd`+新增 `lord*.gd` | `ui/map_renderer.gd` 程序绘制、`demo_battle.gd`、现有 5 个单位 .tres（改写为兵种+将领示例数据） |
