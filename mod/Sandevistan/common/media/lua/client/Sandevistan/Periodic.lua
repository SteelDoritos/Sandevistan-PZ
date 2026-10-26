-- Sandevistan / Periodic: todo lo que corre en horas in-game.
--   EveryTenMinutes: rechazo, (135) inmunodepresion.
--   EveryTenMinutes (136, antes EveryHours): decay de CN, XP pasiva, toxicidad herbal, dolor post-op (hourlyTick: tasas por hora x horas pasadas).
--   EveryOneMinute: síntomas (rechazo, toxicidad, CN), Kerenzikov, despertares, alucinaciones, (135) efectos de la inmunodepresion.
require "Sandevistan/Core"
require "Sandevistan/Kerenzikov"
require "Sandevistan/Effects"
require "Sandevistan/Runtime"
require "Sandevistan/Immunodep"

local CFG = SandevistanConfig
local S = Sandevistan
local E = SandevistanEffects
local R = SandevistanRuntime
local FW = SandevistanFirmware

SandevistanPeriodic = {}
local P = SandevistanPeriodic

local function forEachLocalPlayer(fn)
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p and not p:isDead() then fn(p, S.data(p)) end
  end
end

local function elapsed(d, field, now)
  local last = d[field]
  d[field] = now
  if last == nil then return 0 end
  return math.max(0, math.min(now - last, 24))  -- tope de catch-up: 24 h
end

---------------------------------------------------------------------------
-- Rechazo (cada 10 min in-game)
---------------------------------------------------------------------------
function P.rejectionTick(player, d)
  local now = S.worldHours()
  local hours = elapsed(d, "lastRejectionTickHour", now)
  if not (S.hasWorkingImplant(d) or d.disconnected) or hours <= 0 then return end     -- (165) desconectado: el rechazo sigue como apagado
  local level = S.level(d)
  local adapt = S.adaptationTerm(d, level)
  if player:isAsleep() then adapt = adapt * CFG.Rejection.SleepMultiplier end
  local chronic = S.chronicRejection(d)                          -- CN alta (cronica)
  local tier = S.immunoActiveTier(d, now)
  local m = S.immunoRejectionMultiplier(d, now)
  local traitMult = (d.traits and d.traits.chrome) and CFG.Traits.ChromeRejectionMult or 1
  local gain = (adapt + chronic) * m * hours * CFG.Rejection.RateMultiplier * traitMult * FW.profile(d).rej        -- (82) firmware (Compatibilidad)
             * S.immunoReboundMult(d, now)                                                                              -- (135) rebote al cortar una tanda fuerte
             * S.stopgapRejectionMult(d, now, player:isAsleep())                                                         -- (162) T09: analgésico y somnífero
  -- recuperación natural (implante apagado): completa si no hay ganancia (adaptación estable o cobertura); si la hay pero no es
  -- por carga neuronal crónica, proporcional a lo cerca que esté la adaptación de la ideal (RecoveryFromAdapt..1). Durmiendo, más rápida.
  local decay = 0
  if not R.isActive(player) then
    local RJ = CFG.Rejection
    if gain <= 0 then
      decay = RJ.NaturalDecay * hours
    elseif chronic <= 0 then
      local k = (S.adaptFraction(d) - RJ.RecoveryFromAdapt) / math.max(0.01, 1 - RJ.RecoveryFromAdapt)
      decay = RJ.NaturalDecay * math.max(0, math.min(1, k)) * hours
    end
    if decay > 0 and player:isAsleep() then decay = decay * RJ.SleepDecayMultiplier end
  end
  d.rejection = math.max(0, math.min(100, d.rejection + gain - decay))

  -- despertar de emergencia
  if player:isAsleep() then
    local coverageEnded = d.wasCovered and not tier and adapt > 0
    if d.rejection >= CFG.Rejection.EmergencyWakeAt or coverageEnded then
      S.try("forceAwake", function() player:forceAwake() end)
      E.addPain(player, "Torso_Lower", 30)
      E.halo(player, getText("IGUI_Sandevistan_WakeRejection"), 255, 80, 80)
    end
  end
  d.wasCovered = tier ~= nil
  R.checkThresholds(player)
end

---------------------------------------------------------------------------
-- (135) Inmunodepresion (cada 10 min in-game): baja hacia el piso de la cobertura o hacia 0; al terminar una tanda fuerte, rebote de rechazo
---------------------------------------------------------------------------
function P.immunoTick(player, d)
  local now = S.worldHours()
  local hours = elapsed(d, "lastImmunoTickHour", now)
  if hours <= 0 then return end
  local covered = S.immunoActiveTier(d, now) ~= nil
  if not S.immunodepOn() then
    d.immunodep, d.immunoPeak, d.immunoReboundUntil = 0, 0, -1
  else
    if d.immunoWasCovered and not covered then                        -- termino la cobertura: si la tanda fue fuerte, rebote
      local RB = CFG.Immunosuppressant.Immunodepression.Rebound
      if (d.immunoPeak or 0) >= RB.Peak and S.hasWorkingImplant(d) then
        d.immunoReboundUntil = now + RB.Hours
        E.halo(player, getText("IGUI_Sandevistan_ImmunoRebound"), 255, 140, 80)
      end
      d.immunoPeak = 0
    end
    if (d.immunodep or 0) > 0 then
      local rate = S.immunoDecayRate(player:isAsleep(), E.immunoTraits(player), E.sickReason(player) ~= nil)
      S.immunoTickID(d, now, hours, rate)
    end
  end
  d.immunoWasCovered = covered
end

---------------------------------------------------------------------------
-- Horario
---------------------------------------------------------------------------
function P.hourlyTick(player, d)
  local now = S.worldHours()
  local hours = elapsed(d, "lastCNTickHour", now)
  if hours <= 0 then return end

  -- decay de CN
  if not R.isActive(player) and (now - d.lastDeactivateHour) >= CFG.NeuralLoad.RestHoursBeforeDecay then
    local rate = S.cnDecayPerHour(d)
    if S.immunoActiveTier(d, now) then rate = rate * CFG.NeuralLoad.ImmunoDecayMultiplier * S.immunoShockDecay(d, now) end   -- (135) dosis de choque
    if S.antidepActive(d, now) then rate = rate * CFG.Antidepressant.CNDecayMultiplier end
    if d.disconnected then rate = rate * (CFG.Disconnect.DecayMult or 0.5) end                 -- (165) T12: inerte, la CN baja a la mitad
    local floor = d.cyberpsychosisActive and CFG.NeuralLoad.RemissionFloor or 0
    d.neuralLoad = math.max(floor, d.neuralLoad - rate * hours)
  end

  -- remisión de la cyberpsicosis: horas acumuladas sin implante (×1) o desconectado (×RemissionRate) — (165) T12
  if S.remissionHoursLeft(d, now) then
    local rate = d.disconnected and (CFG.Disconnect.RemissionRate or 0.5) or 1
    d.remissionHours = (d.remissionHours or 0) + hours * rate
    if S.remissionHoursLeft(d, now) <= 0 then
      d.cyberpsychosisActive = false
      d.cyberScar = true
      d.remissionHours = nil
      d.neuralLoad = math.min(d.neuralLoad, CFG.NeuralLoad.RemissionFloor)
      E.halo(player, getText("IGUI_Sandevistan_Remission"), 120, 220, 255)
      S.log("cyberpsicosis en remision")
      local PS = rawget(_G, "SandevistanPsychosis")                     -- (179) C09: cierre narrativo
      if PS and PS.remissionDone then PS.remissionDone(player, d) end
    end
  end

  -- cicatriz térmica: el tope de Heat se recupera despacio mientras el implante está apagado
  if not R.isActive(player) then S.recoverHeatCap(d, hours, player:isAsleep()) end

  -- XP pasiva
  if S.hasWorkingImplant(d) then
    local v = S.variantCfg(d)
    if S.level(d) < v.stableLevel and d.rejection < CFG.XP.PassiveMaxRejection then
      local up = S.addAdaptXP(d, CFG.XP.PassivePerHour * hours * FW.profile(d).xpPassive, "pasiva")
      if up then E.halo(player, getText("IGUI_Sandevistan_LevelUp", up), 80, 220, 255) end
    end
    -- dolor lumbar post-op proporcional a lo que falta para estabilizar
    local frac = 1 - S.level(d) / v.stableLevel
    if frac > 0 then E.setMinPain(player, "Torso_Lower", CFG.Surgery.PostOpPain * frac) end
  end

  -- toxicidad herbal
  if d.herbalToxicity > 0 then
    d.herbalToxicity = math.max(0, d.herbalToxicity - CFG.Immunosuppressant.HerbalToxicity.DecayPerHour * hours)
  end
end

---------------------------------------------------------------------------
-- Alucinaciones (locales: nunca crean zombis reales)
---------------------------------------------------------------------------
local WHISPERS = { "IGUI_Sandevistan_Hallu_1", "IGUI_Sandevistan_Hallu_2", "IGUI_Sandevistan_Hallu_3",
                   "IGUI_Sandevistan_Hallu_4", "IGUI_Sandevistan_Hallu_5" }

function P.hallucinate(player, d)
  local roll = ZombRand(3)
  if roll == 0 then
    E.halo(player, getText(WHISPERS[ZombRand(#WHISPERS) + 1]), 150, 150, 170)
  elseif roll == 1 then
    E.addStat(player, "PANIC", 25)
    E.halo(player, getText("IGUI_Sandevistan_Hallu_Movement"), 150, 150, 170)
  else
    E.addStat(player, "STRESS", 0.1)
    E.reduceHealthWithFloor(player, CFG.NeuralLoad.PsychosomaticDamage, CFG.NeuralLoad.PsychosomaticHealthFloor)
    E.halo(player, getText("IGUI_Sandevistan_Hallu_Pain"), 150, 150, 170)
  end
end

---------------------------------------------------------------------------
-- (178) C05: recuperacion de la cicatriz neural (1 punto por dia de juego con el implante apagado)
---------------------------------------------------------------------------
function P.neuralScarTick(player, d)
  local NS = CFG.NeuralLoad.NeuralScar
  if not (NS and NS.Enabled) then return end
  local now = S.worldHours()
  local last = d.lastScarHour
  d.lastScarHour = now
  if (d.neuralScar or 0) <= 0 then d.neuralScarHours = 0; return end    -- sin cicatriz, la hora se sigue tomando (si vuelve, no regala un dia)
  if last == nil or R.isActive(player) then return end      -- encendido: el tiempo no cuenta (y no se acumula para despues)
  local hours = math.min(24, now - last)                    -- tope de catch-up, como el resto de Periodic
  if hours <= 0 then return end
  d.neuralScarHours = (d.neuralScarHours or 0) + hours
  local need = NS.RecoverHours or 24
  while d.neuralScarHours >= need and (d.neuralScar or 0) > 0 do
    d.neuralScarHours = d.neuralScarHours - need
    S.addNeuralScar(player, d, -(NS.RecoverPerDay or 1))
  end
end

---------------------------------------------------------------------------
-- (180) C08: abstinencia leve (27 §7). Sube estres e infelicidad despacio hasta los topes y el monitor insiste; nunca toca la CN.
---------------------------------------------------------------------------
function P.cravingTick(player, d)
  local CRV = CFG.NeuralLoad.Craving
  local nowH = S.worldHours()
  local crave = S.cravingHours(d, nowH)
  if not crave or player:isAsleep() then return end
  local mult = S.antidepActive(d, nowH) and (CRV.AntidepMult or 0.5) or 1
  if (E.getStat(player, "STRESS") or 0) < (CRV.StressCap or 0.15) then E.addStat(player, "STRESS", (CRV.StressPerMinute or 0) * mult) end
  if (E.getStat(player, "UNHAPPINESS") or 0) < (CRV.UnhappyCap or 20) then E.addStat(player, "UNHAPPINESS", (CRV.UnhappyPerMinute or 0) * mult) end
  local PS = rawget(_G, "SandevistanPsychosis")
  local st = PS and PS.st and PS.st(player) or nil
  if st and S.realMs() >= (st.craveToastMs or 0) then
    st.craveToastMs = S.realMs() + ZombRandFloat(CRV.MonitorEveryMinutes[1], CRV.MonitorEveryMinutes[2]) * 60000
    if PS.toast then PS.toast(getText("IGUI_Sandevistan_Mon_LinkIdle", math.floor(crave)), "warn") end
  end
end

---------------------------------------------------------------------------
-- Cada minuto: síntomas
---------------------------------------------------------------------------
function P.minuteTick(player, d)
  S.syncPerk(player)
  SandevistanImmunodep.tick(player, d)                      -- (135) heridas, resfrio y malestar con la inmunodepresion
  local PS = rawget(_G, "SandevistanPsychosis")
  if PS then PS.minuteTick(player, d) end                   -- terrores nocturnos
  local AN = rawget(_G, "SandevistanAnchors")               -- (179) dormir, compania (leer y comer se enganchan a sus acciones)
  if AN then AN.tick(player, d, PS and PS.st(player) or nil) end
  -- (178) C05: la cicatriz neural se recupera con el implante apagado
  P.neuralScarTick(player, d)
  -- abstinencia: estres y fatiga suben de a poco en los primeros dias de la remision
  local nowH = S.worldHours()
  if S.withdrawalHoursLeft(d, nowH) then
    local W = CFG.NeuralLoad.Remission.Withdrawal
    local mult = S.antidepActive(d, nowH) and W.AntidepMult or 1
    if E.getStat(player, "STRESS") < W.StressCap then E.addStat(player, "STRESS", W.StressPerMinute * mult) end
    if not player:isAsleep() and E.getStat(player, "FATIGUE") < W.FatigueCap then E.addStat(player, "FATIGUE", W.FatiguePerMinute * mult) end
  end
  P.cravingTick(player, d)                                  -- (180) C08: abstinencia leve (nunca toca la CN)
  -- rechazo
  if S.hasWorkingImplant(d) or d.disconnected then
    local lvl = S.rejectionMoodle(d.rejection)
    local fever = S.feverTemp(d.rejection, d, nowH)                 -- (107) desde rechazo 35 (febricula); antes desde 50. (162) el analgésico la baja
    if fever then E.setTemperatureAtLeast(player, fever) end
    if lvl >= 2 then E.setMinPain(player, "Torso_Lower", 15 * lvl) end
    if lvl >= 4 then E.reduceHealth(player, CFG.Rejection.ShockDamagePerHour / 60) end
  end

  -- toxicidad herbal
  local tox = S.toxicityMoodle(d.herbalToxicity)
  if tox >= 2 and E.getStat(player, "FOOD_SICKNESS") < (d.herbalToxicity - 25) then
    E.setStat(player, "FOOD_SICKNESS", d.herbalToxicity - 25)
    SandevistanImmunodep.resnap(player)                     -- (135) la inmunodepresion no amplifica la toxicidad herbal
  end

  -- Carga Neuronal
  local zone = S.cnZone(d)
  if zone == "critical" or zone == "cyberpsychosis" then
    if S.chance(0.05) then E.addStat(player, "PANIC", 15) end
  end
  local halluAt = S.neuralThreshold(d, CFG.NeuralLoad.HallucinationThreshold)    -- (178) C05: la cicatriz neural baja el umbral
  if d.cyberpsychosisActive and CFG.NeuralLoad.Hallucinations
     and d.neuralLoad >= halluAt then
    local f = (d.neuralLoad - halluAt) / math.max(1, 100 - halluAt)
    local c = CFG.NeuralLoad.HallucinationChancePerMinute
    local PS = rawget(_G, "SandevistanPsychosis")
    local mult = (PS and PS.freqMult) and PS.freqMult(d, PS.st(player), "Hallucinations") * S.halluMultiplier(d) or S.symptomMultiplier(d)            -- (176) con la presión
    if S.chance((c.min + (c.max - c.min) * f) * mult) then P.hallucinate(player, d) end
  end

  -- v0.1.15: sangrado nasal (espontáneo y en curso) y grito psicótico
  if E.isNosebleeding(d) then
    local nb = CFG.NeuralLoad.Nosebleed
    E.reduceHealthWithFloor(player, nb.DamagePerMinute, nb.HealthFloor)
    if ZombRand(5) == 0 then E.faceBlood(player) end
  elseif S.chance(S.nosebleedChance(d)) then
    E.startNosebleed(player, d)
  end
  if not player:isAsleep() and S.chance(S.screamChance(d) * S.stopgapScreamMult(d)) then E.scream(player, d) end    -- (162) el betabloqueante lo calma

  -- Kerenzikov
  if Kerenzikov.isActive(player) then
    Kerenzikov.minuteRegen(player)                                     -- (108) 5 a 10 % de resistencia por minuto de juego
  end
  -- (119) el bajon del casero ya no se sostiene cada minuto: pasa una sola vez al terminar el efecto (Kerenzikov.finish)
end

Events.EveryTenMinutes.Add(S.safe("Periodic.EveryTenMinutes", function() forEachLocalPlayer(P.rejectionTick); forEachLocalPlayer(P.immunoTick) end))
-- (136) hourlyTick corre cada 10 min: todo lo que hace es tasa por hora x horas pasadas, asi que el total no cambia, pero la CN baja de a poco
-- y la espera de RestHoursBeforeDecay se cumple con 10 min de margen (antes se perdia la hora en curso: de 1 a 2 h de espera real).
Events.EveryTenMinutes.Add(S.safe("Periodic.HourlyTick", function() forEachLocalPlayer(P.hourlyTick) end))
Events.EveryOneMinute.Add(S.safe("Periodic.EveryOneMinute", function() forEachLocalPlayer(P.minuteTick) end))
return P
