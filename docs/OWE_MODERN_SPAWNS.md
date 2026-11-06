# Modern Spawns ↔ Untamed visible wild integration

## Why Route 1 looked limited

Native Gen 3 land tables contain twelve weighted entries but often only two
*unique* species. Untamed previously read those native entries directly.
Modern Spawns can expand the available species **within each original slot**,
especially in COMPLETE mode, without changing the native encounter-table slot count. Untamed's
separate **Wild population** option now determines how many overworld
wild actors can appear simultaneously (4/6/8/10).

The original encounter.species hook does not handle an OWE because Untamed
constructs the visible actor and its later battle Pokémon itself.

## New pick pipeline

For each ordinary land/water OWE when Modern Spawns is active:

1. Read the native land/water area from the loaded map.
2. Query Modern Spawns API v2 `drawFor(mapId, kind)` *once for this spawn*.
3. Require exactly the same number of native slots. Convert provided
   canonical species names to Gen 3 internal slots with
   `Pokemon.speciesFromName` when required.
4. Keep every slot's original probability and min/max levels. If a candidate
   has no verified Untamed overworld atlas artwork, use the original entry.
5. Pick a weighted slot/level using Untamed's existing code and retain the
   **original native species from that slot** separately.
6. Apply Nuzlocke's optional `untamed.owe.species` hook *afterwards*.
   That hook remains the final randomisation authority for ordinary OWEs.
7. Build the sprite, personality/shiny data and eventual battle foe from
   the final accepted species. Wins chain that **visible species**, while
   repeat-spawn lookup uses the original native slot. A chain-forced repeat
   keeps the previously battled species and skips fresh Modern/Nuzlocke
   species draws, allowing Untamed's native chain-shiny roll to run.

If Modern Spawns is absent, disabled, lacks the API, or returns an invalid
table, Untamed keeps its previous native behaviour.

## Mode behaviour

| Modern Spawns mode | Visible OWE behaviour |
|---|---|
| LIMITED | The generated fixed roster for each area |
| EVERY MAP | The current regenerated roster for the map |
| RANDOM | Fresh table for each visible OWE |
| COMPLETE | Fresh per-slot draw from each slot's covered species pool |

Original slot weighting is retained: this is **not** equal-probability drawing
from every Pokémon and does **not** add a new actor for every species.

Scripted events, player followers, roamers, Feebas, outbreaks and forced
chain-source spawns retain their existing separate treatment.

## Manual validation

Use a new disposable FireRed save with Route 1, National Dex Gen 3,
Modern Spawns COMPLETE and Untamed Advanced enabled:

- Collect 30–50 *ordinary* visible wild appearances; look for more than the
  original Route 1 native species, allowing for habitat/level filtering.
- Compare sprite, battle species, captured species and the chain popup.
- Enable Nuzlocke Random Wild and repeat; check the visible species still
  matches the battle/capture, including Paldean IDs and shiny spawns.
- Change Modern Spawns to LIMITED and RANDOM. Re-enter the map, compare
  variety and ensure disabling Modern restores the old native behaviour.
- Confirm levels and relative native slot rarity stay unchanged; set Wild population to Classic (4) to compare the original concurrent spawn count.
- Test grass and surfing on FRLG, then Emerald/Ruby/Sapphire.
- Verify roamers, Feebas, outbreaks, scripted actors and followers remain
  unaffected.
- Run `lua tests/modern_spawns_owe_test.lua` for the adapter fallback checks.

These tests are a development checklist, **not yet proof of in-game
certification**. The native Nuzlocke encounter priority with Modern Spawns
also needs testing across load orders.
