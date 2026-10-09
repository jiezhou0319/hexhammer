# Hexhammer 规划文档独立评审报告（Fable 主评审）

| 项 | 值 |
|---|---|
| 评估日期 | 2026-10-08（America/Los_Angeles） |
| 评审对象 | `jiezhou0319/hexhammer`，固定提交 `8da3d2db858ce43a5f590a643f9caaa41f986758`（提交时间戳 2026-10-09 12:46 +0800，即洛杉矶时间 10-08 晚，非错误） |
| 评审模型 | Claude Fable 5.1（用户要求"fable5"，实际可用版本为 5.1） |
| 范围 | README、project.godot、tools/（combat_sim.gd、damage_calc.html）、docs/00/02/03/04/05/06/07/08/09/10、旧评审报告 `docs/hexhammer-docs-规划评审报告.md`；01/11 仅作上下文（README 明示其"永不构成拍板权威"） |
| 方法 | 全文静读 + 跨文档交叉核对 + 算术复核；**未运行任何仓库代码，未修改仓库**；主评审本身不做外部研究。评审流程侧辅助核验：[Godot 4.7.2 官方下载归档](https://godotengine.org/download/archive/4.7.2-stable/)确认版本存在；**本机路径 `C:\Users\zerat\godot_tmp\` 未核实**。 |
| 证据链接基准 | `https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/` （全文每条仓库事实均附此基准下的固定链接） |

> **结论性质标注约定**：每条发现末尾标注其性质——
> **【事实】**= 文档/文件原文可直接核对；**【推断】**= 由多处事实做逻辑/算术推导；**【评审意见】**= 基于经验的判断，主创可不采纳。
> 旧报告（docs/hexhammer-docs-规划评审报告.md）已登记并被本提交"收口"的 34 项（G1~G10/S1~S8/C1~C9/A1~A4/R1~R3）本报告**不重复列为新发现**，只在需要时核对其收口是否真正闭合。

---

## 总体结论

这是一套**治理完整度高**的规划文档集：有明确的效力链（00 > 06 > 07/08 > 02 > 03/04，[README L34-L41](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/README.md#L34-L41)）、带日期的修订记录（[00 L6-L25](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/00-vision.md#L6-L25)）、"数值三同步"纪律（[07 L5](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/07-combat-math.md#L5)）、测试版参数载体（[10 L3-L8](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/10-params-test.md#L3-L8)）、把"证伪关口"写进里程碑并配主观门（[03 L112-L117](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L112-L117)、[03 L156](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L156)），以及一份把 34 项外部评审意见逐条收口的提交（提交说明见 git log；旧报告 [docs/hexhammer-docs-规划评审报告.md](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/hexhammer-docs-规划评审报告.md)）。在 RTwP 改向（2026-10-07，[00 L12-L16](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/00-vision.md#L12-L16)）两天内把 00/06/07/08/02/03/04/05/09/10 对齐到这个程度，是可行性的正面信号。【事实 + 评审意见】

但独立复核后，仍有 **2 项 P0**（M1b 验收锚与 M2 入场门与现行规则/里程碑定义存在真正矛盾，须在相应里程碑对表前改文档）、**10 项 P1**（实现者会被迫自行发明口径的规则缺口，或排期/验收可信度问题）和一批 P2（文档卫生）。**P0 都是"改几行文档"量级，不阻塞 M1a 开工**；共同根因是：**旧回合制锚点换算到脉冲口径时，没有把新机制（即时反击、首攻半费、同脉冲序列结算）的影响算进去；以及 M2 入场门漏掉了"抢城/占领"所依赖的地图包子项。**【推断】

总体判断：**规划可行，方向清晰，M1a 可以开工；M1b 对表与 M2 入场前须先修 P0。**【评审意见】

### 评分（10 分制）与评分口径

| 维度 | 分 | 口径说明 |
|---|---|---|
| **可行性** | **6.5** | 衡量"按现文档执行能否在给定产能下到达每期验收"。扣分点：产能基线未自报（[03 L19](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L19)）、04 无逐任务估时（P1-4）、M1a 的 Civ6 式连续地形对单人业余项目偏重（P1-5，已有砍序对冲 [03 L34-L36](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L34-L36)）、M1b 节奏锚可能把团队引向错误的"回炉"（P0-1）；加分点：砍段次序、超支阈值、证伪对冲、零恢复重写决策都写了（[03 L16-L58](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L16-L58)）。 |
| **逻辑清晰度** | **7.5** | 衡量"读者能否唯一地判断哪句话当前有效、机制之间是否自洽"。效力链 + 就地划线做得好（如 [08 L61-L69](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/08-troop-design.md#L61-L69) 字段有效性速查）；扣分点：几处关键术语无定义（"接敌""到战场后的第一刀""被打"是否含 miss，P1-1）、士气乘区未进 07 §3.5 预算表（P1-1f）、同脉冲排序的偏置后果未讨论（P1-2）。 |
| **完整性** | **6.0** | 衡量"进入各里程碑前所需的决策/规则是否都已在文档中登记（已拍或已登记为待拍均算完整）"。M1a/M1b 完整度高（[04](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md)）；M2 入场门漏地图包子项（P0-2，[03 L51-L54](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L51-L54)）；若干 RTwP 新规则的边界条件既未在 06 定义也未在 09 登记（P1-1）。 |

评分为评审意见，不是量化测量；三项分数用同一尺度：9~10 = 可直接作为开发合同；7~8 = 需少量澄清；5~6 = 有必须先修的结构性缺口但不致命；<5 = 需重做。

---

## 已做好的点（独立确认）

1. **效力链与"域内新日期覆盖旧、跨域上游胜"的仲裁规则**写进 README L34-L41，并被 06/07/08 反向引用（[README L34-L41](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/README.md#L34-L41)、[06 L12-L13](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L12-L13)）。【事实】
2. **证伪优先被制度化**：M1b 定义为"不可砍不可延"的存在性判断，配客观清单 + 主观门，并允许在 M1a-T2 后并行启动 M1b-T1 沙盒（[03 L31-L33](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L31-L33)、[03 L78-L83](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L78-L83)、[03 L145-L156](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L145-L156)）。这是对旧报告 S1 的实质性回应而非口头收口。【事实】
3. **钳制已真正落地到两个工具**：`combat_sim.gd` L49-L50 `MOD_CLAMP_MIN/MAX = 0.2/4.0` 并在 L141 生效；`damage_calc.html` L154 `MOD_MIN = 0.2, MOD_MAX = 4`；与 07 §1 L27 一致（[combat_sim.gd L49-L50](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/tools/combat_sim.gd#L49-L50)、[L141](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/tools/combat_sim.gd#L141)、[damage_calc.html L154](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/tools/damage_calc.html#L154)、[07 L27](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/07-combat-math.md#L27)）。【事实】
4. **乘区总预算表 + 极值审计**（07 §3.5）给出了"外层链不受钳、每新增乘区必须登记"的纪律，并算出 ×7.2 / ×24 两档极值（[07 L100-L115](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/07-combat-math.md#L100-L115)）。【事实】
5. **棋子运行态归属**明确落在 UnitState（含反击率当前值、双轴、tag 实例），M2 存档 = BattleState 全量快照 + RNG 状态，M1b-T15 最简快照与之同源（[02 L158-L161](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/02-architecture.md#L158-L161)、[03 L171-L176](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L171-L176)、[04 L135-L139](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L135-L139)）。【事实】
6. **事件最小契约**五字段 + "消费端容忍未知 type / 公共字段只增不改"两条铁律，首批七类事件与 04 T11 对齐（[02 L90-L97](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/02-architecture.md#L90-L97)、[04 L112-L117](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L112-L117)）。【事实】
7. **远程触发窗口已按脉冲制重定义**（06 §3.9：帕提亚 = 自上次主动射击累计移动 ≥2 格；校射 = 对同一目标第 2 次起、移动/换目标清零；两者只认主动射击），08 §2 已划线指向（[06 L121-L131](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L121-L131)、[08 L226-L227](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/08-troop-design.md#L226-L227)）。旧报告 C3 实质闭合。【事实】
8. **09 台账制度**：117 题中 46 题收口/作废只留一行式结论，正文 71 题可计数核对（本次 `rg -c "^#### P"` = 71，与 README L49 一致）；题号锚稳定性纪律写进 03（[03 L44-L47](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L44-L47)）。【事实】
9. **工程口径一致**：project.godot `features=4.7`、`forward_plus`，与 02 ADR-9/ADR-13、README L71 一致（[project.godot](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/project.godot)、[02 L107-L111](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/02-architecture.md#L107-L111)）。【事实】
10. **"数据纪律"从调研（11）正确承接到规则域**：AI 可造集必须显式数据文件、全局成长走乘法/白名单、收入:成本比值锚（[06 L187-L189](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L187-L189)、[06 L205-L207](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L205-L207)、[06 L237-L238](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L237-L238)）。【事实】

---

## 发现（按 P0 / P1 / P2 分级）

分级口径：**P0** = 现行文档内部真正矛盾，且位于某里程碑的验收/入场门上，不改则该门无法按既定口径通过；**P1** = 实现缺口或可信度问题，实现者/评审者会被迫自行发明口径，应在对应任务动工前补；**P2** = 文档卫生/一致性，可批量处理。
"合理留待测试的参数"（双费数值、反击系数、士气百分比、冲锋倍率等）**不列为发现**——10 已明确其为测试版，03/04 已设计调参循环。

### P0

#### P0-1 · 互砍节奏锚"40~48 脉冲"的换算式未计入即时反击与首攻半费，M1b 验收项 4 建筑在它之上

- **事实**：10 §2 给出换算式 `E[脉冲] ≈ 4.8 × 8 × (1/90%) ≈ 43`，并声称"可独立复核"（[10 L37-L40](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/10-params-test.md#L37-L40)）；07 §2 同步写"互砍致死 ≈ 40~48 脉冲 ≈ 1~1.5 账期"（[07 L78-L79](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/07-combat-math.md#L78-L79)）；03 M1b 验收项 4 以"互砍致死 ≈1~1.5 账期……偏差大则双费表回炉"为判据（[03 L153-L154](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L153-L154)）；04 T13 验收同样对表 40~48（[04 L125](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L125)）。
- **推断**：该式只数"主动攻击动作"，而现行规则下每次被打都**立即、不耗攻轴**地按反击率掷骰触发反击（刀盾基础反击率 100%、系数 0.70，[06 L65-L73](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L65-L73)、[10 L55](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/10-params-test.md#L55)），反击率 −5pp/触发、+1pp/脉冲在 8 费互砍下每 8 脉冲净恢复 +3pp，当前率在 1v1 中大体维持在高位。因此每 8 脉冲每方承受约 1 主动 + 接近 0.7 的反击当量，而非 1 刀；再加首攻半费（首刀 4 脉冲）。粗算致死脉冲数应在 **20~28** 量级，而非 40~48——相差约 2 倍。评审侧另有一份**明确假设下的独立敏感性演算**（非项目实测、非 Godot 实现；假设 miss 不触发反击、阵亡不反击、反击不递归、HP √ 修正即时更新）得到无反击 ≈ 39.6 脉冲、开反击 ≈ 27.1 脉冲（P10/P50/P90 ≈ 20/28/36），与上述手算方向一致。**这些数字仅用于说明"43 不是新机制下的推导结果"，不能作为项目的确定性结论。**【推断】
- **为何是 P0**：这不是参数待调，而是**同一文档集内两处口径（06 §3.2 机制 vs 10 §2 换算）互相不兼容**，且落在证伪关口的验收判据上。若按现判据对表，模拟器 v7 有较大概率报"偏差大"，触发"双费表回炉"，但真正该改的是锚点换算，而不是双费表——会把第一轮调参循环引向错误方向。【评审意见】
- **建议**：① 把 10 §2 的换算式改写为"含反击系数与首攻半费的刀当量"版本，或直接把该锚降级为"待 T13 首报回填"，不再称"可独立复核"；② 03 M1b 验收项 4 改为"T13 报表与 10 §2 重算锚对表，偏差 >±30% 时**先复核锚的推导**再决定是否回炉双费"；③ 07 §2 L78-L79 同步。

#### P0-2 · M2 定义要求"占领全图/抢主城"，但攻占规则与中立守军挂在 M3 入场门，城防数值题未列入任何门

- **事实**：03 M2 定义"占点、攒钱、造兵、推平"，验收"一局从开局到占领全图完整可玩"（[03 L162](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L162)、[03 L181](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L181)）；06 §6 含"抢主城后附属概率损坏"等被抢语义（[06 L181-L182](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L181-L182)）。但进 M2 门只列 06 附 #3/#8 与 09 经济-2/4/5/9、P1-核心-1、P1-盲区-2（[03 L51-L52](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L51-L52)）；而**有主设施攻占规则 P1-地图-6 与中立守军 P1-地图-5** 在进 M3 门（以"P1-地图-1~6"整组列入），**城防数值方向 P1-兵种-2 未出现在任何门**（[03 L53-L54](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L53-L54)），06 附 #10 地图包也标为 M3 硬门（[06 L272-L273](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L272-L273)）。09 对应三题仍为开放选择题、无"最小默认"标注（[09 L312-L320](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/09-open-questions.md#L312-L320)、[09 L475-L493](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/09-open-questions.md#L475-L493)）。【事实】
- **推断**：没有"城怎么被占下来"的规则，M2 的胜利条件、队列被抢取消、附属损坏都无法实现；M2 实现者将被迫临场选一个攻占模型（城防 HP 制 / 守军掩护制 / 双层），而这正是 09 P1-地图-6 列出的三分叉——事实上会在 M2 "无拍板地拍板"，违反 03 自己定的"设计债门须清零"。【推断】
- **建议**：把地图包拆成两半——**M2 子集**（攻占规则 P1-地图-6 + 城防数值方向 P1-兵种-2 + 中立设施是否有守军 P1-地图-5）移入进 M2 门；其余（地形修正、LOS、视野半径、出生点）留 M3。或在 09 三题各加一行"M2 最小默认 = X，M3 可复议"。

### P1

#### P1-1 · 若干 RTwP 新规则的边界条件既未在 06 定义，也未在 09 登记（实现缺口）

以下各点经 `rg` 全库检索未见定义或登记（关键词：反击递归/链式、阵亡反击、半费重置、接敌定义、射程外攻击指令）。【事实：未检索到；推断：实现者将自行决定】

| # | 缺口 | 现文位置 | 影响 |
|---|---|---|---|
| a | **反击是否会触发反击**（递归）；被反击打死的攻击者、同一脉冲内已阵亡的目标是否还反击 | 06 §3.2 L65-L77 只说"被打后立即反击"，未排除反击本身作为"被打" | 不排除则高反击率近战互砍可能形成"反击引发反击"的链（反击本身按率掷骰，并非每次必发；链长由双方衰减与掷骰共同决定，无文档给出上限）；事件流/伤害结算递归深度无定义 |
| b | **"首次攻击半费"的重置条件**：06 §2.2 "到战场后的第一刀"（[06 L47](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L47)）——"到战场"无定义：整局一次？每次移动后？每次换目标？ | 06 §2.2 / §3.4 | 直接决定攻频：若"每次移动后"重置，则停-射单位每次都半费，与 10 §2 节奏算式冲突 |
| c | **冲锋"接敌"的判定**：移动 ≥2 格后进入敌邻格即自动触发？只对攻击指令目标触发？路径途经的其他敌邻格是否触发？多敌相邻时打谁？ | 06 §3.4 L86-L94、04 T7 L93-L97 | T7 验收"触发/不触发边界各 1 测"无法写用例 |
| d | **攻击指令目标在射程外**时棋子行为（自动接近=视为移动、攻轴冻结？还是原地空转？） | 06 §2.3 L53-L58 | 决定 AI 与玩家"攻击"指令的语义，T3/T12 依赖 |
| e | **过路费的"移开"定义**：从敌 A 邻格移到仍与 A 相邻的另一格是否付费？ | 06 §3.3 L79-L84；§3.7"追兵每绕一格都付税"暗示付 | 影响断后/绕行推演（M1b 验收项 1） |
| f | **士气"攻防 −x%"的作用位置**：乘在 ATK/DEF 属性输入上，还是作为聚合层增减伤？ | 06 §3.6 L103-L108；07 §3.5 预算表**未登记士气**（[07 L100-L108](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/07-combat-math.md#L100-L108)） | 违反 07 §3.5 自定的"每新增乘区必须登记"；比值公式下乘 ATK 与乘伤害效果不同 |

建议：a~e 在 06 §2/§3 各加一句规则或在 09 开 D-⑬ 子题；f 在 07 §3.5 加一行并写明槽位。

#### P1-2 · 同脉冲"势力序玩家先"不仅是争抢仲裁，还对镜像对决构成系统性偏置，该后果未被讨论

- **事实**：06 §2.2/§3.8 写死"玩家先结算，同势力按 ID"，目的为"结算完全确定、可测试"（[06 L50-L51](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L50-L51)、[06 L115-L119](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L115-L119)）；09 P1-回合-1 已以此收口（[09 L50](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/09-open-questions.md#L50)）；03 M1b 验收项 3 只验证"争抢确定性"（[03 L151-L152](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L151-L152)）。【事实】
- **推断**：双费相同的两枚棋子（如刀盾 vs 刀盾，AI 同派系换色下极常见）攻轴在**同一脉冲**满；先结算方的每一刀都先于对方落地，使对方的 √(HP) 血量修正立即下降并可能在出手前阵亡。这在每次交换中都偏向先手方，叠加到整场即为结构性胜率偏置。评审侧敏感性演算（假设同 P0-1）显示镜像互砍中先手方胜率在 70~80% 区间——**数值仅示方向，不是项目结论**。【推断】
- **为何重要**：06 §9 "AI 同派系换色"意味着镜像对决是常态；该偏置会污染 T13 的胜率报表（AI vs AI 的两方因 faction 序也不对称）与 M4 "胜率对称 ±5%" 类验收。【评审意见】
- **建议**（任选，均保持确定性）：① 同脉冲内所有伤害以**脉冲开始时的 HP 快照**计算、统一在脉冲末应用（同时出手）；② 势力序按脉冲轮转（tick mod 势力数）；③ 若坚持玩家先，在 06 §2.2 显式登记"接受该偏置，T13 报表须分先后手统计"。

#### P1-3 · 风筝推演在 M1b 以"弓箭 vs 骑枪"验证，只覆盖风筝失败面；正向风筝（骑弓 vs 步兵）无验证——主创已拍板延期，此处仅登记为验收局限

- **事实**：03 M1b 验收项 1 用"弓箭走-停-射窗口被骑枪追兵抓住"验证风筝，主创拍板骑弓暂不补入（[03 L146-L149](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L146-L149)）；10 §2 把骑弓风筝节奏写为"4 脉冲走 1 格 + 6 脉冲停射"（[10 L25](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/10-params-test.md#L25)）；06 §5 把骑弓定义为"风筝节奏执行者"（[06 L159](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L159)）。【事实】
- **推断**：按双费表，弓箭（移 8/攻 6）走一格再射的周期远长于骑枪每格 4 脉冲，在开阔直线路径、追兵持续追击的假设下弓箭的走-停-射窗口大概率被抓住——该验收项主要验证"窗口存在且可被抓"，信息量有限。骑弓对步兵（移 8）在同一假设下有拉开空间，对同为 4 费的骑枪则没有；具体格数依赖地形几何、路径与目标是否阵亡，此处不给数字。【推断】
- **性质**：不是当前矛盾（主创已明确拍板延期），而是验收局限：06 §5 的骑弓定位要到 8 兵种齐后才首次被实测。【评审意见】
- **建议**：在 03 验收项 1 注明"M1b 只验证追击窗口的存在，不验证风筝成立；骑弓正向风筝随 8 兵种复检"，避免被误读为已验证。

#### P1-4 · 04 的周数估算不可追溯：仅定义了"半天/一天/两天 = 1.5/3/6 工时"的换算口径，但 24 条任务**无一条标注自身的估时档**

- **事实**：04 L7-L11 定义口径并给出 M1a ≈ 2.5~4 周、M1b ≈ 3.5~5.5 周（[04 L7-L11](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L7-L11)）；M1a-T1~T9、M1b-T1~T15 各条正文均无"半天/一天/两天"标签（全文 `rg "半天|一天|两天"` 仅命中 L7-L8）。03 L25-L28 以同一数字作总账依据（[03 L25-L28](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L25-L28)）。【事实】
- **推断**：旧报告 S2 要求"统一口径"，本提交定义了口径但没有把口径用到任务上，2.5~4 / 3.5~5.5 周无法由任务表重算。按口径反推：M1a 2.5~4 周 × 10~15h = 25~60h / 9 任务 ≈ 2.8~6.7h/任务；M1b 35~82h / 15 任务 ≈ 2.3~5.5h/任务——其中含 Civ6 式悬崖/斜坡连续网格、物理 raycast 拾取、模拟器 v7、事件对象化、寻路等，平均 3~6 小时一条属偏乐观。【推断 + 评审意见】
- **建议**：每条任务加估时档标签（半天/一天/两天）并附一行合计；M1a 收尾按实测回填（03 已规定）。

#### P1-5 · M1a 地形地基对单人业余项目偏重，且其玩法价值到 M3 才兑现——风险已被对冲但对冲触发条件偏松

- **事实**：M1a 范围含离散高程 + 邻格高差悬崖面/斜坡无缝拼合、物理 raycast 拾取、策略相机、高亮、材质槽、随机生成（[03 L85-L98](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L85-L98)）；地形数值修正 M3 才拍（[03 L99-L101](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L99-L101)）；对冲为"允许 T2 后并行启动 M1b-T1 沙盒，何时启动由主创自行决定，不做硬性排期"（[03 L78-L83](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L78-L83)）。【事实】
- **评审意见**：M1a 先行是主创拍板，尊重。但"由主创视情况自行决定"没有触发条件，容易在 T4（高程连接）这个最吃时间的任务上失去判断点。建议把对冲改为带阈值的规则：**M1a 实际耗时达估算下限（3 周）时，若 T4 未验收，强制启动 M1b-T1 平地沙盒并行**。
- **可行性备注**：M1a 的技术路线本身（程序化 hex mesh + 高程 + ConcavePolygonShape raycast）在 Godot 4 中是成熟做法，无技术不可行点。【评审意见】

#### P1-6 · M2 入场门未含任何 AI 域题，但 M2 范围要求"平推 AI：会造兵、占点、推进"

- **事实**：03 M2 范围 6 平推 AI（[03 L170](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L170)）；进 M2 门无 AI 题；AI-3（去留）~AI-7（成军出兵时机）在进 M4 门，AI-2（最小自保底线）未列入任何门（[03 L56](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L56)、[09 L497-L556](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/09-open-questions.md#L497-L556)）。【事实】
- **推断**：平推 AI 必须隐式回答"何时出兵、残血是否撤"，否则无法"推进"。与 P0-2 同类（门禁遗漏），但 AI 可以用"占位规则"过渡，影响小于攻占规则，故列 P1。【推断】
- **建议**：进 M2 门加一行"AI-2/AI-3/AI-7 以 M2 占位规则（最小自保 / 残血阈值撤退 / 固定规模成军）实现，M4 复议"，并把 AI-2 补进某个门，让"无拍板地拍板"变成显式登记。

#### P1-7 · 06 附 #1 已被 10 承接，但 10 §2 的派生自检本身引用了未定义/未登记的规则（与 P1-1 耦合）

- **事实**：10 §2 自检"弓箭 6 费射击……目标进入射程后约 6 脉冲首发（首攻半费则 3 脉冲）"（[10 L43](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/10-params-test.md#L43)）依赖首攻半费的重置条件（P1-1b）；"骑枪冲锋节奏：8 脉冲移动 2 格 → 冲锋首击"（[10 L44-L46](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/10-params-test.md#L44-L46)）依赖"接敌"定义（P1-1c）。【事实】
- **推断**：10 作为"测试版载体"可调数值，但其派生锚如果建立在未定义规则上，T13 对表时仍无法判断偏差来自参数还是来自规则理解不同。【推断】
- **建议**：P1-1 收口后在 10 §1 补一行"本表派生自检所依据的规则定义见 06 §x.y"。

#### P1-8 · 10 §4 速度档标签与倍率不符

- **事实**：1x = 2.0 s/脉冲、2x = 1.0 s、**3x = 0.5 s**（[10 L76-L77](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/10-params-test.md#L76-L77)）；03/04 引用 1x=2s（[03 L120](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L120)、[04 L64](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L64)）。【事实】
- **推断**：0.5 s 相对 2.0 s 是 4 倍速，标"3x"会在 UI/设置/教学文案（M5）中造成口径错误；若意图是三档而非倍数标签，应改写为"档 1/2/3"。【推断】属参数级，但因是口径错误而非待调值，列 P1 末位。

#### P1-9 · 03/04 对 M1b 超支"首砍项"说法不一致

- **事实**：03 M1b 范围 14 与 04 T15 均称最简快照为"超支首砍"（[03 L141](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L141)、[04 L135](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L135)）；04 排期建议又写"超支先缓 T14（CI）并减配 T10"（[04 L160-L161](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L160-L161)）。【事实】
- **建议**：统一为一个有序砍序（如 T14 延后 → T10 减配 → T15 砍），并注明 T15 被砍后"中断续跑"由什么替代（否则与 03 L142-L143 的理由自相矛盾）。

#### P1-10 · 04 M1b-T6 验收"被 2~3 敌围攻时反击频率明显滑落"未量化、无验证；算术提示 2 敌时衰减很弱；且"被打"是否含 miss 未定义

- **事实**：反击率 −5pp/触发、+1pp/脉冲（[06 L67-L69](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L67-L69)、[10 L65-L68](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/10-params-test.md#L65-L68)）；04 T6 验收要求"被 2~3 敌围攻时反击频率明显滑落"（[04 L90-L91](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L90-L91)）；10 §5 把"−5%/+1% 在 2~3 敌围攻下的滑落速度是否可感且不失速"列为复检项（[10 L89-L90](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/10-params-test.md#L89-L90)）。【事实】
- **推断**：以初始状态粗估——两名 8 费敌军、90% 命中、仅命中触发：每 8 脉冲约 1.8 次触发 → −9pp，同期恢复 +8pp，初始平均漂移约 −1pp/8 脉冲；三名约 −5.5pp/8 脉冲。这只是初始漂移：触发率下降后触发次数随之减少、上限截断、敌方攻击错峰都会改变稳态，因此不能断言"不可达"，但足以提示**2 敌时衰减可能弱到不"明显"**。另外 06 §3.2 原文"被打时"未说明未命中是否算"被打"，直接影响触发次数。【推断】
- **为何是 P1 而非 P0**：−5/+1 是 10 的测试参数，可调；问题在于验收用了未量化的"明显"且没有配套验证手段。【评审意见】
- **建议**：① 06 §3.2 明确"被打"= 命中并造成伤害 / 还是含 miss；② 04 T6 验收改为可量化口径（如"3 名 8 费敌围攻 1 账期后当前率 ≤ 基础值 −Xpp"），X 由 T13 首报回填；③ 10 §5 的复检项保留。

### P2（文档卫生）

| # | 发现 | 证据 | 性质 |
|---|---|---|---|
| P2-1 | 09 各级标题仍写历史题数（"P0 · 16 题""P1 · 78 题""P2 · 23 题"），正文实存 3/50/18 | [09 L115](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/09-open-questions.md#L115)、[L163](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/09-open-questions.md#L163)、[L709](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/09-open-questions.md#L709)；`rg -c "^#### P"`=71 | 事实 |
| P2-2 | 09 正文多题仍以 WeGo/回合语境书写（如 P1-UI-1/UI-2/盲区-1/经济-4 的"规划阶段""每回合"），§C 虽声明"重述"但未就地重述；读者需自行翻译 | [09 L560-L578](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/09-open-questions.md#L560-L578)、[L665-L674](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/09-open-questions.md#L665-L674)、[L245-L254](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/09-open-questions.md#L245-L254) | 事实 |
| P2-3 | 05 门 2 称"首批示例 frenzy/fear 随 M1b-T5 落地"，但 04 M1b-T5 与 06/08 现行机制中均无 frenzy/fear；"恐惧类 debuff"属 M3 将领技能 | [05 L25-L26](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/05-extensibility.md#L25-L26)、[04 L81-L84](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L81-L84)、[06 L61](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L61) | 事实 |
| P2-4 | 04 T14 / 03 M1b-13 写 "Gitee CI"，而本次评审的远端是 GitHub；若双远端并存应在 README 写明主远端与 CI 所在 | [04 L131-L133](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L131-L133)、[03 L140](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/03-roadmap.md#L140) | 事实（环境事实由用户核实） |
| P2-5 | `tools/combat_sim.gd` 仍含已废机制常量（`DEFEND_REDUCTION`、`FLANK_BONUS`、`MELEE_WEAK`、迎击先手反转），文件头自述 v6.1 回合制口径；08/README 已标"待 v7 重写"，不构成矛盾，但 T13 验收要求"旧回合口径归档保留"时需防止两份模拟器并存混淆 | [combat_sim.gd L53-L64](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/tools/combat_sim.gd#L53-L64)、[L185-L199](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/tools/combat_sim.gd#L185-L199)、[04 L126](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L126) | 事实 |
| P2-6 | 精锐"四维 ×1.2"的两处说法需择一：09 P1-兵种-3 指出镜像同乘 c 时伤害 D'=cD、HP'=cHP，血量比与轮数理论不变（速/费/概率同等前提下）；08 §6-9 "精锐互砍 3.8 刀快于 4.8" 与之不符，可能是模拟器口径问题（09 已建议复核）；而精锐**单方面**打未强化目标时伤害约 ×1.3（ATK²/(ATK+DEF) 下 ATK×1.2 的放大），两种情形不应混用。07 §3.5 把"精锐 ×1.2"列为非伤害乘区正确，但未说明镜像/非镜像差异 | [07 L107](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/07-combat-math.md#L107)、[08 L483-L485](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/08-troop-design.md#L483-L485)、[09 L323](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/09-open-questions.md#L323) | 推断 |
| P2-7 | 06 §3.6 包围阈值 4 面在"每方 10~30 枚"规模下触发频率可能很低（需 4 枚敌棋同时相邻），"包抄"推演（M1b 验收 1）要求集结 4 枚——属参数，但建议 T13 统计"4 面以上事件数/局"作为是否下调阈值的依据 | [06 L26](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L26)、[06 L105](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L105) | 评审意见 |
| P2-8 | 10 §3 器械/医疗无反击 ⇒ 无过路费，10 已自注为"强化前排保护"；但 06 §3.3 "至少 1 下"（[06 L82](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L82)）在只与器械/医疗相邻时为 0 下，措辞应改为"每个有反击能力的相邻敌各 1 下" | [10 L71-L72](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/10-params-test.md#L71-L72) | 事实 |
| P2-9 | 02 §3 `core/hex` 内部实现仍列 "Voronoi 生成"，03/04 M1a 地图来源为"固定测试图 + 简单随机脚本"；不冲突但 Voronoi 属旧 spike 词汇 | [02 L206](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/02-architecture.md#L206)、[04 L50-L52](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L50-L52) | 事实 |
| P2-10 | 02 ADR-5/ADR-12 确定性口径下，M1b 随机合法 AI 的随机源是否共用 BattleRNG 流未写明；T15 快照"RNG 内部状态"需涵盖 AI 随机源，否则续跑不一致 | [02 L73-L77](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/02-architecture.md#L73-L77)、[04 L135-L139](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L135-L139) | 推断 |
| P2-11 | 06 §2.2 "无指令待机时轴照常充满但空转消耗" 与 10 §4 "无移动指令 → 攻击轴 +1、移动轴空转"口径一致，但 10 标为"建议，随实现验证"，而 04 T2 把"空转消耗"列为验收规则之一——建议 10 §4 去掉"建议"二字或 04 T2 注明以 10 为准 | [06 L48](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/06-game-design.md#L48)、[10 L82-L83](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/10-params-test.md#L82-L83)、[04 L69-L70](https://github.com/jiezhou0319/hexhammer/blob/8da3d2db858ce43a5f590a643f9caaa41f986758/docs/04-tasks-m1.md#L69-L70) | 事实 |

---

## 闭环审查（时间 / 双费 / 命令 / 事件排序 / 随机 / 伤害 / 反击 / 脱战 / 经济 / 将领 / AI / 3D / 排期 / 验收）

| 环 | 闭合状态 | 断点（引用上文编号） |
|---|---|---|
| 时间（脉冲/账期/速度档） | 基本闭合：00 §2 ↔ 06 §2.1 ↔ 10 §4 ↔ 03/04 T1 一致 | P1-8 速度档标签 |
| 双费 | 闭合：06 §2.2 ↔ 10 §2 ↔ 08 §0.5 映射一致（速度 8/4/2 → 费 4/8/16） | P1-1b 首攻半费重置条件 |
| 命令 | 部分：指令集与实时生效一致；攻击指令射程外行为缺 | P1-1d |
| 事件排序 | 闭合：06 §3.8 ↔ 03 M1b-8 ↔ 04 T9 ↔ 02 ADR-7 契约一致；偏置后果未讨论 | P1-2 |
| 随机 | 闭合：00 支柱 3/4 ↔ 07 §1 四类方差 ↔ 06 §3.2/§3.5 ↔ 02 ADR-5 ↔ 09 附录一；AI 随机源归属未写 | P2-10 |
| 伤害 | 闭合：07 §1 公式 ↔ 两工具钳制已落地 ↔ 06 §4；士气未入预算表 | P1-1f |
| 反击 | 部分：率/系数正交清楚；递归/阵亡/miss 未定义；验收"明显滑落"未量化 | P1-10、P1-1a |
| 脱战 | 部分：口径 B 清楚；"移开"定义与"至少 1 下"措辞 | P1-1e、P2-8 |
| 经济 | 待 M2：账期/队列/附属/退款规则清楚；资源终表与收入锚已登记为门；攻占规则漏门 | P0-2 |
| 将领 | 待 M3：四维重锚为硬门、技能/装备/复活题全在 09；M1b 不含将领，T7"技能施加 tag"仅为 API 测试，可接受 | — |
| AI | 部分：节律/预算/旋钮/铁律清楚；M2 平推 AI 无门 | P1-6 |
| 3D | 闭合：ADR-13 ↔ 03 M1a ↔ 04 T3~T8 ↔ project.godot forward_plus；工作量风险 | P1-5 |
| 排期 | 部分：总账/砍序/阈值/校准点齐备；逐任务估时缺失；首砍项不一致 | P1-4、P1-9 |
| 验收 | 部分：M1a 验收可执行；M1b 验收项 1（风筝）信息量有限、项 4（节奏锚）推导有误；T6 验收未量化 | P0-1、P1-3、P1-10 |

---

## 具体建议与阶段验收口径

### 立即（M1a 开工前后均可，纯文档，≈1 晚）
1. **修 P0-1**：10 §2 换算式改为含反击/首攻半费的刀当量版本，或降级为"待 T13 回填"；03 验收项 4 与 07 §2 同步。
2. **修 P0-2**：进 M2 门加入 P1-地图-5/6、P1-兵种-2（或各加"M2 最小默认"）。
3. **修 P1-1 + P1-10**：06 §3.2 定义"被打"、反击是否递归、阵亡不反击；06 §2.2 定义首攻半费重置；06 §3.4 定义"接敌"；06 §2.3 定义射程外攻击指令；06 §3.3 定义"移开"；07 §3.5 登记士气乘区。
4. **P1-2**：在 06 §2.2 二选一登记——"同脉冲 HP 快照同时结算"或"接受玩家先偏置并在 T13 分先后手统计"。

### M1a 期间
- 04 每任务补估时档；M1a 收尾按实测回填（03 已规定）。
- P1-5 对冲加触发阈值（耗时达 3 周且 T4 未验收 → 强制并行 M1b-T1）。
- **M1a 验收补充建议**：在现有 5 项之外加"headless 下 60×40 随机图生成 + 碰撞体构建耗时上限（如 <2 s）"，防 T4/T5 性能债后置。

### M1b 期间（证伪关口）
- T13 首报（T5 后即出）必须同时输出：互砍致死脉冲数分布（P10/P50/P90）、**先手/后手分组胜率**、反击触发次数/脉冲、4 面以上包围事件数/局。
- **M1b 验收修订建议**：项 1 风筝改为"验证追击窗口存在"；项 4 改为"与重算锚对表，偏差 >±30% 先复核锚"；新增"镜像对决先后手胜率差 ≤ 阈值（或已登记接受）"。
- 冻结点仍按 03：冲锋 ×2、长枪迎击两版、士气交互随 T13 拍。

### M2 入场
- 门清单按 P0-2/P1-6 扩充后再进；M2 验收"一局到占领全图"必须能指出其攻占规则出处。

---

## 与旧评审报告的关系（独立复核结论）

- 旧报告 34 项中，本次抽核 G1/G2（版本口径）、C1（预算表）、C2（反击率归属）、C3（触发窗口）、C4（士气三档）、S3/S4（砍段/骑弓）、S5/S7（T13 增量/快照）、A1/A2（门 3）、G7（MapData/MapDef）：**均已在对应文档落字，收口属实**。【事实】
- **收口后新暴露的问题**：S2 的"口径"定了但未用到任务（P1-4）；C8 的换算式补了但算错对象（P0-1）；C4 三档统一后 T6 的验收仍未量化（P1-10）。即旧报告的修复动作本身引入或暴露了二阶问题，这是正常的，但说明**下一轮应以"算一遍"而非"写一遍"为收口标准**。【评审意见】
- 旧报告未覆盖 09；本次覆盖后发现门禁遗漏（P0-2、P1-6）与标题题数陈旧（P2-1）。

---

## 证据边界与局限

1. **未运行仓库代码**：combat_sim.gd / damage_calc.html 的结论来自静读；07 §2 / 08 §5 的历史校准数值未复跑，本报告不对其正确性背书。评审流程侧执行过独立 Python 敏感性演算，见下一条；这不属于项目测试。
2. **评审侧敏感性演算**（P0-1、P1-2 提到）是评审方在明确假设下的独立算术/模拟，**不是项目实测，不代表 Godot 实现结果**；报告中仅用其说明"方向"，所有具体数值不应被写回项目文档。
3. **环境事实**：Godot 4.7.2 版本存在已由评审流程侧通过[官方下载归档](https://godotengine.org/download/archive/4.7.2-stable/)辅助确认。本机路径、Gitee/GitHub 双远端关系、主创实际产能均以文档自述为准，未核实。
4. **主评审未做外部研究**：Civ6 式地形实现成本、Godot 4.7 API 等未查证，P1-5 的可行性判断基于一般工程经验。
5. **行号以固定提交为准**：所有 `#Lx-Ly` 锚指向 commit `8da3d2d`；后续提交行号会漂移。
6. **01/11 未评审**，仅核对其被 06/07 承接的条目是否存在。
7. 评分为 Claude Fable 5.1 的单一主评审意见。交付前对高优先级发现进行了证据与算术核对，但未进行第二轮独立完整评审。

---

报告生成：Claude Fable 5.1 · 2026-10-08（America/Los_Angeles）· 仅供项目主创参考，所有拍板权在主创。
