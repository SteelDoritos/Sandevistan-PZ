-- Sandevistan / Firmware (shared): chips de software con dos slots tipados, Sistema y Habilidad (v0.1.30 (82)).
-- Diseno: 14-catalogo-firmware.md. Plan: 15-plan-firmware.md. Los datos de cada programa estan en Config.Firmware.Programs; aca vive el PERFIL:
-- una tabla de multiplicadores y desplazamientos que junta lo que piden los dos chips instalados y que consultan las formulas del mod (Heat,
-- enfriamiento, CN, rechazo, dilatacion...). Sin chips (o con el firmware apagado, sin implante o con un chip que el hardware no admite) el perfil es
-- NEUTRO y el mod se comporta como siempre. Este archivo no toca el motor ni la interfaz: lo de los chips como objetos (flasheo, menus) esta en
-- client/FirmwareClient.lua. No requiere Core (Core lo requiere a el): usa `Sandevistan` solo al llamarlo.
require "Sandevistan/Config"

local CFG = SandevistanConfig

SandevistanFirmware = {}
local FW = SandevistanFirmware

---------------------------------------------------------------------------
-- Campos del perfil y como se componen entre los dos chips:
--   mul = se multiplican (neutro 1)     add = se suman (neutro 0)     any = o logico (neutro false)
--   last = el ultimo que lo define (neutro nil)
---------------------------------------------------------------------------
FW.KIND = {
  heat = "mul",          -- Heat por segundo de uso                    (Core.heatPerSecond)
  cool = "mul",          -- enfriamiento con el implante apagado       (FirmwareClient.coolMult; (108) Camara criogenica)
  thermalMass = "mul",   -- (110) masa termica: todo el Heat (uso, enfriado, kills) se mueve /thermalMass, como si la barra fuera mas grande (FW.heatMult, FW.coolMult; Reactor)
  maxHeat = "mul",       -- tope de Heat                               (Core.heatCap; (108) Camara criogenica)
  cn = "mul",            -- CN por segundo de uso                      (Runtime.tickActive, InfoView, simulador)
  rej = "mul",           -- rechazo por hora                           (Periodic.rejectionTick)
  rejEvent = "mul",      -- rechazo de un corte o un colapso           (Core.eventRejection)
  immuno = "mul",        -- (135) inmunodepresion que suma cada dosis   (Core.immunoDoseGain; Compatibilidad)
  xpPassive = "mul",     -- XP de adaptacion por hora con el implante puesto (Periodic.hourlyTick)
  xpKill = "mul",        -- XP por kill                                (Combat.onZombieDead)
  xpTime = "mul",        -- XP de adaptacion por segundo con el implante encendido (Runtime.tickActive)
  ab = "mul",            -- bono de velocidad de ataque                (Runtime.effectiveTier)
  critMult = "mul",      -- el extra del golpe critico (1.5 = +50 %) se multiplica por esto (Combat)
  refund = "mul",        -- estamina devuelta por golpe                (Combat.onAttackFinished)
  window = "mul",        -- ventana de Overdrive                       (Core.overdriveWindow)
  momentumRamp = "mul",  -- (110) velocidad a la que sube el Impulso del uso continuo (Runtime.tickActive; Reactor)
  momentumDecay = "mul", -- (110) velocidad a la que se pierde el Impulso con el implante apagado (Runtime.onTick; Reactor)
  stamina = "mul",       -- drenaje de estamina con el implante encendido (Runtime.tickActive; (108) Taller)
  symptoms = "mul",      -- sintomas de CN                             (Core.symptomMultiplier)
  hallu = "mul",         -- (180) frecuencia de las alucinaciones que filtra el Filtro (FakeZombies, Echoes, texto, SelfEcho, Phantoms, Hallucinations)
  noSense = "any",       -- (180) Filtro: sin sentido de peligro ni aviso de Heat por sonido
  killHeat = "add",      -- puntos de Heat que baja cada kill con el implante encendido (Combat.onZombieDead, FirmwareClient.killHeat)
  zs = "add",            -- factor de velocidad de los zombis (mas alto = menos frenados) (Core.dilationTier)
  pb = "add",            -- bono de velocidad del jugador              (Core.dilationTier)
  dmg = "add",           -- daño melee extra sobre el multiplicador del Sandi (0.30 = x1,3) (Combat.damageMult)
  knock = "add",         -- chance de derribo extra                    (Combat)
  wear = "add",          -- tiradas extra de desgaste del arma por golpe (Combat.extraWear)
  noOverdrive = "any", noBerserk = "any",
  overclock = "last",    -- (109) { From, Move, Attack, ZombieSpeed }: bonos segun el Heat (FW.overclockFactor, Runtime.effectiveTier)
  centinela = "last",    -- { still, walk, run, xpStill }: Heat de uso segun el movimiento y XP por tiempo quieto (FirmwareClient.live)
  mode = "last",         -- "work" = modo trabajo de Taller (FW.tier, Runtime, FirmwareClient.workTick)
}

-- Orden en que se listan los campos de un programa (detalle del chip y pestana Implante)
FW.FIELD_ORDER = { "heat", "thermalMass", "maxHeat", "cool", "cn", "rej", "rejEvent", "immuno", "xpPassive", "xpKill", "xpTime", "killHeat", "zs", "pb", "ab", "dmg", "knock", "critMult", "refund", "wear",
                   "window", "momentumRamp", "momentumDecay", "stamina", "symptoms", "hallu", "noSense", "centinela", "overclock", "mode", "noOverdrive", "noBerserk" }

local function neutralProfile()
  local t = {}
  for k, kind in pairs(FW.KIND) do
    if kind == "mul" then t[k] = 1 elseif kind == "add" then t[k] = 0 elseif kind == "any" then t[k] = false end
  end
  return t
end

-- Perfil sin chips. Es una sola tabla compartida: quien consulta el perfil no debe modificarla.
FW.NEUTRAL = neutralProfile()

---------------------------------------------------------------------------
-- Programas e items
---------------------------------------------------------------------------
FW.BLANK = "Sandevistan.FwBlank"

function FW.program(id) return CFG.Firmware.Programs[id] end
function FW.itemType(id) return "Sandevistan.Fw" .. tostring(id) end

local byItem = nil
local function items()
  if not byItem then
    byItem = {}
    for _, id in ipairs(CFG.Firmware.Order) do byItem[FW.itemType(id)] = id end
  end
  return byItem
end

-- Id del programa de un tipo de item ("Sandevistan.FwSostenido" -> "Sostenido"); nil si no es un chip programado.
function FW.idOfItem(fullType) return items()[fullType] end
function FW.isBlank(fullType) return fullType == FW.BLANK end
function FW.isChip(fullType) return fullType == FW.BLANK or items()[fullType] ~= nil end

-- Para pruebas que cambian la configuracion: vuelve a armar los indices y descarta los perfiles guardados.
FW.gen = 0
function FW.invalidate()
  byItem = nil
  FW.gen = FW.gen + 1
end

---------------------------------------------------------------------------
-- Slots (d.firmware = { sistema = id, habilidad = id })
---------------------------------------------------------------------------
-- (108) Un programa que ya no existe (Rafaga, Austero, Tirador, Supresor, Sin limitador o Vigilia de una partida vieja) cuenta como slot vacio: no hace efecto y se puede instalar otro.
function FW.slotProgram(d, slot)
  local t = d and d.firmware
  local id = type(t) == "table" and t[slot] or nil
  if id and not CFG.Firmware.Programs[id] then return nil end
  return id
end

-- Pone (o saca, con id = nil) el programa de un slot. Devuelve el que estaba.
function FW.setSlot(d, slot, id)
  if type(d.firmware) ~= "table" then d.firmware = {} end
  local prev = d.firmware[slot]
  d.firmware[slot] = id
  return prev
end

function FW.enabled() return CFG.Firmware.Enabled ~= false end

-- El hardware admite el programa (los hay solo de laboratorio o solo militares; el Mk. II cuenta como militar y el P06 como laboratorio).
function FW.supported(d, id)
  local p = CFG.Firmware.Programs[id]
  if not p then return false end
  return p.only == nil or p.only == d.variant
end

-- Programa que de verdad esta funcionando: el firmware esta prendido, hay implante que funciona, el chip esta terminado y el hardware lo admite.
function FW.active(d, id)
  local p = CFG.Firmware.Programs[id]
  return p ~= nil and p.ready == true and FW.enabled() and (d.variant == "lab" or d.variant == "military") and FW.supported(d, id)
end

---------------------------------------------------------------------------
-- Perfil
---------------------------------------------------------------------------
local function merge(into, profile)
  for k, v in pairs(profile) do
    local kind = FW.KIND[k]
    if kind == "mul" then into[k] = into[k] * v
    elseif kind == "add" then into[k] = into[k] + v
    elseif kind == "any" then into[k] = into[k] or v
    elseif kind == "last" then into[k] = v end
  end
end

local cache = setmetatable({}, { __mode = "k" })       -- [d] = { sis, hab, var, gen, prof }: el perfil se rearma solo si cambian los chips, la variante o la configuracion

-- Perfil de firmware del jugador (tabla de solo lectura). Siempre devuelve una tabla.
function FW.profile(d)
  if not d or not FW.enabled() then return FW.NEUTRAL end
  if d.disconnected then return FW.NEUTRAL end            -- (165) T12: el implante inerte no ejecuta los chips
  local variant = d.variant
  if variant ~= "lab" and variant ~= "military" then return FW.NEUTRAL end
  local t = d.firmware
  if type(t) ~= "table" then return FW.NEUTRAL end
  local sis, hab = t.sistema, t.habilidad
  if not sis and not hab then return FW.NEUTRAL end
  local c = cache[d]
  if c and c.sis == sis and c.hab == hab and c.var == variant and c.gen == FW.gen then return c.prof end
  local prof, any = neutralProfile(), false
  for _, slot in ipairs(CFG.Firmware.Slots) do
    local id = t[slot]
    if id and FW.active(d, id) then merge(prof, CFG.Firmware.Programs[id].profile); any = true end
  end
  if not any then prof = FW.NEUTRAL end                 -- chips que no cuentan (sin terminar, de otro hardware...): el mismo perfil neutro de siempre
  cache[d] = { sis = sis, hab = hab, var = variant, gen = FW.gen, prof = prof }
  return prof
end

-- Horas de juego de recalibrado que quedan (0 = ninguno). Tras cambiar un chip el Heat sube un poco mas durante una hora.
function FW.recalLeft(d)
  local u = d and d.fwRecalUntil
  if not u or not FW.enabled() then return 0 end
  local S = rawget(_G, "Sandevistan")
  local left = u - (S and S.worldHours() or 0)
  return left > 0 and left or 0
end

-- Multiplicador del Heat de uso: el de los chips por el del recalibrado (si hay).
function FW.heatMult(d)
  local p = FW.profile(d)
  local m = p.heat / p.thermalMass                                                  -- (110) Reactor: la barra se llena como si fuera de 0 a 150
  if d and d.fwRecalUntil and FW.recalLeft(d) > 0 then m = m * CFG.Firmware.Recalibrate.HeatMult end
  return m
end

-- (110) Multiplicador del enfriamiento con el implante apagado: el del perfil (Camara criogenica x1,75; Reactor x0,5) y la masa termica (Reactor /1,5).
function FW.coolMult(d)
  local p = FW.profile(d)
  return p.cool / p.thermalMass
end

-- Menor factor de zombis que acepta el servidor (tramo mas lento por la mitad del Overdrive): ningun chip lo pasa.
local function minZs()
  local lo = 1
  for _, t in ipairs(CFG.DilationTiers) do if t.zombieSpeed < lo then lo = t.zombieSpeed end end
  return lo * (CFG.Overdrive.Bonus.ZombieSpeedMult or 1)
end
FW.minZs = minZs

-- (109) Overclock: 0..1 segun el Heat (0 por debajo de From del tope, 1 en el tope). 0 sin el chip.
function FW.overclockFactor(d)
  local oc = FW.profile(d).overclock
  if not oc then return 0 end
  local S = rawget(_G, "Sandevistan")
  local cap = S and S.heatCap(d) or 100
  local frac = (d.heat or 0) / math.max(1, cap)
  return math.max(0, math.min(1, (frac - oc.From) / math.max(0.01, 1 - oc.From)))
end

-- Tramo de dilatacion con el perfil aplicado. Sin cambios en el factor de zombis ni en la velocidad devuelve el mismo tramo de Config.
function FW.tier(d, tier)
  local p = FW.profile(d)
  if p.mode == "work" then                       -- (86) Taller: un tramo fijo (mundo x0,8, sin bonos); los desplazamientos de otros chips no se aplican
    local World = CFG.Firmware.Work.World
    return { minLevel = tier.minLevel, world = World, comp = 1 / World, zombieSpeed = World, playerBoost = 0, attackBoost = 0 }
  end
  if p == FW.NEUTRAL or (p.zs == 0 and p.pb == 0) then return tier end
  local t = {}
  for k, v in pairs(tier) do t[k] = v end
  t.zombieSpeed = math.max(minZs(), math.min(1, tier.zombieSpeed + p.zs))
  t.playerBoost = math.max(0, tier.playerBoost + p.pb)
  return t
end

---------------------------------------------------------------------------
-- Programas conocidos y escritura (85)
---------------------------------------------------------------------------
-- Un programa se aprende al llegar al nivel de adaptacion de su ficha (Programs.<Id>.level) y queda aprendido para siempre; con la opcion de sandbox
-- FirmwareAllKnown se conocen todos los terminados. Los programas sin terminar (ready = false) no se pueden aprender ni escribir.
function FW.known(d, id)
  local p = CFG.Firmware.Programs[id]
  if not p or not p.ready or not FW.enabled() then return false end
  if CFG.Firmware.AllKnown then return true end
  return type(d.fwKnown) == "table" and d.fwKnown[id] == true
end

-- Los programas que se conocen, en el orden de Config.Firmware.Order.
function FW.knownList(d)
  local out = {}
  for _, id in ipairs(CFG.Firmware.Order) do if FW.known(d, id) then out[#out + 1] = id end end
  return out
end

-- Suma a d.fwKnown los programas terminados cuyo nivel de adaptacion ya alcanzaste (hace falta un implante que funcione). Devuelve los nuevos.
function FW.syncKnown(d)
  local new = {}
  if not FW.enabled() or CFG.Firmware.AllKnown then return new end
  local S = rawget(_G, "Sandevistan")
  if not S or not S.hasWorkingImplant(d) then return new end
  if type(d.fwKnown) ~= "table" then d.fwKnown = {} end
  local level = S.level(d)
  for _, id in ipairs(CFG.Firmware.Order) do
    local p = CFG.Firmware.Programs[id]
    if p.ready and not d.fwKnown[id] and level >= p.level then d.fwKnown[id] = true; new[#new + 1] = id end
  end
  return new
end

-- Segundos que lleva escribir un programa: Write.Seconds[1] sin costumbre con el implante, bajando linealmente hasta Write.Seconds[2] con la adaptacion estable.
function FW.writeSeconds(d)
  local W = CFG.Firmware.Write
  local S = rawget(_G, "Sandevistan")
  local f = S and d and S.adaptFraction(d) or 0
  return W.Seconds[1] + (W.Seconds[2] - W.Seconds[1]) * f
end

-- (87) Aprende un programa por una via que no es el nivel (decompilar su chip, el expediente militar). Devuelve true si era nuevo.
function FW.learn(d, id)
  local p = CFG.Firmware.Programs[id]
  if not p or not p.ready then return false end
  if type(d.fwKnown) ~= "table" then d.fwKnown = {} end
  if d.fwKnown[id] then return false end
  d.fwKnown[id] = true
  return true
end

-- Lo que impide escribir ese programa, sin mirar el inventario (lista de { claveDeTexto }; vacia = se puede).
function FW.writeProblems(d, id)
  local out = {}
  local p = CFG.Firmware.Programs[id]
  if not FW.enabled() then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Disabled" }; return out end
  if not p then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Blank" }; return out end
  if not p.ready then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_NotReady" } end
  if not FW.known(d, id) then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Unknown" } end
  return out
end

-- (87) Decompilar: un chip programado que encontraste, en una computadora con corriente o con el terminal. Aprendes su programa (aunque tu nivel no llegue) y el chip queda en
-- blanco. Lleva Write.DecompileFraction de lo que lleva escribir.
function FW.decompileSeconds(d) return FW.writeSeconds(d) * CFG.Firmware.Write.DecompileFraction end

-- Lo que impide decompilar el chip de ese programa, sin mirar el inventario (lista de { claveDeTexto }; vacia = se puede). Un programa que ya sabes no se decompila: el chip queda como esta.
function FW.decompileProblems(d, id)
  local out = {}
  local p = CFG.Firmware.Programs[id]
  if not FW.enabled() then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Disabled" }; return out end
  if not p then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Blank" }; return out end
  if not p.ready then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_NotReady" } end
  if FW.known(d, id) then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_AlreadyKnown" } end
  return out
end

-- (86) Lo que impide encender el modo trabajo ahora (lista de { claveDeTexto, argumento }; vacia = se puede): la CN alta y el rechazo alto.
function FW.workProblems(d)
  local out = {}
  if FW.profile(d).mode ~= "work" then return out end
  local Wk = CFG.Firmware.Work
  if (d.neuralLoad or 0) >= Wk.MaxCN then out[#out + 1] = { "IGUI_Sandevistan_Fw_WorkCN" } end
  if (d.rejection or 0) >= Wk.MaxRejection then out[#out + 1] = { "IGUI_Sandevistan_Fw_WorkRejection" } end
  return out
end

---------------------------------------------------------------------------
-- Cambiar un chip: que hay que cumplir (lista de { claveDeTexto, claveDelArgumento }; vacia = se puede). Lo de la sesion (implante encendido) lo agrega el
-- cliente. FW.problemTexts los pasa a texto.
---------------------------------------------------------------------------
function FW.flashProblems(d, id)
  local out = {}
  local p = CFG.Firmware.Programs[id]
  if not FW.enabled() then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Disabled" }; return out end
  if not (d.variant == "lab" or d.variant == "military") then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Implant" }; return out end
  if not p then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Blank" }; return out end
  if not p.ready then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_NotReady" } end
  if not FW.supported(d, id) then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Hardware", "IGUI_Sandevistan_Fw_Only_" .. tostring(p.only) } end
  if FW.slotProgram(d, p.slot) == id then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Same" } end
  if (d.rejection or 0) >= CFG.Firmware.BlockAt then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Rejection" } end
  return out
end

-- Sacar el chip de un slot.
function FW.removeProblems(d, slot)
  local out = {}
  if not FW.enabled() then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Disabled" }; return out end
  if not (d.variant == "lab" or d.variant == "military") then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Implant" }; return out end
  if not FW.slotProgram(d, slot) then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Empty" } end
  if (d.rejection or 0) >= CFG.Firmware.BlockAt then out[#out + 1] = { "IGUI_Sandevistan_Fw_Req_Rejection" } end
  return out
end

-- Lista de motivos (de flashProblems / removeProblems) como textos del idioma activo.
function FW.problemTexts(list)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = e[2] and getText(e[1], getText(e[2])) or getText(e[1]) end
  return out
end

---------------------------------------------------------------------------
-- Texto de los cambios exactos de un programa (sale de su perfil: siempre coincide con Config)
---------------------------------------------------------------------------
local function num(v) return string.format("%.2f", v) end

local function fieldValue(k, v)
  local kind = FW.KIND[k]
  if k == "dmg" or k == "knock" then return string.format("%+d %%", math.floor(v * 100 + 0.5)) end
  if k == "wear" then return "x" .. num(1 + v) end
  if k == "killHeat" then return string.format("%d", math.floor(v + 0.5)) end
  if kind == "mul" then return "x" .. num(v) end
  if kind == "add" then return string.format("%+.2f", v) end
  return ""
end

-- Una linea por campo del perfil: "Heat de uso: x0.60". Los indicadores (sin Overdrive...) van solo con su rotulo.
function FW.fieldLines(id)
  local p = CFG.Firmware.Programs[id]
  local out = {}
  if not p then return out end
  for _, k in ipairs(FW.FIELD_ORDER) do
    local v = p.profile[k]
    if v ~= nil then
      local kind = FW.KIND[k]
      local function label() return getText("IGUI_Sandevistan_FwField_" .. k) end       -- solo donde hace falta: los textos con %1 piden argumentos y avisan en la consola si se piden sin ellos
      if k == "overclock" then out[#out + 1] = getText("IGUI_Sandevistan_FwField_overclock", string.format("%d", math.floor(v.From * 100 + 0.5)), num(v.Move), num(v.Attack), num(v.ZombieSpeed))
      elseif k == "centinela" then out[#out + 1] = getText("IGUI_Sandevistan_FwField_centinela", num(v.still), num(v.walk), num(v.run), num(v.xpStill))
      elseif k == "mode" then out[#out + 1] = getText("IGUI_Sandevistan_FwField_mode", num(CFG.Firmware.Work.World), num(CFG.Firmware.Work.CostMult), num(CFG.Firmware.Work.ActionMult))
      elseif kind == "any" then if v then out[#out + 1] = label() end
      else out[#out + 1] = label() .. ": " .. fieldValue(k, v) end
    end
  end
  return out
end

return FW
