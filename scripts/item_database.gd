class_name ItemDatabase
extends RefCounted
## ItemDatabase -- the placeholder item catalogue.
##
## Items are identified by a short string id everywhere in the code ("wolf_pelt"),
## because ids travel over the network and strings survive a serialisation round
## trip in a way that indices into an array do not. Display names live here alone,
## so renaming an item never touches quest or inventory logic.
##
## Placeholder depth on purpose: no stats, no rarity, no icons. Add fields when
## something actually needs them.

const ITEMS: Dictionary = {
	"wolf_pelt": "Wolf Pelt",
	"rusty_sword": "Rusty Sword",
	"bread": "Crusty Bread",
}


## Human-readable name for an id, falling back to the raw id so an unknown item
## shows up as itself instead of as an empty string in the UI.
static func display_name(item_id: String) -> String:
	return ITEMS.get(item_id, item_id)


static func exists(item_id: String) -> bool:
	return ITEMS.has(item_id)