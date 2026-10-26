-- Sandevistan / Combat: bonus melee durante la activación y XP por kill.
require "Sandevistan/Core"
require "Sandevistan/Runtime"
require "Sandevistan/Effects"
require "Sandevistan/Kerenzikov"

local CFG = SandevistanConfig
local S = Sandevistan
local R = SandevistanRuntime
local FW = SandevistanFirmware

SandevistanCombat = { swings = {}, intervals = {}, forceTier = nil }
local C = SandevistanCombat

local function isLocalActive(character)
  if not character or not instanceof(character, "IsoPlayer") then return false end
  if not character:isLocalPlayer() then return false end
  return R.isActive(character) and not R.session(character).work          -- (86) el modo trabajo de Taller no da ventajas de combate
end

-- Tiradas extra de desgaste: cada una baja 1 de condicion con probabilidad 1 / getConditionLowerChance del arma (la parte fraccionaria de extra es una tirada parcial).
function C.extraWear(weapon, extra)
  if not weapon then return 0 end
  local lost = 0
  S.try("extraWear", function()
    local cond = weapon:getCondition()
    if not cond or cond <= 0 then return end
    local one = math.max(2, weapon:getConditionLowerChance() or 10)
    local rolls = math.floor(extra) + (S.chance(extra - math.floor(extra)) and 1 or 0)
    for _ = 1, rolls do
      if cond - lost > 0 and ZombRand(one) == 0 then lost = lost + 1 end
    end
    if lost > 0 then
      weapon:setCondition(cond - lost)
      if S.isMPClient() and rawget(_G, "syncItemFields") then pcall(syncItemFields, getSpecificPlayer(0), weapon) end   -- (115) MP: el servidor lleva la condicion del arma
    end
  end)
  return lost
end

-- Desgaste de la furia (cyberpsicosis o furia total): tiradas extra segun Berserk.WeaponWearMult. Devuelve cuanta condicion se perdio de mas.
-- C.trace (lo arma Debug -> "Desgaste en furia: probar con golpes reales") cuenta golpes y desgaste extra y avisa cada vez que pasa.
function C.furyWear(attacker, weapon)
  local B = CFG.Psychosis.Berserk
  local sess = R.session(attacker)
  if not (B.Enabled and (sess.berserk or sess.fury) and (B.WeaponWearMult or 1) > 1) then return 0 end
  local ty = nil
  pcall(function() ty = weapon:getType() end)
  if ty == "BareHands" then return 0 end                      -- los punos (empujones) no se gastan
  local before = 0
  pcall(function() before = weapon:getCondition() end)
  local lost = C.extraWear(weapon, B.WeaponWearMult - 1)
  local tr = C.trace
  if tr then
    tr.hits, tr.lost = tr.hits + 1, tr.lost + lost
    local name = "arma"
    pcall(function() name = weapon:getName() end)
    S.log(string.format("desgaste en furia: %s, golpe %d, condicion %s -> %s (extra %d)", name, tr.hits, tostring(before), tostring(before - lost), lost))
    if lost > 0 then pcall(function() attacker:Say("Desgaste extra: " .. tostring(before - lost) .. "/" .. tostring(weapon:getConditionMax())) end) end
  end
  return lost
end

-- Desgaste extra del firmware (Martillo: +0.5 tiradas por golpe). Mismas tiradas que la furia; los punos no se gastan. Devuelve cuanta condicion se perdio de mas.
function C.profileWear(weapon, prof)
  local extra = prof and prof.wear or 0
  if extra <= 0 or not weapon then return 0 end
  local ty = nil
  pcall(function() ty = weapon:getType() end)
  if ty == "BareHands" then return 0 end
  return C.extraWear(weapon, extra)
end

C.TEST_MS = 60000

-- Furia de prueba (Debug): 60 s con el implante encendido sin limite de Heat, furia forzada, invulnerable, un bate equipado y zombis de prueba cerca.
-- Cada golpe real se cuenta en C.trace; al terminar se repone todo (apaga el implante, saca el bate y los zombis que puso).
function C.startFuryTest(player)
  local d = S.data(player)
  local say = function(t) pcall(function() player:Say(t) end) end
  if C.trace then say("La furia de prueba ya esta en curso"); return false end
  if not S.hasWorkingImplant(d) then say("Necesito un implante operativo (Debug > Estado > Implante y adaptacion > Instalar)"); return false end
  local now = S.realMs()
  local PS = rawget(_G, "SandevistanPsychosis")
  if PS then PS.st(player).forceBerserkUntilMs = now + C.TEST_MS end
  local tr = { hits = 0, lost = 0, untilMs = now + C.TEST_MS, player = player, one = 10, zombies = {} }
  pcall(function() tr.god = player:isGodMod() == true; player:setGodMod(true) end)
  -- bate equipado (si ya tenias uno en la mano, se usa ese)
  local w = nil
  pcall(function() w = player:getPrimaryHandItem() end)
  if not (w and w.getConditionLowerChance and w:getConditionMax() and not w:isRanged()) then
    pcall(function()
      w = player:getInventory():AddItem("Base.BaseballBat")
      tr.bat = w
      player:setPrimaryHandItem(w); player:setSecondaryHandItem(w)
    end)
  end
  pcall(function() tr.one = math.max(2, w:getConditionLowerChance() or 10); tr.weapon = w end)
  -- zombis de prueba alrededor (marcados: Debug > "Borrar zombis que hayan quedado..." tambien los borra)
  pcall(function()
    local cell, px, py, pz = getCell(), player:getX(), player:getY(), math.floor(player:getZ())
    for i = 1, 4 do
      local ang, r = i * 1.57 + 0.4, 3 + (i % 2)
      local sq = cell:getGridSquare(math.floor(px + math.cos(ang) * r), math.floor(py + math.sin(ang) * r), pz)
      if sq and sq:isFree(false) then
        local list = addZombiesInOutfit(sq:getX(), sq:getY(), sq:getZ(), 1, nil, 50)
        for k = 0, list:size() - 1 do
          local z = list:get(k)
          pcall(function() z:getModData().SandevistanPerf = true end)
          pcall(z.spotted, z, player, true)
          tr.zombies[#tr.zombies + 1] = z
        end
      end
    end
  end)
  C.trace = tr
  C.holdFuryTest(player)
  say("Furia de prueba 60 s: golpea a los zombis; cada golpe dice el desgaste extra")
  return true
end

-- Cada tick de la prueba: implante encendido, sin Heat ni bloqueo termico.
function C.holdFuryTest(player)
  local d = S.data(player)
  d.heat, d.lockUntilCool = 0, false
  local s = R.session(player)
  if not s.active then s.reuseAtMs = 0; R.activate(player) end
  local tr = C.trace
  local w = tr and tr.weapon
  if w then pcall(function() if w:getCondition() <= 1 then w:setCondition(w:getConditionMax()) end end) end    -- que no se rompa a mitad de la prueba
end

-- Cierra la traza cuando se acaba el tiempo (y repone lo que puso la prueba).
function C.traceTick()
  local tr = C.trace
  if not tr then return end
  if S.realMs() < tr.untilMs then
    C.holdFuryTest(tr.player)
    return
  end
  C.trace = nil
  local B = CFG.Psychosis.Berserk
  local msg = string.format("Furia de prueba terminada: %d golpes, %d de desgaste extra (con x%.1f se espera ~1 cada %d golpes)", tr.hits, tr.lost,
    B.WeaponWearMult, math.floor(tr.one / math.max(0.01, B.WeaponWearMult - 1) + 0.5))
  S.log(msg)
  pcall(function() tr.player:Say(msg) end)
  pcall(function() R.deactivate(tr.player, "forced") end)
  pcall(function() tr.player:setGodMod(tr.god == true) end)
  for _, z in ipairs(tr.zombies or {}) do pcall(function() z:removeFromWorld(); z:removeFromSquare() end) end
  if tr.bat then
    pcall(function()
      tr.player:setPrimaryHandItem(nil); tr.player:setSecondaryHandItem(nil)
      tr.player:getInventory():Remove(tr.bat)
    end)
  end
end

---------------------------------------------------------------------------
-- (134) Daño. OnWeaponHitCharacter llega con el daño del golpe ANTES de que el motor lo achique (IsoGameCharacter.Hit -> processHitDamage ->
-- hitConsequences, 42.21): la vida que pierde el zombi es damage x modDelta x 1,5 (blanco no jugador) x (0,3 + 0,1 x nivel del arma) x 0,15
-- (GLOBAL_MELEE_DAMAGE_REDUCTION), x1,5 si el zombi no te mira de frente, x max(2, critico del arma) en un critico, x max(5, critico) contra
-- el piso y x0,5 con un arma de dos manos en una mano. modDelta = 2 x distancia / alcance del arma (1 si da menos de 0,3). Un empujon no hace daño.
-- Antes el bono se restaba sobre damage directo: el "+15 %" era +220 % con nivel 0 y el critico del Sandi valia 7 golpes. Ahora el bono es un
-- multiplicador sobre una perdida de referencia (C.sandiBase: la del golpe medio a media distancia, sin critico): Config.Combat.Damage.Mult (meta: el bate con nivel 0 mata en 3 golpes) corregido por arma (opcion B:
-- (RefDamage / daño medio del arma) ^ WeaponExp, acotado), x(1 + firmware + furia/Overload). El daño extra se resta dentro del evento, antes de
-- que el motor reste el suyo y mire si murio: la kill y la XP quedan del jugador como siempre.
---------------------------------------------------------------------------
local function cfgValue(key, default)
  local v = nil
  pcall(function() v = getCombatConfig():get(CombatConfigKey[key]) end)
  return type(v) == "number" and v or default
end

local function num(fn, default)
  local ok, v = pcall(fn)
  return (ok and type(v) == "number") and v or default
end

local function yes(fn)
  local ok, v = pcall(fn)
  return ok and v == true
end

-- Factor por arma (opcion B): las debiles pegan proporcionalmente mas fuerte y las muy fuertes menos, sin perder el orden entre armas.
function C.weaponFactor(weapon)
  local D = CFG.Combat.Damage
  local lo, hi = num(function() return weapon:getMinDamage() end, nil), num(function() return weapon:getMaxDamage() end, nil)
  if not lo or not hi or lo + hi <= 0 then return 1 end
  local f = (D.RefDamage / ((lo + hi) / 2)) ^ D.WeaponExp
  return math.max(D.WeaponMin, math.min(D.WeaponMax, f))
end

-- Vida que le va a sacar el motor a este golpe (sin el mod) y como se llego a ese numero. Para el bono, el banco de golpes y las pruebas.
function C.vanillaLoss(attacker, target, weapon, damage)
  local r = { damage = damage or 0, modDelta = 1, received = cfgValue("NON_PLAYER_RECEIVED_DAMAGE_MULTIPLIER", 1.5), level = 0, behind = false, crit = false,
              floor = false, oneHand = false, shove = false }
  if r.damage <= 0 then r.loss = 0; return r end
  if instanceof(attacker, "IsoPlayer") and yes(function() return attacker:isDoShove() end) and not yes(function() return attacker:isAimAtFloor() end) then
    r.shove = true; r.loss = 0; return r                              -- el empujon no hace daño (Hit lo marca ignoreDamage)
  end
  local range = num(function() return weapon:getMaxRange(attacker) end, 0)
  local dist = num(function() return attacker:DistTo(target) end, 0)
  if range > 0 then
    local md = 2 * dist / range
    if md >= 0.3 then r.modDelta = md end
  end
  r.level = math.max(0, math.min(10, num(function() return attacker:getWeaponLevel() end, 0)))
  r.levelMult = cfgValue("BASE_WEAPON_DAMAGE_MULTIPLIER", 0.3) + r.level * cfgValue("WEAPON_LEVEL_DAMAGE_MULTIPLIER_INCREMENT", 0.1)
  local loss = r.damage * r.modDelta * r.received * r.levelMult
  -- de espaldas o de costado: el motor compara la direccion zombi - atacante con hacia donde mira el zombi (dot > -0,3)
  pcall(function()
    local dx, dy = target:getX() - attacker:getX(), target:getY() - attacker:getY()
    local len = math.sqrt(dx * dx + dy * dy)
    local fwd = target:getForwardDirection()
    if len > 0 and fwd and (dx * fwd:getX() + dy * fwd:getY()) / len > -0.3 then r.behind = true end
  end)
  if r.behind then loss = loss * 1.5 end
  local critMult = num(function() return weapon:getCriticalDamageMultiplier() end, 2)
  if yes(function() return attacker:isAimAtFloor() end) then r.floor = true; loss = loss * math.max(5, critMult) end
  if yes(function() return attacker:isCriticalHit() end) then r.crit = true; loss = loss * math.max(2, critMult) end
  if yes(function() return weapon:isTwoHandWeapon() end) and not yes(function() return attacker:isItemInBothHands(weapon) end) then
    r.oneHand = true; loss = loss * cfgValue("DAMAGE_PENALTY_ONE_HANDED_TWO_HANDED_WEAPON_MULTIPLIER", 0.5)
  end
  r.loss = loss * cfgValue("GLOBAL_MELEE_DAMAGE_REDUCTION_MULTIPLIER", 0.15)
  return r
end

-- (134b) Base del bono del Sandi: lo que sacaria el golpe medio del arma a media distancia, sin critico del motor, sin el x5 contra el piso y sin la escalada
-- de golpes repetidos: daño medio del arma x 1,5 x (0,3 + 0,1 x nivel) x 0,15 (x1,5 de espaldas, x0,5 dos manos en una). En el juego se pega casi siempre
-- con la punta (modDelta ~1,7) y el motor tira muchos criticos: multiplicar la perdida real por 11 mataba de un golpe con nivel 0 (banco de golpes de la
-- 134: perdida observada = esperada x0,97, de 2 a 6 por golpe). Esa variacion queda solo en la parte del motor.
function C.sandiBase(v, weapon)
  if not v or v.shove or (v.damage or 0) <= 0 then return 0 end
  local lo, hi = num(function() return weapon:getMinDamage() end, nil), num(function() return weapon:getMaxDamage() end, nil)
  local avg = (lo and hi and lo + hi > 0) and (lo + hi) / 2 or v.damage
  local base = avg * (v.received or 1.5) * (v.levelMult or 0.3) * cfgValue("GLOBAL_MELEE_DAMAGE_REDUCTION_MULTIPLIER", 0.15)
  if v.behind then base = base * 1.5 end
  if v.oneHand then base = base * cfgValue("DAMAGE_PENALTY_ONE_HANDED_TWO_HANDED_WEAPON_MULTIPLIER", 0.5) end
  return base
end

-- Multiplicador total del golpe con el implante encendido (1 = sin bono). extraFrac = firmware (Martillo) + furia/Overload.
function C.damageMult(weapon, extraFrac)
  local D = CFG.Combat.Damage
  return math.max(1, D.Mult * C.weaponFactor(weapon) * (1 + (extraFrac or 0)))
end

-- (134e) Velocidad descartada por el tope convertida en daño (Config.Combat.SpeedOverflowDamage): factor del golpe en curso, 1 si no hay.
C.overflow = {}   -- [playerNum] = { mult, untilMs }
function C.speedOverflow(tier, base)
  local O, cap = CFG.Combat.SpeedOverflowDamage, CFG.Combat.MaxCombatSpeed
  if not O or not O.Enabled or not cap or not tier or not base or base <= 0 then return 1 end
  local want = base * (1 + (tier.attackBoost or tier.playerBoost or 0))
  local got = base * C.speedFactor(tier, base)
  if want <= got + 1e-9 then return 1 end
  return math.max(1, math.min(O.Max or 2, 1 + (want / got - 1) * (O.Efficiency or 1)))
end
function C.overflowFor(attacker)
  local o = C.overflow[num(function() return attacker:getPlayerNum() end, 0)]
  if o and S.realMs() <= o.untilMs then return o.mult end
  return 1
end

-- Multiplicador de daño, critico del Sandi y derribo extra, solo melee.
local function onWeaponHitCharacter(attacker, target, weapon, damage)
  if not isLocalActive(attacker) then return end
  if not target or not instanceof(target, "IsoZombie") then return end
  local ranged = false
  S.try("isRanged", function() ranged = weapon and weapon:isRanged() end)
  if ranged then return end
  local eff = R.session(attacker).eff
  -- (82) firmware: Martillo suma daño y derribo, duplica el critico y gasta mas el arma
  local prof = FW.profile(S.data(attacker))
  if damage and damage > 0 then
    local v = C.vanillaLoss(attacker, target, weapon, damage)
    local ov = C.overflowFor(attacker)
    local mult = C.damageMult(weapon, prof.dmg + (eff and eff.extraDamage or 0)) * ov
    local base = C.sandiBase(v, weapon)
    local extra = base * (mult - 1)
    if S.chance(CFG.Combat.MeleeCritBonus) then extra = extra + base * mult * (CFG.Combat.MeleeCritDamageMultiplier - 1) * prof.critMult end
    C.lastHit = { loss = v.loss, extra = extra, mult = mult, base = base, info = v, overflow = ov }
    if ov > 1 and base > 0 then local H = C.hitStats; H.overflowHits = (H.overflowHits or 0) + 1; H.overflowSum = (H.overflowSum or 0) + ov end
    if extra > 0 then S.try("damageBonus", function() target:setHealth(target:getHealth() - extra) end) end
  end
  -- furia: el arma se gasta mas (tiradas extra con la propia probabilidad de desgaste del arma)
  if not C.benchSpeed then                                  -- (134b) el banco de golpes no gasta el arma de mas (se rompia y seguia a mano limpia)
    C.furyWear(attacker, weapon)
    C.profileWear(weapon, prof)
  end
  if S.chance(CFG.Combat.MeleeKnockdownBonus + prof.knock) then
    S.try("knockZombie", function() target:setKnockedDown(true) end)
  end
end

-- +12 XP por kill real mientras está activo (los fantasmas no disparan este evento).
local function onZombieDead(zombie)
  local killer = nil
  S.try("getAttackedBy", function() killer = zombie:getAttackedBy() end)
  if isLocalActive(killer) then
    local kd = S.data(killer)
    local prof = FW.profile(kd)
    R.addPendingXP(killer, CFG.XP.PerKill * prof.xpKill, "kill")                      -- (83) Apogeo: +25 % de XP por kill
    kd.xpSrc = kd.xpSrc or {}; kd.xpSrc.nKills = (kd.xpSrc.nKills or 0) + 1
    local FC = rawget(_G, "SandevistanFirmwareClient")
    if FC and prof.killHeat > 0 then FC.killHeat(killer, kd, prof.killHeat) end       -- (83) Apogeo: cada kill baja el Heat
  end
end

---------------------------------------------------------------------------
-- Velocidad de ataque. La animación melee usa la variable CombatSpeed como velocidad
-- (AnimSets 1HDefault/2HDefault: <m_SpeedScale>CombatSpeed</m_SpeedScale>). El juego la
-- recalcula al iniciar cada golpe, así que se multiplica en OnWeaponSwing y se sostiene
-- durante el golpe por si el motor la vuelve a escribir.
---------------------------------------------------------------------------
local pending = {}   -- [playerIndex] = { target, untilMs, startMs }

-- (107) Black Lace (ex Kerenzikov) sin el implante encendido: un "tramo" chico solo para la velocidad del golpe (sin reintegro de estamina)
C.BLACK_LACE = { attackBoost = 0, blackLace = true }
local function boostTier(p)
  if C.forceTier then return C.forceTier end
  if R.isActive(p) then local s = R.session(p); return s.eff or s.tier end
  if Kerenzikov.isActive(p) then C.BLACK_LACE.attackBoost = CFG.Kerenzikov.AttackBoost; return C.BLACK_LACE end
  return nil
end
C.boostTier = boostTier

-- (116) Anti-cheat del servidor (AntiCheatHitWeapon.isRateExceeded en 42.21, politica por defecto AntiCheatHit = 2: EXPULSA): con un arma cuerpo a cuerpo
-- cuenta los zombis golpeados en los ultimos 1,2 s (3 x 400 ms) y salta si pasan de 3 x maxHits (maxHits = proyectiles x MaxHitCount del arma; con la opcion
-- de sandbox MultiHitZombies, al menos 3). Sin golpear a varios es 3 golpes en 1,2 s: un golpe cada 0,4 s, y el Sandevistan pega mas rapido. En un cliente
-- de multijugador se lleva la misma cuenta y, cerca del limite, el golpe siguiente va a la velocidad normal (sin bono ni pausa acortada). Los admins
-- (CantBeKickedByAnticheat) no tienen el freno. CFG.Combat.MPHitRateGuard = false lo apaga (por ejemplo si el servidor tiene AntiCheatHit en 3 = solo log).
C.hitTimes = {}   -- [playerNum] = { ms, ms, ... } zombis golpeados (uno por zombi)
local RATE_WINDOW_MS = 1200

local function exemptFromAnticheat(p)
  local ok, yes = pcall(function() return p:getRole():hasCapability(Capability.CantBeKickedByAnticheat) end)
  return ok and yes == true
end

function C.maxHits(weapon)
  local n = 1
  pcall(function() n = math.max(1, weapon:getProjectileCount()) * math.max(1, weapon:getMaxHitCount()) end)
  local multi = false
  pcall(function() multi = SandboxVars.MultiHitZombies == true end)
  if multi then n = math.max(n, 3) end
  return n
end

-- true = el proximo golpe tiene que ir sin bono (en SP, sin arma o con un arma de fuego apuntada no aplica)
function C.rateLimited(p, weapon)
  if not S.isMPClient() or CFG.Combat.MPHitRateGuard == false or not p then return false end
  weapon = weapon or (p.getPrimaryHandItem and p:getPrimaryHandItem())
  if weapon and weapon.isAimedFirearm and weapon:isAimedFirearm() then return false end
  if exemptFromAnticheat(p) then return false end
  local list, now, keep = C.hitTimes[p:getPlayerNum()] or {}, S.realMs(), {}
  for _, t in ipairs(list) do if now - t < RATE_WINDOW_MS then keep[#keep + 1] = t end end
  C.hitTimes[p:getPlayerNum()] = keep
  local limit = 3 * (weapon and instanceof(weapon, "HandWeapon") and C.maxHits(weapon) or 1)
  return #keep >= limit - 1
end

function C.countHit(attacker, target)
  if not S.isMPClient() or not attacker or not target or not instanceof(target, "IsoZombie") then return end
  if not instanceof(attacker, "IsoPlayer") or not attacker:isLocalPlayer() then return end
  local idx = attacker:getPlayerNum()
  C.hitTimes[idx] = C.hitTimes[idx] or {}
  table.insert(C.hitTimes[idx], S.realMs())
end

-- tramo para la VELOCIDAD del golpe (con el freno del anti-cheat)
local function speedTier(p, weapon)
  local tier = boostTier(p)
  if tier and C.rateLimited(p, weapon) then C.rateBrakes = (C.rateBrakes or 0) + 1; return nil end
  return tier
end

-- (101, 103) Tope de la velocidad del golpe. El motor deja la velocidad base de ataque entre 0,8 y 1,6 (CombatManager / calculateCombatSpeed); con todos los
-- bonos juntos (tramo, impulso, Overdrive, furia...) el multiplicador llegaba a x4 o mas y se vieron golpes que la animacion hace pero el juego no
-- registra (el evento AttackCollisionCheck cae al 25 % de la animacion). Lo que importa es la velocidad ABSOLUTA que ve la animacion: se limita a
-- CFG.Combat.MaxCombatSpeed (nunca por debajo de la base). El valor exacto donde empieza a fallar se ajusta jugando: la seccion "combate" del REPORTE cuenta
-- los golpes sin cuadro de impacto y con que velocidad pasaron.
function C.speedFactor(tier, base)
  local f = 1 + (tier.attackBoost or tier.playerBoost or 0)
  local cap = CFG.Combat.MaxCombatSpeed
  if cap and base and base > 0 and base * f > cap then f = math.max(1, cap / base) end
  return f
end

local function applyCombat(p, value)
  S.try("setCombatSpeed", function() p:setCombatSpeed(value) end)
  pcall(function() p:setVariable("CombatSpeed", value) end)
end

-- (103) El juego dispara OnWeaponSwingHitPoint en el cuadro de impacto de cada golpe (AttackCollisionCheck) y OnPlayerAttackFinished solo si ese cuadro llego a
-- ocurrir. Un golpe acelerado que empieza otro sin haber pasado por el cuadro de impacto es un golpe que el juego no registro: se cuenta con su velocidad.
C.hitStats = { swings = 0, hit = 0, lost = 0, lostBoosted = 0, lastLost = nil, maxHitSpeed = 0 }
local function closeSwing(e, why)
  if not e or e.closed then return end
  e.closed = true
  local H = C.hitStats
  H.swings = H.swings + 1
  if e.hit then
    H.hit = H.hit + 1
    if e.boosted and (e.target or 0) > H.maxHitSpeed then H.maxHitSpeed = e.target end
  else
    H.lost = H.lost + 1
    if e.boosted then
      H.lostBoosted = H.lostBoosted + 1
      H.lastLost = { speed = e.target, base = e.base, why = why }
      if H.lostBoosted <= 10 then S.log(string.format("golpe sin cuadro de impacto: CombatSpeed %.2f (base %.2f, tope %s) %s", e.target or 0, e.base or 0, tostring(CFG.Combat.MaxCombatSpeed), tostring(why))) end
    end
  end
end

local function onWeaponSwing(attacker, weapon)
  if not attacker or not instanceof(attacker, "IsoPlayer") or not attacker:isLocalPlayer() then return end
  local idx = attacker:getPlayerNum()
  closeSwing(pending[idx], "empezo otro golpe")             -- el anterior no llego a su cuadro de impacto
  local entry = { startMs = S.realMs() }
  pcall(function() entry.endurance = SandevistanEffects.getEndurance(attacker) end)
  -- (146) con la deuda de estamina (139) el gasto del golpe va a la deuda: se mide desde ahi (onAttackFinished)
  if R.debtOn() and R.isActive(attacker) and R.session(attacker).enduranceMark then
    R.syncDebt(attacker)
    entry.debt = R.session(attacker).staminaDebt or 0
  end
  local tier = speedTier(attacker, weapon)
  entry.tier = tier
  entry.realTier = boostTier(attacker)                       -- (116) para el reintegro de estamina aunque el golpe vaya frenado
  C.lastSwingMs = C.lastSwingMs or {}
  local last = C.lastSwingMs[idx]
  if last and S.realMs() - last < 3000 then
    table.insert(C.intervals, { ms = S.realMs() - last, boosted = tier ~= nil })
    if #C.intervals > 50 then table.remove(C.intervals, 1) end
  end
  C.lastSwingMs[idx] = S.realMs()
  local cur = 1
  pcall(function() cur = attacker:getCombatSpeed() end)
  -- si el motor no recalculó desde el último golpe acelerado, la base es la guardada
  local lb = C.lastBoost and C.lastBoost[idx]
  local base = cur
  if lb and math.abs(cur - lb.target) < 0.01 then base = lb.base end
  local bench = C.benchSpeed                      -- (134) banco de golpes (HitBench): velocidad absoluta fija, sin tramo ni tope
  local holdMs = 2000                              -- (134d) la apuñalada critica del cuchillo dura mas: la velocidad se sostiene el doble
  pcall(function() if attacker:isCriticalHit() then holdMs = 4000 end end)
  C.overflow[idx] = nil
  if not tier and not bench and lb then
    applyCombat(attacker, lb.base)               -- restaurar si quedó acelerado
    C.lastBoost[idx] = nil
  end
  if bench then
    entry.target, entry.base, entry.boosted, entry.untilMs = bench, base, true, S.realMs() + holdMs
    C.lastBoost = C.lastBoost or {}
    C.lastBoost[idx] = { base = base, target = bench }
    applyCombat(attacker, bench)
  elseif tier and CFG.Combat.AttackSpeedBoost then
    entry.target = base * C.speedFactor(tier, base)
    entry.base = base
    local ov = C.speedOverflow(tier, base)
    if ov > 1 then C.overflow[idx] = { mult = ov, untilMs = S.realMs() + holdMs } end
    C.lastBoost = C.lastBoost or {}
    C.lastBoost[idx] = { base = base, target = entry.target }
    entry.boosted = true
    entry.untilMs = S.realMs() + holdMs
    applyCombat(attacker, entry.target)
  end
  pending[idx] = entry
end

-- Fraccion de la estamina de un golpe que se devuelve (el firmware la cambia: Martillo devuelve mucho menos).
function C.refund(player) return CFG.Combat.AttackStaminaRefund * FW.profile(S.data(player)).refund end

local function onAttackFinished(player, weapon)
  if not player or not player:isLocalPlayer() then return end
  local e = pending[player:getPlayerNum()]
  local refundFraction = C.refund(player)
  if e and e.realTier and not e.realTier.blackLace and e.endurance and refundFraction > 0 then
    -- reintegro de parte de la stamina del golpe (descontando el drenaje del propio implante)
    local now = SandevistanEffects.getEndurance(player)
    local implantDrain = 0
    if R.isActive(player) then
      implantDrain = S.staminaDrainPerSecond(R.session(player).level or 0, false, S.data(player)) * (S.realMs() - e.startMs) / 1000 * S.timeScale()          -- (127) el implante gasta por segundo de juego
    end
    local s = R.session(player)
    if e.debt and R.isActive(player) and s.enduranceMark then
      -- (139/146) Deuda de estamina: la resistencia esta congelada y el golpe subio la DEUDA (el drenaje del implante tambien entra ahi).
      -- Se anota primero lo que el juego gasto en este cuadro (tickDebt corre en OnTick), se mide cuanto subio la deuda desde el swing y
      -- el reintegro se descuenta de la deuda. Asi da igual en que cuadro descuente el juego el golpe.
      R.syncDebt(player)
      local cost = (s.staminaDebt or 0) - e.debt - implantDrain
      if cost > 0 then R.refundDebt(player, cost * refundFraction) end
    else
      local cost = e.endurance - now - implantDrain
      if cost > 0 then SandevistanEffects.setEndurance(player, now + cost * refundFraction) end
    end
  end
  if e then
    e.hit = true                                     -- OnPlayerAttackFinished solo llega si el cuadro de impacto ocurrio
    closeSwing(e, "terminado")
    table.insert(C.swings, { ms = S.realMs() - e.startMs, boosted = e.boosted == true })
    if #C.swings > 50 then table.remove(C.swings, 1) end
  end
  pending[player:getPlayerNum()] = nil
end

local lastDelay = {}

local function tickMeleeDelay()
  if not CFG.Combat.MeleeDelayBoost then return end
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    local tier = p and speedTier(p)
    if p and tier then
      local d = 0
      pcall(function() d = p:getMeleeDelay() end)
      local prev = lastDelay[idx] or 0
      if d > prev + 0.5 then            -- el juego acaba de fijar una pausa nueva: se acorta una vez
        local lb = C.lastBoost and C.lastBoost[idx]
        d = d / ((lb and lb.base > 0) and (lb.target / lb.base) or C.speedFactor(tier))          -- el mismo factor (con tope) que recibio el golpe
        S.try("setMeleeDelay", function() p:setMeleeDelay(d) end)
      end
      lastDelay[idx] = d
    elseif p then
      lastDelay[idx] = 0
    end
  end
end

-- (107) Reflejo del Black Lace contra los agarres: cada zombi cercano que PASA a atacarte (de no atacar a atacar) se tira una vez; si sale, tropieza hacia
-- atras y el ataque se corta. Solo con el Black Lace activo; cada GrabScanMs.
local wasAttacking = setmetatable({}, { __mode = "k" })
C.grabDodges = 0
local function zombieAttacking(z, p)
  local ok, st = pcall(z.getCurrentStateName, z)
  if ok and st == "AttackState" then return true end
  local ok2, at = pcall(z.isAttacking, z)
  if ok2 and at then
    local okT, t = pcall(z.getTarget, z)
    return okT and t == p
  end
  return false
end

function C.tickGrabDodge(p)
  local K = CFG.Kerenzikov
  local zl = nil
  pcall(function() zl = getCell():getZombieList() end)
  if not zl then return end
  for i = 0, zl:size() - 1 do
    local z = zl:get(i)
    if z and not z:isDead() and z:DistTo(p) <= K.GrabDodgeRadius then
      local now = zombieAttacking(z, p)
      if now and not wasAttacking[z] and S.chance(K.GrabDodgeChance) then
        S.try("zGrabDodge", function() z:setStaggerBack(true) end)
        C.grabDodges = C.grabDodges + 1
      end
      wasAttacking[z] = now
    elseif z then
      wasAttacking[z] = nil
    end
  end
end

-- (111) Empuje y pisoton a la velocidad de ataque: con bono de ataque (implante encendido o Black Lace) se prende la bandera de los nodos SandevistanShove_* y
-- cada variable de velocidad lleva base x el mismo factor que el golpe. La bandera no se cambia a mitad de un empuje (cambiar de nodo reinicia la animacion);
-- las velocidades si (solo cambia el ritmo). Solo se escribe cuando algo cambia.
C.shove = {}
function C.tickShove(p, idx)
  local A = CFG.Combat.ShoveAnim
  if not A or not A.Enabled then return end
  local st = C.shove[idx]
  if not st then st = { on = false, f = nil }; C.shove[idx] = st end
  local tier = speedTier(p)
  local want = tier ~= nil and ((tier.attackBoost or tier.playerBoost or 0) > 0)
  if want then
    local key = 0
    for _, base in ipairs(A.Bases) do key = key + C.speedFactor(tier, base) * base end
    if not st.f or math.abs(st.f - key) > 0.005 then
      st.f = key
      for _, base in ipairs(A.Bases) do
        pcall(p.setVariable, p, A.VarPrefix .. string.format("%03d", math.floor(base * 100 + 0.5)), base * C.speedFactor(tier, base))
      end
    end
  end
  if want ~= st.on then
    local shoving = false
    pcall(function() shoving = p:isDoShove() == true end)
    if shoving then return end
    if pcall(p.setVariable, p, A.Flag, want) then st.on = want end
    if not want then st.f = nil end
  end
end

local lastGrabScan = 0
local function onTick()
  local nowMs = S.realMs()
  if nowMs - lastGrabScan >= CFG.Kerenzikov.GrabScanMs then
    lastGrabScan = nowMs
    for idx = 0, getNumActivePlayers() - 1 do
      local p = getSpecificPlayer(idx)
      if p and not p:isDead() and Kerenzikov.isActive(p) then C.tickGrabDodge(p) end
    end
  end
  tickMeleeDelay()
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p and not p:isDead() then C.tickShove(p, idx) end
  end
  if C.trace then C.traceTick() end
  local now = S.realMs()
  for idx, e in pairs(pending) do
    if e.target then
      if now > e.untilMs then e.target = nil
      else
        local p = getSpecificPlayer(idx)
        local cur = e.target
        if p then pcall(function() cur = p:getCombatSpeed() end) end
        if p and cur < e.target * 0.99 then applyCombat(p, e.target) end
      end
    end
  end
end

Events.OnWeaponSwing.Add(S.safe("Combat.OnWeaponSwing", onWeaponSwing))
if Events.OnWeaponSwingHitPoint then
  Events.OnWeaponSwingHitPoint.Add(S.safe("Combat.OnWeaponSwingHitPoint", function(attacker)
    if attacker and attacker.getPlayerNum and instanceof(attacker, "IsoPlayer") and attacker:isLocalPlayer() then
      local e = pending[attacker:getPlayerNum()]
      if e then e.hit = true end
    end
  end))
end
Events.OnPlayerAttackFinished.Add(S.safe("Combat.OnPlayerAttackFinished", onAttackFinished))
Events.OnTick.Add(S.safe("Combat.OnTick", onTick))
Events.OnWeaponHitCharacter.Add(S.safe("Combat.OnWeaponHitCharacter", onWeaponHitCharacter))
Events.OnWeaponHitCharacter.Add(S.safe("Combat.CountHit", function(attacker, target) C.countHit(attacker, target) end))   -- (116) cuenta del anti-cheat
Events.OnZombieDead.Add(S.safe("Combat.OnZombieDead", onZombieDead))