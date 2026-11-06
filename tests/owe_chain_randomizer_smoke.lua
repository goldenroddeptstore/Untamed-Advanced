-- Regression: Nuzlocke Random Wild uses visible species for chain popups,
-- but keeps the native slot only for forced spawning and shiny chain odds.
bit = { band=function() return 0 end, bxor=function() return 0 end,
    rshift=function() return 0 end }
local Owe = assert(loadfile("owe.lua"))()
local messages = {}
local engine = {
  C = { OWE_SPAWNS_MAX=1, OWE_ROGUE_CHAIN=true },
  V = { roamerCount=0 },
  Follower = { ANIMS={}, animFrame=function() return 0 end },
  Data = { ATLAS={} },
  actors = { [2]={} },
  popup = function(species,count)
    messages[#messages+1] = {species=species,count=count}
  end,
}
Owe.init(engine)
-- Feraligatr (160) was assigned from an authored Rattata (19) slot.
for _=1,3 do Owe._chain.onBattleEnd("win", 160, 19) end
local visible,count,authored = Owe.chainState()
assert(visible==160 and count==3 and authored==19)
assert(#messages==1 and messages[1].species==160 and
    messages[1].count==3, "popups must show Feraligatr, not Rattata")
local nativeSlot = {species=19, minLevel=5,maxLevel=7}
assert(Owe._chain.sourceSlot({{species=21},nativeSlot})==nativeSlot,
    "forced spawn must resolve authored slot, not randomised species")
Owe._chain.onBattleEnd("win",160,19)
assert(Owe.chainState()==160 and Owe._chain.source()==19)
assert(messages[#messages].species==160 and messages[#messages].count==4)
Owe._chain.onBattleEnd("win",161,20)
assert(messages[#messages].species==160 and
    messages[#messages].count==nil,
    "a different visible species breaks the displayed chain")
assert(Owe.chainState()==161 and Owe._chain.source()==20)
Owe._chain.onBattleEnd("caught",161,20)
assert(Owe.chainState()==nil and Owe._chain.source()==nil,
    "capturing ends the visible species chain")
Owe._chain.onBattleEnd("win",19)
assert(Owe.chainState()==19 and Owe._chain.source()==19,
    "without randomisation native chains work unchanged")
-- Regression: Modern Spawns replaces the content of an ORIGINAL wild slot.
-- The displayed species must chain, even when Nuzlocke randomises it again.
-- A forced repeat must keep that displayed species and roll chain shininess.
local modernCalls, randomizerCalls = 0, 0
local native = {{species=19,minLevel=5,maxLevel=6},
                {species=21,minLevel=6,maxLevel=7}}
local generated = {{species=160,minLevel=5,maxLevel=6},
                   {species=161,minLevel=6,maxLevel=7}}
local chainPID = 0x12345678
local shinyPID = 0xABCD5678
local testEngine = {
  C = {
    OWE_SPAWNS_MAX=1, OWE_ROGUE_CHAIN=true,
    OWE_CHAIN_BASE_SHINY_ODDS=8192, OWE_CHAIN_SHINY_TARGET=16,
    OWE_CHAIN_SHINY_MAX_COUNT=48, WE_OWE_PREVENT_SHINY_DESPAWN=true,
  },
  V = {roamerCount=0,abilities={}},
  Follower = {ANIMS={},animFrame=function()return 0 end},
  Data = {ATLAS={}}, actors={[2]={}},
  wildHeader=function() return true end,
  encounterKind=function() return "land" end,
  wildArea=function() return native end,
  random=function() return 0 end, -- pick first slot and force chain
  random32=function() return chainPID end,
  leadMon=function() return nil end,
  expansionSpecies=function(sp) return sp end,
  shinyFor=function(pid) return pid == shinyPID end,
  makeShiny=function(pid) return 0xABCD0000 + pid % 65536 end,
  femaleFor=function() return false end,
  popup=function() end,
  modernWildArea=function(kind, slots)
    modernCalls = modernCalls + 1
    assert(kind=="land" and slots==native)
    return generated
  end,
  OWESpeciesHook={
    apply=function(_, sp)
      randomizerCalls = randomizerCalls + 1
      assert(sp==160)
      return 300
    end,
    applyShiny=function(_, _, _, pid, shiny) return pid, shiny end,
  },
}
Owe.init(testEngine)
local info = {category=3} -- CAT_UNDEFINED: no roamers, outbreak=0, feebas=1, wild=2
assert(Owe._chain.spawnInfo(info, 10, 10))
assert(info.engineSpecies==300 and info.authoredSpecies==19,
  "the native source slot must survive Modern Spawns and Nuzlocke")
assert(not info.shiny and modernCalls==1 and randomizerCalls==1)
for _=1,6 do
  Owe._chain.onBattleEnd("win", info.engineSpecies, info.authoredSpecies)
end
local sp, count, source = Owe.chainState()
assert(sp==300 and count==6 and source==19)
assert(Owe._chain.sourceSlot(native)==native[1],
  "the saved source must be found in the untouched native table")
local forced = {category=3}
assert(Owe._chain.spawnInfo(forced, 10, 10))
assert(forced.engineSpecies==300 and forced.authoredSpecies==19,
  "forced chain encounters must preserve the ACTUAL chained species")
assert(forced.level==5 and forced.personality==shinyPID and forced.shiny,
  "forced spawns must use native levels and roll the chain shiny PID")
assert(forced.noDespawn==true, "chained shiny must be protected")
assert(modernCalls==1 and randomizerCalls==1,
  "forced chain spawns must not redraw Modern or reroll Nuzlocke")
Owe._chain.onBattleEnd("win", forced.engineSpecies, forced.authoredSpecies)
assert(select(2,Owe.chainState())==7, "the forced encounter must extend the chain")

-- Modern Spawns without the Nuzlocke randomizer must work identically.
Owe._chain.set(nil,0)
testEngine.OWESpeciesHook.apply=function(_,sp) return sp end
local modernOnly={category=3}
assert(Owe._chain.spawnInfo(modernOnly,10,10))
assert(modernOnly.engineSpecies==160 and modernOnly.authoredSpecies==19)
Owe._chain.set(160,6,19)
local modernForced={category=3}
assert(Owe._chain.spawnInfo(modernForced,10,10))
assert(modernForced.engineSpecies==160 and modernForced.authoredSpecies==19)
assert(modernForced.shiny and modernForced.personality==shinyPID)

-- Without either provider, preserve the native chain behavior.
Owe._chain.set(nil,0)
testEngine.modernWildArea=nil
testEngine.OWESpeciesHook=nil
local vanilla={category=3}
assert(Owe._chain.spawnInfo(vanilla,10,10))
assert(vanilla.engineSpecies==19 and vanilla.authoredSpecies==19)
Owe._chain.set(19,6,19)
local vanillaForced={category=3}
assert(Owe._chain.spawnInfo(vanillaForced,10,10))
assert(vanillaForced.engineSpecies==19 and vanillaForced.shiny)

print("Untamed randomized visible chain display and source-slot lookup: PASS")
