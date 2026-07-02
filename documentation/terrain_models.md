# Terrain Generation Models (State-1)

This document captures the parameters and mathematical formulas used to procedurally generate the game's road height and land topography in `road.gd`.

## Preset Options Choice
You can select the active terrain style using the **`terrain_type`** property dropdown in the Godot Inspector:
* **`RUGGED`**: The classic, high-difficulty driving experience. Sets preset amplitudes for all seven wave functions.
* **`SMOOTH`**: A rolling, undulating roadway with pleasant hills. Avoids sharp tire-rattling spikes and deep cliffs.
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
| **Smooth Spikes** | `65.0` | `15.0` | `sin(x * 0.0060)` | Rapid steep climbs (gentle curves in Smooth). |
| **Sharp Dips** | `25.0` | `8.0` | `sin(x * 0.0030)` | Ground dips (very mild in Smooth). |
| **Lil' Spikes** | `18.0` | `0.0` | `sin(x * 0.0220)` | Micro tire vibration spikes (completely removed in Smooth). |
| **Small Bumps** | `12.0` | `6.0` | `sin(x * 0.0080)` | Subtle surface noise. |
