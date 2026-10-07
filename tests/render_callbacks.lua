-- Headless regression for gen1recomp's draw(renderActor, camX, camY) contract.
-- Run from the repository root: luajit tests/render_callbacks.lua [source-root]
bit = require("bit")
local root = arg[1] or "."
local function source(name)
  local f = assert(io.open(root .. "/" .. name, "rb"))
  local s = f:read("*a"); f:close(); return s
end
local function section(s, first, last)
  local a = assert(s:find(first, 1, true), first)
  local b = assert(s:find(last, a, true), last)
  return s:sub(a, b - 1)
end
local loadSource = loadstring or load
local failures, cases = 0, 0
local function test(name, fn)
  cases = cases + 1
  local ok, err = pcall(fn)
  if not ok then failures = failures + 1 end
  print((ok and "PASS " or "FAIL ") .. name .. (ok and "" or (": " .. tostring(err))))
end
local function equal(actual, expected)
  assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end

-- Execute the actual integration block, not a rewritten copy of its hooks.
-- Loading only this block avoids requiring a ROM, save, graphics driver or host UI.
local wiring = section(source("main.lua"),
  "  -- Actor pool shaped", "  -- Quest Log frames are saved")
local setup = assert(loadSource("return function(E, C, V)\n" .. wiring .. "\nend", "@main.lua:render-wiring"))()
local frame, sprites, binds, unbinds, nativeCalls, seen = nil, {}, 0, 0, 0, {}
local native = { localId = 1, graphicsId = 7, px = 10, py = 20 }
local C = { OWE_SPAWNS_MAX = 2 }
local V = { maps = {}, mb = {}, songs = {} }
local E = {
  C = C, V = V, Player = {}, Collision = {},
  Objects = { forDraw = function() return { native } end },
  OwSprites = { draw = function() nativeCalls = nativeCalls + 1; return true end },
  FieldEffects = { _fx = { cx = 2, cy = 3 }, drawFront = function() end },
  Gfx = {
    bind = function() binds = binds + 1 end,
    unbind = function() unbinds = unbinds + 1 end,
    draw = function(sheet, spriteFrame, flip, row, x, y)
      sprites[#sprites + 1] = { sheet = sheet, x = x, y = y }; return true
    end,
  },
  typeId = function() return nil end,
  drawShadow = function(a) seen.shadow = a end,
  drawGrass = function(a) seen.grass = a end,
}
-- Mirror field_view's wrapper construction and callback precedence. The wrapper
-- intentionally lacks y2/sheet/emote, just like the real engine's render actor.
local function render(eo, camX, camY)
  local a = { eventObject = eo, graphicsId = eo.graphicsId, draw = eo.draw,
    x = eo.px + (eo.raiseX or 0), y = eo.py + (eo.raiseY or 0) }
  if a.draw then a:draw(camX, camY)
  else E.OwSprites.draw(a.graphicsId, a.x, a.y, camX, camY, eo.facing, 0, false) end
end
E.FieldView = { draw = function(camX, camY)
  frame = E.Objects.forDraw()
  for _, eo in ipairs(frame) do render(eo, camX, camY) end
end }
setup(E, C, V)
E.Data = assert(loadSource(source("data.lua"), "@data.lua"))()
E.Follower = assert(loadSource(source("follower.lua"), "@follower.lua"))()
E.Owe = assert(loadSource(source("owe.lua"), "@owe.lua"))()
E.Follower.init(E)
E.Owe.init(E)
local follower = E.FOLLOWER
follower.active, follower.invisible = true, false
follower.px, follower.py, follower.sheet, follower.palRow = 32, 64, 1, 0
follower.y2 = -3

-- Use the actual OWE sprite callback without invoking encounter generation.
local oweDraw = section(source("owe.lua"), "local function pose(a)", "local function spawnOWE")
local getOweDraw = assert(loadSource("return function(E, A)\n"
  .. "local FACE_FRAME = { down = 0 }; local ACT_JUMP_IN_PLACE = 4; local rshift = bit.rshift\n"
  .. oweDraw .. "\nreturn draw\nend", "@owe.lua:draw"))()
local owe = E.actors[2]
-- Respect the callback name installed by the actual spawn code in each candidate.
local callbackName = assert(source("owe.lua"):match("a%.(%w+), a%.pose = draw, pose"))
owe[callbackName] = getOweDraw(E, E.Data.ATLAS)
owe.active, owe.px, owe.py = true, 64, 80
owe.sheet, owe.palRow, owe.y2, owe.icon = 1, 0, -5, -1
local fx = E.Owe.fx[1]
fx.active, fx.px, fx.py = true, 96, 97

local function only(actor)
  follower.active, owe.active, fx.active = false, false, false
  actor.active = true
  sprites, seen = {}, {}
end

test("follower draws original actor with screen coordinates and y2", function()
  only(follower)
  E.FieldView.draw(7, 11)
  equal(#sprites, 1); equal(sprites[1].x, 25); equal(sprites[1].y, 50)
  equal(seen.shadow, follower); equal(seen.grass, follower)
end)
test("OWE draws original actor with screen coordinates and y2", function()
  only(owe)
  E.FieldView.draw(7, 11)
  equal(#sprites, 1); equal(sprites[1].x, 57); equal(sprites[1].y, 64)
  equal(seen.shadow, owe)
end)
test("spawn effect draws original effect state", function()
  only(fx)
  E.FieldView.draw(7, 11)
  local h = E.Data.ATLAS.sheets[4]
  equal(#sprites, 1); equal(sprites[1].x, 89)
  equal(sprites[1].y, 97 - 11 - 1 + bit.rshift(h, 1) - 16)
end)
test("grass redraw retains original actor and recorded screen origin", function()
  only(follower)
  E.FieldView.draw(7, 11)
  equal(follower.lastSx, 25); equal(follower.lastSy, 53)
  -- drawFront runs inside FieldView, with a player north of the follower.
  -- The integration hook's raw renderer consults this hook on the next draw.
  local oldDraw = E.drawGrass
  E.drawGrass = function(a, x, y, front)
    if front and not E.redrawing then E.FieldEffects.drawFront(7, 11, 48) end
  end
  sprites = {}
  E.FieldView.draw(7, 11)
  E.drawGrass = oldDraw
  equal(#sprites, 2); equal(sprites[2].x, 25); equal(sprites[2].y, 50)
  equal(E.redrawing, false)
end)
test("ordinary graphics IDs still delegate to engine", function()
  local n = nativeCalls
  E.OwSprites.draw(7, 10, 20, 7, 11, "down", 0, false)
  equal(nativeCalls, n + 1)
end)
test("mod actors are absent outside the field draw pass", function()
  local list = E.Objects.forDraw()
  equal(#list, 1); equal(list[1], native)
end)
test("graphics binding is balanced after successful draws", function()
  only(fx)
  local b, u = binds, unbinds
  E.FieldView.draw(7, 11)
  equal(binds - b, 1); equal(unbinds - u, 1)
end)
test("draw failure clears field-pass and redraw state", function()
  only(follower)
  local callback = follower.drawSprite or follower.draw
  local name = follower.drawSprite and "drawSprite" or "draw"
  follower[name] = function() error("intentional draw failure") end
  local ok, err = pcall(E.FieldView.draw, 7, 11)
  follower[name] = callback
  equal(ok, false); assert(tostring(err):find("intentional draw failure", 1, true))
  equal(#E.Objects.forDraw(), 1); equal(E.redrawing, false)
  E.FieldView.draw(7, 11)
end)
test("camera and vertical-offset sweep", function()
  only(follower)
  for x = -16, 16, 8 do
    for y = -16, 16, 8 do
      for offset = -8, 0 do
        follower.y2 = offset
        sprites = {}
        E.FieldView.draw(x, y)
        equal(sprites[1].x, 32 - x); equal(sprites[1].y, 64 - y + offset)
      end
    end
  end
end)
print("METRIC failures=" .. failures)
print("METRIC cases=" .. cases)
if failures > 0 then os.exit(1) end
