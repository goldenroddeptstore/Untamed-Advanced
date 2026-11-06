-- Optional mod hook for generated overworld wild Pokemon.
-- Intentionally kept independent of the engine renderer / actor lifecycle so
-- extensions can be smoke tested and unsupported replacements fail open.
local M = {}
function M.apply(E, species, level, kind, x, y)
  local hooks = type(E) == "table" and E.ModHooks
  if type(hooks) ~= "table" or type(hooks.wantsHook) ~= "function"
      or type(hooks.call) ~= "function"
      or not hooks.wantsHook("untamed.owe.species") then return species end
  local source = { species = species, level = level }
  local ctx = { source = "untamed_advanced", mapId = E.mapId(),
    terrain = kind, x = x, y = y }
  local value = hooks.call("untamed.owe.species",
    function(original) return original end, source, ctx)
  local id = type(value) == "table" and tonumber(value.species) or nil
  if not id or id % 1 ~= 0 or id <= 0 or id == species then
    return species
  end
  -- Preserve native sprites and battles if a randomiser returns invalid IDs
  -- or visual assets are absent. Followers and scripted OWEs never come here.
  local ok, dex = pcall(E.Pokemon.national, id)
  local nat = ok and tonumber(dex)
  -- National Dex Gen 3 may register genuine #387-1025 species at engine
  -- slots unrelated to either their National number or expansion atlas id.
  -- Validate the translated sprite, not a hardcoded Gen 3 386 cap.
  if not nat or nat < 1 or nat > 1025 then return species end
  local okForm, gfx = pcall(E.expansionSpecies, id, 0)
  if not okForm or type(gfx) ~= "number" then return species end
  -- sheetFor() can return the generic Substitute placeholder when an
  -- actual Pokemon sprite is absent. Require a real atlas species sheet:
  -- the thing visible to the player must match the battle Pokemon.
  local atlas = E.Data and E.Data.ATLAS
  if type(atlas) ~= "table" or type(atlas.species) ~= "table"
      or not atlas.species[gfx] then return species end
  local okSheet, sheet = pcall(E.Gfx.sheetFor, gfx, false, false)
  if not okSheet or not sheet then return species end
  return id
end
-- Optional shiny-personality hook. Only a validated native-shiny PID may
-- replace the original. Retaining the low 16 bits preserves gender-related
-- properties, and makes the visible sprite agree with the eventual battle.
function M.applyShiny(E, species, level, personality, shiny, kind, x, y)
  -- Natural and chain shinies are already authoritative. Never ask another
  -- provider to reroll them or consume its random stream.
  if shiny == true then return personality, shiny end
  local hooks = type(E) == "table" and E.ModHooks
  if type(hooks) ~= "table" or type(hooks.wantsHook) ~= "function"
      or type(hooks.call) ~= "function"
      or not hooks.wantsHook("untamed.owe.shiny") then
    return personality, shiny
  end
  local source = { species = species, level = level,
    personality = personality, shiny = shiny }
  local ctx = { source = "untamed_advanced", mapId = E.mapId(),
    terrain = kind, x = x, y = y,
    makeShiny = function(pid) return E.makeShiny(pid) end }
  local value = hooks.call("untamed.owe.shiny",
    function(original) return original end, source, ctx)
  if type(value) ~= "table" or value.species ~= species
      or value.level ~= level or value.shiny ~= true or shiny then
    return personality, shiny
  end
  local pid = value.personality
  if type(pid) ~= "number" or pid ~= math.floor(pid)
      or pid < 0 or pid >= 4294967296 or pid == personality
      or pid % 65536 ~= personality % 65536 then
    return personality, shiny
  end
  local ok, nativeShiny = pcall(E.shinyFor, pid)
  if not ok or nativeShiny ~= true then return personality, shiny end
  return pid, true
end

return M
