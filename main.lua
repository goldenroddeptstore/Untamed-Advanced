return function(mod)
  if mod.generation ~= 3 then return end

  local function include(name)
    local source = mod:read(name)
    assert(source, name .. " missing from " .. tostring(mod.path))
    local chunk = assert(load(source, "@" .. mod.path .. "/" .. name))
    return chunk()
  end

  -- Per-version assumptions live only here; nil = unsupported (feature stays off).
  local VERSIONS = {
    firered = {
      feebas = nil,          -- WE_OWE_FEEBAS_SPOTS: no Feebas tiles in FR
      outbreaks = nil,       -- mass outbreaks: not in FR
      roamers = true,        -- legendary beasts roam (RoamerMon in save)
      -- MAP_TYPE_TOWN 1 / MAP_TYPE_CITY 2 (names too, for string map types)
      townMapTypes = { MAP_TYPE_TOWN = true, MAP_TYPE_CITY = true, [1] = true, [2] = true },
      repelVar = 0x4020,     -- VAR_REPEL_STEP_COUNT
      lureVar = nil,         -- VAR_LURE_STEP_COUNT: no lures
      roamerCount = 1,       -- ROAMER_COUNT
      sootopolis = nil,      -- AreLegendariesInSootopolisPreventingEncounters (flag absent in R/S -> false)
      mapTypeIndoor = 8,     -- MAP_TYPE_INDOOR (include/constants/map_types.h)
      battleFrontier = nil,  -- WE_OWE_BATTLE_PIKE / PYRAMID
      -- follower message conditions (follower_helper.c).  Names absent here
      -- never match.  pokefirered/include/constants/metatile_behaviors.h:
      mb = { TALL_GRASS = 0x02, POND_WATER = 0x10, WATERFALL = 0x13, OCEAN_WATER = 0x15,
        PUDDLE = 0x16, SHALLOW_WATER = 0x17, SAND = 0x21, ICE = 0x23,
        CYCLING_ROAD_PULL_DOWN_GRASS = 0xD1 }, -- no LONG_GRASS / ASH_GRASS
      mapTypeUnderwater = nil, -- MAP_TYPE_UNDERWATER: no Dive in FR
      mapTypeUnderground = 4,  -- MAP_TYPE_UNDERGROUND (CurrentMapHasShadows)
      -- Script flags/vars; FR owns FLAG_TEMP_E, so hideFollower stays unmapped.
      flags = {
        followersDisabled = nil, -- B_FLAG_FOLLOWERS_DISABLED
        hideFollower = nil,      -- FLAG_TEMP_HIDE_FOLLOWER
        oweDisabled = nil,       -- WE_OWE_FLAG_DISABLED
        noEncounter = nil,       -- WE_FLAG_NO_ENCOUNTER
      },
      vars = {
        allowedSpecies = nil,    -- OW_FOLLOWERS_ALLOWED_SPECIES
        allowedMetLvl = nil,     -- OW_FOLLOWERS_ALLOWED_MET_LVL
        allowedMetLoc = nil,     -- OW_FOLLOWERS_ALLOWED_MET_LOC
      },
      -- pokefirered/include/constants/songs.h (MUS_RG_GYM in the expansion)
      songs = { MUS_RG_GYM = 275 },
      maps = {},             -- Hoenn MATCH_MAP targets: none in Kanto
      timeOfDay = nil,       -- no RTC: MSG_COND_TIME_OF_DAY never matches
      -- pokefirered/include/constants/abilities.h.  The follower code's
      -- POISON_HEAL / IMPOSTER / ILLUSION don't exist in Gen 3 (absent = never)
      abilities = { INTIMIDATE = 22, STATIC = 9, MAGNET_PULL = 42, PRESSURE = 46,
        KEEN_EYE = 51, HUSTLE = 55, CUTE_CHARM = 56, VITAL_SPIRIT = 72,
        FLASH_FIRE = 18, LIGHTNING_ROD = 31, SWARM = 68 },
      -- ChooseAmbientCrySpecies: Emerald's Route 130 (water cries unless
      -- Mirage Island) -> function() return waterOnly end; none in Kanto
      ambientWaterOnly = nil,
      -- pokefirered OBJ_EVENT_GFX_* Pokémon objects -> species (Lapras doll, Deoxys A/D stay vanilla)
      reskin = {
      [109] = 143, [110] = 21, [111] = 104, [112] = 62, [113] = 35, [114] = 18, [115] = 39,
      [116] = 16, [117] = 113, [118] = 138, [119] = 115, [120] = 25, [121] = 54, [122] = 29,
      [123] = 32, [124] = 33, [125] = 52, [126] = 86, [127] = 100, [128] = 79, [129] = 80,
      [130] = 66, [131] = 40, [132] = 84, [133] = 22, [134] = 67, [135] = 131, [136] = 145,
      [137] = 146, [138] = 144, [139] = 150, [140] = 151, [141] = 244, [142] = 245, [143] = 243,
      [144] = 249, [145] = 250, [146] = 251, [147] = 140, [150] = 386,
      },
    },
  }
  VERSIONS.leafgreen = VERSIONS.firered

  -- Emerald / Ruby / Sapphire: ids come from game3's own pokeemerald /
  -- pokeruby constants.  Metatile
  -- behaviors use game3's canonical ids (src.core.game3.mb: FR ids, RSE-only
  -- ones at 0x100 + raw), which is what Collision.behavior returns.
  local function rse(game)
    local K = require("src.core.game3.constants").of(game)
    local MB = require("src.core.game3.mb")
    local MapIds = require("src.core.game3.map_ids")
    local Runtime = require("src.core.game3.runtime")
    local Rng = require("src.core.game3.rng")
    local function id(kind, name) local ok, v = pcall(K.id, K, kind, name); return ok and v or nil end
    local function map(name) return MapIds.forConst(name, game) end
    local function session() return Runtime.getSession() end
    local function mapId() local s = session(); return s and s.map end
    local function rules()
      local ok, r = pcall(function() return require("src.core.game3.encounters").rules() end)
      return ok and r or nil
    end
    local mb = {}
    for _, n in ipairs({ "TALL_GRASS", "LONG_GRASS", "POND_WATER", "WATERFALL",
      "OCEAN_WATER", "PUDDLE", "SHALLOW_WATER", "SAND", "DEEP_SAND", "FOOTPRINTS", "ICE" }) do
      mb[n] = MB.id(n)
    end
    mb.ASH_GRASS = MB.id("ASHGRASS") -- pokeemerald spells it MB_ASHGRASS
    local maps = {}
    for _, n in ipairs({ "MAP_EVER_GRANDE_CITY", "MAP_ROUTE112", "MAP_ROUTE117_POKEMON_DAY_CARE",
      "MAP_MAUVILLE_CITY_BIKE_SHOP", "MAP_NEW_MAUVILLE_INSIDE", "MAP_SLATEPORT_CITY_STERNS_SHIPYARD_1F",
      "MAP_SLATEPORT_CITY_STERNS_SHIPYARD_2F", "MAP_LILYCOVE_CITY_DEPARTMENT_STORE_ELEVATOR",
      "MAP_SHOAL_CAVE_LOW_TIDE_ICE_ROOM", "MAP_ROUTE117" }) do
      maps[n] = map(n)
    end
    local songs = {}
    for _, n in ipairs({ "MUS_GYM", "MUS_POKE_MART", "MUS_VICTORY_ROAD", "MUS_SAILING", "MUS_MT_PYRE" }) do
      songs[n] = id("songs", n)
    end
    local ROUTE119, ROUTE130, SOOTOPOLIS = map("MAP_ROUTE119"), map("MAP_ROUTE130"), map("MAP_SOOTOPOLIS_CITY")
    local FR = VERSIONS.firered
    return {
      -- CheckFeebasAtCoords (game3's Route 119 port); mon() = the gWildFeebas entry
      feebas = {
        at = function(x, y)
          local r, m = rules(), mapId()
          return m ~= nil and m == ROUTE119 and r ~= nil and r.checkFeebas ~= nil and r.checkFeebas(m, { x = x, y = y }) == true
        end,
        mon = function()
          local r = rules()
          if not (r and r.wildExtra) then return nil end
          local ok, extra = pcall(r.wildExtra)
          return ok and extra and extra.feebas and extra.feebas.mon or nil
        end,
      },
      -- DoMassOutbreakEncounterTest / SetUpMassOutbreakEncounter (session.outbreak, rse/tv.lua)
      outbreaks = {
        test = function()
          local s = session()
          local o = s and s.outbreak
          if type(o) ~= "table" or (tonumber(o.species) or 0) == 0 or o.map ~= s.map then return false end
          return Rng.Random() % 100 < (tonumber(o.probability) or 0)
        end,
        mon = function()
          local o = session().outbreak
          local moves = type(o.moves) == "table" and { o.moves[1], o.moves[2], o.moves[3], o.moves[4] } or nil
          return tonumber(o.species), tonumber(o.level) or 1, moves
        end,
      },
      roamers = true,          -- Latias / Latios
      roamerCount = 1,
      townMapTypes = FR.townMapTypes,
      repelVar = id("vars", "VAR_REPEL_STEP_COUNT"),
      lureVar = nil,
      -- AreLegendariesInSootopolisPreventingEncounters (flag absent in R/S -> false)
      sootopolis = function()
        local f, s = id("flags", "FLAG_LEGENDARIES_IN_SOOTOPOLIS"), session()
        if not (f and s and s.map == SOOTOPOLIS) then return false end
        return require("src.core.game3.scripting.flags").getFlag(s, nil, f) == true
      end,
      mapTypeIndoor = 8,
      battleFrontier = nil,    -- Pike / Pyramid keep game3's own encounters
      mb = mb,
      mapTypeUnderwater = 5,   -- MAP_TYPE_UNDERWATER
      mapTypeUnderground = 4,
      flags = FR.flags,
      vars = FR.vars,
      songs = songs,
      maps = maps,
      timeOfDay = nil,         -- vanilla RSE has no day/night
      abilities = FR.abilities, -- same Gen 3 ids
      -- ChooseAmbientCrySpecies: Route 130 without Mirage Island -> water cries
      ambientWaterOnly = function()
        if mapId() ~= ROUTE130 then return false end
        local ok, F = pcall(require, "src.core.game3.scripting.natives_field_rse")
        return not (ok and F.isMirageIslandPresent and F.isMirageIslandPresent(session()))
      end,
      -- OBJ_EVENT_GFX_* Pokémon objects -> species (dolls, the Kyogre/Groudon/
      -- Rayquaza cutscene sprites, Deoxys, Kecleon's shadow stay vanilla)
      reskin = game == "emerald" and {
        [98] = 263, [208] = 263, [203] = 300, [204] = 352, [209] = 25, [210] = 184,
        [211] = 278, [214] = 298, [220] = 261, [225] = 281, [226] = 356, [228] = 185,
        [229] = 151, [187] = 380, [188] = 381, [200] = 377, [201] = 378, [202] = 379,
        [237] = 249, [238] = 250,
      } or { -- pokeruby
        [98] = 261, [208] = 263, [203] = 300, [204] = 352, [209] = 25, [210] = 184,
        [211] = 278, [214] = 298, [187] = 380, [188] = 381, [200] = 377, [201] = 378,
        [202] = 379,
      },
    }
  end
  VERSIONS.emerald = function() return rse("emerald") end
  VERSIONS.ruby = function() return rse("ruby") end
  VERSIONS.sapphire = function() return rse("sapphire") end

  local version = require("src.core.GameVersion").get()
  local V = VERSIONS[version]
  if type(V) == "function" then -- built after game3 loads its constants
    local ok, row = pcall(V)
    if not ok then
      mod.log:error("%s VERSIONS row failed (%s); mod disabled", version, tostring(row))
      return
    end
    V = row
  end
  if not V then
    mod.log:error("no VERSIONS row for %q; mod disabled", tostring(version))
    return
  end

  -- Menu options (key, default, label) first, then locked settings (key,
  -- value, nil): locked ones are fixed for this hack and not shown.
  local FLAGS = {
    { "OW_FOLLOWERS_ENABLED",        true,  "Followers" },
    { "WE_OW_ENCOUNTERS",            true,  "OW encounters" },
    -- pokeemerald-rogue encounter chaining (not expansion; PARITY R1-R4)
    { "OWE_ROGUE_CHAIN",             true,  "Chaining" },
    { "OW_FOLLOWERS_BOBBING",        true,  "Bobbing" },
    { "OW_MON_WANDER_WALK",          true,  "Marching" },
    { "WE_VANILLA_RANDOM",           false, "Random battles" },
    { "WE_OWE_RESTRICT_METATILE",    true,  "Limit movement" },
    -- not expansion (D40): FR's own Pokémon objects use the mod's sprites
    { "OW_STATIC_RESKIN",            true,  "Mod sprites" },
    -- locked
    { "OW_FOLLOWERS_POKEBALLS",      true },
    { "OW_FOLLOWERS_APPEAR_NOW",     true }, -- not expansion (D39)
    { "OW_FOLLOWERS_WEATHER_FORMS",  true },
    { "OW_FOLLOWERS_COPY_WILD_PKMN", false },
    { "OW_FOLLOWERS_SCRIPT_MOVEMENT", true },
    { "OW_SUBSTITUTE_PLACEHOLDER",   true },
    { "OW_OBJECT_VANILLA_SHADOWS",   true },
    { "WE_OWE_SPECIAL_ONLY",         false },
    { "WE_OWE_RESTRICT_MAP",         true },
    { "WE_OWE_UNRESTRICT_SIGHT",     false },
    { "WE_OWE_SPAWN_REPLACEMENT",    true },
    { "WE_OWE_FLEE_DESPAWN",         false },
    { "WE_OWE_SHINY_SPARKLE",        true },
    { "WE_OWE_FEEBAS_SPOTS",         true },
    { "WE_OWE_DESPAWN_SOUND",        false },
    { "WE_OWE_APPROACH_FOR_BATTLE",  false },
    { "WE_OWE_PREVENT_SHINY_DESPAWN", true },
    { "WE_OWE_PREVENT_FEEBAS_DESPAWN", false },
    { "WE_OWE_PREVENT_SPECIAL_MOVEMENT_DESPAWN", true },
    { "WE_OWE_DESPAWN_ON_ENTER_TOWN", true },
    { "WE_OWE_NO_REPEL_DEXNAV_COLLISION", false },
  }
  -- include/config/overworld.h:152-159 OW_AMBIENT_CRIES (enum, not a flag)
  local AMBIENT = { { "NONE", 0 }, { "VANILLA", 1 }, { "OWE PRIORITY", 2 }, { "OWE ONLY", 3 } }
  local schema = {}
  for _, f in ipairs(FLAGS) do
    if f[3] then
      schema[#schema + 1] = { key = f[1], label = f[3], type = "toggle", default = f[2] }
    end
  end
  schema[#schema + 1] = { key = "OW_AMBIENT_CRIES", label = "Ambient cries",
    type = "choice", default = 1, choices = AMBIENT }
  mod.options:define(schema)

  -- Flat option cache, refreshed on change, so hot paths skip mod.options:get.
  local C = {
    -- include/wild_encounter_ow.h, src/wild_encounter_ow.c:46-58
    OWE_SPAWNS_MAX = 4,
    OWE_APPROACH_DISTANCE = 2,
    OWE_APPROACH_JUMP_TIMER_MIN = 16,
    OWE_APPROACH_JUMP_TIMER_MAX = 64,
    OWE_FLEE_COLLISION_TIME = 6,
    OWE_DESPAWN_FRAMES = 30,
    OWE_SPAWN_DISTANCE_LAND = 1,
    OWE_SPAWN_DISTANCE_WATER = 3,
    OWE_SPAWN_WIDTH_TOTAL = 15,
    OWE_SPAWN_HEIGHT_TOTAL = 9,
    OWE_SPAWN_WIDTH_RADIUS = 7,
    OWE_SPAWN_HEIGHT_RADIUS = 4,
    OWE_SPAWN_TIME_REPLACEMENT = 240,
    OWE_SPAWN_TIME_LURE = 0,
    OWE_SPAWN_TIME_MINIMUM = 30,
    OWE_SPAWN_TIME_PER_ACTIVE = 30,
    OWE_DEFAULT_CHASE_RANGE = 5,
    -- rogue_controller.c GetEncounterChainShinyOdds (Gen 3 base 1/8192)
    OWE_CHAIN_BASE_SHINY_ODDS = 8192,
    OWE_CHAIN_SHINY_TARGET = 16,
    OWE_CHAIN_SHINY_MAX_COUNT = 48,
    OWE_CHAIN_POPUP_FRAMES = 150,
  }
  local function readOptions()
    for _, f in ipairs(FLAGS) do
      local v = f[3] and mod.options:get(f[1])
      if v == nil or not f[3] then v = f[2] end
      C[f[1]] = v and true or false
    end
    C.OW_AMBIENT_CRIES = tonumber(mod.options:get("OW_AMBIENT_CRIES")) or 1
    -- features the running version cannot support stay off
    if not V.feebas then C.WE_OWE_FEEBAS_SPOTS = false end
  end
  readOptions()

  -- All game3 access goes through E; a missing function disables the mod instead of crashing.
  local E = { V = V, C = C, version = version, log = mod.log }
  local REQUIRED = {
    { "Field",      "src.core.game3.field",         { "update", "interact" } },
    { "FieldView",  "src.core.game3.field_view",    { "draw" } },
    { "Objects",    "src.core.game3.objects",       { "forDraw", "at", "blocks", "playerBlocks", "elevationsCompatible" } },
    { "Collision",  "src.core.game3.collision",     { "canEnter", "behavior", "isSurfable", "ledgeLanding", "nextElevation",
      "inBounds", "elevationAt", "isWalkable", "isWater" } },
    { "Forced",     "src.core.game3.forced_movement", { "isForced", "isForcedMovementTile", "fieldControlsLocked" } },
    { "Runtime",    "src.core.game3.runtime",       { "getSession" } },
    { "Pokemon",    "src.core.game3.pokemon",       { "speciesOf", "national", "isEgg", "isShiny", "unownLetter" } },
    { "OwSprites",  "src.core.game3.ow_sprites",    { "draw" } },
    { "Player",     "src.core.game3.player",        {} },
    { "Encounters", "src.core.game3.encounters",    { "terrainAt", "tableFor" } },
    { "Battle",     "src.core.game3.battle_bridge", { "startWild" } },
  }
  for _, r in ipairs(REQUIRED) do
    local ok, m = pcall(require, r[2])
    if not ok or type(m) ~= "table" then
      mod.log:error("engine module %s unavailable (%s); mod disabled", r[2], tostring(m))
      return
    end
    for _, fn in ipairs(r[3]) do
      if type(m[fn]) ~= "function" then
        mod.log:error("%s.%s missing -- engine changed; mod disabled", r[2], fn)
        return
      end
    end
    E[r[1]] = m
  end
  -- optional modules: a missing one only turns its feature off
  for name, path in pairs({
    Audio = "src.core.game3.audio", FieldWeather = "src.core.game3.field_weather",
    Types = "src.core.game3.battle.types", Rng = "src.core.game3.rng",
    Message = "src.ui.game3.message", Map = "src.core.game3.map",
    Roamer = "src.core.game3.roamer", FieldEffects = "src.core.game3.field_effects",
    Doors = "src.core.game3.doors", Warp = "src.core.game3.warp",
    Movement = "src.core.game3.scripting.movement", Heal = "src.core.game3.pokecenter_heal",
    QuestRecorder = "src.core.game3.quest_log_recorder", QuestLogUI = "src.ui.game3.quest_log",
  }) do
    local ok, m = pcall(require, path)
    if ok and type(m) == "table" then E[name] = m end
  end

  -- Actor pool shaped like engine EOs so field_view sorts them. Slot 1 = follower, rest = OWEs.
  local POOL = 1 + C.OWE_SPAWNS_MAX
  local actors = {}
  for i = 1, POOL do
    local a = {
      uadv = true, slot = i, active = false,
      visible = true, hidden = false, invisible = false,
      cellX = 0, cellY = 0, px = 0, py = 0, raiseX = 0, raiseY = 0,
      targetX = 0, targetY = 0, moving = false, animClock = 0, stepFrames = 16,
      stepFlip = false, facing = "down", elevation = 3, currentElevation = 3,
      customFrame = nil, localId = -100 - i, def = nil,
      oweType = nil, -- "generated" | "manual" (OWE_GENERATED / OWE_MANUAL)
      draw = nil, -- function(actor, sx, sy, walkPhase, stepFlip)
    }
    a.graphicsId = a
    actors[i] = a
  end
  E.actors = actors
  E.FOLLOWER = actors[1]

  --- Active actor on (x, y), excluding `except`.  Integer compare, no alloc.
  function E.actorAt(x, y, except)
    for i = 1, POOL do
      local a = actors[i]
      if a.active and a ~= except then
        if (a.cellX == x and a.cellY == y)
            or (a.moving and a.targetX == x and a.targetY == y) then
          return a
        end
      end
    end
    return nil
  end

  -- draw injection: forDraw appends our actors only while FieldView.draw runs
  local inFieldDraw = false
  local drawSerial = 0
  local FieldView, Objects, OwSprites = E.FieldView, E.Objects, E.OwSprites

  -- Priority-1 overlays (emotes, '!'/'?') queue here and flush after the actor passes.
  local OVL_MAX = 1 + C.OWE_SPAWNS_MAX
  local ovl = {}
  for i = 1, OVL_MAX * 5 do ovl[i] = 0 end
  local ovlN = 0
  function E.queueOverlay(sheet, frame, palRow, sx, sy)
    if ovlN >= OVL_MAX or E.redrawing then return end
    local b = ovlN * 5
    ovl[b + 1], ovl[b + 2], ovl[b + 3], ovl[b + 4], ovl[b + 5] = sheet, frame, palRow, sx, sy
    ovlN = ovlN + 1
  end
  local function flushOverlays()
    if ovlN == 0 then return end
    local G = E.Gfx
    G.bind()
    for i = 0, ovlN - 1 do
      local b = i * 5
      G.draw(ovl[b + 1], ovl[b + 2], false, ovl[b + 3], ovl[b + 4], ovl[b + 5])
    end
    G.unbind()
    ovlN = 0
  end
  E.flushOverlays = flushOverlays

  local FX = E.FieldEffects
  -- On the GBA objects south of the player draw over its grass cover; redraw them after it.
  -- redraw in field_view's sort order (sortY, localId)
  local redrawList, redrawKey = {}, {}
  local function sortKey(a)
    local y = a.py
    if a.moving and a.targetY > a.cellY and a.targetY * 16 > y then y = a.targetY * 16 end
    return y
  end
  local function redrawOverPlayerGrass(playerPy)
    local fx = FX._fx
    if not fx or not playerPy then return end
    local gx, gy = fx.cx * 16, fx.cy * 16
    local n, hit = 0, false
    for i = 1, POOL do
      local a = actors[i]
      if a.active and a.visible and a.draw and a.drawnAt == drawSerial and a.py > playerPy then
        if a.py < gy + 32 and a.px > gx - 16 and a.px < gx + 16 then hit = true end
        local k = sortKey(a)
        local j = n
        while j > 0 and (redrawKey[j] > k or (redrawKey[j] == k
            and redrawList[j].localId > a.localId)) do
          redrawList[j + 1], redrawKey[j + 1] = redrawList[j], redrawKey[j]
          j = j - 1
        end
        redrawList[j + 1], redrawKey[j + 1] = a, k
        n = n + 1
      end
    end
    if not hit then return end
    E.redrawing = true
    E.Gfx.bind()
    for i = 1, n do
      local a = redrawList[i]
      a.draw(a, a.lastSx, a.lastSy)
    end
    E.Gfx.unbind()
    E.redrawing = false
  end
  if FX and FX.drawFront then
    local rawFront = FX.drawFront
    FX.drawFront = function(camX, camY, playerPy, ...)
      local r = rawFront(camX, camY, playerPy, ...)
      if inFieldDraw then
        redrawOverPlayerGrass(playerPy)
        flushOverlays()
      end
      return r
    end
  end

  local rawFieldDraw = FieldView.draw
  FieldView.draw = function(...)
    drawSerial = drawSerial + 1
    inFieldDraw = true
    ovlN = 0
    local ok, a, b, c = pcall(rawFieldDraw, ...)
    inFieldDraw = false
    if not ok then ovlN = 0; E.Gfx.unbind(); E.redrawing = false; error(a, 0) end
    if ovlN > 0 then flushOverlays() end
    return a, b, c
  end

  local rawForDraw = Objects.forDraw
  Objects.forDraw = function()
    local list = rawForDraw()
    if inFieldDraw then
      local n = #list
      for i = 1, POOL do
        local a = actors[i]
        if a.active and a.visible and a.draw then
          n = n + 1
          list[n] = a
        end
      end
      local fx = E.Owe and E.Owe.fx
      if fx then
        for i = 1, #fx do
          if fx[i].active then n = n + 1; list[n] = fx[i] end
        end
      end
    end
    return list
  end

  local RESKIN = V.reskin or {} -- OBJ_EVENT_GFX_* Pokémon objects -> species
  local reskinSheet, reskinRow = {}, {} -- species -> sheet / palette row (false = no sheet)
  local staticT = 0

  local rawOwDraw = OwSprites.draw
  local questGid = {} -- recorded id -> parsed pose (false = not ours)
  OwSprites.draw = function(gid, px, py, camX, camY, facing, walkPhase, stepFlip, opts)
    if type(gid) == "table" and gid.uadv then
      gid.lastSx, gid.lastSy, gid.drawnAt = px - camX, py - camY, drawSerial
      local G = E.Gfx
      G.bind()
      local r = gid.draw(gid, px - camX, py - camY, walkPhase, stepFlip)
      G.unbind()
      return r ~= false
    end
    local sp = C.OW_STATIC_RESKIN and (RESKIN[gid] or (type(gid) == "string" and RESKIN[tonumber(gid)]))
    if sp then
      local sheet = reskinSheet[sp]
      if sheet == nil then
        local s, row = E.Gfx.sheetFor(sp, false, false)
        if s == E.Data.ATLAS.SUBSTITUTE then s = nil end
        sheet, reskinRow[sp] = s or false, row
        reskinSheet[sp] = sheet
      end
      if sheet then
        -- idle = the follower's walk-in-place at half speed (bobbing) or a still face frame
        local dir = facing or "down"
        local Fo = E.Follower
        local T = Fo.ANIMS[E.Data.ATLAS.asym[sp] == 1]
        local f, flip
        if C.OW_FOLLOWERS_BOBBING or (walkPhase and walkPhase ~= 0) then
          f, flip = Fo.animFrame(T.go[dir] or T.go.down, math.floor(staticT / 2))
        else
          f, flip = Fo.animFrame(T.face[dir] or T.face.down, 0)
        end
        return E.Gfx.draw(sheet, f, flip, reskinRow[sp], px - camX, py - camY)
      end
    end
    if type(gid) == "string" then
      local r = questGid[gid]
      if r == nil then
        local s, f, fl, row, y2 = gid:match("^uadv:(%d+):(%d+):(%d):(%d+):(%-?%d+)$")
        s = tonumber(s)
        r = (s and s <= #E.Data.ATLAS.sheets / 6)
          and { s, tonumber(f), fl == "1", tonumber(row), tonumber(y2) } or false
        questGid[gid] = r
      end
      if r then
        -- the Quest Log UI greys past scenes with its own shader, which ours replaces
        local QL = E.QuestLogUI
        local gray = QL and QL.shader and love.graphics.getShader() == QL.shader
        local G = E.Gfx
        if gray and G.ready then G.shader:send("gray", 1) end
        local ok = G.draw(r[1], r[2], r[3], r[4], px - camX, py - camY + r[5])
        if gray and G.ready then G.shader:send("gray", 0) end
        return ok
      end
    end
    return rawOwDraw(gid, px, py, camX, camY, facing, walkPhase, stepFlip, opts)
  end

  -- Quest Log frames are saved, so actors go in as a data-only "uadv:..." id;
  -- the engine skips ids it can't resolve, so saves stay safe without the mod.
  local QR = E.QuestRecorder
  if QR and type(QR.capture) == "function" then
    local rawCapture = QR.capture
    QR.capture = function(...)
      local f = rawCapture(...)
      if type(f) == "table" and type(f.actors) == "table" then
        local list = f.actors
        for i = 1, POOL do
          local a = actors[i]
          if a.active and a.visible and a.pose then
            local s, fr, fl, row, y2 = a.pose(a)
            if s then
              list[#list + 1] = { id = a.localId, x = a.px, y = a.py, facing = a.facing,
                graphicsId = string.format("uadv:%d:%d:%d:%d:%d", s, fr, fl and 1 or 0, row, y2 or 0) }
            end
          end
        end
      end
      return f
    end
  end

  -- canEnter records the mover from opts.fromX/fromY, since Objects.blocks doesn't name it.
  local Collision, Player = E.Collision, E.Player
  local PLAYER = { isPlayer = true } -- mover/obstacle sentinel for the avatar
  E.PLAYER = PLAYER
  local FOLLOWER = actors[1]
  local elevOk = Objects.elevationsCompatible
  local mover = nil -- current collision mover, nil = unknown (no side effects)

  local function isOwe(a) return a.uadv == true and a.slot > 1 end
  E.isOwe = isOwe

  -- src/wild_encounter_ow.c:1052 DespawnOWEDueToNPCCollision
  local function despawnOWEDueToNPCCollision(obstacle, active)
    if active.isPlayer then return false end
    if active.uadv then return false end -- OWE (or follower, which never collides)
    if not (isOwe(obstacle) and obstacle.oweType == "generated") then return false end
    E.Owe.remove(obstacle)
    return true
  end

  -- src/wild_encounter_ow.c:638 TryTriggerOverworldWildEncounter
  local function tryTrigger(obstacle, collider)
    if C.WE_OWE_NO_REPEL_DEXNAV_COLLISION and E.repelSteps() > 0 then return end
    local wild
    if (collider.isPlayer or collider == FOLLOWER) and isOwe(obstacle) then
      wild = obstacle
    elseif (obstacle.isPlayer or obstacle == FOLLOWER) and isOwe(collider) then
      wild = collider
    else
      return
    end
    E.Owe.trigger(wild)
  end

  --- Port of GetObjectObjectCollidesWith restricted to pool obstacles.
  --- Returns the blocking actor or nil.  `m` = mover (PLAYER, engine EO, actor).
  local function poolCollides(m, x, y, elevation)
    if m == FOLLOWER then return nil end -- follower collides with nothing
    for i = 1, POOL do
      local a = actors[i]
      -- the player never collides with the follower (MOVEMENT_TYPE_FOLLOW_PLAYER)
      if a.active and a ~= m and not (a == FOLLOWER and m.isPlayer) then
        -- currentCoords / previousCoords == cell / target while stepping
        if ((a.cellX == x and a.cellY == y)
            or (a.moving and a.targetX == x and a.targetY == y))
            and elevOk(elevation, a.currentElevation) then
          if not despawnOWEDueToNPCCollision(a, m) then
            tryTrigger(a, m)
            return a
          end
        end
      end
    end
    return nil
  end
  E.poolCollides = poolCollides

  local rawCanEnter = Collision.canEnter
  Collision.canEnter = function(game, tx, ty, opts)
    if mover then return rawCanEnter(game, tx, ty, opts) end
    local fx, fy = opts and opts.fromX, opts and opts.fromY
    if fx and fx == Player.cellX and fy == Player.cellY then
      mover = PLAYER
    elseif fx then
      mover = Objects.at(fx, fy) -- engine EO stepping (or nil)
    end
    local ok, r1, r2 = pcall(rawCanEnter, game, tx, ty, opts)
    mover = nil
    if not ok then error(r1, 0) end
    return r1, r2
  end

  local rawBlocks = Objects.blocks
  Objects.blocks = function(tx, ty, exceptLocalId, elevation)
    local m = mover
    if m == nil and exceptLocalId ~= nil then
      m = E.eoById(exceptLocalId)
    end
    if m == FOLLOWER then return false end
    if rawBlocks(tx, ty, exceptLocalId, elevation) then return true end
    if m and m.uadv then
      -- our actor vs the avatar (engine EOs were covered by rawBlocks)
      if Objects.playerBlocks(tx, ty, elevation) then
        tryTrigger(PLAYER, m)
        return true
      end
    end
    if m then return poolCollides(m, tx, ty, elevation) ~= nil end
    -- unknown mover: block on any pool actor except the follower, no effects
    for i = 2, POOL do
      local a = actors[i]
      if a.active and ((a.cellX == tx and a.cellY == ty)
          or (a.moving and a.targetX == tx and a.targetY == ty))
          and elevOk(elevation, a.currentElevation) then
        return true
      end
    end
    return false
  end

  function E.eoById(localId)
    local byId = Objects._byId
    return byId and byId[localId] or nil
  end

  --- Can pool actor `a` step onto (tx, ty) going `dir`?  Tile + EO + avatar
  --- + pool collision, with the actor as the named mover.
  local moveOpts = {} -- reused: canMove runs per OWE step decision
  function E.canMove(a, tx, ty, dir, surfing)
    local prev = mover
    mover = a
    moveOpts.fromX, moveOpts.fromY, moveOpts.dir = a.cellX, a.cellY, dir
    moveOpts.elevation, moveOpts.surfing = a.currentElevation, surfing or false
    local ok, r1, r2 = pcall(rawCanEnter, E.Field._game, tx, ty, moveOpts)
    mover = prev
    if not ok then error(r1, 0) end
    return r1, r2
  end

  -- Player / party / map queries. No allocation.
  local Forced, Runtime, Pokemon = E.Forced, E.Runtime, E.Pokemon

  --- gPlayerParty (session party table) or nil
  function E.party()
    local s = Runtime.getSession()
    return s and s.party
  end

  function E.controlsLocked() return Forced.fieldControlsLocked() end

  -- gMapHeader.mapType == MAP_TYPE_INDOOR
  function E.mapIndoor()
    local def = Collision._mapDef
    return def ~= nil and tonumber(def.mapType) == V.mapTypeIndoor
  end

  -- player currentCoords / previousCoords (pret shifts current to the
  -- destination when a step starts; previous keeps the origin until idle)
  function E.playerCur()
    if Player.moving then return Player.targetX, Player.targetY end
    return Player.cellX, Player.cellY
  end
  -- tryConnection leaves prevCellX on the old map; fall back to cellX when it's > 2 cells away.
  function E.playerPrev()
    if Player.moving then
      local x, y = Player.prevCellX, Player.prevCellY
      local dx, dy = x - Player.targetX, y - Player.targetY
      if dx >= -2 and dx <= 2 and dy >= -2 and dy <= 2 then return x, y end
    end
    return Player.cellX, Player.cellY
  end

  -- Tile half cached per (prev, cur, map); it only changes when the player moves.
  local fvPX, fvPY, fvCX, fvCY, fvDef, fvOk
  function E.followerVisible()
    if Player.surfing or Player.surfHopping or Player.biking or Forced.isForced() then
      return false
    end
    local px, py = E.playerPrev()
    local cx, cy = E.playerCur()
    local def = Collision._mapDef
    if px ~= fvPX or py ~= fvPY or cx ~= fvCX or cy ~= fvCY or def ~= fvDef then
      fvPX, fvPY, fvCX, fvCY, fvDef = px, py, cx, cy, def
      fvOk = not Collision.isSurfable(Collision.behavior(px, py))
        and not Forced.isForcedMovementTile(Collision.behavior(cx, cy))
    end
    return fvOk
  end

  --- GetMonInfo: expansion species id (== national dex, Unown letters at
  --- SPECIES_UNOWN_B + n - 1), shiny, female.  nil species for eggs/none.
  function E.monInfo(mon)
    if not mon or Pokemon.isEgg(mon) then return nil end
    local nat = E.expansionSpecies(Pokemon.speciesOf(mon), mon.personality or 0)
    if not nat then return nil end
    return nat, Pokemon.isShiny(mon), mon.gender == "F"
  end

  -- VarGet(id) on the session (script vars); 0 when the version has no var
  local function sessionVar(id)
    if not id then return 0 end
    local s = Runtime.getSession()
    local vars = s and s.vars
    return type(vars) == "table" and tonumber(vars[id]) or 0
  end

  E.varGet = sessionVar

  -- FlagGet(id); nil id (flag "0" in the expansion config) = FALSE
  local okFlags, Flags = pcall(require, "src.core.game3.scripting.flags")
  function E.flagGet(id)
    if not id or not okFlags then return false end
    return Flags.getFlag(Runtime.getSession(), nil, id) == true
  end

  -- REPEL_STEP_COUNT (game3 mirrors it in session.repelSteps)
  function E.repelSteps()
    local s = Runtime.getSession()
    return (s and tonumber(s.repelSteps)) or sessionVar(V.repelVar)
  end

  -- LURE_STEP_COUNT: no lures before Gen 8 items -> 0
  function E.lureSteps() return sessionVar(V.lureVar) end

  -- Spawner queries run on countdown expiry or a step, never per frame.
  function E.surfing() return Player.surfing == true or Player.surfHopping == true end

  -- player currentCoords != previousCoords
  function E.playerMidStep() return Player.moving == true end

  function E.insidePlayerMap(x, y) return Collision.inBounds(x, y) end

  -- MapGridGetElevationAt (ELEVATION_TRANSITION 0 / ELEVATION_MULTI_LEVEL 15)
  function E.elevationAt(x, y) return Collision.elevationAt(x, y) or 0 end

  -- MapGridGetCollisionAt != 0 (water is passable data-wise; surfing decides)
  function E.collisionAt(x, y)
    return not (Collision.isWalkable(x, y) or Collision.isWater(x, y))
  end

  -- MetatileBehavior_IsLandWildEncounter / IsWaterWildEncounter: FR decides
  -- by the metatile's encounter type, which terrainAt resolves
  function E.encounterKind(x, y) return E.Encounters.terrainAt(x, y) end

  -- Cached per map id; cleared by E.invalidateMapCaches.
  local headerMap, headerVal = nil, nil
  function E.wildHeader()
    local id = E.mapId()
    if id ~= nil and id == headerMap then return headerVal end
    local ok, t = pcall(E.Encounters.tableFor, id)
    headerMap, headerVal = id, (ok and type(t) == "table") and t or nil
    return headerVal
  end

  -- map-bound caches (wild header, follower tile test): cleared on map load
  function E.invalidateMapCaches()
    headerMap, headerVal = nil, nil
    fvDef = false
  end

  -- landMonsInfo / waterMonsInfo as a slot list, nil when absent
  function E.wildArea(header, kind)
    local area = header and (kind == "water" and header.water or (header.land or header.grass))
    if type(area) ~= "table" then return nil end
    local slots = area.slots or area.mons or area
    if type(slots) ~= "table" or #slots == 0 then return nil end
    return slots
  end

  function E.random32()
    if Rng and Rng.Random32 then return Rng.Random32() end
    return E.random() + E.random() * 65536
  end

  -- lead party mon (gParties[B_TRAINER_PLAYER][0]), nil for an egg/none
  function E.leadMon()
    local p = E.party()
    local m = p and p[1]
    if not m or Pokemon.isEgg(m) then return nil end
    return m
  end

  function E.leadAbility()
    local m = E.leadMon()
    return m and E.monAbility(m) or 0
  end

  function E.speciesTypes(species)
    local t = Pokemon.types and Pokemon.types(species)
    if not t then return -1, -1 end
    return t[1] or -1, t[2] or t[1] or -1
  end

  -- IsWildLevelAllowedByRepel (I_REPEL_INCLUDE_FAINTED = GEN_LATEST)
  function E.levelAllowedByRepel(level)
    if E.repelSteps() == 0 then return true end
    local p = E.party()
    if not p then return false end
    for i = 1, 6 do
      local m = p[i]
      if m and not Pokemon.isEgg(m) then return level >= (tonumber(m.level) or 0) end
    end
    return false
  end

  -- ComputePlayerShinyOdds(personality, READ_OTID_FROM_SAVE)
  function E.shinyFor(personality)
    local s = Runtime.getSession() or {}
    local id = tonumber(s.trainerId or s.id or s.playerId) or 0
    local sid = tonumber(s.secretId or s.otSecretId) or math.floor(id / 65536)
    return Pokemon.isShiny({ personality = personality, otId = id % 65536, otSecretId = sid % 65536 })
  end

  -- Shiny personality with the same low half (gender, Unown bits of the
  -- low bytes): hi = tid ^ sid ^ lo ^ r, r < 8  (PARITY R3)
  function E.makeShiny(personality)
    local s = Runtime.getSession() or {}
    local id = tonumber(s.trainerId or s.id or s.playerId) or 0
    local sid = tonumber(s.secretId or s.otSecretId) or math.floor(id / 65536)
    local lo = personality % 65536
    local hi = bit.bxor(id % 65536, sid % 65536, lo, E.random() % 8)
    return hi * 65536 + lo
  end

  -- One popup slot, newest wins; slides down 2px/frame at top-right.
  local popup = { timer = 0, text = "", broke = false }
  local okChrome, Chrome = pcall(require, "src.ui.game3.chrome")
  local okFont, Font = pcall(require, "src.ui.game3.frlg_font")
  local nativeUi = okChrome and okFont and Chrome.mapPopupFrame and Font.draw
  function E.popup(species, count)
    local ok, name = pcall(Pokemon.name, species)
    if not ok or type(name) ~= "string" then name = tostring(species) end
    popup.broke = count == nil
    popup.text = popup.broke and (name .. " chain broke!") or (name .. " chain x" .. count)
    -- already on screen: refresh text without replaying the slide-in
    local full = C.OWE_CHAIN_POPUP_FRAMES
    popup.timer = (popup.timer > 12 and popup.timer < full - 12) and full - 12 or full
  end
  function E.tickPopup() if popup.timer > 0 then popup.timer = popup.timer - 1 end end
  function E.drawPopup(vp)
    if popup.timer <= 0 or not (love and love.graphics) then return end
    local g, sc = love.graphics, vp.scale or 1
    local elapsed = C.OWE_CHAIN_POPUP_FRAMES - popup.timer
    local tPos = math.min(24, elapsed * 2, popup.timer * 2)
    if tPos <= 0 then return end
    if nativeUi then
      local textW = (Font.measure and Font.measure(popup.text)) or 6 * #popup.text
      local tiles = math.ceil((textW + 8) / 8)
      local gameW = math.floor(vp.gameWidth / sc + 0.5)
      local px, py = gameW - (tiles + 2) * 8, tPos - 24
      g.push()
      g.translate(vp.gameX, vp.gameY)
      g.scale(sc, sc)
      pcall(Chrome.mapPopupFrame, px, py, tiles)
      pcall(Font.draw, popup.text, px + 8 + math.floor((tiles * 8 - textW) / 2), py + 5,
        { colors = popup.broke and Font.COLOR.RED or Font.COLOR.NORMAL, maxWidth = tiles * 8 })
      g.pop()
    else
      local font = g.getFont()
      local w = (font:getWidth(popup.text) + 12) * sc
      local h = (font:getHeight() + 6) * sc
      local x, y = vp.gameX + vp.gameWidth - w - 4 * sc, vp.gameY + (tPos - 24 + 4) * sc
      g.setColor(0, 0, 0, 0.7); g.rectangle("fill", x, y, w, h)
      g.setColor(1, 1, 1, 1)
      g.print(popup.text, x + 6 * sc, y + 3 * sc, 0, sc, sc)
    end
    g.setColor(1, 1, 1, 1)
  end

  function E.femaleFor(species, personality)
    return Pokemon.gender and Pokemon.gender(species, personality) == "F" or false
  end

  -- roamer[0] (FR has ROAMER_COUNT 1): IsRoamerAt + its level, via the
  -- engine's roamer module (which also applies the repel level rule)
  function E.roamerAt(index)
    if not V.roamers or index ~= 0 or not E.Roamer then return nil end
    local s = Runtime.getSession()
    local ok, enc = pcall(E.Roamer.tryEncounter, s, E.mapId(), "land")
    if ok and enc then return enc.species, enc.level, enc.foe end
    return nil
  end

  function E.roamerMove(index)
    if not V.roamers or index ~= 0 or not E.Roamer then return end
    pcall(E.Roamer.move, Runtime.getSession())
  end

  -- PlayCry_NormalNoDucking(species, pan, volume, CRY_PRIORITY_AMBIENT)
  function E.playCryAt(species, pan, volume)
    local Au = E.Audio
    if Au and Au.playCry then
      pcall(Au.playCry, species, { mode = 0, pan = pan, volume = volume, noDuck = true })
    end
  end

  -- playmoncry(species, mode) / waitmoncry
  function E.playCryMode(species, mode)
    local Au = E.Audio
    if Au and Au.playCry then pcall(Au.playCry, species, mode) end
  end
  function E.cryFinished()
    local Au = E.Audio
    if not (Au and Au.isCryFinished) then return true end
    local ok, r = pcall(Au.isCryFinished)
    return not ok or r ~= false
  end

  -- BattleSetup_StartWildBattle / BattleSetup_StartRoamerBattle.
  -- done(result) runs once the field is back; false if it did not start.
  function E.startWildBattle(foe, roamer, done)
    local ok, r = pcall(E.Battle.startWild, mod, E.Field._game, foe,
      { roamer = roamer or nil, done = done })
    return ok and r ~= nil
  end

  -- gMapHeader.mapType is TOWN or CITY
  function E.mapIsTown()
    local def = Collision._mapDef
    local t = def and def.mapType
    return t ~= nil and (V.townMapTypes[t] == true or V.townMapTypes[tonumber(t) or -1] == true)
  end

  -- Called on A press or transform roll only, so temporaries are fine.
  local Rng = E.Rng
  function E.random()
    if Rng and Rng.Random then return Rng.Random() end
    return math.random(0, 65535)
  end

  function E.weather()
    local W = E.FieldWeather
    return (W and W.getWeather and tonumber(W.getWeather())) or 0
  end

  function E.mapMusic()
    local Au = E.Audio
    return Au and tonumber(Au._mapSong) or -1
  end

  -- gMapHeader.regionMapSectionId
  function E.mapsec()
    local def = Collision._mapDef
    return def and tonumber(def.regionMapSectionId) or -1
  end

  -- gSaveBlock1Ptr->location (compared against VERSIONS.maps values)
  function E.mapId()
    local s = Runtime.getSession()
    return s and s.map
  end

  function E.behaviorAt(x, y) return Collision.behavior(x, y) end

  -- gMapHeader.mapType == MAP_TYPE_UNDERWATER (player underwater)
  function E.mapUnderwater()
    local def = Collision._mapDef
    return V.mapTypeUnderwater ~= nil and def ~= nil and tonumber(def.mapType) == V.mapTypeUnderwater
  end

  -- pret TYPE_* ids (battle/types.lua Types.ID; same numbering in pokefirered)
  local TYPE_FALLBACK = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4,
    ROCK = 5, BUG = 6, GHOST = 7, STEEL = 8, MYSTERY = 9, FIRE = 10, WATER = 11,
    GRASS = 12, ELECTRIC = 13, PSYCHIC = 14, ICE = 15, DRAGON = 16, DARK = 17 }
  function E.typeId(name)
    local T = E.Types
    local ids = (T and T.ID) or TYPE_FALLBACK
    return ids[name]
  end

  function E.monTypes(mon)
    local t = Pokemon.types and Pokemon.types(Pokemon.speciesOf(mon))
    if not t then return -1, -1 end
    return t[1] or -1, t[2] or t[1] or -1
  end

  -- GetOverworldTypeEffectiveness: multiplier of `atkType` on the mon
  function E.typeEffect(atkType, mon)
    local T = E.Types
    if not (T and T.effectiveness) or atkType == E.typeId("MYSTERY") then return 1 end
    local t1, t2 = E.monTypes(mon)
    return T.effectiveness(atkType, t1, t2)
  end

  -- mon->status as "SLP" / "PSN" / "TOX" / "BRN" / "FRZ" / "PAR" / nil
  local STATUS_ALIAS = { BURN = "BRN", POISON = "PSN", TOXIC = "TOX", SLEEP = "SLP",
    PARALYSIS = "PAR", FREEZE = "FRZ" }
  function E.monStatus(mon)
    local s = mon and mon.status
    if not s or s == 0 or s == "" then return nil end
    s = tostring(s):upper()
    return STATUS_ALIAS[s] or s
  end

  function E.friendship(mon)
    if Pokemon.friendshipOf then return Pokemon.friendshipOf(mon) end
    return tonumber(mon.friendship) or 0
  end

  function E.isEgg(mon) return mon == nil or Pokemon.isEgg(mon) end

  function E.monAbility(mon)
    if not Pokemon.abilityId then return 0 end
    return Pokemon.abilityId(Pokemon.speciesOf(mon), mon.personality) or 0
  end

  function E.knowsMove(mon, move)
    return Pokemon.knowsMove ~= nil and Pokemon.knowsMove(mon, move) == true
  end

  function E.monName(mon)
    if Pokemon.displayName then return Pokemon.displayName(mon) end
    return tostring(mon.nickname or "")
  end

  -- playfirstmoncry (CRY_MODE_NORMAL) / waitmoncry
  function E.playCry(mon)
    local Au = E.Audio
    if Au and Au.playCry then pcall(Au.playCry, Pokemon.speciesOf(mon), 0) end
  end

  function E.playSe(name)
    local Au = E.Audio
    if Au and Au.playSe then pcall(Au.playSe, name) end
  end

  -- message + waitbuttonpress; `done` runs when the box is dismissed
  function E.message(text, done)
    local M = E.Message
    if not (M and M.show) then return done() end
    M.show(text, { done = done })
  end

  -- lock / release (script context owns the field while set)
  function E.lock() E.Field.locked = true end
  function E.release()
    if E.Field.unlock then E.Field.unlock() else E.Field.locked = false end
  end

  --- Expansion species id for an engine species (national dex, Unown letter
  --- forms at SPECIES_UNOWN_B + n - 1).  nil if it has no national number.
  local SPECIES_UNOWN, SPECIES_UNOWN_B = 201, 1024
  function E.expansionSpecies(species, personality)
    local nat = Pokemon.national(species)
    if not nat then return nil end
    if nat == SPECIES_UNOWN and personality then
      local l = Pokemon.unownLetter(personality)
      if l > 0 then nat = SPECIES_UNOWN_B + l - 1 end
    end
    return nat
  end

  -- src/wild_encounter.c:974 GetLocalWildMon (ChooseWildMonIndex_Land/Water
  -- slot weights), as an expansion species id; nil = SPECIES_NONE
  local LAND_W = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
  local WATER_W = { 60, 30, 5, 4, 1 }
  local function pickSlot(area, w, n)
    local slots = type(area) == "table" and (area.slots or area.mons or area)
    if type(slots) ~= "table" or #slots == 0 then return nil end
    local r, acc = E.random() % n, 0
    for i = 1, #w do
      acc = acc + w[i]
      if r < acc then
        local e = slots[i] or slots[#slots]
        local sp = type(e) == "table" and tonumber(e.species or e[1]) or tonumber(e)
        if sp then return E.expansionSpecies(sp), sp end
      end
    end
  end
  function E.localWildMon()
    local ok, t = pcall(E.Encounters.tableFor, E.mapId())
    if not ok or type(t) ~= "table" then return nil end
    local land = t.land or t.grass
    local water = t.water
    local hasLand = type(land) == "table" and #(land.slots or land.mons or land) > 0
    local hasWater = type(water) == "table" and #(water.slots or water.mons or water) > 0
    if not hasLand and not hasWater then return nil end
    -- extra results: *isWaterMon, the engine species id (for cries)
    local isWater = not hasLand or (hasWater and E.random() % 100 >= 80)
    local nat, sp = pickSlot(isWater and water or land, isWater and WATER_W or LAND_W, 100)
    return nat, isWater, sp
  end

  -- Indexed atlas + palette texture; palette row rides in the draw colour. Lazy-loaded.
  local Gfx = { ready = false }
  E.Gfx = Gfx
  local PAL_SHADER = [[
    uniform Image pal;
    uniform float palH;     // pal is 256 wide: 16 rows per line, see packPalettes
    uniform float mosaic;   // REG_MOSAIC block size in px, 1 = off
    uniform vec2 atlasSize;
    uniform float gray;     // Quest Log past scenes are monochrome
    // highp uv: mediump (fp16) misses texels past x=2048
    vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 sc) {
      highp vec2 uv = VaryingTexCoord.st;
      // sample texel centres: a coord on a texel edge rounds either way (crunchy sprites)
      uv = (floor(uv * atlasSize / mosaic) * mosaic + 0.5) / atlasSize;
      float idx = floor(Texel(tex, uv).r * 255.0 / 16.0 + 0.5);
      if (idx < 0.5) discard;
      // row = lo + hi * 256 never formed: rows > 2048 are inexact in mediump
      float lo = floor(color.r * 255.0 + 0.5);
      float hi = floor(color.g * 255.0 + 0.5);
      float px = idx + 16.0 * mod(lo, 16.0);
      float py = hi * 16.0 + floor(lo / 16.0);
      vec4 c = Texel(pal, vec2((px + 0.5) / 256.0, (py + 0.5) / palH));
      c.rgb = mix(c.rgb, vec3(1.0), color.b);
      if (gray > 0.5) c.rgb = vec3(dot(c.rgb, vec3(0.299, 0.587, 0.114)));
      return vec4(c.rgb, color.a);
    }
  ]]

  local function loadImage(name, format)
    local bytes = assert(mod:read(name), name .. " missing")
    local data = love.image.newImageData(love.filesystem.newFileData(bytes, name))
    if format == "r8" then
      -- 4x less VRAM: copy R into a single-channel image (FFI, load-time only)
      local ok, ffi = pcall(require, "ffi")
      if ok then
        local w, h = data:getDimensions()
        local r8 = love.image.newImageData(w, h, "r8")
        local src = ffi.cast("const uint8_t*", data:getFFIPointer())
        local dst = ffi.cast("uint8_t*", r8:getFFIPointer())
        for i = 0, w * h - 1 do dst[i] = src[i * 4] end
        data = r8
      end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    return img
  end

  -- palettes.png (16 x rows) -> 256 x 16*ceil(rows/256): row r = lo + hi*256
  -- sits at (16*(lo%16), hi*16 + lo/16), so every shader coord is < 2048
  local function packPalettes(rows)
    local bytes = assert(mod:read("palettes.png"), "palettes.png missing")
    local src = love.image.newImageData(love.filesystem.newFileData(bytes, "palettes.png"))
    local dst = love.image.newImageData(256, 16 * math.ceil(rows / 256))
    for r = 0, rows - 1 do
      local lo, hi = r % 256, math.floor(r / 256)
      dst:paste(src, 16 * (lo % 16), hi * 16 + math.floor(lo / 16), 0, r, 16, 1)
    end
    local img = love.graphics.newImage(dst)
    img:setFilter("nearest", "nearest")
    return img
  end

  function Gfx.load()
    if Gfx.ready or Gfx.failed then return Gfx.ready end
    local ok, err = pcall(function()
      local A = E.Data.ATLAS
      Gfx.pages = {}
      for i = 1, A.pages do Gfx.pages[i] = loadImage("atlas" .. i .. ".png", "r8") end
      Gfx.pal = packPalettes(A.palRows)
      Gfx.shader = love.graphics.newShader(PAL_SHADER)
      Gfx.shader:send("pal", Gfx.pal)
      Gfx.shader:send("palH", Gfx.pal:getHeight())
      Gfx.shader:send("mosaic", 1)
      Gfx.shader:send("gray", 0)
      Gfx.shader:send("atlasSize", { A.w, A.h }) -- every page is w x h
      Gfx.mosaic = 1
      Gfx.quads = {}
    end)
    if not ok then
      Gfx.failed = true
      mod.log:error("atlas load failed: %s", tostring(err))
      return false
    end
    Gfx.ready = true
    return true
  end

  local SHEETS
  --- Sheet index for a species (female/placeholder fallback per
  --- OW_SUBSTITUTE_PLACEHOLDER), and its normal/shiny palette rows.
  function Gfx.sheetFor(species, female, shiny)
    local A = E.Data.ATLAS
    local s = (female and A.female[species]) or A.species[species]
    if not s then
      if not C.OW_SUBSTITUTE_PLACEHOLDER then return nil end
      s = A.SUBSTITUTE
    end
    local row = A.sheets[(s - 1) * 6 + 6]
    if shiny and A.shinyPal[species] then row = A.shinyPal[species] end
    return s, row
  end

  -- white: 0..1 white fill; xscale: ball affine scale; mosaic: block size (nil/1 = none).
  function Gfx.draw(sheet, frame, flip, palRow, sx, sy, white, alpha, xscale, mosaic)
    if not Gfx.ready and not Gfx.load() then return false end
    SHEETS = SHEETS or E.Data.ATLAS.sheets
    local b = (sheet - 1) * 6
    local fw, fh = SHEETS[b + 3], SHEETS[b + 4]
    local nf = SHEETS[b + 5]
    if frame >= nf then frame = nf - 1 end
    local qs = Gfx.quads[sheet]
    if not qs then qs = {}; Gfx.quads[sheet] = qs end
    local q = qs[frame]
    local A = E.Data.ATLAS
    local y = SHEETS[b + 2]
    if not q then
      q = love.graphics.newQuad(SHEETS[b + 1] + frame * fw, y % A.h, fw, fh, A.w, A.h)
      qs[frame] = q
    end
    local lg = love.graphics
    local bound = Gfx.bound
    local prev
    if not bound then prev = lg.getShader(); lg.setShader(Gfx.shader) end
    mosaic = mosaic or 1
    if mosaic ~= Gfx.mosaic then Gfx.mosaic = mosaic; Gfx.shader:send("mosaic", mosaic) end
    lg.setColor((palRow % 256) / 255, math.floor(palRow / 256) / 255, white or 0, alpha or 1)
    local k = xscale or 1
    if flip then k = -k end
    lg.draw(Gfx.pages[math.floor(y / A.h) + 1], q, math.floor(sx) + 8, math.floor(sy) + 16 - fh, 0, k, 1, fw / 2, 0)
    if not bound then lg.setShader(prev); lg.setColor(1, 1, 1, 1) end
    return true
  end

  -- Bind once across several draws: each shader switch splits LOVE's sprite batch.
  function Gfx.bind()
    if Gfx.bound or not Gfx.ready then return end -- Gfx.draw loads on demand
    local lg = love.graphics
    Gfx.prevShader = lg.getShader()
    lg.setShader(Gfx.shader)
    Gfx.bound = true
  end
  function Gfx.unbind()
    if not Gfx.bound then return end
    love.graphics.setShader(Gfx.prevShader)
    love.graphics.setColor(1, 1, 1, 1)
    Gfx.bound, Gfx.prevShader = false, nil
  end

  -- Shadow and tall grass are draw-time tests; tile checks cached per cell.
  local RUSTLE, GRASS_DUR, FEET_H = { 1, 2, 3, 4, 0 }, 10, 8
  local function grassSheet()
    local FXm = E.FieldEffects
    if not FXm then return nil end
    local sh = FXm._sheets and FXm._sheets.tall_grass
    if sh == nil and FXm.tallGrassAt then
      local keep = FXm._fx -- tallGrassAt is the only public loader
      FXm.tallGrassAt(-32768, -32768, true)
      FXm._fx = keep
      sh = FXm._sheets.tall_grass
    end
    return sh or nil
  end
  function E.tickGrass()
    for i = 1, POOL do
      local a = actors[i]
      if a.active then
        local x, y = a.cellX, a.cellY
        if a.moving then x, y = a.targetX, a.targetY end
        if x ~= a.grX or y ~= a.grY then
          local fresh = a.grX == nil and not a.moving -- spawned in grass
          a.grX, a.grY = x, y
          if Collision.isGrass and Collision.isGrass(x, y) then
            a.grStep, a.grT = fresh and #RUSTLE - 1 or 0, 0
          else
            a.grStep = nil
          end
        elseif a.grStep and a.grStep < #RUSTLE - 1 then
          a.grT = a.grT + 1
          if a.grT >= GRASS_DUR then a.grT, a.grStep = 0, a.grStep + 1 end
        end
      elseif a.grX then
        a.grX, a.grY, a.grStep = nil, nil, nil
      end
    end
  end
  --- front=false: base pad, only flagged here and drawn by drawGrassBase under
  --- every object (pret oam priority below the avatar); true: feet cover (over it).
  function E.drawGrass(a, sx, sy, front)
    if not front then
      if not E.redrawing then a.grBase = drawSerial end
      return
    end
    if not a.grStep then return end
    local sh = grassSheet()
    if not sh then return end
    local f = RUSTLE[a.grStep + 1]
    local gx, gy = sx + (a.grX * 16 - a.px), sy + (a.grY * 16 - a.py)
    local q
    do
      local feet = a.py + 16
      if feet < a.grY * 16 + FEET_H or feet > a.grY * 16 + 18 then return end
      q = sh.quadsFront and sh.quadsFront[f]
      gy = gy + 16 - FEET_H
    end
    if not q then return end
    -- grass is a plain RGBA sheet: step out of the palette shader if bound
    local lg, bound = love.graphics, Gfx.bound
    if bound then lg.setShader(Gfx.prevShader) end
    lg.setColor(1, 1, 1, 1)
    lg.draw(sh.image, q, gx, gy)
    if bound then lg.setShader(Gfx.shader) end
  end

  -- base pads of actors drawn last frame, with the map, before any object
  local function drawGrassBase(camX, camY)
    local sh
    for i = 1, POOL do
      local a = actors[i]
      if a.active and a.grStep and a.grBase == drawSerial - 1 then
        sh = sh or grassSheet()
        local q = sh and sh.quads[RUSTLE[a.grStep + 1]]
        if q then
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(sh.image, q, a.grX * 16 - camX, a.grY * 16 - camY)
        end
      end
    end
  end
  local FXb = E.FieldEffects
  if FXb and FXb.drawBehind then
    local rawBehind = FXb.drawBehind
    FXb.drawBehind = function(camX, camY, ...)
      local r = rawBehind(camX, camY, ...)
      if inFieldDraw then drawGrassBase(camX or 0, camY or 0) end
      return r
    end
  end

  local SHADOWS = nil
  local function shadowTileOk(x, y)
    local b, mb = Collision.behavior(x, y), V.mb
    return not (b == mb.TALL_GRASS or b == mb.CYCLING_ROAD_PULL_DOWN_GRASS or b == mb.PUDDLE
      or Collision.isSurfable(b))
  end
  function E.drawShadow(a, sx, sy, jumping)
    if E.redrawing then return end
    if C.OW_OBJECT_VANILLA_SHADOWS then
      if not jumping then return end
    elseif V.mapTypeUnderground then
      local def = Collision._mapDef
      if def and tonumber(def.mapType) == V.mapTypeUnderground then return end
    end
    local x, y = a.cellX, a.cellY
    if a.moving then x, y = a.targetX, a.targetY end
    if x ~= a.shX or y ~= a.shY then
      -- currentMetatileBehavior + previousMetatileBehavior (surfable check)
      local prevOk = a.shX == nil or not Collision.isSurfable(Collision.behavior(a.shX, a.shY))
      a.shX, a.shY = x, y
      a.shOk = prevOk and shadowTileOk(x, y)
    end
    if not a.shOk then return end
    SHADOWS = SHADOWS or E.Data.ATLAS.shadows
    local size = E.Data.ATLAS.shadow[a.species]
    local sheet = size and SHADOWS[size]
    if not sheet then return end -- SHADOW_SIZE_NONE
    -- Centre lands every sprite size on the object's cell; half alpha (D37).
    Gfx.draw(sheet, 0, false, E.Data.ATLAS.sheets[(sheet - 1) * 6 + 6], sx, sy, 0, 0.5)
  end

  -- Subsystems.  Each file returns a table with init(E), reset(), tick(),
  -- onStep(ev), onMapEntered(ev), onBattleStarted(ev), onBattleEnded(ev).
  local Data = include("data.lua")
  E.Data = Data
  local Follower = include("follower.lua")
  local Owe = include("owe.lua")
  E.Follower, E.Owe = Follower, Owe
  Follower.init(E)
  Owe.init(E)
  mod.exports.engine = E -- headless tests + debugging

  -- per-frame tick after player/NPC update (fixed 60 Hz = one GBA frame)
  local rawFieldUpdate = E.Field.update
  E.Field.update = function(dt)
    local r = rawFieldUpdate(dt)
    staticT = staticT + 1
    if E.Field.running then
      if C.OW_FOLLOWERS_ENABLED then Follower.tick() end
      if C.WE_OW_ENCOUNTERS then Owe.tick() end
      Owe.updateAmbientCry() -- Task_RunTimeBasedEvents
      E.tickGrass()
    end
    return r
  end

  -- Follower enters its ball while the door opens.
  local Warp = E.Warp
  if Warp and Warp.startDoorEntrance then
    local rawDoor = Warp.startDoorEntrance
    Warp.startDoorEntrance = function(...)
      if not Warp._busy and C.OW_FOLLOWERS_ENABLED then Follower.enterBall() end
      return rawDoor(...)
    end
  end

  -- Scripted movement on anyone else puts the follower away unless it only turns/emotes/waits.
  local Movement = E.Movement
  if Movement and Movement.start and Movement.decodeAction then
    local SAFE = { ["end"] = true, nop = true, turn = true, sleep = true, face_player = true,
      face_original = true, emote = true, lock_facing = true }
    local rawStart = Movement.start
    Movement.start = function(ctx, localId, bytes, adapters)
      local stream = bytes
      if type(bytes) == "string" and adapters and adapters.lookupMovement then
        stream = adapters.lookupMovement(bytes)
      end
      if C.OW_FOLLOWERS_ENABLED and type(stream) == "table" then
        for i = 1, #stream do
          local b = stream[i]
          local act = type(b) == "number" and Movement.decodeAction(b) or b
          if type(act) ~= "table" or act.kind == "end" then break end
          if not SAFE[act.kind] then Follower.enterBall(true); break end
        end
      end
      return rawStart(ctx, localId, bytes, adapters)
    end
  end

  -- FR's nurse script has no hidefollower; recall at the heal effect instead.
  local Heal = E.Heal
  if Heal and Heal.start then
    local rawHeal = Heal.start
    Heal.start = function(...)
      if C.OW_FOLLOWERS_ENABLED then Follower.enterBall(true) end
      return rawHeal(...)
    end
  end

  -- Same gates as Field.interact; an engine object on the cell wins.
  local FACE_DX = { up = 0, down = 0, left = -1, right = 1 }
  local FACE_DY = { up = -1, down = 1, left = 0, right = 0 }
  local rawInteract = E.Field.interact
  E.Field.interact = function(game, ...)
    local F, FA = E.Field, E.FOLLOWER
    if C.OW_FOLLOWERS_ENABLED and F.running and not F.locked and FA.active
        and not FA.invisible and not FA.moving and not Follower.talking()
        and not Player.moving and not Forced.fieldControlsLocked()
        and not (Runtime.uiBusy and Runtime.uiBusy()) then
      local fx = Player.cellX + (FACE_DX[Player.facing] or 0)
      local fy = Player.cellY + (FACE_DY[Player.facing] or 0)
      if FA.cellX == fx and FA.cellY == fy and not Objects.at(fx, fy) then
        return Follower.talk()
      end
    end
    -- GetOverworlWildEncounterScript -> InteractWithOverworldWildEncounter
    if C.WE_OW_ENCOUNTERS and F.running and not F.locked and not Player.moving
        and not Forced.fieldControlsLocked()
        and not (Runtime.uiBusy and Runtime.uiBusy()) then
      local fx = Player.cellX + (FACE_DX[Player.facing] or 0)
      local fy = Player.cellY + (FACE_DY[Player.facing] or 0)
      local a = E.actorAt(fx, fy)
      if a and E.isOwe(a) and not Objects.at(fx, fy) then
        return Owe.interact(a)
      end
    end
    return rawInteract(game, ...)
  end

  -- the built-in trail follower is never used
  mod.hooks:wrap("world.follower.spawn", function() return false end)

  -- src/wild_encounter.c: WE_VANILLA_RANDOM gates random step battles
  mod.hooks:wrap("encounter.roll", function(nextFn, ...)
    if C.WE_OW_ENCOUNTERS and not C.WE_VANILLA_RANDOM then return nil end
    return nextFn(...)
  end)

  mod.hooks:wrap("render.hud", function(nextFn, game, vp, ...)
    local r = nextFn(game, vp, ...)
    if C.OWE_ROGUE_CHAIN and vp then E.tickPopup(); E.drawPopup(vp) end
    return r
  end)

  mod.events:on("world.stepped", function(ev)
    if C.OW_FOLLOWERS_ENABLED then Follower.onStep(ev) end
    if C.WE_OW_ENCOUNTERS then Owe.onStep(ev) end
  end)
  mod.events:on("map.entered", function(ev)
    E.invalidateMapCaches()
    Follower.onMapEntered(ev)
    Owe.onMapEntered(ev)
  end)
  mod.events:on("game.ready", function()
    -- upload the atlas during load instead of on the first draw
    if love and love.graphics and love.graphics.newShader then Gfx.load() end
    Follower.update()
  end)
  mod.events:on("battle.started", function(ev)
    Follower.onBattleStarted(ev)
    Owe.onBattleStarted(ev)
  end)
  mod.events:on("battle.ended", function(ev)
    Follower.onBattleEnded(ev)
    Owe.onBattleEnded(ev)
  end)
  mod.events:on("mod.options_changed", function(ev)
    if ev.mod ~= mod.id then return end
    readOptions()
    if not C.OW_FOLLOWERS_ENABLED then Follower.reset() end
    if not C.WE_OW_ENCOUNTERS then Owe.reset() end
  end)
end
