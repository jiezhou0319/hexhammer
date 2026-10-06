# 04 · 任务拆分（M1 批次 · skirmish 时代批次）

> **状态：待审 + 大部分失效（2026-10-06 自 docs/archive 恢复）**
> 本批按 WFB/skirmish 规则写（冲锋响应三选一、战果分、LOS 掩护、rally），与
> "棋子即兵 + WeGo 大地图"不符，需重拆；spike 代码已删除，任务对象亦不存在。
> **仍可复用**：T1 事件对象化、T8 存档/读档、T9 回放、T11 CI（Gitee 账号 zeratulzhou）、T12 骰子可视化。
> **已失效**：T2/T3/T5/T6（旧规则层）；T4/T7 需按新士气与"占领全图"重定。
>
> 粒度标准：一条任务 = 半天到两天的明确交付，附验收。可直接变成 issue。
> 标注：🟦 可并行（互不依赖）；🔒 有前置；⭐ 里程碑关键路径。

## M1-T1 ⭐🟦 事件对象体系（ADR-7 落地）
- 新建 `core/events/battle_event.gd` 基类 + 首批子类：`PhaseChanged / DiceRolled / WoundsApplied / UnitFled / UnitSlain / BattleEnded`
- `BattleEngine.logged(String)` 旁路保留，新增 `events_emitted(events: Array)`；HUD 日志改为订阅事件派生文本
- 验收：现有 34 测试全绿 + 新增"射击一次产出 ≥3 个事件对象且字段完整"测试
- 备注：动 battle_engine 主干，先做，其他任务在它之上

## M1-T2 ⭐🔒(T1) 冲锋响应三选一
- 被冲方在 ChargeCommand 执行时选择：hold / stand & shoot（有远程且距离 ≥ 一半射程）/ flee（立即溃逃检定）
- 热座下弹选择框；headless 下引擎默认 hold（保持测试确定性）
- 验收：三种响应各有单测（含 stand&shoot 的"冲到一半被射死→冲锋取消"）

## M1-T3 🟦 射击视线与掩护
- LOS：起点到目标六边形中心连线穿过的格子中，森林/丘陵计为遮挡（参考 godot-hexgrid Los.gd 的栅格化连线算法）
- 软掩护：被 1 格遮挡 -1 命中；2+ 格不可射
- 验收：典型遮挡场景（隔森林/隔丘陵/开阔）各 1 测试；`shootable_targets` 过滤不可见目标

## M1-T4 🟦 恐慌测试接入
- 触发：①友军单位在其 6 格内被消灭 ②友军溃逃穿过 ③本队损失过半（skirmish 简化）
- 失败后果：自身溃逃（复用 `_do_flee`）
- 验收：三个触发点各 1 测试（ScriptedRNG 驱动）

## M1-T5 🔒(T1) rally（重整）规则
- 己方回合开始：溃逃单位测 Ld（英雄光环适用），成功→停逃可正常行动，失败→继续逃
- 连续溃逃 2 回合且接近地图边缘的敌人 → 大幅简化自裁逻辑：维持"被冲锋即被歼"
- 验收：rally 成功/失败/出界三态测试

## M1-T6 ⭐🟦 近战战果分（skirmish 简化版）
- 战果分 = 造成未豁免致伤 + 冲锋方 +1 + 攻击侧翼/背面 +1/+2（六向朝向：单位记录 facing，冲锋结束时朝向目标）
- 败方 break test 修正 = -战果分差（替换当前 -伤害差）
- 验收：同战力下冲锋方 vs 被冲方的崩溃概率差（autobattle 快报验证方向正确）

## M1-T7 🟦 胜利条件系统
- `VictoryCondition` Resource：`annihilation`（现状）/ `rout`（敌方 ≥50% 点值溃逃/阵亡）/ `objective_hex`（占领 N 回合）
- scenarios 可配；M1 先代码挂载，M2 并入剧本文件
- 验收：三种条件各有 headless 终局测试

## M1-T8 ⭐🔒(T1) 存档/读档
- `BattleState.to_dict()/from_dict()`：地图 seed+改写记录、单位、回合机、RNG seed+已掷次数
- 场景层 F5/F9 快捷键接 UI
- 验收：随机打 10 回合 → 存 → 读 → 同 seed 继续跑 10 回合，与不存档路径逐事件一致（回放对比，事件对象化的红利）

## M1-T9 ⭐🔒(T8) 回放器（命令日志）
- 记录 `[(seed, cmd)…]`，`ReplayRunner` 重放到任意回合；UI 加"上一事件/下一事件"步进
- 验收：一场完整对战的录像文件可重放且与实况事件流一致

## M1-T10 🟦 Hatred 规则（注册表扩展性验收）
- 新 .tres + 注册表 case：近战首回合命中骰重投
- 验收（即 M1 里程碑验收之一）：除注册表与数据外零文件改动

## M1-T11 🟦 CI 管线
- GitHub Actions（或 Gitea/Gitee CI，用户 gitee 账号 zeratulzhou）：`--import` + headless 测试，PR 门禁
- 验收：故意提交一个红测试，CI 拦截

## M1-T12 🟦 骰子过程可视化（第一代 UI 内）
- HUD 日志按事件着色（命中绿/致伤红/崩溃橙），鼠标悬停单位显示"上次解算详情"
- 验收：手动——打一场能仅凭日志复盘每颗骰子

---

## 排期建议（单人，每晚 2~3 小时节奏）

```
第 1 周   T1(事件) → T12(骰子可视化, 顺手验证事件流)
第 2 周   T2(冲锋响应) + T4(恐慌)          [关键路径]
第 3 周   T6(战果分) + T3(LOS) + T5(rally)
第 4 周   T8(存档) → T9(回放) + T7(胜利条件) + T10 + T11 → M1 收尾 retro
```

关键路径：T1 → T2 → T6 → T8 → T9。任何一周超支，砍 T3/T7 保关键路径。

## M2+ 的粗粒度占位（到里程碑前再细拆）

- M2：addon 化 / TileMap 第二代 UI / ArmyList+部署 / MapDef+scenarios / autobattle 工具（5 个任务族）
- M3：成长系统 / 战利品 / 战役剧本 / 注册表重构（4 个）
- M4：AI L0→L2 / 自战回归（3 个）
- M5：音效 / 教学 / 本地化 / export / IP 自查（5 个）
