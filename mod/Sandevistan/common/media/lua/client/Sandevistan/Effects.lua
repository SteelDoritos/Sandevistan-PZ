-- Sandevistan / Effects: todo lo que toca stats, cuerpo o animación del personaje.
-- Cada llamada a API no confirmada va protegida con S.try para que un fallo no rompa el mod.
require "Sandevistan/Core"
require "Sandevistan/Kerenzikov"
require "Sandevistan/Net"

local CFG = SandevistanConfig
local S = Sandevistan

SandevistanEffects = {}
local E = SandevistanEffects

---------------------------------------------------------------------------
-- Stats (B42.20 usa CharacterStat; fallback a getters antiguos)
---------------------------------------------------------------------------
function E.getStat(player, name)
  local stats = player:getStats()
  if CharacterStat and CharacterStat[name] then
    local ok, v = pcall(stats.get, stats, CharacterStat[name])
    if ok and v then return v end
  end
  local legacy = { ENDURANCE = "getEndurance", PANIC = "getPanic", STRESS = "getStress",
                   FATIGUE = "getFatigue", PAIN = "getPain" }
  local m = legacy[name]
  if m and stats[m] then return stats[m](stats) end
  return 0
end

-- (114) En multijugador el cambio tambien se le avisa al servidor (SandevistanNet.queueStat): si no, el servidor lo pisa al reenviar sus stats.
function E.setStat(player, name, value)
  local stats = player:getStats()
  if CharacterStat and CharacterStat[name] then
    local stat = CharacterStat[name]
    local N = SandevistanNet
    local before = (N and N.enabled()) and E.getStat(player, name) or nil
    local ok = pcall(function()
      stats:set(stat, stat:clamp(value))
    end)
    if ok then
      if before ~= nil then N.queueStat(player, name, before, E.getStat(player, name)) end
      return true
    end
  end
  local legacy = { ENDURANCE = "setEndurance", PANIC = "setPanic", STRESS = "setStress",
                   FATIGUE = "setFatigue", PAIN = "setPain" }
  local m = legacy[name]
  if m and stats[m] then stats[m](stats, value); return true end
  S.warnOnce("stat_" .. name, "no se pudo setear " .. name)
  return false
end

function E.addStat(player, name, delta)
  return E.setStat(player, name, E.getStat(player, name) + delta)
end

function E.getEndurance(player) return E.getStat(player, "ENDURANCE") end
function E.setEndurance(player, v) return E.setStat(player, "ENDURANCE", math.max(0, math.min(1, v))) end

function E.moodleLevel(player, typeName)
  if not MoodleType or not MoodleType[typeName] then return 0 end
  local ok, lvl = pcall(function() return player:getMoodles():getMoodleLevel(MoodleType[typeName]) end)
  return ok and lvl or 0
end

function E.isHeavilyEncumbered(player)
  return E.moodleLevel(player, "HEAVY_LOAD") >= 3
end

-- (135) Rasgos que cambian la inmunodepresion (Core.immunoDecayRate, Core.immunoStrength).
function E.immunoTraits(player)
  local t = {}
  local CT = rawget(_G, "CharacterTrait")
  local function has(name) local ok, v = pcall(function() return CT and CT[name] and player:hasTrait(CT[name]) end); return ok and v == true end
  t.resilient, t.prone, t.fastHealer, t.slowHealer = has("RESILIENT"), has("PRONE_TO_ILLNESS"), has("FAST_HEALER"), has("SLOW_HEALER")
  return t
end

-- (135) Por que el cuerpo esta peleando algo (la inmunodepresion baja mas lento): "wound" (herida infectada), "cold" (resfrio) o "sick" (moodle de
-- malestar, comida o cadaveres, en SickMoodle o mas; sin el moodle, los stats en SickStat). nil si nada. El hambre y el cansancio no cuentan.
-- Segundo valor (solo con "wound"): si el jugador ya lo puede saber. El panel de Salud del juego (ISHealthPanel) muestra "Infectada" solo sin venda y con
-- Primeros Auxilios > 8 o el nivel de infeccion x 10 >= 2,5 - Primeros Auxilios (con 0: desde 0,25); antes, el cuerpo pelea igual pero la pestaña no la nombra.
function E.infectionVisible(player, bp)
  local doc = 0
  pcall(function() doc = player:getPerkLevel(Perks.Doctor) or 0 end)
  local ok, vis = pcall(function()
    return bp:isInfectedWound() and not bp:bandaged() and (doc > 8 or bp:getWoundInfectionLevel() * 10 >= 2.5 - doc)
  end)
  return ok and vis == true
end

function E.sickReason(player)
  local C = CFG.Immunosuppressant.Immunodepression
  local bd = nil
  pcall(function() bd = player:getBodyDamage() end)
  if bd then
    local infected, visible = false, false
    pcall(function()
      local parts = bd:getBodyParts()
      for i = 0, parts:size() - 1 do
        local bp = parts:get(i)
        if bp:isInfectedWound() then
          infected = true
          if E.infectionVisible(player, bp) then visible = true; break end
        end
      end
    end)
    if infected and visible then return "wound", true end
    local cold = false
    pcall(function() cold = bd:isHasACold() == true end)
    if cold then return "cold" end
    if infected then
      if E.moodleLevel(player, "SICK") >= C.SickMoodle then return "sick" end        -- algo que se ve antes que la infeccion escondida
      return "wound", false
    end
  end
  if MoodleType and MoodleType.SICK then
    if E.moodleLevel(player, "SICK") >= C.SickMoodle then return "sick" end
  else                                                     -- sin el moodle: los stats como fraccion de su tope (FOOD_SICKNESS va de 0 a 100, SICKNESS de 0 a 1)
    for _, n in ipairs({ "FOOD_SICKNESS", "SICKNESS" }) do
      local max = 100
      pcall(function() max = CharacterStat[n]:clamp(1e9) end)
      if max > 0 and E.getStat(player, n) / max * 100 >= C.SickStat then return "sick" end
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Feedback
---------------------------------------------------------------------------
function E.say(player, text)
  if not text then return end
  S.try("Say", function() player:Say(text) end)
end

function E.halo(player, text, r, g, b)
  if HaloTextHelper and HaloTextHelper.addText then
    S.try("halo", function() HaloTextHelper.addText(player, text, "", r or 255, g or 255, b or 255) end)
  else
    E.say(player, text)
  end
end

-- Sonidos del mod (scripts/Sandevistan_sounds.txt; algunos son WAV sintéticos de tools/gen_sounds.py, a reemplazar por archivos reales con el mismo nombre); si el motor no los encuentra, no pasa nada.
E.soundLog = {}   -- nombre -> resultado de la última reproducción (lo muestra el diagnóstico de sonidos)
E.soundUntil = {}   -- "<jugador>:<nombre>" -> ms reales hasta que termina la reproducción anterior
-- vol (opcional, 0..1): multiplica el volumen de esta reproducción (solo si el emisor lo permite; v0.1.29: antes se ignoraba).
-- Devuelve el id del emisor (numero) o, en el respaldo de getSoundManager():PlaySound, un FMODAudio (se corta con :stop(); ver M.stopDoseSound).
-- localOnly: solo lo oye este cliente (E.privateSound). (187) Hasta la 186 iba por getSoundManager():PlaySound, que tambien se oia en los demas.
function E.sound(player, name, vol, localOnly)
  if not (CFG.Sound and CFG.Sound.Enabled) then return end
  -- sonidos que no se apilan: mientras el anterior no terminó no se lanza otro (ej.: spamear el error de activación)
  local hold = CFG.Sound.NoOverlapSeconds and CFG.Sound.NoOverlapSeconds[name]
  if hold then
    local key, now = tostring(player:getPlayerNum()) .. ":" .. name, S.realMs()
    if now < (E.soundUntil[key] or 0) then return nil end
    E.soundUntil[key] = now + hold * 1000
  end
  if localOnly then return E.privateSound(player, name, vol) end
  local id, loaded = nil, nil
  S.try("soundScript", function()
    if getScriptManager and getScriptManager().getGameSound then loaded = getScriptManager():getGameSound(name) ~= nil end
  end)
  if loaded == false then S.warnOnce("snd_" .. name, "sonido '" .. name .. "' no está cargado (script de sonidos)") end
  S.try("sound", function()
    local em = player:getEmitter()
    id = em:playSound(name)
    if id and id ~= 0 and vol and vol < 1 and em.setVolume ~= nil then em:setVolume(id, vol) end
  end)
  if (id == nil or id == 0) and getSoundManager then          -- respaldo: reproducción no espacial
    S.try("sound2", function() id = getSoundManager():PlaySound(name, false, 1.0) end)
  end
  E.soundLog[name] = "script=" .. tostring(loaded) .. " id=" .. tostring(id)
  return id
end

-- (187) Sonidos que solo oye este cliente (la cyberpsicosis, la escena de instalacion). En multijugador, playSound de un emisor del juego le
-- avisa al servidor y lo oyen los que estan cerca: el del personaje como PlaySound del jugador, el de un emisor libre (y el de
-- getSoundManager():PlaySound, que usa uno) como PlayWorldSound en ese lugar. playSoundImpl suena igual y no avisa a nadie (verificado con javap
-- en 42.21: playSound(nombre) = aviso a la red + playSoundImpl(nombre, nil); vanilla lo usa asi en ISAddItemInRecipe).
-- Emisor libre en (x, y, z): devuelve id, emisor. playSoundImpl(nombre, false, nil): la unica de tres argumentos (las de dos son ambiguas).
function E.privateAt(name, x, y, z, vol)
  local id, em = nil, nil
  S.try("soundPrivateAt", function()
    em = getWorld():getFreeEmitter(x, y, z)
    if em then id = em:playSoundImpl(name, false, nil) end
  end)
  if id and id ~= 0 and vol and em and em.setVolume ~= nil then pcall(function() em:setVolume(id, vol) end) end
  if id == 0 then id = nil end
  return id, em
end

-- En el emisor del personaje (se mueve con el). Con el personaje invisible (modo admin) ese emisor no suena: va un emisor libre en su lugar.
-- Deja el emisor usado en E.lastEmitter (para el tono y los parametros de FMOD).
function E.privateSound(player, name, vol)
  local id, em = nil, nil
  S.try("soundPrivate", function()
    em = player:getEmitter()
    id = em:playSoundImpl(name, nil)
  end)
  if id and id ~= 0 then
    if vol and vol < 1 and em.setVolume ~= nil then pcall(function() em:setVolume(id, vol) end) end
  else
    id, em = E.privateAt(name, player:getX(), player:getY(), player:getZ(), vol)
  end
  E.lastEmitter = em
  E.soundLog[name] = "privado id=" .. tostring(id)
  return id
end

-- Pruebas atléticas (vallas, ventanas, paredes, choques): ver client/Sandevistan/Athletic.lua.
-- Devuelve las palancas de las pruebas atléticas a como estaban (al apagar el implante, colapsar o morir).
function E.athleticRelease(player, sess)
  local A = rawget(_G, "SandevistanAthletic")
  if A ~= nil then A.release(sess) end
end

function E.athleticGuard(player, sess, d)
  local A = rawget(_G, "SandevistanAthletic")
  return A ~= nil and A.guard(player, sess, d) or false
end

function E.worldNoise(player, radius)
  if not radius or radius <= 0 then return end
  S.try("addSound", function()
    addSound(player, player:getX(), player:getY(), player:getZ(), radius, radius)
  end)
end

---------------------------------------------------------------------------
-- Tropiezo / inconsciencia (la inconsciencia lleva un timer en tiempo real que lee Runtime)
---------------------------------------------------------------------------
E.timers = {}   -- [playerIndex] = { unconsciousUntilMs }

local function t(player)
  local idx = player:getPlayerNum()
  E.timers[idx] = E.timers[idx] or {}
  return E.timers[idx]
end

-- Sin animaciones de bump: en B42 forzar el estado "bump" del jugador podía dejarlo sin control, invisible o en ragdoll.
-- El tropiezo (movimiento al 25 %) y la inconsciencia (clavado en el lugar) usan el amortiguador del jugador (SD.slowPlayer).
function E.stagger(player, seconds, ignoreKerenzikov)
  if not ignoreKerenzikov and Kerenzikov and Kerenzikov.isActive(player) and seconds <= 1.0 then
    return -- Kerenzikov: inmunidad a stagger leve
  end
  E.setEndurance(player, E.getEndurance(player) - 0.05 * seconds)
  -- v0.1.26: efecto real: movimiento al 25 % mientras dura (mismo amortiguador que el arrastre; no atraviesa nada)
  local SD = rawget(_G, "SandevistanSlowdown")
  if SD then SD.slowPlayer(player, seconds, CFG.Stagger.MoveFactor) end
end

function E.knockOut(player, seconds)
  local tm = t(player)
  tm.unconsciousUntilMs = S.gameMs() + seconds * 1000          -- (127) reloj de juego (acelera con el avance rapido)
  E.addStat(player, "PANIC", 50)
  local SD = rawget(_G, "SandevistanSlowdown")
  if SD then SD.slowPlayer(player, seconds, 0) end        -- v0.1.26: queda clavado en el lugar
end

function E.isUnconscious(player)
  local tm = t(player)
  return (tm.unconsciousUntilMs or 0) > S.gameMs()
end

---------------------------------------------------------------------------
-- Cuerpo
---------------------------------------------------------------------------
-- (115) Multijugador: el servidor manda en el cuerpo (heridas, dolor, salud) y se lo reenvia al cliente (NetworkPlayerAI.syncDamage, paquetes
-- PlayerDamage/PlayerHealth que solo van del servidor al cliente): lo que el mod hacia solo aca (la herida del colapso, el sangrado nasal, la
-- muerte por cyberpsicosis...) se deshacia. Cada cambio se aplica aca (respuesta inmediata) y se le pide al servidor (comando "body").
local function bodyNet(player, args)
  if S.isMPClient() then sendClientCommand(player, "Sandevistan", "body", args) end
end

E.bodyNet = bodyNet

local function bodyPart(player, name)
  local bd = player:getBodyDamage()
  local ok, bp = pcall(function() return bd:getBodyPart(BodyPartType[name]) end)
  if ok then return bp end
  return nil
end

function E.addPain(player, partName, amount)
  local bp = bodyPart(player, partName)
  if not bp then return end
  S.try("addPain", function()
    bp:setAdditionalPain(math.min(100, bp:getAdditionalPain() + amount))
  end)
  bodyNet(player, { op = "pain", part = partName, amount = amount })
end

function E.setMinPain(player, partName, amount)
  local bp = bodyPart(player, partName)
  if not bp then return end
  S.try("setPain", function()
    if bp:getAdditionalPain() < amount then bp:setAdditionalPain(amount) end
  end)
  bodyNet(player, { op = "minPain", part = partName, amount = amount })
end

-- (163) T11: quemadura por forzar el calor. La aplica también el servidor (comando body op "burn"), así no se revierte en MP.
function E.burn(player, partName)
  local bp = bodyPart(player, partName)
  if not bp then return end
  S.try("setBurned", function() bp:setBurned() end)
  bodyNet(player, { op = "burn", part = partName })
end

function E.damagePart(player, partName, amount)
  local bp = bodyPart(player, partName)
  if not bp then return end
  S.try("damagePart", function() bp:AddDamage(amount) end)
  bodyNet(player, { op = "damage", part = partName, amount = amount })
end

-- severity: "massive" | "severe" | "light" ((125) la herida de la instalacion con el binder: CFG.Surgery.StudentDossier.SloppyWound)
function E.hemorrhageBleeding(severity)
  if severity == "massive" then return 60 end
  if severity == "light" then return CFG.Surgery.StudentDossier.SloppyWound.bleeding end
  return 30
end

function E.hemorrhageDamage(severity)
  if severity == "massive" then return 60 end
  if severity == "light" then return CFG.Surgery.StudentDossier.SloppyWound.damage end
  return 35
end

function E.hemorrhage(player, partName, severity)
  local bp = bodyPart(player, partName)
  if not bp then return end
  S.try("hemorrhage", function()
    bp:generateDeepWound()
    bp:setBleedingTime(E.hemorrhageBleeding(severity))
    bp:AddDamage(E.hemorrhageDamage(severity))
  end)
  bodyNet(player, { op = "hemorrhage", part = partName, massive = severity == "massive", light = severity == "light" or nil })
end

-- Un corte simple en una parte del cuerpo (extracción tosca: se corta la mano).
function E.cutPart(player, partName)
  local bp = bodyPart(player, partName)
  if not bp then return end
  S.try("cutPart", function() bp:setCut(true) end)
  bodyNet(player, { op = "cut", part = partName })
end

-- Salud general 0–100 con piso (para daño psicosomático).
function E.overallHealth(player)
  local ok, h = pcall(function() return player:getBodyDamage():getOverallBodyHealth() end)
  return ok and h or 100
end

function E.reduceHealthWithFloor(player, amount, floorFrac)
  local h = E.overallHealth(player)
  local floor = floorFrac * 100
  if h - amount < floor then amount = math.max(0, h - floor) end
  if amount <= 0 then return end
  S.try("reduceHealth", function() player:getBodyDamage():ReduceGeneralHealth(amount) end)
  bodyNet(player, { op = "health", amount = amount, floor = floorFrac })
end

function E.reduceHealth(player, amount)
  S.try("reduceHealth", function() player:getBodyDamage():ReduceGeneralHealth(amount) end)
  bodyNet(player, { op = "health", amount = amount })
end

function E.setTemperatureAtLeast(player, temp)
  if E.getStat(player, "TEMPERATURE") < temp then
    E.setStat(player, "TEMPERATURE", temp)
  end
end

---------------------------------------------------------------------------
-- Síntomas neurológicos (v0.1.15)
---------------------------------------------------------------------------
-- Sangre en la cara (cosmético). Firma B41/B42: addBlood(parte, rasguño, mordida, todasLasCapas).
function E.faceBlood(player)
  S.try("addBlood", function() player:addBlood(BloodBodyPartType.Head, false, false, false) end)
  bodyNet(player, { op = "blood" })                         -- (115) la sangre que pone el cliente no la ven los demas (AddBlood va del servidor)
end

-- Sangrado nasal: dura unos minutos in-game; el goteo lo aplica Periodic cada minuto.
function E.startNosebleed(player, d)
  local c = CFG.NeuralLoad.Nosebleed
  local now = S.worldHours()
  local mins = S.randRange(c.Minutes[1], c.Minutes[2])
  local wasBleeding = (d.nosebleedUntil or -1) > now
  d.nosebleedUntil = math.max(d.nosebleedUntil or -1, now + mins / 60)
  E.faceBlood(player)
  if not wasBleeding then E.say(player, getText("IGUI_Sandevistan_Nosebleed")) end   -- solo lo dice el personaje (no es un moodle)
end

function E.isNosebleeding(d) return (d.nosebleedUntil or -1) > S.worldHours() end

-- Grito psicótico: ruido fuerte que atrae zombis.
function E.scream(player, d)
  local c = CFG.NeuralLoad.Scream
  d.lastScreamHour = S.worldHours()
  local n = ZombRand(3) + 1
  E.say(player, getText("IGUI_Sandevistan_Scream_" .. n))
  if SandevistanNet and SandevistanNet.enabled() then
    SandevistanNet.scream(player, n, c.Radius)     -- MP: los demás ven el texto y el servidor genera el ruido
  else
    E.worldNoise(player, c.Radius)
  end
  E.addStat(player, "PANIC", c.Panic)
  S.try("stopSneak", function() player:setSneaking(false) end)
end

-- Muerte por daño general: el juego procesa la muerte como cualquier otra (en MP el cuerpo lo registra el servidor;
-- v0.1.25 además forzaba setHealth(0) en el cliente, lo que deja un cuerpo que desaparece y no se puede manejar).
function E.kill(player)
  S.try("kill", function() player:getBodyDamage():ReduceGeneralHealth(1000) end)
  bodyNet(player, { op = "kill" })
end

return E
