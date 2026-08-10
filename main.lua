--[[
  Secrets Reveal
  ------------------------------------------------------------------
  Reveals the things the game deliberately hides:
    * Secret Room / Super Secret Room / Ultra Secret Room on the map
    * Rooms that contain a Crawlspace (revealed on the map)
    * In-room markers over Crawlspaces, Tinted Rocks, Super Tinted Rocks and
      X-marked skulls

  Config is persisted through mod data and exposed through Mod Config Menu
  when that mod is installed.
--]]

local mod  = RegisterMod("Secrets Reveal", 1)
local json = require("json")

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------

-- Map display flags: bit 0 = room box, bit 2 = room icon. 5 == "fully shown".
local DISPLAY_REVEALED = 5

-- Grid types we care about. The `or` fallbacks keep this working even if a
-- future patch renames an enum member.
local GRID_TINTED = GridEntityType.GRID_ROCKT     or 4   -- Tinted Rock
local GRID_SUPER  = GridEntityType.GRID_ROCK_SS   or 22  -- Super Tinted Rock
local GRID_CRAWL  = GridEntityType.GRID_STAIRS    or 18  -- Crawlspace
-- Observed in game: this type matches the X-marked skull that yields a reward
-- when broken, and nothing else. It is NOT the Downpour crawlspace rock this
-- was originally, and wrongly, written for. Marking it is still worthwhile --
-- an X-marked skull is exactly the kind of thing this mod exists to point at --
-- but do not describe it as a crawlspace hint.
local GRID_MARKED = GridEntityType.GRID_ROCK_ALT2 or 26

-- Every rock type a crawlspace can actually be dug out of. Built from enum
-- names so a member missing on some build is skipped instead of turning into a
-- bad guess.
--
-- GRID_ROCKB is deliberately absent: it is the immovable block, not a rock.
-- Bombable rocks have their own type (GRID_ROCK_BOMB), so nothing breakable is
-- lost by excluding it. When the engine's chosen index lands on a block the
-- crawlspace is genuinely unreachable, and marking it promised a crawlspace
-- that was never there.
local ROCK_TYPES = {}
for _, name in ipairs({
  "GRID_ROCK", "GRID_ROCKT", "GRID_ROCK_BOMB", "GRID_ROCK_ALT",
  "GRID_ROCK_SS", "GRID_ROCK_SPIKED", "GRID_ROCK_ALT2", "GRID_ROCK_GOLD",
}) do
  local value = GridEntityType[name]
  if value then ROCK_TYPES[value] = true end
end

-- Frame indices inside gfx/secretsreveal_markers.anm2
local MARKER_TINTED    = 0
local MARKER_SUPER     = 1
local MARKER_CRAWL     = 2
local MARKER_MARKED    = 3
local MARKER_CRAWLROCK = 4

-- Secondary markers are drawn fainter so they never compete with the ones
-- pointing at a confirmed crawlspace or tinted rock.
local CANDIDATE_ALPHA = 0.55

-- The spritesheet is white, so a marker's colour is whatever tint it is drawn
-- with. Keep this list append-only: saved configs store the index, so
-- reordering it would silently repaint everyone's markers.
local PALETTE = {
  { name = "White",  r = 1.00, g = 1.00, b = 1.00 },
  { name = "Cyan",   r = 0.35, g = 0.86, b = 1.00 },
  { name = "Blue",   r = 0.42, g = 0.56, b = 1.00 },
  { name = "Green",  r = 0.47, g = 0.90, b = 0.55 },
  { name = "Lime",   r = 0.72, g = 1.00, b = 0.33 },
  { name = "Gold",   r = 1.00, g = 0.80, b = 0.24 },
  { name = "Orange", r = 1.00, g = 0.58, b = 0.20 },
  { name = "Red",    r = 1.00, g = 0.36, b = 0.36 },
  { name = "Pink",   r = 1.00, g = 0.50, b = 0.80 },
  { name = "Violet", r = 0.78, g = 0.51, b = 1.00 },
}

local PALETTE_CYAN, PALETTE_GREEN   = 2, 4
local PALETTE_GOLD, PALETTE_VIOLET  = 6, 10

-- Which config entry supplies each frame's tint.
local MARKER_COLOR_KEY = {
  [MARKER_TINTED]    = "colorTinted",
  [MARKER_SUPER]     = "colorSuper",
  [MARKER_CRAWL]     = "colorCrawl",
  [MARKER_MARKED]    = "colorMarked",
  [MARKER_CRAWLROCK] = "colorCrawlRock",
}

-- Entity id used for a crawlspace inside a room layout (STB/XML "spawn" id).
local SPAWN_ID_CRAWLSPACE = 9100

local ROCK_STATE_BROKEN = 2

-- Built key by key so a missing enum member degrades instead of erroring at
-- load time (a nil table key is a hard error in a table constructor).
local SECRET_ROOM_TYPES = {}
SECRET_ROOM_TYPES[RoomType.ROOM_SECRET      or 7]  = "secret"
SECRET_ROOM_TYPES[RoomType.ROOM_SUPERSECRET or 8]  = "supersecret"
SECRET_ROOM_TYPES[RoomType.ROOM_ULTRASECRET or 29] = "ultrasecret"

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------

local DEFAULTS = {
  enabled      = true,   -- master switch (toggle key flips this)

  secret       = true,   -- reveal Secret Rooms on the map
  supersecret  = true,   -- reveal Super Secret Rooms on the map
  ultrasecret  = true,   -- reveal Ultra Secret Rooms on the map
  crawlRooms   = true,   -- reveal rooms whose layout contains a crawlspace

  markCrawl    = true,   -- in-room marker over crawlspaces
  markTinted   = true,   -- in-room marker over tinted rocks
  markSuper    = true,   -- in-room marker over super tinted rocks
  markRubble   = true,   -- faint marker over X-marked skulls (key kept for
                         -- compatibility with configs saved before the rename)
  markCrawlRock = true,  -- marker over the rock this room hides a crawlspace in

  -- Marker colours, as indices into PALETTE
  colorTinted    = PALETTE_CYAN,
  colorSuper     = PALETTE_GOLD,
  colorCrawl     = PALETTE_VIOLET,
  colorMarked    = PALETTE_GREEN,
  colorCrawlRock = PALETTE_VIOLET,

  pulse        = true,   -- markers fade in and out
  opacity      = 1.0,    -- overall marker transparency
  scale        = 1.0,    -- marker size multiplier
  notify       = true,   -- short on-screen notices (bottom-left)
  noticeScale  = 0.8,    -- notice text size multiplier

  toggleKey    = Keyboard.KEY_F5 or 294,  -- toggles the whole mod
  noticeKey    = Keyboard.KEY_F6 or 295,  -- toggles the bottom-left notices
}

local cfg = {}
for k, v in pairs(DEFAULTS) do cfg[k] = v end

local function saveConfig()
  mod:SaveData(json.encode(cfg))
end

local function loadConfig()
  if not mod:HasData() then return end
  local ok, decoded = pcall(json.decode, mod:LoadData())
  if not ok or type(decoded) ~= "table" then return end
  for k in pairs(DEFAULTS) do
    if decoded[k] ~= nil then cfg[k] = decoded[k] end
  end

  -- A colour index from an older or hand-edited config must never index past
  -- the palette: that would be a nil lookup on every rendered marker.
  for _, key in pairs(MARKER_COLOR_KEY) do
    local index = cfg[key]
    if type(index) ~= "number" or not PALETTE[index] then
      cfg[key] = DEFAULTS[key]
    end
  end

  -- Likewise the multipliers: a non-number would poison every Color() call,
  -- and zero opacity would look identical to the mod being broken.
  for key, lowest in pairs({ opacity = 0.05, scale = 0.1, noticeScale = 0.1 }) do
    if type(cfg[key]) ~= "number" or cfg[key] < lowest then
      cfg[key] = DEFAULTS[key]
    end
  end
end

loadConfig()

----------------------------------------------------------------------
-- Rendering helpers
----------------------------------------------------------------------

local markerSprite   = Sprite()
local markerAvailable = nil  -- nil = not tried yet

local function ensureSprite()
  if markerAvailable ~= nil then return markerAvailable end
  markerAvailable = pcall(function()
    markerSprite:Load("gfx/secretsreveal_markers.anm2", true)
    markerSprite:SetFrame("Marker", MARKER_TINTED)
  end)
  return markerAvailable
end

-- Smallest legible font first. luaminioutlined carries its own black outline,
-- which keeps it readable over any floor. Fall back through progressively
-- larger fonts if a build is missing one.
local FONT_CANDIDATES = {
  "font/luaminioutlined.fnt",
  "font/pftempestasevencondensed.fnt",
  "font/terminus.fnt",
}

local font       = Font()
local fontLoaded = false
local fontHeight = 8

for _, path in ipairs(FONT_CANDIDATES) do
  local ok, loaded = pcall(function()
    font:Load(path)
    return font:IsLoaded()
  end)
  if ok and loaded then
    fontLoaded = true
    local okHeight, height = pcall(function() return font:GetLineHeight() end)
    if okHeight and height and height > 0 then fontHeight = height end
    break
  end
end

local function drawText(text, x, y, alpha, scale)
  if not fontLoaded then
    Isaac.RenderText(text, x, y, 1, 1, 1, alpha)
    return
  end
  scale = scale or 1
  font:DrawStringScaled(text, x, y, scale, scale, KColor(1, 1, 1, alpha), 0, false)
end

-- Both set once per room scan rather than per marker: the dimension cannot
-- change without a room change, and probing it is a guarded call.
local roomMirrored = false
local mirrorAxisX  = 0

local function isMirrorWorld(room)
  local ok, mirrored = pcall(function() return room:IsMirrorWorld() end)
  return ok and mirrored == true
end

-- The horizontal middle of the room, derived from its static bounds.
-- GetCenterPos is NOT usable here: in a room large enough to scroll it follows
-- the camera, so reflecting about it made markers slide sideways as the player
-- moved. Top-left and bottom-right are fixed for the life of the room.
local function mirrorAxisFor(room)
  local ok, axis = pcall(function()
    return (room:GetTopLeftPos().X + room:GetBottomRightPos().X) * 0.5
  end)
  if ok and axis then return axis end
  return room:GetCenterPos().X
end

-- Must be WorldToScreen, not WorldToRenderPosition. The latter is relative to
-- the room's render origin and carries no camera scroll, so markers freeze on
-- screen the moment a room is large enough for the camera to follow the player.
-- Rooms that never scroll hide the difference entirely.
local function worldToScreen(pos)
  local room = Game():GetRoom()

  -- Downpour II's mirror dimension draws the room flipped horizontally while
  -- grid entities keep their unmirrored world coordinates, so reflect X about
  -- the room's midline or every marker lands on the wrong side of the room.
  if roomMirrored then
    pos = Vector(mirrorAxisX * 2 - pos.X, pos.Y)
  end

  if Isaac.WorldToScreen then
    return Isaac.WorldToScreen(pos)
  end
  -- Fallback: undo the scroll by hand.
  return Isaac.WorldToRenderPosition(pos) - room:GetRenderScrollOffset()
end

----------------------------------------------------------------------
-- Notifications
----------------------------------------------------------------------

-- Anchored to the bottom-left corner. Bump NOTICE_BOTTOM_MARGIN if the text
-- ever collides with the pocket item / card slot down there.
local NOTICE_X             = 6
local NOTICE_BOTTOM_MARGIN = 8

local notices = {}  -- { {text = string, expires = renderFrame}, ... }

local function notify(text, seconds)
  if not cfg.notify then return end
  notices[#notices + 1] = {
    text    = text,
    expires = Isaac.GetFrameCount() + math.floor((seconds or 4) * 60),
  }
end

----------------------------------------------------------------------
-- Map reveal
----------------------------------------------------------------------

-- Walks a room's layout data looking for a given spawn id. Room layout data is
-- only exposed on newer API revisions, so every access is guarded.
local function layoutContainsSpawn(data, spawnId)
  if not data then return false end
  local ok, found = pcall(function()
    local spawns = data.Spawns
    if not spawns then return false end
    local spawnCount = data.SpawnCount or spawns.Size or 0
    for i = 0, spawnCount - 1 do
      local spawn = spawns:Get(i)
      if spawn then
        local entries = spawn.Entries
        for j = 0, (spawn.EntryCount or 0) - 1 do
          local entry = entries:Get(j)
          if entry and entry.Type == spawnId then return true end
        end
      end
    end
    return false
  end)
  return ok and found or false
end

local function revealRooms()
  local level = Game():GetLevel()
  local rooms = level:GetRooms()

  local found = { secret = 0, supersecret = 0, ultrasecret = 0, crawl = 0 }
  local changed = false

  for i = 0, rooms.Size - 1 do
    local desc = rooms:Get(i)
    if desc and desc.Data then
      local gridIndex = desc.SafeGridIndex
      -- Off-grid rooms (the crawlspace interior itself, Devil deals, ...) have
      -- a negative index and cannot be placed on the map.
      if gridIndex >= 0 then
        local key      = SECRET_ROOM_TYPES[desc.Data.Type]
        local isSecret = key ~= nil and cfg[key]
        local isCrawl  = cfg.crawlRooms
                         and layoutContainsSpawn(desc.Data, SPAWN_ID_CRAWLSPACE)

        if isSecret or isCrawl then
          -- GetRoomByIdx returns the descriptor for the *current* dimension, so
          -- confirm it is the same room before writing. Mirror / Ascent rooms
          -- share grid indices with their normal-dimension counterparts.
          local writable = level:GetRoomByIdx(gridIndex)
          if writable and writable.ListIndex == desc.ListIndex then
            if isSecret then found[key]   = found[key]   + 1 end
            if isCrawl  then found.crawl  = found.crawl  + 1 end

            local flags = writable.DisplayFlags | DISPLAY_REVEALED
            if flags ~= writable.DisplayFlags then
              writable.DisplayFlags = flags
              changed = true
            end
          end
        end
      end
    end
  end

  if changed then level:UpdateVisibility() end
  return found
end

----------------------------------------------------------------------
-- In-room grid scanning
----------------------------------------------------------------------

local tracked      = {}  -- { {pos = Vector, frame = int}, ... }
local lastScanFrame = -1

local function isIntactRock(grid)
  return grid.State ~= ROCK_STATE_BROKEN
end

local function rescanRoom()
  tracked = {}

  local room = Game():GetRoom()
  local size = room:GetGridSize()

  roomMirrored = isMirrorWorld(room)
  if roomMirrored then mirrorAxisX = mirrorAxisFor(room) end

  -- The engine already knows which grid index hides this room's crawlspace --
  -- "dungeon" is its internal name for one -- so ask rather than reproduce the
  -- seed maths. Returns an index outside the grid when the room has none.
  local crawlRockIdx = -1
  if cfg.markCrawlRock then
    local ok, idx = pcall(function() return room:GetDungeonRockIdx() end)
    if ok and type(idx) == "number" then crawlRockIdx = idx end
  end

  for i = 0, size - 1 do
    local grid = room:GetGridEntity(i)
    if grid then
      local gtype = grid:GetType()

      -- Checked before the type branches so it wins over the plain tinted or
      -- X-marked treatment when the crawlspace happens to be under one of those.
      if i == crawlRockIdx and ROCK_TYPES[gtype] and isIntactRock(grid) then
        tracked[#tracked + 1] = { pos = grid.Position, frame = MARKER_CRAWLROCK }
      elseif gtype == GRID_CRAWL then
        if cfg.markCrawl then
          tracked[#tracked + 1] = { pos = grid.Position, frame = MARKER_CRAWL }
        end
      elseif gtype == GRID_TINTED then
        if cfg.markTinted and isIntactRock(grid) then
          tracked[#tracked + 1] = { pos = grid.Position, frame = MARKER_TINTED }
        end
      elseif gtype == GRID_SUPER then
        if cfg.markSuper and isIntactRock(grid) then
          tracked[#tracked + 1] = { pos = grid.Position, frame = MARKER_SUPER }
        end
      elseif gtype == GRID_MARKED then
        if cfg.markRubble and isIntactRock(grid) then
          tracked[#tracked + 1] = {
            pos = grid.Position, frame = MARKER_MARKED, faint = true,
          }
        end
      end
    end
  end
end

local function describeRoomContents()
  local counts = {
    [MARKER_TINTED] = 0, [MARKER_SUPER]  = 0, [MARKER_CRAWL] = 0,
    [MARKER_MARKED] = 0, [MARKER_CRAWLROCK] = 0,
  }
  for _, m in ipairs(tracked) do counts[m.frame] = counts[m.frame] + 1 end

  -- X-marked skulls are deliberately left out. The notice is for things worth
  -- changing your route over; the skull already advertises itself with the X.
  local parts = {}
  if counts[MARKER_CRAWL]     > 0 then parts[#parts + 1] = "Crawlspace"           end
  if counts[MARKER_CRAWLROCK] > 0 then parts[#parts + 1] = "Crawlspace under rock" end
  if counts[MARKER_SUPER]  > 0 then parts[#parts + 1] = "Super Tinted Rock" end
  if counts[MARKER_TINTED] > 0 then parts[#parts + 1] = "Tinted Rock"       end

  if #parts == 0 then return nil end
  return "In this room: " .. table.concat(parts, ", ")
end

----------------------------------------------------------------------
-- Callbacks
----------------------------------------------------------------------

function mod:onNewLevel()
  if not cfg.enabled then return end

  local found = revealRooms()

  local parts = {}
  if found.secret      > 0 then parts[#parts + 1] = "Secret"       end
  if found.supersecret > 0 then parts[#parts + 1] = "Super Secret" end
  if found.ultrasecret > 0 then parts[#parts + 1] = "Ultra Secret" end

  local summary = {}
  if #parts > 0 then
    summary[#summary + 1] = table.concat(parts, " + ") .. " revealed"
  end
  if found.crawl > 0 then
    summary[#summary + 1] = string.format("%d crawlspace room%s",
      found.crawl, found.crawl == 1 and "" or "s")
  end
  if #summary > 0 then
    notify(table.concat(summary, "  |  "), 5)
  end
end

function mod:onNewRoom()
  if not cfg.enabled then
    tracked = {}
    return
  end

  -- Re-apply on every room change: the game re-derives visibility during
  -- transitions and a fresh reveal also covers rooms added mid-floor.
  revealRooms()

  rescanRoom()
  lastScanFrame = Game():GetFrameCount()

  local desc = describeRoomContents()
  if desc then notify(desc, 3) end
end

function mod:onUpdate()
  if not cfg.enabled then return end

  -- Rocks get destroyed and crawlspaces get uncovered mid-room, so refresh the
  -- marker list periodically rather than only on room entry.
  local frame = Game():GetFrameCount()
  if frame - lastScanFrame >= 10 then
    lastScanFrame = frame
    rescanRoom()
  end
end

local keyCooldown = 0

local function setNotices(on)
  cfg.notify = on
  if on then
    notify("Notices: ON", 2)
  else
    notices = {}
  end
  saveConfig()
end

local function setEnabled(on)
  cfg.enabled = on
  if on then
    revealRooms()
    rescanRoom()
    notify("Secrets Reveal: ON", 2)
  else
    tracked = {}
    notices = {}
  end
  saveConfig()
end

-- Forward declaration; defined with the Mod Config Menu block below.
local tryModConfigMenu

-- Mod Config Menu draws its own full-screen UI without pausing the game, so
-- Game():IsPaused() stays false and nothing else here would notice it is open.
-- Tolerates IsVisible being either a field or a function.
local function configMenuOpen()
  if not ModConfigMenu then return false end
  local visible = ModConfigMenu.IsVisible
  if type(visible) == "function" then
    local ok, result = pcall(visible)
    return ok and result == true
  end
  return visible == true
end

local function resetColors()
  for _, key in pairs(MARKER_COLOR_KEY) do cfg[key] = DEFAULTS[key] end
  saveConfig()
end

local function resetAll()
  for key, value in pairs(DEFAULTS) do cfg[key] = value end
  saveConfig()
end

function mod:onRender()
  tryModConfigMenu()

  -- Nothing this mod draws belongs on top of a menu, and while Mod Config Menu
  -- is capturing input a rebind prompt would otherwise see F5/F6 as a toggle.
  if configMenuOpen() then return end

  -- Keys are polled here so they also work while the game is paused.
  if keyCooldown > 0 then keyCooldown = keyCooldown - 1 end
  if keyCooldown == 0 then
    if cfg.toggleKey and cfg.toggleKey >= 0
       and Input.IsButtonTriggered(cfg.toggleKey, 0) then
      keyCooldown = 20
      setEnabled(not cfg.enabled)
    elseif cfg.noticeKey and cfg.noticeKey >= 0
       and Input.IsButtonTriggered(cfg.noticeKey, 0) then
      keyCooldown = 20
      setNotices(not cfg.notify)
    end
  end

  -- Checked after the keys so F5/F6 still work from the pause screen, but
  -- before anything is drawn so neither markers nor notices land on the menu.
  if Game():IsPaused() then return end

  local now = Isaac.GetFrameCount()

  -- Notices, stacked upward from the bottom-left corner with the newest last.
  if not cfg.notify then notices = {} end
  for i = #notices, 1, -1 do
    if notices[i].expires <= now then
      table.remove(notices, i)
    end
  end

  if #notices > 0 then
    local scale  = cfg.noticeScale
    local lineH  = fontHeight * scale
    local bottom = Isaac.GetScreenHeight() - NOTICE_BOTTOM_MARGIN
    local count  = #notices
    for i = count, 1, -1 do
      local alpha = math.min(1, (notices[i].expires - now) / 45)
      drawText(notices[i].text, NOTICE_X, bottom - lineH * (count - i + 1), alpha, scale)
    end
  end

  if not cfg.enabled or #tracked == 0 then return end
  if not ensureSprite() then return end

  -- Opacity scales whatever the pulse produces, so the two settings compose
  -- instead of one overriding the other.
  local alpha = cfg.opacity
  if cfg.pulse then
    alpha = alpha * (0.6 + 0.35 * math.sin(now * 0.12))
  end

  markerSprite.Scale = Vector(cfg.scale, cfg.scale)

  for _, m in ipairs(tracked) do
    -- The sheet is white, so this tint is the marker's colour outright. The
    -- black outline is unaffected: black multiplied by any tint stays black.
    local tint = PALETTE[cfg[MARKER_COLOR_KEY[m.frame]]] or PALETTE[1]
    markerSprite.Color = Color(tint.r, tint.g, tint.b,
                               m.faint and alpha * CANDIDATE_ALPHA or alpha)
    markerSprite:SetFrame("Marker", m.frame)
    markerSprite:Render(worldToScreen(m.pos), Vector.Zero, Vector.Zero)
  end
end

function mod:onCommand(cmd, params)
  cmd = string.lower(cmd)
  if cmd ~= "secrets" then return end

  params = string.lower(params or "")

  -- "secrets logs [on|off]" controls the bottom-left notices only.
  local logArg = string.match(params, "^logs%s*(%a*)$")
  if logArg then
    if     logArg == "on"  then setNotices(true)
    elseif logArg == "off" then setNotices(false)
    else                        setNotices(not cfg.notify) end
    return "Secrets Reveal notices: " .. (cfg.notify and "ON" or "OFF")
  end

  if params == "reset colours" or params == "reset colors" then
    resetColors()
    return "Secrets Reveal: marker colours reset"
  elseif params == "reset" then
    resetAll()
    rescanRoom()
    return "Secrets Reveal: all settings reset"
  end

  if     params == "off" then setEnabled(false)
  elseif params == "on"  then setEnabled(true)
  else                        setEnabled(not cfg.enabled) end
  return "Secrets Reveal: " .. (cfg.enabled and "ON" or "OFF")
end

mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.onNewLevel)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM,  mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE,    mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_RENDER,    mod.onRender)
mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD,    mod.onCommand)

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
  loadConfig()
  if cfg.enabled then revealRooms() end
end)

----------------------------------------------------------------------
-- Mod Config Menu (optional dependency)
----------------------------------------------------------------------

local mcmDone = false

local function setupModConfigMenu()
  local CATEGORY = "Secrets Reveal"

  ModConfigMenu.RemoveCategory(CATEGORY)
  ModConfigMenu.UpdateCategory(CATEGORY, {
    Info = { "Reveal secret rooms, crawlspaces and tinted rocks" },
  })

  local function addToggle(subcategory, key, label, info)
    ModConfigMenu.AddSetting(CATEGORY, subcategory, {
      Type           = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function() return cfg[key] end,
      Display        = function() return label .. ": " .. (cfg[key] and "On" or "Off") end,
      OnChange       = function(value)
        cfg[key] = value
        saveConfig()
        if key == "enabled" and not value then tracked = {} end
        revealRooms()
        rescanRoom()
      end,
      Info = info,
    })
  end

  addToggle("Map",     "enabled",     "Mod enabled",         { "Master switch for everything" })
  addToggle("Map",     "secret",      "Secret Rooms",        { "Show Secret Rooms on the map" })
  addToggle("Map",     "supersecret", "Super Secret Rooms",  { "Show Super Secret Rooms on the map" })
  addToggle("Map",     "ultrasecret", "Ultra Secret Rooms",  { "Show Ultra Secret Rooms on the map" })
  addToggle("Map",     "crawlRooms",  "Crawlspace rooms",    { "Show rooms whose layout holds a crawlspace" })

  addToggle("Markers", "markCrawl",   "Crawlspaces",         { "Marker over crawlspaces in the room" })
  addToggle("Markers", "markTinted",  "Tinted Rocks",        { "Marker over tinted rocks in the room" })
  addToggle("Markers", "markSuper",   "Super Tinted Rocks",  { "Marker over super tinted rocks in the room" })
  addToggle("Markers", "markRubble",  "X-marked skulls",     { "Faint marker over skulls carrying an X,", "which drop a reward when broken" })
  addToggle("Markers", "markCrawlRock", "Crawlspace rocks",  { "Marks the exact rock hiding this room's", "crawlspace, straight from the engine" })
  addToggle("Markers", "pulse",       "Pulsing markers",     { "Fade markers in and out" })
  addToggle("Markers", "notify",      "On-screen notices",   { "Short text when a floor or room holds a secret" })

  ModConfigMenu.AddSetting(CATEGORY, "Markers", {
    Type           = ModConfigMenu.OptionType.NUMBER,
    CurrentSetting = function() return math.floor(cfg.scale * 100) end,
    Minimum        = 50,
    Maximum        = 200,
    ModifyBy       = 10,
    Display        = function() return "Marker size: " .. math.floor(cfg.scale * 100) .. "%" end,
    OnChange       = function(value) cfg.scale = value / 100; saveConfig() end,
    Info           = { "Size of the in-room markers" },
  })

  ModConfigMenu.AddSetting(CATEGORY, "Markers", {
    Type           = ModConfigMenu.OptionType.NUMBER,
    CurrentSetting = function() return math.floor(cfg.opacity * 100) end,
    Minimum        = 10,
    Maximum        = 100,
    ModifyBy       = 5,
    Display        = function() return "Marker opacity: " .. math.floor(cfg.opacity * 100) .. "%" end,
    OnChange       = function(value) cfg.opacity = value / 100; saveConfig() end,
    Info           = { "How solid the markers are drawn.", "Scales the pulse rather than replacing it" },
  })

  ModConfigMenu.AddSetting(CATEGORY, "Markers", {
    Type           = ModConfigMenu.OptionType.NUMBER,
    CurrentSetting = function() return math.floor(cfg.noticeScale * 100) end,
    Minimum        = 50,
    Maximum        = 200,
    ModifyBy       = 10,
    Display        = function() return "Notice text size: " .. math.floor(cfg.noticeScale * 100) .. "%" end,
    OnChange       = function(value) cfg.noticeScale = value / 100; saveConfig() end,
    Info           = { "Size of the bottom-left notice text" },
  })

  -- Mod Config Menu has no colour picker, so cycle a named palette instead.
  -- Reads better than three raw RGB sliders per marker anyway.
  local function addColor(key, label)
    ModConfigMenu.AddSetting(CATEGORY, "Colours", {
      Type           = ModConfigMenu.OptionType.NUMBER,
      CurrentSetting = function() return cfg[key] end,
      Minimum        = 1,
      Maximum        = #PALETTE,
      ModifyBy       = 1,
      Display        = function()
        return label .. ": " .. (PALETTE[cfg[key]] and PALETTE[cfg[key]].name or "?")
      end,
      OnChange       = function(value)
        if PALETTE[value] then cfg[key] = value; saveConfig() end
      end,
      Info = { "Colour of the " .. label .. " marker" },
    })
  end

  addColor("colorCrawlRock", "buried crawlspace")
  addColor("colorCrawl",     "open crawlspace")
  addColor("colorTinted",    "tinted rock")
  addColor("colorSuper",     "super tinted rock")
  addColor("colorMarked",    "X-marked skull")

  local function addKeybind(key, label, info)
    ModConfigMenu.AddSetting(CATEGORY, "Markers", {
      Type           = ModConfigMenu.OptionType.KEYBIND_KEYBOARD,
      CurrentSetting = function() return cfg[key] end,
      Display        = function()
        local name = InputHelper and InputHelper.KeyboardToString[cfg[key]]
        return label .. ": " .. (name or tostring(cfg[key]))
      end,
      OnChange       = function(value) cfg[key] = value or -1; saveConfig() end,
      Info           = info,
      PopupGfx       = ModConfigMenu.PopupGfx and ModConfigMenu.PopupGfx.WIDE_SMALL or nil,
    })
  end

  addKeybind("toggleKey", "Toggle mod key",     { "Turns the whole mod on and off in game" })
  addKeybind("noticeKey", "Toggle notices key", { "Shows/hides the bottom-left notices" })

  -- Mod Config Menu has no button widget. A boolean whose CurrentSetting always
  -- reports false acts as one: toggling it fires OnChange and the row snaps
  -- straight back to "Off", so it reads as a press rather than a state.
  local function addResetButton(subcategory, label, action, info)
    ModConfigMenu.AddSetting(CATEGORY, subcategory, {
      Type           = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function() return false end,
      Display        = function() return label end,
      OnChange       = function(value) if value then action() end end,
      Info           = info,
    })
  end

  addResetButton("Colours", ">> Reset colours to default <<", resetColors,
    { "Puts all five marker colours back", "to how they shipped" })

  addResetButton("Reset", ">> Reset colours to default <<", resetColors,
    { "Marker colours only. Everything else", "is left alone" })
  addResetButton("Reset", ">> Reset EVERYTHING to default <<", resetAll,
    { "Every setting on every page, including", "colours and both keybinds" })
end

-- Mod Config Menu may load after this mod, so keep looking for it for a few
-- seconds. Give up after that rather than probing every frame for the whole
-- session when it simply is not installed.
local MCM_RETRY_FRAMES = 600
local mcmAttemptsLeft  = MCM_RETRY_FRAMES

tryModConfigMenu = function()
  if mcmDone or mcmAttemptsLeft <= 0 then return end
  mcmAttemptsLeft = mcmAttemptsLeft - 1
  if not ModConfigMenu then return end
  -- Mark done first: a partially built category is better than retrying a
  -- failing registration on every frame.
  mcmDone = true
  pcall(setupModConfigMenu)
end
