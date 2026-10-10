## make_trial_textures.gd — 生成贴图试验的入库占位纹理（F-2 修复，2026-10-10）
## 用法：
##   "C:/Users/zerat/godot_tmp/Godot_v4.7.2-stable_win64_console.exe" --headless \
##     --path . --script res://tools/make_trial_textures.gd
## 背景：terrain_materials_textured_trial.tres 原引用 art_tests/*.png（.gitignore 排除
##   ——"美术图层/贴图本地试验不入库"），干净克隆上门禁 2 用例必挂（Fable 审查 F-2）。
## 本工具生成两张**入库**占位纹理（resources/terrain/trial/），确定性公式、无随机
## ——重跑逐字节一致；art_tests 本地大图仍走原 .gitignore 规则（换真贴图即所见
## 的流程不变：本地把 .tres 的 ext_resource 指回 art_tests 即可，不入库）。
## 纹理设计（为目检服务，非美术资产）：
##   - grass：2×2 田字格两档绿 + 32px 栅格线——验证顶面世界平面映射的平铺连续性；
##   - offset：错位砖纹（行间半砖偏移）——验证 UV 方向/朝向（u 轴镜像会立刻可见）。
extends SceneTree

const OUT_DIR := "res://resources/terrain/trial"
const GRASS_PATH := OUT_DIR + "/grass_tile2x2_placeholder.png"
const OFFSET_PATH := OUT_DIR + "/offset_test_placeholder.png"
const SIZE := 64

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_grass_image(), GRASS_PATH)
	_save(_offset_image(), OFFSET_PATH)
	print("已生成：", GRASS_PATH, " / ", OFFSET_PATH)
	quit(0)

## 2×2 田字绿 + 栅格线：块内再叠 8px 微差方格（仍确定性公式），
## 让"整图无缝平铺"与"每格重复"目检都可判。
func _grass_image() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var block := Vector2i(x / 32, y / 32)
			var base := Color(0.30, 0.52, 0.24) if (block.x + block.y) % 2 == 0 else Color(0.38, 0.60, 0.28)
			if x % 32 == 0 or y % 32 == 0:
				base = Color(0.16, 0.34, 0.14)  # 栅格线（平铺对齐参照）
			elif (x % 8 == 0) != (y % 8 == 0):
				base = base.darkened(0.08)  # 块内微差方格（重复感参照）
			img.set_pixel(x, y, base)
	return img

## 错位砖纹：16px 高砖行、32px 宽砖、奇数行水平偏移半砖——灰棕两色 + 砖缝。
## u 轴若镜像/翻转，错位方向与砖缝走向立变（UV 朝向目检锚）。
func _offset_image() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var row := y / 16
			var off := 16 if row % 2 == 1 else 0
			var brick_x := (x + off) % 32
			var col: int = ((x + off) / 32 + row) % 2
			var base := Color(0.52, 0.46, 0.40) if col == 0 else Color(0.46, 0.40, 0.34)
			if y % 16 == 0 or brick_x == 0:
				base = Color(0.30, 0.27, 0.24)  # 砖缝
			img.set_pixel(x, y, base)
	return img

func _save(img: Image, res_path: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(res_path))
	if err != OK:
		print("!!! 写入失败 ", res_path, " err=", err)
		quit(1)
