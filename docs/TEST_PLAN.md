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

## Phase 06 Manual Checklist (Station Economy Loop)

1. Start a new game, mine at least 5 `Common Ore`, then dock at `Anchor Station`.
2. Confirm the station menu shows top tabs and station header with:
   - station name
   - economy type
   - live credits in the top-right.
3. Open `Market` tab and verify `Sell Cargo` lists each cargo item with quantity, per-unit price, and total.
4. Sell one listed stack and confirm:
   - cargo quantity drops
   - credits increase
   - success toast appears.
5. Click `Sell All` and confirm remaining sellable cargo converts to credits.
6. Re-enter with mixed cargo and click `Quick Sell All`; confirm mission/story items are not sold.
7. In `Market` -> `Buy Goods`, buy commodities using `Buy 1`, `Buy 5`, `Buy 10`, and `Buy Max`; confirm stock/credits/cargo update each time.
8. Fly to `Ferrite Belt Outpost`, dock, and compare market prices against Anchor Station for the same item; confirm visible price variation.
9. At `Ferrite Belt Outpost`, verify limited services behavior:
   - `Market` and `Repair` available
   - `Refinery` and `Workshop` unavailable/disabled.
10. Return to `Anchor Station` and open `Refinery` tab.
11. Refine `Common Ore x5 -> Metal Plates x2`; confirm ore is consumed and plates are added.
12. Verify recipe rows gray out/disable when inputs are missing.
13. Open `Workshop` tab and verify `Warp Stabilizer Mk I` and `Long-Range Warp Drive` recipes are listed.
14. Confirm missing requirements render as `REQUIREMENTS NOT MET` with clear red feedback.
15. Open `Repair` tab with damaged hull and confirm:
    - cost is `2 credits` per missing hull point
    - full repair deducts credits and restores hull instantly.
16. With full hull, confirm repair tab reports `Ship in good condition`.
17. Hover market/refinery/workshop item labels and confirm tooltip panel:
    - shows name and description
    - includes trade info (base value / best sold at)
    - follows mouse and remains on-screen.
18. Verify station cargo review panel updates live after every sell, buy, refine, and craft attempt.
19. In-flight, verify simplified cargo panel is visible and updates when cargo changes.
20. While docked, open the `Galaxy Map` tab and press `Open Galaxy Map`; close map and confirm return to station menu with world still paused.

## Phase 07 Manual Checklist (Upgrades, Modules, Galaxy Expansion)

1. Start a new game, dock at `Anchor Station`, and open `Upgrades`.
2. Verify six upgrade paths are listed (`Hull`, `Shield`, `Engine`, `Cargo`, `Scanner`, `Mining`) with tier progression and costs.
3. Purchase `Hull Plating Mk I` (after meeting requirements) and confirm max hull increases immediately.
4. Confirm upgrade purchases only allow the next tier (cannot skip directly to Mk III).
5. In module sections, buy and equip `Kinetic Cannon`; undock and verify:
   - primary shots are slower/heavier than Pulse Laser
   - damage and cadence differ from Pulse Laser baseline.
6. Buy and equip `Railgun`; verify very high damage, slow cadence, and longer projectile range.
7. Buy and equip `Missile Pod` secondary; press `R` and confirm homing behavior + reload cycle.
8. Buy and equip `EMP Charge` secondary; fire and confirm AoE/EMP behavior on target groups.
9. Buy and equip `Tractor Beam`; verify nearby loot crates are pulled toward the ship.
10. Buy and equip `Repair Drone`; verify orbiting drone visual appears and hull regeneration is active.
11. Buy and equip `Shield Burst`; press `C` and verify shield instantly restores by ~50% with cooldown.
12. Validate power budget line updates when equipping modules (`Power used/capacity`).
13. Attempt to equip an over-budget loadout and verify equip is blocked with a clear reason/tooltip.
14. Validate mass/agility readout updates when equipping heavier modules.
15. Confirm ship handling changes with heavy loadout (reduced acceleration/turn responsiveness).
16. Craft `Warp Stabilizer Mk I` in workshop and verify:
   - unlock toast appears for Galaxy 2
   - brief screen flash appears
   - Red Corsair Run -> Relay Market gate becomes usable.
17. Warp into `Relay Market`, `Storm Fields`, and `Drone Foundry` and verify populated content (resources, hazards, patrols).
18. Craft `Long-Range Warp Drive` and verify Galaxy 3 unlock feedback.
19. Warp through `Drone Foundry` -> `Archive Gate`, then visit `Silent Orbit` and `Core Bastion`.
20. Verify all Galaxy 3 sectors load with expected hazards/resources and alien patrol archetypes.
21. Confirm loadout and upgrades persist across sector transitions and repeated docking/undocking.
22. Hover module entries in station menu and verify tooltip includes current vs candidate comparison context.

## Phase 08 Manual Checklist (Stability, Save/Load, Settings, Tutorial Polish)

1. Launch the project and confirm Main Menu loads without script/resource errors.
2. Verify `Continue` is disabled if no save files exist; create a save and verify it becomes enabled.
3. Start a new game, dock once, and confirm autosave trigger occurs (toast + `user://saves/slot_1.json` created).
4. While docked, open station menu and click `Save`; confirm manual save success toast.
5. Pause while docked, click `Save`, and confirm pause-save path succeeds.
6. Pause while undocked, click `Save`, and confirm warning appears (manual save blocked while undocked).
7. Quit to Main Menu, click `Continue`, and verify load resumes from last docked station sector.
8. Verify credits, cargo, upgrades, equipped modules, missions, discovered sectors, and wreck state are preserved after load.
9. Trigger a mission objective completion and confirm autosave occurs on mission complete.
10. Trigger a mission turn-in and confirm autosave occurs after rewards are applied.
11. Craft a galaxy unlock item and confirm unlock feedback plus autosave on unlock.
12. Corrupt a slot JSON manually and attempt load; confirm `Save corrupted` toast and no crash.
13. Open `Settings` from Main Menu; adjust Master/Music/SFX sliders and close.
14. Relaunch game and verify audio settings persist from `user://settings.json`.
15. In settings Display tab, toggle Fullscreen and VSync and confirm values persist after restart.
16. Set Screen Shake to `0%`, enter combat, and verify camera shake is effectively disabled.
17. Set Screen Shake back to `100%`, re-enter combat, and verify shake intensity returns.
18. Start/accept `First Steps` and verify tutorial overlay appears at center-bottom with step counter.
19. Complete tutorial steps 1–8 (movement/boost/scan/mine/loot/dock) and confirm auto-advance behavior.
20. At tutorial step 9, verify Market tab highlight appears in station menu and selling cargo advances tutorial.
21. Press `Esc` during tutorial and verify skip flow works and tutorial flag persists.
22. In-flight HUD validation:
   - hull/shield/boost bars animate smoothly
   - hull critical state pulses with vignette
   - cargo-full pulses orange
   - waypoint arrow + distance text point to off-screen objectives.
23. Destroy enemies and verify floating `+credits` kill-confirmed text appears near death location.
24. Verify exploration music transitions to combat on aggro and returns to exploration after combat cool-down.
25. Validate all 9 sectors still load and remain traversable with no regressions to docking, warp flow, missions, or bosses.

## Deferred Runtime Checks (Future Phases)
- Full mission board logic and station service implementation.
- Upgrade/module purchasing and equipment compare flows.
- Secondary weapon content, advanced weapon families, and boss-specific behavior patterns.
- Persistent save/load implementation beyond stubs.
