-- Sandevistan / Immunodep (135): los efectos de la inmunodepresion sobre el cuerpo (21-plan-inmunodepresion.md, §3). Corre cada minuto de juego
-- (Periodic.minuteTick) y AMPLIFICA lo que el juego hizo en ese minuto, en vez de reemplazarlo, asi que lo que sirve contra eso sigue sirviendo:
--   heridas: una tirada de infeccion extra (la misma cuenta que el juego) en las heridas abiertas sin desinfectar ni venda limpia y sin antibioticos;
--            la subida de la infeccion x infectGrowth; los temporizadores de curacion (rasguño, corte, profunda, quemadura) bajan /healing.
--   resfrio: la subida de catchACold x coldCatch; la de coldStrength x coldStrength y su bajada /coldRecovery.
--   malestar: la subida de FOOD_SICKNESS y SICKNESS x sickness (sin la toxicidad herbal ni la nausea de la dosis casera: M.resnap).
-- Los valores del minuto anterior viven en memoria (no en el save): al cargar, el primer minuto solo mide. En multijugador el cuerpo lo maneja el
-- servidor: se aplica igual aca (para no esperar la sincronizacion) y se le manda la misma operacion acotada (server/Net.lua, N.body "immuno").
require "Sandevistan/Core"
require "Sandevistan/Effects"

local CFG = SandevistanConfig
local S = Sandevistan
local E = SandevistanEffects

SandevistanImmunodep = {}
local M = SandevistanImmunodep

M.snap = {}        -- [numJugador] = { ms, parts = { [i] = { inf, scr, cut, deep, burn } }, catch, cold, FOOD_SICKNESS, SICKNESS }
M.stats = { rolls = 0, infected = 0, grown = 0, held = 0, cold = 0, sick = 0 }   -- para el REPORTE

local TIMERS = { { "scr", "getScratchTime", "setScratchTime" }, { "cut", "getCutTime", "setCutTime" },
                 { "deep", "getDeepWoundTime", "setDeepWoundTime" }, { "burn", "getBurnTime", "setBurnTime" } }
local SICK_STATS = { "FOOD_SICKNESS", "SICKNESS" }

local function call(o, m, ...) local ok, v = pcall(o[m], o, ...); if ok then return v end return nil end
local function idx(player) local ok, i = pcall(function() return player:getPlayerNum() end); return ok and i or 0 end

-- N del juego para la tirada de infeccion de una parte (BodyPart.DamageUpdate de 42.21): Rand.Next(N) == 0 por cada 1/30 s. nil si esa parte no tira.
function M.vanillaOnsetN(bp)
  local V = CFG.Immunosuppressant.Immunodepression.Onset
  local deep, scr, cut = call(bp, "getDeepWoundTime") or 0, call(bp, "getScratchTime") or 0, call(bp, "getCutTime") or 0
  if deep <= 0 and scr <= 0 and cut <= 0 and (call(bp, "getStitchTime") or 0) <= 0 then return nil end
  local n = V.Base
  if not call(bp, "bandaged") then n = n - V.NoBandage
  elseif (call(bp, "getBandageLife") or 0) == 0 then n = n - V.DirtyBandage end
  if scr > 0 then n = n - V.Scratch end
  if cut > 0 then n = n - V.Cut end
  if deep > 0 then n = n - V.Deep end
  if call(bp, "haveGlass") then n = n - V.Glass end
  if (call(bp, "getBurnTime") or 0) > 0 then
    n = n - V.Burn
    if call(bp, "isNeedBurnWash") then n = n - V.BurnWash end
  end
  if call(bp, "hasDirtyClothing") then n = n - V.DirtyClothing end
  if call(bp, "hasBloodyClothing") then n = n - V.BloodyClothing end
  return math.max(V.Min, n)
end

-- ¿Puede tirar la infeccion extra? Herida abierta sin infectar, sin desinfectar (alcohol), sin venda limpia, y el jugador sin antibioticos.
function M.canInfect(player, bp)
  if call(bp, "isInfectedWound") or call(bp, "IsInfected") then return false end
  if (call(bp, "getAlcoholLevel") or 0) > 0 then return false end
  if call(bp, "bandaged") and (call(bp, "getBandageLife") or 0) > 0 then return false end
  if (call(player, "getReduceInfectionPower") or 0) > 0 then return false end
  return M.vanillaOnsetN(bp) ~= nil
end

-- Probabilidad de la tirada extra en "seconds" segundos reales: la del juego con (infectOnset - 1) veces mas tiradas.
function M.extraOnsetChance(n, seconds, mult)
  if not n or mult <= 1 or seconds <= 0 then return 0 end
  return 1 - math.exp(-30 * seconds * (mult - 1) / n)
end

-- Segundos reales del ultimo minuto de juego: lo medido, con tope en lo que dura un minuto a velocidad normal (una pausa no cuenta).
function M.realSeconds(snap, nowMs)
  local nominal = 2.5
  pcall(function() nominal = getGameTime():getMinutesPerDay() * 60 / 1440 end)
  if not snap or not snap.ms then return nominal end
  return math.max(0, math.min(nominal, (nowMs - snap.ms) / 1000))
end

-- Operacion para el servidor de una parte (indice 0..): solo lo que cambio.
local function send(player, op)
  if S.isMPClient() and not S.isEmpty(op) then
    op.op = "immuno"
    E.bodyNet(player, op)
  end
end

function M.tick(player, d)
  local i = idx(player)
  local ID = CFG.Immunosuppressant.Immunodepression
  if not S.immunodepOn() or (d.immunodep or 0) <= 0 then M.snap[i] = nil; return end
  local bd = call(player, "getBodyDamage")
  if not bd then return end
  local prev = M.snap[i]
  local nowMs = S.realMs()
  local cur = { ms = nowMs, parts = {} }
  local traits = E.immunoTraits(player)
  local fx = {}
  for _, k in ipairs({ "infectOnset", "infectGrowth", "healing", "coldCatch", "coldStrength", "coldRecovery", "sickness" }) do fx[k] = S.immunoEffect(d, k, traits) end
  local seconds = M.realSeconds(prev, nowMs)
  local parts = call(bd, "getBodyParts")
  local n = parts and parts:size() or 0
  for pi = 0, n - 1 do
    local bp = parts:get(pi)
    local p0 = prev and prev.parts[pi]
    local op = {}
    -- tirada de infeccion extra
    if fx.infectOnset > 1 and M.canInfect(player, bp) then
      M.stats.rolls = M.stats.rolls + 1
      if S.chance(M.extraOnsetChance(M.vanillaOnsetN(bp), seconds, fx.infectOnset)) then
        pcall(bp.setInfectedWound, bp, true)
        op.infect = true
        M.stats.infected = M.stats.infected + 1
      end
    end
    local now = { inf = call(bp, "getWoundInfectionLevel") or 0 }
    -- avance de la infeccion: solo la subida
    if p0 and fx.infectGrowth > 1 and call(bp, "isInfectedWound") and now.inf > p0.inf then
      local add = math.min(ID.Net.InfLevel, (now.inf - p0.inf) * (fx.infectGrowth - 1))
      now.inf = math.min(10, now.inf + add)
      pcall(bp.setWoundInfectionLevel, bp, now.inf)
      op.lvl = add
      M.stats.grown = M.stats.grown + 1
    end
    -- curacion: se devuelve parte de lo que bajo cada temporizador (si la herida sigue abierta)
    for _, t in ipairs(TIMERS) do
      local v = call(bp, t[2]) or 0
      if p0 and fx.healing > 1 and v > 0 and p0[t[1]] and v < p0[t[1]] then
        local back = math.min(ID.Net.Timer, (p0[t[1]] - v) * (1 - 1 / fx.healing))
        v = v + back
        pcall(bp[t[3]], bp, v)
        op[t[1]] = back
        M.stats.held = M.stats.held + 1
      end
      now[t[1]] = v
    end
    cur.parts[pi] = now
    if not S.isEmpty(op) then op.part = pi; send(player, op) end
  end
  -- resfrio
  local catch, cold = call(bd, "getCatchACold") or 0, call(bd, "getColdStrength") or 0
  if prev and prev.catch then
    local op = {}
    if fx.coldCatch > 1 and catch > prev.catch then
      local add = math.min(ID.Net.Cold, (catch - prev.catch) * (fx.coldCatch - 1))
      catch = math.min(100, catch + add); pcall(bd.setCatchACold, bd, catch); op.catch = add
    end
    if call(bd, "isHasACold") then
      if fx.coldStrength > 1 and cold > prev.cold then
        local add = math.min(ID.Net.Cold, (cold - prev.cold) * (fx.coldStrength - 1))
        cold = math.min(100, cold + add); pcall(bd.setColdStrength, bd, cold); op.cold = add
      elseif fx.coldRecovery > 1 and cold < prev.cold and cold > 0 then
        local back = math.min(ID.Net.Cold, (prev.cold - cold) * (1 - 1 / fx.coldRecovery))
        cold = cold + back; pcall(bd.setColdStrength, bd, cold); op.cold = back
      end
    end
    if not S.isEmpty(op) then M.stats.cold = M.stats.cold + 1; send(player, op) end
  end
  cur.catch, cur.cold = catch, cold
  -- malestar por comida y por cadaveres (en multijugador E.addStat ya se lo avisa al servidor)
  for _, st in ipairs(SICK_STATS) do
    local v = E.getStat(player, st)
    if prev and prev[st] and fx.sickness > 1 and v > prev[st] then
      E.addStat(player, st, (v - prev[st]) * (fx.sickness - 1))
      v = E.getStat(player, st)
      M.stats.sick = M.stats.sick + 1
    end
    cur[st] = v
  end
  M.snap[i] = cur
end

-- Vuelve a medir el malestar sin amplificarlo (lo que puso el mod: toxicidad herbal, nausea de la dosis casera).
function M.resnap(player)
  local s = M.snap[idx(player)]
  if not s then return end
  for _, st in ipairs(SICK_STATS) do s[st] = E.getStat(player, st) end
end

return M
