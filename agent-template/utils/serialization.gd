class_name Serialization
extends RefCounted

static var record: Dictionary[String, Dictionary] = {}

# Serializes the current object state into a Dictionary
static func _to_dict(config: Dictionary[String, int], object: Variant) -> Dictionary:
	var final = {}
	for key in config:
		final[key] = object[key]
	return final

# Deserializes a Dictionary into object matching config
static func _from_dict(config: Dictionary[String, int], data: Dictionary):
	var final = {}
	for key in config:
		var type_enum = config[key]
		
		if key in data and typeof(data[key]) == type_enum:
			final[key] = data[key]
		else:
			push_error("Validation Error for type ", key, " meant to be type ", config[key], ", not ", typeof(data[key]))
			return null
	return final
	
# Applies a Dictionary to an object
static func _apply_from_dict(data: Dictionary, object: Variant):
	for key in data:
		object[key] = data[key]

static func register(key: String, config: Dictionary[String, int]) -> String:
	var to_dict = func(object: Variant) -> Dictionary:
		return _to_dict(config, object)
	var from_dict = func(data: Dictionary, create_obj):
		var validated_data = _from_dict(config, data)
		if validated_data == null:
			return null
		var new_object = create_obj.call()
		_apply_from_dict(validated_data, new_object)
		return new_object
	
	record.set(key, {"to_dict": to_dict, "from_dict": from_dict})
	return key

static func get_config(key: String):
	return record.get(key)
