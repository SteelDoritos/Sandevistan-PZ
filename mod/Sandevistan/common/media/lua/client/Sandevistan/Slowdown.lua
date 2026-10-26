-- Sandevistan / Slowdown: interfaz única de dilatación.
-- El resto del mod solo llama activate/deactivate/tick y nunca sabe qué estrategia corre.
--   A: reloj global (solo SP, experimental: sin compensación del jugador todavía).
--   B: zonal. Zombis en el radio (Config.SpatialSlow.Radius, 16 por defecto) se ralentizan. v0.1.30 (62): tickLOD (nivel de detalle: se elige a
--      quien frenar cada SelectMs, los cercanos se amortiguan en cada tick y los lejanos cada FarMs); tickFull es el camino de antes (cada zombi,
--      cada tick) y queda como linea base de la prueba de rendimiento (Config.SlowLOD.Enabled = false).
require "Sandevistan/Core"
require "Sandevistan/Net"

local CFG = SandevistanConfig
local S = Sandevistan

SandevistanSlowdown = {}
local SD = SandevistanSlowdown

SD.active = {}                                   -- [playerIndex] = tier
SD.slowed = {}   -- zombie -> { orig = speedMod, lastX, lastY, factor }

local function isSP() return not isClient() and not isServer() end

function SD.strategy()
  if isSP() and not CFG.UseSpatialSlowInSP then return "A" end
  return "B"
end

SD.releasing = {}   -- (64) zombi -> info: soltandose de a poco tras apagar el implante (ver SD.beginRelease)
SD.boost = {}   -- [playerIndex] = { baseMove, lastX, lastY, animOn, animMult }
SD.holds = {}   -- [playerIndex] = { since } : la bandera de animacion rapida sigue puesta hasta que termine la vallada/trepada en curso

local function setFlag(p, on)
  return pcall(p.setVariable, p, CFG.FastAnimations.Flag, on)
end

function SD.activate(player, tier)
  SD.cancelRelease()
  local idx = player:getPlayerNum()
  SD.active[idx] = tier
  local b = { lastX = player:getX(), lastY = player:getY() }
  if SD.holds[idx] then b.animOn = true; SD.holds[idx] = nil end       -- la bandera sigue puesta (vallada en curso): se retoma sin soltarla
  pcall(function() b.baseMove = player:getMoveSpeed() end)
  if CFG.PlayerBoostMethod == "animVar" then
    -- en B42 GetVariable devuelve el valor directo (no un objeto); solo se lee si se usa animVar
    -- porque un pcall fallido igual vuelca el stack trace a la consola
    pcall(function() b.baseWalk = tonumber(tostring(player:GetVariable("WalkSpeed"))) end)
    pcall(function() b.baseRun = tonumber(tostring(player:GetVariable("RunSpeed"))) end)
  end
  SD.boost[idx] = b
  SandevistanNet.send(player, tier)
end

-- Cambia el tramo efectivo de un jugador activo (Impulso, Overdrive).
function SD.setTier(player, tier)
  local idx = player:getPlayerNum()
  if SD.active[idx] then SD.active[idx] = tier end
end

function SD.deactivate(player)
  local idx = player:getPlayerNum()
  SD.active[idx] = nil
  local b = SD.boost[idx]
  if b then SD.clearFastAnim(player, b) end
  if b and b.baseMove and CFG.PlayerBoostMethod == "moveSpeed" then
    S.try("restoreMoveSpeed", function() player:setMoveSpeed(b.baseMove) end)
  end
  if b and CFG.PlayerBoostMethod == "animVar" then
    pcall(function()
      if b.baseWalk then player:setVariable("WalkSpeed", b.baseWalk) end
      if b.baseRun then player:setVariable("RunSpeed", b.baseRun) end
    end)
  end
  SD.boost[idx] = nil
  SandevistanNet.send(player, nil)
  SandevistanNet.clearLocal(player)
  if S.isEmpty(SD.active) then
    if not SD.beginRelease(player) then SD.restoreAll() end
  end
end

---------------------------------------------------------------------------
-- Boost del jugador
--   moveSpeed: IsoPlayer:setMoveSpeed(base * (1 + boost)) cada tick.
--   nudge: amplifica el desplazamiento del tick solo si la casilla destino es
--          alcanzable (misma planta, sin pared/ventana/puerta entre medio, libre).
---------------------------------------------------------------------------
SD.nudgeStats = { applied = 0, blocked = 0, why = {} }
local function blocked(reason)
  SD.nudgeStats.blocked = SD.nudgeStats.blocked + 1
  SD.nudgeStats.why[reason] = (SD.nudgeStats.why[reason] or 0) + 1
end

local function nudge(p, b, boost)
  local x, y = p:getX(), p:getY()
  local dx, dy = x - b.lastX, y - b.lastY
  b.lastX, b.lastY = x, y
  local dist2 = dx * dx + dy * dy
  if dist2 < 1e-6 or dist2 > 0.25 then return end     -- quieto o teletransporte/vehículo
  -- En la escalera la Z es fraccionaria y la ajusta el motor según el avance sobre el escalón (doStairs). Empujar en X/Y ahí saltea
  -- esa subida: el jugador queda pasado del último escalón con la Z todavía por debajo del piso de arriba, sin escalera debajo, y el
  -- motor lo toma como caída (daño y hasta fractura; más al subir). En la escalera y al entrar o salir de ella no se empuja.
  local z = p:getZ()
  if z - math.floor(z) > 0.01 then blocked("escalera"); return end
  local nx, ny = x + dx * boost, y + dy * boost
  local cell = getCell()
  local cur = p:getCurrentSquare()
  local dst = cell:getGridSquare(math.floor(nx), math.floor(ny), math.floor(z))
  if not cur or not dst then blocked("sinCasilla"); return end
  if cur:HasStairs() or dst:HasStairs() or cur:HasStairsBelow() or dst:HasStairsBelow() then blocked("escalera"); return end
  if dst ~= cur then
    if cur:isBlockedTo(dst) then blocked("pared"); return end
    if dst:isSolid() then blocked("solido"); return end
    if dst:isSolidTrans() then blocked("mueble"); return end
    if not dst:isSolidFloor() then blocked("sinPiso"); return end
  end
  SD.nudgeStats.applied = SD.nudgeStats.applied + 1
  p:setX(nx); p:setY(ny)
  pcall(function() p:setLastX(nx); p:setLastY(ny) end)
  b.lastX, b.lastY = nx, ny
end

-- Animación rápida del jugador (AnimSets player/SandevistanFast_*.xml): caminar, correr y sprint acompañan el aumento de velocidad.
-- La bandera elige los nodos rápidos y una variable por escala base (el m_SpeedScale de esos nodos) trae base * (1 + boost); el tramo
-- cambia pocas veces, así que solo se escribe cuando cambia (a 0.01).
-- Cambiar de animacion a mitad de una vallada/trepada reinicia la animacion (el nodo se vuelve a elegir y arranca de cero; alternando se repetia
-- y el personaje avanzaba de a poco): la bandera no se toca mientras el estado de trepada siga en curso, ni al apagar ni al encender.
local function inHoldState(p)
  local F = CFG.FastAnimations
  if not F.HoldStates then return false end
  local name = ""
  pcall(function() name = tostring(p:getCurrentStateName() or "") end)
  if name == "" then return false end
  for _, frag in ipairs(F.HoldStates) do
    if string.find(name, frag, 1, true) then return true end
  end
  return false
end
SD.inHoldState = inHoldState

local function updateFastAnim(p, b, boost)
  local F = CFG.FastAnimations
  if not b.animOn then
    if inHoldState(p) then SD.deferred = (SD.deferred or 0) + 1; return end          -- se activa a mitad de la trepada: la animacion original termina primero
    if not setFlag(p, true) then S.warnOnce("fastAnim", "no se pudo poner la variable de animacion rapida en el jugador"); return end
    b.animOn = true
    S.perfCount("jugador.animacionRapida")
  end
  local mult = math.min(F.MaxMultiplier, 1 + boost)
  if b.animMult and math.abs(b.animMult - mult) < 0.005 then return end
  b.animMult = mult
  for _, base in ipairs(F.Bases) do
    pcall(p.setVariable, p, F.VarPrefix .. string.format("%03d", math.floor(base * 100 + 0.5)), base * mult)
  end
end
SD.updateFastAnim = updateFastAnim

local function clearFastAnim(p, b)
  if not (b and b.animOn) then return end
  local idx = nil
  pcall(function() idx = p:getPlayerNum() end)
  if idx ~= nil and inHoldState(p) then          -- trepada en curso: la bandera y las variables quedan hasta que termine (SD.tickHolds)
    SD.holds[idx] = { since = getTimestampMs() }
    b.animOn, b.animMult = false, nil
    SD.holdStats = (SD.holdStats or 0) + 1
    return
  end
  setFlag(p, false); b.animOn, b.animMult = false, nil
end
SD.clearFastAnim = clearFastAnim

-- Suelta las banderas retenidas cuando el estado de trepada termino (o paso el tope de seguridad por si el estado no se puede leer)
function SD.tickHolds()
  for idx, h in pairs(SD.holds) do
    local p = getSpecificPlayer(idx)
    local maxMs = (CFG.FastAnimations.HoldMaxSeconds or 6) * 1000
    if not p or p:isDead() or not inHoldState(p) or getTimestampMs() - h.since > maxMs then
      if p then setFlag(p, false) end
      SD.holds[idx] = nil
    end
  end
end

function SD.tickPlayers()
  for idx, tier in pairs(SD.active) do
    local p = getSpecificPlayer(idx)
    local b = SD.boost[idx]
    if p and b and CFG.FastAnimations.Enabled and tier.playerBoost > 0 and not p:isDead() and not p:getVehicle() then          -- (86) sin bono (modo trabajo) no hay animacion rapida
      updateFastAnim(p, b, tier.playerBoost)
    elseif p and b then
      clearFastAnim(p, b)
    end
    if CFG.PlayerBoostMethod ~= "none" and p and b and tier.playerBoost > 0 and not p:isDead() and not p:getVehicle() then
      if CFG.PlayerBoostMethod == "animVar" then
        -- velocidad de la animación de caminar/correr (variables leídas por el autotest)
        S.try("animVarBoost", function()
          if b.baseWalk then p:setVariable("WalkSpeed", b.baseWalk * (1 + tier.playerBoost)) end
          if b.baseRun then p:setVariable("RunSpeed", b.baseRun * (1 + tier.playerBoost)) end
        end)
      elseif CFG.PlayerBoostMethod == "moveSpeed" then
        if b.baseMove then S.try("setMoveSpeed", function() p:setMoveSpeed(b.baseMove * (1 + tier.playerBoost)) end) end
      else
        local ok = pcall(nudge, p, b, tier.playerBoost)
        if not ok then S.warnOnce("nudge", "boost por desplazamiento falló") end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Arrastre: el jugador se mueve solo una fracción de lo que avanza cada tick durante N segundos
-- (tras el colapso del Overdrive). Siempre vuelve hacia la casilla anterior, así que nunca
-- atraviesa nada.
---------------------------------------------------------------------------
SD.playerSlow = {}   -- [playerIndex] = { untilMs, factor, lastX, lastY }

function SD.slowPlayer(player, seconds, factor)
  local idx = player:getPlayerNum()
  local e = SD.playerSlow[idx]
  if e then                                   -- ya hay uno en curso: se extiende/actualiza sin reiniciar las posiciones
    e.untilMs = math.max(e.untilMs, S.gameMs() + seconds * 1000)          -- (127) reloj de juego
    e.factor = math.min(e.factor, factor)
    return
  end
  SD.playerSlow[idx] = { untilMs = S.gameMs() + seconds * 1000, factor = factor, lastX = player:getX(), lastY = player:getY() }
end

-- Un jugador con el Sandevistan apagado cerca de otro activo se mueve más lento (como los zombis) mientras esté en su radio.
-- Cada cliente aplica el efecto solo a sus propios jugadores; si el afectado activa el suyo, deja de sentirlo.
function SD.tickPlayerVsPlayer()
  local sources = {}
  for idx, tier in pairs(SD.active) do
    local p = getSpecificPlayer(idx)
    if p and not p:isDead() and not SD.isGlitching(idx) then sources[#sources + 1] = { player = p, zs = tier.zombieSpeed } end
  end
  for _, r in ipairs(SandevistanNet.activeRemotes()) do sources[#sources + 1] = r end
  if #sources == 0 then return end
  local r2 = CFG.SpatialSlow.Radius * CFG.SpatialSlow.Radius
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p and not p:isDead() and not SD.active[idx] then
      local f = nil
      for _, src in ipairs(sources) do
        if src.player ~= p and math.floor(src.player:getZ()) == math.floor(p:getZ()) then
          local dx, dy = src.player:getX() - p:getX(), src.player:getY() - p:getY()
          if dx * dx + dy * dy <= r2 and (not f or src.zs < f) then f = src.zs end
        end
      end
      if f and f < CFG.Firmware.Work.PlayerSlowBelow then SD.slowPlayer(p, 0.3, f) end          -- (86) el modo trabajo (0,8) no frena a otros jugadores
    end
  end
end

function SD.isPlayerSlowed(player)
  local e = SD.playerSlow[player:getPlayerNum()]
  return e ~= nil and e.untilMs > S.gameMs()
end

function SD.tickPlayerSlow()
  local now = S.gameMs()
  for idx, e in pairs(SD.playerSlow) do
    local p = getSpecificPlayer(idx)
    if not p or p:isDead() or now >= e.untilMs then
      SD.playerSlow[idx] = nil
    elseif not p:getVehicle() then
      local x, y = p:getX(), p:getY()
      local dx, dy = x - e.lastX, y - e.lastY
      if dx * dx + dy * dy > 0.25 then          -- teletransporte: no se corrige
        e.lastX, e.lastY = x, y
      else
        local nx, ny = e.lastX + dx * e.factor, e.lastY + dy * e.factor
        S.try("slowPlayer", function() p:setX(nx); p:setY(ny); p:setLastX(nx); p:setLastY(ny) end)
        e.lastX, e.lastY = nx, ny
      end
    end
  end
end

-- Inestabilidad temporal (Psychosis.lua): mientras dura, la dilatación de ese jugador "tartamudea" y los zombis cercanos
-- (y los jugadores que la sufrían) vuelven a velocidad normal.
SD.glitchUntil = {}
function SD.isGlitching(idx) return (SD.glitchUntil[idx] or 0) > S.realMs() end

function SD.isAnyActive() return not S.isEmpty(SD.active) end

-- (134) Para los mods opcionales (Config.FX). Velocidad de la lluvia y la nieve: Precip.Factor con un jugador local dilatado fuera de un glitch, 1 si no
-- (el modo trabajo de Taller no la frena). Tono de un zombi frenado con este factor: 1 sin frenar o en modo trabajo.
function SD.fxDilated()
  for idx, tier in pairs(SD.active) do
    if not SD.isGlitching(idx) and (tonumber(tier and tier.zombieSpeed) or 1) < CFG.Firmware.Work.AnimBelow then return true end
  end
  return false
end

function SD.precipFactor()
  local P = CFG.FX and CFG.FX.Precip
  if not (P and P.Enabled) then return 1 end
  return SD.fxDilated() and P.Factor or 1
end

-- (134b) Tono del ambiente del mundo (la lluvia va dentro de ese evento): Config.FX.Ambience.Pitch con dilatacion, 1 sin.
function SD.ambiencePitch()
  local A = CFG.FX and CFG.FX.Ambience
  if not (A and A.Enabled) then return 1 end
  return SD.fxDilated() and A.Pitch or 1
end

function SD.pitchFor(factor)
  local P = CFG.FX and CFG.FX.Pitch
  factor = tonumber(factor)
  if not (P and P.Enabled) or not factor or factor >= CFG.Firmware.Work.AnimBelow then return 1 end
  return P.Min + (1 - P.Min) * math.max(0, factor)
end

---------------------------------------------------------------------------
-- Estrategia B
---------------------------------------------------------------------------
-- v0.1.30: llamadas directas con pcall(método, objeto, arg) en vez de S.try(function ... end): en los bucles por zombi y por tick
-- cada función anónima era un objeto nuevo para el recolector.
-- Animación en cámara lenta (AnimSets Sandevistan_*.xml): la variable elige los nodos lentos mientras el zombi está frenado.
-- Cambiar la variable a mitad de una animacion de una sola pasada (ataque, empujon, levantarse...) hace que el motor elija el otro nodo y la
-- animacion arranque de cero. Como con las vallas del jugador (FastAnimations.HoldStates): en esos estados no se toca. Al encender se reintenta en
-- el proximo refresco; al soltar, el zombi queda en SD.zHolds y SD.tickZombieHolds quita la variable cuando el estado termina.
SD.zHolds = {}   -- zombi -> desde (ms): la variable lenta sigue puesta hasta que termine la animacion en curso

local function zombieInHold(z)
  local A = CFG.SlowAnimations
  if not A.HoldStates then return false end
  local ok, name = pcall(z.getCurrentStateName, z)
  if not ok or not name then return false end
  name = tostring(name)
  for _, frag in ipairs(A.HoldStates) do
    if string.find(name, frag, 1, true) then return true end
  end
  return false
end
SD.zombieInHold = zombieInHold

-- (134) Un zombi muerto que todavia no paso a cadaver esta haciendo la caida de la muerte: tambien se retiene.
local function zombieDying(z)
  local ok, dead = pcall(z.isDead, z)
  return ok and dead == true
end
SD.zombieDying = zombieDying

local function setAnimSlow(z, info, on)
  if (info.animSlow or false) == on then return end
  if on and not CFG.SlowAnimations.Enabled then return end
  if on and SD.zHolds[z] then                    -- se lo soltaba pero seguia en una animacion retenida: la variable sigue puesta
    SD.zHolds[z] = nil
    info.animSlow = true
    return
  end
  if zombieInHold(z) or (not on and zombieDying(z)) then
    if not on then SD.zHolds[z] = S.realMs(); info.animSlow = false end
    S.perfCount("dilatacion.animacionRetenida")
    return
  end
  if pcall(z.setVariable, z, CFG.SlowAnimations.Variable, on) then
    info.animSlow = on
    if on then S.perfCount("dilatacion.animacionLenta") end
  else
    S.warnOnce("zAnimSlow", "no se pudo poner la variable de animacion lenta en el zombi")
  end
end
SD.setAnimSlow = setAnimSlow

-- Giro en cámara lenta (Config.SlowTurning): turnDelta del zombi = el suyo * factor. Si el valor actual no es el que pusimos, el motor lo recalculó
-- (doZombieSpeed): ese pasa a ser el original. Sin getTurnDelta (zombi de prueba, otra versión del juego) no se hace nada.
local function getTurn(z)
  local ok, v = pcall(z.getTurnDelta, z)
  if ok and type(v) == "number" then return v end
end

local function setTurnSlow(z, info, factor)
  local T = CFG.SlowTurning
  if not (T and T.Enabled) then return end
  local cur = getTurn(z)
  if not cur then return end
  if not info.turnSet or math.abs(cur - info.turnSet) > 1e-4 then info.turnOrig = cur end
  local want = info.turnOrig * math.max(T.Min or 0, math.min(1, factor * (T.Gain or 1)))
  if info.turnSet and math.abs(cur - want) <= 1e-4 then return end
  if pcall(z.setTurnDelta, z, want) then
    info.turnSet = want
    S.perfCount("dilatacion.giroLento")
  else
    S.warnOnce("zTurnSet", "setTurnDelta falló")
  end
end

local function restoreTurn(z, info)
  if not info.turnSet then return end
  local cur = getTurn(z)
  -- si el motor ya lo recalculó por su cuenta, se deja el suyo
  if cur and math.abs(cur - info.turnSet) <= 1e-4 and not pcall(z.setTurnDelta, z, info.turnOrig) then
    S.warnOnce("zTurnRestore", "setTurnDelta (restaurar) falló")
  end
  info.turnSet = nil
end

-- Tiempo en el piso (Config.SlowGround): ZombieOnGroundState descuenta reanimateTimer (30 a 90 al caer, en frames de 30 fps) y el zombi se levanta
-- al llegar a ~0. Igual que con la posicion, de lo que bajo desde la ultima pasada se deja solo la parte factor. Una subida (otro derribo, lo pisan) se
-- acepta tal cual; una bajada de golpe (el servidor lo pone en 0) tambien. Con info.floor = false (de pie) no se lee nada.
local GROUND_JUMP = 10                          -- mas frames que esto entre dos pasadas no es el descuento normal: no se amortigua

local function dampGround(z, info, factor)
  local ok, t = pcall(z.getReanimateTimer, z)
  if not ok or type(t) ~= "number" then info.floor = false; return end
  local last = info.rtLast
  if last then
    local dec = last - t
    if dec > 0 and dec <= GROUND_JUMP then
      t = last - dec * factor
      z:setReanimateTimer(t)
    end
  end
  info.rtLast = t
end

local function checkFloor(z, info)
  local G = CFG.SlowGround
  local ok, on = pcall(z.isOnFloor, z)
  info.floor = (G and G.Enabled and ok and on) and true or false
  if not info.floor then info.rtLast = nil end
end

local function restoreZombie(z, info)
  if CFG.SlowMethod == "speedMod" and info.orig then
    if not pcall(z.setSpeedMod, z, info.orig) then S.warnOnce("zSpeedRestore", "setSpeedMod (restaurar) falló") end
  end
  setAnimSlow(z, info, false)
  restoreTurn(z, info)
end

function SD.tickZombieHolds()
  local A = CFG.SlowAnimations
  local now, maxMs, dyingMs = S.realMs(), (A.HoldMaxSeconds or 6) * 1000, (A.DyingMaxSeconds or 12) * 1000
  for z, since in pairs(SD.zHolds) do
    local release
    if zombieDying(z) then
      release = now - since > dyingMs                -- (134) la caida de la muerte termina entera en camara lenta (antes se soltaba al morir)
    else
      release = now - since > maxMs or not zombieInHold(z)
    end
    if release then
      pcall(z.setVariable, z, CFG.SlowAnimations.Variable, false)
      SD.zHolds[z] = nil
    end
  end
end

function SD.restoreAll()
  for z, info in pairs(SD.releasing) do restoreZombie(z, info) end
  SD.releasing = {}
  for z, info in pairs(SD.slowed) do restoreZombie(z, info) end
  SD.slowed = {}
  SD.cand, SD.candAtMs = {}, 0
  SD.nearList, SD.farList, SD.selAtMs, SD.selSig, SD.lastTickMs, SD.farBudget = {}, {}, 0, nil, nil, 0
  if SD.lod then SD.lod.near, SD.lod.far, SD.lod.fast = 0, 0, 0 end
  if SD.strategy() == "A" then SD.restoreClock() end
end

-- Primera vez que se frena a un zombi: guarda su velocidad original (solo con SlowMethod speedMod).
local function engage(z)
  local info = { z = z }
  if CFG.SlowMethod == "speedMod" then
    local ok, sm = pcall(function() return z:getSpeedMod() end)
    info.orig = ok and sm or 1
  end
  SD.slowed[z] = info
  return info
end

local function applyZombie(z, factor)
  local info = SD.slowed[z]
  if not info then info = engage(z) end
  setAnimSlow(z, info, factor < CFG.Firmware.Work.AnimBelow)          -- (86) el modo trabajo de Taller (factor 0,8) no usa los nodos de camara lenta
  setTurnSlow(z, info, factor)
  checkFloor(z, info)
  if info.floor then dampGround(z, info, factor) end
  if info.factor ~= factor and CFG.SlowMethod == "speedMod" then
    if not pcall(z.setSpeedMod, z, info.orig * factor) then S.warnOnce("zSpeedSet", "setSpeedMod falló") end
  end
  info.factor = factor
  if CFG.SlowMethod ~= "speedMod" then
    -- damping: amortigua el desplazamiento del tick (tiene que correr cada tick)
    local x, y = z:getX(), z:getY()
    if info.lastX then
      local f = math.min(1, factor * (CFG.DampingGain or 1))
      local nx = info.lastX + (x - info.lastX) * f
      local ny = info.lastY + (y - info.lastY) * f
      z:setX(nx); z:setY(ny)                      -- sin pcall por zombi: el bucle entero va protegido en tickB
      x, y = nx, ny
    end
    info.lastX, info.lastY = x, y
  end
end

-- Fuentes de dilatacion: jugadores locales activos (con su latido de MP) + remotos activos replicados por Net.
-- Devuelve la lista y una firma (cantidad y tramos) para notar entre refrescos que cambio algo sin comparar listas.
local function collectSources()
  local sources, sig = {}, 0
  for idx, tier in pairs(SD.active) do
    local p = getSpecificPlayer(idx)
    if p and not p:isDead() then
      if not SD.isGlitching(idx) then
        sources[#sources + 1] = { x = p:getX(), y = p:getY(), zs = tier.zombieSpeed }
        sig = sig + tier.zombieSpeed * (#sources + 6)
      end
      SandevistanNet.heartbeat(p, tier)
    end
  end
  for _, r in ipairs(SandevistanNet.activeRemotes()) do
    sources[#sources + 1] = { x = r.player:getX(), y = r.player:getY(), zs = r.zs }
    sig = sig + r.zs * (#sources + 6)
  end
  return sources, sig
end

-- Muestra para el reporte (cada ~2 s): ¿el zombi frenado tiene la variable de animación lenta?
local function sampleSlowed(z, now)
  SD.sampleAtMs = now + 2000
  local smp = { atMs = now }
  pcall(function() smp.var = z:getVariableBoolean(CFG.SlowAnimations.Variable) end)
  pcall(function() smp.state = tostring(z:getCurrentStateName()) end)
  pcall(function() smp.walkType = tostring(z:getVariableString("zombieWalkType")) end)
  local info = SD.slowed[z]
  smp.marked = info and info.animSlow
  SD.lastSample = smp
end

-- v0.1.30: la lista completa de zombis cargados (cientos en una horda) se recorre cada CandidateMs, no en cada frame: se guardan
-- los que están a radio + margen de alguna fuente y cada tick solo se miden esos. Un zombi corredor no cruza el margen en ese tiempo.
SD.cand = {}
SD.candAtMs = 0
SD.candSources = 0
local CANDIDATE_MS, CANDIDATE_MARGIN = 150, 3

local function rescan(zl, sources, reach2)
  local cand = {}
  local n = zl:size()
  for i = 0, n - 1 do
    local z = zl:get(i)
    if z and not z:isDead() then
      local zx, zy = z:getX(), z:getY()
      for s = 1, #sources do
        local src = sources[s]
        local dx, dy = zx - src.x, zy - src.y
        if dx * dx + dy * dy <= reach2 then cand[#cand + 1] = z; break end
      end
    end
  end
  S.perfCount("dilatacion.escaneos")
  S.perfCount("dilatacion.zombisRecorridos", n)
  return cand
end

-- Camino de antes de la (62): cada tick se mide a los candidatos, se elige a los que estan en el radio y se amortigua a cada uno.
function SD.tickFull()
  local cell = getCell()
  if not cell then return end
  local zl = cell:getZombieList()
  if not zl then return end
  local radius = CFG.SpatialSlow.Radius
  local r2 = radius * radius
  local sources = collectSources()
  local now = S.realMs()
  if #sources == 0 then
    SD.cand = {}
  elseif now >= SD.candAtMs or #sources ~= SD.candSources then
    local reach = radius + CANDIDATE_MARGIN
    SD.cand = rescan(zl, sources, reach * reach)
    SD.candAtMs, SD.candSources = now + CANDIDATE_MS, #sources
  end
  local wanted = {}
  local cand = SD.cand
  for i = 1, #cand do
    local z = cand[i]
    if not z:isDead() then
      local zx, zy = z:getX(), z:getY()
      for s = 1, #sources do
        local src = sources[s]
        local dx, dy = zx - src.x, zy - src.y
        if dx * dx + dy * dy <= r2 then
          local f = wanted[z]
          if not f or src.zs < f then wanted[z] = src.zs end
        end
      end
    end
  end
  for z, info in pairs(SD.slowed) do
    if not wanted[z] then
      restoreZombie(z, info)
      SD.slowed[z] = nil
    end
  end
  if now >= (SD.sampleAtMs or 0) then
    for z, _ in pairs(wanted) do sampleSlowed(z, now); break end
  end
  local applied = 0
  local ok, err = pcall(function()
    for z, f in pairs(wanted) do applyZombie(z, f); applied = applied + 1 end
  end)
  if not ok then S.warnOnce("zDamp", "amortiguación de zombis falló: " .. tostring(err)) end
  S.perfCount("dilatacion.zombisFrenados", applied)
end

---------------------------------------------------------------------------
-- v0.1.30 (62): dilatacion con nivel de detalle
--   refreshLOD (cada SelectMs o al cambiar las fuentes): un solo recorrido de la lista de zombis; los que estan en el radio quedan frenados
--     (animacion lenta, velocidad si SlowMethod es speedMod) y se reparten en dos listas: cercanos (a NearTiles o menos de una fuente) y lejanos.
--   cada tick: los cercanos se amortiguan todos; de los lejanos le toca a una parte, la que corresponde al tiempo pasado desde el tick anterior
--     (FarMs = cada cuanto se actualiza cada lejano; 0 = todos los ticks). El amortiguado usa el desplazamiento acumulado desde la ultima vez
--     (lastX/lastY), asi saltear ticks no cambia la velocidad media: solo que el zombi avanza a tirones mas largos.
---------------------------------------------------------------------------
SD.nearList, SD.farList = {}, {}                -- listas de info (info.z = el zombi), armadas en cada refresco
SD.farCursor, SD.farBudget = 1, 0
SD.selAtMs, SD.selSig, SD.lastTickMs = 0, nil, nil
SD.lod = { near = 0, far = 0, fast = 0 }        -- tamaño de las listas tras el ultimo refresco (lo lee el reporte); fast = lejanos tratados como cercanos por su velocidad
local TELEPORT2 = 25                            -- un salto de mas de 5 casillas entre dos pasadas no es movimiento: no se amortigua
local SPEED_BASE_MS = 500                       -- la velocidad de un zombi se mide entre dos posiciones separadas por lo menos esto (con menos, el serrucho de FarMs la ensucia)

-- Prepara al zombi para frenarlo con este factor: variable de animacion lenta y velocidad (speedMod) solo cuando cambia.
local function tune(z, info, factor)
  setAnimSlow(z, info, factor < CFG.Firmware.Work.AnimBelow)          -- (86) idem
  setTurnSlow(z, info, factor)                                         -- cada refresco: el motor puede haber recalculado su turnDelta
  checkFloor(z, info)                                                  -- caido o de pie: se mira cada refresco; el timer se amortigua en dampRange
  if info.factor ~= factor and CFG.SlowMethod == "speedMod" then
    if not pcall(z.setSpeedMod, z, (info.orig or 1) * factor) then S.warnOnce("zSpeedSet", "setSpeedMod falló") end
  end
  info.factor = factor
  info.df = math.min(1, factor * (CFG.DampingGain or 1))
end

-- farMs y maxJump (> 0 los dos) activan la guarda de velocidad: un zombi lejano al que el motor movera mucho entre dos pasadas (corredor) se trata como
-- cercano. El salto que se ve al reacomodarlo es (1 - df) * velocidad del motor * farMs; con la velocidad efectiva ve (la que se mide, ya amortiguada)
-- el salto es (1 - df) / df * ve * farMs, y se tolera hasta maxJump casillas.
local function refreshLOD(zl, sources, r2, nearR2, now, farMs, maxJump)
  local nearList, farList, seen = {}, {}, {}
  local slowed = SD.slowed
  local nSrc = #sources
  local guard = farMs and maxJump and farMs > 0 and maxJump > 0
  local fast = 0
  local n = zl:size()
  for i = 0, n - 1 do
    local z = zl:get(i)
    if z and not z:isDead() then
      local zx, zy = z:getX(), z:getY()
      local f, nd2 = nil, nil
      for s = 1, nSrc do
        local src = sources[s]
        local dx, dy = zx - src.x, zy - src.y
        local d2 = dx * dx + dy * dy
        if d2 <= r2 then
          if not f or src.zs < f then f = src.zs end
          if not nd2 or d2 < nd2 then nd2 = d2 end
        end
      end
      if f then
        local info = slowed[z] or engage(z)
        info.z = z
        tune(z, info, f)
        seen[z] = true
        local isNear = nd2 <= nearR2
        if guard then
          local rt = info.rt
          if not rt then
            info.rx, info.ry, info.rt = zx, zy, now
          elseif now - rt >= SPEED_BASE_MS then
            local dx, dy = zx - info.rx, zy - info.ry
            local d2, dt = dx * dx + dy * dy, now - rt
            info.ve2 = d2 <= TELEPORT2 and d2 / (dt * dt) or nil            -- casillas/ms al cuadrado; un salto de posicion no cuenta
            info.rx, info.ry, info.rt = zx, zy, now
          end
          if not isNear and info.ve2 then
            local df = info.df
            local lim = maxJump * df / (math.max(1 - df, 0.05) * farMs)
            if info.ve2 > lim * lim then isNear = true; fast = fast + 1 end
          end
        end
        if isNear then nearList[#nearList + 1] = info else farList[#farList + 1] = info end
      end
    end
  end
  for z, info in pairs(slowed) do
    if not seen[z] then
      restoreZombie(z, info)
      slowed[z] = nil
    end
  end
  SD.nearList, SD.farList = nearList, farList
  SD.lod.near, SD.lod.far, SD.lod.fast = #nearList, #farList, fast
  if now >= (SD.sampleAtMs or 0) then
    local info = nearList[1] or farList[1]
    if info then sampleSlowed(info.z, now) end
  end
  S.perfCount("dilatacion.escaneos")
  S.perfCount("dilatacion.zombisRecorridos", n)
end

-- Amortigua list[from..to] (cada zombi con el desplazamiento acumulado desde su ultima pasada). Devuelve cuantos.
local function dampRange(list, from, to)
  local n = 0
  for i = from, to do
    local info = list[i]
    local z = info.z
    if not z:isDead() then
      local x, y = z:getX(), z:getY()
      local lx = info.lastX
      if lx then
        local ly, f = info.lastY, info.df
        local dx, dy = x - lx, y - ly
        if dx * dx + dy * dy <= TELEPORT2 then
          x, y = lx + dx * f, ly + dy * f
          z:setX(x); z:setY(y)                    -- sin pcall por zombi: el bucle entero va protegido en tickLOD
        end
      end
      info.lastX, info.lastY = x, y
      if info.floor then dampGround(z, info, info.factor or 1) end
      n = n + 1
    end
  end
  return n
end

local function clearLOD()
  for z, info in pairs(SD.slowed) do restoreZombie(z, info) end
  SD.slowed = {}
  SD.nearList, SD.farList = {}, {}
  SD.lod.near, SD.lod.far, SD.lod.fast = 0, 0, 0
  SD.farCursor, SD.farBudget, SD.selAtMs, SD.selSig, SD.lastTickMs = 1, 0, 0, nil, nil
end

-- Para la prueba de rendimiento: tras cambiar Config.SlowLOD, que el proximo tick vuelva a elegir.
function SD.lodChanged()
  SD.selAtMs, SD.candAtMs, SD.selSig = 0, 0, nil
  SD.farBudget, SD.lastTickMs = 0, nil
end

-- Parte de cada tick: cercanos completos y la porcion de lejanos que toca. Va aparte (y se llama con pcall(funcion, args)) para no crear una funcion por tick.
local function dampTick(lod, now)
  local applied = 0
  local nearList = SD.nearList
  if nearList[1] then applied = dampRange(nearList, 1, #nearList) end
  local far = SD.farList
  local nf = #far
  if nf > 0 then
    local k = nf
    local farMs = lod.FarMs or 0
    if farMs > 0 then
      local b = SD.farBudget + (SD.lastTickMs and (now - SD.lastTickMs) or 0) * nf / farMs
      k = math.floor(b)
      if k >= nf then k = nf; b = 0 else b = b - k end
      SD.farBudget = b
    end
    if k > 0 then
      local c = SD.farCursor
      if c > nf then c = 1 end
      local last = c + k - 1
      if last <= nf then
        applied = applied + dampRange(far, c, last)
        c = last + 1
      else
        applied = applied + dampRange(far, c, nf) + dampRange(far, 1, last - nf)
        c = last - nf + 1
      end
      SD.farCursor = c
    end
  end
  return applied
end

function SD.tickLOD()
  local sources, sig = collectSources()
  if #sources == 0 then
    if not S.isEmpty(SD.slowed) then clearLOD() end
    return
  end
  local lod = CFG.SlowLOD
  local now = S.realMs()
  if now >= SD.selAtMs or sig ~= SD.selSig then          -- la lista de zombis solo se pide al elegir de nuevo
    local cell = getCell()
    local zl = cell and cell:getZombieList()
    if not zl then return end
    local radius = CFG.SpatialSlow.Radius
    local near = math.min(radius, lod.NearTiles or 8)
    refreshLOD(zl, sources, radius * radius, near * near, now, lod.FarMs or 0, lod.FarMaxJump or 0)
    SD.selAtMs, SD.selSig = now + (lod.SelectMs or 150), sig
  end
  if CFG.SlowMethod == "speedMod" then SD.lastTickMs = now; return end       -- el motor aplica la velocidad: nada que amortiguar por tick
  local ok, applied = pcall(dampTick, lod, now)
  SD.lastTickMs = now
  if not ok then S.warnOnce("zDamp", "amortiguación de zombis falló: " .. tostring(applied)); applied = 0 end
  S.perfCount("dilatacion.zombisFrenados", applied)
end

function SD.tickB()
  local lod = CFG.SlowLOD
  if lod and lod.Enabled then SD.tickLOD() else SD.tickFull() end
end

---------------------------------------------------------------------------
-- Estrategia A (experimental)
---------------------------------------------------------------------------
function SD.tickA()
  local slowest = 1
  for _, tier in pairs(SD.active) do slowest = math.min(slowest, tier.world) end
  S.try("setMultiplier", function()
    local gt = getGameTime()
    gt:setMultiplier(gt:getTrueMultiplier() * slowest)
  end)
end

function SD.restoreClock()
  S.try("restoreMultiplier", function()
    local gt = getGameTime()
    gt:setMultiplier(gt:getTrueMultiplier())
  end)
end

---------------------------------------------------------------------------
-- (64) Salida gradual: al apagar el implante, los zombis cercanos al jugador no pasan de golpe a su velocidad. Durante SlowRelease.Ms el factor de
-- amortiguado sube de df a 1 (mismo desplazamiento acumulado que en dampRange) y la animacion y el giro lentos se sueltan a la mitad. Lo demas se restaura al instante.
---------------------------------------------------------------------------
function SD.beginRelease(player)
  local RL = CFG.SlowRelease
  if not (RL and RL.Enabled) or SD.strategy() ~= "B" or CFG.SlowMethod == "speedMod" or S.isEmpty(SD.slowed) then return false end
  local px, py = 0, 0
  if not pcall(function() px, py = player:getX(), player:getY() end) then return false end
  local lim2 = RL.Tiles * RL.Tiles
  local rel, now, n = {}, S.realMs(), 0
  for z, info in pairs(SD.slowed) do
    local ok, zx, zy = pcall(function() return z:getX(), z:getY() end)
    if ok and info.lastX and not z:isDead() and (zx - px) ^ 2 + (zy - py) ^ 2 <= lim2 then
      info.relAt = now
      info.df0 = info.df or math.min(1, (info.factor or 1) * (CFG.DampingGain or 1))
      rel[z] = info
      n = n + 1
    end
  end
  if n == 0 then return false end
  for z in pairs(rel) do SD.slowed[z] = nil end
  SD.restoreAll()                       -- el resto vuelve ya (y se vacian las listas)
  SD.releasing = rel
  S.perfCount("dilatacion.salidaGradual", 1)
  return true
end

-- Volver a encender a mitad de la salida: esos zombis vuelven a estar frenados (con lo que ya tenian puesto).
function SD.cancelRelease()
  for z, info in pairs(SD.releasing) do SD.slowed[z] = info end
  SD.releasing = {}
end

local function releaseStep(now, ms)
  for z, info in pairs(SD.releasing) do
    local t = (now - info.relAt) / ms
    if t >= 1 or z:isDead() then
      restoreZombie(z, info)
      SD.releasing[z] = nil
    else
      if t >= 0.5 then
        if info.animSlow then setAnimSlow(z, info, false) end
        if info.turnSet then restoreTurn(z, info) end
      end
      local lx = info.lastX
      local x, y = z:getX(), z:getY()
      if lx then
        local ly = info.lastY
        local dx, dy = x - lx, y - ly
        if dx * dx + dy * dy <= TELEPORT2 then
          local f = info.df0 + (1 - info.df0) * t
          x, y = lx + dx * f, ly + dy * f
          z:setX(x); z:setY(y)
        end
      end
      info.lastX, info.lastY = x, y
    end
  end
end

function SD.tickRelease()
  local ok, err = pcall(releaseStep, S.realMs(), CFG.SlowRelease.Ms)
  if not ok then
    S.warnOnce("zRelease", "salida gradual de zombis fallo: " .. tostring(err))
    for z, info in pairs(SD.releasing) do pcall(restoreZombie, z, info) end
    SD.releasing = {}
  end
end

function SD.tick()
  if not S.isEmpty(SD.releasing) then SD.tickRelease() end
  if not S.isEmpty(SD.zHolds) then SD.tickZombieHolds() end
  -- nada que hacer (lo normal con el implante apagado): sin crear tablas ni recorrer nada
  if not S.isEmpty(SD.holds) then SD.tickHolds() end
  if S.isEmpty(SD.active) and S.isEmpty(SD.playerSlow) and S.isEmpty(SD.slowed) and S.isEmpty(SandevistanNet.remote) then return end
  SD.tickPlayerVsPlayer()
  SD.tickPlayerSlow()
  if SD.strategy() == "B" and SandevistanNet.enabled() and (not S.isEmpty(SandevistanNet.remote) or not S.isEmpty(SD.slowed)) then
    SD.tickB(); SD.tickPlayers()      -- MP: también hay que ralentizar (o restaurar) por jugadores remotos
    return
  end
  if not SD.isAnyActive() then return end
  if SD.strategy() == "A" then SD.tickA() else SD.tickB(); SD.tickPlayers() end
end

-- Un personaje nuevo (o cargado) arranca sin la bandera de animación rápida.
Events.OnCreatePlayer.Add(S.safe("Slowdown.OnCreatePlayer", function(idx)
  local p = idx ~= nil and getSpecificPlayer(idx)
  if idx ~= nil then SD.holds[idx] = nil end
  if p then setFlag(p, false) end
end))

-- Por si el juego recicla un objeto zombi que quedó marcado: todo zombi nuevo arranca sin la animación lenta.
Events.OnZombieCreate.Add(S.safe("Slowdown.OnZombieCreate", function(z)
  if z then SD.zHolds[z] = nil; pcall(z.setVariable, z, CFG.SlowAnimations.Variable, false) end
end))

return SD
