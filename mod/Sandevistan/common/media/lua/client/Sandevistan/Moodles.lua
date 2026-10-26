-- Sandevistan / Moodles: los estados del implante como moodles del juego, a través de Moodle Framework (MF).
-- Los moodles son el indicador real del estado (como los vanilla): Heat, bloqueo, rechazo, Carga Neuronal,
-- cyberpsicosis, toxicidad, inmunodepresion, sangrado nasal, bajón de Kerenzikov y implante destruido (malos); dilatación
-- activa, Kerenzikov, cobertura de inmunosupresores y antidepresivos (buenos). El panel propio (HUD.lua y la
-- pestaña "Implante") queda como detalle opcional; si MF no está, el panel flotante se muestra solo.
--
-- Convención de MF (B42): MF.createMoodle(nombre) al cargar; textos en Translate/<IDIOMA>/Moodles.json
-- (Moodles_<nombre>_<Good|Bad>_lvl<N> y ..._desc_lvl<N>); íconos media/ui/<nombre>.png (96x96; el juego los escala) y
-- <nombre>_<Good|Bad>_<N>.png. El mod fija el valor 0..1 (0.5 = oculto; por debajo malo, por encima bueno).
--
-- v0.1.25: el registro fallaba porque corría al cargar el archivo, antes de que MF existiera, y nunca
-- reintentaba (require de MF_ISMoodle dentro del "if disponible"). Ahora: require primero, reintentos en
-- OnGameBoot / OnGameStart / OnCreatePlayer / OnTick, umbrales por jugador al primer uso, y un moodle que
-- todavía no existe no invalida al resto. Todo va con pcall y no lanza errores (el depurador con
-- "Break On Error" se detiene aunque haya pcall).
require "Sandevistan/Core"
require "Sandevistan/Kerenzikov"

local CFG = SandevistanConfig
local S = Sandevistan

-- La sesión en memoria (activo, overdrive, tramo) vive en Runtime.lua; se consulta perezosamente para no depender del orden de carga.
local function session(p)
  local R = rawget(_G, "SandevistanRuntime")
  return R and R.session(p) or {}
end

SandevistanMoodles = {}
local M = SandevistanMoodles

M.registered = false     -- createMoodle hecho para todos
M.ready = false          -- al menos un valor llegó al moodle del jugador 0: el panel flotante se oculta solo
M.failed = false         -- MF respondió con errores repetidos
M.created = {}           -- [nombre] = true
M.applied = {}           -- [numJugador][nombre] = { obj = moodle, key = "Bad2" }: lo último enviado
M.cache = {}             -- [numJugador] = { ms, list }: estados calculados (para el panel y la pestaña)
M.lastUpdateMs, M.lastTryMs = 0, -100000
M.attempts, M.errStreak = 0, 0
M.lastError = nil

local function bad(level) return 0.45 - 0.1 * level end      -- nivel 1..4 -> 0.35 .. 0.05
local function good(level) return 0.55 + 0.1 * level end     -- nivel 1..4 -> 0.65 .. 0.95

function M.valueFor(kind, level)
  if not level or level <= 0 then return 0.5 end
  return kind == "Good" and good(level) or bad(level)
end

-- nivel 0..4 según una tabla de umbrales ascendente { n1, n2, n3, n4 }
local function band(v, t)
  if v >= t[4] then return 4 elseif v >= t[3] then return 3 elseif v >= t[2] then return 2 elseif v >= t[1] then return 1 end
  return 0
end

local function tierIndex(s, d)
  local tier = s.tier or S.dilationTier(d, S.level(d))
  for i, t in ipairs(CFG.DilationTiers) do if t == tier then return i end end
  return 1
end

---------------------------------------------------------------------------
-- Definiciones. level(p, d, s, now) devuelve el nivel 0..4 (0 = oculto). "single": moodle de un solo nivel
-- (usa ese nivel para el color; los cuatro textos son iguales). "row": se lista como fila de texto en el
-- panel flotante cuando MF no está (los demás ya tienen barra o franja propia). "hud": ícono del panel.
---------------------------------------------------------------------------
local MC = CFG.Moodles

M.DEFS = {
  { name = "SandevistanHeat", kind = "Bad", hud = "Heat",
    level = function(p, d) return S.hasWorkingImplant(d) and band(S.heatPct(d), MC.Heat) or 0 end },
  { name = "SandevistanLockout", kind = "Bad", single = 2, hud = "Heat",
    level = function(p, d) return (S.hasWorkingImplant(d) and d.lockUntilCool and (d.heat or 0) > 0) and 2 or 0 end },
  { name = "SandevistanRejection", kind = "Bad", hud = "Rejection",
    level = function(p, d) return S.hasWorkingImplant(d) and S.rejectionMoodle(d.rejection or 0) or 0 end },
  { name = "SandevistanNeuralLoad", kind = "Bad", hud = "Neural",
    level = function(p, d) return band(d.neuralLoad or 0, MC.NeuralLoad) end },
  { name = "SandevistanCyberpsychosis", kind = "Bad", hud = "Neural", row = true,
    level = function(p, d, s, now)
      if not d.cyberpsychosisActive then return 0 end
      local cn, t = d.neuralLoad or 0, MC.Cyberpsychosis
      if cn >= t[3] then return 4 elseif cn >= t[2] then return 3 elseif cn >= t[1] then return 2 end
      if S.remissionHoursLeft(d, now) then return 0 end        -- (66) en remision lo cuentan los moodles de la recuperacion
      return 1
    end },
  -- (66) Recuperacion: abstinencia de los primeros dias (Bad: 2 = mas de un dia, 1 = menos) y despues la cuenta de lo que falta para la remision (Good: 1 = mas de 2 dias ... 4 = menos de medio dia)
  { name = "SandevistanWithdrawal", kind = "Bad", hud = "Pill", row = true,
    level = function(p, d, s, now)
      local left = S.withdrawalHoursLeft(d, now)
      if not left then return 0 end
      return left > MC.WithdrawalEasingHours and 2 or 1
    end },
  { name = "SandevistanRecovery", kind = "Good", hud = "Pill", row = true,
    level = function(p, d, s, now)
      local rem = S.remissionHoursLeft(d, now)
      if not rem or S.withdrawalHoursLeft(d, now) then return 0 end
      local t = MC.RecoveryHours
      if rem > t[3] then return 1 elseif rem > t[2] then return 2 elseif rem > t[1] then return 3 end
      return 4
    end },
  { name = "SandevistanToxicity", kind = "Bad", hud = "Leaf", row = true,
    level = function(p, d) return S.toxicityMoodle(d.herbalToxicity or 0) end },
  -- (135) inmunodepresion: niveles por ID (Immunodepression.Moodles); apagada por sandbox, nunca
  { name = "SandevistanImmunodep", kind = "Bad", hud = "Pill", row = true,
    level = function(p, d) return S.immunodepOn() and S.immunoMoodle(d.immunodep) or 0 end },
  { name = "SandevistanKereCrash", kind = "Bad", hud = "Bolt", row = true,
    level = function(p) return Kerenzikov.crashLevel(p) end },
  -- (139) Deuda de estamina (27 §2): lo que el cuerpo gasto con el implante encendido, como proporcion de la resistencia que tenia al
  -- encender (MoodleSteps 25/50/75/100 %). Se paga de golpe al apagar.
  { name = "SandevistanBorrowed", kind = "Bad", hud = "Bolt", row = true,
    level = function(p, d, s)
      local D = CFG.Stamina.Deferred
      if not (s.active and D and D.Enabled) then return 0 end
      return band(S.staminaDebtRatio(s.staminaDebt, s.enduranceMark), D.MoodleSteps)
    end },
  { name = "SandevistanDestroyed", kind = "Bad", single = 3, hud = "Rejection",
    level = function(p, d) return d.variant == "destroyed" and 3 or 0 end },
  { name = "SandevistanActive", kind = "Good", hud = "Bolt",
    level = function(p, d, s)
      if not s.active then return 0 end
      if s.overdrive then return 4 end
      return math.min(3, tierIndex(s, d))
    end },
  { name = "SandevistanKerenzikov", kind = "Good", single = 2, hud = "Bolt", row = true,
    level = function(p) return Kerenzikov.isActive(p) and 2 or 0 end },
  { name = "SandevistanCoverage", kind = "Good", hud = "Pill",
    level = function(p, d, s, now)
      local h = S.immunoHoursLeft(d, now)
      if h <= 0 then return 0 end
      local t = MC.CoverageHours
      if h >= t[3] then return 4 elseif h >= t[2] then return 3 elseif h >= t[1] then return 2 end
      return 1
    end },
  { name = "SandevistanAntidep", kind = "Good", single = 1, hud = "Pill", row = true,
    level = function(p, d, s, now) return S.antidepActive(d, now) and 1 or 0 end },
  -- (88) Recalibrando: tras cambiar un chip de firmware el Heat sube un 10 % mas durante una hora de juego (un solo moodle para todos los chips)
  { name = "SandevistanRecalibrating", kind = "Bad", single = 1, hud = "Bolt", row = true,
    level = function(p, d)
      local FW = rawget(_G, "SandevistanFirmware")
      return (FW and S.hasWorkingImplant(d) and FW.recalLeft(d) > 0) and 1 or 0
    end },
}
local DEFS = M.DEFS

function M.textKey(def, level, desc)
  return "Moodles_" .. def.name .. "_" .. def.kind .. (desc and "_desc" or "") .. "_lvl" .. level
end

-- Estados activos del jugador: { def, name, kind, level, title, desc, hud, row }. Se recalcula cada 200 ms.
function M.states(p)
  local idx = 0
  pcall(function() idx = p:getPlayerNum() end)
  local now = S.realMs()
  local c = M.cache[idx]
  if c and now - c.ms < 200 then return c.list end
  local d, s, hours = S.data(p), session(p), S.worldHours()
  local list = {}
  for _, def in ipairs(DEFS) do
    local lvl = def.level(p, d, s, hours) or 0
    if lvl > 0 then
      list[#list + 1] = { def = def, name = def.name, kind = def.kind, level = lvl, hud = def.hud, row = def.row,
                          title = getText(M.textKey(def, lvl)), desc = getText(M.textKey(def, lvl, true)) }
    end
  end
  M.cache[idx] = { ms = now, list = list }
  return list
end

---------------------------------------------------------------------------
-- Moodle Framework
---------------------------------------------------------------------------
function M.available()
  return rawget(_G, "MF") ~= nil and type(MF.createMoodle) == "function" and type(MF.getMoodle) == "function"
end

-- Crea los moodles en MF. Se llama al cargar y de nuevo en OnGameBoot / OnGameStart / OnCreatePlayer / OnTick
-- (con "force" desde los eventos; desde OnTick, como mucho cada RetrySeconds y MaxRetries veces).
function M.tryRegister(force)
  if M.registered then return true end
  local now = S.realMs()
  if not force then
    if M.attempts >= MC.MaxRetries or now - M.lastTryMs < MC.RetrySeconds * 1000 then return false end
  end
  M.lastTryMs = now
  if not M.available() and not M.requireTried then
    M.requireTried = true                    -- una sola vez: si MF no está instalado, require falla y deja una línea en la consola
    pcall(require, "MF_ISMoodle")            -- carga el framework si todavía no se ejecutó (su archivo de cliente)
  end
  if not M.available() then
    M.attempts = M.attempts + 1
    return false
  end
  local okAll = true
  for _, def in ipairs(DEFS) do
    if not M.created[def.name] then
      local ok, err = pcall(MF.createMoodle, def.name)
      if ok then
        M.created[def.name] = true
      else
        okAll = false
        M.lastError = "createMoodle(" .. def.name .. "): " .. tostring(err)
        S.warnOnce("mfCreate", "Moodle Framework: " .. M.lastError)
      end
    end
  end
  M.attempts = M.attempts + 1
  M.registered = okAll
  if okAll then S.log("moodles registrados en Moodle Framework (" .. #DEFS .. ")") end
  return okAll
end

local function getMoodle(name, idx)
  local ok, m = pcall(MF.getMoodle, name, idx)
  if ok then return m end
  return nil
end

-- Umbrales por objeto (se fijan la primera vez que se ve el moodle de ese jugador). Los de MF ya son
-- 0.1/0.2/0.3/0.4 y 0.6/0.7/0.8/0.9; se envían igual por si cambian. Si no existe el método, no pasa nada.
local function configure(m)
  if type(m.setThresholds) ~= "function" then return end
  local t = MC.Thresholds
  local ok, err = pcall(function() m:setThresholds(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8]) end)
  if not ok then S.warnOnce("mfThresholds", "Moodle Framework: setThresholds falló (" .. tostring(err) .. ")") end
end

-- Envía el valor al moodle del jugador. Devuelve true si llegó. Un moodle que aún no existe se ignora.
local function push(idx, def, key, value)
  local m = getMoodle(def.name, idx)
  if not m then
    M.missingSince = M.missingSince or S.realMs()
    return false
  end
  M.applied[idx] = M.applied[idx] or {}
  local rec = M.applied[idx][def.name]
  if rec and rec.obj == m and rec.key == key then return true end
  if not rec or rec.obj ~= m then configure(m) end
  local ok, err = pcall(function() m:setValue(value) end)
  if not ok then
    M.errStreak = M.errStreak + 1
    M.lastError = "setValue(" .. def.name .. "): " .. tostring(err)
    S.warnOnce("mfSet", "Moodle Framework: " .. M.lastError)
    if M.errStreak >= 5 then M.failed = true; M.ready = false end   -- el panel flotante vuelve a mostrarse
    return false
  end
  M.errStreak = 0
  M.applied[idx][def.name] = { obj = m, key = key }
  if idx == 0 then M.ready = true; M.missingSince = nil end
  return true
end

---------------------------------------------------------------------------
-- Prueba (Debug → Interfaz y visual → Moodles): recorre todos los moodles y niveles, 1.5 s cada uno, y muestra el título esperado.
---------------------------------------------------------------------------
local function testSteps()
  local steps = {}
  for _, def in ipairs(DEFS) do
    if def.single then
      steps[#steps + 1] = { def = def, level = def.single, label = def.name .. " " .. def.kind .. " " .. def.single }
    else
      for l = 1, 4 do steps[#steps + 1] = { def = def, level = l, label = def.name .. " " .. def.kind .. " " .. l } end
    end
  end
  return steps
end

function M.startTest() M.testStart = S.realMs(); M.testStep = nil; M.applied = {} end

function M.update()
  local now = S.realMs()
  if now - M.lastUpdateMs < MC.UpdateMs then return end
  M.lastUpdateMs = now
  if not M.registered then M.tryRegister(false) end      -- reintenta con acelerador; los ya creados funcionan igual
  if M.failed then return end

  local testStep = nil
  if M.testStart then
    local steps = testSteps()
    local i = math.floor((now - M.testStart) / 1500) + 1
    if i > #steps then
      M.testStart = nil; M.applied = {}
    else
      testStep = steps[i]
      if M.testStep ~= i then
        M.testStep = i
        local title = getText(M.textKey(testStep.def, testStep.level))
        S.log("moodles prueba: " .. testStep.label .. " -> " .. tostring(title))
        local hp = getSpecificPlayer(0)
        if hp and HaloTextHelper and HaloTextHelper.addText then
          pcall(function() HaloTextHelper.addText(hp, testStep.label .. ": " .. tostring(title), "", 255, 255, 255) end)
        end
      end
    end
  end

  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p and not p:isDead() then
      local d, s, hours = S.data(p), session(p), S.worldHours()
      for _, def in ipairs(DEFS) do
        local lvl
        if M.testStart then
          lvl = (testStep and testStep.def == def) and testStep.level or 0
        else
          lvl = def.level(p, d, s, hours) or 0
        end
        if M.created[def.name] then
          push(idx, def, lvl > 0 and (def.kind .. lvl) or "none", M.valueFor(def.kind, lvl))
          if M.failed then return end
        end
      end
    end
  end

  -- se registró pero MF no entrega los moodles del jugador: avisar una vez (se crean al cargar la partida)
  if M.missingSince and not M.ready and now - M.missingSince > 15000 then
    S.warnOnce("mfMissing", "Moodle Framework no entregó los moodles del jugador tras 15 s: se crean al empezar la "
      .. "partida; si el mod se activó tarde, reiniciá el juego. Detalle: sección 'diagnostico de moodles' del REPORTE (Debug > Pruebas e informes).")
  end
end

---------------------------------------------------------------------------
-- Diagnóstico: lo incluye el REPORTE (sección 'diagnostico de moodles'); sin quiet también va a la consola con el prefijo [Sandevistan].
---------------------------------------------------------------------------
local function sortedKeys(t)
  local ks = {}
  for k, v in pairs(t) do ks[#ks + 1] = tostring(k) .. ":" .. type(v) end
  table.sort(ks)
  return ks
end

function M.diagnose(quiet)
  local out = {}
  local function add(t) out[#out + 1] = t; if not quiet then S.log("moodles: " .. t) end end
  local mf = rawget(_G, "MF")
  add("MF = " .. tostring(mf ~= nil) .. "; createMoodle = " .. tostring(mf ~= nil and mf.createMoodle ~= nil)
      .. "; getMoodle = " .. tostring(mf ~= nil and mf.getMoodle ~= nil) .. "; MF_ISMoodle = " .. tostring(rawget(_G, "MF_ISMoodle") ~= nil))
  pcall(function()
    local mods, found = getActivatedMods(), {}
    for i = 0, mods:size() - 1 do
      local id = tostring(mods:get(i))
      if string.find(string.lower(id), "moodle") then found[#found + 1] = id end
    end
    add("mods activos con 'moodle': " .. (#found > 0 and table.concat(found, ", ") or "ninguno") .. " (de " .. mods:size() .. ")")
  end)
  add("registrados=" .. tostring(M.registered) .. " listos=" .. tostring(M.ready) .. " fallo=" .. tostring(M.failed)
      .. " intentos=" .. M.attempts .. " ultimoError=" .. tostring(M.lastError))
  if mf then
    local ok, ks = pcall(sortedKeys, mf)
    add("contenido de MF: " .. (ok and table.concat(ks, " ") or "(no se pudo listar)"))
  else
    add("Moodle Framework no esta cargado: activá el mod 'Moodle Framework' (B42) y reiniciá la partida")
  end
  for _, def in ipairs(DEFS) do
    local info = "creado=" .. tostring(M.created[def.name] == true)
    if mf and mf.getMoodle then
      local m = getMoodle(def.name, 0)
      if m then
        info = info .. " objeto=si setValue=" .. tostring(type(m.setValue) == "function")
          .. " setThresholds=" .. tostring(type(m.setThresholds) == "function")
      else
        info = info .. " objeto=NO (todavia no lo entrega MF)"
      end
    end
    local lvl = def.single or 1
    info = info .. "; texto=" .. tostring(getTextOrNull(M.textKey(def, lvl))) .. "; ícono="
      .. tostring(getTexture("media/ui/" .. def.name .. ".png") ~= nil)
    add(def.name .. ": " .. info)
  end
  -- métodos del moodle de MF (para ajustar la integración si algo no encaja)
  if mf and mf.getMoodle then
    local m = getMoodle(DEFS[1].name, 0)
    if m then
      pcall(function()
        local mt = getmetatable(m)
        local idxT = mt and mt.__index
        if type(idxT) == "table" then add("métodos del moodle: " .. table.concat(sortedKeys(idxT), " ")) end
      end)
    end
  end
  local p = getSpecificPlayer(0)
  if p then
    local names = {}
    for _, st in ipairs(M.states(p)) do names[#names + 1] = st.name .. " " .. st.kind .. " " .. st.level end
    add("estados ahora: " .. (#names > 0 and table.concat(names, "; ") or "ninguno"))
  end
  return out
end

local function on(event, fn)
  if Events and Events[event] then Events[event].Add(fn) end
end

pcall(M.tryRegister, true)            -- al cargar: si MF ya está (o se puede cargar con require), queda registrado
on("OnGameBoot", S.safe("Moodles.OnGameBoot", function() M.tryRegister(true) end))
on("OnGameStart", S.safe("Moodles.OnGameStart", function() M.tryRegister(true); M.applied = {} end))
on("OnCreatePlayer", S.safe("Moodles.OnCreatePlayer", function(idx)
  M.tryRegister(true)
  M.applied[idx or 0] = nil            -- jugador nuevo (o reaparecido): MF crea moodles nuevos, se vuelven a enviar
  M.cache[idx or 0] = nil
end))
on("OnTick", S.safe("Moodles.OnTick", M.update))

return M
