class_name ItemRegistry

class ItemDefinition:
	var id: ItemData.ID
	var name: String
	
	func _init(_id: ItemData.ID, _name: String):
		id = _id
		name = _name
	
	func get_mesh_path() -> String:
		var script_path: String = ItemRegistry.new().get_script().get_path()
		var script_path_parts: PackedStringArray = script_path.split("/")
		return "/".join(script_path_parts.slice(0, -1)) + "/models/" + name + ".res"
	func get_icon_path() -> String:
		var script_path: String = ItemRegistry.new().get_script().get_path()
		var script_path_parts: PackedStringArray = script_path.split("/")
		return "/".join(script_path_parts.slice(0, -1)) + "/icons/" + name + "_icon.png"

static func get_by_id(id: ItemData.ID) -> ItemDefinition:
	return item_registry.get(id)

static var item_registry: Dictionary[ItemData.ID, ItemDefinition] = make_item_registry()

# We also define a maker func in case in-editor @tools need to reference the item registry (e.g. icon generator)
static func make_item_registry() -> Dictionary[ItemData.ID, ItemDefinition]:
	return {
		ItemData.ID.Beer: ItemDefinition.new(
			ItemData.ID.Beer,
			"Beer",
		),
		ItemData.ID.Berries: ItemDefinition.new(
			ItemData.ID.Berries,
			"Berries",
		),
		ItemData.ID.Meat: ItemDefinition.new(
			ItemData.ID.Meat,
			"Meat",
		),
		ItemData.ID.Obsidian: ItemDefinition.new(
			ItemData.ID.Obsidian,
			"Obsidian",
		),
		ItemData.ID.Stone: ItemDefinition.new(
			ItemData.ID.Stone,
			"Stone",
		),
		ItemData.ID.Wood: ItemDefinition.new(
			ItemData.ID.Wood,
			"Wood",
		),
	}

#region mesh
const BEER_MESH: Mesh = preload("uid://dmq7p12tbkor2")
const BERRIES_MESH: Mesh = preload("uid://dk66gy7oc0465")
const MEAT_MESH: Mesh = preload("uid://bphxdfcdd26ed")
const OBSIDIAN_MESH: Mesh = preload("uid://b6vjutl8u1666")
const STONE_MESH: Mesh = preload("uid://b6g32rxopmuxt")
const WOOD_MESH: Mesh = preload("uid://8cmlk5rjwtf5")

static func get_item_mesh(id: ItemData.ID) -> Mesh:
	match id:
		ItemData.ID.Beer:
			return BEER_MESH
		ItemData.ID.Berries:
			return BERRIES_MESH
		ItemData.ID.Meat:
			return MEAT_MESH
		ItemData.ID.Obsidian:
			return OBSIDIAN_MESH
		ItemData.ID.Stone:
			return STONE_MESH
		ItemData.ID.Wood:
			return WOOD_MESH
	assert(false, "Tried to get an item mesh with an invalid id")
	return
#endregion

##region icon
#const BEER_MESH: Mesh = preload("uid://dmq7p12tbkor2")
#const BERRIES_MESH = preload("uid://dk66gy7oc0465")
#const MEAT_MESH = preload("uid://bphxdfcdd26ed")
#const OBSIDIAN_MESH = preload("uid://b6vjutl8u1666")
#const STONE_MESH = preload("uid://b6g32rxopmuxt")
#const WOOD_MESH = preload("uid://8cmlk5rjwtf5")
#
#static func get_item_icon(id: ItemData.ID):
	#match id:
		#ItemData.ID.Beer:
			#return BEER_MESH
		#ItemData.ID.Berries:
			#return BERRIES_MESH
		#ItemData.ID.Meat:
			#return MEAT_MESH
		#ItemData.ID.Obsidian:
			#return OBSIDIAN_MESH
		#ItemData.ID.Stone:
			#return STONE_MESH
		#ItemData.ID.Wood:
			#return WOOD_MESH
##endregion
