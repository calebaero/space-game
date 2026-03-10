# Changelog — Space Explorer

## Phase 05
- Added data-driven combat catalogs:
  - `data/items/weapons.tres` for player/enemy weapon definitions (including Pulse Laser baseline).
  - `data/enemies/enemy_archetypes.tres` for four enemy archetypes with behavior and loot tables.
- Extended sector schema/content loading with `enemy_patrols` arrays and populated all Galaxy 1 sectors with patrol definitions.
- Implemented reusable `Projectile` scene/script with range/lifetime despawn, damage application, asteroid collision, and gravity-well influence.
- Implemented reusable enemy stack:
  - `EnemyShip` with inertial movement, shields/hull, firing, explosions, and loot drops.
  - `EnemyAIController` state machine (`PATROL`, `ALERT`, `CHASE`, `ATTACK`, `FLEE`, `LEASH_RETURN`) with leash break-off behavior.
- Added `Damageable` core component and integrated shield recharge delay/recharge behavior for enemies.
- Upgraded player combat loop:
  - Right-click primary firing from equipped loadout (Pulse Laser default).
  - Secondary fire stub behavior for empty slot.
  - Soft target lock + Tab cycling + lead indicator.
  - Incoming hostile fire warning and ion-storm targeting disruption.
  - Shield/hull hit feedback hooks and death signal wiring.
- Extended `GameStateManager` with:
  - Equipped weapon helpers.
  - Shield recharge delay handling.
  - Player damage/death signals.
  - Wreck beacon state helpers.
  - Cargo clear helper and fixed `remove_cargo()` flow bug.
- Implemented player death penalty flow in `GameRoot`:
  - Death explosion.
  - Repair fee (10% credits, min 50).
  - Cargo transfer into wreck snapshot with nearby-enemy loss chance (10–30%).
  - Game Over overlay + respawn at last docked station sector with full hull/shield.
- Added wreck recovery loop:
  - `WreckBeacon` world entity with minimap marker.
  - `WreckRecoveryPanel` UI to recover cargo subject to capacity.
  - One-active-wreck behavior with previous-wreck destruction toast.
- Added boss framework shell:
  - `BossHealthBar` UI with intro text and phase-capable API.
  - `BossEncounterTrigger` reusable trigger scaffold.
- Updated HUD with target panel fields, target lead marker, incoming warning presentation, low-hull pulse, and hull-hit screen flash.
- Updated minimap overlays to include wreck beacon markers.

## Phase 04
- Added data-driven resource catalog (`data/items/resources.tres`) with 6 resource families, node tiers, and hazard definitions.
- Expanded sector schema/population for resource nodes, asteroid fields, hazard zones, and hidden loot crates.
- Implemented `ResourceNode` mining targets with scan highlight, tier/yield data, unstable burst behavior, and loot spawn on extraction.
- Implemented scanner pulse (`Q`) with cooldown/range from `GameStateManager`, expanding ring VFX, and reveal hooks for nodes/anomalies/hidden loot.
- Implemented mining loop (`F` hold) with range + facing checks, beam/spark visuals, progress tracking, interruption handling, and extraction to loot crates.
- Reworked cargo model in `GameStateManager` to quantity stacks and capacity-aware add/remove checks, including partial overflow messaging and relic inventory separation.
- Added `LootCrate` pickup flow with drift, despawn timer, content processing, and AudioManager pickup SFX stub call.
- Added `AsteroidField` generation with collision asteroids, subtle rotation, and embedded mineable resource nodes.
- Expanded `AnomalyPoint` to require scanning before interaction, support typed stubs, and enforce single-use per sector visit.
- Added `HazardZone` with 6 configurable hazard archetypes (debris, radiation, ion storm, minefield, gravity well, EMP) and entry/exit toasts.
- Updated HUD with minimap overlays (resources/loot/anomalies/hazards) and scanner cooldown indicator.
- Updated station menu shell to show a live cargo manifest list with per-unit value display.

## Phase 03
- Added data-driven sector interaction layer with reusable `Planet`, `SpaceStation`, `WarpGate`, and `AnomalyPoint` scenes.
- Expanded sector definition schema to include galaxy tint, station payload, planet arrays, warp gate arrays, and anomaly stubs.
- Implemented `SectorPopulator` for content instancing from sector data resources.
- Added docking interactions and `StationMenu` shell (dock, autosave stub trigger, undock flow).
- Added warp gate interactions and transition presentation (speed-lines + fade) with sector handoff.
- Added `GalaxyMapScreen` overlay with sector nodes, connections, lock indicators, detail panel, and discovery-aware presentation.
- Reworked sector boundaries to leave gate gaps and added boundary warning interaction toasts.

## Phase 02
- Added `PlayerShip` with inertial top-down flight: momentum steering, thrust, braking, boost, rotational assist, damping, and soft max-speed handling.
- Added smooth ship camera behavior with velocity lead, speed-based zoom, and trauma-based shake support.
- Added persistent `HUD` scene with hull/shield/boost bars, speed, cargo, credits, mission placeholder, target/cooldown placeholders, and velocity vector indicator.
- Upgraded `UIManager` to queue and fade toasts; integrated startup sector welcome toast.
- Updated sector flow so `GameRoot` spawns the player into `SectorScene` and binds HUD to the active ship.
- Added static collision boundaries for the 8000×8000 sector play space and control-zone damping stubs near station/planet anchors.

## Phase 01
- Added initial project architecture for main menu, game root, autoload manager shell, and sector loading flow.
- Implemented placeholder data resources for 3 galaxies and 9 sectors.
- Added minimal `SectorScene`, `PauseMenu`, and placeholder planet/station visuals.
- Registered autoload scripts and core project settings in `project.godot`.

## Phase 00
- Initial project bootstrap.
