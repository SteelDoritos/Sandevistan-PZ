-- Sandevistan / HitBench (134): banco de golpes de Debug. Por cada arma y cada CombatSpeed fija pega N golpes a un zombi quieto delante y anota, golpe a golpe,
-- si llego el cuadro de impacto (OnWeaponSwingHitPoint), si le dio al zombi (OnWeaponHitCharacter), a que distancia y angulo, y la vida antes y despues
-- (con la perdida que esperaba Combat.vanillaLoss + el bono del Sandi). Al final escribe Zomboid/Lua/Sandevistan_hitbench.txt con la velocidad mas alta
-- que todavia registra el 95 % de los golpes por arma: el numero para Config.Combat.MaxCombatSpeed. Solo en partida local (en MP el anti-cheat expulsa).
-- Los golpes los dispara el propio banco (IsoPlayer.pressedAttack, como el clic); si el motor no arranca ninguno en 1,5 s pasa a modo manual: vos mantenes
-- apretado el ataque y el banco cuenta y cambia de velocidad solo.
-- (134d) Apuñalamiento critico del cuchillo (AnimSets player/melee/1handed/KnifeCrit.xml): hereda <m_SpeedScale>CombatSpeed</m_SpeedScale> de KnifeDefault
-- (x0,8 por la mezcla), el impacto cae al 35 % en vez del 25 %, el motor le suma x1,1 a la velocidad (CombatManager.pressedAttack) y mata siempre (daño
-- x1000 con ZombieHitReaction=KnifeDeath); a veces deja el cuchillo clavado en la mandibula (applyKnifeDeathEffect: lo saca de la mano). El banco anota
-- cada apuñalada y cuanto duro el golpe, la deja fuera de la cuenta del daño, le da mas tiempo y hace una pasada con el critico forzado en los cuchillos.
require "Sandevistan/Core"
require "Sandevistan/Runtime"
require "Sandevistan/Combat"

local CFG = SandevistanConfig
local S = Sandevistan
local R = SandevistanRuntime
local C = SandevistanCombat

SandevistanHitBench = {}
local HB = SandevistanHitBench

HB.FILE = "Sandevistan_hitbench.txt"
HB.WEAPONS = { "Base.KitchenKnife", "Base.HuntingKnife", "Base.BaseballBat", "Base.Crowbar", "Base.Axe", "Base.Machete", "Base.Katana",
               "Base.SpearCrafted", "Base.Sledgehammer" }
HB.SPEEDS = { 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0 }
HB.SWINGS = 8                 -- golpes por arma y velocidad
HB.GOOD = 0.95                -- fraccion de golpes que tienen que darle al zombi para que la velocidad cuente como buena
HB.DIST = 0.6                 -- el zombi va a esta fraccion entre el alcance minimo y el maximo del arma
HB.START_MS = 1500            -- sin OnWeaponSwing en este tiempo despues de pressedAttack -> modo manual
HB.SWING_MS = 4000            -- un golpe que no termina en este tiempo se cierra como perdido
HB.EQUIP_MS = 600             -- espera despues de cambiar de arma (el modelo de la mano tiene que cargar: isWeaponReady)
HB.HEALTH = 100               -- vida del zombi de prueba (que no muera; la perdida se mide igual)
HB.STAB_WEAPONS = { "Base.KitchenKnife", "Base.HuntingKnife" }   -- (134d) pasada extra con el apuñalamiento critico forzado
HB.STAB_MS = 8000             -- (134d) la apuñalada es mas larga: tiempo para darla por perdida

local run = nil

function HB.running() return run ~= nil end
function HB.phaseName()
  if not run then return "-" end
  local st = run.plan[run.step]
  if not st then return "-" end
  return string.format("%s x%.1f %d/%d%s", st.short, st.speed, HB.realSwings(st), HB.SWINGS, run.manual and " (manual)" or "")
end

local function say(p, t) pcall(function() p:Say(t) end) end
local function shortName(full) return (string.gsub(full, "^.*%.", "")) end

-- (134b) Un empujon no es un golpe con el arma (el motor lo elige si el jugador no esta apuntando; pega con las manos y sin daño): no cuenta para la
-- velocidad. En la primera corrida la lanza, el cuchillo de caza y la maza salian "buenos hasta x5" porque casi todo eran empujones.
function HB.realSwings(st)
  local n = 0
  for _, w in ipairs(st.swings) do if not w.shove then n = n + 1 end end
  return n
end

-- Resumen de un paso: golpes, cuadros de impacto, golpes al zombi y la perdida observada contra la esperada.
function HB.summarize(st)
  local r = { swings = 0, shoves = 0, impact = 0, hit = 0, noImpact = 0, noTarget = 0, obs = 0, exp = 0, nDmg = 0, stabs = 0, jaws = 0,
              msNormal = 0, nNormal = 0, msStab = 0, nStab = 0, vObs = 0, vExp = 0, critKills = 0 }
  for _, w in ipairs(st.swings) do
    if w.shove then r.shoves = r.shoves + 1 else
    r.swings = r.swings + 1
    if w.hit then r.hit = r.hit + 1 end
    if w.impact or w.hit then r.impact = r.impact + 1 end
    if not w.impact and not w.hit then r.noImpact = r.noImpact + 1
    elseif not w.hit then r.noTarget = r.noTarget + 1 end
    if w.stab then r.stabs = r.stabs + 1 end
    if w.jaw then r.jaws = r.jaws + 1 end
    if w.critKill then r.critKills = r.critKills + 1 end
    if w.durMs and w.hit then
      if w.stab then r.msStab, r.nStab = r.msStab + w.durMs, r.nStab + 1 else r.msNormal, r.nNormal = r.msNormal + w.durMs, r.nNormal + 1 end
    end
    if w.hit and not w.stab and not w.critKill and w.lossObs and w.lossExp and w.lossExp > 0 then r.obs = r.obs + w.lossObs; r.exp = r.exp + w.lossExp; r.nDmg = r.nDmg + 1
      if (w.vanilla or 0) > 0 then r.vObs, r.vExp = r.vObs + w.lossObs - (w.extra or 0), r.vExp + w.vanilla end   -- (134d) la parte del motor sola
    end
    end
  end
  r.rate = r.swings > 0 and r.hit / r.swings or 0
  r.ratio = r.exp > 0 and r.obs / r.exp or nil
  r.vRatio = r.vExp > 0 and r.vObs / r.vExp or nil
  r.avgNormal = r.nNormal > 0 and r.msNormal / r.nNormal or nil
  r.avgStab = r.nStab > 0 and r.msStab / r.nStab or nil
  return r
end

-- Por arma: la velocidad mas alta tal que ella y todas las de abajo registran >= HB.GOOD (la primera que falla corta).
function HB.maxGood(steps)
  local best, broke = nil, nil
  for _, st in ipairs(steps) do
    local r = HB.summarize(st)
    if r.swings > 0 then
      if r.rate >= HB.GOOD and not broke then best = st.speed
      elseif r.rate < HB.GOOD and not broke then broke = st.speed end
    end
  end
  return best, broke
end

-- (134d) Apuñalada contra golpe normal, por cuchillo y velocidad (juntando los criticos naturales y los forzados): cuanto duran y si registran. Si la
-- apuñalada se acorta al subir la velocidad igual que el golpe normal, el Sandi tambien la acelera.
function HB.stabLines(plan)
  local L, rows, order = {}, {}, {}
  for _, st in ipairs(plan) do
    local r = HB.summarize(st)
    local key = st.full .. "|" .. st.speed
    local row = rows[key]
    if not row then row = { name = shortName(st.full), speed = st.speed, msN = 0, nN = 0, msS = 0, nS = 0, stabs = 0, tried = 0, hitS = 0 }; rows[key] = row; order[#order + 1] = row end
    row.msN, row.nN, row.msS, row.nS = row.msN + r.msNormal, row.nN + r.nNormal, row.msS + r.msStab, row.nS + r.nStab
    row.stabs = row.stabs + r.stabs
    if st.stab then row.tried, row.hitS = row.tried + r.swings, row.hitS + r.hit end
  end
  local any = false
  for _, row in ipairs(order) do if row.stabs > 0 or row.tried > 0 then any = true end end
  if not any then return L end
  L[#L + 1] = "== apunalamiento critico del cuchillo ==  arma velocidad: golpe normal ms / apunalada ms (cuantas), y con el critico forzado: al zombi / intentos"
  for _, row in ipairs(order) do
    if row.stabs > 0 or row.tried > 0 then
      L[#L + 1] = string.format("%-14s x%.1f  normal %s / apunalada %s (%d)%s", row.name, row.speed,
        row.nN > 0 and string.format("%d ms", math.floor(row.msN / row.nN + 0.5)) or "-",
        row.nS > 0 and string.format("%d ms", math.floor(row.msS / row.nS + 0.5)) or "-", row.stabs,
        row.tried > 0 and string.format("  forzado %d / %d", row.hitS, row.tried) or "")
    end
  end
  L[#L + 1] = ""
  return L
end

function HB.buildLines(res)
  local L = {}
  local function add(s) L[#L + 1] = s end
  add("Sandevistan - banco de golpes (build " .. tostring(CFG.Build) .. ")")
  add(string.format("modo: %s | implante: %s | %d golpes por paso | bueno = %d %% al zombi | tope actual MaxCombatSpeed = %s",
    res.manual and "manual (ataque apretado)" or "automatico (pressedAttack)", res.implant and "encendido" or "apagado", HB.SWINGS,
    math.floor(HB.GOOD * 100 + 0.5), tostring(CFG.Combat.MaxCombatSpeed)))
  if res.cancelled then add("CANCELADO: " .. tostring(res.cancelled)) end
  add("")
  add("== velocidad maxima con golpes registrados, por arma ==")
  local byWeapon, order = {}, {}
  for _, st in ipairs(res.plan) do
    if not byWeapon[st.short] then byWeapon[st.short] = {}; order[#order + 1] = st.short end
    table.insert(byWeapon[st.short], st)
  end
  local worst = nil
  for _, name in ipairs(order) do
    local best, broke = HB.maxGood(byWeapon[name])
    if best and (not worst or best < worst) then worst = best end
    add(string.format("%-14s maxima buena %s%s", name, best and string.format("x%.1f", best) or "ninguna",
      broke and string.format(" (empieza a fallar en x%.1f)", broke) or ""))
  end
  add(worst and string.format("todas las armas: hasta x%.1f (comparar con MaxCombatSpeed %s)", worst, tostring(CFG.Combat.MaxCombatSpeed)) or "todas las armas: sin datos")
  add("")
  for _, l in ipairs(HB.stabLines(res.plan)) do add(l) end
  add("== por paso ==  golpes / impacto / al zombi / sin impacto / impacto sin blanco / perdida observada / esperada (empujones aparte, zombi nuevo por paso,")
  add("                 apunaladas fuera de la cuenta del dano: matan siempre; motor = la parte del motor sola, lo del Sandi se suma tal cual)")
  for _, st in ipairs(res.plan) do
    local r = HB.summarize(st)
    if r.swings > 0 then
      add(string.format("%-14s x%.1f  %2d  %2d  %2d  %2d  %2d  %s%s%s", st.short, st.speed, r.swings, r.impact, r.hit, r.noImpact, r.noTarget,
        r.ratio and string.format("%.3f / %.3f (x%.2f, motor x%.2f)", r.obs / r.nDmg, r.exp / r.nDmg, r.ratio, r.vRatio or 0) or "-",
        r.shoves > 0 and string.format("  (+%d empujones)", r.shoves) or "", st.rearmed and string.format("  (arma re-equipada %d)", st.rearmed) or "")
        .. (r.stabs > 0 and string.format("  (%d apunaladas%s)", r.stabs, r.jaws > 0 and string.format(", %d clavadas", r.jaws) or "") or "")
        .. (r.critKills > 0 and string.format("  (%d criticos que matan)", r.critKills) or "")
        .. (st.stab and r.stabs == 0 and (r.hit > 0 and "  (el motor no acepto el critico forzado)" or "  (ningun golpe llego al zombi)") or ""))
    elseif st.skipped then
      add(string.format("%-14s x%.1f  salteado: el golpe no arranco", st.short, st.speed))
    end
  end
  add("")
  add("== golpe a golpe ==  arma velocidad n: CombatSpeed real, impacto, al zombi, distancia, angulo, vida antes > despues, perdida esperada (motor + Sandi x mult), duracion")
  for _, st in ipairs(res.plan) do
    for i, w in ipairs(st.swings) do
      add(string.format("%s x%.1f %d: %s%scs %.2f %s %s d %.2f ang %d vida %.3f > %s esp %s%s%s", st.short, st.speed, i, w.shove and "EMPUJON " or "",
        w.stab and "APUNALADA " or "", w.cs or 0,
        w.impact and "IMP" or "imp-", w.hit and "HIT" or "hit-", w.dist or 0, math.floor((w.angle or 0) + 0.5), w.hp0 or 0,
        w.hp1 and string.format("%.3f", w.hp1) or "-",
        w.stab and "mata (x1000)" or w.lossExp and string.format("%.3f (%.3f + %.3f x%.1f)", w.lossExp, w.vanilla or 0, w.extra or 0, w.mult or 1) or "-",
        w.durMs and string.format(" %d ms", math.floor(w.durMs + 0.5)) or "", w.note and (" " .. w.note) or ""))
    end
  end
  return L
end

local function writeReport(res)
  local okB, lines = pcall(HB.buildLines, res)
  if not okB then lines = { "# no se pudo armar el informe: " .. tostring(lines) } end
  return pcall(function()
    local w = getFileWriter(HB.FILE, true, false)
    if not w then error("sin escritor") end
    for _, l in ipairs(lines) do w:write(S.ascii(l) .. "\n") end
    w:close()
  end)
end

---------------------------------------------------------------------------
-- El zombi de prueba: quieto, mirandote de frente, a HB.DIST del alcance del arma; se repone si queda en el piso, muerto o lejos.
---------------------------------------------------------------------------
local function zombieOk(z)
  if not z then return false end
  local ok, bad = pcall(function()
    return z:isDead() or z:isOnFloor() or z:isKnockedDown() or not z:getCurrentSquare()
  end)
  return ok and not bad
end

local function removeZombie(z)
  if z then pcall(function() z:removeFromWorld(); z:removeFromSquare() end) end
end

local function spot(p, weapon)
  local range, minR = 1.2, 0
  pcall(function() range = weapon:getMaxRange(p) end)
  pcall(function() minR = weapon:getMinRange() or 0 end)
  -- (134d) mas cerca que el alcance minimo el motor empuja (CombatManager.calculateAttackVars; el cuchillo, en cambio, apuñala): la lanza (minimo 0,98)
  -- salia toda empujones y la maza (0,7) la mitad
  local d = math.max(0.45, minR + 0.1, minR + (range - minR) * HB.DIST)
  local ang = 0
  pcall(function() ang = math.rad(p:getDirectionAngle()) end)
  return p:getX() + math.cos(ang) * d, p:getY() + math.sin(ang) * d, d
end

local function placeZombie(p, weapon)
  local x, y = spot(p, weapon)
  local z = run.zombie
  if not zombieOk(z) then
    removeZombie(z)
    run.zombie = nil
    pcall(function()
      local list = addZombiesInOutfit(math.floor(x), math.floor(y), math.floor(p:getZ()), 1, nil, 50)
      if list and list:size() > 0 then run.zombie = list:get(0) end
    end)
    z = run.zombie
    if not z then return false end
    run.respawns = run.respawns + 1
    pcall(function() z:getModData().SandevistanPerf = true end)
    pcall(function() z:setUseless(true) end)
  end
  pcall(function()
    z:setX(x); z:setY(y); z:setLastX(x); z:setLastY(y)
    z:setHealth(HB.HEALTH)
    z:faceThisObject(p)
  end)
  return true
end

---------------------------------------------------------------------------
-- Plan y estado
---------------------------------------------------------------------------
local function equip(p, full)
  local item = nil
  pcall(function()
    item = p:getInventory():AddItem(full)
    p:setPrimaryHandItem(item)
    if item:isTwoHandWeapon() or item:isRequiresEquippedBothHands() then p:setSecondaryHandItem(item) else p:setSecondaryHandItem(nil) end
  end)
  if item then run.items[#run.items + 1] = item end
  return item
end

local function keepUp(p)
  local d = S.data(p)
  if run.implant then
    d.heat, d.lockUntilCool = 0, false
    local s = R.session(p)
    if not s.active then s.reuseAtMs = 0; pcall(R.activate, p) end
  end
  pcall(function() SandevistanEffects.setEndurance(p, 1) end)
  local w = run.weapon
  if w then pcall(function() w:setCondition(w:getConditionMax()) end) end
end

function HB.start(p, opts)
  opts = opts or {}
  if run then say(p, "El banco de golpes ya esta en curso"); return false end
  if S.isMPClient() then say(p, "El banco de golpes es solo para partida local (en MP el anti-cheat expulsa)"); return false end
  local plan = {}
  for _, full in ipairs(opts.weapons or HB.WEAPONS) do
    for _, sp in ipairs(opts.speeds or HB.SPEEDS) do
      plan[#plan + 1] = { full = full, short = shortName(full), speed = sp, swings = {} }
    end
  end
  for _, full in ipairs(opts.stabWeapons or HB.STAB_WEAPONS) do
    for _, sp in ipairs(opts.speeds or HB.SPEEDS) do
      plan[#plan + 1] = { full = full, short = shortName(full) .. "/crit", speed = sp, swings = {}, stab = true }
    end
  end
  run = { p = p, plan = plan, step = 0, phase = "next", items = {}, respawns = 0, manual = opts.manual == true, t0 = S.realMs() }
  pcall(function() run.prim = p:getPrimaryHandItem(); run.sec = p:getSecondaryHandItem() end)
  pcall(function() run.god = p:isGodMod() == true; p:setGodMod(true) end)
  run.hitStats = C.hitStats                                                   -- los golpes del banco no cuentan en la seccion "combate" del REPORTE
  C.hitStats = { swings = 0, hit = 0, lost = 0, lostBoosted = 0, lastLost = nil, maxHitSpeed = 0 }
  run.implant = S.hasWorkingImplant(S.data(p))
  say(p, string.format("Banco de golpes: %d armas (+%d con apunalada) x %d velocidades x %d golpes. Quedate quieto%s", #(opts.weapons or HB.WEAPONS),
    #(opts.stabWeapons or HB.STAB_WEAPONS),
    #(opts.speeds or HB.SPEEDS), HB.SWINGS, run.implant and "" or " (sin implante: sin el bono de dano)"))
  return true
end

function HB.finish(reason)
  local r = run
  if not r then return end
  run = nil
  C.benchSpeed = nil
  if r.hitStats then C.hitStats = r.hitStats end
  local p = r.p
  removeZombie(r.zombie)
  pcall(function() p:setIsAiming(false) end)
  if r.implant then pcall(R.deactivate, p, "forced") end
  pcall(function() p:setGodMod(r.god == true) end)
  pcall(function() p:setPrimaryHandItem(r.prim); p:setSecondaryHandItem(r.sec) end)
  for _, it in ipairs(r.items) do pcall(function() p:getInventory():Remove(it) end) end
  local res = { plan = r.plan, manual = r.manual, implant = r.implant, cancelled = reason, respawns = r.respawns }
  HB.last = res
  local wrote = writeReport(res)
  say(p, reason and ("Banco de golpes cancelado: " .. tostring(reason)) or
    (wrote and ("Banco de golpes listo -> Zomboid/Lua/" .. HB.FILE) or "Banco de golpes listo (no se pudo escribir el txt)"))
end
function HB.cancel(reason) HB.finish(reason or "cancelado") end

---------------------------------------------------------------------------
-- Eventos: cada golpe del jugador abre un registro; el impacto, el blanco y el final lo completan.
---------------------------------------------------------------------------
local function mine(a) return run and a == run.p end

local function onSwing(attacker)
  if not mine(attacker) then return end
  local st = run.plan[run.step]
  if not st or run.phase ~= "await" and run.phase ~= "ready" then return end
  if HB.realSwings(st) >= HB.SWINGS then return end
  local w = { startMs = S.realMs() }
  pcall(function() w.shove = attacker:isDoShove() == true end)
  if st.stab then pcall(function() attacker:setCriticalHit(true) end) end    -- (134d) por si el motor recalculo el critico despues de pressedAttack
  pcall(function() w.crit = attacker:isCriticalHit() == true end)
  pcall(function() w.hp0 = run.zombie:getHealth() end)
  st.swings[#st.swings + 1] = w
  run.cur = w
  run.phase = "swing"
  C.lastHit = nil
  local wp = run.weapon                                       -- (134b) condicion llena antes de cada golpe: un golpe podia romperla antes del tick
  if wp then pcall(function() wp:setCondition(wp:getConditionMax()) end) end
end

-- (134b) El arma del paso sigue en la mano y sana; si se rompio o se cayo, se equipa otra igual (y se anota). Devuelve false si no se pudo.
function HB.ensureWeapon(p, st)
  local inHand, broken = nil, false
  pcall(function() inHand = p:getPrimaryHandItem() end)
  pcall(function() broken = run.weapon and run.weapon:isBroken() == true end)
  if run.weapon and inHand == run.weapon and not broken then return true end
  st.rearmed = (st.rearmed or 0) + 1
  run.weapon = equip(p, st.full)
  run.phase, run.phaseMs = "equip", S.realMs()
  return run.weapon ~= nil
end

local function onImpact(attacker)
  if mine(attacker) and run.cur then
    run.cur.impact = true
    pcall(function() run.cur.cs = attacker:getCombatSpeed() end)
  end
end

local function onHit(attacker, target, weapon, damage)
  if not mine(attacker) or not run.cur or target ~= run.zombie then return end
  local w = run.cur
  w.hit = true
  pcall(function()
    w.dist = attacker:DistTo(target)
    local dx, dy = target:getX() - attacker:getX(), target:getY() - attacker:getY()
    local a = math.deg(math.atan2(dy, dx)) - attacker:getDirectionAngle()
    w.angle = (a + 540) % 360 - 180
  end)
  pcall(function() w.stab = attacker:getVariableString("ZombieHitReaction") == "KnifeDeath" end)   -- (134d) apuñalada: mata siempre
  local v = C.vanillaLoss(attacker, target, weapon, damage)
  if v.shove or (run.weapon and weapon ~= run.weapon) then w.shove = true end
  w.vanilla = v.loss
  local lh = C.lastHit
  if lh and math.abs((lh.loss or 0) - v.loss) < 1e-6 then w.extra, w.mult = lh.extra, lh.mult else w.extra, w.mult = 0, 1 end
  w.lossExp = w.vanilla + w.extra
  if v.crit then w.note = "critico del motor"; w.engineCrit = true end
end

local function closeCur(note)
  local w = run.cur
  if not w then return end
  pcall(function() if w.hit then w.hp1 = run.zombie:getHealth() end end)
  if w.hp0 and w.hp1 then w.lossObs = w.hp0 - w.hp1 end
  -- (134d) critico que mata sin pasar por la cuenta del daño (la lanza: ZombieHitReaction=HitSpearDeath1/2): fuera de la comparacion, como la apuñalada
  if w.engineCrit and not w.stab and w.hp1 and w.hp1 <= 0 then w.critKill = true; note = (note and (note .. ", ") or "") .. "lo mato" end
  if w.startMs then w.durMs = S.realMs() - w.startMs end
  if w.stab then                                            -- (134d) el cuchillo quedo clavado en el zombi: ensureWeapon equipa otro
    local inHand = nil
    pcall(function() inHand = run.p:getPrimaryHandItem() end)
    if run.weapon and inHand ~= run.weapon then w.jaw = true; note = (note and (note .. ", ") or "") .. "cuchillo clavado en la mandibula" end
  end
  if note then w.note = (w.note and (w.note .. ", ") or "") .. note end
  run.cur = nil
end

local function onFinished(p)
  if not mine(p) or run.phase ~= "swing" then return end
  closeCur(nil)
  run.phase = "cool"
  run.phaseMs = S.realMs()
end

---------------------------------------------------------------------------
-- OnTick: next (arma y velocidad) -> equip (espera el modelo) -> ready (zombi y golpe) -> await (llega OnWeaponSwing) -> swing -> cool -> ready...
---------------------------------------------------------------------------
local function attackFree(p)
  local ok, free = pcall(function() return not p:isAttackStarted() and (p:getMeleeDelay() or 0) <= 0 end)
  return not ok or free
end

function HB.tick()
  if not run then return end
  local p, now = run.p, S.realMs()
  local okDead, dead = pcall(function() return p:isDead() end)
  if okDead and dead then HB.finish("el jugador murio"); return end
  keepUp(p)
  local st = run.plan[run.step]
  if run.phase == "next" then
    run.step = run.step + 1
    st = run.plan[run.step]
    if not st then HB.finish(nil); return end
    if not run.weapon or run.weaponName ~= st.full then
      run.weapon = equip(p, st.full)
      run.weaponName = st.full
      if not run.weapon then st.swings[1] = { note = "no se pudo crear " .. st.full }; return end
    end
    C.benchSpeed = st.speed
    removeZombie(run.zombie)                 -- (134b) zombi nuevo en cada paso: el motor sube el daño de los golpes repetidos al mismo zombi
    run.zombie = nil
    run.phase, run.phaseMs = "equip", now
  elseif run.phase == "equip" then
    if now - run.phaseMs >= HB.EQUIP_MS then run.phase = "ready" end
  elseif run.phase == "ready" then
    if HB.realSwings(st) >= HB.SWINGS or #st.swings >= HB.SWINGS * 3 then run.phase = "next"; return end
    if not attackFree(p) then return end
    if not HB.ensureWeapon(p, st) then HB.finish("no se pudo equipar " .. st.full); return end
    if run.phase ~= "ready" then return end                 -- re-equipada: espera el modelo de la mano
    if not placeZombie(p, run.weapon) then HB.finish("no se pudo poner el zombi de prueba"); return end
    if not run.manual then
      pcall(function() p:faceThisObject(run.zombie) end)
      pcall(function() p:setIsAiming(true) end)
      pcall(function() p:setDoShove(false) end)          -- (134b) sin apuntar, el motor convierte el ataque en empujon
      pcall(function() p:pressedAttack() end)
      if st.stab then pcall(function() p:setCriticalHit(true) end) end   -- (134d) el motor tira el critico en pressedAttack; la animacion lo lee despues
    end
    run.phase, run.phaseMs = "await", now
  elseif run.phase == "await" then
    if not run.manual and now - run.phaseMs > HB.START_MS then
      run.misses = (run.misses or 0) + 1
      st.stalls = (st.stalls or 0) + 1
      if run.misses >= 3 and not run.everSwung then
        run.manual = true
        say(p, "No puedo disparar el golpe solo: mantene apretado el ataque mirando al zombi; el banco cambia de arma y velocidad")
      end
      run.phase = "ready"
      if st.stalls >= 8 then st.skipped = true; run.phase = "next" end          -- este paso no arranca: se sigue con el proximo
    elseif run.manual and now - run.phaseMs > 60000 then
      HB.finish("un minuto sin golpes en modo manual")
    end
  elseif run.phase == "swing" then
    run.everSwung = true
    local started = now - (run.cur and run.cur.startMs or now)
    local okA, attacking = pcall(function() return p:isAttackStarted() end)
    local limit = (st.stab or (run.cur and (run.cur.stab or run.cur.crit))) and HB.STAB_MS or HB.SWING_MS
    if started > limit then closeCur("no termino"); run.phase, run.phaseMs = "cool", now
    elseif okA and not attacking and started > 250 then                -- la animacion termino sin OnPlayerAttackFinished: el golpe no paso por su cuadro de impacto
      closeCur(not (run.cur and run.cur.impact) and "termino sin cuadro de impacto" or nil); run.phase, run.phaseMs = "cool", now
    end
  elseif run.phase == "cool" then
    if now - run.phaseMs >= 150 and attackFree(p) then run.phase = "ready" end
  end
end

-- Un golpe que empieza antes de que termine el anterior (OnWeaponSwing sin OnPlayerAttackFinished): el anterior queda sin cerrar; se cierra al abrir el nuevo.
local function onSwingWrapped(attacker, weapon)
  if mine(attacker) and run.phase == "swing" and run.cur then closeCur("empezo otro golpe"); run.phase = "ready" end
  onSwing(attacker, weapon)
end

Events.OnWeaponSwing.Add(S.safe("HitBench.OnWeaponSwing", onSwingWrapped))
if Events.OnWeaponSwingHitPoint then Events.OnWeaponSwingHitPoint.Add(S.safe("HitBench.OnWeaponSwingHitPoint", onImpact)) end
Events.OnWeaponHitCharacter.Add(S.safe("HitBench.OnWeaponHitCharacter", onHit))
Events.OnPlayerAttackFinished.Add(S.safe("HitBench.OnPlayerAttackFinished", onFinished))
Events.OnTick.Add(S.safe("HitBench.OnTick", HB.tick))
