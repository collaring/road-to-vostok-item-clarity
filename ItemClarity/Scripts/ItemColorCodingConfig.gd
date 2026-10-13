extends Node

# Load MCM helpers with load() instead of preload() so a missing MCM doesn't crash
var McmHelpers = load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")

const MOD_ID = "ItemClarity"
const FILE_PATH = "user://MCM/ItemClarity"

# [section, key] pairs in definition order, used by the built-in settings panel
var ordered_keys: Array = []
var _headings: Array = []  # "Tab: Section" headings in first-use order

# Section of each setting within its tab. _add() folds this into the setting's
# category as "Tab: Section", which is what both MCM and our panel display.
const GROUPS = {
	"colorCodingMode": "Inventory",  "searchBox": "Inventory",
	"inventoryTools": "Inventory",   "quickStackRange": "Inventory",
	"weightBarPosition": "Inventory",
	"weightOk": "Carry Weight Bar",  "weightWarn": "Carry Weight Bar",
	"weightOver": "Carry Weight Bar",
	"tooltipRework": "Tooltips",     "tooltipDelay": "Tooltips",
	"pricePerSlot": "Tooltips",      "recipeTooltip": "Tooltips",
	"compareEquipped": "Tooltips",
	"taskMarking": "Tasks",          "notedTasksOnly": "Tasks",
	"taskHaveCount": "Tasks",
	"taskDetailsAlways": "Tasks",
	"statPreview": "Highlights",     "compatHighlight": "Highlights",
	"compatHighlightColor": "Highlights",
	"worldHighlightStyle": "Style",  "worldDotPosition": "Style",
	"groundHighlight": "Ground Items",          "groundHighlightDistance": "Ground Items",
	"groundHighlightColor": "Ground Items",     "groundHighlightShelters": "Ground Items",
	"containerHighlight": "Containers",         "containerHighlightDistance": "Containers",
	"containerHighlightColor": "Containers",
	"crosshairDot": "Crosshair",              "crosshairColor": "Crosshair",
	"crosshairSize": "Crosshair",
	"icFocusSearch": "Inventory",              "icSort": "Inventory",
	"icQuickStack": "Inventory",              "icLockItem": "Inventory",              "icTaskDetails": "Tasks",
	"catAmmo": "Category Colors",
	"catArmor": "Category Colors",
	"catAttachments": "Category Colors",
	"catBackpacks": "Category Colors",
	"catBelts": "Category Colors",
	"catBooks": "Category Colors",
	"catClothing": "Category Colors",
	"catConsumables": "Category Colors",
	"catElectronics": "Category Colors",
	"catFishing": "Category Colors",
	"catGrenades": "Category Colors",
	"catHelmets": "Category Colors",
	"catInstruments": "Category Colors",
	"catKeys": "Category Colors",
	"catKnives": "Category Colors",
	"catLore": "Category Colors",
	"catMedical": "Category Colors",
	"catMisc": "Category Colors",
	"catRigs": "Category Colors",
	"catWeapons": "Category Colors",
	"rarCommon": "Rarity Colors",
	"rarRare": "Rarity Colors",
	"rarLegendary": "Rarity Colors",
	"valueMetric": "Value Colors",
	"valLow": "Value Colors",
	"valFair": "Value Colors",
	"valGood": "Value Colors",
	"valGreat": "Value Colors",
	"valTop": "Value Colors",
}


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
		# Always refresh names, headings and order (keeping values), so both our
		# panel and MCM pick up layout changes from newer versions
		if merge_defaults(_config, defaults):
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


# Every setting gets "Tab: Section" as its category and its definition order as
# menu_pos. MCM has no tabs, only headings sorted by the Category entries'
# menu_pos and settings sorted by their own menu_pos (else alphabetically), so
# this makes MCM show exactly the built-in panel's structure and order.
func _add(cfg: ConfigFile, section: String, key: String, data: Dictionary) -> void:
	if GROUPS.has(key):
		data["category"] = str(data.get("category", "General")) + ": " + GROUPS[key]
	data["menu_pos"] = ordered_keys.size() + 1
	cfg.set_value(section, key, data)
	ordered_keys.append([section, key])
	if not _headings.has(data.get("category", "")):
		_headings.append(data.get("category", ""))


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
	# Drop settings (and tabs, e.g. the old "Ground Items") removed in newer versions
	for section in ["Bool", "Dropdown", "Float", "Color", "Category"]:
		if cfg.has_section(section):
			for key in cfg.get_section_keys(section):
				if not defaults.has_section_key(section, key):
					cfg.erase_section_key(section, key)
					changed = true
	return changed


func build_defaults() -> ConfigFile:
	ordered_keys = []
	_headings = []
	var _config = ConfigFile.new()

	# ── General ───────────────────────────────────────────────────────────────
	_add(_config, "Dropdown", "colorCodingMode", {
		"name"    = "Color Coding",
		"tooltip" = "How to color-code items in your inventory.",
		"default" = 0,
		"value"   = 0,
		"options" = [
			"Category",
			"Rarity",
			"Value",
			"None"
		],
		"category" = "General"
	})

	_add(_config, "Bool", "searchBox", {
		"name"     = "Inventory Search Box",
		"tooltip"  = "Adds a search box while the inventory is open. Can give it focus with Spacebar as the default. Searches name, type, caliber and category, so '762' finds 7.62x39.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_add(_config, "Dropdown", "weightBarPosition", {
		"name"    = "Carry Weight Bar",
		"tooltip" = "A bar filling toward your carry limit, hovering an item in a container shows how much it would add/remove.",
		"default" = 0,
		"value"   = 0,
		"options" = [
			"Under Equipment Stats",
			"Under Inventory",
			"Off"
		],
		"category" = "General"
	})

	_add(_config, "Bool", "inventoryTools", {
		"name"     = "Sort & Quick Stack Buttons",
		"tooltip"  = "Adds a Sort button (which also merges partial stacks) above your inventory. In shelters, Quick Stack moves inventory items into nearby containers that already hold the same item.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_add(_config, "Float", "quickStackRange", {
		"name"     = "Quick Stack Range (meters)",
		"tooltip"  = "How close a shelter container must be for Quick Stack to put items into it.",
		"default"  = 6.0,
		"value"    = 6.0,
		"minRange" = 2.0,
		"maxRange" = 20.0,
		"step"     = 1.0,
		"category" = "General"
	})

	_add(_config, "Bool", "tooltipRework", {
		"name"     = "Tooltip Rework",
		"tooltip"  = "Smoother inventory tooltips to prevent jitter.",
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

	_add(_config, "Bool", "pricePerSlot", {
		"name"     = "Price per Slot Tooltip",
		"tooltip"  = "Shows the item's value divided by the number of inventory slots it occupies when hovering in the inventory.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_add(_config, "Bool", "recipeTooltip", {
		"name"     = "Show Crafting Recipes in Tooltip",
		"tooltip"  = "Shows which crafting recipes use this item as an ingredient when hovering it in the inventory.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_add(_config, "Bool", "compareEquipped", {
		"name"     = "Compare With Equipped Gear",
		"tooltip"  = "When hovering gear or a weapon, shows how it differs from what you have equipped in that slot.",
		"default"  = true,
		"value"    = true,
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

	_add(_config, "Bool", "taskDetailsAlways", {
		"name"     = "Always Show Task Details",
		"tooltip"  = "Always list a task's other items (and how many you have) in the tooltip, instead of only while holding the Task Details key (Alt by default).",
		"default"  = false,
		"value"    = false,
		"category" = "General"
	})

	_add(_config, "Bool", "statPreview", {
		"name"     = "Preview Stat Changes",
		"tooltip"  = "While hovering food, drinks or medical items, the Character panel shows stat changes in real-time. Hovering a stat outlines every item that would raise it.",
		"default"  = true,
		"value"    = true,
		"category" = "General"
	})

	_add(_config, "Bool", "compatHighlight", {
		"name"     = "Highlight Compatible Items",
		"tooltip"  = "When hovering or dragging an item, outlines every compatible item like ammo, magazines, weapons and attachments.",
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


	# ── World Highlights: Style ────────────────────────────────────────────────
	_add(_config, "Dropdown", "worldHighlightStyle", {
		"name"    = "Highlight Style",
		"tooltip" = "Outline draws an edge/overlay around ground items and containers. Dot shows a small marker instead (uses each one's color at a fixed opacity).",
		"default" = 0,
		"value"   = 0,
		"options" = [
			"Outline",
			"Dot"
		],
		"category" = "World Highlights"
	})

	_add(_config, "Dropdown", "worldDotPosition", {
		"name"    = "Dot Position",
		"tooltip" = "Where dots sit when Highlight Style is Dot: just above the item or container, or at its center.",
		"default" = 1,
		"value"   = 1,
		"options" = [
			"Above",
			"Centered"
		],
		"category" = "World Highlights"
	})

	# ── World Highlights: Ground Items ────────────────────────────────────────
	_add(_config, "Bool", "groundHighlight", {
		"name"     = "Outline Nearby Ground Items",
		"tooltip"  = "Draws an outline around items lying on the ground when you're close to them.",
		"default"  = true,
		"value"    = true,
		"category" = "World Highlights"
	})

	_add(_config, "Float", "groundHighlightDistance", {
		"name"     = "Outline Distance (meters)",
		"tooltip"  = "How close you need to be for ground items to be outlined.",
		"default"  = 8.0,
		"value"    = 8.0,
		"minRange" = 1.0,
		"maxRange" = 30.0,
		"step"     = 1.0,
		"category" = "World Highlights"
	})

	_add(_config, "Color", "groundHighlightColor", {
		"name"       = "Outline Color",
		"tooltip"    = "Color of the ground item outline. Lower the alpha for a subtler outline.",
		"default"    = Color("#ffffff26"),
		"value"      = Color("#ffffff26"),
		"allowAlpha" = true,
		"category"   = "World Highlights"
	})

	_add(_config, "Bool", "groundHighlightShelters", {
		"name"     = "Outline in Shelters",
		"tooltip"  = "Also outline items lying around inside your shelters.",
		"default"  = false,
		"value"    = false,
		"category" = "World Highlights"
	})

	# ── World Highlights: Containers ──────────────────────────────────────────
	_add(_config, "Bool", "containerHighlight", {
		"name"     = "Outline Unsearched Containers",
		"tooltip"  = "Outlines openable containers you haven't searched yet this raid when you're close.",
		"default"  = false,
		"value"    = false,
		"category" = "World Highlights"
	})

	_add(_config, "Float", "containerHighlightDistance", {
		"name"     = "Container Outline Distance (meters)",
		"tooltip"  = "How close you need to be for unsearched containers to be outlined.",
		"default"  = 8.0,
		"value"    = 8.0,
		"minRange" = 1.0,
		"maxRange" = 30.0,
		"step"     = 1.0,
		"category" = "World Highlights"
	})

	_add(_config, "Color", "containerHighlightColor", {
		"name"       = "Container Outline Color",
		"tooltip"    = "Color of the unsearched container outline.",
		"default"    = Color("#ffd24d26"),
		"value"      = Color("#ffd24d26"),
		"allowAlpha" = true,
		"category"   = "World Highlights"
	})

	# ── World Highlights: Crosshair ───────────────────────────────────────────
	_add(_config, "Dropdown", "crosshairDot", {
		"name"    = "Crosshair Dot",
		"tooltip" = "A small dot at the center of the screen so you can see exactly what you're pointing at.",
		"default" = 1,
		"value"   = 1,
		"options" = [
			"Always",
			"When Aiming at Items, Containers & Doors",
			"Off"
		],
		"category" = "World Highlights"
	})

	_add(_config, "Color", "crosshairColor", {
		"name"       = "Crosshair Color",
		"tooltip"    = "Color of the crosshair dot.",
		"default"    = Color(1.0, 1.0, 1.0, 0.85),
		"value"      = Color(1.0, 1.0, 1.0, 0.85),
		"allowAlpha" = true,
		"category"   = "World Highlights"
	})

	_add(_config, "Float", "crosshairSize", {
		"name"     = "Crosshair Size (pixels)",
		"tooltip"  = "Radius of the crosshair dot.",
		"default"  = 2.5,
		"value"    = 2.5,
		"minRange" = 1.0,
		"maxRange" = 6.0,
		"step"     = 0.5,
		"category" = "World Highlights"
	})

	# ── Keybinds ──────────────────────────────────────────────────────────────
	_add(_config, "Keycode", "icFocusSearch", {
		"name"           = "Focus Search",
		"tooltip"        = "Jumps into the inventory search box while the inventory is open.",
		"default"        = KEY_SPACE,
		"value"          = KEY_SPACE,
		"type"           = "Key",
		"default_type"   = "Key",
		"altPressed"     = false,
		"controlPressed" = false,
		"metaPressed"    = false,
		"shiftPressed"   = false,
		"category"       = "Keybinds"
	})

	_add(_config, "Keycode", "icSort", {
		"name"           = "Sort",
		"tooltip"        = "Sorts (and merges stacks in) your inventory, or the open shelter container if you're hovering it. Unbound by default.",
		"default"        = 0,
		"value"          = 0,
		"type"           = "Key",
		"default_type"   = "Key",
		"altPressed"     = false,
		"controlPressed" = false,
		"metaPressed"    = false,
		"shiftPressed"   = false,
		"category"       = "Keybinds"
	})

	_add(_config, "Keycode", "icQuickStack", {
		"name"           = "Quick Stack",
		"tooltip"        = "In a shelter, runs Quick Stack without clicking the button. Unbound by default.",
		"default"        = 0,
		"value"          = 0,
		"type"           = "Key",
		"default_type"   = "Key",
		"altPressed"     = false,
		"controlPressed" = false,
		"metaPressed"    = false,
		"shiftPressed"   = false,
		"category"       = "Keybinds"
	})

	_add(_config, "Keycode", "icLockItem", {
		"name"           = "Lock Item",
		"tooltip"        = "Locks or unlocks the item under your mouse. Locked items are never moved by Sort or Quick Stack.",
		"default"        = KEY_L,
		"value"          = KEY_L,
		"type"           = "Key",
		"default_type"   = "Key",
		"altPressed"     = false,
		"controlPressed" = false,
		"metaPressed"    = false,
		"shiftPressed"   = false,
		"category"       = "Keybinds"
	})

	_add(_config, "Keycode", "icTaskDetails", {
		"name"           = "Task Details",
		"tooltip"        = "Hold while hovering a task item to also list the task's other items and how many of each you have.",
		"default"        = KEY_ALT,
		"value"          = KEY_ALT,
		"type"           = "Key",
		"default_type"   = "Key",
		"altPressed"     = false,
		"controlPressed" = false,
		"metaPressed"    = false,
		"shiftPressed"   = false,
		"category"       = "Keybinds"
	})

	# ── Category Colors ───────────────────────────────────────────────────────
	# Alpha controls tint opacity. Transparent (alpha=0) means no color is applied.
	_add(_config, "Color", "catAmmo", {
		"name"       = "Ammo",
		"tooltip"    = "Tint color for Ammo items. Set alpha to 0 to disable.",
		"default"    = Color(0.15, 0.65, 0.15, 0.15),
		"value"      = Color(0.15, 0.65, 0.15, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catArmor", {
		"name"       = "Armor",
		"tooltip"    = "Tint color for Armor items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catAttachments", {
		"name"       = "Attachments",
		"tooltip"    = "Tint color for Attachment items. Set alpha to 0 to disable.",
		"default"    = Color(0.15, 0.65, 0.15, 0.15),
		"value"      = Color(0.15, 0.65, 0.15, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catBackpacks", {
		"name"       = "Backpacks",
		"tooltip"    = "Tint color for Backpack items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catBelts", {
		"name"       = "Belts",
		"tooltip"    = "Tint color for Belt items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catBooks", {
		"name"       = "Books",
		"tooltip"    = "Tint color for Book items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catClothing", {
		"name"       = "Clothing",
		"tooltip"    = "Tint color for Clothing items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catConsumables", {
		"name"       = "Consumables",
		"tooltip"    = "Tint color for Consumable items. Set alpha to 0 to disable.",
		"default"    = Color(0.90, 0.60, 0.05, 0.15),
		"value"      = Color(0.90, 0.60, 0.05, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catElectronics", {
		"name"       = "Electronics",
		"tooltip"    = "Tint color for Electronics items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catFishing", {
		"name"       = "Fishing",
		"tooltip"    = "Tint color for Fishing items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catGrenades", {
		"name"       = "Grenades",
		"tooltip"    = "Tint color for Grenade items. Set alpha to 0 to disable.",
		"default"    = Color(0.15, 0.65, 0.15, 0.15),
		"value"      = Color(0.15, 0.65, 0.15, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catHelmets", {
		"name"       = "Helmets",
		"tooltip"    = "Tint color for Helmet items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catInstruments", {
		"name"       = "Instruments",
		"tooltip"    = "Tint color for Instrument items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catKeys", {
		"name"       = "Keys",
		"tooltip"    = "Tint color for Key items. Set alpha to 0 to disable.",
		"default"    = Color(0.95, 0.40, 0.70, 0.15),
		"value"      = Color(0.95, 0.40, 0.70, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catKnives", {
		"name"       = "Knives",
		"tooltip"    = "Tint color for Knife items. Set alpha to 0 to disable.",
		"default"    = Color(0.25, 0.25, 0.25, 0.15),
		"value"      = Color(0.25, 0.25, 0.25, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catLore", {
		"name"       = "Lore",
		"tooltip"    = "Tint color for Lore items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catMedical", {
		"name"       = "Medical",
		"tooltip"    = "Tint color for Medical items. Set alpha to 0 to disable.",
		"default"    = Color(0.85, 0.10, 0.10, 0.15),
		"value"      = Color(0.85, 0.10, 0.10, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catMisc", {
		"name"       = "Misc",
		"tooltip"    = "Tint color for Misc items. Set alpha to 0 to disable.",
		"default"    = Color(0.0, 0.0, 0.0, 0.0),
		"value"      = Color(0.0, 0.0, 0.0, 0.0),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catRigs", {
		"name"       = "Rigs",
		"tooltip"    = "Tint color for Rig items. Set alpha to 0 to disable.",
		"default"    = Color(0.55, 0.15, 0.75, 0.15),
		"value"      = Color(0.55, 0.15, 0.75, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "catWeapons", {
		"name"       = "Weapons",
		"tooltip"    = "Tint color for Weapon items. Set alpha to 0 to disable.",
		"default"    = Color(0.25, 0.25, 0.25, 0.15),
		"value"      = Color(0.25, 0.25, 0.25, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	# ── Rarity Colors ─────────────────────────────────────────────────────────
	_add(_config, "Color", "rarCommon", {
		"name"       = "Common",
		"tooltip"    = "Tint color for Common rarity items. Set alpha to 0 to disable.",
		"default"    = Color(0.40, 0.40, 0.40, 0.15),
		"value"      = Color(0.40, 0.40, 0.40, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "rarRare", {
		"name"       = "Rare",
		"tooltip"    = "Tint color for Rare rarity items. Set alpha to 0 to disable.",
		"default"    = Color(0.60, 0.20, 0.80, 0.15),
		"value"      = Color(0.60, 0.20, 0.80, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "rarLegendary", {
		"name"       = "Legendary",
		"tooltip"    = "Tint color for Legendary rarity items. Set alpha to 0 to disable.",
		"default"    = Color(1.00, 0.65, 0.00, 0.15),
		"value"      = Color(1.00, 0.65, 0.00, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	# ── Value Colors ──────────────────────────────────────────────────────────
	_add(_config, "Dropdown", "valueMetric", {
		"name"    = "Value Measure",
		"tooltip" = "What 'value' means for Value color coding, uses the game's item database.",
		"default" = 0,
		"value"   = 0,
		"options" = [
			"Per Slot",
			"Total"
		],
		"category" = "Colors"
	})

	_add(_config, "Color", "valLow", {
		"name"       = "Low",
		"tooltip"    = "Tint for low value items when Color Coding is set to Value. Bottom 40% of items by value.",
		"default"    = Color(0.45, 0.45, 0.45, 0.15),
		"value"      = Color(0.45, 0.45, 0.45, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "valFair", {
		"name"       = "Fair",
		"tooltip"    = "Tint for fair value items when Color Coding is set to Value. Next 30% (40th-70th percentile).",
		"default"    = Color(0.30, 0.75, 0.35, 0.15),
		"value"      = Color(0.30, 0.75, 0.35, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "valGood", {
		"name"       = "Good",
		"tooltip"    = "Tint for good value items when Color Coding is set to Value. Next 18% (70th-88th percentile).",
		"default"    = Color(0.25, 0.55, 0.95, 0.15),
		"value"      = Color(0.25, 0.55, 0.95, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "valGreat", {
		"name"       = "Great",
		"tooltip"    = "Tint for great value items when Color Coding is set to Value. Next 7% (88th-95th percentile).",
		"default"    = Color(0.65, 0.30, 0.90, 0.15),
		"value"      = Color(0.65, 0.30, 0.90, 0.15),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "valTop", {
		"name"       = "Elite",
		"tooltip"    = "Tint for elite value items when Color Coding is set to Value. The most valuable 5% of items in the game.",
		"default"    = Color(1.00, 0.70, 0.10, 0.18),
		"value"      = Color(1.00, 0.70, 0.10, 0.18),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	# ── Carry Weight Bar colours ───────────────────────────────────────────────
	_add(_config, "Color", "weightOk", {
		"name"       = "Under 50%",
		"tooltip"    = "Carry weight bar color below half your carry limit.",
		"default"    = Color(0.35, 0.85, 0.35, 1.0),
		"value"      = Color(0.35, 0.85, 0.35, 1.0),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "weightWarn", {
		"name"       = "50% and Over",
		"tooltip"    = "Carry weight bar color from half your carry limit (the game shows your weight in yellow here).",
		"default"    = Color(0.95, 0.8, 0.2, 1.0),
		"value"      = Color(0.95, 0.8, 0.2, 1.0),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	_add(_config, "Color", "weightOver", {
		"name"       = "Overweight",
		"tooltip"    = "Carry weight bar color once you're over your carry limit.",
		"default"    = Color(1.0, 0.35, 0.3, 1.0),
		"value"      = Color(1.0, 0.35, 0.3, 1.0),
		"allowAlpha" = true,
		"category"   = "Colors"
	})

	# ── Category ordering ────────────────────────────────────────────────────
	for i in _headings.size():
		_config.set_value("Category", _headings[i], { "menu_pos" = i + 1 })

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
