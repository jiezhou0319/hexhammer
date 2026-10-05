## 武器数据。近战武器增强使用者属性；远程武器由 ranged_weapon 槽单独持有。
class_name WeaponProfile
extends Resource

@export var display_name: String = "Hand weapon"

## > 0 表示可射击的最大格数；0 = 纯近战武器
@export var range_hex: int = 0

## > 0 时射击强度固定用这个值（长弓 S3、弩 S4），否则用单位 S
@export var strength_override: int = 0

## 近战强度加值（巨斧 +1 之类），叠加在单位 S 或 override 上
@export var strength_bonus: int = 0

## 破甲：目标护甲需要值每点 +1（变差）
@export var armor_piercing: int = 0

## 攻击数加值（额外手枪/双持一类）
@export var attacks_bonus: int = 0

## 移动后本回合不可射击（弩、火枪）；冲锋/逃跑同样算移动过
@export var move_or_fire: bool = false
