# Optional wandering Pokémon randomiser interface

Untamed-Advanced's Overworld Wild Encounters (OWE) do **not** use
`encounter.species`; they generate their own species, sprite, and battle foe.

When generating an **ordinary wild land/water OWE**, Untamed calls the shared
Gen1Recomp mod hook `untamed.owe.species` before choosing its sprite or
constructing the battle Pokémon. Other mods may use it without modifying
Untamed's actor tables.

Hook contract (Lua):

```lua
mod.hooks:wrap("untamed.owe.species", function(next, encounter, context)
    local original = next(encounter, context)
    -- original.species = native internal numeric species ID
    -- original.level   = selected native level
    -- context.source   = "untamed_advanced"
    -- context.mapId / terrain ("land" or "water") / x / y
    -- Return a fresh table with numeric species, retain the level.
    return original
end)
```

Untamed validates the returned replacement: integer internal species ID,
National Dex number 1–386, supported sprite. Invalid results revert to the
authored species without cancelling the spawn. The visible sprite, cry,
gender/shiny assessment, and eventual battle all use the **same final
internal species ID**.

Roamers, Feebas special spawns, outbreaks, and manually placed actors bypass
this hook. Encounter-chain popups and counts follow the **actual visible/battled species** (for example, Feraligatr rather than the native Rattata slot it replaces). The original authored **native** slot is stored separately, including when
Modern Spawns supplies a different species before this hook is called. It
preserves the increased chance to spawn that source in later encounters.
When a chain forces this slot, Untamed keeps the actual chained species
without redrawing the Modern Spawns roster or rerolling Nuzlocke's species
hook; the normal chain-shiny odds then apply. Followers are unaffected.

The hook is optional. Untamed behaves as before when nobody subscribes.
The corresponding [Nuzlocke v3.0.0-BETA](https://github.com/Deluxe0111/nuzlocke) hook connects this to **Random Wild** using the normal Nuzlocke Randomiser seed, Gen 3 species pool, and balance settings. Integration by **Deluxe0111**.
Both mod branches must be installed to enable the feature.

## In-game tests

- With both updated mods and Random Wild ON, ordinary wandering species
  should change. Their battle species must match the sprite.
- Repeat with fixed seed, reload, and different spawn locations to confirm
  mappings are stable for the same original species/map/land-water type.
- With Random Wild OFF, only native wandering Pokémon should spawn.
- Verify normal wild land/water encounters, fishing, trainer fights and
  player followers remain on their existing independent paths.
- Test a roamer, Feebas tile/outbreak where available: special species
  must remain native.
- Defeat repeated randomised wandering Pokémon (e.g. Feraligatr from a Rattata slot) and confirm the chain popup names **Feraligatr**, the repeat-spawn bonus works, and there are no wrong-species or crash reports.
- Repeat on FireRed, LeafGreen, Ruby, Sapphire, and Emerald with a
  disposable save.

These checks require a running ROM; the repo's headless Lua tests cover
the hook fallback/sprite-eligibility contract, not the renderer.

## Modern Spawns integration

Untamed's ordinary land/water OWE picker is independent of the engine's
`encounter.species` hooks. If Modern Spawns is installed, active and exposes
API v2 `drawFor`, Untamed calls `drawFor(mapId, "land"|"water")` **once
per ordinary visible spawn**. It uses only the picked species, preserving
the original engine's slot probabilities and level ranges. A fixed number
of native slots does not limit COMPLETE mode's potential species roster.

The provider's canonical Pokémon names are translated to native internal
engine slots via `Pokemon.speciesFromName`. Missing APIs, invalid tables,
unregistered Pokémon and artwork without an Untamed atlas sheet fail back
to the original native source slot. Non-ordinary OWE categories are unchanged.
Nuzlocke's optional `untamed.owe.species` hook still runs after this draw.

See [OWE Modern Spawns details](OWE_MODERN_SPAWNS.md).

## Shiny rate integration

Ordinary generated wandering Pokémon also offer an optional
`untamed.owe.shiny` hook **after the native personality and chain-shiny
decisions**, but before the sprite and battle Pokémon are finalised.

```lua
mod.hooks:wrap("untamed.owe.shiny", function(next, source, ctx)
    local mon = next(source, ctx)
    -- source: { species, level, personality, shiny }
    -- ctx: { source="untamed_advanced", mapId, terrain, x, y,
    --        makeShiny=function(personality) }
    -- Return a copy with personality=ctx.makeShiny(mon.personality)
    -- and shiny=true, or return the original.
    return mon
end)
```

Only valid shiny personalities with the original low 16 bits are accepted;
changing species, level, or an already naturally/chain-shiny Pokémon is
rejected. The converted personality is used for the overworld colour,
shiny sparkle, non-despawn handling, and the later wild battle/capture.
No additional shiny roll is made by Untamed if no provider subscribes.

**Nuzlocke v3.0.0-BETA:** `CLAUSES → SHINY RATE` affects regular
wandering Pokémon as well as native wild battles, even if Random Wild is
OFF. The companion Nuzlocke mod records the spawn decision so it cannot
reroll the same Pokémon at battle start. Roamers, Feebas, outbreaks,
scripted actors and player followers are excluded. Native chaining still
offers its own bonus, so chain-shiny odds can exceed the configured base
rate. Both updated mods must be installed for visible shiny spawns.
