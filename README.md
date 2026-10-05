# Hexhammer

大地图回合制征服战旗（Godot 4）：三国志 11 的行军与接触战 + 英雄无敌的带兵与养成，
装在中古战锤的世界观里。单张持久大地图，占点造兵养将领，规划-结算分离的自动战斗。

> IP 提醒：Warhammer 是 Games Workshop 的知识产权。本项目个人自用与规则研究；
> 公开发布时全部使用自创名词（见 docs/00 与 docs/06 §9）。

## 当前状态（2026-10-05）

**设计定稿，架构重写中。**当天完成：M0 技术 spike（代码在 `scripts/` `tests/`，
34 单测全绿，可玩灰色原型）→ 四批设计访谈推翻 skirmish 定位 →
大地图征服方向定稿（docs/00 v3 + docs/06）。旧规划已归档至 docs/archive/。
**下一步：按 v3 设计重写架构与路线图（docs/06 附录的 10 项待细化是前置队列）。**

## 文档（先读这里，再读代码）

| 文档 | 内容 |
| --- | --- |
| [docs/00-vision.md](docs/00-vision.md) | 愿景与五条设计支柱、核心循环图（v3，当前有效） |
| [docs/06-game-design.md](docs/06-game-design.md) | **游戏设计总纲**：四批访谈的全部拍板决策 + 待细化清单（当前最权威） |
| [docs/01-research.md](docs/01-research.md) | 调研：Wesnoth / godot-hexgrid / 三国志11 / HOMM / Dominions 参照系 |
| docs/archive/ | skirmish 时代的架构 ADR 与路线图（已归档，仅历史参考） |

## 已有代码（M0 spike，按 v3 大部分将重构）

- 保留：`scripts/core/hex/`（六边形数学/地图/寻路，粒度无关）、命令层结构、测试基建
- 重构方向：部队=将领+兵数、WeGo 结算、经济系统、7 兵种（详见 docs/06）

## 环境与运行

- Godot 4.3+（本机 4.6.2 位于 `E:\Godot\`），打开项目运行 `scenes/main.tscn`
  （旧 skirmish demo，三势力小图混战——仅作技术验证，不代表新设计）

```
"E:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://tests/run_tests.gd
```
