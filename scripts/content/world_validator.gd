## world_validator.gd — 可玩校验器（T5 WORLD-04；执行方案
##   docs/M1a-terrain-T2-T5-execution-plan.md §6 WORLD-04 + 数据合同草案 §11）
## 职责：**结构化错误报告**的单一入口——错误 {code, cell_ids, link_ids,
##   constraint_id, explanation} 指向具体对象（草案 §11 错误码清单落码：
##   NO_VALID_SPAWN / RESOURCE_UNREACHABLE / RIVER_CYCLE / NO_RIVER_OUTLET /
##   BRIDGE_ENDPOINT_INVALID / ROAD_NETWORK_DISCONNECTED /
##   LOCKED_CONSTRAINT_CONFLICT；清单「先包括」= 可扩格——本文件另落
##   POI_FOOTPRINT_CONFLICT 与 WORLD_DATA_INVALID 两个结构性扩格码，全部在
##   类头 ERROR_CODES 登记）。Azgaar「无阶段诊断产物」反面教训的补丁：失败必带
##   错误码 + 对象定位，不许只报「地图无效」（§8.4 可诊断性指标）。
## 分层：WorldData.validate 管数据形状/拓扑/对账（首错返回串——数据层口径）；
##   本校验器消费其串并**另查可玩面**（出生 footprint 通行/冲突、资源可达、
##   路网连通、锁定约束）——全部错误**收集不短路**（修复循环需要全清单）。
## opts（全部可选，默认 = 不查该面）：
##   - water_terrain_id / max_road_delta / max_bridge_bank_delta：透传
##     WorldData.validate 的生成配置口径（-1 = 无配置不查，§7 禁止项）；
##   - require_road_network: bool——必需聚落全连通检查的开关（道路阶段开启时置
##     true；跳过阶段 = 无该能力即无该约束）；
##   - resource_budget: int——资源点距出生锚的最大六边形环距（0 = 不查预算只查
##     可达；模板 scenario 组投影）；
##   - locked_cells: Array[int]——锁定格（WORLD-04 修复循环「修复不动 locked」的
##     校验面：道路格不得落入锁定格）。
## 纯函数：RefCounted、零场景节点（ADR-2）；不预加载任何生成器（被
##   RoadNetworkGenerator 增量重验与 WorldPipeline 修复循环消费——依赖方向单向）。
class_name WorldValidator
extends RefCounted

const Hex := preload("res://addons/hexhammer/hex_math.gd")
const MapDataClass := preload("res://scripts/core/data/map_data.gd")
const WorldDataClass := preload("res://scripts/core/data/world_data.gd")
const GenConnectivity := preload("res://scripts/content/map_generation_connectivity.gd")

## §11 错误码清单（「先包括」七码 + 本文件结构性扩格码——评审面）
const ERROR_CODES := ["NO_VALID_SPAWN", "RESOURCE_UNREACHABLE", "RIVER_CYCLE",
	"NO_RIVER_OUTLET", "BRIDGE_ENDPOINT_INVALID", "ROAD_NETWORK_DISCONNECTED",
	"LOCKED_CONSTRAINT_CONFLICT", "POI_FOOTPRINT_CONFLICT", "WORLD_DATA_INVALID"]

## 校验入口：返回 {"ok": bool, "errors": Array[Dictionary]}——每个错误
##   {code: String, cell_ids: Array[int], link_ids: Array[Vector2i],
##    constraint_id: String, explanation: String}（explanation 恒含对象定位——
##   cell/link/reach/poi id；WORLD-04 测试锚「每个错误码至少一个 fixture 断言
##   explanation 含定位」的落点）。
static func validate_report(map: MapDataClass, world: WorldDataClass,
		opts := {}) -> Dictionary:
	var errors: Array[Dictionary] = []
	# ---- ① 结构面（WorldData.validate 首错串 → 结构化；错误码取串首「全大写
	#      下划线」token——world_data 各分支的具名码，无码形状错误归
	#      WORLD_DATA_INVALID）----
	var verdict := world.validate(map, int(opts.get("water_terrain_id", -1)),
		int(opts.get("max_road_delta", -1)),
		int(opts.get("max_bridge_bank_delta", -1)))
	if verdict != "":
		errors.append(_error(_code_of(verdict), [], [], "", verdict))
	# ---- ② 出生区可玩面（§11 POI 行：footprint 界内可通行 = NO_VALID_SPAWN；
	#      设施冲突 = POI_FOOTPRINT_CONFLICT——冲突对象逐格指向）----
	var flanks := world.river_flank_cells()
	var banks := {}
	for c in world.crossings:
		banks[c.bank_a] = true
		banks[c.bank_b] = true
	var road_at := {}  # cell_id → 使用该格的 road_id 集（路口重数合法）
	for r in world.roads:
		for cid in r.cells:
			if not road_at.has(cid):
				road_at[cid] = {}
			road_at[cid][r.road_id] = true
	var zones := world.pois_of_kind(WorldDataClass.POIData.Kind.SPAWN_ZONE)
	for z in zones:
		var bad_pass: Array[int] = []
		for cid in z.footprint_cells:
			var cell := _cell_of(map, cid)
			if not map.is_passable(cell):
				bad_pass.append(cid)
		if not bad_pass.is_empty():
			errors.append(_error("NO_VALID_SPAWN", bad_pass, [], "",
				"出生区 poi %d（锚 %d）footprint 含不可通行格 %s（中心+六邻须全可通行——落兵区有效性，§11）"
				% [z.poi_id, z.cell_id, str(bad_pass)]))
		# 设施冲突：河岸锚点格 / 桥端 / 道路格（本区主城服务的路除外）/ 他方出生区
		# （他方区重叠已由 WorldData.POIS 规范序查重面拒绝，此处防御性复核）
		for cid in z.footprint_cells:
			if flanks.has(cid):
				errors.append(_error("POI_FOOTPRINT_CONFLICT", [cid], [],
					"poi:%d" % z.poi_id,
					"出生区 poi %d footprint 格 %d 与河岸锚点格重叠（有河 link 两岸格——格边口径「河床占格」的格级代理，§9 footprint 冲突约束）"
					% [z.poi_id, cid]))
				break
			if banks.has(cid):
				errors.append(_error("POI_FOOTPRINT_CONFLICT", [cid], [],
					"poi:%d" % z.poi_id,
					"出生区 poi %d footprint 格 %d 与桥端格重叠（bank_a/bank_b，§9）"
					% [z.poi_id, cid]))
				break
		# 道路冲突（带服务豁免：含本区主城锚的路可穿本区——WORLD-05 生成侧同款
		# 口径；两端 = 道路骨架的出发/终点必然入区）
		for cid in z.footprint_cells:
			if not road_at.has(cid):
				continue
			var serving := false
			for rid in road_at[cid]:
				var road: WorldDataClass.RoadData = world.road_by_id(int(rid))
				if road != null and road.cells.has(z.cell_id):
					serving = true
					break
			if not serving:
				errors.append(_error("POI_FOOTPRINT_CONFLICT", [cid], [],
					"poi:%d" % z.poi_id,
					"出生区 poi %d footprint 格 %d 与道路 %s 重叠且该路不经本区主城（非服务路不得穿出生区，§9）"
					% [z.poi_id, cid, str(road_at[cid].keys())]))
				break
	# ---- ③ 资源可达面（§11：必需资源可达——规则未启用按平地通行口径 =
	#      边级通行图（passable + Crossing 认领），草案 §11 原文；预算面
	#      resource_budget > 0 时加查环距）----
	var budget := int(opts.get("resource_budget", 0))
	if not zones.is_empty():
		for p in world.pois_of_kind(WorldDataClass.POIData.Kind.RESOURCE):
			var reached := false
			var over_budget_only := true
			var best_anchor := -1
			for z in zones:
				var anchor := _cell_of(map, z.cell_id)
				var conn := GenConnectivity.required_connected(map, world, anchor,
					_cell_of(map, p.cell_id))
				if conn["ok"]:
					over_budget_only = false
					if budget <= 0 or Hex.distance(anchor,
							_cell_of(map, p.cell_id)) <= budget:
						reached = true
						best_anchor = z.cell_id
						break
			if not reached and not over_budget_only:
				errors.append(_error("RESOURCE_UNREACHABLE", [p.cell_id], [],
					"poi:%d" % p.poi_id,
					"资源点 poi %d（格 %d）超出任一出生锚的预算（环距 > %d——可达但过远）"
					% [p.poi_id, p.cell_id, budget]))
			elif not reached:
				# 无任何出生锚可达：指向资源格 + 最近的被阻河段（blocked_river 非空时）
				var links: Array[Vector2i] = []
				var detail := ""
				for z in zones:
					var anchor := _cell_of(map, z.cell_id)
					var reach: Dictionary = GenConnectivity.reachable_set(map, world,
						anchor)["cells"]
					if reach.has(_cell_of(map, p.cell_id)):
						continue
					var blocked: Array = GenConnectivity.reachable_set(map, world,
						anchor)["blocked_river"]
					if not blocked.is_empty():
						var b0: Dictionary = blocked[0]
						links.append(b0["link"])
						detail = "，前沿被河段 reach %d 的边 %s 阻挡（无桥认领）" \
							% [int(b0["reach"]), str(b0["link"])]
				errors.append(_error("RESOURCE_UNREACHABLE", [p.cell_id], links,
					"poi:%d" % p.poi_id,
					"资源点 poi %d（格 %d）自任一出生锚均不可达（平地通行口径：格 passable × 有河 link 须桥认领）%s"
					% [p.poi_id, p.cell_id, detail]))
	# ---- ④ 路网连通面（§11 道路行：必需聚落全连通——聚落图经道路共享格成连通）----
	if bool(opts.get("require_road_network", false)):
		var settlements := world.pois_of_kind(WorldDataClass.POIData.Kind.SETTLEMENT)
		if settlements.size() >= 2:
			var comp := {}
			var idx_of_anchor := {}
			for i in settlements.size():
				comp[i] = i
				idx_of_anchor[settlements[i].cell_id] = i
			for r in world.roads:
				var members: Array[int] = []
				for cid in r.cells:
					if idx_of_anchor.has(cid):
						members.append(int(idx_of_anchor[cid]))
				for k in range(1, members.size()):
					var ra := _find(comp, members[0])
					var rb := _find(comp, members[k])
					if ra != rb:
						comp[ra] = rb
			var roots := {}
			for i in settlements.size():
				var root := _find(comp, i)
				roots[root] = true
			if roots.size() > 1:
				var comps := {}
				for i in settlements.size():
					var root := _find(comp, i)
					if not comps.has(root):
						comps[root] = []
					(comps[root] as Array).append(settlements[i].cell_id)
				var parts: Array = comps.values()
				var cell_ids: Array[int] = []
				for i in settlements.size():
					cell_ids.append(settlements[i].cell_id)
				errors.append(_error("ROAD_NETWORK_DISCONNECTED", cell_ids, [], "",
					"必需聚落未全连通：%d 个聚落分裂为 %d 个道路连通分量 %s（骨架/桥缺失——聚落图 MST 不完整）"
					% [settlements.size(), roots.size(), str(parts)]))
	# ---- ⑤ 锁定约束面（WORLD-04「修复不动 locked」的校验面：道路格禁入锁定格；
	#      豁免 = SETTLEMENT 锚定格——主城锚是路网**必经端点**（连接主城的路必然
	#      含锚格），锁定语义在此 = 主城不动 + 服务性道路到达，绕行面由其余锁定
	#      格承担；锚定出生/资源的保持由修复循环 pins 结构性保证）----
	var locked := {}
	for cid in opts.get("locked_cells", []):
		locked[int(cid)] = true
	if not locked.is_empty():
		var anchors := {}
		for p in world.pois:
			if p.kind == WorldDataClass.POIData.Kind.SETTLEMENT:
				anchors[p.cell_id] = true
		for r in world.roads:
			for cid in r.cells:
				if locked.has(cid) and not anchors.has(cid):
					errors.append(_error("LOCKED_CONSTRAINT_CONFLICT", [cid], [],
						"cell:%d" % cid,
						"道路 %d 的格 %d 落入锁定格（修复/定线不得触碰 locked 约束——WORLD-04 ②）"
						% [r.road_id, cid]))
	return {"ok": errors.is_empty(), "errors": errors}

# ---------------- 内部 ----------------

## cell 稳定 ID → axial 格（WorldData._cell_of_id 同式；校验器侧自持只读版——
## 避免跨文件私有依赖，SettlementGenerator.cell_of_id / RiverNetworkGenerator
## 同款先例）。
static func _cell_of(map: MapDataClass, id: int) -> Vector2i:
	return Hex.axial_of(Vector2i(id % map.width, id / map.width))

## 错误对象构造（固定键序——报告可 diff）。
static func _error(code: String, cell_ids: Array[int], link_ids: Array[Vector2i],
		constraint_id: String, explanation: String) -> Dictionary:
	return {"code": code, "cell_ids": cell_ids, "link_ids": link_ids,
		"constraint_id": constraint_id, "explanation": explanation}

## world_data 校验串 → 错误码（串首「：」前 token 且全部字符 ∈ [A-Z0-9_] 才认码
## ——RIVER_CYCLE / WATER_SEA_OUTLET 等；无码形状错误 → WORLD_DATA_INVALID，
## 仍带全文 explanation 定位）。
static func _code_of(verdict: String) -> String:
	var head := verdict.split("：")[0]
	var ok := not head.is_empty()
	for ch in head:
		if not (ch == "_" or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")):
			ok = false
			break
	return head if ok else "WORLD_DATA_INVALID"

static func _find(comp: Dictionary, i: int) -> int:
	var root := i
	while comp[root] != root:
		root = comp[root]
	return root
