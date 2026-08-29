extends Node
class_name PlayerSettings

const _SettingsSectionName := "player-settings"

class Fields:
	const Fullscreen := "fullscreen"

static func get_config_path() -> String:
	var path := "user://player-config.cfg"
	
	# If running in the editor, append the instance ID so players don't share configs
	if OS.is_debug_build():
		var args := OS.get_cmdline_args()
		for arg in args:
			if arg.begins_with("instance="):
				path = "user://player-config-" + arg.split("=")[1] + ".cfg"
				break
	
	return path

static func get_default_settings() -> Dictionary[String, Variant]:
	return {
		Fields.Fullscreen: true
	}

static func set_setting(key: String, value: Variant):
	var config := ConfigFile.new()
	config.load(get_config_path())
	
	config.set_value(_SettingsSectionName, key, value)
	config.save(get_config_path())

static func get_settings() -> Dictionary[String, Variant]:
	var config := ConfigFile.new()
	var err = config.load(get_config_path())

	var default_settings: Dictionary[String, Variant] = get_default_settings()
	if err != OK or !config.has_section(_SettingsSectionName):
		return default_settings
	else:
		for setting_key in config.get_section_keys(_SettingsSectionName):
			default_settings.set(setting_key, config.get_value(_SettingsSectionName, setting_key))
		return default_settings

static func get_setting(key: String) -> Variant:
	return get_settings().get(key)

static func reset_settings_to_default():
	var config := ConfigFile.new()
	var err = config.load(get_config_path())

	if err != OK:
		return
	elif config.has_section(_SettingsSectionName):
		config.erase_section(_SettingsSectionName)
		config.save(get_config_path())
