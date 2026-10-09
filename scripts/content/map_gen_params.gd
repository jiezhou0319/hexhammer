## map_gen_params.gd — 随机地图生成参数（M1a-T9；docs/04-tasks-m1.md M1a-T9 +
##   docs/02-architecture.md §4「scripts/content/ ← 战役/名单/地图等上层内容系统」+
##   M1a 实现调研「相机、高亮和随机地图」）
## 职责：MapGenerator 的纯参数载体——「参数化尺寸/类型/高程分布」的落字：
##   - 尺寸：width/height（列×行，odd-r 矩形口径与 MapData 一致）；
##   - 类型：noise_type（高度场噪声类型；FastNoiseLite 枚举值）——不同噪声类型
##     直接改变地貌形态（simplex 连绵 / cellular 块状胞腔 / value 阶梯感…）；
##   - 高程分布：elevation_levels（陆地高程档数）+ sea_level（归一化高度海面阈值，
##     控制水体占比）+ frequency（噪声频率，越低越平缓连绵）。
## 复现口径（04 M1a-T9 细化）：同 seed + 同参数 → 同图，**限定在固定生成器版本
##   （MapGenerator.GENERATOR_VERSION）与同一引擎构建下**——FastNoiseLite 输出
##   随引擎版本可能变化，不承诺跨引擎版本永不漂移（meta 中存引擎版本号备查）。
## 纯数据类：RefCounted、零场景节点（ADR-2；删 scripts/ui/** 不影响本文件与 tests/）。
class_name MapGenParams
extends RefCounted

## FastNoiseLite 噪声类型名 → 枚举值（CLI/检查器友好；MapGenerator 只认枚举值）
const NOISE_TYPE_NAMES := {
	"simplex": FastNoiseLite.TYPE_SIMPLEX,
	"simplex_smooth": FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
	"cellular": FastNoiseLite.TYPE_CELLULAR,
	"perlin": FastNoiseLite.TYPE_PERLIN,
	"value_cubic": FastNoiseLite.TYPE_VALUE_CUBIC,
	"value": FastNoiseLite.TYPE_VALUE,
}

const MIN_SIZE := 1
const MAX_SIZE := 4096
const MIN_ELEVATION_LEVELS := 1
const MAX_ELEVATION_LEVELS := 64
const MIN_OCTAVES := 1
const MAX_OCTAVES := 10
const MIN_FREQUENCY := 0.0001
const MAX_FREQUENCY := 10.0

## 浮点参数字段（from_dict 类型感知赋值用；其余均为整数字段）
const FLOAT_FIELDS := ["frequency", "sea_level", "moisture_frequency"]

## 默认 seed=7：默认参数下连通性检查通过的单分量图（默认值即「能玩」，
## 扫描实证见 tests/test_map_source.gd 的 default 主题用例；换默认须重扫）
var seed := 7
var width := 60                      # 列数（MapData 宽）
var height := 40                     # 行数（MapData 高）
var noise_type := FastNoiseLite.TYPE_SIMPLEX  # 高度场噪声类型（「类型」参数）
var frequency := 0.05                # 高度场频率（世界单位；低频 → 平缓连绵地貌）
var fractal_octaves := 3             # 高度场 FBM 倍频数（越大细节越多、越碎）
var sea_level := 0.25                # 归一化高度海面阈值：n < sea_level → 水（值域 [0,1)）
var elevation_levels := 4            # 陆地高程档数（陆地层 = 1..levels，水体恒 0）
var moisture_frequency := 0.12       # 湿度场频率（植被动静脉，独立第二噪声通道）


## 参数校验：合法返回 ""，非法返回原因串（调用方显式处理，无隐式兜底）。
## 校验的是「生成器可工作」的硬边界，不是内容口味（内容口味由默认值承担）。
func validate() -> String:
	if width < MIN_SIZE or width > MAX_SIZE:
		return "width ∈ [%d,%d] 越界：%d" % [MIN_SIZE, MAX_SIZE, width]
	if height < MIN_SIZE or height > MAX_SIZE:
		return "height ∈ [%d,%d] 越界：%d" % [MIN_SIZE, MAX_SIZE, height]
	if not NOISE_TYPE_NAMES.values().has(noise_type):
		return "noise_type 非法枚举值：%d" % noise_type
	if frequency < MIN_FREQUENCY or frequency > MAX_FREQUENCY:
		return "frequency ∈ (%s,%s] 越界：%s" % [str(MIN_FREQUENCY), str(MAX_FREQUENCY), str(frequency)]
	if fractal_octaves < MIN_OCTAVES or fractal_octaves > MAX_OCTAVES:
		return "fractal_octaves ∈ [%d,%d] 越界：%d" % [MIN_OCTAVES, MAX_OCTAVES, fractal_octaves]
	if sea_level < 0.0 or sea_level >= 1.0:
		return "sea_level ∈ [0,1) 越界：%s" % str(sea_level)
	if elevation_levels < MIN_ELEVATION_LEVELS or elevation_levels > MAX_ELEVATION_LEVELS:
		return "elevation_levels ∈ [%d,%d] 越界：%d" % [MIN_ELEVATION_LEVELS, MAX_ELEVATION_LEVELS, elevation_levels]
	if moisture_frequency < MIN_FREQUENCY or moisture_frequency > MAX_FREQUENCY:
		return "moisture_frequency ∈ (%s,%s] 越界：%s" % [str(MIN_FREQUENCY), str(MAX_FREQUENCY), str(moisture_frequency)]
	return ""


## 元数据载体：全部参数落 dict（生成 meta 与 CLI 落盘共用；键序固定 → 文件可 diff）。
func to_dict() -> Dictionary:
	return {
		"seed": seed,
		"width": width,
		"height": height,
		"noise_type": noise_type,
		"frequency": frequency,
		"fractal_octaves": fractal_octaves,
		"sea_level": sea_level,
		"elevation_levels": elevation_levels,
		"moisture_frequency": moisture_frequency,
	}


## to_dict 往返（CLI/JSON 参数文件 → 参数对象）；缺键/类型不符/值非法 → null。
static func from_dict(data: Dictionary) -> MapGenParams:
	var required: Array = to_dict_static().keys()
	if not data.has_all(required):
		return null
	var p := MapGenParams.new()
	for k in required:
		var v: Variant = data[k]
		if v is bool or not (v is int or v is float) or (v is float and not is_finite(v)):
			return null
		if FLOAT_FIELDS.has(k):
			p.set(k, float(v))
		elif int(v) != v:
			return null  # 整数字段不得带小数（静默截断 = 改值）
		else:
			p.set(k, int(v))
	return p if p.validate() == "" else null


static func to_dict_static() -> Dictionary:
	return MapGenParams.new().to_dict()
