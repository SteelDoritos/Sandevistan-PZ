-- Sandevistan / Doppelganger (cliente, 0.7 (148)): el clon de la cyberpsicosis (26 §7). Con la cyberpsicosis en etapa 3, de a ratos aparece una copia
-- del jugador (su piel, su pelo y su ropa, sin arma) a pocas casillas, casi siempre a la espalda. O se queda quieta mirandote, o copia tus pasos con
-- un segundo de atraso. Si la miras de frente un momento, o te le acercas, se deshace con el glitch de los zombis falsos; si no, se va sola. No hace
-- ruido (salvo pasos muy suaves en modo espejo, 171), no choca, no ataca y nadie mas la ve. No se guarda.
-- El dibujo lo pone el mod opcional SandevistanPsychosis (un titere con el AnimSet "player-avatar": idle, walk, run, ext). Usa el mismo backend que los
-- zombis falsos (FZ.backend, que llena SandevistanPsychosis/Bridge.lua); sin ese jar no hay clon.
require "Sandevistan/Core"
require "Sandevistan/Effects"
require "Sandevistan/Psychosis"
require "Sandevistan/FakeZombies"

local CFG = SandevistanConfig
local S = Sandevistan
local E = SandevistanEffects
local P = SandevistanPsychosis
local FZ = SandevistanFakeZombies

-- Los ids de los titeres son de un solo mapa en el jar: los del clon van aparte de los de los zombis falsos.
SandevistanDoppelganger = { list = {}, nextId = 1000000, trail = {},
                            spawned = 0, looked = 0, touched = 0, expired = 0, blocked = 0, noRoom = 0, errors = 0 }
local DG = SandevistanDoppelganger

local function C() return CFG.Psychosis.Doppelganger end
local function lerp(a, b, t) return a + (b - a) * t end
local function rnd(a, b) return lerp(a, b, ZombRandFloat(0, 1)) end
local function backend() return FZ.backend end

function DG.ready()
  local b = backend()
  if not (b and b.canClone) then return false end
  return S.cached("DG.ready", 1000, function()          -- (194) una vez por segundo, no en cada tick
    local ok, r = pcall(function() return b.ready() and b.canClone() end)
    return ok and r == true
  end, b)
end

-- Activo para este jugador: opcion encendida, el jar con clon, cyberpsicosis activa en etapa MinStage o mas, despierto y a pie.
function DG.active(player, d)
  local c = C()
  if not (c and c.Enabled) or CFG.NeuralLoad.Hallucinations == false or not DG.ready() then return false end
  if not d.cyberpsychosisActive or P.stage(d) < (c.MinStage or 3) then return false end
  if player:isAsleep() then return false end
  local inCar = false
  pcall(function() inCar = player:getVehicle() ~= nil end)
  return not inCar
end

local function forward(player)
  local fx, fy = 0, 1
  pcall(function() fx, fy = player:getForwardDirectionX(), player:getForwardDirectionY() end)
  local len = math.sqrt(fx * fx + fy * fy)
  if len < 1e-4 then return 0, 1 end
  return fx / len, fy / len
end

-- Rastro del jugador para el modo espejo: una muestra por tick (posicion, rumbo y si camina o corre), los ultimos 3 s.
function DG.record(player, now)
  local idx = player:getPlayerNum()
  local tr = DG.trail[idx] or {}
  DG.trail[idx] = tr
  local fx, fy = forward(player)
  local running = false
  pcall(function() running = player:isRunning() or player:isSprinting() end)
  tr[#tr + 1] = { t = now, x = player:getX(), y = player:getY(), fx = fx, fy = fy, running = running }
  while #tr > 2 and now - tr[1].t > 3000 do table.remove(tr, 1) end
end

-- La muestra del rastro de hace delay ms (la mas nueva que no es posterior); nil si todavia no hay tanto rastro.
function DG.sampleAt(idx, at)
  local tr = DG.trail[idx]
  if not tr or #tr == 0 or tr[1].t > at then return nil end
  local best = tr[1]
  for i = 2, #tr do
    if tr[i].t <= at then best = tr[i] else break end
  end
  return best
end

-- Nace un clon. mode = "watch" (quieto, mirandote), "wave" (quieto, saludandote) o "mirror" (copia tus pasos con atraso); nil lo tira con
-- MirrorChance y, si queda quieto, saluda con WaveChance.
-- forced (Debug): sigue aunque la cyberpsicosis no este en la etapa del clon (solo pide el jar).
function DG.spawn(player, mode, forced)
  local c = C()
  local b = backend()
  if not (b and b.spawnClone) then return nil end
  local idx = player:getPlayerNum()
  local pz = math.floor(player:getZ())
  local now = S.realMs()
  mode = mode or (ZombRandFloat(0, 1) < (c.MirrorChance or 0.5) and "mirror" or "watch")
  local wave = mode == "wave" or (mode == "watch" and ZombRandFloat(0, 1) < (c.WaveChance or 0))
  if mode == "wave" then mode = "watch" end
  for _ = 1, 4 do
    local x, y = P.pickPos(player, c.Dist[1], c.Dist[2], true)
    if x and FZ.canStep(x, y, x, y, pz) then
      local id = DG.nextId
      DG.nextId = DG.nextId + 1
      local ok, born = pcall(b.spawnClone, id, player, x, y, pz, idx)
      if not ok or born ~= true then
        if not ok then DG.errors = DG.errors + 1; S.warnOnce("cloneSpawn", "clon: " .. tostring(born)) end
        return nil
      end
      local g = { id = id, idx = idx, x = x, y = y, z = pz, bornMs = now, mode = mode, lookMs = 0, forced = forced == true, wave = wave,
                  lifeMs = rnd(c.LifeSeconds[1], c.LifeSeconds[2]) * 1000 }
      if mode == "mirror" then
        -- el clon repite el desplazamiento del jugador desde la muestra de hace MirrorDelayMs, a partir de donde nacio
        local s0 = DG.sampleAt(idx, now - (c.MirrorDelayMs or 1000)) or { x = player:getX(), y = player:getY() }
        g.ax, g.ay, g.sx, g.sy = x, y, s0.x, s0.y
      end
      pcall(b.look, id, c.Alpha or 1, c.Tint[1], c.Tint[2], c.Tint[3])
      if wave and b.state then pcall(b.state, id, "sdvwave") end          -- (150) el saludo vanilla, en bucle (AnimSets/player-avatar/sdvwave)
      DG.face(g, player)
      DG.list[#DG.list + 1] = g
      DG.spawned = DG.spawned + 1
      S.log(string.format("clon: nace %d a %.2f casillas (%s)", id,
        math.sqrt((x - player:getX()) ^ 2 + (y - player:getY()) ^ 2), mode == "mirror" and "espejo" or (wave and "saludando" or "mirando")))
      return g
    end
  end
  DG.noRoom = DG.noRoom + 1
  return nil
end

-- (179) C09: despedida de la remision. Un clon lejos (10 a 14 casillas), te saluda y se deshace despacio, sin glitch. Si no hay jar,
-- no pasa nada: el monitor ya aviso "HUMANIDAD RESTAURADA".
function DG.spawnRemission(player)
  local b = backend()
  if not (b and b.spawnClone) or not DG.ready() then return nil end
  local pz, now, idx = math.floor(player:getZ()), S.realMs(), player:getPlayerNum()
  for _ = 1, 6 do
    local x, y = P.pickPos(player, 10, 14, false)
    if x and FZ.canStep(x, y, x, y, pz) then
      local id = DG.nextId
      DG.nextId = DG.nextId + 1
      local ok, born = pcall(b.spawnClone, id, player, x, y, pz, idx)
      if not ok or born ~= true then
        if not ok then DG.errors = DG.errors + 1; S.warnOnce("cloneRemission", "clon: " .. tostring(born)) end
        return nil
      end
      local c = C()
      local g = { id = id, idx = idx, x = x, y = y, z = pz, bornMs = now, mode = "watch", lookMs = 0, wave = true,
                  lifeMs = 6000, noGlitch = true, forced = true }
      pcall(b.look, id, c.Alpha or 1, c.Tint[1], c.Tint[2], c.Tint[3])
      if b.state then pcall(b.state, id, "sdvwave") end
      DG.face(g, player)
      DG.list[#DG.list + 1] = g
      DG.spawned = DG.spawned + 1
      S.log(string.format("clon: despedida de la remision a %.1f casillas", math.sqrt((x - player:getX()) ^ 2 + (y - player:getY()) ^ 2)))
      return g
    end
  end
  DG.noRoom = DG.noRoom + 1
  return nil
end

-- Quieto, de frente al jugador.
function DG.face(g, player)
  local dx, dy = player:getX() - g.x, player:getY() - g.y
  local len = math.sqrt(dx * dx + dy * dy)
  if len > 1e-3 then g.fx, g.fy = dx / len, dy / len end
  pcall(backend().move, g.id, g.x, g.y, g.z, 0, 0, g.fx or 0, g.fy or 1)
end

-- Empieza a deshacerse (por que: "look", "touch", "expired", "blocked"). Al mirarlo o tocarlo, el susto chico.
function DG.dissolve(g, why, player)
  if g.fadeAt then return end
  g.fadeAt = S.realMs()
  g.why = why
  local c = C()
  pcall(backend().state, g.id, "idle")
  if why == "look" or why == "touch" then
    if why == "look" then DG.looked = DG.looked + 1 else DG.touched = DG.touched + 1 end
    S.markSeen(player, "clone")                                            -- (179) lo descubriste

    E.addStat(player, "STRESS", c.Stress or 0)
    E.addStat(player, "PANIC", c.Panic or 0)
    P.textGlitch(c.TextGlitch or 0.3, 500)
    pcall(P.play, player, "glitchVanish", g.x, g.y, g.z, 0.7)
  elseif why == "blocked" then
    DG.blocked = DG.blocked + 1
  else
    DG.expired = DG.expired + 1
  end
end

-- Lo esta mirando: de frente (LookDot) y la casilla a la vista.
function DG.seen(g, player)
  local c = C()
  local dx, dy = g.x - player:getX(), g.y - player:getY()
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 1e-3 then return true end
  local fx, fy = forward(player)
  if (dx * fx + dy * fy) / dist < (c.LookDot or 0.85) then return false end
  local cell = getCell()
  local sq = cell and cell:getGridSquare(math.floor(g.x), math.floor(g.y), g.z)
  local ok, can = pcall(function() return sq and sq:isCanSee(player:getPlayerNum()) end)
  return ok and can == true
end

-- Un paso del clon. Devuelve false cuando hay que sacarlo.
function DG.update(g, player, dt, now)
  local c = C()
  local b = backend()
  if g.fadeAt then
    local t = (now - g.fadeAt) / math.max(1, c.FadeMs or 700)
    if t >= 1 then return false end
    local calm = S.lessFlashes()                                         -- (170) C01: fundido liso, sin glitch
    local flick = (g.noGlitch or calm or math.floor(now / 45) % 2 == 0) and 1 or 0.35
    pcall(b.look, g.id, (c.Alpha or 1) * (1 - t) * flick, c.Tint[1], c.Tint[2], c.Tint[3])
    if not g.noGlitch and b.glitch then pcall(b.glitch, g.id, calm and 0 or (0.8 * (1 - t) + 0.2)) end   -- (179) la despedida de la remision se va sin glitch
    return true
  end
  if now - g.bornMs >= g.lifeMs then DG.dissolve(g, "expired", player); return true end
  local px, py = player:getX(), player:getY()
  if math.sqrt((g.x - px) ^ 2 + (g.y - py) ^ 2) < (c.TouchDist or 1.3) then DG.dissolve(g, "touch", player); return true end
  if DG.seen(g, player) then
    g.lookMs = g.lookMs + dt * 1000
    if g.lookMs >= (c.LookMs or 500) then DG.dissolve(g, "look", player); return true end
  else
    g.lookMs = math.max(0, g.lookMs - dt * 500)
  end
  if g.mode == "mirror" then
    local s = DG.sampleAt(g.idx, now - (c.MirrorDelayMs or 1000))
    if s then
      local nx, ny = g.ax + (s.x - g.sx), g.ay + (s.y - g.sy)
      if not FZ.canStep(g.x, g.y, nx, ny, g.z) then DG.dissolve(g, "blocked", player); return true end
      local mx, my = nx - g.x, ny - g.y
      local moved = math.sqrt(mx * mx + my * my)
      local vx, vy = 0, 0
      if dt > 0 then vx, vy = mx / dt, my / dt end
      g.x, g.y, g.fx, g.fy = nx, ny, s.fx, s.fy
      local state = moved / math.max(dt, 1e-3) > 0.2 and (s.running and "run" or "walk") or "idle"
      pcall(b.state, g.id, state)
      DG.mirrorStep(g, player, moved, s.running)
      pcall(b.move, g.id, g.x, g.y, g.z, vx, vy, g.fx, g.fy)
      return true
    end
  end
  DG.face(g, player)
  return true
end

-- (171) C02 (29 §4.2): en modo espejo el clon pisa muy suave, con el mismo segundo de atraso que sus pasos (copia tu caminar, tambien el sonido).
-- Pasos de persona en su casilla, con el piso y la velocidad. Respeta las alucinaciones de audio (PsychosisAudio) como los zombis falsos.
function DG.mirrorStep(g, player, moved, running)
  local M = C().MirrorSteps
  if not (M and M.Enabled) or moved <= 0 or not (P.audioOn and P.audioOn()) then return end
  g.stepAcc = (g.stepAcc or 0) + moved
  if g.stepAcc < (g.stepNext or 0.75) then return end
  g.stepAcc = 0
  local SE = (running and M.RunStepEvery) or M.StepEvery or { 0.7, 0.85 }
  g.stepNext = rnd(SE[1], SE[2])
  local ok, id = pcall(P.play, player, "footstepHuman", g.x, g.y, g.z, M.Volume or 0.18)
  if ok and P.setParams then
    P.setParams(id, { FootstepMaterial = P.footstepMaterial(g.x, g.y, g.z), CharacterMovementSpeed = running and 4 or 3 })
  end
  DG.steps = (DG.steps or 0) + 1
end

function DG.clear(idx, keepForced)
  local b = backend()
  for i = #DG.list, 1, -1 do
    local g = DG.list[i]
    if (idx == nil or g.idx == idx) and not (keepForced and g.forced) then
      if b then pcall(b.remove, g.id) end
      table.remove(DG.list, i)
    end
  end
end

function DG.countFor(idx)
  local n = 0
  for _, g in ipairs(DG.list) do if g.idx == idx then n = n + 1 end end
  return n
end

-- Desde Psychosis.tick (dt en segundos de juego; 0 en pausa).
function DG.tick(player, d, st, now, dt)
  local idx = player:getPlayerNum()
  local active = DG.active(player, d)
  if not active then
    DG.clear(idx, DG.ready())                  -- los del Debug siguen mientras este el jar
    if DG.countFor(idx) == 0 then DG.trail[idx] = nil; return end
  end
  if dt <= 0 then return end
  DG.record(player, now)
  for i = #DG.list, 1, -1 do
    local g = DG.list[i]
    if g.idx == idx then
      local ok, keep = pcall(DG.update, g, player, dt, now)
      if not ok then DG.errors = DG.errors + 1; S.warnOnce("cloneUpdate", "clon: " .. tostring(keep)); keep = false end
      if not keep then
        pcall(backend().remove, g.id)
        table.remove(DG.list, i)
      end
    end
  end
  if not active then return end
  local c = C()
  if not st.nextCloneMs then st.nextCloneMs = now + c.FirstDelaySeconds * 1000 end
  if now < st.nextCloneMs or DG.countFor(idx) >= (c.Max or 1) then return end
  local every = lerp(c.EverySeconds[2], c.EverySeconds[1], P.intensity(d)) / math.max(0.2, P.freqMult(d, st, "Doppelganger"))
  st.nextCloneMs = now + every * 1000 * rnd(0.6, 1.4)
  DG.spawn(player)
end

function DG.statusLine()
  return string.format("clon: %d vivos | nacidos %d (sin lugar %d), mirados %d, tocados %d, frenados %d, vencidos %d, errores %d",
    #DG.list, DG.spawned, DG.noRoom, DG.looked, DG.touched, DG.blocked, DG.expired, DG.errors)
end

Events.OnPlayerDeath.Add(S.safe("Doppelganger.OnPlayerDeath", function(player) DG.clear(player:getPlayerNum()) end))

return DG
