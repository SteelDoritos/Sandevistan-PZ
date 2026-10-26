-- Sandevistan / PerfTest: la PRUEBA DE RENDIMIENTO de Debug (v0.1.30 (39)). Un solo txt: Zomboid/Lua/Sandevistan_perf.txt.
-- Mide cuanto cuesta el mod en escenarios de carga creciente, con zombis creados por la propia prueba (y borrados al terminar):
--   1. sin zombis, implante apagado                 (linea base del juego solo)
--   2. N zombis,   implante apagado                 (lo que cuestan los zombis sin el mod)
--   3. N zombis,   implante encendido               (dilatacion, animaciones lentas, estelas, HUD, sonidos)
--   4. M zombis,   implante encendido
--   5. M zombis,   OVERDRIVE sostenido              (estelas mas densas, efectos al maximo)
-- Cada etapa descarta los primeros segundos (calentamiento: los zombis se acomodan) y mide el resto: ticks por segundo, intervalo entre ticks (promedio,
-- peor, % de ticks lentos), el tiempo de cada handler del mod (S.perf, el mismo de S.safe) y la distancia que recorriste (las estelas solo se generan si te
-- mueves: hay que correr en circulos durante las etapas con el implante encendido). El costo del mod se ve comparando 2 contra 3.
-- Mientras dura: invulnerable, Heat/Rechazo/CN en 0 y estamina llena; al final se repone TODO el estado del implante como estaba y se borran los zombis.
-- Crear zombis: addZombiesInOutfit funciona en un jugador o anfitrion; un cliente de multijugador puro puede no poder (el txt lo anota y mide con los zombis
-- que haya). Los zombis de la prueba llevan la marca SandevistanPerf en su ModData: si el juego se cierra en medio, al cargar la partida se barren.
--
-- v0.1.30 (62): PRUEBA PROGRESIVA de la dilatacion (preset "lod", un solo txt: Zomboid/Lua/Sandevistan_lod.txt). Con 150 zombis que te persiguen, sube de a un
-- escalon el salto con que se actualizan los zombis LEJANOS (Config.SlowLOD.FarMs: 0 = todos los ticks, 20, 40, ... 300 ms) y en cada uno mide
--   costo:    Slowdown.tick por llamada, el mod por tick, ticks por segundo, pasadas por segundo
--   calidad:  la velocidad media de los lejanos (tiene que seguir igual) y cuanto se apartan de su trayectoria suavizada (vibracion, en px a zoom 1)
--   tu ojo:   una pregunta Si / No por nivel ("se ven fluidos los de lejos?"); dos No seguidos cortan la subida
-- El primer nivel es el camino de antes de la (62) (Config.SlowLOD.Enabled = false) para comparar. Al final el txt propone el FarMs mas alto que contestaste Si.
require "Sandevistan/Core"
require "Sandevistan/Runtime"
require "Sandevistan/Slowdown"
require "Sandevistan/Effects"
require "Sandevistan/SpeedMeter"
require "Sandevistan/Dialog"

local CFG = SandevistanConfig
local S = Sandevistan
local R = SandevistanRuntime
local E = SandevistanEffects

SandevistanPerfTest = {}
local PT = SandevistanPerfTest

PT.FILE = "Sandevistan_perf.txt"
PT.WARMUP_MS = 2500
PT.MEASURE_MS = 12000
PT.SPAWN_PER_TICK = 6                 -- zombis que se crean por tick (todos de golpe congelaria el juego)
PT.SPAWN_TRIES = 12                   -- intentos de encontrar un cuadro libre por zombi
PT.RING = { 7, 15 }                   -- radio (tiles) del anillo donde aparecen
PT.NEAR = 30                          -- "zombis cerca": dentro de estos tiles
PT.SLOW_TICK_MS = { 33, 50, 100, 250 }
PT.PRESETS = { normal = { 30, 80 }, heavy = { 60, 150 } }

-- Prueba progresiva de la dilatacion (preset "lod")
PT.LOD_FILE = "Sandevistan_lod.txt"
PT.LOD_ZOMBIES = 150
PT.LOD_RING = { 10, 13 }              -- aparecen alrededor del punto donde empezaste (no de donde estes en ese momento: todos los niveles parten igual), dentro del radio de la dilatacion
PT.LOD_MEASURE_MS = 10000             -- los zombis se te acercan con el tiempo (y dejan de ser lejanos): la medicion de cada nivel es mas corta
PT.LOD_SAMPLE = 24                    -- zombis lejanos cuya posicion se registra en cada tick para medir la vibracion y la velocidad
PT.LOD_WINDOW_MS = 600                -- ventana del promedio centrado contra el que se compara cada posicion
PT.LOD_ASK_MS = 90000                 -- tiempo maximo para contestar la pregunta de cada nivel
PT.LOD_HUNT_PER_TICK = 2              -- zombis a los que se les vuelve a avisar donde estas en cada tick (rotando)
PT.PX_X, PT.PX_Y = 64, 32             -- a zoom 1, una casilla en x o en y mueve la imagen (64, 32) px (isometrico)
PT.LOD_LEVELS = {                     -- de menos a mas salto: FarMs = cada cuanto se actualiza cada zombi lejano (la guarda de velocidad, FarMaxJump, se apaga para medir el FarMs puro)
  { id = "antes", label = "como antes de la (62): cada zombi, cada tick",            lod = { Enabled = false } },
  { id = "f0",    label = "camino nuevo, lejanos en todos los ticks",                lod = { Enabled = true, FarMs = 0, FarMaxJump = 0 } },
  { id = "f20",   label = "lejanos cada 20 ms",                                      lod = { Enabled = true, FarMs = 20, FarMaxJump = 0 } },
  { id = "f40",   label = "lejanos cada 40 ms",                                      lod = { Enabled = true, FarMs = 40, FarMaxJump = 0 } },
  { id = "f60",   label = "lejanos cada 60 ms",                                      lod = { Enabled = true, FarMs = 60, FarMaxJump = 0 } },
  { id = "f90",   label = "lejanos cada 90 ms",                                      lod = { Enabled = true, FarMs = 90, FarMaxJump = 0 } },
  { id = "f130",  label = "lejanos cada 130 ms",                                     lod = { Enabled = true, FarMs = 130, FarMaxJump = 0 } },
  { id = "f200",  label = "lejanos cada 200 ms",                                     lod = { Enabled = true, FarMs = 200, FarMaxJump = 0 } },
  { id = "f300",  label = "lejanos cada 300 ms (exagerado, para tener la referencia)", lod = { Enabled = true, FarMs = 300, FarMaxJump = 0 } },
  { id = "defecto", label = "configuracion por defecto (Config.SlowLOD tal cual, con la guarda de velocidad: lo que se juega)", lod = {}, final = true },
}

local run = nil
PT.last = nil                         -- resultado de la ultima corrida (el reporte puede leerlo)
function PT.running() return run ~= nil end
function PT.stageName()
  if not run then return "-" end
  local st = run.stages[run.idx]
  return st and (run.idx .. "/" .. #run.stages .. " " .. st.label) or "-"
end

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = deepcopy(v) end
  return c
end

local function say(p, text)
  S.log("prueba de rendimiento: " .. text)
  pcall(function() p:Say(text) end)
end

local function makeStages(low, high)
  return {
    { id = "base",  label = "sin zombis, implante apagado",                  zombies = 0,    active = false },
    { id = "zoff",  label = low .. " zombis, implante apagado",              zombies = low,  active = false },
    { id = "zon",   label = low .. " zombis, implante encendido",            zombies = low,  active = true },
    { id = "zhigh", label = high .. " zombis, implante encendido",          zombies = high, active = true },
    { id = "od",    label = high .. " zombis, OVERDRIVE sostenido",          zombies = high, active = true, overdrive = true },
  }
end

local function makeLodStages(n)
  local list = { { id = "ref", label = "referencia: " .. n .. " zombis, implante apagado", zombies = n, active = false, respawn = true } }
  for i, lv in ipairs(PT.LOD_LEVELS) do
    list[#list + 1] = { id = lv.id, label = "nivel " .. i .. ": " .. lv.label, desc = lv.label, zombies = n, active = true, respawn = true, lod = lv.lod, ask = true, level = i, final = lv.final }
  end
  return list
end

---------------------------------------------------------------------------
-- Zombis de la prueba
---------------------------------------------------------------------------
local function markZombie(z)
  pcall(function() z:getModData().SandevistanPerf = true end)
end

local function freeSquare(p)
  local cell = getCell()
  local px, py, pz = p:getX(), p:getY(), p:getZ()
  if run and run.kind == "lod" and run.cx then px, py = run.cx, run.cy end
  for _ = 1, PT.SPAWN_TRIES do
    local ang = ZombRandFloat(0, 6.2832)
    local ring = (run and run.kind == "lod") and PT.LOD_RING or PT.RING
    local r = ZombRandFloat(ring[1], ring[2])
    local sq = cell:getGridSquare(math.floor(px + math.cos(ang) * r), math.floor(py + math.sin(ang) * r), math.floor(pz))
    local free = false
    if sq then pcall(function() free = sq:isFree(false) end) end
    if free then return sq end
  end
  return nil
end

-- Crea un zombi en un cuadro libre del anillo. Devuelve true si se creo.
function PT.spawnOne(p)
  local sq = freeSquare(p)
  if not sq then run.noSquare = (run.noSquare or 0) + 1; return false end
  local list = nil
  local ok = pcall(function() list = addZombiesInOutfit(sq:getX(), sq:getY(), sq:getZ(), 1, nil, 50) end)
  if not ok or not list then run.spawnErrors = (run.spawnErrors or 0) + 1; return false end
  local made = 0
  pcall(function()
    for i = 0, list:size() - 1 do
      local z = list:get(i)
      markZombie(z)
      run.spawned[#run.spawned + 1] = z
      made = made + 1
      if run.hunt then pcall(z.spotted, z, run.p, true) end
    end
  end)
  if made == 0 then run.spawnErrors = (run.spawnErrors or 0) + 1 end
  return made > 0
end

local function removeZombie(z)
  pcall(function() z:removeFromWorld() end)
  pcall(function() z:removeFromSquare() end)
end

-- Borra los zombis de la prueba (los que creo esta corrida y, por si quedaron de un cierre del juego, cualquiera con la marca). Devuelve cuantos.
function PT.sweep()
  local n = 0
  if run then
    for _, z in ipairs(run.spawned) do removeZombie(z); n = n + 1 end
    run.spawned = {}
  end
  pcall(function()
    local zl = getCell():getZombieList()
    local marked = {}
    for i = 0, zl:size() - 1 do
      local z = zl:get(i)
      local m = nil
      pcall(function() m = z:getModData().SandevistanPerf end)
      if m then marked[#marked + 1] = z end
    end
    for _, z in ipairs(marked) do removeZombie(z); n = n + 1 end
  end)
  return n
end

local function zombieCounts(p)
  local total, near = 0, 0
  pcall(function()
    local zl = getCell():getZombieList()
    total = zl:size()
    local px, py = p:getX(), p:getY()
    for i = 0, total - 1 do
      local z = zl:get(i)
      local dx, dy = z:getX() - px, z:getY() - py
      if dx * dx + dy * dy <= PT.NEAR * PT.NEAR then near = near + 1 end
    end
  end)
  return total, near
end

local function memoryKB()
  local kb = nil
  pcall(function() kb = collectgarbage("count") end)
  return kb
end

---------------------------------------------------------------------------
-- Estado del jugador
---------------------------------------------------------------------------
local function hold(p, st)
  local d = S.data(p)
  d.heat, d.lockUntilCool, d.rejection, d.neuralLoad, d.cyberpsychosisActive = 0, false, 0, 0, false
  E.setEndurance(p, 1)
  local s = R.session(p)
  if st.active then
    if not s.active then s.reuseAtMs = 0; R.activate(p) end
    if st.overdrive then
      if not s.overdrive and s.active then R.startOverdrive(p) end
      s.overdriveUntilMs = S.gameMs() + 1500                   -- nunca llega al colapso: se sostiene mientras dure la etapa. (194) Reloj de juego,
                                                               -- como Runtime (127): con el real, despues de un avance rapido colapsaba en cada tick
    end
  else
    if s.active then R.deactivate(p, "forced") end
  end
end

---------------------------------------------------------------------------
-- Prueba progresiva: nivel de detalle, muestreo de posiciones y analisis
---------------------------------------------------------------------------
-- Pone Config.SlowLOD del escalon (siempre partiendo de la configuracion original) y avisa a Slowdown para que vuelva a elegir.
local function applyLod(st)
  local L = CFG.SlowLOD
  if not (L and run and run.lodBase) then return end
  for k, v in pairs(run.lodBase) do L[k] = v end
  if st.lod then for k, v in pairs(st.lod) do L[k] = v end end
  local SD = rawget(_G, "SandevistanSlowdown")
  if SD and SD.lodChanged then SD.lodChanged() end
end

local function restoreLod()
  local L = CFG.SlowLOD
  if not (L and run and run.lodBase) then return end
  for k, v in pairs(run.lodBase) do L[k] = v end
  local SD = rawget(_G, "SandevistanSlowdown")
  if SD and SD.lodChanged then SD.lodChanged() end
end

-- Elige los zombis cuya posicion se registra: lejanos (mas alla de NearTiles + 1 casillas) y, con el implante encendido, frenados.
local function pickSample(p, st)
  local SD = rawget(_G, "SandevistanSlowdown")
  local L = CFG.SlowLOD
  local limit = ((L and L.NearTiles) or 8) + 1
  local px, py = p:getX(), p:getY()
  local cands = {}
  for _, z in ipairs(run.spawned) do
    local ok, x, y = pcall(function() return z:getX(), z:getY() end)
    if ok then
      local dx, dy = x - px, y - py
      if dx * dx + dy * dy >= limit * limit and (not st.active or (SD and SD.slowed[z])) then cands[#cands + 1] = z end
    end
  end
  local step = math.max(1, math.floor(#cands / PT.LOD_SAMPLE))
  local zs = {}
  for i = 1, #cands, step do
    if #zs < PT.LOD_SAMPLE then zs[#zs + 1] = cands[i] end
  end
  st.smp = { zs = zs, T = {}, X = {}, Y = {}, limit2 = limit * limit, candidates = #cands }
  for k = 1, #zs do st.smp.X[k], st.smp.Y[k] = {}, {} end
end

-- Un renglon por tick: posicion de cada zombi de la muestra (false si en ese tick no cuenta: ya no esta frenado o se acerco a menos de NearTiles + 1).
local function recordSample(p, st, now)
  local smp = st.smp
  if not smp then return end
  local SD = rawget(_G, "SandevistanSlowdown")
  local slowed = SD and SD.slowed or {}
  local n = #smp.T + 1
  smp.T[n] = now
  local px, py = p:getX(), p:getY()
  local lim2, needSlowed = smp.limit2, st.active
  local zs, X, Y = smp.zs, smp.X, smp.Y
  for k = 1, #zs do
    local z = zs[k]
    local x, y = z:getX(), z:getY()
    local ok = (not needSlowed) or slowed[z] ~= nil
    if ok then
      local dx, dy = x - px, y - py
      ok = dx * dx + dy * dy >= lim2
    end
    X[k][n], Y[k][n] = ok and x or false, y
  end
end

-- Vibracion y velocidad de una serie de posiciones: smp = { zs, T = {ms}, X = { [k] = { x | false } }, Y = { [k] = { y } } }.
--   vibracion: distancia (px a zoom 1) entre cada posicion y el promedio de las posiciones de +-windowMs/2 alrededor (solo ventanas enteras y validas);
--     un zombi que avanza parejo da 0; los saltos de actualizacion (FarMs) aparecen como desvio. Media, percentil 95 y maximo.
--   velocidad: la del medidor de la PRUEBA COMPLETA (desplazamiento neto en ventanas de 0.5 s, sin las quietas).
function PT.analyzeSeries(smp, windowMs)
  local SM = SandevistanSpeedMeter
  local half = (windowMs or PT.LOD_WINDOW_MS) / 2
  local BIN, NB = 0.25, 400
  local bins = {}
  for i = 1, NB + 1 do bins[i] = 0 end
  local n, sum, max, tracked = 0, 0, 0, 0
  local T = smp.T
  local last = #T
  local m = SM.new()
  local pxx, pxy = PT.PX_X, PT.PX_Y
  for k = 1, #smp.zs do
    local key, X, Y = smp.zs[k], smp.X[k], smp.Y[k]
    local lo, hi = 1, 0
    local sx, sy, cnt, bad = 0, 0, 0, 0
    local any = false
    for i = 1, last do
      local xi = X[i]
      if xi then SM.sample(m, key, xi, Y[i], "lod", T[i]); any = true else m.z[key] = nil end
      while hi < last and T[hi + 1] <= T[i] + half do
        hi = hi + 1
        local xv = X[hi]
        if xv then sx = sx + xv; sy = sy + Y[hi]; cnt = cnt + 1 else bad = bad + 1 end
      end
      while T[lo] < T[i] - half do
        local xv = X[lo]
        if xv then sx = sx - xv; sy = sy - Y[lo]; cnt = cnt - 1 else bad = bad - 1 end
        lo = lo + 1
      end
      if xi and bad == 0 and cnt > 0 and T[i] - T[1] >= half and T[last] - T[i] >= half then
        local ex, ey = xi - sx / cnt, Y[i] - sy / cnt
        local d = math.sqrt(((ex - ey) * pxx) ^ 2 + ((ex + ey) * pxy) ^ 2)
        n = n + 1; sum = sum + d
        if d > max then max = d end
        local b = math.floor(d / BIN) + 1
        if b > NB + 1 then b = NB + 1 end
        bins[b] = bins[b] + 1
      end
    end
    if any then tracked = tracked + 1 end
  end
  local p95 = nil
  if n > 0 then
    local target, acc = n * 0.95, 0
    for b = 1, NB + 1 do
      acc = acc + bins[b]
      if acc >= target then p95 = b * BIN; break end
    end
  end
  local res = SM.result(m, "lod")
  return { n = n, mean = n > 0 and sum / n or nil, p95 = p95, max = n > 0 and max or nil, tracked = tracked,
           speed = res and res.speed or nil, windows = res and res.windows or 0, snaps = res and res.snaps or 0 }
end

local function closeAsk()
  if run and run.askWin then
    pcall(function() run.askWin:setVisible(false); run.askWin:removeFromUIManager() end)
    run.askWin = nil
  end
end

-- Pregunta Si / No en una ventana chica arriba a la izquierda (se arrastra); el nivel sigue andando mientras contestas.
local function beginAsk(p, st)
  run.phase, run.phaseAt = "ask", S.clockMs()
  run.answer = nil
  local text = " <RGB:1,1,1> Nivel " .. tostring(st.level) .. " de " .. #PT.LOD_LEVELS .. ": " .. tostring(st.desc or st.label) .. " <LINE> <LINE> "
    .. "Se ven fluidos los zombis de LEJOS al moverse? <LINE> Si = se ven bien. No = se nota que vibran, saltan o patinan. <LINE> <LINE> "
    .. "(Segui corriendo mientras decidis; este nivel sigue activo hasta que contestes.)"
  local D = rawget(_G, "SandevistanDialog")
  local win = nil
  pcall(function()
    win = D and D.yesNo(p:getPlayerNum(), text, 400, 240, function(yes)
      if run and run.phase == "ask" then run.answer = yes and "si" or "no" end
    end, "Sandevistan: prueba progresiva")
  end)
  if win then
    run.askWin = win
    pcall(function() win:setX(16); win:setY(16) end)
  else
    run.answer = "sin ventana"
  end
end

---------------------------------------------------------------------------
-- Etapas
---------------------------------------------------------------------------
local function measureMs() return run.kind == "lod" and PT.LOD_MEASURE_MS or PT.MEASURE_MS end

local function beginStage(p)
  local st = run.stages[run.idx]
  run.phase, run.phaseAt = "warmup", S.clockMs()
  if run.kind == "lod" then
    applyLod(st)
    if st.respawn then PT.sweep() end                 -- zombis nuevos en el anillo: los del nivel anterior ya se te vinieron encima
    run.hunt = st.active
  end
  st.startTotal, st.startNear = zombieCounts(p)
  say(p, "Etapa " .. PT.stageName() .. (st.active and " (correr en circulos)" or ""))
end

-- (132) Motor de estelas con pose real (mod opcional SandevistanViewpoint; desde la 136 tambien en isometrico): si trae medidor,
-- se pone en cero al medir y se anota por etapa.
local function backend()
  local A = rawget(_G, "SandevistanAfterimages")
  return A and A.backend or nil
end

local function beginMeasure(p)
  local st = run.stages[run.idx]
  run.phase, run.phaseAt = "measure", S.clockMs()
  S.perfReset()
  local b3 = backend()
  if b3 and b3.reset then pcall(b3.reset) end
  st.ticks, st.sumDt, st.maxDt = 0, 0, 0
  st.slow = {}
  for i = 1, #PT.SLOW_TICK_MS do st.slow[i] = 0 end
  st.dist = 0
  st.lastX, st.lastY = p:getX(), p:getY()
  st.lastTick = nil
  st.memStart = memoryKB()
  st.midTotal, st.midNear = zombieCounts(p)
  if run.kind == "lod" then
    local ok, err = pcall(pickSample, p, st)
    if not ok then run.errors = (run.errors or 0) + 1; S.log("prueba progresiva: no se pudo elegir la muestra: " .. tostring(err)) end
    local SD = rawget(_G, "SandevistanSlowdown")
    if SD and SD.lod and CFG.SlowLOD.Enabled then st.lodStart = { near = SD.lod.near, far = SD.lod.far, fast = SD.lod.fast } end       -- el camino de antes no arma las listas
  end
end

local function endStage(p)
  local st = run.stages[run.idx]
  local secs = math.max(0.001, (S.clockMs() - run.phaseAt) / 1000)
  st.secs = secs
  st.spans = deepcopy(S.perf.spans)
  st.counts = deepcopy(S.perf.counts)
  st.memEnd = memoryKB()
  st.endTotal, st.endNear = zombieCounts(p)
  local SD = rawget(_G, "SandevistanSlowdown")
  if SD then
    local n = 0
    for _ in pairs(SD.slowed) do n = n + 1 end
    st.slowed = n
  end
  local sp = st.spans["Runtime.OnTick"]
  st.tps = sp and sp.calls / secs or (st.ticks / secs)
  local modTotal = 0
  for name, s2 in pairs(st.spans) do
    if not string.find(name, " > ", 1, true) and not string.find(name, "^PerfTest") then modTotal = modTotal + s2.total end
  end
  st.modMs = modTotal
  st.modPct = 100 * modTotal / (secs * 1000)
  st.modPerTick = st.ticks > 0 and modTotal / st.ticks or 0
  st.frameAvg = st.ticks > 0 and st.sumDt / st.ticks or 0
  local V = rawget(_G, "SandevistanViewport")
  st.view3D = false
  pcall(function() st.view3D = V and V.is3D() == true end)
  local b3 = backend()
  if b3 and b3.perf then
    local ok, txt = pcall(b3.perf)
    if ok then st.vp = tostring(txt) end
  end
  st.hudOn = false
  pcall(function() st.hudOn = SandevistanHUD and SandevistanHUD.instance and SandevistanHUD.instance:getHeight() > 0 end)
  if run.kind == "lod" then
    if SD and SD.lod and CFG.SlowLOD.Enabled then st.lodEnd = { near = SD.lod.near, far = SD.lod.far, fast = SD.lod.fast } end
    st.lodCfg = deepcopy(CFG.SlowLOD)
    if st.smp then
      local ok, q = pcall(PT.analyzeSeries, st.smp, PT.LOD_WINDOW_MS)
      if ok then
        q.sampled, q.candidates = #st.smp.zs, st.smp.candidates
        st.q = q
      else
        run.errors = (run.errors or 0) + 1
        S.log("prueba progresiva: fallo el analisis de la muestra: " .. tostring(q))
      end
      st.smp = nil                                            -- las series ocupan memoria: ya no hacen falta
    end
  end
end

---------------------------------------------------------------------------
-- Arranque y cierre
---------------------------------------------------------------------------
-- preset: "normal" (30 / 80 zombis) o "heavy" (60 / 150)
function PT.start(p, preset)
  if run then return false end
  local d = S.data(p)
  if not S.hasWorkingImplant(d) then
    say(p, "La prueba de rendimiento necesita un implante operativo instalado")
    return false
  end
  local counts = PT.PRESETS[preset or "normal"] or PT.PRESETS.normal
  local kind = preset == "lod" and "lod" or "perf"
  local md = p:getModData()
  run = { p = p, kind = kind, stages = kind == "lod" and makeLodStages(PT.LOD_ZOMBIES) or makeStages(counts[1], counts[2]), idx = 1, spawned = {}, t0 = S.clockMs(),
          keepPerf = S.perf, preset = preset or "normal", lodBase = deepcopy(CFG.SlowLOD),
          snap = deepcopy(md.Sandevistan), ksnap = deepcopy(md.Kerenzikov), endurance = E.getEndurance(p) }
  pcall(function() if S.perk() then run.perkLevel = p:getPerkLevel(S.perk()) end end)
  local god = false
  pcall(function() god = p:isGodMod() == true end)
  run.god = god
  pcall(function() p:setGodMod(true) end)
  R.deactivate(p, "forced")
  S.perf = { since = S.clockMs(), spans = {}, counts = {} }
  S.perfDetail = true                                       -- (194) Psychosis.tick mide cada subsistema
  local IS = rawget(_G, "SandevistanInstallScene")
  if IS then run.sceneSuppress = IS.suppress; IS.suppress = true end
  if kind == "lod" then
    run.cx, run.cy = p:getX(), p:getY()
    say(p, "Prueba progresiva de la dilatacion (" .. #run.stages .. " etapas, ~" .. math.floor(#run.stages * (PT.WARMUP_MS + PT.LOD_MEASURE_MS) / 1000) .. " s mas lo que tardes en contestar). "
      .. "Quedate en un lugar abierto y corre en circulos grandes; cuando aparezca la pregunta contesta con el mouse sin dejar de correr")
  else
    say(p, "Prueba de rendimiento (" .. #run.stages .. " etapas, ~" .. math.floor(#run.stages * (PT.WARMUP_MS + PT.MEASURE_MS) / 1000) .. " s). Quedate en un lugar abierto y corre en circulos cuando el implante este encendido")
  end
  beginStage(p)
  return true
end

local function fmt(v, f) return string.format(f or "%.2f", v or 0) end
local function fmtn(v, f) if v == nil then return "-" end return string.format(f or "%.2f", v) end
local function pct(a, b) if a and b and b > 0 then return string.format("%+.0f%%", 100 * (a / b - 1)) end return "-" end

-- Detalle de una etapa (lo comparten los dos informes): ticks, ticks lentos, handlers del mod y contadores.
local function stageDetail(add, st, extra)
  if not st.secs then return end
  add("== etapa: " .. st.label)
  if extra then extra(add, st) end
  add(string.format("medido %.1f s | ticks = %d | HUD visible = %s | memoria Lua KB (ini -> fin) = %s -> %s | zombis cargados ini/medio/fin = %d/%d/%d",
    st.secs, st.ticks, tostring(st.hudOn), tostring(st.memStart and math.floor(st.memStart) or "?"), tostring(st.memEnd and math.floor(st.memEnd) or "?"),
    st.startTotal or 0, st.midTotal or 0, st.endTotal or 0))
  add("camara = " .. (st.view3D and "3D (Viewpoint)" or "isometrica") .. (st.vp and (" | estelas (jar): " .. st.vp) or ""))
  add(string.format("ticks lentos: > %d ms = %d, > %d ms = %d, > %d ms = %d, > %d ms = %d", PT.SLOW_TICK_MS[1], st.slow[1], PT.SLOW_TICK_MS[2], st.slow[2],
    PT.SLOW_TICK_MS[3], st.slow[3], PT.SLOW_TICK_MS[4], st.slow[4]))
  local names = {}
  for name in pairs(st.spans) do if not string.find(name, "^PerfTest") then names[#names + 1] = name end end
  table.sort(names, function(a, b) return st.spans[a].total > st.spans[b].total end)
  add("handler | llamadas | ms promedio | ms max | ms total | % del tiempo")
  for i, name in ipairs(names) do
    -- (194) los tramos de la cyberpsicosis salen siempre, aunque no esten entre los 18 primeros
    if i <= 18 or string.find(name, "^Psychosis >") then
      local sp = st.spans[name]
      add(string.format("%s | %d | %.3f | %d | %d | %.2f%%", name, sp.calls, sp.total / math.max(1, sp.calls), sp.max, sp.total, 100 * sp.total / (st.secs * 1000)))
    end
  end
  local cnames = {}
  for name in pairs(st.counts) do cnames[#cnames + 1] = name end
  table.sort(cnames)
  for _, name in ipairs(cnames) do add(string.format("contador %s = %d (%.1f por segundo)", name, st.counts[name], st.counts[name] / st.secs)) end
  add("")
end

-- Lineas del txt (se arman aparte para poder probarlas sin archivo)
function PT.buildLines(p, res)
  local L = {}
  local function add(s) L[#L + 1] = s end
  add("# Sandevistan " .. tostring(CFG.Version) .. ": prueba de rendimiento")
  add("preset = " .. tostring(res.preset) .. ", duracion total = " .. fmt(res.seconds, "%.0f") .. " s, calentamiento " .. PT.WARMUP_MS / 1000 .. " s + medicion " .. PT.MEASURE_MS / 1000 .. " s por etapa")
  add("implante = " .. tostring(res.variant) .. ", nivel = " .. tostring(res.level) .. ", multijugador (cliente) = " .. tostring(res.isClient) .. ", servidor = " .. tostring(res.isServer))
  local w, h = 0, 0
  pcall(function() w, h = getCore():getScreenWidth(), getCore():getScreenHeight() end)
  add("pantalla = " .. tostring(w) .. "x" .. tostring(h))
  add("zombis pedidos por etapa / creados en total = " .. tostring(res.requestedMax) .. " / " .. tostring(res.created)
    .. "  (sin cuadro libre: " .. tostring(res.noSquare or 0) .. ", errores al crear: " .. tostring(res.spawnErrors or 0) .. ")")
  if res.created == 0 and res.requestedMax > 0 then
    add("AVISO: no se pudo crear ningun zombi (un cliente de multijugador puro puede no poder). Las etapas con zombis midieron solo los que ya habia.")
  end
  add("zombis borrados al terminar = " .. tostring(res.removed))
  if res.cancelled then add("CANCELADA: " .. tostring(res.cancelled)) end
  add("")
  add("== resumen")
  add("etapa | zombis cerca (ini/fin) | ticks por s | intervalo medio ms | peor ms | % ticks > 33 ms | mod ms/tick | mod % del tiempo | frenados | distancia recorrida (tiles)")
  for _, st in ipairs(res.stages) do
    if st.secs then
      add(string.format("%s | %d/%d | %.1f | %.1f | %d | %.1f%% | %.3f | %.2f%% | %s | %.0f", st.label, st.startNear or 0, st.endNear or 0, st.tps or 0,
        st.frameAvg, st.maxDt, st.ticks > 0 and 100 * st.slow[1] / st.ticks or 0, st.modPerTick, st.modPct, tostring(st.slowed or "-"), st.dist))
    else
      add(st.label .. " | no se midio")
    end
  end
  add("")
  add("== lectura")
  local by = {}
  for _, st in ipairs(res.stages) do by[st.id] = st end
  if by.zoff and by.zon and by.zoff.secs and by.zon.secs then
    local dT = (by.zoff.tps or 0) - (by.zon.tps or 0)
    local dF = by.zon.frameAvg - by.zoff.frameAvg
    add(string.format("costo del mod con %d zombis: %.1f ticks por segundo menos (%.1f -> %.1f), intervalo entre ticks +%.1f ms; el mod mide %.3f ms por tick (%.2f%% del tiempo)",
      by.zon.endNear or 0, dT, by.zoff.tps or 0, by.zon.tps or 0, dF, by.zon.modPerTick, by.zon.modPct))
  end
  if by.zon and by.zhigh and by.zon.secs and by.zhigh.secs then
    add(string.format("al subir de carga: mod %.3f -> %.3f ms por tick, ticks por segundo %.1f -> %.1f", by.zon.modPerTick, by.zhigh.modPerTick, by.zon.tps or 0, by.zhigh.tps or 0))
  end
  if by.od and by.od.secs then add(string.format("OVERDRIVE sostenido: mod %.3f ms por tick (%.2f%%)", by.od.modPerTick, by.od.modPct)) end
  local worst = 0
  for _, st in ipairs(res.stages) do if st.secs and st.active and st.modPerTick > worst then worst = st.modPerTick end end
  local verdict = worst < 1 and "OK (menos de 1 ms por tick)" or (worst < 3 and "MEDIO (1 a 3 ms por tick)" or "ALTO (mas de 3 ms por tick: conviene optimizar)")
  add("veredicto del peor caso con el implante encendido: " .. fmt(worst, "%.3f") .. " ms por tick = " .. verdict)
  for _, st in ipairs(res.stages) do
    if st.secs and st.active and st.dist < 5 then
      add("AVISO: en '" .. st.label .. "' casi no te moviste (" .. fmt(st.dist, "%.1f") .. " tiles): las estelas casi no se generaron, el costo de esa parte esta subestimado")
    end
  end
  add("")
  for _, st in ipairs(res.stages) do stageDetail(add, st) end
  return L
end

-- Umbral objetivo de vibracion (px a zoom 1, percentil 95) para sugerir un nivel cuando no hay respuestas tuyas
PT.LOD_P95_OK = 2.0

-- Informe de la prueba progresiva (Sandevistan_lod.txt)
function PT.buildLodLines(p, res)
  local L = {}
  local function add(s) L[#L + 1] = s end
  local stages = res.stages
  local by = {}
  for _, st in ipairs(stages) do by[st.id] = st end
  local function slowAvg(st)                                             -- ms por llamada de Runtime > Slowdown.tick
    local sp = st and st.spans and st.spans["Runtime > Slowdown.tick"]
    if sp and sp.calls > 0 then return sp.total / sp.calls, sp end
    return nil, sp
  end
  local function farLabel(st)
    if not st.active then return "-" end
    local lod = st.lodCfg or st.lod                                    -- la configuracion efectiva del nivel
    if not lod then return "-" end
    if lod.Enabled == false then return "cada tick (camino de antes)" end
    if (lod.FarMs or 0) <= 0 then return "cada tick" end
    return lod.FarMs .. " ms" .. ((st.tps and st.tps > 0) and string.format(" (~cada %.1f ticks)", lod.FarMs * st.tps / 1000) or "")
      .. ((lod.FarMaxJump or 0) > 0 and (" con guarda de velocidad (" .. lod.FarMaxJump .. ")") or "")
  end
  local function lodCount(t) if not t then return "-" end return t.near .. "/" .. t.far .. ((t.fast or 0) > 0 and (" (rapidos " .. t.fast .. ")") or "") end
  add("# Sandevistan " .. tostring(CFG.Build) .. ": prueba progresiva de la dilatacion (cada cuanto se actualizan los zombis lejanos)")
  add("zombis por nivel = " .. PT.LOD_ZOMBIES .. " (aparecen a " .. PT.LOD_RING[1] .. "-" .. PT.LOD_RING[2] .. " casillas del punto donde empezaste y te persiguen), calentamiento " .. PT.WARMUP_MS / 1000
    .. " s + medicion " .. PT.LOD_MEASURE_MS / 1000 .. " s por nivel, duracion total = " .. fmt(res.seconds, "%.0f") .. " s (con lo que tardaste en contestar)")
  add("implante = " .. tostring(res.variant) .. ", nivel = " .. tostring(res.level) .. ", multijugador (cliente) = " .. tostring(res.isClient) .. ", servidor = " .. tostring(res.isServer))
  local w, h, zoom = 0, 0, nil
  pcall(function() w, h = getCore():getScreenWidth(), getCore():getScreenHeight() end)
  pcall(function() zoom = getCore():getZoom(0) end)
  add("pantalla = " .. tostring(w) .. "x" .. tostring(h) .. ", zoom = " .. tostring(zoom) .. " (los px de la vibracion son a zoom 1: una casilla mueve la imagen " .. PT.PX_X .. " px en x o "
    .. PT.PX_Y .. " en y; con otro zoom se achican o agrandan en esa proporcion)")
  local base = res.lodBase or {}
  add("configuracion de partida = Enabled " .. tostring(base.Enabled) .. ", SelectMs " .. tostring(base.SelectMs) .. ", NearTiles " .. tostring(base.NearTiles) .. ", FarMs " .. tostring(base.FarMs)
    .. ", FarMaxJump " .. tostring(base.FarMaxJump) .. " (la prueba la repone al terminar; en los niveles apaga la guarda de velocidad: FarMaxJump = 0)")
  add("zombis creados en total = " .. tostring(res.created) .. "  (sin cuadro libre: " .. tostring(res.noSquare or 0) .. ", errores al crear: " .. tostring(res.spawnErrors or 0)
    .. "), borrados al terminar = " .. tostring(res.removed))
  if res.created == 0 then add("AVISO: no se pudo crear ningun zombi: las etapas midieron solo los que ya habia.") end
  if res.cancelled then add("CANCELADA: " .. tostring(res.cancelled)) end
  if res.stopNote then add("SALTEO: " .. tostring(res.stopNote)) end
  if res.errors and res.errors > 0 then add("AVISO: " .. res.errors .. " errores internos de la prueba (console.txt, buscar 'prueba progresiva')") end
  add("")
  add("== resumen")
  add("nivel | salto de los lejanos | Slowdown.tick ms por llamada | contra antes | mod ms por tick | ticks por s | pasadas por s | us por pasada | refrescos por s | cercanos/lejanos (fin) | velocidad de los lejanos casillas/s | desvio medio px | desvio p95 px | desvio max px | zombis medidos | tu respuesta")
  local baseAvg = slowAvg(by.antes)
  local baseSpeed = by.antes and by.antes.q and by.antes.q.speed
  for _, st in ipairs(stages) do
    if st.secs then
      local avg, sp = slowAvg(st)
      local q = st.q or {}
      local c = st.counts or {}
      local apps = c["dilatacion.zombisFrenados"] or 0
      add(string.format("%s | %s | %s | %s | %.3f | %.1f | %.0f | %s | %.1f | %s | %s | %s | %s | %s | %s | %s",
        st.label, farLabel(st), fmtn(avg, "%.3f"), pct(avg, baseAvg),
        st.modPerTick or 0, st.tps or 0, apps / st.secs, (sp and apps > 0) and string.format("%.1f", sp.total * 1000 / apps) or "-", (c["dilatacion.escaneos"] or 0) / st.secs,
        lodCount(st.lodEnd), fmtn(q.speed, "%.3f"), fmtn(q.mean), fmtn(q.p95), fmtn(q.max),
        q.tracked and (q.tracked .. "/" .. tostring(q.sampled)) or "-", tostring(st.answer or "-")))
    else
      add(st.label .. " | no se midio")
    end
  end
  add("")
  add("== lectura")
  local ref, f0 = by.ref, by.f0
  if baseAvg and f0 and f0.secs then
    local a0 = slowAvg(f0)
    if a0 then
      add(string.format("camino nuevo sin saltear ticks: Slowdown.tick %.3f -> %.3f ms por llamada (%s), mod %.3f -> %.3f ms por tick",
        baseAvg, a0, pct(a0, baseAvg), by.antes.modPerTick or 0, f0.modPerTick or 0))
    end
  end
  -- velocidad media: tiene que quedar igual que en el camino de antes
  for _, st in ipairs(stages) do
    local q = st.q
    if st.secs and st.active and q and q.speed and baseSpeed and baseSpeed > 0 and st.id ~= "antes" then
      local ratio = q.speed / baseSpeed
      if ratio < 0.85 or ratio > 1.15 then
        add(string.format("AVISO: en '%s' la velocidad media de los lejanos fue %.0f%% de la del camino de antes (la compensacion no deberia cambiarla; puede ser el ruido de zombis distintos en cada nivel)", st.label, 100 * ratio))
      end
    end
    if st.secs and st.active and q and (q.tracked or 0) >= 6 and (q.speed == nil or q.speed < 0.05) then
      add("AVISO: en '" .. st.label .. "' los zombis lejanos casi no se movieron (velocidad media " .. fmtn(q.speed, "%.3f") .. " casillas/s): si no te persiguen no hay nada que ver ni medir; avisame")
    end
    if st.secs and st.active and q and (q.tracked or 0) < 6 then
      add("AVISO: en '" .. st.label .. "' se siguieron pocos zombis lejanos (" .. tostring(q.tracked or 0) .. "): la vibracion medida es poco fiable")
    end
    if st.secs and st.active and (st.dist or 0) < 5 then
      add("AVISO: en '" .. st.label .. "' casi no te moviste (" .. fmt(st.dist, "%.1f") .. " tiles): las estelas casi no se generaron y los zombis no te siguieron igual")
    end
  end
  if ref and ref.secs then add(string.format("referencia (implante apagado): %.1f ticks por segundo; con la dilatacion encendida en el camino de antes: %.1f", ref.tps or 0, by.antes and by.antes.tps or 0)) end
  -- recomendacion: el nivel mas alto con Si y sin ningun No en los de menos salto
  local best, blocked, answered = nil, false, 0
  for _, st in ipairs(stages) do
    if st.secs and st.ask and st.lod and st.lod.Enabled and st.lod.FarMs ~= nil then
      if st.answer == "no" then blocked = true end
      if st.answer == "si" or st.answer == "no" then answered = answered + 1 end
      if st.answer == "si" and not blocked then best = st end
    end
  end
  add("")
  add("== recomendacion")
  local function cfgLine(ms) return string.format("Config.SlowLOD = { Enabled = true, SelectMs = %d, NearTiles = %d, FarMs = %d, FarMaxJump = %s }", base.SelectMs or 150, base.NearTiles or 8, ms, tostring(base.FarMaxJump or 0.015)) end
  if best then
    local avg = slowAvg(best)
    add("el nivel mas alto con Si y sin un No antes: " .. best.label)
    add(cfgLine(best.lod.FarMs))
    if avg and baseAvg then
      add(string.format("Slowdown.tick con ese nivel: %.3f ms por llamada contra %.3f del camino de antes (%s)", avg, baseAvg, pct(avg, baseAvg)))
    end
    local appsBest = best.counts and best.counts["dilatacion.zombisFrenados"]
    local appsBase = by.antes and by.antes.counts and by.antes.counts["dilatacion.zombisFrenados"]
    if appsBest and appsBase and best.secs and by.antes.secs then
      local a, b = appsBest / best.secs, appsBase / by.antes.secs
      add(string.format("pasadas por segundo: %.0f contra %.0f del camino de antes (%s)", a, b, pct(a, b)))
    end
    if best.q and best.q.p95 then add(string.format("vibracion medida en ese nivel: media %.2f px, p95 %.2f px (el nivel siguiente que te parecio mal se ve en la tabla de arriba)", best.q.mean or 0, best.q.p95)) end
  elseif answered > 0 then
    add("ningun nivel con salto te parecio bien: conviene dejar FarMs = 0 (el camino nuevo sin saltear ticks ya ahorra lo que muestra la tabla)")
    add(cfgLine(0))
  else
    -- sin respuestas: se sugiere por la medicion
    local pick = nil
    for _, st in ipairs(stages) do
      if st.secs and st.ask and st.lod and st.lod.Enabled and (st.lod.FarMs or 0) > 0 and st.q and st.q.p95 and st.q.p95 <= PT.LOD_P95_OK then pick = st end
    end
    add("no contestaste ninguna pregunta: solo hay medicion (umbral usado: p95 de la vibracion <= " .. fmt(PT.LOD_P95_OK, "%.1f") .. " px a zoom 1)")
    if pick then
      add("el nivel mas alto dentro del umbral: " .. pick.label)
      add(cfgLine(pick.lod.FarMs))
    else
      add("ningun nivel con salto entra en el umbral: " .. cfgLine(0))
    end
  end
  local def = by.defecto
  if def and def.secs then
    local avg = slowAvg(def)
    add("configuracion por defecto (la que se juega, con la guarda de velocidad): " .. tostring(def.answer or "sin respuesta") .. "; Slowdown.tick " .. fmtn(avg, "%.3f") .. " ms por llamada ("
      .. pct(avg, baseAvg) .. " contra el camino de antes), zombis lejanos tratados como cercanos por su velocidad = " .. tostring(def.lodEnd and def.lodEnd.fast or "-"))
    if def.answer == "no" then add("AVISO: la configuracion por defecto no te parecio fluida: hay que bajar FarMs o FarMaxJump") end
  end
  add("")
  for _, st in ipairs(stages) do
    stageDetail(add, st, function(add2, s2)
      add2("nivel de detalle: " .. farLabel(s2) .. " | configuracion = " .. (s2.lodCfg and string.format("Enabled %s, SelectMs %s, NearTiles %s, FarMs %s, FarMaxJump %s", tostring(s2.lodCfg.Enabled),
        tostring(s2.lodCfg.SelectMs), tostring(s2.lodCfg.NearTiles), tostring(s2.lodCfg.FarMs), tostring(s2.lodCfg.FarMaxJump)) or "-") .. " | cercanos/lejanos al inicio y al fin = "
        .. lodCount(s2.lodStart) .. " y " .. lodCount(s2.lodEnd))
      local q = s2.q
      if q then
        add2(string.format("muestra: %s zombis lejanos seguidos de %s candidatos | ventanas de vibracion evaluadas = %d | ventanas de velocidad = %d | saltos de posicion > 0.8 casillas en un tick = %d",
          tostring(q.tracked), tostring(q.candidates), q.n or 0, q.windows or 0, q.snaps or 0))
      end
      if s2.answer then add2(string.format("respuesta: %s (en %.0f s)", tostring(s2.answer), (s2.answerMs or 0) / 1000)) end
    end)
  end
  return L
end

function PT.finish(reason)
  if not run then return end
  local p = run.p
  local res = { kind = run.kind, preset = run.preset, stages = run.stages, cancelled = reason, seconds = (S.clockMs() - run.t0) / 1000, stopNote = run.stopNote,
                errors = run.errors, lodBase = run.lodBase }
  local d0 = S.data(p)
  res.variant, res.level = tostring(d0.variant), S.level(d0)
  res.isClient, res.isServer = isClient(), isServer()
  res.created, res.noSquare, res.spawnErrors = run.created or 0, run.noSquare, run.spawnErrors
  res.requestedMax = 0
  for _, st in ipairs(run.stages) do if st.zombies > res.requestedMax then res.requestedMax = st.zombies end end
  -- reponer todo
  closeAsk()
  restoreLod()
  R.deactivate(p, "forced")
  res.removed = PT.sweep()
  if run.snap then
    local md = p:getModData()
    md.Sandevistan, md.Kerenzikov = run.snap, run.ksnap
    R.sessions[p:getPlayerNum()] = nil
    E.setEndurance(p, run.endurance or 1)
    S.resetPerkTo(p, md.Sandevistan, run.perkLevel)
    S.syncPerk(p)
  end
  pcall(function() p:setGodMod(run.god == true) end)
  local IS = rawget(_G, "SandevistanInstallScene")
  if IS then IS.suppress = run.sceneSuppress == true end
  S.perf = run.keepPerf
  S.perfDetail = nil
  run = nil
  PT.last = res
  local isLod = res.kind == "lod"
  local file = isLod and PT.LOD_FILE or PT.FILE
  local okB, lines = pcall(isLod and PT.buildLodLines or PT.buildLines, p, res)
  if not okB then lines = { "# no se pudo armar el informe: " .. tostring(lines) } end
  local wrote = pcall(function()
    local w = getFileWriter(file, true, false)
    if not w then error("sin escritor") end
    for _, l in ipairs(lines) do w:write(S.ascii(l) .. "\n") end
    w:close()
  end)
  S.log("prueba de rendimiento: " .. #lines .. " lineas, " .. (wrote and ("escrito en Zomboid/Lua/" .. file) or "NO se pudo escribir"))
  say(p, wrote and ((isLod and "Prueba progresiva terminada: Zomboid/Lua/" or "Prueba de rendimiento terminada: Zomboid/Lua/") .. file) or "No se pudo escribir el txt de la prueba")
  return lines
end

function PT.cancel(reason) PT.finish(reason or "cancelada") end

---------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------
local function nextStage(p)
  local st = run.stages[run.idx]
  if run.kind == "lod" and st.ask and st.lod and st.lod.FarMs and st.lod.FarMs > 0 then
    run.noStreak = (run.answerOf == "no") and ((run.noStreak or 0) + 1) or 0
    if run.noStreak >= 2 then
      -- subir mas no agrega informacion: se salta a la configuracion por defecto (siempre se prueba, es la que se va a jugar)
      run.stopNote = "se saltearon los niveles que faltan tras el nivel " .. tostring(st.level) .. ": dos 'No' seguidos (subir mas no agrega informacion); se pasa a la configuracion por defecto"
      run.noStreak = 0
      if run.idx < #run.stages - 1 then run.idx = #run.stages - 1 end
    end
  end
  if run.idx >= #run.stages then PT.finish(); return end
  run.idx = run.idx + 1
  beginStage(p)
end

function PT.tick()
  if not run then return end
  local p, now = run.p, S.clockMs()
  if not p or p:isDead() then PT.finish("el jugador murio"); return end
  local st = run.stages[run.idx]
  if not S.hasWorkingImplant(S.data(p)) then PT.finish("el implante dejo de estar operativo"); return end
  hold(p, st)
  -- crear zombis hasta el objetivo de la etapa (por tandas)
  local made, guard = 0, 0
  while #run.spawned < st.zombies and made < PT.SPAWN_PER_TICK and guard < PT.SPAWN_PER_TICK * 3 do
    guard = guard + 1
    if PT.spawnOne(p) then made = made + 1; run.created = (run.created or 0) + 1 end
  end
  -- prueba progresiva: se les vuelve a avisar donde estas, de a pocos por tick, para que no pierdan el rastro
  if run.hunt and #run.spawned > 0 then
    for _ = 1, PT.LOD_HUNT_PER_TICK do
      run.huntAt = (run.huntAt or 0) % #run.spawned + 1
      local z = run.spawned[run.huntAt]
      if z then pcall(z.spotted, z, p, true) end
    end
  end
  if run.phase == "warmup" then
    if now - run.phaseAt >= PT.WARMUP_MS then beginMeasure(p) end
  elseif run.phase == "measure" then
    -- intervalo entre ticks y distancia recorrida
    if st.lastTick then
      local dt = now - st.lastTick
      st.ticks = st.ticks + 1
      st.sumDt = st.sumDt + dt
      if dt > st.maxDt then st.maxDt = dt end
      for i, lim in ipairs(PT.SLOW_TICK_MS) do if dt > lim then st.slow[i] = st.slow[i] + 1 end end
    end
    st.lastTick = now
    local x, y = p:getX(), p:getY()
    st.dist = st.dist + math.sqrt((x - st.lastX) ^ 2 + (y - st.lastY) ^ 2)
    st.lastX, st.lastY = x, y
    if st.smp then
      local ok, err = pcall(recordSample, p, st, now)
      if not ok then st.smp = nil; run.errors = (run.errors or 0) + 1; S.log("prueba progresiva: fallo el registro de posiciones: " .. tostring(err)) end
    end
    if now - run.phaseAt >= measureMs() then
      endStage(p)
      if run.kind == "lod" and st.ask then beginAsk(p, st); return end
      nextStage(p)
    end
  elseif run.phase == "ask" then
    local timedOut = now - run.phaseAt >= PT.LOD_ASK_MS
    if run.answer ~= nil or timedOut then
      st.answer = run.answer or "sin respuesta"
      run.answerOf = run.answer
      st.answerMs = now - run.phaseAt
      closeAsk()
      run.answer = nil
      nextStage(p)
    end
  end
end

Events.OnTick.Add(S.safe("PerfTest.OnTick", PT.tick))

-- Si el juego se cerro en medio de una prueba, los zombis marcados quedaron guardados: se barren al cargar.
Events.OnGameStart.Add(S.safe("PerfTest.sweepOnStart", function() if not run then PT.sweep() end end))

return PT
