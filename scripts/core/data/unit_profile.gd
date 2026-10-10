## 兵种模板（"棋子即兵"：一枚棋子 = 一个独立单位，无带兵结构）
## 数值唯一权威：docs/08-troop-design.md v6.1（docs/07 v5 比值法）。
## 挂 PackedScene 模型引用 → 数据驱动 3D 表现，UI/引擎都不 hardcode 模型路径。
class_name UnitProfile
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
## 攻击（比值公式 基础伤害 = ATK²/(ATK+DEF)）
@export var atk: int = 0
## 防御
@export var def: int = 0
## 生命
@export var hp: int = 1
## 移动力（六边形格数）
@export var speed: int = 4
## 射程（1 = 纯近战）
@export var attack_range: int = 1
## 闪避率 0~1
@export_range(0.0, 1.0) var dodge: float = 0.0
## 招募成本（刀盾 = 100 基准）
@export var cost: int = 100
## 士气 Leadership（崩溃测试基准，细则待 docs/06）
@export var leadership: int = 8
## 桌面棋子底座颜色 / 势力色索引
@export var model: PackedScene
