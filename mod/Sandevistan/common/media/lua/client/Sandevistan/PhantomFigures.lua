-- Sandevistan / PhantomFigures (cliente, 0.7 (181)): C13.2, figuras fantasma de la cyberpsicosis (31 §10.2). Con cyberpsicosis activa, de a ratos
-- una figura se entrevé al costado de lo que ves, a unas 8-13 casillas: semitransparente y oscura, quieta mirandote o caminando despacio de
-- costado. Nunca embiste ni toca y no hace ningun ruido (esa es su pista). Si la miras de frente un momento, o te acercas, se deshace; si no, se
-- va sola. Nadie mas la ve y no se guarda.
-- El dibujo lo pone el mod opcional SandevistanPsychosis: es un titere zombi como los zombis falsos (mismo backend, FZ.backend), con alfa baja.
-- Sin ese jar no hay figuras (quedan las marcas fantasma de siempre). Aca va toda la logica.
require "Sandevistan/Core"
require "Sandevistan/Psychosis"
require "Sandevistan/FakeZombies"

local CFG = SandevistanConfig
local S = Sandevistan
local P = SandevistanPsychosis
local FZ = SandevistanFakeZombies

-- Los ids de los titeres son de un solo mapa en el jar: zombis falsos desde 1, el clon desde 1e6, el disfraz desde 2e6, las figuras desde 3e6.
SandevistanPhantomFigures = { list = {}, nextId = 3000000, spawned = 0, looked = 0, near = 0, expired = 0, noRoom = 0, errors = 0 }
local PF = SandevistanPhantomFigures

local function C() return CFG.Psychosis.PhantomFigures end
local function lerp(a, b, t) return a + (b - a) * t end
local function rnd(a, b) return lerp(a, b, ZombRandFloat(0, 1)) end
local function backend() return FZ.backend end

function PF.ready() return FZ.ready() end

-- Activas para este jugador: opcion encendida (y las alucinaciones), el jar listo, cyberpsicosis activa en la etapa MinStage, despierto y a pie.
function PF.active(player, d)
  local c = C()
  if not (c and c.Enabled) or CFG.NeuralLoad.Hallucinations == false or not PF.ready() then return false end
  if not d.cyberpsychosisActive or P.stage(d) < (c.MinStage or 2) then return false end
  if player:isAsleep() then return false end
  local inCar = false
  pcall(function() inCar = player:getVehicle() ~= nil end)
  return not inCar
end

local function forward(player)
  local fx, fy = 0, 1
  pcall(function() fx, fy = player:getForwardDirectionX(), player:getForwardDirectionY() end)
  local len = math.sqrt(fx * fx + fy * fy)
  if len < 1e-4 then return 0, 1 end
  return fx / len, fy / len
end

-- La casilla se ve ahora (en el cono de vision y con luz): el titere solo se dibuja ahi (Puppets.render).
local function visible(x, y, z, pn)
  local cell = getCell()
  local sq = cell and cell:getGridSquare(math.floor(x), math.floor(y), z)
  if not sq then return false end
  local ok, can = pcall(function() return sq:isCanSee(pn) end)
  return ok and can == true
end

-- Un lugar al costado de lo que ves: el rumbo del jugador girado SideDeg grados (a un lado o al otro), a Dist casillas, en una casilla libre que
-- se este viendo. nil si no hay.
function PF.pickPos(player, c)
  local fx, fy = forward(player)
  local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ())
  local pn = player:getPlayerNum()
  for _ = 1, (c.Tries or 8) do
    local ang = rnd(c.SideDeg[1], c.SideDeg[2]) * math.pi / 180 * (ZombRandFloat(0, 1) < 0.5 and -1 or 1)
    local ca, sa = math.cos(ang), math.sin(ang)
    local dx, dy = fx * ca - fy * sa, fx * sa + fy * ca
    local dist = rnd(c.Dist[1], c.Dist[2])
    local x, y = px + dx * dist, py + dy * dist
    if FZ.canStep(x, y, x, y, pz) and visible(x, y, pz, pn) then return x, y, pz end
  end
  return nil
end

-- Nace una figura. forced (Debug) = sin pedir cyberpsicosis (solo el jar). Devuelve la figura o nil.
function PF.spawn(player, forced)
  local c = C()
  local b = backend()
  if not b then return nil end
  local x, y, z = PF.pickPos(player, c)
  if not x then PF.noRoom = PF.noRoom + 1; return nil end
  local id = PF.nextId
  PF.nextId = PF.nextId + 1
  local female = ZombRandFloat(0, 1) < 0.5
  local outfits = c.Outfits or CFG.Psychosis.FakeZombies.Outfits
  local ok, born = pcall(b.spawn, id, outfits[ZombRand(#outfits) + 1], female, x, y, z, player:getPlayerNum())
  if not ok or born ~= true then
    if not ok then PF.errors = PF.errors + 1; S.warnOnce("figureSpawn", "figura fantasma: " .. tostring(born)) end
    return nil
  end
  local f = { id = id, idx = player:getPlayerNum(), x = x, y = y, z = z, bornMs = S.realMs(), lookMs = 0, forced = forced == true,
              lifeMs = rnd(c.LifeSeconds[1], c.LifeSeconds[2]) * 1000 }
  -- caminando: de costado (perpendicular a la linea con el jugador), despacio; si no, quieta mirandote
  if ZombRandFloat(0, 1) < (c.WalkChance or 0.5) then
    local dx, dy = x - player:getX(), y - player:getY()
    local len = math.max(1e-3, math.sqrt(dx * dx + dy * dy))
    local side = ZombRandFloat(0, 1) < 0.5 and 1 or -1
    f.wx, f.wy = -dy / len * side, dx / len * side
    pcall(b.var, id, "zombieWalkType", "1")
    pcall(b.var, id, "bMoving", "true")
  else
    pcall(b.var, id, "bMoving", "false")
  end
  pcall(b.look, id, c.Alpha or 0.35, c.Tint[1], c.Tint[2], c.Tint[3])
  PF.face(f, player)
  PF.list[#PF.list + 1] = f
  PF.spawned = PF.spawned + 1
  S.log(string.format("figura fantasma: nace %d a %.1f casillas (%s)", id, math.sqrt((x - player:getX()) ^ 2 + (y - player:getY()) ^ 2),
    f.wx and "caminando" or "quieta"))
  return f
end

-- Quieta: de frente al jugador. Caminando: hacia donde va.
function PF.face(f, player)
  local b = backend()
  if f.wx then
    pcall(b.move, f.id, f.x, f.y, f.z, 0, 0, f.wx, f.wy)
    return
  end
  local dx, dy = player:getX() - f.x, player:getY() - f.y
  pcall(b.move, f.id, f.x, f.y, f.z, 0, 0, dx, dy)
end

-- Empieza a deshacerse ("look", "near", "expired"). Mirarla o acercarse cuenta como descubrirla (estado mental legible, 179).
function PF.dissolve(f, why, player)
  if f.fadeAt then return end
  f.fadeAt = S.realMs()
  f.why = why
  pcall(backend().var, f.id, "bMoving", "false")
  if why == "look" then PF.looked = PF.looked + 1
  elseif why == "near" then PF.near = PF.near + 1
  else PF.expired = PF.expired + 1 end
  if (why == "look" or why == "near") and player then S.markSeen(player, "figure") end
end

-- La miras de frente (LookDot) y su casilla se ve.
function PF.seen(f, player)
  local dx, dy = f.x - player:getX(), f.y - player:getY()
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 1e-3 then return true end
  local fx, fy = forward(player)
  if (dx * fx + dy * fy) / dist < (C().LookDot or 0.93) then return false end
  return visible(f.x, f.y, f.z, player:getPlayerNum())
end

-- Un paso de una figura. Devuelve false cuando hay que sacarla.
function PF.update(f, player, dt, now)
  local c = C()
  local b = backend()
  if f.fadeAt then
    local t = (now - f.fadeAt) / math.max(1, c.FadeMs or 450)
    if t >= 1 then return false end
    local calm = S.lessFlashes()                                         -- (170) C01: fundido liso, sin glitch
    pcall(b.look, f.id, (c.Alpha or 0.35) * (1 - t), c.Tint[1], c.Tint[2], c.Tint[3])
    if b.glitch then pcall(b.glitch, f.id, calm and 0 or 0.7 * (1 - t)) end
    return true
  end
  if now - f.bornMs >= f.lifeMs or math.floor(player:getZ()) ~= f.z then PF.dissolve(f, "expired", player); return true end
  local px, py = player:getX(), player:getY()
  if math.sqrt((f.x - px) ^ 2 + (f.y - py) ^ 2) < (c.NearDist or 5) then PF.dissolve(f, "near", player); return true end
  if PF.seen(f, player) then
    f.lookMs = f.lookMs + dt * 1000
    if f.lookMs >= (c.LookMs or 250) then PF.dissolve(f, "look", player); return true end
  else
    f.lookMs = 0
  end
  if f.wx then
    -- (138e) el paso lo da la animacion, como en los zombis falsos; hasta medirlo, WalkSpeed
    local speed = c.WalkSpeed or 0.4
    local anim = b.speed and select(2, pcall(b.speed, f.id))
    if type(anim) == "number" and anim >= 0 then speed = math.min(anim, 1.2) end
    local nx, ny = f.x + f.wx * speed * dt, f.y + f.wy * speed * dt
    if (math.floor(nx) ~= math.floor(f.x) or math.floor(ny) ~= math.floor(f.y)) and not FZ.canStep(f.x, f.y, nx, ny, f.z) then
      f.wx, f.wy = nil, nil                                              -- una pared: se queda quieta, mirandote
      pcall(b.var, f.id, "bMoving", "false")
      PF.face(f, player)
      return true
    end
    f.x, f.y = nx, ny
    pcall(b.move, f.id, nx, ny, f.z, f.wx * speed, f.wy * speed, f.wx, f.wy)
  else
    PF.face(f, player)
  end
  return true
end

function PF.clear(idx, keepForced)
  local b = backend()
  for i = #PF.list, 1, -1 do
    local f = PF.list[i]
    if (idx == nil or f.idx == idx) and not (keepForced and f.forced) then
      if b then pcall(b.remove, f.id) end
      table.remove(PF.list, i)
    end
  end
end

function PF.countFor(idx)
  local n = 0
  for _, f in ipairs(PF.list) do if f.idx == idx and not f.fadeAt then n = n + 1 end end
  return n
end

-- Desde Psychosis.tick (dt en segundos de juego; 0 en pausa).
function PF.tick(player, d, st, now, dt)
  local idx = player:getPlayerNum()
  local active = PF.active(player, d)
  if not active then
    PF.clear(idx, PF.ready())                  -- las del Debug siguen mientras este el jar
    if #PF.list == 0 then return end
  end
  if dt <= 0 then return end
  for i = #PF.list, 1, -1 do
    local f = PF.list[i]
    if f.idx == idx then
      local ok, keep = pcall(PF.update, f, player, dt, now)
      if not ok then PF.errors = PF.errors + 1; S.warnOnce("figureUpdate", "figura fantasma: " .. tostring(keep)); keep = false end
      if not keep then
        pcall(backend().remove, f.id)
        table.remove(PF.list, i)
      end
    end
  end
  if not active then return end
  local c = C()
  if not st.nextFigureMs then st.nextFigureMs = now + c.FirstDelaySeconds * 1000 end
  if now < st.nextFigureMs or PF.countFor(idx) >= (c.Max or 1) then return end
  local every = lerp(c.EverySeconds[2], c.EverySeconds[1], P.intensity(d)) / math.max(0.2, P.freqMult(d, st, "PhantomFigures")) / S.halluMultiplier(d)   -- (180) Filtro
  st.nextFigureMs = now + every * 1000 * rnd(0.6, 1.4)
  if not PF.spawn(player) then st.nextFigureMs = now + (c.RetrySeconds or 15) * 1000 end   -- sin lugar a la vista: prueba de nuevo pronto
end

function PF.statusLine()
  return string.format("figuras fantasma: %d vivas | nacidas %d (sin lugar %d), miradas %d, de cerca %d, vencidas %d, errores %d",
    #PF.list, PF.spawned, PF.noRoom, PF.looked, PF.near, PF.expired, PF.errors)
end

Events.OnPlayerDeath.Add(S.safe("PhantomFigures.OnPlayerDeath", function(player) PF.clear(player:getPlayerNum()) end))

return PF
