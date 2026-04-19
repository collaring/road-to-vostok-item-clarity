extends Node

# Load MCM helpers with load() instead of preload() so a missing MCM doesn't crash
var McmHelpers = load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")

const MOD_ID = "ItemClarity"
const FILE_PATH = "user://MCM/ItemClarity"

func _ready() -> void:
	var _config = ConfigFile.new()

	# ── General ───────────────────────────────────────────────────────────────
	_config.set_value("Dropdown", "colorCodingMode", {
		"name"    = "Color Coding",
		"tooltip" = "How to color-code items in your inventory. Category takes priority and uses the colors below. Rarity uses the rarity colors. None disables color coding.",
		"default" = 0,
		"value"   = 0,
		"options" = [
			"Category",
			"Rarity",
			"None"
		],
		"category" = "General"
	})

	_config.set_value("Bool", "taskMarking", {
		"name"     = "Mark Items Needed for Tasks",
		"tooltip"  = "Shows a '!' badge on items required for active trader tasks, and lists them in the item tooltip.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_config.set_value("Bool", "notedTasksOnly", {
		"name"     = "Only Show Task Marker on Noted Tasks",
		"tooltip"  = "When enabled, the '!' badge only appears on items needed for tasks you have manually added to your notes.",
		"default"  = false,
		"value"    = false,
		"category" = "General"
	})

	_config.set_value("Dropdown", "taskMarkerCorner", {
		"name"    = "Task Marker Corner",
		"tooltip" = "Which corner to place the '!' task marker on items needed for active tasks.",
		"default" = 0,
		"value"   = 0,
		"options" = [
			"Bottom Right",
			"Bottom Left",
			"Top Right",
			"Top Left"
		],
		"category" = "General"
	})

	_config.set_value("Bool", "recipeTooltip", {
		"name"     = "Show Crafting Recipes in Tooltip",
		"tooltip"  = "Shows which crafting recipes use this item as an ingredient when hovering it in the inventory.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_config.set_value("Bool", "pricePerSlot", {
		"name"     = "Price per Slot Tooltip",
		"tooltip"  = "Shows the item's value divided by the number of inventory slots it occupies when hovering in the inventory.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_config.set_value("Float", "tooltipDelay", {
		"name"     = "Tooltip Delay (seconds)",
		"tooltip"  = "How long to hover an item before its tooltip appears. Default game value is 0.5.",
		"default"  = 0.1,
		"value"    = 0.1,
		"minRange" = 0.0,
		"maxRange" = 2.0,
		"step"     = 0.05,
		"category" = "General"
	})

	# ── Category Colors ───────────────────────────────────────────────────────
	# Alpha controls tint opacity. Transparent (alpha=0) means no color is applied.
	_config.set_value("Color", "catAmmo", {
		"name"       = "Ammo",
		"tooltip"    = "Tint color for Ammo items. Set alpha to 0 to disable.",
		"default"    = Color(0.15, 0.65, 0.15, 0.15),
		"value"      = Color(0.15, 0.65, 0.15, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catArmor", {
		"name"       = "Armor",
		"tooltip"    = "Tint color for Armor items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catAttachments", {
		"name"       = "Attachments",
		"tooltip"    = "Tint color for Attachment items. Set alpha to 0 to disable.",
		"default"    = Color(0.15, 0.65, 0.15, 0.15),
		"value"      = Color(0.15, 0.65, 0.15, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catBackpacks", {
		"name"       = "Backpacks",
		"tooltip"    = "Tint color for Backpack items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catBelts", {
		"name"       = "Belts",
		"tooltip"    = "Tint color for Belt items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catBooks", {
		"name"       = "Books",
		"tooltip"    = "Tint color for Book items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catClothing", {
		"name"       = "Clothing",
		"tooltip"    = "Tint color for Clothing items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catConsumables", {
		"name"       = "Consumables",
		"tooltip"    = "Tint color for Consumable items. Set alpha to 0 to disable.",
		"default"    = Color(0.90, 0.60, 0.05, 0.15),
		"value"      = Color(0.90, 0.60, 0.05, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catElectronics", {
		"name"       = "Electronics",
		"tooltip"    = "Tint color for Electronics items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catFishing", {
		"name"       = "Fishing",
		"tooltip"    = "Tint color for Fishing items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catGrenades", {
		"name"       = "Grenades",
		"tooltip"    = "Tint color for Grenade items. Set alpha to 0 to disable.",
		"default"    = Color(0.15, 0.65, 0.15, 0.15),
		"value"      = Color(0.15, 0.65, 0.15, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catHelmets", {
		"name"       = "Helmets",
		"tooltip"    = "Tint color for Helmet items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catInstruments", {
		"name"       = "Instruments",
		"tooltip"    = "Tint color for Instrument items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catKeys", {
		"name"       = "Keys",
		"tooltip"    = "Tint color for Key items. Set alpha to 0 to disable.",
		"default"    = Color(0.95, 0.40, 0.70, 0.15),
		"value"      = Color(0.95, 0.40, 0.70, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catKnives", {
		"name"       = "Knives",
		"tooltip"    = "Tint color for Knife items. Set alpha to 0 to disable.",
		"default"    = Color(0.25, 0.25, 0.25, 0.15),
		"value"      = Color(0.25, 0.25, 0.25, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catLore", {
		"name"       = "Lore",
		"tooltip"    = "Tint color for Lore items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catMedical", {
		"name"       = "Medical",
		"tooltip"    = "Tint color for Medical items. Set alpha to 0 to disable.",
		"default"    = Color(0.85, 0.10, 0.10, 0.15),
		"value"      = Color(0.85, 0.10, 0.10, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catMisc", {
		"name"       = "Misc",
		"tooltip"    = "Tint color for Misc items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catRigs", {
		"name"       = "Rigs",
		"tooltip"    = "Tint color for Rig items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_config.set_value("Color", "catWeapons", {
		"name"       = "Weapons",
		"tooltip"    = "Tint color for Weapon items. Set alpha to 0 to disable.",
		"default"    = Color(0.25, 0.25, 0.25, 0.15),
		"value"      = Color(0.25, 0.25, 0.25, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	# ── Rarity Colors ─────────────────────────────────────────────────────────
	_config.set_value("Color", "rarCommon", {
		"name"       = "Common",
		"tooltip"    = "Tint color for Common rarity items. Set alpha to 0 to disable.",
		"default"    = Color(0.40, 0.40, 0.40, 0.15),
		"value"      = Color(0.40, 0.40, 0.40, 0.15),
		"allowAlpha" = true,
		"category"   = "Rarity Colors"
	})

	_config.set_value("Color", "rarRare", {
		"name"       = "Rare",
		"tooltip"    = "Tint color for Rare rarity items. Set alpha to 0 to disable.",
		"default"    = Color(0.60, 0.20, 0.80, 0.15),
		"value"      = Color(0.60, 0.20, 0.80, 0.15),
		"allowAlpha" = true,
		"category"   = "Rarity Colors"
	})

	_config.set_value("Color", "rarLegendary", {
		"name"       = "Legendary",
		"tooltip"    = "Tint color for Legendary rarity items. Set alpha to 0 to disable.",
		"default"    = Color(1.00, 0.65, 0.00, 0.15),
		"value"      = Color(1.00, 0.65, 0.00, 0.15),
		"allowAlpha" = true,
		"category"   = "Rarity Colors"
	})

	# ── Category ordering ────────────────────────────────────────────────────
	_config.set_value("Category", "General",         { "menu_pos" = 1 })
	_config.set_value("Category", "Category Colors", { "menu_pos" = 2 })
	_config.set_value("Category", "Rarity Colors",   { "menu_pos" = 3 })

	if !FileAccess.file_exists(FILE_PATH + "/config.ini"):
		DirAccess.make_dir_recursive_absolute(FILE_PATH)
		_config.save(FILE_PATH + "/config.ini")
	else:
		if McmHelpers:
			McmHelpers.CheckConfigurationHasUpdated(MOD_ID, _config, FILE_PATH + "/config.ini")
		_config.load(FILE_PATH + "/config.ini")

	_apply_tooltip_delay(_config)

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


func _apply_tooltip_delay(config: ConfigFile) -> void:
	var v = config.get_value("Float", "tooltipDelay", 0.1)
	var delay: float = float(v.get("value", 0.1) if v is Dictionary else v)
	var interface = get_node_or_null("/root/Map/Core/UI/Interface")
	if interface and "tooltipDelay" in interface:
		interface.tooltipDelay = delay


func _warn_mcm_missing() -> void:
	push_warning("[ItemColorCoding] Mod Configuration Menu is not installed. Color settings will use defaults.")
