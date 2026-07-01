# Recent Changes Summary (Last 7 Commits)

Here is a simple summary of the last 7 updates made to the game:

* **Commit 1: Tunnel Spawning Update (`c2c01e4`)**
  * Tunnels now spawn every 3,000 meters.
  * If a mission or event is active, the tunnel waits in a queue.
  * The tunnel spawns 300 meters after the mission or event ends.
  * Fixed road glitching/warping when events start or end.

* **Commit 2: Coin Adjustments (`0366cc7`)**
  * Coins spawn half as often (larger gaps between them).
  * Coins are 30% smaller in scale.
  * Coins hover higher above the road so they do not clip.
  * Coin point rewards are halved for all colors.

* **Commit 3: Empty Cargo Start (`b1758f6`)**
  * Removed the starting glass cargo item so the truck container begins completely empty.

* **Commit 4: Tow Mission Stability (`bc0083b`)**
  * Towed cars spawn at a relaxed distance so they do not yank or flip.
  * Towed car speed matches the truck speed instantly on spawn.

* **Commit 5: Opponent Lift System (`dce7b2a`)**
  * Added a separate elevator for the opponent car during races.
  * Elevators now support lifting both vehicles at the same time.

* **Commit 6: Crusher Gauntlet Improvements (`eaedaf6`)**
  * Road stays flat until the player is fully past the crusher area to prevent rendering glitches.
  * Better screen shake and cleaner hazard removal.

* **Commit 7: Biome Swap & Joint Fixes (`ba7da96`)**
  * Disabled collision on old parts during land/water swaps to prevent physics explosions.
  * Fixed connection joints and kept towed cars attached after swapping.
