## Hex 数学核心单测（axial / pointy-top）
extends RefCounted


func test_neighbor_set() -> String:
	var cell := Vector2i(3, -2)
	var nbs := Hex.neighbors(cell)
	var expect := [Vector2i(4, -2), Vector2i(4, -3), Vector2i(3, -3),
		Vector2i(2, -2), Vector2i(2, -1), Vector2i(3, -1)]
	for e in expect:
		if e not in nbs:
			return "缺邻居 %s（实际 %s）" % [e, nbs]
	if Hex.neighbors(Vector2i(0, 0)).size() != 6:
		return "邻居数 != 6"
	return ""


func test_distance() -> String:
	var cases := [
		[Vector2i(0, 0), Vector2i(0, 0), 0],
		[Vector2i(0, 0), Vector2i(1, 0), 1],
		[Vector2i(0, 0), Vector2i(3, -3), 3],
		[Vector2i(1, 2), Vector2i(4, -2), 4],
		[Vector2i(-3, 5), Vector2i(2, -1), 6],
	]
	for c in cases:
		var got := Hex.distance(c[0], c[1])
		if got != c[2]:
			return "distance(%s, %s) = %d，期望 %d" % [c[0], c[1], got, c[2]]
	return ""


func test_distance_symmetry() -> String:
	for a in [Vector2i(0, 0), Vector2i(2, 1), Vector2i(-4, 3)]:
		for b in [Vector2i(1, 1), Vector2i(-2, 6), Vector2i(5, -5)]:
			if Hex.distance(a, b) != Hex.distance(b, a):
				return "距离不对称：%s <-> %s" % [a, b]
	return ""


func test_ring() -> String:
	if Hex.ring(Vector2i(0, 0), 0) != [Vector2i(0, 0)]:
		return "ring 半径 0 应为 [center]"
	var r1 := Hex.ring(Vector2i(0, 0), 1)
	if r1.size() != 6:
		return "ring 1 大小 = %d，期望 6" % r1.size()
	var r3 := Hex.ring(Vector2i(2, -1), 3)
	if r3.size() != 18:
		return "ring 3 大小 = %d，期望 18" % r3.size()
	for cell in r3:
		if Hex.distance(Vector2i(2, -1), cell) != 3:
			return "ring 3 成员 %s 距中心 != 3" % cell
	return ""


func test_spiral_radius() -> String:
	var cells := Hex.spiral(Vector2i(0, 0), 2)
	if cells.size() != 1 + 6 + 12:
		return "spiral(2) 大小 = %d，期望 19" % cells.size()
	for cell in cells:
		if Hex.distance(Vector2i(0, 0), cell) > 2:
			return "spiral 越界成员 %s" % cell
	return ""


func test_world_roundtrip() -> String:
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-3, 2),
			Vector2i(5, -4), Vector2i(-7, -7), Vector2i(12, 3)]:
		var world := Hex.axial_to_world(cell)
		var back := Hex.world_to_axial(world)
		if back != cell:
			return "往返失败：%s → %s → %s" % [cell, world, back]
	return ""


func test_neighbor_adjacent_by_world() -> String:
	## 相邻格的世界坐标距离应一致（间距 = sqrt(3)*HEX_SIZE，误差内）
	var center := Vector2i(2, 3)
	var wc := Hex.axial_to_world(center)
	for nb in Hex.neighbors(center):
		var wn := Hex.axial_to_world(nb)
		var gap := wc.distance_to(wn)
		if absf(gap - sqrt(3.0) * Hex.HEX_SIZE) > 0.001:
			return "邻居 %s 间距 %.4f 异常" % [nb, gap]
	return ""


func test_line() -> String:
	if Hex.line(Vector2i(0, 0), Vector2i(0, 0)) != [Vector2i(0, 0)]:
		return "line 自身应为 [自身]"
	var l1 := Hex.line(Vector2i(0, 0), Vector2i(3, 0))
	if l1.size() != 4 or l1[0] != Vector2i(0, 0) or l1[3] != Vector2i(3, 0):
		return "line 东向 3 格应为 4 站：%s" % l1
	for cell in l1:
		if Hex.distance(cell, Vector2i(0, 0)) + Hex.distance(cell, Vector2i(3, 0)) != 3:
			return "line 成员 %s 不在直线上" % cell
	var l2 := Hex.line(Vector2i(-2, 4), Vector2i(2, 1))
	if l2.size() != Hex.distance(Vector2i(-2, 4), Vector2i(2, 1)) + 1:
		return "line 站数 != 距离+1"
	if l2[0] != Vector2i(-2, 4) or l2[-1] != Vector2i(2, 1):
		return "line 端点错误"
	return ""


func test_oddr_roundtrip() -> String:
	for col in range(-5, 6):
		for row in range(0, 8):
			var ax := Hex.oddr_to_axial(col, row)
			var back := Hex.axial_to_oddr(ax)
			if back != Vector2i(col, row):
				return "oddr 往返失败：(%d,%d) → %s → %s" % [col, row, ax, back]
	return ""
