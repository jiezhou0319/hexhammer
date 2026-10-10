# M1a+ BLEND-01 实现注记——相邻两格颜色权重的过渡合同

> 对应 docs/04-tasks-m1.md §M1a+ 第一批卡 BLEND-01 与
> docs/M1a-terrain-world-proposal.md「材质过渡」/「材质升级的最小安全路径」。
> 本文登记实现取舍与目检口径，供 BLEND-02/03 与后续纹理版沿用；翻案须同步改
> `tests/test_hex_terrain_blend.gd` 的锚。

## 数据路径（权重 = 独立渲染数据，不进规则/逻辑层）

```text
TerrainMaterialLibrary .tres（与 fallback 同源，换表即两风格同时换观感）
  └→ HexTerrainBlend.palette_from_materials → palette {terrain_id: Color}
       └→ HexTerrainBuilder.build_map_blend / build_chunk_blend
            · 顶面（格心扇面）：全部顶点 = 本格纯色（中心主地形纯度）
            · 边带：owner 侧端点 (v1,v2) = owner 纯色、邻侧 (v3,v4) = 邻格纯色
            · 角落：p1 = 归属格、p2 = N(k) 侧、p3 = N(k−1) 侧，各 = 所在格纯色
            · 几何/UV/法线/索引/faces 与 fallback 逐位一致（同一发射路径，
              仅多 COLOR 通道——face 表/碰撞合同零改动）
       └→ HexTerrainBlend.make_blend_material（白 albedo × 顶点色 albedo 导管）
```

## 权重合同的读法（headless 锚 = tests/test_hex_terrain_blend.gd）

- 边带参数 t ∈ [0,1]：0 = 归属格内边（owner 权重 1）、1 = 邻格内边（owner 权重 0）。
  `HexTerrainBlend.edge_weights(t) = (1−t, t)`；合法性 = 有限、非负、和恒 1。
- **中点 0.5 不落成 mesh 顶点**：细分边带会改面数 → 动 face 表与碰撞合同
  （任务卡实现要点 5 明令不许）。中点由「端点纯色 + 仿射线性行插值」实现——
  边带为仿射参数（v3 = v1 + bridge），线性插值在几何中点恰为 0.5 权重混合。
  单测用 `blend_color(端点纯色, edge_weights(0.5))` 链路锚定该等价，不依赖跑帧。
- **8-bit 顶点色量化**：Godot 标准 `ARRAY_COLOR` 通道按 8-bit 归一化存储
  （0.9 → 229/255 ≈ 0.898）。纯色语义锚在权重合同/色板层（浮点精确），mesh 顶点色
  与色板纯色的比较用 1/255 级容差（`_expect_color_eq8`）；mesh↔mesh（同管线两次
  产出）仍逐位精确比较。BLEND-03 换 style 对账时沿用此口径。

## fallback 兼容（双 style 并存）

- `build_map`（材质槽路线）零改动：不设 COLOR 通道、材质不开
  `vertex_color_use_as_albedo`（04 M1a-T3 细化原样保留，测试双锚）。
- blend 结果 schema 与 fallback 同构（chunk/mesh/surfaces/face_counts/faces），
  仅材质统一为共享 blend_material、多 `palette`/`blend_material`/`style` 字段——
  `HexPicking.chunk_collision_faces`/`chunk_face_table`/`MapPicker.setup` 不感知
  style 差异。
- surface 仍按地形分组（分组键 terrain 只是排序依据，不代表渲染材质）——这是
  「faces 序与 fallback 逐位一致」的实现前提；将来若改单 surface 组织（省 draw
  call），须回改本文与等价性测试锚。

## 目检载体（F6）

- 打开方式：编辑器打开 `scenes/blend_sandbox.tscn` → 运行当前场景（F6）。
  项目约定无主场景，不要为此场景设置 run/main_scene。
- 默认 `render_style = BLEND`：6×4 草-泥固定图（col<3 = 草，odd-r 奇数行偏移使
  边界锯齿化、六方向边带都有样本；全平高程——本卡只验材质过渡）。
- 检查器切 `render_style = SLOTS` 重跑 = 旧单材质 fallback（草-泥硬切对照）；
  `material_library` 可指认任意 .tres（换表即两风格同时换观感）。
- 拾取/高亮照常挂接（移动 = 暖黄 hover、左键 = 蓝色选择集）——顶点 COLOR 不动
  几何/face 表/碰撞的目检面。

## 交付证据（2026-10-10）

- 门禁：`run_tests.gd` 184 用例 / 0 失败（exit 0；含本卡 15 用例）。
- 引擎级：`picking_scene_check.gd` / `highlight_scene_check.gd` /
  `camera_scene_check.gd` 各自 exit 0。
- 沙盒冒烟：`blend_sandbox.tscn` BLEND/SLOTS 两风格 headless 启动无错误
  （`--quit-after` / 临时实例化脚本，验证后即删）。
