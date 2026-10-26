-- Sandevistan / FirmwareClient: los chips de firmware como objetos (v0.1.30 (82)). Instalar y sacar un chip (flasheo), devolverlos al explantar, el texto
-- de detalle de cada programa y las ayudas de Debug. El perfil (lo que hace cada programa) esta en shared/Firmware.lua y los menus en ContextMenus.lua.
-- Todo lo que crea o borra items usa los patrones que el servidor reconoce en multijugador: S.grantItem para crear (114: lo crea el servidor) y DoRemoveItem +
-- sendRemoveItemFromContainer para borrar (como Dossier.lua).
require "Sandevistan/Core"
require "Sandevistan/Effects"
require "Sandevistan/Runtime"

local CFG = SandevistanConfig
local S = Sandevistan
local E = SandevistanEffects
local R = SandevistanRuntime
local FW = SandevistanFirmware

SandevistanFirmwareClient = {}
local FC = SandevistanFirmwareClient

-- Color del aviso de cada slot (el mismo de los chips: Sistema verde circuito, Habilidad violeta)
FC.COLOR = { sistema = { 60, 255, 140 }, habilidad = { 180, 96, 255 } }

function FC.name(id) return getText("IGUI_Sandevistan_Fw_Name_" .. tostring(id)) end
function FC.slotLabel(slot) return getText("IGUI_Sandevistan_Fw_Slot_" .. tostring(slot)) end

-- "Tiempo" de la accion temporizada que dura `seconds` segundos.
function FC.ticks(seconds) return math.max(1, math.floor(seconds * CFG.Firmware.TicksPerSecond + 0.5)) end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
-- Saca un item de su contenedor avisando al servidor (multijugador): mismo patron que Dossier.lua.
function FC.removeItem(item)
  local c = item and item:getContainer()
  if not c then return false end
  c:DoRemoveItem(item)
  if isClient() and rawget(_G, "sendRemoveItemFromContainer") then pcall(sendRemoveItemFromContainer, c, item) end
  return true
end

-- Crea el chip de un programa ("Blank" = el chip base) en el inventario del jugador.
function FC.giveChip(player, id)
  local ft = (id == "Blank") and FW.BLANK or FW.itemType(id)
  return S.grantItem(player, ft)            -- (114) en multijugador lo crea el servidor
end

---------------------------------------------------------------------------
-- Instalar y sacar chips
---------------------------------------------------------------------------
-- Motivos por los que no se puede instalar ese programa (textos del idioma activo; vacia = se puede). Suma lo de la sesion: con el implante
-- encendido no se cambia nada.
function FC.flashReasons(player, id)
  local d = S.data(player)
  local out = FW.problemTexts(FW.flashProblems(d, id))
  if S.hasWorkingImplant(d) and R.isActive(player) then out[#out + 1] = getText("IGUI_Sandevistan_Fw_Req_Active") end
  return out
end

function FC.removeReasons(player, slot)
  local d = S.data(player)
  local out = FW.problemTexts(FW.removeProblems(d, slot))
  if S.hasWorkingImplant(d) and R.isActive(player) then out[#out + 1] = getText("IGUI_Sandevistan_Fw_Req_Active") end
  return out
end

-- Costo comun de cualquier cambio de chip: un poco de rechazo y el recalibrado (el Heat sube mas durante una hora de juego).
function FC.afterChange(player, d, slot, text)
  local F = CFG.Firmware
  d.rejection = math.min(100, (d.rejection or 0) + F.FlashRejection)
  d.fwRecalUntil = S.worldHours() + F.Recalibrate.Hours
  local c = FC.COLOR[slot] or { 255, 255, 255 }
  E.halo(player, text, c[1], c[2], c[3])
  -- (190) MP: los slots de firmware y el rechazo tienen que quedar guardados ya, no dentro de 15 s
  local N = rawget(_G, "SandevistanNet")
  if N and N.saveState then pcall(N.saveState, player) end
end

-- Instala el chip `item` (un programa terminado). Devuelve true si lo hizo. El chip que estaba en ese slot vuelve al inventario.
function FC.flash(player, item)
  local d = S.data(player)
  local id = item and FW.idOfItem(item:getFullType())
  if not id or #FC.flashReasons(player, id) > 0 then return false end
  local slot = FW.program(id).slot
  if not FC.removeItem(item) then return false end
  local prev = FW.setSlot(d, slot, id)
  if prev then FC.giveChip(player, prev) end
  FC.afterChange(player, d, slot, getText("IGUI_Sandevistan_Fw_Flashed", FC.name(id)))
  return true
end

-- Saca el chip de un slot y lo deja en el inventario.
function FC.unflash(player, slot)
  local d = S.data(player)
  if #FC.removeReasons(player, slot) > 0 then return false end
  local prev = FW.setSlot(d, slot, nil)
  if not prev then return false end
  FC.giveChip(player, prev)
  FC.afterChange(player, d, slot, getText("IGUI_Sandevistan_Fw_Removed", FC.name(prev)))
  return true
end

-- Al explantar el implante: los chips vuelven al inventario de quien lo tenia (S.grantItem: en multijugador los crea el servidor).
-- Si un chip no se pudo crear queda en su slot (no se pierde). Devuelve cuantos devolvio.
function FC.returnChips(player)
  local d = S.data(player)
  local n = 0
  for _, slot in ipairs(CFG.Firmware.Slots) do
    local id = FW.slotProgram(d, slot)
    if id and FC.giveChip(player, id) then
      FW.setSlot(d, slot, nil)
      n = n + 1
    end
  end
  if n > 0 then E.halo(player, getText("IGUI_Sandevistan_Fw_Returned", n), 200, 220, 255) end
  d.fwRecalUntil = nil
  local N = rawget(_G, "SandevistanNet")
  if N and N.saveState then pcall(N.saveState, player) end
  return n
end

---------------------------------------------------------------------------
-- Capa en vivo (83): lo que depende del momento y no se puede sacar del estado guardado. Runtime la consulta en cada tick solo si hay un chip que la use.
---------------------------------------------------------------------------
FC.mot = {}                 -- [playerNum] = { x, y, ms, speed, cls }: posicion anterior y velocidad suavizada
FC.kills = {}               -- [playerNum] = marcas (ms reales) de las bajas que ya bajaron el Heat (Apogeo)
local LIVE = { heat = 1, xpTime = 1, motion = "still" }       -- una sola tabla reutilizada: Runtime la usa enseguida

-- Movimiento del jugador: "still" (quieto), "walk" o "run". La velocidad se mide por el cambio de posicion y se suaviza SmoothSeconds, asi que parar y
-- arrancar no engana; apuntar o girar sin desplazarte cuenta como quieto. Correr = isRunning / isSprinting (si el juego no responde, cuenta como caminar).
function FC.motion(player)
  local M = CFG.Firmware.Motion
  local idx = player:getPlayerNum()
  local now = S.realMs()
  local x, y = player:getX(), player:getY()
  local m = FC.mot[idx]
  if not m or now - m.ms > 1500 then                      -- sin mediciones recientes: se arranca de cero
    m = { x = x, y = y, ms = now, speed = 0, cls = "still" }
    FC.mot[idx] = m
    return m.cls, m
  end
  local el = (now - m.ms) / 1000 * S.timeScale()          -- (127) velocidad en casillas por segundo DE JUEGO: a x40 caminar no cuenta como correr
  if el > 0 then
    local inst = math.min(M.MaxSpeed, math.sqrt((x - m.x) ^ 2 + (y - m.y) ^ 2) / el)
    m.speed = m.speed + (inst - m.speed) * math.min(1, el / M.SmoothSeconds)
    m.x, m.y, m.ms = x, y, now
  end
  if m.speed < M.StillSpeed then
    m.cls = "still"
  else
    local run = false
    pcall(function() run = player:isRunning() or player:isSprinting() end)
    m.cls = run and "run" or "walk"
  end
  return m.cls, m
end

function FC.sneaking(player)
  local v = false
  pcall(function() v = player:isSneaking() end)
  return v == true
end

function FC.motionLabel(cls) return getText("IGUI_Sandevistan_Fw_Motion_" .. tostring(cls)) end

-- Factores en vivo de un tick con el implante encendido (nil si ningun chip los pide): heat = multiplicador del Heat de uso, xpTime = de la XP por tiempo.
function FC.live(player, d, dt)
  local cen = FW.profile(d).centinela
  if not cen then return nil end
  local cls = FC.motion(player)
  LIVE.motion = cls
  LIVE.heat = (cls == "still" and cen.still) or (cls == "run" and cen.run) or cen.walk
  LIVE.xpTime = (cls == "still") and cen.xpStill or 1
  return LIVE
end

-- Multiplicador del enfriamiento con el implante apagado ((108) Camara criogenica x1,75; (110) Reactor x0,5 y su masa termica).
function FC.coolMult(player, d, s)
  return FW.coolMult(d)
end

-- Apogeo: un kill con el implante encendido baja el Heat `points`; como mucho MaxKills bajas cada WindowSeconds. Devuelve cuanto bajo.
function FC.killHeat(player, d, points)
  if not points or points <= 0 then return 0 end
  points = points / FW.profile(d).thermalMass                       -- (110) Reactor: un kill baja la barra como si fuera de 0 a 150
  local K = CFG.Firmware.KillHeat
  local idx = player:getPlayerNum()
  local now = S.realMs()
  local list = FC.kills[idx]
  if not list then list = {}; FC.kills[idx] = list end
  for i = #list, 1, -1 do if now - list[i] > K.WindowSeconds * 1000 then table.remove(list, i) end end
  if #list >= K.MaxKills then return 0 end
  list[#list + 1] = now
  local before = d.heat or 0
  d.heat = math.max(0, before - points)
  return before - d.heat
end

---------------------------------------------------------------------------
-- Taller: modo trabajo (86). Config.Firmware.Work; el regimen (tramo, costos, sin bonos) esta en FW.tier y Runtime; aca viven los candados y el flujo (que dependen del
-- momento) y las acciones mas rapidas.
---------------------------------------------------------------------------
-- ¿Hay una accion larga en curso? (fabricar, vendar, leer...: el motor lleva la cola de acciones del personaje)
function FC.isWorking(player)
  local w = false
  pcall(function() w = player:hasTimedActions() == true end)
  return w
end

-- Candado 1: un zombi que te ataca o te persigue a ThreatTiles o menos. Mira la lista de cercanos de Slowdown (SD.nearList, solo mientras Taller esta activo); si no tiene
-- nada (nivel de detalle apagado o aun sin elegir), la lista de zombis de la celda.
function FC.workThreat(player)
  local Wk = CFG.Firmware.Work
  local r2 = Wk.ThreatTiles * Wk.ThreatTiles
  local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ())
  local function threatening(z)
    if not z then return false end
    local dead = false
    pcall(function() dead = z:isDead() end)
    if dead then return false end
    local dx, dy, same = 0, 0, false
    pcall(function() dx, dy = z:getX() - px, z:getY() - py; same = math.floor(z:getZ()) == pz end)
    if not same or dx * dx + dy * dy > r2 then return false end
    local hit = false
    pcall(function() hit = z:isAttacking() or z:getTarget() == player end)
    return hit
  end
  local SD = rawget(_G, "SandevistanSlowdown")
  local list = SD and SD.nearList
  if list and #list > 0 then
    for i = 1, #list do
      if threatening(list[i].z) then return true end
    end
    return false
  end
  local cell = getCell()
  local zl = cell and cell:getZombieList()
  if not zl then return false end
  for i = 0, zl:size() - 1 do
    if threatening(zl:get(i)) then return true end
  end
  return false
end

-- Un tick del modo trabajo (Runtime.tickActive). Lleva el flujo (sube con una accion en curso, se conserva FlowGraceSeconds y despues se pierde) y aplica los candados:
-- CN o rechazo altos y amenazas cercanas (bloquea ThreatLockSeconds). Devuelve nil o (true, motivo) para suspenderlo. (108) Sin el corte de la fatiga mental.
-- s.workForce (Debug) se salta los candados.
function FC.workTick(player, d, s, dt)
  local Wk = CFG.Firmware.Work
  local working = s.workForceWorking == true or FC.isWorking(player)
  s.workNow = working
  if working then
    s.workFlow = math.min(Wk.FlowSeconds, (s.workFlow or 0) + dt); s.workIdle = 0
  else
    s.workIdle = (s.workIdle or 0) + dt
    if s.workIdle > Wk.FlowGraceSeconds then s.workFlow = 0 end
  end
  if s.workForce then return nil end
  if (d.neuralLoad or 0) >= Wk.MaxCN or (d.rejection or 0) >= Wk.MaxRejection then return true, "limit" end
  s.workAcc = (s.workAcc or 0) + dt
  if s.workAcc >= Wk.ThreatCheckSeconds then
    s.workAcc = 0
    if FC.workThreat(player) then
      s.workLockUntilMs = S.gameMs() + Wk.ThreatLockSeconds * 1000          -- (127) reloj de juego
      return true, "threat"
    end
  end
  return nil
end

-- Multiplicador de la CN por uso en modo trabajo (se suma al x CostMult de Heat): trabajando, CostMult x (1 - adaptacion x flujo): con el flujo completo y la adaptacion estable la CN
-- llega a cero; sin una accion en curso, CostMult x (1 - IdleAdaptReduction x adaptacion): nunca llega a cero.
function FC.workCnMult(d, s)
  local Wk = CFG.Firmware.Work
  local a = S.adaptFraction(d)
  if s.workNow then return Wk.CostMult * (1 - a * math.min(1, (s.workFlow or 0) / Wk.FlowSeconds)) end
  return Wk.CostMult * (1 - Wk.IdleAdaptReduction * a)
end

-- Acciones mas rapidas: con el modo trabajo encendido las acciones de Work.Actions duran ActionMult veces lo normal. Se engancha getDuration de cada clase de la lista (la mayoria arma
-- `maxTime` con getDuration al crearse) y, de refuerzo, ISBaseTimedAction.adjustMaxTime (por si alguna lo fija de otro modo); una marca en la accion (_sandeF) evita aplicar el factor dos
-- veces o cambiarlo a mitad de la accion. Solo actua mientras el jugador de la accion tiene el modo trabajo activo; todo va con pcall. FC.work.scaled cuenta las aceleradas (Debug y reporte).
FC.work = { hooked = false, scaled = 0, last = nil, classes = {}, missing = {}, base = false }
local function workFactor(action)
  local f = action._sandeF
  if f ~= nil then return f end
  f = 1
  if not CFG.Firmware.Work.ActionsEnabled then return 1 end
  pcall(function()
    local ch = action.character
    local s = ch and R.sessions[ch:getPlayerNum()]
    if s and s.active and s.work then f = CFG.Firmware.Work.ActionMult end
  end)
  action._sandeF = f
  return f
end

local function listed(typeName)
  for _, n in ipairs(CFG.Firmware.Work.Actions) do if n == typeName then return true end end
  return false
end
FC.workListed = listed

function FC.hookActions()
  local Wk = CFG.Firmware.Work
  if not Wk.ActionsEnabled then return 0 end
  local n = 0
  for _, name in ipairs(Wk.Actions) do
    local cls = rawget(_G, name)
    if type(cls) == "table" and type(cls.getDuration) == "function" then
      if not rawget(cls, "_sandeWork") then
        local orig = cls.getDuration
        cls.getDuration = function(self, ...)
          local t = orig(self, ...)
          if type(t) == "number" and t > 0 then
            local f = workFactor(self)
            if f ~= 1 then FC.work.scaled = FC.work.scaled + 1; FC.work.last = name; return t * f end
          end
          return t
        end
        cls._sandeWork = true
        FC.work.classes[name] = true
        FC.work.missing[name] = nil                                      -- una clase que no estaba al cargar el mod y aparece despues (OnGameStart)
        n = n + 1
      end
    else
      FC.work.missing[name] = true
    end
  end
  local A = rawget(_G, "ISBaseTimedAction")
  if type(A) == "table" and type(A.adjustMaxTime) == "function" and not rawget(A, "_sandeWork") then
    local orig = A.adjustMaxTime
    A.adjustMaxTime = function(self, maxTime)
      local t = orig(self, maxTime)
      if type(t) == "number" and t > 0 and self._sandeF == nil and listed(self.Type) then
        local f = workFactor(self)
        if f ~= 1 then FC.work.scaled = FC.work.scaled + 1; FC.work.last = tostring(self.Type); return t * f end
      end
      return t
    end
    A._sandeWork = true
    FC.work.base = true
    n = n + 1
  end
  FC.work.hooked = true
  return n
end
FC.hookActions()                                                       -- al cargar el mod (las clases de vanilla ya existen); OnGameStart repite por si alguna se definio despues
Events.OnGameStart.Add(S.safe("FirmwareClient.hookActions", function() FC.hookActions() end))

---------------------------------------------------------------------------
-- Aprender y escribir programas (85)
---------------------------------------------------------------------------
-- Anota los programas que se te ocurren al subir de nivel y avisa de cada uno (cada minuto y al cargar la partida). Con un implante tambien se aprende a
-- fabricar el chip virgen y el terminal (Medical.knows("firmware") lo lee de d.knows.firmware).
-- (87) El expediente militar completo (los dos que pide el Prototipo 07) trae el codigo de los programas con `dossiers` (Compatibilidad y Camara criogenica): se aprenden al llevarlo encima, sin importar
-- el nivel. Devuelve los nuevos y avisa de cada uno.
function FC.syncDossiers(player, d)
  local out = {}
  if not FW.enabled() or CFG.Firmware.AllKnown then return out end
  local pending = {}
  for _, id in ipairs(CFG.Firmware.Order) do
    local p = CFG.Firmware.Programs[id]
    if p.ready and p.dossiers and not FW.known(d, id) then pending[#pending + 1] = id end
  end
  local Md = rawget(_G, "SandevistanMedical")
  if #pending == 0 or not (Md and Md.militaryDossiersComplete) then return out end
  local ok, complete = pcall(Md.militaryDossiersComplete, player)
  if not (ok and complete) then return out end
  for _, id in ipairs(pending) do
    if FW.learn(d, id) then
      out[#out + 1] = id
      local c = FC.COLOR[FW.program(id).slot] or { 255, 255, 255 }
      E.halo(player, getText("IGUI_Sandevistan_Fw_LearnedDossier", FC.name(id)), c[1], c[2], c[3])
    end
  end
  return out
end

function FC.syncKnown(player)
  local d = S.data(player)
  if FW.enabled() and S.hasAnyImplant(d) then d.knows.firmware = true end
  local fromDossier = FC.syncDossiers(player, d)                     -- (ya avisa de cada uno)
  local new = FW.syncKnown(d)
  if #new > 3 then                                   -- una partida con un nivel alto que se carga por primera vez: un solo aviso en vez de una lluvia
    E.halo(player, getText("IGUI_Sandevistan_Fw_LearnedMany", #new), 200, 220, 255)
  else
    for _, id in ipairs(new) do
      local c = FC.COLOR[FW.program(id).slot] or { 255, 255, 255 }
      E.halo(player, getText("IGUI_Sandevistan_Fw_Learned", FC.name(id)), c[1], c[2], c[3])
    end
  end
  for _, id in ipairs(fromDossier) do new[#new + 1] = id end
  return new
end

local function forEachPlayer(fn)
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p and not p:isDead() then fn(p) end
  end
end
Events.OnGameStart.Add(S.safe("FirmwareClient.syncKnownStart", function() forEachPlayer(FC.syncKnown) end))
Events.EveryOneMinute.Add(S.safe("FirmwareClient.syncKnown", function() forEachPlayer(FC.syncKnown) end))

-- Cuantos items de ese tipo hay en el inventario (incluye las bolsas).
local function have(player, fullType) return player:getInventory():getCountTypeRecurse(fullType) end
local function firstOf(player, fullType) return player:getInventory():getFirstTypeRecurse(fullType) end

-- ¿Este objeto del mundo es una computadora? Por el prefijo de su sprite o por palabras de su nombre y su grupo (CustomName, GroupName, tipo de objeto). Lo que cuenta esta en
-- Config.Firmware.Write.Computer y se verifica con la sonda 1 de Debug (que objeto es una PC y si su casilla tiene corriente).
function FC.isComputer(obj)
  local C = CFG.Firmware.Write.Computer
  local sprite = nil
  pcall(function() sprite = obj:getSpriteName() end)
  if type(sprite) == "string" then
    for _, pre in ipairs(C.SpritePrefixes) do
      if string.sub(sprite, 1, #pre) == pre then return true end
    end
  end
  local text, props = "", nil
  pcall(function() props = obj:getProperties() end)
  if props then
    for _, key in ipairs({ "CustomName", "GroupName" }) do
      pcall(function() local v = props:get(key); if v then text = text .. " " .. tostring(v) end end)
    end
  end
  pcall(function() text = text .. " " .. tostring(obj:getObjectName()) end)
  text = string.lower(text)
  for _, w in ipairs(C.Words) do
    if string.find(text, w, 1, true) then return true end
  end
  return false
end

-- Computadoras entre los objetos del menu de mundo (una por casilla). Devuelve una lista de { obj, square }.
function FC.computersIn(worldObjects)
  local out, seen = {}, {}
  for _, obj in ipairs(worldObjects or {}) do
    local sq = nil
    pcall(function() sq = obj:getSquare() end)
    if sq and not seen[sq] then
      seen[sq] = true
      local objs = nil
      pcall(function() objs = sq:getObjects() end)
      for i = 0, (objs and objs:size() or 0) - 1 do
        local o = objs:get(i)
        if FC.isComputer(o) then out[#out + 1] = { obj = o, square = sq }; break end
      end
    end
  end
  return out
end

-- ¿La casilla tiene corriente? (red electrica del mundo o un generador cercano). Las dos llamadas se prueban por separado.
function FC.powered(square)
  if not square then return false end
  local ok = false
  pcall(function() ok = square:haveElectricity() == true end)
  if ok then return true end
  pcall(function() ok = square:hasGridPower() == true end)
  return ok
end

-- Segundos y "tiempo" de la accion de escribir (60 s sin costumbre, 25 s con la adaptacion estable).
function FC.writeSeconds(player) return FW.writeSeconds(S.data(player)) end
function FC.writeTicks(player) return FC.ticks(FC.writeSeconds(player)) end

-- Lo que pide la fuente (escribir y decompilar usan la misma): una computadora con corriente (src = { kind = "pc", square = casilla }) o el terminal encima con una bateria
-- (src = { kind = "terminal", item = item }). Suma los motivos a `out`.
local function sourceReasons(player, src, out)
  local W = CFG.Firmware.Write
  if src and src.kind == "terminal" then
    if not (src.item and src.item:getContainer() ~= nil and player:getInventory():contains(src.item, true)) then out[#out + 1] = getText("IGUI_Sandevistan_Fw_Req_Terminal")
    elseif have(player, W.Battery) < W.BatteriesPerWrite then out[#out + 1] = getText("IGUI_Sandevistan_Fw_Req_Battery") end
  elseif src and src.kind == "pc" then
    if not FC.powered(src.square) then out[#out + 1] = getText("IGUI_Sandevistan_Fw_Req_Power") end
  end
end

-- Gasta lo que consume la fuente al terminar: con el terminal, las baterias (la computadora no gasta nada).
local function consumeSource(player, src)
  if not (src and src.kind == "terminal") then return end
  local W = CFG.Firmware.Write
  for _ = 1, W.BatteriesPerWrite do
    local b = firstOf(player, W.Battery)
    if b then FC.removeItem(b) end
  end
end

-- Motivos por los que no se puede escribir ese programa ahora (textos del idioma activo; vacia = se puede). src = { kind = "pc", square = casilla } o { kind = "terminal", item = item }.
function FC.writeReasons(player, id, src)
  local d = S.data(player)
  local out = FW.problemTexts(FW.writeProblems(d, id))
  local W = CFG.Firmware.Write
  local p = FW.program(id)
  if not p then return out end
  if have(player, FW.BLANK) < 1 then out[#out + 1] = getText("IGUI_Sandevistan_Fw_Req_BlankChip") end
  if (p.only == "military" or p.origin == "military") and have(player, W.MilitaryChip) < 1 then out[#out + 1] = getText("IGUI_Sandevistan_Fw_Req_MilChip") end
  sourceReasons(player, src, out)
  return out
end

-- Escribe el programa: consume el chip virgen (y el microchip militar, y la bateria con el terminal) y entrega el chip programado. Sin tirada: con el programa conocido y los materiales
-- siempre sale. Cancelar la accion antes de que termine no gasta nada (todo se consume aca, al final). Devuelve true si lo hizo.
function FC.write(player, id, src)
  if #FC.writeReasons(player, id, src) > 0 then return false end
  local W = CFG.Firmware.Write
  local p = FW.program(id)
  local blank = firstOf(player, FW.BLANK)
  if not blank or not FC.removeItem(blank) then return false end
  if p.only == "military" or p.origin == "military" then          -- (111) los disenos militares (Camara criogenica) piden el microchip
    local chip = firstOf(player, W.MilitaryChip)
    if chip then FC.removeItem(chip) end
  end
  consumeSource(player, src)
  FC.giveChip(player, id)
  local c = FC.COLOR[p.slot] or { 255, 255, 255 }
  E.halo(player, getText("IGUI_Sandevistan_Fw_Written", FC.name(id)), c[1], c[2], c[3])
  return true
end

---------------------------------------------------------------------------
-- Decompilar (87): un chip programado que encontraste, en una computadora con corriente o con el terminal. Aprendes su programa y el chip queda en blanco.
---------------------------------------------------------------------------
function FC.decompileSeconds(player) return FW.decompileSeconds(S.data(player)) end
function FC.decompileTicks(player) return FC.ticks(FC.decompileSeconds(player)) end

-- Los chips programados que lleva el jugador (uno por programa), en el orden de Config.Firmware.Order: lista de { id, item }.
function FC.programmedChips(player)
  local out = {}
  for _, id in ipairs(CFG.Firmware.Order) do
    local it = firstOf(player, FW.itemType(id))
    if it then out[#out + 1] = { id = id, item = it } end
  end
  return out
end

-- Motivos por los que no se puede decompilar el chip de ese programa ahora (vacia = se puede). Mismas fuentes que escribir.
function FC.decompileReasons(player, id, src)
  local out = FW.problemTexts(FW.decompileProblems(S.data(player), id))
  if FW.program(id) and have(player, FW.itemType(id)) < 1 then out[#out + 1] = getText("IGUI_Sandevistan_Fw_Req_ChipMissing") end
  sourceReasons(player, src, out)
  return out
end

-- Decompila: el chip programado se gasta (y la bateria con el terminal), el jugador aprende el programa y recibe un chip en blanco. Todo al final: cancelar antes no cuesta nada.
function FC.decompile(player, id, src)
  if #FC.decompileReasons(player, id, src) > 0 then return false end
  local chip = firstOf(player, FW.itemType(id))
  if not chip or not FC.removeItem(chip) then return false end
  consumeSource(player, src)
  FC.giveChip(player, "Blank")
  FW.learn(S.data(player), id)
  local c = FC.COLOR[FW.program(id).slot] or { 255, 255, 255 }
  E.halo(player, getText("IGUI_Sandevistan_Fw_Decompiled", FC.name(id)), c[1], c[2], c[3])
  return true
end

---------------------------------------------------------------------------
-- Texto de detalle (formato del texto enriquecido de PZ; SandevistanMenus.showText lo muestra)
---------------------------------------------------------------------------
function FC.detail(player, id)
  local p = FW.program(id)
  if not p then return getText("IGUI_Sandevistan_Fw_BlankName"), getText("IGUI_Sandevistan_Fw_BlankText") end
  local only = getText("IGUI_Sandevistan_Fw_Only_" .. (p.only or "all"))
  local body = { getText("IGUI_Sandevistan_Fw_DetailSlot", FC.slotLabel(p.slot), only), " <LINE> <LINE> " }
  if p.ready then
    body[#body + 1] = getText("IGUI_Sandevistan_FwDesc_" .. id)
    body[#body + 1] = " <LINE> <LINE> " .. getText("IGUI_Sandevistan_Fw_DetailChanges") .. " <LINE> "
    for _, l in ipairs(FW.fieldLines(id)) do body[#body + 1] = "- " .. l .. " <LINE> " end
  else
    body[#body + 1] = getText("IGUI_Sandevistan_Fw_DetailNotReady")
    body[#body + 1] = " <LINE> "
  end
  body[#body + 1] = " <LINE> " .. getText("IGUI_Sandevistan_Fw_DetailLevel", p.level)
  if p.dossiers then body[#body + 1] = " <LINE> " .. getText("IGUI_Sandevistan_Fw_DetailDossier") end
  body[#body + 1] = " <LINE> " .. getText("IGUI_Sandevistan_Fw_DetailDecompile")
  return getText("IGUI_Sandevistan_Fw_DetailTitle", FC.name(id), p.code), table.concat(body)
end

---------------------------------------------------------------------------
-- Debug (Debug -> Firmware)
---------------------------------------------------------------------------
-- Da el chip base y un chip de cada programa.
function FC.debugGiveAll(player)
  local n = 0
  if FC.giveChip(player, "Blank") then n = n + 1 end
  for _, id in ipairs(CFG.Firmware.Order) do
    if FC.giveChip(player, id) then n = n + 1 end
  end
  return n
end

-- (85) Para probar escribir programas: el terminal portatil, tres baterias, tres chips virgenes y un microchip militar. Devuelve cuantos items dio.
function FC.debugGiveWriter(player)
  local W = CFG.Firmware.Write
  local n = 0
  if S.grantItem(player, W.Terminal) then n = n + 1 end
  for _ = 1, 3 do if S.grantItem(player, W.Battery) then n = n + 1 end end
  for _ = 1, 3 do if FC.giveChip(player, "Blank") then n = n + 1 end end
  if S.grantItem(player, W.MilitaryChip) then n = n + 1 end
  return n
end

-- (87) Para probar decompilar: el terminal portatil, tres baterias y un chip programado de cada programa. Devuelve cuantos items dio.
function FC.debugGiveDecompile(player)
  local W = CFG.Firmware.Write
  local n = 0
  if S.grantItem(player, W.Terminal) then n = n + 1 end
  for _ = 1, 3 do if S.grantItem(player, W.Battery) then n = n + 1 end end
  for _, id in ipairs(CFG.Firmware.Order) do
    if CFG.Firmware.Programs[id].ready and FC.giveChip(player, id) then n = n + 1 end
  end
  return n
end

-- (86) Modo trabajo sin condiciones: pone Taller (sin costo ni chip) y lo enciende ignorando los candados (CN, rechazo y amenazas). Con off = true lo apaga.
function FC.debugWork(player, off)
  local s = R.session(player)
  if off then s.workForce = false; s.workForceWorking = false; R.deactivate(player, "forced"); return false end
  FC.debugSet(player, "Taller")
  s.workForce = true; s.workForceWorking = true; s.reuseAtMs = 0
  return R.activate(player)
end

-- (85) Marca como aprendidos todos los programas terminados (sin tocar el nivel de adaptacion) / olvida todos.
function FC.debugLearnAll(player)
  local d = S.data(player)
  if type(d.fwKnown) ~= "table" then d.fwKnown = {} end
  local n = 0
  for _, id in ipairs(CFG.Firmware.Order) do
    if CFG.Firmware.Programs[id].ready and not d.fwKnown[id] then d.fwKnown[id] = true; n = n + 1 end
  end
  d.knows.firmware = true
  return n
end
function FC.debugForgetAll(player) S.data(player).fwKnown = {} end

-- Pone un programa en su slot sin costo ni chip (para probar). Devuelve el que estaba.
function FC.debugSet(player, id)
  local d = S.data(player)
  local p = FW.program(id)
  if not p then return nil end
  return FW.setSlot(d, p.slot, id)
end

function FC.debugClear(player)
  local d = S.data(player)
  for _, slot in ipairs(CFG.Firmware.Slots) do FW.setSlot(d, slot, nil) end
  d.fwRecalUntil = nil
end

-- El perfil vigente como lineas de texto "campo = valor" (solo lo que se aparta de lo neutro) para el log y el reporte.
function FC.profileLines(player)
  local d = S.data(player)
  local prof = FW.profile(d)
  local out = {}
  for _, k in ipairs(FW.FIELD_ORDER) do
    local v, n = prof[k], FW.NEUTRAL[k]
    if v ~= nil and v ~= n then
      if type(v) == "table" then out[#out + 1] = string.format("%s = { %s, %s }", k, tostring(v[1]), tostring(v[2]))
      else out[#out + 1] = string.format("%s = %s", k, tostring(v)) end
    end
  end
  return out
end

return FC
