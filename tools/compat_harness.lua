-- Loads the real Secrets_reveal/main.lua under Isaac API stubs and checks it
-- behaves identically whether or not Guaranteed Crawlspaces is present.

local MAIN = ...

local VecMT = {}
VecMT.__index = VecMT
function VecMT:Distance(o)
  local dx, dy = self.X - o.X, self.Y - o.Y
  return math.sqrt(dx * dx + dy * dy)
end
function VecMT:__add(o) return Vector(self.X + o.X, self.Y + o.Y) end
function VecMT:__sub(o) return Vector(self.X - o.X, self.Y - o.Y) end
-- Callable table rather than a plain function, so Vector.Zero can exist the way
-- the real API has it.
local function makeVector(x, y) return setmetatable({ X = x, Y = y }, VecMT) end
Vector = setmetatable({}, { __call = function(_, x, y) return makeVector(x, y) end })
Vector.Zero = makeVector(0, 0)

function Color(r, g, b, a) return { R = r, G = g, B = b, A = a,
  SetColorize = function() end, SetTint = function() end } end
function KColor(r, g, b, a) return { Red = r, Green = g, Blue = b, Alpha = a } end

local RngMT = {}
RngMT.__index = RngMT
function RngMT:SetSeed(s) self.seed = s end
function RngMT:RandomInt(n) return self.seed % n end
function RNG() return setmetatable({ seed = 1 }, RngMT) end

GridEntityType = {
  GRID_DECORATION = 1, GRID_ROCK = 2, GRID_ROCKB = 3, GRID_ROCKT = 4,
  GRID_ROCK_BOMB = 5, GRID_ROCK_ALT = 6, GRID_PIT = 7, GRID_TNT = 12,
  GRID_WALL = 15, GRID_STAIRS = 18, GRID_ROCK_SS = 22,
  GRID_ROCK_SPIKED = 25, GRID_ROCK_ALT2 = 26, GRID_ROCK_GOLD = 27,
}
RoomType = { ROOM_SECRET = 7, ROOM_SUPERSECRET = 8, ROOM_ULTRASECRET = 29 }
RoomDescriptor = { DISPLAY_BOX = 1 << 0, DISPLAY_LOCK = 1 << 1, DISPLAY_ICON = 1 << 2 }
Dimension = { NORMAL = 0, MIRROR = 1 }
ModCallbacks = {
  MC_POST_NEW_LEVEL = "level", MC_POST_NEW_ROOM = "room",
  MC_POST_UPDATE = "update", MC_POST_RENDER = "render",
  MC_EXECUTE_CMD = "cmd", MC_POST_GAME_STARTED = "start",
}
ModConfigMenu = nil

-- Only the members Secrets_reveal names; the numbers are the real ones.
Keyboard = { KEY_F1 = 290, KEY_F2 = 291, KEY_F3 = 292, KEY_F4 = 293,
             KEY_GRAVE_ACCENT = 96, KEY_TAB = 258 }
InputHook = { IS_ACTION_PRESSED = 0 }
ButtonAction = {}

-- No key is ever held; the hotkey path is not what is under test here.
Input = {
  IsButtonTriggered = function() return false end,
  IsButtonPressed = function() return false end,
  IsActionTriggered = function() return false end,
  IsActionPressed = function() return false end,
  GetButtonValue = function() return 0 end,
}

package.preload["json"] = function()
  local stash
  return { encode = function(t) stash = t; return "<b>" end,
           decode = function() return stash end }
end

----------------------------------------------------------------------
-- Recording render surfaces
----------------------------------------------------------------------

local rendered = {}          -- {frame=, x=, y=}
local texts = {}

local function newSprite()
  local s = {
    Color = Color(1, 1, 1, 1),
    _frame = 0,
    Load = function() end,
    SetFrame = function(self, anim, f) self._frame = f end,
    Play = function() end,
    Update = function() end,
    Render = function(self, pos)
      rendered[#rendered + 1] = { frame = self._frame, x = pos.X, y = pos.Y }
    end,
    RenderLayer = function() end,
  }
  return s
end
function Sprite() return newSprite() end

function Font()
  return {
    Load = function() return true end,
    IsLoaded = function() return true end,
    DrawString = function(self, str) texts[#texts + 1] = str end,
    DrawStringScaled = function(self, str) texts[#texts + 1] = str end,
    GetStringWidth = function(_, s) return #s * 4 end,
    GetLineHeight = function() return 8 end,
  }
end

----------------------------------------------------------------------
-- World
----------------------------------------------------------------------

local W, H = 15, 9
local world = {
  frame = 0, stage = 1, stageType = 0,
  gridEntities = {},          -- index -> {type=, state=}
  dungeonIdx = -1,
  rooms = {},                 -- list of descriptors
  revealed = {},              -- ListIndex -> true when DisplayFlags written
}

local function gridPos(i) return Vector((i % W) * 40, math.floor(i / W) * 40) end

local room = {}
function room:GetType() return 1 end
function room:GetGridSize() return W * H end
function room:GetGridWidth() return W end
function room:GetGridHeight() return H end
function room:GetGridPosition(i) return gridPos(i) end
function room:GetDungeonRockIdx() return world.dungeonIdx end
function room:GetGridEntity(i)
  local g = world.gridEntities[i]
  if g == nil then return nil end
  return { State = g.state, Position = gridPos(i),
           GetType = function() return g.type end }
end
function room:GetRenderMode() return 0 end
function room:GetCenterPos() return Vector(280, 160) end
function room:GetTopLeftPos() return Vector(40, 40) end
function room:GetBottomRightPos() return Vector(520, 280) end
function room:IsMirrorWorld() return false end
function room:GetRoomShape() return 1 end

local level = {}
function level:GetStage() return world.stage end
function level:GetStageType() return world.stageType end
function level:GetDimension() return 0 end
function level:GetRooms()
  return { Size = #world.rooms, Get = function(_, i) return world.rooms[i + 1] end }
end
function level:GetRoomByIdx(idx)
  for _, d in ipairs(world.rooms) do
    if d.SafeGridIndex == idx then return d end
  end
  return nil
end
function level:UpdateVisibility() end
function level:GetCurrentRoomDesc() return world.rooms[1] end
function level:GetCurrentRoomIndex() return 4 end

local game = {}
function game:GetLevel() return level end
function game:GetRoom() return room end
function game:GetFrameCount() return world.frame end
function game:IsGreedMode() return false end
function game:IsPaused() return false end
function game:GetHUD() return { IsVisible = function() return true end } end
function Game() return game end

Isaac = {}
function Isaac.GetFrameCount() return world.frame end
function Isaac.WorldToScreen(v) return v end
function Isaac.WorldToRenderPosition(v) return v end
function Isaac.RenderText(str) texts[#texts + 1] = str end
function Isaac.GetScreenWidth() return 480 end
function Isaac.GetScreenHeight() return 270 end
function Isaac.GetPlayer() return { Position = Vector(280, 200) } end

local callbacks = {}
local saved = nil
function RegisterMod()
  return {
    AddCallback = function(_, id, fn) callbacks[id] = fn end,
    SaveData = function(_, s) saved = s end,
    LoadData = function() return saved end,
    HasData = function() return saved ~= nil end,
  }
end

----------------------------------------------------------------------
-- Load Secrets_reveal
----------------------------------------------------------------------

local function makeDesc(listIndex, safeGrid, roomType, hasLayoutCrawl)
  local spawns
  if hasLayoutCrawl then
    local entry = { Type = 9100 }
    local spawn = { EntryCount = 1,
                    Entries = { Get = function(_, j) return j == 0 and entry or nil end } }
    spawns = { Size = 1, Get = function(_, i) return i == 0 and spawn or nil end }
  else
    spawns = { Size = 0, Get = function() return nil end }
  end
  return {
    ListIndex = listIndex, SafeGridIndex = safeGrid, DisplayFlags = 0,
    Data = { Type = roomType, Spawns = spawns,
             SpawnCount = hasLayoutCrawl and 1 or 0 },
  }
end

world.rooms = {
  makeDesc(0, 4, 1, false),
  makeDesc(1, 5, 1, false),
  makeDesc(2, 6, 7, false),      -- a secret room
  makeDesc(3, 7, 1, true),       -- layout carries a crawlspace
}

local chunk, err = loadfile(MAIN)
if chunk == nil then error("load failed: " .. tostring(err)) end
chunk()

----------------------------------------------------------------------
-- Assertions
----------------------------------------------------------------------

local failures, passes = 0, 0
local function check(name, cond, detail)
  if cond then passes = passes + 1
  else
    failures = failures + 1
    print("FAIL  " .. name .. (detail and ("  -- " .. detail) or ""))
  end
end

local MARKER_CRAWLROCK = 4

local function runRoom()
  rendered, texts = {}, {}
  world.frame = world.frame + 100
  callbacks["start"]()
  callbacks["level"]()
  callbacks["room"]()
  callbacks["update"]()
  callbacks["render"]()
end

local function tryRoom()
  local ok, err = pcall(runRoom)
  if not ok then print("   ERROR: " .. tostring(err)) end
  return ok
end

local function markerAt(frame)
  for _, r in ipairs(rendered) do
    if r.frame == frame then return r end
  end
  return nil
end

local ROCK_A, ROCK_B = 4 * 15 + 4, 3 * 15 + 9

----------------------------------------------------------------------
-- Case A: Guaranteed Crawlspaces absent entirely.
----------------------------------------------------------------------
GuaranteedCrawlspaces = nil
world.gridEntities = { [ROCK_A] = { type = 2, state = 0 },
                       [ROCK_B] = { type = 2, state = 0 } }
world.dungeonIdx = ROCK_A

local ok = tryRoom()
check("absent: runs without error", ok)
local m = markerAt(MARKER_CRAWLROCK)
check("absent: buried-crawlspace marker still drawn", m ~= nil)
check("absent: drawn at the engine's index",
      m and m.x == gridPos(ROCK_A).X and m.y == gridPos(ROCK_A).Y,
      m and (m.x .. "," .. m.y) or "none")
check("absent: layout crawlspace room still revealed on the map",
      world.rooms[4].DisplayFlags ~= 0,
      tostring(world.rooms[4].DisplayFlags))
check("absent: a plain room is not revealed", world.rooms[2].DisplayFlags == 0)

----------------------------------------------------------------------
-- Case B: present, and it moved the crawlspace to a different rock.
----------------------------------------------------------------------
for _, d in ipairs(world.rooms) do d.DisplayFlags = 0 end
GuaranteedCrawlspaces = {
  GetRockIndex = function() return ROCK_B end,
  GetRoomListIndex = function() return 1 end,
}
local ok2 = tryRoom()
check("present: runs without error", ok2)
local m2 = markerAt(MARKER_CRAWLROCK)
check("present: marker follows the moved rock",
      m2 and m2.x == gridPos(ROCK_B).X and m2.y == gridPos(ROCK_B).Y,
      m2 and (m2.x .. "," .. m2.y) or "none")
check("present: the named room is revealed on the map",
      world.rooms[2].DisplayFlags ~= 0)

----------------------------------------------------------------------
-- Case C: present but reporting nothing (mod switched off in its own menu).
----------------------------------------------------------------------
for _, d in ipairs(world.rooms) do d.DisplayFlags = 0 end
GuaranteedCrawlspaces = {
  GetRockIndex = function() return -1 end,
  GetRoomListIndex = function() return -1 end,
}
local ok3 = tryRoom()
check("silent: runs without error", ok3)
local m3 = markerAt(MARKER_CRAWLROCK)
check("silent: falls back to the engine's index",
      m3 and m3.x == gridPos(ROCK_A).X and m3.y == gridPos(ROCK_A).Y,
      m3 and (m3.x .. "," .. m3.y) or "none")
check("silent: no extra room revealed", world.rooms[2].DisplayFlags == 0)

----------------------------------------------------------------------
-- Case D: present but broken -- a consumer must not be taken down by it.
----------------------------------------------------------------------
for _, d in ipairs(world.rooms) do d.DisplayFlags = 0 end
GuaranteedCrawlspaces = {
  GetRockIndex = function() error("boom") end,
  GetRoomListIndex = function() error("boom") end,
}
local ok4 = tryRoom()
check("throwing API: Secrets Reveal survives", ok4)
local m4 = markerAt(MARKER_CRAWLROCK)
check("throwing API: falls back to the engine's index",
      m4 and m4.x == gridPos(ROCK_A).X)

----------------------------------------------------------------------
-- Case E: present but returning nonsense types.
----------------------------------------------------------------------
GuaranteedCrawlspaces = {
  GetRockIndex = function() return "nonsense" end,
  GetRoomListIndex = function() return {} end,
}
local ok5 = tryRoom()
check("nonsense API: Secrets Reveal survives", ok5)
local m5 = markerAt(MARKER_CRAWLROCK)
check("nonsense API: falls back to the engine's index",
      m5 and m5.x == gridPos(ROCK_A).X)

print(string.format("\n%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
