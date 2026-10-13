extends RefCounted

# Which settings file to use. MCM keeps one file per mod-loader profile:
# config.ini for the default profile, "<profile name>.ini" for any other
# (the active profile is stored in user://mod_config.cfg). Reading anything
# else means changes made in MCM under a profile never reach the mod.

const DIR = "user://MCM/ItemClarity"
const DEFAULT_FILE = "config.ini"


static func file_name() -> String:
	var loader = ConfigFile.new()
	if loader.load("user://mod_config.cfg") == OK:
		var profile := str(loader.get_value("settings", "active_profile", "Default"))
		if profile != "" and profile != "Default":
			return profile + ".ini"
	return DEFAULT_FILE


static func path() -> String:
	return DIR + "/" + file_name()
