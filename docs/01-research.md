# 01 · 调研报告：现成项目与可借鉴点

> 2026-10-05 调研。目的：站在成熟项目的肩膀上，避免重复发明与踩已知坑。
> 结论先行：**没有"Godot 战锤战旗"级别的成品可以直接用**，最成熟的路径是
> Wesnoth 的数据驱动哲学 + godot-hexgrid 的六边形基础设施 + 自研战锤规则层
> （这正是目前的方向，调研后确认而非推翻）。

## A. 参考项目清单

### A1. Battle for Wesnoth（最重要参照系）
- <https://github.com/wesnoth/wesnoth> · C++ · 20+ 年历史的最成熟开源六边形回合制战棋
- **结构与哲学**：
  - 引擎与内容彻底分离：单位/地形/战役/规则几乎全部在 WML（数据文件）里，C++ 只是解释器。"平台，不是产品"
  - AI 分三层：默认 RCA AI（参数配置）、Formula AI（函数式 DSL）、Lua AI（全功能脚本）——按投入梯度选层
  - addon 生态 = 内容全部数据化的自然结果
- **借鉴**：① 一切内容皆数据（我们用 .tres，对应它的 WML）；② AI 接口按"参数→脚本"分层；③ 把"新派系"作为加数据文件而非改代码的验收标准
- **不抄**：WML 自成语法生态太重，Godot 的 Resource 系统原生够用

### A2. jeremyz/godot-hexgrid（Godot 侧最直接参考）
- <https://github.com/jeremyz/godot-hexgrid> · GDScript · 156★
- **结构**：`addons/hexgrid/`（HexMap / Tile / Piece 三件套核心，addon 化）与 `demo/`（演示游戏）严格分离
- **特性清单**（README 即路线图写法）：distance / adjacents / 3D LOS / BFS reachable / A* path / influence range
- 上游同作者有 Java 版 gdx-boardgame、Rust 版 rustanddust——同一 hex 核心跨三次引擎，证明"六边形数学与游戏规则解耦"是可维护路线
- **借鉴**：① hex 核心做成 addon（我们已独立成 `scripts/core/hex/`，M2 时升格为 `addons/`）；② LOS 早已实现，做射击视线时直接参考其算法；② demo 与框架分离的目录约定
- **注意**：Godot 2/3 时代代码（Node 结构老式），思路可取，代码不直接搬

### A3. mwerezak/godot-heavy-gear
- <https://github.com/mwerezak/godot-heavy-gear> · GDScript(Godot 3) · 20★
- DreamPod9 Heavy Gear 桌规的 Godot 实现——和本项目同类："桌面战棋规则 → 电子化"
- **借鉴**：真实桌规映射到状态机的粒度划分；踩坑记录（3.x → 4 迁移断层）

### A4. Tessera engine / auspex（战锤规则引擎类）
- Tessera：40k 11 版**确定性 Monte Carlo 解算引擎**（AGPL-3.0，playtessera.gg 的数学核心）
- auspex：40k 精确战斗数学引擎 + 军队构建器 + 名单 DSL
- **借鉴**：① 解算引擎独立成库、可脱离 UI 跑海量模拟（平衡性验证自动化——我们可以用"同 seed 批量自战"验证新兵种强度）；② 军队名单用 DSL/数据描述
- **红线**：AGPL 传染，**只借鉴思路，一行代码都不看**

### A5. yiyuezhuo/Hex-Wargame-JavaScript
- <https://github.com/yiyuezhuo/Hex-Wargame-JavaScript> · 38★
- 经典六边形战棋 + **网页版场景编辑器**（地图/剧本数据与游戏引擎分离）
- **借鉴**：地图格式独立成数据文件后，编辑器可以后置、可以换形态（甚至代码内嵌生成器）

### A6. theLiquidFire《Godot Tactics RPG》教程
- <https://theliquidfire.com/2023/11/09/godot-tactics-rpg-01-intro-setup>（Unity 同名教程的 Godot 移植）
- **借鉴**：教学式渐进推进（每一章一个可运行增量）——对应我们"每个任务交付可玩增量"的节奏

### A7. Vassal（开源虚拟桌面）
- <https://github.com/vassalengine/vassal> · Java · 桌面战棋模拟器
- **借鉴**：模块化思维：一个"模组"= 规则提示 + 资产 + 棋盘的打包。我们的 modding 目标形态参考它

### A8. 部队级抽象参照系（v2 粒度变更后新增，2026-10-05）
- **三国志 11**（光荣）：大地图回合战略 + "将+兵数"的部队棋子、接触自动战斗、
  兵种适性。本项目的操作手感与规模感的第一参照。可借鉴：部队=将领属性×兵数的
  战斗力公式；武将阵亡/俘虏的战役后果。
- **英雄无敌系列**：英雄（RPG 成长：等级/装备/技能）+ 堆叠兵种（一格格子兵）。
  借鉴：将领养成与部队 stack 的分工边界——养成全在英雄，消耗全在兵。
- **Dominions 系列**：超大规模 PBEM，战斗完全自动解算（玩家只下部署意图）。
  借鉴："下意图不操刀"的自驱哲学极限；也是我们战斗解算器质量的标尺——
  解算要足够有趣到值得"看回放"。
- **Total War: Warhammer**：官方战锤电子化的分层：战役层（将领+部队卡片）与
  战斗层（模型级）分离。我们等于把它的战役层做成回合制战棋本体。
  借鉴：将领技能树形态、部队传统/ veterancy。

## B. 横向结论

1. **没有现成轮子能直接装**：Godot 生态无成熟 SRPG 框架（对比 Dialog至于视觉小说之于 Godot）；战锤规则的电子实现集中在 40k 且偏解算器不是完整游戏。**自研规则层是必经之路，且我们的 spike 已验证可行。**
2. **成功项目的共性**（我们要照抄的"结构"）：
   - 引擎/内容分离（Wesnoth、Vassal）→ 我们的 `scripts/core` vs `resources/`
   - hex 基础设施 addon 化、与玩法解耦（godot-hexgrid）→ 我们的 `core/hex/` 升格为 addon
   - 解算可脱离 UI 独立运行（Tessera）→ 我们的纯函数解算 + headless 测试已具备
   - 地图/剧本是数据不是代码（Hex-Wargame-JS）→ M1 引入 JSON/.tres 地图格式
3. **已知坑**：
   - Godot 3 → 4 迁移断层（heavy-gear）：锁定 4.x 特性集，`project.godot` 保持低版本特性（已做：4.3 features）
   - 回合制游戏的状态同步 bug 高发区在"回合边界"（Wesnoth 的 save/load bug 史）：回合机要显式状态机（已做），存档尽早进入测试（M1 就做 state 序列化冒烟测试）

## C. 对现有代码的直接结论

Spike（2026-10-05 产出）方向与调研结论一致，保留其逻辑层与测试；
表现层（程序绘制 UI）定位为可抛弃原型，M1 起按正式场景结构重建（见 02-architecture §5）。
