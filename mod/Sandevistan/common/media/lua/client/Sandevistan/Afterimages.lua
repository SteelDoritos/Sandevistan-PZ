-- Sandevistan / Afterimages: estelas estilo Edgerunners mientras el implante está activo.
-- Siluetas blancas (textures/Sandevistan_Ghost_<gait>_<DIR>_<frame>.png, generadas con
-- tools/gen_ghosts.py) tintadas por variante. La pose depende de la marcha (idle / walk / run /
-- sprint y, agachado, crouch / sneak / sneakrun). Ancladas a posiciones pasadas del jugador en el mundo y proyectadas a pantalla.
-- Se dibujan desde el HUD (capa de UI), sin elementos que capturen el mouse.
require "Sandevistan/Core"
require "Sandevistan/Viewport"

local CFG = SandevistanConfig
local S = Sandevistan

SandevistanAfterimages = {}
local A = SandevistanAfterimages

A.images = {}        -- { x, y, z, dir, frame, bornMs, lifeMs, alpha, idx }
A.last = nil         -- última posición registrada
A.counter = 0
A.remote = {}
A.uid = 0            -- (131) id unico de cada estela, local o remota (lo usa el motor 3D)

-- (131) Motor de estelas con poses reales: lo pone el mod opcional SandevistanViewpoint. Sirve para los DOS modos de camara:
-- con la camara 3D de Viewpoint dibuja la pose dentro de esa camara, y en la isometrica normal dibuja con el mismo pipeline del
-- juego (136). Tabla con ready() -> bool, stamp(player, uid), show(uid, r, g, b, a), drop(uid), clear() y status() -> texto.
-- Sin ese mod, nil: quedan las siluetas 2D de siempre. La logica (cuando nace cada estela, cuanto dura, su color) no cambia.
A.backend = nil

-- El motor si esta listo para el modo de camara actual; si no, nil.
function A.engine()
  local b = A.backend
  if not b then return nil end
  local ok, ready = pcall(b.ready)
  if ok and ready then return b end
  return nil
end

-- (138h) Motor para las estelas del Sandevistan: en la camara 3D de Viewpoint y, con PoseIso, tambien en la isometrica (es el default
-- desde la 138h: se arreglaron los pedidos que se perdian y las estelas que el juego tiraba al reciclar la ranura del personaje; ver
-- 20-estelas-viewpoint.md §10.8). PoseIso = false deja las siluetas 2D en isometrico. Los ecos (Echoes.lua) usan A.engine() siempre.
function A.trailEngine()
  local b = A.engine()
  if not b then return nil end
  if CFG.Afterimage.PoseIso or SandevistanViewport.is3D() then return b end
  return nil
end

local function forget(img)
  if img.vp and A.backend then pcall(A.backend.drop, img.uid) end
end

local GAIT_FRAMES = { idle = 1, walk = 2, run = 2, sprint = 2, crouch = 1, sneak = 2, sneakrun = 2 }

local DIRS = { N = true, NE = true, E = true, SE = true, S = true, SW = true, W = true, NW = true }
local texCache = {}

function A.texture(gait, dir, frame)
  dir = dir or "S"
  if frame >= (GAIT_FRAMES[gait] or 1) then frame = 0 end
  local key = gait .. "_" .. dir .. "_" .. frame
  local t = texCache[key]
  if t == nil then
    t = getTexture("media/textures/Sandevistan_Ghost_" .. key .. ".png") or false
    if not t then S.warnOnce("ghostTex", "no se encontró la textura de estela " .. key) end
    texCache[key] = t
  end
  return t or nil
end

function A.enabled()
  if SandevistanViewport.is3D() and not A.engine() then return false end   -- (95) camara 3D de Project Viewport: la proyeccion isometrica no vale (131: salvo con el motor; 136: el motor tambien dibuja en isometrico)
  return not SandevistanInput or SandevistanInput.getOption("afterimages", true)
end

local function playerDir(player)
  local dir = "S"
  pcall(function() dir = tostring(player:getDir()) end)
  if not DIRS[dir] then dir = "S" end
  return dir
end

-- Marcha del jugador: "idle" | "walk" | "run" | "sprint" y, agachado, "sneak" | "sneakrun" (quieto agachado: "crouch", lo decide
-- A.update). Primero las banderas del motor; si ninguna existe, se estima por la velocidad medida (tiles/s).
function A.gait(player, speed, sneaking)
  local sprint, run, found = false, false, false
  local ok1, v1 = pcall(function() return player:isSprinting() end)
  if ok1 and v1 ~= nil then found = true; sprint = v1 and true or false end
  local ok2, v2 = pcall(function() return player:isRunning() end)
  if ok2 and v2 ~= nil then found = true; run = v2 and true or false end
  if found then
    if sneaking then return (sprint or run) and "sneakrun" or "sneak" end
    if sprint then return "sprint" end
    if run then return "run" end
    return "walk"
  end
  local fb = CFG.Afterimage.GaitSpeedFallback
  if sneaking then return speed >= (fb.sneakRun or 1.6) and "sneakrun" or "sneak" end
  if speed >= fb.sprint then return "sprint" elseif speed >= fb.run then return "run" end
  return "walk"
end

-- HSV (h en 0..1) -> RGB
local function hsv(h)
  local i = math.floor(h * 6) % 6
  local f = h * 6 - math.floor(h * 6)
  local q, t = 1 - f, f
  if i == 0 then return 1, t, 0 elseif i == 1 then return q, 1, 0 elseif i == 2 then return 0, 1, t
  elseif i == 3 then return 0, q, 1 elseif i == 4 then return t, 0, 1 end
  return 1, 0, q
end

-- Color de una estela según variante, modo arcoíris, Overdrive y cyberpsicosis.
function A.color(d, img, nowMs)
  local C = CFG.Afterimage
  local rainbow = img.overdrive or (SandevistanInput and SandevistanInput.getOption("afterimagesRainbow", false))
  if d.cyberpsychosisActive and not img.overdrive then
    local pal = C.Palettes.cyberpsychosis
    local c = pal[(img.idx % #pal) + 1]
    return c[1], c[2], c[3]
  end
  if rainbow then
    return hsv(((nowMs - img.bornMs) / C.RainbowPeriodMs + img.idx * C.RainbowStep) % 1)
  end
  local pal = C.Palettes[d.variant] or C.Palettes.lab
  local c = pal[(img.idx % #pal) + 1]
  return c[1], c[2], c[3]
end

local function purge(track, now)
  for i = #track.images, 1, -1 do
    local img = track.images[i]
    if now - img.bornMs > img.lifeMs then table.remove(track.images, i); forget(img) end
  end
end

local function forgetAll(track)
  for _, img in ipairs(track.images) do forget(img) end
end

-- Registra una estela nueva en `track` (A para el jugador local; una pista por jugador remoto en A.remote) si `player` se movio o giro desde la ultima.
local function record(track, player, now, od, mult)
  local C = CFG.Afterimage
  local x, y, z = player:getX(), player:getY(), player:getZ()
  local dir = playerDir(player)
  local last = track.last
  -- marcha según la velocidad desde la última estela (para el fallback) y las banderas del motor
  local moved, speed = 0, 0
  if last then
    local mx, my = x - last.x, y - last.y
    moved = math.sqrt(mx * mx + my * my)
    speed = moved / math.max(0.001, (now - last.ms) / 1000)
  end
  local sneak = false
  pcall(function() sneak = player:isSneaking() == true end)
  local minMove = C.MinMoveTiles * (sneak and 0.3 or 1)       -- agachado se avanza mucho más despacio
  local gait = sneak and "crouch" or "idle"
  if last and moved >= minMove then gait = A.gait(player, speed, sneak) end
  local G = C.Gaits[gait]
  mult = mult or 1                                             -- (123) S.afterimageMult: adaptacion y maestria (los remotos, 1)
  local interval = od and C.Overdrive.IntervalMs or (G and G.IntervalMs) or C.IntervalMs
  if last and now - last.ms < interval then return end
  if last and moved < minMove and dir == last.dir then return end
  track.counter = track.counter + 1
  A.uid = A.uid + 1
  local img = {
    x = x, y = y, z = z, dir = dir, gait = gait,
    frame = (gait ~= "idle") and (track.counter % 2) or 0,
    bornMs = now, lifeMs = (od and C.Overdrive.LifetimeMs or (G and G.LifetimeMs) or C.LifetimeMs) * mult,
    alpha = od and C.Overdrive.Alpha or C.Alpha, idx = track.counter, overdrive = od,
    hide = G and G.HideTiles,          -- agachado se avanza despacio: la estela puede aparecer más cerca del personaje
    uid = A.uid,
  }
  table.insert(track.images, img)
  local b3 = A.trailEngine()                                  -- (138h) con el motor, el guarda la pose de este momento (isometrico y, con Viewpoint, tambien en 3D)
  -- (138h) se le pasa la posicion donde nace: si el jar recien la captura en el cuadro siguiente, la estela igual queda ahi
  if b3 and pcall(b3.stamp, player, img.uid, x, y, z) then img.vp = true end
  while #track.images > math.floor(C.Max * mult) do forget(table.remove(track.images, 1)) end
  track.last = { x = x, y = y, dir = dir, ms = now }
end

function A.update(player, s, d)
  local now = S.realMs()
  purge(A, now)
  if not s.active or s.work or not A.enabled() then A.last = nil; return end          -- (86) sin estelas en el modo trabajo
  record(A, player, now, s.overdrive, S.afterimageMult(S.data(player)))
end

-- v0.1.30 (31): estelas de OTROS jugadores (multijugador). Un tercero no ve la estela de alguien con el Sandevistan: solo se ve cuando AMBOS lo tienen activo
-- (quien lo usa percibe a otro que esta en el mismo "tiempo"). Cada cliente las arma sola con la posicion de los remotos que figuran activos
-- (SandevistanNet.activeRemotes) mientras el jugador local este activo: no viaja nada por la red. Si el local se apaga, todas desaparecen.
A.remote = {}        -- [onlineID] = { images, last, counter, variant }
function A.updateRemotes(localPlayer, s)
  local now = S.realMs()
  local N = rawget(_G, "SandevistanNet")
  if not (s and s.active and A.enabled() and N and N.activeRemotes) then
    for _, tr in pairs(A.remote) do forgetAll(tr) end
    A.remote = {}
    return
  end
  local seen = {}
  for _, r in ipairs(N.activeRemotes()) do
    local id = r.id
    if id ~= nil and r.player and r.player ~= localPlayer then
      seen[id] = true
      local tr = A.remote[id]
      if not tr then tr = { images = {}, last = nil, counter = 0 }; A.remote[id] = tr end
      local look = N.remoteLook and N.remoteLook(id)
      tr.variant = look and look.variant or tr.variant or "lab"
      purge(tr, now)
      record(tr, r.player, now, false, 1)
    end
  end
  for id, tr in pairs(A.remote) do                       -- los que dejaron de estar activos: la estela que ya tenian se desvanece sola; despues se descartan
    if not seen[id] then
      tr.last = nil
      purge(tr, now)
      if #tr.images == 0 then A.remote[id] = nil end
    end
  end
end

local function drawOne(ui, img, a, r, g, b, zoom, ax, ay)
  local tex = A.texture(img.gait or "idle", img.dir, img.frame)
  if not tex then return end
  local C = CFG.Afterimage
  local w, h = C.Width / zoom, C.Height / zoom
  local sx = isoToScreenX(0, img.x, img.y, img.z) - ax
  local sy = isoToScreenY(0, img.x, img.y, img.z) - ay + C.OffsetY / zoom
  ui:drawTextureScaled(tex, sx - w / 2, sy - h, w, h, a, r, g, b)
end

-- Dibuja las estelas del jugador 0 (coordenadas relativas al elemento de UI).
function A.draw(ui, player, d)
  local hasRemote = false
  for _ in pairs(A.remote) do hasRemote = true; break end
  if #A.images == 0 and not hasRemote then return end
  local now = S.realMs()
  local ax, ay = ui:getAbsoluteX(), ui:getAbsoluteY()
  local zoom = 1
  pcall(function() zoom = getCore():getZoom(0) end)
  local px, py = player:getX(), player:getY()
  local hide = CFG.Afterimage.HideNearPlayerTiles
  local b3 = A.trailEngine()                               -- (138g: solo en 3D) (131) con el motor las dibuja el (poses guardadas), no la proyeccion isometrica; (136) tambien en isometrico
  local ok = pcall(function()
    for _, img in ipairs(A.images) do
      local dx, dy = img.x - px, img.y - py
      local h = img.hide or hide
      if dx * dx + dy * dy >= h * h then
        local f = 1 - (now - img.bornMs) / img.lifeMs
        if f > 0 then
          local r, g, b = A.color(d, img, now)
          if b3 then
            if img.vp then b3.show(img.uid, r, g, b, img.alpha * f * math.sqrt(f)) end
          else
            drawOne(ui, img, img.alpha * f * math.sqrt(f), r, g, b, zoom, ax, ay)
          end
        end
      end
    end
    for _, tr in pairs(A.remote) do                     -- estelas ajenas (solo hay si ambos estan activos), con el color de la variante del otro
      local rd = { variant = tr.variant, cyberpsychosisActive = false }
      for _, img in ipairs(tr.images) do
        local f = 1 - (now - img.bornMs) / img.lifeMs
        if f > 0 then
          local r, g, b = A.color(rd, img, now)
          if b3 then
            if img.vp then b3.show(img.uid, r, g, b, img.alpha * f * math.sqrt(f)) end
          else
            drawOne(ui, img, img.alpha * f * math.sqrt(f), r, g, b, zoom, ax, ay)
          end
        end
      end
    end
  end)
  if not ok then S.warnOnce("afterimageDraw", "no se pudieron dibujar las estelas") end
end

function A.clear()
  A.images = {}; A.last = nil; A.remote = {}
  if A.backend then pcall(A.backend.clear) end
end

return A
