# Untamed Advanced

A line-by-line port of pokeemerald-expansion's **Follower Pokémon** and **Overworld Wild Encounters**, plus Emerald Rogue's **encounter chaining**, for FireRed, LeafGreen and Emerald on [gen1recomp](https://github.com/bryanthaboi/gen1recomp).

Same logic, same timings, same messages. If you've played a romhack with these features, this should feel exactly the same.

## What you get

- **A buddy.** Your lead Pokémon walks behind you. Talk to it and it'll tell you how it's feeling.
- **Visible wild Pokémon.** They pop up in grass and water. Some wander, some chase you, some run away. Bump into one to battle it.
- **Chaining.** Beat the same species a few times in a row to make it show up more and boost your shiny odds.
- **A matching world.** Mewtwo, Snorlax, the legendary birds and every other Pokémon already standing on the maps (Kecleon, Latias, the Regis and friends in Emerald) get the same sprites and idle animation as your buddy.

Pretty much everything can be toggled in the mod's options.

## Tests

Run `luajit tests/render_callbacks.lua` from the repository root. These headless
regression tests exercise the mod's rendering hooks against gen1recomp's render
wrapper callback contract; they do not require a ROM or LÖVE graphics context.

## Credits

See [CREDITS.md](CREDITS.md).
