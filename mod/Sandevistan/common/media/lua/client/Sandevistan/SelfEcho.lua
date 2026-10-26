-- Sandevistan / SelfEcho (cliente, 0.7 (175)): el eco de tus propios ruidos (27 §6). Con la carga neuronal alta, un ruido que hiciste vos se
-- repite 5 a 20 s despues desde otra direccion, casi siempre a tu espalda: tu golpe, tu disparo (lejos), la puerta que acabas de abrir o cerrar,
-- o tus pasos corriendo detras tuyo. Es solo sonido en este cliente: no atrae zombis, no tiene fuente visible y nadie mas lo oye.
-- Se anotan los ruidos que el mod ve: OnWeaponSwing (el sonido del arma: en las de fuego es el disparo), las puertas que cambian de estado al lado
-- tuyo (IsoDoor: prefijo + "Open"/"Close", como IsoDoor.playDoorSound) y las corridas de RunSeconds o mas (pasos de persona con piso y velocidad).
-- Respeta las alucinaciones de audio (PsychosisAudio) y la intensidad (S.symptomMultiplier). Etapa 1 suave, etapa 2 y 3 mas seguido.
require "Sandevistan/Core"
require "Sandevistan/Psychosis"

local CFG = SandevistanConfig
local S = Sandevistan
local P = SandevistanPsychosis

SandevistanSelfEcho = { pending = {}, last = {}, doors = {}, recorded = 0, played = 0, skipped = 0 }
local SE = SandevistanSelfEcho

local function C() return CFG.Psychosis.SelfEcho end
local function lerp(a, b, t) return a + (b - a) * t end
local function rnd(a, b) return lerp(a, b, ZombRandFloat(0, 1)) end

function SE.active(player, d)
  local c = C()
  if not (c and c.Enabled) or not P.audioOn() then return false end
  if player:isAsleep() then return false end
  return P.stage(d) >= (c.MinStage or 1)
end

-- Chance de que un ruido tenga eco: etapa 1 la baja; etapa 2 y 3 de la baja a la alta con la CN; por la intensidad y los paliativos.
function SE.chance(d, st)
  local c = C()
  local ch = P.stage(d) >= 2 and lerp(c.Chance[1], c.Chance[2], P.intensity(d)) or c.Chance[1]
  return math.min(c.MaxChance or 0.9, ch * P.freqMult(d, st, "SelfEcho") * S.halluMultiplier(d))       -- (180) Filtro                 -- (176) con la presión
end

-- (175b) Lo que se escribe en la consola: los primeros LogFirst ruidos anotados y todos los ecos.
local function log(msg) S.log("eco: " .. msg) end

-- Un ruido propio. kind = "swing" (name = el sonido del arma; firearm = disparo; hit = el impacto del arma melee), "door" (name) o "run".
-- Lo guarda como el ultimo (para el Debug) y, con la chance, agenda el eco.
function SE.record(player, kind, name, firearm, hit)
  local idx = player:getPlayerNum()
  local n = { kind = kind, name = name, firearm = firearm == true, hit = hit }
  SE.last[idx] = n
  SE.recorded = SE.recorded + 1
  local d = S.data(player)
  local c = C()
  local function done(what)
    if SE.recorded <= (c.LogFirst or 0) then log(string.format("anotado %s %s: %s", kind, tostring(SE.echoName(n) or "pasos"), what)) end
  end
  if not SE.active(player, d) then done("sin eco (apagado, dormido o etapa " .. P.stage(d) .. ")"); return false end
  local now = S.realMs()
  local list = SE.pending[idx] or {}
  SE.pending[idx] = list
  SE.cooldownUntil = SE.cooldownUntil or {}
  if #list >= (c.MaxPending or 2) or now < (SE.cooldownUntil[idx] or 0) then SE.skipped = SE.skipped + 1; done("salteado (tope o pausa)"); return false end
  local ch = SE.chance(d, P.st(player))
  if ZombRandFloat(0, 1) >= ch then done(string.format("sin suerte (chance %.2f)", ch)); return false end
  local at = now + rnd(c.DelaySeconds[1], c.DelaySeconds[2]) * 1000
  list[#list + 1] = { at = at, noise = n }
  SE.cooldownUntil[idx] = now + (c.CooldownSeconds or 30) * 1000
  done(string.format("eco en %.0f s", (at - now) / 1000))
  return true
end

-- El sonido que suena en el eco: en un golpe melee, el impacto si existe (el zumbido del swing casi no se oye); si no, el del ruido.
function SE.echoName(n)
  if n.kind == "swing" and not n.firearm and n.hit and P.soundKnown(n.hit) then return n.hit end
  return n.name
end

-- Suena el eco de n: golpes y puertas cerca a tu espalda, el disparo lejos, la corrida como pasos que se acercan por detras.
function SE.play(player, n, now, near)
  local c = C()
  if n.kind == "run" then
    local x, y, z = P.pickPos(player, c.Dist[1] + 2, c.Dist[2] + 2, true)
    log("corrida: pasos desde atras")
    local steps = ZombRand(c.RunSteps[1], c.RunSteps[2] + 1)
    SE.running = SE.running or {}
    SE.running[player:getPlayerNum()] = { x = x, y = y, z = z, left = steps, nextMs = now }
    SE.played = SE.played + 1
    return true
  end
  local name = SE.echoName(n)
  if not name or P.soundKnown(name) == false then log(tostring(name) .. ": el juego no conoce ese sonido"); return false end
  local far = n.firearm and not near
  local r = near and (c.NearDist or { 2, 3 }) or (far and c.FarDist or c.Dist)
  local x, y, z = P.pickPos(player, r[1], r[2], not far)
  local id = P.playAt(name, x, y, z, (far and c.FarVolume or c.Volume) * (CFG.Psychosis.Audio.Volume or 1))
  local dist = math.sqrt((x - player:getX()) ^ 2 + (y - player:getY()) ^ 2)
  log(string.format("%s a %.1f casillas: %s", name, dist, id and ("suena (id " .. tostring(id) .. ")") or "no sono (sin emisor)"))
  if id then SE.played = SE.played + 1 end
  return id ~= nil
end

-- Pasos de la corrida: cada RunStepMs uno, acercandose al jugador.
function SE.runTick(player, now)
  local r = SE.running and SE.running[player:getPlayerNum()]
  if not r or now < r.nextMs then return end
  local c = C()
  local px, py = player:getX(), player:getY()
  local dx, dy = px - r.x, py - r.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist > 1.5 then r.x, r.y = r.x + dx / dist * 0.9, r.y + dy / dist * 0.9 end
  local ok, id = pcall(P.play, player, "footstepHuman", r.x, r.y, r.z, c.StepVolume or 0.5)
  if ok and P.setParams then
    P.setParams(id, { FootstepMaterial = P.footstepMaterial(r.x, r.y, r.z), CharacterMovementSpeed = 4 })
  end
  r.left = r.left - 1
  r.nextMs = now + (c.RunStepMs or 330)
  if r.left <= 0 then SE.running[player:getPlayerNum()] = nil end
end

-- Puertas al lado del jugador (RefreshMs): si una cambio de estado, la toco el (o alguien pegado a el: da igual, el eco es de lo que oyo).
function SE.doorTick(player, now)
  local c = C()
  local idx = player:getPlayerNum()
  local st = SE.doors[idx] or { nextMs = 0, seen = {} }
  SE.doors[idx] = st
  if now < st.nextMs then return end
  st.nextMs = now + (c.DoorRefreshMs or 250)
  local cell = getCell()
  if not cell then return end
  local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
  local seen = {}
  for x = px - 1, px + 1 do
    for y = py - 1, py + 1 do
      local sq = cell:getGridSquare(x, y, pz)
      local objs = sq and sq:getObjects()
      for i = 0, (objs and objs:size() or 0) - 1 do
        local o = objs:get(i)
        if o and instanceof(o, "IsoDoor") then
          local open = o:IsOpen()
          local before = st.seen[o]
          if before ~= nil and before ~= open then
            local prefix = o:getSoundPrefix()
            if prefix then SE.record(player, "door", prefix .. (open and "Open" or "Close")) end
          end
          seen[o] = open
        end
      end
    end
  end
  st.seen = seen
end

-- Corridas: RunSeconds seguidos corriendo o esprintando cuentan como un ruido (uno por corrida).
function SE.runRecord(player, now)
  local idx = player:getPlayerNum()
  local running = false
  pcall(function() running = player:isRunning() or player:isSprinting() end)
  SE.runSince = SE.runSince or {}
  if not running then SE.runSince[idx] = nil; return end
  local since = SE.runSince[idx]
  if not since then SE.runSince[idx] = now; return end
  if since > 0 and now - since >= (C().RunSeconds or 2) * 1000 then
    SE.runSince[idx] = -1                                -- ya conto esta corrida
    SE.record(player, "run")
  end
end

-- Desde Psychosis.tick.
function SE.tick(player, d, st, now, dt)
  local idx = player:getPlayerNum()
  if dt <= 0 then return end
  local active = SE.active(player, d)
  if not active then
    SE.pending[idx] = nil
    if SE.running then SE.running[idx] = nil end
  end
  if not active then
    SE.runSince = SE.runSince or {}
    SE.runSince[idx] = nil
    SE.doors[idx] = nil                          -- al volver, las puertas se miran de cero (no cuenta lo que cambio mientras tanto)
    return
  end
  SE.doorTick(player, now)                       -- (194) puertas y corridas solo con el eco activo (antes en cada tick, con o sin implante)
  SE.runRecord(player, now)
  SE.runTick(player, now)
  local list = SE.pending[idx]
  if not list then return end
  for i = #list, 1, -1 do
    if now >= list[i].at then
      local e = table.remove(list, i)
      pcall(SE.play, player, e.noise, now)
    end
  end
end

-- (Debug) El eco de tu ultimo ruido, ya (sin chance ni etapa).
function SE.echoNow(player)
  local n = SE.last[player:getPlayerNum()]
  if not n then return false end
  return SE.play(player, n, S.realMs(), true)
end

function SE.statusLine()
  local n = 0
  for _, l in pairs(SE.pending) do n = n + #l end
  return string.format("eco de tus ruidos: %d anotados, %d ecos sonados, %d esperando, %d salteados (tope o pausa)", SE.recorded, SE.played, n, SE.skipped)
end

-- Golpes y disparos del jugador local: el sonido del arma (HandWeapon.getSwingSound; en las de fuego, el disparo).
Events.OnWeaponSwing.Add(S.safe("SelfEcho.OnWeaponSwing", function(chr, weapon)
  if not (chr and weapon and instanceof(chr, "IsoPlayer") and chr:isLocalPlayer()) then return end
  local name, firearm, hit = nil, false, nil
  pcall(function()
    name = weapon:getSwingSound()
    firearm = weapon:isRanged()
    if not firearm then hit = weapon:getZombieHitSound() end   -- (175b) el HitSound del arma (HandWeapon.getZombieHitSound devuelve hitSound)
  end)
  if hit == "" then hit = nil end
  if name and name ~= "" then SE.record(chr, "swing", name, firearm, hit) end
end))

Events.OnPlayerDeath.Add(S.safe("SelfEcho.OnPlayerDeath", function(player)
  local idx = player:getPlayerNum()
  SE.pending[idx] = nil
  if SE.running then SE.running[idx] = nil end
end))

return SE
