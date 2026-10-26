-- Sandevistan / Net (cliente): replicación del estado "activo" en multiplayer.
--   Envío: al activar/desactivar y un latido cada HeartbeatMs mientras dure.
--   Recepción: guarda a los jugadores remotos activos con vencimiento; Slowdown.tickB los
--   suma como fuentes de ralentización. En SP no hace nada (isClient() es false).
require "Sandevistan/Core"

local CFG = SandevistanConfig
local S = Sandevistan

SandevistanNet = SandevistanNet or {}
local N = SandevistanNet

local MODULE = "Sandevistan"

N.remote = {}     -- [onlineID] = { zs = velocidad zombi del tramo, untilMs = vencimiento }
N.lastSend = {}   -- [playerNum] = ms del último envío
N.look = {}       -- [onlineID] = { variant, proto, untilMs }: aspecto del implante de jugadores remotos
N.lastLook = {}   -- [playerNum] = { variant, ms }

-- v0.1.26: también en el jugador que hostea (isClient e isServer a la vez): antes su implante no se enviaba y los demás no lo veían.
function N.enabled() return isClient() end

-- Envía el estado del jugador local. tier = nil para avisar que se apagó.
function N.send(player, tier)
  if not N.enabled() then return end
  local on = tier ~= nil
  sendClientCommand(player, MODULE, "active", { on = on, zs = on and tier.zombieSpeed or nil })
  N.lastSend[player:getPlayerNum()] = S.realMs()
end

-- Latido: llamado cada tick desde Slowdown mientras haya jugadores locales activos.
function N.heartbeat(player, tier)
  if not N.enabled() then return end
  local last = N.lastSend[player:getPlayerNum()] or 0
  if S.realMs() - last >= CFG.Net.HeartbeatMs then N.send(player, tier) end
end

function N.clearLocal(player) N.lastSend[player:getPlayerNum()] = nil end

-- Remotos vigentes: devuelve lista { player, zs }. Purga vencidos y desconectados.
function N.activeRemotes()
  local out = {}
  if not N.enabled() then return out end
  local now = S.realMs()
  for id, info in pairs(N.remote) do
    local p = nil
    if now < info.untilMs then
      pcall(function() p = getPlayerByOnlineID(id) end)
    end
    if p and not p:isDead() then
      out[#out + 1] = { player = p, zs = info.zs, id = id }
    else
      N.remote[id] = nil
    end
  end
  return out
end

local function isLocalId(id)
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p and p:getOnlineID() == id then return true end
  end
  return false
end

-- Aspecto del implante (variante) para que los demás lo vean en la espalda. Se manda al cambiar
-- y cada LookHeartbeatMs.
function N.sendLook(player, variant, proto)
  if not N.enabled() then return end
  local idx = player:getPlayerNum()
  local last = N.lastLook[idx]
  local v = variant or "none"
  if last and last.variant == v and last.proto == proto and S.realMs() - last.ms < CFG.Net.LookHeartbeatMs then return end
  N.lastLook[idx] = { variant = v, proto = proto, ms = S.realMs() }
  sendClientCommand(player, MODULE, "look", { variant = v, proto = proto })
end

function N.remoteLook(id)
  local e = N.look[id]
  if e and e.untilMs > S.realMs() and e.variant ~= "none" then return e end
  return nil
end

-- Grito de cyberpsicosis: el texto sobre el jugador no viaja solo, se pide al servidor que lo
-- retransmita (y que genere el ruido). Solo se manda el número de la frase: cada cliente la traduce.
function N.scream(player, n, radius)
  if not N.enabled() then return end
  sendClientCommand(player, MODULE, "scream", { n = n, radius = radius })
end

-- (114) Stats en multijugador. En 42.21 el SERVIDOR manda en la resistencia, la fatiga, el panico, etc.: cada tanto le reenvia al cliente sus
-- valores (NetworkPlayerAI.syncStats) y pisa lo que el cliente cambio por su cuenta (sendPlayerStat solo anda con permisos de admin). Por eso el Black
-- Lace daba resistencia y "volvia a bajar". Todo lo que el mod cambia pasa por E.setStat, que lo anota aca; cada StatFlushMs se le manda al servidor:
-- la resistencia y la fatiga como DIFERENCIA (el servidor tambien la gasta al correr: se suma a lo suyo) y el resto como valor final.
local STAT_DELTA = { ENDURANCE = true, FATIGUE = true }
N.statQueue = {}   -- [playerNum] = { player, d = { [stat] = suma }, s = { [stat] = valor }, any }

function N.queueStat(player, name, before, after)
  if not N.enabled() or before == nil or after == nil then return end
  local idx = player:getPlayerNum()
  local q = N.statQueue[idx]
  if not q then q = { player = player, d = {}, s = {} }; N.statQueue[idx] = q end
  q.player = player
  if STAT_DELTA[name] then
    if after ~= before then q.d[name] = (q.d[name] or 0) + (after - before); q.any = true end
  else
    q.s[name] = after; q.any = true
  end
end

function N.flushStats(force)
  if not N.enabled() then return end
  local now = S.realMs()
  if not force and now - (N.lastStatFlush or 0) < (CFG.Net.StatFlushMs or 250) then return end
  N.lastStatFlush = now
  for idx, q in pairs(N.statQueue) do
    if q.any and q.player and not q.player:isDead() then
      local d, s, nd, ns = {}, {}, 0, 0
      for k, v in pairs(q.d) do if math.abs(v) > 1e-5 then d[k] = v; nd = nd + 1 end end
      for k, v in pairs(q.s) do s[k] = v; ns = ns + 1 end
      if nd + ns > 0 then sendClientCommand(q.player, MODULE, "stats", { d = nd > 0 and d or nil, s = ns > 0 and s or nil }) end
    end
    N.statQueue[idx] = nil
  end
end

-- (114) El estado del mod (implante, Heat, rechazo, Black Lace, bajon...) vive en el ModData del jugador. En multijugador quien lo GUARDA es el servidor
-- (ServerPlayerDB guarda su copia del jugador) y esa copia solo se entera con transmitModData (el juego lo hace, por ejemplo, al cambiar la barra de
-- acceso rapido: por eso el implante "a veces" sobrevivia al reinicio y el Black Lace no). Se manda cada SaveEveryMs y al cambiar algo importante.
function N.saveState(player)
  if not N.enabled() or not player then return end
  local okL, isLocal = pcall(player.isLocalPlayer, player)
  if okL and isLocal == false then return end
  pcall(function() player:transmitModData() end)
  N.lastSave = N.lastSave or {}
  N.lastSave[player:getPlayerNum()] = S.realMs()
end

-- (118) La duracion de las acciones temporizadas la calcula el servidor (y el cliente la toma de alla): se le avisa si el modo trabajo de Taller esta
-- encendido y cuanto acelera la recarga (server/ActionSpeed.lua aplica los mismos ganchos que FirmwareClient y Firearms). Solo al cambiar.
N.speedSent = {}
function N.speedState(player)
  local R, F = rawget(_G, "SandevistanRuntime"), rawget(_G, "SandevistanFirearms")
  local s = R and R.sessions and R.sessions[player:getPlayerNum()]
  local work = (s and s.active and s.work) and true or false
  local reload = 1
  if F and F.multiplier then pcall(function() reload = F.multiplier(player) end) end
  return work, math.floor((reload or 1) * 20 + 0.5) / 20             -- de a 0,05: no se manda por cada cambio del impulso
end

function N.syncSpeed(player)
  local work, reload = N.speedState(player)
  local idx = player:getPlayerNum()
  local last = N.speedSent[idx]
  if last and last.work == work and last.reload == reload then return false end
  N.speedSent[idx] = { work = work, reload = reload }
  sendClientCommand(player, MODULE, "speed", { work = work, reload = reload })
  return true
end

function N.tick()
  if not N.enabled() then return end
  N.flushStats(false)
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p and not p:isDead() then N.syncSpeed(p) end
  end
  local now, every = S.realMs(), CFG.Net.SaveEveryMs or 15000
  N.lastSave = N.lastSave or {}
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p and not p:isDead() and now - (N.lastSave[idx] or 0) >= every then
      if N.lastSave[idx] == nil then N.lastSave[idx] = now           -- la primera vez espera un ciclo: al conectar, el ModData recien llega del servidor
      else N.saveState(p) end
    end
  end
end

-- Manejadores de mensajes entre jugadores (cirugía remota): los registra RemoteSurgery.lua.
N.handlers = {}

local function onServerCommand(module, command, args)
  if module ~= MODULE then return end
  S.perfCount("red.recibido." .. tostring(command))     -- el reporte muestra qué llegó del servidor
  if type(args) ~= "table" then args = {} end
  if command == "remoteActive" then
    local id = args.id
    if id == nil or isLocalId(id) then return end       -- ignorar el eco de los jugadores locales
    if args.on and tonumber(args.zs) then
      N.remote[id] = { zs = tonumber(args.zs), untilMs = S.realMs() + CFG.Net.ExpireMs }
    else
      N.remote[id] = nil
    end
  elseif command == "remoteLook" then
    if args.id == nil or isLocalId(args.id) then return end
    N.look[args.id] = { variant = args.variant, proto = args.proto, untilMs = S.realMs() + CFG.Net.LookExpireMs }
  elseif command == "remoteScream" then
    if args.id == nil or isLocalId(args.id) then return end
    local p = nil
    pcall(function() p = getPlayerByOnlineID(args.id) end)
    local n = math.floor(tonumber(args.n) or 0)
    if p and n >= 1 and n <= 3 then
      pcall(function() p:Say(getText("IGUI_Sandevistan_Scream_" .. n)) end)
    end
  elseif N.handlers[command] then
    N.handlers[command](args)
  end
end

-- v0.1.30 (13): en multijugador el mundo (cadáveres con implante) es del servidor, pero el estado del implante vive en el cliente y
-- OnPlayerDeath solo dispara acá: se le avisa al servidor con qué implante murió el jugador para que su cadáver lo lleve.
function N.onPlayerDeath(player)
  if not N.enabled() or not player then return end
  local okL, isLocal = pcall(player.isLocalPlayer, player)
  if okL and isLocal == false then return end
  local d = player:getModData().Sandevistan
  if type(d) ~= "table" or (d.variant ~= "lab" and d.variant ~= "military") then return end
  sendClientCommand(player, MODULE, "implantDeath", { variant = d.variant, deg = d.degradation or 1, floor = d.degradationFloor or 1,
    x = player:getX(), y = player:getY(), z = player:getZ() })
end

if isClient() then
  Events.OnServerCommand.Add(S.safe("Net.OnServerCommand", onServerCommand))
  Events.OnPlayerDeath.Add(S.safe("Net.OnPlayerDeath", N.onPlayerDeath))
  Events.OnTick.Add(S.safe("Net.Tick", N.tick))
end

return N
