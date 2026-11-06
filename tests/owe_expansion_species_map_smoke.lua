-- Regression: National Dex number != pokeemerald-expansion atlas species id.
-- Paldea #906-1025 previously drew Mega or form sprites from IDs 906+.
local map = assert(loadfile("owe_expansion_species_map.lua"))()
local data = assert(loadfile("data.lua"))()
local atlas = assert(data.ATLAS and data.ATLAS.species)
local function eq(a,b,msg) assert(a==b,(msg or "mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
eq(map.resolve(906),1289,"Sprigatito MUST NOT draw Mega Venusaur (906)")
eq(map.resolve(907),1290,"Floragato MUST NOT draw Mega Charizard X (907)")
eq(map.resolve(908),1291,"Meowscarada MUST NOT draw Mega Charizard Y (908)")
eq(map.resolve(909),1292,"Fuecoco MUST NOT draw Mega Blastoise (909)")
eq(map.resolve(915),1298,"Lechonk atlas position")
eq(map.resolve(1025),1434,"Pecharunt atlas position")
eq(map.resolve(25),25,"Vanilla Pikachu remains unchanged")
eq(map.resolve(387),387,"Sinnoh Turtwig stays in the native-numbered range")
eq(map.resolve(201,nil,1),1024,"Preserve legacy Unown-letter logic")
eq(map.resolve(128,"TAUROS_PALDEA_COMBAT_BREED"),1402,
  "Paldean Tauros form is not vanilla Tauros")
eq(map.resolve(800,"NECROZMA_DUSK"),1207,"Dusk Mane Necrozma form")
eq(map.resolve(1017,"OGERPON_WELLSPRING_MASK"),1417,
  "Ogerpon mask must retain its own overworld sprite")
eq(map.resolve(670,"FLOETTE_YELLOW"),nil,
  "Unsupported sprite must fail closed, not silently impersonate a base form")
eq(map.resolve(906,"SPRIGATITO"),1289,"Base species remains correct")
eq(map.resolve(nil),nil,"Absent species never resolves")
local n=0
for national=906,1025 do
  local key=map.national[national]
  assert(type(key)=="number" and key>0 and atlas[key],
    "No built-in atlas for National Dex species "..national.." -> "..tostring(key))
  n=n+1
end
local forms,notDrawn=0,0
for name in pairs(map.formIds) do
  local code=map.forms[name]
  if code then
    assert(atlas[code],"Mapped form without an atlas entry: "..name)
    forms=forms+1
  else notDrawn=notDrawn+1 end
end
eq(n,120,"Full Paldean base Pokédex coverage")
eq(forms,124,"Only atlas-backed forms are accepted")
eq(notDrawn,4,"Unknown Floette colours are left to a future art pack")
print("PASS: 120 Paldean species, 124 valid forms, conservative 4-form fallback")
