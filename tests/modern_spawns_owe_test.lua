-- Pure contract check: Untamed consumes Modern Spawns without changing
-- the map's encounter slot count, levels or source tables.
local factory = assert(loadfile("modern_owe_adapter.lua"))()
local calls, active, mode = 0, true, "complete"
local MOD = {
  find=function(_,id)
    assert(id=="modern_spawns")
    return {exports={
      apiVersion=2,
      isActive=function() return active end,
      spawnMode=function() return mode end,
      drawFor=function(mapId,terrain)
        calls=calls+1
        assert(mapId=="FR_ROUTE_1" and terrain=="land")
        return {rate=20,slots={
          {species="ALPHA",minLevel=2,maxLevel=3},
          {species="BETA",minLevel=4,maxLevel=5},
          {species="UNSUPPORTED",minLevel=7,maxLevel=9},
        }}
      end,
    }}
  end
}
local pokemon={
  ALPHA=100, BETA=200, UNSUPPORTED=300,
  national=function(id) return id end,
}
-- Avoid a closure-upvalue initializer issue in older Lua.
pokemon.speciesFromName=function(name) return pokemon[name] end
local E={
  Pokemon=pokemon,
  Data={ATLAS={species={[1100]=true,[1200]=true}}},
  expansionSpecies=function(id) return id+1000 end,
  mapId=function() return "FR_ROUTE_1" end,
}
local draw=factory(MOD,E)
local native={
  {species=1,minLevel=2,maxLevel=3},
  {species=2,minLevel=4,maxLevel=5},
  {species=3,minLevel=7,maxLevel=9},
}
local changed=assert(draw("land",native))
assert(#changed==3 and changed[1].species==100
  and changed[2].species==200
  and changed[3].species==3)
assert(changed[1].minLevel==2 and changed[1].maxLevel==3
  and changed[2].minLevel==4 and changed[2].maxLevel==5)
assert(native[1].species==1 and native[2].species==2)
assert(calls==1)
active=false
assert(draw("land",native)==nil and calls==1)
active=true
assert(draw("fish",native)==nil and calls==1)
-- Bad provider payload must fall back to the native spawn table.
MOD.find=function()
  return {exports={apiVersion=2,isActive=function()return true end,
    drawFor=function() return {slots={{species="ALPHA"}}} end}}
end
assert(draw("land",native)==nil)
print("Untamed / Modern Spawns per-pick adapter: PASS")
