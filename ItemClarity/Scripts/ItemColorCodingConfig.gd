extends Node

# Load MCM helpers with load() instead of preload() so a missing MCM doesn't crash
var McmHelpers = load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")

const MOD_ID = "ItemClarity"
const FILE_PATH = "user://MCM/ItemClarity"

# [section, key] pairs in definition order, used by the built-in settings panel
var ordered_keys: Array = []


func _ready() -> void:
	var defaults = build_defaults()
	var _config = ConfigFile.new()

	if !FileAccess.file_exists(FILE_PATH + "/config.ini"):
		DirAccess.make_dir_recursive_absolute(FILE_PATH)
		defaults.save(FILE_PATH + "/config.ini")
		_config = defaults
	else:
		if McmHelpers:
			McmHelpers.CheckConfigurationHasUpdated(MOD_ID, defaults, FILE_PATH + "/config.ini")
		_config.load(FILE_PATH + "/config.ini")
		# Without MCM nobody else adds settings introduced in newer versions
		if not McmHelpers and merge_defaults(_config, defaults):
			_config.save(FILE_PATH + "/config.ini")

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


func _add(cfg: ConfigFile, section: String, key: String, data: Dictionary) -> void:
	cfg.set_value(section, key, data)
	ordered_keys.append([section, key])


# Adds missing settings and refreshes metadata (names, tooltips, options) from
# defaults while keeping the user's values. Returns true if anything changed.
func merge_defaults(cfg: ConfigFile, defaults: ConfigFile) -> bool:
	var changed := false
	for section in defaults.get_sections():
		for key in defaults.get_section_keys(section):
			var def = defaults.get_value(section, key)
			if not cfg.has_section_key(section, key):
				cfg.set_value(section, key, def)
				changed = true
				continue
			var cur = cfg.get_value(section, key)
			if def is Dictionary and cur is Dictionary and def.has("value"):
				var merged: Dictionary = def.duplicate()
				merged["value"] = cur.get("value", def["value"])
				if merged != cur:
					cfg.set_value(section, key, merged)
					changed = true
	# Drop settings that were removed in newer versions
	for section in ["Bool", "Dropdown", "Float", "Color"]:
		if cfg.has_section(section):
			for key in cfg.get_section_keys(section):
				if not defaults.has_section_key(section, key):
					cfg.erase_section_key(section, key)
					changed = true
	return changed


func build_defaults() -> ConfigFile:
	ordered_keys = []
	var _config = ConfigFile.new()

	# ── General ───────────────────────────────────────────────────────────────
	_add(_config, "Dropdown", "colorCodingMode", {
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

	_add(_config, "Bool", "taskMarking", {
		"name"     = "Mark Items Needed for Tasks",
		"tooltip"  = "Shows a '!' badge on items required for active trader tasks, and lists them in the item tooltip.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_add(_config, "Bool", "notedTasksOnly", {
		"name"     = "Only Show Task Marker on Noted Tasks",
		"tooltip"  = "When enabled, the '!' badge only appears on items needed for tasks you have manually added to your notes.",
		"default"  = false,
		"value"    = false,
		"category" = "General"
	})

	_add(_config, "Bool", "taskHaveCount", {
		"name"     = "Show How Many You Have for Tasks",
		"tooltip"  = "Adds '(have 1/2)' to task lines in the tooltip, counting your inventory, equipment and all your shelters' storage. Stackables only count when the stack is full enough for the trader to accept.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_add(_config, "Dropdown", "taskMarkerCorner", {
		"name"    = "Task Marker Corner",
		"tooltip" = "Which corner to place the '!' task marker on items needed for active tasks.",
		"default" = 3,
		"value"   = 3,
		"options" = [
			"Bottom Right",
			"Bottom Left",
			"Top Right",
			"Top Left"
		],
		"category" = "General"
	})

	_add(_config, "Bool", "recipeTooltip", {
		"name"     = "Show Crafting Recipes in Tooltip",
		"tooltip"  = "Shows which crafting recipes use this item as an ingredient when hovering it in the inventory.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_add(_config, "Bool", "pricePerSlot", {
		"name"     = "Price per Slot Tooltip",
		"tooltip"  = "Shows the item's value divided by the number of inventory slots it occupies when hovering in the inventory.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_add(_config, "Float", "tooltipDelay", {
		"name"     = "Tooltip Delay (seconds)",
		"tooltip"  = "How long to hover an item before its tooltip appears. Default game value is 0.5.",
		"default"  = 0.1,
		"value"    = 0.1,
		"minRange" = 0.0,
		"maxRange" = 2.0,
		"step"     = 0.05,
		"category" = "General"
	})

	_add(_config, "Bool", "searchBox", {
		"name"     = "Inventory Search Box",
		"tooltip"  = "Adds a search box while the inventory is open. Matching items are outlined and everything else is dimmed. Searches name, type, caliber and category, so '762' finds 7.62x39.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_add(_config, "Bool", "statPreview", {
		"name"     = "Preview Stat Changes",
		"tooltip"  = "While hovering food, drinks or medical items, the Character panel shows what your health, energy, hydration, mental and body temperature would be after using it. Hovering a stat outlines every item that would raise it.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})


	_add(_config, "Bool", "compatHighlight", {
		"name"     = "Highlight Compatible Items",
		"tooltip"  = "When hovering or dragging an item, outlines every compatible item: ammo, magazines, weapons and attachments.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_add(_config, "Color", "compatHighlightColor", {
		"name"       = "Compatible Highlight Color",
		"tooltip"    = "Outline color for compatible items.",
		"default"    = Color("#ffffff46"),
		"value"      = Color("#ffffff46"),
		"allowAlpha" = true,
		"category"   = "General"
	})

	_add(_config, "Bool", "tooltipRework", {
		"name"     = "Tooltip Rework",
		"tooltip"  = "Smoother inventory tooltips: they stay open while you move the mouse, follow the cursor every frame, update instantly when you move to another item, and stay on screen.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	# ── Ground Items ──────────────────────────────────────────────────────────
	_add(_config, "Bool", "groundHighlight", {
		"name"     = "Outline Nearby Ground Items",
		"tooltip"  = "Draws an outline around items lying on the ground when you're close to them. If you also use Loot Highlight, turn one of them off to avoid double outlines.",
		"default"  = true,
		"value"    = true,
		"category" = "Ground Items"
	})

	_add(_config, "Float", "groundHighlightDistance", {
		"name"     = "Outline Distance (meters)",
		"tooltip"  = "How close you need to be for ground items to be outlined.",
		"default"  = 8.0,
		"value"    = 8.0,
		"minRange" = 1.0,
		"maxRange" = 30.0,
		"step"     = 1.0,
		"category" = "Ground Items"
	})

	_add(_config, "Color", "groundHighlightColor", {
		"name"       = "Outline Color",
		"tooltip"    = "Color of the ground item outline. Lower the alpha for a subtler outline.",
		"default"    = Color("#ffffff26"),
		"value"      = Color("#ffffff26"),
		"allowAlpha" = true,
		"category"   = "Ground Items"
	})

	_add(_config, "Bool", "groundHighlightShelters", {
		"name"     = "Outline in Shelters",
		"tooltip"  = "Also outline items lying around inside your shelters.",
		"default"  = false,
		"value"    = false,
		"category" = "Ground Items"
	})

	# ── Category Colors ───────────────────────────────────────────────────────
	# Alpha controls tint opacity. Transparent (alpha=0) means no color is applied.
	_add(_config, "Color", "catAmmo", {
		"name"       = "Ammo",
		"tooltip"    = "Tint color for Ammo items. Set alpha to 0 to disable.",
		"default"    = Color(0.15, 0.65, 0.15, 0.15),
		"value"      = Color(0.15, 0.65, 0.15, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catArmor", {
		"name"       = "Armor",
		"tooltip"    = "Tint color for Armor items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catAttachments", {
		"name"       = "Attachments",
		"tooltip"    = "Tint color for Attachment items. Set alpha to 0 to disable.",
		"default"    = Color(0.15, 0.65, 0.15, 0.15),
		"value"      = Color(0.15, 0.65, 0.15, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catBackpacks", {
		"name"       = "Backpacks",
		"tooltip"    = "Tint color for Backpack items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catBelts", {
		"name"       = "Belts",
		"tooltip"    = "Tint color for Belt items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catBooks", {
		"name"       = "Books",
		"tooltip"    = "Tint color for Book items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catClothing", {
		"name"       = "Clothing",
		"tooltip"    = "Tint color for Clothing items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catConsumables", {
		"name"       = "Consumables",
		"tooltip"    = "Tint color for Consumable items. Set alpha to 0 to disable.",
		"default"    = Color(0.90, 0.60, 0.05, 0.15),
		"value"      = Color(0.90, 0.60, 0.05, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catElectronics", {
		"name"       = "Electronics",
		"tooltip"    = "Tint color for Electronics items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catFishing", {
		"name"       = "Fishing",
		"tooltip"    = "Tint color for Fishing items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catGrenades", {
		"name"       = "Grenades",
		"tooltip"    = "Tint color for Grenade items. Set alpha to 0 to disable.",
		"default"    = Color(0.15, 0.65, 0.15, 0.15),
		"value"      = Color(0.15, 0.65, 0.15, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catHelmets", {
		"name"       = "Helmets",
		"tooltip"    = "Tint color for Helmet items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catInstruments", {
		"name"       = "Instruments",
		"tooltip"    = "Tint color for Instrument items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catKeys", {
		"name"       = "Keys",
		"tooltip"    = "Tint color for Key items. Set alpha to 0 to disable.",
		"default"    = Color(0.95, 0.40, 0.70, 0.15),
		"value"      = Color(0.95, 0.40, 0.70, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catKnives", {
		"name"       = "Knives",
		"tooltip"    = "Tint color for Knife items. Set alpha to 0 to disable.",
		"default"    = Color(0.25, 0.25, 0.25, 0.15),
		"value"      = Color(0.25, 0.25, 0.25, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catLore", {
		"name"       = "Lore",
		"tooltip"    = "Tint color for Lore items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catMedical", {
		"name"       = "Medical",
		"tooltip"    = "Tint color for Medical items. Set alpha to 0 to disable.",
		"default"    = Color(0.85, 0.10, 0.10, 0.15),
		"value"      = Color(0.85, 0.10, 0.10, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catMisc", {
		"name"       = "Misc",
		"tooltip"    = "Tint color for Misc items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catRigs", {
		"name"       = "Rigs",
		"tooltip"    = "Tint color for Rig items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	_add(_config, "Color", "catWeapons", {
		"name"       = "Weapons",
		"tooltip"    = "Tint color for Weapon items. Set alpha to 0 to disable.",
		"default"    = Color(0.25, 0.25, 0.25, 0.15),
		"value"      = Color(0.25, 0.25, 0.25, 0.15),
		"allowAlpha" = true,
		"category"   = "Category Colors"
	})

	# ── Rarity Colors ─────────────────────────────────────────────────────────
	_add(_config, "Color", "rarCommon", {
		"name"       = "Common",
		"tooltip"    = "Tint color for Common rarity items. Set alpha to 0 to disable.",
		"default"    = Color(0.40, 0.40, 0.40, 0.15),
		"value"      = Color(0.40, 0.40, 0.40, 0.15),
		"allowAlpha" = true,
		"category"   = "Rarity Colors"
	})

	_add(_config, "Color", "rarRare", {
		"name"       = "Rare",
		"tooltip"    = "Tint color for Rare rarity items. Set alpha to 0 to disable.",
		"default"    = Color(0.60, 0.20, 0.80, 0.15),
		"value"      = Color(0.60, 0.20, 0.80, 0.15),
		"allowAlpha" = true,
		"category"   = "Rarity Colors"
	})

	_add(_config, "Color", "rarLegendary", {
		"name"       = "Legendary",
		"tooltip"    = "Tint color for Legendary rarity items. Set alpha to 0 to disable.",
		"default"    = Color(1.00, 0.65, 0.00, 0.15),
		"value"      = Color(1.00, 0.65, 0.00, 0.15),
		"allowAlpha" = true,
		"category"   = "Rarity Colors"
	})

	# ── Category ordering ────────────────────────────────────────────────────
	_config.set_value("Category", "General",         { "menu_pos" = 1 })
	_config.set_value("Category", "Ground Items",    { "menu_pos" = 2 })
	_config.set_value("Category", "Category Colors", { "menu_pos" = 3 })
	_config.set_value("Category", "Rarity Colors",   { "menu_pos" = 4 })

	return _config


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
	print("[ItemClarity] Mod Configuration Menu not installed; use the Item Clarity button in the inventory to change settings.")
