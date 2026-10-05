## 单位九维属性（战锤式 M/WS/BS/S/T/W/I/A/Ld）+ 存档槽。
## 每个单位是一个 .tres，加兵种不改代码。
class_name UnitProfile
extends Resource

enum Role { TROOP, HERO }

@export var display_name: String = "Warrior"
@export var role: Role = Role.TROOP

# ---- 九维 ----
@export var movement: int = 4          # M：一格 1 点移动力
@export var weapon_skill: int = 3      # WS
@export var ballistic_skill: int = 3   # BS
@export var strength: int = 3          # S
@export var toughness: int = 3         # T
@export var wounds: int = 1            # W
@export var initiative: int = 3        # I（先攻）
@export var attacks: int = 1           # A
@export var leadership: int = 7        # Ld（士气测试）

# ---- 豁免 ----
@export var armor_save: int = 7        # 7 = 无甲；5 = 需 5+ 才保住
@export var ward_save: int = 0         # 0 = 无；神器守护不可被破甲

# ---- 装备与规则 ----
@export var melee_weapon: WeaponProfile
@export var ranged_weapon: WeaponProfile
@export var special_rules: Array[SpecialRule] = []

@export var points: int = 0            # 点值（以后做军队表用）
