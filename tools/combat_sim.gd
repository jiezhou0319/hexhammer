## 战斗数值校准模拟器 v6.1（法师定值 ATK，docs/08 v6.1 配套）
## 用法:
##   "E:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://tools/combat_sim.gd
## v6.1 变更（2026-10-06）：法师取消 3d6×8 掷骰 ATK，改定值 84（原期望值），
##   并入统一伤害公式（docs/08 v6.1 裁决）；其余与 v6 一致。
## v6 变更（公式结构与既有常量零改动，只恢复 8 兵种数值带 + 新机制挂靠既有修正层）:
##   - 公式/常量 = v5 定稿原样（比值基础伤害 ATK²/(ATK+DEF) + 纯乘法修正链，无保底）
##   - 8 兵种数值带按 docs/08 重锚；刀盾 120/50/320 定稿不动
##   - 新机制全部映射到公式既有槽位（公式本体未动）:
##       克制层   : 长枪×1.75（启用触发，常量本就存在）；器械攻城×3（对设施占位条目）
##       增减伤层 : 贴脸×0.5（远程被近战钉住时自身出手）；盾墙（刀盾邻伴减远程伤）；
##                  校射（弓箭对同目标第 2 轮起+20%）；帕提亚（骑弓移动后射击+20%，以常数近似验证）
##       先手层   : 迎击（长枪被骑类攻击时反转先手；B 变体同时抵消冲锋加成——待用户裁决）
##       单位属性 : 法师定值 ATK 84（v6.1 起不再掷骰）；秘法穿甲（无视目标 DEF）
##   - 新增单方面远程压制测试 _volley（射击场口径：目标不还手）
## 数值三同步纪律: docs/07 + 本文件 + damage_calc.html 默认值
extends SceneTree

# ---------------- 兵种数值带 v6（docs/08-troop-design.md） ----------------
# atk 攻 def 防 hp 血 spd 速度(格/回合) rng 射程(1=近战) dodge 闪避(小数)
# 机制旗标: spear 反骑克制 / intercept 迎击 / mount 骑类 / melee_weak 被贴脸还手减半 /
#           pierce 无视防御 / sustained 校射 / siege_mult 攻城倍率
const TROOPS := {
	"刀盾": {"atk": 120.0, "def": 50.0, "hp": 320.0, "spd": 4, "rng": 1, "dodge": 0.0},
	"长枪": {"atk": 105.0, "def": 70.0, "hp": 300.0, "spd": 4, "rng": 1, "dodge": 0.0,
		"spear": true, "intercept": true},
	"骑枪": {"atk": 175.0, "def": 55.0, "hp": 200.0, "spd": 8, "rng": 1, "dodge": 0.10,
		"mount": true, "charge": true},
	"骑弓": {"atk": 95.0, "def": 45.0, "hp": 170.0, "spd": 8, "rng": 3, "dodge": 0.15,
		"mount": true, "melee_weak": true},
	"弓箭": {"atk": 130.0, "def": 45.0, "hp": 160.0, "spd": 4, "rng": 4, "dodge": 0.0,
		"melee_weak": true, "sustained": 0.20},
	"法师": {"atk": 84.0, "def": 45.0, "hp": 120.0, "spd": 4, "rng": 3, "dodge": 0.0,
		"melee_weak": true, "pierce": true},
	"器械": {"atk": 85.0, "def": 130.0, "hp": 300.0, "spd": 2, "rng": 5, "dodge": 0.0,
		"melee_weak": true, "siege_mult": 3.0},
	"医疗": {"atk": 0.0, "def": 55.0, "hp": 150.0, "spd": 4, "rng": 2, "dodge": 0.0,
		"heal": 45.0},
	# 设施占位条目（docs/06 待细化 #4 未定，仅给攻城机制一个验证靶子，非兵种）
	"城防(占位)": {"atk": 0.0, "def": 100.0, "hp": 400.0, "spd": 0, "rng": 0, "dodge": 0.0,
		"facility": true},
}

# ---------------- 全局参数（v5 定稿，不动） ----------------
const BASE_HIT := 0.90          # 基础命中率（带宽钳制 5%~95%）
const CRIT_RATE := 0.08         # 基础暴击率（各单位可独立，此处为默认值）
const CRIT_MULT := 1.5          # 暴击倍率
const FLOAT_RANGE := 0.15       # 随机浮动 ±15%

# ---------------- 修正层（v5 定稿常量，不动） ----------------
const CHARGE_MULT := 2.0        # 冲锋首轮（对非防守目标）
const FLANK_BONUS := 1.25       # 围攻：第 2 接战方向起
const DEFEND_REDUCTION := 0.40  # 防守姿态减伤 + 免疫冲锋加成
const SPEAR_VS_CAV := 1.75      # 克制层（长枪反骑），v6 起启用触发

# ---------------- v6 新机制常量（docs/08 设计稿，可调） ----------------
const MELEE_WEAK := 0.50        # 远程被贴脸还手 ×0.5（特性常量，docs/06 拍板值）
const SIEGE_MULT := 3.0         # 器械对设施伤害倍率（占位，待 docs/06 #4）
const INTERCEPT_MODE := "B"     # 迎击变体：A=仅先手反转；B=先手反转+抵消冲锋（待裁决）
const PARTHIAN_BONUS := 0.20    # 帕提亚回射：移动≥2 格后射击 +20%（近似常数）
const SUSTAINED_AIM := 0.20     # 校射：对同一目标第 2 轮起 +20%
const SHIELD_WALL := 0.15       # 盾墙：每邻一个友军刀盾减远程伤 15%（最多 2 邻 30%）

var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 20261005
	print("=== v6.1 校准：8 兵种（刀盾 120/50/320 锚点不动，法师定值 ATK，2000 次/组，迎击变体 %s） ===\n" % INTERCEPT_MODE)

	print("--- A. 硬目标校准 ---")
	print("%-30s %6s %6s %8s %7s %8s" % ["对局", "A胜率", "均轮", "存活HP%", "双亡%", "实际挨刀"])
	_pair("刀盾", "刀盾")                                        # ① 刀盾互砍 ~5 刀
	_pair("长枪", "骑枪")                                        # ②a 长枪 vs 骑枪（无冲锋）
	_pair("骑枪", "长枪", {"a_charge": true, "intercept": "B"})   # ②b 骑枪冲锋撞长枪（迎击B）
	_pair("骑枪", "长枪", {"a_charge": true, "intercept": "A"})  # ②c 同上但迎击仅先手（对照）
	_pair("骑枪", "长枪", {"a_charge": true, "intercept": "off"}) # ②d 无迎击（对照）
	_pair("骑枪", "弓箭", {"a_charge": true})                    # ③a 骑枪冲弓箭 ≤2 轮
	_pair("弓箭", "刀盾")                                        # ③b 弓箭被贴脸胜率 <15%
	_pair("骑弓", "刀盾")                                        # ③c 骑弓被贴脸胜率 <15%
	_pair("骑弓", "骑枪")                                        # ③d 轻骑被枪骑贴脸 <15%
	_pair("骑枪", "刀盾", {"a_charge": true, "b_defend": true})  # ④ 守姿态免疫冲锋反制

	print("\n--- B. 机制验证（射击场=目标不还手；对拼=互殴） ---")
	print("%-40s %10s %10s" % ["机制/场景", "致杀轮数", "每轮均伤"])
	_volley("弓箭", "刀盾")                                          # 基线远程压制
	_volley("弓箭", "刀盾", {"b_guard": SHIELD_WALL})                # 盾墙×1 邻
	_volley("弓箭", "刀盾", {"b_guard": 2.0 * SHIELD_WALL})          # 盾墙×2 邻
	_volley("法师", "刀盾", {"b_guard": 2.0 * SHIELD_WALL})          # 盾墙不挡魔法（pierce 跳过）
	_volley("弓箭", "刀盾", {"strip_sustained": true})               # 校射关闭（对照）
	_volley("骑弓", "弓箭")                                          # 帕提亚关闭（对照）
	_volley("骑弓", "弓箭", {"a_extra": 1.0 + PARTHIAN_BONUS})       # 帕提亚 +20%
	_volley("法师", "器械")                                          # 穿甲 vs 高防
	_volley("弓箭", "器械")                                          # 高防下普通远程（对照）
	_volley("法师", "刀盾")                                          # 穿甲 vs 中防
	_volley("器械", "城防(占位)")                                    # 攻城 ×3
	_volley("弓箭", "城防(占位)")                                    # 攻城对照

	print("\n--- C. 兵种对拼矩阵（无姿态无冲锋，迎击 B 生效；行=攻方；医疗无输出不列攻方） ---")
	print("%-18s %6s %6s %8s %7s" % ["对局", "A胜率", "均轮", "存活HP%", "双亡%"])
	var order := ["刀盾", "长枪", "骑枪", "骑弓", "弓箭", "法师", "器械", "医疗"]
	for an in order:
		for bn in order:
			if an == "医疗":
				continue
			_pair(an, bn, {"matrix": true})
	quit(0)

# ---------------- 攻击结算（v5 公式原样；v6 仅在既有修正层内挂机制） ----------------
func strike(a: Dictionary, b: Dictionary,
		defending := false, charging := false, flanking := false,
		extra := 1.0, melee := true) -> Dictionary:
	var dodge: float = b["dodge"]
	var hit_chance: float = clampf(BASE_HIT - dodge, 0.05, 0.95)
	if _rng.randf() > hit_chance:
		return {"hit": false, "dmg": 0.0}
	var atk_val: float = a["atk"]
	var def_val: float = b["def"]
	if a.get("pierce", false):                        # 秘法穿甲：无视目标防御
		def_val = 0.0
	# 基础伤害 = ATK²/(ATK+DEF)，恒正、无保底（v5 定稿）
	var dmg: float = atk_val * atk_val / (atk_val + def_val)
	dmg *= sqrt(a["hp"] / a["max_hp"])                # 血量修正 = √(攻击者当前/满血)
	# ---- 克制层 ----
	if a.get("spear", false) and b.get("mount", false):
		dmg *= SPEAR_VS_CAV                           # 长枪反骑（触发启用，常量未动）
	if b.get("facility", false):
		var siege: float = a.get("siege_mult", 0.0)
		if siege > 0.0:
			dmg *= siege                              # 器械攻城
	# ---- 增减伤层 ----
	if defending:
		dmg *= 1.0 - DEFEND_REDUCTION                 # 防守姿态减伤（定稿）
	if melee and a.get("melee_weak", false):
		dmg *= MELEE_WEAK                             # 远程被贴脸还手 ×0.5（定稿常量）
	if a["rng"] > 1 and not a.get("pierce", false):
		var guard: float = b.get("guard_ranged", 0.0) # 盾墙：仅挡远程物理，魔法跳过
		if guard > 0.0:
			dmg *= 1.0 - guard
	dmg *= extra                                      # 校射/帕thian 等增减伤（测试注入）
	# ---- 暴击 / 冲锋 / 围攻 / 浮动（v5 顺序原样） ----
	if _rng.randf() < CRIT_RATE:
		dmg *= CRIT_MULT
	if charging and not defending:
		dmg *= CHARGE_MULT
	if flanking:
		dmg *= FLANK_BONUS
	dmg *= 1.0 + _rng.randf_range(-FLOAT_RANGE, FLOAT_RANGE)
	return {"hit": true, "dmg": dmg}

# ---------------- 对拼模拟（速度快者先手，先杀免还手；迎击可反转先手） ----------------
func _clone(name: String) -> Dictionary:
	var t: Dictionary = TROOPS[name].duplicate()
	t["name"] = name
	t["max_hp"] = t["hp"]
	return t

func _round_extra(u: Dictionary, round: int) -> float:
	var ex: float = u.get("extra_mult", 1.0)
	if round >= 2:
		ex *= 1.0 + u.get("sustained", 0.0)           # 校射：对同一目标第 2 轮起
	return ex

func _pair(a_name: String, b_name: String, opts := {}) -> void:
	var iterations: int = opts.get("iterations", 2000)
	var a_charge: bool = opts.get("a_charge", false)
	var b_defend: bool = opts.get("b_defend", false)
	var intercept_mode: String = opts.get("intercept", INTERCEPT_MODE)
	var matrix: bool = opts.get("matrix", false)
	var a_wins := 0
	var draws := 0
	var rounds_sum := 0
	var a_hp_pct_sum := 0.0
	var b_hits_sum := 0
	for i in iterations:
		var a := _clone(a_name)
		var b := _clone(b_name)
		if opts.has("a_extra"):
			a["extra_mult"] = opts["a_extra"]
		if opts.has("b_guard"):
			b["guard_ranged"] = opts["b_guard"]
		var round := 0
		var b_hits := 0
		while a["hp"] > 0.0 and b["hp"] > 0.0 and round < 60:
			round += 1
			var a_first: bool = a["spd"] > b["spd"]
			var b_first: bool = b["spd"] > a["spd"]
			# 迎击：长枪被骑类攻击时先手反转；B 变体另抵消该次冲锋加成
			if intercept_mode != "off":
				if b.get("intercept", false) and a.get("mount", false):
					b_first = true
					a_first = false
				if a.get("intercept", false) and b.get("mount", false):
					a_first = true
					b_first = false
			var b_intercepts_now: bool = intercept_mode == "B" \
					and b.get("intercept", false) and a.get("mount", false)
			var a_charging: bool = a_charge and round == 1 and not b_intercepts_now
			if a_first:
				var r1 := strike(a, b, b_defend, a_charging, false, _round_extra(a, round))
				if r1["hit"]:
					b_hits += 1
					b["hp"] -= r1["dmg"]
				if b["hp"] > 0.0:
					var r2 := strike(b, a, false, false, false, _round_extra(b, round))
					if r2["hit"]:
						a["hp"] -= r2["dmg"]
			elif b_first:
				var r1 := strike(b, a, false, false, false, _round_extra(b, round))
				if r1["hit"]:
					a["hp"] -= r1["dmg"]
				if a["hp"] > 0.0:
					var r2 := strike(a, b, b_defend, a_charging, false, _round_extra(a, round))
					if r2["hit"]:
						b_hits += 1
						b["hp"] -= r2["dmg"]
			else:
				var ra := strike(a, b, b_defend, a_charging, false, _round_extra(a, round))
				var rb := strike(b, a, false, false, false, _round_extra(b, round))
				if ra["hit"]:
					b_hits += 1
					b["hp"] -= ra["dmg"]
				if rb["hit"]:
					a["hp"] -= rb["dmg"]
		rounds_sum += round
		b_hits_sum += b_hits
		if a["hp"] > 0.0:
			a_wins += 1
			a_hp_pct_sum += a["hp"] / a["max_hp"]
		elif b["hp"] > 0.0:
			pass
		else:
			draws += 1
	var label := "%s%s vs %s%s%s" % [a_name,
		"[冲锋]" if a_charge else "",
		b_name,
		"[防守]" if b_defend else "",
		"[迎击%s]" % intercept_mode.to_upper() if intercept_mode != INTERCEPT_MODE else ""]
	if matrix:
		print("%-18s %5.1f%% %6.1f %8.1f %7.1f" % [
			label,
			100.0 * a_wins / iterations,
			float(rounds_sum) / iterations,
			100.0 * a_hp_pct_sum / iterations,
			100.0 * draws / iterations,
		])
	else:
		print("%-30s %5.1f%% %6.1f %8.1f %7.1f %8.1f" % [
			label,
			100.0 * a_wins / iterations,
			float(rounds_sum) / iterations,
			100.0 * a_hp_pct_sum / iterations,
			100.0 * draws / iterations,
			float(b_hits_sum) / iterations,
		])

# ---------------- 单方面远程压制（射击场：目标不还手、攻方每轮射击） ----------------
func _volley(atk_name: String, def_name: String, opts := {}) -> void:
	var iterations: int = opts.get("iterations", 2000)
	var b_defend: bool = opts.get("b_defend", false)
	var rounds_sum := 0
	var hits_sum := 0
	var dmg_sum := 0.0
	for i in iterations:
		var a := _clone(atk_name)
		var b := _clone(def_name)
		if opts.has("a_extra"):
			a["extra_mult"] = opts["a_extra"]
		if opts.has("b_guard"):
			b["guard_ranged"] = opts["b_guard"]
		if opts.get("strip_sustained", false):
			a.erase("sustained")
		var round := 0
		while b["hp"] > 0.0 and round < 40:
			round += 1
			var r := strike(a, b, b_defend, false, false, _round_extra(a, round), false)
			if r["hit"]:
				hits_sum += 1
				var d: float = r["dmg"]
				b["hp"] -= d
				dmg_sum += d
		rounds_sum += round
	var guard_tag: String = ""
	if opts.has("b_guard"):
		guard_tag = "[盾墙%.0f%%]" % [100.0 * float(opts["b_guard"])]
	var label := "%s%s%s → %s%s" % [atk_name,
		"[帕提亚]" if opts.has("a_extra") else "",
		"[无校射]" if opts.get("strip_sustained", false) else "",
		def_name, guard_tag]
	print("%-40s %10.1f %10.1f" % [
		label,
		float(rounds_sum) / iterations,
		(dmg_sum / iterations) / (float(rounds_sum) / iterations),
	])
