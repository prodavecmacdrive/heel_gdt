# Project Rules for AI Agent (Godot 4.x)
1. **Language:** Strict GDScript 2.0 (use static typing `var x: int = 0`, `func foo() -> void:`, `@export`, `@onready`, `super()`). Never use Godot 3 syntax.
2. **File Management:** Never manually generate or modify `.uid` or `.import` files.
3. **Tooling Architecture:** 
   - Keep tools lightweight using `@tool` scripts and `@export_tool_button` where possible instead of complex custom docks.
   - Full EditorPlugins must reside in `res://addons/<plugin_name>/`.
   - Always guard editor-only logic with `if Engine.is_editor_hint():`.
4. **Scene Cleanliness:** Rooms in `res://rooms/` must inherit/use `res://core/room_base.gd`. Global state lives strictly in `GameManager` (`res://core/game_manager.gd`).
5. **Execution Mode (Code Editing Only):**
   - You are operating STRICTLY as a static code and scene file editor.
   - DO NOT attempt to run the Godot binary, execute scenes, spawn background processes, or perform visual/headless runtime testing.
   - Validation must be done exclusively via static analysis: checking GDScript syntax, static types, correct inheritance, and ensuring valid scene node hierarchies.
6. Never commit or push to Git unless I ask you to.
### CRITICAL OPERATIONAL CONSTRAINT:
- CODE-ONLY INTERACTION: Do not run `godot`, execute tests, launch background processes, or attempt any visual/headless scene execution. 
- You must ONLY read, create, and modify project files (`.gd`, `.tscn`, `.tres`).
- Verification is strictly static (syntax, strict typing, node tree ownership).