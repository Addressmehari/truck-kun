# Future Expansion Ideas for "Truck-Kun" 🚚💨

This document outlines creative and technical concepts to evolve **Truck-Kun** from a side-scrolling physics prototype into a fully fleshed-out, engaging, and polished game.

---

## 1. Physics & Core Driving Mechanics 🔧

Since the game is heavily physics-based (using jointed `RigidBody2D` nodes for the chassis and trailer, plus rolling wheels), enhancing driving dynamics will add depth to the control loop.

*   **Dynamic Weight Distribution**: 
    *   Currently, slotting crates is visual, but it could dynamically calculate the total cargo mass and update the trailer's center of mass (`mass` and `inertia` of `container_body`).
    *   *Gameplay Impact*: Heavy cargo loaded at the very back of the trailer causes the truck to tip backward or lose steering grip on the front wheel (`tyre-1`).
*   **Active Suspension & Ground Clearance**:
    *   Add a key to adjust suspension stiffness or ride height (e.g., locking springs for high-speed road sections, or loosening them to absorb rough off-road terrain).
*   **Tire Traction & Friction Zones**:
    *   Create different road surfaces in `road.gd` (e.g., mud, ice, tarmac). Update tire friction coefficients dynamically based on collision detection.
    *   *Visual Tip*: Muddy zones can cause tyre spin, throwing up mud-colored particles instead of standard dust.

---

## 2. Cargo & Inventory System Upgrades 📦

The cargo management system (drag-and-drop slots in the trailer) is a unique hook. Expanding this loop adds puzzle-like elements.

*   **Diverse Cargo Types (with unique physical properties)**:
    *   **Fragile Cargo**: Glass crates with a "health" bar. Bumping the truck too hard or flipping the vehicle cracks the glass. If it breaks completely, you lose the reward.
    *   **Volatile/Explosive Cargo**: Fuel barrels that slowly build up a "pressure" meter on bumpy roads. Driving too fast causes them to detonate, blasting the trailer off the chassis.
    *   **Sloshing Liquid Cargo**: Barrels filled with liquid where the center of mass moves back and forth dynamically, pushing/pulling the truck based on momentum.
    *   **Oversized Loose Cargo**: Cargo that does not fit in the 6 slots and must be physically tied down or balanced in an open flatbed, susceptible to falling out.
*   **Tetris-style Packing**:
    *   Instead of fixed slots, crates could have various sizes (1x1, 1x2, 2x2). Players must manually arrange them in a grid inside the trailer to maximize cargo space.

---

## 3. Level Design, Environmental Hazards & Progression 🗺️

To make the 10 levels in `menu.gd` exciting, each should offer a distinct environmental challenge.

*   **Delivery Zones & Waypoints**:
    *   Introduce warehouse delivery zones at the end of the road. Players must park the truck, zoom in (`Gear.PARK`), open the shutter, and manually drag cargo out into the loading bay to complete the level.
*   **Dynamic Hazards**:
    *   **Collapsing Bridges**: Wooden bridges that bend and break if the truck is carrying heavy crates. Players must gain speed to cross them safely.
    *   **Wind Storms**: Strong wind currents that apply forces on the truck, forcing the player to use air-tilting controls (`A`/`D`) to keep the truck balanced in mid-air.
    *   **Steep Cliffs & Cargo Drops**: Potholes and vertical drops where loose cargo can easily fall out of the back if the shutter door isn't closed or is blocked.

---

## 4. Upgrade Shop & Economy 💰

Adding a simple economy loop gives players a strong reason to complete levels and earn money.

*   **The Garage Screen**:
    *   Accessible from the main menu or between levels, allowing players to spend money earned from cargo deliveries on truck parts:
        *   **Engine Upgrades**: Increases `torque_power` to help climb steep mountains.
        *   **Tire Upgrades**: Increases maximum tyre friction/grip to prevent slipping on mud.
        *   **Chassis Stabilization**: Upgrades the air-tilt control (`air_tilt_power`) for better mid-air control.
        *   **Container Extension**: Adds slots to the container body (e.g., upgrading from 6 slots to 8 or 10).
        *   **Cabin Cosmetics**: Custom paint jobs, exhaust pipe styles, and custom cabins.

---

## 5. Juiciness & Polish (Enhancing Game Feel) ✨

The current version features nice engine shakes and dust effects. Here are ways to push the "juice" even further.

*   **Dynamic Headlights & Day/Night Cycle**:
    *   Add a `PointLight2D` headlight to the cabin that casts real-time shadows on the hills.
    *   A simple background color tween simulating sunset and nightfall, forcing players to rely on their headlights.
*   **Deformation & Structural Damage**:
    *   Add dynamic damage mesh deformation or swap textures (dents, scratches) on the cabin and trailer based on high-velocity impact forces.
*   **Interactive Cockpit Dashboard**:
    *   Display a miniature speed needle, engine temperature dial, and glowing gear indicator (P/R/D) inside the cabin window, or as a physical dashboard UI on the HUD.
*   **Audio Atmosphere**:
    *   Pitched engine hums that change based on angular wheel velocity.
    *   Suspension squeaks when landing jumps.
    *   Heavy metal thuds and wooden clanks when crates bump into each other inside the trailer.
