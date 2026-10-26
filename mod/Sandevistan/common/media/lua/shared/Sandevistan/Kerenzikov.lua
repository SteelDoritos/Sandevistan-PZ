-- Sandevistan / Kerenzikov: sistema independiente. El Sandevistan solo consulta isActive().
require "Sandevistan/Core"

local CFG = SandevistanConfig
local S = Sandevistan

Kerenzikov = {}
Kerenzikov.endMark = {}   -- [playerNum] = resistencia al final del tick anterior (despues del gasto del implante); no se guarda

-- (108) Como en Cyberpunk 2077: la duracion se cuenta en SEGUNDOS REALES (k.activeSeconds, lo que queda; no corre con el juego en pausa), no en horas de juego.
function Kerenzikov.isActive(player)
  return (S.kdata(player).activeSeconds or 0) > 0
end

function Kerenzikov.isCrashing(player)
  local k = S.kdata(player)
  return k.crashUntilHour > S.worldHours()
end

-- Recupera escalones de tolerancia por días limpios y calcula la duración efectiva.
function Kerenzikov.effectiveMultiplier(k, now)
  local cleanDays = math.floor((now - k.lastDoseHour) / CFG.Kerenzikov.ToleranceWindowHours)
  if cleanDays > 0 then k.toleranceSteps = math.max(0, k.toleranceSteps - cleanDays) end
  return math.max(CFG.Kerenzikov.ToleranceFloor, 1 - CFG.Kerenzikov.ToleranceStep * k.toleranceSteps)
end

-- Devuelve la duración aplicada en segundos reales.
function Kerenzikov.take(player, crafted)
  local k = S.kdata(player)
  local now = S.worldHours()
  -- recuperar escalones por días limpios; luego, si esta dosis cae dentro de la ventana, sube la tolerancia
  Kerenzikov.effectiveMultiplier(k, now)
  if now - k.lastDoseHour < CFG.Kerenzikov.ToleranceWindowHours then
    k.toleranceSteps = k.toleranceSteps + 1
  end
  local mult = math.max(CFG.Kerenzikov.ToleranceFloor, 1 - CFG.Kerenzikov.ToleranceStep * k.toleranceSteps)
  local base = crafted and CFG.Kerenzikov.crafted.durationSeconds or CFG.Kerenzikov.military.durationSeconds
  local dur = base * mult
  k.activeSeconds = (k.activeSeconds or 0) + dur
  k.isCrafted = crafted and true or false
  Kerenzikov.holdFatigue(player, k)
  k.crashUntilHour = -1                     -- (108) el bajon del casero arranca cuando se termina el efecto (Kerenzikov.tick), no al tomarlo
  k.lastDoseHour = now
  return dur
end

-- (119) Mientras dura te saca el sueño: el cansancio que tenias al tomarlo se guarda (k.fatigueDebt) y queda en 0; al terminar vuelve, sumado a lo que
-- se haya juntado mientras tanto. Una segunda dosis con el efecto activo suma lo poco que se junto desde la primera.
function Kerenzikov.holdFatigue(player, k)
  local E = rawget(_G, "SandevistanEffects")
  if not E or CFG.Kerenzikov.HoldsFatigue == false then return end
  local f = E.getStat(player, "FATIGUE") or 0
  k.fatigueDebt = (k.fatigueDebt or 0) + f
  if f > 0 then E.setStat(player, "FATIGUE", 0) end
end

-- (119) Al terminar el efecto: vuelve el cansancio guardado y, si era el casero, el bajon de golpe (una sola vez, no se sostiene): el cansancio sube a
-- crashFatigue y la estamina baja a crashEndurance; despues la estamina se recupera sola, como siempre. El moodle del bajon queda crashHours.
function Kerenzikov.finish(player, k)
  local E = SandevistanEffects
  if k.fatigueDebt and k.fatigueDebt > 0 then E.setStat(player, "FATIGUE", math.min(1, E.getStat(player, "FATIGUE") + k.fatigueDebt)) end
  k.fatigueDebt = nil
  if k.isCrafted then
    local c = CFG.Kerenzikov.crafted
    k.crashUntilHour = S.worldHours() + c.crashHours
    if E.getStat(player, "FATIGUE") < c.crashFatigue then E.setStat(player, "FATIGUE", c.crashFatigue) end
    if E.getEndurance(player) > c.crashEndurance then E.setEndurance(player, c.crashEndurance) end
  end
end

-- (108) Un tick con el efecto activo (Runtime.onTick, dt en segundos reales; 0 en pausa): descuenta la duracion, saca TODO el dolor y, al terminarse el
-- casero, arranca el bajon. El juego recalcula el dolor en cada update y solo lo sube de a poco (1/500 de la diferencia por update): ponerlo en 0 en cada tick lo
-- mantiene en 0 sin que el moodle parpadee; al terminar el efecto el dolor de las heridas vuelve solo.
-- Ademas: panico y estres en 0 (CalmMind) y la resistencia que gastaron las acciones desde el tick anterior se devuelve en parte (StaminaCostMult). La marca
-- la pone Runtime al final del tick (Kerenzikov.markEndurance), despues del gasto del Sandevistan, asi lo que falta ahora es solo lo del motor (correr,
-- golpear, empujar...). Una caida mayor a StaminaMaxDropPerTick no es una accion (el mod la puso en 0, por ejemplo): no se devuelve.
function Kerenzikov.tick(player, dt)
  local k = S.kdata(player)
  if (k.activeSeconds or 0) <= 0 then return end
  k.activeSeconds = math.max(0, k.activeSeconds - dt)
  local K, E = CFG.Kerenzikov, SandevistanEffects
  if K.PainFree then E.setStat(player, "PAIN", 0) end
  if K.CalmMind then E.setStat(player, "PANIC", 0); E.setStat(player, "STRESS", 0) end
  local mark = Kerenzikov.endMark[player:getPlayerNum()]
  local mult = K.StaminaCostMult or 1
  if mark and mult < 1 then
    local now = E.getEndurance(player)
    local spent = mark - now
    if spent > 0 and spent <= (K.StaminaMaxDropPerTick or 0.15) then E.setEndurance(player, now + spent * (1 - mult)) end
  end
  if k.activeSeconds <= 0 then Kerenzikov.finish(player, k) end
end

-- Runtime.onTick, al final de cada tick del jugador (despues del gasto del Sandevistan): la marca contra la que se mide el gasto de las acciones.
function Kerenzikov.markEndurance(player)
  local idx = player:getPlayerNum()
  if Kerenzikov.isActive(player) then Kerenzikov.endMark[idx] = SandevistanEffects.getEndurance(player)
  else Kerenzikov.endMark[idx] = nil end
end

-- (108) Cada minuto de juego con el efecto activo (Periodic.minuteTick): recupera entre StaminaRegenPerMinute[1] y [2] de resistencia (5 a 10 %).
function Kerenzikov.minuteRegen(player)
  if not Kerenzikov.isActive(player) then return 0 end
  local r = CFG.Kerenzikov.StaminaRegenPerMinute
  local add = r[1] + (r[2] - r[1]) * ZombRandFloat(0, 1)
  local E = SandevistanEffects
  E.setEndurance(player, E.getEndurance(player) + add)
  return add
end

-- Nivel del moodle de crash (0–4) según el tiempo restante.
function Kerenzikov.crashLevel(player)
  local k = S.kdata(player)
  local now = S.worldHours()
  if k.crashUntilHour <= now or (k.activeSeconds or 0) > 0 then return 0 end
  local frac = (k.crashUntilHour - now) / CFG.Kerenzikov.crafted.crashHours
  return math.max(1, math.min(4, math.ceil(frac * 4)))
end

return Kerenzikov
