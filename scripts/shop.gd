extends Node
## The shop button opens the shop menu, which lists its categories; each
## category is a folder in SHOP_DIR whose images are its items. Picking an
## item puts it to use and remembers it between runs:
## - UI skins: the art drawn over the bottom of the screen (the UI sprite).
##   Skins are only looks: the humans measure the walkable area from the
##   scene's own UI art before the saved skin replaces it, which this node
##   being after Humans in the scene makes sure of.

const Menu := preload("res://scripts/menu.gd")

const SHOP_DIR := "res://visual assets/shop/"
## Category folders in SHOP_DIR, in menu order, and their titles.
const CATEGORIES := {
	"UI": "UI SKINS",
}
const SETTINGS_FILE := "user://settings.cfg"
## More items than this scroll in a category's list.
const MAX_VISIBLE_ITEMS := 6

@export var button: Sprite2D
@export var ui: Sprite2D

var _menu: Menu
var _category_menus := {}
var _category_lists := {}


func _ready() -> void:
	# Usable while paused; the menus below inherit this.
	process_mode = Node.PROCESS_MODE_ALWAYS
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu = Menu.new(button.texture, "SHOP")
	add_child(_menu)
	for category: String in CATEGORIES:
		var m := Menu.new(button.texture, CATEGORIES[category])
		add_child(m)
		_category_lists[category] = m.add_scroll()
		m.add_item("BACK", _open)
		_category_menus[category] = m
		_menu.add_item(CATEGORIES[category], _open_category.bind(category))
		var saved := _saved(category)
		if saved != "" and ResourceLoader.exists(saved):
			_apply(category, saved)
	_menu.add_item("CLOSE", func(): pass)
	button.pressed.connect(_open)


func _open() -> void:
	Tips.event("shop")
	_menu.open()


func _open_category(category: String) -> void:
	var m: Menu = _category_menus[category]
	var list: VBoxContainer = _category_lists[category]
	Menu.clear(list)
	var current := _current(category)
	for path in _items(category):
		m.add_button(_item_name(path), _pick.bind(category, path), path == current, list)
	m.fit_scroll(list, MAX_VISIBLE_ITEMS)
	m.open()


## The category's items, the original look first and the rest by name.
func _items(category: String) -> PackedStringArray:
	var dir := SHOP_DIR + category + "/"
	var paths: Array[String] = []
	# Lists imported files by their source names, in exports too.
	for file in ResourceLoader.list_directory(dir):
		if file.get_extension().to_lower() in ["png", "webp", "jpg", "jpeg"]:
			paths.append(dir + file)
	paths.sort_custom(func(a: String, b: String):
		var a_orig := a.get_file().get_basename() == "original"
		var b_orig := b.get_file().get_basename() == "original"
		return a_orig if a_orig != b_orig else a.naturalnocasecmp_to(b) < 0)
	return PackedStringArray(paths)


func _item_name(path: String) -> String:
	return path.get_file().get_basename().replace("_", " ").to_upper()


## Puts the item to use and reopens the list with it marked.
func _pick(category: String, path: String) -> void:
	_apply(category, path)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	cfg.set_value("shop", category, path)
	cfg.save(SETTINGS_FILE)
	Tips.event("shop_item_picked", {"item": _item_name(path), "category": category})
	_open_category(category)


func _apply(category: String, path: String) -> void:
	match category:
		"UI":
			ui.texture = load(path)


## The item in use.
func _current(category: String) -> String:
	match category:
		"UI":
			return ui.texture.resource_path
	return ""


func _saved(category: String) -> String:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	return cfg.get_value("shop", category, "")
