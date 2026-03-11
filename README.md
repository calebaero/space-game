# Space Explorer

A top-down 2D space exploration/combat game built with Godot 4.x and GDScript.

## Requirements
- Godot 4.6.x (project currently validated with `4.6.1`)
- Desktop platform (PC target)

## Open And Run
1. Open Godot and import this folder:
   - `/Users/calebkennedy/Documents/GitHub/space-game`
2. Run the project (`F5`) from the editor.

CLI launch:
```bash
godot4 --path /Users/calebkennedy/Documents/GitHub/space-game
```

## Save And Settings Files
The game uses the `user://` sandbox:
- Saves: `user://saves/slot_1.json` .. `slot_3.json`
- Settings: `user://settings.json`

## Core Controls
- Mouse: aim
- Left Click or `W`: thrust
- Right Click: primary fire
- `R`: secondary fire
- `Space` or `Shift`: boost
- `S`: brake
- `A` / `D`: rotational assist
- `E`: interact/dock/confirm
- `F`: mine
- `Q`: scanner pulse
- `C`: utility module
- `Tab`: cycle target
- `Y`: cycle tracked mission
- `M`: galaxy map
- `Esc`: pause / close menus

## Game Flow
Main Menu -> New Game -> Tutorial prompt -> Sector flight/mining/combat -> Dock station for market/refinery/workshop/upgrades -> Unlock G2 and G3 -> Finish story and post-game contracts.

## Project Structure
Primary folders:
- `scenes/` runtime scenes
- `scripts/` gameplay/autoload/UI scripts
- `data/` catalog and content data resources
- `docs/` changelog, test plan, export notes

## Extension Guide
### Add a new resource
1. Add entry to `data/items/resources.tres` and `data/items/items.tres`.
2. Reference it in sector content (`data/sectors/*.tres`) or loot tables.
3. If refine/craft paths are needed, update `data/economy/refining_recipes.tres` or `data/economy/crafting_recipes.tres`.

### Add a new enemy archetype
1. Add archetype in `data/enemies/enemy_archetypes.tres`.
2. Add patrol usage in sector data (`enemy_patrols`).
3. If new weapon behavior is needed, define weapon in `data/items/weapons.tres`.

### Add a new sector
1. Create `data/sectors/sector_<id>.tres` from existing pattern.
2. Add it to the owning galaxy file in `data/galaxies/`.
3. Register inter-sector connections and warp gates.

### Add a new mission template
1. Contracts: update `data/missions/contract_templates.tres`.
2. Story: update `data/missions/story_missions.tres` with objective dictionaries and rewards.
3. Validate objective types against `scripts/autoload/MissionManager.gd` handlers.

## Export
See `docs/EXPORT_NOTES.md` for PC export checklist and preset notes.
