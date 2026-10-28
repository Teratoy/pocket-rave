@tool
extends EditorPlugin
## Adds the BackgroundMusic Android library (built from res://android_plugin)
## to Android exports. Needs "Use Gradle Build" in the Android preset.

var _export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	const NAME := "BackgroundMusic"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var build := "debug" if debug else "release"
		return PackedStringArray(["background_music/bin/%s-%s.aar" % [NAME, build]])

	func _get_name() -> String:
		return NAME
