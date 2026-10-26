-- Sandevistan / Disguise (cliente, 0.7 (174)): el disfraz como episodio de la cyberpsicosis (29 §4.1 y §4.3, 22 §6.2). En etapa 3, de a ratos y por
-- 20 a 40 s, este cliente ve a otros con la piel del otro bando. Nadie mas lo ve y no cambia nada del mundo.
--  * Zombis -> personas (nivel A): zombis reales a la vista con piel sana (su ropa y su andar de zombi). Es la unica alucinacion que puede doler de
--    verdad: el zombi es real y muerde (regla de justicia 3, 22 §2.1). Por eso es rara, corta y lleva la pista del salto de imagen.
--  * Jugadores -> zombis: otros jugadores a la vista. Nivel B si se puede (el real no se dibuja y va un titere zombi con su ropa que lo sigue y
--    copia su andar), si no nivel A (piel podrida). Por defecto solo con PvP apagado (opcion de sandbox PsychosisDisguise). Nunca sobre uno mismo.
-- Pista (TellChance por segundo): el disfrazado "salta" un instante a como es de verdad (nivel A) o se le corren los colores (nivel B); con
-- "menos destellos" el salto dura mas (nivel A) o es un bajon suave (nivel B).
-- (188) Nivel B, jugadores: el zombi actua como zombi con el que lo ve (Config.Psychosis.Disguise.Approach). Con el jugador quieto y cerca gira
-- de a poco hacia vos y, mas cerca, levanta los brazos; tiene voz de zombi todo el episodio. Al levantar los brazos a veces se suelta y va hacia
-- vos como un zombi falso (FakeZombies.adopt): si te toca o le pegas se deshace, y ahi vuelve el real donde este y su disfraz termina.
-- El dibujo lo pone el mod opcional SandevistanPsychosis (DS.backend, lo llena su Bridge.lua). Sin ese jar no hay disfraz.
require "Sandevistan/Core"
require "Sandevistan/Psychosis"
require "Sandevistan/Viewport"

local CFG = SandevistanConfig
local S = Sandevistan
local P = SandevistanPsychosis

-- Los ids de los titeres son de un solo mapa en el jar: los del disfraz van aparte de los zombis falsos y del clon (1000000).
SandevistanDisguise = { nextId = 2000000, eps = {},
                        episodes = 0, zombieEps = 0, playerEps = 0, levelB = 0, levelA = 0, fallbacks = 0, tells = 0, noTarget = 0, errors = 0,
                        faces = 0, arms = 0, detaches = 0, reveals = 0 }
local DS = SandevistanDisguise

local function C() return CFG.Psychosis.Disguise end
local function lerp(a, b, t) return a + (b - a) * t end
local function rnd(a, b) return lerp(a, b, ZombRandFloat(0, 1)) end

-- Modos del nivel A (SandevistanPsy.disguise): 1 persona, 2..4 zombi con podredumbre 1..3.
local HUMAN = 1

function DS.ready()
  local b = DS.backend
  if not (b and b.ready) then return false end
  return S.cached("DS.ready", 1000, function()          -- (194) una vez por segundo, no en cada tick
    local ok, r = pcall(b.ready)
    return ok and r == true
  end, b)
end

-- Nivel B disponible: el jar lo trae y, con la camara 3D de Viewpoint, LevelB3D (186: SandevistanViewpoint esconde al real en su dibujo; hasta
-- la 185 en 3D siempre era nivel A).
function DS.canHide()
  local b = DS.backend
  if not (b and b.canHide) then return false end
  local ok, r = pcall(b.canHide)
  if not (ok and r == true) then return false end
  return not SandevistanViewport.is3D() or C().LevelB3D == true
end

-- El PvP del servidor esta apagado (sin poder preguntar, se toma como encendido).
function DS.pvpOff()
  local ok, pvp = pcall(function() return getServerOptions():getBoolean("PVP") end)
  return ok and pvp == false
end

-- Jugadores -> zombis permitido: opcion "always", o "nopvp" con el PvP del servidor apagado. Solo en multijugador.
function DS.playersAllowed()
  local c = C()
  if not isClient() or c.Players == "never" then return false end
  if c.Players == "always" then return true end
  return DS.pvpOff()
end

function DS.active(player, d)
  local c = C()
  if not (c and c.Enabled) or CFG.NeuralLoad.Hallucinations == false or not DS.ready() then return false end
  if not d.cyberpsychosisActive or P.stage(d) < (c.MinStage or 3) then return false end
  return not player:isAsleep()
end

-- Vivo, mismo piso, a Range casillas, a la vista y a mas de MinDist (no se transforma en la cara). minDist nil = sin minimo.
local function candidate(player, chr, r2, minD2)
  local ok, d2 = pcall(function()
    if chr:isDead() or math.floor(chr:getZ()) ~= math.floor(player:getZ()) then return nil end
    local dx, dy = chr:getX() - player:getX(), chr:getY() - player:getY()
    local dd = dx * dx + dy * dy
    if dd > r2 or dd < (minD2 or 0) then return nil end
    local sq = chr:getCurrentSquare()
    if not sq or sq:isCouldSee(player:getPlayerNum()) ~= true then return nil end
    return dd
  end)
  return ok and d2 or nil
end

local function closest(list, max)
  table.sort(list, function(a, b) return a.d2 < b.d2 end)
  local out = {}
  for i = 1, math.min(#list, max) do out[i] = list[i].chr end
  return out
end

function DS.pickZombies(player)
  local c = C()
  local list = {}
  local cell = getCell()
  local zs = cell and cell:getZombieList()
  if not zs then return list end
  local r2, m2 = c.Range * c.Range, (c.MinDist or 0) ^ 2
  for i = 0, zs:size() - 1 do
    local z = zs:get(i)
    local d2 = candidate(player, z, r2, m2)
    if d2 then list[#list + 1] = { chr = z, d2 = d2 } end
  end
  return closest(list, c.MaxZombies or 3)
end

-- Otros jugadores (nunca uno mismo ni otro jugador local de pantalla dividida).
function DS.pickPlayers(player)
  local c = C()
  local list = {}
  local ok, ps = pcall(getOnlinePlayers)
  if not ok or not ps then return list end
  local r2 = c.Range * c.Range
  for i = 0, ps:size() - 1 do
    local o = ps:get(i)
    local isLocal = true
    pcall(function() isLocal = o == player or o:isLocalPlayer() end)
    if not isLocal then
      local d2 = candidate(player, o, r2, nil)
      if d2 then list[#list + 1] = { chr = o, d2 = d2 } end
    end
  end
  return closest(list, c.MaxPlayers or 2)
end

-- Nivel A sobre chr por ms (el Bridge lo saca solo al vencer).
local function levelA(t, ms)
  local ok, r = pcall(DS.backend.disguise, t.chr, t.mode, ms)
  return ok and r == true
end

-- Nivel B: titere zombi en lugar del jugador.
local function levelB(ep, t)
  local id = DS.nextId
  DS.nextId = DS.nextId + 1
  local ok, r = pcall(DS.backend.hide, t.chr, id, ep.idx, t.rot)
  if not (ok and r == true) then
    if not ok then DS.errors = DS.errors + 1; S.warnOnce("disguiseHide", "disfraz nivel B: " .. tostring(r)) end
    return false
  end
  t.level, t.id, t.anim = "B", id, {}
  return true
end

-- Empieza un episodio. kind = "zombies" o "players"; nil lo elige (jugadores con PlayerChance si hay y se puede). forced (Debug): sin pedir
-- etapa ni permiso de PvP. Devuelve el episodio o nil (sin nadie a la vista).
function DS.start(player, kind, forced)
  local c = C()
  local idx = player:getPlayerNum()
  if DS.eps[idx] then DS.stop(idx) end
  local now = S.realMs()
  local players = (forced or DS.playersAllowed()) and DS.pickPlayers(player) or {}
  if kind == nil then
    kind = (#players > 0 and ZombRandFloat(0, 1) < (c.PlayerChance or 0.5)) and "players" or "zombies"
  end
  local chrs = kind == "players" and players or DS.pickZombies(player)
  if #chrs == 0 then DS.noTarget = DS.noTarget + 1; return nil end
  local ms = rnd(c.Seconds[1], c.Seconds[2]) * 1000
  local ep = { idx = idx, kind = kind, bornMs = now, untilMs = now + ms, forced = forced == true, targets = {} }
  local hide = kind == "players" and c.LevelB ~= false and DS.canHide()
  for _, chr in ipairs(chrs) do
    local rot = ZombRand(c.Rot[1], c.Rot[2] + 1)
    local t = { chr = chr, rot = rot, mode = kind == "players" and (rot + 1) or HUMAN, level = "A", bornMs = now }
    if hide and levelB(ep, t) then
      DS.levelB = DS.levelB + 1
    elseif levelA(t, ms) then
      DS.levelA = DS.levelA + 1
    else
      t = nil
    end
    if t then ep.targets[#ep.targets + 1] = t end
  end
  if #ep.targets == 0 then DS.noTarget = DS.noTarget + 1; return nil end
  DS.eps[idx] = ep
  DS.episodes = DS.episodes + 1
  if kind == "players" then DS.playerEps = DS.playerEps + 1 else DS.zombieEps = DS.zombieEps + 1 end
  S.log(string.format("disfraz: %s, %d a la vista, %.0f s (%s)", kind == "players" and "jugadores como zombis" or "zombis como personas",
    #ep.targets, ms / 1000, ep.targets[1].level == "B" and "nivel B" or "nivel A"))
  return ep
end

local function FZm() return rawget(_G, "SandevistanFakeZombies") end

-- Devuelve al disfrazado como es. (188) Se va tambien su voz de zombi y, si se habia soltado, el zombi falso que quedaba.
local function release(t)
  local F = FZm()
  if F and t.vf then F.voiceStop(t.vf) end
  if F and t.detached and F.forget then F.forget(t.id) end
  local b = DS.backend
  if not b then return end
  if t.level == "B" or t.detached then pcall(b.unhide, t.chr) else pcall(b.disguise, t.chr, 0) end
end

function DS.stop(idx)
  local ep = DS.eps[idx]
  if not ep then return end
  for _, t in ipairs(ep.targets) do release(t) end
  DS.eps[idx] = nil
end

function DS.clear()
  for idx in pairs(DS.eps) do DS.stop(idx) end
end

-- Nivel B -> nivel A (camara 3D, el titere no aparece o se cayo): el jugador queda con piel podrida lo que falta del episodio.
function DS.fallback(ep, t, now)
  local F = FZm()
  if F and t.vf then F.voiceStop(t.vf) end                              -- (188) la voz de zombi es del nivel B
  pcall(DS.backend.unhide, t.chr)
  t.level, t.id = "A", nil
  DS.fallbacks = DS.fallbacks + 1
  return levelA(t, math.max(1000, ep.untilMs - now))
end

-- Lo que hace el jugador de verdad, en variables del grupo de acciones "zombie" (solo las que cambian). Quieto, camina (caminata rapida de
-- corredor: el jugador camina mas rapido que un zombi comun), agachado (caminata comun) o corre (corredor, shouldSprint) y golpea (bAttack).
-- (174b) Camina o corre solo si se desplazo de verdad: despues de un golpe melee el juego puede seguir diciendo que se mueve (postura de
-- combate) y el titere quedaba caminando en el lugar con los brazos levantados. El desplazamiento se sostiene MoveHoldMs para que no
-- parpadee entre ticks (los jugadores remotos se actualizan de a saltos).
-- (188) player = el que lo ve: con el disfrazado quieto y cerca, gira hacia el y levanta los brazos (DS.approach).
function DS.animate(t, now, dt, player, ep)
  local c = C()
  local chr = t.chr
  local x, y = chr:getX(), chr:getY()
  local speed = 0
  if t.lastX and dt > 0 then speed = math.sqrt((x - t.lastX) ^ 2 + (y - t.lastY) ^ 2) / dt end
  t.lastX, t.lastY = x, y
  local says, saysRun, sneaking, attacking = false, false, false, false
  local known = pcall(function()
    says = chr:isPlayerMoving()
    saysRun = chr:isRunning() or chr:isSprinting()
    sneaking = chr:isSneaking()
    attacking = chr:isAttacking()
  end)
  local hold = c.MoveHoldMs or 300
  if speed > (c.MoveSpeed or 0.3) or (says and speed > (c.MinSpeed or 0.05)) then t.moveUntil = now + hold end
  -- (187) Corre solo si el juego dice que corre o esprinta (en multijugador viaja por la red: NetworkPlayerVariables, verificado con javap).
  -- Antes tambien corria por velocidad medida (RunSpeed): entre un tick y otro la medida da picos y caminando rapido a veces corria.
  -- La velocidad queda solo de respaldo si no se pudo preguntar.
  if (known and saysRun and speed > (c.MoveSpeed or 0.3)) or (not known and speed > (c.RunSpeed or 3.2)) then t.runUntil = now + hold end
  local moving = now < (t.moveUntil or 0)
  local running = moving and now < (t.runUntil or 0)
  local arms = false
  if player then arms = DS.approach(ep, t, player, now, not moving and not attacking) end
  -- (188) Brazos arriba quieto = la postura de embestida del juego (face-target: Zombie_Idle_Lunge), que pide bAttack sin isFacingTarget;
  -- es la misma en la que ya quedaba al golpear. Sin golpe ni brazos, isFacingTarget la deja volver a idle (antes podia quedar trabado ahi).
  local up = attacking or arms
  local want = {
    bMoving = moving and "true" or "false",
    zombieWalkType = (running or not sneaking) and "sprint" .. ((t.rot - 1) % 5 + 1) or "1",
    shouldSprint = running and "true" or "false",
    bAttack = up and "true" or "false",
    isFacingTarget = up and "false" or "true",
  }
  local b = SandevistanFakeZombies and SandevistanFakeZombies.backend
  if not b then return end
  for k, v in pairs(want) do
    if t.anim[k] ~= v then
      t.anim[k] = v
      pcall(b.var, t.id, k, v)
    end
  end
end

-- (188) La voz de zombi del disfrazado (la del zombi falso: un evento continuo con su estado), solo para este cliente. t.vf hace de zombi
-- falso para FakeZombies (posicion, sexo y la voz).
function DS.voice(t, player, now, state)
  local A = C().Approach
  local F = FZm()
  if not (A and A.Voice and F and F.voiceUpdate) then return end
  local vf = t.vf
  if not vf then
    local female = false
    pcall(function() female = t.chr:isFemale() == true end)
    vf = { female = female, sprint = false }
    t.vf = vf
  end
  vf.x, vf.y, vf.z = t.chr:getX(), t.chr:getY(), t.chr:getZ()
  F.voiceUpdate(player, vf, now, state)
end

-- (188) Se puede soltar: episodio de jugadores, con el jar que lo sabe hacer, los zombis falsos andando y (PvPOnly) sin PvP.
function DS.canDetach(ep, player)
  local A = C().Approach
  if not (A and (A.DetachChance or 0) > 0) or not ep or ep.kind ~= "players" then return false end
  if not (DS.backend and DS.backend.canDetach and DS.backend.canDetach()) then return false end
  if A.PvPOnly ~= false and not DS.pvpOff() then return false end
  local F = FZm()
  return F ~= nil and F.adopt ~= nil and ep.fzOk == true
end

-- (188) El disfrazado actua como zombi con el que lo ve: quieto (still) y a TurnDist casillas gira hacia el; a ArmsDist levanta los brazos y,
-- la primera vez de cada acercamiento, tira DetachChance de soltarse (DS.detach, en DS.update). Devuelve si van los brazos arriba.
function DS.approach(ep, t, player, now, still)
  local A = C().Approach
  if not (A and A.Enabled) or not t.id then return false end
  local b = DS.backend
  local F = FZm()
  if t.chr == player then                                               -- prueba sobre uno mismo: solo la voz, quieta
    if F and F.ZSTATE then DS.voice(t, player, now, F.ZSTATE.Idle) end
    return false
  end
  local dist = math.sqrt((t.chr:getX() - player:getX()) ^ 2 + (t.chr:getY() - player:getY()) ^ 2)
  local near = still and dist <= (A.TurnDist or 5)
  local arms = near and dist <= (A.ArmsDist or 2.5)
  if near ~= (t.facing == true) then
    t.facing = near
    if near then DS.faces = DS.faces + 1 end
  end
  -- la posicion del que lo ve cambia: se manda en cada paso mientras mira (el jar gira de a poco hacia ese punto)
  if b and b.face and (near or t.faceSent) then
    pcall(b.face, t.id, near, player:getX(), player:getY(), A.TurnDegPerSec or 90)
    t.faceSent = near
  end
  if arms ~= (t.arms == true) then
    t.arms = arms
    if arms then DS.arms = DS.arms + 1 end
  end
  if dist > (A.TurnDist or 5) then t.rolled = false end
  if arms and not t.rolled then
    t.rolled = true
    if DS.canDetach(ep, player) and ZombRandFloat(0, 1) < (A.DetachChance or 0) then t.wantDetach = true end
  end
  local Z = F and F.ZSTATE
  if Z then DS.voice(t, player, now, arms and Z.LockTarget or (near and Z.SearchTarget or Z.Idle)) end
  return arms
end

-- (188) El titere deja al disfrazado y va hacia el que lo ve como un zombi falso (FakeZombies lo maneja). El real sigue oculto hasta que el
-- zombi falso se va (te toca, le pegas, se choca o vence) y ahi vuelve, donde este; su disfraz termina con eso.
-- opts (Debug): holdMs (cuanto sigue oculto el real), lifeMs (cuanto vive el zombi falso) y x, y (donde empieza).
function DS.detach(ep, t, player, now, opts)
  local A = C().Approach
  local F = FZm()
  opts = opts or {}
  local hold = opts.holdMs or A.HoldMs or 6000
  local ok, id = pcall(DS.backend.detach, t.chr, hold)
  if not ok or type(id) ~= "number" or id < 0 then
    if not ok then DS.errors = DS.errors + 1; S.warnOnce("disguiseDetach", "disfraz: soltar: " .. tostring(id)) end
    return false
  end
  local voice = t.vf and t.vf.voice
  if t.vf then t.vf.voice = nil end
  local female = false
  pcall(function() female = t.chr:isFemale() == true end)
  local fade = (CFG.Psychosis.FakeZombies.FadeMs or 350) + 300
  local f = F.adopt(player, id, opts.x or t.chr:getX(), opts.y or t.chr:getY(), t.chr:getZ(), female, voice,
    { lifeMs = opts.lifeMs or math.max(1000, hold - fade), onGone = function() DS.reveal(t) end })
  if not f then pcall(DS.backend.unhide, t.chr); return false end
  t.detached, t.level = true, "D"
  DS.detaches = DS.detaches + 1
  S.log("disfraz: el zombi se suelta del jugador y va hacia vos")
  return true
end

-- (188) Se fue el zombi falso que era el disfrazado: vuelve el real en el mismo paso (sin cuadro vacio) y su disfraz termina.
function DS.reveal(t)
  if t.revealed then return end
  t.revealed = true
  if DS.backend then pcall(DS.backend.unhide, t.chr) end
  DS.reveals = DS.reveals + 1
end

-- La pista: el disfrazado salta un instante a como es (nivel A: se saca el disfraz TellMs y se vuelve a poner; nivel B: colores corridos).
-- Con menos destellos: nivel A el salto dura TellStretch veces mas; nivel B un bajon suave de la opacidad.
function DS.tell(ep, t, now, dt)
  local c = C()
  local pb = SandevistanFakeZombies and SandevistanFakeZombies.backend
  if t.tellUntil then
    if now < t.tellUntil then
      if t.level == "B" and t.tellCalm and pb then
        local u = (now - t.tellStart) / math.max(1, t.tellUntil - t.tellStart)
        pcall(pb.look, t.id, 1 - 0.6 * math.sin(math.pi * u), 1, 1, 1)
      end
      return
    end
    t.tellUntil = nil
    if t.level == "A" then levelA(t, math.max(1000, ep.untilMs - now))
    elseif pb then pcall(pb.glitch, t.id, 0); pcall(pb.look, t.id, 1, 1, 1, 1) end
    return
  end
  if (c.TellChance or 0) <= 0 or ZombRandFloat(0, 1) >= c.TellChance * dt then return end
  t.tellCalm = S.lessFlashes()
  t.tellStart = now
  t.tellUntil = now + (c.TellMs or 160) * (t.tellCalm and (CFG.LessFlashes.TellStretch or 4) or 1)
  DS.tells = DS.tells + 1
  local pl = getSpecificPlayer and getSpecificPlayer(ep.idx) or nil           -- (179) notaste el cambio
  if pl then S.markSeen(pl, "disguise") end
  if t.level == "A" then pcall(DS.backend.disguise, t.chr, 0)
  elseif pb and not t.tellCalm then pcall(pb.glitch, t.id, 0.7) end
end

-- Un paso de un disfrazado. Devuelve false cuando hay que soltarlo (murio, se fue lejos o de otro piso).
function DS.update(ep, t, player, now, dt)
  local c = C()
  if t.detached then return not t.revealed end                        -- (188) lo maneja FakeZombies hasta que se va
  local gone = true
  pcall(function()
    local far = (c.Range * 1.5) ^ 2
    gone = t.chr:isDead() or math.floor(t.chr:getZ()) ~= math.floor(player:getZ())
      or (t.chr:getX() - player:getX()) ^ 2 + (t.chr:getY() - player:getY()) ^ 2 > far
  end)
  if gone then return false end
  if t.level == "B" then
    if not DS.canHide() then return DS.fallback(ep, t, now) end
    local ok, hidden = pcall(DS.backend.hidden, t.chr)
    if ok and hidden == true then t.seenMs = now
    elseif now - (t.seenMs or t.bornMs) > (c.LevelBGraceMs or 1500) then return DS.fallback(ep, t, now) end
    DS.animate(t, now, dt, player, ep)
    if t.wantDetach then
      t.wantDetach = nil
      if DS.detach(ep, t, player, now) then return true end
    end
  end
  DS.tell(ep, t, now, dt)
  return true
end

-- Desde Psychosis.tick (dt en segundos de juego; 0 en pausa).
function DS.tick(player, d, st, now, dt)
  local idx = player:getPlayerNum()
  local ep = DS.eps[idx]
  local active = DS.active(player, d)
  if ep and not active and not (ep.forced and DS.ready()) then DS.stop(idx); ep = nil end
  if ep then
    if now >= ep.untilMs then DS.stop(idx); return end
    if dt <= 0 then return end
    local F = FZm()
    ep.fzOk = F ~= nil and F.active ~= nil and F.active(player, d) == true      -- (188) para soltarse hacen falta los zombis falsos
    for i = #ep.targets, 1, -1 do
      local t = ep.targets[i]
      local ok, keep = pcall(DS.update, ep, t, player, now, dt)
      if not ok then DS.errors = DS.errors + 1; S.warnOnce("disguiseUpdate", "disfraz: " .. tostring(keep)); keep = false end
      if not keep then
        release(t)
        table.remove(ep.targets, i)
      end
    end
    if #ep.targets == 0 then DS.eps[idx] = nil end
    return
  end
  if not active or dt <= 0 then return end
  local c = C()
  if not st.nextDisguiseMs then st.nextDisguiseMs = now + c.FirstDelaySeconds * 1000 end
  if now < st.nextDisguiseMs then return end
  local every = lerp(c.EverySeconds[2], c.EverySeconds[1], P.intensity(d)) / math.max(0.2, P.freqMult(d, st, "Disguise"))
  -- sin nadie a la vista se reintenta pronto (el disfraz necesita a alguien)
  if DS.start(player) then st.nextDisguiseMs = now + every * 1000 * rnd(0.6, 1.4) else st.nextDisguiseMs = now + (c.RetrySeconds or 30) * 1000 end
end

-- (Debug) Nivel B sobre uno mismo, para probarlo en una partida de un jugador: tu personaje no se dibuja y en su lugar va el zombi que te sigue.
function DS.testSelf(player, ms)
  local idx = player:getPlayerNum()
  if DS.eps[idx] then DS.stop(idx) end
  if not DS.canHide() then return false end
  local now = S.realMs()
  local ep = { idx = idx, kind = "players", bornMs = now, untilMs = now + (ms or 20000), forced = true, targets = {} }
  local t = { chr = player, rot = 2, mode = 3, level = "A", bornMs = now }
  if not levelB(ep, t) then return false end
  ep.targets[1] = t
  DS.eps[idx] = ep
  DS.levelB = DS.levelB + 1
  return true
end

-- (188) (Debug) Para probarlo en una partida de un jugador: un titere con tu ropa (el del nivel B sobre vos) se suelta enseguida y viene hacia
-- vos como zombi falso desde 4 a 6 casillas. Vos seguis viendote (no se te oculta). Necesita la cyberpsicosis activa (los zombis falsos).
function DS.testDetach(player)
  local F = FZm()
  local b = DS.backend
  if not (DS.canHide() and b and b.canDetach and b.canDetach()) then return false, "sin el jar 5 de SandevistanPsychosis (o camara 3D sin LevelB3D)" end
  if not (F and F.adopt and F.ready()) then return false, "sin titeres" end
  local d = S.data and S.data(player)
  if not (d and F.active(player, d)) then return false, "hace falta la cyberpsicosis activa (Debug: Etapa 3)" end
  local x, y
  for _ = 1, 6 do
    local px, py = P.pickPos(player, 4, 6, false)
    if px and F.pathClear(px, py, player:getX(), player:getY(), math.floor(player:getZ())) then x, y = px, py; break end
  end
  if not x then return false, "no hubo lugar con camino recto hasta vos (proba en un lugar abierto)" end
  local idx = player:getPlayerNum()
  if DS.eps[idx] then DS.stop(idx) end
  local now = S.realMs()
  local ep = { idx = idx, kind = "players", bornMs = now, untilMs = now + 30000, forced = true, targets = {} }
  local t = { chr = player, rot = 2, mode = 3, level = "A", bornMs = now }
  if not levelB(ep, t) then return false, "el titere no nacio" end
  ep.targets[1] = t
  DS.eps[idx] = ep
  if not DS.detach(ep, t, player, now, { holdMs = 0, lifeMs = 20000, x = x, y = y }) then DS.stop(idx); return false, "no se pudo soltar" end
  return true
end

function DS.statusLine()
  local live = 0
  for _, ep in pairs(DS.eps) do live = live + #ep.targets end
  return string.format("disfraz: %d disfrazados ahora | %d episodios (%d zombis, %d jugadores), nivel B %d, nivel A %d, B->A %d, saltos %d, "
    .. "sin nadie %d, errores %d | (188) giran %d, brazos %d, soltados %d, devueltos %d | nivel B %s | jugadores->zombis %s", live, DS.episodes,
    DS.zombieEps, DS.playerEps, DS.levelB, DS.levelA, DS.fallbacks, DS.tells, DS.noTarget, DS.errors, DS.faces, DS.arms, DS.detaches, DS.reveals, DS.canHide() and "disponible" or "no disponible (sin el jar, o camara 3D sin LevelB3D)",
    DS.playersAllowed() and "permitido" or "no (un jugador, PvP o la opcion)")
end

Events.OnPlayerDeath.Add(S.safe("Disguise.OnPlayerDeath", function(player) DS.stop(player:getPlayerNum()) end))

return DS
