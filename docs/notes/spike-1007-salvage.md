# notes · spike-1007-demo 分支摘取评估（2026-10-10）

> 定位：`spike-1007-demo` 分支（c321993，2026-10-07 本地 demo 全量存档）相对
> 主线的逐件评估。**全部为参考件：非拍板、非权威、未入主线代码。**
> 上桌时机统一为 **M1a（含 M1a+ 全部卡片）完成之后**——届时 M1b 建单位/战斗
> 表现层、风格卡做美术化，以下件才具备接入条件；在那之前，射程/移动/数值
> 一律只是参考，不构成任何口径。
> 分支中被主线 M1a 彻底超越、无参考价值的部分（旧 hex 数学单文件、简易测试
> runner、camera_rig、demo 的拾取/移动交互链路、`--auto-shot` 钩子）不在此列，
> 留在分支即可，主线已有更强的对应实现（hex_math / 门禁 v2 / T6 相机 /
> T5 拾取 / render_probe）。

## 1. 渲染与表现件（评估结论：按任务卡摘取改写，勿整文件拷入）

### 1.1 格线层 `_make_grid_lines()` ——保留；M1a+ 风格卡候选参考

- **是什么**：文明6 式逻辑分区格线——每个格子六条边用"内外圈夹出宽度的
  四边形条"画成细描边，全部格子合并进一张 SurfaceTool mesh。
- **关键参数/做法**：贴各自格面高度抬升 `LIFT=0.01` 防深度冲突；线宽
  `EDGE_W=0.012`（沿边中点向外法向内缩）；线色 `(0.02,0.02,0.02,0.28)`；
  材质三件套 = UNSHADED + ALPHA + CULL_DISABLED（双面渲染，斜视不消失）；
  水格沉、陆格浮各贴各面。
- **主线现状**：无任何格线渲染（M1a+ BLEND 只做材质过渡；make_trial_textures
  的栅格线是贴图平铺验证，不是格线层）。而 2026-10-10 已拍板**风格 = 阶地
  棋盘感默认**，格子可读性是正向需求——此件是唯一已验证的实现参考。
- **上桌**：M1a+ 风格卡（或美术化任务）时改写为 TerrainStyle 体系下的可选
  overlay 层；注意与 BLEND 权重过渡叠加时的视觉密度需重调。

### 1.2 斜阳与雾环境参数 ——保留；沙盒/render_probe 美术化起手值

spike `_setup_environment()` 的一组**已验证可看**的落点（grimdark 定调的
第一次参数化，对应 docs/12 §1 第 5 条"雾是灵魂"）：

| 件 | 参数 |
| --- | --- |
| 斜阳 DirectionalLight3D | 旋转 (-52°, 155°, 0°)；色 (1.0, 0.87, 0.72)；能量 1.3；阴影开 |
| 雾 | fog_density 0.008；fog_light_color = 天际色 (0.78, 0.84, 0.9) |
| ProceduralSky | 顶 (0.32,0.52,0.82) / 天际 (0.78,0.84,0.9)；地面底 (0.35,0.4,0.35) |
| 环境光 | AMBIENT_SOURCE_SKY，能量 1.1 |

- **主线现状**：m1a_sandbox 为取证口径的暗底色环境（背景 0.16,0.17,0.2 +
  环境光 0.9 + 直射 -52°,-32°/1.2），无天空无雾——这是证据图可复现性的选择，
  不是美术结论。
- **上桌**：美术化/定调出图（垂直切片）时以本组为起手值调；BiomeDef 的
  `atmosphere` 字段（docs/12 §5）承接。

### 1.3 确定性散布哈希 `_hash01(a,b,salt)` ——保留；docs/12 §3 散布系统地基

- 公式：`(a·374761393 + b·668265263 + salt·1274126177) mod 100003 / 100003`，
  整数哈希→[0,1)；同输入恒同输出，无需存摆位。
- spike 用它做：逐格色调抖动（±4% 明度）、装饰散布位置/朝向/缩放（树丛三棵
  各自哈希错开）。这正是 docs/12 §3"配方由散布系统运行时组装"的地基算法。
- 主线现状：`make_trial_textures.gd` 已用确定性公式生成试验贴图（同一思想、
  不同场景）；运行时散布未实现。
- **上桌**：T1/T2 内容物量产 + BiomeDef 落地时（docs/12 §8 下一步 2）。

### 1.4 单位表现件套组 ——保留；M1b 单位上桌参考

- 阵营色棋子底座：扁圆柱 + `emission = color × 0.35` 自发光；选中态改色 +
  底座呼吸 Tween（scale 1→1.14 正弦往返，选中"心跳感"）。
- 移动范围覆盖层：金色六边形描边（`EDGE_W=0.05`，α 0.95）+ 极淡填充（α 0.13），
  内缩比 0.94 不压格边，合并单 mesh、UNSHADED 双面。
- 程序化占位图元：胶囊身躯 + 圆柱/锥（**Godot 无 ConeMesh：圆柱顶半径归零即锥**）；
  占位配色即 grimdark 低饱和雏形（GRASS 0.24,0.32,0.18 等，见分支源码常量）。
- 与主线关系：hex_highlight（内顶面扇形）管选中/路径高亮，本件管**范围提示
  +单位本体**，互补不冲突；正式模型接入走 `UnitProfile.model: PackedScene`。

### 1.5 `HexMath` 缺口三件：`ring / spiral / line` ——保留；M1b 时移植

主线 `hex_math.gd` 无此三函数（M1a 只建了地形所需）：

| 函数 | 签名 | 用途 |
| --- | --- | --- |
| ring | `(center, radius) -> Array[Vector2i]` | 半径环（射程环/冲击波） |
| spiral | `(center, radius) -> Array[Vector2i]` | 半径内全部格（视野/区域效果） |
| line | `(a, b) -> Array[Vector2i]` | cube 插值直线格序列（直线弹道/视线） |

标准 redblobgames 移植，spike 版已按本作 axial 口径写好（分支
`addons/hexhammer/hex.gd`）；M1b 做射程/移动/弹道时抄入 `hex_math.gd` 并按
其"翻案须同步改测试"纪律补锚用例。

## 2. Godot 4.7 坑位记录（spike 实测；主线已规避的注背景）

1. **SurfaceTool 顶点色全黑**：几何/AABB 正常但 COLOR 丢失 → 顶点色一律走
   ArrayMesh 手动组装（COLOR 数组直写）。主线 builder 本就直写 arrays，未踩。
2. **无 DirectionalLight3D 时 SurfaceTool mesh 全体隐形**（仅天空环境光不行）。
   主线沙盒恒挂 Sun，未踩。
3. **无 ConeMesh**：`CylinderMesh.top_radius = 0` 即锥。
4. **movie writer（--write-movie）在 AMD/RX7700XT 只录到背景色**：自动出图用
   viewport `get_texture().get_image()` 自存。主线 render_probe 已内置同思路。
5. **相机沿视线放置会沉地**（y<0 背面剔除 → 全屏背景色）：必须沿视线**反向**
   抬升。主线 T6 相机另实现，此坑对自由相机调试仍有参考价值。
6. **手写 .tres 引用 GLB 前必须先跑一次 `--import`**（生成 PackedScene 导入
   信息），否则资源解析失败。

## 3. 兵种数据参考（`resources/units/*.tres` ×8 + `unit_profile.gd`）

> **数值 = 参考，不是权威。权威 = docs/08（其 §4 数值带自称"重锚前仅作相对
> 高低参考"）；v7 重锚与后续共创必有调整。本节仅记录"曾有一份机器可读版"
> 这一事实与字段口径差。**

- 2026-10-10 对账：8 兵种六列（ATK/DEF/HP/速度/射程/闪避）与主线 docs/08 v7
  数值带**逐格一致**（弓箭 130/45/160/4/4、骑弓 95/45/170/8/3/15% 等）。
- **字段口径漂移三处**（M1b 建正式 UnitProfile 时须改）：
  1. `leadership`：Ld 列已废（08 §0.5，士气确定性化）——删除；
  2. `cost: int` 单金币：08 §4 成本改分类型资源重锚——字段形态待重设计；
  3. 缺**反击系数/反击能力位**（08 v7 新增列）——补。
- `model: PackedScene` 数据驱动绑定（.tres 里拖模型，代码零 hardcode）设计
  沿用。8 兵种超出 M1b"3 势力×4 兵种"证伪范围，mage/medic/siege/horse_archer
  属 M2+ 储备。
- **上桌**：M1b 兵种数据层任务（M1a 全部完成后）；届时以 docs/08 当日口径
  重生成 .tres，本节表格不作为生成依据。

## 4. KayKit 历史速查（完整版 = 分支 `docs/10-asset-pipeline.md`）

路线已废（2026-10-07 移除，见 docs/12 头注），此处只留"重新获取 CC0 素材"
时的事实速查：

- 三包：KayKit Medieval Hexagon 1.0（221 模型，CC0）/ KayKit Skeletons 1.0
  （4 角色+27 武器件，CC0）/ Kenney KayKit-Hexagons（10 GLB，MIT）。
- 来源均走 GitHub 镜像（`KayKit-Game-Assets` org、`KenneyNL/KayKit-Hexagons`）；
  itch.io 本机不可达（CDN 被墙）。下载用 codeload tar.gz + 断点续传。
- **Adventurers 角色包仓库已被官方删除（404）**：活人系兵种模型缺口，候补
  `taictdev/KayKit`（74GB 合集）、poly.pizza（搜 Kay Lousbert）。
- 分支 docs/10 §5 复现命令中的 Godot 路径（`E:\Godot` 4.6.2）已失效——
  现行 `C:\Users\zerat\godot_tmp\` 4.7.2（README 环境节）。
