-- Sandevistan / FakeZombies (cliente, 0.7 (138)): zombis falsos de la cyberpsicosis. Con la cyberpsicosis activa, de a ratos aparece un zombi que no
-- existe, casi siempre a tu espalda y fuera de la vista: camina (o corre) hacia vos y, al tocarte o al pegarle, se deshace con un glitch. El golpe es
-- psicosomatico: panico, estres y un poco de dolor, sin herida ni infeccion. Nadie mas lo ve, no hace ruido para los zombis reales y no se guarda.
-- No se frena con el Sandevistan (no existe): es la forma de darse cuenta.
-- El dibujo lo pone el mod opcional SandevistanPsychosis (titeres de Java, SandevistanPsychosis/Bridge.lua llena FZ.backend). Sin ese mod no hay zombis falsos
-- (quedan las marcas fantasma de siempre). Aca va toda la logica: cuando nace, por donde va, que animacion hace y cuando se deshace.
--   backend = { ready() -> bool, spawn(id, outfit, female, x, y, z, playerNum) -> bool, move(id, x, y, z, vx, vy, fx, fy),
--               var(id, name, value), look(id, alpha, r, g, b), remove(id), clear(), stats() -> texto }
require "Sandevistan/Core"
require "Sandevistan/Effects"
require "Sandevistan/Psychosis"

local CFG = SandevistanConfig
local S = Sandevistan
local E = SandevistanEffects
local P = SandevistanPsychosis

SandevistanFakeZombies = { list = {}, nextId = 1, backend = nil,
                           spawned = 0, touched = 0, hit = 0, blocked = 0, expired = 0, noRoom = 0, errors = 0 }
local FZ = SandevistanFakeZombies

local function C() return CFG.Psychosis.FakeZombies end
local function lerp(a, b, t) return a + (b - a) * t end
local function rnd(a, b) return lerp(a, b, ZombRandFloat(0, 1)) end

-- (140) Un sonido del zombi falso EN SU posicion: emisor del mundo, asi el volumen, el estereo y la distancia son los del juego. Solo lo
-- oye este cliente y NO es ruido de mundo (nunca addSound): los zombis reales no lo escuchan. Respeta PsychosisAudio (sandbox) y
-- Sound.Enabled, y usa la voz del mismo sexo que el títere.
-- (171) C02: los pasos llevan el piso de su casilla y la velocidad (caminar / correr, como DoFootstepSound de IsoZombie: Walk = 3, Sprint = 5) y
-- las voces la distancia al jugador (PlayerDistance, como un zombi real), asi suenan igual que los de verdad.
local MOVE_WALK, MOVE_SPRINT = 3, 5
local function sound(player, f, role, vol)
  if not f or not P.audioOn or not P.audioOn() then return end
  local ok, id = pcall(P.play, player, role, f.x, f.y, f.z, vol, f.female)
  if not ok or not P.setParams then return end
  if role == "footstep" then
    FZ.sounds.steps = FZ.sounds.steps + 1
    P.setParams(id, { FootstepMaterial = P.footstepMaterial(f.x, f.y, f.z), CharacterMovementSpeed = f.sprint and MOVE_SPRINT or MOVE_WALK })
  elseif player then
    local dist = math.sqrt((f.x - player:getX()) ^ 2 + (f.y - player:getY()) ^ 2)
    P.setParams(id, { PlayerDistance = math.ceil(dist) })
  end
end

local function groanRole(f) return f.sprint and "groanSprint" or "groan" end

-- (172) LA VOZ, como la de un zombi de verdad. El juego no lanza gruñidos sueltos: cada zombi tiene UN evento de voz continuo
-- (IsoZombie.vocalEvent, ZombieVocalsManager: "MaleZombieVoiceA", "FemaleZombieSprinterVoiceB"...) y le cambia el parametro ZombieState segun lo
-- que hace; el evento de FMOD elige solo el sonido (quieto, buscando, brazos arriba al embestir, ataque, golpe). Hasta la 171 el zombi falso
-- lanzaba ese evento suelto cada 4-11 s sin estado: sonaba siempre "quieto" (o casi nada) y no seguia lo que hacia. Ahora: una voz por zombi
-- falso en un emisor libre del mundo que lo sigue (setPos), con su estado, la distancia al jugador (PlayerDistance) y cortada al irse. Si el
-- evento termina solo (isPlaying da false), se vuelve a lanzar despues de GroanEvery, como hace el juego. Verificado en 42.21 (javap):
-- BaseSoundEmitter.setPos(float, float, float), isPlaying(long), stopSound(long), setParameterValueByName(long, String, float).
FZ.ZSTATE = { Idle = 0, SearchTarget = 2, LockTarget = 3, AttackBite = 6, Hit = 7, Attack = 12 }        -- ParameterZombieState$State (index)
FZ.sounds = { steps = 0, voices = 0, restarts = 0, fails = 0 }

function FZ.voiceState(f, state)
  local v = f.voice
  if not v or v.state == state then return end
  v.state = state
  pcall(function() v.em:setParameterValueByName(v.id, "ZombieState", state) end)
end

-- Arranca la voz en un emisor LIBRE (P.playAt, nunca el del jugador: se mueve con setPos). Sin emisor no hay voz (no cae al del jugador).
function FZ.voiceStart(player, f, state, vol)
  if f.voice or not (P.audioOn and P.audioOn()) then return false end
  local name = P.resolve and P.resolve(groanRole(f), f.female)
  if not name then return false end
  local id = P.playAt(name, f.x, f.y, f.z, (vol or 0.75) * (CFG.Psychosis.Audio.Volume or 1))
  local em = P.lastEmitter
  if type(id) ~= "number" or id == 0 or not em then FZ.sounds.fails = FZ.sounds.fails + 1; return false end
  f.voice = { em = em, id = id, name = name, vol = (vol or 0.75) * (CFG.Psychosis.Audio.Volume or 1) }
  f.voiceName = name
  FZ.voiceState(f, state or FZ.ZSTATE.SearchTarget)
  FZ.sounds.voices = FZ.sounds.voices + 1
  return true
end

-- lingerMs: el golpe y la mordida se dejan sonar un poco despues de que el titere se deshace. (173) Y nunca se corta en seco: stopSound
-- frena el evento con el fundido que tenga en FMOD (EventSound.release -> FMOD_Studio_EventInstance_Stop), y las voces de zombi no tienen,
-- asi que se cortaban de golpe (lo noto el usuario en el susto). Ahora se baja el volumen de a poco (setVolume) durante VoiceFadeMs y recien
-- ahi se corta.
FZ.lingering = {}
function FZ.voiceStop(f, lingerMs)
  local v = f.voice
  if not v then return end
  f.voice = nil
  local now = S.realMs()
  local fade = C().Sound.VoiceFadeMs or 600
  FZ.lingering[#FZ.lingering + 1] = { v = v, fadeAt = now + (lingerMs or 0), untilMs = now + (lingerMs or 0) + fade }
end

function FZ.lingerTick(now)
  for i = #FZ.lingering, 1, -1 do
    local l = FZ.lingering[i]
    if now >= l.untilMs then
      pcall(function() l.v.em:stopSound(l.v.id) end)
      table.remove(FZ.lingering, i)
    elseif now >= l.fadeAt then
      local k = (l.untilMs - now) / math.max(1, l.untilMs - l.fadeAt)
      pcall(function() l.v.em:setVolume(l.v.id, (l.v.vol or 0.75) * k * k) end)
    end
  end
end

-- En cada paso: la voz sigue al zombi falso y lleva la distancia; si se termino sola, se relanza despues de GroanEvery.
function FZ.voiceUpdate(player, f, now, state)
  local c = C()
  local Snd = c.Sound
  if not (Snd and Snd.Enabled) or f.silent or not (P.audioOn and P.audioOn()) then FZ.voiceStop(f); return end
  local v = f.voice
  if v then
    local playing = true
    pcall(function() playing = v.em:isPlaying(v.id) == true end)
    if not playing then
      f.voice = nil
      local GE = Snd.GroanEvery or { 4.5, 11 }
      f.nextVoiceMs = now + rnd(GE[1], GE[2]) * 1000
      return
    end
    pcall(function() v.em:setPos(f.x, f.y, f.z) end)
    FZ.voiceState(f, state)
    if now >= (v.distMs or 0) then
      v.distMs = now + 500
      local dist = math.sqrt((f.x - player:getX()) ^ 2 + (f.y - player:getY()) ^ 2)
      pcall(function() v.em:setParameterValueByName(v.id, "PlayerDistance", math.ceil(dist)) end)
    end
  elseif now >= (f.nextVoiceMs or 0) then
    if FZ.voiceStart(player, f, state, Snd.GroanVolume or 0.75) then FZ.sounds.restarts = FZ.sounds.restarts + 1 end
    local GE = Snd.GroanEvery or { 4.5, 11 }
    f.nextVoiceMs = now + rnd(GE[1], GE[2]) * 1000
  end
end

-- La mordida de la MISMA voz (IsoZombie.getBiteSoundName: "MaleZombieVoiceB" -> "MaleZombieBiteB"); si no existe, una del rol.
function FZ.biteName(f)
  local n = f.voiceName and string.gsub(f.voiceName, "Voice", "Bite", 1)
  if n and n ~= f.voiceName and P.soundKnown and P.soundKnown(n) then return n end
  return nil
end

-- (141) El juego delinea en rojo a los zombis que el jugador podria golpear mientras apunta: CombatManager.highlightTargets pide la opcion
-- "contorno melee", jugador local que apunta con algo que no sea un arma a distancia, y la lista de golpes (calculateHitListWeapon: 9 de
-- distancia al cuadrado = 3 casillas y dot con el rumbo >= 0,8). El titere no es una entidad y no puede entrar en esa lista: se repite la
-- misma cuenta para dibujarle el mismo borde y que no se delate por no tenerlo.
function FZ.meleeTarget(player, f)
  local O = C().Outline
  if not (O and O.Enabled) then return false end
  local aiming = false
  pcall(function() aiming = player:isAiming() == true end)
  if not aiming then return false end
  local on = true
  pcall(function() on = getCore():getOptionMeleeOutline() ~= false end)
  if not on then return false end
  local w = nil
  pcall(function() w = player:getUseHandWeapon() end)
  if w then
    local ranged = false
    pcall(function() ranged = w:isRanged() == true end)
    if ranged then return false end
  end
  local dx, dy = f.x - player:getX(), f.y - player:getY()
  local r = O.Range or 3.0
  if dx * dx + dy * dy > r * r then return false end
  local dot = -1
  pcall(function() dot = player:getDotWithForwardDirection(f.x, f.y) end)
  return dot >= (O.Dot or 0.8)
end

function FZ.ready()
  local b = FZ.backend
  if not b then return false end
  return S.cached("FZ.ready", 1000, function()          -- (194) una vez por segundo, no en cada tick
    local ok, r = pcall(b.ready)
    return ok and r == true
  end, b)
end

-- (171) C13.1 (31 §10.2): por que no hay titeres, para el Debug. Antes decia siempre "falta el mod" aunque el jar estuviera y los titeres se
-- hubieran apagado por un error: ahora, si el jar esta, va su estado (SandevistanPsy.status() trae Puppets.lastError).
function FZ.notReadyReason()
  if FZ.ready() then return nil end
  if not FZ.backend then return "falta el mod SandevistanPsychosis (activalo en la lista de mods)" end
  local B = rawget(_G, "SandevistanPsyBridge")
  if not (B and B.status) then return "falta el mod SandevistanPsychosis (activalo en la lista de mods)" end
  local ok, st = pcall(B.status)
  return "SandevistanPsychosis: " .. (ok and tostring(st) or ("error: " .. tostring(st)))
end

-- Activos para este jugador: opcion encendida, el jar listo y cyberpsicosis activa (etapa 2 o mas), despierto y a pie.
function FZ.active(player, d)
  local c = C()
  if not (c and c.Enabled) or CFG.NeuralLoad.Hallucinations == false or not FZ.ready() then return false end
  if not d.cyberpsychosisActive or P.stage(d) < (c.MinStage or 2) then return false end
  if player:isAsleep() then return false end
  local inCar = false
  pcall(function() inCar = player:getVehicle() ~= nil end)
  return not inCar
end

local function square(x, y, z)
  local cell = getCell()
  return cell and cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z)) or nil
end

-- Se puede pasar de la casilla de (x1, y1) a la de (x2, y2)? Sin casilla, solida o con pared/puerta cerrada/ventana en el medio: no.
function FZ.canStep(x1, y1, x2, y2, z)
  local a, b = square(x1, y1, z), square(x2, y2, z)
  if not a or not b then return false end
  if a == b then return true end
  local ok, blocked = pcall(function() return b:isSolid() or b:isSolidTrans() or a:isBlockedTo(b) end)
  return ok and not blocked
end

-- Camino recto libre de (x, y) al jugador, de a media casilla (asi no hace falta buscar caminos: si no hay recta, no nace ahi).
function FZ.pathClear(x, y, px, py, z)
  local dx, dy = px - x, py - y
  local n = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) * 2))
  local cx, cy = x, y
  for i = 1, n do
    local nx, ny = x + dx * i / n, y + dy * i / n
    if not FZ.canStep(cx, cy, nx, ny, z) then return false end
    cx, cy = nx, ny
  end
  return true
end

local function pick(list) return list[ZombRand(#list) + 1] end

-- (146) El susto (Config.Psychosis.FakeZombies.Jumpscare): un corredor callado que nace a tu espalda y grita al llegar a ScreamDist.
-- jumpscare = true lo fuerza (Debug), false lo prohibe; nil lo tira a la suerte con Chance (solo en la etapa MinStage o mas).
local function rollJumpscare(c, d, jumpscare)
  local J = c.Jumpscare
  if jumpscare ~= nil then return jumpscare == true and J ~= nil end
  if not (J and J.Enabled) then return false end
  if d and P.stage(d) < (J.MinStage or 2) then return false end
  return ZombRandFloat(0, 1) < (J.Chance or 0)
end

function FZ.spawn(player, jumpscare)
  local c = C()
  local b = FZ.backend
  local pz = math.floor(player:getZ())
  local px, py = player:getX(), player:getY()
  local scare = rollJumpscare(c, S.data and S.data(player) or nil, jumpscare)
  local J = c.Jumpscare or {}
  local dist = scare and (J.SpawnDist or c.SpawnDist) or c.SpawnDist
  for _ = 1, 4 do
    local behind = scare or ZombRandFloat(0, 1) < (c.BehindChance or 0.6)
    local x, y = P.pickPos(player, dist[1], dist[2], behind)
    if x and FZ.pathClear(x, y, px, py, pz) then
      local id = FZ.nextId
      FZ.nextId = FZ.nextId + 1
      local female = ZombRandFloat(0, 1) < 0.5
      local ok, born = pcall(b.spawn, id, pick(c.Outfits), female, x, y, pz, player:getPlayerNum())
      if not ok or born ~= true then
        if not ok then FZ.errors = FZ.errors + 1; S.warnOnce("fakeSpawn", "zombi falso: " .. tostring(born)) end
        return nil
      end
      local sprint = scare or ZombRandFloat(0, 1) < (c.SprintChance or 0)
      local f = { id = id, idx = player:getPlayerNum(), x = x, y = y, z = pz, bornMs = S.realMs(), sprint = sprint,
                  speed = sprint and c.SprintSpeed or rnd(c.WalkSpeed[1], c.WalkSpeed[2]), lifeMs = c.LifeSeconds * 1000,
                  female = female, stepAcc = 0, jumpscare = scare, silent = scare }
      pcall(b.var, id, "zombieWalkType", sprint and ("sprint" .. (ZombRand(5) + 1)) or tostring(ZombRand(5) + 1))
      -- (152) los corredores del juego (walktoward/sprintN) piden shouldSprint y bHasTarget; sin shouldSprint caminaban (sprintWalkN) y
      -- recien corrian al embestir, de cerca. Ahora vienen corriendo desde que nacen.
      if sprint then pcall(b.var, id, "shouldSprint", "true") end
      pcall(b.var, id, "bMoving", "true")
      pcall(b.look, id, c.Alpha or 1, c.Tint[1], c.Tint[2], c.Tint[3])
      FZ.list[#FZ.list + 1] = f
      FZ.spawned = FZ.spawned + 1
      -- (145) una linea por aparicion: sirve para saber si el zombi falso nacio cuando no se ve en la camara 3D
      S.log(string.format("zombi falso: nace %d a %.2f casillas (lado %s)%s", id,
        math.sqrt((x - px) * (x - px) + (y - py) * (y - py)), behind and "atras" or "adelante", scare and " [susto: corredor callado]" or ""))
      if scare then FZ.scares = (FZ.scares or 0) + 1 end
      -- (140) sonidos: gruñido al aparecer (no siempre) y, despues, pasos y gruñidos cada tanto mientras camina
      local Snd = c.Sound
      if Snd and Snd.Enabled then
        -- (172) la voz arranca al nacer (ya te tiene de objetivo: buscando), salvo el susto, que va callado hasta gritar
        if not f.silent then FZ.voiceStart(player, f, FZ.ZSTATE.SearchTarget, Snd.StartVolume or 0.8) end
        local SE = Snd.StepEvery or { 0.65, 0.9 }
        f.stepNext = rnd(SE[1], SE[2])
      end
      return f
    end
  end
  FZ.noRoom = FZ.noRoom + 1
  return nil
end

-- (188) Un titere que ya existe (el del disfraz nivel B, que se solto de su jugador) pasa a ser un zombi falso en (x, y, z): va hacia el jugador
-- ya con los brazos arriba (embestida desde el principio), conserva su voz si la traia y su color (sin el tinte de los zombis falsos).
-- opts: lifeMs (tope de vida), onGone (se llama una vez al sacarlo, por cualquier motivo, salvo FZ.forget).
function FZ.adopt(player, id, x, y, z, female, voice, opts)
  local c = C()
  local b = FZ.backend
  if not b then return nil end
  opts = opts or {}
  local f = { id = id, idx = player:getPlayerNum(), x = x, y = y, z = math.floor(z), bornMs = S.realMs(), sprint = false,
              speed = rnd(c.WalkSpeed[1], c.WalkSpeed[2]), lifeMs = opts.lifeMs or c.LifeSeconds * 1000, female = female == true,
              stepAcc = 0, adopted = true, lungeAlways = true, tint = { 1, 1, 1 }, onGone = opts.onGone }
  if voice then f.voice, f.voiceName = voice, voice.name end
  -- sale de la postura de brazos arriba quieto (face-target vuelve a idle con isFacingTarget) y embiste caminando
  pcall(b.var, id, "bAttack", "false")
  pcall(b.var, id, "isFacingTarget", "true")
  pcall(b.var, id, "shouldSprint", "false")
  pcall(b.var, id, "bMoving", "true")
  pcall(b.move, id, x, y, f.z, 0, 0, 0, 0)
  local Snd = c.Sound
  if Snd and Snd.Enabled then
    local SE = Snd.StepEvery or { 0.65, 0.9 }
    f.stepNext = rnd(SE[1], SE[2])
  end
  FZ.list[#FZ.list + 1] = f
  FZ.adopted = (FZ.adopted or 0) + 1
  return f
end

-- (188) Saca un zombi falso adoptado sin avisar (onGone no se llama): lo usa el disfraz cuando su episodio termina primero.
function FZ.forget(id)
  for i = #FZ.list, 1, -1 do
    local f = FZ.list[i]
    if f.id == id then
      FZ.voiceStop(f)
      table.remove(FZ.list, i)
    end
  end
end

local function gone(f)
  local cb = f.onGone
  f.onGone = nil
  if cb then
    local ok, err = pcall(cb, f)
    if not ok then FZ.errors = FZ.errors + 1; S.warnOnce("fakeGone", "zombi falso (adoptado): " .. tostring(err)) end
  end
end

-- Empieza a deshacerse (por que: "touch", "hit", "blocked", "expired"). El parpadeo y la animacion los pone update.
function FZ.dissolve(f, why, player)
  if f.fadeAt then return end
  f.fadeAt = S.realMs()
  f.why = why
  local b = FZ.backend
  if f.outline then f.outline = false; if b and b.outline then pcall(b.outline, f.id, false) end end   -- (141) sin contorno al deshacerse
  if why == "touch" then
    FZ.touched = FZ.touched + 1
    pcall(b.var, f.id, "bAttack", "true")
    pcall(b.var, f.id, "isFacingTarget", "true")
    pcall(b.var, f.id, "AttackOutcome", "start")
  elseif why == "hit" then
    FZ.hit = FZ.hit + 1
    pcall(b.var, f.id, "bStaggerBack", "true")
    local Snd = C().Sound
    FZ.voiceState(f, FZ.ZSTATE.Hit)                                         -- (172) la voz del golpe (antes un gruñido suelto)
  elseif why == "blocked" then
    FZ.blocked = FZ.blocked + 1
  else
    FZ.expired = FZ.expired + 1
  end
  if player and (why == "touch" or why == "hit") then pcall(P.play, player, "glitchVanish", f.x, f.y, f.z, 0.9) end
end

-- El golpe que no existio: panico, estres y dolor en el brazo o el cuello que "agarro". Sin herida, sin infeccion.
function FZ.contact(f, player)
  local c = C()
  local J = f.jumpscare and c.Jumpscare or nil
  local Snd = c.Sound
  FZ.voiceState(f, FZ.ZSTATE.AttackBite)                                     -- (172) la voz muerde
  if Snd and Snd.Enabled and P.audioOn and P.audioOn() then                  -- (140) el mordisco, (172) de la misma voz si existe
    local bite = FZ.biteName(f)
    if bite then
      local id = P.playAt(bite, f.x, f.y, f.z, (Snd.BiteVolume or 1.0) * (CFG.Psychosis.Audio.Volume or 1))
      if type(id) ~= "number" or id == 0 then sound(player, f, "bite", Snd.BiteVolume or 1.0) end
    else
      sound(player, f, "bite", Snd.BiteVolume or 1.0)
    end
  end
  S.markSeen(player, "fakeTouch")                                          -- (179) lo descubriste al tocarte
  E.addStat(player, "PANIC", J and J.Panic or c.Panic)
  E.addStat(player, "STRESS", c.Stress * (J and J.StressMult or 1))
  if (c.Pain or 0) > 0 then E.addPain(player, pick(c.PainParts), c.Pain) end
  E.halo(player, getText("IGUI_Sandevistan_FakeZombieGone"), 120, 220, 255)
  P.toast(getText("IGUI_Sandevistan_Mon_FakeZombie"), "crit")
  P.textGlitch(J and J.TextGlitch or CFG.Psychosis.TextGlitch.OnFakeZombie, 700)
  -- (146) el susto rompe la pantalla un instante (tiras, desgarro y el panel con separacion de color)
  if J and (J.ScreenGlitchMs or 0) > 0 and SandevistanHUD and SandevistanHUD.forceGlitch then SandevistanHUD.forceGlitch(J.ScreenGlitchMs) end
  if P.shake then P.shake(player, J and "Scare" or "Touch") end             -- (181) C13.3
  FZ.dissolve(f, "touch", player)
end

-- (146) "Salto" de un instante mientras camina: parpadea y se le corren los colores (TellMs), como si la imagen fallara. Es la pista de que no
-- existe; con TellChance por segundo es raro. Al terminar vuelve al aspecto normal.
function FZ.tell(f, dt, now)
  local c = C()
  local G = c.Glitch
  local b = FZ.backend
  if f.tellUntil then                                   -- primero se termina el salto en curso (aunque la opcion se haya apagado)
    if now < f.tellUntil then
      local flick = (math.floor(now / 35) % 2 == 0) and 1 or 0.3
      if f.tellCalm then                                -- (170) C01 menos destellos: un solo bajon suave en vez del parpadeo
        local u = (now - f.tellStart) / math.max(1, f.tellUntil - f.tellStart)
        flick = 1 - 0.5 * math.sin(math.pi * u)
      end
      local tn = f.tint or c.Tint                       -- (188) el adoptado conserva su color
      pcall(b.look, f.id, flick * (c.Alpha or 1), tn[1], tn[2], tn[3])
      return
    end
    f.tellUntil = nil
    local tn = f.tint or c.Tint
    pcall(b.look, f.id, c.Alpha or 1, tn[1], tn[2], tn[3])
    if b.glitch then pcall(b.glitch, f.id, 0) end
    return
  end
  if not (G and G.Enabled) or (G.TellChance or 0) <= 0 then return end
  if ZombRandFloat(0, 1) < G.TellChance * dt then
    f.tellCalm = S.lessFlashes()
    f.tellStart = now
    f.tellUntil = now + (G.TellMs or 110) * (f.tellCalm and (CFG.LessFlashes.TellStretch or 4) or 1)
    f.tells = (f.tells or 0) + 1
    if b.glitch and not f.tellCalm then pcall(b.glitch, f.id, 0.7) end
  end
end

-- Un paso de un zombi falso. Devuelve false cuando hay que sacarlo.
function FZ.update(f, player, dt, now)
  local c = C()
  local b = FZ.backend
  if f.fadeAt then
    local t = (now - f.fadeAt) / math.max(1, c.FadeMs)
    if t >= 1 then return false end
    local G = c.Glitch
    local calm = S.lessFlashes()                                         -- (170) C01: fundido liso, sin parpadeo, tirones ni colores alternados
    local flick = (calm or math.floor(now / 45) % 2 == 0) and 1 or 0.35  -- parpadeo del glitch
    local jx, jy = 0, 0
    local r, g, bl = 0.55 + 0.45 * flick, 1, 1
    if calm then r, g, bl = 0.55, 1, 1
    elseif G and G.Enabled then
      -- (142) glitch cyberpunk: tirones de posicion (cada vez mas chicos) y color cian / magenta / blanco en franjas cortas
      local j = (G.JitterTiles or 0.12) * (1 - t)
      if ZombRandFloat(0, 1) < (G.JitterChance or 0.35) then jx = rnd(-j, j); jy = rnd(-j, j) end
      local k = math.floor(now / (G.ColorMs or 55)) % 3
      if k == 0 then r, g, bl = 1.0, 0.15, 0.85
      elseif k == 1 then r, g, bl = 0.15, 1.0, 1.0
      else r, g, bl = 1.0, 1.0, 1.0 end
      if flick < 0.5 then r, g, bl = r * 0.45, g * 0.45, bl * 0.45 end
    end
    pcall(b.look, f.id, (1 - t) * flick * (c.Alpha or 1), r, g, bl)
    pcall(b.move, f.id, f.x + jx, f.y + jy, f.z, 0, 0, 0, 0)
    if b.glitch then pcall(b.glitch, f.id, (G and G.Enabled and not calm) and (1 - t) or 0) end     -- (142) separacion de color del jar
    return true
  end
  if now - f.bornMs > f.lifeMs then FZ.dissolve(f, "expired", player); return true end
  if math.floor(player:getZ()) ~= f.z then FZ.dissolve(f, "blocked", player); return true end
  local px, py = player:getX(), player:getY()
  local dx, dy = px - f.x, py - f.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist <= c.TouchDist then FZ.contact(f, player); return true end
  local ux, uy = dx / dist, dy / dist
  -- (146) el susto: callado hasta ScreamDist; ahi grita fuerte y ya suena como cualquier corredor
  if f.silent and dist <= ((c.Jumpscare and c.Jumpscare.ScreamDist) or 4.5) then
    f.silent = false
    f.screamed = true
    local Snd = c.Sound
    -- (172) el grito es la voz que arranca con el objetivo fijado (brazos arriba), fuerte
    if Snd and Snd.Enabled then FZ.voiceStart(player, f, FZ.ZSTATE.LockTarget, (c.Jumpscare and c.Jumpscare.ScreamVolume) or 1.2) end
    if P.shake then P.shake(player, "Scare") end                            -- (181) C13.3: el grito sacude
  end
  local lunge = dist <= c.LungeDist or f.lungeAlways == true           -- (188) el adoptado ya viene con los brazos arriba
  if lunge ~= f.lunge then
    f.lunge = lunge
    pcall(b.var, f.id, "bLunge", lunge and "true" or "false")
    -- (138c) en el grupo de acciones del juego la embestida solo vuelve a caminar sin objetivo y con bStopLunging
    pcall(b.var, f.id, "bStopLunging", lunge and "false" or "true")
    pcall(b.var, f.id, "bHasTarget", (lunge or f.sprint) and "true" or "false")     -- (152) el corredor necesita objetivo para correr
    local Snd = c.Sound
    -- (172) al embestir la voz pasa a "objetivo fijado" (FZ.voiceUpdate, abajo): ya no hay un gruñido suelto aparte
  end
  local speed = lunge and math.max(f.speed, c.LungeSpeed) or f.speed
  -- (138e) con el jar, el paso lo da la animacion (como un zombi de verdad: los pies no patinan y cada forma de caminar alcanza a su ritmo).
  -- Hasta medirlo (los primeros cuadros) o sin esa funcion, la velocidad de la configuracion.
  local anim = b.speed and select(2, pcall(b.speed, f.id))
  if type(anim) == "number" and anim >= 0 then speed = math.min(anim, c.MaxAnimSpeed or 4) end
  local step = math.min(speed * dt, dist - c.TouchDist * 0.5)
  local nx, ny = f.x + ux * step, f.y + uy * step
  if (math.floor(nx) ~= math.floor(f.x) or math.floor(ny) ~= math.floor(f.y)) and not FZ.canStep(f.x, f.y, nx, ny, f.z) then
    FZ.dissolve(f, "blocked", player)                  -- una puerta que se cerro o una pared: no la rodea, se deshace
    return true
  end
  f.x, f.y = nx, ny
  pcall(b.move, f.id, nx, ny, f.z, ux * speed, uy * speed, ux, uy)
  -- (140) pasos cada StepEvery casillas recorridas y un gruñido cada GroanEvery segundos (los dos en su posicion)
  FZ.tell(f, dt, now)                                   -- (146) la pista: un salto de imagen de vez en cuando
  local Snd = c.Sound
  if Snd and Snd.Enabled and not f.silent then
    f.stepAcc = (f.stepAcc or 0) + step
    if f.stepAcc >= (f.stepNext or 0.7) then
      f.stepAcc = 0
      -- (171) C02: el corredor da trancos mas largos (unos 3 pasos por segundo, no 5) y pisa mas fuerte, como en vanilla (0,5 caminando, 1 corriendo)
      local SE = (f.sprint and Snd.StepEverySprint) or Snd.StepEvery or { 0.65, 0.9 }
      f.stepNext = rnd(SE[1], SE[2])
      sound(player, f, "footstep", (f.sprint and Snd.StepVolumeSprint) or Snd.StepVolume or 0.5)
    end
  end
  -- (172) la voz sigue al zombi falso; (173) el susto, despues de gritar, queda con el objetivo fijado (si vuelve a "buscando" corta el grito)
  FZ.voiceUpdate(player, f, now, (f.lunge or f.screamed) and FZ.ZSTATE.LockTarget or FZ.ZSTATE.SearchTarget)
  -- (141) contorno rojo como el de un zombi real (solo cuando cambia: el jar lo guarda por titere)
  if b.outline then
    local want = FZ.meleeTarget(player, f)
    if want ~= f.outline then
      f.outline = want
      pcall(b.outline, f.id, want)
    end
  end
  return true
end

function FZ.clear(idx)
  local b = FZ.backend
  for i = #FZ.list, 1, -1 do
    local f = FZ.list[i]
    if idx == nil or f.idx == idx then
      if b then pcall(b.remove, f.id) end
      FZ.voiceStop(f)                                                  -- (172)
      table.remove(FZ.list, i)
      gone(f)                                                          -- (188)
    end
  end
end

function FZ.countFor(idx)
  local n = 0
  for _, f in ipairs(FZ.list) do if f.idx == idx and not f.fadeAt then n = n + 1 end end
  return n
end

-- Desde Psychosis.tick (dt en segundos de juego; 0 en pausa).
function FZ.tick(player, d, st, now, dt)
  local idx = player:getPlayerNum()
  if not FZ.active(player, d) then
    FZ.clear(idx)
    return
  end
  if dt <= 0 then return end
  for i = #FZ.list, 1, -1 do
    local f = FZ.list[i]
    if f.idx == idx then
      local ok, keep = pcall(FZ.update, f, player, dt, now)
      if not ok then FZ.errors = FZ.errors + 1; S.warnOnce("fakeUpdate", "zombi falso: " .. tostring(keep)); keep = false end
      if not keep then
        pcall(FZ.backend.remove, f.id)
        -- (172) la voz se va con el titere; (173) el susto deja sonar mas el grito y la mordida
        local Snd = C().Sound
        local linger = (f.why == "hit" or f.why == "touch") and (f.jumpscare and (Snd.ScareLingerMs or 2500) or (Snd.VoiceLingerMs or 1500)) or 0
        FZ.voiceStop(f, linger)
        table.remove(FZ.list, i)
        gone(f)                                                          -- (188) el adoptado devuelve a su jugador

      end
    end
  end
  local c = C()
  if not st.nextFakeMs then st.nextFakeMs = now + c.FirstDelaySeconds * 1000 end
  if now < st.nextFakeMs or FZ.countFor(idx) >= c.Max then return end
  local every = lerp(c.EverySeconds[2], c.EverySeconds[1], P.intensity(d)) / math.max(0.2, P.freqMult(d, st, "FakeZombies")) / S.halluMultiplier(d)          -- (180) Filtro
  st.nextFakeMs = now + every * 1000 * rnd(0.6, 1.4)
  FZ.spawn(player)
end

-- Un golpe del jugador (con o sin arma) deshace a los zombis falsos que tiene adelante, al alcance.
function FZ.onSwing(attacker, weapon)
  if #FZ.list == 0 or not attacker or not instanceof(attacker, "IsoPlayer") or not attacker:isLocalPlayer() then return end
  local reach = 1.2
  pcall(function() if weapon and weapon.getMaxRange then reach = weapon:getMaxRange() end end)
  reach = reach + (C().HitSlack or 0.4)
  local fx, fy = 0, 0
  pcall(function() fx, fy = attacker:getForwardDirectionX(), attacker:getForwardDirectionY() end)
  local idx, px, py = attacker:getPlayerNum(), attacker:getX(), attacker:getY()
  for _, f in ipairs(FZ.list) do
    if f.idx == idx and not f.fadeAt then
      local dx, dy = f.x - px, f.y - py
      local dist = math.sqrt(dx * dx + dy * dy)
      if dist <= reach and (dist < 0.3 or (dx * fx + dy * fy) / dist >= 0.4) then
        S.markSeen(attacker, "fakeHit")                                    -- (179) lo descubriste al golpearlo
        FZ.dissolve(f, "hit", attacker)
      end
    end
  end
end

-- (173) Las voces que se estan apagando corren aparte de FZ.tick: si los zombis falsos se borran todos (sin cyberpsicosis, al morir) el
-- fundido sigue hasta cortarlas.
if Events and Events.OnTick then
  Events.OnTick.Add(function() if #FZ.lingering > 0 then pcall(FZ.lingerTick, S.realMs()) end end)
end

function FZ.statusLine()
  local b = FZ.backend
  local st = b and select(2, pcall(b.stats)) or "sin el mod SandevistanPsychosis"
  local snd = FZ.sounds                                                     -- (172) sonidos: si da 0 voces y fallas > 0, no hubo emisor libre
  return string.format("zombis falsos: %d vivos | nacidos %d (sustos %d, sin lugar %d, disfraces soltados %d), al tocarte %d, golpeados %d, frenados por paredes %d, vencidos %d, errores %d | sonidos: %d pasos, %d voces (%d relanzadas, %d fallidas) | %s",
    #FZ.list, FZ.spawned, FZ.scares or 0, FZ.noRoom, FZ.adopted or 0, FZ.touched, FZ.hit, FZ.blocked, FZ.expired, FZ.errors,
    snd.steps, snd.voices, snd.restarts, snd.fails, tostring(st))
end

Events.OnWeaponSwing.Add(S.safe("FakeZombies.OnWeaponSwing", FZ.onSwing))
Events.OnPlayerDeath.Add(S.safe("FakeZombies.OnPlayerDeath", function(player) FZ.clear(player:getPlayerNum()) end))

return FZ
