# M1a+ BLEND-02 实现注记——三格交汇与跨 chunk 过渡

> 对应 docs/04-tasks-m1.md §M1a+ 第一批卡 BLEND-02 与
> docs/M1a-terrain-world-proposal.md「材质过渡」（「每三角形最多三种地形索引」
> 的最小落地 = 色板权重版）+「跨 chunk 与增量更新」（角 key 稳定、锚点从世界
> 数据计算）。本文登记实现取舍与目检口径，供 BLEND-03 与纹理版沿用；翻案须同步改
> `tests/test_hex_terrain_blend_corner.gd` 的锚。

## 数据路径（BLEND-01 之上的增量）

```text
HexTerrainBlend（纯逻辑合同，本卡新增三格部分）
  · corner_weights(u, v) = (1−u−v, u, v)  → (归属格, N(k), N(k−1)) 权重
  · is_valid_weights3(w)                  → 有限、非负（−eps 浮点零点窗口）、和恒 1
  · blend_color3(c_owner, c_nbk, c_nbk1, w) → 三色逐通道加权和
       └→ HexTerrainBuilder.build_map_blend / build_chunk_blend（几何/COLOR 零行为变化——
            角面顶点本就是合同单位权重锚点：p1=(1,0,0)、p2=(0,1,0)、p3=(0,0,1)，
            发射序 (p1,p3,p2) → 色 (owner, N(k−1), N(k))，与 BLEND-01 落地规则同构）
       └→ 面内三色过渡 = 顶点 COLOR 的 GPU 线性插值（重心 = 1/3 均权，和恒 1）
```

## 权重合同的读法（headless 锚 = tests/test_hex_terrain_blend_corner.gd）

- 角面重心参数 (u, v) 与几何同构：角面三角形 = p1 + u·bridge_k + v·bridge_{k−1}
  （仿射参数域 u,v ≥ 0、u+v ≤ 1）——重心 u=v=1/3 ⇔ 几何重心 = p1 +
  (bridge_k + bridge_{k−1})/3（与 BLEND-01「边带中点 = owner 端 + 半桥」同一对应）。
- **单位权重锚点不落成新的 mesh 顶点**：角面仍是一个三角（面数不变 → face 表/
  碰撞合同不动，任务卡边界）。三方混合全部由三个顶点纯色的线性插值实现；
  单测用 `blend_color3(顶点色…, corner_weights(1/3,1/3))` 链路锚定重心等价。
- **两色角退化**（草-草-泥这类）：按地形聚合权重后 = 共色 2/3 + 独色 1/3，
  与边带合同 `blend_color(c, d, 2/3)` 逐通道一致——「角混三种」的最大=3、
  常见=2 由同一合同覆盖，测试双锚（合同层 + mesh 层）。
- 浮点口径三条（均沿用 BLEND-01 的既有教训，非新坑）：
  ① mesh 顶点色 8-bit 量化 → 与色板纯色比较用 1/255 容差；
  ② Vector3 权重分量 float32（1/3 不可精确表示）→ 重心均值断言用 1e-6 窗口
  （BLEND-01 中点 1e-9 精确是因为 0.5 可精确表示）；
  ③ `1−u−v` 在 u+v=1 边界有 ≤1 ulp 负舍入（u=0.9,v=0.1 → −2.8e-17）→
  `is_valid_weights3` 非负项带 −eps 零点窗口（真负权重 ≫ eps 照拒）。

## 跨 chunk 与 shared position

- T4 归属规则不动：角面仍由三格稳定 ID 最小者生成、锚点从同一全局参数计算
  （HexMath.inner_vertex / bridge_xz 全局格心现算）——权重/颜色是逐顶点纯色，
  与 chunk 划分无关。
- 一致性锚法：同一张 5×5 草-泥-岩图用**三种划分**构建（单 chunk 10×10 /
  行切 5×1（trio 跨 2 块）/ 每格一 chunk 1×1（trio 分属 3 块）），目标角面的
  位置 + 顶点色跨划分**逐位一致**（mesh↔mesh 精确口径）；另做三格各自视角的
  同一物理点跨路径对账（1e-5）。
- 无裂缝/无重复角面：全图物理角 key 恰一面 × 每划分；每格一 chunk（25 块，
  全部连接几何都是跨块）再过焊接流形不变量（每焊接边恰 1/2 面引用、无重复面
  key、1 面边界边 = 期望外沿、法线全朝上——沿用 test_hex_terrain_elevation.gd
  口径的平地版）。
- 拾取不受影响：跨块划分下 blend ↔ fallback 的碰撞汤/face 表逐位一致 + 角面
  `resolve_face` 归属 = 三格之一；引擎级证据 = 既有三个 scene_check（本卡零改动，
  全绿复跑）。

## 目检载体（F6）

- 打开方式：编辑器打开 `scenes/blend_corner_sandbox.tscn` → 运行当前场景（F6）。
  项目约定无主场景，不要为此场景设置 run/main_scene。
- 默认 `render_style = BLEND`：6×5 草-泥-岩固定图（草底 + 泥区左下 + 岩带首行
  右段；全平高程），chunk 按行切（6×1 = 5 块）——row0/row1 的 chunk 缝正好从
  草-泥-岩三格交汇角中间穿过。
- 看点：角面三端贴各自纯色、角面内连续过渡（重心 ≈ 三色均权）；跨缝无错位、
  无重复角面（重叠会有 z-fighting 网纹）；检查器切 `render_style = SLOTS`
  重跑 = 三色硬切对照；拾取/高亮照常（移动 = 暖黄 hover、左键 = 蓝色选择集）。

## 交付证据（2026-10-10）

- 门禁：`run_tests.gd` 193 用例 / 0 失败（exit 0；含本卡 9 用例——BLEND-01
  交付时为 184）。
- 引擎级：`picking_scene_check.gd` / `highlight_scene_check.gd` /
  `camera_scene_check.gd` 各自 exit 0。
- 沙盒冒烟：`blend_corner_sandbox.tscn` BLEND/SLOTS 两风格 headless 实例化
  无错误、5 chunk 挂载、拾取/高亮节点齐备（临时脚本验证后即删）。
