# 10 · 3D 资产管线与表现层地基（2026-10-07）

> ⚠️ **2026-10-07 追记：KayKit/Kenney 三包已从项目彻底移除**（`assets/kaykit/` 删除）。
> 决策见 [11-terrain-pipeline.md](11-terrain-pipeline.md) §1：地形转向自研地形系统 +
> AI 生成内容物管线（在线质量件 / 本地白模型量产 / 程序化规则件三路供给），
> KayKit 瓦片路线废弃，散件亦不再使用。`demo_hexfield.gd` 已切换为程序化占位版
> （六棱柱瓦片 + 胶囊单位 + 哈希散布，交互链路不变）。
> 本文以下内容保留作**历史记录**（下载/验证流程在需要重新获取 CC0 素材时仍可复用）。

> 本文档记录 KayKit 资产接入、目录结构、验证流程。表现层定位：为 M2"第二代 UI"铺路，
> 分层纪律不变（docs/02 §3）：demo 脚本属 `scripts/ui`，删掉后逻辑层测试仍须全绿。

## 1. 资产来源与授权

| 包 | 内容 | 授权 | 位置 |
| --- | --- | --- | --- |
| KayKit Medieval Hexagon Pack 1.0 | 221 模型：草/水/坡地瓦片、19 种建筑×5 色、装饰 | **CC0** | `assets/kaykit/medieval/` |
| KayKit Character Pack: Skeletons 1.0 | 4 个带动画角色 GLB + 27 武器件 | **CC0** | `assets/kaykit/skeletons/` |
| KayKit Hexagons（Kenney 官方） | 10 GLB：森林/岩石/沙地瓦片 + 物件 | **MIT**（©Kenney） | `assets/kaykit/hexagons/` |

- 来源均为 GitHub 镜像（`KayKit-Game-Assets` org、`KenneyNL/KayKit-Hexagons`），
  itch.io 本机不可达（CDN 被墙）；下载脚本要点见 §5。
- **Adventurers 角色包仓库已被官方删除**（404，非网络问题）。活人系兵种模型缺口，
  候补源：`taictdev/KayKit`（74MB 合集）、poly.pizza（搜 Kay Lousberg）。
- 五色建筑（红蓝绿黄中立）正好覆盖"AI 同派系换色"（docs/00 支柱 5）。

## 2. 目录结构（新增部分）

```
assets/kaykit/            ← 第三方 3D 资产（含各自的 LICENSE 副本）
addons/hexhammer/hex.gd   ← 六边形数学（axial/pointy-top），M2 计划提前落地
resources/units/*.tres    ← 8 兵种 UnitProfile（数值 = docs/08 v6.1 定稿带）
scenes/demo_hexfield.tscn ← 3D 演示主场景
scripts/ui/demo_hexfield.gd ← 表现层 demo（地图铺设/点选/移动范围/Tween 移动）
scripts/ui/camera_rig.gd    ← 战旗相机（WASD 平移 + 滚轮缩放）
scripts/core/data/unit_profile.gd ← 兵种数据模型（model 字段留接 PackedScene）
tests/run_tests.gd + test_hex.gd ← 零依赖 runner + hex 单测（8 用例）
```

## 3. 几何约定（对齐 KayKit 瓦片）

- KayKit 六边形瓦片按**格中心距 = 1 世界单位**设计 → 外接圆半径 = `1/√3`。
- `Hex.axial_to_world(cell, hex_radius)`：调用处传 `TILE_SPACING / sqrt(3)`。
- odd-r offset 只在地图生成与显示时转换（ADR-1 纪律）。

## 4. 模型绑定路线（现状 → 目标）

- **现状**：`demo_hexfield.gd` 的 `UNIT_MODELS` 字典集中映射兵种 id → GLB 路径。
- **目标**：`UnitProfile.model: PackedScene` 字段直接引用（.tres 编辑器里拖 GLB），
  demo 字典随后删除。兵种→模型的绑定全部数据化，代码零 hardcode。

## 5. 下载与验证流程（复现用）

```bash
# 资产下载（GitHub codeload 间歇超时，重试 + 断点续传）
curl -sL -C - -o pack.tar.gz \
  "https://codeload.github.com/KayKit-Game-Assets/<包名>-1.0/tar.gz/refs/heads/main"

# 导入验证（450+ 文件，约 1 分钟）
"E:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --import

# 单测（当前 8 用例）
"E:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . \
  --script res://tests/run_tests.gd

# 3D 画面自动验收（起窗口 3 秒，存图即退；--close-shot 为单位近景）
"E:\Godot\Godot_v4.6.2-stable_win64_console.exe" --path . --resolution 1600x900 \
  -- "--auto-shot=E:/Code/model-previews/tmp/demo.png" [--close-shot]
```

坑位记录：
- movie writer（`--write-movie`）在本机 AMD/RX7700XT 只录到背景色，不可用 →
  用 demo 内置 `--auto-shot` 钩子（`get_viewport().get_texture().get_image()`）。
- 相机沿视线方向放置会沉到地下（y<0 背面剔除 → 全屏背景色），必须**反向**抬升。
- 手写 .tres 引用 GLB 前必须先跑一次 `--import`（生成 PackedScene 导入信息）。

## 6. 下一步（对齐 docs/03 路线图）

1. M1 规则闭环优先：BattleEngine/命令模式/事件流重建（demo 的移动改发命令）。
2. 活人系兵种模型补齐（Adventures 替代源）+ `UnitProfile.model` 数据化绑定。
3. 地形数据化：瓦片类型进 MapDef（水/坡地 → 移动消耗/视线遮挡的规则输入）。
