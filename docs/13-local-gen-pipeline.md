# 13 · 本地 ComfyUI 白模/贴图生产线（设计 v0.1 + 部署实录，待共创审）

> 2026-10-07 起草于 spike；2026-10-10 入库改号（原 12-local-gen-pipeline，
> 完整原稿存档于 `spike-1007-demo` 分支）。定位：
> [12-terrain-content-pipeline.md](12-terrain-content-pipeline.md) §6.1 三路供给中
> **本地生成**与 **T0 贴图生图**两条的落地工程方案。回答四个问题：
> 环境怎么搭（§1）、单件工作流怎么设计（§2~§4）、量产循环怎么跑（§5）、
> 出问题怎么回退（§6）。上承 docs/12 全部决策（白模原则/三道闸/验收卡/规格书），
> 本文不改任何已拍板项，只做工程化。
> **§9 部署实录：环境已落地、图生 3D 冒烟 PASS（2026-10-07）**；
> 本文待共创审，未拍板。

## 0. 结论先行

| 项 | 结论 |
| --- | --- |
| 生成底座 | **ComfyUI Desktop（Windows ROCm 官方版）**。2026 年起 ComfyUI v0.7+ 官方支持 AMD ROCm on Windows，RX 7000 系在支持列表内（本机 RX7700XT ✅）。备选：patientx/comfyui-rocm → ComfyUI-ZLUDA（见 §6）。**实际落地（§9 实录）：改用 patientx-cfz/comfyui-rocm（更适配无人值守），Desktop 路线未采用** |
| 白模引擎 | **Hunyuan3D 2.1 shape-only**（docs/12 §6.1 已拍板，本文验证仍正确）。几何阶段优化后 3~6GB 显存，12GB 卡稳定可跑；**贴图阶段（21GB+）本地不碰**——本来白模原则就弃 AI 贴图。优先用 ComfyUI **原生** Hunyuan3D 节点，kijai wrapper 作备选。**2.5 不换**（差距分析见 §1.2 注） |
| 贴图引擎 | SDXL（T0 无缝贴图 + 概念图）。可选 FLUX.1-schnell fp8 备选（质量更高、更慢更吃显存，待拍板 §7-2） |
| 空间账 | ComfyUI + 全套权重 ≈ 30~45GB → **装 E 盘 `E:\ComfyUI\`**（2026-10-07 已清理，E 剩 241G；repo 内只进小文件，单件白模 <5MB） |
| 显存账 | 三个 GPU 阶段**互斥串行**：概念图 SDXL ~8GB / 白模 3~6GB / T0 贴图 ~8GB，无一超 12GB；CPU 阶段（Blender 后处理/验收）不占显存，随时可跑 |
| 产物对齐 | 每件出 **白模 glb（含 UV + AO 顶点色）**；贴图只产 T0 无缝图（+派生法线/粗糙度）。UV 一律保留——docs/12 §8 决策点 3（PropMaterial 纯色 vs 轻噪细节贴图）未定，留 UV 是零成本保险 |

## 1. 环境搭建（一次性，6 步）

### 1.0 目录规划（先定盘）

```
E:\ComfyUI\            ← ComfyUI 本体 + custom nodes（§9 实录：comfyui-rocm）
E:\ComfyUI\models\     ← 权重（下载清单 §1.2；安装器默认就在这）
E:\Code\active\hexhammer\tools\ai_gen\   ← 驱动脚本/工作流 JSON/验收脚本（进 git）
E:\Code\active\hexhammer\assets\props\   ← 最终入库产物（进 git，glb 很小）
E:\Code\active\hexhammer\resources\props_manifest.json  ← 资产清单表（docs/12 §6.1）
E:\Code\active\hexhammer\tools\ai_gen\out\  ← 中间产物（概念图/raw mesh，不进 git）
```

原则：**repo 内只进小文件**（workflow JSON、脚本、入库 glb、manifest）；权重与
中间产物一律在盘外。`.gitignore` 补 `tools/ai_gen/out/`。

### 1.1 装 ComfyUI Desktop（ROCm 版）

1. 官网下 Windows 安装器，安装时选 **ROCm** 后端（不要选 CPU/CUDA），安装位置
   指到 `E:\ComfyUI\`（安装器会询问；models 随本体落 `E:\ComfyUI\models\`）。
2. 首启后在设置里确认设备识别为 `cuda:0 gfx1101`（ROCm 把 AMD 卡映射成 cuda 设备名，PyTorch 层透明）。
3. 冒烟：自带默认 SD1.5 工作流跑一张图，~30s 内出图即通。
   不通 → §6 回退链（comfyui-rocm 便携包 → ZLUDA legacy）。

### 1.2 权重清单（下到 E:\ComfyUI\models\，用 ABDM 多线程下；原稿误书 D 盘，2026-10-10 入库更正——§9 实录权重已就位）

| 权重 | 用途 | 体积 | 位置（下载页为准） |
| --- | --- | --- | --- |
| SDXL base 1.0 | WF-A 概念图 + WF-C T0 贴图 | ~7GB | hf `stabilityai/stable-diffusion-xl-base-1.0`（safetensors 单文件版） |
| Hunyuan3D 2.1 shape 模型 | WF-B 白模（shape-only） | ~8~12GB | hf `tencent/Hunyuan3D-2.1`（只下 geometry/dit 部分，**跳过 texture 模型**） |
| Blender 4.5 LTS 便携 zip | S1 后处理 | ~350MB | blender.org（zip 解压即用，不走安装器） |
| （可选）FLUX.1-schnell fp8 | T0 贴图备选底模 | ~11GB | hf `black-forest-labs/FLUX.1-schnell`（Apache-2.0 可商用） |

注：**白模引擎按"本地跑起来谁好谁差"横评定案：Hunyuan3D 2.1（2026-10-07 复核）**。
候选与结论（shape-only、本机 12GB 口径）：

| 候选 | 本地可跑性 | 几何（白模）质量 | 12GB 适配 | 结论 |
| --- | --- | --- | --- | --- |
| Hunyuan3D 2.1 | ✅ 权重可下载 | **本地几何之王**：官方 bench 超全部基线，社区实测共识几何略胜 TRELLIS；两段式（形状/贴图分离）网格更干净 | shape 优化后最低 ~3GB，宽裕 | **选用** |
| Hunyuan3D 2.5 | ❌ **无权重文件可下载**（官方仅网页托管，issue #316/#111 社区追问无果）——本地赛道不存在此选项 | 纸面 +15% 几何 / +20% 贴图（无从本地验证） | 24GB+ | 不存在 |
| TRELLIS(.2) | ✅ | 几何偏粗（voxel/SLAT 表示），强项在贴图/PBR 保真——恰是本管线弃用段 | 默认 12~16GB，偏紧 | 备选 A/B |
| TripoSR | ✅ | 明显低一档，快而糙 | ~6GB | 草稿预览级 |

2.5 补充：即便日后权重放出，其优势落点（贴图 +20%/4K PBR、高频细节、原始
拓扑）恰是白模管线**弃用的三样**（白模原则弃贴图；S1 减面抹掉高频细节；
游戏散件不依赖 AI 原生拓扑）。能穿过减面留在最终资产上的只有**大形剪影
准确度与薄结构成活率**（几何精度 +15% 的一部分——栅栏/残旗/枝干这类薄件
2.1 偶发粘连），该残余差距用三路供给里的在线质量件通道兜底难件即可
（docs/12 §6.1 配比本就如此）。若首批实测 2.1 薄件成活率过低，调的是
供给配比（多花在线额度），不是本地引擎。

### 1.3 Custom nodes（ComfyUI Manager 里装）

| 节点包 | 用途 |
| --- | --- |
| ComfyUI-Seamless-Texture（或等效 circular padding 节点） | WF-C 无缝平铺 |
| ComfyUI-Hunyuan3DWrapper（kijai） | 仅当原生节点在 ROCm 上有问题时启用（§6） |
| Image Saver 类节点 | 统一输出命名（id/seed/prompt 嵌文件名） |

### 1.4 Python 侧（repo 内 venv）

`tools/ai_gen/requirements.txt`：`trimesh`、`numpy`、`requests`（提交 ComfyUI
HTTP API 用）。`py -3.13 -m venv .venv` 建，验收脚本 S2 与队列驱动共用。

### 1.5 Blender 便携版

解压到 `E:\Tools\blender-4.5\`，`blender.exe --background --python <脚本>` 方式
headless 调用，无需进 PATH。

### 1.6 冒烟验收（每路一件，全过才算环境就绪）

1. SDXL 文生图 1 张（1024²）→ ~1min
2. Hunyuan3D 2.1：喂一张现成石头照片 → 出 glb → ~2~5min
3. Blender headless：对该 glb 跑 S1 骨架 → 输出 glb 不报错
4. S2 验收脚本：对输出 glb 出 PASS/FAIL 表

## 2. 一个物件的旅程（总图）

细化 docs/12 §6 六步，标注执行单元与产物：

```
需求行（queue.json，源自 docs/12 §7 清单）
   │
   ▼  [GPU·SDXL ~8GB]  WF-A 概念图 ×4（batch，prompt 骨架固定只换物件词）
人审 4 选 1 ←———— 唯一人工点（美术总监；文件管理器缩略图即可挑）
   │ 挑中 <id>/<seed>.png
   ▼  [GPU·Hy3D 3~6GB] WF-B 白模：image→shape（fp8/lowvram），出 ~10万面 raw glb
   ▼  [CPU]            S1 Blender 后处理六连（§4.1）→ <name>_v#.glb（含 UV+AO 顶点色）
   ▼  [CPU]            S2 验收卡五项 → FAIL 则带参数回炉（改 seed / 调 decimate）
   ▼  [CPU]            入库 assets/props/<群系>/<类>/ + manifest 登记（prompt/seed 可追溯）
   └→ 挂散布表（数据替换，不动代码）
```

**时序纪律（本机硬件红线）**：GPU 阶段运行时**不跑 Ollama/其他 GPU 大模型**
（GPU 满载时 CPU 并行大模型会断电，反之亦然）；批量生产时段安排成"GPU 只属于
ComfyUI"的整块时间。S1/S2 是纯 CPU，可与 WF-A/B 排队并行流水。

## 3. 三个 ComfyUI 工作流（WF-A/B/C）

调参在 ComfyUI UI 里做首件，定稿后**导出 JSON 存 repo**
（`tools/ai_gen/workflows/wfA_concept.json` 等），批量走 API 模式（§5.2）复用
同一 JSON——**首件调参、后续全自动**。

### WF-A 概念图（剪影定形，不管配色——配色是 PropMaterial 的事）

- 底模 SDXL，1024²，steps 30，CFG 6~7。
- 正面词 = docs/12 §6.1 骨架原文，只换 `{物件}` 槽：
  `low-poly stylized {物件}, single game asset, flat base, centered, front view,
  muted desaturated colors, grimdark dark fantasy, medieval warhammer inspired,
  no background, no texture detail`
- 负面词固定一组（`photo, realistic, high detail texture, clutter, multiple objects,
  text, watermark, cropped, perspective`）。
- seed 策略：每物件一个基 seed（= hash(id)），batch 4 张 = 基 seed+0..3 → **全程
  可复现**，manifest 里记 seed 即可重造。
- 输出：`out/concepts/<id>/<seed>.png`（Image Saver 嵌 prompt 元数据）。
- 变体需求（T2 每型 3~5 变体，docs/12 §3）：同一物件多组基 seed 即多套剪影。

### WF-B 白模（Hunyuan3D 2.1，shape-only）

- 优先 **ComfyUI 原生 Hunyuan3D 2.1 节点**（官方文档 tutorials/3d/hunyuan3d-2）：
  LoadImage → 概念图 → Hunyuan3D image→3D（shape 模型，fp8）→ Export GLB。
- 参数锚点：Octree 分辨率中档（白模减面后差距不可见，不用拉满省显存）；多视图
  阶段（若有）关闭。
- 输出：`out/raw_mesh/<id>.glb`（高面数，未减面——减面在 S1 做，保留最高质量源）。
- 原生节点在 ROCm 报错时 → kijai wrapper（功能等价，装法见其 README）→ 仍不行
  → 该件转在线三路（Meshy），环境问题另修不阻塞生产。

### WF-C T0 无缝贴图（docs/12 §7：18 张，三类群系）

- SDXL + Seamless 节点，1024²（首发 1024 够用，splat + 世界坐标 UV 下 2K 无必要）。
- 正面词 = 骨架：`seamless tileable texture, {草甸/泥地/岩面}, desaturated,
  painterly, top-down, no vignette`（docs/12 §6.1 原文）+ 群系调色词（低饱和
  铁灰/暗绿/泥褐，对齐 §1 美术五条）。
- **平铺校验**：工作流尾接 3×3 tile 拼接预览节点，人眼看接缝；入库前 S3 脚本做
  像素级接缝检测（左右/上下边缘 32px 差分，超阈值 FAIL）。
- **PBR 通道派生（S3 脚本，纯 CPU）**：albedo → 高度图（亮度+高通分离）→ 法线
  （Sobel 3×3）→ 粗糙度（亮度反相 + 材质预设偏移）。**法线+粗糙度首发即做
  （2026-10-07 已拍板）**：陡坡露岩/积雪的 splat shader 靠法线卖体积，裸 albedo
  太平——比"先只出 albedo 后补"省一轮返工。
- 输出：`assets/props/textures/<biome>/<名>_albedo.png + _normal.png + _rough.png`。

### （可选 WF-D）灰度噪细节贴图

仅当 docs/12 §8 决策点 3 拍板"PropMaterial 带轻噪细节"时启用；程序化噪声即可，
不必生图。**本文不展开。**

## 4. 脚本三件套（tools/ai_gen/，随环境冒烟一起实现）

### 4.1 S1 后处理（Blender headless）

```
E:\Tools\blender-4.5\blender.exe --background --python s1_post.py --
    <in.glb> <out.glb> --class T1|T2|T3
```

六连（顺序固定）：①导入 + 网格修复（non-manifold 补洞，Hunyuan 偶发闭底破面）
②减面 decimate 至类预算（T1<500 / T2<3000 / T3<15000，docs/12 §4 验收卡④）
③Smart UV Project（island margin 0.05~0.1，angle limit 默认）④原点贴地
（-Z 最小值归零）+ 朝向 +Z ⑤尺寸归一化（按 docs/12 §4 规格书单位：树 1.2~2.0
格、巨石 0.5~1.0 格…，1 格 = 外接圆半径 1.0 世界单位——现行 `HexMath` size 口径；原稿 1/√3 系 spike 期 KayKit 对齐约定，已废，2026-10-10 入库更正）⑥AO 烘焙进顶点色（PropMaterial
的 AO 输入，docs/12 §4 闸 2）→ 导出 glb（弃原贴图，只留 mesh+UV+顶点色）。

### 4.2 S2 验收卡（docs/12 §4 五项，trimesh）

读 glb 输出 PASS/FAIL 表 + 回写 manifest：①bbox 比例合规 ②原点贴地 ③+Z 朝向
④面数阈值 ⑤法线外向无破面（winding 一致性 + 体积正值）。FAIL 给出具体项与
建议动作（重挑概念图 / 调 decimate 强度 / 手修）。

### 4.3 驱动器 build_props.py（生产循环主控）

- 读 `queue.json`（字段：id/群系/类/物件名/prompt 槽词/变体数），逐行推进状态机
  `queued → concepted → picked → meshed → processed → passed → registered`，
  断点续跑（状态即进度）。
- ComfyUI API 模式：HTTP `POST /prompt`（workflow JSON + 参数覆盖）+ websocket
  收完成事件——批量不必开 UI。
- 人审点：`concepted` 状态暂停该件，等人工把挑中的 seed 写回 queue（或 CLI
  `build_props.py pick <id> <seed>`）。

## 5. 量产循环

### 5.1 首件全链（先于一切批量）

垂直切片定调用（docs/12 §8 下一步 1 的"首批 10 个 AI 模型"由此出）：**1 棵
橡树 v1** 从 queue 到验收 PASS 截图全链证据，味道不对不铺量（docs/12 原话）。

### 5.2 批量节奏

- 单件成本：概念图 4×~30s + 人审 ~1min + 白模 2~5min + S1/S2 ~30s
  → **~10 分钟/件**，一个晚上可出 T1/T2 白模 30~50 件。
- 首发 ~100 模型中本地承担：T1 全部（21）+ T2 大部分（~24）+ T3 定调后的部分
  变体 ≈ 50~60 件 → **2~3 个晚上**出全白模库；在线额度只花 T3/T4 + 定调件
  10~15 个（docs/12 §6.1 配比不变）。
- T0 贴图 18 张 + 派生通道：单晚搞定。

## 6. 风险与回退

| # | 风险 | 判定信号 | 回退动作 |
| --- | --- | --- | --- |
| R1 | ComfyUI Desktop ROCm 对 Hunyuan3D 原生节点不兼容（自定义算子/编译扩展） | §1.6 冒烟 2 失败 | ①换 kijai wrapper ②换 patientx/comfyui-rocm 便携包 ③换 ZLUDA legacy ④该件转在线，环境问题不阻塞生产 |
| R2 | E 盘空间再陷紧张（清理后剩 241G，全套占 ~45G） | <100GB 告警 | out/ 中间产物定期清（raw mesh 挑完即删）；FLUX 可选包最后下/不下 |
| R3 | GPU 断电红线 | —— | 纪律问题：批跑时段关 Ollama（§2 时序）；build_props.py 启动时探测 GPU 占用并警告 |
| R4 | SDXL 剪影风格漂移 | 首件对比参照清单 | 概念图只管剪影不管色（PropMaterial 统一色）；漂了换 seed/加 LoRA，不动骨架词 |
| R5 | Hunyuan 破面/闭底 | S2 ⑤ FAIL 率 >30% | S1 ①步换更强修复（blender 3D-print toolbox 修 manifold）；仍高则该类物件转程序化（docs/12 §6.1 三路本就并行） |
| R6 | ROCm 长跑稳定性（OOM/驱动重置） | 单晚 >2 次 | 队列粒度小（API 单件提交，崩了续跑）；显存余量调 8GB 档参数 |

## 7. 决策点（待共创拍板）

1. ~~底座：ComfyUI Desktop ROCm（建议，官方一键）vs comfyui-rocm 便携包（更可控）？~~ **已落定（§9 实录）：comfyui-rocm。**
2. T0 贴图底模：SDXL（稳、快）先行 vs 直接 FLUX schnell fp8（质量高、慢 ~3×）？建议 SDXL 先行、FLUX 做 A/B。
3. ~~T0 派生通道首发就带法线+粗糙度？~~ **已拍板（2026-10-07）：带**（§3 WF-C）。
4. workflow JSON 进 git（tools/ai_gen/workflows/）以便追溯复现？（建议进）
5. Blender 锁 4.5 LTS？（建议锁，headless 脚本跨版本易碎）

## 8. 下一步（顺序执行；2026-10-10 入库时点核对进度）

1. ✅ §1 环境安装 + 冒烟（2026-10-07 完成，见 §9/§9.1——路线从 Desktop 改 comfyui-rocm）
2. ⬜ S1/S2 脚本实现 + queue.json 生成器（从 docs/12 §7 清单展开）
3. ⬜ 橡树 v1 首件全链 + 验收证据 → **定调拍板**（前置：M1a 内容物侧任务上桌，见 docs/12 §8）
4. ⬜ 味道对 → 批量循环跑起来（docs/12 §8 下一步 3）

## 9. 部署实录（2026-10-07 当晚，供复现）

**装机路线实况**（原计划 §1.1 的 ComfyUI Desktop 改为 comfyui-rocm，更适配无人值守）：

- 底座：`patientx-cfz/comfyui-rocm` git clone 到 `E:\ComfyUI\`（用 AMD 官方
  TheRock ROCm/PyTorch 包）。**不跑 install.bat**（三个坑，见下），手工分步装。
- **网络五坑（本机实测）**：
  ①GitHub 直连半通（握手成功、长传输断流）→ git 全局重写
  `GIT_CONFIG_GLOBAL` 临时文件指向 ghfast.top 前缀代理，clone/whl 全走它；
  ②HF 与 hf-mirror 直连超时 → **权重全部改走 ModelScope（魔搭）**：官方结构
  在 `AI-ModelScope/Hunyuan3D-2.1`，**Comfy 原生模板要的重打包单文件在
  `Comfy-Org/hunyuan3D_2.1_repackaged`（7.37GB，ABDM 国内 CDN 飞快）**；
  ③AMD stable 源（stable.repo.amd.com）短请求通、长传输卡死 → 改用
  **nightly 源 rocm.nightlies.amd.com/v2/gfx110X-dgpu/**（index 快且全）；
  ④AMD 源 pip 直连仍不稳 → 抓 index 页拿 wheel 直链，**ABDM 多线程拉**
  （6 件套 ~2.9GB 十分钟内完）；⑤清华 PyPI 镜像全程稳，pip 一律挂
  `PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple`。
- **install.bat 三坑**：①tar 解 zip 失败——Git Bash 启动时 PATH 里 GNU tar
  抢先（不认 zip），要么净化 PATH 要么手工 Expand-Archive；②GPU 检测在 bat
  环境失败（wmic 已从 Win11 24H2+ 移除 + PowerShell 法环境敏感），手动跑
  `detect_gpu.py` 正常输出 `gfx1101`；③pip 版本解析坑——不锁版本时 pip 会
  从清华拿到官方 CPU torch 2.14.1 而非本地 2.9.1+rocm，必须 `torch==2.9.1+rocm7.10.0a20251120` 精确锁定；`rocm` 元包是 sdist（清华同名片
  是 poetry 占位包必炸，AMD 官方 sdist 是 setuptools 可直装）。
- **torch 栈版本**：torch 2.9.1+rocm7.10.0a20251120 / torchvision 0.25.0a0 /
  torchaudio 2.9.0 / rocm-sdk-devel+core+libraries(gfx110x-dgpu) 同 build
  20251120，全在 `E:\ComfyUI\wheels_amd\` 留档。
- **本机最大坑（必设）**：APU 核显 + RX7700XT 双 GPU，HIP 默认把核显排
  device 0，kernel 发上去就段错误（hipHccModuleLaunchKernel 0xC0000005）。
  **启动必带 `HIP_VISIBLE_DEVICES=1`**（只暴露 7700XT）。加上后 randn+matmul
  冒烟通过：`torch.cuda.get_device_name(0) == 'AMD Radeon RX 7700 XT'`。
- 启动环境全套（对齐 comfyui-rocm.bat）：`HIP_VISIBLE_DEVICES=1` +
  `TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1` + MIOPEN/ROCBLAS 路径三件
  （指向 `python_env\Lib\site-packages\_rocm_sdk_devel\bin`）+ 启动参数
  `--disable-partner-nodes --cache-lru 20 --disable-smart-memory
  --disable-pinned-memory --enable-manager --disable-triton-backend
  --enable-dynamic-vram`。
- 权重已就位（`E:\ComfyUI\models\`，四件 ~20GB 已验证 safetensors 头）：
  `checkpoints/hunyuan3d-dit-v2.safetensors`（2.0 冒烟/备胎）、
  `checkpoints/hunyuan_3d_v2.1.safetensors`（原生 2.1 模板用）、
  `checkpoints/hunyuan3d-dit-v2-1_fp16.ckpt + vae/hunyuan3d-vae-v2-1_fp16.ckpt`
  （官方分离结构，kijai wrapper 备胎路线用）。
- **torchvision 配对坑**：TheRock nightly 同一天戳有两条线（torch 2.9.1 稳定线
  配 torchvision **0.24.0**；torch 2.10.0a0 开发线配 0.25.0a0）。跨线混装
  → `operator torchvision::nms does not exist`（WinError 127 ABI 断裂）。
  字符串排序会把 2.10 排在 2.9 之前漏选，抓包时要显式配对。
  **本机定装组合：torch 2.9.1+rocm7.10.0a20251120 / torchvision 0.24.0 /
  torchaudio 2.9.0**。

### 9.1 图生3D 冒烟结果（2026-10-07 深夜，✅ PASS）

- **流程**：官方 `3d_hunyuan3d_image_to_model` 模板（ImageOnlyCheckpointLoader
  →CLIPVisionEncode→EmptyLatentHunyuan3Dv2(3072)→KSampler(20步/cfg8/euler)
  →VAEDecodeHunyuan3D(num_chunks 8000/octree 256)→VoxelToMesh(surface net
  0.6)→SaveGLB），API 格式存 `E:\ComfyUI\smoke_api.json`。
- **输入**：Hunyuan3D 官方 demo 图（500² RGBA，`input/hydemo.png`）。
- **输出**：`output/smoke/hydemo_00001_.glb`，**6.2MB，glTF 2.0 合法**。
- **耗时**：提交到完成 **约 45 秒**（含首次权重加载；后续件更快）。
- **显存**：Dinov2 2.16GB + Hunyuan3Dv2 DiT 2.12GB + ShapeVAE 0.84GB 分批
  staging（--enable-dynamic-vram），峰值 <5GB / 12272MB，**远低于预估**——
  T2/T3 量产余量巨大，后续可试 octree 512 拉细节。
- server 启动模板（全套环境变量见 §9），端口 8188，API 提交+轮询
  `/history/{id}` 全自动，UI 仅供调参。

## 附：调研依据（2026-10-07）

- ComfyUI v0.7+ 官方 AMD ROCm on Windows 支持（RX 7000/9000 系）：blog.comfy.org
  "Official AMD ROCm Support Arrives on Windows for ComfyUI Desktop"；ROCm 7.1.1
  性能公告 rocm.blogs.amd.com。
- Hunyuan3D 2.x 显存分档（shape ~10GB → 优化 3~6GB；texture 21GB+；全链 29GB）：
  docs.comfy.org tutorials/3d/hunyuan3D-2、comfyui-wiki.com、
  Hunyuan3D-2-WinPortable（github）、Hunyuan3D-2GP（deepbeepmeep）。
- kijai/ComfyUI-Hunyuan3DWrapper（含 2.1 lowvram 讨论 issue #165）。
- patientx/ComfyUI-Zluda 及其继任 comfyui-rocm（RDNA1~4）。
- Hunyuan3D 2.5/3.x 无权重可下（官方仅托管：huggingface tencent/Hunyuan3D-2
  仅到 2.1；github Tencent-Hunyuan/Hunyuan3D-2 issue #316、Hunyuan3D-2.1
  issue #111）；本地横评（Hunyuan 2.1 vs TRELLIS.2 vs TripoSR，几何/显存）：
  triposr.org/blog/hunyuan3d-vs-trellis、vset3d.com WinPortable 基准、
  reddit r/comfyui 实测；2.5 对 2.1 纸面差（10B LATTICE、1024 分辨率、
  +15% 几何、+20% 贴图、4K PBR）：vset3d.com、meshy.ai/compare、scenario.com。
