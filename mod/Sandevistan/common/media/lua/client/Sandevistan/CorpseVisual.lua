-- Sandevistan / CorpseVisual (cliente, 137): la placa 3D de la espalda en los cadáveres que llevan el implante, puesta por cada cliente.
-- El servidor marca el cadáver (ModData Sandevistan = { variant, ... }, World.claimBody + transmitModData), pero un visual de cuerpo agregado en el
-- servidor no viaja a los clientes (Config.ExSubjects.Visual3D): en multijugador un NPC de Project A-Life al que el servidor le saca la prenda
-- (ALife.strip) se veía sin la espalda apenas moría. Acá cada cliente mira los cadáveres de alrededor cada tanto y, con la marca, les pone la placa
-- (si no la tienen ya, como el de un ex-sujeto en un jugador); al extraerse la saca. La primera vez que te acercás a uno, un aviso dice que se
-- puede extraer. Solo toca el dibujo local del cadáver: nada viaja por la red.
require "Sandevistan/Core"
require "Sandevistan/Effects"

local CFG = SandevistanConfig
local S = Sandevistan
local E = SandevistanEffects

SandevistanCorpseVisual = { applied = 0, removed = 0, hints = 0, errors = 0, nextMs = 0 }
local CV = SandevistanCorpseVisual

local seen = setmetatable({}, { __mode = "k" })     -- cadáver -> estado aplicado ("lab", "military", "none")
local hinted = setmetatable({}, { __mode = "k" })

local function settings()
  local V = CFG.ExSubjects and CFG.ExSubjects.Visual3D or {}
  return V, V.CorpseScan or {}
end

-- Todos los tipos de placa que puede llevar un cadáver (con o sin LEDs).
local function spineTypes(variant)
  local base = "Sandevistan.SandevistanSpine" .. (variant == "military" and "Military" or "Lab")
  return { base, base .. "On" }
end

-- Variante cuya placa corresponde dibujar, o nil (sin implante o ya extraído).
function CV.wanted(body)
  local info = nil
  pcall(function() info = body:getModData().Sandevistan end)
  if type(info) ~= "table" or info.extracted then return nil end
  if info.variant ~= "lab" and info.variant ~= "military" then return nil end
  return info.variant
end

local function hasAny(visual, variant)
  for _, t in ipairs(spineTypes(variant)) do
    if visual:hasBodyVisualFromItemType(t) then return true end
  end
  return false
end

-- Deja el cadáver como corresponde. Devuelve "added", "removed" o nil.
function CV.sync(body)
  local want = CV.wanted(body)
  local state = want or "none"
  if seen[body] == state then return nil end
  local V = settings()
  local result = nil
  local ok, err = pcall(function()
    local visual = body:getHumanVisual()
    if not visual then return end
    if want then
      if not hasAny(visual, want) then
        visual:addBodyVisualFromItemType(spineTypes(want)[V.Lit and 2 or 1])
        result = "added"
      end
    elseif seen[body] == "lab" or seen[body] == "military" then
      for _, variant in ipairs({ "lab", "military" }) do
        for _, t in ipairs(spineTypes(variant)) do
          if visual:hasBodyVisualFromItemType(t) then visual:removeBodyVisualFromItemType(t); result = "removed" end
        end
      end
    end
    if result then body:invalidateCorpse() end
  end)
  if not ok then
    CV.errors = CV.errors + 1
    S.warnOnce("corpseVisual", "placa 3D del cadaver: " .. tostring(err))
    return nil
  end
  seen[body] = state
  if result == "added" then CV.applied = CV.applied + 1 elseif result == "removed" then CV.removed = CV.removed + 1 end
  return result
end

function CV.scan(player)
  local V, C = settings()
  if V.Enabled == false or C.Enabled == false then return end
  local cell = getCell()
  if not cell then return end
  local r = C.Radius or 12
  local hint = C.HintDist or 2.5
  local hint2 = hint * hint
  local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ())
  local cx, cy = math.floor(px), math.floor(py)
  for dx = -r, r do
    for dy = -r, r do
      local sq = cell:getGridSquare(cx + dx, cy + dy, pz)
      local bodies = sq and sq:getDeadBodys()
      for i = 0, (bodies and bodies:size() or 0) - 1 do
        local body = bodies:get(i)
        CV.sync(body)
        if C.Hint ~= false and not hinted[body] and CV.wanted(body) then
          local ex, ey = body:getX() - px, body:getY() - py
          if ex * ex + ey * ey <= hint2 then
            hinted[body] = true
            CV.hints = CV.hints + 1
            E.halo(player, getText("IGUI_Sandevistan_CorpseImplantHint"), 80, 220, 255)
          end
        end
      end
    end
  end
end

function CV.tick()
  local now = S.realMs()
  if now < CV.nextMs then return end
  local _, C = settings()
  CV.nextMs = now + (C.EveryMs or 2000)
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p and not p:isDead() then CV.scan(p) end
  end
end

function CV.statusLine()
  return string.format("placa 3D en cadaveres (cliente): puestas = %d, sacadas = %d, avisos = %d, errores = %d", CV.applied, CV.removed, CV.hints, CV.errors)
end

Events.OnTick.Add(S.safe("CorpseVisual.tick", CV.tick))

return CV
