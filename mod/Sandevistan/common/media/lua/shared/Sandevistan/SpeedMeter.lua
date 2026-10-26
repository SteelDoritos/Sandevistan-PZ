-- Sandevistan / SpeedMeter (v0.1.30 (13)): velocidad de los zombis medida por ventanas de tiempo, para la PRUEBA COMPLETA.
-- Lo usan el cliente (TestSuite.lua) y el servidor (Net.lua: la misma medición vista por el servidor).
-- Por qué ventanas: en multijugador la posición de un zombi que simula otro (el servidor u otro cliente) llega a saltos (varios ticks
-- quieto y después un paso largo). Medir tick a tick contaba solo los ticks del salto y daba velocidades imposibles (9 tiles/s);
-- el desplazamiento en 0.5 s promedia esos saltos y da la velocidad real.
--   SM.new()                               medidor vacío
--   SM.sample(m, z, x, y, categoria, now)  una muestra por zombi y por tick (si cambia de categoría, su ventana vuelve a empezar)
--   SM.sweep(m, now)                        olvida los zombis que no se vieron en este tick (salieron del rango o murieron)
--   SM.result(m, categoria)                 { zombies, windows, moving, speed, fast, snaps } o nil sin datos
SandevistanSpeedMeter = {}
local SM = SandevistanSpeedMeter

SM.WINDOW_MS = 500
SM.MOVING = 0.1            -- tiles/s: una ventana más lenta cuenta como "quieto" (no entra en el promedio)
SM.FAST = 6                -- tiles/s: ningún zombi corre así en 0.5 s; es una corrección de posición (red o motor)
SM.SNAP = 0.8              -- tiles en un solo tick: salto de posición

function SM.new() return { z = {}, cats = {} } end

local function cat(m, name)
  local c = m.cats[name]
  if not c then
    c = { seen = {}, zombies = 0, windows = 0, moving = 0, dist = 0, time = 0, fast = 0, snaps = 0 }
    m.cats[name] = c
  end
  return c
end

function SM.sample(m, z, x, y, name, now)
  local e = m.z[z]
  if not e or e.cat ~= name then
    m.z[z] = { cat = name, x0 = x, y0 = y, t0 = now, lx = x, ly = y, at = now }
    return
  end
  e.at = now
  local c = cat(m, name)
  local sx, sy = x - e.lx, y - e.ly
  if sx * sx + sy * sy > SM.SNAP * SM.SNAP then c.snaps = c.snaps + 1 end
  e.lx, e.ly = x, y
  local dt = now - e.t0
  if dt >= SM.WINDOW_MS then
    local dx, dy = x - e.x0, y - e.y0
    local d = math.sqrt(dx * dx + dy * dy)
    local v = d / (dt / 1000)
    c.windows = c.windows + 1
    if not c.seen[z] then c.seen[z] = true; c.zombies = c.zombies + 1 end
    if v >= SM.MOVING then c.moving = c.moving + 1; c.dist = c.dist + d; c.time = c.time + dt / 1000 end
    if v >= SM.FAST then c.fast = c.fast + 1 end
    e.x0, e.y0, e.t0 = x, y, now
  end
end

function SM.sweep(m, now)
  for z, e in pairs(m.z) do
    if e.at ~= now then m.z[z] = nil end
  end
end

function SM.result(m, name)
  local c = m.cats[name]
  if not c or c.windows == 0 then return nil end
  return { zombies = c.zombies, windows = c.windows, moving = c.moving, speed = c.time > 0 and c.dist / c.time or nil,
           fast = c.fast, snaps = c.snaps }
end

-- Suma de varias categorías (ej.: frenados propios + remotos).
function SM.merged(m, names)
  local out = { zombies = 0, windows = 0, moving = 0, fast = 0, snaps = 0 }
  local dist, time = 0, 0
  for _, name in ipairs(names) do
    local c = m.cats[name]
    if c then
      out.zombies = out.zombies + c.zombies; out.windows = out.windows + c.windows; out.moving = out.moving + c.moving
      out.fast = out.fast + c.fast; out.snaps = out.snaps + c.snaps
      dist, time = dist + c.dist, time + c.time
    end
  end
  if out.windows == 0 then return nil end
  out.speed = time > 0 and dist / time or nil
  return out
end

return SM
