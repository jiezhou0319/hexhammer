# Hexhammer M1a 地图地基：实现路线与学习参考

本报告针对你的 M1a，而不是泛泛讨论“怎样生成地图”。推荐采用“自己掌握六边形数学与地图数据，借鉴成熟的连续网格三角化算法，用 Godot 原生 Mesh 和物理射线完成表现与交互”的路线；最值得组合学习的是 Red Blob Games、Catlike Coding 的 Hex Map 高程章节，以及老李游戏学院的 Godot 移植工程。[六边形数学](https://www.redblobgames.com/grids/hexagons/)、[高程与阶梯教程](https://catlikecoding.com/unity/tutorials/hex-map/part-3/)和[中文 Godot 工程](https://github.com/LiGameAcademy/godot_hex_map)分别覆盖这三个环节。

调研日期：2026-10-09。需求基线为 Hexhammer 提交 `83b6874668dd7952d9a037825f25e52b61c227e9`；最新版已移除工期估算，改为按验收推进，因此这里也不给未经实测的周数承诺。[当前任务拆分](https://raw.githubusercontent.com/jiezhou0319/hexhammer/83b6874668dd7952d9a037825f25e52b61c227e9/docs/04-tasks-m1.md)

本文中的“推荐”“建议”和验收补充是方案设计，不是已运行的性能结论。对参考工程进行了文档阅读和部分核心代码静读，没有在 Godot 中运行这些工程，也没有改动你的项目代码。

## 先给结论

**这套需求有可学习、可拆解的实现路径，不需要从零发明全部算法。** 但没有证据表明某个现成插件可以直接满足你的“连续高程地形、纯逻辑分层、固定俯角相机、精确拾取”全部约束；推荐借鉴局部算法，而不是整体替换项目架构。[你的 M1a 要求](https://raw.githubusercontent.com/jiezhou0319/hexhammer/83b6874668dd7952d9a037825f25e52b61c227e9/docs/04-tasks-m1.md)、[参考工程的功能与结构](https://github.com/LiGameAcademy/godot_hex_map)

- **最难的部分：** 不是画出六边形，而是两格之间的连接带、三格交汇的角落，以及跨 chunk 的一致性；Catlike Coding 分别给出了高程边分类、角落组合处理和分块刷新方法。[高程与角落](https://catlikecoding.com/unity/tutorials/hex-map/part-3/)、[分块地图](https://catlikecoding.com/unity/tutorials/hex-map/part-5/)
- **最容易被低估的部分：** “点中哪个格”不能只验格心；Godot 的射线能够返回碰撞位置，而凹三角网格还可返回 `face_index`，可用于设计斜坡、悬崖与交汇角的归属规则。[射线查询结果](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html)
- **最该控制的范围：** M1a 保留固定测试图、色块材质、有限高程与简单随机来源，不顺带实现河流、道路、复杂生态、地图编辑器和迷雾；你的当前路线图也明确不在本阶段实现地形战斗数值或精细美术。[M1a 范围](https://raw.githubusercontent.com/jiezhou0319/hexhammer/83b6874668dd7952d9a037825f25e52b61c227e9/docs/03-roadmap.md)

## 最值得参考学习的资料

| 优先级 | 资料 | 对你的用途 | 不要误解成什么 |
|---|---|---|---|
| 必学 | [Red Blob Games：Hexagonal Grids](https://www.redblobgames.com/grids/hexagons/) | Axial/cube 坐标、六邻居、距离、坐标变换、浮点 cube rounding，直接对应 T1。 | 是算法指南，不是 Godot 连续高程地图插件。 |
| 必学 | [Catlike Coding：Elevation and Terraces](https://catlikecoding.com/unity/tutorials/hex-map/part-3/) | 等高、一级高差、多级高差分类，边连接与三格角落处理，直接对应 T4。 | Unity/C# 教程，要移植算法；教程外观不等于 Civilization VI 引擎实现。 |
| 必看源码 | [老李游戏学院：godot_hex_map](https://github.com/LiGameAcademy/godot_hex_map) | 中文说明，Godot 4.6/Forward+，GDScript 网格、分块、高程与编辑器；MIT 许可，最贴近当前学习环境。 | 不是已验证在你的 Godot 4.7.2 下零改动运行的组件，也不该把编辑器、水体、道路全部搬进 M1a。 |
| 对照学习 | [davepruitt：hex_map_godot](https://github.com/davepruitt/hex_map_godot) | 作者说明完成原版 27 篇 Hex Map 教程的 Godot/GDScript 移植，MIT 许可，适合对照不同组织方式。 | 作者承认有细小差异或 bug；工程配置写的是 4.3/Mobile，不是你的目标环境。[配置证据](https://raw.githubusercontent.com/davepruitt/hex_map_godot/135dc754245fa867385a0d4af01ee0ae594ce526/hex_project_godot/project.godot) |
| 实现时查 | [Godot SurfaceTool](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/surfacetool.html) 与 [ArrayMesh](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/arraymesh.html) | 顶点、索引、法线、UV、颜色及 Mesh 提交，直接对应 T3/T4/T8。 | API 说明不会替你决定格子拓扑、边归属或角落补洞。 |
| 实现时查 | [Godot Ray-casting](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html) 与 [Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html) | 屏幕射线、世界命中、投影/反投影、正交相机 size，直接对应 T5/T6。 | 一条射线命中不等于已经定义“悬崖应归哪个格”。 |
| 后续按需 | [Catlike Coding：Larger Maps](https://catlikecoding.com/unity/tutorials/hex-map/part-5/) | Chunk 划分、局部重建、跨块刷新，适合从小图走向 60×40。 | 教程的 5×5 chunk 是示例，不是你项目的性能最优答案。 |

中文工程 README 提到配套课程《从零手搓六边形网格系统》，也提供课程社区入口；本次只核实到这一说明，没有核实课程价格、访问权限或完整教学质量，可以先用公开源码判断是否适合自己。[课程说明所在 README](https://github.com/LiGameAcademy/godot_hex_map)

### 中文工程具体读哪些文件

建议按以下顺序阅读，不要直接从最复杂的地形文件开始。下列文件在静读快照 `cb5460fd20ae54d2be285eb2110b6a5fbf0a8b43` 中已核对。

- **`hex_coordinates.gd`：** 读 `from_offset()`、`from_position()`，理解从世界 XZ 到浮点坐标再修正成合法 cube/axial 的过程；用你自己的单测重新实现，而不是把教程的变量名和坐标方向当成唯一标准。[坐标代码](https://raw.githubusercontent.com/LiGameAcademy/godot_hex_map/cb5460fd20ae54d2be285eb2110b6a5fbf0a8b43/addons/hex_map_editor/scripts/hex_coordinates.gd)
- **`hex_mesh.gd`：** 读 `begin_triangles()`、`add_triangle()`、`add_quad()`、`commit_triangles()`；它用 SurfaceTool 收集顶点、颜色和可选地形自定义数据，然后提交 Mesh，适合学习“算法输出几何”的边界。[网格构建代码](https://raw.githubusercontent.com/LiGameAcademy/godot_hex_map/cb5460fd20ae54d2be285eb2110b6a5fbf0a8b43/addons/hex_map_editor/prefabs/hex_mesh.gd)
- **`hex_grid_chunk.gd`：** 优先读 `_triangulate_connection()`、`_triangulate_edge_terraces()`、`_triangulate_corner()` 和两个 slope/cliff 混合角落分支；先跳过 river、water、road 和 feature 的路径，避免学习范围被完整示例带偏。[地形三角化代码](https://raw.githubusercontent.com/LiGameAcademy/godot_hex_map/cb5460fd20ae54d2be285eb2110b6a5fbf0a8b43/addons/hex_map_editor/prefabs/hex_grid_chunk.gd)
- **`hex_map_camera.gd`：** 可以借鉴输入、平移、缩放和边界计算；但它会随缩放把俯角从 −90° 插值到 −45°，与你固定俯角的要求不同，应删去或关闭这条插值逻辑。[相机代码](https://raw.githubusercontent.com/LiGameAcademy/godot_hex_map/cb5460fd20ae54d2be285eb2110b6a5fbf0a8b43/addons/hex_map_editor/prefabs/hex_map_camera.gd)、[你的相机要求](https://raw.githubusercontent.com/jiezhou0319/hexhammer/83b6874668dd7952d9a037825f25e52b61c227e9/docs/04-tasks-m1.md)

## 推荐的最小架构

以下是适配建议，不是要求你照搬参考工程。核心原则是：地图数据不持有场景节点；渲染器读数据生成几何；输入组件把命中转换成格子坐标；相机与高亮不修改地图规则。

```text
HexMath                     纯数学：邻居、距离、rounding
MapData / MapDef            格子表：terrain_id / elevation / passability
    ↓
HexTerrainBuilder           生成顶面、连接带、角落与碰撞三角形
    ↓
MapView
    ├─ TerrainChunk         MeshInstance3D + 静态地形碰撞
    ├─ HighlightLayer       每格高亮，只更新变更集合
    └─ MapPicker            射线 → 命中 → cell coordinate

CameraRig                   固定俯角、平移、缩放、边界钳制
TerrainMaterialLibrary      terrain_id → 材质资源
MapGenerator                固定图 / 种子随机图 → MapData
```

**不要为了学习连续网格而把整套地图编辑器变成项目基础设施。** 中文参考工程同时包含编辑器、地形特征、纹理数组等完整功能；你的任务只需要其中的局部原理，当前 `MapData` 约定仍以尺寸、地形、离散高程和通行性为核心。[参考工程结构](https://github.com/LiGameAcademy/godot_hex_map)、[你的 T2/T8/T9](https://raw.githubusercontent.com/jiezhou0319/hexhammer/83b6874668dd7952d9a037825f25e52b61c227e9/docs/04-tasks-m1.md)

### Hex 数学与数据层：先定约定

推荐使用 pointy-top、XZ 为地面、Y 为高程作为第一套约定；若你希望 flat-top，也可以选择另一套公式，但不要在不同模块中混用方向。Axial 存 `(q,r)`，需要 cube 时计算第三轴 `s=-q-r`，是 Red Blob 推荐的组织方式。[坐标系统](https://www.redblobgames.com/grids/hexagons/)

若采用半径为 \(R\) 的 pointy-top 网格，可用：

\[
x=\sqrt{3}R(q+r/2),\qquad z=\frac{3}{2}Rr,\qquad y=h\Delta H
\]

前两式来自 pointy-top 六边形坐标映射，假设各轴使用相同半径且地图局部原点为零；第三式是本报告建议的离散高程到世界高度约定。[坐标映射实现](https://www.redblobgames.com/grids/hexagons/implementation.html)、[离散高程示例](https://catlikecoding.com/unity/tutorials/hex-map/part-3/)

建议同时写清四件事：

- **地图外形：** “60×40”是 60 列×40 行的 offset 矩形，还是 axial 范围形成的平行四边形？建议内部算法用 axial，地图存储/边界使用明确的 row/column 转换。
- **方向编号：** 固定 0～5 的顺序，保证邻居向量、顶点、边、朝向一致。
- **边界规则：** 不存在的邻格不能生成悬空连接；地图外沿是否需要侧壁，作为单独表现规则。
- **数据版本：** `MapDef` 留 `schema_version`；格子顺序固定，地图摘要可比较。

这些都是实施前的小决策，不需要重新讨论玩法。T1 单测优先覆盖邻居反向、距离对称、坐标往返、负坐标 rounding、边界转换；Red Blob 特别说明 cube rounding 需要修正最大误差轴，不能简单分别四舍五入两个轴。[Rounding 算法](https://www.redblobgames.com/grids/hexagons/)

### 连续高程网格：用“顶面、边带、角落”拆开

推荐先理解 Catlike Coding 的结构：每格保留一个可站立的内顶面，格与格之间留出连接带，三格交汇处有独立角落面；教程根据等高、一级高差、多级高差选择连接与角落的三角化方法。[高程算法](https://catlikecoding.com/unity/tutorials/hex-map/part-3/)

建议把你的实现分成三个纯几何步骤：

- **顶面：** 根据格心和六个内顶点，生成三角扇；首版保持平整、不加噪声扰动，方便站立点和拾取。
- **边带：** 两格等高则平连接；相差一级则斜坡或简化阶梯；更大高差使用陡面/悬崖连接。
- **角落：** 读取相邻三格的高程组合，生成补洞几何；不能只把两两边带拼在一起后假定角落自然封闭。

Catlike Coding 将高差绝对值 1 分类为 Slope，其余非零高差为 Cliff，并对混合角落使用不同分支；这一点可以直接学，但其 Cliff 的几何不必然是严格垂直墙。[边分类与角落处理](https://catlikecoding.com/unity/tutorials/hex-map/part-3/) 如果你要求真正垂直的悬崖壁，需补充墙面位置、墙顶/墙底连接及点击归属规则，不应把教程的“Cliff”名称等同于最终视觉需求。

建议在几何构建前加“归属”规则，避免重复面：

- **共享边：** 每条无向边只有一个生成者，例如两格稳定 ID 较小者。
- **共享角：** 用三个格子的稳定 ID 形成唯一 key，只有一个生成者。
- **跨块采样：** Chunk 可以读取邻块格子数据；不能把 chunk 边界当地图边界。
- **一致顶点：** 顶点从相同的全局格心/边参数计算；不要在两个 chunk 内各自随机扰动同一接缝。

这些归属策略是本报告的实现建议；参考工程采用方向范围限制来避免重复连接，并把三格角落按高程顺序交给不同三角化分支，可以对照理解，不必原样复制方向枚举。[连接与角落源码](https://raw.githubusercontent.com/LiGameAcademy/godot_hex_map/cb5460fd20ae54d2be285eb2110b6a5fbf0a8b43/addons/hex_map_editor/prefabs/hex_grid_chunk.gd)

### Mesh、分块与材质：先可读，再优化

推荐首版使用 SurfaceTool，等三角化正确后，再根据实测决定是否改为直接填 PackedArrays 的 ArrayMesh；SurfaceTool 提供顶点属性收集、索引与法线生成，ArrayMesh 则直接接收数组，并要求相应顶点属性数量一致。[SurfaceTool](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/surfacetool.html)、[ArrayMesh](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/arraymesh.html)

建议首版不用“每格一个完整地形场景”，而使用 chunk 地形 mesh。以 10×10 格作为可实验的起点，60×40 会形成 24 个 chunk；这只是方便实现的起始参数，不是性能结论，需与 5×5、其他块尺寸实测比较。Catlike Coding 的分块教程说明了 draw call、剔除和重建范围之间的取舍，也要求修改格子时刷新受影响的邻块。[Chunk 教程](https://catlikecoding.com/unity/tutorials/hex-map/part-5/)

建议材质先用简单路线：

- **类型到材质：** `terrain_id → Material.tres`，每 chunk 按少量地形类型组织 surface，而不是每格一个 surface。
- **纹理接口：** 现在就约定 UV 尺度、地形顶面与侧面的映射；否则“只替换贴图、不改主线”没有成立条件。
- **法线：** 平顶和陡壁是否保持硬边要明确；不应期待自动平滑法线给出所有期望效果。
- **边界混色：** 首版可用固定归属颜色；Texture2DArray、自定义 shader 和三地形混合是以后升级，不是“换一张贴图”同样简单的工作。

参考中文工程已经使用纹理数组和自定义地形数据；其 `HexMesh` 也演示了顶点颜色与 custom attributes 的写入，可作为后续扩展参照。[工程功能](https://github.com/LiGameAcademy/godot_hex_map)、[Mesh 代码](https://raw.githubusercontent.com/LiGameAcademy/godot_hex_map/cb5460fd20ae54d2be285eb2110b6a5fbf0a8b43/addons/hex_map_editor/prefabs/hex_mesh.gd) 若首版用顶点颜色显示地形，Godot 材质需要开启 `vertex_color_use_as_albedo`，默认值是 false。[材质属性](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html)

### 拾取：先打通当前设计，再补边界归属

你现在的设计是“屏幕射线 → 地形 mesh 物理 raycast → 世界坐标 → axial”，这条主链可以保留。[T5 原要求](https://raw.githubusercontent.com/jiezhou0319/hexhammer/83b6874668dd7952d9a037825f25e52b61c227e9/docs/04-tasks-m1.md) Godot 提供 `Camera3D.project_ray_origin()`、`project_ray_normal()` 和 `PhysicsDirectSpaceState3D.intersect_ray()`，可以实现它。[Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)、[射线查询](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html)

推荐实现过程：

1. 地形 chunk 使用静态碰撞体，射线 mask 只查地形，不让棋子、高亮或装饰先截获。
2. 输入记录点击请求，在合适的物理回调中查询；官方教程提醒物理空间在其他回调时可能被锁定。[查询时机](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html)
3. 命中位置是世界坐标，先变换到地图根节点局部坐标，再用局部 XZ 转浮点 axial 并 rounding。
4. 若点在顶面，用标准转换；若点在斜坡、悬崖、交汇角，应用事先定义的归属规则。
5. 对有歧义的三角形，可保存 `face → 候选格子` 表作为增强机制，不必一开始就替换所有坐标转换。

静态地形可以使用 `ConcavePolygonShape3D` 的三角网格；但它是空心、适用于静态关卡几何的碰撞形状，不宜当移动棋子的通用碰撞体。[碰撞形状限制](https://docs.godotengine.org/en/stable/classes/class_concavepolygonshape3d.html) `face_index` 只对该形状有效，其他形状会返回 −1，因此如果采用面归属表，要用自己明确提交的碰撞三角形顺序建立映射，并用小场景校验，不能假定它自动等于任意渲染 mesh 的索引。[face_index 条件](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html)

建议默认的归属方案是“顶面归本格，斜坡按局部 XZ 最近的逻辑格心判定，距离相等按固定 ID 决定，悬崖归高地侧或明确拒绝点击”。这是可选择的产品规则，不是官方 API 保证；选定后再写测试，才能谈边界点击的正确性。

### 相机、高亮和随机地图

- **相机：** 建议先用固定俯角的 CameraRig；平移在 XZ 平面，缩放选择正交 `size` 或透视距离之一。Godot 对正交 size 有明确说明，参考中文工程则使用随 zoom 变化的俯角，不能不加修改地照搬。[Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)、[参考相机](https://raw.githubusercontent.com/LiGameAcademy/godot_hex_map/cb5460fd20ae54d2be285eb2110b6a5fbf0a8b43/addons/hex_map_editor/prefabs/hex_map_camera.gd)
- **相机边界：** 建议先定义是限制“相机焦点”还是“整个可见地图范围”，然后覆盖最大/最小缩放测试；拖拽建议使用固定参考平面或稳定锚点，避免跨高程时镜头跳动。
- **高亮：** 保留你现有每格半透明 mesh 方案，首版贴合内顶面或复制相关表面三角形后加少量偏移，缓存节点并按集合差异切换，避免鼠标移动时重建地形。[T7 要求](https://raw.githubusercontent.com/jiezhou0319/hexhammer/83b6874668dd7952d9a037825f25e52b61c227e9/docs/04-tasks-m1.md) 透明模式有深度与排序取舍，先测试近远缩放和相邻重叠，不建议靠“关闭深度测试”掩盖穿山问题。[材质透明与深度](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html)
- **随机地图：** 建议低频噪声采样 → 量化整数高程 → 地形分类 → 连通性检查，先不要对每格独立随机高程。FastNoiseLite 提供 seed，Noise 提供 `get_noise_2d()`；部分 cellular 类型数值可能超过 1，不能对所有噪声类型都假定输出严格在 −1～1。[FastNoiseLite](https://docs.godotengine.org/en/stable/classes/class_fastnoiselite.html)、[Noise API](https://docs.godotengine.org/en/stable/classes/class_noise.html)
- **复现与测试：** 建议保存 seed、参数、生成器版本和最终格子表摘要；同 seed 的验收限定在固定生成器/引擎配置下，不承诺跨版本噪声输出永不改变。固定测试图仍是几何验证的主依据，随机图只是补充。

## 怎样把 T1～T9 真正做完

下表是建议的实施顺序和新增验收，不是对你原任务的强制改写。原有范围和验收以当前 [04 任务拆分](https://raw.githubusercontent.com/jiezhou0319/hexhammer/83b6874668dd7952d9a037825f25e52b61c227e9/docs/04-tasks-m1.md)为准。

| 原任务 | 推荐产物 | 最有价值的检查 |
|---|---|---|
| T1 数学 | `HexMath` 和纯单测 | 六邻居反向、距离、rounding、坐标往返、负坐标。 |
| T2 数据 | `MapData`、固定小测试图 | 数据无场景依赖；序列化往返一致；明确地图外形与边界。 |
| T3 平地渲染 | 小图 chunk mesh、固定材质表 | 顶点顺序、法线、UV、相邻无缝；之后再扩大到 60×40。 |
| T4 高程连接 | 顶面、边带、角落三角化 | 0/0/0、0/0/1、0/1/1、0/1/2、0/0/2 等交汇组合，跨 chunk 和地图外沿。 |
| T5 拾取 | 地形碰撞、picker、归属规则 | 格心全量测试；边/角/斜坡/悬崖；地图根节点平移后仍正确。 |
| T6 相机 | 固定俯角 CameraRig | 拖拽稳定、边缘平移、缩放极值、焦点边界。 |
| T7 高亮 | 独立 HighlightLayer | hover、选择集合、清空、切换；不重建地形；无穿山/闪烁。 |
| T8 材质 | UV 约定、材质资源表、小实验场景 | 换材质/贴图不改主线；把混合 shader 升级另列任务。 |
| T9 地图来源 | 固定图 + 参数化简单生成器 | 同配置同 seed 格子摘要一致；断路/孤岛可检查；失败图保存。 |

### 推荐的学习与练习顺序

1. **先读 Red Blob 的 Coordinates、Neighbors、Distances、Hex to pixel、Pixel to hex、Rounding。** 随后独立写数学单测，不先打开复杂地图场景。[算法指南](https://www.redblobgames.com/grids/hexagons/)
2. **用 SurfaceTool 画一个六边形，再画一个 7 格小图。** 只解决顶点、法线、UV、材质，不加随机、不加美术资产。[SurfaceTool 教程](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/surfacetool.html)
3. **读 Catlike Coding 高程章节，对照中文工程做两格边带和三格角落。** 先用固定高程样例，把混合角落补洞走通；这是 M1a 的核心学习关口。[高程教程](https://catlikecoding.com/unity/tutorials/hex-map/part-3/)、[中文三角化实现](https://raw.githubusercontent.com/LiGameAcademy/godot_hex_map/cb5460fd20ae54d2be285eb2110b6a5fbf0a8b43/addons/hex_map_editor/prefabs/hex_grid_chunk.gd)
4. **在带高程小图上接拾取、相机和高亮。** 不用平面求交代替最终 terrain raycast，但可以用数学单测验证坐标公式。[当前 T5/T6/T7](https://raw.githubusercontent.com/jiezhou0319/hexhammer/83b6874668dd7952d9a037825f25e52b61c227e9/docs/04-tasks-m1.md)
5. **加入 chunk 和跨块测试，再扩大到 60×40。** 最后记录 Mesh 构建、碰撞构建、射线查询、帧时间和高亮切换数据；无实测前不保证任意方案“肯定流畅”。[分块原理](https://catlikecoding.com/unity/tutorials/hex-map/part-5/)
6. **最后接简单随机图与换贴图实验。** 用随机图找几何反例，不让地形生成、美术和 shader 先拖住核心正确性。

建议的最小垂直切片是：**一个 chunk、少量固定格子、三档高程、平/坡/陡面连接、格心可点选、可高亮、固定俯角相机**。这是一项实施建议，不是删掉最终 60×40 验收；通过后再扩展全图，比同时处理所有需求更容易定位问题。

## 哪些工具不要误选

- **HexGrid_Godot_4.0：** 适合作为数学函数对照，有邻居、距离、rounding 和 2D 坐标转换接口，但没有提供连续高程连接的实现证据；不应把它当 T4 的答案。[仓库接口说明](https://github.com/HugoEnzo/HexGrid_Godot_4.0)
- **Hex Strategy Map：** 资产页列出的 renderer 使用 Polygon2D/Sprite2D 等节点，适合学习数据、寻路与交互接口，不是你要求的 3D 连续地形交付物。[资产页](https://godotengine.org/asset-library/asset/5136)
- **dmlary/godot-hex-map：** 提供 Godot 4 GDExtension 的 3D hex tile 节点及规则放置，README 明示 API 尚未冻结且文档稀疏；建议暂不作为 M1a 的核心依赖，你更需要能解释边与角如何连接的可控几何算法。[项目 README](https://github.com/dmlary/godot-hex-map/blob/main/README.md)

## 建议现在先决定的三个小问题

- **悬崖样式：** 大高差接受 Catlike 风格的陡连接面，还是必须是垂直墙？两者都可设计，但几何和点击归属不同。
- **站立与高亮范围：** 棋子只站在格心平顶，高亮只覆盖内顶面，还是连斜坡连接带也需完整覆盖？建议首版先选前者。
- **边界点击归属：** 斜坡、悬崖和三格角落具体选谁？建议先给固定策略，再做测试。

这三个决定比现在选一个复杂地形插件更有价值。确定后，可以把上面的方案转为 T1～T5 的具体接口和测试用例，而不必重开整个游戏设计。

## 核验范围

已核对当前 Hexhammer M1a 文档、Godot 官方 API、Catlike 高程与分块教程、两个 Godot 移植工程的 README，并静读了部分中文工程核心脚本。参考工程的版本标记分别为中文工程 4.6/Forward+、Dave 工程 4.3/Mobile；这些标记不是在你目标版本上的运行证明。[中文工程配置](https://raw.githubusercontent.com/LiGameAcademy/godot_hex_map/cb5460fd20ae54d2be285eb2110b6a5fbf0a8b43/project.godot)、[Dave 工程配置](https://raw.githubusercontent.com/davepruitt/hex_map_godot/135dc754245fa867385a0d4af01ee0ae594ce526/hex_project_godot/project.godot)

本次未核实 Civilization VI 内部地图实现，也未执行 Godot 兼容性、渲染性能或碰撞 face_index 对照测试。算法路线是有证据支持的学习建议，最终外观、兼容性和性能仍需要你的最小样例验证。
