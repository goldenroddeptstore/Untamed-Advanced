# Overworld Wild Encounter Spawn Tuning

Untamed Advanced's expanded wild encounter density is independent of Pokémon species selection, Modern Spawns, the Nuzlocke randomiser, and Emerald Rogue chaining.

## Options (mod menu)

| Option | Choices | Default | Effect |
|---|---|---|---|
| Wild population | Classic (4), Balanced (6), Lively (8), Busy (10) | Lively (8) | Simultaneously generated wild Pokémon, while the physical actor pool stays 10 |
| Wild proximity | Classic, Nearby, Close | Nearby | Controls how near valid candidate tiles are preferred |
| Wild frequency | Classic, Faster, Fastest | Faster | Spawn retries, refill and replacement pace |

These settings can be changed while playing. Reducing the population trims the oldest eligible generated actors. Special/manual actors and generated actors with no-despawn protection (notably shiny OWEs) are not forcibly deleted. Protected encounters can temporarily leave the active count above the chosen target until they resolve naturally.

## Timing

Values are game frames at 60 FPS; actual success depends on the terrain, map, movement and encounter restrictions.

| Frequency | Initial / failed-attempt delay | Additional delay per generated actor | Full-population replacement |
|---|---:|---:|---:|
| Classic | 30 | 30 | 240 |
| Faster (default) | 15 | 10 | 90 |
| Fastest | 6 | 4 | 45 |

Lures retain their existing faster behaviour. Replacement still favours the oldest eligible generated actor; special/manual and no-despawn actors are excluded.

## Tile placement

- **Classic:** original single random candidate, original land minimum 1 tile / water minimum 3 tiles.
- **Nearby (default):** up to 8 candidate tiles per spawn opportunity, biased toward the player (typically within +/-5 horizontal and +/-3 vertical tiles), with outer-field candidates for variety. Water minimum reduced to 2 tiles.
- **Close:** up to 8 candidate tiles; first 6 prefer a roughly +/-3-by-2 area, then check the wider field if needed. Water minimum 2 tiles.
- All modes still require the correct encounter terrain, valid elevation, no collision, no overlapping NPC / actor, and a point inside the current map. A spawn cannot occupy the player's tile.
- Eight attempts is a fixed upper bound for performance. No per-frame full-map scan is performed.

The native encounter table's slot count, weights, levels, rare species, forms, scripting restrictions and battle identity remain unchanged. An expanded species roster changes **which Pokémon** is selected; these controls change **how many, where, and when**.

## Test checklist

1. With FireRed and Emerald, compare each frequency preset on a grassy route and while surfing. Check that new Pokémon appear while stationary.
2. Change population live between 4, 6, 8 and 10. Check the actor count and confirm manual/scripted spawns and protected shiny Pokémon survive reductions.
3. With proximity set to Close, ensure valid spawn positions near the player on Route 1, constrained grass patches, corners, and narrow corridors. Compare Classic to verify legacy distribution.
4. Check collisions: NPCs, player/follower, trees, ledges, water/land transitions, map borders.
5. With Modern Spawns COMPLETE and Nuzlocke Random Wild on/off, compare the visible species with the battle/capture species and check chains / shiny continuity. Confirm probabilities and levels are not altered.
6. Measure FPS in the Busy + Fastest combination, especially on an NPC-dense map, and try slower settings if needed.

Smoke test: `lua tests/owe_spawn_tuning_smoke.lua`. This test is headless and does not replace on-ROM validation.
