@tool
extends EditorPlugin
## Adds the Moon Tips dock (see tips_dock.gd), a Project > Tools > Moon
## Tips entry that opens it, and the Tips autoload.

const TipsDock := preload("res://addons/moon_tips/tips_dock.gd")
const MENU_ITEM := "Moon Tips"

var _dock: EditorDock


func _enable_plugin() -> void:
	add_autoload_singleton("Tips", "res://addons/moon_tips/tips.gd")


func _disable_plugin() -> void:
	remove_autoload_singleton("Tips")


func _enter_tree() -> void:
	_dock = TipsDock.new()
	add_dock(_dock)
	add_tool_menu_item(MENU_ITEM, _show_dock)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	remove_dock(_dock)
	_dock.queue_free()
	_dock = null


func _show_dock() -> void:
	_dock.open()
	_dock.make_visible()
