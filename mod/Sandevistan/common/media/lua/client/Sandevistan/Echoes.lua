-- Sandevistan / Echoes (cliente, 0.7 (138)): ecos de la cyberpsicosis. Con la cyberpsicosis activa, de a ratos los zombis reales que estas viendo dejan
-- una estela de su pose, alternando rojo y cian (vision doble), durante un segundo y medio. No cambia nada del mundo: es solo lo que ves.
-- Los dibuja el mismo motor de estelas con pose real que usan las estelas del Sandevistan (Afterimages.backend, del mod opcional
-- SandevistanViewpoint: en isometrico y, con Viewpoint, en 3D). Sin ese mod, no hay ecos. Los ids salen del mismo contador (Afterimages.uid).
require "Sandevistan/Core"
require "Sandevistan/Afterimages"
require "Sandevistan/Psychosis"

local CFG = SandevistanConfig
local S = Sandevistan
local A = SandevistanAfterimages
local P = SandevistanPsychosis

SandevistanEchoes = { images = {}, episodes = 0, stamped = 0, errors = 0 }
local EC = SandevistanEchoes

local function C() return CFG.Psychosis.Echoes end
local function lerp(a, b, t) return a + (b - a) * t end
local function rnd(a, b) return lerp(a, b, ZombRandFloat(0, 1)) end

function EC.engine() return A.engine() end

function EC.active(player, d)
  local c = C()
  if not (c and c.Enabled) or CFG.NeuralLoad.Hallucinations == false then return false end
  if not d.cyberpsychosisActive or P.stage(d) < (c.MinStage or 2) or player:isAsleep() then return false end
  return EC.engine() ~= nil
end

-- Zombis vivos del mismo piso, a Range casillas y a la vista, del mas cercano al mas lejano (hasta MaxZombies).
function EC.pickZombies(player)
  local c = C()
  local list = {}
  local cell = getCell()
  local zs = cell and cell:getZombieList()
  if not zs then return list end
  local px, py, pz, pn = player:getX(), player:getY(), math.floor(player:getZ()), player:getPlayerNum()
  local r2 = c.Range * c.Range
  for i = 0, zs:size() - 1 do
    local z = zs:get(i)
    local ok, d2 = pcall(function()
      if z:isDead() or math.floor(z:getZ()) ~= pz then return nil end
      local dx, dy = z:getX() - px, z:getY() - py
      local dd = dx * dx + dy * dy
      if dd > r2 then return nil end
      local sq = z:getCurrentSquare()
      if not sq or sq:isCouldSee(pn) ~= true then return nil end
      return dd
    end)
    if ok and d2 then list[#list + 1] = { z = z, d2 = d2 } end
  end
  table.sort(list, function(a, b) return a.d2 < b.d2 end)
  local out = {}
  for i = 1, math.min(#list, c.MaxZombies) do out[i] = list[i].z end
  return out
end

function EC.start(player, st, now)
  local zs = EC.pickZombies(player)
  if #zs == 0 then return false end
  st.echo = { untilMs = now + C().DurationMs, nextStampMs = now, zombies = zs, n = 0, t = 0 }
  EC.episodes = EC.episodes + 1
  return true
end

local function drop(i)
  local img = EC.images[i]
  local b = A.backend
  if b then pcall(b.drop, img.uid) end
  table.remove(EC.images, i)
end

function EC.clear(idx)
  for i = #EC.images, 1, -1 do
    if idx == nil or EC.images[i].idx == idx then drop(i) end
  end
end

-- Desde Psychosis.tick.
function EC.tick(player, d, st, now)
  local idx = player:getPlayerNum()
  local c = C()
  for i = #EC.images, 1, -1 do
    if EC.images[i].idx == idx and now - EC.images[i].bornMs > c.LifeMs then drop(i) end
  end
  if not EC.active(player, d) then
    st.echo = nil
    EC.clear(idx)
    return
  end
  local e = st.echo
  if e then
    if now >= e.untilMs then
      st.echo = nil
    elseif now >= e.nextStampMs then
      e.nextStampMs = now + c.StampMs
      e.t = e.t + 1                                   -- tanda: el color alterna en el tiempo (cada zombi rojo, cian, rojo...)
      local col = c.Colors[(e.t % #c.Colors) + 1]
      local b = EC.engine()
      for _, z in ipairs(e.zombies) do
        local alive = false
        pcall(function() alive = not z:isDead() end)
        if alive then
          e.n = e.n + 1
          A.uid = A.uid + 1
          local uid = A.uid
          -- (138h) la pose se captura cuando el juego dibuja al zombi y puede demorarse un cuadro: va con su posicion actual
          local zx, zy, zz = z:getX(), z:getY(), z:getZ()
          local ok, err = pcall(b.stamp, z, uid, zx, zy, zz)
          if ok then
            EC.images[#EC.images + 1] = { uid = uid, idx = idx, bornMs = now, r = col[1], g = col[2], b = col[3] }
            EC.stamped = EC.stamped + 1
          else
            EC.errors = EC.errors + 1
            S.warnOnce("echoStamp", "eco: " .. tostring(err))
          end
        end
      end
    end
    return
  end
  if not st.nextEchoMs then st.nextEchoMs = now + c.FirstDelaySeconds * 1000 end
  if now < st.nextEchoMs then return end
  local every = lerp(c.EverySeconds[2], c.EverySeconds[1], P.intensity(d)) / math.max(0.2, P.freqMult(d, st, "Echoes")) / S.halluMultiplier(d)              -- (180) Filtro
  -- sin zombis a la vista se reintenta pronto (el eco necesita algo que ver)
  if EC.start(player, st, now) then st.nextEchoMs = now + every * 1000 * rnd(0.6, 1.4) else st.nextEchoMs = now + 3000 end
end

-- En cada cuadro (desde Psychosis.draw): el motor suelta una estela que no se muestra en 300 ms.
function EC.draw(player)
  if #EC.images == 0 then return end
  local b = EC.engine()
  if not b then return end
  local idx, now, c = player:getPlayerNum(), S.realMs(), C()
  for _, img in ipairs(EC.images) do
    if img.idx == idx then
      local f = 1 - (now - img.bornMs) / c.LifeMs
      if f > 0 then pcall(b.show, img.uid, img.r, img.g, img.b, c.Alpha * f) end
    end
  end
end

function EC.statusLine()
  return string.format("ecos: %d episodios, %d poses guardadas, %d a la vista, errores %d | motor %s", EC.episodes, EC.stamped, #EC.images, EC.errors,
    EC.engine() and "listo" or "no disponible (falta SandevistanViewpoint o no anda en esta camara)")
end

Events.OnPlayerDeath.Add(S.safe("Echoes.OnPlayerDeath", function(player) EC.clear(player:getPlayerNum()) end))

return EC
