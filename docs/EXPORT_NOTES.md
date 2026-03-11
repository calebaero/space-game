# Export Notes (PC)

## Current Project Export Baseline
- Main scene: `res://scenes/main/MainMenu.tscn`
- Project name/window title: `Space Explorer`
- Window size: `1920x1080`
- Stretch mode: `canvas_items`
- Stretch aspect: `expand`
- Physics ticks: `60`
- Icon: `res://icon.svg` (placeholder)

## Godot Export Presets
`export_presets.cfg` is not currently committed in this repository. Create/export presets locally in Godot:
1. `Project -> Export...`
2. Add `Windows Desktop` preset (and/or Linux/macOS as needed).
3. Configure executable name (`SpaceExplorer`), architecture, and output path.
4. Export with default placeholder icon/audio/assets for now.

## Pre-export Quick Checklist
- Run once from editor and verify New Game + Continue + Save/Load.
- Verify no missing resource/script errors in output console.
- Verify settings persistence (`user://settings.json`).
- Verify all 9 sectors can load from normal progression.
