# Terrain Generation Models (State-1)

This document captures the parameters and mathematical formulas used to procedurally generate the game's road height and land topography in `road.gd`.

## Preset Options Choice
You can select the active terrain style using the **`terrain_type`** property dropdown in the Godot Inspector:
* **`RUGGED`**: The classic, high-difficulty driving experience. Sets preset amplitudes for all seven wave functions.
* **`SMOOTH`**: A rolling, undulating roadway with pleasant hills. Avoids sharp tire-rattling spikes and deep cliffs.
* **`BOTH`**: Dynamic shifting mode. The road starts completely smooth, scaling up in maximum difficulty the further you travel. Additionally, it shifts back and forth between smooth sections and rugged sections periodically based on traveled distance.
* **`CUSTOM`**: Actively selected if you manually edit any of the slider values, allowing custom topography profiles.

Selecting `RUGGED` or `SMOOTH` automatically overwrites the wave amplitudes listed below.

---

## Global Multiplier
The amplitude of all terrain features is scaled dynamically by the multiplier `mult`:
```gdscript
var mult = hill_amplitude_multiplier * get_convoy_multiplier(x)
```
- **`hill_amplitude_multiplier`**: Baseline slider/config for hill intensity.
- **`get_convoy_multiplier(x)`**: Dynamic flattening applied near convoys (drops amplitude to `0.15` to smooth out driving).

---

## Synthesis Formula
The final baseline height (before transitions or flattening zones) is calculated from a unified mathematical model:
```gdscript
var height = 42.0 + (mountains + long_hills + medium_waves + smooth_spikes + sharp_dips + lil_spikes + small_bumps)
```

The component parts and their defaults by preset are:

| Component Name | Default (Rugged) | Default (Smooth) | Wave Function / Frequency | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Mountains** | `220.0` | `130.0` | `sin(x * 0.0003)` | Broad long-range elevation rises. |
| **Long Hills** | `85.0` | `60.0` | `sin(x * 0.0007)` | Spaced-out rolling hills. |
| **Medium Waves** | `50.0` | `35.0` | `cos(x * 0.0013)` | Medium undulations. |
| **Smooth Spikes** | `65.0` | `15.0` | `sin(x * 0.0060)` | Rapid steep climbs. |
| **Sharp Dips** | `25.0` | `8.0` | `sin(x * 0.0030)` | Ground dips. |
| **Lil' Spikes** | `18.0` | `0.0` | `sin(x * 0.0220)` | Micro tire vibration spikes. |
| **Small Bumps** | `12.0` | `6.0` | `sin(x * 0.0080)` | Subtle surface noise. |

---

## Dynamic Both Mode (TerrainType.BOTH)
When `BOTH` mode is active, the wave amplitudes at any given coordinate `x` are interpolated dynamically:
```gdscript
active_amplitude = lerp(smooth_default, rugged_default, blend)
```
The dynamic blend factor `blend` is defined by:
1. **Difficulty Ramping Envelope (`max_ruggedness`):**
   Starts at `0.0` (fully smooth) for the first 1,000 pixels (~50m) and scales up quickly to `1.0` (rugged potential unlocked) over the next 6,000 pixels (~300m total).
2. **Periodic Cycle (`raw_shift`):**
   A low-frequency sine wave based on distance `x` (wavelength of ~25,000 pixels / 1.25km). The shift is biased so that the rugged terrain stays fully active for ~50% of the cycle, transitions smoothly for ~21%, and leaves a quick smooth breather section for ~29% of the cycle.
3. **Synthesis:**
   `blend = raw_shift * max_ruggedness`

---

## Procedural Physics Bridges
To add physical and aesthetic variety, the terrain system periodically cuts the road to spawn hanging, physics-jointed bridges:
* **Spawning Criteria:** Spawns deterministically in chunks where `abs(chunk_index) % 8 == 5`, excluding water biomes, start buffer zones, or chunks with tunnels/elevators.
* **Canyon Profile:** Shipped as a smooth parabolic canyon of width `700` pixels:
  $$\text{depth}(x) = \text{base\_height} + 260.0 \times \left( \frac{\cos\left(\frac{x - x_{center}}{350.0} \pi\right) + 1.0}{2} \right)$$
* **Plank Bridge System:**
  - Spawns a chain of **10 RigidBody2D planks** (with wooden Polygon2D aesthetics and borders) linked using **PinJoint2D** connectors.
  - The left-most and right-most joints anchor the bridge to the main `StaticBody2D` road.
  - The asphalt visual lines (`Line2D` and `Line2D2`) are split precisely around the bridge gap so they stop at the cliffs, keeping the bridge looking natural and suspended.
