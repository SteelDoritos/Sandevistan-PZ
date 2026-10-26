-- Sandevistan / Core: tiempo, estado persistente y fórmulas puras (sin efectos).
require "Sandevistan/Config"
require "Sandevistan/Firmware"

local CFG = SandevistanConfig
local FW = SandevistanFirmware

Sandevistan = Sandevistan or {}
local S = Sandevistan

---------------------------------------------------------------------------
-- Log
---------------------------------------------------------------------------
local warned = {}
S.warned = warned
-- últimas líneas del log en memoria (para el reporte de diagnóstico de Debug)
S.logBuffer = {}
local LOG_KEEP = 300
local function remember(line)
  local b = S.logBuffer
  b[#b + 1] = line
  if #b > LOG_KEEP then table.remove(b, 1) end
end
-- (189) C12: en la versión publicada la consola solo muestra avisos y errores. Todo lo que va por S.log es traza de diagnóstico
-- (estado, títeres, firmware, arranque): queda en el buffer para el REPORTE y se imprime solo con "Registro detallado" o con -debug.
-- Los avisos y errores van por S.logAlways y se imprimen siempre.
function S.logVerbose()
  if S.debugOn() then return true end
  local I = rawget(_G, "SandevistanInput")
  if I and I.getOption then
    local okV, v = pcall(I.getOption, "verboseLog", false)
    if okV and v == true then return true end
  end
  return false
end
function S.logAlways(msg)
  local line = "[Sandevistan] " .. tostring(msg)
  print(line)
  remember(line)
end
function S.log(msg)
  local line = "[Sandevistan] " .. tostring(msg)
  remember(line)
  if S.logVerbose() then print(line) end
end
function S.warnOnce(key, msg)
  if warned[key] then return end
  warned[key] = true
  S.logAlways("WARN " .. tostring(msg))
end
function S.debugOn()
  return CFG.Debug or (isDebugEnabled and isDebugEnabled()) or false
end

-- Llamada protegida a un método Java/Lua. Devuelve ok, resultado.
function S.try(key, fn, ...)
  local ok, res = pcall(fn, ...)
  if not ok then S.warnOnce(key, key .. " falló: " .. tostring(res)) end
  return ok, res
end

---------------------------------------------------------------------------
-- Tiempo: s = segundos reales (getTimestampMs), h = horas in-game (getWorldAgeHours)
---------------------------------------------------------------------------
function S.realMs() return getTimestampMs() end
function S.worldHours() return getGameTime():getWorldAgeHours() end

-- (170) C01: opcion del mod "menos destellos" (fotosensibilidad, 29 §7.1). Con ella los efectos no parpadean: el glitch de pantalla va sin
-- tiras y como mucho uno por segundo, las alucinaciones se deshacen con un fundido y las marcas no titilan. Solo cliente (en el servidor, false).
function S.lessFlashes()
  local I = rawget(_G, "SandevistanInput")
  return I ~= nil and I.getOption ~= nil and I.getOption("lessFlashes", false) == true
end

-- (127) Reloj de juego del mod. Las mecanicas en segundos (Heat, enfriamiento, estamina, CN, Black Lace, Overdrive, KO, tropiezo, espera para volver a
-- encender) corren a velocidad normal como segundos reales, pero con el avance rapido de un jugador tienen que acelerar con el mundo: si no, a x40 el
-- implante encendido costaba 40 veces menos y el enfriamiento casi no avanzaba. S.timeScale() = cuantos segundos de juego pasan por segundo real:
-- 1 normal, 5 / 20 / 40 con los botones 2, 3 y 4 (getGameSpeed() devuelve el BOTON, no el multiplicador: verificado en el jar, SpeedControls ->
-- GameTime.setMultiplier 1/5/20/40), 0 en pausa. En multijugador el tiempo no se acelera: siempre 1.
-- Lo que es animacion o interfaz (estelas, HUD, avisos, alucinaciones, sonidos) sigue en tiempo real.
S.SPEED_MULT = { [1] = 1, [2] = 5, [3] = 20, [4] = 40 }
function S.timeScale()
  if isClient() then return 1 end
  if isGamePaused and isGamePaused() then return 0 end
  local ok, v = pcall(getGameSpeed)
  if not ok or type(v) ~= "number" then return 1 end
  if v <= 0 then return 0 end
  return S.SPEED_MULT[v] or 1
end

-- Milisegundos del reloj de juego (para plazos: "hasta cuando dura"). Arranca en la hora real y avanza con el real x S.timeScale(): a velocidad normal es
-- IGUAL a S.realMs() (los plazos se comportan como antes), con el avance rapido corre mas rapido y en pausa se frena. Runtime.onTick lo llama en cada tick.
S._gclock = { real = nil, game = nil }
function S.gameMs()
  local now = getTimestampMs()
  local c = S._gclock
  if not c.real then c.real, c.game = now, now end
  local dms = now - c.real
  if dms > 0 then c.game = c.game + dms * S.timeScale() end
  c.real = now
  return c.game
end

---------------------------------------------------------------------------
-- Estado persistente del jugador (ModData)
---------------------------------------------------------------------------
local DEFAULTS = {
  variant = nil,           -- nil | "lab" | "military" | "destroyed"
  degradation = 1.0,
  degradationFloor = 1.0,
  heat = 0,
  heatCap = 100,           -- tope de Heat (cicatriz térmica: baja con cada Overdrive/furia y se recupera con el tiempo)
  neuralLoad = 0,
  cyberpsychosisActive = false,
  rejection = 0,
  adaptXP = 0,             -- fuente de verdad de la adaptación (v0.1 no usa perk vanilla)
  lastDeactivateHour = -1000,
  lastRejectionTickHour = nil,
  lastCNTickHour = nil,
  herbalToxicity = 0,
  subjectId = nil,
  traits = {},             -- rasgos de creación de personaje (Traits.lua): special, chrome, psycho, ...
  kitGiven = false,
  ripperdocKitGiven = false,   -- (154) T01: los dos libros de guía del Aprendiz de ripperdoc ya se entregaron
  guideGiven = false,      -- v0.1.30 (30): la guia de campo ya se entrego
  knows = {},              -- recetas propias aprendidas: crafted, compound, kerenzikov
  immuno = {},             -- clinicalUntil, craftedUntil, herbalUntil (horas absolutas)
  immunoDoses = {},        -- horas de las dosis recientes (dosis de choque)
  immunodep = 0,           -- (135) inmunodepresion 0..100 (21-plan-inmunodepresion.md)
  immunoPeak = 0,          -- (135) ID maxima de la tanda de cobertura actual (rebote)
  immunoReboundUntil = -1, -- (135) hora de juego en que termina el rebote de rechazo
  cooldownMult = 1,
  antidepUntil = -1,       -- v0.1.15: cobertura de antidepresivos (hora absoluta)
  nosebleedUntil = -1,     -- v0.1.15: sangrado nasal en curso (hora absoluta)
  lastScreamHour = -1000,
  stopgap = {},            -- (162) T09: paliativos (painkillerUntil, painkillerDoses, sleepingUntil, betaUntil)
  prototype = nil,         -- "04" | "06" si el implante instalado es un prototipo alternativo
  plateName = nil,         -- (69) nombre que el jugador le puso a la placa del implante instalado (P06 / Mk. II)
  firmware = {},           -- (82) chips instalados: { sistema = id, habilidad = id } (shared/Firmware.lua)
  fwKnown = {},            -- (82) programas de firmware que el jugador sabe escribir (se aprenden con el nivel de adaptacion)
  fwRecalUntil = nil,      -- (82) hora de juego en que termina el recalibrado tras cambiar un chip
  incidents = {},          -- (178) C05: caja negra (anillo de incidentes; se guarda)
  seen = {},               -- (179) alucinaciones que el jugador ya descubrio (fakeTouch, fakeHit, clone, disguise, phantom)
  neuralScar = 0,          -- (178) C05: cicatriz neural acumulativa (puntos; bajan los umbrales)
  neuralScarHours = 0,     -- (178) C05: horas de juego con el implante apagado para recuperar el proximo punto
}

function S.data(player)
  local md = player:getModData()
  local d = md.Sandevistan
  if type(d) ~= "table" then d = {}; md.Sandevistan = d end
  for k, v in pairs(DEFAULTS) do
    if d[k] == nil then
      if type(v) == "table" then d[k] = {} else d[k] = v end
    end
  end
  -- (109) Pacto paso a llamarse Overclock: partidas de antes (chip instalado y programa aprendido)
  if d.firmware.habilidad == "Pacto" then d.firmware.habilidad = "Overclock" end
  if d.fwKnown and d.fwKnown.Pacto then d.fwKnown.Pacto = nil; d.fwKnown.Overclock = true end
  -- (114) se quito el programa Sostenido: el slot queda vacio (comportamiento de fabrica) y se olvida
  if d.firmware.sistema == "Sostenido" then d.firmware.sistema = nil end
  if d.fwKnown then d.fwKnown.Sostenido = nil end
  -- (165) T12: la remisión pasa de "desde cuándo" (noImplantSinceHour) a "cuánto se acumuló" (remissionHours). Migración de partidas viejas.
  if d.remissionHours == nil then
    d.remissionHours = d.noImplantSinceHour and math.max(0, S.worldHours() - d.noImplantSinceHour) or 0
    d.noImplantSinceHour = nil
  end
  return d
end

function S.kdata(player)
  local md = player:getModData()
  local k = md.Kerenzikov
  if type(k) ~= "table" then
    k = { activeSeconds = 0, isCrafted = false, crashUntilHour = -1, toleranceSteps = 0, lastDoseHour = -1000 }
    md.Kerenzikov = k
  end
  if k.activeSeconds == nil then k.activeSeconds = 0; k.activeUntilHour = nil end     -- (108) partidas de antes: la duracion pasa a segundos reales
  return k
end

-- Etiqueta de pantalla de la marca de un implante ("P06", "Mk.II").
-- (69) Limpia el nombre de una placa: mayusculas, solo letras/numeros y unos signos, espacios simples, tope de largo. nil si queda vacio.
function S.cleanPlate(text)
  if type(text) ~= "string" then return nil end
  local t = string.upper(text)
  t = string.gsub(t, "[^A-Z0-9 %.%-_'/#+&!?]", "")
  t = string.gsub(t, "%s+", " ")
  t = string.gsub(t, "^%s+", "")
  local max = (CFG.Plate and CFG.Plate.MaxLength) or 16
  t = string.sub(t, 1, max)
  t = string.gsub(t, "%s+$", "")
  if t == "" then return nil end
  return t
end

-- (69) Titulo del implante instalado: el nombre de la placa si el jugador le puso uno; si no, segun el diseno (P05 "PROTOTYPE 05", P04, P06, militar y su replica).
function S.plateTitle(d)
  if d.plateName then return d.plateName end
  if d.variant == "lab" then
    if d.prototype == "04" then return getText("IGUI_Sandevistan_HUD_P04") end
    if d.prototype == "06" then return getText("IGUI_Sandevistan_HUD_P06") end
    return getText("IGUI_Sandevistan_HUD_Lab")
  end
  if d.prototype == "07" then return getText("IGUI_Sandevistan_HUD_P07") end            -- (71) la replica militar
  local n = getText("IGUI_Sandevistan_HUD_Military")
  if d.prototype then n = n .. " " .. S.protoLabel(d.prototype) end
  return n
end

function S.protoLabel(tag) return (CFG.ProtoLabels and CFG.ProtoLabels[tag]) or ("P" .. tostring(tag)) end

-- (82) perfil de firmware (shared/Firmware.lua): multiplicadores y desplazamientos de los chips instalados; neutro sin chips.
S.profile = FW.profile

-- (165) T12: desconectado, el implante está inerte: cuenta como no operativo (pero sigue instalado: hasAnyImplant).
function S.hasWorkingImplant(d) return (d.variant == "lab" or d.variant == "military") and not d.disconnected end
function S.disconnected(d) return d and d.disconnected == true end
function S.hasAnyImplant(d) return d.variant ~= nil end
function S.variantCfg(d) return CFG.Variants[d.variant] end

---------------------------------------------------------------------------
-- Adaptación (XP interna)
---------------------------------------------------------------------------
function S.xpForLevel(level)   -- XP acumulada necesaria para alcanzar "level"
  local total = 0
  for i = 1, math.min(level, #CFG.XP.Table) do total = total + CFG.XP.Table[i] end
  return total
end

-- Nivel maximo de adaptacion de este jugador: el de su variante. Sin implante, 0.
function S.maxLevel(d)
  if not S.hasWorkingImplant(d) then return 0 end
  return S.variantCfg(d).maxLevel
end

function S.level(d)
  if not S.hasWorkingImplant(d) then return 0 end
  local lvl, total = 0, 0
  for i = 1, #CFG.XP.Table do
    total = total + CFG.XP.Table[i]
    if d.adaptXP >= total then lvl = i else break end
  end
  if d.traits and d.traits.special then lvl = lvl + CFG.Traits.SpecialLevels end
  return math.min(lvl, S.maxLevel(d))
end

-- Progreso dentro del nivel (escala del mod): nivel mostrado, XP hecha en el tramo, XP del tramo y fracción 0..1 (1 en el techo).
-- v0.1.30 (13): con el rasgo "Sos especial" el nivel mostrado va uno arriba del que da la XP; el tramo se mide sobre la XP (el panel
-- calculaba el tramo con el nivel mostrado y daba XP negativa).
function S.levelProgress(d)
  if not S.hasWorkingImplant(d) then return 0, 0, 0, 0 end
  local level = S.level(d)
  if level >= S.maxLevel(d) then return level, 0, 0, 1 end
  local bonus = (d.traits and d.traits.special) and CFG.Traits.SpecialLevels or 0
  local base = math.max(0, level - bonus)
  local lo, hi = S.xpForLevel(base), S.xpForLevel(base + 1)
  local into, need = math.max(0, d.adaptXP - lo), hi - lo
  return level, into, need, need > 0 and math.min(1, into / need) or 0
end

-- Ventana de Overdrive (segundos reales): WindowSeconds a nivel 0, lineal hasta Variants.<v>.overdriveMax en el nivel maximo de la variante.
function S.overdriveWindow(d, level)
  local v = S.variantCfg(d)
  local base = CFG.Overdrive.WindowSeconds
  if not v then return base end
  level = math.max(0, math.min(level or 0, v.maxLevel))
  local extra = (CFG.Mastery and CFG.Mastery.WindowPerRank or 0) * S.masteryRankAt(d, level)                     -- (123) maestria
  return (base + (v.overdriveMax - base) * level / math.max(1, v.maxLevel) + extra) * FW.profile(d).window        -- (83) Camara criogenica: ventana x0,8
end

-- 0..1: adaptación relativa al nivel estable de la variante (lab 5, militar 8). Lineal desde el nivel 0.
function S.adaptFraction(d)
  if not S.hasWorkingImplant(d) then return 0 end
  local v = S.variantCfg(d)
  local stable = v.stableLevel or v.maxLevel or 1
  return math.max(0, math.min(1, S.level(d) / math.max(1, stable)))
end

function S.xpCap(d)
  if not S.variantCfg(d) then return 0 end
  if S.masteryEnabled(d) then                                    -- (123) con Beyond Ten la XP sigue hasta la maestria 15
    local total = S.masteryBase(d)
    for _, c in ipairs(CFG.Mastery.Table) do total = total + c end
    return total
  end
  return S.xpForLevel(S.maxLevel(d))
end

---------------------------------------------------------------------------
-- (123) Maestria: niveles 11-15 de la adaptacion con el mod Beyond Ten (CFG.Mastery). Solo la variante con `mastery` (militar).
-- S.level sigue con techo en el nivel maximo; la maestria (0..5) se cuenta con la XP por encima de la que da ese nivel y suma bonos aparte.
-- Beyond Ten corre en el cliente y en el servidor (sus archivos shared), asi que los dos lados ven lo mismo.
---------------------------------------------------------------------------
function S.beyondTen()
  local BT = rawget(_G, "BeyondTen")
  if type(BT) ~= "table" or type(BT.SetStoredXP) ~= "function" or type(BT.GetTotalMasteryCost) ~= "function" then return nil end
  return BT
end

function S.masteryEnabled(d)
  local v = S.variantCfg(d)
  return v ~= nil and v.mastery == true and CFG.Mastery ~= nil and S.beyondTen() ~= nil
end

-- XP con la que se llega al nivel maximo (con "Sos especial", la de un nivel menos: el rasgo adelanta tambien la maestria)
function S.masteryBase(d)
  local bonus = (d.traits and d.traits.special) and CFG.Traits.SpecialLevels or 0
  return S.xpForLevel(math.max(0, S.maxLevel(d) - bonus))
end

-- Maestria, XP hecha en el tramo, XP del tramo y fraccion 0..1 (1 en la 15). Sin maestria o antes del nivel maximo: 0, 0, 0, 0.
function S.masteryProgress(d)
  if not S.hasWorkingImplant(d) or not S.masteryEnabled(d) or S.level(d) < S.maxLevel(d) then return 0, 0, 0, 0 end
  local rest = math.max(0, (d.adaptXP or 0) - S.masteryBase(d))
  local T = CFG.Mastery.Table
  for i = 1, #T do
    if rest < T[i] then return i - 1, rest, T[i], rest / T[i] end
    rest = rest - T[i]
  end
  return #T, 0, 0, 1
end

function S.mastery(d) return (S.masteryProgress(d)) end
function S.masteryMax() return CFG.Mastery and #CFG.Mastery.Table or 0 end
-- nivel que se muestra (panel de skills, HUD, avisos): el de la adaptacion mas la maestria
function S.displayLevel(d) return S.level(d) + S.mastery(d) end

-- maestria que vale para una formula evaluada a "level": solo en el nivel maximo de la variante (las pruebas y el tooltip piden otros niveles)
function S.masteryRankAt(d, level)
  if level == nil or not S.variantCfg(d) or level < S.maxLevel(d) then return 0 end
  return S.mastery(d)
end

-- Reduccion del tropiezo, el arrastre y el KO tras el colapso: la de la adaptacion (hasta `base` a adaptacion estable) mas la de la maestria
function S.collapseRecoveryReduction(d, base)
  return (base or 0) * S.adaptFraction(d) + (CFG.Mastery and CFG.Mastery.RecoveryPerRank or 0) * S.mastery(d)
end

-- Multiplicador de duracion y cantidad de estelas del jugador local: AdaptMaxMultiplier a adaptacion estable y AfterimageExtra mas desde la maestria AfterimageRank
function S.afterimageMult(d)
  local C, M = CFG.Afterimage, CFG.Mastery
  local mult = 1 + ((C.AdaptMaxMultiplier or 3) - 1) * S.adaptFraction(d)
  if M and S.mastery(d) >= (M.AfterimageRank or 99) then mult = mult + (M.AfterimageExtra or 0) end
  return mult
end

-- Suma XP respetando el techo de la variante. Devuelve el nivel nuevo si subió.
-- source: "time" (segundos con el implante encendido), "kill", "pasiva" (horas con el implante puesto) u "otro": se acumula en d.xpSrc (v0.1.30 (41)) para ver de
-- donde sale la XP (Report e Info). d.xpSrc.nKills / nActivations / activeSeconds son contadores de vida del personaje.
function S.addAdaptXP(d, amount, source)
  if not S.hasWorkingImplant(d) or amount <= 0 then return nil end
  local before = S.level(d)
  local mult = CFG.XP.Multiplier * ((d.traits and d.traits.special) and (1 + CFG.Traits.SpecialXPBonus) or 1)
  d.xpSrc = d.xpSrc or {}
  local key = source or "otro"
  d.xpSrc[key] = (d.xpSrc[key] or 0) + amount * mult
  local cap = S.xpCap(d)
  if d.adaptXP < cap then d.adaptXP = math.min(cap, d.adaptXP + amount * mult) end        -- por encima del tope (partidas con el viejo Sin limitador) la XP guardada ni baja ni sube
  local after = S.level(d)
  if after > before then return after end
  return nil
end

---------------------------------------------------------------------------
-- Espejo en la skill vanilla (media/perks.txt). La XP propia sigue siendo la fuente
-- de verdad; la skill solo muestra el nivel en el panel de habilidades.
---------------------------------------------------------------------------
S._perk = nil
function S.perk()
  if S._perk ~= nil then return S._perk or nil end
  local p = nil
  pcall(function() p = Perks.SandevistanAdaptation end)
  if not p then pcall(function() p = Perks.FromString("SandevistanAdaptation") end) end
  local ok = false
  if p then pcall(function() ok = tostring(p:getId()) == "SandevistanAdaptation" end) end
  S._perk = ok and p or false
  if not ok then S.warnOnce("perk", "skill SandevistanAdaptation no registrada (perks.txt)") end
  return S._perk or nil
end

-- XP de la skill del juego (su propia escala). El juego multiplica los requisitos de perks.txt x1.5 (el panel pide 375 para el nivel 2
-- donde el mod pide 250): se espeja la FRACCIÓN del nivel, no la XP. Sin las funciones del perk, se asume la tabla del mod.
function S.perkXP(player, perk)
  local ok, v = pcall(function() return player:getXp():getXP(perk) end)
  return ok and type(v) == "number" and v or nil
end

function S.perkXPFor(perk, level, frac)
  local total, nextXp = nil, nil
  pcall(function() total = perk:getTotalXpForLevel(level) end)
  pcall(function() nextXp = perk:getXpForLevel(level + 1) end)
  if type(total) ~= "number" then total = S.xpForLevel(level) end
  if type(nextXp) ~= "number" or nextXp < 0 then nextXp = CFG.XP.Table[level + 1] or 0 end
  return total + (frac or 0) * nextXp
end

-- Suma XP a la skill SOLO en este proceso (remote = true: sin aviso a la red; SyncXp manda después el estado completo). v0.1.30 (13): el
-- global addXpNoMultiplier en un cliente de multijugador no suma nada localmente (la pestaña quedaba en "0 / 375" con 44 XP propias).
-- Se verifica leyendo la XP de vuelta; lo que el juego multiplique (XP del servidor) se aprende y se compensa la vez siguiente. Si no
-- suma nada no se reintenta en esta sesión (en multijugador, reintentar podía mandarle XP de más al servidor).
S.perkAdd = { scale = 1, broken = false, via = nil }
function S.addPerkXP(player, perk, amount)
  local st = S.perkAdd
  if st.broken or amount < 1 then return false end
  local xp = nil
  pcall(function() xp = player:getXp() end)
  if not xp then return false end
  local before = S.perkXP(player, perk) or 0
  local req = amount / st.scale
  local ok = pcall(xp.AddXP, xp, perk, req, false, false, true)
  local got = (S.perkXP(player, perk) or before) - before
  local via = "AddXP(remote)"
  if (not ok or got < 0.5) and not isClient() then
    req = amount
    ok = pcall(xp.AddXPNoMultiplier, xp, perk, req)
    got = (S.perkXP(player, perk) or before) - before
    via = "AddXPNoMultiplier"
  end
  if got >= 0.5 then
    st.scale = math.max(0.01, got / req)
    if st.via ~= via then st.via = via; S.log("XP de la skill via " .. via) end
    return true
  end
  st.broken = true
  S.warnOnce("perkXP", "no se pudo sumar XP a la skill: la pestaña de skills muestra el nivel pero no el avance dentro del nivel")
  return false
end

-- (123) Con Beyond Ten, del nivel 10 en adelante la skill no se toca: Beyond Ten deja la XP del juego en el total del nivel 9 a proposito (su "reservorio")
-- y toma por maestria toda XP que entre por AddXP (antes de la (123) el mod reponia esa XP en cada sync y Beyond Ten la convertia en maestria falsa). Ahora
-- el mod deja la skill en el nivel 10 y escribe la maestria en el almacen de Beyond Ten (BT.SetStoredXP: en el servidor, su almacen autoritativo, y se le
-- avisa al cliente con BeyondTenServer.SendPerkSync; en un jugador, el ModData). Por debajo del 10 vacia la maestria guardada (explantar, otro implante):
-- si no, Beyond Ten la devolveria entera al volver al 10. Devuelve true si se encargo (target >= 10 con Beyond Ten). Corre en un jugador o en el servidor.
function S.writeMastery(player, perk, target, frac)
  local BT = S.beyondTen()
  if not BT or not perk then return false end
  local native = BT.NATIVE_MAX_LEVEL or 10
  local top = BT.MAX_LEVEL or 15
  local stored = 0
  if target >= native then
    local pl = nil
    pcall(function() pl = player:getPerkLevel(perk) end)
    if pl ~= native then
      -- setXPToLevel no pasa por AddXP: Beyond Ten lo toma por una restauracion (o activa la skill al escanear) y no suma maestria
      S.try("setPerkLevel", function() player:setPerkLevelDebug(perk, native) end)
      S.try("setXPToLevel", function() player:getXp():setXPToLevel(perk, native) end)
    end
    local lvl = math.min(target, top)
    stored = BT.GetTotalMasteryCost(perk, lvl)
    if lvl < top then stored = stored + math.max(0, math.min(0.999, frac or 0)) * BT.GetMasteryCost(perk, lvl + 1) end
  end
  local have = 0
  pcall(function() have = tonumber(BT.GetStoredXP(player, perk)) or 0 end)
  if math.abs(stored - have) >= 1 or (stored == 0 and have > 0) then
    S.try("masteryXP", function() BT.SetStoredXP(player, perk, stored) end)
    local BTS = rawget(_G, "BeyondTenServer")
    if isServer() and type(BTS) == "table" and type(BTS.SendPerkSync) == "function" then
      S.try("masterySync", function() BTS.SendPerkSync(player, perk) end)      -- sin niveles: solo el estado (el aviso de nivel lo da el mod en el cliente)
    end
  end
  return target >= native
end

-- Nivel y fraccion que se espejan en la skill: el de la adaptacion y el avance dentro del nivel; en el techo, con maestria (123), el nivel 11..15 y su avance.
function S.perkTarget(d)
  local traitLevel = (d.traits and d.traits.special) and CFG.Traits.SpecialLevels or 0
  if not S.hasWorkingImplant(d) then return traitLevel, 0 end          -- sin implante la skill muestra igual el punto del rasgo "Sos especial"
  local target, cap = S.level(d), S.maxLevel(d)
  if target < cap then
    local _, _, _, f = S.levelProgress(d)
    return target, math.min(0.999, f)
  end
  if S.masteryEnabled(d) then
    local rank, _, _, f = S.masteryProgress(d)
    return target + rank, rank < S.masteryMax() and math.min(0.999, f) or 0
  end
  return target, 0                                                      -- en el techo, la skill queda justo en el nivel
end

-- Espeja la adaptación en la skill vanilla: el nivel y el avance dentro del nivel (la barra de la pestaña de skills).
function S.syncPerk(player)
  local perk = S.perk()
  if not perk then return end
  local d = S.data(player)
  local working = S.hasWorkingImplant(d)
  local traitLevel = (d.traits and d.traits.special) and CFG.Traits.SpecialLevels or 0
  local cap = working and S.maxLevel(d) or 0
  local pl = nil
  pcall(function() pl = player:getPerkLevel(perk) end)
  -- Cambio externo de la skill (comandos de admin, otros mods): la skill difiere de lo que dejó este mismo mod la última
  -- vez (d.perkSeen). Se adopta hacia arriba siempre y hacia abajo solo en un jugador (en multijugador el servidor puede
  -- devolver un valor viejo y eso no debe borrar la adaptación).
  -- (119) en multijugador, mientras el servidor no confirmo el nivel que se le pidio (hasta 15 s), lo que muestra la skill es viejo: no es un cambio externo
  local waiting = S.isMPClient() and S.perkPendingLevel ~= nil and pl ~= S.perkPendingLevel and S.realMs() - (S.perkPendingMs or 0) < 15000
  if S.perkPendingLevel ~= nil and pl == S.perkPendingLevel then S.perkPendingLevel = nil end
  if working and pl and d.perkSeen ~= nil and pl ~= d.perkSeen and not waiting then
    local base = math.max(0, math.min(pl - traitLevel, cap))
    local was = d.adaptXP
    if pl > d.perkSeen then
      if S.xpForLevel(base) > d.adaptXP then d.adaptXP = S.xpForLevel(base) end
    elseif not isClient() then
      d.adaptXP = S.xpForLevel(base)
    end
    if d.adaptXP ~= was then                                     -- (41) se anota: si la XP "se duplica", aca se veria
      d.xpSrc = d.xpSrc or {}
      d.xpSrc.adoptada = (d.xpSrc.adoptada or 0) + (d.adaptXP - was)
      S.log(string.format("skill cambiada desde afuera: nivel %s -> %s, adaptXP %.0f -> %.0f", tostring(d.perkSeen), tostring(pl), was, d.adaptXP))
    end
  end
  local target, frac = S.perkTarget(d)
  local native = math.min(target, 10)                             -- (123) con maestria la skill del juego queda en 10; el resto lo lleva Beyond Ten
  -- (119) Cliente de multijugador: la skill la escribe SOLO el servidor. Antes este cliente la ponia aca y ademas se la pedia al servidor; el servidor
  -- la calcula con su propia escala de XP y, al reenviarla (syncXp), no coincidia: el cliente la "corregia", la volvia a pedir y la barra parpadeaba
  -- cada 2 s. Ahora se manda el nivel y la fraccion (comando "perk") cuando cambian (o cada 30 s, por si se perdio) y el servidor arma la XP.
  if S.isMPClient() then
    local key = target .. ":" .. string.format("%.2f", frac)
    local now = S.realMs()
    if S.perkSentKey ~= key or now - (S.perkSentMs or 0) > 30000 then
      S.perkSentKey, S.perkSentMs = key, now
      if pl ~= native then S.perkPendingLevel, S.perkPendingMs = native, now end
      sendClientCommand(player, "Sandevistan", "perk", { level = target, frac = frac })
    end
    d.perkSeen = native
    return
  end
  if S.writeMastery(player, perk, target, frac) then              -- (123) del 10 en adelante con Beyond Ten
    local after = nil
    pcall(function() after = player:getPerkLevel(perk) end)
    d.perkSeen = after or native
    return
  end
  local changed = false
  local function setLevel()
    S.try("setPerkLevel", function() player:setPerkLevelDebug(perk, target) end)
    S.try("setXPToLevel", function() player:getXp():setXPToLevel(perk, target) end)
    changed = true
  end
  if (pl or 0) ~= target then setLevel() end
  local want, have = S.perkXPFor(perk, target, frac), S.perkXP(player, perk)
  if have and math.abs(want - have) >= 1 then
    if have > want then setLevel(); have = S.perkXP(player, perk) or have end   -- se pasó (o la adaptación bajó): desde el umbral
    if want - have >= 1 and S.addPerkXP(player, perk, want - have) then changed = true end
    -- una suma de más no puede subir la skill de nivel: el próximo sync lo tomaría como una subida externa
    local lv = nil
    pcall(function() lv = player:getPerkLevel(perk) end)
    if lv and lv ~= target then setLevel() end
  end
  local after = nil
  pcall(function() after = player:getPerkLevel(perk) end)
  d.perkSeen = after or target
end

-- Pruebas (FullTest / TestSuite): deja la skill vanilla en "level" y la marca como vista. Al reponer el estado guardado, syncPerk
-- tomaba el nivel que habían dejado las pruebas por una subida externa (comandos) y se lo sumaba a la adaptación real del personaje.
function S.resetPerkTo(player, d, level)
  local perk = S.perk()
  if not perk or level == nil then return end
  S.try("resetPerk", function() player:setPerkLevelDebug(perk, level); player:getXp():setXPToLevel(perk, level) end)
  if d then d.perkSeen = level end
end

---------------------------------------------------------------------------
-- Fórmulas puras
---------------------------------------------------------------------------
-- (178) C05: puntos de cicatriz neural que bajan los umbrales (tope Max; 0 si la funcion esta apagada). Lo usan todos los umbrales
-- neurales en vez de leer Config directo, asi la cicatriz se resta en un solo lugar.
function S.scarOffset(d)
  local NS = CFG.NeuralLoad.NeuralScar
  if not (NS and NS.Enabled) then return 0 end
  local v = math.floor((d.neuralScar or 0) + 0.5)
  return math.max(0, math.min(NS.Max or 10, v))
end

-- Un umbral neural con la cicatriz restada (nunca baja de 0).
function S.neuralThreshold(d, base) return math.max(0, (base or 0) - S.scarOffset(d)) end

-- Suma (o resta, con amount negativo) puntos de cicatriz, respetando 0..Max, y avisa al servidor en MP.
function S.addNeuralScar(player, d, amount)
  local NS = CFG.NeuralLoad.NeuralScar
  if not (NS and NS.Enabled) then return S.scarOffset(d) end
  d.neuralScar = math.max(0, math.min(NS.Max or 10, (d.neuralScar or 0) + (amount or NS.PerOverload or 2)))
  local N = rawget(_G, "SandevistanNet")
  if player and N and N.saveState then pcall(N.saveState, player) end
  return d.neuralScar
end

-- (178) C05: CAJA NEGRA. Anota un incidente en el anillo d.incidents (los que el jugador recordaria) y lo guarda en MP.
-- e = { kind, cn, stage, pressure, secs, why, fury }; t y cn se completan aca si no vienen.
function S.addIncident(player, d, e)
  local BB = CFG.Psychosis.BlackBox
  if not (BB and BB.Enabled) or type(e) ~= "table" then return end
  local list = d.incidents
  if type(list) ~= "table" then list = {}; d.incidents = list end
  if e.t == nil then e.t = S.worldHours() end
  if e.cn == nil then e.cn = math.floor((d.neuralLoad or 0) + 0.5) end
  list[#list + 1] = e
  local max = math.max(1, BB.MaxEntries or 15)
  while #list > max do table.remove(list, 1) end
  local N = rawget(_G, "SandevistanNet")
  if player and N and N.saveState then pcall(N.saveState, player) end
end

-- (179) Marca una alucinacion descubierta ("fakeTouch", "fakeHit", "clone", "disguise", "phantom"). Se guarda en MP.
function S.markSeen(player, key, n)
  local d = S.data(player)
  d.seen = d.seen or {}
  d.seen[key] = (d.seen[key] or 0) + (n or 1)
  local N = rawget(_G, "SandevistanNet")
  if player and N and N.saveState then pcall(N.saveState, player) end
end

function S.lastIncident(d)
  local list = d and d.incidents
  if type(list) ~= "table" or #list == 0 then return nil end
  return list[#list]
end

-- Cuantos incidentes hubo en las ultimas "hours" horas de juego (por defecto 24).
function S.incidentCount(d, hours, now)
  local list = d and d.incidents
  if type(list) ~= "table" then return 0 end
  now = now or S.worldHours()
  local n, span = 0, hours or 24
  for i = 1, #list do
    local e = list[i]
    if e and type(e.t) == "number" and now - e.t <= span then n = n + 1 end
  end
  return n
end

function S.cnZone(d)
  local off = S.scarOffset(d)
  if d.cyberpsychosisActive and d.neuralLoad >= CFG.NeuralLoad.Zones.critical - off then return "cyberpsychosis" end
  local z = CFG.NeuralLoad.Zones
  if d.neuralLoad >= z.cyberpsychosis - off then return "cyberpsychosis" end
  if d.neuralLoad >= z.critical - off then return "critical" end
  if d.neuralLoad >= z.risk - off then return "risk" end
  return "safe"
end

-- Tope de Heat (cicatriz térmica) sin el firmware: 100 salvo que Overdrives o furias recientes lo hayan bajado. Con la opción desactivada siempre 100.
local function scarCap(d)
  local H = CFG.Overdrive.HeatCap
  if not H or not H.Enabled then return 100 end
  return math.max(H.Min, math.min(100, d.heatCap or 100))
end

-- Tope de Heat efectivo: la cicatriz térmica por el del firmware ((108) Camara criogenica x0,8).
function S.heatCap(d) return scarCap(d) * FW.profile(d).maxHeat end

-- Heat relativo al tope (0..100): con el tope bajo, los avisos y umbrales se alcanzan antes.
function S.heatPct(d) return math.min(100, (d.heat or 0) / S.heatCap(d) * 100) end

-- Baja el tope "amount" puntos (no menos de Min) y recorta el Heat actual. Devuelve el tope nuevo.
function S.scarHeatCap(d, amount)
  local H = CFG.Overdrive.HeatCap
  if not H or not H.Enabled then return 100 end
  d.heatCap = math.max(H.Min, scarCap(d) - amount)
  local cap = S.heatCap(d)
  if (d.heat or 0) > cap then d.heat = cap end
  return cap
end

-- Colapso de Overdrive: el primero de cada FreeEveryHours no deja cicatriz. Devuelve el tope nuevo y si fue el colapso "gratis".
-- always (163, T11): un colapso forzado por calor siempre deja cicatriz, sin el colapso gratis del día.
function S.overdriveScar(d, now, always)
  local H = CFG.Overdrive.HeatCap
  if not H or not H.Enabled then return 100, true end
  if not always and now - (d.lastFreeOverdriveHour or -1e9) >= (H.FreeEveryHours or 0) then
    d.lastFreeOverdriveHour = now
    return S.heatCap(d), true
  end
  return S.scarHeatCap(d, H.PerCollapse), false
end

-- Horas hasta que el próximo colapso vuelva a ser gratis (0 = ya lo es).
function S.freeOverdriveIn(d, now)
  local H = CFG.Overdrive.HeatCap
  if not H or not H.Enabled then return 0 end
  return math.max(0, (d.lastFreeOverdriveHour or -1e9) + (H.FreeEveryHours or 0) - now)
end

-- Recuperación lenta del tope con el tiempo (implante apagado); el llamador decide si corresponde.
function S.recoverHeatCap(d, hours, asleep)
  local H = CFG.Overdrive.HeatCap
  if not H or not H.Enabled or (d.heatCap or 100) >= 100 then return end
  d.heatCap = math.min(100, d.heatCap + H.RecoverPerHour * hours * (asleep and H.SleepMult or 1))
end

-- Remisión de la cyberpsicosis: horas que faltan (nil si no corresponde: sin cyberpsicosis, con implante o desactivada).
-- (165) T12: la remisión se acumula en d.remissionHours (ver Periodic.hourlyTick): ×1 sin implante, ×RemissionRate desconectado.
-- Con un implante operativo instalado no avanza; desconectado sí (a la mitad).
function S.remissionHoursLeft(d, now)
  local RM = CFG.NeuralLoad.Remission
  if not RM.Enabled or not d.cyberpsychosisActive then return nil end
  if S.hasAnyImplant(d) and not d.disconnected then return nil end
  local done = d.remissionHours or 0
  return math.max(0, RM.HoursWithoutImplant - done)
end

-- (180) C08: abstinencia leve. Horas desde el ultimo uso de UseSeconds o mas, si corresponde (implante operativo, no desconectado,
-- CN >= MinCN y entre StartHours y EndHours). nil si no hay ganas.
function S.cravingHours(d, now)
  local c = CFG.NeuralLoad.Craving
  if not (c and c.Enabled) or not S.hasWorkingImplant(d) or d.disconnected then return nil end
  if (d.neuralLoad or 0) < (c.MinCN or 60) then return nil end
  local last = d.lastSatisfiedHour
  if last == nil then last = d.lastDeactivateHour end
  if last == nil or last < -500 then return nil end
  local h = (now or S.worldHours()) - last
  if h < (c.StartHours or 12) or h >= (c.EndHours or 48) then return nil end
  return h
end

-- Abstinencia (64): horas que quedan de la ventana de los primeros dias de la remision (nil si no corresponde).
function S.withdrawalHoursLeft(d, now)
  local W = CFG.NeuralLoad.Remission.Withdrawal
  local left = S.remissionHoursLeft(d, now)
  if not W or not left then return nil end
  local elapsed = CFG.NeuralLoad.Remission.HoursWithoutImplant - left
  if elapsed >= W.Hours then return nil end
  return W.Hours - elapsed
end

function S.heatPerSecond(d, level)
  local v = S.variantCfg(d)
  local zone = S.cnZone(d)
  local zm = CFG.HeatZoneMultiplier[zone] or 1
  if d.cyberpsychosisActive then zm = math.max(zm, CFG.HeatZoneMultiplier.cyberpsychosis) end
  local trait = (d.traits and d.traits.edgerunner) and CFG.Traits.EdgerunnerHeatMult or 1     -- rasgo Edgerunner: el Heat sube más rápido
  local mastery = 1 - (CFG.Mastery and CFG.Mastery.HeatPerRank or 0) * S.masteryRankAt(d, level)                      -- (123) maestria
  return v.baseHeat * (1 - level * v.heatReductionPerLevel) * mastery * (d.degradation or 1) * zm * trait * (CFG.HeatRateMultiplier or 1) * FW.heatMult(d)   -- (82) chips y recalibrado
end

function S.coolPerSecond(d, level)
  local v = S.variantCfg(d) or CFG.Variants.lab
  local mastery = 1 + (CFG.Mastery and CFG.Mastery.CoolPerRank or 0) * S.masteryRankAt(d, level)                       -- (123) maestria
  return v.baseCool * (1 + level * v.coolBonusPerLevel) * mastery / (d.cooldownMult or 1)
end

-- (138i) Humedad del cuerpo en 0..1: promedio de los nodos del termorregulador. 0 si el juego cambia esas clases (nunca rompe el tick).
function S.bodyWetness(player)
  if not player then return 0 end
  local sum, n = 0, 0
  pcall(function()
    local tr = player:getBodyDamage():getThermoregulator()
    n = tr:getNodeSize()
    for i = 0, n - 1 do sum = sum + tr:getNode(i):getBodyWetness() end
  end)
  if n <= 0 then return 0 end
  return math.max(0, math.min(1, sum / n))
end

-- (138i) Multiplicador de enfriamiento por el ambiente (27 §3): >= 1, SOLO bonus. Frio (getAirTemperatureForCharacter ya cuenta techo y
-- calefaccion), cuerpo mojado (0..1) y viento al aire libre. La lluvia no se cuenta aparte: entra por la humedad del cuerpo. La ropa no
-- entra: solo podria castigar y el entorno nunca enfria peor que hoy. No se guarda: se recalcula cada vez.
function S.ambientCoolMult(player)
  local AC = CFG.AmbientCooling
  if not AC or not AC.Enabled or not player then return 1 end
  local T, wind, outside = AC.Cold.RefTemp or 18, 0, false
  pcall(function()
    local cm = getClimateManager()
    if cm and cm.getAirTemperatureForCharacter then T = cm:getAirTemperatureForCharacter(player) end
    pcall(function() outside = player:isOutside() == true end)
    if outside and cm and cm.getWindIntensity then wind = math.max(0, cm:getWindIntensity()) end
  end)
  local cold = math.max(0, ((AC.Cold.RefTemp or 18) - T) * (AC.Cold.PerDegree or 0.02))
  local wet = S.bodyWetness(player) * (AC.BodyWet or 0.25)
  local mult = 1 + cold + wet + wind * (AC.Wind or 0.05)
  return math.max(1, math.min(AC.Max or 1.45, mult))
end

-- (138j) Cuanto frena el ambiente la suba de Heat mientras el implante esta encendido (<= 1). Es el MISMO bonus ambiental, aplicado en
-- menor proporcion (DurationShare): con x1,45 de enfriamiento, 0,35 da x0,865 de suba (~x1,16 de duracion). No se guarda.
function S.ambientHeatMult(player)
  local AC = CFG.AmbientCooling
  local share = AC and AC.DurationShare or 0
  if not AC or not AC.Enabled or share <= 0 then return 1 end
  local amb = S.ambientCoolMult(player)
  if amb <= 1 then return 1 end
  return 1 / (1 + (amb - 1) * share)
end

-- (138i) Enfriamiento total de un cuadro: el extra del firmware (Camara criogenica x1,75) por el ambiente, con el tope conjunto
-- (CombinedMax, x2,0): x1,75 x x1,45 daria x2,5 y era demasiado. En el modo Taller no hay criogenica: extra = 1.
function S.totalCoolMult(player, extra)
  local total = (extra or 1) * S.ambientCoolMult(player)
  local cap = CFG.AmbientCooling and CFG.AmbientCooling.CombinedMax
  if cap and cap > 0 and total > cap then total = cap end
  return total
end

-- (138i) El implante caliente seca el cuerpo (0..100 de wetness, como BodyDamage:decreaseBodyWetness). En multijugador puede que el
-- servidor vuelva a subir la humedad (manda en los stats): ahi es solo cosmetico, nunca rompe nada.
function S.dryBody(player, amount)
  if not player or not amount or amount <= 0 then return end
  pcall(function() player:getBodyDamage():decreaseBodyWetness(amount) end)
end

-- Tramo de dilatacion de una variante a un nivel, sin firmware. Devuelve el tramo y su indice.
function S.tierFor(v, level)
  local tiers = CFG.DilationTiers
  local tier, idx = tiers[1], 1
  for i, t in ipairs(tiers) do
    if level >= t.minLevel and i <= v.maxDilationTier then tier, idx = t, i end
  end
  return tier, idx
end

function S.dilationTier(d, level)
  local tier = S.tierFor(S.variantCfg(d), level + S.masteryRankAt(d, level))       -- (123) la maestria cuenta como niveles de mas: el tramo IV pide la 15
  return FW.tier(d, tier)            -- (82) con chips que cambian el factor de zombis o la velocidad devuelve una copia ajustada; si no, el mismo tramo
end

function S.staminaDrainPerSecond(level, heavy, d)
  local drain = CFG.Stamina.BaseDrain * (1 - level * CFG.Stamina.ReductionPerLevel)
  if d then drain = drain * (1 - (CFG.Mastery and CFG.Mastery.StaminaPerRank or 0) * S.masteryRankAt(d, level)) end      -- (123) maestria
  if heavy then drain = drain * CFG.Stamina.EncumbranceMultiplier end
  return drain
end

-- (139) Deuda de estamina (27 §2): cuanto de la resistencia congelada al encender ya se debe (1,0 = todo lo que habia). Con el
-- piso de 0,05 para que una marca casi vacia no dispare el moodle con un gasto minimo. Lo usan el moodle y la pestaña Implante.
function S.staminaDebtRatio(debt, mark)
  return (debt or 0) / math.max(0.05, mark or 0.25)
end

function S.cnDecayPerHour(d)
  local z = S.cnZone(d)
  if d.neuralLoad >= S.neuralThreshold(d, CFG.NeuralLoad.Zones.cyberpsychosis) then z = "cyberpsychosis" end
  local rate = CFG.NeuralLoad.Decay[z] or 0.1
  if d.traits and d.traits.unstable then rate = rate * CFG.Traits.UnstableDecayMult end     -- rasgo "Neuralmente inestable"
  return rate
end

-- (48) el cuerpo se acostumbra: la CN que suma el tiempo de uso baja hasta UseAdaptReduction con la adaptacion estable (multiplicador <= 1)
function S.adaptUseMultiplier(d)
  return 1 - (CFG.NeuralLoad.UseAdaptReduction or 0) * S.adaptFraction(d) - (CFG.Mastery and CFG.Mastery.NeuralUsePerRank or 0) * S.mastery(d)   -- (123) maestria
end

-- Tabla { {umbral, valor}, ... }: devuelve el valor del umbral más alto alcanzado.
-- Interpola {min,max} entre dos valores de CN (fuera del rango: 0 debajo, max arriba).
function S.cnScaled(d, fromCN, toCN, range)
  if d.neuralLoad < fromCN then return 0 end
  local f = math.min(1, (d.neuralLoad - fromCN) / math.max(1, toCN - fromCN))
  return range.min + (range.max - range.min) * f
end

-- Antidepresivos
function S.antidepActive(d, now)
  return (d.antidepUntil or -1) > (now or S.worldHours())
end

function S.symptomMultiplier(d, now)
  local m = (S.antidepActive(d, now) and CFG.Antidepressant.SymptomMultiplier or 1) * FW.profile(d).symptoms          -- (83) Supresor
  if d.disconnected then m = m * ((CFG.Disconnect or {}).SymptomMult or 0.5) end                                     -- (165) T12: a la mitad
  return m * (CFG.Psychosis.FreqMult or 1)                                     -- (170) C01: intensidad de la cyberpsicosis (sandbox)
end

-- (180) C08: Filtro (FLT). Multiplicador de frecuencia de las alucinaciones que filtra (1 sin el chip). Se aplica AFUERA del piso 0,2 de
-- los sitios que dividen, para que el antidepresivo no se coma el filtro. El clon y el disfraz no pasan por aca.
function S.halluMultiplier(d) return FW.profile(d).hallu end

-- (180) C08: el Filtro apaga el sentido de peligro (marcas reales y fantasma) y el aviso de Heat por sonido.
function S.senseOff(d) return FW.profile(d).noSense == true end

function S.glitchRate(d, now)            -- episodios por segundo real
  local g = CFG.NeuralLoad.Glitch
  return S.cnScaled(d, g.MinCN, 100, g.RatePerSecond) * S.symptomMultiplier(d, now)
end

function S.nosebleedChance(d, now)       -- por minuto in-game
  local n = CFG.NeuralLoad.Nosebleed
  return S.cnScaled(d, n.MinCN, 100, n.ChancePerMinute) * S.symptomMultiplier(d, now)
end

function S.screamChance(d, now)          -- por minuto in-game
  local c = CFG.NeuralLoad.Scream
  now = now or S.worldHours()
  if now - (d.lastScreamHour or -1000) < c.CooldownHours then return 0 end
  return S.cnScaled(d, c.MinCN, 100, c.ChancePerMinute) * S.symptomMultiplier(d, now)
end

function S.thresholdValue(tbl, skill)
  local val = nil
  for _, e in ipairs(tbl) do if skill >= e[1] then val = e[2] end end
  return val
end

-- Cobertura de inmunosupresores
function S.immunoActiveTier(d, now)
  now = now or S.worldHours()
  local im = d.immuno or {}
  if (im.clinicalUntil or -1) > now then return "clinical" end
  if (im.craftedUntil or -1) > now then return "crafted" end
  if (im.herbalUntil or -1) > now then return "herbal" end
  return nil
end

function S.immunoRejectionMultiplier(d, now)
  local tier = S.immunoActiveTier(d, now)
  if not tier then return 1 end
  return CFG.Immunosuppressant[tier].rateMultiplier
end

-- Registra una dosis (dosis de choque: cuenta las de la ventana de NeuralUse).
function S.immunoLogDose(d, now)
  d.immunoDoses = d.immunoDoses or {}          -- fuera de d.immuno: ahí solo hay horas (clinicalUntil...) y se recorre con pairs
  table.insert(d.immunoDoses, now)
end

-- (135) Dosis tomadas en las ultimas NeuralUse.WindowHours (borra las viejas).
function S.immunoDoseCount(d, now)
  now = now or S.worldHours()
  local W = CFG.Immunosuppressant.NeuralUse.WindowHours
  local log, n = d.immunoDoses or {}, 0
  for i = #log, 1, -1 do
    if now - log[i] > W then table.remove(log, i) else n = n + 1 end
  end
  return n
end

-- Multiplicador (<= 1) de la CN por uso segun la cobertura activa. (135) Dosis de choque: las dosis recientes SUBEN la reduccion (Stack, tope Cap).
function S.immunoNeuralMultiplier(d, now)
  now = now or S.worldHours()
  local tier = S.immunoActiveTier(d, now)
  if not tier then return 1 end
  local NU = CFG.Immunosuppressant.NeuralUse
  local n = math.max(1, S.immunoDoseCount(d, now))
  local bonus = NU.Stack[math.min(n, #NU.Stack)] or 0
  return 1 - math.min(NU.Cap, NU[tier] * (1 + bonus))
end

-- (135) Multiplicador extra del decay de CN con ShockDoses dosis o mas en la ventana (y cobertura).
function S.immunoShockDecay(d, now)
  now = now or S.worldHours()
  local NU = CFG.Immunosuppressant.NeuralUse
  if S.immunoActiveTier(d, now) and S.immunoDoseCount(d, now) >= NU.ShockDoses then return NU.ShockDecay end
  return 1
end

-- (135) Tolerancia: lo que cubre la proxima dosis (x1 la primera de la ventana, -ToleranceStep por cada una que ya hay).
function S.immunoDurationFactor(d, now)
  local NU = CFG.Immunosuppressant.NeuralUse
  return math.max(NU.ToleranceFloor, 1 - NU.ToleranceStep * S.immunoDoseCount(d, now))
end

---------------------------------------------------------------------------
-- (135) Inmunodepresion (21-plan-inmunodepresion.md): d.immunodep 0..100, separada de la cobertura
---------------------------------------------------------------------------
local function IDC() return CFG.Immunosuppressant.Immunodepression end

function S.immunodepOn() return (IDC().Level or 0) > 0 end

-- Piso mientras dura la cobertura: el del tier activo mas fuerte (0 sin cobertura).
function S.immunoFloor(d, now)
  local tier = S.immunoActiveTier(d, now)
  return tier and IDC().Floor[tier] or 0
end

-- ID que suma una dosis del tier (Compatibilidad: x perfil.immuno).
function S.immunoDoseGain(d, tier)
  local FW = rawget(_G, "SandevistanFirmware")
  local mult = FW and FW.profile(d).immuno or 1
  return (IDC().Gain[tier] or 0) * mult
end

-- ID despues de una dosis del tier: suma la ganancia y no queda bajo el piso del tier (la primera clinica deja 50; la segunda, 95). Tope 100.
function S.immunoAfterDose(d, tier, now)
  local cur = math.max(d.immunodep or 0, S.immunoFloor(d, now))
  return math.min(100, math.max(cur + S.immunoDoseGain(d, tier), IDC().Floor[tier] or 0))
end

-- Ritmo de bajada por hora. traits = { resilient, prone }, sick = herida infectada / resfrio / malestar (E.sickReason).
function S.immunoDecayRate(asleep, traits, sick)
  local C = IDC()
  local r = asleep and C.DecayAsleep or C.DecayAwake
  traits = traits or {}
  if traits.resilient then r = r * C.Resilient end
  if traits.prone then r = r * C.Prone end
  if sick then r = math.max(math.min(r, C.SickMin), r * C.Sick) end     -- un solo factor; el minimo no lo sube por encima de lo sano
  return r
end

-- Avanza la ID "hours" horas hacia el piso (con cobertura) o hacia 0. El piso puede terminar en el medio: se parte en dos tramos.
function S.immunoTickID(d, now, hours, rate)
  local id = d.immunodep or 0
  if hours <= 0 then return id end
  local start = now - hours
  local left = S.immunoHoursLeft(d, start)
  local floor = S.immunoFloor(d, start)
  if left > 0 and left < hours then                     -- termina la cobertura dentro del tramo
    if id > floor then id = math.max(floor, id - rate * left) end
    id = math.max(0, id - rate * (hours - left))
  elseif left > 0 then
    if id > floor then id = math.max(floor, id - rate * hours) end
  else
    id = math.max(0, id - rate * hours)
  end
  d.immunodep = id
  return id
end

-- Horas hasta volver a 0 al ritmo dado (con la cobertura actual).
function S.immunoHoursToNormal(d, now, rate)
  local id = d.immunodep or 0
  if id <= 0 then return 0 end
  if rate <= 0 then return nil end
  local left, floor = S.immunoHoursLeft(d, now), S.immunoFloor(d, now)
  if left > 0 then
    local atEnd = math.max(math.min(id, floor), id - rate * left)
    return left + atEnd / rate
  end
  return id / rate
end

function S.immunoMoodle(id)
  local m = IDC().Moodles
  id = id or 0
  if id >= m[4] then return 4 elseif id >= m[3] then return 3 elseif id >= m[2] then return 2 elseif id >= m[1] then return 1 end
  return 0
end

-- Fuerza de los efectos: k = ID/100 x Level x rasgo (tope MaxStrength). traits = { resilient, prone, fastHealer, slowHealer }; healing aplica los de curacion.
function S.immunoStrength(d, traits, healing)
  local C = IDC()
  local k = (d.immunodep or 0) / 100 * (C.Level or 0)
  if k <= 0 then return 0 end
  traits = traits or {}
  if traits.resilient then k = k * C.TraitStrength.Resilient end
  if traits.prone then k = k * C.TraitStrength.Prone end
  if healing then
    if traits.fastHealer then k = k * C.HealerStrength.Fast end
    if traits.slowHealer then k = k * C.HealerStrength.Slow end
  end
  return math.min(C.MaxStrength, k)
end

-- Multiplicador de un efecto (Config Immunodepression.Max: infectOnset, infectGrowth, healing, coldCatch, coldStrength, coldRecovery, sickness).
function S.immunoEffect(d, effect, traits)
  local max = IDC().Max[effect] or 1
  return 1 + (max - 1) * S.immunoStrength(d, traits, effect == "healing")
end

-- Rebote: x Rebound.RejectionMult del rechazo mientras dure (escala con Level: leve x1,25, dura x1,75).
function S.immunoReboundMult(d, now)
  now = now or S.worldHours()
  if (d.immunoReboundUntil or -1) <= now then return 1 end
  return 1 + (IDC().Rebound.RejectionMult - 1) * (IDC().Level or 0)
end

function S.immunoHoursLeft(d, now)
  now = now or S.worldHours()
  local im, best = d.immuno or {}, 0
  for _, k in ipairs({ "clinicalUntil", "craftedUntil", "herbalUntil" }) do
    if im[k] and im[k] - now > best then best = im[k] - now end
  end
  return best
end

-- Rechazo por hora que no depende de la adaptacion: la CN crónica (a partir de ChronicThreshold).
-- Mientras haya algo de esto el rechazo no se recupera solo (Periodic.rejectionTick).
function S.chronicRejection(d)
  return (d.neuralLoad >= CFG.Rejection.ChronicThreshold) and CFG.Rejection.ChronicRate or 0
end

function S.adaptationTerm(d, level)
  local v = S.variantCfg(d)
  if not v or level >= v.stableLevel then return 0 end
  local dossier = S.knowsDossier(d, "researcher") and CFG.Notes.ResearcherRejectionMult or 1     -- (106) expediente del investigador completo
  return CFG.Rejection.BaseRate * (1 - level / v.stableLevel) * dossier
end

---------------------------------------------------------------------------
-- (106) Expedientes de notas completos (en shared: los usan la receta del P06, el rechazo y los menus)
---------------------------------------------------------------------------
function S.storyById(id)
  for _, st in ipairs(CFG.Notes.Stories) do if st.id == id then return st end end
end

-- ¿lleva encima el expediente `id` completo? Si lo lleva, ademas queda aprendido (S.knowsDossier) para los beneficios permanentes.
function S.dossierComplete(character, id)
  local st = S.storyById(id)
  if not st or not character then return false end
  local item, raw = nil, nil
  pcall(function() item = character:getInventory():getFirstTypeRecurse("Sandevistan." .. st.dossier) end)
  if not item then return false end
  pcall(function() raw = item:getModData().SandevistanFiled end)
  local c = 0
  if type(raw) == "string" then
    for n in string.gmatch(raw, "%d+") do n = tonumber(n); if st.page[n] then c = c + 1 end end
  end
  local ok = c >= st.total
  if ok then pcall(function() S.data(character).knows["dossier_" .. id] = true end) end
  return ok
end

function S.dossiersComplete(character, ids)
  for _, id in ipairs(ids or {}) do
    if not S.dossierComplete(character, id) then return false end
  end
  return true
end

-- ¿armo alguna vez el expediente completo? (beneficios que quedan aunque despues lo tire)
function S.knowsDossier(d, id) return d and d.knows and d.knows["dossier_" .. id] == true or false end

-- Rechazo que suma un evento (corte térmico, colapso): rango min..max menos la fracción "reduction" a adaptación estable (v0.1.29).
function S.eventRejection(d, min, max, reduction)
  local trait = (d.traits and d.traits.edgerunner) and CFG.Traits.EdgerunnerEventRejectionMult or 1   -- rasgo Edgerunner
  return S.randRange(min, max) * (1 - (reduction or 0) * S.adaptFraction(d)) * trait * FW.profile(d).rejEvent       -- (82) firmware
end

-- (107) temperatura minima del cuerpo por el rechazo (nil = sin fiebre). (162) T09: el analgésico la baja FeverDrop.
function S.feverTemp(r, d, now)
  local t = nil
  for _, e in ipairs(CFG.Rejection.Fever) do if r >= e[1] then t = e[2] end end
  if t and d and S.stopgapPainkillerMult(d, now) < 1 then
    local G = CFG.Stopgaps or {}
    t = math.max(36.5, t - ((G.Painkiller or {}).FeverDrop or 0))
  end
  return t
end

---------------------------------------------------------------------------
-- (162) T09: paliativos (pastillas vanilla). Frenan un poco, no bajan nada de golpe, tienen tolerancia y un tope conjunto.
-- Estado en d.stopgap: painkillerUntil + painkillerDoses (horas de las últimas 24 h), sleepingUntil y betaUntil.
-- Se activan SOLO al tomarlas (Medical.hookAntidep -> applyStopgap), no cuando una receta o una cirugía gasta el ítem.
---------------------------------------------------------------------------
function S.stopgap(d)
  local st = d and d.stopgap
  if type(st) ~= "table" then st = {}; if d then d.stopgap = st end end
  return st
end

-- Multiplicador de rechazo del analgésico, con tolerancia: cada dosis extra en 24 h rinde Diminish de lo anterior.
function S.stopgapPainkillerMult(d, now)
  local G = CFG.Stopgaps or {}
  local pk = G.Painkiller or {}
  local st = S.stopgap(d)
  now = now or S.worldHours()
  if not (G.Enabled and st.painkillerUntil and st.painkillerUntil > now) then return 1 end
  local n = 0
  for _, h in ipairs(st.painkillerDoses or {}) do if now - h < 24 then n = n + 1 end end
  local reduce = (1 - (pk.RejectionMult or 1)) * ((pk.Diminish or 1) ^ math.max(0, n - 1))
  return math.max((G.Caps and G.Caps.RejectionMult) or 0, 1 - reduce)
end

function S.stopgapSleeping(d, now)
  local G = CFG.Stopgaps or {}
  local st = S.stopgap(d)
  now = now or S.worldHours()
  return (G.Enabled and st.sleepingUntil and st.sleepingUntil > now) and true or false
end

function S.stopgapBeta(d, now)
  local G = CFG.Stopgaps or {}
  local st = S.stopgap(d)
  now = now or S.worldHours()
  return (G.Enabled and st.betaUntil and st.betaUntil > now) and true or false
end

-- Rechazo: analgésico y, durmiendo con somnífero, el factor de la noche. El tope conjunto es el del analgésico.
function S.stopgapRejectionMult(d, now, asleep)
  local mult = S.stopgapPainkillerMult(d, now)
  if asleep and S.stopgapSleeping(d, now) then
    mult = mult * ((CFG.Stopgaps.Sleeping or {}).SleepRejectionMult or 1)
  end
  return mult
end

function S.stopgapCNMult(d, now)
  if not S.stopgapBeta(d, now) then return 1 end
  local G = CFG.Stopgaps or {}
  return math.max((G.Caps and G.Caps.CNUseMult) or 0, (G.Beta and G.Beta.CNUseMult) or 1)
end

function S.stopgapScreamMult(d, now)
  if not S.stopgapBeta(d, now) then return 1 end
  return ((CFG.Stopgaps.Beta or {}).ScreamMult) or 1
end

function S.stopgapTerrorMult(d, now)
  if not S.stopgapBeta(d, now) then return 1 end
  return ((CFG.Stopgaps.Beta or {}).TerrorMult) or 1
end

function S.stopgapNoNightTerrors(d, now)
  return S.stopgapSleeping(d, now) and ((CFG.Stopgaps.Sleeping or {}).NoNightTerrors ~= false)
end

-- Rechazo máximo con el que todavía deja dormir (75 sin paliativo; hasta AllowSleepUpTo con el somnífero).
function S.stopgapSleepLimit(d, now)
  local limit = CFG.Rejection.BlockSleepAt
  if S.stopgapSleeping(d, now) then limit = math.max(limit, ((CFG.Stopgaps.Sleeping or {}).AllowSleepUpTo) or limit) end
  return limit
end

function S.rejectionMoodle(r)
  local m = CFG.Rejection.Moodles
  if r >= m[4] then return 4 elseif r >= m[3] then return 3 elseif r >= m[2] then return 2 elseif r >= m[1] then return 1 end
  return 0
end

function S.toxicityMoodle(t)
  local m = CFG.Immunosuppressant.HerbalToxicity.Moodles
  if t >= m[4] then return 4 elseif t >= m[3] then return 3 elseif t >= m[2] then return 2 elseif t >= m[1] then return 1 end
  return 0
end

-- Crea un ítem en un contenedor de forma que el servidor lo conozca (MP): AddItem(String) en el cliente crea un ítem
-- que el servidor no reconoce y no se puede tirar ni mover (v0.1.25). ItemSpawner.spawnItem lo registra bien.
-- md (opcional): ModData que se pone ANTES de avisar a los clientes (puesto despues, no les llega).
-- En el servidor, ItemSpawner.spawnItem(tipo, contenedor) solo hace AddItem (verificado en 42.21): no avisa a nadie. Sin sendAddItemToContainer el ítem
-- lo ve solo quien carga ese chunk despues (lo baja entero del servidor); quien ya lo tenia cargado no se entera hasta que alguien lo mueve.
function S.giveItem(container, fullType, md)
  local item = nil
  local via = nil
  local function withMd(it)
    if it and md then for k, v in pairs(md) do it:getModData()[k] = v end end
    return it
  end
  -- Cliente en multijugador: patrón vanilla del panel de admin (instanceItem + AddItem + sendAddItemToContainer). Es el
  -- que produce ítems que el servidor conoce (se pueden tirar/mover); ItemSpawner desde el cliente no lo garantiza.
  if isClient() and not isServer() and rawget(_G, "instanceItem") and rawget(_G, "sendAddItemToContainer") then
    pcall(function()
      item = withMd(instanceItem(fullType))
      if item then container:AddItem(item); sendAddItemToContainer(container, item); via = "instanceItem+send" end
    end)
    if not via then item = nil end
  end
  if not item and rawget(_G, "ItemSpawner") and ItemSpawner.spawnItem then
    pcall(function()
      local proto = md and rawget(_G, "instanceItem") and withMd(instanceItem(fullType))
      if proto then item = ItemSpawner.spawnItem(proto, container) else item = ItemSpawner.spawnItem(fullType, container) end
    end)
    if type(item) == "boolean" then item = nil end
    if item then
      via = "ItemSpawner"
      withMd(item)
      if isServer() and rawget(_G, "sendAddItemToContainer") then
        pcall(sendAddItemToContainer, container, item)
        via = "ItemSpawner+send"
      end
    end
  end
  if not item then
    pcall(function()
      item = withMd(container:AddItem(fullType))
      -- servidor o cliente que no pasó por ItemSpawner: avisar a los demás para que el ítem exista también allá
      if item and (isClient() or isServer()) and rawget(_G, "sendAddItemToContainer") then sendAddItemToContainer(container, item) end
    end)
    if item then via = "AddItem" end
  end
  if via and via ~= S.lastGiveVia then S.lastGiveVia = via; S.log("giveItem via " .. via) end
  return item
end

-- (115) Cliente de multijugador (no el servidor ni SP).
function S.isMPClient() return isClient() and not isServer() end

-- (115) El ModData de un ítem que cambia el cliente no le llega al servidor (SyncItemModData va solo del servidor al cliente, verificado en el jar):
-- se le pide al servidor que lo ponga (comando "itemMd", lo busca por id en el inventario del jugador). keys = claves del ModData a copiar (las que
-- quedaron en nil se borran alla); el nombre va si es propio (setCustomName). Sin efecto en SP y en el servidor.
function S.syncItem(player, item, keys)
  if not item or not S.isMPClient() then return end
  player = player or getSpecificPlayer(0)
  local id = nil
  pcall(function() id = item:getID() end)
  if not player or not id then return end
  local md, clear, src = {}, {}, item:getModData()
  for _, k in ipairs(keys or {}) do
    if src[k] == nil then clear[#clear + 1] = k else md[k] = src[k] end
  end
  local name = nil
  pcall(function() if item:isCustomName() then name = item:getName() end end)
  sendClientCommand(player, "Sandevistan", "itemMd", { id = id, md = md, clear = table.concat(clear, ","), name = name })
end

-- (115) Consumo de un ítem hecho en el cliente (una dosis de un drenable, un poco de un fluido): en multijugador el servidor tiene su propia copia
-- y el juego solo sincroniza si el consumo corre alla (Use(..., true) y sendSyncEntity no hacen nada en un cliente). Se le pide que lo repita
-- (comando "consume"). op = "use" | "fluid" (amount = litros). Sin efecto en SP y en el servidor.
function S.serverUse(player, item, op, amount)
  if not item or not S.isMPClient() then return end
  local id = nil
  pcall(function() id = item:getID() end)
  player = player or getSpecificPlayer(0)
  if id and player then sendClientCommand(player, "Sandevistan", "consume", { id = id, op = op, amount = amount }) end
end

-- (114) Da un ítem al jugador de forma que el SERVIDOR lo conozca. En 42.21 sendAddItemToContainer no hace nada si lo llama un cliente (solo anda en el
-- servidor; verificado en LuaManager): el ítem que crea el cliente existe solo en su pantalla y el servidor no lo deja tirar, mover ni pasar a otro
-- jugador (pasaba con las carpetas de notas). En un cliente de multijugador se le pide al servidor (comando "give") y se devuelve true, no el ítem:
-- el ModData (md) y el nombre (name) van en el pedido. En SP y en el servidor se crea aca y se devuelve el ítem.
-- S.localItems (lo prenden la PRUEBA COMPLETA y el RECORRIDO mientras corren): se crean aca igual, porque las pruebas usan el ítem y lo borran al terminar.
function S.grantItem(player, fullType, md, name)
  if isClient() and not isServer() and not S.localItems then
    sendClientCommand(player, "Sandevistan", "give", { type = fullType, md = md, name = name })
    return true
  end
  local item = S.giveItem(player:getInventory(), fullType, md)
  if item and name then pcall(function() item:setName(name); item:setCustomName(true) end) end
  return item
end

-- getText que, para los requisitos de ítems vanilla (bisturí, aguja, espejo...), usa el nombre que el propio juego
-- le da al ítem en el idioma activo (los nombres escritos a mano pueden no coincidir con la traducción vanilla).
-- (160) el espejo ya no va acá: el motivo dice que también sirve uno del mundo (IGUI_Sandevistan_Req_MirrorPlace)
local REQ_ITEMS = { IGUI_Sandevistan_Req_Scalpel = "Base.Scalpel", IGUI_Sandevistan_Req_Suture = "Base.SutureNeedle",
  IGUI_Sandevistan_Req_Screwdriver = "Base.Screwdriver" }
function S.text(key, ...)
  local ft = REQ_ITEMS[key]
  if ft then
    local name = nil
    pcall(function() name = getItemNameFromFullType(ft) end)
    if name and name ~= "" and name ~= ft then return getText("IGUI_Sandevistan_Req_Missing", name) end
  end
  return getText(key, ...)
end

-- Envuelve un handler de evento: un error se reporta una vez (con conteo) en vez de
-- inundar la consola en cada tick.
local errCount = {}
---------------------------------------------------------------------------
-- Rendimiento (v0.1.30): cada handler envuelto con S.safe suma su tiempo (ms reales). El reloj es de milisegundos: una llamada suele
-- medir 0 o 1, pero sumadas miles de llamadas el promedio es fiel (el error de redondeo se compensa). S.perfAdd / S.perfCount para
-- secciones internas y contadores. El reporte de diagnóstico lo vuelca; la PRUEBA COMPLETA los reinicia al empezar su tramo de 25 s.
---------------------------------------------------------------------------
S.perf = { since = nil, spans = {}, counts = {} }
local function clockMs() local f = rawget(_G, "getTimestampMs"); return f and f() or 0 end
S.clockMs = clockMs
function S.perfReset()
  S.perf.since = clockMs(); S.perf.spans = {}; S.perf.counts = {}
end
function S.perfAdd(name, ms)
  local sp = S.perf.spans[name]
  if not sp then sp = { calls = 0, total = 0, max = 0 }; S.perf.spans[name] = sp end
  sp.calls = sp.calls + 1
  sp.total = sp.total + ms
  if ms > sp.max then sp.max = ms end
end
function S.perfCount(name, n)
  local c = S.perf.counts
  c[name] = (c[name] or 0) + (n or 1)
end

function S.safe(name, fn)
  return function(...)
    local t0 = clockMs()
    if not S.perf.since then S.perf.since = t0 end
    local ok, err = pcall(fn, ...)
    S.perfAdd(name, clockMs() - t0)
    if not ok then
      errCount[name] = (errCount[name] or 0) + 1
      local n = errCount[name]
      if n == 1 or n == 100 or n % 10000 == 0 then
        S.logAlways("ERROR en " .. name .. " (x" .. n .. "): " .. tostring(err))
      end
    end
  end
end

-- Texto ASCII para reportes en archivo. Sin gsub (Kahlua lo resuelve mal con acentos):
-- recorre por código de carácter y soporta tanto strings Unicode (Kahlua) como UTF-8 crudo.
local CODE = { [225] = "a", [233] = "e", [237] = "i", [243] = "o", [250] = "u", [241] = "n",
  [193] = "A", [201] = "E", [205] = "I", [211] = "O", [218] = "U", [209] = "N",
  [252] = "u", [191] = "?", [161] = "!", [8776] = "~", [8594] = "->", [8212] = "-", [8211] = "-" }
local UTF8_C3 = { [161] = "a", [169] = "e", [173] = "i", [179] = "o", [186] = "u", [177] = "n",
  [129] = "A", [137] = "E", [141] = "I", [147] = "O", [154] = "U", [145] = "N", [188] = "u" }
function S.ascii(text)
  local r = tostring(text)
  local out, i, n = {}, 1, string.len(r)
  while i <= n do
    local b = string.byte(r, i)
    if b < 128 then
      out[#out + 1] = string.sub(r, i, i); i = i + 1
    elseif CODE[b] then
      out[#out + 1] = CODE[b]; i = i + 1
    elseif b == 195 and i < n then
      out[#out + 1] = UTF8_C3[string.byte(r, i + 1)] or "?"; i = i + 2
    elseif b == 194 and i < n then
      out[#out + 1] = CODE[string.byte(r, i + 1)] or "?"; i = i + 2
    elseif b >= 224 and b < 240 and i + 2 <= n then
      local cp = (b - 224) * 4096 + (string.byte(r, i + 1) - 128) * 64 + (string.byte(r, i + 2) - 128)
      out[#out + 1] = CODE[cp] or "?"; i = i + 3
    else
      out[#out + 1] = "?"; i = i + 1
    end
  end
  return table.concat(out)
end

-- Kahlua no expone next(): comprobar tablas vacías con pairs.
function S.isEmpty(t)
  if t == nil then return true end
  for _ in pairs(t) do return false end
  return true
end

-- (194) Un "si" de fn() guardado ttlMs (reloj real) mientras dep (el backend) sea el mismo. Para preguntas que se hacian en cada tick
-- (si el jar de la cyberpsicosis esta listo): con el jar, costaban llamadas a Java en cada tick aunque no hubiera cyberpsicosis. El "no" no se
-- guarda: sin el jar la pregunta es Lua puro, y asi el jar que aparece tarde se ve enseguida.
local cachedVals = {}
function S.cached(key, ttlMs, fn, dep)
  local now = getTimestampMs()
  local c = cachedVals[key]
  if c and c.dep == dep and now < c.untilMs then return c.v end
  local v = fn()
  if v then cachedVals[key] = { v = v, untilMs = now + ttlMs, dep = dep } else cachedVals[key] = nil end
  return v
end
function S.cacheClear(key) cachedVals[key] = nil end

function S.randRange(a, b) return a + ZombRandFloat(0, 1) * (b - a) end
function S.chance(p) return ZombRandFloat(0, 1) < p end

---------------------------------------------------------------------------
-- (167) T13: mapas anotados. Se registran al cargar (y el cliente suma la vista del mapa en OnGameBoot).
require "Sandevistan/AnnotatedMaps"

return S
