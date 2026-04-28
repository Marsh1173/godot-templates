class_name Cell
extends RefCounted

var coords: Vector2i = Vector2i(0, 0)
var possible_tiles: Array[HexTile]= []
var is_collapsed: bool = false

func get_entropy() -> float:
	var sum: float = 0.0 # I think this is how you calculate Shannon Entropy
	for possible_tile in possible_tiles:
		sum += possible_tile.weight
	return sum

func collapse():
	assert(len(possible_tiles) != 0, "possible_tiles was 0??")
	assert(is_collapsed == false, "is_collapsed was true in collapse()")
	
	var sum: float = 0
	for tile in possible_tiles:
		sum += tile.weight
	
	var selected_weight := randf_range(0, sum)
	
	for tile in possible_tiles:
		selected_weight -= tile.weight
		if selected_weight <= 0:
			possible_tiles = [tile]
			is_collapsed = true
			break
