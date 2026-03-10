# Test Plan — Space Explorer

## Phase 01 Manual Checklist

1. Launch the project.
2. Confirm the game opens to `MainMenu` with title, dark background, and slowly scrolling stars.
3. Confirm `Continue` is disabled.
4. Click `New Game`.
5. Confirm the scene transitions to `GameRoot` and displays the starting sector.
6. Verify debug text shows `Frontier Verge — Anchor Station` on the first line.
7. Verify a placeholder station (hexagon) and planet (circle) are visible in the sector.
8. Press `Esc` to open the pause overlay.
9. Confirm gameplay pauses while pause menu is visible.
10. Press `Resume` and confirm pause closes.
11. Press `Esc` again, then `Quit to Menu`.
12. Confirm return to `MainMenu` and project remains responsive.

## Phase 02 Manual Checklist (Flight + HUD)

1. From `MainMenu`, start a new game and wait for sector load.
2. Confirm a player ship appears near the station with a smooth-follow camera.
3. Verify a toast appears at top-center: `Welcome to Anchor Station sector`, then fades out after ~2 seconds.
4. Hold left mouse button and verify forward thrust acceleration.
5. Hold `W` and verify alternate thrust works.
6. Move mouse around and verify the ship rotates toward cursor with momentum (no instant snap).
7. Release thrust and verify velocity persists (drift).
8. While drifting in any direction, hold `S` and verify braking opposes velocity vector (not facing direction).
9. Press `A` and `D` and verify fine manual rotational assist is added.
10. Press `Space` (or `Shift`) once and verify boost burst for ~2 seconds, then cooldown behavior before reuse.
11. Watch HUD boost meter drop by boost cost and recharge over time.
12. Build speed above cruise and verify camera zooms out smoothly; slow down and verify zoom returns.
13. Observe velocity vector indicator near the ship and verify it points in drift direction distinct from ship nose when sliding.
14. Fly into sector edges and verify static boundary walls prevent leaving the 8000×8000 sector.
15. Confirm HUD values stay live (speed readout, hull/shield placeholders, cargo and credits).
16. Press `Esc` to pause/unpause and verify flight simulation halts/resumes correctly.

## Phase 03 Manual Checklist (Sector Interactions)

1. Start a new game and fly to Anchor Station.
2. Enter station docking zone and verify prompt toast:
   - `Press E to Dock` when speed < 50
   - `Reduce Speed to Dock` when speed is too high
3. Press `E` while dockable and verify station menu opens, world pauses, and station info is shown.
4. Click `Undock` and verify station menu closes, world unpauses, and ship respawns at station undock position.
5. Fly to Anchor east gate and verify prompt `Press E to Warp to Ferrite Belt`.
6. Press `E` at gate and verify warp sequence:
   - Speed-line effect (~0.5s)
   - Fade to black (~0.3s)
   - Destination sector load
   - Fade from black (~0.3s)
7. Confirm arrival in Ferrite Belt with sector content populated from data.
8. From Ferrite Belt, warp east to Red Corsair Run and confirm successful transition.
9. In Red Corsair Run, approach east locked gate and verify prompt/toast requirement (`Requires galaxy_2`) and no warp occurs.
10. Fly toward sector edge away from gate gaps and verify toast `Sector Boundary - No Gate Here` near boundary.
11. Press `M` to open galaxy map, verify all sectors/connections render with current sector highlighted.
12. Click multiple sector nodes and verify detail panel updates (name, threat, hazards, station info).
13. Verify undiscovered sectors show `?` and dim styling.
14. Verify locked cross-galaxy links render dashed with lock labels.
15. Close map with `M`, `Tab`, and `Esc` (each should work).

## Phase 04 Manual Checklist (Scanning + Mining + Hazards)

1. Start a new game and enter `Anchor Station`.
2. Press `Q` and confirm:
   - expanding scanner ring appears around the ship
   - nearby resource nodes display temporary reveal/highlight markers
   - scanner cooldown indicator near minimap begins recharging.
3. Attempt scanning again immediately and confirm cooldown messaging/lockout behavior.
4. Fly within ~200 px of a resource node, face it, and hold `F`.
5. Confirm mining beam + spark effects appear and node progress bar fills over extraction time.
6. Rotate away or drift out of range mid-extraction and confirm `Mining Interrupted` toast and reset progress.
7. Complete a full extraction and confirm:
   - node disappears
   - loot crate spawns at node location
   - extraction toast appears (`+[quantity] [Resource Name]`).
8. Fly through spawned loot crate and confirm cargo increases and pickup toasts appear.
9. Fill cargo near capacity, mine/pickup more, and confirm:
   - partial acceptance when nearly full
   - `Cargo Full!` and lost-units warning messaging when overflow occurs.
10. In Ferrite Belt, confirm asteroid fields spawn with physical asteroid collision blockers and embedded mineable nodes.
11. Scan in Ferrite/Red sectors and confirm hidden loot crates become visible temporarily.
12. Approach anomaly points before scanning and confirm prompt requires scanning.
13. Scan anomaly, then press `E` and confirm one-time stub reward behavior.
14. Enter hazard zones and confirm entry/exit toasts:
   - Debris Field: contact with debris chunks causes hull damage
   - Radiation Cloud: shield recharge slows noticeably
   - Ion Storm (if placed/tested): steering noise and minimap jitter are visible
   - Minefield (if placed/tested): mine arms/explodes with damage when close
   - Gravity Well (if placed/tested): ship is pulled toward zone center
   - EMP Zone (if placed/tested): shield recharge stops and utility warning appears.
15. Dock at station and verify cargo manifest panel lists resource name, quantity, and value per unit.

## Phase 05 Manual Checklist (Combat + Death + Wreck)

1. Start a new game and travel to a sector containing enemy patrols (`Anchor Station` outskirts, `Ferrite Belt`, or `Red Corsair Run`).
2. Right-click (`fire_primary`) and verify Pulse Laser projectiles fire in ship-facing direction.
3. Confirm player projectiles damage enemy shields first, then hull.
4. Verify enemies patrol until the player enters aggro range, then transition to chase/attack behavior.
5. Pull enemies far from their patrol origin and verify they disengage and return (`lost interest` toast appears).
6. Press `Tab` to cycle nearby targets and confirm target brackets move between enemies.
7. Confirm target panel updates live with target name, faction, hull, shield, and distance.
8. Confirm lead indicator appears for active target and shifts with target motion.
9. Let enemies fire from off-screen and verify incoming warning appears near HUD edge.
10. Verify shield absorbs incoming damage, then hull takes remaining damage.
11. After taking damage, confirm shield recharge waits for delay before resuming.
12. Deplete shield and confirm `Shield Down!` toast appears.
13. Destroy enemies and confirm explosion + loot crate drops (1–3 crates depending on archetype data).
14. Collect drops and confirm credits/material pickups are applied.
15. Allow player hull to reach 0 and verify:
   - game over overlay opens
   - repair fee is deducted
   - cargo hold is cleared.
16. Continue from game over and confirm respawn at last docked station sector with full hull/shield.
17. Return to death sector and confirm wreck beacon appears on minimap/world.
18. Interact with wreck beacon (`E`) and verify recovery panel opens.
19. Recover cargo and confirm capacity limits are respected (partial recovery if hold is full).
20. Die again before recovering previous wreck and confirm `Previous wreck destroyed` toast behavior.

## Deferred Runtime Checks (Future Phases)
- Full mission board logic and station service implementation.
- Economy/refinery/workshop functionality beyond menu shell.
- Secondary weapon content, advanced weapon families, and boss-specific behavior patterns.
- Persistent save/load implementation beyond stubs.
