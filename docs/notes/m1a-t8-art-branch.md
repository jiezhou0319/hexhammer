# M1a-T8 notes · 材质槽体系 + 美术并行验证分支（2026-10-09）

> 实施笔记（非拍板文档；任务卡 = docs/04-tasks-m1.md M1a-T8，调研依据 =
> docs/hexhammer-m1a-map-implementation-research.md「Mesh、分块与材质」节）。
> 本文承载三件事：**UV 约定与法线硬边策略的定死落字**（「换贴图不改主线」的
> 接口前提）、**试验场景使用说明**、**美术并行分支的合并路径演练**（书面，
> 本任务不实际开分支）。翻案须同步改 `tests/test_hex_terrain_materials.gd`
> 的对应锚，并回改 04 任务卡验收——不动架构（02）。

## 1. 材质槽体系（本次交付）

渲染管线的地形材质从「builder 内置色表合成」改为**外部映射表**：

| 件 | 位置 | 说明 |
| --- | --- | --- |
| 映射表类 | `scripts/core/data/terrain_material_library.gd` | `TerrainMaterialLibrary extends Resource`；`materials: Dictionary[int, Material]`；`load_at/load_default/material_for/missing_ids`；`materials_from_colors`（测试/工具自建表）；`build_default` + `DEFAULT_PALETTE`（代码侧默认口径） |
| 主线默认库 | `resources/terrain/terrain_materials_default.tres` | 色块起步：6 类型 StandardMaterial3D（草0/泥1/岩2/水3/沙4/林5），颜色 = `DEFAULT_PALETTE` |
| 贴图试验库 | `resources/terrain/terrain_materials_textured_trial.tres` | 美术分支产物示例：0=草贴图原色、1=草贴图×棕 tint、2=另片草裁片×冷 tint、3/4/5 保持色块（同表混用贴图/色块/乘色合法） |
| 管线接口 | `HexTerrainBuilder.build_map(map, chunk_cols, chunk_rows, materials, …)` | 第 4 参 = `{terrain_id: Material}` 平面表（= 库的 `.materials` 直接透传）；**表缺图内 id / 表值非 Material → 显式 null**（无隐式兜底，旧「空表落默认色板」路径已删） |
| view 层 | `MapView.build(…, materials, …)`；`m1a_sandbox` 增 `@export material_library` | 沙盒检查器可直接指认任意 .tres——换库即换观感、零代码；留空 = 主线默认库 |

分层纪律不变：库类在 `scripts/core/data/`（02 §4「.tres 数据模型」位），
纯 Resource 零场景节点；删 `scripts/ui/**` 后 tests 全绿口径不受影响
（`art_trial.gd` 属 ui，可整体删除）。

**契约测试**（`tests/test_hex_terrain_materials.gd`，13 用例——2026-10-10 外审订正：实为 13 个 test 函数）：
- 表缺槽/值非 Material → null；surface 材质 = 表内共享实例；结果表 echo 恰好被用到的类型；
- 默认 .tres 可载入、逐类型与 `build_default()` 同色（.tres 与代码默认口径防漂移）；
- **换表不变量**：同一图、色块表 vs 贴图表两次构建——全部 chunk/surface 的
  顶点/法线/UV/索引/faces 元数据**逐位一致**，仅材质引用不同。这是
  「换贴图不改主线」的可执行断言：换库若动了几何/UV，测试即红。

## 2. UV 约定（定死；代码落字 = hex_terrain_builder.gd 头注 + `_uv_*` 三函数）

- **尺寸**：1 纹理重复 `[0,1]²` = **2R×2R 世界方形**（R = `size` 外接圆半径）。
  整体缩放属材质参数（`uv1_scale`），不动 mesh——美术在 .tres 里调即所见。
- **水平面**（顶面 / 平连边带 / 等高角落）：**世界平面映射** `u = x/2R`、`v = −z/2R`。
  与归属格无关 → 平地整图无缝连续平铺（相邻格、跨 chunk 均连续）；世界原点处
  格心 UV = (0,0)（旧 T3「格心 (0.5,0.5)」口径作废，锚已改）。
- **侧面**（|Δh|≥1 边带：斜坡/陡面）：`u = XZ 沿边切向投影/2R`
  （`HexMath.edge_tangent_world(d)`：dir 单位向量绕 +Y 转 90°，(x,z)→(−z,x)；
  方向 0 的边切向 = +z/南）、`v = −y/2R`——竖向纹理随高程走：Δ1 半纹、
  Δ2 恰一整纹；对真竖直墙纵横比正确（本作 ~80° 陡面拉伸 ≈1.5%，可忽略）。
- **非等高角落**（补洞小三角）：`u = x/2R`（平面 u）、`v = −y/2R`。
- **已接受代价**（显式登记）：相邻方向边带 u 轴相差 60°；侧面与顶面在共享边上
  不连续；角落 u 与两侧边带轴不连续。选**无缝平铺**贴图（如 art_tests 草图）
  时不显眼。边界混色 / Texture2DArray / 三平面映射 / 自定义 shader =
  后续升级任务，不混入本条（04 M1a-T8 明示）。

## 3. 法线硬边策略（定死）

**全 flat shading、全硬边**：每三角独立 3 顶点 + 面法线现算（顶面恒 +Y），
不焊接顶点、不做平滑组。理由：① 平顶/陡壁的硬边是低模策略地形的目标可读性
（台阶感是特性不是缺陷）；② 平滑 = 顶点焊接 + 按面分类平滑组 + 法线重建，
牵动 T5 拾取的顶点序契约与全部几何锚，属表现层升级，须单列任务再议。
锚：`test_hard_edge_face_normals_within_face`（面内三顶点法线逐位一致 +
面法线 = cross 归一，不平滑不平均）。

## 4. 试验场景（「换贴图即所见」的目检载体）

`scenes/art_trial.tscn` + `scripts/ui/art_trial.gd`（F6 运行）：
- 12×8 阶梯图（草0/泥1/岩2；西→东 0/1/2 层 + 南侧 0→2 直落）——平顶/平连/
  斜坡/陡面四类面齐备，各 UV 类目均有目检对象；
- **按 1 = 主线默认色块库 / 按 2 = 贴图试验库**：同一 `MapView.build` 接口、
  只换材质表资源重建（几何逐位不变，契约测试锚定）；
- 固定斜视相机（只验材质，不挂拾取/高亮/策略相机——那是 m1a_sandbox 的事）。

主沙盒 `scenes/m1a_sandbox.tscn` 同步支持检查器 `material_library` 指认 .tres
（60×40 全功能目检 + 换库）。**「换贴图/纹理直接看效果」的最终确认为主创
目测项**（04 验收原文），headless 侧只能保证构建/契约绿。

## 5. .tres 维护方式（ADR-3 编辑器原生编辑）

- 双击 .tres → 检查器直接改材质/贴图/颜色/tint/uv1_scale，即存即所见；
- 两张 .tres 由一次性脚本（`Lib.build_default()` / 手工组装 + `ResourceSaver.save`）
  生成，生成脚本已删（内容自足于 .tres，无再生成需求）；
- `DEFAULT_PALETTE` 变更时：改代码常量 → `Lib.build_default()` 存回 .tres
  （测试锚定两者逐类型同色，漏改即红）；
- 贴图槽位引用 art_tests 素材（`grass_tile2x2.png` / `offset_test_hd.png`）。
  注意 .import 现 `detect_3d/compress_to=1`：贴图被 3D 引用后引擎可能重导入为
  有损压缩，若平铺接缝异常先把该贴图 `compress/mode` 固定为 Lossless
  （art_tests 均已带 .import，本次未改动、headless 冒烟无异常）。

## 6. 美术并行分支工作流与合并路径演练（书面；本任务不实际开分支）

**目标**（04 M1a-T8 + ADR-13 ③）：美术在分支上换贴图/调材质直接看效果，
主线代码零改动；分支成果可控并回。

**分支模型**（真实 git 流程，本次以工作区形态演练）：

1. 从 main 切 `art/trial-textures`（或按批切 `art/textures-<主题>`）；
2. 分支上**只动两类文件**：
   - `resources/terrain/*.tres`（改材质参数/换贴图引用/加槽）；
   - 贴图资产本身（`art_tests/` 或未来的 assets 目录，含 .import）。
   **不许动** `addons/`、`scripts/`、`tests/`、`tools/`——动了即越权，
   合并门前置检查 `git diff --name-only` 只含上述目录。
3. 分支验收门 = 主线同一门禁命令：
   `--headless --import` → `--script res://tools/run_tests.gd` 退出码 0。
   其中 `test_swap_material_table_geometry_bitwise_identical` 是关键闸门：
   美术无论怎么换表，几何/UV/索引逐位不变；测试红 = 分支改了几何或破坏了
   材质表契约，不允许合并。
4. 目检门（主创，本地开 `scenes/art_trial.tscn` 或沙盒检查器指认该 .tres）：
   换贴图即所见、接缝/对齐/侧面观感合格。
5. **合并回主线**：材质 .tres 与贴图资产直接 merge（冲突面极小——只可能
   两边同时改同一 .tres 的同一槽，按新值手工合并即可）；主线代码零改动，
   无需任何适配 PR。若新增了独立 .tres（如 `terrain_materials_<主题>.tres`），
   一并合入，主线场景按需指认或仅作备选库存在。
6. 合并后主线门禁再跑一次（.tres 变更也过同一测试——契约对资源内容生效）。

**本次演练形态**：因工作流不做 git 操作，分支产物以工作区新增文件落地——
`terrain_materials_textured_trial.tres`（= 分支上那张表）与
`scenes/art_trial.tscn`（= 分支目检载体）。「并回主线」的等价验证 =
`test_swap_material_table_geometry_bitwise_identical`：把这张表喂给同一
`build_map` 接口，几何/UV/索引与默认色块表构建逐位一致、faces 元数据一致
（T5 拾取面表不受影响）、仅材质引用不同——即合并后主线行为完全可预期。

## 7. 验收对照（04 M1a-T8）

| 验收 | 状态 | 载体 |
| --- | --- | --- |
| 分支上换贴图/纹理直接看效果，主线代码零改动 | 代码面已锚定；目测待主创 | 契约测试 §1 + `scenes/art_trial.tscn` |
| 材质资源化（类型→材质映射，色块起步），T3 管线改走映射 | 完成 | `TerrainMaterialLibrary` + 两张 .tres + `build_map` 第 4 参 |
| UV 约定定死（顶面/侧面映射、UV 尺寸） | 完成 | 本文 §2 + builder `_uv_*` + UV 锚测试 |
| 法线硬边策略显式定 | 完成 | 本文 §3 + 硬边锚测试 |
| 边界混色/Texture2DArray/自定义 shader 不做 | 未做（按任务卡） | —— |
| 合并路径演练一次 | 书面完成 | 本文 §6 |
