extends RefCounted

func test_neighbors_are_six() -> String:
	var n := Hex.neighbors(Vector2i(3, 3))
	if n.size() != 6:
		return "expected 6 neighbors, got %d" % n.size()
	return ""

func test_neighbors_are_distance_one() -> String:
	for n in Hex.neighbors(Vector2i.ZERO):
		if Hex.distance(Vector2i.ZERO, n) != 1:
			return "neighbor %s not at distance 1" % str(n)
	return ""

func test_distance_known_values() -> String:
	var cases := [
		[Vector2i(0, 0), Vector2i(3, 0), 3],
		[Vector2i(0, 0), Vector2i(0, 3), 3],
		[Vector2i(0, 0), Vector2i(3, -3), 3],
		[Vector2i(0, 0), Vector2i(-2, 1), 2],
	]
	for c in cases:
		var got := Hex.distance(c[0], c[1])
		if got != c[2]:
			return "distance(%s, %s) = %d, want %d" % [str(c[0]), str(c[1]), got, c[2]]
	return ""

func test_distance_symmetry() -> String:
	for a in [Vector2i(0, 0), Vector2i(2, 5), Vector2i(-3, 7)]:
		for b in [Vector2i(1, 1), Vector2i(-4, 2), Vector2i(9, -9)]:
			if Hex.distance(a, b) != Hex.distance(b, a):
				return "distance not symmetric for %s / %s" % [str(a), str(b)]
	return ""

func test_offset_axial_roundtrip() -> String:
	for row in [0, 1, 2, 7, 29]:
		for col in [0, 1, 13, 39]:
			var ax := Hex.offset_to_axial(col, row)
			if Hex.axial_to_offset(ax) != Vector2i(col, row):
				return "roundtrip failed for offset (%d,%d)" % [col, row]
	return ""

func test_pixel_roundtrip_all_hexes() -> String:
	var fails := 0
	for row in 30:
		for col in 40:
			var ax := Hex.offset_to_axial(col, row)
			var px := Hex.to_pixel(ax, 34.0)
			if Hex.from_pixel(px, 34.0) != ax:
				fails += 1
	if fails > 0:
		return "%d hexes failed pixel roundtrip" % fails
	return ""

func test_pixel_roundtrip_with_jitter() -> String:
	var ax := Hex.offset_to_axial(7, 9)
	var px := Hex.to_pixel(ax, 34.0)
	for offset in [Vector2(5, 5), Vector2(-8, 3), Vector2(2, -9), Vector2(-6, -6)]:
		if Hex.from_pixel(px + offset, 34.0) != ax:
			return "jitter %s broke roundtrip" % str(offset)
	return ""

func test_pathfinding_reachable_plain() -> String:
	var map := HexMap.new(12, 10, 1)
	for hex in map.terrain:
		map.terrain[hex] = HexMap.Terrain.PLAIN
	var reach := HexPathfinding.reachable(map, {}, Hex.offset_to_axial(5, 4), 4.0)
	# 平原上半径 4 的球 = 61 格（1+6+12+18+24），12x10 内无裁剪
	if reach.size() != 61:
		return "expected 61 reachable hexes on open plain, got %d" % reach.size()
	return ""

func test_pathfinding_blocked_enemy() -> String:
	var map := HexMap.new(12, 10, 1)
	for hex in map.terrain:
		map.terrain[hex] = HexMap.Terrain.PLAIN
	var origin := Hex.offset_to_axial(2, 2)
	var east := origin + Vector2i(1, 0)
	var reach := HexPathfinding.reachable(map, {east: true}, origin, 1.0)
	# 东侧被敌军堵住：可达格 = 起点 + 另外 5 个邻居
	if reach.has(east):
		return "blocked hex is reachable"
	if reach.size() != 6:
		return "expected 6 reachable, got %d" % reach.size()
	return ""

func test_pathfinding_path_length() -> String:
	var map := HexMap.new(12, 10, 1)
	for hex in map.terrain:
		map.terrain[hex] = HexMap.Terrain.PLAIN
	var origin := Hex.offset_to_axial(2, 2)
	var dest := origin + Vector2i(3, 0)
	var path := HexPathfinding.find_path(map, {}, origin, dest, 10.0)
	if path.size() != 4:
		return "expected path of 4 hexes, got %d" % path.size()
	if path[0] != origin or path[path.size() - 1] != dest:
		return "path endpoints wrong"
	return ""
