# Recent Commits Summary

This document summarizes the last 10 commits in the repository, focusing on the implementation and stabilization of the **Mystery Box Mini-Event** system, procedural road/house generation fixes, mission system decoupling, and other visual and physics refinements.

---

## Commit Log

| Commit | Date (2026) | Author | Description Summary |
| :--- | :--- | :--- | :--- |
| **`3fed11e`** | Jul 1, 13:25 | addressmehari | crusher landshift fixed |
| **`a0143ca`** | Jul 1, 13:19 | addressmehari | tunnel fixed |
| **`53105bd`** | Jul 1, 13:07 | addressmehari | houses fixed and dialogue box ui updated |
| **`1788da0`** | Jul 1, 12:36 | addressmehari | added cool down and restricted while in race mission |
| **`530cf5a`** | Jul 1, 12:22 | addressmehari | no mystery box spawn in between the mini event and removed boosted velocity for convoy |
| **`52b5515`** | Jul 1, 12:12 | addressmehari | bug fixed |
| **`b050cb3`** | Jul 1, 12:09 | addressmehari | mystery boxes triggers mini events |
| **`68fbee1`** | Jul 1, 12:03 | addressmehari | destroy animation added |
| **`b686e03`** | Jul 1, 11:57 | addressmehari | cheat code added "mystery" |
| **`ce0dfaf`** | Jul 1, 11:48 | addressmehari | added graphics for the cube |

---

## Detailed Commit Summaries

### 1. `3fed11e` — crusher landshift fixed
* **File(s) Modified:** `ui/crusher_progress_bar.gd`
* **Changes:** Removed the `_road.call("regenerate_runtime_chunks")` call when resetting flat road coordinates at the end of the Crusher Gauntlet event.
* **Impact:** Prevents the road mesh and collision geometry from suddenly morphing underneath the player or active towed vehicles/enemies, ensuring a smooth transition back to the default hilly landscape without physics glitches.

### 2. `a0143ca` — tunnel fixed
* **File(s) Modified:** `road/road.gd`
* **Changes:**
  * Updated initial tunnel spawning distance target (`next_planned_tunnel_x`) from `90000.0` (3000m) to `30000.0` (1000m).
  * Adjusted `get_next_tunnel_spacing()` to default to `30000.0` (1000m) between tunnels.
  * Scaled biome-specific tunnel spacing (water and silhouette biomes) to range from 1000m to 1500m (`randf_range(30000.0, 45000.0)`).
* **Impact:** Tunnels now spawn more frequently (every 1000m), making biome transitions faster and keeping gameplay fresh.

### 3. `53105bd` — houses fixed and dialogue box ui updated
* **File(s) Modified:** `road/road.gd`, `road/house.gd`, `ui/dialogue_box.gd`
* **Changes:**
  * Resolved a PRNG seed correlation issue where only racing garages were spawning. Switched the seed initialization from consecutive numeric values to non-linear string-based hashes (e.g. `hash(str(chunk_index) + "_" + str(road_seed) + "_housetype")`).
  * Decoupled the delivery mission from the race event: accepting a delivery contract now only spawns the crates for transport, without initiating an opponent car, locking controls, or starting a countdown.
  * Created a dedicated `[ DELIVERY COMPLETED ]` dialogue screen instead of the checkered flag "Race Finished" dialog.
  * Updated the dialogue box drawing style with custom neon green and amber glowing borders for delivery success.

### 4. `1788da0` — added cool down and restricted while in race mission
* **File(s) Modified:** `obstacles/coin_spawner.gd`, `road/road.gd`
* **Changes:**
  * Added a randomized spawn cooldown (**25.0s to 35.0s**) for mystery boxes after a mini-event ends to prevent continuous events.
  * Added an `is_racing_active` check to `is_event_active()`, suppressing mystery box spawns or cheat code manual summoning during active racing mini-missions.

### 5. `530cf5a` — no mystery box spawn in between the mini event and removed boosted velocity for convoy
* **File(s) Modified:** `road/road.gd`, `truck/truck.gd`
* **Changes:**
  * Added `is_convoy_active` checks to `is_event_active()` inside `road.gd` to prevent mystery box spawning during active convoy combat sequences.
  * Removed the reward speed boost at the end of the convoy event in `truck.gd` so the player vehicle stays at normal speeds once control is returned.

### 6. `52b5515` — bug fixed
* **Changes:** Minor bug fixes, script warnings cleanup, and syntax validation.

### 7. `b050cb3` — mystery boxes triggers mini events
* **File(s) Modified:** `obstacles/mystery_box.gd`
* **Changes:** Integrated mystery boxes into the event dispatcher. Upon collection, the box randomly triggers either the **Crusher Gauntlet** or the **Convoy** mini-event using `call_deferred` to avoid physics stack overflows during road chunk regeneration.

### 8. `68fbee1` — destroy animation added
* **File(s) Modified:** `obstacles/mystery_box.gd`
* **Changes:** Added collection visual effects: triggers screen shake (`dashboard.shake_intensity`), spawns 50 high-velocity exploding particles, and spawns expanding multi-ring shockwaves.

### 9. `b686e03` — cheat code added "mystery"
* **File(s) Modified:** `road/road.gd`
* **Changes:** Added the developer cheat command `"mystery"`. Entering the code spawns a mystery box slightly ahead of the truck for debugging, unless blocked by an active event.

### 10. `ce0dfaf` — added graphics for the cube
* **File(s) Modified:** `obstacles/mystery_box.gd`, `obstacles/mystery_box.tscn`
* **Changes:** Built the procedural 3D spinning wireframe neon cube graphics with central `?` mark support, complete with editor preview visualization using `@tool`.
