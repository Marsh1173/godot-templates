class_name Serialization
extends RefCounted

static var record: Dictionary[String, Dictionary] = {}

# Serializes the current object state into a JSON-ready Dictionary
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
		
		# JSON spec always parses numbers as floats, not ints
		if type_enum == TYPE_INT:
			type_enum = TYPE_FLOAT
		
		if key in data and typeof(data[key]) == type_enum:
			if config[key] == TYPE_INT:
				# Cast float to int if int was the original type
				final[key] = int(data[key])
			else:
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
	var to_json = func(object: Variant) -> String:
		return JSON.stringify(_to_dict(config, object))
	var from_json = func(json_string: String, create_obj):
		var data = JSON.parse_string(json_string)
		
		if data != null:
			if typeof(data) == TYPE_DICTIONARY:
				var validated_data = _from_dict(config, data)
				if validated_data == null:
					return null
				var new_object = create_obj.call()
				_apply_from_dict(validated_data, new_object)
				return new_object
			else:
				push_error("JSON data is not a dictionary")
		else:
			push_error("JSON Parse Error for type ", key, " in data ", json_string)
		return null
	
	record.set(key, {"to_json": to_json, "from_json": from_json})
	return key

static func get_config(key: String):
	return record.get(key)
