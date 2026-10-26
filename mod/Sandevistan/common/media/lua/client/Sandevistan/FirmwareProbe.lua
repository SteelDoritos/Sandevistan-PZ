-- Sandevistan / FirmwareProbe: sondas de Debug (Debug -> Firmware -> Sondas) para comprobar en el juego lo que el firmware no puede dar por sentado
-- (v0.1.30 (82)). Cada una es independiente, va envuelta en pcall y deja su resultado en Zomboid/Lua/Sandevistan_fwprobe.txt (el archivo junta lo ultimo
-- de las tres). Se usan para decidir tres cosas de la entrega 4 y la 5 del plan (15-plan-firmware.md, seccion 7):
--   1. objetos    que objeto del mundo hace de PC (sprite, nombre y propiedades) y si la casilla tiene corriente        -> escribir firmware
--   2. acciones   que acciones temporizadas hay (clase y duracion) y si ISBaseTimedAction.adjustMaxTime se llama       -> Taller
--   3. movimiento que dicen isPlayerMoving / isRunning / isSprinting / isSneaking / isAiming en cada situacion        -> Centinela y Camara criogenica
require "Sandevistan/Core"

local S = Sandevistan

SandevistanFirmwareProbe = {}
local P = SandevistanFirmwareProbe
P.FILE = "Sandevistan_fwprobe.txt"
P.sections = {}            -- titulo -> lineas de la ultima corrida de esa sonda
P.order = { "objetos", "acciones", "movimiento" }

-- Valor de una llamada que puede fallar: el resultado o "ERR".
local function try(fn, ...)
  local ok, v = pcall(fn, ...)
  if ok then return v end
  return "ERR"
end

local function str(v)
  if type(v) == "number" then return string.format("%.3f", v) end
  return tostring(v)
end

---------------------------------------------------------------------------
-- Archivo
---------------------------------------------------------------------------
function P.export(player)
  local lines = { "# Sandevistan " .. tostring(SandevistanConfig.Build) .. ": sondas del firmware (la ultima corrida de cada una)" }
  for _, title in ipairs(P.order) do
    local sec = P.sections[title]
    lines[#lines + 1] = ""
    lines[#lines + 1] = "== " .. title
    if sec then for _, l in ipairs(sec) do lines[#lines + 1] = l end else lines[#lines + 1] = "(no se corrio en esta sesion)" end
  end
  local wrote = pcall(function()
    local w = getFileWriter(P.FILE, true, false)
    if not w then error("sin escritor") end
    for _, l in ipairs(lines) do w:write(S.ascii(l) .. "\n") end
    w:close()
  end)
  S.log("sondas del firmware: " .. #lines .. " lineas, " .. (wrote and ("escrito en Zomboid/Lua/" .. P.FILE) or "NO se pudo escribir"))
  if player then pcall(function() player:Say(wrote and ("Sondas: Zomboid/Lua/" .. P.FILE) or "No se pudo escribir las sondas") end) end
  return lines, wrote
end

---------------------------------------------------------------------------
-- 1. Objetos cercanos
---------------------------------------------------------------------------
-- Recorre las casillas del piso del jugador en un radio y agrupa los objetos por sprite/nombre/propiedades. Muestra si la casilla tiene corriente
-- (haveElectricity / hasGridPower). La PC es el objeto con nombre o grupo de computadora/television/electrodomestico.
function P.scanObjects(player, radius)
  radius = radius or 7
  local out = {}
  local function add(l) out[#out + 1] = l end
  local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
  add(string.format("jugador en %d,%d,%d | radio %d casillas, mismo piso", px, py, pz, radius))
  local hydro = nil
  pcall(function() hydro = getWorld():isHydroPowerOn() end)
  add(string.format("red electrica del mundo (isHydroPowerOn) = %s | ElecShutModifier = %s | horas de juego = %.1f",
    tostring(hydro), tostring(SandboxVars and SandboxVars.ElecShutModifier), S.worldHours()))
  local cell = getCell()
  local groups, order = {}, {}
  local squares, withPower, withGrid = 0, 0, 0
  for dx = -radius, radius do
    for dy = -radius, radius do
      local sq = cell:getGridSquare(px + dx, py + dy, pz)
      if sq then
        squares = squares + 1
        local power = try(function() return sq:haveElectricity() end)
        local grid = try(function() return sq:hasGridPower() end)
        if power == true then withPower = withPower + 1 end
        if grid == true then withGrid = withGrid + 1 end
        local objs = sq:getObjects()
        for i = 0, (objs and objs:size() or 0) - 1 do
          local o = objs:get(i)
          local sprite = try(function() return o:getSpriteName() end)
          local kind = try(function() return o:getObjectName() end)
          local props = try(function() return o:getProperties() end)
          local custom, group = "", ""
          if type(props) ~= "string" and props then
            custom = try(function() return props:get("CustomName") end) or ""
            group = try(function() return props:get("GroupName") end) or ""
          end
          local key = tostring(sprite) .. "|" .. tostring(kind) .. "|" .. tostring(custom) .. "|" .. tostring(group)
          local g = groups[key]
          if not g then
            g = { sprite = sprite, kind = kind, custom = custom, group = group, n = 0, power = 0, grid = 0, x = px + dx, y = py + dy }
            groups[key] = g
            order[#order + 1] = g
            local names = try(function() return props:getPropertyNames() end)
            if type(names) ~= "string" and names then
              local list = {}
              for k = 0, math.min(names:size(), 14) - 1 do list[#list + 1] = tostring(names:get(k)) end
              g.props = table.concat(list, ",")
            end
          end
          g.n = g.n + 1
          if power == true then g.power = g.power + 1 end
          if grid == true then g.grid = g.grid + 1 end
        end
      end
    end
  end
  add(string.format("casillas leidas = %d | con corriente (haveElectricity) = %d | con red (hasGridPower) = %d | objetos distintos = %d", squares, withPower, withGrid, #order))
  add("formato: veces | sprite | tipo | CustomName | GroupName | casillas con corriente / con red | primera casilla | propiedades")
  -- primero los que tienen nombre o grupo (candidatos a PC y electrodomesticos), despues el resto
  table.sort(order, function(a, b)
    local an, bn = (a.custom ~= "" or a.group ~= "") and 0 or 1, (b.custom ~= "" or b.group ~= "") and 0 or 1
    if an ~= bn then return an < bn end
    return tostring(a.sprite) < tostring(b.sprite)
  end)
  for i, g in ipairs(order) do
    if i > 160 then add("(...faltan " .. (#order - 160) .. " grupos mas)"); break end
    add(string.format("%d | %s | %s | %s | %s | %d/%d | %d,%d | %s", g.n, tostring(g.sprite), tostring(g.kind), tostring(g.custom), tostring(g.group),
      g.power, g.grid, g.x, g.y, tostring(g.props or "")))
  end
  P.sections.objetos = out
  return out
end

---------------------------------------------------------------------------
-- 2. Acciones temporizadas
---------------------------------------------------------------------------
P.act = { on = false, hooked = false, log = {}, counts = {} }
local ACT_MAX = 400

local function actKey(a)
  local t = a and (a.Type or a.name) or "?"
  return tostring(t)
end

local function logAct(line)
  local L = P.act.log
  L[#L + 1] = line
  if #L > ACT_MAX then table.remove(L, 1) end
end

-- Engancha (una sola vez) ISTimedActionQueue.add y ISBaseTimedAction.adjustMaxTime. Los envoltorios no tocan nada: solo anotan mientras la sonda esta prendida.
function P.hookActions()
  if P.act.hooked then return true end
  local Q, B = rawget(_G, "ISTimedActionQueue"), rawget(_G, "ISBaseTimedAction")
  if type(Q) ~= "table" or type(Q.add) ~= "function" then return false end
  local origAdd = Q.add
  Q.add = function(action, ...)
    if P.act.on then
      local k = actKey(action)
      local c = P.act.counts[k] or { add = 0, adj = 0, maxTime = nil }
      c.add = c.add + 1
      c.maxTime = action and action.maxTime or c.maxTime
      P.act.counts[k] = c
      logAct(string.format("ADD %s maxTime=%s stopOnWalk=%s", k, str(action and action.maxTime), tostring(action and action.stopOnWalk)))
    end
    return origAdd(action, ...)
  end
  if type(B) == "table" and type(B.adjustMaxTime) == "function" then
    local origAdjust = B.adjustMaxTime
    B.adjustMaxTime = function(self, maxTime, ...)
      local r = origAdjust(self, maxTime, ...)
      if P.act.on then
        local k = actKey(self)
        local c = P.act.counts[k] or { add = 0, adj = 0 }
        c.adj = c.adj + 1
        P.act.counts[k] = c
        logAct(string.format("ADJ %s entra=%s sale=%s", k, str(maxTime), str(r)))
      end
      return r
    end
  end
  P.act.hooked = true
  return true
end

function P.actionLines(player)
  local out = {}
  local function add(l) out[#out + 1] = l end
  add("ISTimedActionQueue.add enganchado = " .. tostring(P.act.hooked) .. " | sonda " .. (P.act.on and "PRENDIDA" or "apagada"))
  local mod = try(function() return player:getTimedActionTimeModifier() end)
  add("player:getTimedActionTimeModifier() = " .. str(mod) .. " | isTimedActionInstant = " .. tostring(try(function() return player:isTimedActionInstant() end)))
  add("ISBaseTimedAction.adjustMaxTime existe = " .. tostring(type(rawget(_G, "ISBaseTimedAction")) == "table" and type(ISBaseTimedAction.adjustMaxTime) == "function"))
  add("formato: clase | veces que se encolo | veces que paso por adjustMaxTime | ultimo maxTime")
  local keys = {}
  for k in pairs(P.act.counts) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local c = P.act.counts[k]
    add(string.format("%s | %d | %d | %s", k, c.add, c.adj or 0, str(c.maxTime)))
  end
  if #keys == 0 then add("(sin acciones registradas: prende la sonda, fabrica / venda / cocina / lee algo y apagala)") end
  add("-- ultimas lineas del registro --")
  for _, l in ipairs(P.act.log) do add(l) end
  return out
end

-- Prende o apaga el registro. Al apagarlo guarda el resultado.
function P.toggleActions(player)
  if not P.hookActions() then
    P.sections.acciones = { "ISTimedActionQueue no existe: no se pudo enganchar" }
    return false
  end
  P.act.on = not P.act.on
  if P.act.on then
    P.act.log, P.act.counts = {}, {}
    pcall(function() player:Say("Sonda de acciones PRENDIDA: hace lo que quieras que dure (fabricar, vendar, cocinar, leer) y volve a elegirla para apagarla") end)
  else
    P.sections.acciones = P.actionLines(player)
    P.export(player)
  end
  return P.act.on
end

---------------------------------------------------------------------------
-- 3. Movimiento
---------------------------------------------------------------------------
P.mov = { on = false }
P.MOV_STAGES = {
  { 0, "quieto, sin tocar nada" },
  { 5, "apuntando con el boton derecho SIN moverte" },
  { 10, "girando sobre tu eje (mouse) sin moverte" },
  { 15, "caminando" },
  { 20, "corriendo" },
  { 25, "sprint (la tecla de sprint)" },
  { 30, "agachado y quieto" },
  { 35, "agachado y caminando" },
}
P.MOV_SECONDS, P.MOV_EVERY_MS = 40, 250

function P.startMovement(player)
  if P.mov.on then return false end
  P.mov = { on = true, player = player, t0 = S.realMs(), nextMs = 0, stage = 0, rows = {}, lastX = player:getX(), lastY = player:getY(), lastMs = S.realMs() }
  pcall(function() player:Say("Sonda de movimiento: 40 s, sigue lo que te va diciendo") end)
  return true
end

local function sampleMovement()
  local m = P.mov
  if not m.on then return end
  local now = S.realMs()
  local el = (now - m.t0) / 1000
  local pl = m.player
  if el >= P.MOV_SECONDS or not pl or pl:isDead() then
    m.on = false
    local out = {}
    local function add(l) out[#out + 1] = l end
    add("muestras cada " .. P.MOV_EVERY_MS .. " ms durante " .. P.MOV_SECONDS .. " s; porcentaje de muestras con la bandera en true y velocidad media (casillas por segundo)")
    add("etapa | muestras | isPlayerMoving | isMoving | isRunning | isSprinting | isSneaking | isAiming | velocidad")
    for i, st in ipairs(P.MOV_STAGES) do
      local rows = m.rows[i] or {}
      local n = #rows
      local function pct(k) local c = 0; for _, r in ipairs(rows) do if r[k] == true then c = c + 1 end end return n > 0 and (100 * c / n) or 0 end
      local sp = 0
      for _, r in ipairs(rows) do sp = sp + r.speed end
      add(string.format("%s | %d | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %.2f", st[2], n, pct("pm"), pct("mv"), pct("run"), pct("spr"), pct("snk"), pct("aim"), n > 0 and sp / n or 0))
    end
    P.sections.movimiento = out
    P.export(pl)
    return
  end
  local stage = 1
  for i, st in ipairs(P.MOV_STAGES) do if el >= st[1] then stage = i end end
  if stage ~= m.stage then
    m.stage = stage
    pcall(function() pl:Say(P.MOV_STAGES[stage][2]) end)
  end
  if now < m.nextMs then return end
  m.nextMs = now + P.MOV_EVERY_MS
  local x, y = pl:getX(), pl:getY()
  local dt = math.max(0.001, (now - m.lastMs) / 1000)
  local speed = math.sqrt((x - m.lastX) ^ 2 + (y - m.lastY) ^ 2) / dt
  m.lastX, m.lastY, m.lastMs = x, y, now
  local rows = m.rows[stage]
  if not rows then rows = {}; m.rows[stage] = rows end
  rows[#rows + 1] = {
    pm = try(function() return pl:isPlayerMoving() end), mv = try(function() return pl:isMoving() end),
    run = try(function() return pl:isRunning() end), spr = try(function() return pl:isSprinting() end),
    snk = try(function() return pl:isSneaking() end), aim = try(function() return pl:isAiming() end), speed = speed,
  }
end

Events.OnTick.Add(S.safe("FirmwareProbe.OnTick", sampleMovement))

return P
