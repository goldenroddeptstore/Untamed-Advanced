-- Pure-contract tests for the optional Untamed OWE species hook.
local Hook = assert(loadfile("owe_species_hook.lua"))()
local calls, wanted = 0, false
local spriteAvailable = true
local runtime = {
    wantsHook = function(name)
        assert(name == "untamed.owe.species")
        return wanted
    end,
    call = function(name, native, encounter, context)
        calls = calls + 1
        assert(name == "untamed.owe.species")
        assert(context.source == "untamed_advanced"
            and context.mapId == "FR_ROUTE_1"
            and context.terrain == "land"
            and context.x == 5 and context.y == 9)
        assert(encounter.species == 16 and encounter.level == 7)
        local copy = {species=25,level=encounter.level}
        return copy
    end,
}
local engine = {
    ModHooks = runtime,
    Data = { ATLAS = { species = { [25] = 100 } } },
    mapId = function() return "FR_ROUTE_1" end,
    Pokemon = {
        national = function(sp) return ({[16]=16,[25]=25})[sp] end,
    },
    expansionSpecies = function(sp, personality)
        assert(personality==0)
        return sp
    end,
    Gfx = { sheetFor = function(sp, female, shiny)
        return spriteAvailable and sp==25 and not female and not shiny
            and 100 or nil
    end },
}
assert(Hook.apply(engine,16,7,"land",5,9)==16
    and calls == 0,"no hook must leave native OWE unchanged")
wanted=true
assert(Hook.apply(engine,16,7,"land",5,9)==25 and calls==1,
    "valid replacement updates sprite and eventual battle species")
spriteAvailable=false
assert(Hook.apply(engine,16,7,"land",5,9)==16,
    "missing sprite refuses replacement")
spriteAvailable=true
engine.Data.ATLAS.species[25] = nil
assert(Hook.apply(engine,16,7,"land",5,9)==16,
    "Substitute placeholder must never represent a different battle species")
engine.Data.ATLAS.species[25] = 100
runtime.call=function()
    calls=calls+1
    return {species=999,level=7}
end
assert(Hook.apply(engine,16,7,"land",5,9)==16,
    "invalid Gen3 species refuses replacement")
runtime.call=function() return {species="unknown"} end
assert(Hook.apply(engine,16,7,"land",5,9)==16,
    "nonnumeric species leaves native OWE intact")
runtime.call=function() return nil end
assert(Hook.apply(engine,16,7,"land",5,9)==16,
    "missing provider result does not break spawn")
assert(Hook.apply({mapId=engine.mapId},16,7,"land",5,9)==16,
    "without shared runtime Untamed retains vanilla behaviour")
-- A National Dex Gen 3 Pokémon uses three DIFFERENT identifiers:
-- native slot 970, National #906, expansion atlas 1289 (Sprigatito).
-- The atlas ID 906 is Mega Venusaur, so it must never be drawn directly.
engine.Pokemon.national = function(sp)
    return ({[16]=16,[25]=25,[970]=906})[sp]
end
local spriteMap = assert(loadfile("owe_expansion_species_map.lua"))()
engine.expansionSpecies = function(sp)
    return spriteMap.resolve(engine.Pokemon.national(sp))
end
engine.Data.ATLAS.species[1289] = 101
engine.Gfx.sheetFor = function(sp, female, shiny)
    return spriteAvailable and sp==1289 and not female and not shiny
        and 101 or nil
end
runtime.wantsHook = function(name)
    return name == "untamed.owe.species"
end
runtime.call = function() return {species=970,level=7} end
assert(Hook.apply(engine,16,7,"land",5,9)==970,
    "expanded species with a verified proper atlas sprite must be accepted")
engine.Data.ATLAS.species[1289] = nil
assert(Hook.apply(engine,16,7,"land",5,9)==16,
    "expanded species must not spawn with a missing or incorrect sprite")
engine.Data.ATLAS.species[1289] = 101
-- Shiny conversion must happen in the OWE PID, not just the rendered flag.
local shinyHookEnabled, shinyCalls = false, 0
engine.shinyFor = function(pid) return pid == 65546 end
engine.makeShiny = function(pid)
    assert(pid == 10)
    return 65546
end
runtime.wantsHook = function(name)
    return name == "untamed.owe.shiny" and shinyHookEnabled
end
runtime.call = function(name, native, source, ctx)
    shinyCalls = shinyCalls + 1
    assert(name == "untamed.owe.shiny")
    assert(source.species == 25 and source.level == 7
        and source.personality == 10 and source.shiny == false)
    assert(ctx.source == "untamed_advanced" and ctx.terrain == "land")
    return { species = source.species, level = source.level,
        personality = ctx.makeShiny(source.personality), shiny = true }
end
local pid, shiny = Hook.applyShiny(engine,25,7,10,false,"land",5,9)
assert(pid == 10 and not shiny and shinyCalls == 0,
    "without a provider, native overworld shininess is unchanged")
shinyHookEnabled = true
pid, shiny = Hook.applyShiny(engine,25,7,10,false,"land",5,9)
assert(pid == 65546 and shiny and shinyCalls == 1,
    "validated PID changes sprite and eventual battle shininess")
pid, shiny = Hook.applyShiny(engine,25,7,10,true,"land",5,9)
assert(pid == 10 and shiny, "naturally shiny OWEs are never rewritten")
runtime.call = function() return {species=25,level=7,
    personality=11,shiny=true} end
pid, shiny = Hook.applyShiny(engine,25,7,10,false,"land",5,9)
assert(pid == 10 and not shiny,
    "unverified PID must not make a false shiny sprite")
runtime.call = function() return {species=16,level=7,
    personality=65546,shiny=true} end
pid, shiny = Hook.applyShiny(engine,25,7,10,false,"land",5,9)
assert(pid == 10 and not shiny,
    "shiny hook may not change species")
assert(select(1,Hook.applyShiny({},25,7,10,false,"land",5,9)) == 10,
    "missing runtime keeps ordinary shiny calculation")
print("Untamed OWE species and shiny adapters: PASS")
