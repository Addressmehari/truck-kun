# Biome transitions and Tunnel Adjustments (Last 4 Commits Summary)

Here is a simple summary of the last 4 commits implementing and refining the tunnel biome transitions:

* **Commit 1: Biome Transitions & Towing Joint Fixes (`48d8620`)**
  * Increased tunnel length to `2000` pixels and added horizontal auto-scaling.
  * Configured the tunnel exit to trigger the `cycle_biome()` event.
  * Cleaned up state-swapping physics collisions to prevent vehicle explosion.
  * Ensured towed vehicles remain properly attached and reconnected during biome swaps.

* **Commit 2: Water Spawning & Next Biome Announcements (`0186807`)**
  * Allowed tunnels to spawn in the water biome.
  * Added a golden HUD alert at the tunnel entrance to announce the upcoming biome (e.g. `NEXT BIOME: SUNSET SILHOUETTE`).
  * Implemented dynamic tunnel spacing between `1500m to 2000m` for the water and silhouette biomes.
  * Set up initial probabilities for cycling biomes (50% Grass, 25% Water, 25% Silhouette).

* **Commit 3: Transition Crash & Spikes Resolution (`0ad49e8`)**
  * Fixed terrain spikes at tunnel entrances/exits by increasing the search influence boundary to `2500` pixels.
  * Resolved the double-trigger and height alignment crash by reordering biome-swap steps (aligning the new vehicle first, then removing the crossed tunnel position).

* **Commit 4: Biome Probability Tuning (`33d2a8b`)**
  * Refined transition weights to favor returning to the main Grass biome ($80\%$ chance) when exiting Sunset Silhouette or Deep Water, keeping the gameplay centered in the primary biome.
