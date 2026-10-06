# Hexhammer

大地图回合制征服战旗（Godot 4）：三国志 11 的行军与接触战 + 英雄无敌的将领养成，
装在中古战锤的世界观里。单张持久大地图，占点造兵养将领，规划-结算分离的自动战斗。

> IP 提醒：Warhammer 是 Games Workshop 的知识产权。本项目个人自用与规则研究；
> 公开发布时全部使用自创名词（见 docs/00 与 docs/06 §9）。

## 当前状态（更新于 2026-10-06）

**仅总体思路定稿，其余设计中。** 2026-10-05 完成 M0 技术 spike 与四批设计访谈，
skirmish 定位被推翻，大地图征服方向确立（docs/00，现 v4）。
**注意：当前唯一获认可的是 docs/00 的总体思路；docs/06/07/08 与 02~05 均未敲定，
待审 ≠ 冻结。** 原 docs/archive/ 的 02~05 已取回 docs/ 顶层。
**下一步：以 00 为基准逐个敲定其余文档的冲突项，再重写架构与路线图。**

> 2026-10-06：已移除全部 M0 旧实现——`scenes/`、`scripts/`（含 demo 与计算核心）、
> `resources/`、`tests/` 均与当前设计撕裂，需要时从 git 历史（`9719eba`）找回。
> 仓库现仅保留 `docs/` 与 `tools/`（数值模拟器 + 伤害计算台）。
>
> 2026-10-06 **三项设计裁决**（已回写 docs/00 v4 / 06 v0.4 / 07 / 08 v6.1）：
> ① **棋子即兵**，删除 HOMM 带兵表述；② 接战全自动，去留与施法**只在回合前意图阶段**
> 下达，结算全程不打断；③ 法师弃 3d6 掷骰，并入统一伤害公式。

## 文档（先读这里，再读代码）

| 文档 | 内容 |
| --- | --- |
| [docs/00-vision.md](docs/00-vision.md) | 愿景与五条设计支柱、核心循环图（v4，当前有效） |
| [docs/06-game-design.md](docs/06-game-design.md) | **游戏设计总纲**：四批访谈的全部拍板决策 + 待细化清单（v0.4，最权威） |
| [docs/07-combat-math.md](docs/07-combat-math.md) | **战斗数值唯一权威**（v5）：伤害公式、刀盾定稿、校准锚点 |
| [docs/08-troop-design.md](docs/08-troop-design.md) | 兵种设计（v6.1）：8 兵种数值带 + 校准报告 |
| [docs/01-research.md](docs/01-research.md) | 调研：Wesnoth / godot-hexgrid / 三国志11 / HOMM / Dominions 参照系 |
| [docs/02-architecture.md](docs/02-architecture.md) | 架构 ADR-1~11（**待审**：ADR-10 已废止，ADR-11 待对齐 WeGo） |
| [docs/03-roadmap.md](docs/03-roadmap.md) | 里程碑 M0~M5（**待审 + 待重写**：M1/M3 按 skirmish 定位所写） |
| [docs/04-tasks-m1.md](docs/04-tasks-m1.md) | M1 任务拆分（**待审**：T1/T8/T9/T11/T12 可复用，余者失效） |
| [docs/05-extensibility.md](docs/05-extensibility.md) | 扩展性门 1~8（**待审**：原则大体仍成立） |
| docs/archive/ | 仅存迁移说明（原 02~05 已取回 docs/ 顶层，非作废） |

## 仓库代码

- `tools/combat_sim.gd`：战斗数值校准模拟器 **v6.1**（docs/08 配套，法师定值 ATK 口径）
- `tools/damage_calc.html`：伤害计算台（浏览器直接打开）
- 其余 M0 spike 代码（引擎/UI/单测）已于 2026-10-06 移除，git 历史 `9719eba` 可找回
- 重构方向：**棋子即兵**（无带兵/编制/兵数条）、WeGo 结算、经济系统、8 兵种（详见 docs/06/08）

## 环境与运行

- Godot 4.3+（本机 4.6.2 位于 `E:\Godot\`）。项目无主场景，当前仅运行数值模拟器：

```
"E:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://tools/combat_sim.gd
```

- 伤害计算台直接用浏览器打开 `tools/damage_calc.html`。
