## GameState — lightweight autoload singleton.
## Persists data that must survive scene transitions (e.g. the retry seed).
extends Node

## 0 = pick random seed on next game load.
## Any other value = use that specific seed.
var pending_road_seed: int = 0
