extends Node

# Load MCM helpers with load() instead of preload() so a missing MCM doesn't crash
var McmHelpers = load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")

const MOD_ID = "ItemClarity"
const FILE_PATH = "user://MCM/ItemClarity"

var border_opacity: float = 0.15

func _ready() -> void:
	var _config = ConfigFile.new()

	_config.set_value("Bool", "categoryColorCoding", {
		"name"    = "Color Coding - Category",
		"tooltip" = "Color items by category (Medical, Ammo, Weapons, etc.). Takes priority over rarity coding.",
		"default" = true,
		"value"   = true
	})

	_config.set_value("Bool", "rarityColorCoding", {
		"name"    = "Color Coding - Rarity",
		"tooltip" = "Color items by rarity (Common, Rare, Legendary). Used when category coding is off or the item has no known category.",
		"default" = false,
		"value"   = false
	})

	_config.set_value("Float", "borderOpacity", {
		"name"     = "Color Opacity",
		"tooltip"  = "Opacity of the rarity color (0 = invisible, 1 = fully opaque).",
		"default"  = 0.15,
		"value"    = 0.15,
		"minRange" = 0.0,
		"maxRange" = 1.0
	})

	_config.set_value("Bool", "taskMarking", {
		"name"    = "Mark Items Needed for Tasks",
		"tooltip" = "Shows a '!' badge on items required for active trader tasks, and lists them in the item tooltip.",
		"default" = true,
		"value"   = true
	})

	_config.set_value("Float", "tooltipDelay", {
		"name"     = "Tooltip Delay (seconds)",
		"tooltip"  = "How long to hover an item before its tooltip appears. Default game value is 0.5.",
		"default"  = 0.1,
		"value"    = 0.1,
		"minRange" = 0.0,
		"maxRange" = 2.0
	})

	if !FileAccess.file_exists(FILE_PATH + "/config.ini"):
		DirAccess.make_dir_recursive_absolute(FILE_PATH)
		_config.save(FILE_PATH + "/config.ini")
	else:
		if McmHelpers:
			McmHelpers.CheckConfigurationHasUpdated(MOD_ID, _config, FILE_PATH + "/config.ini")
		_config.load(FILE_PATH + "/config.ini")

	# Apply the loaded values immediately
	_apply_config(_config)

	if McmHelpers:
		McmHelpers.RegisterConfiguration(
			MOD_ID,
			"Item Clarity",
			FILE_PATH,
			"Color codes items by category or rarity, and marks items needed for active trader tasks.",
			{
				"config.ini" = _on_config_saved
			}
		)
	else:
		_warn_mcm_missing()


# Called by MCM whenever the player saves changes in the configuration menu
func _on_config_saved(_config: ConfigFile) -> void:
	_apply_tooltip_delay(_config)
	var root = get_tree().get_root()
	var main = _find_node_named(root, "ItemClarity")
	if main and main.has_method("refresh_all_slots"):
		main.refresh_all_slots()


func _find_node_named(node: Node, target: String) -> Node:
	if node.name == target:
		return node
	for child in node.get_children():
		var found = _find_node_named(child, target)
		if found:
			return found
	return null


func _apply_config(config: ConfigFile) -> void:
	border_opacity = config.get_value("Float", "borderOpacity", 0.15)
	_apply_tooltip_delay(config)


func _apply_tooltip_delay(config: ConfigFile) -> void:
	var v = config.get_value("Float", "tooltipDelay", 0.1)
	var delay: float = float(v.get("value", 0.1) if v is Dictionary else v)
	var interface = get_node_or_null("/root/Map/Core/UI/Interface")
	if interface and "tooltipDelay" in interface:
		interface.tooltipDelay = delay


func _warn_mcm_missing() -> void:
	push_warning("[ItemColorCoding] Mod Configuration Menu is not installed. Color settings will use defaults.")
