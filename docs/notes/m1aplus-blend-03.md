# M1a+ BLEND-03 实现注记——纹理可替换，不改世界事实

> 对应 docs/04-tasks-m1.md §M1a+ 第一批卡 BLEND-03 与
> docs/M1a-terrain-world-proposal.md「换美术者」用户故事（「我希望换纹理或改变
> 过渡宽度时，地图拓扑、道路连接和可达性结果不变」）+「世界事实、游戏规则、
> 表现三层分离」。本文登记实现取舍与目检口径；翻案须同步改
> `tests/test_terrain_style.gd` 的锚。

## 数据路径（style = 表现层的换装旋钮，不进规则/逻辑层）

```text
TerrainStyle .tres（scripts/core/data/terrain_style.gd；T8 材质槽同款资源化先例）
  · mode ∈ {SLOTS, BLEND} —— 选 HexTerrainBuilder 双入口（build_map / build_map_blend）
  · material_library: TerrainMaterialLibrary —— 两路线共同外观来源（换库即两风格同换观感）
  · blend_material: Material —— BLEND 顶点色导管（.tres 烘焙官方工厂产物属性；
      SLOTS 忽略；BLEND 缺失 → 解析显式失败）
  └→ inputs_for(map)（纯解析：只对图内被用到的地形 id 预检/取值）
       · SLOTS → {"mode":"slots", "materials":{用到的 id: 库实例}}
       · BLEND → {"mode":"blend", "palette":{用到的 id: albedo_color}, "blend_material"}
       └→ MapView.build_with_style（scripts/ui/map_view.gd；按 mode 分发到既有
            build / build_blend 同一挂载面——builder 零改动）
```

入库两套默认（`resources/terrain/styles/`）：`terrain_style_slots_default.tres`
（默认色块——旧单材质 fallback 对照/退回档）与 `terrain_style_blend_default.tres`
（混合过渡——BLEND-01/02 过渡合同）；代码内对账基准 = `make_default_slots()` /
`make_default_blend()`（与 .tres 同源，tests 锚定，TerrainMaterialLibrary.build_default
同纪律）。

## 换 style 不变量（headless 锚 = tests/test_terrain_style.gd，9 用例）

- Given 守卫：MapGenerator 同 seed 双实例（seed 7301 / 12×8——扫描实证 6 地形、
  76/96 可通行含水、连通 ok 单分量）summary 逐字节一致——「同一张图」不靠共享实例
  伪造，走真实生成管线。
- Then ①（世界事实零变化）：SLOTS 与 BLEND 构建前后 `MapData.summary()` 逐字节
  不变、`to_dict()` 不变（地形/高程/通行位逐格一致）、`mods` 保持空——「不新增
  规则语义」的可执行表达（移动费 M3 前不存在，表现层不得预写扩展位）。
- Then ②（索引/face 映射逐位不变）：跨 chunk 划分（12×8 / 5×3）下逐 chunk 逐
  surface 比对 `ARRAY_INDEX` / 顶点 / 法线 / UV / faces 元数据 / face_counts 全部
  逐位一致；`HexPicking.chunk_collision_faces` / `chunk_face_table`（引擎消费的
  碰撞汤与增强表）逐位一致。BLEND-01 已锚 blend↔fallback 等价，本卡把同一不变量
  **穿过 style 解析层**再锚一遍（验收口径的直接表达，路径 = inputs_for → builder）。
- Then ③（可达性不变）：`MapConnectivity.check` 报告整体一致（含分量全表），
  且 ok=true / 单分量 / 有水域——可达性对账有实质内容，非全通行退化图。
- Then ④（材质实例确不同）：SLOTS surface 材质 = 库内逐地形实例（≥2 种、全不开
  `vertex_color_use_as_albedo`）；BLEND 全图单一共享导管材质（与 SLOTS 材质无同一
  实例、开顶点色 albedo）；渲染数据差异可锚——BLEND 逐顶点 COLOR 齐备且跨地形
  边带端点异色、SLOTS 无 COLOR 通道。「材质效果不同」的像素级差异属沙盒目检面
  （GATE-02 范畴），headless 锚到材质实例 + 顶点色通道为止。
- 解析纪律：库缺失 / 缺图内 id 槽 / BLEND 缺导管 / BLEND 遇非 StandardMaterial3D
  槽（图内用到）→ `inputs_for` = null（不静默换路线）；`problems_for` 给人读问题
  清单（沙盒/工具显式报缺，missing_ids 同款双保险分工）。**预检只看图内被用到的
  id**——库里多余的未用槽（哪怕 ShaderMaterial）不挡图；色板逐槽提取而非
  `palette_from_materials` 全表提（口径同 builder「先全图预检后建」）。

## 目检载体（F6）

- 打开方式：编辑器打开 `scenes/style_sandbox.tscn` → 运行当前场景（F6）。
  项目约定无主场景，不要为此场景设置 run/main_scene。
- 默认 `terrain_style = null` → 自动载入混合过渡默认档；**检查器把 terrain_style
  换成另一套 .tres 重跑 = 同图换装**（SLOTS：草-泥-岩硬切对照；BLEND：边带/角落
  连续渐变）。8×5 固定图（地形 = (col·2 + row·3) % 3 交错；全平高程——本卡只验
  换 style，高程不掺变量）。
- 换观感第二条路 = 改 style 指向的材质库 .tres（两风格同源）。
- 拾取/高亮/相机在两 style 下照常挂接（移动 = 暖黄 hover、左键 = 蓝色选择集）。

## 与 M1b 的关系（边界重申）

本卡零改动规则层：MapData/MapConnectivity/寻路（尚无）/战斗（尚无）不感知 style；
fallback（build_map 材质槽路线）保留为一键退回档（GATE 纪律「每次迭代都能回到
旧渲染」的可执行面）。纹理版（Should 级，提案 T1）在 style 载体就位后 =
给材质库换贴图槽 / 给 blend_material 换 shader，不动本卡合同。

## 交付证据（2026-10-10）

- 门禁：`run_tests.gd` 202 用例 / 0 失败（exit 0；含本卡 9 用例——BLEND-02
  交付时为 193）。
- 引擎级：`picking_scene_check.gd`（6/0）/ `highlight_scene_check.gd`（31/0）/
  `camera_scene_check.gd`（11/0）各自 exit 0。
- 沙盒冒烟：`style_sandbox.tscn` 两套 style .tres headless 实例化无错误、
  chunk 挂载、拾取/高亮/相机齐备、材质换装生效（BLEND=1 共享导管材质、
  SLOTS=3 库材质实例；临时脚本验证后即删）。
