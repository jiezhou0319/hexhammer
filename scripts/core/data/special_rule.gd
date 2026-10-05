## 特殊规则：以数据形式挂在 UnitProfile 上（Frenzy、Fear、Hatred……）。
## rule_id 在 SpecialRuleEffects 里查效果实现；params 传数值参数。
## 加新规则 = 加一个 .tres + 在效果注册表里实现，不改单位代码。
class_name SpecialRule
extends Resource

@export var rule_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var params: Dictionary = {}
