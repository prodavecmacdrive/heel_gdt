@tool
extends EditorPlugin

const BUNKER_MASTER_SCRIPT: Script = preload("res://addons/bunker_master/bunker_master.gd")
const BUNKER_MASTER_ICON: Texture2D = preload("res://icon.svg")

func _enter_tree() -> void:
	add_custom_type("BunkerMaster", "Node3D", BUNKER_MASTER_SCRIPT, BUNKER_MASTER_ICON)

func _exit_tree() -> void:
	remove_custom_type("BunkerMaster")

