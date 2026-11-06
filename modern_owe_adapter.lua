-- Modern Spawns API consumer for generated visible wild Pokemon.
-- Do NOT change the number of native encounter slots or the odds/levels.
-- drawFor() varies the species inside those slots for RANDOM and COMPLETE.
-- This helper is pure enough to exercise with mocked provider/atlas data.
return function(mod, E)
  -- Modern's registry may return canonical species names rather than
  -- internal Gen 3 numeric slots; map them before calling Untamed.
  local function engineSpecies(value)
    local id = tonumber(value)
    if id == nil and type(value) == "string"
        and type(E.Pokemon.speciesFromName) == "function" then
      local ok, found = pcall(E.Pokemon.speciesFromName, value)
      if ok then id = tonumber(found) end
    end
    if not id or id < 1 or id % 1 ~= 0 then return nil end
    return id
  end
  local function viableSpecies(species)
    if not species then return false end
    local ok, national = pcall(E.Pokemon.national, species)
    if not ok or type(national) ~= "number"
        or national < 1 or national > 1025 then return false end
    local okGfx, gfx = pcall(E.expansionSpecies, species, 0)
    local atlas = E.Data and E.Data.ATLAS
    if not okGfx or type(gfx) ~= "number" or not atlas
        or not atlas.species or not atlas.species[gfx] then return false end
    return true
  end

  return function(kind, authored)
    if (kind ~= "land" and kind ~= "water")
        or type(authored) ~= "table" or #authored == 0
        or type(mod.find) ~= "function" then return nil end
    local ok, plugin = pcall(mod.find, mod, "modern_spawns")
    local api = ok and type(plugin) == "table" and plugin.exports or nil
    if type(api) ~= "table" or (tonumber(api.apiVersion) or 0) < 2
        or type(api.isActive) ~= "function"
        or type(api.drawFor) ~= "function" then return nil end
    local activeOk, active = pcall(api.isActive)
    if not activeOk or active ~= true then return nil end
    local mapId = E.mapId()
    if mapId == nil then return nil end
    -- One provider draw per new normal OWE, never once per frame.
    -- COMPLETE's poolPick can change a slot's species on every draw.
    local drawOk, table_ = pcall(api.drawFor, mapId, kind)
    local provided = drawOk and type(table_) == "table"
        and table_.slots or nil
    if type(provided) ~= "table"
        or #provided ~= #authored then return nil end
    local out, changed = {}, false
    for i = 1, #authored do
      local original, picked = authored[i], provided[i]
      if type(original) ~= "table" or type(picked) ~= "table" then
        return nil
      end
      local originalId = engineSpecies(original.species or original[1])
      local newId = engineSpecies(picked.species or picked[1])
      if newId and viableSpecies(newId) then
        local item = {}
        for k,v in pairs(original) do item[k] = v end
        item.species = newId
        out[i] = item
        if newId ~= originalId then changed = true end
      else
        -- An unsupported alternate-form artwork is not an empty spawn.
        out[i] = original
      end
    end
    return changed and out or nil
  end
end
