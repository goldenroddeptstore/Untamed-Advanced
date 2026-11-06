-- Headless regression for spawn policy and dynamic active population limits.
-- Run from the repository root: lua tests/owe_spawn_tuning_smoke.lua
bit = bit or {
  band = function() return 0 end,
  bxor = function() return 0 end,
  rshift = function() return 0 end,
}
local Owe = assert(loadfile("owe.lua"))()
local C = {
  OWE_SPAWNS_MAX = 10, OWE_ACTIVE_LIMIT = 8,
  OWE_SPAWN_PROXIMITY = 0, OWE_SPAWN_DISTANCE_LAND = 1,
  OWE_SPAWN_DISTANCE_WATER = 3,
  OWE_SPAWN_WIDTH_TOTAL = 15, OWE_SPAWN_HEIGHT_TOTAL = 9,
  OWE_SPAWN_WIDTH_RADIUS = 7, OWE_SPAWN_HEIGHT_RADIUS = 4,
  OWE_SPAWN_TIME_MINIMUM = 30, OWE_SPAWN_TIME_LURE = 0,
  WE_OW_ENCOUNTERS = true, WE_OWE_DESPAWN_SOUND = false,
}
local objects = {}
for i = 2, 11 do objects[i] = {slot = i} end
local tiles, terrain, surfing = 0, "land", false
local E = {
  C = C, V = {roamerCount = 0, mb = {}},
  Follower = {ANIMS = {}, animFrame = function() return 0 end},
  Data = {ATLAS = {}}, actors = objects,
  random = function() return 5 end,
  surfing = function() return surfing end,
  playerCur = function() return 100, 100 end,
  insidePlayerMap = function() return true end,
  elevationAt = function() return 3 end,
  encounterKind = function()
    tiles = tiles + 1
    if tiles <= 2 then return "invalid" end
    return terrain
  end,
  collisionAt = function() return false end,
  Objects = {at = function() return nil end},
  actorAt = function() return nil end,
  lureSteps = function() return 0 end,
  behaviorAt = function() return 0 end,
  mapUnderwater = function() return false end,
  Collision = {isSurfable = function() return false end},
}
Owe.init(E)
-- In Classic, a single rejected tile must not be retried.
tiles = 0
assert(Owe.trySelectTile() == nil and tiles == 1,
  "Classic should use exactly one native-position candidate")
-- Nearby retries invalid tiles, while staying inside the normal view.
C.OWE_SPAWN_PROXIMITY = 1
C.OWE_SPAWN_DISTANCE_WATER = 2
tiles = 0
local x, y = Owe.trySelectTile()
assert(x and y and tiles == 3, "Nearby should retry invalid encounter tiles")
assert(math.abs(x-100) <= 7 and math.abs(y-100) <= 4)
-- Close favours a smaller footprint, including water.
C.OWE_SPAWN_PROXIMITY = 2
tiles = 3
x, y = Owe.trySelectTile()
assert(x and y and math.abs(x-100) <= 3 and math.abs(y-100) <= 2,
  "Close should prefer tiles close to the player")
surfing, terrain = true, "water"
x, y = Owe.trySelectTile()
assert(x and y and math.max(math.abs(x-100), math.abs(y-100)) >= 2,
  "surfing must respect minimum separation")
-- The active count is independent of the ten-actor storage pool.
surfing, terrain = false, "land"
for i = 2, 9 do
  local a = objects[i]
  a.active, a.oweType, a.species = true, "generated", i
  a.cellX, a.cellY, a.age, a.category = 101, 101, 12-i, 2
end
objects[9].noDespawn = true -- shiny/protected actor
objects[10].active, objects[10].oweType, objects[10].species =
  true, "manual", 999
objects[10].cellX, objects[10].cellY = 102, 102
C.OWE_ACTIVE_LIMIT = 4
Owe.fieldEffect = function() end -- no sprite data in this headless test
Owe.trimPopulation()
assert(Owe.numActive("generated") == 4,
  "decreasing population must trim eligible generated actors")
assert(objects[9].active and objects[9].noDespawn,
  "protected generated actors must survive a density change")
assert(objects[10].active and objects[10].oweType == "manual",
  "manual encounters must never be trimmed")
C.OWE_SPAWN_TIME_MINIMUM = 15
Owe.setMinimumSpawnTimer()
assert(Owe.countdown() == 15, "new frequency applies without restarting")
print("Untamed OWE spawn tuning: PASS")
