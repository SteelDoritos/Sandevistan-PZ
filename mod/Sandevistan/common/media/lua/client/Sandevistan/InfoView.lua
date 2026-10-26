-- Sandevistan / InfoView: pestaña "Implante" en la ventana de información del personaje (junto a Salud, Habilidades, etc.).
-- Los moodles (Moodles.lua) son el indicador de estado; esta pestaña da el detalle: el mismo panel del HUD, el
-- interruptor del panel flotante y una lista con los números reales (Heat por segundo, tiempos hasta el corte o
-- el rechazo, cobertura, carga neuronal y su descenso, Kerenzikov) y el texto completo de cada moodle activo.
--
-- La pestaña solo existe mientras hay algo que mostrar (implante, carga neuronal, toxicidad, cobertura...).
-- Todo va protegido con pcall: si la interfaz vanilla cambia, la pestaña no aparece y el resto del mod sigue igual.
-- buildLines() es una función pura (sin UI) para poder probarla fuera del juego.
pcall(require, "ISUI/ISPanel")
pcall(require, "ISUI/ISButton")
pcall(require, "ISUI/ISTabPanel")
pcall(require, "XpSystem/ISUI/ISCharacterInfoWindow")
require "Sandevistan/Core"
require "Sandevistan/Kerenzikov"
require "Sandevistan/Runtime"
require "Sandevistan/Moodles"
require "Sandevistan/HUDPanel"
require "Sandevistan/HUD"

local CFG = SandevistanConfig
local S = Sandevistan
local R = SandevistanRuntime
local FW = SandevistanFirmware

SandevistanInfoView = {}
local I = SandevistanInfoView

---------------------------------------------------------------------------
-- Contenido (puro): lista de líneas { kind, text, r, g, b }. kind: h = título de sección, t = texto,
-- w = aviso, g = positivo, m = título de moodle.
---------------------------------------------------------------------------
local function f0(v) return string.format("%d", math.floor(v + 0.5)) end
local function f1(v) return string.format("%.1f", v) end
local function f2(v) return string.format("%.2f", v) end
local function pct(v) return string.format("%d", math.floor(v * 100 + 0.5)) end

-- Duración in-game: minutos, horas o días.
local function span(hours)
  if hours == nil or hours ~= hours then return "-" end
  if hours >= 9999 then return ">400 d" end
  if hours < 1 then return string.format("%d min", math.max(1, math.floor(hours * 60 + 0.5))) end
  if hours < 48 then return string.format("%.1f h", hours) end
  return string.format("%.1f d", hours / 24)
end
I.span = span

-- (178) C05: texto de una entrada de la caja negra (localizado). Se usa en la pestaña Implante.
function I.incidentLabel(e)
  if not e then return getText("IGUI_Sandevistan_Inc_None") end
  local secs = f0(e.secs or 0)
  if e.kind == "overload" then
    return getText(e.fury and "IGUI_Sandevistan_Inc_OverloadFury" or "IGUI_Sandevistan_Inc_OverloadKO", secs)
  elseif e.kind == "episode" then
    return getText("IGUI_Sandevistan_Inc_Episode", getText("IGUI_Sandevistan_Info_CrisisType_" .. tostring(e.why)), secs)
  elseif e.kind == "crisisAborted" then
    return getText("IGUI_Sandevistan_Inc_CrisisAborted", getText("IGUI_Sandevistan_Inc_Why_" .. tostring(e.why)))
  elseif e.kind == "cascadeAvoided" then
    return getText("IGUI_Sandevistan_Inc_CascadeAvoided")
  elseif e.kind == "blackout" then
    return getText("IGUI_Sandevistan_Inc_Blackout", secs)
  elseif e.kind == "nightTerror" then
    return getText("IGUI_Sandevistan_Inc_NightTerror")
  end
  return getText("IGUI_Sandevistan_Inc_Other")
end

local function variantName(d)
  if d.variant == "destroyed" then return getText("IGUI_Sandevistan_HUD_Destroyed") end
  if d.disconnected then return getText("IGUI_Sandevistan_HUD_Disconnected") end       -- (165) T12
  return S.plateTitle(d)
end

-- Horas de descanso hasta que la Carga Neuronal baje de "target" con la cobertura actual (nil si no baja nunca).
function I.restHoursToBelow(d, now, target)
  local cn = d.neuralLoad or 0
  if cn < target then return 0 end
  local floor = d.cyberpsychosisActive and CFG.NeuralLoad.RemissionFloor or 0
  if floor >= target then return nil end
  local mult = 1
  if S.immunoActiveTier(d, now) then mult = mult * CFG.NeuralLoad.ImmunoDecayMultiplier * S.immunoShockDecay(d, now) end      -- (135)
  if S.antidepActive(d, now) then mult = mult * CFG.Antidepressant.CNDecayMultiplier end
  local tmp = { neuralLoad = cn, cyberpsychosisActive = d.cyberpsychosisActive, variant = d.variant, firmware = d.firmware, traits = d.traits,
                neuralScar = d.neuralScar }      -- (83) con el firmware y los rasgos (Supresor, inestable); (178) con la cicatriz
  local hours, step = 0, 0.5
  while tmp.neuralLoad >= target and hours < 10000 do
    tmp.neuralLoad = math.max(floor, tmp.neuralLoad - S.cnDecayPerHour(tmp) * mult * step)
    hours = hours + step
  end
  if tmp.neuralLoad >= target then return nil end
  return hours
end

function I.buildLines(p, d, s, now)
  local L = {}
  local function add(kind, text, r, g, b) L[#L + 1] = { kind = kind, text = text, r = r, g = g, b = b } end
  local function H(key) add("h", getText("IGUI_Sandevistan_Info_H_" .. key)) end
  local function T(key, ...) add("t", getText("IGUI_Sandevistan_Info_" .. key, ...)) end
  local function W(key, ...) add("w", getText("IGUI_Sandevistan_Info_" .. key, ...)) end
  local function G(key, ...) add("g", getText("IGUI_Sandevistan_Info_" .. key, ...)) end

  local working = S.hasWorkingImplant(d)
  local level = S.level(d)
  local v = S.variantCfg(d)
  local NL, OD = CFG.NeuralLoad, CFG.Overdrive

  -- ---- implante ----
  H("Implant")
  if d.variant == "destroyed" then
    W("Destroyed")
  elseif not working and not d.disconnected then
    T("NoImplant")
  else
    T("Variant", variantName(d))
    local maxLevel = S.maxLevel(d)
    T("Adapt", level, maxLevel, v.stableLevel)
    if level < maxLevel then
      local _, into, need = S.levelProgress(d)
      T("AdaptXP", f0(into), f0(need), level + 1)
    elseif S.masteryEnabled(d) then                                         -- (123) maestria con Beyond Ten
      local rank, into, need = S.masteryProgress(d)
      local M = CFG.Mastery
      G("Mastery", level + rank, level + S.masteryMax())
      if rank < S.masteryMax() then T("AdaptXP", f0(into), f0(need), level + rank + 1) end
      if rank > 0 then
        T("MasteryBonus", pct(M.HeatPerRank * rank), pct(M.CoolPerRank * rank), f1(M.WindowPerRank * rank), pct(M.StaminaPerRank * rank))
      end
    end
    local xs = d.xpSrc
    if xs then T("XPSrc", f0(xs.time or 0), f0(xs.kill or 0), f0(xs.pasiva or 0)) end
    T("Degrade", f2(d.degradation or 1))
    local tier = S.dilationTier(d, level)
    local fw = FW.profile(d)                                                -- (82) el tramo ya trae el factor de zombis y la velocidad del firmware; falta el ataque y el daño
    T("Dilation", f2(tier.zombieSpeed), pct(tier.playerBoost), pct(tier.attackBoost * fw.ab),
      f1(fw.mode == "work" and 1 or CFG.Combat.Damage.Mult * (1 + fw.dmg)))                 -- (134) multiplicador del daño melee (con el arma de referencia, el bate)
    local OV = CFG.Combat.SpeedOverflowDamage                               -- (134e)
    if OV and OV.Enabled and CFG.Combat.MaxCombatSpeed and fw.mode ~= "work" then T("SpeedOverflow", f1(CFG.Combat.MaxCombatSpeed), f1(OV.Max or 2)) end
    T("Athletic", pct(math.min(1, S.adaptFraction(d) * ((CFG.Athletic and CFG.Athletic.GuardScale) or 1))))
    T("Momentum", pct(CFG.Momentum.PlayerBoost), pct(CFG.Momentum.AttackBoost), CFG.Momentum.RampSeconds)

    -- ---- firmware (82): los dos slots, lo que cambia cada chip y el recalibrado ----
    if FW.enabled() then
      H("Firmware")
      for _, slot in ipairs(CFG.Firmware.Slots) do
        local id = FW.slotProgram(d, slot)
        local label = getText("IGUI_Sandevistan_Fw_Slot_" .. slot)
        if id then
          local p = FW.program(id)
          local name = getText("IGUI_Sandevistan_Fw_Name_" .. id)
          if not FW.supported(d, id) then W("FwUnsupported", label, name)
          elseif not p.ready then W("FwNotReady", label, name)
          else G("FwSlot", label, name, p.code) end
          local eff = FW.fieldLines(id)
          if #eff > 0 then T("FwEffect", table.concat(eff, "; ")) end
        else
          T("FwEmpty", label)
        end
      end
      if FW.slotProgram(d, "sistema") or FW.slotProgram(d, "habilidad") then T("FwRemoveHint") end          -- (88) como sacar un chip
      local fwp = FW.profile(d)
      local FC = rawget(_G, "SandevistanFirmwareClient")
      if FC and fwp.centinela then                                            -- (83) lo que depende de como te movias hace un instante
        local cls = FC.motion(p)
        T("FwLiveHeat", FC.motionLabel(cls), f2(cls == "still" and fwp.centinela.still or (cls == "run" and fwp.centinela.run or fwp.centinela.walk)))
      end
      if fwp.overclock then T("FwOverclock", pct(FW.overclockFactor(d)), f0(fwp.overclock.From * 100)) end          -- (109) cuanto rinde ahora la linea roja
      do                                                                       -- (85) cuantos programas conoces y cuando se te ocurre el proximo
        local total, nextLevel, nextId = 0, nil, nil
        for _, id in ipairs(CFG.Firmware.Order) do
          local pr = CFG.Firmware.Programs[id]
          if pr.ready then
            total = total + 1
            if not FW.known(d, id) and (not nextLevel or pr.level < nextLevel) then nextLevel, nextId = pr.level, id end
          end
        end
        T("FwKnown", #FW.knownList(d), total, f0(FW.writeSeconds(d)))
        if nextId then T("FwNext", nextLevel, getText("IGUI_Sandevistan_Fw_Name_" .. nextId)) end
      end
      if FW.profile(d).mode == "work" then                                    -- (86) Taller: el modo trabajo (numeros con la formula real y estado de ahora)
        local Wk = CFG.Firmware.Work
        local a = S.adaptFraction(d)
        local cn1 = NL.PerSecondActive * v.neuralLoadMultiplier * S.adaptUseMultiplier(d) * FW.profile(d).cn * Wk.CostMult * 60
        T("FwWork", f1(S.heatPerSecond(d, level) * Wk.CostMult), f1(S.coolPerSecond(d, level) * Wk.ActiveCoolFraction / FW.profile(d).thermalMass), f2(cn1 * (1 - a)), f2(cn1 * (1 - Wk.IdleAdaptReduction * a)))
        if s and s.active and s.work then
          T("FwWorkNow", f0(100 * math.min(1, (s.workFlow or 0) / Wk.FlowSeconds)))
        end
      end
      local recal = FW.recalLeft(d)
      if recal > 0 then W("FwRecal", span(recal), pct(CFG.Firmware.Recalibrate.HeatMult - 1)) end
    end

    -- ---- Heat y Overdrive ----
    H("Heat")
    local amb = S.ambientCoolMult(p)                                                                         -- (138i) frio, mojado o viento
    local ambHeat = S.ambientHeatMult(p)                                                                     -- (138j) cuanto alarga la rafaga
    local heatRate = S.heatPerSecond(d, level) * ambHeat
    local coolRate = S.coolPerSecond(d, level) * S.totalCoolMult(p, FW.coolMult(d))                          -- (108) criogenica x1,75; (138i) ambiente y tope x2,0
    local cap = S.heatCap(d)
    T("HeatNow", f0(d.heat or 0), f1(heatRate), f1(coolRate), f0(cap))
    if amb > 1.001 then T("AmbientCool", f2(amb), f2(1 / ambHeat)) end                                       -- (138i/138j)
    if OD.HeatCap.Enabled and (d.heatCap or 100) < 100 then W("HeatScar", f0(cap), f1(OD.HeatCap.RecoverPerHour)) end          -- solo la cicatriz termica (no el tope del firmware)
    if OD.HeatCap.Enabled then
      local freeIn = S.freeOverdriveIn(d, now)
      if freeIn <= 0 then T("ScarFree") else T("ScarFreeIn", span(freeIn), OD.HeatCap.PerCollapse) end
    end
    if d.lockUntilCool and (d.heat or 0) > 0 then W("Locked") end
    if s.active and not s.overdrive and heatRate > 0 then
      T("CutoffIn", f1(math.max(0, (cap - (d.heat or 0)) / heatRate)))
    end
    T("Burst", f1(cap / heatRate), f1(cap / coolRate))
    if FW.profile(d).noOverdrive then
      W("FwNoOverdrive")                                                       -- (83) Overclock y Taller
    else
      T("Overdrive1", f1(R.overdriveWindow(p)), pct(OD.Bonus.PlayerBoost), pct(OD.Bonus.AttackBoost))
      T("Overdrive2", OD.NeuralLoadMin, OD.NeuralLoadMax, OD.RejectionMin, OD.RejectionMax)
    end
    T("Stamina", f1(S.staminaDrainPerSecond(level, false, d) * FW.profile(d).stamina * 100), f0(CFG.Stamina.MinToActivate * 100),
      f0(CFG.Stamina.ReductionPerLevel * 100))                                                 -- (120) y cuanto baja por nivel
    if s.active and R.debtOn and R.debtOn() then
      local debt, mark = R.debt(p)
      T("StaminaDebt", f0(100 * S.staminaDebtRatio(debt, mark)))                               -- (139) lo que se cobra al apagar
    end

    -- ---- rechazo ----
    H("Rejection")
    local rej = d.rejection or 0
    if rej >= CFG.Rejection.BlockActivationAt then W("Rejection", f0(rej)) else T("Rejection", f0(rej)) end
    local adapt = S.adaptationTerm(d, level)
    local chronic = S.chronicRejection(d)                                   -- (84) CN alta y costo fijo del firmware
    local mult = S.immunoRejectionMultiplier(d, now)
    local gain = (adapt + chronic) * mult * CFG.Rejection.RateMultiplier * FW.profile(d).rej          -- (82)
    if gain > 0 then
      T("RejRate", f2(gain), f2(adapt), f2(chronic), f2(mult))
      if rej < CFG.Rejection.BlockActivationAt then
        T("RejTo75", span((CFG.Rejection.BlockActivationAt - rej) / gain), span((100 - rej) / gain))
      elseif rej < 100 then
        T("RejTo100", span((100 - rej) / gain))
      end
    else
      T("RejFalling", f2(CFG.Rejection.NaturalDecay))
    end
    T("RejNote")
  end

  -- ---- inmunosupresores y toxicidad ----
  H("Coverage")
  local im, any = d.immuno or {}, false
  for _, tier in ipairs({ "clinical", "crafted", "herbal" }) do
    local left = (im[tier .. "Until"] or -1) - now
    if left > 0 then
      any = true
      G("CovTier", getText("IGUI_Sandevistan_Info_Tier_" .. tier), span(left))
    end
  end
  if any then
    T(S.immunoActiveTier(d, now) == "herbal" and "CovEffectQuarter" or "CovEffectStop")
  else
    T("CovNone")
  end
  -- (135) dosis de choque (tolerancia de la proxima) e inmunodepresion
  local doses = S.immunoDoseCount(d, now)
  if doses > 0 then T("ImmunoDoses", doses, pct(S.immunoDurationFactor(d, now))) end
  if S.immunoShockDecay(d, now) > 1 then G("ImmunoShock", f1(S.immunoShockDecay(d, now))) end
  local idv = d.immunodep or 0
  if S.immunodepOn() and idv > 0 then
    local E = SandevistanEffects
    local traits = E and E.immunoTraits(p) or {}
    local sick, seen = nil, false
    if E then sick, seen = E.sickReason(p) end
    if sick == "wound" and not seen then sick = "hidden" end              -- una infeccion que el panel de Salud todavia no muestra: no se nombra
    local rate = S.immunoDecayRate(p and p:isAsleep() or false, traits, sick ~= nil)          -- "hidden" tambien frena: el cuerpo la pelea igual
    local toZero = S.immunoHoursToNormal(d, now, rate)
    local lvl = S.immunoMoodle(idv)
    local key = lvl >= 3 and W or T
    key("Immunodep", f0(idv), lvl, toZero and span(toZero) or "?")
    T("ImmunoEffects", f1(S.immunoEffect(d, "infectOnset", traits)), f1(S.immunoEffect(d, "healing", traits)), f1(S.immunoEffect(d, "coldCatch", traits)))
    if sick then W("ImmunoSick", getText("IGUI_Sandevistan_Info_ImmunoSick_" .. sick), f1(rate)) end
  end
  if (d.immunoReboundUntil or -1) > now then
    W("ImmunoRebound", f1(S.immunoReboundMult(d, now)), span(d.immunoReboundUntil - now))
  end
  local tox = d.herbalToxicity or 0
  if tox > 0 then
    local decay = CFG.Immunosuppressant.HerbalToxicity.DecayPerHour
    if S.toxicityMoodle(tox) >= 2 then W("Toxicity", f0(tox), f1(decay), span(tox / decay))
    else T("Toxicity", f0(tox), f1(decay), span(tox / decay)) end
  end

  -- ---- carga neuronal ----
  H("Neural")
  local cn = d.neuralLoad or 0
  local zone = S.cnZone(d)
  local zoneText = getText("IGUI_Sandevistan_Info_Zone_" .. zone)
  if zone == "safe" then T("Neural", f0(cn), zoneText) else W("Neural", f0(cn), zoneText) end
  if working then
    T("NeuralUse", f2(NL.PerSecondActive * v.neuralLoadMultiplier * S.adaptUseMultiplier(d) * FW.profile(d).cn), f1(v.neuralLoadMultiplier))
  end
  if d.cyberpsychosisActive then W("NeuralCyberUse", NL.CyberpsychosisUseMultiplier) end
  local immM = S.immunoNeuralMultiplier(d, now)
  if working and immM < 1 then T("NeuralImmuno", f0((1 - immM) * 100)) end
  local rate = S.cnDecayPerHour(d)
  if S.immunoActiveTier(d, now) then rate = rate * NL.ImmunoDecayMultiplier * S.immunoShockDecay(d, now) end      -- (135) dosis de choque
  if S.antidepActive(d, now) then rate = rate * CFG.Antidepressant.CNDecayMultiplier end
  if s.active then
    T("NeuralDecayNone")
  else
    local rest = now - (d.lastDeactivateHour or -1000)
    if rest >= NL.RestHoursBeforeDecay then
      T("NeuralDecay", f2(rate), NL.RestHoursBeforeDecay)
    else
      T("NeuralDecayWait", span(NL.RestHoursBeforeDecay - rest), NL.RestHoursBeforeDecay)
    end
  end
  for _, base in ipairs({ NL.Zones.risk, NL.Zones.critical }) do
    local target = S.neuralThreshold(d, base)                      -- (178) C05: con la cicatriz neural el umbral es mas bajo
    if cn >= target then
      local h = I.restHoursToBelow(d, now, target)
      if h then T("NeuralRest", target, span(h)) end
    end
  end
  if d.cyberpsychosisActive then T("NeuralFloor", NL.RemissionFloor) end
  if d.disconnected then W("Disconnected") end                 -- (165) T12: el implante está inerte
  local remLeft = S.remissionHoursLeft(d, now)
  if remLeft then G("Remission", span(remLeft)) end
  local wdLeft = S.withdrawalHoursLeft(d, now)
  if wdLeft then W("Withdrawal", span(wdLeft)) end
  local crave = S.cravingHours(d, now)                                   -- (180) C08: abstinencia leve
  if crave then W("Craving", span(crave)) end
  if d.cyberScar then W("CyberScar", pct(NL.Remission.ScarUseMult - 1)) end
  -- (178) C05: cicatriz neural acumulativa (umbrales mas bajos) y caja negra. La linea sale siempre (en 0 explica de que se trata):
  -- si no, el jugador no tiene forma de enterarse de que existe hasta la primera sobrecarga.
  local scarOff = S.scarOffset(d)
  local NS = NL.NeuralScar
  if NS and NS.Enabled then
    if scarOff > 0 then W("ScarOffset", scarOff, NS.PerOverload or 2)
    else T("ScarOffsetZero", NS.PerOverload or 2) end
  end
  if zone == "risk" then T("Sym_risk")
  elseif zone == "critical" then T("Sym_critical") end
  if d.cyberpsychosisActive or zone == "cyberpsychosis" then W("Sym_cyber", NL.Scream.Radius) end
  -- (176) C05: presion psicotica (sin numero: el nivel y lo que la sube)
  local PS = rawget(_G, "SandevistanPsychosis")
  local pst = (PS and p and PS.pressureLevel) and PS.st(p) or nil
  local plvl = pst and PS.pressureLevel(pst)
  if plvl and CFG.Psychosis.Pressure.Enabled and PS.stage(d) >= 1 then
    local by = {}
    for _, k in ipairs({ "fatigue", "crowd", "pain", "heat" }) do
      if ((pst.pressureFactors or {})[k] or 0) >= 0.3 then by[#by + 1] = getText("IGUI_Sandevistan_Info_Pressure_" .. k) end
    end
    local tail = #by > 0 and getText("IGUI_Sandevistan_Info_Pressure_by", table.concat(by, ", ")) or ""
    local key = plvl == "high" and W or T
    key("Pressure", getText("IGUI_Sandevistan_Info_Pressure_" .. plvl), tail)
  end
  local AN = rawget(_G, "SandevistanAnchors")                             -- (179) ancla de humanidad activa
  if AN and pst and AN.active(pst) then
    T("AnchorActive", getText("IGUI_Sandevistan_Anchor_" .. tostring(pst.anchorKind)), span(pst.anchorUntilHour - now))
  end
  local V = CFG.Psychosis.Vulnerable                                      -- (180) C06
  if V and V.Enabled and PS and PS.stage(d) >= (V.MinStage or 2) and (d.vulnUntilHour or -1) > now then
    W("Vulnerable", span(d.vulnUntilHour - now))
  end
  local CRv = rawget(_G, "SandevistanCrisis")                 -- (177) crisis en curso
  local cstate, ctype = nil, nil
  if CRv and p then cstate, ctype = CRv.state(p) end
  if cstate == "cascade" then W("Cascade")
  elseif cstate then W(cstate == "crisis" and "Crisis" or "Episode", getText("IGUI_Sandevistan_Info_CrisisType_" .. ctype)) end
  -- (179) estado mental legible: etapa, proxima crisis, lo descubierto y las ultimas entradas de la caja negra
  H("Mental")
  local stage = PS and PS.stage and PS.stage(d) or 0
  T("MentalStage", getText("IGUI_Sandevistan_Info_MentalStage_" .. stage))
  if CRv and not cstate and CRv.nextHint then
    local hint = CRv.nextHint(pst)
    if hint then T("MentalNext", getText("IGUI_Sandevistan_Info_MentalNext_" .. hint)) end
  end
  local seen = d.seen or {}
  if (seen.fakeTouch or 0) + (seen.fakeHit or 0) > 0 then T("MentalSeenFake", seen.fakeTouch or 0, seen.fakeHit or 0) end
  if (seen.clone or 0) > 0 then T("MentalSeenClone", seen.clone) end
  if (seen.disguise or 0) > 0 then T("MentalSeenDisguise", seen.disguise) end
  if (seen.phantom or 0) > 0 then T("MentalSeenPhantom", seen.phantom) end
  if (seen.figure or 0) > 0 then T("MentalSeenFigure", seen.figure) end                  -- (181) C13.2
  local BB = CFG.Psychosis.BlackBox
  if BB and BB.Enabled then
    local in24 = S.incidentCount(d, BB.Hours24 or 24, now)
    if in24 > 0 then T("Incidents24", in24) end
    local list = (type(d.incidents) == "table") and d.incidents or {}
    for i = #list, 1, -1 do
      if #list - i >= 3 then break end
      local e = list[i]
      if e then T("MentalIncident", span(math.max(0, now - (e.t or now))), I.incidentLabel(e)) end
    end
  end
  if S.antidepActive(d, now) then
    G("Antidep", span(d.antidepUntil - now), f1(CFG.Antidepressant.CNDecayMultiplier))
  end
  -- (162) T09: paliativos activos
  local stg = S.stopgap(d)
  if S.stopgapBeta(d, now) then W("StopgapBeta", span(stg.betaUntil - now)) end
  if S.stopgapSleeping(d, now) then W("StopgapSleeping", span(stg.sleepingUntil - now)) end
  if (stg.painkillerUntil or -1) > now then W("StopgapPainkiller", span(stg.painkillerUntil - now), f1(S.stopgapPainkillerMult(d, now))) end

  -- ---- Kerenzikov ----
  local k = S.kdata(p)
  local kActive, kCrash = Kerenzikov.isActive(p), Kerenzikov.isCrashing(p)
  local KC = CFG.Kerenzikov
  local steps = 0
  if (k.lastDoseHour or -1000) > -500 then
    steps = math.max(0, (k.toleranceSteps or 0) - math.floor((now - k.lastDoseHour) / KC.ToleranceWindowHours))
  end
  if kActive or kCrash or steps > 0 then
    H("Kerenzikov")
    if kActive then
      G("Kere", string.format("%d s", math.ceil(k.activeSeconds or 0)), OD.Kerenzikov.UnconsciousMinSeconds, OD.Kerenzikov.UnconsciousMaxSeconds)     -- (108) segundos reales
    elseif kCrash then
      W("KereCrash", span(k.crashUntilHour - now))
    end
    if steps > 0 then
      T("KereTol", steps, pct(math.max(KC.ToleranceFloor, 1 - KC.ToleranceStep * steps)))
    end
  end

  -- ---- estados (el texto completo de cada moodle) ----
  H("Moodles")
  local states = SandevistanMoodles and SandevistanMoodles.states(p) or {}
  if #states == 0 then
    T("NoStatus")
  else
    for _, st in ipairs(states) do
      add("m", st.title, st.kind == "Good" and 0.55 or 1.0, st.kind == "Good" and 0.9 or 0.6, st.kind == "Good" and 0.6 or 0.45)
      add("t", st.desc)
    end
  end

  -- ---- controles ----
  H("Controls")
  local keyName = "Z"
  pcall(function() keyName = getKeyName(SandevistanInput.key()) end)
  T("Controls1", keyName)
  T("Controls2")
  return L
end

---------------------------------------------------------------------------
-- Vista (ISPanel dentro de un ISTabPanel)
---------------------------------------------------------------------------
local V = nil
if ISPanel then
  SandevistanInfoViewPanel = ISPanel:derive("SandevistanInfoViewPanel")
  V = SandevistanInfoViewPanel

  local PAD = 10
  local COLORS = { t = { 0.86, 0.9, 0.95 }, w = { 1.0, 0.72, 0.4 }, g = { 0.55, 0.92, 0.65 } }

  local function fontH(font)
    local ok, h = pcall(function() return getTextManager():getFontHeight(font) end)
    return (ok and h and h > 0) and h or 14
  end

  local function measure(font, text)
    local ok, w = pcall(function() return getTextManager():MeasureStringX(font, text) end)
    return (ok and w) or string.len(text) * 6
  end

  -- Palabras de un texto (separadas por espacios). Sin patrones: en Kahlua fallan con caracteres acentuados.
  local function words(text)
    local list, i, n = {}, 1, string.len(text)
    while i <= n do
      local j = string.find(text, " ", i, true)
      if not j then list[#list + 1] = string.sub(text, i); break end
      if j > i then list[#list + 1] = string.sub(text, i, j - 1) end
      i = j + 1
    end
    return list
  end

  -- Parte "text" en renglones de ancho <= maxW (por palabras). Devuelve una lista de strings.
  local function wrap(font, text, maxW)
    local out, cur = {}, ""
    for _, word in ipairs(words(text)) do
      local try = (cur == "") and word or (cur .. " " .. word)
      if cur ~= "" and measure(font, try) > maxW then
        out[#out + 1] = cur
        cur = word
      else
        cur = try
      end
    end
    if cur ~= "" then out[#out + 1] = cur end
    if #out == 0 then out[1] = "" end
    return out
  end
  I.wrap = wrap

  function V:new(x, y, w, h, playerNum)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.playerNum = playerNum or 0
    o.scroll, o.maxScroll = 0, 0
    o.lines, o.wrapped = {}, {}
    o.builtMs, o.wrappedW = -100000, -1
    o.panelH = 160
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    return o
  end

  function V:createChildren()
    local ok, err = pcall(function()
      local b1 = ISButton:new(PAD, 6, 200, 24, "", self, V.onTogglePanel)
      b1:initialise(); b1:instantiate()
      b1.borderColor = { r = 1, g = 1, b = 1, a = 0.35 }
      self:addChild(b1); self.btnToggle = b1
      local b2 = ISButton:new(PAD + 204, 6, 60, 24, getText("IGUI_Sandevistan_Info_BtnAuto"), self, V.onAuto)
      b2:initialise(); b2:instantiate()
      b2.borderColor = { r = 1, g = 1, b = 1, a = 0.35 }
      self:addChild(b2); self.btnAuto = b2
      local b3 = ISButton:new(PAD + 268, 6, 70, 24, getText("IGUI_Sandevistan_Info_BtnGuide"), self, V.onGuide)      -- v0.1.30 (30)
      b3:initialise(); b3:instantiate()
      b3.borderColor = { r = 1, g = 1, b = 1, a = 0.35 }
      self:addChild(b3); self.btnGuide = b3
    end)
    if not ok then S.warnOnce("infoBtn", "pestaña Implante: no se pudieron crear los botones (" .. tostring(err) .. ")") end
  end

  function V:player() return getSpecificPlayer(self.playerNum) end

  function V:onGuide()
    local p = self:player()
    if p and SandevistanMenus and SandevistanMenus.showGuide then SandevistanMenus.showGuide(p) end
  end

  function V:onTogglePanel()
    local p = self:player()
    if p and SandevistanHUD then SandevistanHUD.toggleFloating(p) end
    self.builtMs = -100000
  end

  function V:onAuto()
    local p = self:player()
    if p then S.data(p).hudFloating = nil end
  end

  -- Reconstruye el contenido a lo sumo 2 veces por segundo (y al cambiar el ancho).
  function V:refresh(p, d, s, innerW)
    local now = S.realMs()
    if now - self.builtMs >= 500 then
      self.builtMs = now
      local ok, res = pcall(I.buildLines, p, d, s, S.worldHours())
      if ok then self.lines = res else S.warnOnce("infoLines", "pestaña Implante: " .. tostring(res)); self.lines = {} end
      self.wrappedW = -1
    end
    if self.wrappedW ~= innerW then
      self.wrappedW = innerW
      local small, medium = UIFont.Small, UIFont.Medium
      local hs, hm = fontH(small), fontH(medium)
      local w, y = {}, 0
      for _, ln in ipairs(self.lines) do
        if ln.kind == "h" then
          y = y + (#w > 0 and 8 or 0)
          w[#w + 1] = { kind = "h", text = ln.text, y = y, h = hm + 4, font = medium }
          y = y + hm + 6
        else
          local font = small
          local indent = (ln.kind == "m") and 0 or 0
          for _, piece in ipairs(wrap(font, ln.text, innerW - indent)) do
            w[#w + 1] = { kind = ln.kind, text = piece, y = y, h = hs + 1, font = font, x = indent, r = ln.r, g = ln.g, b = ln.b }
            y = y + hs + 2
          end
          if ln.kind == "t" or ln.kind == "w" or ln.kind == "g" then y = y + 2 end
        end
      end
      self.wrapped, self.contentH, self.lineH = w, y, hs + 2
    end
  end

  function V:onMouseWheel(del)
    self.scroll = math.max(0, math.min(self.maxScroll or 0, self.scroll + del * 3 * (self.lineH or 16)))
    return true
  end

  function V:prerender()
    -- ocupar todo el panel de pestañas (la ventana se puede redimensionar)
    local par = self.parent
    if par and par.getWidth then
      local pw = par:getWidth()
      local ph = par:getHeight() - self:getY()
      if pw ~= self:getWidth() then self:setWidth(pw) end
      if ph > 0 and ph ~= self:getHeight() then self:setHeight(ph) end
    end
    local W, Hh = self:getWidth(), self:getHeight()
    local p = self:player()
    if not p then return end
    local d, s = S.data(p), R.session(p)
    local hs = fontH(UIFont.Small)

    -- botones: estado del panel flotante
    local visible = SandevistanHUD and SandevistanHUD.floatingVisible(d)
    local explicit = d.hudFloating ~= nil
    if self.btnToggle then
      self.btnToggle:setTitle(getText(visible and "IGUI_Sandevistan_Info_BtnShown" or "IGUI_Sandevistan_Info_BtnHidden"))
      local bw = W - 2 * PAD - (explicit and 64 or 0) - 74          -- (32): deja lugar al boton Guide (70) entre este y Auto
      self.btnToggle:setWidth(math.max(120, bw))
      self.btnToggle:setHeight(24)
    end
    if self.btnAuto then
      self.btnAuto:setVisible(explicit)
      self.btnAuto:setX(W - PAD - 60)
    end
    if self.btnGuide then self.btnGuide:setX(W - PAD - (explicit and 64 or 0) - 70) end
    local y = 34
    if not explicit then
      local key = (SandevistanMoodles and SandevistanMoodles.ready) and "IGUI_Sandevistan_Info_PanelAutoHidden" or "IGUI_Sandevistan_Info_PanelAutoShown"
      self:drawText(getText(key), PAD, y, 0.6, 0.65, 0.7, 1, UIFont.Small)
      y = y + hs + 6
    end

    -- panel del HUD incrustado (si la ventana es alta; si no, solo la lista)
    local showPanel = Hh >= (y + self.panelH + 150)
    if showPanel and SandevistanHUD and SandevistanHUDPanel then
      local ok, w, h = pcall(function()
        local model = SandevistanHUD.buildModel(p, d, s)
        model.statuses = {}
        model.idle = false
        local px = math.max(PAD, math.floor((W - SandevistanHUDPanel.BASE_W) / 2))
        return SandevistanHUDPanel.draw(self, model, 1, px, y)
      end)
      if ok and h then self.panelH = h; y = y + h + 8
      else S.warnOnce("infoPanel", "pestaña Implante: no se pudo dibujar el panel (" .. tostring(w) .. ")") end
    end

    -- lista con scroll (solo se dibujan los renglones que caben completos)
    local top = y
    local visH = Hh - top - 6
    local innerW = W - 2 * PAD - 8
    self:refresh(p, d, s, innerW)
    self.maxScroll = math.max(0, (self.contentH or 0) - visH)
    if self.scroll > self.maxScroll then self.scroll = self.maxScroll end
    self:drawRect(PAD, top - 3, W - 2 * PAD, 1, 0.35, 1, 1, 1)
    local hr, hg, hb = 0.4, 0.85, 1.0
    if d.variant == "military" then hr, hg, hb = 1.0, 0.7, 0.15 end
    for _, ln in ipairs(self.wrapped) do
      local ly = top + ln.y - self.scroll
      if ly >= top and ly + ln.h <= top + visH then
        if ln.kind == "h" then
          self:drawText(ln.text, PAD, ly, hr, hg, hb, 1, ln.font)
          self:drawRect(PAD, ly + ln.h - 1, W - 2 * PAD - 8, 1, 0.3, hr, hg, hb)
        else
          local c = COLORS[ln.kind] or COLORS.t
          local r, g, b = ln.r or c[1], ln.g or c[2], ln.b or c[3]
          self:drawText(ln.text, PAD + (ln.x or 0), ly, r, g, b, 1, ln.font)
        end
      end
    end
    -- barra de desplazamiento
    if self.maxScroll > 0 and visH > 20 then
      local total = self.contentH
      local th = math.max(16, math.floor(visH * visH / total))
      local ty = top + math.floor((visH - th) * (self.scroll / self.maxScroll))
      self:drawRect(W - 8, top, 3, visH, 0.15, 1, 1, 1)
      self:drawRect(W - 8, ty, 3, th, 0.7, hr, hg, hb)
    end
  end
end

---------------------------------------------------------------------------
-- Alta y baja de la pestaña en la ventana de información de cada jugador
---------------------------------------------------------------------------
function I.wanted(p)
  local d = S.data(p)
  return S.hasAnyImplant(d) or (d.neuralLoad or 0) > 0 or (d.herbalToxicity or 0) > 0 or S.immunoHoursLeft(d) > 0 or (d.immunodep or 0) > 0
         or Kerenzikov.isActive(p) or Kerenzikov.isCrashing(p) or S.antidepActive(d)
end

-- Agrega o quita la pestaña según haga falta. Devuelve true si hubo un cambio.
function I.sync(win)
  if not V or not win or not win.panel or win.sandevistanFailed then return false end
  local p = getSpecificPlayer(win.playerNum or 0)
  if not p then return false end
  local want = I.wanted(p)
  if want and not win.sandevistanShown then
    if not win.sandevistanView then
      local pn = win.panel
      local v = V:new(0, pn.tabHeight or 8, pn:getWidth(), pn:getHeight() - (pn.tabHeight or 8), win.playerNum or 0)
      v:initialise()
      if not v.javaObject then v:instantiate() end
      v:setVisible(false)
      win.sandevistanView = v
    end
    win.panel:addView(getText("IGUI_Sandevistan_Info_Tab"), win.sandevistanView)
    win.sandevistanShown = true
    return true
  elseif not want and win.sandevistanShown then
    win.panel:removeView(win.sandevistanView)
    win.sandevistanShown = false
    return true
  end
  return false
end

local function syncSafe(win)
  local ok, err = pcall(I.sync, win)
  if not ok then
    win.sandevistanFailed = true                 -- no reintentar cada segundo
    S.warnOnce("infoTab", "pestaña Implante no disponible (" .. tostring(err) .. ")")
  end
end

-- La ventana crea sus pestañas en createChildren: se envuelve para agregar la nuestra.
if ISCharacterInfoWindow and not ISCharacterInfoWindow.sandevistanHooked then
  ISCharacterInfoWindow.sandevistanHooked = true
  local original = ISCharacterInfoWindow.createChildren
  function ISCharacterInfoWindow:createChildren()
    original(self)
    syncSafe(self)
  end
end

-- Revisa cada segundo si la pestaña debe aparecer o desaparecer (instalar, extraer, terminar la cobertura...).
local lastCheckMs = 0
local function tick()
  local now = S.realMs()
  if now - lastCheckMs < 1000 then return end
  lastCheckMs = now
  for idx = 0, getNumActivePlayers() - 1 do
    local win = getPlayerInfoPanel and getPlayerInfoPanel(idx) or nil
    if win then syncSafe(win) end
  end
end
Events.OnTick.Add(S.safe("InfoView.OnTick", tick))

return I
