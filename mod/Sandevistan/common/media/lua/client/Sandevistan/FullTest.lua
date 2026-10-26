-- Sandevistan / FullTest: prueba todos los sistemas dentro del juego sin jugar.
-- Paso 1 de Debug → Pruebas e informes → PRUEBA COMPLETA (ver TestSuite). Guarda una copia del estado del personaje, corre
-- las pruebas con tiempo simulado, restaura el estado y borra los ítems de prueba.
-- Recomendado con un personaje de prueba: algunas pruebas consumen ítems iguales a los tuyos.
require "Sandevistan/Core"
require "Sandevistan/Kerenzikov"
require "Sandevistan/Effects"
require "Sandevistan/Slowdown"
require "Sandevistan/Runtime"
require "Sandevistan/Periodic"
require "Sandevistan/Medical"
require "Sandevistan/Dossier"

local CFG = SandevistanConfig
local S = Sandevistan
local E = SandevistanEffects
local R = SandevistanRuntime
local P = SandevistanPeriodic
local M = SandevistanMedical
local V = CFG.Crafting.Items

SandevistanFullTest = {}
local F = SandevistanFullTest
F.checkLog = nil                -- (53) las pruebas offline (tools/tests/fulltest_new.lua) leen el resultado de cada comprobacion

local lines, passed, failed = {}, 0, 0
local function out(l) l = S.ascii(l); table.insert(lines, l); print("[Sandevistan][FULLTEST] " .. l) end
local function check(name, cond, detail)
  if cond then passed = passed + 1 else failed = failed + 1 end
  if F.checkLog then F.checkLog[#F.checkLog + 1] = { name = name, ok = cond and true or false, detail = detail } end
  out((cond and "[OK]    " or "[FALLA] ") .. name .. (detail and ("  (" .. detail .. ")") or ""))
end
local function f1(x) return string.format("%.1f", x or -1) end

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = deepcopy(v) end
  return c
end

local function add(p, t, n) for _ = 1, (n or 1) do p:getInventory():AddItem(t) end end

-- Avanza la simulación "seconds" segundos en pasos de 0.25 s (tiempo simulado, no real).
local function simulate(p, seconds)
  local s = R.session(p)
  for _ = 1, math.floor(seconds / 0.25 + 0.5) do
    s.lastMs = S.realMs() - 250
    R.onTick()
  end
end

local function coolDown(p)
  local d = S.data(p)
  local guard = 0
  while d.heat > 0 and guard < 2000 do simulate(p, 1); guard = guard + 1 end
  d.cooldownMult = 1
  R.session(p).reuseAtMs = 0
end

-- Envuelve una prueba: al terminar (bien o con error) borra del inventario todo lo que la prueba agrego (lo que habia antes queda).
local function cleanAfter(fn)
  return function(p)
    local before = {}
    local all = p:getInventory():getItems()
    for i = 0, all:size() - 1 do before[all:get(i):getID()] = true end
    local ok, err = pcall(fn, p)
    local inv = p:getInventory()
    local items = inv:getItems()
    for i = items:size() - 1, 0, -1 do
      local it = items:get(i)
      if not before[it:getID()] then inv:DoRemoveItem(it) end
    end
    if not ok then error(err, 0) end
  end
end

local function fresh(p, variant)
  local d = S.data(p)
  R.deactivate(p, "forced")
  d.variant = variant; d.degradation = 1.0; d.degradationFloor = 1.0
  d.heat = 0; d.rejection = 0; d.neuralLoad = 0; d.cyberpsychosisActive = false
  d.adaptXP = 0; d.immuno = {}; d.herbalToxicity = 0; d.lockUntilCool = false; d.cooldownMult = 1
  d.antidepUntil = -1; d.nosebleedUntil = -1; d.lastScreamHour = -1000; d.prototype = nil; d.plateName = nil
  d.heatCap = 100; d.cyberScar = nil; d.remissionHours = 0; d.lastOverloadHour = nil; d.lastFreeOverdriveHour = nil
  local kd = S.kdata(p); kd.activeSeconds = 0; kd.crashUntilHour = -1; kd.toleranceSteps = 0           -- (87) un Kerenzikov activo de una prueba anterior bajaba el Heat un 20 % y falseaba las medidas
  d.firmware = {}; d.fwRecalUntil = nil        -- (82) sin chips: las pruebas miden las formulas de siempre aunque el personaje tenga alguno puesto
  d.traits = {}                               -- sin rasgos: "You Are Special" suma un nivel y cambiaba los números esperados
  d.lastRejectionTickHour = S.worldHours(); d.lastCNTickHour = S.worldHours()
  local ss = R.session(p)
  ss.reuseAtMs = 0
  ss.xpPending = 0; ss.xpBy = {}; ss.momentum = 0          -- la XP pendiente de pruebas anteriores inflaba el nivel en "XP y skill"
  ss.work = false; ss.workForce = nil; ss.workLockUntilMs = nil          -- (86) sin modo trabajo
  S.resetPerkTo(p, d, 0)                     -- la skill vanilla también arranca de cero (la dejaba la prueba anterior)
  E.setEndurance(p, 1)
  return d
end

---------------------------------------------------------------------------
-- Pruebas lógicas (instantáneas)
---------------------------------------------------------------------------
local tests = {}

tests[#tests + 1] = { "Cirugia exitosa", function(p)
  local d = fresh(p, nil)
  add(p, M.T.Military); add(p, M.T.Harness); add(p, V.Suture); add(p, V.AlcoholWipes)
  local implant = M.find(p, M.T.Military)
  local sutures = M.count(p, V.Suture)
  M.performSurgery(p, p, implant, { key = "guided", chance = 1 })
  check("instala militar", d.variant == "military", tostring(d.variant))
  check("consume el implante", implant:getContainer() == nil)
  check("consume una sutura", M.count(p, V.Suture) == sutures - 1)
  check("el arnes no se consume", M.find(p, M.T.Harness) ~= nil)
end }

tests[#tests + 1] = { "Cirugia fallida", function(p)
  local d = fresh(p, nil)
  add(p, M.T.Lab); add(p, V.Suture); add(p, V.AlcoholWipes)
  local implant = M.find(p, M.T.Lab)
  M.performSurgery(p, p, implant, { key = "guided", chance = 0 })
  local deg = M.itemDegradation(implant)
  check("no instala", d.variant == nil)
  check("el implante se conserva", implant:getContainer() ~= nil)
  check("degradacion +0.1", math.abs(deg - 1.1) < 0.01, f1(deg))
end }

tests[#tests + 1] = { "Heat y corte termico (militar L0)", function(p)
  local d = fresh(p, "military")
  check("activa", R.activate(p))
  simulate(p, 5)
  check("Heat a 5 s ~ 60", math.abs(d.heat - 60) < 3, f1(d.heat))
  local rej = d.rejection
  simulate(p, 4)
  check("corte automatico antes de 9 s", not R.isActive(p))
  check("rechazo +2..4", d.rejection - rej >= 1.9 and d.rejection - rej <= 4.1, f1(d.rejection - rej))
  check("bloqueado hasta Heat 0", d.lockUntilCool == true)
  check("no reactiva con Heat > 0", not R.activate(p))
  coolDown(p)
  check("reactiva tras enfriar", R.activate(p))
  R.deactivate(p, "manual")
end }

tests[#tests + 1] = { "Corte manual: 1 s y el Heat sigue", function(p)
  local d = fresh(p, "military")
  R.activate(p); simulate(p, 3); R.deactivate(p, "manual")
  local h = d.heat
  check("sin bloqueo termico", not d.lockUntilCool)
  check("no reactiva en el mismo instante", not R.activate(p))
  R.session(p).reuseAtMs = 0
  check("reactiva pasado el segundo", R.activate(p))
  check("el Heat continua (no vuelve a 0)", d.heat > 0 and math.abs(d.heat - h) < 1, f1(h) .. " -> " .. f1(d.heat))
  R.deactivate(p, "manual")
end }

tests[#tests + 1] = { "Overdrive", function(p)
  local d = fresh(p, "military")
  d.adaptXP = S.xpForLevel(4)
  R.activate(p)
  R.session(p).armed = true
  simulate(p, 12)
  local s = R.session(p)
  check("entra en Overdrive", s.overdrive == true)
  check("ventana militar L4 = 4.3 s (2.5 + 4.5 x 4/10)", math.abs(R.overdriveWindow(p) - 4.3) < 0.01, f1(R.overdriveWindow(p)))
  local rej = d.rejection
  check("Impulso sube con el uso continuo", (s.momentum or 0) > 0, f1(s.momentum or 0))
  check("Overdrive: bonos de carrera y ataque", s.eff and s.eff.playerBoost >= s.tier.playerBoost + 0.39
        and s.eff.attackBoost >= s.tier.attackBoost + 0.99)
  local cn0 = d.neuralLoad
  s.overdriveUntilMs = S.gameMs() - 1                  -- (194) reloj de juego, como Runtime (127)
  simulate(p, 0.25)
  check("CN del colapso entre 5 y 10", d.neuralLoad - cn0 >= 4.9 and d.neuralLoad - cn0 <= 10.5, f1(d.neuralLoad - cn0))
  check("se arrastra tras el colapso", SandevistanSlowdown.isPlayerSlowed(p))
  check("el Impulso se reinicia", (s.momentum or 0) == 0)
  check("colapsa al agotar la ventana", not R.isActive(p))
  check("no destruye el implante", d.variant == "military")
  check("enfriamiento x2", d.cooldownMult == 2)
  -- v0.1.29: a adaptación estable el colapso cuesta menos (RejectionAdaptReduction); a L4 militar = 50 % de la estable
  local OD = CFG.Overdrive
  local lo = OD.RejectionMin * (1 - OD.RejectionAdaptReduction * S.adaptFraction(d))
  local hi = OD.RejectionMax
  check("rechazo del colapso escalado por adaptacion", d.rejection - rej >= lo - 0.1 and d.rejection - rej <= hi + 0.1,
        f1(d.rejection - rej) .. " en " .. f1(lo) .. ".." .. f1(hi))
  if OD.HeatCap.Enabled then
    check("primer colapso del dia: sin cicatriz", math.abs(S.heatCap(d) - 100) < 0.01, f1(S.heatCap(d)))
    -- un segundo colapso enseguida si deja cicatriz
    coolDown(p); d.lockUntilCool = false; R.activate(p); R.session(p).armed = true; simulate(p, 12)
    R.session(p).overdriveUntilMs = S.gameMs() - 1; simulate(p, 0.25)
    check("segundo colapso: tope de Heat 100 -> " .. (100 - OD.HeatCap.PerCollapse), math.abs(S.heatCap(d) - (100 - OD.HeatCap.PerCollapse)) < 0.01, f1(S.heatCap(d)))
    check("el Heat queda en el tope nuevo", math.abs(d.heat - S.heatCap(d)) < 0.5, f1(d.heat))
  end
end }

tests[#tests + 1] = { "Cicatriz termica: el Heat no pasa el tope", function(p)
  local d = fresh(p, "military")
  if not CFG.Overdrive.HeatCap.Enabled then check("opcion de sandbox desactivada (se salta)", true); return end
  d.heatCap = 60
  check("activa con tope 60", R.activate(p))
  simulate(p, 8)
  check("corte termico al llegar al tope", not R.isActive(p) and d.lockUntilCool == true, "Heat " .. f1(d.heat))
  check("el Heat nunca pasa el tope", d.heat <= 60.01, f1(d.heat))
  d.heat = 0; d.lockUntilCool = false; d.lastCNTickHour = S.worldHours() - 10; d.lastDeactivateHour = S.worldHours() - 10
  P.hourlyTick(p, d)
  check("se recupera con el implante apagado", S.heatCap(d) > 60, f1(S.heatCap(d)))
end }

tests[#tests + 1] = { "Fiebre por rechazo (desde el nivel 2)", function(p)
  local d = fresh(p, "lab")
  local base = 36.9
  E.setStat(p, "TEMPERATURE", base)
  d.rejection = 30; P.minuteTick(p, d)
  local t1 = E.getStat(p, "TEMPERATURE")
  check("rechazo 30: sin fiebre", t1 < 37.3, f1(t1))
  d.rejection = 55; P.minuteTick(p, d)
  local t2 = E.getStat(p, "TEMPERATURE")
  check("rechazo 55: fiebre >= 37.8", t2 >= 37.79, f1(t2))
  E.setStat(p, "TEMPERATURE", base)
end }

tests[#tests + 1] = { "Remision de la cyberpsicosis", function(p)
  local d = fresh(p, "lab")
  d.cyberpsychosisActive = true; d.neuralLoad = 70
  M.explantPatientPart(p)
  check("sin implante empieza a contar", d.remissionHours ~= nil and S.remissionHoursLeft(d, S.worldHours()) ~= nil)
  if not CFG.NeuralLoad.Remission.Enabled then check("opcion de sandbox desactivada (se salta)", true); return end
  d.lastCNTickHour = S.worldHours() - 1; P.hourlyTick(p, d)
  check("todavia no (faltan dias)", d.cyberpsychosisActive == true)
  d.remissionHours = CFG.NeuralLoad.Remission.HoursWithoutImplant + 1
  d.lastCNTickHour = S.worldHours() - 1; P.hourlyTick(p, d)
  check("remision tras los dias sin implante", d.cyberpsychosisActive == false and d.cyberScar == true)
  check("CN como mucho en el piso", d.neuralLoad <= CFG.NeuralLoad.RemissionFloor + 0.01, f1(d.neuralLoad))
end }

tests[#tests + 1] = { "Cuchillos para la extraccion tosca", function(p)
  fresh(p, nil)
  for _, t in ipairs({ "Base.KitchenKnife", "Base.HuntingKnife", "Base.Scissors" }) do
    local okAdd, it = pcall(function() return p:getInventory():AddItem(t) end)
    if not okAdd then it = nil end
    local tool = it and M.crudeTool(p)
    check(t .. ": " .. (it and "existe" or "NO existe en esta version"), it == nil or tool ~= nil,
          it and ("reconocido: " .. tostring(tool and tool:getFullType())) or nil)
    if it then p:getInventory():DoRemoveItem(it) end
  end
end }

tests[#tests + 1] = { "Expedientes de notas", function(p)
  fresh(p, nil)
  local DOS = SandevistanDossier
  local st = CFG.Notes.Stories[1]
  local before = M.count(p, DOS.noteType(1))          -- v0.1.30 (23): el jugador puede tener notas propias (Debug las da): se compara contra lo que ya habia
  local n1 = p:getInventory():AddItem(DOS.noteType(1))
  local n3 = p:getInventory():AddItem(DOS.noteType(3))
  check("notas creadas", n1 ~= nil and n3 ~= nil)
  DOS.fileNotes(p, st, { { n = 1, item = n1 }, { n = 3, item = n3 } })
  local dossier = DOS.find(p, st)
  check("expediente creado", dossier ~= nil)
  check("paginas archivadas 1 y 3", dossier ~= nil and DOS.count(dossier, st) == 2)
  check("las notas se consumen", M.count(p, DOS.noteType(1)) == before)
  if dossier then
    local title, body = DOS.readText(dossier, st)
    check("titulo con avance (2/10)", string.find(title, "(2/10)", 1, true) ~= nil, title)
    check("marca las paginas que faltan", string.find(body, getText("IGUI_Sandevistan_DossierMissing", 2), 1, true) ~= nil)
    check("nombre del item con avance", string.find(tostring(dossier:getName()), "(2/10)", 1, true) ~= nil, tostring(dossier:getName()))
  end
end }

tests[#tests + 1] = { "Traducciones (informativo)", function(p)
  local lang = nil
  pcall(function() lang = tostring(Translator.getLanguage()) end)
  out("idioma: " .. tostring(lang))
  local name = nil
  pcall(function() name = getItemNameFromFullType("Sandevistan.SandevistanLab") end)
  out("nombre de Sandevistan.SandevistanLab en el juego: " .. tostring(name))
  local text = getText("IGUI_Sandevistan_NoteText_02")
  check("texto de la nota 2 cargado", text ~= "IGUI_Sandevistan_NoteText_02" and string.len(text) > 200, string.sub(text, 1, 40))
end }

tests[#tests + 1] = { "XP por fuente y detalle de la skill (v0.1.30 (41)/(35))", function(p)
  local d = fresh(p, "military")
  local s = R.session(p); s.xpPending, s.xpBy = 0, {}
  d.adaptXP, d.xpSrc = 0, nil
  R.addPendingXP(p, 30, "time"); R.addPendingXP(p, 12, "kill"); R.flushXP(p, true)
  local xs = d.xpSrc or {}
  check("la XP se reparte por fuente (uso 30, kills 12)", math.abs((xs.time or 0) - 30) < 0.01 and math.abs((xs.kill or 0) - 12) < 0.01, string.format("%.1f / %.1f", xs.time or 0, xs.kill or 0))
  check("la adaptacion suma las dos", math.abs(d.adaptXP - 42) < 0.01, tostring(d.adaptXP))
  S.addAdaptXP(d, 5, "pasiva")
  check("pasiva registrada aparte", math.abs((d.xpSrc.pasiva or 0) - 5) < 0.01)
  -- ventana de Overdrive por variante
  check("Overdrive militar nivel 10 = 7 s, laboratorio nivel 5 = 4 s", math.abs(S.overdriveWindow({ variant = "military" }, 10) - 7) < 1e-9 and math.abs(S.overdriveWindow({ variant = "lab" }, 5) - 4) < 1e-9)
  -- detalle por nivel del tooltip de la skill
  local ST = rawget(_G, "SandevistanSkillTooltip")
  if ST then
    local txt = ST.lines(5, ST.variantsFor(p))
    check("detalle del nivel 5 con textos traducidos", #txt > 40 and not string.find(txt, "IGUI_Sandevistan_" .. "LvlTip", 1, true))
    check("el nivel 8 militar marca el tramo nuevo de dilatacion", ST.stats(CFG.Variants.military, 8).newTier == true and ST.stats(CFG.Variants.lab, 5).stable == true)
  end
  d.adaptXP, d.xpSrc = 0, nil
end }

tests[#tests + 1] = { "Stamina", function(p)
  local d = fresh(p, "military")
  E.setEndurance(p, 0.2)
  check("no activa con stamina < 0.25", not R.activate(p))
  E.setEndurance(p, 0.3)
  R.activate(p); simulate(p, 7)
  check("apagado de emergencia bajo 0.15", not R.isActive(p), "endurance " .. f1(E.getEndurance(p)))
end }

tests[#tests + 1] = { "Rechazo e inmunosupresores", function(p)
  local d = fresh(p, "military")
  d.lastRejectionTickHour = S.worldHours() - 24
  P.rejectionTick(p, d)
  check("24 h a L0 ~ 33.6", math.abs(d.rejection - 33.6) < 1, f1(d.rejection))
  add(p, M.T.Clinical)
  M.takeImmuno(p, M.find(p, M.T.Clinical), "clinical")
  check("clinico deja el rechazo en 0", d.rejection == 0)
  check("cobertura 48 h", math.abs(S.immunoHoursLeft(d) - 48) < 0.1, f1(S.immunoHoursLeft(d)))
  d.lastRejectionTickHour = S.worldHours() - 24
  P.rejectionTick(p, d)
  check("sin rechazo con cobertura", d.rejection == 0, f1(d.rejection))
  add(p, M.T.Herbal)
  M.takeImmuno(p, M.find(p, M.T.Herbal), "herbal")
  check("herbal suma toxicidad 25", d.herbalToxicity == 25, f1(d.herbalToxicity))
  d.immuno = {}; d.rejection = 100
  R.checkThresholds(p)
  check("rechazo 100 destruye el implante", d.variant == "destroyed")
  check("destruido apaga el rechazo", d.rejection == 0)
end }

tests[#tests + 1] = { "Carga Neuronal", function(p)
  local d = fresh(p, "lab")
  R.activate(p)
  check("encender no suma CN (v0.1.25)", d.neuralLoad == 0, f1(d.neuralLoad))
  simulate(p, 2); R.deactivate(p, "manual")
  check("lab x0.7 solo por tiempo de uso", d.neuralLoad > 0.05 and d.neuralLoad < 0.3, f1(d.neuralLoad))
  d.neuralLoad = 85; R.checkThresholds(p)
  check("cyberpsicosis a 80+", d.cyberpsychosisActive)
  d.neuralLoad = 55; coolDown(p)
  R.activate(p)
  check("con cyberpsicosis encender tampoco suma CN", d.neuralLoad == 55, f1(d.neuralLoad))
  R.deactivate(p, "manual")
  d.neuralLoad = 55; d.lastDeactivateHour = S.worldHours() - 10; d.lastCNTickHour = S.worldHours() - 100
  P.hourlyTick(p, d)
  check("piso de remision 50", d.neuralLoad >= 50, f1(d.neuralLoad))
end }

tests[#tests + 1] = { "Kerenzikov", function(p)
  local k = S.kdata(p)
  k.activeSeconds = 0; k.toleranceSteps = 0; k.lastDoseHour = -1000; k.crashUntilHour = -1
  local a = Kerenzikov.take(p, false)
  k.activeSeconds = 0
  local b = Kerenzikov.take(p, false)
  check("(108) tolerancia 300 -> 225 s reales", math.abs(a - 300) < 0.1 and math.abs(b - 225) < 0.1, f1(a) .. " / " .. f1(b))
  check("activo", Kerenzikov.isActive(p))
  k.activeSeconds = 0; k.toleranceSteps = 0; k.lastDoseHour = -1000
  check("(108) casero: 150 s reales", math.abs(Kerenzikov.take(p, true) - 150) < 0.1)
  E.addPain(p, "Torso_Upper", 40); Kerenzikov.tick(p, 1)
  check("(108) sin dolor mientras dura", E.getStat(p, "PAIN") < 1, f1(E.getStat(p, "PAIN")))
  check("casero: el bajon espera a que termine", k.crashUntilHour < 0)
  Kerenzikov.tick(p, 1000)
  check("casero: al terminar arranca el bajon", not Kerenzikov.isActive(p) and Kerenzikov.isCrashing(p))
  k.crashUntilHour = -1
  pcall(function() p:getBodyDamage():getBodyPart(BodyPartType.Torso_Upper):setAdditionalPain(0) end)
end }

tests[#tests + 1] = { "XP y skill", function(p)
  local d = fresh(p, "lab")
  R.addPendingXP(p, 150); R.flushXP(p, true)
  check("nivel 1 con 150 XP", S.level(d) == 1, tostring(S.level(d)))
  d.adaptXP = 99999
  check("techo lab = 5", S.level(d) == 5, tostring(S.level(d)))
  d.adaptXP = 150
  local perk = S.perk()
  if perk then
    S.syncPerk(p)
    check("skill espejada nivel 1", p:getPerkLevel(perk) == 1, tostring(p:getPerkLevel(perk)))
  else
    check("skill registrada", false)
  end
end }

tests[#tests + 1] = { "Sintesis", function(p)
  local d = fresh(p, "lab")
  d.knows.crafted = true; d.knows.kerenzikov = true
  add(p, V.Painkillers, 3); add(p, V.Disinfectant, 2); add(p, V.Coldpack); add(p, V.Mortar)
  local okC = pcall(M.Recipes.compound.perform, p)
  check("compuesto sintetico", okC and M.find(p, M.T.Compound) ~= nil)
  local okI = pcall(M.Recipes.crafted.perform, p)
  check("inmunosupresor casero", okI and M.find(p, M.T.Crafted) ~= nil)
  add(p, V.WildGarlic, 2); add(p, V.BlackSage, 2); add(p, V.Whiskey)
  local okH = pcall(M.Recipes.herbal.perform, p)
  check("herbolario", okH and M.find(p, M.T.Herbal) ~= nil)
  add(p, V.Painkillers); add(p, V.Caffeine)
  local okK = pcall(M.Recipes.kerenzikov.perform, p)
  check("Kerenzikov casero", okK and M.find(p, M.T.KereCrafted) ~= nil)
end }

tests[#tests + 1] = { "Recetas nativas y dosis (v0.1.30 15)", function(p)
  local RC = SandevistanRecipeCode
  local d = fresh(p, "lab")
  -- las recetas del menu de crafteo del juego: cargadas, y aprendidas segun lo que sabe el mod
  for _, key in ipairs(M.RecipeOrder) do
    check("receta nativa cargada: " .. key, M.nativeRecipe(key) ~= nil, CFG.Crafting.Recipes[key])
  end
  d.knows.compound = true; d.knows.crafted = true; d.knows.kerenzikov = true
  M.syncRecipes(p)
  local okKnown = true
  for _, key in ipairs({ "compound", "crafted", "kerenzikov" }) do
    local known = false
    pcall(function() known = p:isRecipeActuallyKnown(CFG.Crafting.Recipes[key]) == true end)
    if not known then okKnown = false end
  end
  check("el mod les ensena las recetas conocidas", okKnown)
  -- inmunosupresor casero DRENABLE (item Pack): el juego cuenta los usos; cada dosis gasta uno y el ultimo se lleva la unidad
  -- el item recien creado (AddItem lo devuelve): M.find podia traer un pack a medio usar que el jugador ya tenia en la mochila (fallo falso de (46))
  local it = p:getInventory():AddItem(M.T.Crafted)
  check("el item es un drenable del juego", RC.isDrainable(it))
  check("unidad con todas las dosis", RC.dosesLeft(it) == CFG.Immunosuppressant.Uses, tostring(RC.dosesLeft(it)))
  d.rejection = 0
  M.takeImmuno(p, it, "crafted")
  check("una dosis no gasta la unidad", it:getContainer() ~= nil and RC.dosesLeft(it) == CFG.Immunosuppressant.Uses - 1, tostring(RC.dosesLeft(it)))
  for _ = 1, CFG.Immunosuppressant.Uses - 1 do M.takeImmuno(p, it, "crafted") end
  check("la ultima dosis se lleva la unidad", it:getContainer() == nil)
  check("sonido de dosis definido", getScriptManager():getGameSound(M.DOSE_SOUND.crafted) ~= nil)
  -- Prototipo 06: tirada (se fuerza) con la logica de OnCreate. v0.1.30 (24): con partes (cinco desde la (68)); el fallo devuelve todas con su calidad
  local P = CFG.Prototype06
  add(p, M.T.Lab)
  local lab = M.find(p, M.T.Lab)
  local l2 = { size = function() return 1 end, get = function() return lab end }
  local scrapBefore = M.count(p, V.ElectronicsScrap)
  local compBefore = M.count(p, M.T.Compound)
  local function countParts06() local n = 0; for _, key in ipairs(P.PartOrder) do n = n + M.count(p, P.Parts[key].item) end; return n end
  local partsBefore = countParts06()
  RC.forcedChance = 0
  RC.onCreateProto06({ getAllCreatedItems = function() return l2 end }, p)
  RC.forcedChance = nil
  check("P06 fallido: se pierde el implante creado", lab:getContainer() == nil)
  check("P06 fallido: el compuesto ya no vuelve", M.count(p, M.T.Compound) == compBefore, tostring(M.count(p, M.T.Compound) - compBefore))
  check("P06 fallido: la chatarra no vuelve (los conectores se pierden)", M.count(p, V.ElectronicsScrap) == scrapBefore, tostring(M.count(p, V.ElectronicsScrap)))
  local partsAfter = countParts06()
  check("P06 fallido: vuelven las partes (v0.1.30 (43): ya no se quema una)", partsAfter == partsBefore + #P.PartOrder, tostring(partsAfter - partsBefore))
  add(p, M.T.Lab)
  lab = M.find(p, M.T.Lab)
  l2 = { size = function() return 1 end, get = function() return lab end }
  RC.forcedChance = 1
  RC.onCreateProto06({ getAllCreatedItems = function() return l2 end }, p)
  RC.forcedChance = nil
  check("P06 logrado: implante lab marcado 06", lab:getModData().prototype == "06" and (lab:getModData().heatDegradationMultiplier or 0) >= 1.0)
  -- calidad de las partes segun el nivel de quien las arma
  local board = M.addItem(p, M.T.PartBoard)
  local bl = { size = function() return 1 end, get = function() return board end }
  RC.onCreatePart({ getAllCreatedItems = function() return bl end }, p)
  local qb = board and board:getModData().partQuality
  check("parte fabricada: guarda su calidad", qb ~= nil and qb >= 1.0 and qb <= 1.5, tostring(qb))
  check("calidad final = promedio de las partes", math.abs(RC.finalQuality({ board = 1.0, regulator = 1.4, cell = 1.3, chassis = 1.1, harness = 1.2 }) - 1.20) < 0.001
    and RC.finalQuality({}) == P.DefaultPartQuality)
  -- limpiar lo que devolvio la prueba: la de Prototipo 06 de abajo cuenta compuestos y chatarra exactos
  for _, t in ipairs({ M.T.Compound, V.ElectronicsScrap, M.T.Lab, M.T.PartBoard, M.T.PartRegulator, M.T.PartCell, M.T.PartChassis, M.T.PartHarness }) do
    local guard = 0
    while M.find(p, t) and guard < 50 do
      p:getInventory():DoRemoveItem(M.find(p, t)); guard = guard + 1
    end
  end
end }

tests[#tests + 1] = { "Calibracion y Prototipo 04", cleanAfter(function(p)          -- (112) no dejaba limpio el inventario (implante, chatarra, destornillador)
  local d = fresh(p, nil)
  add(p, M.T.Lab); add(p, V.ElectronicsScrap, 9); add(p, V.Screwdriver); add(p, V.AlcoholWipes)
  local it = M.find(p, M.T.Lab)
  it:getModData().heatDegradationMultiplier = 1.5
  M.performCalibration(p, it)
  check("calibra suelto a 1.0", M.itemDegradation(it) == 1.0)
  check("(122) la calibracion cobra una chatarra por cada 0,1x (0,5x: 5)", M.count(p, V.ElectronicsScrap) == 4, tostring(M.count(p, V.ElectronicsScrap)))
  local keep = CFG.Prototype04.chance
  local c4, P6, RC = CFG.Prototype04, CFG.Prototype06, SandevistanRecipeCode
  add(p, M.T.P04)
  -- (95) reparar pide reemplazar las piezas quemadas y gastar el estabilizador: sin ellas no se puede
  check("reparar pide las piezas y el compuesto", #M.repairReq(p) >= #c4.Repair.Parts + 1, tostring(#M.repairReq(p)))
  for _, key in ipairs(c4.Repair.Parts) do add(p, P6.Parts[key].item) end
  add(p, M.T.Compound, 2)
  local reasonsLeft = #M.repairReq(p)
  check("con piezas y compuesto, solo queda lo que no tengas (habilidades)", reasonsLeft < #c4.Repair.Parts + 1, tostring(reasonsLeft))
  local scrap0, comp0 = M.count(p, V.ElectronicsScrap), M.count(p, M.T.Compound)
  CFG.Prototype04.chance = { { 0, 0 } }
  M.performRepair(p, M.find(p, M.T.P04))
  check("reparacion fallida conserva el P04 y las piezas", M.find(p, M.T.P04) ~= nil and M.find(p, P6.Parts[c4.Repair.Parts[1]].item) ~= nil and M.find(p, P6.Parts[c4.Repair.Parts[2]].item) ~= nil)
  check("la fallida gasta el compuesto y la chatarra", M.count(p, M.T.Compound) == comp0 - c4.Repair.CompoundRequired and M.count(p, V.ElectronicsScrap) == scrap0 - c4.ScrapRequired)
  local worn = RC and RC.partQuality(M.find(p, P6.Parts[c4.Repair.Parts[1]].item)) or 0
  check("las piezas vuelven con " .. c4.Repair.FailWear .. " de desgaste de mas", worn >= P6.DefaultPartQuality + c4.Repair.FailWear - 0.001, tostring(worn))
  add(p, V.ElectronicsScrap, c4.ScrapRequired)
  CFG.Prototype04.chance = { { 0, 1 } }
  M.performRepair(p, M.find(p, M.T.P04))
  CFG.Prototype04.chance = keep
  check("reparacion exitosa quita el P04 y gasta las piezas", M.find(p, M.T.P04) == nil and M.find(p, P6.Parts[c4.Repair.Parts[1]].item) == nil and M.find(p, P6.Parts[c4.Repair.Parts[2]].item) == nil)
  d = fresh(p, "lab"); d.degradation = 1.5
  add(p, V.ElectronicsScrap); add(p, V.AlcoholWipes)
  M.performInstalledCalibration(p, p)
  check("calibra el instalado a 1.0", d.degradation == 1.0, f1(d.degradation))
end) }

tests[#tests + 1] = { "Prototipo 06 (ingenieria inversa)", function(p)
  local RC = SandevistanRecipeCode
  local d = fresh(p, nil)
  d.knows.proto06 = nil
  local c = CFG.Prototype06
  add(p, M.T.Lab); add(p, V.Screwdriver)
  local ref = M.find(p, M.T.Lab)
  ref:getModData().heatDegradationMultiplier = 1.0
  M.performStudy(p, ref)
  check("estudiar ensena el diseno", d.knows.proto06 == true)
  check("estudiar degrada el implante +0.1", math.abs(M.itemDegradation(ref) - 1.1) < 0.001, f1(M.itemDegradation(ref)))
  p:getInventory():DoRemoveItem(ref)
  add(p, V.ElectronicsScrap, c.ScrapRequired); add(p, M.T.Compound, c.CompoundRequired)
  add(p, M.T.PartBoard); add(p, M.T.PartRegulator); add(p, M.T.PartCell); add(p, M.T.PartChassis); add(p, M.T.PartHarness)
  local scrap0 = M.count(p, V.ElectronicsScrap)
  local function nParts() local n = 0; for _, key in ipairs(c.PartOrder) do n = n + M.count(p, c.Parts[key].item) end; return n end
  local parts0 = nParts()                                   -- el jugador puede llevar partes propias (kit de Debug): se compara contra lo que habia
  local compound0 = M.count(p, M.T.Compound)
  M.performProto06(p, 0)
  check("fallo gasta los conectores", M.count(p, V.ElectronicsScrap) == scrap0 - c.ScrapRequired, tostring(M.count(p, V.ElectronicsScrap)))
  check("fallo gasta el compuesto", M.count(p, M.T.Compound) == compound0 - c.CompoundRequired)
  check("fallo conserva las cinco partes", nParts() == parts0, tostring(nParts() - parts0))
  local wornQ = RC.partQuality(M.find(p, M.T.PartBoard))
  check("fallo desgasta las partes (+FailWear)", wornQ >= c.DefaultPartQuality + c.FailWear - 0.001, tostring(wornQ))
  add(p, V.ElectronicsScrap, c.ScrapRequired); add(p, M.T.Compound, c.CompoundRequired)                 -- de nuevo lo que consume el armado
  local item = M.performProto06(p, 1)
  check("fabrica un implante lab", item ~= nil and M.implantVariant(item) == "lab")
  check("marcado como P06", item ~= nil and M.itemPrototype(item) == "06")
  check("degradacion = promedio de las partes (las desgastadas por el fallo)", item ~= nil and math.abs(M.itemDegradation(item) - (c.DefaultPartQuality + c.FailWear)) < 0.001,
        item and f1(M.itemDegradation(item)))
  local _, floor = M.itemDegradation(item)
  check("sin piso de degradacion (calibrable a 1.0)", floor == 1.0)
  -- se instala y el prototipo viaja con el implante
  add(p, V.Suture, 2); add(p, V.AlcoholWipes, 2); add(p, V.Scalpel); add(p, V.Mirror)
  M.performSurgery(p, p, item, { key = "guided", chance = 1 })
  check("instalado como lab P06", d.variant == "lab" and d.prototype == "06", tostring(d.variant) .. "/" .. tostring(d.prototype))
  M.performExplant(p, p, 1)
  -- puede haber otros implantes lab en el inventario (de pruebas anteriores o del jugador): se busca el marcado
  local back = nil
  local all = p:getInventory():getAllTypeRecurse(M.T.Lab)
  for i = 0, all:size() - 1 do
    if M.itemPrototype(all:get(i)) == "06" then back = all:get(i) end
  end
  check("explantado conserva la marca P06", back ~= nil and d.prototype == nil)
end }

tests[#tests + 1] = { "Prototipo 07 (replica militar)", function(p)
  local RC = SandevistanRecipeCode
  local d = fresh(p, nil)
  d.knows.proto07 = nil
  local c = CFG.Prototype07
  add(p, M.T.Military); add(p, V.Screwdriver)
  local ref = M.find(p, M.T.Military)
  ref:getModData().heatDegradationMultiplier = 1.0
  if not M.militaryDossiersComplete(p) then            -- (si el jugador ya lleva los dos completos, esta comprobacion no aplica)
    check("sin expedientes militares no se puede estudiar el diseno", #M.studyMilReq(p, ref) >= 1)
  end
  -- expedientes militares completos: se simula el progreso de los dos (el jugador puede tener expedientes propios y esta prueba no los toca)
  local realProgress = M.dossierProgress
  M.dossierProgress = function(_, id)
    for _, st in ipairs(CFG.Notes.Stories) do
      if st.id == id then local n = st.total; return n, n end
    end
  end
  local dossierReason = getText("IGUI_Sandevistan_Req_Dossiers")           -- (el resto de los requisitos, como la Electricidad, dependen de las habilidades del personaje)
  local others = {}
  for _, r in ipairs(M.studyMilReq(p, ref)) do if r == dossierReason then others[#others + 1] = r end end
  check("con los dos expedientes completos se cumple el requisito", M.militaryDossiersComplete(p) and #others == 0, tostring(#others))
  M.performStudyMil(p, ref)
  M.dossierProgress = realProgress
  check("estudiar el militar ensena el diseno 07", d.knows.proto07 == true)
  check("estudiar degrada el militar +0.1", math.abs(M.itemDegradation(ref) - 1.1) < 0.001, f1(M.itemDegradation(ref)))
  p:getInventory():DoRemoveItem(ref)
  -- ensamblado con la logica de OnCreate (tirada forzada)
  add(p, M.T.Military)
  local mil = M.find(p, M.T.Military)
  local l7 = { size = function() return 1 end, get = function() return mil end }
  RC.forcedChance = 1
  RC.onCreateProto07({ getAllCreatedItems = function() return l7 end }, p)
  RC.forcedChance = nil
  check("P07 logrado: militar marcado 07 sin piso de desgaste", mil:getModData().prototype == "07" and (mil:getModData().heatDegradationMultiplier or 0) >= 1.0)
  local _, floor = M.itemDegradation(mil)
  check("P07 sin piso de degradacion", floor == 1.0)
  add(p, V.Suture, 2); add(p, V.AlcoholWipes, 2); add(p, V.Scalpel); add(p, V.Mirror)
  M.performSurgery(p, p, mil, { key = "guided", chance = 1 })
  check("instalado como militar P07", d.variant == "military" and d.prototype == "07", tostring(d.variant) .. "/" .. tostring(d.prototype))
  M.performExplant(p, p, 1)
  local back = nil
  local all = p:getInventory():getAllTypeRecurse(M.T.Military)
  for i = 0, all:size() - 1 do
    if M.itemPrototype(all:get(i)) == "07" then back = all:get(i) end
  end
  check("explantado conserva la marca P07", back ~= nil and d.prototype == nil)
end }

---------------------------------------------------------------------------
-- (53) Comprobaciones de lo agregado desde la (46): extraccion por First Aid, menu de dosis, cadena del Mk. II con habilidades reales,
-- tooltip y CN por uso con la adaptacion. Las habilidades del juego se ponen y se REPONEN (nivel y XP) aunque la prueba falle.
---------------------------------------------------------------------------
local function withSkills(p, levels, fn)
  local xp = p:getXp()
  local saved = {}
  for name in pairs(levels) do
    local perk = Perks[name]
    saved[name] = { perk = perk, level = p:getPerkLevel(perk), xp = S.perkXP(p, perk) }
  end
  local ok, err = pcall(function()
    for name, lv in pairs(levels) do
      p:setPerkLevelDebug(Perks[name], lv); xp:setXPToLevel(Perks[name], lv)
    end
    fn()
  end)
  for _, s in pairs(saved) do
    pcall(function()
      p:setPerkLevelDebug(s.perk, s.level); xp:setXPToLevel(s.perk, s.level)
      local have = S.perkXP(p, s.perk)
      if s.xp and have and s.xp - have >= 1 then xp:AddXPNoMultiplier(s.perk, s.xp - have) end
    end)
  end
  if not ok then error(err, 0) end
end

local function listOf(items) return { size = function() return #items end, get = function(_, i) return items[i + 1] end } end
-- Corre la prueba y borra despues lo que creo (los implantes y partes que dejarian las pruebas siguientes con datos de esta)
local function idsOf(p, fullType)
  local ids = {}
  local all = p:getInventory():getAllTypeRecurse(fullType)
  for i = 0, all:size() - 1 do ids[all:get(i):getID()] = true end
  return ids
end
local function newOf(p, fullType, before)
  local all = p:getInventory():getAllTypeRecurse(fullType)
  for i = 0, all:size() - 1 do if not before[all:get(i):getID()] then return all:get(i) end end
  return nil
end

-- (65) El desgaste extra de la furia deja de depender de la suerte: con la probabilidad de desgaste del arma puesta en 1/2 y 60 golpes, el arma TIENE que llegar a 0
-- (la chance de que no pase es de 1 en cien millones); sin furia o con x1.0 no se toca; y con la probabilidad real se mide cuanto desgasta contra lo esperado.
tests[#tests + 1] = { "Desgaste del arma en furia (v0.1.30 (65))", cleanAfter(function(p)
  fresh(p, "lab")
  local C = rawget(_G, "SandevistanCombat")
  local B = CFG.Psychosis.Berserk
  if not C or not C.furyWear then out("info: sin Combat.furyWear"); return end
  local w = nil
  pcall(function() w = p:getInventory():AddItem("Base.BaseballBat") end)
  if not w then out("info: sin Base.BaseballBat en esta version: salteada"); return end
  local s = R.session(p)
  local keepMult, keepB, keepF = B.WeaponWearMult, s.berserk, s.fury
  local ok, err = pcall(function()
    local max = w:getConditionMax()
    local real = w:getConditionLowerChance()
    check("el arma tiene durabilidad", max ~= nil and max >= 2, "condicion maxima " .. tostring(max) .. ", 1 de cada " .. tostring(real) .. " golpes")
    B.WeaponWearMult = 2.0
    local function hits(n, setup)
      w:setCondition(max); local lost = 0
      for _ = 1, n do if setup then setup() end; lost = lost + C.furyWear(p, w) end
      return lost, w:getCondition()
    end
    s.berserk, s.fury = false, false
    local lost, cond = hits(60)
    check("sin furia no hay desgaste extra", lost == 0 and cond == max, "perdio " .. tostring(lost))
    s.berserk = true
    B.WeaponWearMult = 1.0
    lost, cond = hits(60)
    check("con WeaponWearMult 1.0 tampoco", lost == 0 and cond == max, "perdio " .. tostring(lost))
    B.WeaponWearMult = 2.0
    pcall(function() w:setConditionLowerChance(2) end)
    lost, cond = hits(60)
    check("en furia, con 1/2 de chance por tirada, el arma llega a 0 en 60 golpes (no depende de la suerte)", cond == 0 and lost == max, "condicion " .. tostring(cond) .. ", perdio " .. tostring(lost))
    s.berserk, s.fury = false, true
    lost, cond = hits(60)
    check("tambien con la furia total", cond == 0, "condicion " .. tostring(cond))
    s.berserk, s.fury = true, false
    -- probabilidad real del arma: perdida esperada = golpes * (mult - 1) / chance (se repone la condicion en cada golpe para que no se rompa)
    pcall(function() w:setConditionLowerChance(real) end)
    local N, got = 3000, 0
    for _ = 1, N do w:setCondition(max); got = got + C.furyWear(p, w) end
    local want = N * (B.WeaponWearMult - 1) / math.max(2, real)
    check("con la chance real (1/" .. tostring(real) .. ") el desgaste extra es el esperado", got > 0 and got > want * 0.6 and got < want * 1.5, string.format("%d en %d golpes, esperado ~%.0f", got, N, want))
  end)
  B.WeaponWearMult, s.berserk, s.fury = keepMult, keepB, keepF
  if not ok then error(err, 0) end
end) }

tests[#tests + 1] = { "Extraccion segun First Aid (v0.1.30 (50))", cleanAfter(function(p)
  fresh(p, nil)
  if isClient() then out("info: salteada en multijugador (cambia las habilidades del cliente)"); return end
  local X = CFG.Extraction
  local function body() local md = { Sandevistan = { variant = "lab", degradation = 1.0 } }
    return { getModData = function() return md end, transmitModData = function() end } end
  local function extractedDegradation(crude)
    local before = idsOf(p, M.T.Lab)
    M.performExtraction(p, body(), crude)
    local it = newOf(p, M.T.Lab, before)
    return it and it:getModData().heatDegradationMultiplier
  end
  local keepChance = S.chance
  S.chance = function() return false end                 -- sin corte en la mano en la tosca
  local ok, err = pcall(function()
    for _, fa in ipairs({ 0, 1, 2, 3, 4, 8 }) do
      withSkills(p, { Doctor = fa }, function()
        local deg = extractedDegradation(false)
        check("extraccion limpia con First Aid " .. fa, deg ~= nil and math.abs(deg - M.extractionDegradation(fa)) < 1e-6, deg and string.format("%.2f", deg) or "sin implante")
      end)
    end
    withSkills(p, { Doctor = 0 }, function()
      check("First Aid 0: desgaste maximo de la limpia", math.abs(M.extractionDegradation(0) - X.DegradationAtFA0) < 1e-9)
      local deg = extractedDegradation(true)
      check("tosca con First Aid 0: + desgaste extra (tope " .. X.MaxDegradation .. ")", deg ~= nil and math.abs(deg - math.min(X.MaxDegradation, X.DegradationAtFA0 + X.Crude.DegradationExtra)) < 1e-6, deg and string.format("%.2f", deg) or "-")
    end)
    withSkills(p, { Doctor = X.PerfectFA }, function()
      local deg = extractedDegradation(false)
      check("First Aid " .. X.PerfectFA .. ": perfecta (1.0)", deg ~= nil and math.abs(deg - 1.0) < 1e-9, deg and string.format("%.2f", deg) or "-")
    end)
  end)
  S.chance = keepChance
  if not ok then error(err, 0) end
end) }

tests[#tests + 1] = { "Menu del inmunosupresor: efecto de la dosis (v0.1.30 (49))", function(p)
  local d = fresh(p, "lab")
  local MN = rawget(_G, "SandevistanMenus")
  if not MN or not MN.fillInventory or not ISContextMenu or not instanceItem then out("info: menu no disponible, salteada"); return end
  local function optionNames(fullType)
    local item = instanceItem(fullType)
    local ctx = ISContextMenu:new(0, 0, 200, 20)
    local ok, err = pcall(MN.fillInventory, p:getPlayerNum(), ctx, { item })
    local names = {}
    if not ok then names[1] = "error: " .. tostring(err) end
    for i = 1, (ctx.numOptions or 0) do local o = ctx.options and ctx.options[i]; if o and o.name then names[#names + 1] = o.name end end
    pcall(function() ctx:clear() end)
    return ok, names
  end
  local function has(names, text) for _, n in ipairs(names) do if n == text then return true end end return false end
  local now = S.worldHours()
  for _, e in ipairs({ { "clinical", M.T.Clinical, 0 }, { "crafted", M.T.Crafted, 30 }, { "herbal", M.T.Herbal, 45 } }) do
    d.immuno = {}; d.rejection = 60
    local ok, names = optionNames(e[2])
    local before, after, hours, idB, idA = M.immunoPreview(p, e[1])
    local want = getText("IGUI_Sandevistan_TakeDoseInfo", math.floor(before + 0.5), math.floor(after + 0.5), math.floor(hours + 0.5))
    if S.immunodepOn() then want = want .. getText("IGUI_Sandevistan_TakeDoseImmunodep", math.floor(idB + 0.5), math.floor(idA + 0.5)) end     -- (135)
    check("menu " .. e[1] .. ": la opcion muestra el efecto", ok and has(names, want), want .. " | " .. table.concat(names, " ; "))
    check("menu " .. e[1] .. ": rechazo " .. 60 .. " -> " .. e[3], math.abs(before - 60) < 1e-6 and math.abs(after - e[3]) < 1e-6, string.format("%.0f -> %.0f", before, after))
  end
  d.immuno = { clinicalUntil = now + 30 }; d.rejection = 20
  local _, _, hours = M.immunoPreview(p, "clinical")
  check("la cobertura suma lo que ya tenias y respeta el tope", math.abs(hours - CFG.Immunosuppressant.CapHours) < 1e-6, string.format("%.1f h", hours))
  d.immuno = {}
end }

tests[#tests + 1] = { "Mk. II: especialidades, recetas y cadena con habilidades reales", cleanAfter(function(p)
  local d = fresh(p, "lab")
  if isClient() then out("info: salteada en multijugador (cambia las habilidades del cliente)"); return end
  local RC = SandevistanRecipeCode
  local P7 = CFG.Prototype07
  -- (a) la calidad de cada parte depende de UNA habilidad y mejora con el nivel (funcion pura: no toca tus habilidades)
  local function who(l) return { getPerkLevel = function() return l end } end
  local mono = true
  for _, key in ipairs(P7.PartOrder) do
    local prev = 99
    for l = 0, 10 do
      local q = RC.partQualityFor(key, who(l), P7)
      if q > prev + 1e-9 then mono = false end
      prev = q
    end
  end
  check("la calidad de las partes nunca empeora con el nivel", mono)
  check("soldar rinde mas por nivel (bonus del regulador)", RC.partQualityFor("regulator", who(8), P7) < RC.partQualityFor("board", who(8), P7) + 1e-9)
  -- (b) recetas: todas (19 desde la (68)) son validas para el personaje con nivel suficiente y las de habilidad no lo son sin ella
  local CRM = rawget(_G, "CraftRecipeManager")
  local gated = { board = true, regulator = true, cell = true, chassis = true, harness = true, proto06 = true, board07 = true, regulator07 = true, cell07 = true,
                  chassis07 = true, harness07 = true, chip07 = true, proto07 = true }
  local nGated = 0
  for _ in pairs(gated) do nGated = nGated + 1 end
  local function recipeOf(key) local full = CFG.Crafting.Recipes[key]; return full and getScriptManager():getCraftRecipe(full), full end
  local function valid(key)
    local r, full = recipeOf(key)
    if not r then return nil end
    pcall(function() p:learnRecipe(M.bareName(full)) end)
    local ok, v = pcall(CRM.isValidRecipeForCharacter, r, p, nil, nil)
    return ok and v or false
  end
  if CRM and CRM.isValidRecipeForCharacter then
    local bad = {}
    withSkills(p, { Electricity = 10, MetalWelding = 10, Doctor = 10, Mechanics = 10, Tailoring = 10 }, function()
      for _, key in ipairs(M.SyncOrder) do if valid(key) ~= true then bad[#bad + 1] = key end end
    end)
    check("con nivel 10 todas las recetas son validas para el personaje", #bad == 0, #bad > 0 and table.concat(bad, ", ") or (#M.SyncOrder .. "/" .. #M.SyncOrder))
    local leaks = {}
    withSkills(p, { Electricity = 0, MetalWelding = 0, Doctor = 0, Mechanics = 0, Tailoring = 0 }, function()
      for key in pairs(gated) do if valid(key) == true then leaks[#leaks + 1] = key end end
    end)
    check("sin habilidad las recetas de especialidad no son validas", #leaks == 0, #leaks > 0 and ("validas sin nivel: " .. table.concat(leaks, ", ")) or (nGated .. "/" .. nGated .. " bloqueadas"))
  else
    out("info: CraftRecipeManager.isValidRecipeForCharacter no existe: se saltea el chequeo de habilidades de las recetas")
  end
  -- (c) cadena: las cinco partes con nivel 10 -> ensamblado (exito y falla) con los OnCreate reales
  withSkills(p, { Electricity = 10, MetalWelding = 10, Doctor = 10, Mechanics = 10, Tailoring = 10 }, function()
    local parts, quals = {}, {}
    for _, key in ipairs(P7.PartOrder) do
      local it = S.giveItem(p:getInventory(), P7.Parts[key].item)
      RC.onCreatePart({ getAllCreatedItems = function() return listOf({ it }) end }, p)
      parts[#parts + 1] = it; quals[key] = RC.partQuality(it)
    end
    local perfect = true
    for _, key in ipairs(P7.PartOrder) do if quals[key] ~= 1.0 then perfect = false end end
    check("partes con nivel 10: perfectas (1.0)", perfect, string.format("%.2f / %.2f / %.2f / %.2f / %.2f", quals.board, quals.regulator, quals.cell, quals.chassis, quals.harness))
    check("First Aid 10: chance de ensamblado " .. P7.chance[#P7.chance][2], math.abs(M.proto07Chance(p) - P7.chance[#P7.chance][2]) < 1e-9, string.format("%.2f", M.proto07Chance(p)))
    local mil = S.giveItem(p:getInventory(), M.T.Military)
    RC.forcedChance = 1
    RC.onCreateProto07({ getAllCreatedItems = function() return listOf({ mil }) end, getAllConsumedItems = function() return listOf(parts) end }, p)
    RC.forcedChance = nil
    local md = mil:getModData()
    check("ensamblado logrado: Mk. II marcado y perfecto con partes perfectas", md.prototype == "07" and math.abs((md.heatDegradationMultiplier or 9) - 1.0) < 1e-9, tostring(md.prototype) .. " / " .. tostring(md.heatDegradationMultiplier))
    check("las cinco partes se leyeron del ensamblado", RC.lastProto07 and RC.lastProto07.partsRead == #P7.PartOrder, tostring(RC.lastProto07 and RC.lastProto07.partsRead))
    -- falla: se pierde el implante creado y las partes vuelven con el desgaste de mas
    local before = {}
    for key, def in pairs(P7.Parts) do before[key] = M.count(p, def.item) end
    local mil2 = S.giveItem(p:getInventory(), M.T.Military)
    RC.forcedChance = 0
    RC.onCreateProto07({ getAllCreatedItems = function() return listOf({ mil2 }) end, getAllConsumedItems = function() return listOf(parts) end }, p)
    RC.forcedChance = nil
    check("ensamblado fallido: se pierde el implante creado", mil2:getContainer() == nil)
    local old = {}
    for _, pt in ipairs(parts) do old[pt:getID()] = true end
    local back, worn = true, true
    for key, def in pairs(P7.Parts) do
      if M.count(p, def.item) ~= before[key] + 1 then back = false end
      local it = newOf(p, def.item, old)
      if not it or math.abs(RC.partQuality(it) - (1.0 + P7.FailWear)) > 1e-6 then worn = false end
    end
    check("ensamblado fallido: las cinco partes vuelven", back)
    check("ensamblado fallido: vuelven con " .. P7.FailWear .. " de desgaste de mas", worn)
  end)
end) }

tests[#tests + 1] = { "Nombre de la placa (v0.1.30 (69))", function(p)
  local d = fresh(p, nil)
  local item = M.addItem(p, M.T.Lab)
  check("el implante se crea", item ~= nil)
  if not item then return end
  check("un P05 no se renombra", not M.plateAllowed(item))
  item:getModData().prototype = "06"
  check("un P06 si", M.plateAllowed(item))
  check("limpieza del texto", S.cleanPlate("el relampago!") == "EL RELAMPAGO!" and S.cleanPlate("   ") == nil and #S.cleanPlate(string.rep("a", 40)) == CFG.Plate.MaxLength)
  local plate = M.setPlate(item, "mi sande")
  check("guarda el nombre y el item lo muestra", plate == "MI SANDE" and item:getModData().plateName == "MI SANDE" and string.find(item:getName(), "MI SANDE", 1, true) ~= nil, item:getName())
  M.applyImplant(p, "lab", 1.0, 1.0, "06", M.itemPlate(item))
  p:getInventory():DoRemoveItem(item)                                  -- la cirugia consume el item
  check("instalado: el jugador lleva el nombre", d.plateName == "MI SANDE" and d.prototype == "06")
  local H = rawget(_G, "SandevistanHUD")
  local m = H and H.buildModel(p, d, R.session(p))
  check("el HUD usa el nombre de la placa", m ~= nil and m.title == "MI SANDE" and m.plate == "MI SANDE", m and tostring(m.title))
  local snap = M.explantPatientPart(p)
  check("explantado: el jugador ya no lo lleva", snap.plate == "MI SANDE" and d.plateName == nil)
  local before = M.count(p, M.T.Lab)
  M.explantGive(p, snap)
  local back = nil                                                    -- el personaje puede llevar otros implantes de laboratorio: se busca el que tiene la marca
  local all = p:getInventory():getAllTypeRecurse(M.T.Lab)
  for i = 0, all:size() - 1 do if all:get(i):getModData().prototype == "06" then back = all:get(i) end end
  check("el implante vuelve a las manos con el nombre", M.count(p, M.T.Lab) == before + 1 and back ~= nil and back:getModData().prototype == "06"
    and back:getModData().plateName == "MI SANDE", back and tostring(back:getModData().plateName))
  for _ = 1, 4 do local it = M.find(p, M.T.Lab); if it then p:getInventory():DoRemoveItem(it) end end
  d.variant = nil; d.prototype = nil; d.plateName = nil
end }

tests[#tests + 1] = { "Tooltip y CN por uso con la adaptacion (v0.1.30 (48))", function(p)
  local d = fresh(p, "military")
  local ST = rawget(_G, "SandevistanSkillTooltip")
  local B = CFG.NeuralLoad.UseAdaptReduction
  if ST then
    local variants = { { "x", "military", CFG.Variants.military } }
    local want = getText("IGUI_Sandevistan_LvlTip_NeuralUse", string.format("%d%%", math.floor(ST.stats(CFG.Variants.military, 4).neuralUse * 100 + 0.5)))
    check("el tooltip del nivel 4 muestra la CN por uso", string.find(ST.lines(4, variants), want, 1, true) ~= nil, want)
    check("el tooltip del nivel 0 no la muestra", string.find(ST.lines(0, variants), getText("IGUI_Sandevistan_LvlTip_NeuralUse", "0%"), 1, true) == nil)
  else
    out("info: sin SandevistanSkillTooltip")
  end
  -- CN real por uso: con la adaptacion estable sube (1 - UseAdaptReduction) de lo que sube sin adaptacion
  local d0 = fresh(p, "military")
  R.activate(p); simulate(p, 6); R.deactivate(p, "manual")
  local g0 = d0.neuralLoad
  d0 = fresh(p, "military"); d0.adaptXP = S.masteryBase(d0)          -- (123) el nivel 10 justo: con Beyond Ten S.xpCap llega a la maestria 15 (otro %)
  R.activate(p); simulate(p, 6); R.deactivate(p, "manual")
  local g1 = d0.neuralLoad
  check("la CN por uso baja " .. string.format("%d%%", B * 100) .. " con la adaptacion estable", g0 > 0 and math.abs(g1 / g0 - (1 - B)) < 0.04, string.format("%.3f -> %.3f (x%.2f)", g0, g1, g0 > 0 and g1 / g0 or 0))
end }

-- (123) Maestria con Beyond Ten: bonos sobre el nivel 10 y, en un jugador, la skill queda en 10 y la maestria va al almacen de Beyond Ten sin ida y vuelta
tests[#tests + 1] = { "Beyond Ten: maestria", function(p)
  local BT = S.beyondTen()
  if not BT then out("info: salteada (Beyond Ten no esta activo)"); return end
  local M = CFG.Mastery
  local d = fresh(p, "military")
  local base = S.masteryBase(d)
  d.adaptXP = base
  local heat10, cool10, win10 = S.heatPerSecond(d, 10), S.coolPerSecond(d, 10), S.overdriveWindow(d, 10)
  check("en el 10 justo, maestria 0", S.level(d) == 10 and S.mastery(d) == 0, tostring(S.mastery(d)))
  d.adaptXP = S.xpCap(d)
  local n = #M.Table
  check("con toda la XP, maestria " .. n .. " (nivel 15)", S.mastery(d) == n and S.displayLevel(d) == 10 + n, tostring(S.displayLevel(d)))
  check("Heat y enfriamiento de la maestria", math.abs(S.heatPerSecond(d, 10) / heat10 - (1 - n * M.HeatPerRank)) < 1e-6
    and math.abs(S.coolPerSecond(d, 10) / cool10 - (1 + n * M.CoolPerRank)) < 1e-6, string.format("%.3f / %.3f", S.heatPerSecond(d, 10) / heat10, S.coolPerSecond(d, 10) / cool10))
  check("ventana de Overdrive +" .. (n * M.WindowPerRank) .. " s", math.abs(S.overdriveWindow(d, 10) - win10 - n * M.WindowPerRank) < 1e-6, string.format("%.2f", S.overdriveWindow(d, 10)))
  check("tramo IV en la 15", S.dilationTier(d, 10).zombieSpeed == CFG.DilationTiers[4].zombieSpeed, tostring(S.dilationTier(d, 10).zombieSpeed))
  if isClient() then out("info: la escritura en Beyond Ten se prueba en un jugador (en multijugador la hace el servidor)"); return end
  local perk = S.perk()
  if not perk then out("info: sin la skill registrada"); return end
  d.adaptXP = base + M.Table[1] + M.Table[2] / 2
  S.syncPerk(p)
  local stored = BT.GetStoredXP(p, perk)
  check("la skill del juego queda en 10", p:getPerkLevel(perk) == 10, tostring(p:getPerkLevel(perk)))
  check("Beyond Ten muestra 12", BT.GetEffectiveLevel(p, perk) == 12, tostring(BT.GetEffectiveLevel(p, perk)) .. " (XP " .. tostring(stored) .. ")")
  S.syncPerk(p); S.syncPerk(p)
  check("sin ida y vuelta con Beyond Ten", math.abs(BT.GetStoredXP(p, perk) - stored) < 1 and p:getPerkLevel(perk) == 10 and d.adaptXP == base + M.Table[1] + M.Table[2] / 2,
    string.format("%.0f -> %.0f", stored, BT.GetStoredXP(p, perk)))
  d.adaptXP = 0; S.syncPerk(p)
  check("bajo el 10 la maestria guardada se vacia", BT.GetStoredXP(p, perk) == 0 and p:getPerkLevel(perk) == 0, tostring(BT.GetStoredXP(p, perk)))
end }

tests[#tests + 1] = { "Sintomas de CN y antidepresivos", function(p)
  local d = fresh(p, "lab")
  d.neuralLoad = 59
  check("sin glitches bajo CN 60", S.glitchRate(d) == 0)
  check("sin sangrado espontaneo bajo CN 60", S.nosebleedChance(d) == 0)
  d.neuralLoad = 60
  check("glitches desde CN 60", S.glitchRate(d) > 0, f1(S.glitchRate(d)))
  d.neuralLoad = 79
  check("sin grito bajo CN 80", S.screamChance(d) == 0)
  d.neuralLoad = 100
  local full = S.glitchRate(d)
  check("glitch maximo a CN 100", math.abs(full - CFG.NeuralLoad.Glitch.RatePerSecond.max) < 0.001, f1(full))
  check("grito posible a CN 100", S.screamChance(d) > 0)
  E.scream(p, d)
  check("grito con enfriamiento", S.screamChance(d) == 0)
  E.startNosebleed(p, d)
  check("sangrado nasal activo", E.isNosebleeding(d))
  d.nosebleedUntil = -1
  -- sangrado al apagar con CN alta
  local keep = CFG.NeuralLoad.Nosebleed.OnDeactivateChance
  CFG.NeuralLoad.Nosebleed.OnDeactivateChance = 1
  d.neuralLoad = 65; d.cyberpsychosisActive = false
  R.activate(p); R.deactivate(p, "manual")
  CFG.NeuralLoad.Nosebleed.OnDeactivateChance = keep
  check("sangrado al apagar con CN >= 60", E.isNosebleeding(d))
  d.nosebleedUntil = -1
  -- antidepresivos
  d.neuralLoad = 100; d.lastScreamHour = -1000
  M.applyAntidepressant(p)
  check("antidepresivo activo", S.antidepActive(d))
  check("antidepresivo reduce glitches", math.abs(S.glitchRate(d) - full * CFG.Antidepressant.SymptomMultiplier) < 0.001)
  local now = S.worldHours()
  M.applyAntidepressant(p); M.applyAntidepressant(p); M.applyAntidepressant(p); M.applyAntidepressant(p)
  check("tope de cobertura", d.antidepUntil <= now + CFG.Antidepressant.CapHours + 0.001)
  d.neuralLoad = 20; d.cyberpsychosisActive = false; d.immuno = {}
  d.lastDeactivateHour = -1000; d.lastCNTickHour = S.worldHours() - 1
  P.hourlyTick(p, d)
  local expect = 20 - CFG.NeuralLoad.Decay.safe * CFG.Antidepressant.CNDecayMultiplier
  check("decay de CN x1.5 con antidepresivo", math.abs(d.neuralLoad - expect) < 0.05, f1(d.neuralLoad))
  out("info: accion vanilla de pastillas enganchada = " .. tostring(M.antidepHooked))
end }

tests[#tests + 1] = { "Explantacion y cambio de implante", function(p)
  local d = fresh(p, "lab")
  d.adaptXP = S.xpForLevel(4); d.neuralLoad = 40
  add(p, V.Suture, 3); add(p, V.AlcoholWipes, 2); add(p, V.Scalpel); add(p, V.Mirror)
  local before = M.count(p, M.T.Lab)
  M.performExplant(p, p, 0)
  check("explantacion fallida no quita nada", d.variant == "lab" and M.count(p, M.T.Lab) == before)
  M.performExplant(p, p, 1)
  check("explantacion exitosa devuelve el implante", d.variant == nil and M.count(p, M.T.Lab) == before + 1)
  local found = false
  local all = p:getInventory():getAllTypeRecurse(M.T.Lab)
  for i = 0, all:size() - 1 do
    if math.abs(M.itemDegradation(all:get(i)) - 1.2) < 0.01 then found = true end
  end
  check("implante retirado +0.2x", found)
  check("conserva la Carga Neuronal", d.neuralLoad == 40, f1(d.neuralLoad))
  add(p, M.T.Military); add(p, M.T.Harness)
  M.performSurgery(p, p, M.find(p, M.T.Military), { key = "guided", chance = 1 })
  check("instala el militar", d.variant == "military")
  check("conserva toda la adaptacion", math.abs(d.adaptXP - S.xpForLevel(4)) < 0.01, f1(d.adaptXP))          -- (124) antes la mitad
  check("rechazo inicial 30", d.rejection == 30, f1(d.rejection))
  d.variant = "destroyed"
  M.performExplant(p, p, 1)
  check("explanta un implante destruido", d.variant == nil)
  check("de uno destruido se conserva la mitad", math.abs((d.keptXP or 0) - S.xpForLevel(4) * CFG.Explant.KeepXPFractionDestroyed) < 0.01, f1(d.keptXP or 0))
  d.keptXP = nil; d.pendingRejection = nil
end }

-- (82) Firmware. Con un laboratorio nivel 5 los chips cambian el juego de verdad: se miden el Heat y la CN con el ciclo real del Runtime (implante encendido), la
-- instalacion y la extraccion por la logica de FirmwareClient, y que explantar devuelva los chips al inventario.
tests[#tests + 1] = { "Firmware: chips, perfil e instalacion (v0.1.30 (82))", cleanAfter(function(p)
  local FW, FC = rawget(_G, "SandevistanFirmware"), rawget(_G, "SandevistanFirmwareClient")
  check("el firmware esta activo en esta partida", FW ~= nil and FC ~= nil and FW.enabled(), "sandbox FirmwareEnabled")
  if not (FW and FC and FW.enabled()) then return end
  local F = CFG.Firmware
  local d = fresh(p, "lab")
  d.adaptXP = S.xpForLevel(5)
  -- los chips se crean y tienen nombre traducido
  local types = { FW.BLANK }
  for _, id in ipairs(F.Order) do types[#types + 1] = FW.itemType(id) end
  local bad = {}
  for _, t in ipairs(types) do
    local it = M.addItem(p, t)
    local name = nil
    if it then pcall(function() name = it:getDisplayName() end) end
    if it and not name then pcall(function() name = it:getName() end) end
    if not it then bad[#bad + 1] = t .. " (no se crea)"
    elseif not name or name == "" or string.find(name, "ItemName_", 1, true) then bad[#bad + 1] = t .. " (sin nombre)" end
  end
  check("los " .. #types .. " chips se crean con nombre", #bad == 0, table.concat(bad, ", "))
  -- Heat y CN en 4 s de uso, con el ciclo real
  local function burst()
    d.heat = 0; d.neuralLoad = 0; d.lockUntilCool = false; d.rejection = 0; R.session(p).reuseAtMs = 0
    R.activate(p); simulate(p, 4)
    local out = { heat = d.heat, cn = d.neuralLoad }
    R.deactivate(p, "manual"); d.lockUntilCool = false; d.heat = 0
    return out
  end
  local base = burst()
  check("sin chips: laboratorio nivel 5, 4 s de uso = 40 de Heat", math.abs(base.heat - 40) < 2 and base.cn > 0, f1(base.heat) .. " / CN " .. string.format("%.3f", base.cn))
  d.firmware = { sistema = "Compatibilidad" }; d.fwRecalUntil = nil
  local cmp = burst()
  check("(108) Compatibilidad: el Heat sube un 10 % mas y la CN igual", math.abs(cmp.heat / base.heat - 1.1) < 0.03 and math.abs(cmp.cn / base.cn - 1) < 0.04,
    f1(cmp.heat) .. " contra " .. f1(base.heat) .. string.format(", CN x%.2f", cmp.cn / base.cn))
  d.firmware = { habilidad = "Overclock" }
  local pac = burst()
  check("(109) Overclock: la CN por uso x1.5 y el Heat igual", math.abs(pac.cn / base.cn - 1.5) < 0.06 and math.abs(pac.heat / base.heat - 1) < 0.05,
    string.format("CN x%.2f, Heat x%.2f", pac.cn / base.cn, pac.heat / base.heat))
  d.firmware = { sistema = "Compatibilidad" }; d.fwRecalUntil = S.worldHours() + 1
  local recal = burst()
  check("recalibrando: el Heat sube un 10 % mas", math.abs(recal.heat / cmp.heat - F.Recalibrate.HeatMult) < 0.03, string.format("x%.2f", recal.heat / cmp.heat))
  d.fwRecalUntil = nil
  -- instalar y sacar con la logica real
  d.firmware = {}; d.fwRecalUntil = nil; d.rejection = 0; d.heat = 0
  local T = FW.itemType("Centinela")
  local chip = M.addItem(p, T)
  local have = M.count(p, T)
  check("instalar el chip", FC.flash(p, chip) == true and d.firmware.sistema == "Centinela" and M.count(p, T) == have - 1, tostring(d.firmware.sistema))
  check("el cambio suma el rechazo y recalibra", math.abs(d.rejection - F.FlashRejection) < 0.01 and FW.recalLeft(d) > 0.9, f1(d.rejection) .. " / " .. string.format("%.2f h", FW.recalLeft(d)))
  R.session(p).reuseAtMs = 0; R.activate(p)
  local other = M.addItem(p, FW.itemType("Compatibilidad"))
  check("con el implante encendido no se cambia el chip", FC.flash(p, other) == false and d.firmware.sistema == "Centinela")
  R.deactivate(p, "manual"); d.lockUntilCool = false
  check("sacar el chip lo devuelve al inventario", FC.unflash(p, "sistema") == true and d.firmware.sistema == nil and M.count(p, T) == have)
  -- explantar devuelve los chips
  d.firmware = { sistema = "Compatibilidad", habilidad = "Martillo" }
  local a0, m0 = M.count(p, FW.itemType("Compatibilidad")), M.count(p, FW.itemType("Martillo"))
  M.explantPatientPart(p)
  check("explantar devuelve los dos chips y deja los slots vacios", M.count(p, FW.itemType("Compatibilidad")) == a0 + 1 and M.count(p, FW.itemType("Martillo")) == m0 + 1
        and d.firmware.sistema == nil and d.firmware.habilidad == nil and d.variant == nil)
  d.keptXP = nil; d.pendingRejection = nil
  fresh(p, "lab")
end) }

-- (83) Firmware: los chips con comportamiento ((108) despues de quitar seis): kills de Apogeo, Overclock sin Overdrive, Centinela (con el personaje de la prueba quieto: el movimiento
-- se mide por la posicion; si se movio, sale como info) y la Camara criogenica (enfria x1,75 apagado, tope de Heat x0,8, Heat x1,2 y ventana x0,8).
tests[#tests + 1] = { "Firmware: chips con comportamiento (v0.1.30 (108))", cleanAfter(function(p)
  local FW, FC = rawget(_G, "SandevistanFirmware"), rawget(_G, "SandevistanFirmwareClient")
  check("el firmware esta activo en esta partida", FW ~= nil and FC ~= nil and FW.enabled(), "sandbox FirmwareEnabled")
  if not (FW and FC and FW.enabled()) then return end
  local d = fresh(p, "lab")
  d.adaptXP = S.xpForLevel(5)
  local s = R.session(p)
  -- Apogeo (Habilidad): cada kill con el implante encendido baja killHeat de Heat, hasta MaxKills por ventana
  d.firmware = { habilidad = "Apogeo" }; d.heat = 80; s.reuseAtMs = 0; FC.kills = {}
  local KH, MK = CFG.Firmware.Programs.Apogeo.profile.killHeat, CFG.Firmware.KillHeat.MaxKills
  local p2 = FW.profile(d)
  check("Apogeo: perfil (Heat x1.1, XP por kill x1.25, 20 de Heat por kill)", math.abs(p2.heat - 1.1) < 1e-6 and math.abs(p2.xpKill - 1.25) < 1e-6 and p2.killHeat == KH and KH == 20)
  local got = 0
  for _ = 1, 7 do got = got + FC.killHeat(p, d, p2.killHeat) end
  check("Apogeo: siete kills seguidos bajan " .. (KH * MK) .. " de Heat (tope de " .. MK .. " por ventana)", math.abs(got - KH * MK) < 1e-6 and math.abs(d.heat - (80 - KH * MK)) < 1e-6, "bajo " .. f1(got) .. ", Heat " .. f1(d.heat))
  FC.kills = {}; d.firmware = {}; d.heat = 0
  -- (109) Overclock: sintomas x1,5, la linea roja sube con el Heat y sin Overdrive (armado y al tope corta como siempre)
  d.firmware = {}; local sym0 = S.symptomMultiplier(d)
  d.firmware = { habilidad = "Overclock" }
  check("Overclock: sintomas x1.5 y sin Overdrive", math.abs(S.symptomMultiplier(d) - sym0 * 1.5) < 1e-6 and FW.profile(d).noOverdrive == true)
  d.heat = 0; d.lockUntilCool = false; s.reuseAtMs = 0
  R.activate(p); local pbCold = s.eff and s.eff.playerBoost or 0
  d.heat = 95; simulate(p, 0.25)
  check("Overclock: con el Heat alto el bono de movimiento sube solo (linea roja)", s.eff and s.eff.playerBoost > pbCold + 0.15, string.format("%.3f -> %.3f", pbCold, s.eff and s.eff.playerBoost or -1))
  s.armed = true; simulate(p, 1.5)
  check("Overclock: al tope corta sin entrar en Overdrive", not s.overdrive and not R.isActive(p), "Overdrive " .. tostring(s.overdrive) .. ", activo " .. tostring(R.isActive(p)))
  R.deactivate(p, "manual"); d.firmware = {}; d.heat = 0; d.lockUntilCool = false; d.rejection = 0
  -- Centinela: el Heat de uso depende del movimiento (quieto x0.35)
  local function burst4()
    d.heat = 0; d.neuralLoad = 0; d.lockUntilCool = false; d.rejection = 0; s.reuseAtMs = 0; FC.mot = {}
    R.activate(p); simulate(p, 4)
    local cls = FC.motion(p)
    local h = d.heat
    R.deactivate(p, "manual"); d.lockUntilCool = false; d.heat = 0
    return h, cls
  end
  d.firmware = {}; local base = burst4()
  d.firmware = { sistema = "Centinela" }; local cen, cls = burst4()
  if cls == "still" then
    check("Centinela: quieto, el Heat de uso sube x0.35", base > 20 and math.abs(cen / base - 0.35) < 0.06, string.format("%.1f contra %.1f (x%.2f)", cen, base, cen / math.max(base, 0.01)))
  else
    out("info: Centinela no probado: el personaje se estaba moviendo (" .. tostring(cls) .. ")")
  end
  d.firmware = {}
  -- Camara criogenica ((111) en los dos implantes; se prueba en el militar): enfria x1,75 con el implante apagado (quieto o no), tope de Heat 80
  d = fresh(p, "military"); d.adaptXP = S.xpForLevel(8)
  d.firmware = { sistema = "CamaraCriogenica" }
  local pc = FW.profile(d)
  check("Camara criogenica: en un militar cuenta (Heat x1.2, ventana x0.8, enfriamiento x1.75, tope x0.8)", math.abs(pc.window - 0.8) < 1e-6 and math.abs(pc.heat - 1.2) < 1e-6
        and math.abs(pc.cool - 1.75) < 1e-6 and math.abs(S.heatCap(d) - 80) < 1e-6, f1(S.heatCap(d)))
  local function coolTwo()
    d.heat = 50; s.postCoolUntilMs = nil
    simulate(p, 2)
    local lost = 50 - d.heat
    d.heat = 0
    return lost
  end
  d.firmware = {}; local plain = coolTwo()
  d.firmware = { sistema = "CamaraCriogenica" }; local cam = coolTwo()
  check("Camara criogenica: con el implante apagado el Heat baja x1.75", plain > 5 and math.abs(cam / plain - 1.75) < 0.12, string.format("%.1f contra %.1f (x%.2f)", cam, plain, cam / math.max(plain, 0.01)))
  d.heat = 79; d.lockUntilCool = false; s.reuseAtMs = 0; R.activate(p); simulate(p, 1)
  check("Camara criogenica: corta al llegar a 80 de Heat", not R.isActive(p) and d.heat <= 80.01, f1(d.heat))
  R.deactivate(p, "manual"); d.firmware = {}; d.heat = 0; d.lockUntilCool = false
  fresh(p, "lab")
end) }

-- (84) Firmware ((108) reajustados): Compatibilidad (rechazo por hora y por evento x0,75, XP pasiva x1,5). (114) Sin Sostenido.
tests[#tests + 1] = { "Firmware: Compatibilidad (v0.1.30 (108))", cleanAfter(function(p)
  local FW, FC = rawget(_G, "SandevistanFirmware"), rawget(_G, "SandevistanFirmwareClient")
  check("el firmware esta activo en esta partida", FW ~= nil and FC ~= nil and FW.enabled(), "sandbox FirmwareEnabled")
  if not (FW and FC and FW.enabled()) then return end
  local d = fresh(p, "lab")
  d.adaptXP = S.xpForLevel(5)
  local P = rawget(_G, "SandevistanPeriodic")
  local function rejHour(chip)
    d.firmware = chip and { sistema = "Compatibilidad" } or {}; d.rejection = 10; d.immuno = {}; d.neuralLoad = 0; d.lastRejectionTickHour = S.worldHours() - 1
    if P then P.rejectionTick(p, d) end
    return d.rejection
  end
  if P then
    d.adaptXP = 0                                                             -- con la adaptacion estable el rechazo por hora no sube
    local r0, r1 = rejHour(false) - 10, rejHour(true) - 10
    d.adaptXP = S.xpForLevel(5)
    check("Compatibilidad: el rechazo por hora x0.75", math.abs(r0) > 0.01 and math.abs(r1 / r0 - 0.75) < 0.02, string.format("%.3f contra %.3f", r1, r0))
  else
    out("info: rechazo por hora de Compatibilidad no probado (sin Periodic)")
  end
  d.firmware = {}; local ev0 = S.eventRejection(d, 10, 18, 0.5)
  d.firmware = { sistema = "Compatibilidad" }
  check("Compatibilidad: rechazo de cortes y colapsos x0.75 y XP pasiva x1.5", math.abs(S.eventRejection(d, 10, 18, 0.5) - ev0 * 0.75) < 1e-6 and math.abs(FW.profile(d).xpPassive - 1.5) < 1e-6)
  d.firmware = {}; d.rejection = 0
  fresh(p, "lab")
end) }

-- (85) Firmware: aprender programas con el nivel de adaptacion y escribirlos en un chip virgen con el terminal portatil (con items reales); las recetas del chip virgen y del terminal
-- tienen que estar cargadas en el juego. La escritura en una computadora del mundo no se puede automatizar aca: la cubre el RECORRIDO (menu) y la sonda 1 de Debug.
tests[#tests + 1] = { "Firmware: aprender y escribir (v0.1.30 (85))", cleanAfter(function(p)
  local FW, FC = rawget(_G, "SandevistanFirmware"), rawget(_G, "SandevistanFirmwareClient")
  check("el firmware esta activo en esta partida", FW ~= nil and FC ~= nil and FW.enabled(), "sandbox FirmwareEnabled")
  if not (FW and FC and FW.enabled()) then return end
  local W = CFG.Firmware.Write
  local d = fresh(p, "lab")
  local keepAll = CFG.Firmware.AllKnown
  CFG.Firmware.AllKnown = false
  -- aprender por nivel: la cuenta sale de la Config (programas terminados con nivel <= el de adaptacion)
  d.fwKnown = {}
  local bad = {}
  for level = 1, 5 do
    d.adaptXP = S.xpForLevel(level); FW.syncKnown(d)
    local want = 0
    for _, id in ipairs(CFG.Firmware.Order) do local pr = CFG.Firmware.Programs[id]; if pr.ready and pr.level <= level then want = want + 1 end end
    if #FW.knownList(d) ~= want then bad[#bad + 1] = string.format("nivel %d: %d conocidos, esperados %d", level, #FW.knownList(d), want) end
  end
  check("los programas se aprenden con el nivel (1 a 5 del laboratorio)", #bad == 0, table.concat(bad, " | "))
  check("(111) la Camara criogenica (nivel 5) se aprende tambien en un laboratorio nivel 5", FW.known(d, "CamaraCriogenica"))
  d.fwKnown = {}; d.adaptXP = 0; d.knows.firmware = nil
  check("con adaptacion 0 no se conoce ningun programa", #FW.syncKnown(d) == 0 and #FW.knownList(d) == 0)
  d.adaptXP = S.xpForLevel(4); FC.syncKnown(p)                -- (108) nivel 4: Martillo, Centinela, Apogeo y Compatibilidad
  check("al subir de nivel se aprenden programas y el chip virgen y el terminal", #FW.knownList(d) >= 3 and d.knows.firmware == true and M.knows(p, "firmware"), tostring(#FW.knownList(d)))
  check("escribir lleva 60 s sin costumbre y 25 s con la adaptacion estable", math.abs(FW.writeSeconds(S.data(p)) - (60 - 35 * 0.8)) < 0.01, string.format("%.1f s en el nivel 4", FW.writeSeconds(S.data(p))))
  if M.nativeRecipesLoaded() then
    check("la receta nativa del chip virgen esta cargada", M.nativeRecipe("fwchip") ~= nil)
  else
    out("info: recetas nativas no cargadas en esta partida")
  end
  -- escribir con el terminal (items reales: el terminal, el chip virgen y una bateria de Base). Las cuentas son por diferencia: el personaje puede llevar baterias o chips propios.
  d.adaptXP = S.xpForLevel(5); d.fwKnown = {}; FW.syncKnown(d)
  local term = M.addItem(p, W.Terminal)
  local blank = M.addItem(p, FW.BLANK)
  local src = { kind = "terminal", item = term }
  check("existen el terminal y el chip virgen", term ~= nil and blank ~= nil)
  if term and blank then
    local batteries = M.count(p, W.Battery)
    if batteries == 0 then
      check("sin bateria el terminal no escribe", #FC.writeReasons(p, "Compatibilidad", src) == 1 and FC.write(p, "Compatibilidad", src) == false)
      M.addItem(p, W.Battery)
    end
    if M.count(p, W.Battery) > 0 then
      check("con la bateria no falta nada", #FC.writeReasons(p, "Compatibilidad", src) == 0, table.concat(FC.writeReasons(p, "Compatibilidad", src), " | "))
      local b0, c0, r0 = M.count(p, W.Battery), M.count(p, FW.BLANK), M.count(p, FW.itemType("Compatibilidad"))
      local wrote = FC.write(p, "Compatibilidad", src)
      check("escribir gasta el chip virgen y la bateria y entrega el chip del programa", wrote == true and M.count(p, FW.BLANK) == c0 - 1 and M.count(p, W.Battery) == b0 - 1
        and M.count(p, FW.itemType("Compatibilidad")) == r0 + 1, string.format("virgenes %d -> %d, baterias %d -> %d", c0, M.count(p, FW.BLANK), b0, M.count(p, W.Battery)))
    else
      out("info: no se pudo crear " .. tostring(W.Battery) .. " en esta version")
    end
    M.addItem(p, FW.BLANK); d.fwKnown.Overclock = nil
    check("un programa que no sabes no se escribe", FC.write(p, "Overclock", src) == false)
  end
  CFG.Firmware.AllKnown = keepAll
  d.fwKnown = {}; d.knows.firmware = nil
  fresh(p, "lab")
end) }

-- (86) Firmware: Taller, el modo trabajo (con el ciclo real del Runtime): tramo fijo de 0,8 sin bonos, Heat x0,28 con enfriado activo, sin estamina ni XP por tiempo, los candados de CN y
-- rechazo, la pausa de la fatiga mental y los ganchos de las acciones mas rapidas (que clases del juego engancho). Las amenazas con zombis y el tiempo de una accion real se miran en el RECORRIDO.
tests[#tests + 1] = { "Firmware: Taller, modo trabajo (v0.1.30 (86))", cleanAfter(function(p)
  local FW, FC = rawget(_G, "SandevistanFirmware"), rawget(_G, "SandevistanFirmwareClient")
  check("el firmware esta activo en esta partida", FW ~= nil and FC ~= nil and FW.enabled(), "sandbox FirmwareEnabled")
  if not (FW and FC and FW.enabled()) then return end
  local Wk = CFG.Firmware.Work
  local d = fresh(p, "lab")
  d.adaptXP = S.xpForLevel(5); d.firmware = { habilidad = "Taller" }
  local s = R.session(p)
  local t = S.dilationTier(d, S.level(d))
  check("tramo del modo trabajo: mundo x0,75 y sin bonos", math.abs(t.zombieSpeed - 0.75) < 1e-9 and t.playerBoost == 0 and t.attackBoost == 0, tostring(t.zombieSpeed))
  s.reuseAtMs = 0; d.heat = 20; d.neuralLoad = 0
  local e0 = E.getEndurance(p)
  local ok = R.activate(p)
  check("enciende el modo trabajo", ok == true and s.work == true and R.isActive(p))
  if ok then
    local debt0 = select(1, R.debt(p))
    simulate(p, 4)
    check("(108) Heat por segundo x0,15 con enfriado activo: baja unos 0,98 por segundo (laboratorio nivel 5)", d.heat > 14.5 and d.heat < 17.5, f1(d.heat))
    local drain = S.staminaDrainPerSecond(S.level(d), false) * 4
    if R.debtOn() then
      -- (139) con la deuda de estamina la resistencia no baja: el drenaje del implante va a la deuda
      local spent = select(1, R.debt(p)) - debt0
      check("(108) gasta estamina x0,2 (como deuda)", spent > 0 and spent <= drain * 0.2 + 0.01, string.format("deuda +%.4f (sin chip serian %.4f)", spent, drain))
      check("con la deuda la resistencia no baja", math.abs(E.getEndurance(p) - e0) < 1e-6, string.format("%.4f -> %.4f", e0, E.getEndurance(p)))
    else
      check("(108) gasta estamina x0,2", E.getEndurance(p) < e0 and E.getEndurance(p) >= e0 - drain * 0.2 - 0.01, string.format("%.4f -> %.4f (sin chip serian %.4f)", e0, E.getEndurance(p), drain))
    end
    check("sin XP de adaptacion por tiempo ni impulso", (s.xpPending or 0) == 0 and (s.momentum or 0) == 0)
    check("el tramo efectivo no tiene bonos", s.eff ~= nil and s.eff.playerBoost == 0 and s.eff.attackBoost == 0 and math.abs(s.eff.zombieSpeed - 0.75) < 1e-9)
    d.neuralLoad = Wk.MaxCN; simulate(p, 0.25)
    check("con CN en zona critica el modo trabajo se suspende solo", not R.isActive(p) and d.lockUntilCool == false, "CN " .. f1(d.neuralLoad))
  end
  d.neuralLoad = 0; d.heat = 0; s.reuseAtMs = 0
  d.rejection = Wk.MaxRejection
  local can, why = R.canActivate(p)
  check("con rechazo 50 no se enciende", can == false and why == "IGUI_Sandevistan_Fw_WorkRejection", tostring(why))
  d.rejection = 0
  -- ganchos de las acciones mas rapidas
  local hooked, missing = {}, {}
  for k in pairs(FC.work.classes) do hooked[#hooked + 1] = k end
  for k in pairs(FC.work.missing) do missing[#missing + 1] = k end
  table.sort(hooked); table.sort(missing)
  check("se engancho getDuration de al menos una clase de acciones del juego (ISHandcraftAction o ISCraftAction)", FC.work.classes.ISHandcraftAction == true or FC.work.classes.ISCraftAction == true,
    "enganchadas: " .. table.concat(hooked, ", ") .. " | no existen: " .. table.concat(missing, ", "))
  out("info: acciones aceleradas hasta ahora = " .. tostring(FC.work.scaled) .. "; ISBaseTimedAction.adjustMaxTime enganchado = " .. tostring(FC.work.base))
  d.firmware = {}; s.work = false
  fresh(p, "lab")
end) }

-- (87) Firmware: decompilar un chip programado (items reales y el terminal portatil: la computadora del mundo la cubre el RECORRIDO), el expediente militar que ensena la Camara criogenica y
-- los chips programados en el botin y en la base militar (solo informa: depende de la partida y del servidor).
tests[#tests + 1] = { "Firmware: decompilar y chips del mundo (v0.1.30 (87))", cleanAfter(function(p)
  local FW, FC = rawget(_G, "SandevistanFirmware"), rawget(_G, "SandevistanFirmwareClient")
  check("el firmware esta activo en esta partida", FW ~= nil and FC ~= nil and FW.enabled(), "sandbox FirmwareEnabled")
  if not (FW and FC and FW.enabled()) then return end
  local W = CFG.Firmware.Write
  local d = fresh(p, "lab")
  local keepAll = CFG.Firmware.AllKnown
  CFG.Firmware.AllKnown = false
  d.adaptXP = 0; d.fwKnown = {}
  check("decompilar lleva la mitad de lo que lleva escribir", math.abs(FW.decompileSeconds(S.data(p)) - FW.writeSeconds(S.data(p)) * 0.5) < 1e-9, string.format("%.1f s sin costumbre", FW.decompileSeconds(S.data(p))))
  local term = M.addItem(p, W.Terminal)
  local chip = M.addItem(p, FW.itemType("Overclock"))
  local src = { kind = "terminal", item = term }
  check("existen el terminal y un chip programado de Overclock", term ~= nil and chip ~= nil)
  if term and chip then
    if M.count(p, W.Battery) == 0 then
      check("sin bateria el terminal no decompila", #FC.decompileReasons(p, "Overclock", src) == 1 and FC.decompile(p, "Overclock", src) == false and M.count(p, FW.itemType("Overclock")) >= 1)
      M.addItem(p, W.Battery)
    end
    if M.count(p, W.Battery) > 0 then
      check("con la bateria no falta nada", #FC.decompileReasons(p, "Overclock", src) == 0, table.concat(FC.decompileReasons(p, "Overclock", src), " | "))
      local b0, c0, r0 = M.count(p, W.Battery), M.count(p, FW.BLANK), M.count(p, FW.itemType("Overclock"))
      local ok = FC.decompile(p, "Overclock", src)
      check("decompilar gasta el chip programado y la bateria, entrega un chip virgen y ensena el programa", ok == true and M.count(p, FW.itemType("Overclock")) == r0 - 1
        and M.count(p, FW.BLANK) == c0 + 1 and M.count(p, W.Battery) == b0 - 1 and FW.known(d, "Overclock"),
        string.format("programados %d -> %d, virgenes %d -> %d, baterias %d -> %d", r0, M.count(p, FW.itemType("Overclock")), c0, M.count(p, FW.BLANK), b0, M.count(p, W.Battery)))
      check("un programa que ya sabes no se decompila", #FC.decompileReasons(p, "Overclock", src) >= 1 and FC.decompile(p, "Overclock", src) == false)
    else
      out("info: no se pudo crear " .. tostring(W.Battery) .. " en esta version")
    end
  end
  -- el menu real del terminal con un chip programado encima ofrece decompilar
  local MN = rawget(_G, "SandevistanMenus")
  if MN and MN.addDecompileMenu and term and ISContextMenu then
    M.addItem(p, FW.itemType("Compatibilidad")); d.fwKnown.Compatibilidad = nil
    local ctx = ISContextMenu:new(0, 0, 200, 20)
    local okMenu, errMenu = pcall(MN.addDecompileMenu, ctx, p, src)
    local found = false
    for i = 1, (ctx.numOptions or 0) do local o = ctx.options and ctx.options[i]; if o and o.name == getText("IGUI_Sandevistan_Fw_DecompileTerminal") then found = true end end
    pcall(function() ctx:clear() end)
    check("el menu del terminal ofrece 'Decompilar un chip con el terminal'", okMenu and found, tostring(errMenu))
  else
    out("info: menu de decompilar no probado (sin menus en este entorno)")
  end
  -- expediente militar: con los dos expedientes completos encima la Camara criogenica se aprende sola (se prueba el chequeo real y la ruta con uno de mentira)
  local Md = rawget(_G, "SandevistanMedical")
  check("la Camara criogenica se aprende tambien con el expediente militar", CFG.Firmware.Programs.CamaraCriogenica.dossiers == true)
  if Md and Md.militaryDossiersComplete then
    local okC, complete = pcall(Md.militaryDossiersComplete, p)
    check("el chequeo de los expedientes militares completos corre", okC and type(complete) == "boolean", tostring(complete))
    d.fwKnown = {}
    local real = Md.militaryDossiersComplete
    Md.militaryDossiersComplete = function() return true end
    local got = FC.syncDossiers(p, d)
    Md.militaryDossiersComplete = real
    check("con los expedientes completos se aprenden Compatibilidad y la Camara criogenica (aunque el nivel no llegue)", #got == 2 and FW.known(d, "CamaraCriogenica") and FW.known(d, "Compatibilidad"), table.concat(got, ","))
  end
  -- botin y base (informativo)
  local PD = rawget(_G, "ProceduralDistributions")
  if PD and PD.list and not isClient() then
    local n, tables = 0, 0
    for _, dist in pairs(PD.list) do
      if type(dist) == "table" and type(dist.items) == "table" then
        local here = 0
        for i = 1, #dist.items, 2 do if type(dist.items[i]) == "string" and string.find(dist.items[i], "Sandevistan.Fw", 1, true) and dist.items[i] ~= FW.BLANK then here = here + 1 end end
        if here > 0 then tables = tables + 1; n = n + here end
      end
    end
    check("las tablas de botin traen chips de firmware programados", n > 0, string.format("%d entradas en %d tablas", n, tables))
  else
    out("info: botin no revisado (en multijugador lo reparte el servidor)")
  end
  local Wd = rawget(_G, "SandevistanWorld")
  local log = Wd and Wd.authority and Wd.data and Wd.data().placedLog and Wd.data().placedLog.base
  if log then
    local n = 0
    for _, e in ipairs(log) do if type(e.t) == "string" and string.find(e.t, "Sandevistan.Fw", 1, true) then n = n + 1 end end
    local want = #CFG.World.FwBaseChips.fixed + CFG.World.FwBaseChips.random.count
    out(string.format("info: chips de firmware programados colocados en la base militar = %d (esperados %d en una partida nueva)", n, want))
  else
    out("info: la base militar todavia no se coloco en esta partida (o no corre en este cliente)")
  end
  CFG.Firmware.AllKnown = keepAll
  d.fwKnown = {}; d.knows.firmware = nil
  fresh(p, "lab")
end) }

---------------------------------------------------------------------------
-- Prueba de mundo (asíncrona): ex-sujeto → cadáver → extracción
---------------------------------------------------------------------------
local world = nil

local function startWorldTest(p)
  -- v0.1.30 (13): en un cliente de multijugador el mundo no corre (lo maneja el servidor): la prueba spawneaba un zombi local
  if not SandevistanWorld or not SandevistanWorld.authority then
    if isClient() then out("info: prueba de mundo salteada (en multijugador el mundo lo maneja el servidor)")
    else check("mundo disponible", false) end
    return false
  end
  local sq = getCell():getGridSquare(math.floor(p:getX()) + 3, math.floor(p:getY()), p:getZ())
  local id = sq and SandevistanWorld.spawnAt(sq, "test", "lab")
  check("spawnea ex-sujeto de prueba", id ~= nil)
  if not id then return false end
  local zl = getCell():getZombieList()
  local z = nil
  for i = 0, zl:size() - 1 do
    local c = zl:get(i)
    if SandevistanWorld.tagged()[c] == id then z = c end
  end
  check("queda marcado en memoria", z ~= nil)
  if not z then return false end
  S.try("killTest", function() z:Kill(p) end)
  world = { id = id, untilMs = S.realMs() + 5000 }
  return true
end

local function pollWorldTest(p)
  local sub = SandevistanWorld.data().subjects[world.id]
  if sub and sub.state == "corpse" then
    local body = nil
    local cell = getCell()
    for dx = -3, 3 do for dy = -3, 3 do
      local sq = cell:getGridSquare(sub.x + dx, sub.y + dy, sub.z)
      local bodies = sq and sq:getDeadBodys()
      if bodies then
        for i = 0, bodies:size() - 1 do
          local md = bodies:get(i):getModData().Sandevistan
          if type(md) == "table" and md.subjectId == world.id then body = bodies:get(i) end
        end
      end
    end end
    check("cadaver con implante registrado", body ~= nil)
    if body then
      local before = M.count(p, M.T.Lab)
      M.performExtraction(p, body)
      check("extraccion entrega el implante", M.count(p, M.T.Lab) == before + 1)
      check("no se puede extraer dos veces", M.corpseImplant(body) == nil)
    end
    sub.state = "test"
    return true
  end
  if S.realMs() > world.untilMs then
    check("el ex-sujeto muerto genera cadaver con implante", false, "estado=" .. tostring(sub and sub.state))
    if sub then sub.state = "test" end
    return true
  end
  return false
end

-- (90) Firmware: CADA chip, de punta a punta. Para cada programa: se instala el chip de verdad (FC.flash con el item) en el hardware que lo admite, se mide cada campo del perfil
-- contra la formula real del motor (el mismo numero que muestra la pestana Implante) comparando con el mismo personaje sin chips, y se saca (FC.unflash). Los campos que solo se
-- ven con un golpe, un kill o el paso de las horas se dejan para sus pruebas ("chips con comportamiento", "Taller...") y quedan listados como info.
tests[#tests + 1] = { "Firmware: cada chip, efecto en el motor (v0.1.30 (90))", cleanAfter(function(p)
  local FW, FC = rawget(_G, "SandevistanFirmware"), rawget(_G, "SandevistanFirmwareClient")
  local CB = rawget(_G, "SandevistanCombat")
  check("el firmware esta activo en esta partida", FW ~= nil and FC ~= nil and FW.enabled(), "sandbox FirmwareEnabled")
  if not (FW and FC and FW.enabled()) then return end
  local function near(a, b, tol) return math.abs((a or 0) - (b or 0)) <= (tol or 0.02) * math.max(1, math.abs(b or 0)) end
  local function fmt(x) return string.format("%.3f", x or 0) end
  local measuredAll, pendingAll = 0, {}

  -- lo que mide el motor ahora mismo con los chips que haya puestos (hardware y nivel fijos por quien llama)
  local function engine(d, level)
    local s = R.session(p)
    s.tier = S.dilationTier(d, level); s.momentum = 0; s.overdrive = false; s.active = false
    local eff = R.effectiveTier(s, d)
    local m = {
      heat = S.heatPerSecond(d, level), cool = S.coolPerSecond(d, level) * (FC.coolMult(p, d, R.session(p)) or 1), window = S.overdriveWindow(d, level),
      cap = S.heatCap(d),
      sym = S.symptomMultiplier(d), ev = S.eventRejection(d, 10, 10, 0.5),
      zs = eff.zombieSpeed, pb = eff.playerBoost, ab = eff.attackBoost,
    }
    if CB and CB.refund then m.refund = CB.refund(p) end
    return m
  end
  -- rechazo por hora y XP pasiva de adaptacion con la adaptacion en cero (si no, el nivel estable las anula)
  local function hourly(d)
    local xp0 = d.adaptXP
    d.adaptXP = 0; d.rejection = 0; d.lastRejectionTickHour = S.worldHours() - 1
    P.rejectionTick(p, d)
    local rej = d.rejection
    d.rejection = 0; d.xpSrc = nil; d.lastCNTickHour = S.worldHours() - 1
    P.hourlyTick(p, d)
    local xp = d.adaptXP
    d.adaptXP = xp0; d.rejection = 0
    return rej, xp
  end
  -- 2 s con el implante encendido: CN y XP por tiempo ganadas (y el Heat real acumulado)
  local function live(d)
    local s = R.session(p)
    d.heat = 0; d.neuralLoad = 0; d.lockUntilCool = false; d.rejection = 0; s.reuseAtMs = 0; s.xpPending = 0; s.xpBy = {}; FC.mot = {}
    local xp0 = d.adaptXP
    if not R.activate(p) then return nil end
    simulate(p, 2)
    local r = { cn = d.neuralLoad, heat = d.heat, xp = (d.adaptXP - xp0) + (s.xpPending or 0), cls = FC.motion(p) }
    R.deactivate(p, "manual"); d.lockUntilCool = false; d.heat = 0; d.neuralLoad = 0
    s.xpPending = 0; s.xpBy = {}; d.adaptXP = xp0; s.reuseAtMs = 0
    return r
  end

  for _, id in ipairs(CFG.Firmware.Order) do
    local pr = CFG.Firmware.Programs[id]
    local mil = pr.only == "military"
    local d = fresh(p, mil and "military" or "lab")
    local level = mil and 8 or 5
    d.adaptXP = S.xpForLevel(level)
    local s = R.session(p)
    local base = engine(d, level)
    local baseRej, baseXp = hourly(d)
    local baseLive = live(d)
    check(id .. ": se puede encender el implante sin chip (linea base de las medidas en vivo)", baseLive ~= nil, "R.activate dijo no")

    -- instalar de verdad, con el chip del inventario
    local chip = S.giveItem(p:getInventory(), FW.itemType(id))
    check(id .. ": el chip existe como item (" .. FW.itemType(id) .. ")", chip ~= nil and chip ~= false)
    local ok = chip and FC.flash(p, chip)
    check(id .. ": se instala con el chip y el programa queda activo en su slot", ok == true and FW.slotProgram(d, pr.slot) == id and FW.active(d, id), "slot " .. tostring(FW.slotProgram(d, pr.slot)))
    d.rejection = 0; d.fwRecalUntil = nil                       -- el costo de instalar (+3 de rechazo y recalibrado) no entra en las medidas
    if ok then
      local prof = FW.profile(d)
      local m = engine(d, level)
      local rej, xp = hourly(d)
      local notes, done = {}, 0
      local function ratio(name, got, want, ref, tol)
        done = done + 1
        check(string.format("%s: %s (x%s esperado, midio x%s)", id, name, fmt(want), fmt(ref and ref ~= 0 and got / ref or 0)), ref ~= nil and ref ~= 0 and near(got / ref, want, tol), fmt(got) .. " contra " .. fmt(ref))
      end
      local work = prof.mode == "work"
      if work then
        local t = FW.tier(d, S.dilationTier(d, level))
        done = done + 1
        check(id .. ": modo trabajo: tramo fijo con el mundo a " .. fmt(CFG.Firmware.Work.World) .. " y sin bonos", near(t.world, CFG.Firmware.Work.World) and t.playerBoost == 0 and t.attackBoost == 0, fmt(t.world))
        notes[#notes + 1] = "el resto de Taller (candados, acciones, flujo): prueba 'Taller, modo trabajo'"
      else
        local hw, cw = prof.heat / prof.thermalMass, prof.cool / prof.thermalMass          -- (110) la masa termica (Reactor) divide todo el Heat
        if hw ~= 1 then ratio("Heat por segundo", m.heat, hw, base.heat) end
        if cw ~= 1 then ratio("enfriamiento con el implante apagado", m.cool, cw, base.cool) end
        if prof.maxHeat ~= 1 then ratio("tope de Heat", m.cap, prof.maxHeat, base.cap) end
        if prof.window ~= 1 then ratio("ventana de Overdrive", m.window, prof.window, base.window) end
        if prof.symptoms ~= 1 then ratio("sintomas de la CN", m.sym, prof.symptoms, base.sym) end
        if prof.rejEvent ~= 1 then ratio("rechazo de cortes y colapsos", m.ev, prof.rejEvent, base.ev) end
        if prof.rej ~= 1 then ratio("rechazo por hora", rej, prof.rej, baseRej) end
        if prof.xpPassive ~= 1 then ratio("XP pasiva de adaptacion", xp, prof.xpPassive, baseXp) end
        if prof.refund ~= 1 and m.refund and base.refund then ratio("estamina devuelta por golpe", m.refund, prof.refund, base.refund) end
        if prof.ab ~= 1 and base.ab ~= 0 then ratio("bono de velocidad de ataque", m.ab, prof.ab, base.ab) end
        if prof.zs ~= 0 then
          done = done + 1
          local want = math.min(1, math.max(FW.minZs(), base.zs + prof.zs))
          check(string.format("%s: factor de velocidad de los zombis %s -> %s", id, fmt(base.zs), fmt(want)), near(m.zs, want, 0.005), fmt(m.zs))
        end
        if prof.pb ~= 0 then
          done = done + 1
          local want = math.max(0, base.pb + prof.pb)
          check(string.format("%s: bono de velocidad del jugador %s -> %s", id, fmt(base.pb), fmt(want)), near(m.pb, want, 0.005), fmt(m.pb))
        end
        -- con el implante encendido: CN por uso, XP por tiempo y Heat acumulado de verdad (el Heat de los que miran el movimiento o cortan solo se prueba en su prueba)
        local lv = live(d)
        if lv and baseLive then
          if prof.cn ~= 1 and baseLive.cn > 0 then ratio("CN por segundo de uso (encendido 2 s)", lv.cn, prof.cn, baseLive.cn, 0.04) end
          if prof.xpTime ~= 1 and baseLive.xp > 0 then ratio("XP de adaptacion por segundo de uso (encendido 2 s)", lv.xp, prof.xpTime, baseLive.xp, 0.04) end
          if hw ~= 1 and not prof.centinela and baseLive.heat > 0 then ratio("Heat real acumulado (encendido 2 s)", lv.heat, hw, baseLive.heat, 0.04) end
        else
          done = done + 1
          check(id .. ": se puede encender el implante con el chip puesto", lv ~= nil, "R.activate dijo no")
        end
        if prof.momentumRamp ~= 1 or prof.momentumDecay ~= 1 then notes[#notes + 1] = "inercia del Impulso: se ve usando el implante seguido" end
        if prof.centinela or prof.killHeat ~= 0 or prof.noOverdrive or prof.overclock then notes[#notes + 1] = "comportamiento (movimiento, kills, linea roja, sin Overdrive): prueba 'chips con comportamiento'" end
        if prof.dmg ~= 0 or prof.knock ~= 0 or prof.wear ~= 0 or prof.critMult ~= 1 or prof.xpKill ~= 1 then notes[#notes + 1] = "golpes y kills (dano, derribo, critico, desgaste, XP por kill): se ven en combate real" end
      end
      measuredAll = measuredAll + done
      out(string.format("%s: %d campos medidos contra el motor%s", id, done, #notes > 0 and ("; no medidos aca: " .. table.concat(notes, " / ")) or ""))
      if #notes > 0 then pendingAll[#pendingAll + 1] = id end
      -- sacarlo: el chip vuelve al inventario y el perfil queda neutro
      local out1 = FC.unflash(p, pr.slot)
      check(id .. ": se saca y vuelve al inventario como chip", out1 == true and FW.slotProgram(d, pr.slot) == nil and p:getInventory():getCountTypeRecurse(FW.itemType(id)) >= 1, tostring(FW.slotProgram(d, pr.slot)))
    end
    -- el hardware que no lo admite lo rechaza (solo militar en laboratorio, solo laboratorio en militar)
    if pr.only then
      local other = fresh(p, mil and "lab" or "military")
      local why = FW.flashProblems(other, id)
      check(id .. ": en el otro hardware no se instala (solo " .. pr.only .. ")", #why > 0, #why > 0 and tostring(why[1][1]) or "se dejaba instalar")
    end
  end
  out(string.format("-- %d campos de perfil medidos contra el motor; con comportamiento o de combate (se prueban aparte): %s", measuredAll, table.concat(pendingAll, ", ")))
  fresh(p, "lab")
end) }

---------------------------------------------------------------------------
-- (135) Inmunodepresion (21-plan-inmunodepresion.md): contra el juego real. Debug -> Rechazo -> "Probar la inmunodepresion" las corre solas
-- (Zomboid/Lua/Sandevistan_immuno.txt). El cuerpo se prueba en una parte SANA del personaje y se la deja como estaba; el estado del mod lo repone F.finish.
---------------------------------------------------------------------------
local function near(a, b, eps) return math.abs((a or -999) - (b or 999)) < (eps or 1e-4) end

tests[#tests + 1] = { "Inmunodepresion: el juego tiene lo que usa el mod", function(p)
  local bd = p:getBodyDamage()
  local bp = bd:getBodyPart(BodyPartType.Hand_L)
  local missing = {}
  for _, m in ipairs({ "getScratchTime", "setScratchTime", "getCutTime", "setCutTime", "getDeepWoundTime", "setDeepWoundTime", "getBurnTime", "setBurnTime",
                       "getStitchTime", "getWoundInfectionLevel", "setWoundInfectionLevel", "isInfectedWound", "setInfectedWound", "IsInfected", "getAlcoholLevel",
                       "bandaged", "getBandageLife", "haveGlass", "isNeedBurnWash", "hasDirtyClothing", "hasBloodyClothing" }) do
    if bp[m] == nil then missing[#missing + 1] = "BodyPart." .. m end
  end
  for _, m in ipairs({ "getCatchACold", "setCatchACold", "getColdStrength", "setColdStrength", "isHasACold", "getBodyParts" }) do
    if bd[m] == nil then missing[#missing + 1] = "BodyDamage." .. m end
  end
  if p.getReduceInfectionPower == nil then missing[#missing + 1] = "player.getReduceInfectionPower" end
  check("metodos del cuerpo, del resfrio y de los antibioticos", #missing == 0, #missing > 0 and table.concat(missing, ", ") or nil)
  check("stats de malestar (FOOD_SICKNESS y SICKNESS)", CharacterStat ~= nil and CharacterStat.FOOD_SICKNESS ~= nil and CharacterStat.SICKNESS ~= nil)
  check("moodle de malestar del juego (MoodleType.SICK)", MoodleType ~= nil and MoodleType.SICK ~= nil)
  check("rasgos (Resistente, Propenso, curacion rapida y lenta)", CharacterTrait ~= nil and CharacterTrait.RESILIENT ~= nil and CharacterTrait.PRONE_TO_ILLNESS ~= nil
    and CharacterTrait.FAST_HEALER ~= nil and CharacterTrait.SLOW_HEALER ~= nil)
  local secs = SandevistanImmunodep.realSeconds(nil, 0)
  check("duracion de un minuto de juego en segundos reales", secs > 0 and secs < 60, f1(secs) .. " s")
  local t = E.immunoTraits(p)
  out(string.format("info: rasgos del personaje: resistente=%s propenso=%s rapida=%s lenta=%s | enfermo ahora: %s | sandbox x%.1f",
    tostring(t.resilient), tostring(t.prone), tostring(t.fastHealer), tostring(t.slowHealer), tostring(E.sickReason(p)), CFG.Immunosuppressant.Immunodepression.Level or 0))
end }

tests[#tests + 1] = { "Inmunodepresion: dosis, piso, dosis de choque y rebote", cleanAfter(function(p)
  local d = fresh(p, "lab")
  if not S.immunodepOn() then out("info: apagada en el sandbox, salteada"); return end
  d.immunodep, d.immunoPeak, d.immunoDoses, d.immunoReboundUntil = 0, 0, {}, -1
  add(p, M.T.Clinical)
  local _, _, _, i0, i1 = M.immunoPreview(p, "clinical")
  M.takeImmuno(p, M.find(p, M.T.Clinical), "clinical", true)
  check("primera clinica: 0 -> 50 (y la vista previa lo decia)", near(d.immunodep, 50) and near(i0, 0) and near(i1, 50), f1(d.immunodep))
  check("CN por uso -50 %, sin dosis de choque", near(S.immunoNeuralMultiplier(d), 0.5) and S.immunoShockDecay(d) == 1, f1(S.immunoNeuralMultiplier(d)))
  M.takeImmuno(p, M.find(p, M.T.Clinical), "clinical", true)
  check("segunda clinica: 95, CN por uso -65 %, la CN baja x1,5", near(d.immunodep, 95) and near(S.immunoNeuralMultiplier(d), 0.35) and S.immunoShockDecay(d) == 1.5,
    f1(d.immunodep) .. ", x" .. string.format("%.2f", S.immunoNeuralMultiplier(d)))
  check("tolerancia: la proxima cubre el 50 %", near(S.immunoDurationFactor(d), 0.5), f1(S.immunoDurationFactor(d)))
  local MDS = rawget(_G, "SandevistanMoodles")
  local mdef; for _, def in ipairs(MDS and MDS.DEFS or {}) do if def.name == "SandevistanImmunodep" then mdef = def end end
  check("moodle Inmunodeprimido en nivel 4", mdef ~= nil and mdef.level(p, d) == 4)
  -- 24 h despues con cobertura: baja hacia el piso 50 (4/h despierto, 6/h dormido, 2/h como minimo)
  local now = S.worldHours()
  d.lastImmunoTickHour = now - 24
  P.immunoTick(p, d)
  check("24 h con cobertura: baja y se queda en el piso 50", near(d.immunodep, 50), f1(d.immunodep))
  -- termina la cobertura: rebote (la tanda llego a 95)
  d.immuno = { clinicalUntil = now - 0.1 }
  d.lastImmunoTickHour = now - 0.2
  P.immunoTick(p, d)
  check("al terminar la cobertura: rebote de rechazo x1,5 por 6 h", S.immunoReboundMult(d, now) == 1 + 0.5 * (CFG.Immunosuppressant.Immunodepression.Level or 0)
    and near(d.immunoReboundUntil - now, CFG.Immunosuppressant.Immunodepression.Rebound.Hours, 0.01), f1(d.immunoReboundUntil - now) .. " h")
  local rate = S.immunoDecayRate(p:isAsleep(), E.immunoTraits(p), E.sickReason(p) ~= nil)
  check("vuelve a 0 en unas 12 h (a tu ritmo actual: " .. f1(rate) .. "/h)", near(S.immunoHoursToNormal(d, now, rate), d.immunodep / rate, 0.01), f1(S.immunoHoursToNormal(d, now, rate)) .. " h")
  local IV = rawget(_G, "SandevistanInfoView")
  if not IV then out("info: pestana Implante no cargada, salteada"); return end
  local txt = {}
  for _, l in ipairs(IV.buildLines(p, d, R.session(p), now)) do txt[#txt + 1] = l.text end
  txt = table.concat(txt, "\n")
  check("la pestana Implante muestra la inmunodepresion y el rebote", txt:find(getText("IGUI_Sandevistan_Info_ImmunoRebound", "", ""):sub(1, 6), 1, true) ~= nil
    and txt:find(getText("IGUI_Sandevistan_Info_Immunodep", "", "", ""):sub(1, 6), 1, true) ~= nil)
end) }

tests[#tests + 1] = { "Inmunodepresion: efectos sobre el cuerpo real", function(p)
  local d = fresh(p, "lab")
  if not S.immunodepOn() then out("info: apagada en el sandbox, salteada"); return end
  if isClient() then out("info: salteada en multijugador (el servidor deshace los cambios del cuerpo hechos en el cliente)"); return end
  local IM = SandevistanImmunodep
  local bd = p:getBodyDamage()
  -- una parte sana (sin heridas, sin venda, sin infeccion): se la deja como estaba con RestoreToFullHealth
  local bp, name = nil, nil
  for _, n in ipairs({ "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperLeg_L", "UpperLeg_R" }) do
    local b = bd:getBodyPart(BodyPartType[n])
    if b and b:getScratchTime() <= 0 and b:getCutTime() <= 0 and b:getDeepWoundTime() <= 0 and b:getBurnTime() <= 0 and not b:bandaged()
       and not b:isInfectedWound() and not b:IsInfected() and not b:haveGlass() and b:getHealth() >= 100 then bp, name = b, n; break end
  end
  if not bp then out("info: no hay una mano, antebrazo o pierna sana para probar, salteada"); return end
  local saved = { catch = bd:getCatchACold(), cold = bd:getColdStrength(), fs = E.getStat(p, "FOOD_SICKNESS"), sk = E.getStat(p, "SICKNESS"), stats = deepcopy(IM.stats) }
  local chance0, canInfect0 = S.chance, IM.canInfect
  local ok, err = pcall(function()
    d.immunodep = 100
    local k = S.immunoStrength(d, E.immunoTraits(p))
    local fx = function(e) return S.immunoEffect(d, e, E.immunoTraits(p)) end
    out(string.format("info: parte %s; a ID 100 con tus rasgos: infeccion x%.2f, curacion /%.2f, resfrio x%.2f, malestar x%.2f (fuerza %.2f)",
      name, fx("infectOnset"), fx("healing"), fx("coldCatch"), fx("sickness"), k))
    bp:setScratched(true, true)
    check("rasguno de prueba hecho", bp:getScratchTime() > 0, f1(bp:getScratchTime()))
    local n = IM.vanillaOnsetN(bp)
    out(string.format("info: N del juego para ese rasguno = %s; chance extra por minuto de juego = %.3f %%", tostring(n), 100 * IM.extraOnsetChance(n, IM.realSeconds(nil, 0), fx("infectOnset"))))
    check("el rasguno abierto puede infectarse de mas", IM.canInfect(p, bp))
    -- 1) tirada extra (forzada a salir) solo en la parte de prueba
    IM.snap[p:getPlayerNum()] = nil
    IM.canInfect = function(pl, b) return b == bp and canInfect0(pl, b) end
    S.chance = function() return true end
    IM.tick(p, d)
    S.chance, IM.canInfect = chance0, canInfect0
    check("la tirada extra infecta la herida (setInfectedWound)", bp:isInfectedWound())
    -- 2) avance de la infeccion: el juego sube 0,01 -> el mod suma otro tanto
    bp:setWoundInfectionLevel(1); IM.tick(p, d)
    bp:setWoundInfectionLevel(bp:getWoundInfectionLevel() + 0.01); local l0 = bp:getWoundInfectionLevel()
    IM.canInfect = function() return false end
    IM.tick(p, d)
    check("la infeccion sube x" .. f1(fx("infectGrowth")), near(bp:getWoundInfectionLevel(), l0 + 0.01 * (fx("infectGrowth") - 1)), string.format("%.4f", bp:getWoundInfectionLevel()))
    -- 3) curacion: el juego baja el rasguno 0,1 -> el mod devuelve parte
    local s0 = bp:getScratchTime()
    bp:setScratchTime(s0 - 0.1); IM.tick(p, d)
    check("el rasguno cura " .. f1(fx("healing")) .. " veces mas lento", near(bp:getScratchTime(), s0 - 0.1 + 0.1 * (1 - 1 / fx("healing"))), string.format("%.4f", bp:getScratchTime()))
    -- 4) contagio del resfrio y malestar
    -- (la escala de cada stat sale del juego: FOOD_SICKNESS va de 0 a 100 y SICKNESS de 0 a 1)
    local skMax = CharacterStat.SICKNESS:clamp(1000)
    bd:setCatchACold(10); E.setStat(p, "FOOD_SICKNESS", 10); E.setStat(p, "SICKNESS", 0.10 * skMax); IM.snap[p:getPlayerNum()] = nil; IM.tick(p, d)
    bd:setCatchACold(11); E.setStat(p, "FOOD_SICKNESS", 20); E.setStat(p, "SICKNESS", 0.12 * skMax); IM.tick(p, d)
    check("el contagio del resfrio sube x" .. f1(fx("coldCatch")), near(bd:getCatchACold(), 11 + (fx("coldCatch") - 1)), f1(bd:getCatchACold()))
    check("el malestar por comida sube x" .. f1(fx("sickness")), near(E.getStat(p, "FOOD_SICKNESS"), 20 + 10 * (fx("sickness") - 1), 0.01), f1(E.getStat(p, "FOOD_SICKNESS")))
    check("el malestar por cadaveres sube x" .. f1(fx("sickness")), near(E.getStat(p, "SICKNESS"), (0.12 + 0.02 * (fx("sickness") - 1)) * skMax, 0.001 * skMax),
      string.format("%.3f de %.0f", E.getStat(p, "SICKNESS"), skMax))
    -- 5) con la herida desinfectada ya no tira
    bp:setInfectedWound(false); bp:setAlcoholLevel(5)
    check("desinfectada (alcohol) no tira la infeccion extra", not IM.canInfect(p, bp))
  end)
  S.chance, IM.canInfect = chance0, canInfect0
  pcall(function() bp:RestoreToFullHealth() end)
  pcall(function() bd:setCatchACold(saved.catch); bd:setColdStrength(saved.cold) end)
  E.setStat(p, "FOOD_SICKNESS", saved.fs); E.setStat(p, "SICKNESS", saved.sk)
  IM.snap[p:getPlayerNum()] = nil; IM.stats = saved.stats
  check("la parte de prueba quedo sana", bp:getScratchTime() <= 0 and not bp:isInfectedWound() and bp:getWoundInfectionLevel() <= 0)
  if not ok then error(err, 0) end
end }

-- (135) Debug -> Rechazo -> "Probar la inmunodepresion": solo esas pruebas, en Zomboid/Lua/Sandevistan_immuno.txt
function F.runImmuno(p)
  F.run(p, { only = function(name) return string.sub(name, 1, 16) == "Inmunodepresion:" end, file = "Sandevistan_immuno.txt", title = "prueba de la inmunodepresion", skipWorld = true })
end

---------------------------------------------------------------------------
-- Orquestación
---------------------------------------------------------------------------
local run = nil
F.tests = tests                 -- (53) para correr una prueba suelta desde las pruebas offline

-- opt (90): { only = function(nombre) -> bool (que pruebas correr), file = "txt de salida", title = "...", skipWorld = true }. Sin opt corre todo y escribe Sandevistan_fulltest.txt.
function F.run(p, opt)
  if run then return end
  opt = opt or {}
  lines, passed, failed = {}, 0, 0
  if SandevistanInstallScene then SandevistanInstallScene.suppress = true end      -- las cirugias simuladas no muestran la escena
  S.localItems = true                                                              -- (114) los items de prueba se crean aca (se usan y se borran al terminar)
  out("=== Sandevistan " .. CFG.Version .. " " .. (opt.title or "autotest completo") .. " ===")
  local md = p:getModData()
  local ids = {}
  local items = p:getInventory():getItems()
  for i = 0, items:size() - 1 do ids[items:get(i):getID()] = true end
  run = { p = p, snap = deepcopy(md.Sandevistan), ksnap = deepcopy(md.Kerenzikov), ids = ids,
          endurance = E.getEndurance(p), perkLevel = S.perk() and p:getPerkLevel(S.perk()), file = opt.file or "Sandevistan_fulltest.txt" }
  for _, t in ipairs(tests) do
    if not opt.only or opt.only(t[1]) then
      out("-- " .. t[1])
      local ok, err = pcall(t[2], p)
      if not ok then check(t[1] .. " (error)", false, tostring(err)) end
    end
  end
  R.deactivate(p, "forced")
  if opt.skipWorld then F.finish(); return end
  out("-- Mundo: ex-sujeto, cadaver y extraccion")
  local ok, started = pcall(startWorldTest, p)
  if not ok or not started then F.finish() end
end

function F.finish()
  local p = run.p
  local md = p:getModData()
  R.deactivate(p, "forced")
  md.Sandevistan = run.snap
  md.Kerenzikov = run.ksnap
  R.sessions[p:getPlayerNum()] = nil
  E.setEndurance(p, run.endurance)
  S.resetPerkTo(p, md.Sandevistan, run.perkLevel)     -- sin esto el nivel que dejaron las pruebas se sumaba a la adaptación real
  S.syncPerk(p)
  M.syncRecipes(p, true)                              -- y las recetas que enseño la prueba (P06) se olvidan si el estado repuesto no las trae
  -- borrar ítems creados por las pruebas
  local inv = p:getInventory()
  local items = inv:getItems()
  local removed = 0
  for i = items:size() - 1, 0, -1 do
    local it = items:get(i)
    if not run.ids[it:getID()] then inv:DoRemoveItem(it); removed = removed + 1 end
  end
  out("items de prueba borrados: " .. removed)
  out(string.format("=== resultado: %d OK, %d FALLA ===", passed, failed))
  pcall(function()
    local w = getFileWriter(run.file or "Sandevistan_fulltest.txt", true, false)
    for _, l in ipairs(lines) do w:write(l .. "\n") end
    w:close()
  end)
  if HaloTextHelper then
    pcall(function() HaloTextHelper.addText(p, string.format("Autotest: %d OK / %d FALLA", passed, failed), "", 120, 220, 255) end)
  end
  F.last = { lines = lines, passed = passed, failed = failed }
  run, world = nil, nil
  S.localItems = nil
  if SandevistanInstallScene then SandevistanInstallScene.suppress = false end
  local after = F.afterFinish
  F.afterFinish = nil
  if after then pcall(after, p) end
end

-- (90) Debug -> Firmware -> "Probar todos los chips": solo las pruebas de firmware (cada chip medido contra el motor, el comportamiento de los de Sistema, los niveles 6 y 7, Taller
-- y decompilar), sin el mundo, y su propio txt: Zomboid/Lua/Sandevistan_chips.txt. Mismo estado de personaje de prueba que la PRUEBA COMPLETA (se restaura al terminar).
function F.runChips(p)
  F.run(p, { only = function(name) return string.sub(name, 1, 9) == "Firmware:" end, file = "Sandevistan_chips.txt", title = "prueba de los chips de firmware", skipWorld = true })
end

Events.OnTick.Add(S.safe("FullTest.OnTick", function()
  if not run or not world then return end
  local ok, done = pcall(pollWorldTest, run.p)
  if not ok then check("prueba de mundo (error)", false, tostring(done)); done = true end
  if done then F.finish() end
end))

return F
