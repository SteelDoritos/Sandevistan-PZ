-- Sandevistan / TestSuite: la PRUEBA COMPLETA de Debug, de una sola vez y en un solo txt (Zomboid/Lua/Sandevistan_report.txt).
--   1. autotest de sistemas (FullTest: tiempo simulado, restaura el estado al terminar)
--   2. multijugador: diagnóstico local y respuesta del servidor (MPTest; en SP se anota y se sigue)
--   3. dilatación medida en el juego, ~30 s reales: 5 s con el implante apagado (velocidad normal de los zombis cercanos) y 25 s
--      encendido. v0.1.30 (13): velocidades por ventanas de 0.5 s (SpeedMeter) y separadas por quién simula a cada zombi (este cliente
--      o la red), más los "recién soltados" (salieron del radio hace < 2 s: si corren de más, se están poniendo al día con la posición
--      que tenía el servidor). En multijugador el servidor mide lo mismo de su lado (mpMeasure): si él los ve a velocidad normal, el
--      frenado es solo visual en este cliente. También mide el rendimiento del mod en ese tramo. Mientras dura: invulnerable, Heat
--      en 0, estamina llena y sin carga neuronal; al final se repone TODO el estado del implante como estaba.
--   4. reporte con todas las secciones (Report.lua lee TS.results).
require "Sandevistan/Core"
require "Sandevistan/SpeedMeter"
require "Sandevistan/Net"
require "Sandevistan/Runtime"
require "Sandevistan/Slowdown"
require "Sandevistan/Effects"
require "Sandevistan/Report"

local CFG = SandevistanConfig
local S = Sandevistan
local R = SandevistanRuntime
local SD = SandevistanSlowdown
local E = SandevistanEffects
local SM = SandevistanSpeedMeter

SandevistanTestSuite = { results = nil }
local TS = SandevistanTestSuite

TS.MP_WAIT_MS = 6000
TS.BASE_MS, TS.ON_MS = 5000, 25000
TS.MEASURE_RANGE = 30                 -- tiles alrededor del jugador en los que se siguen zombis
TS.RELEASED_MS = 2000                 -- "recién soltado": salió del radio de frenado hace menos que esto
TS.SERVER_WAIT_MS = 4000              -- después del tramo encendido, cuánto se espera la medición del servidor
-- categorías de la medición (en un jugador todos los zombis son "own": los simula este mismo proceso)
TS.CATS = { "base.own", "base.rem", "slow.own", "slow.rem", "released", "free.own", "free.rem" }

local run = nil

local PHASE_NAMES = { fulltest = "autotest", mp = "multijugador", base = "dilatacion: base 5 s", on = "dilatacion: 25 s",
                      serverwait = "esperando al servidor", report = "reporte" }

function TS.running() return run ~= nil end
function TS.phaseName() return run and (PHASE_NAMES[run.phase] or run.phase) or "-" end

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = deepcopy(v) end
  return c
end

local function say(p, text)
  S.log("prueba completa: " .. text)
  pcall(function() p:Say(text) end)
end

-- Seguimiento de zombis por ventanas de 0.5 s, por categoría: fase, frenado o no, y quién lo simula (isRemoteZombie: en multijugador,
-- los que simula el servidor u otro cliente llegan por la red; este cliente solo puede atrasar su dibujo, no frenarlos de verdad).
local function track(m, p, now, onPhase)
  local cell = getCell()
  local zl = cell and cell:getZombieList()
  if not zl then return end
  local px, py = p:getX(), p:getY()
  local r2 = TS.MEASURE_RANGE * TS.MEASURE_RANGE
  for i = 0, zl:size() - 1 do
    local z = zl:get(i)
    if z and not z:isDead() then
      local x, y = z:getX(), z:getY()
      local dx, dy = x - px, y - py
      if dx * dx + dy * dy <= r2 then
        -- en un jugador todos los zombis los simula este mismo proceso (el reporte los tomaba por "red"): solo en un cliente MP cuenta isRemoteZombie
        local okR, remote = pcall(z.isRemoteZombie, z)
        local own = not (isClient() and okR and remote == true)
        local name
        if not onPhase then
          name = own and "base.own" or "base.rem"
        elseif SD.slowed[z] then
          m.lastSlow[z] = now
          name = own and "slow.own" or "slow.rem"
        elseif m.lastSlow[z] and now - m.lastSlow[z] < TS.RELEASED_MS then
          name = "released"
        else
          name = own and "free.own" or "free.rem"
        end
        SM.sample(m.meter, z, x, y, name, now)
      end
    end
  end
  SM.sweep(m.meter, now)
end

-- Medición del lado del servidor (solo multijugador): pide que mida los zombis alrededor de este jugador durante "ms".
local function askServer(phase, ms)
  if not isClient() or not run then return end
  run.results.server = run.results.server or {}
  run.results.server.asked = true
  pcall(sendClientCommand, run.p, "Sandevistan", "mpMeasure", { phase = phase, ms = ms, range = CFG.SpatialSlow.Radius })
end

function TS.onServerMeasure(args)
  local res = run and run.results or TS.results
  if not res or type(args) ~= "table" or not args.phase then return end
  res.server = res.server or {}
  res.server[args.phase] = args
end

-- Mantiene al jugador en condiciones de medir: implante encendido, sin calor, sin carga, sin rechazo, con estamina.
local function holdActive(p, d)
  d.heat, d.lockUntilCool, d.rejection, d.neuralLoad, d.cyberpsychosisActive = 0, false, 0, 0, false
  E.setEndurance(p, 1)
  local s = R.session(p)
  if not s.active then
    s.reuseAtMs = 0
    R.activate(p)
  end
end

function TS.start(p)
  if run then return end
  local d = S.data(p)
  run = { p = p, phase = "fulltest", t0 = S.clockMs(), results = {}, keepPerf = S.perf }
  TS.results = run.results
  run.results.startedHour = S.worldHours()
  run.results.implant = tostring(d.variant)
  local N = rawget(_G, "SandevistanNet")
  if N and N.handlers then N.handlers.mpMeasureReply = S.safe("TestSuite.serverMeasure", TS.onServerMeasure) end
  say(p, "Prueba completa: 1/3 autotest...")
  -- el autotest simula miles de ticks: sus tiempos no se mezclan con los de la partida
  S.perf = { since = S.clockMs(), spans = {}, counts = {} }
  local F = rawget(_G, "SandevistanFullTest")
  if not F then run.results.fulltest = "no disponible"; TS.next("mp"); return end
  F.afterFinish = function() if run then TS.next("mp") end end
  local ok, err = pcall(F.run, p)
  if not ok then run.results.fulltest = "error: " .. tostring(err); TS.next("mp") end
end

function TS.next(phase)
  if not run then return end
  local p = run.p
  run.phase, run.phaseAt = phase, S.clockMs()
  if phase == "mp" then
    S.perf = run.keepPerf
    local MP = rawget(_G, "SandevistanMPTest")
    run.results.mpClient = isClient()
    if MP then pcall(MP.run, p) end
    say(p, "Prueba completa: 2/3 multijugador...")
  elseif phase == "base" then
    local d = S.data(p)
    -- copia del estado para reponerlo al final
    local md = p:getModData()
    run.snap, run.ksnap = deepcopy(md.Sandevistan), deepcopy(md.Kerenzikov)
    pcall(function() if S.perk() then run.perkLevel = p:getPerkLevel(S.perk()) end end)
    run.endurance = E.getEndurance(p)
    local god = false
    pcall(function() god = p:isGodMod() == true end)
    run.god = god
    pcall(function() p:setGodMod(true) end)
    R.deactivate(p, "forced")
    run.m = { meter = SM.new(), lastSlow = {} }
    run.canMeasure = S.hasWorkingImplant(d)
    if not run.canMeasure then run.results.dilation = "sin implante operativo instalado: la medicion de la dilatacion se salta" end
    if run.canMeasure then askServer("base", TS.BASE_MS) end
    say(p, "Prueba completa: 3/3 dilatacion (quedate cerca de zombis 30 s)...")
  elseif phase == "on" then
    S.perfReset()                                   -- rendimiento: solo el tramo con el implante encendido
    holdActive(p, S.data(p))
    askServer("on", TS.ON_MS)
  elseif phase == "serverwait" then
    R.deactivate(p, "forced")
  elseif phase == "report" then
    TS.finish()
  end
end

function TS.finish()
  if not run then return end
  local p, res = run.p, run.results
  if run.m then
    local m = run.m.meter
    local cats = {}
    for _, name in ipairs(TS.CATS) do cats[name] = SM.result(m, name) end
    local function ratio(a, b) return (a and b and a.speed and b.speed and a.speed > 0) and b.speed / a.speed or nil end
    res.dil = {
      cats = cats,
      base = SM.merged(m, { "base.own", "base.rem" }), slow = SM.merged(m, { "slow.own", "slow.rem" }),
      expected = run.expectedZs,
      radius = CFG.SpatialSlow.Radius,
      windowMs = SM.WINDOW_MS, fast = SM.FAST,
      animMarked = S.perf.counts["dilatacion.animacionLenta"] or 0,
    }
    res.dil.ratio = ratio(res.dil.base, res.dil.slow)
    res.dil.ratioOwn = ratio(cats["base.own"], cats["slow.own"])
    res.dil.ratioRem = ratio(cats["base.rem"], cats["slow.rem"])
  end
  -- reponer el estado del implante como estaba
  if run.snap then
    local md = p:getModData()
    R.deactivate(p, "forced")
    md.Sandevistan, md.Kerenzikov = run.snap, run.ksnap
    R.sessions[p:getPlayerNum()] = nil
    E.setEndurance(p, run.endurance or 1)
    pcall(function() p:setGodMod(run.god == true) end)
    S.resetPerkTo(p, md.Sandevistan, run.perkLevel)
    S.syncPerk(p)
  end
  res.seconds = (S.clockMs() - run.t0) / 1000
  run = nil
  local RP = rawget(_G, "SandevistanReport")
  if RP then RP.export(p) end
  say(p, "Prueba completa terminada: Zomboid/Lua/" .. (RP and RP.FILE or "Sandevistan_report.txt"))
end

function TS.cancel(reason)
  if not run then return end
  if run.results then run.results.cancelled = reason or "cancelada" end
  local F = rawget(_G, "SandevistanFullTest")
  if F then F.afterFinish = nil end
  TS.finish()
end

function TS.tick()
  if not run then return end
  local p, now = run.p, S.clockMs()
  if not p or p:isDead() then TS.cancel("el jugador murio"); return end
  local age = now - (run.phaseAt or now)
  if run.phase == "mp" then
    local MP = rawget(_G, "SandevistanMPTest")
    local done = not isClient() or (MP and MP.gotReply) or age > TS.MP_WAIT_MS
    if done then
      run.results.mpLines = MP and MP.lines or {}
      run.results.mpReply = MP and MP.gotReply or false
      TS.next("base")
    end
  elseif run.phase == "base" then
    if not run.canMeasure then TS.next("report"); return end
    track(run.m, p, now, false)
    if age >= TS.BASE_MS then TS.next("on") end
  elseif run.phase == "on" then
    holdActive(p, S.data(p))
    local eff = R.session(p).eff
    if eff and eff.zombieSpeed then run.expectedZs = eff.zombieSpeed end
    track(run.m, p, now, true)
    if age >= TS.ON_MS then
      local srv = run.results.server
      TS.next((srv and srv.asked and not srv.on) and "serverwait" or "report")
    end
  elseif run.phase == "serverwait" then
    local srv = run.results.server
    if (srv and srv.on) or age >= TS.SERVER_WAIT_MS then TS.next("report") end
  end
end

-- Después del tick de Runtime (el archivo carga después): se leen las posiciones ya amortiguadas.
Events.OnTick.Add(S.safe("TestSuite.OnTick", TS.tick))

return TS
