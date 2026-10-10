# Hexhammer M1a 提交深度代码审查（Claude Fable 5.1）

本报告评估 M1a 的代码质量、交付阻断缺陷与测试门禁可信度，结论来自 Fable 5.1 源码审查和独立 Godot 4.7.2 实跑。它不将尚未实现的 M1b 功能计为缺陷，也不将本次软件渲染结果当作目标 GPU 的性能验收。

- 仓库：https://github.com/jiezhou0319/hexhammer ，审查 HEAD `687b843`，范围 `ed2afe1..687b843`（12 个提交：T1 `8ecda4c`/`55f56ac` → T2 `aab4bec` → T3 `9902065` → T4 `3668cb1` → T5 `59f82cd` → T6 `1fb6510` → T7 `77bcc33` → T8 `b7b12af` → T9 `baab6ac` → 收尾 `4f1b425`/`687b843`）。
- 审查方式：全量直读 `addons/hexhammer/*.gd`、`scripts/**`、`tools/run_tests.gd`、`tests/test_case.gd` 及关键测试文件；只读，未修改仓库（`git status` 干净）。
- 独立实证（主代理在 Godot **4.7.2 stable Linux** 上完成，下文保留关键日志）：干净克隆 `--import` exit 0；`run_tests.gd` **exit 1，10 文件 / 166 用例 / 2 失败**；三个 `tools/*_scene_check.gd` 均 exit 0；Xvfb + Mesa llvmpipe **Compatibility 渲染器**俯视像素探针；runner 故障注入；沙盒交互/高亮缓存探针。**Forward+ 与真实 GPU 未验证**（Vulkan surface 不可用自动降级），本报告不对其性能/观感下结论。
- 模型说明：用户要求 fable5；本环境可调用的是 **Claude Fable 5.1**，因此实际使用此版本主导审查，主代理复核运行结果与修复建议。
- 口径：**M1b 未实现项不计 M1a 缺陷**；每条发现标注「已证实（引擎实跑）/ 已证实（代码直读）/ 推测」。

---

## 结论摘要

| 等级 | 结论 |
|---|---|
| **致命（阻断交付）** | T4/T7 渲染 mesh 绕序与 Godot「正面=顺时针」约定相反，默认 `CULL_BACK` 下地形、高亮扇面、路径条带**在俯视下 0 像素可见**（引擎实跑证实）。03 §M1a 验收第 1/3/5 条（渲染、高亮、换贴图可见）在主线代码下**无法目视通过**。 |
| **严重（门禁失真）** | 干净克隆门禁 **不是全绿**：2 用例依赖被 `.gitignore` 排除的 `art_tests/*.png`，与复盘记录的全绿结果不同。runner 未将运行时 SCRIPT ERROR 计为失败，断言计数跨用例累计，且浮点比较放行 NaN，进一步削弱「全绿」证据。 |
| **中** | 沙盒左键选择用的是**陈旧 hover 格**（点击位置 ≠ 选中格，引擎实跑证实）；`HighlightLayer.setup` 重复调用时节点缓存失效未处理（实跑证实）。 |
| **低/观察** | `TIE_EPS` 量纲不一致、`expect(true)` 占位断言、文档行号/口径漂移等；审查提出的 Packed 数组别名风险经实跑排除，不计入缺陷。 |

整体评价：纯逻辑层（hex 数学、数据层、几何不变量、归属规则、相机状态机、生成器/连通性）**代码质量高、文档与测试锚定意识强**；但表现层交付缺少一次「引擎可见性」验证，导致一个在 T5 提交时**已被作者自己发现并写进注释**的绕序问题，带着 T7 的两个同源副本一路滚到了收尾。

---

## 交付阻断缺陷

这里的「致命」指阻断 M1a 地形与高亮交付，不是已经证实存在远程执行、账号泄漏或存档毁损等安全事故。源码证据与引擎探针支持以下结论，但不替代目标设备上的整图与性能验收。

### F-1 渲染 mesh 绕序反向 → 地形/高亮/路径在默认剔除下不可见（已证实：引擎实跑）

#### 代码证据

- 顶面三角 `(格心, inner_k, inner_{k+1})`，绕序约定写死为 `cross(B−A,C−A).y > 0`：[hex_terrain_builder.gd#L24-L28](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_terrain_builder.gd#L24-L28)、[#L206-L213](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_terrain_builder.gd#L206-L213)（引入提交 `3668cb1`，T3 `9902065` 已同口径）。边带 `(v1,v3,v4)+(v1,v4,v2)` [#L233-L247](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_terrain_builder.gd#L233-L247)、角落 `(p1,p3,p2)` [#L267-L273](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_terrain_builder.gd#L267-L273) 同口径。
- `cross(B−A,C−A).y > 0` 等价于「从 +Y 俯视为逆时针」。[Godot 官方 ArrayMesh 文档](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html)明确：“Godot uses clockwise winding order for front faces of triangle primitive modes.” 因此俯视看到的是背面，`StandardMaterial3D` 默认 `cull_mode = CULL_BACK` 时被剔除。
- **作者在 T5 已知**：[hex_picking.gd#L55-L58](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_picking.gd#L55-L58)「Godot 正面绕序 = 顺时针…T4 mesh 的 cross 朝上绕序须翻转后提交，否则 intersect_ray 全 miss（2026-10-09 引擎探针实测；**渲染 mesh 的绕序问题属 T4**）」，并在 [#L66-L70](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_picking.gd#L66-L70) 对碰撞汤逐面 `(a, c, b)` 翻转。即：**碰撞层修了、渲染层没修**，问题被登记为「待目检」而非缺陷（[docs/retro/M1a.md#L26-L29](https://github.com/jiezhou0319/hexhammer/blob/687b843/docs/retro/M1a.md#L26-L29)）。
- T7 两个同源副本：扇形索引 `(0, 1+k, 1+(k+1)%6)` [hex_highlight.gd#L96-L99](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_highlight.gd#L96-L99)；路径条带 `_emit_quad` [#L175-L183](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_highlight.gd#L175-L183)；两种材质显式 `cull_mode = CULL_BACK` 且注释「扇形绕序朝上，俯视即正面」[#L60](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_highlight.gd#L60)、[#L71](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_highlight.gd#L71) ： 这一前提是错的。
- 测试把错误口径锁死为「不变量」：[test_hex_terrain_builder.gd#L114-L119](https://github.com/jiezhou0319/hexhammer/blob/687b843/tests/test_hex_terrain_builder.gd#L114-L119)、[test_hex_terrain_elevation.gd#L482-L484](https://github.com/jiezhou0319/hexhammer/blob/687b843/tests/test_hex_terrain_elevation.gd#L482-L484)、[test_hex_highlight.gd#L160-L165](https://github.com/jiezhou0319/hexhammer/blob/687b843/tests/test_hex_highlight.gd#L160-L165)、[#L261-L262](https://github.com/jiezhou0319/hexhammer/blob/687b843/tests/test_hex_highlight.gd#L261-L262)。而 [test_hex_picking_ray.gd#L254-L262](https://github.com/jiezhou0319/hexhammer/blob/687b843/tests/test_hex_picking_ray.gd#L254-L262) 的软件射线又按「正面=顺时针」剔除：同一仓库内两套互斥的正面口径同时全绿，说明测试锚的是实现而非引擎语义。

#### 引擎实跑证据

```
RENDER_PROBE terrain_original_back_cull    visible_pixels=0
RENDER_PROBE terrain_control_cull_disabled visible_pixels=12092
RENDER_PROBE terrain_control_front_cull    visible_pixels=12092
RENDER_PROBE highlight_original_back_cull  visible_pixels=0
RENDER_PROBE highlight_control_cull_disabled visible_pixels=12092
RENDER_PROBE path_original_back_cull       visible_pixels=0
RENDER_PROBE path_control_cull_disabled    visible_pixels=5096
```
原材质 0 像素、仅改 `CULL_FRONT`/`CULL_DISABLED` 即全部可见，排除了光照/相机/深度等其它原因，直接定位到绕序。（Forward+ 未测，但剔除约定与渲染器无关。）

**影响**：地形顶面、高亮和路径的正面可见性不满足 M1a 的渲染交付要求；材质换表也无法纠正几何绕序。实证是隔离小图的正上方视角，不应将其扩大为「完整沙盒 55° 视角下所有像素必定为空」；目标视角的坡面、陡面和整图仍须补验。三个 `tools/*_scene_check.gd` 不检查像素，故它们通过不代表可见性通过。

**复现**：F6 运行 `scenes/m1a_sandbox.tscn` 从上方检查顶面与高亮；自动复现使用附件 `render_probe.gd`（命令见文末），不要通过永久关闭剔除掩盖错误。

#### 修复方案

- **方案 A（推荐，最小改动）**：只翻转**渲染索引**。`hex_terrain_builder._emit_face`（[#L309-L311](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_terrain_builder.gd#L309-L311)）改为 `add_index(base); add_index(base+2); add_index(base+1)`；原始顶点缓冲仍按 `(a,b,c)` 写入、显式法线 `n`（+Y 侧）与 UV 不动。因为 `hex_picking.chunk_collision_faces`（[#L64-L70](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_picking.gd#L64-L70)）**忽略 `ARRAY_INDEX`、直接取 raw `ARRAY_VERTEX` 再做 `(a,c,b)` 翻转**，raw buffer 不变 ⇒ 碰撞层**现有翻转保留、无需改动**，`face_index ↔ faces[i]` 映射也不变。`hex_highlight.inner_fan_mesh` 同理只改索引序（`0, 1+(k+1)%6, 1+k`）；`_emit_quad` 无索引、直接写顶点，需改为顺时针顶点序（或补索引）。
- **方案 B**：改实际顶点序为 `(a,c,b)`。此时必须**同步删除** `chunk_collision_faces` 的翻转（否则二次翻转、`intersect_ray` 全 miss），并同步 UV/法线逐顶点对应与所有「v0/v1/v2 逐位」测试锚。不推荐。
- 两案修后都要：① 明确 mesh-vertex/face 映射测试锚定的是**索引序**还是**原始 soup 序**（方案 A 下二者不再相同，[test_hex_picking.gd](https://github.com/jiezhou0319/hexhammer/blob/687b843/tests/test_hex_picking.gd) 对「顶点序=三角序」的核对须写明口径）；② 跑一次**真实物理 raycast**（`tools/picking_scene_check.gd`）确认 face_index 与归属仍对；③ 跑像素探针确认可见。
- 测试：明确区分 raw 顶点的几何方向、渲染索引决定的正面，以及独立碰撞汤的方向。方案 A 下 raw 顶点叉积朝上的几何测试可以保留；另按 `ARRAY_INDEX` 取实际渲染三角形，用已知可见的小面及像素探针锚定 Godot 正面。碰撞汤不变时，软件射线的剔除符号不应无条件翻转，须以真实物理射线结果复核。
- **新增门禁**：把 `render_probe.gd` 式像素计数纳入 `tools/`（独立命令即可，不要求 headless 门禁），验收项 1/3/5 必须附像素/截图证据。

### F-2 干净克隆门禁失败：测试依赖被 `.gitignore` 排除的本地素材（已证实：引擎实跑）

- `.gitignore` 自基线 `ed2afe1` 起即含 `art_tests/`（[.gitignore#L19-L20](https://github.com/jiezhou0319/hexhammer/blob/687b843/.gitignore#L19-L20)）。
- T8 提交 `b7b12af` 入库的 [terrain_materials_textured_trial.tres#L3-L4](https://github.com/jiezhou0319/hexhammer/blob/687b843/resources/terrain/terrain_materials_textured_trial.tres#L3-L4) 以 `ext_resource` 引用 `res://art_tests/grass_tile2x2.png`、`res://art_tests/offset_test_hd.png`。
- 两个用例硬依赖该 .tres：[test_hex_terrain_materials.gd#L53-L54](https://github.com/jiezhou0319/hexhammer/blob/687b843/tests/test_hex_terrain_materials.gd#L53-L54)（`test_textured_trial_library_loads`，还断言贴图路径必须 `begins_with("res://art_tests/")` [#L66-L67](https://github.com/jiezhou0319/hexhammer/blob/687b843/tests/test_hex_terrain_materials.gd#L66-L67)）与 [#L155-L166](https://github.com/jiezhou0319/hexhammer/blob/687b843/tests/test_hex_terrain_materials.gd#L155-L166)（`test_swap_material_table_geometry_bitwise_identical`：这恰是 03 验收第 5 条「材质槽接口」的唯一换表不变量锚）。
- 实跑（`godot-tests.log`）：
  ```
  ERROR: res://resources/terrain/terrain_materials_textured_trial.tres:8 - Parse Error: [ext_resource] referenced non-existent resource at: res://art_tests/grass_tile2x2.png.
  FAIL test_hex_terrain_materials.gd:test_textured_trial_library_loads : 贴图试验库 .tres 应可载入（美术分支产物示例）
  === 测试汇总：10 文件 / 166 用例 / 2 失败 ===   (exit 1)
  ```
- [docs/retro/M1a.md#L46-L50](https://github.com/jiezhou0319/hexhammer/blob/687b843/docs/retro/M1a.md#L46-L50) 记录「10 文件 / 166 用例 / 0 失败、exit=0」，但此次干净克隆不能复现。历史运行是否成功未独立验证；本次证据说明交付依赖未入库的本地资源，不能以历史日志替代干净克隆验收。

**修复**：① 把试验贴图换成**入库的小体积占位纹理**（如 `resources/terrain/trial/*.png`，或运行时 `ImageTexture` 程序生成），`.gitignore` 规则保留给真正的本地大图；② 换表不变量测试不应依赖磁盘 .tres：用两个内存 `StandardMaterial3D`（一个带 `ImageTexture.create_from_image`）即可证明「换材质不动几何」；③ 复盘/README 的「全绿」措辞改为「干净克隆全绿」并写明命令。

---

## 测试门禁可信度

### S-1 runner 吞掉运行时错误：用例中途 SCRIPT ERROR 仍计为通过（已证实：引擎实跑）

- [run_tests.gd#L53-L65](https://github.com/jiezhou0319/hexhammer/blob/687b843/tools/run_tests.gd#L53-L65)：`suite.call(method)` 后只看 `_case_failures()`。GDScript 运行时错误（非法下标/空引用等）只是 `push_error` 并中止该函数，不进 `_fails`。
- 故障注入（`runner-fault-probe.log`，一次 `expect(true)` 后访问不存在字典键、其后的 `expect(false)` 永远到不了）：
  ```
  SCRIPT ERROR: Invalid access to property or key 'missing_key' on a base object of type 'Dictionary'.
            at: test_a_runtime_error_after_assertion (res://tests/test_fault_probe.gd:6)
  === 测试汇总：1 文件 / 3 用例 / 0 失败 ===   (exit 0)
  ```
- 含义：任何几何/拾取测试若在前几条断言后崩溃，门禁仍绿。考虑到本仓库大量用例是「先 `expect(...)` 再循环深查」，这是实质性风险。

**修复**：至少增加外层进程包装：不仅检查退出码，还检查 `SCRIPT ERROR` 等未预期引擎错误，负向测试预期的错误须有精确允许名单。若采用引擎日志捕获 API，先在固定的 4.7.2 构建上验证其可用性；也可增加用例完成标记，运行时错误导致未到达正常结束时判失败。必须用当前故障注入证明改后 exit 非零，不能只增加一次普通断言。

### S-2 零断言用例不告警：`_checks` 跨用例累计（已证实：引擎实跑）

- [test_case.gd#L47-L54](https://github.com/jiezhou0319/hexhammer/blob/687b843/tests/test_case.gd#L47-L54)：`_begin_case()` 只清 `_fails`，不清 `_checks`；[run_tests.gd#L60-L61](https://github.com/jiezhou0319/hexhammer/blob/687b843/tools/run_tests.gd#L60-L61) 的「用例没有任何断言」WARN 只对**文件内第一个**零断言用例有效。故障注入中第二个零断言用例无任何告警。
- 顺带：有参 `test_*` 方法被静默跳过（[#L45](https://github.com/jiezhou0319/hexhammer/blob/687b843/tools/run_tests.gd#L45)），拼错签名即「隐形删测」。
- **修复**：`_begin_case` 同时 `_checks = 0`；零断言升级为 FAIL 而非 WARN；有参 `test_*` 和测试文件零有效用例也应 FAIL，避免发现阶段静默丢测。

### S-3 测试口径锁死实现而非引擎语义（已证实：代码直读 + F-1 实跑）

- 见 F-1 第四点：三套文件的「绕序朝上」不变量全绿，但渲染不可见。几何不变量（焊接/闭合/无重复面/无共面）设计得很好，唯独缺「可见性」这一引擎事实。**建议**：在 `tools/` 增加像素级探针（已有 `render_probe.gd` 原型），并把 03 验收第 1/3/5 条的「自动化侧证」改为引用该探针日志。

### S-4 浮点断言会把 NaN 当作相等（已证实：引擎实跑）

- [test_case.gd#L32-L39](https://github.com/jiezhou0319/hexhammer/blob/687b843/tests/test_case.gd#L32-L39)仅在 `absf(got-want)>eps` 时记录失败；NaN 比较不会满足该条件。隔离故障套中的 `expect_almost_eq(NAN, 1.0, 0.001)` 没有计为失败，最终仍 exit 0。
- **修复**：先验证实参和容差为有限数、容差非负，再比较误差；若允许无穷值，需要单独定义合同。补入 NaN、正负无穷和负容差的断言基类自测，几何与相机测试不能依赖一个放行非法浮点的 oracle。

---

## 交互与生命周期缺陷

### M-1 沙盒左键选择的是陈旧 hover 格（已证实：引擎实跑）

- [m1a_sandbox.gd#L228-L231](https://github.com/jiezhou0319/hexhammer/blob/687b843/scripts/ui/m1a_sandbox.gd#L228-L231)：左键先 `_confirm_selection()`（用 `_hover_cell`），再 `request_pick_at(position)`；而拾取在下一物理帧才解析（[map_picker.gd#L102-L116](https://github.com/jiezhou0319/hexhammer/blob/687b843/scripts/ui/map_picker.gd#L102-L116)）。
- 实跑（`interaction-probe.log`）：`clicked=(21,20) selected_immediately=(20,20)`；3 物理帧后 `hover_after_ray=(21,20)` 但 `selected_after_ray` 仍 `(20,20)`。这证明当 hover 已陈旧时点击会选择旧格；快速移动、相机移动后鼠标不动等路径可能产生这一状态，实际触发频率未测。
- 虽是目检脚本，但它是 03 验收「鼠标任意点选…拾取正确」的唯一实操载体，会把正确的拾取层误判为错。
- **修复**：点击入队时带 `kind=select` 标记，在 `cell_picked` 回调中按请求类型分派；或 `MapPicker` 的信号携带请求 id/类型。

### M-2 `HighlightLayer.setup` 可重入但缓存失效未处理（已证实：引擎实跑）

- [highlight_layer.gd#L54-L75](https://github.com/jiezhou0319/hexhammer/blob/687b843/scripts/ui/highlight_layer.gd#L54-L75)：`setup` 先 `clear()`（只隐藏），`_nodes` 字典与旧 `MeshInstance3D` 保留；随后重建 `_fan_mesh/_material`，但 `_node_for` 缓存命中时直接复用旧节点（[#L152-L154](https://github.com/jiezhou0319/hexhammer/blob/687b843/scripts/ui/highlight_layer.gd#L152-L154)），其 `position`/`mesh`/`material_override` 均为旧图/旧尺寸值。
- 实跑：`setup(map1)->highlight((0,0))` 后 `setup(map2 高程4, hex_size 2)->highlight((0,0))`，节点 y 仍 0.02（应 4.02），`cached.mesh != layer._fan_mesh = true`。
- 当前沙盒只 setup 一次，故**首启不触发**；若以后复用同一层切图/重载地图，会遇到此问题，不能计为尚未实现的 M1b 功能缺陷。**修复**：重新 setup 时释放并清空缓存，或逐一更新 mesh、材质和位置；路径节点若也重置，须先移除/释放旧节点，不能仅置 null 留下孤儿。

### M-3 高亮层「只隐藏不释放」+ 位置快照（代码直读）

- 节点位置在创建时按高程快照（[#L161](https://github.com/jiezhou0319/hexhammer/blob/687b843/scripts/ui/highlight_layer.gd#L161)），地图高程若变更（M2 编辑/事件）即错位；与 M-2 同根因。M1a 范围内可接受，登记为设计债。

---

## 次要问题与代码质量

| # | 位置 | 说明 | 等级 |
|---|---|---|---|
| L-1 | [hex_picking.gd#L169-L172](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_picking.gd#L169-L172) | `d`、`best_d` 是**距离平方**，却与 `TIE_EPS * size`（线性量纲）比较；`TIE_EPS=1e-6` 下行为上无害，但注释「相对 size」口径不成立。建议改 `TIE_EPS * size * size` 或比较开方值。 | 低（代码直读） |
| L-2（排除） | [map_data.gd#L253-L256](https://github.com/jiezhou0319/hexhammer/blob/687b843/scripts/core/data/map_data.gd#L253-L256) | 代码直读曾怀疑 Packed 数组会反写调用方；实跑 `from_dict(d)` 后修改地图高程为 7，原字典高程仍为 0。此次构建的行为不支持该缺陷判断，故撤回，不要求为此修复。 | 非缺陷（引擎复核） |
| L-3 | [test_hex_camera.gd#L138-L146](https://github.com/jiezhou0319/hexhammer/blob/687b843/tests/test_hex_camera.gd#L138-L146) | `expect(true, …)` 仅为计数占位（失败走 `fail()`+`return`），逻辑正确但与 S-2 叠加会掩盖零断言。 | 低 |
| L-4 | [strategy_camera.gd#L99-L103](https://github.com/jiezhou0319/hexhammer/blob/687b843/scripts/ui/strategy_camera.gd#L99-L103) | 拖拽每个 motion 事件用**平滑中的渲染位姿**重新投影锚点，`smooth_speed>0` 时锚点与光标有一帧级漂移（收敛，不发散）。手感项，主创实操确认。 | 观察 |
| L-5 | [map_picker.gd#L74-L76](https://github.com/jiezhou0319/hexhammer/blob/687b843/scripts/ui/map_picker.gd#L74-L76) | 每个 mouse-motion 入队一次射线、物理帧内批量查询；高 DPI 鼠标下一物理帧可能排几十条，建议只保留最后一条 hover 请求。 | 观察 |
| L-6 | [docs/retro/M1a.md#L19-L24](https://github.com/jiezhou0319/hexhammer/blob/687b843/docs/retro/M1a.md#L19-L24) / 提交 `4f1b425` | 提交信息含 `undefined`；README「仓库现仅保留 docs/ 与 tools/」已过时；复盘「166/0 失败」见 F-2。 | 文档 |
| L-7 | [m1a_sandbox.gd#L99](https://github.com/jiezhou0319/hexhammer/blob/687b843/scripts/ui/m1a_sandbox.gd#L99) | `print(pick_ok if pick_ok else "...")` 成功时输出裸 `true`。 | 琐碎 |

**未发现问题、值得肯定的部分（代码直读 + 测试实跑通过）**：`HexMath` 的 odd-r 负坐标处理与 cube rounding（[hex_math.gd#L95-L102](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_math.gd#L95-L102)、[#L135-L148](https://github.com/jiezhou0319/hexhammer/blob/687b843/addons/hexhammer/hex_math.gd#L135-L148)）正确；`MapData` 哨兵/值域/`from_dict` 校验严谨；T4 归属规则（稳定 ID 最小者生成共享边/角、界外不生成）与焊接闭合测试（[test_hex_terrain_elevation.gd#L422-L486](https://github.com/jiezhou0319/hexhammer/blob/687b843/tests/test_hex_terrain_elevation.gd#L422-L486)）设计扎实；拾取归属规则按微决策 3 实现且软件射线覆盖 60×40 抽样；`MapGenerator` 对噪声值域做实测归一（不假定 ±1）、meta 落 seed/版本/引擎版本；`MapConnectivity` BFS 正确；固定图 digest 锚定。三个 scene_check（picking 6 / camera 11 / highlight 28 项）引擎实跑通过。

---

## 门禁完整性与修复优先级

**判断：当前门禁不完善，不能独立证明 M1a 可验收。** 已有纯逻辑回归覆盖是有价值的，但存在资源不可复现、运行时错误假绿、断言 oracle 缺陷和可见性缺测；仓库中未找到已跟踪的 CI 工作流配置，三个场景检查也没有由 `run_tests.gd` 自动串联。文档将 Gitee CI 恢复列在 M1b 范围，所以不能把尚未建设的远端 CI 本身算作违反 M1a 承诺；远端实际必需状态检查、分支保护、合并权限和历史执行记录没有得到验证。[任务范围与 CI 约定](https://github.com/jiezhou0319/hexhammer/blob/687b843/docs/04-tasks-m1.md#L204-L214)

建议依次处理：先补齐可入库的资源并修复地形/高亮/路径绕序；再加固 runner、修复 NaN 断言；随后修复点击请求归属和高亮 setup 生命周期。完成后，用一个固定版本的入口串联干净克隆导入、单测、三个场景检查、渲染像素检查及 runner 变异自测，最后在目标 GPU 上补完 60×40 渲染、手感和性能人工门。软件渲染下约 250 ms 的构建时间不是目标设备 FPS 验收。

| 缺口 | 现状 | 建议新增 |
|---|---|---|
| 渲染可见性 | 无（scene_check 不看像素） | `tools/render_probe.gd`：俯视渲染固定小图，断言地形/高亮/路径像素数 > 0 且 `CULL_BACK` 下与 `CULL_DISABLED` 像素数一致 |
| 绕序口径 | raw 几何方向被错误等同于引擎正面 | 分别检查 raw 顶点、实际索引三角形和碰撞汤；采用方案 A 时保留现有碰撞翻转，真实 raycast 与像素检查都必须通过 |
| 干净克隆门禁 | 依赖 `.gitignore` 资产 | CI/本地脚本在 `git clone --depth 1` 临时目录执行 `--import` + `run_tests`；禁止 tests 引用 ignore 路径（grep 门禁） |
| runner 健壮性 | SCRIPT ERROR 不计失败、零断言漏报、NaN 比较假通过 | 变异测试纳入 `tools/`：分别注入运行时错误/零断言/有参 test/NaN，runner 必须 exit 1 |
| 交互正确性 | 无 | headless 场景注入 `InputEventMouseMotion/Button` 校验「点击格 == 选中格」（原型 `interaction_probe.gd`） |
| 高亮层生命周期 | 无 | `setup` 两次换图后 `highlight` 节点 y/mesh 与新图一致 |
| 边缘情况 | 可加强 | `pick_by_nearest_center` 在不同 size 下用**真实对称点**验证等距归属；保留 Packed 数组独立性的回归测试，但本次未发现其反写缺陷 |

---

## 实跑结果与复现命令

| 检查 | 本次结果 | 解释 |
|---|---|---|
| 干净克隆 `--headless --import` | exit 0 | 导入成功不代表所有运行时资源都可加载 |
| `tools/run_tests.gd` | 10 文件 / 166 用例 / 2 失败，exit 1 | 两项 T8 测试因缺少贴图失败 |
| `tools/picking_scene_check.gd` | 6 通过 / 0 失败，exit 0 | 真物理拾取链路通过 |
| `tools/camera_scene_check.gd` | 11 通过 / 0 失败，exit 0 | 场景与合成输入通过，不等于手感验收 |
| `tools/highlight_scene_check.gd` | 28 通过 / 0 失败，exit 0 | 缓存与节点行为通过，不检查实际像素 |
| 渲染探针 | 原地形/高亮/路径均 0 像素；改剔除后可见 | Compatibility 小图正上方视角 |
| runner 故障注入 | SCRIPT ERROR + 零断言 + NaN，仍 exit 0 | 证明当前门禁会假绿 |
| 交互与 setup 探针 | 点击 B 选 A；换图后高亮 y 仍旧值 | 已确认的两项集成缺陷 |

将附件脚本放在仓库外的 `AUDIT_DIR`；`REPO` 指向干净克隆，`GODOT` 指向 Godot 4.7.2 可执行文件。渲染脚本的 PNG 输出应改到本机已有可写目录；其 stdout 像素统计不依赖 PNG 保存成功。

```sh
"$GODOT" --headless --path "$REPO" --import
"$GODOT" --headless --path "$REPO" --script res://tools/run_tests.gd
"$GODOT" --headless --path "$REPO" --script res://tools/picking_scene_check.gd
"$GODOT" --headless --path "$REPO" --script res://tools/camera_scene_check.gd
"$GODOT" --headless --path "$REPO" --script res://tools/highlight_scene_check.gd
"$GODOT" --headless --path "$REPO" --script "$AUDIT_DIR/interaction_probe.gd"
xvfb-run -a "$GODOT" --path "$REPO" --audio-driver Dummy \
  --rendering-method gl_compatibility --script "$AUDIT_DIR/render_probe.gd"
```

runner 自测只能在隔离副本执行：暂时移出原 `tests/`，新 `tests/` 保留原 `test_case.gd` 并加入附件 `test_fault_probe.gd`、`test_empty_probe.gd`，运行原 `tools/run_tests.gd`。注入用例包括一次成功断言后的非法字典访问、零断言、NaN 浮点比较和有参测试方法；修复后的门禁应拒绝这些故障。

## 发现汇总（JSON）

```json
[
  {"id":"F-1","severity":"critical","status":"confirmed_engine","area":"T3/T4/T7 render","files":["addons/hexhammer/hex_terrain_builder.gd:206-213,233-247,267-273,298-312","addons/hexhammer/hex_highlight.gd:60,71,96-99,175-183","addons/hexhammer/hex_picking.gd:55-70"],"commits":["9902065","3668cb1","77bcc33","59f82cd"],"summary":"mesh 绕序为逆时针(俯视)，Godot 正面=顺时针，CULL_BACK 下地形/高亮/路径俯视 0 像素；碰撞层已翻转、渲染层未修","evidence":"render-probe.log: terrain/highlight/path original=0px, cull_disabled=12092/12092/5096px (Godot 4.7.2 Compatibility llvmpipe)","fix":"方案A(推荐): 仅翻转渲染索引(base,base+2,base+1)/扇形索引/_emit_quad 顶点序，raw vertex buffer+UP 法线+UV 不动，chunk_collision_faces 取 raw 顶点故现有碰撞翻转保留；方案B 改顶点序则必须同步删碰撞翻转。修后明确映射测试锚索引序还是 soup 序，跑真实 raycast + 像素探针；区分原始顶点与实际渲染索引口径"},
  {"id":"F-2","severity":"critical_gate","status":"confirmed_engine","area":"T8 gate","files":[".gitignore:19-20","resources/terrain/terrain_materials_textured_trial.tres:3-4","tests/test_hex_terrain_materials.gd:53-67,155-166","docs/retro/M1a.md:46-50"],"commits":["b7b12af","687b843"],"summary":"测试依赖被 .gitignore 排除的 art_tests/*.png，干净克隆 166 用例 2 失败 exit 1；复盘历史全绿结果在此次干净克隆上无法复现","evidence":"godot-tests.log","fix":"入库占位纹理或内存材质；换表不变量测试去磁盘依赖；文档改口径"},
  {"id":"S-1","severity":"high_gate","status":"confirmed_engine","area":"runner","files":["tools/run_tests.gd:53-65"],"commits":["8ecda4c","55f56ac"],"summary":"用例内 SCRIPT ERROR 不计失败，exit 0","evidence":"runner-fault-probe.log","fix":"外层日志门禁检查未预期 SCRIPT ERROR，并校验用例正常完成"},
  {"id":"S-2","severity":"high_gate","status":"confirmed_engine","area":"runner","files":["tests/test_case.gd:47-54","tools/run_tests.gd:45,60-61"],"commits":["8ecda4c"],"summary":"_checks 不随用例重置，零断言用例不告警；有参 test_ 静默跳过","evidence":"runner-fault-probe.log","fix":"_begin_case 清零；零断言=FAIL"},
  {"id":"S-3","severity":"high","status":"confirmed_code","area":"tests","files":["tests/test_hex_terrain_builder.gd:114-119","tests/test_hex_terrain_elevation.gd:482-484","tests/test_hex_highlight.gd:160-165,261-262","tests/test_hex_picking_ray.gd:254-262"],"summary":"绕序测试锚实现口径且与拾取测试口径互斥，无引擎可见性验证","fix":"统一引擎口径 + 像素探针"},
  {"id":"S-4","severity":"high_gate","status":"confirmed_engine","area":"assertions","files":["tests/test_case.gd:32-39"],"summary":"expect_almost_eq(NAN,1.0) 不记录失败","evidence":"runner-fault-probe.log","fix":"先验证有限数与有效容差，再比较误差；补 NaN/INF 自测"},
  {"id":"M-1","severity":"medium","status":"confirmed_engine","area":"sandbox/T5-T7","files":["scripts/ui/m1a_sandbox.gd:228-231","scripts/ui/map_picker.gd:102-116"],"commits":["77bcc33"],"summary":"左键选择使用陈旧 hover 格，点击格≠选中格","evidence":"interaction-probe.log","fix":"按请求类型分派 cell_picked"},
  {"id":"M-2","severity":"medium","status":"confirmed_engine","area":"T7 view","files":["scripts/ui/highlight_layer.gd:54-75,152-154"],"commits":["77bcc33"],"summary":"setup 重入时旧节点缓存(位置/mesh/材质)未失效；首启不触发","evidence":"interaction-probe.log CACHE_PROBE","fix":"setup 释放缓存节点"},
  {"id":"L-1","severity":"low","status":"confirmed_code","files":["addons/hexhammer/hex_picking.gd:169-172"],"summary":"TIE_EPS 比较距离平方与线性阈值，量纲不一致，非默认尺寸下的影响未验证"},
  {"id":"L-3","severity":"low","status":"confirmed_code","files":["tests/test_hex_camera.gd:146"],"summary":"expect(true) 占位断言"},
  {"id":"L-4","severity":"observation","status":"speculative","files":["scripts/ui/strategy_camera.gd:99-103"],"summary":"拖拽锚点在平滑位姿下重投影，可能有一帧漂移(手感项，未实测)"},
  {"id":"L-5","severity":"observation","status":"speculative","files":["scripts/ui/map_picker.gd:74-76"],"summary":"motion 事件全部入队，高频鼠标下单物理帧多次射线(性能，未实测)"},
  {"id":"L-6","severity":"doc","status":"confirmed_code","files":["docs/retro/M1a.md:19-24,46-50","README.md"],"summary":"提交信息 undefined、README 过时、全绿口径失实"}
]
```

**范围声明**：像素实证仅覆盖 Godot 4.7.2 Compatibility（Mesa llvmpipe 软件渲染）；Forward+ 与真实 GPU 的观感/性能未验证。所有「推测」项未经引擎实跑，列为风险而非缺陷。
