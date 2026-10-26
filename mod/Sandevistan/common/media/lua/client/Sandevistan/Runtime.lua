-- Sandevistan / Runtime: sesión activa en tiempo real (Heat, stamina, CN y XP por segundo),
-- cortes, Overdrive, colapso y falla catastrófica.
require "Sandevistan/Core"
require "Sandevistan/Kerenzikov"
require "Sandevistan/Effects"
require "Sandevistan/Slowdown"
require "Sandevistan/SlowAudio"

local CFG = SandevistanConfig
local S = Sandevistan
local E = SandevistanEffects
local SD = SandevistanSlowdown
local FW = SandevistanFirmware

SandevistanRuntime = {}
local R = SandevistanRuntime

R.sessions = {}   -- [playerIndex] = estado en memoria (no persiste: al cargar, el implante arranca apagado)

function R.session(player)
  local idx = player:getPlayerNum()
  local s = R.sessions[idx]
  if not s then
    s = { active = false, armed = false, overdrive = false, overdriveUntilMs = 0, reuseAtMs = 0,
          lastMs = S.realMs(), lastFlushMs = S.realMs(), xpPending = 0, tier = nil,
          momentum = 0, staminaDebt = 0, enduranceMark = nil }
    R.sessions[idx] = s
  end
  return s
end

function R.isActive(player) return R.session(player).active end

-- Tramo efectivo: el del nivel más el bono de Impulso (uso prolongado) y, en Overdrive, el salto
-- de ventajas. Slowdown y Combat leen esto en vez del tramo base.
function R.effectiveTier(s, d)
  local base = s.tier
  if not base then return nil end
  if d and FW.profile(d).mode == "work" then          -- (86) Taller: sin impulso, Overdrive, furia, rasgos ni chips (el tramo ya es el del modo trabajo)
    return { world = base.world, comp = base.comp, minLevel = base.minLevel, zombieSpeed = base.zombieSpeed, playerBoost = 0, attackBoost = 0, extraDamage = 0 }
  end
  local M, OB = CFG.Momentum, CFG.Overdrive.Bonus
  local m = s.momentum or 0
  local t = { world = base.world, comp = base.comp, minLevel = base.minLevel,
              zombieSpeed = base.zombieSpeed,
              playerBoost = base.playerBoost + M.PlayerBoost * m,
              attackBoost = (base.attackBoost or base.playerBoost) + M.AttackBoost * m,
              extraDamage = 0 }
  if d and d.traits and d.traits.edgerunner then      -- rasgo Edgerunner (v0.1.30 (15)): velocidad y ataque por encima del tramo
    t.playerBoost = t.playerBoost + CFG.Traits.EdgerunnerPlayerBoost
    t.attackBoost = t.attackBoost + CFG.Traits.EdgerunnerAttackBoost
  end
  if s.overdrive then
    t.playerBoost = t.playerBoost + OB.PlayerBoost
    t.attackBoost = t.attackBoost + OB.AttackBoost
    t.zombieSpeed = t.zombieSpeed * OB.ZombieSpeedMult
    t.extraDamage = OB.DamageBonus
  end
  if s.berserk then                                   -- furia cibernética (Psychosis.lua): cyberpsicosis + implante encendido
    local B = CFG.Psychosis.Berserk
    t.attackBoost = t.attackBoost + B.AttackBoost
    t.extraDamage = t.extraDamage + B.DamageBonus
  end
  if s.fury then                                      -- furia total de la sobrecarga neural (Psychosis.lua): se suma a la furia
    local F = CFG.Psychosis.Overload.Fury
    t.attackBoost = t.attackBoost + F.AttackBoost
    t.extraDamage = t.extraDamage + F.DamageBonus
  end
  -- (82) firmware: el bono de ataque total (tramo, impulso, Overdrive y furia) se multiplica por el del perfil (Martillo x0.5).
  -- El factor de zombis y la velocidad del jugador ya vienen ajustados en el tramo base (S.dilationTier).
  if d then
    local ab = FW.profile(d).ab
    if ab ~= 1 then t.attackBoost = t.attackBoost * ab end
    -- (109) Overclock ("linea roja"): con el Heat por encima de From del tope los bonos suben en linea recta hasta el tope (movimiento +Move, ataque +Attack,
    -- zombis x ZombieSpeed); el factor de zombis no baja del piso que acepta el servidor
    local oc = FW.profile(d).overclock
    if oc then
      local f = FW.overclockFactor(d)
      if f > 0 then
        t.playerBoost = t.playerBoost + oc.Move * f
        t.attackBoost = t.attackBoost + oc.Attack * f
        t.zombieSpeed = math.max(FW.minZs(), t.zombieSpeed * (1 - (1 - oc.ZombieSpeed) * f))
      end
      t.overclock = f
    end
  end
  return t
end

local function refreshTier(player, s)
  s.eff = R.effectiveTier(s, S.data(player))
  if s.eff then SD.setTier(player, s.eff) end
end

R.refreshTier = refreshTier

local function txt(key, ...) return getText(key, ...) end

---------------------------------------------------------------------------
-- Precondiciones
---------------------------------------------------------------------------
-- (163) T11: ignore = { stamina = true, heat = true } saltea esos dos seguros (es lo que hace R.force); el resto sigue igual.
function R.canActivate(player, ignore)
  local d = S.data(player)
  local ig = ignore or {}
  if d.variant == "destroyed" then return false, "IGUI_Sandevistan_Err_Destroyed" end
  if d.disconnected then return false, "IGUI_Sandevistan_Err_Disconnected" end          -- (165) T12: inerte hasta reconectar
  if not S.hasWorkingImplant(d) then return false, nil end
  if player:isDead() then return false, nil end
  if player:getVehicle() then return false, "IGUI_Sandevistan_Err_Vehicle" end
  if player:isAsleep() or E.isUnconscious(player) then return false, nil end
  if d.lockUntilCool and d.heat <= 0 then d.lockUntilCool = false end
  if not ig.heat then
    if d.lockUntilCool and d.heat > 0 then return false, "IGUI_Sandevistan_Err_Heat" end
    if d.heat >= S.heatCap(d) then return false, "IGUI_Sandevistan_Err_Heat" end
  end
  if S.gameMs() < R.session(player).reuseAtMs then return false, nil end                    -- (127) plazos en el reloj de juego
  if d.rejection >= CFG.Rejection.BlockActivationAt then return false, "IGUI_Sandevistan_Err_Rejection" end
  local work = FW.profile(d).mode == "work"
  if work then                                        -- (86) Taller: CN o rechazo altos y el bloqueo tras una amenaza (Debug: workForce los ignora)
    local ss = R.session(player)
    if not ss.workForce then
      local wp = FW.workProblems(d)
      if #wp > 0 then return false, wp[1][1], wp[1][2] end
      if S.gameMs() < (ss.workLockUntilMs or 0) then return false, nil end
    end
  end
  if not ig.stamina and E.getEndurance(player) < CFG.Stamina.MinToActivate then return false, "IGUI_Sandevistan_Err_Stamina" end        -- (108) Taller tambien gasta estamina
  return true, nil
end

---------------------------------------------------------------------------
-- Activar / desactivar
---------------------------------------------------------------------------
local function evasiveReflex(player)
  local cell = getCell()
  local zl = cell and cell:getZombieList()
  if not zl then return end
  local r = CFG.Combat.EvasiveReflexRadius
  for i = 0, zl:size() - 1 do
    local z = zl:get(i)
    if z and not z:isDead() and z:DistTo(player) <= r then
      local attacking = false
      S.try("zIsAttacking", function() attacking = z:isAttacking() or z:getTarget() == player end)
      if attacking then S.try("zStagger", function() z:setStaggerBack(true) end) end
    end
  end
end

local function activateNow(player)
  local d = S.data(player)
  local s = R.session(player)
  local level = S.level(d)
  s.work = FW.profile(d).mode == "work"               -- (86) Taller: modo trabajo
  if s.work then s.workFlow, s.workIdle, s.workAcc, s.workNow = 0, 0, 0, false end
  s.active, s.armed, s.overdrive = true, false, false
  s.lastMs = S.realMs()
  s.level = level
  s.tier = S.dilationTier(d, level)
  s.ocStep = nil                                    -- (109) Overclock
  s.eff = R.effectiveTier(s, d)
  -- (139) Deuda de estamina: se congela la resistencia en la marca de ahora y se arrastra la deuda que haya quedado sin pagar
  -- (por ejemplo, si el jugador salio con el implante encendido y volvio).
  if R.debtOn() then
    s.enduranceMark = E.getEndurance(player)
    s.staminaDebt = math.max(d.staminaDebt or 0, s.staminaDebt or 0)
  else
    s.enduranceMark, s.staminaDebt = nil, 0
  end
  -- v0.1.25: encender no suma Carga Neuronal; solo el tiempo de uso (tickActive). v0.1.26: tampoco con cyberpsicosis
  -- (ahí la CN sube al doble de ritmo mientras se usa).
  d.xpSrc = d.xpSrc or {}
  d.xpSrc.nActivations = (d.xpSrc.nActivations or 0) + 1
  SD.activate(player, s.eff)
  if not s.work then evasiveReflex(player) end
  if not s.work then E.sound(player, "SandevistanActivate") end          -- (91) Taller se enciende y apaga muy seguido: sin sonido
  if SandevistanHUD then SandevistanHUD.flash("activate") end
  return true
end

function R.activate(player)
  local ok, reason, arg = R.canActivate(player)
  if not ok then
    if reason then E.halo(player, arg and txt(reason, arg) or txt(reason), 255, 80, 80); E.sound(player, "SandevistanError") end
    return false
  end
  return activateNow(player)
end

---------------------------------------------------------------------------
-- (163) T11: forzar el implante (30 §3.4). Con el implante apagado, mantener la tecla saltea el seguro del aire o del calor y entra
-- directo en Overdrive. Siempre termina en colapso, con la cuenta extra de lo que se forzó (fatiga/prohibición de esprint o quemadura,
-- desgaste y cicatriz térmica sin el colapso gratis del día). Los bloqueos se levantan al recuperar la resistencia o al enfriarse del todo.
---------------------------------------------------------------------------
function R.forceFlags(player)
  local d = S.data(player)
  local flags = {}
  if E.getEndurance(player) < CFG.Stamina.MinToActivate then flags.stamina = true end
  if (d.lockUntilCool and d.heat > 0) or d.heat >= S.heatCap(d) then flags.heat = true end
  return flags
end

-- Devuelve ok, flags, motivo (clave de texto). Sin nada que forzar, ok = false y flags vacío: es el caso normal, no un error.
function R.canForce(player)
  local d = S.data(player)
  local s = R.session(player)
  local F = CFG.Force
  if not (F and F.Enabled) then return false, {}, "IGUI_Sandevistan_Err_ForceOff" end
  if s.fury then return false, {}, "IGUI_Sandevistan_Err_Fury" end                     -- furia total: el implante está trabado
  if FW.profile(d).noOverdrive then return false, {}, "IGUI_Sandevistan_Fw_NoOverdrive" end
  local flags = R.forceFlags(player)
  if not (flags.stamina or flags.heat) then return false, flags end
  local ok, reason, arg = R.canActivate(player, flags)
  if not ok then return false, flags, reason, arg end
  local lk = d.forceLock or {}
  if flags.stamina and lk.stamina then return false, flags, "IGUI_Sandevistan_Err_ForceAir" end
  if flags.heat and lk.heat then return false, flags, "IGUI_Sandevistan_Err_ForceHeat" end
  return true, flags
end

function R.force(player, flags)
  if not activateNow(player) then return false end
  local s = R.session(player)
  s.forced = flags or {}
  s.armed = true
  R.startOverdrive(player)
  E.halo(player, txt("IGUI_Sandevistan_Forced"), 255, 60, 60)
  if SandevistanHUD then SandevistanHUD.flash("forcing") end
  return true
end

---------------------------------------------------------------------------
-- (139) Deuda de estamina (27 §2)
---------------------------------------------------------------------------
-- Mientras el Sandevistan esta encendido la resistencia no baja: en cada tick se vuelve a la marca (s.enduranceMark) y todo lo que
-- el cuerpo gasto (correr, esprintar, golpear, empujar, trepar, tropezar) mas el drenaje del implante se anota como deuda. El juego
-- regenera resistencia con el tiempo: esa regeneracion no sube la resistencia, paga deuda. Al apagar se cobra todo junto
-- (R.applyStaminaDebt) y, si la deuda paso lo que habia, el cuerpo paga el sobregiro: tropiezo y sin esprint un rato.
-- No es un castigo nuevo: es el MISMO gasto movido de lugar. Durante la rafaga no ves el agotamiento; al apagar lo recibis entero.
local function deferredCfg() return CFG.Stamina.Deferred end

function R.debtOn()
  local D = deferredCfg()
  return (D and D.Enabled) and true or false
end

-- Deuda y marca de la sesion (0, nil si no hay sesion activa).
function R.debt(player)
  local s = R.session(player)
  return s.staminaDebt or 0, s.enduranceMark
end

-- Escribe la deuda en el ModData: sobrevive a guardar, cargar y desconectarse sin agregar red (27 §2.6).
local function persistDebt(player, s)
  local d = S.data(player)
  d.staminaDebt = (s.staminaDebt or 0) > 0 and s.staminaDebt or nil
end

-- Un tick con el implante encendido: congela la resistencia en la marca, anota el gasto y deja que la regeneracion pague deuda.
local function tickDebt(player, s, d, drain)
  local mark = s.enduranceMark
  if not mark then
    mark = E.getEndurance(player)
    s.enduranceMark = mark
  end
  local cur = E.getEndurance(player)
  local spent = math.max(0, mark - cur)                    -- lo que gastaron las acciones desde el tick anterior
  local regen = math.max(0, cur - mark)                    -- lo que regenero el juego: paga deuda
  s.staminaDebt = math.max(0, (s.staminaDebt or 0) + spent + (drain or 0) - regen)
  if cur ~= mark then E.setEndurance(player, mark) end     -- el numero que ves no se mueve
  persistDebt(player, s)
end

-- (146) Para Combat: anota ya el gasto que el juego hizo desde el ultimo tick (sin drenaje del implante: ese lo pone tickActive).
function R.syncDebt(player)
  local s = R.session(player)
  if s.active and s.enduranceMark and R.debtOn() then tickDebt(player, s, S.data(player), 0) end
end

-- (146) Reintegro de estamina del golpe (Config.Combat.AttackStaminaRefund) con la deuda activa: se descuenta de la deuda.
function R.refundDebt(player, amount)
  local s = R.session(player)
  if not (s.active and s.enduranceMark) or (amount or 0) <= 0 then return end
  s.staminaDebt = math.max(0, (s.staminaDebt or 0) - amount)
  persistDebt(player, s)
end

-- Sin esprint tras el sobregiro: se usa el estado del juego que ya usan los moodles de agotamiento (moodleCantSprint).
function R.noSprint(player, seconds)
  local s = R.session(player)
  s.noSprintUntilMs = math.max(s.noSprintUntilMs or 0, S.gameMs() + seconds * 1000)
end

function R.tickNoSprint(player, s)
  local untilMs = s.noSprintUntilMs
  if not untilMs then return end
  local on = S.gameMs() < untilMs
  if on ~= s.noSprintOn then
    s.noSprintOn = on
    S.try("cantSprint", function() player:setMoodleCantSprint(on) end)
  end
  if not on then s.noSprintUntilMs = nil end
end

-- Cobra la deuda (27 §2.2): toda junta al apagar. kind = motivo de R.deactivate; "forced" (vehiculo, sueño, muerte, implante
-- arrancado) y "work" (Taller) pagan sin castigo. Si la deuda paso la marca, el sobregiro deja tropiezo (salvo en el corte de
-- emergencia, que ya tropieza) y sin esprint; la opcion Suave del sandbox apaga esos dos.
function R.applyStaminaDebt(player, kind)
  local s = R.session(player)
  local d = S.data(player)
  local D = deferredCfg()
  if R.debtOn() and s.enduranceMark then tickDebt(player, s, d, 0) end      -- el ultimo gasto del cuadro tambien se cobra
  local debt, mark = s.staminaDebt or 0, s.enduranceMark
  s.staminaDebt, s.enduranceMark = 0, nil
  d.staminaDebt = nil
  if debt <= 0 or not mark then return 0 end
  local after = mark - debt
  E.setEndurance(player, math.max(0, after))
  if after >= 0 then return after end
  if not (D and D.Punish) or kind == "forced" or kind == "work" then return after end
  local over = math.min(1, -after / math.max(0.01, D.MaxOverdraft))          -- 0..1 de sobregiro
  if kind ~= "emergency" then E.stagger(player, D.OverdraftStaggerSeconds) end
  local NS = D.NoSprintSeconds
  R.noSprint(player, NS[1] + (NS[2] - NS[1]) * over)
  return after
end

-- La deuda se borra sin pagar (colapso del Overdrive, fin de la furia, muerte): esos caminos ya dejan el cuerpo seco.
function R.clearDebt(player)
  local s = R.session(player)
  s.staminaDebt, s.enduranceMark = 0, nil
  local d = S.data(player)
  if d then d.staminaDebt = nil end
end

-- Al cargar: si quedo deuda anotada (el jugador salio con el implante encendido), se paga sin castigo.
function R.settleDebt(player)
  local d = S.data(player)
  local debt = d.staminaDebt
  if not debt or debt <= 0 then return end
  d.staminaDebt = nil
  E.setEndurance(player, math.max(0, E.getEndurance(player) - debt))
end

-- kind: "manual" | "auto" | "emergency" | "forced" | "work" (Taller suspende el modo trabajo; arg = "threat" | "limit" | "stamina")
function R.deactivate(player, kind, arg)
  local s = R.session(player)
  if not s.active then return end
  if s.fury and kind ~= "forced" then return end     -- furia total: el implante queda trabado hasta que se apague sola
  local d = S.data(player)
  s.active, s.armed, s.overdrive = false, false, false
  s.craveSec = nil                                          -- (180) el uso se corta: la cuenta de 10 s arranca de nuevo
  local wasWork = s.work
  s.work = false
  R.applyStaminaDebt(player, kind)                    -- (139) se cobra toda la deuda junta, sea cual sea el motivo del apagado
  d.lastDeactivateHour = S.worldHours()
  SD.deactivate(player)
  E.athleticRelease(player, s)
  R.flushXP(player, true)
  s.reuseAtMs = S.gameMs() + CFG.ManualCutoff.ReuseDelaySeconds * 1000
  s.ocStep = nil
  if kind == "work" then
    -- (86) Taller: el modo trabajo se suspende solo (amenaza, CN y rechazo altos o (108) sin estamina): sin tropiezo ni rechazo; el motivo sale como aviso
    E.halo(player, txt("IGUI_Sandevistan_Fw_WorkStop_" .. tostring(arg or "limit")), 255, 200, 80)
  elseif kind == "auto" then
    d.lockUntilCool = true
    E.stagger(player, CFG.ThermalCutoff.StaggerSeconds)
    -- la salida segura no castiga con rechazo a la adaptación ideal (sí a nivel bajo)
    local TC = CFG.ThermalCutoff
    d.rejection = math.min(100, d.rejection + S.eventRejection(d, TC.RejectionMin, TC.RejectionMax, TC.RejectionAdaptReduction))
    E.halo(player, txt("IGUI_Sandevistan_ThermalCutoff"), 255, 120, 60)
  elseif kind == "emergency" then
    d.lockUntilCool = true
    E.stagger(player, CFG.Stamina.EmergencyStaggerSeconds)
    E.halo(player, txt("IGUI_Sandevistan_Exhausted"), 255, 200, 80)
  end
  -- v0.1.15: sangrado nasal al apagar con la CN alta (no en apagados forzados por sueño/vehículo)
  local nb = CFG.NeuralLoad.Nosebleed
  if kind ~= "forced" and d.neuralLoad >= nb.MinCN and S.chance(nb.OnDeactivateChance) then
    E.startNosebleed(player, d)
  end
  local quiet = wasWork and (kind == "manual" or kind == "work")          -- (91) Taller se apaga muy seguido: sin sonido (un corte raro, como el forzado, si suena)
  if not quiet then E.sound(player, (kind == "manual" or kind == "work") and "SandevistanDeactivate" or (kind == "forced" and "SandevistanDeactivate" or "SandevistanError")) end
  if SandevistanHUD then SandevistanHUD.flash(kind == "work" and "manual" or kind) end
end

---------------------------------------------------------------------------
-- Overdrive
---------------------------------------------------------------------------
function R.overdriveWindow(player)
  local d = S.data(player)
  return S.overdriveWindow(d, S.level(d))
end

function R.startOverdrive(player)
  local s = R.session(player)
  s.overdrive = true
  s.overdriveUntilMs = S.gameMs() + R.overdriveWindow(player) * 1000
  refreshTier(player, s)
  E.halo(player, txt("IGUI_Sandevistan_Overdrive"), 255, 40, 40)
  E.sound(player, "SandevistanOverdrive")
end

function R.collapse(player)
  local s = R.session(player)
  local d = S.data(player)
  local OD = CFG.Overdrive
  s.active, s.armed, s.overdrive = false, false, false
  s.craveSec = nil                                          -- (180) el uso se corta: la cuenta de 10 s arranca de nuevo
  R.clearDebt(player)                                -- (139) el colapso ya deja el cuerpo seco: la deuda se borra, no se suma un tropiezo
  d.lastDeactivateHour = S.worldHours()
  d.lockUntilCool = true
  s.reuseAtMs = S.gameMs() + CFG.ManualCutoff.ReuseDelaySeconds * 1000
  SD.deactivate(player)
  E.athleticRelease(player, s)
  R.flushXP(player, true)

  -- 1. muerte (solo cyberpsicosis)
  if d.cyberpsychosisActive and S.chance(OD.Cyberpsychosis.DeathChance) then
    E.kill(player)
    return
  end
  -- (163) T11: la cuenta extra de lo que forzaste (si morís, no hay nada que pagar)
  local forced = s.forced
  s.forced = nil
  if forced then
    local F = CFG.Force
    if forced.stamina and F.Stamina then
      E.setEndurance(player, 0)
      R.noSprint(player, F.Stamina.NoSprintSeconds)
      E.addStat(player, "FATIGUE", F.Stamina.Fatigue)
      d.forceLock = d.forceLock or {}
      d.forceLock.stamina = true
      E.halo(player, txt("IGUI_Sandevistan_ForcedAir"), 255, 140, 60)
    end
    if forced.heat and F.Heat then
      E.burn(player, F.Heat.BurnPart)
      d.degradation = math.min(CFG.Extraction.MaxDegradation, (d.degradation or 1) + F.Heat.Wear)
      d.forceLock = d.forceLock or {}
      d.forceLock.heat = true
      E.halo(player, txt("IGUI_Sandevistan_ForcedHeat"), 255, 140, 60)
    end
    local N = rawget(_G, "SandevistanNet")
    if N and N.saveState then pcall(N.saveState, player) end
  end
  -- 2. herida de pecho (nunca destruye el implante)
  local wound = d.cyberpsychosisActive and OD.Cyberpsychosis.ChestWoundChance or OD.ChestWoundChance
  if S.chance(wound) then
    E.hemorrhage(player, "Torso_Upper", "severe")
    E.halo(player, txt("IGUI_Sandevistan_ChestWound"), 255, 40, 40)
  end
  -- 3. Kerenzikov + Overdrive
  local cnMult = 1
  local kere = Kerenzikov.isActive(player)
  if kere then
    -- queda clavado (Effects); a adaptación estable el KO dura hasta la mitad
    E.knockOut(player, S.randRange(OD.Kerenzikov.UnconsciousMinSeconds, OD.Kerenzikov.UnconsciousMaxSeconds)
      * math.max(0, 1 - S.collapseRecoveryReduction(d, OD.Kerenzikov.UnconsciousAdaptReduction)))          -- (123) mas la maestria
    E.setEndurance(player, 0)
    E.damagePart(player, "Torso_Upper", OD.Kerenzikov.ArrhythmiaDamage)
    cnMult = OD.Kerenzikov.NeuralLoadMultiplier
  else
    local rec = math.max(0, 1 - S.collapseRecoveryReduction(d, OD.RecoveryAdaptReduction))          -- más corto con la adaptación y (123) la maestria
    E.stagger(player, OD.StaggerSeconds * rec, true)
    SD.slowPlayer(player, OD.SlowAfter.Seconds * rec, OD.SlowAfter.Factor)           -- se arrastra unos segundos
  end
  s.momentum = 0
  -- 4. consecuencias comunes
  local oldCap = S.heatCap(d)
  local cap = S.overdriveScar(d, S.worldHours(), (forced and forced.heat and CFG.Force.Heat.ScarAlways) or nil)
  d.heat = cap
  d.cooldownMult = OD.CoolingMultiplier
  local V = CFG.Psychosis.Vulnerable
  if V and V.Enabled then d.vulnUntilHour = S.worldHours() + (V.Hours or 0.4) end     -- (180) C06: ventana vulnerable
  if cap < oldCap then E.halo(player, txt("IGUI_Sandevistan_HeatScar", math.floor(cap)), 255, 140, 60) end
  E.setTemperatureAtLeast(player, S.randRange(OD.MinTemp, OD.MaxTemp))
  E.damagePart(player, "Torso_Upper", OD.TorsoDamage)
  E.addPain(player, "Torso_Upper", OD.TorsoPain)
  d.neuralLoad = math.min(CFG.NeuralLoad.Max, d.neuralLoad + S.randRange(OD.NeuralLoadMin, OD.NeuralLoadMax) * cnMult)
  d.rejection = math.min(100, d.rejection + S.eventRejection(d, OD.RejectionMin, OD.RejectionMax, OD.RejectionAdaptReduction))
  E.worldNoise(player, OD.SoundRadius)
  local NB = CFG.NeuralLoad.Nosebleed
  if NB.OnCollapse and d.neuralLoad >= (NB.OnCollapseMinCN or 0) then E.startNosebleed(player, d) end
  E.halo(player, txt("IGUI_Sandevistan_Collapse"), 255, 40, 40)
  E.sound(player, "SandevistanCollapse")
  R.checkThresholds(player)
end

function R.triggerCatastrophicFailure(player, cause)
  local s = R.session(player)
  local d = S.data(player)
  if s.active then
    s.active, s.armed, s.overdrive = false, false, false
    SD.deactivate(player)
    E.athleticRelease(player, s)
  end
  R.applyStaminaDebt(player, "forced")             -- (139) el implante se destruye, pero el cuerpo igual paga lo que gasto (sin castigo)
  d.variant = "destroyed"
  d.rejection = 0
  d.heat = 0
  d.cooldownMult = 1
  d.immuno = {}
  E.hemorrhage(player, "Torso_Upper", cause == "rejection" and "massive" or "severe")
  E.addPain(player, "Torso_Upper", 80)
  E.halo(player, txt("IGUI_Sandevistan_Destroyed"), 255, 0, 0)
  S.log("falla catastrófica: " .. tostring(cause))
end

---------------------------------------------------------------------------
-- XP
---------------------------------------------------------------------------
-- src: "time" | "kill" | "otro" (ver S.addAdaptXP). xpPending es el total; xpBy el desglose por fuente.
function R.addPendingXP(player, amount, src)
  local s = R.session(player)
  s.xpPending = s.xpPending + amount
  s.xpBy = s.xpBy or {}
  local k = src or "otro"
  s.xpBy[k] = (s.xpBy[k] or 0) + amount
end

function R.flushXP(player, force)
  local s = R.session(player)
  local now = S.realMs()
  if not force and now - s.lastFlushMs < CFG.XP.FlushSeconds * 1000 then return end
  s.lastFlushMs = now
  if s.xpPending <= 0 then s.xpBy = {}; return end
  local d = S.data(player)
  local before = S.level(d)
  local any = false
  for src, amt in pairs(s.xpBy or {}) do
    if amt > 0 then any = true; S.addAdaptXP(d, amt, src) end
  end
  if not any then S.addAdaptXP(d, s.xpPending, "otro") end
  s.xpPending, s.xpBy = 0, {}
  S.syncPerk(player)
  local after = S.level(d)
  if after > before then
    E.halo(player, txt("IGUI_Sandevistan_LevelUp", after), 80, 220, 255)
  end
  local rank = S.mastery(d)                                        -- (123) maestria: aviso de nivel 11..15 (Beyond Ten no lo da: la escribe el mod)
  if rank > (s.masteryShown or rank) then
    E.halo(player, txt("IGUI_Sandevistan_MasteryUp", S.level(d) + rank), 255, 170, 50)
  end
  s.masteryShown = rank
end

---------------------------------------------------------------------------
-- Umbrales (cyberpsicosis, rechazo 100)
---------------------------------------------------------------------------
function R.checkThresholds(player)
  local d = S.data(player)
  if d.neuralLoad >= S.neuralThreshold(d, CFG.NeuralLoad.Zones.cyberpsychosis) and not d.cyberpsychosisActive then
    d.cyberpsychosisActive = true
    E.halo(player, txt("IGUI_Sandevistan_Cyberpsychosis"), 200, 0, 0)
  end
  if S.hasWorkingImplant(d) and d.rejection >= 100 then
    R.triggerCatastrophicFailure(player, "rejection")
  end
end

---------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------
-- (180) C08: segundos de uso de la sesion. Al llegar a UseSeconds, la abstinencia leve se reinicia (en Taller cuenta la mitad).
function R.craveTick(player, s, d, dt, work)
  local c = CFG.NeuralLoad.Craving
  if not (c and c.Enabled) then return end
  s.craveSec = (s.craveSec or 0) + dt * (work and (c.WorkUseMult or 0.5) or 1)
  if s.craveSec >= (c.UseSeconds or 10) then
    s.craveSec = 0
    d.lastSatisfiedHour = S.worldHours()
    local N = rawget(_G, "SandevistanNet")
    if N and N.saveState then pcall(N.saveState, player) end
  end
end

local function tickActive(player, s, d, dt)
  local level = s.level or S.level(d)
  local now = S.gameMs()          -- (127) plazos (Overdrive) en el reloj de juego
  local prof = FW.profile(d)
  local FC = rawget(_G, "SandevistanFirmwareClient")
  local live = FC and FC.live(player, d, dt) or nil          -- (83) factores que dependen del movimiento (Centinela)
  local work = s.work and prof.mode == "work"                -- (86) Taller: modo trabajo

  -- apagados forzados
  if player:getVehicle() or player:isAsleep() or E.isUnconscious(player) or player:isDead() then
    R.deactivate(player, "forced"); return
  end
  if not S.hasWorkingImplant(d) then R.deactivate(player, "forced"); return end

  -- (86) modo trabajo: flujo, CN y rechazo altos y amenazas cercanas (FirmwareClient.workTick); puede suspenderlo
  local workCn = 1
  if work and FC then
    local stop, why = FC.workTick(player, d, s, dt)
    if stop then R.deactivate(player, "work", why); return end
    workCn = FC.workCnMult(d, s)
  end

  if not work then E.athleticGuard(player, s, d) end

  -- Heat
  if not s.overdrive then
    local before = d.heat
    local heatMult = Kerenzikov.isActive(player) and CFG.Kerenzikov.HeatGainMult or 1      -- sinergia: con Kerenzikov el Heat sube menos
    if live then heatMult = heatMult * live.heat end
    if work then heatMult = heatMult * CFG.Firmware.Work.CostMult end                      -- (86) Heat por segundo x0,15 y se enfria activo
    heatMult = heatMult * S.ambientHeatMult(player)                                        -- (138j) el ambiente tambien alarga un poco la rafaga
    local cap = S.heatCap(d)
    local gross = S.heatPerSecond(d, level) * heatMult * dt
    local gain = gross
    if work then gain = gain - S.coolPerSecond(d, level) * CFG.Firmware.Work.ActiveCoolFraction / prof.thermalMass * dt
      * S.totalCoolMult(player, 1) end                                                    -- (138i) el ambiente tambien enfria trabajando
    d.heat = math.max(0, math.min(cap, d.heat + gain))
    -- (138i) El implante caliente devuelve el calor al cuerpo: lo seca (0..100 de wetness). Con el Sandi encendido la ropa y el cuerpo se secan.
    local AC = CFG.AmbientCooling
    if AC and AC.Enabled and gross > 0 then S.dryBody(player, gross * (AC.Dry.BodyPerHeat or 0)) end
    local w = (CFG.Sound and CFG.Sound.HeatWarnAt or 80) * cap / 100          -- el aviso escala con el tope
    if before < w and d.heat >= w and not S.senseOff(d) then E.sound(player, "SandevistanHeatWarn") end   -- (180) Filtro: sin aviso de Heat
  end

  -- Stamina x el perfil ((108) Taller x0,2: trabajo liviano). Sin aire, el modo trabajo se suspende sin castigo; el combate corta de emergencia
  local drain = S.staminaDrainPerSecond(level, E.isHeavilyEncumbered(player), d) * prof.stamina          -- (123) con d: la maestria
  if R.debtOn() then
    -- (139) Deuda: la resistencia no baja. Se anota el drenaje del implante y lo que gastaron las acciones; sin aire, el corte de
    -- emergencia mira la deuda (lo que habia al encender + MaxOverdraft).
    tickDebt(player, s, d, drain * dt)
    if s.staminaDebt >= s.enduranceMark + CFG.Stamina.Deferred.MaxOverdraft and not s.overdrive then
      if work then R.deactivate(player, "work", "stamina"); return end
      -- (163) D7: armado, el límite del aire entra en Overdrive en vez de cortar; sin armar, el corte de emergencia de siempre
      if s.armed and not prof.noOverdrive and not (d.forceLock and d.forceLock.stamina) then
        s.forced = s.forced or {}; s.forced.stamina = true
        R.startOverdrive(player)
      else
        R.deactivate(player, "emergency"); return
      end
    end
  else
    E.setEndurance(player, E.getEndurance(player) - drain * dt)
    if E.getEndurance(player) < CFG.Stamina.ExhaustionCutoff and not s.overdrive then
      if work then R.deactivate(player, "work", "stamina"); return end
      if s.armed and not prof.noOverdrive and not (d.forceLock and d.forceLock.stamina) then
        s.forced = s.forced or {}; s.forced.stamina = true
        R.startOverdrive(player)
      else
        R.deactivate(player, "emergency"); return
      end
    end
  end

  -- CN por uso
  local v = S.variantCfg(d)
  local useMult = d.cyberpsychosisActive and CFG.NeuralLoad.CyberpsychosisUseMultiplier or 1
  if d.traits and d.traits.psycho then useMult = useMult * CFG.Traits.PsychoNeuralMult end
  if d.cyberScar then useMult = useMult * CFG.NeuralLoad.Remission.ScarUseMult end          -- cicatriz de una cyberpsicosis superada
  useMult = useMult * S.immunoNeuralMultiplier(d) * S.adaptUseMultiplier(d) * FW.profile(d).cn * workCn          -- (82) firmware, (86) modo trabajo
  useMult = useMult * S.stopgapCNMult(d)                                                                            -- (162) T09: betabloqueante
  d.neuralLoad = math.min(CFG.NeuralLoad.Max, d.neuralLoad + CFG.NeuralLoad.PerSecondActive * v.neuralLoadMultiplier * useMult * dt)

  R.craveTick(player, s, d, dt, work)                          -- (180) C08: uso sostenido = abstinencia calmada

  if not work then
    -- Impulso: sube con el uso continuo y mejora un poco carrera y ataque
    local before = s.momentum or 0
    s.momentum = math.min(1, before + dt * prof.momentumRamp / CFG.Momentum.RampSeconds)          -- (110) Reactor: inercia
    if s.momentum ~= before then refreshTier(player, s) end

    -- XP (sin XP de adaptacion por tiempo en el modo trabajo)
    R.addPendingXP(player, CFG.XP.PerSecondActive * dt * (live and live.xpTime or 1) * FW.profile(d).xpTime, "time")
    d.xpSrc = d.xpSrc or {}
    d.xpSrc.activeSeconds = (d.xpSrc.activeSeconds or 0) + dt
    R.flushXP(player, false)
  end

  -- (109) Overclock: el bono sigue al Heat; el tramo se vuelve a armar cada 5 % de cambio
  if prof.overclock then
    local step = math.floor(FW.overclockFactor(d) * 20)
    if step ~= s.ocStep then s.ocStep = step; refreshTier(player, s) end
  end

  -- Límite térmico
  if s.overdrive then
    if now >= s.overdriveUntilMs then R.collapse(player); return end
  elseif d.heat >= S.heatCap(d) then
    if s.armed and not prof.noOverdrive then R.startOverdrive(player) else R.deactivate(player, "auto"); return end
  end

  R.checkThresholds(player)
end

local function tickCooling(player, s, d, dt)
  if d.heat <= 0 then d.cooldownMult = 1; return end
  local level = S.level(d)
  local FC = rawget(_G, "SandevistanFirmwareClient")
  local extra = FC and FC.coolMult(player, d, s) or 1        -- (108) Camara criogenica x1,75
  -- (138i) El ambiente (frio, mojado, viento) multiplica el enfriamiento, con tope conjunto con la criogenica (x2,0)
  local total = S.totalCoolMult(player, extra)
  local removed = S.coolPerSecond(d, level) * dt * total
  d.heat = math.max(0, d.heat - removed)          -- (127) dt ya viene en segundos de juego
  -- (138i) Evaporacion: mientras el implante se enfria, el agua del cuerpo se gasta (el agua es un recurso, no un enfriamiento gratis)
  local AC = CFG.AmbientCooling
  if AC and AC.Enabled and removed > 0 then S.dryBody(player, removed * (AC.Dry.EvapPerCool or 0)) end
  if d.heat <= 0 then d.heat = 0; d.cooldownMult = 1 end
end

-- Segundos de juego por segundo real (S.timeScale: 1, 5, 20 o 40 en un jugador; 0 en pausa). (127) Antes devolvia el BOTON de velocidad (1..4): a x40 el
-- enfriamiento corria x4. Ahora todo el tick del implante (encendido y apagado) usa segundos de juego (R.onTick).
function R.speedFactor() return S.timeScale() end

-- Con el rechazo alto no se puede dormir (dolor): se despierta al personaje.
local lastWakeMs = {}
local function checkSleep(player, d)
  if not S.hasWorkingImplant(d) or not player:isAsleep() then return end
  if (d.rejection or 0) < S.stopgapSleepLimit(d) then return end                  -- (162) T09: con somnífero deja dormir hasta AllowSleepUpTo
  S.try("forceAwake", function() player:forceAwake() end)
  local now, idx = S.realMs(), player:getPlayerNum()
  if now - (lastWakeMs[idx] or -10000) > 5000 then
    lastWakeMs[idx] = now
    E.addPain(player, "Torso_Lower", 20)
    E.halo(player, txt("IGUI_Sandevistan_WakeRejection"), 255, 80, 80)
  end
end

function R.onTick()
  local paused = isGamePaused and isGamePaused()
  local scale = S.timeScale()                         -- (127) segundos de juego por segundo real
  S.gameMs()                                          -- avanza el reloj de juego del mod en cada tick
  for idx = 0, getNumActivePlayers() - 1 do
    local player = getSpecificPlayer(idx)
    if player and not player:isDead() then
      local s = R.session(player)
      local now = S.realMs()
      local dt = math.min((now - s.lastMs) / 1000, 0.25)
      s.lastMs = now
      if paused then dt = 0 end
      dt = dt * scale                                      -- (127) de aca en adelante, segundos de juego (antes reales: con el avance rapido no aceleraba)
      local d = S.data(player)
      checkSleep(player, d)
      -- (163) T11: los bloqueos de forzar se levantan solos (con la resistencia recuperada o el implante frío)
      if d.forceLock then
        if d.forceLock.stamina and E.getEndurance(player) >= CFG.Force.Stamina.UnlockAt then d.forceLock.stamina = nil end
        if d.forceLock.heat and d.heat <= 0 then d.forceLock.heat = nil end
        if not (d.forceLock.stamina or d.forceLock.heat) then d.forceLock = nil end
      end
      local PS = rawget(_G, "SandevistanPsychosis")
      if PS then                                             -- cyberpsicosis por etapas (Psychosis.lua)
        local t0 = S.clockMs()
        PS.tick(player, s, d, dt)
        S.perfAdd("Runtime > Psychosis.tick", S.clockMs() - t0)
      end
      if now - (s.lastPerkSyncMs or 0) > 2000 then s.lastPerkSyncMs = now; S.syncPerk(player) end   -- cambios de la skill por comandos
      if not paused then Kerenzikov.tick(player, math.min((now - (s.kereMs or now)) / 1000, 1) * scale) end     -- (108) Black Lace: duracion en segundos (127: de juego) y sin dolor
      s.kereMs = now
      if S.hasAnyImplant(d) and dt > 0 then
        if s.active then tickActive(player, s, d, dt) else
          tickCooling(player, s, d, dt)
          if (s.momentum or 0) > 0 then s.momentum = math.max(0, s.momentum - dt * FW.profile(d).momentumDecay / CFG.Momentum.DecaySeconds) end     -- (110) Reactor: inercia
        end
      end
      Kerenzikov.markEndurance(player)                       -- Black Lace: despues del gasto del implante, para medir solo el de las acciones
      R.tickNoSprint(player, s)                              -- (139) sobregiro: sin esprint un rato despues de pagar la deuda
    end
  end
  local t0 = S.clockMs()
  SD.tick()
  S.perfAdd("Runtime > Slowdown.tick", S.clockMs() - t0)
  if SandevistanSlowAudio then SandevistanSlowAudio.tick() end          -- (126) voces de los zombis mas bajas con la dilatacion
end

Events.OnTick.Add(S.safe("Runtime.OnTick", R.onTick))
Events.OnPlayerDeath.Add(S.safe("Runtime.OnPlayerDeath", function(player)
  local idx = player:getPlayerNum()
  local s = R.sessions[idx]
  if s and s.active then
    s.active = false
    SD.deactivate(player)
  end
  R.clearDebt(player)                                -- (139) muerto: la deuda se borra
  -- limpiar todo lo que apunta al jugador muerto: si algo sigue tocando su posición o su estado al reaparecer,
  -- el juego puede quedar con un jugador "fantasma" (pantalla negra / "Coop player already exists")
  R.sessions[idx] = nil
  SD.playerSlow[idx] = nil
  SD.active[idx] = nil
  SD.boost[idx] = nil
  E.timers[idx] = nil
end))

-- Un personaje nuevo en el mismo índice (tras morir) no hereda el estado en memoria del anterior (Impulso, armado...).
Events.OnCreatePlayer.Add(S.safe("Runtime.OnCreatePlayer", function(idx)
  if idx ~= nil then R.sessions[idx] = nil end
end))

Events.OnGameStart.Add(S.safe("Runtime.OnGameStart", function()
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p then S.syncPerk(p); R.settleDebt(p) end         -- (139) deuda que quedo anotada de la sesion anterior
  end
end))

return R
