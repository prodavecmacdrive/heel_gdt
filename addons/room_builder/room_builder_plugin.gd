@tool
extends EditorPlugin

const ROOM_BUILDER_SCRIPT: Script = preload("res://addons/room_builder/room_builder.gd")
const ROOM_BUILDER_ICON: Texture2D = preload("res://icon.svg")

func _enter_tree() -> void:
	add_custom_type("RoomBuilder", "Node3D", ROOM_BUILDER_SCRIPT, ROOM_BUILDER_ICON)

func _exit_tree() -> void:
	remove_custom_type("RoomBuilder")

