# M1a · 地形地基 复盘（2026-10-10 收尾验收）

> 依据 docs/03-roadmap.md §M1a 验收清单（五条）逐条核验；自动化证据 = 收尾时测试/代码直读
> + 工作流任务交付记录（每任务门禁实跑）；本文件为收尾验收唯一新增文件。
> 2026-10-10 独立复核后修订：T4 渲染 mesh 绕序疑点升为进 M1b 前最高优先项；
> 随验收记录订正初版转述的若干行号偏差（判断本身不变，详见收尾验收记录 notes）。

## 五行复盘

1. **为何偏离**：无排期/范围偏离——T1~T9 九个任务全部由工作流按 docs/04-tasks-m1.md
   任务卡逐项实现，未跳项、未换序；唯一实质偏离是流程性的：实现、门禁与提交均由
   工作流代跑，主创未逐任务亲手过目，03 §M1a 验收清单的主观/目测半边收尾时无人执行。
2. **砍掉什么**：无砍范围——03「砍段次序」一级未动，M1a 范围 8 项全部交付；仅两处
   登记性载体偏差：固定测试图以 JSON 落盘承载 MapData 同字段集（.tres 留 M2，
   04 T2 条目明示）、美术分支「合并路径演练」以书面流程 + 换表不变量测试等价
   （docs/notes/m1a-t8-art-branch.md §6）——均有文档依据，非验收口径降级。
3. **主观门未走完**：五条验收中四条的目测半边（60×40 带高程渲染与悬崖/斜坡无缝、
   相机平移/缩放/钳制顺手、高亮/取消无感知延迟、并行分支换贴图即见效果）尚待主创
   在 Godot 中实操确认；当前状态是「自动化证据齐、主观门未走」，不读作验收完成。
4. **提交状态**：每个任务在门禁全绿后已由工作流提交并推送 origin/main（Gitee）；
   2026-10-10 复核轮实查 `git rev-list --left-right --count origin/main...main` = `0 0`，
   HEAD = 4f1b425（本复盘，工作流主控 01:05 提交推送；提交信息模板含「undefined」
   字样，登记供知悉）。附带发现：github 镜像远端落后 11 个提交（十个任务 + 本复盘），
   待补推。
5. **下期改什么（进 M1b 前三件事 + 一个习惯）**：① 主创补走下方 M1a 主观门清单——
   **最高优先**确认 T4 渲染 mesh 绕序疑点：几何不变量全绿（法线朝上/无破面/无
   z-fighting）不等于引擎可见性（Godot 正面=顺时针；addons/hexhammer/hex_picking.gd:55-58
   注释佐证：碰撞层为此翻转顶序提交，渲染 mesh 的绕序问题属 T4 待目检拍板），
   F6 目检时地形从上方不可见/穿底应按此已登记项处理、非新事故；② 清点九任务低严重度遗留
   （恒真断言、自报计数失实、edge_tangent 缺独立值锚等，见收尾验收记录 notes）；
   ③ 按 03 证伪对冲注决定 M1b-T1 脉冲时钟是否并行启动。习惯：主观门改为
   「每任务收尾即走」，不再堆积到里程碑末。

## 附：M1a 主观门清单（待主创在 Godot 中实操确认，F6 运行）

| # | 验收条目（03 §M1a） | 操作载体 | 自动化侧证（已齐，headless） |
|---|---|---|---|
| 1 | 60×40 带高程渲染，悬崖/斜坡无缝无破面 | scenes/m1a_sandbox.tscn（默认 FIXED 手工图：高程 0..4，平/坡/崖边 6451/464/86，见 resources/maps/fixed/playable_60x40.meta.json） | test_hex_terrain_elevation.gd（13 用例，含 test_random_elevation_map_no_broken_faces_no_zfighting）、test_hex_terrain_builder.gd（16 用例） |
| 2 | 相机平移/缩放/边界钳制顺手 | 同场景拖拽/滚轮/推边缘（档位表/边缘速度/边距/平滑全 export 可调） | test_hex_camera.gd（12 用例，四角钳制闭式 oracle） |
| 3 | 高亮/取消无感知延迟 | 沙盒 hover 暖黄单格 / 框选蓝多格 / 左键路径描线 | test_hex_highlight.gd（9 用例：单格/多格/清除幂等/差分切换/深度测试/扇形贴顶/lift 分层/路径条带） |
| 4 | 并行分支换贴图即见效果 | scenes/art_trial.tscn 按 1/2 切色块库/贴图库 | test_hex_terrain_materials.gd:155 换表几何逐位一致（13 用例） |
| + | 鼠标真实点选（含高程差格） | 沙盒内点击看 cell_picked 打印 | test_hex_picking_ray.gd:208 test_sampling_60x40（400 格全对）+ test_hex_picking.gd（16 用例） |
| + | 一键可玩测试图观感 | 打开沙盒即默认固定图（map_source=FIXED） | test_map_source.gd（25 用例，含 test_fixed_map_playable） |

（第 4 条验收「hex 数学/数据层/拾取映射单测全绿（headless）」为纯自动项：四文件
78 用例 + runner tools/run_tests.gd 自动发现全套 10 文件 166 用例，无需目测。
复核轮已实跑坐实：`Godot_v4.7.2-stable_win64_console.exe --headless --path hexhammer
--script res://tools/run_tests.gd` →「=== 测试汇总：10 文件 / 166 用例 / 0 失败 ===」、
exit=0（2026-10-10，跑后工作区无新增改动）。）

读法两注（独立复核增）：
① 第 1 行「三档连接齐备」按方向 0/1/2 界内邻边判定（tests/test_hex_terrain_elevation.gd:220-223
   `for d in 3`）——无向边覆盖已足，非全 6 方向遍历，勿误读。
② 第 1 行自动侧证（不变量全绿）不推出「渲染出来看得见且无缝」：T4 渲染 mesh 绕序
   疑点正落在本行目检范围（见第 5 行①），目检不过时先查该项再谈其他。

---

## 补记（2026-10-10 下午，Fable 5.1 外审处置）

> 外审报告：docs/M1a_Fable_review.md（引擎实跑口径：干净克隆 + Xvfb/Compatibility 像素探针 +
> runner 故障注入）。下列代码侧已由工作流主控当日修复并过门禁；目测半边仍待主创（清单见下）。

- **F-1 渲染绕序（致命）已修**：确认上注②疑点为真——索引三角俯视逆时针 = Godot 背面，
  CULL_BACK 下地形/高亮/路径俯视 0 像素（外审像素探针实证）。修法 = 方案 A：**只翻渲染索引**
  （hex_terrain_builder `_emit_face` 逐面 (base, base+2, base+1)；hex_highlight 扇形索引与
  `_emit_quad` 顶点序同口径），raw 顶点/法线/UV 与碰撞汤翻转（直读 raw）一律不动；
  测试改锚**引擎语义**（索引三角俯视顺时针 cross.y<0；raw 几何序 cross.y>0 两层口径分立）。
- **F-2 干净克隆门禁（致命）已修**：贴图试验库 .tres 原引用 .gitignore 排除的
  art_tests/*.png——入库占位纹理 resources/terrain/trial/（tools/make_trial_textures.gd
  确定性生成，grass 田字格 + offset 错位砖纹兼作 UV 朝向目检锚）；本地换真贴图仍走
  art_tests（.tres ext_resource 指回即可，不入库）。外审实跑的「166 用例 2 失败」为真，
  本复盘上方「166/0」是本机（含未入库素材）口径，非干净克隆口径——已订正认知。
- **S-1/S-2/S-4 门禁加固**：run_tests.gd v2 = 逐文件子进程隔离（tools/run_one.gd），
  父进程扫子输出检 SCRIPT ERROR（运行时错误中止被调函数不冒泡，单进程无法自检）；
  零断言用例/有参 test_*/空文件 = 失败；浮点断言拒绝 NaN/无穷/负容差；门禁自带
  变异自检（tools/runner_fixtures/ 五样本：应拦尽拦、应放尽放，全量跑 ~10s）。
- **M-1/M-2（中）已修**：左键选择改走独立请求通道（request_select_at → cell_selected
  信号回执——点击格即选中格，不再读陈旧 hover）；HighlightLayer.setup 重入先摘树再释放
  旧缓存（顺带修了重入时新节点被引擎改自动名 @MeshInstance3D@N 的名字占位问题），
  回归锚 = tools/highlight_scene_check.gd G 组。
- **L 级**：TIE_EPS 平方量纲（L-1）已修；README「仅保留 docs 与 tools」过时口径（L-6）
  已订正；提交信息 undefined 字样维持原样不改史。
- **目测门清单更新**：外审像素探针仅覆盖 Compatibility 软渲染小图正上方视角，F6 实操
  仍不可替代（Forward+/真 GPU、55° 视角整图、手感/延迟项）；执行时第 1 项优先核对
  「地形/高亮/描线从上方全部可见」（F-1 修复的直接验证）。
