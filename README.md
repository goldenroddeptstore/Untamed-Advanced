# Untamed Advanced

A line-by-line port of pokeemerald-expansion's **Follower Pokémon** and **Overworld Wild Encounters**, plus Emerald Rogue's **encounter chaining**, for FireRed, LeafGreen, Ruby, Sapphire and Emerald on [gen1recomp](https://github.com/bryanthaboi/gen1recomp).

The original encounter rules, battle flow and messages remain, with **configurable wild encounter density**. Choose Classic settings for the original 1:1 spawn pacing and range, or use the livelier defaults.

## What you get

- **A buddy.** Your lead Pokémon walks behind you. Talk to it and it'll tell you how it's feeling.
- **Visible wild Pokémon.** They pop up in grass and water. Some wander, some chase you, some run away. Bump into one to battle it.
- **Chaining.** Beat the same species a few times in a row to make it show up more and boost your shiny odds.
- **A matching world.** Mewtwo, Snorlax, the legendary birds and every other Pokémon already standing on the maps (Kecleon, Latias, the Regis and friends in Emerald) get the same sprites and idle animation as your buddy.

Pretty much everything can be toggled in the mod's options.

## Overworld wild population and spawn settings

Untamed now exposes three independent mod options (all work without Modern Spawns or Nuzlocke):

| Option | Choices | Default |
|---|---|---|
| Wild population | Classic (4), Balanced (6), Lively (8), Busy (10) | Lively (8) |
| Wild proximity | Classic, Nearby, Close | Nearby |
| Wild frequency | Classic, Faster, Fastest | Faster |

**Nearby** favours wild Pokémon within about 5 horizontal / 3 vertical tiles; **Close** favours around 3 / 2 tiles. Both retry up to eight valid-tile candidates on a spawn attempt and retain some wider placements. Classic uses the original placement distribution and single attempt.

**Faster** uses 15 initial frames + 10 per visible wild and a 90-frame full-population replacement timer; Classic remains 30 + 30 per visible wild / 240 replacement. Fastest uses 6 + 4 / 45. A fixed maximum ten-actor pool avoids reallocating actors when settings change. Frequency values are game frames at nominal 60 FPS, not real-time guarantees.

These affect **how many, where and how often** wild Pokémon appear, not the native wild-table slot probabilities or levels. Existing collision, terrain, repel, restricted-map and special encounter protections remain in place. See [Spawn tuning guide](docs/OWE_SPAWN_TUNING.md) for details and tests.

## Nuzlocke Randomiser compatibility

**Untamed Advanced works with [Nuzlocke v3.0.0-BETA](https://github.com/Deluxe0111/nuzlocke)**, including its Generation 3 **Random Wild** option.

With both compatible mods installed, turning **Random Wild ON** in Nuzlocke also randomises the Pokémon visibly wandering around the world. The Pokémon you see is the one you battle and can catch. It uses Nuzlocke's existing randomiser seed, species pool and balance settings — there is nothing extra to enable here.

- **Followers stay yours.** Your lead Pokémon and scripted/special overworld encounters are not randomised.
- **Chaining shows the actual Pokémon.** If Feraligatr appears in a native Rattata slot, defeating it counts towards a **Feraligatr** chain, not a Rattata chain. The original slot is kept internally for chain-based spawn odds.
- **Shiny Rate matches visible Pokémon.** Nuzlocke's **CLAUSES → SHINY RATE** also changes the odds of ordinary wandering Pokémon, even with Random Wild OFF. A boosted shiny is already shiny in the overworld and stays shiny in battle/capture — no surprise battle reroll. Untamed's native chain bonuses remain active.
- **No Nuzlocke required.** Untamed's usual wandering encounters and chaining still work when Nuzlocke isn't installed or Random Wild is OFF.

Compatibility integration by **[Deluxe0111](https://github.com/Deluxe0111)**. For the technical hook contract, see [Overworld Randomiser Hook](docs/OWE_RANDOMIZER_HOOK.md).

## Expanded National Dex sprite compatibility

National Dex Gen 3, Modern Spawns and Untamed use different species numbering
systems. A Gen 9 Pokémon can have a **National Dex number**, an **engine slot**,
and a different **pokeemerald-expansion overworld atlas ID**. For example,
Sprigatito is National #906, registered at engine slot 970, but its expansion
overworld artwork is #1289; raw atlas key 906 would draw Mega Venusaur.

The optional [sprite-ID translation](owe_expansion_species_map.lua) corrects
the 120 Paldean base species and atlas-backed alternate forms without changing
Pokémon identities, Nuzlocke run state, save data or randomiser seeds. Four
Floette colour variants currently have no matching artwork in Untamed's built-in
atlas and therefore fail closed instead of using misleading art.

**This is an artwork/identity fix, not yet full six-mod certification.** In
particular, Nuzlocke and Modern Spawns can independently select expanded
species and their randomiser precedence still needs live validation. The mods' randomiser
priority and shiny/provider ownership need further integration tests.

## Modern Spawns visible-encounter support

With [Modern Spawns](https://github.com/poooooby/g1r_modern_spawns)
installed and enabled, Untamed now asks its public `drawFor(mapId, terrain)`
API for **each normal visible wild spawn**. In **COMPLETE** mode this samples
the larger per-slot species pools instead of repeatedly displaying only the
original two Route 1 species. RANDOM likewise draws a new table per spawn;
LIMITED and EVERY MAP use their corresponding rosters.

The **native number of encounter-table slots, appearance odds and level ranges remain unchanged**.
Concurrent visible Pokémon are now controlled separately by **Wild population**.
Untamed falls back to
native species for missing provider APIs and any alternate form without a
supported sprite. Special roamers, Feebas, outbreaks and scripted actors keep
their separate logic; Nuzlocke's Random Wild hook still runs afterwards for
ordinary visible spawns. A native chain-forced source remains independent
of these fresh random draws.

See [Modern Spawns integration notes](docs/OWE_MODERN_SPAWNS.md).
This integration needs on-ROM testing with all three mods before calling
the combined stack verified.

## Credits

See [CREDITS.md](CREDITS.md).
