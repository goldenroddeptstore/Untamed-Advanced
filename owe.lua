-- Species always come from the running map's wild table; only slot odds are constants.
local Owe = {}
local E, C, V
local battleCo, updateBattleScript -- InteractWithOverworldWildEncounter
local FIRST, LAST -- actor slots owned by OWEs (spawnSlot 0 = FIRST)
local band, bxor, rshift = bit.band, bit.bxor, bit.rshift

-- enum CategoryOWE: roamers are 0..ROAMER_COUNT-1
local ROAMER_COUNT, CAT_OUTBREAK, CAT_FEEBAS, CAT_WILD, CAT_UNDEFINED
local OWE_NO_ENCOUNTER_SET = 0xFF
local sOWESpawnCountdown = 0
local ANIMS, animFrame, A -- follower.lua anim tables, atlas index (init)
local ACT_NONE, ACT_FACE, ACT_WALK, ACT_IN_PLACE, ACT_JUMP_IN_PLACE, ACT_EMOTE = 0, 1, 2, 3, 4, 5

-- ChooseWildMonIndex_Land / _Water slot odds (wild_encounter.c)
local LAND_W = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
local WATER_W = { 60, 30, 5, 4, 1 }

local FACE_FRAME = { down = 0, up = 2, left = 4, right = 4 }
local STANDARD_DIRS = { "down", "up", "left", "right" } -- gStandardDirections

-- IsOverworldWildEncounter(owe, type): "any" | "generated" | "manual"
local function isOWE(a, t)
  if not a.active or not a.oweType then return false end
  return t == nil or t == "any" or a.oweType == t
end
Owe.isOWE = isOWE

local function numActive(t)
  local n = 0
  for i = FIRST, LAST do
    if isOWE(E.actors[i], t) then n = n + 1 end
  end
  return n
end
Owe.numActive = numActive

local function slotActor(s) return E.actors[FIRST + s] end
local function ow_species(a) return a.active and a.species or nil end

-- Countdown.  SetMinimumOWESpawnTimer / SetNewOWESpawnCountdown
local function setMinimumOWESpawnTimer()
  if not C.WE_OW_ENCOUNTERS then return end
  sOWESpawnCountdown = C.OWE_SPAWN_TIME_MINIMUM
  if E.lureSteps() > 0 and numActive("generated") < C.OWE_SPAWNS_MAX then
    sOWESpawnCountdown = C.OWE_SPAWN_TIME_LURE
  end
end
Owe.setMinimumSpawnTimer = setMinimumOWESpawnTimer

local function setNewOWESpawnCountdown()
  local n = numActive("generated")
  if C.WE_OWE_SPAWN_REPLACEMENT and n >= C.OWE_SPAWNS_MAX then
    sOWESpawnCountdown = C.OWE_SPAWN_TIME_REPLACEMENT
  elseif E.lureSteps() > 0 and n < C.OWE_SPAWNS_MAX then
    sOWESpawnCountdown = C.OWE_SPAWN_TIME_LURE
  else
    sOWESpawnCountdown = C.OWE_SPAWN_TIME_MINIMUM + C.OWE_SPAWN_TIME_PER_ACTIVE * n
  end
end

function Owe.countdown() return sOWESpawnCountdown end

-- Spawn / despawn anims: FLDEFF_OW_ENCOUNTER_SPAWN_ANIM + cry / SE_SHINY / SE_FLEE.
local function spawnAnimType(x, y)
  local b, mb = E.behaviorAt(x, y), V.mb
  if b == mb.TALL_GRASS or b == mb.CYCLING_ROAD_PULL_DOWN_GRASS or b == mb.ASH_GRASS then
    return "grass" -- MetatileBehavior_IsPokeGrass / IsAshGrass
  elseif b == mb.LONG_GRASS then
    return "long_grass"
  elseif E.Collision.isSurfable(b) and not E.mapUnderwater() then
    return "water" -- MetatileBehavior_IsSurfableFishableWater
  elseif E.mapUnderwater() then
    return "underwater" -- PLAYER_AVATAR_FLAG_UNDERWATER
  end
  return "cave"
end

-- xOffset, yOffset, frame durations, uses bubbles callback.
local FX_INFO = {
  grass      = { 0, 8,  { 8, 8, 8, 8 }, false },          -- JUMP_TALL_GRASS
  long_grass = { 0, 0,  { 4, 4, 8, 8, 8, 8 }, false },    -- JUMP_LONG_GRASS
  water      = { 0, 8,  { 8, 8, 8, 8 }, false },          -- JUMP_BIG_SPLASH
  underwater = { 0, 0,  { 4, 4, 4, 6, 6, 4, 4, 4 }, true }, -- BUBBLES
  cave       = { 0, 12, { 8, 8, 8 }, false },             -- GROUND_IMPACT_DUST
  shiny      = { 0, 0,  { 4, 4, 4, 6, 6, 4, 4, 4 }, true }, -- SHINY_SPARKLE
}
-- Effect sprite pool; dropped when full, like pret.
local FX_POOL = 8
local fxPool = {}
Owe.fx = fxPool

local function drawFx(s, sx, sy)
  local fh = A.sheets[(s.sheet - 1) * 6 + 4]
  -- sprite centre = map coords + (8, 0) + offsets; py carries +1 (see D25)
  return E.Gfx.draw(s.sheet, s.frame, false, s.palRow,
    sx + s.xOff, sy - 1 + s.yOff - s.rise + rshift(fh, 1) - 16)
end

-- FldEff_OWE_SpawnAnim (field_effect_helpers.c:1912)
function Owe.fieldEffect(t, x, y)
  local s
  for i = 1, FX_POOL do
    if not fxPool[i].active then s = fxPool[i]; break end
  end
  if not s then return end -- MAX_SPRITES
  local fi = FX_INFO[t]
  s.info, s.sheet = fi, A.fx[t]
  s.palRow = A.sheets[(s.sheet - 1) * 6 + 6]
  s.xOff, s.yOff, s.rise, s.sY = fi[1], fi[2], 0, 0
  s.frame, s.timer = 0, fi[3][1]
  s.cellX, s.cellY, s.px, s.py = x, y, x * 16, y * 16 + 1
  s.elevation = E.elevationAt(x, y)
  s.currentElevation = s.elevation
  s.active = true
end

-- AnimateSprite + UpdateJumpImpactEffect / UpdateBubblesFieldEffect
local function updateFx()
  for i = 1, FX_POOL do
    local s = fxPool[i]
    if s.active then
      local fi = s.info
      if fi[4] then
        -- sY += 0x80; sY &= 0x100; y -= sY >> 8 (literal: sY starts at 0)
        s.sY = band(s.sY + 128, 256)
        s.rise = s.rise + rshift(s.sY, 8)
      end
      s.timer = s.timer - 1
      if s.timer <= 0 then
        local d = fi[3]
        if s.frame + 1 >= #d then
          s.active = false -- animEnded -> FieldEffectStop
        else
          s.frame = s.frame + 1
          s.timer = d[s.frame + 1]
        end
      end
    end
  end
end
Owe.updateFx = updateFx

local function playOWECry(a)
  if not isOWE(a, "any") then return end
  local px, py = E.playerCur()
  local WR, HR = C.OWE_SPAWN_WIDTH_RADIUS, C.OWE_SPAWN_HEIGHT_RADIUS
  local dx, dy = a.cellX - px, a.cellY - py
  if dx > WR then dx = WR elseif dx < -WR then dx = -WR end
  if dy < 0 then dy = -dy end
  if dy > HR then dy = HR end
  local dmax = WR + HR
  local d = (dx < 0 and -dx or dx) + dy
  if d > dmax then d = dmax end
  local volume = 80 - math.floor(d * (80 - 50) / dmax)
  local pan = 212 + math.floor((dx + WR) * (300 - 212) / (2 * WR))
  if pan > 127 then pan = pan - 256 end -- s8
  E.playCryAt(a.engineSpecies, pan, volume)
end
Owe.playCry = playOWECry

-- TryPlayAmbientCryOWE / GetRandomOWEObjectEvent
function Owe.tryPlayAmbientCry()
  local n = numActive("any")
  if n == 0 then return false end
  local k = E.random() % n
  for i = FIRST, LAST do
    local a = E.actors[i]
    if isOWE(a, "any") then
      if k == 0 then playOWECry(a); return true end
      k = k - 1
    end
  end
  return false
end

-- game3 has no ambient cries, so VANILLA is served from here too.
local AMB_CRY_INIT, AMB_CRY_FIRST, AMB_CRY_RESET, AMB_CRY_WAIT, AMB_CRY_IDLE = 0, 1, 2, 3, 4
local ambState, ambDelay = AMB_CRY_INIT, 0
local sAmbientCrySpecies, sIsAmbientCryWaterMon = nil, false -- engine species id

-- ChooseAmbientCrySpecies (Route 130's GetLocalWaterMon branch: V.ambientWaterOnly)
function Owe.chooseAmbientCrySpecies()
  local nat, water, sp = E.localWildMon()
  if V.ambientWaterOnly and V.ambientWaterOnly() then water = true end
  sAmbientCrySpecies = nat and sp or nil
  sIsAmbientCryWaterMon = water == true
end

local function shouldPlayVanillaAmbientCry()
  local m = C.OW_AMBIENT_CRIES
  if m == 1 then return true end                            -- VANILLA
  if m == 2 then return not Owe.tryPlayAmbientCry() end     -- OWE_PRIORITY
  if m == 3 then Owe.tryPlayAmbientCry(); return false end  -- OWE_ONLY
  return false                                              -- NONE
end

local function playAmbientCry()
  if not shouldPlayVanillaAmbientCry() then return end
  local x, y = E.playerCur() -- PlayerGetDestCoords
  if sIsAmbientCryWaterMon and not E.Collision.isSurfable(E.behaviorAt(x, y)) then return end
  local pan = E.random() % 88 + 212
  if pan > 127 then pan = pan - 256 end -- s8
  local volume = E.random() % 30 + 50
  -- gDisableMapMusicChangeOnMapLoad: game3 has no such switch (D34)
  E.playCryAt(sAmbientCrySpecies, pan, volume)
end

function Owe.updateAmbientCry()
  if E.controlsLocked() then return end
  if ambState == AMB_CRY_INIT then
    ambState = sAmbientCrySpecies and AMB_CRY_FIRST or AMB_CRY_IDLE
  elseif ambState == AMB_CRY_FIRST then
    ambDelay = E.random() % 2400 + 1200
    ambState = AMB_CRY_WAIT
  elseif ambState == AMB_CRY_RESET then
    local divBy = 1
    local party = E.party()
    if party then
      -- pret checks party[0]'s ability for every non-egg slot (kept)
      local lead = party[1]
      for i = 1, #party do
        if not E.isEgg(party[i]) and lead and E.monAbility(lead) == V.abilities.SWARM then
          divBy = 2
          break
        end
      end
    end
    ambDelay = math.floor((E.random() % 1200 + 1200) / divBy)
    ambState = AMB_CRY_WAIT
  elseif ambState == AMB_CRY_WAIT then
    ambDelay = band(ambDelay - 1, 0xFFFF)
    if ambDelay == 0 then
      playAmbientCry()
      ambState = AMB_CRY_RESET
    end
  end
end

-- ResetFieldTasksArgs (overworld.c:912) + ChooseAmbientCrySpecies on load
local function resetAmbientCry()
  ambState, ambDelay = AMB_CRY_INIT, 0
  Owe.chooseAmbientCrySpecies()
end

local function doOWESpawnAnim(a)
  local t
  if C.WE_OWE_SHINY_SPARKLE and a.shiny then
    E.playSe("SE_SHINY")
    t = "shiny"
  else
    playOWECry(a)
    t = spawnAnimType(a.cellX, a.cellY)
  end
  Owe.fieldEffect(t, a.cellX, a.cellY)
end

local function shouldDespawnGeneratedForNewOWE(a)
  if not isOWE(a, "generated") then return false end
  return C.WE_OWE_SPAWN_REPLACEMENT and numActive("generated") >= C.OWE_SPAWNS_MAX
end

local function shouldPlayFleeSound(a)
  if not isOWE(a, "any") or not a.species then return false end
  if not E.insidePlayerMap(a.cellX, a.cellY) then return false end
  if shouldDespawnGeneratedForNewOWE(a) then return false end
  if a.offScreen then return false end
  return C.WE_OWE_DESPAWN_SOUND
end

local function doOWEDespawnAnim(a)
  Owe.fieldEffect(spawnAnimType(a.cellX, a.cellY), a.cellX, a.cellY)
  if shouldPlayFleeSound(a) then E.playSe("SE_FLEE") end
end

local function clearSlot(a)
  a.active, a.moving, a.oweType = false, false, nil
  a.species, a.engineSpecies, a.level, a.age, a.category = nil, nil, 0, 0, nil
  a.noDespawn, a.offScreen = false, false
end

-- RemoveObjectEvent -> OnOverworldWildEncounterDespawn
function Owe.remove(a)
  if isOWE(a, "any") then
    if a.category and a.category < ROAMER_COUNT then E.roamerMove(a.category) end
    doOWEDespawnAnim(a)
      end
  clearSlot(a)
  if Owe.pending == a then Owe.pending = nil end
end

-- ClearObjectEvent: no despawn callback
local function clearObjectEvent(a)
  clearSlot(a)
  if Owe.pending == a then Owe.pending = nil end
end

-- Ages.  SortOWEAges / GetOldestActiveOWESlot
local ageSlot, ageVal = {}, {} -- preallocated struct AgeSort[OWE_SPAWNS_MAX]

local function sortOWEAges()
  local n = numActive("generated")
  if C.OWE_SPAWNS_MAX <= 1 then return end
  local count = 0
  for i = 0, C.OWE_SPAWNS_MAX - 1 do
    local a = slotActor(i)
    if isOWE(a, "any") and a.species then
      count = count + 1
      ageSlot[count], ageVal[count] = i, a.age
    end
    if count == n then break end
  end
  for i = 2, n do -- insertion sort, oldest first
    local cs, ca = ageSlot[i], ageVal[i]
    local j = i - 1
    while j >= 1 and ageVal[j] < ca do
      ageSlot[j + 1], ageVal[j + 1] = ageSlot[j], ageVal[j]
      j = j - 1
    end
    ageSlot[j + 1], ageVal[j + 1] = cs, ca
  end
  for i = 1, n do slotActor(ageSlot[i]).age = n - i + 1 end
end

local function hasNoDespawnFlag(a) return a.noDespawn == true end

local function getOldestActiveOWESlot(forceRemove)
  local oldest, first
  for s = 0, C.OWE_SPAWNS_MAX - 1 do
    local a = slotActor(s)
    if ow_species(a) and (not hasNoDespawnFlag(a) or forceRemove) then
      oldest, first = a, s
      break
    end
  end
  if not first then return nil end
  for s = first, C.OWE_SPAWNS_MAX - 1 do
    local a = slotActor(s)
    if ow_species(a) and (not hasNoDespawnFlag(a) or forceRemove) and a.age > oldest.age then
      oldest = a
    end
  end
  return oldest.slot - FIRST
end

-- GetNextOWESpawnSlot (nil = OWE_INVALID_SPAWN_SLOT)
local function getNextOWESpawnSlot()
  if numActive("generated") >= C.OWE_SPAWNS_MAX then
    if C.WE_OWE_SPAWN_REPLACEMENT then return getOldestActiveOWESlot(false) end
    return nil
  end
  for s = 0, C.OWE_SPAWNS_MAX - 1 do
    if not ow_species(slotActor(s)) then return s end
  end
  return nil
end

function Owe.removeOldestGenerated()
  local s = getOldestActiveOWESlot(true)
  if not s then return nil end
  local a = slotActor(s)
  Owe.remove(a)
  return a
end

-- Tile.  TrySelectTileForOWE -> x, y or nil
local function trySelectTileForOWE()
  local water = E.surfing()
  local cd = water and C.OWE_SPAWN_DISTANCE_WATER or C.OWE_SPAWN_DISTANCE_LAND
  local x = E.random() % (C.OWE_SPAWN_WIDTH_TOTAL - 2 * cd) - (C.OWE_SPAWN_WIDTH_RADIUS - cd)
  if x < 0 then x = x - cd else x = x + cd end
  local y = E.random() % (C.OWE_SPAWN_HEIGHT_TOTAL - 2 * cd) - (C.OWE_SPAWN_HEIGHT_RADIUS - cd)
  if y < 0 then y = y - cd else y = y + cd end
  local px, py = E.playerCur() -- PlayerGetDestCoords
  x, y = x + px, y + py

  if not E.insidePlayerMap(x, y) then return nil end
  local elevation = E.elevationAt(x, y)
  if elevation == 0 or elevation == 15 then return nil end

  local kind = E.encounterKind(x, y)
  local isEncounterTile = (water and kind == "water") or (not water and kind == "land")
  if isEncounterTile and not E.collisionAt(x, y) then
    -- GetObjectEventIdByPosition(x, y, 0) == OBJECT_EVENTS_COUNT
    if not E.Objects.at(x, y) and not E.actorAt(x, y) then return x, y end
  end
  return nil
end
Owe.trySelectTile = trySelectTileForOWE

-- Species.  CreateEnemyPartyOWE / TryGenerateWildMon / SetSpeciesInfoForOWE
local function entrySpecies(e) return tonumber(type(e) == "table" and (e.species or e[1]) or e) end
local function entryLevels(e)
  if type(e) ~= "table" then return 5, 5 end
  local lo = tonumber(e.minLevel or e.level or e[2]) or 5
  local hi = tonumber(e.maxLevel or e.level or e[3] or e[2]) or lo
  return lo, hi
end

-- TryGetAbilityInfluencedWildMonIndex (non-BUGFIX: scans NUM_LAND slots)
local validIdx = {}
local function abilityInfluencedIndex(slots, typeName, abilityName)
  local ab = V.abilities[abilityName]
  if not ab or not E.leadMon() or E.leadAbility() ~= ab then return nil end
  if E.random() % 2 ~= 0 then return nil end
  local want = E.typeId(typeName)
  local n, count = #LAND_W, 0
  for i = 1, n do
    local sp = entrySpecies(slots[i])
    if sp then
      local t1, t2 = E.speciesTypes(sp)
      if t1 == want or t2 == want then count = count + 1; validIdx[count] = i end
    end
  end
  if count == 0 or count == n then return nil end
  return validIdx[E.random() % count + 1]
end

local function chooseIndex(w)
  local r, acc = E.random() % 100, 0
  for i = 1, #w do
    acc = acc + w[i]
    if r < acc then return i end
  end
  return #w
end

-- ChooseWildMonLevel (LURE_STEP_COUNT == 0 branch; lures don't exist yet)
local function chooseWildMonLevel(e)
  local lo, hi = entryLevels(e)
  if hi < lo then lo, hi = hi, lo end
  local rand = E.random() % (hi - lo + 1)
  if E.leadMon() then
    local ab, A = E.leadAbility(), V.abilities
    if ab ~= 0 and (ab == A.HUSTLE or ab == A.VITAL_SPIRIT or ab == A.PRESSURE) then
      if E.random() % 2 == 0 then return hi end
      if rand ~= 0 then rand = rand - 1 end
    end
  end
  return lo + rand
end

-- TryGenerateWildMon(info, area, 0) -> engine species, level
local INFLUENCE = { { "STEEL", "MAGNET_PULL" }, { "ELECTRIC", "STATIC" },
  { "ELECTRIC", "LIGHTNING_ROD" }, { "FIRE", "FLASH_FIRE" }, { "GRASS", "HARVEST" },
  { "WATER", "STORM_DRAIN" } }
local function tryGenerateWildMon(slots, kind)
  local idx
  for i = 1, #INFLUENCE do
    idx = abilityInfluencedIndex(slots, INFLUENCE[i][1], INFLUENCE[i][2])
    if idx then break end
  end
  idx = idx or chooseIndex(kind == "water" and WATER_W or LAND_W)
  local e = slots[idx] or slots[#slots]
  local sp = entrySpecies(e)
  if not sp then return nil end
  return sp, chooseWildMonLevel(e)
end

-- Encounter chain (pokeemerald-rogue, not expansion: PARITY R1-R4).
-- RAM only like sFollowMonData.encounterChain*: never saved.
local chainSpecies, chainCount = nil, 0

-- rogue_followmon.c UpdateWildEncounterChain (nil = SPECIES_NONE)
local function updateWildEncounterChain(species)
  if chainSpecies ~= species then
    if chainCount >= 3 then E.popup(chainSpecies, nil) end -- PokemonChainBroke (>= so every shown chain reports its break)
    chainSpecies, chainCount = species, 0
  end
  if species then
    if chainCount < 255 then chainCount = chainCount + 1 end
    if chainCount >= 3 then E.popup(species, chainCount) end -- PokemonChain
  end
end

-- rogue_controller.c DidCompleteWildChain / DidFailWildChain (engine result names)
local CHAIN_WON = { win = true }
local CHAIN_CAUGHT = { catch = true, caught = true }
local CHAIN_FAIL = { lose = true, lost = true, blackout = true, whiteout = true,
  draw = true, drew = true, run = true, fled = true, fled_player = true, forfeited = true,
  mon_fled = true, mon_teleported = true, player_teleported = true }

-- Rogue_Battle_EndWildBattle (chain part)
local function onChainBattleEnd(result, species)
  if not C.OWE_ROGUE_CHAIN then return end
  if CHAIN_WON[result] then updateWildEncounterChain(species)
  elseif CHAIN_CAUGHT[result] or (CHAIN_FAIL[result] and chainSpecies == species) then
    updateWildEncounterChain(nil)
  end
end

local function getEncounterChainShinyOdds(count)
  local baseOdds = C.OWE_CHAIN_BASE_SHINY_ODDS
  if count <= 4 then return baseOdds end
  local range = C.OWE_CHAIN_SHINY_MAX_COUNT - 4
  local t = count - 4
  if t > range then t = range end
  return math.floor((C.OWE_CHAIN_SHINY_TARGET * t + baseOdds * (range - t)) / range)
end

-- IsChainSpeciesValidForSpawning -> matching slot (for its level range)
local function chainSlot(slots)
  if not chainSpecies then return nil end
  for i = 1, #slots do
    if entrySpecies(slots[i]) == chainSpecies then return slots[i] end
  end
  return nil
end

-- ForceChainSpeciesSpawn (GetChainSpawnOdds = 10 - min(count, 9))
local function forceChainSpeciesSpawn(slots)
  if not C.OWE_ROGUE_CHAIN or chainCount <= 1 then return nil end
  local e = chainSlot(slots)
  if not e then return nil end
  local n = chainCount < 9 and chainCount or 9
  if E.random() % (10 - n) == 0 then return e end
  return nil
end

function Owe.chainState() return chainSpecies, chainCount end
Owe._chain = { update = updateWildEncounterChain, onBattleEnd = onChainBattleEnd,
  shinyOdds = getEncounterChainShinyOdds,
  set = function(s, n) chainSpecies, chainCount = s, n end }

local function roamerOWEExists(index)
  for i = FIRST, LAST do
    local a = E.actors[i]
    if isOWE(a, "any") and a.category == index then return true end
  end
  return false
end

-- CreateEnemyPartyOWE + SetSpeciesInfoForOWE.  Fills `info`; false = none.
local function setSpeciesInfoForOWE(info, x, y)
  local header = E.wildHeader()
  if not header then return false end -- HEADER_NONE (no Pike/Pyramid: V.battleFrontier)
  local kind = E.encounterKind(x, y) == "water" and "water" or "land"
  local slots = E.wildArea(header, kind)
  if not slots then return false end

  local sp, level, chainE
  if info.category == CAT_UNDEFINED then
    -- TryStartRoamerEncounter: IsRoamerAt && Random() % 4 == 0
    for i = 0, ROAMER_COUNT - 1 do
      local rs, rl = E.roamerAt(i)
      if rs and E.random() % 4 == 0 then
        if not roamerOWEExists(i) then sp, level, info.category = rs, rl, i end
        break
      end
    end
    if sp then
    elseif C.WE_OWE_FEEBAS_SPOTS and kind == "water" and V.feebas and V.feebas.at(x, y) then
      local e = V.feebas.mon()
      sp, level = e and tonumber(e.species), e and chooseWildMonLevel(e)
      info.category = CAT_FEEBAS
      if C.WE_OWE_PREVENT_FEEBAS_DESPAWN then info.noDespawn = true end
    elseif V.outbreaks and V.outbreaks.test() and kind == "land" then
      sp, level, info.moves = V.outbreaks.mon()
      info.category = CAT_OUTBREAK
    else
      chainE = forceChainSpeciesSpawn(slots) -- Rogue_CreateWildMon (PARITY R2)
      if chainE then
        sp, level = chainSpecies, chooseWildMonLevel(chainE)
      else
        sp, level = tryGenerateWildMon(slots, kind)
      end
    end
  else
    sp, level = tryGenerateWildMon(slots, kind)
  end
  if not sp then return false end

  -- CreateWildMon: random personality (GetSynchronizedGender = Cute Charm)
  local personality = E.random32()
  local lead = E.leadMon()
  if lead and E.leadAbility() == V.abilities.CUTE_CHARM and E.random() % 3 ~= 0 then
    local want = lead.gender == "F" and "M" or "F"
    for _ = 1, 64 do
      local g = E.Pokemon.gender(sp, personality)
      if g == "U" or g == want then break end
      personality = E.random32()
    end
  end

  info.engineSpecies, info.level = sp, level
  info.species = E.expansionSpecies(sp, personality)
  if not info.species then return false end
  info.shiny = E.shinyFor(personality)
  -- chain shiny odds (PARITY R3): Rogue rolls 1/odds; shininess here comes
  -- from the personality, so a hit rewrites its high half (gender kept).
  if chainE and not info.shiny and E.random() % getEncounterChainShinyOdds(chainCount) == 0 then
    personality, info.shiny = E.makeShiny(personality), true
    info.species = E.expansionSpecies(sp, personality) or info.species
  end
  info.personality = personality
  info.female = E.femaleFor(sp, personality)
  if C.WE_OWE_PREVENT_SHINY_DESPAWN and info.shiny then info.noDespawn = true end
  if info.category == CAT_UNDEFINED then info.category = CAT_WILD end
  return true
end

local function abilityAllowsEncounter(level)
  local lead = E.leadMon()
  if not lead then return true end
  local ab, A = E.leadAbility(), V.abilities
  if ab ~= 0 and (ab == A.KEEN_EYE or ab == A.INTIMIDATE) then
    local pl = tonumber(lead.level) or 0
    if pl > 5 and level <= pl - 5 and E.random() % 2 == 0 then return false end
  end
  return true
end

-- Spawn.  UpdateOverworldWildEncounter
local info = {} -- struct InfoOWE, reused
local setMovementType, updateActors -- AI section below

-- sprite frame without effects; also what the Quest Log records
local function pose(a)
  local f, flip
  if a.anim then
    f, flip = animFrame(a.anim, a.animT)
  else
    f, flip = FACE_FRAME[a.facing] or 0, a.facing == "right"
    if flip and a.asym then f, flip = 6, false end
  end
  return a.sheet, f, flip, a.palRow, a.y2
end

local function draw(a, sx, sy)
  local _, f, flip = pose(a)
  E.drawShadow(a, sx, sy, a.act == ACT_JUMP_IN_PLACE)
  local grass = a.act ~= ACT_JUMP_IN_PLACE
  if grass then E.drawGrass(a, sx, sy, false) end
  local ok = E.Gfx.draw(a.sheet, f, flip, a.palRow, sx, sy + a.y2)
  if grass then E.drawGrass(a, sx, sy, true) end
  if a.icon >= 0 and ok then
    -- SpriteCB_TrainerIcons: object x, object centre - 16, + y2 + bounce
    local fh = A.sheets[(a.sheet - 1) * 6 + 4]
    local is = A.ICONS
    E.queueOverlay(is, a.icon, A.sheets[(is - 1) * 6 + 6],
      sx, sy + 16 - rshift(fh, 1) - 24 + a.y2 + a.iconY) -- OAM priority 1
  end
  return ok
end

local function spawnOWE(a, x, y)
  local sheet, row = E.Gfx.sheetFor(info.species, info.female, info.shiny)
  a.sheet, a.palRow = sheet, row
  a.asym = E.Data.ATLAS.asym[info.species] == 1
  a.species, a.engineSpecies, a.level = info.species, info.engineSpecies, info.level
  a.shiny, a.female, a.category, a.noDespawn = info.shiny, info.female, info.category, info.noDespawn
  a.personality, a.moves = info.personality, info.moves
  a.oweType, a.age, a.offScreen = "generated", 0, false
  a.cellX, a.cellY, a.targetX, a.targetY = x, y, x, y
  a.initX, a.initY = x, y
  a.px, a.py = x * 16, y * 16
  a.elevation = E.elevationAt(x, y)
  a.currentElevation = a.elevation
  a.moving, a.visible, a.invisible, a.hidden = false, true, false, false
  a.facing, a.moveDir = "down", "down"
  a.water = E.encounterKind(x, y) == "water"
  a.y2, a.icon, a.anim, a.animT = 0, -1, nil, 0
  a.saved = false -- OWE_SAVED_MOVEMENT_STATE_FLAG
  setMovementType(a)
  a.draw, a.pose = draw, pose
  a.active = true
  -- OnOverworldWildEncounterSpawn (from SpawnSpecialObjectEvent)
  sortOWEAges()
  doOWESpawnAnim(a)
end

function Owe.tick()
  if battleCo then updateBattleScript() end
  updateActors()
  updateFx()
  local water = E.surfing()
  -- ArePlayerFieldControlsLocked / CheckCurrentWildMonHeaderForOWE
  if battleCo or E.controlsLocked() or not E.wildArea(E.wildHeader(), water and "water" or "land") then
    return
  end
  -- WE_OWE_FLAG_DISABLED / WE_FLAG_NO_ENCOUNTER (V.flags, nil in FR); Pike /
  -- Pyramid / Trainer Hill: no such facilities in FR (VERSIONS)
  if E.flagGet(V.flags.oweDisabled) or E.flagGet(V.flags.noEncounter) then
    if sOWESpawnCountdown ~= OWE_NO_ENCOUNTER_SET then
      Owe.despawnAll("generated", false)
      sOWESpawnCountdown = OWE_NO_ENCOUNTER_SET
    end
    return
  elseif sOWESpawnCountdown == OWE_NO_ENCOUNTER_SET then
    setMinimumOWESpawnTimer()
  end

  if sOWESpawnCountdown > 0 then
    sOWESpawnCountdown = sOWESpawnCountdown - 1
    return
  end
  if E.playerMidStep() then return end

  local slot = getNextOWESpawnSlot()
  local x, y
  if slot then x, y = trySelectTileForOWE() end
  if not slot or (water and V.sootopolis and V.sootopolis()) or not x then
    setMinimumOWESpawnTimer()
    return
  end

  info.category, info.noDespawn, info.moves = CAT_UNDEFINED, false, nil
  info.species, info.engineSpecies = nil, nil
  local ok = setSpeciesInfoForOWE(info, x, y)
  if not ok
      or (C.WE_OWE_SPECIAL_ONLY and info.category >= CAT_WILD)
      or not E.levelAllowedByRepel(info.level)
      or not abilityAllowsEncounter(info.level)
      or not E.Gfx.sheetFor(info.species, info.female, info.shiny) then -- CheckCanLoadOWE
    setMinimumOWESpawnTimer()
    return
  end

  local a = slotActor(slot)
  if shouldDespawnGeneratedForNewOWE(a) then Owe.remove(a) end
  spawnOWE(a, x, y)
  local d = STANDARD_DIRS[band(E.random(), 3) + 1] -- ObjectEventTurn
  a.facing, a.moveDir, a.anim = d, d, ANIMS[a.asym].face[d]
  setNewOWESpawnCountdown()
end

-- DespawnAllOverworldWildEncounters(type, WILD_CHECK_REPEL?)
function Owe.despawnAll(t, checkRepel)
  for i = FIRST, LAST do
    local a = E.actors[i]
    if isOWE(a, t) then
      local keep = checkRepel and (E.repelSteps() == 0 or hasNoDespawnFlag(a)
        or E.levelAllowedByRepel(a.level))
      if not keep then Owe.remove(a) end
    end
  end
end

local function despawnExempt(a)
  return isOWE(a, "any") and hasNoDespawnFlag(a) and E.insidePlayerMap(a.cellX, a.cellY)
end

-- RemoveObjectEventsOutsideView / RemoveObjectEventIfOutsideView: camera
-- view = player -9..+10 horizontally, -7..+9 vertically (pos +/- margins)
local function inView(x, y, px, py)
  return x >= px - 9 and x <= px + 10 and y >= py - 7 and y <= py + 9
end
function Owe.removeOutsideView()
  local px, py = E.playerCur()
  for i = FIRST, LAST do
    local a = E.actors[i]
    if a.active and not despawnExempt(a)
        and not inView(a.cellX, a.cellY, px, py) and not inView(a.initX, a.initY, px, py) then
      a.offScreen = true
      Owe.remove(a)
    end
  end
end

-- TryDespawnOWEsCrossingMapConnection (called on every camera move)
local function tryDespawnCrossingMapConnection()
  if not C.WE_OWE_DESPAWN_ON_ENTER_TOWN then return end
  if not E.mapIsTown() then return end
  Owe.despawnAll("generated", false)
end

-- OWE movement types; sprite->data fields live on the actor.
local MT_WANDER, MT_CHASE, MT_FLEE, MT_WATCH, MT_APPROACH, MT_DESPAWN = 1, 2, 3, 4, 5, 6
local NEVER_RETURN, PLAYER_CANT_BE_SEEN = 0, 2
-- enum SpeedOWE -> walk frames (GetWalk{Normal,Slow,Fast,Faster}MovementAction)
local SPEED_FRAMES = { [0] = 16, 32, 8, 4 }
local sMovementDelaysOWE = { 64, 80, 96, 128 }
local OWE_RESTORED_MOVEMENT_FUNC_ID = 10
local ICON_FRAMES = 60 -- sSpriteAnim_Icons1/2: ANIMCMD_FRAME(n, 60), ANIMCMD_END

local DX = { up = 0, down = 0, left = -1, right = 1 }
local DY = { up = -1, down = 1, left = 0, right = 0 }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
-- sRotate90Direction[dir][clockwise]
local ROT90 = { down = { [0] = "right", "left" }, up = { [0] = "left", "right" },
  left = { [0] = "down", "up" }, right = { [0] = "up", "down" } }
local JUMP_Y_HIGH = { [0] = -4, -6, -8, -10, -11, -12, -12, -12, -11, -10, -9, -8, -6, -4, 0, 0 }


-- behavior of OW_SPECIES(owe): the preset row
local function behavior(a)
  local B = E.Data.OWE_BEHAVIOR
  return B[E.Data.OWE_SPECIES_BEHAVIOR[a.species] or 0] or B[0]
end

setMovementType = function(a) -- template.movementType = OWE_GetMovementTypeFromSpecies
  a.beh = behavior(a)
  a.movementType = a.beh[1]
  a.typeFunc, a.act, a.single, a.delay, a.d3, a.d6, a.jumpTimer = 0, ACT_NONE, false, 0, 0, 0, 0
end

local function randomUniform(lo, hi) return lo + E.random() % (hi - lo + 1) end

local function setDirection(a, dir) a.facing, a.moveDir = dir, dir end

-- GetDirectionToFace(owe, player) = DetermineObjectEventDirectionFromObject(player, owe)
local function dirToPlayer(a)
  local px, py = E.playerCur()
  local x, y = a.cellX, a.cellY
  if x > px then return "left" end
  if x < px then return "right" end
  if y > py then return "up" end
  return "down"
end

local function clearMovement(a)
  a.single, a.act, a.typeFunc = false, ACT_NONE, 0
end

-- ObjectEventSetSingleMovement(Step0 inits happen on the first exec, same frame)
local function setSingle(a, act, dir, n)
  a.act, a.actDir, a.actDur, a.actT = act, dir, n or 0, 0
end

local function anims(a) return ANIMS[a.asym] end

-- ObjectEventExecSingleMovementAction -> true when the action finished
local function exec(a)
  local act = a.act
  if act == ACT_NONE then return true end
  local t = a.actT
  if t == 0 then -- Step0 (init)
    local dir = a.actDir
    if act == ACT_FACE then
      setDirection(a, dir); a.anim = anims(a).face[dir]
      a.act = ACT_NONE; return true
    elseif act == ACT_EMOTE then -- MovementAction_Emote{Exclamation,Question}Mark
      a.icon, a.iconT, a.iconY, a.iconVel = a.actDur, 0, 0, -5
      a.act = ACT_NONE; return true
    elseif act == ACT_WALK then -- InitNpcForMovement + SetStepAnimHandleAlternation
      setDirection(a, dir)
      a.targetX, a.targetY = a.cellX + DX[dir], a.cellY + DY[dir]
      a.moving = true
      a.currentElevation = E.Collision.nextElevation(E.Collision._mapDef,
        a.currentElevation, a.targetX, a.targetY, a.cellX, a.cellY)
      local go = a.actDur <= 8 and anims(a).goFast[dir] or anims(a).go[dir]
      if a.anim ~= go then a.anim, a.animT = go, 0 end
    else -- InitMoveInPlace / InitJumpRegular(JUMP_DISTANCE_IN_PLACE, JUMP_TYPE_HIGH)
      setDirection(a, dir)
      local go = anims(a).go[dir]
      if a.anim ~= go then a.anim, a.animT = go, 0 end
    end
  end
  t = t + 1
  a.actT = t
  a.animT = a.animT + 1
  if act == ACT_WALK then
    local dur = a.actDur
    local p = (dur == 32) and rshift(t, 1) or math.floor(t * 16 / dur)
    a.px = a.cellX * 16 + DX[a.actDir] * p
    a.py = a.cellY * 16 + DY[a.actDir] * p
    if t >= dur then -- ShiftStillObjectEventCoords; animPaused
      a.cellX, a.cellY = a.targetX, a.targetY
      a.px, a.py, a.moving = a.cellX * 16, a.cellY * 16, false
      a.act = ACT_NONE
      return true
    end
  elseif act == ACT_IN_PLACE then
    a.d3 = a.actDur - t -- --sprite->data[3]
    if a.d3 <= 0 then a.act = ACT_NONE; return true end
  elseif act == ACT_JUMP_IN_PLACE then
    a.y2 = JUMP_Y_HIGH[t - 1] or 0
    if t >= 16 then a.y2 = 0; a.act = ACT_NONE; return true end
  end
  return false
end

-- icon sprite callback (runs while the icon exists)
local function updateIcon(a)
  if a.icon < 0 then return end
  local t = a.iconT + 1
  a.iconT = t
  if t >= ICON_FRAMES then a.icon = -1; return end -- animEnded -> FieldEffectStop
  a.iconY = a.iconY + a.iconVel
  if a.iconY ~= 0 then a.iconVel = a.iconVel + 1 else a.iconVel = 0 end
end

local function updateMonMoveInPlace(a)
  if not a.single then
    setSingle(a, ACT_IN_PLACE, a.facing, 16) -- GetWalkInPlaceNormalMovementAction
    a.single = true
    return true
  elseif exec(a) then
    a.single = false
  elseif C.OW_FOLLOWERS_BOBBING and band(a.d3, 7) == 2 then
    a.y2 = bxor(a.y2, -1)
  end
  return false
end

-- IsElevationMismatchAt(owe elevation, player coords) -> CanOWEReachPlayer
local function canOWEReachPlayer(a, px, py)
  local el = a.currentElevation
  if el == 0 then return true end
  local m = E.elevationAt(px, py)
  return m == 0 or m == 15 or m == el
end

local function isPlayerInsideActiveDistance(a)
  local distance = a.species and a.beh[4] or C.OWE_DEFAULT_CHASE_RANGE
  local px, py = E.playerCur()
  local ax, ay = px - a.cellX, py - a.cellY
  if ax < 0 then ax = -ax end
  if ay < 0 then ay = -ay end
  if ax > distance or ay > distance then return false end
  return ax + ay <= rshift(distance * 362, 8) -- distance * sqrt(2)
end

local function canAwareOWESeePlayer(a)
  if a.movementType == MT_WANDER then return false end
  local P = E.Player
  if P.moving and (P.running or P.biking) and isPlayerInsideActiveDistance(a) then
    return true
  end
  local b = a.beh
  local viewDistance, halfWidth = b[2], rshift(b[3] - 1, 1)
  local px, py = E.playerCur()
  local x, y = a.cellX, a.cellY
  local f = a.facing
  if f == "up" then
    if not (py <= y and y - py <= viewDistance and px >= x - halfWidth and px <= x + halfWidth) then return false end
  elseif f == "down" then
    if not (py >= y and py - y <= viewDistance and px >= x - halfWidth and px <= x + halfWidth) then return false end
  elseif f == "right" then
    if not (px >= x and px - x <= viewDistance and py >= y - halfWidth and py <= y + halfWidth) then return false end
  else
    if not (px <= x and x - px <= viewDistance and py >= y - halfWidth and py <= y + halfWidth) then return false end
  end
  return canOWEReachPlayer(a, px, py)
end
Owe.canSeePlayer = canAwareOWESeePlayer

-- IsOWENextToObject(owe, object at px, py)
local function isNextTo(a, px, py)
  local x, y = a.cellX, a.cellY
  if (x ~= px and y ~= py) or x < px - 1 or x > px + 1 or y < py - 1 or y > py + 1 then
    return false
  end
  return true
end

local function isNextToPlayer(a) return isNextTo(a, E.playerCur()) end

local function restrictedMetatile(x, y, nx, ny)
  if not C.WE_OWE_RESTRICT_METATILE then return false end
  local cur, new = E.encounterKind(x, y), E.encounterKind(nx, ny)
  if cur == "land" and new == "land" then return false end
  if cur == "water" and new == "water" then return false end
  if cur ~= "land" and cur ~= "water" then return false end
  return true
end

-- CheckRestrictedOWEMovementMap: OWEs are always on the player's map, so only branch 1 applies
local function restrictedMap(nx, ny)
  if not C.WE_OWE_RESTRICT_MAP then return false end
  return not E.insidePlayerMap(nx, ny)
end

-- GetCollisionAtCoords != COLLISION_NONE (tile + objects + player)
local function collisionAt(a, nx, ny, dir)
  return not E.canMove(a, nx, ny, dir, a.water)
end

-- CheckRestrictedOWEMovement: true = restricted
local function checkRestricted(a, dir)
  local x, y = a.cellX, a.cellY
  local nx, ny = x + DX[dir], y + DY[dir]
  if collisionAt(a, nx, ny, dir) then return true end
  if C.WE_OWE_UNRESTRICT_SIGHT and a.movementType ~= MT_WANDER and canAwareOWESeePlayer(a) then
    return false
  end
  if restrictedMetatile(x, y, nx, ny) then return true end
  return restrictedMap(nx, ny)
end

-- CheckRestrictedOWEMovementAtCoords: true = NOT restricted
local function unrestrictedAt(a, nx, ny, collisionDir)
  if restrictedMetatile(a.cellX, a.cellY, nx, ny) then return false end
  if restrictedMap(nx, ny) then return false end
  if collisionAt(a, nx, ny, collisionDir) then return false end
  return true
end

local function checkPathFromCollision(a, newDir)
  local md = a.moveDir
  local x, y = a.cellX + DX[newDir], a.cellY + DY[newDir]
  if unrestrictedAt(a, x, y, newDir) then
    if a.movementType == MT_FLEE then return OPPOSITE[newDir] end
    x, y = x + DX[md], y + DY[md]
    if unrestrictedAt(a, x, y, md) then return newDir end
  end
  local od = OPPOSITE[newDir]
  x, y = a.cellX + DX[od], a.cellY + DY[od]
  if unrestrictedAt(a, x, y, newDir) then
    if a.movementType == MT_FLEE then return newDir end
    x, y = x + DX[md], y + DY[md]
    if unrestrictedAt(a, x, y, md) then return od end
  end
  return md
end

local function directionFromCollision(a)
  local px, py = E.playerCur()
  local md = a.moveDir
  if md == "up" or md == "down" then
    if px < a.cellX then return "left" end
    if px == a.cellX then
      return checkPathFromCollision(a, band(E.random(), 1) ~= 0 and "right" or "left")
    end
    return "right"
  end
  if py < a.cellY then return "up" end
  if py == a.cellY then
    return checkPathFromCollision(a, band(E.random(), 1) ~= 0 and "up" or "down")
  end
  return "down"
end

-- GetApproachingOWEDistanceToPlayer -> distance, equalDistances
local function approachDistance(a)
  local px, py = E.playerCur()
  local ax, ay = px - a.cellX, py - a.cellY
  if ax < 0 then ax = -ax end
  if ay < 0 then ay = -ay end
  if ay > ax then return ay, false end
  return ax, ay == ax
end

-- GetObjectObjectCollidesWith(owe, next tile) == player
local function playerAhead(a, dir)
  local px, py = E.playerCur()
  return a.cellX + DX[dir] == px and a.cellY + DY[dir] == py
end

local function canRemoveForMovement(a)
  return not (C.WE_OWE_PREVENT_SPECIAL_MOVEMENT_DESPAWN and isOWE(a, "any") and a.noDespawn)
end

local function activeFrames(a) return SPEED_FRAMES[a.beh[6]] end

local function wander_Step0(a) -- MovementType_WanderAround_Step0
  clearMovement(a)
  a.typeFunc = 1
  return true
end
local function wander_Step1(a) -- MovementType_WanderAround_Step1
  setSingle(a, ACT_FACE, a.facing)
  a.typeFunc = 2
  return true
end
local function wander_Step2(a)
  if not exec(a) then return false end
  a.delay = sMovementDelaysOWE[E.random() % 4 + 1] -- SetMovementDelay
  a.typeFunc = 3
  return true
end
local function wander_Step3(a)
  a.delay = a.delay - 1
  if a.delay == 0 then -- WaitForMovementDelay
    a.d3 = 0
    clearMovement(a) -- resets a mid-movement sprite
    a.typeFunc = 4
    return true
  end
  if C.OW_MON_WANDER_WALK then updateMonMoveInPlace(a) end
  if canAwareOWESeePlayer(a) then a.typeFunc = 7 end
  return false
end
local function wander_Step4(a)
  local d = a.moveDir
  if band(E.random(), 3) ~= 0 then d = ROT90[d][E.random() % 2] end
  setDirection(a, d)
  a.typeFunc = 5
  if checkRestricted(a, d) then a.typeFunc = 1 end
  return true
end
local function wander_Step5(a)
  setSingle(a, ACT_WALK, a.moveDir, SPEED_FRAMES[a.beh[5]])
  a.single = true
  a.typeFunc = 6
  return true
end
local function wander_Step6(a) -- MovementType_WanderAround_Step6
  if exec(a) then
    a.single = false
    a.typeFunc = 1
  end
  return false
end

-- common aware steps
local function common_Step7(a)
  clearMovement(a)
  a.saved = true -- SetSavedOWEMovementState
  a.typeFunc = 8
  return true
end
local function common_Step9(a)
  if exec(a) then a.typeFunc = 10 end
  return true
end
local function common_Step12(a)
  if exec(a) then
    a.single = false
    a.typeFunc = 10
    local r, returnToIdle = a.beh[7], nil
    if r == NEVER_RETURN then
      returnToIdle = false
    elseif r == PLAYER_CANT_BE_SEEN then
      returnToIdle = not canAwareOWESeePlayer(a)
    else
      returnToIdle = not isPlayerInsideActiveDistance(a)
    end
    if returnToIdle then
      a.saved = false -- ClearSavedOWEMovementState
      a.typeFunc = 0
    end
  end
  return false
end
local function faceToPlayer_Step10(a) -- {Chase,Watch,Approach,Despawn}_Step10
  setDirection(a, dirToPlayer(a))
  a.typeFunc = 11
  return true
end

-- sidestep for chase / approach (walk around, but never around the player)
local function walkTowardOrAround(a)
  local frames = activeFrames(a)
  local d = a.moveDir
  if checkRestricted(a, d) then
    if playerAhead(a, d) then
      setSingle(a, ACT_FACE, a.facing)
      a.single = true
      return nil
    end
    local nd = directionFromCollision(a)
    if checkRestricted(a, nd) then
      setSingle(a, ACT_IN_PLACE, a.facing, 16)
    else
      setSingle(a, ACT_WALK, nd, frames)
    end
    return true
  end
  setSingle(a, ACT_WALK, d, frames)
  return true
end

local function chase_Step8(a)
  setDirection(a, dirToPlayer(a))
  if isNextToPlayer(a) then
    a.typeFunc = 10
    return true
  end
  setSingle(a, ACT_EMOTE, nil, 0)
  E.playSe("SE_PIN")
  a.typeFunc = 9
  return true
end
local function chase_Step11(a)
  a.typeFunc = 12
  if walkTowardOrAround(a) == nil then return false end
  a.single = true
  return true
end

local function flee_Step8(a)
  setDirection(a, OPPOSITE[dirToPlayer(a)])
  setSingle(a, ACT_EMOTE, nil, 0)
  E.playSe("SE_PIN")
  a.typeFunc = 9
  return true
end
local function flee_Step10(a)
  if C.WE_OWE_FLEE_DESPAWN and a.d6 >= C.OWE_FLEE_COLLISION_TIME and canRemoveForMovement(a) then
    Owe.remove(a)
    return false
  end
  setDirection(a, OPPOSITE[dirToPlayer(a)])
  a.typeFunc = 11
  return true
end
local function flee_Step11(a)
  local frames = activeFrames(a)
  local d = a.moveDir
  if checkRestricted(a, d) then
    local nd = directionFromCollision(a)
    if nd ~= a.moveDir then nd = OPPOSITE[nd] end
    if checkRestricted(a, nd) then
      a.d6 = a.d6 + 1
      setSingle(a, ACT_IN_PLACE, a.facing, 16)
    else
      a.d6 = 0
      setSingle(a, ACT_WALK, nd, frames)
    end
  else
    a.d6 = 0
    setSingle(a, ACT_WALK, d, frames)
  end
  a.single = true
  a.typeFunc = 12
  return true
end

local function watch_Step8(a) -- also ApproachPlayer_Step8 minus the jump timer
  setDirection(a, dirToPlayer(a))
  a.typeFunc = 10
  if not isNextToPlayer(a) then
    setSingle(a, ACT_EMOTE, nil, 1)
    a.typeFunc = 9
  end
  return true
end
local function watch_Step11(a)
  setSingle(a, ACT_IN_PLACE, a.facing, 16)
  a.single = true
  a.typeFunc = 12
  return true
end

local function approach_Step8(a)
  a.jumpTimer = randomUniform(C.OWE_APPROACH_JUMP_TIMER_MIN, C.OWE_APPROACH_JUMP_TIMER_MAX)
  return watch_Step8(a)
end
local function approach_Step11(a)
  local distance, equal = approachDistance(a)
  local frames = activeFrames(a)
  if distance <= 1 then
    setDirection(a, OPPOSITE[a.moveDir])
    local d = a.moveDir
    if checkRestricted(a, d) then
      local px, py = E.playerCur()
      local nd = directionFromCollision(a)
      if a.cellX ~= px and a.cellY ~= py then nd = OPPOSITE[nd] end
      if checkRestricted(a, nd) then
        setSingle(a, ACT_IN_PLACE, a.facing, 16)
      else
        setSingle(a, ACT_WALK, nd, frames)
      end
    else
      setSingle(a, ACT_WALK, d, frames)
    end
  elseif distance == C.OWE_APPROACH_DISTANCE and not equal then
    if a.jumpTimer <= 0 then
      a.jumpTimer = randomUniform(C.OWE_APPROACH_JUMP_TIMER_MIN, C.OWE_APPROACH_JUMP_TIMER_MAX)
      setSingle(a, ACT_JUMP_IN_PLACE, a.facing)
      E.playSe("SE_LEDGE")
    else
      a.jumpTimer = a.jumpTimer - 1
      setSingle(a, ACT_IN_PLACE, a.facing, 16)
    end
  else
    -- player dead ahead: face and stay on Step11 without resetting sJumpTimer (as in C)
    if walkTowardOrAround(a) == nil then return false end
    a.jumpTimer = randomUniform(C.OWE_APPROACH_JUMP_TIMER_MIN, C.OWE_APPROACH_JUMP_TIMER_MAX)
  end
  a.single = true
  a.typeFunc = 12
  return true
end

local function despawn_Step8(a)
  setDirection(a, dirToPlayer(a))
  setSingle(a, ACT_EMOTE, nil, 0)
  E.playSe("SE_PIN")
  a.d6 = 0
  a.typeFunc = 9
  return true
end
local function despawn_Step11(a)
  if a.d6 == C.OWE_DESPAWN_FRAMES and canRemoveForMovement(a) then
    Owe.remove(a)
    return false
  end
  setSingle(a, ACT_FACE, a.facing)
  a.single = true
  a.d6 = a.d6 + 1
  a.typeFunc = 12
  return true
end

-- gMovementTypeFuncs_*_OverworldWildEncounter
local function table13(s8, s10, s11)
  return { [0] = wander_Step0, wander_Step1, wander_Step2, wander_Step3, wander_Step4,
    wander_Step5, wander_Step6, common_Step7, s8, common_Step9, s10, s11, common_Step12 }
end
local MOVEMENT_TYPE_FUNCS = {
  [MT_WANDER] = table13(nil, nil, nil),
  [MT_CHASE] = table13(chase_Step8, faceToPlayer_Step10, chase_Step11),
  [MT_FLEE] = table13(flee_Step8, flee_Step10, flee_Step11),
  [MT_WATCH] = table13(watch_Step8, faceToPlayer_Step10, watch_Step11),
  [MT_APPROACH] = table13(approach_Step8, faceToPlayer_Step10, approach_Step11),
  [MT_DESPAWN] = table13(despawn_Step8, faceToPlayer_Step10, despawn_Step11),
}

-- movement_type_def: run the callback while it returns TRUE
local function updateMovement(a)
  local funcs = MOVEMENT_TYPE_FUNCS[a.movementType]
  while a.active and funcs[a.typeFunc](a) do end
end

-- RestoreSavedOWEBehaviorState (sprite re-created while aware)
function Owe.restoreSavedBehaviorState(a)
  if isOWE(a, "any") and a.saved then
    a.typeFunc = OWE_RESTORED_MOVEMENT_FUNC_ID
    if a.movementType == MT_APPROACH then
      a.jumpTimer = randomUniform(C.OWE_APPROACH_JUMP_TIMER_MIN, C.OWE_APPROACH_JUMP_TIMER_MAX)
    end
  end
end

-- per-frame object update for the OWE slots (ObjectEventCallback + icon)
updateActors = function()
  local frozen = E.controlsLocked() -- FreezeObjectEvents under a script lock
  for i = FIRST, LAST do
    local a = E.actors[i]
    if a.active then
      if not frozen and a ~= Owe.pending then updateMovement(a) end
      if a.active then updateIcon(a) end
    end
  end
end

function Owe.init(engine)
  E, C, V = engine, engine.C, engine.V
  ANIMS, animFrame, A = engine.Follower.ANIMS, engine.Follower.animFrame, engine.Data.ATLAS
  FIRST, LAST = 2, 1 + C.OWE_SPAWNS_MAX
  for i = 1, FX_POOL do
    local s = { uadv = true, fx = true, slot = 0, active = false, visible = true,
      cellX = 0, cellY = 0, px = 0, py = 0, raiseX = 0, raiseY = 0,
      elevation = 0, currentElevation = 0, facing = "down", localId = -200 - i,
      info = nil, sheet = 1, palRow = 0, frame = 0, timer = 0,
      xOff = 0, yOff = 0, rise = 0, sY = 0, draw = drawFx }
    s.graphicsId = s
    fxPool[i] = s
  end
  ROAMER_COUNT = V.roamerCount or 0
  CAT_OUTBREAK, CAT_FEEBAS, CAT_WILD, CAT_UNDEFINED =
    ROAMER_COUNT, ROAMER_COUNT + 1, ROAMER_COUNT + 2, ROAMER_COUNT + 3
  Owe.CAT = { OUTBREAK = CAT_OUTBREAK, FEEBAS = CAT_FEEBAS, WILD = CAT_WILD }
  for i = FIRST, LAST do clearSlot(E.actors[i]) end
end

function Owe.reset()
  Owe.cancelInteraction()
  Owe.pending = nil
  for i = FIRST, LAST do clearSlot(E.actors[i]) end
  for i = 1, FX_POOL do fxPool[i].active = false end
  sOWESpawnCountdown = OWE_NO_ENCOUNTER_SET
end

-- Coroutine created on trigger/A press, so allocations stay out of the frame loop.
local battleDone, battleActor = false, nil
local function yield() coroutine.yield() end
local CRY_MODE_DOUBLES = 1

-- DetermineObjectEventDirectionFromObject(target at tx,ty, mover at x,y)
local function dirFromTo(x, y, tx, ty)
  if x > tx then return "left" end
  if x < tx then return "right" end
  if y > ty then return "up" end
  return "down"
end

-- ObjectEventTurn (face without a held movement)
local function turn(a, d) setDirection(a, d); a.anim = anims(a).face[d] end

-- Task_OWEApproachForBattle: step until next to the player or follower.
local function approachForBattle(a)
  if not C.WE_OWE_APPROACH_FOR_BATTLE then return end -- FreezeObjectEvent
  local F, P = E.FOLLOWER, E.Player
  while a.active do
    if a.act == ACT_NONE then -- ObjectEventClearHeldMovementIfFinished
      local px, py = E.playerCur()
      local nextP = isNextTo(a, px, py)
      if nextP or (F.active and isNextTo(a, F.cellX, F.cellY)) then
        if nextP then -- ObjectEventsTurnToEachOther(player, OWE)
          P.facing = dirFromTo(px, py, a.cellX, a.cellY)
          turn(a, dirFromTo(a.cellX, a.cellY, px, py))
        else
          P.facing = dirFromTo(px, py, F.cellX, F.cellY)
          E.Follower.face(dirFromTo(F.cellX, F.cellY, a.cellX, a.cellY))
          turn(a, dirFromTo(a.cellX, a.cellY, F.cellX, F.cellY))
        end
        return
      end
      setDirection(a, dirToPlayer(a))
      local act, d = ACT_WALK, a.moveDir
      if checkRestricted(a, d) then
        local nx, ny = a.cellX + DX[d], a.cellY + DY[d]
        if F.active and not F.invisible and E.actorAt(nx, ny, a) == F then
          E.Follower.enterBall()
        elseif nx == px and ny == py then
          act, d = ACT_FACE, a.facing
        else
          d = directionFromCollision(a)
          setDirection(a, d)
        end
      end
      setSingle(a, act, d, activeFrames(a))
    end
    exec(a)
    yield()
  end
end

local function startWildBattleWithOWE(a)
  local sp = a.engineSpecies
  local done = function(result)
    battleDone = true
    onChainBattleEnd(result, sp) -- Rogue_Battle_EndWildBattle (PARITY R1)
  end
  local cat = a.category
  if cat and cat < ROAMER_COUNT then -- StartWildBattleWithOWE_CheckRoamer
    local sp, _, foe = E.roamerAt(cat)
    if sp and foe then return E.startWildBattle(foe, true, done) end
  end
  -- Spawn personality already carries gender and shininess (PARITY D31, D32).
  -- StartWildBattleWithOWE_CheckMassOutbreak: outbreak mons keep their TV moves
  local foe = { species = a.engineSpecies, level = a.level, personality = a.personality, moves = a.moves }
  return E.startWildBattle(foe, false, done)
end

local function interactWithOverworldWildEncounter(a)
  E.lock()                                             -- lock
  approachForBattle(a)                                 -- overworldwildencounterapproach
  if a.active then
    setSingle(a, ACT_EMOTE, nil, 0); exec(a)           -- applymovement ExclamationMark
    E.playSe("SE_PIN")
    -- facetogether: done by the approach task's turn / below when it is off
    if not C.WE_OWE_APPROACH_FOR_BATTLE then
      local px, py = E.playerCur()
      E.Player.facing = dirFromTo(px, py, a.cellX, a.cellY)
      turn(a, dirFromTo(a.cellX, a.cellY, px, py))
    end
    E.playCryMode(a.engineSpecies, CRY_MODE_DOUBLES)   -- playmoncry
    yield()
    while not E.cryFinished() do yield() end           -- waitmoncry
    battleDone = false
    if startWildBattleWithOWE(a) then                  -- tryoverworldwildencounter
      while not battleDone do yield() end              -- waitstate
    end
  end
  E.release()                                          -- end
end

local function beginInteraction(a)
  if battleCo then return false end
  if a.act == ACT_IN_PLACE then clearMovement(a); a.y2 = 0 end
  Owe.pending, battleActor = a, a -- gSpecialVar_LastTalked
  -- ScriptContext_SetupScript: starts on the next Owe.tick
  battleCo = coroutine.create(interactWithOverworldWildEncounter)
  return true
end

--- Drop a queued / running interaction (reset, tests).
function Owe.cancelInteraction()
  if battleCo and E.Field.locked then E.release() end
  battleCo, battleActor, Owe.pending = nil, nil, nil
end

updateBattleScript = function()
  if coroutine.status(battleCo) == "suspended" then
    local ok, err = coroutine.resume(battleCo, battleActor)
    if not ok then battleCo = nil; Owe.pending = nil; E.release(); error(err, 0) end
  end
  if battleCo and coroutine.status(battleCo) == "dead" then
    local a = battleActor
    battleCo, battleActor, Owe.pending = nil, nil, nil
    if a.active then a.typeFunc = 0 end -- no battle: UnfreezeObjectEvents
  end
end

-- src/wild_encounter_ow.c:638 tail
function Owe.trigger(a)
  if a.category and a.category < ROAMER_COUNT and not E.roamerAt(a.category) then
    Owe.remove(a)
    return
  end
  beginInteraction(a)
end

--- A press on an OWE (GetOverworlWildEncounterScript).
function Owe.interact(a) return beginInteraction(a) end

function Owe.busy() return battleCo ~= nil end

-- field_control_avatar.c:187 (tookStep) + field_camera.c:484 + camera view
function Owe.onStep(_)
  Owe.despawnAll("generated", true)
  tryDespawnCrossingMapConnection()
  Owe.removeOutsideView()
end

-- object events are rebuilt on map load; overworld.c:926/987
function Owe.onMapEntered(_)
  for i = FIRST, LAST do clearObjectEvent(E.actors[i]) end
  for i = 1, #fxPool do fxPool[i].active = false end
  setMinimumOWESpawnTimer()
  resetAmbientCry()
end

-- battle_setup.c:268 DespawnOWEOnBattleStart
function Owe.onBattleStarted(_)
  local a = Owe.pending
  if a and isOWE(a, "any") then
    clearObjectEvent(a)
    setNewOWESpawnCountdown()
  end
  Owe.pending = nil
end

function Owe.onBattleEnded(_) end

return Owe
