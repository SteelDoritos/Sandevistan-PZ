-- Sandevistan / World (servidor; en SP corre en el mismo proceso).
-- ModData global, campus activos, colocaciones únicas por zona, ex-sujetos, registro de
-- cadáveres con implante y aparición de respaldo.
require "Sandevistan/Core"

local CFG = SandevistanConfig
local S = Sandevistan

SandevistanWorld = {}
local W = SandevistanWorld

-- v0.1.30 (13): quién maneja el mundo. El cliente de multijugador también carga los archivos de server/ (el primer reporte MP mostró
-- "mundo inicializado" en el cliente): ahí no se registra ningún evento del mundo. Antes cada cliente colocaba su propia copia de
-- los sets (con ítems reales que viajaban al servidor) y spawneaba sus propios ex-sujetos, de nuevo en cada sesión, porque el ModData
-- global del cliente no se guarda. Autoridad = un jugador (SP) o el proceso servidor (dedicado o anfitrión).
W.authority = isServer() or not isClient()

local ZONES_CAMPUS = { "lsu", "ekron" }

function W.data()
  local w = ModData.getOrCreate("SandevistanWorld")
  w.placements = w.placements or {}
  w.zones = w.zones or {}
  w.subjects = w.subjects or {}
  w.aliveByOutfit = w.aliveByOutfit or {}
  w.anchorOverrides = w.anchorOverrides or {}
  w.civilExSubject = w.civilExSubject or {}
  w.nextId = w.nextId or 1
  return w
end

---------------------------------------------------------------------------
-- Inicialización: campus activos y tiradas (una sola vez por mundo)
---------------------------------------------------------------------------
function W.init()
  SandevistanConfig.applySandbox()
  local w = W.data()
  if w.initialized then return end
  local mode = CFG.World.LabCampus
  local active = {}
  if mode == "all" then active = { "lsu", "ekron" }
  elseif mode == "random" then active = { ZONES_CAMPUS[ZombRand(#ZONES_CAMPUS) + 1] }
  elseif CFG.Campuses[mode] then active = { mode }
  else active = { "lsu", "ekron" } end
  w.activeCampuses = active
  for _, c in ipairs(active) do
    w.civilExSubject[c] = S.chance(CFG.ExSubjects.CivilExSubjectChance)
  end
  w.initialized = true
  S.log("mundo inicializado; campus activos: " .. table.concat(active, ", "))
end

function W.isZoneActive(zone)
  if zone == "base" then return true end
  local w = W.data()
  for _, c in ipairs(w.activeCampuses or {}) do if c == zone then return true end end
  return false
end

function W.zoneState(zone)
  local w = W.data()
  w.zones[zone] = w.zones[zone] or { fixedSpawned = false, extraCount = 0, lastCheckHour = -1000, placed = false }
  return w.zones[zone]
end

---------------------------------------------------------------------------
-- Anclas
---------------------------------------------------------------------------
function W.anchor(zone)
  local w = W.data()
  if w.anchorOverrides[zone] then return w.anchorOverrides[zone] end
  if zone == "base" then return CFG.Locations.base.anchor end
  return CFG.Campuses[zone] and CFG.Campuses[zone].anchor or nil
end

local anchorIndex = nil
function W.rebuildAnchorIndex()
  anchorIndex = {}
  for _, zone in ipairs({ "base", "lsu", "ekron" }) do
    local a = W.anchor(zone)
    if a and W.isZoneActive(zone) then
      anchorIndex[a.x .. "," .. a.y .. "," .. a.z] = zone
    end
  end
end

-- Debug: fija el ancla de una zona en un cuadrado y dispara su carga.
function W.setAnchor(zone, square)
  local w = W.data()
  w.anchorOverrides[zone] = { x = square:getX(), y = square:getY(), z = square:getZ() }
  W.rebuildAnchorIndex()
  W.resetScan(zone)
  W.processZone(zone, true)
  S.log("ancla " .. zone .. " = " .. square:getX() .. "," .. square:getY() .. "," .. square:getZ())
end

---------------------------------------------------------------------------
-- Colocaciones únicas
---------------------------------------------------------------------------
-- Jugadores a considerar: en un servidor son los conectados (getSpecificPlayer/getNumActivePlayers solo existen
-- en el cliente: en v0.1.25 el servidor nunca veía a nadie y no colocaba nada).
local function allPlayers()
  local out = {}
  if isServer() then
    local ok, online = pcall(getOnlinePlayers)
    for i = 0, ((ok and online) and online:size() or 0) - 1 do out[#out + 1] = online:get(i) end
  else
    for i = 0, getNumActivePlayers() - 1 do
      local p = getSpecificPlayer(i)
      if p then out[#out + 1] = p end
    end
  end
  return out
end
W.allPlayers = allPlayers

-- what: tipo completo o un ítem ya armado (la bolsa de Leo, llena). ItemSpawner (y AddWorldInventoryItem sin el ultimo argumento) lo transmite a los
-- clientes al ponerlo en el suelo, con su ModData y su contenido: por eso el ModData va ANTES (puesto despues, a los clientes no les llega).
local function dropItem(square, what, md)
  local item = nil
  local proto = what
  if type(what) == "string" and md and rawget(_G, "instanceItem") then pcall(function() proto = instanceItem(what) end) end
  if type(proto) ~= "string" and md then for k, v in pairs(md) do proto:getModData()[k] = v end end
  local x, y = ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8)
  if rawget(_G, "ItemSpawner") then
    S.try("ItemSpawner", function() item = ItemSpawner.spawnItem(proto, square, x, y, 0) end)
    if type(item) == "boolean" then item = nil end
  end
  if not item then
    S.try("AddWorldInventoryItem", function() item = square:AddWorldInventoryItem(proto, x, y, 0) end)
  end
  if item and md then for k, v in pairs(md) do item:getModData()[k] = v end end
  return item
end

local function nearbySquare(ax, ay, az, minR, maxR, tries)
  local cell = getCell()
  for _ = 1, tries or 20 do
    local r = S.randRange(minR, maxR)
    local ang = ZombRandFloat(0, 6.2831)
    local x = math.floor(ax + math.cos(ang) * r)
    local y = math.floor(ay + math.sin(ang) * r)
    local sq = cell:getGridSquare(x, y, az)
    if sq and sq:isSolidFloor() and sq:isFree(false) then return sq end
  end
  return cell:getGridSquare(ax, ay, az)
end

---------------------------------------------------------------------------
-- Escaneo del edificio: habitaciones por nombre alrededor del ancla (todas las plantas)
---------------------------------------------------------------------------
local scanCache = {}

local function zoneCfg(zone)
  if zone == "base" then return CFG.Locations.base end
  return CFG.Campuses[zone] or {}
end

-- Caja de escaneo alrededor del ancla: desplazamientos x0..x1 (oeste..este) e y0..y1 (norte..sur). scanRadius simétrico; scanExtent
-- { w, e, n, s } lo hace asimétrico (el ancla no siempre queda en el centro del complejo).
local function scanBox(zone)
  local zc = zoneCfg(zone)
  local r = zc.scanRadius or 40
  local ex = zc.scanExtent or {}
  return -(ex.w or r), (ex.e or r), -(ex.n or r), (ex.s or r)
end

local function categorize(name)
  local n = string.lower(name or "")
  for _, cat in ipairs({ "medical", "lab", "storage", "office" }) do
    for _, word in ipairs(CFG.RoomKeywords[cat] or {}) do
      if string.find(n, word, 1, true) then return cat end
    end
  end
  return "other"
end

function W.resetScan(zone) scanCache[zone] = nil end

function W.scanBuilding(zone)
  if scanCache[zone] then return scanCache[zone] end
  local a = W.anchor(zone)
  if not a then return nil end
  local zc = zoneCfg(zone)
  local r = zc.scanRadius or 40
  local bx0, bx1, by0, by1 = scanBox(zone)
  local res = { containers = {}, floors = {}, all = {}, roomNames = {}, top = nil, nContainers = 0, anchor = a, zone = zone }
  local cell = getCell()
  for z = zc.zMin or -3, zc.zMax or 3 do
    for dx = bx0, bx1 do
      for dy = by0, by1 do
        local sq = cell:getGridSquare(a.x + dx, a.y + dy, z)
        local room = sq and sq:getRoom()
        if room then
          local name = "?"
          pcall(function() name = tostring(room:getName()) end)
          local cat = categorize(name)
          res.roomNames[name] = cat
          res.floors[cat] = res.floors[cat] or {}
          table.insert(res.floors[cat], sq)
          table.insert(res.all, sq)
          if not res.top or z > res.top:getZ() or (z == res.top:getZ() and sq:getY() < res.top:getY()) then res.top = sq end
          local objs = sq:getObjects()
          for i = 0, objs:size() - 1 do
            local c = nil
            pcall(function() c = objs:get(i):getContainer() end)
            if c then
              res.containers[cat] = res.containers[cat] or {}
              table.insert(res.containers[cat], { c = c, sq = sq })
              res.nContainers = res.nContainers + 1
            end
          end
        end
      end
    end
  end
  local summary = {}
  for name, cat in pairs(res.roomNames) do table.insert(summary, name .. ":" .. cat) end
  S.log("escaneo " .. zone .. ": " .. #res.all .. " casillas con habitacion, " .. res.nContainers .. " contenedores | " .. table.concat(summary, ", "))
  if #res.all > 0 then scanCache[zone] = res end
  return res
end

-- Elige un contenedor de la primera categoría con candidatos. prefer: "low" | "high" | nil (azar)
local function pickContainer(res, cats, prefer, minZ, maxZ)
  local function zOk(z) return (not minZ or z >= minZ) and (not maxZ or z <= maxZ) end
  if prefer == "low" then
    -- la planta más baja entre TODAS las categorías permitidas (v0.1.29: antes mandaba la categoría y, con un laboratorio en la
    -- superficie, las cajas criogénicas quedaban arriba); dentro de esa planta, la primera categoría con candidatos
    local target = nil
    for _, cat in ipairs(cats) do
      for _, e in ipairs(res.containers[cat] or {}) do
        local z = e.sq:getZ()
        if zOk(z) and (target == nil or z < target) then target = z end
      end
    end
    if target == nil then return nil end
    for _, cat in ipairs(cats) do
      local same = {}
      for _, e in ipairs(res.containers[cat] or {}) do if e.sq:getZ() == target then table.insert(same, e) end end
      if #same > 0 then return same[ZombRand(#same) + 1] end
    end
    return nil
  end
  for _, cat in ipairs(cats) do
    local list = {}
    for _, e in ipairs(res.containers[cat] or {}) do
      if zOk(e.sq:getZ()) then table.insert(list, e) end
    end
    if #list > 0 then
      if prefer then
        local target = nil
        for _, e in ipairs(list) do
          local z = e.sq:getZ()
          if target == nil or (prefer == "low" and z < target) or (prefer == "high" and z > target) then target = z end
        end
        local same = {}
        for _, e in ipairs(list) do if e.sq:getZ() == target then table.insert(same, e) end end
        list = same
      end
      return list[ZombRand(#list) + 1]
    end
  end
  return nil
end

-- Registro de colocaciones (ModData: sobrevive a casillas descargadas): dónde quedó cada ítem del set, en qué habitación y cómo
-- (contenedor / suelo de una habitación / suelo del ancla). Lo muestra la auditoría y sirve para ir a verlo.
local function roomOf(sq)
  local n = "-"
  pcall(function() local r = sq:getRoom(); if r then n = tostring(r:getName()) end end)
  return n
end

local function logPlaced(zone, fullType, sq, how)
  if not zone or not sq then return end
  local w = W.data()
  w.placedLog = w.placedLog or {}
  local l = w.placedLog[zone] or {}
  w.placedLog[zone] = l
  local e = { t = fullType, x = sq:getX(), y = sq:getY(), z = sq:getZ(), room = roomOf(sq), how = how }
  l[#l + 1] = e
  S.log(string.format("colocado %s: %s en %s (%d,%d,%d) hab=%s", zone, fullType, how, e.x, e.y, e.z, e.room))
end

-- Coloca un ítem en un contenedor de las categorías dadas; si no hay, en el piso de una
-- habitación de esas categorías; si tampoco, en el ancla.
-- minZ / maxZ (opcionales): límites de planta. Si con maxZ no hay contenedor, se relaja (mejor un lugar razonable que el suelo del ancla).
-- Marca de "lo colocó el mod" (v0.1.29): la purga de debug solo borra ítems marcados, nunca lo que el jugador trajo o soltó.
local function markPlaced(item)
  if item then pcall(function() item:getModData().SandevistanPlaced = true end) end
  return item
end

local function place(res, cats, fullType, prefer, md, minZ, maxZ)
  local e = res and (pickContainer(res, cats, prefer, minZ, maxZ) or (maxZ and pickContainer(res, cats, prefer, minZ)))
  local item = nil
  local zone = res and res.zone
  local all = { SandevistanPlaced = true }                 -- la marca y el ModData pedido viajan con el ítem
  if md then for k, v in pairs(md) do all[k] = v end end
  if e then
    S.try("containerAdd", function() item = S.giveItem(e.c, fullType, all) end)     -- giveItem avisa a los clientes (MP)
    if item then logPlaced(zone, fullType, e.sq, "contenedor") end
  end
  if not item then
    local sq = nil
    local how = "suelo de habitación"
    for _, cat in ipairs(cats) do
      local fl = res and res.floors[cat]
      if fl and #fl > 0 then sq = fl[ZombRand(#fl) + 1]; break end
    end
    if not sq and res and res.all and #res.all > 0 then sq = res.all[ZombRand(#res.all) + 1]; how = "suelo (sin habitación de la categoría)" end
    if not sq then
      local a = res and res.anchor
      sq = a and getCell():getGridSquare(a.x, a.y, a.z)
      how = "suelo del ANCLA (respaldo)"
    end
    if sq then
      item = dropItem(sq, fullType, all)
      if item then logPlaced(zone, fullType, sq, how) end
    end
    if not item then S.logAlways("WARN no se pudo colocar " .. fullType .. " en " .. tostring(zone)) end
  end
  markPlaced(item)
  if item and md then for k, v in pairs(md) do item:getModData()[k] = v end end
  return item
end

-- (125) ¿El set ya esta en el mapa? El juego guarda los chunks ANTES que el ModData global ("Saving worldgen params" -> chunks -> "Saving GlobalModData"):
-- si se cierra en el medio, los items quedan guardados pero placements no, y la sesion siguiente colocaba el set otra vez (paso en Ekron el 2026-10-09:
-- notas y bolso de Leo duplicados). Antes de colocar se buscan items con la marca del mod en los contenedores, el suelo y la casilla fija del bolso;
-- si hay, se da el set por colocado y se rehace placedLog con lo encontrado (los ex-sujetos aparecen al lado del set).
local placedIn
local function placedItem(it, depth, found, sq)
  local md, ft = nil, nil
  pcall(function() md = it:getModData(); ft = it:getFullType() end)
  if md and (md.SandevistanPlaced == true or md.SandevistanLeoBag == true) then
    found[#found + 1] = { t = ft, sq = sq }
  elseif depth < 1 then
    local inner = nil
    pcall(function() if it.getInventory then inner = it:getInventory() end end)
    if inner then placedIn(inner:getItems(), depth + 1, found, sq) end
  end
end

placedIn = function(list, depth, found, sq)
  for i = 0, list:size() - 1 do placedItem(list:get(i), depth, found, sq) end
end

local function squareFloorItems(sq, found)
  pcall(function()
    local wo = sq:getWorldObjects()
    for i = 0, wo:size() - 1 do
      local it = wo:get(i):getItem()
      if it then placedItem(it, 0, found, sq) end
    end
  end)
end

function W.findPlaced(zone, res)
  local found = {}
  for _, list in pairs(res.containers) do
    for _, e in ipairs(list) do pcall(placedIn, e.c:getItems(), 0, found, e.sq) end
  end
  for _, sq in ipairs(res.all) do squareFloorItems(sq, found) end
  local zc = zoneCfg(zone)
  if zc and zc.bagAt then
    local sq = getCell():getGridSquare(zc.bagAt.x, zc.bagAt.y, zc.bagAt.z)
    if sq then squareFloorItems(sq, found) end
  end
  return found
end

-- Solo cuentan los items propios del set de la zona, y hacen falta al menos dos: una nota que el jugador trajo de otro lugar y solto ahi no frena la colocacion.
local function ownsItem(zone, ft)
  local n = tonumber(string.match(ft or "", "^Sandevistan%.SandevistanNote(%d+)$"))
  if zone == "base" then return (n and n <= 15) or ft == "Sandevistan.SandevistanCryoBox" end
  return (n and n >= 16) or ft == CFG.Crafting.Items.LeoBag or ft == "Sandevistan.ImmunoSynthesisBook"
end

local function recoverPlaced(zone, res)
  local found = {}
  for _, f in ipairs(W.findPlaced(zone, res)) do if ownsItem(zone, f.t) then found[#found + 1] = f end end
  if #found < 2 then return false end
  local w = W.data()
  w.placements[zone .. ".set"] = true
  w.placedLog = w.placedLog or {}
  w.placedLog[zone] = nil
  for _, f in ipairs(found) do logPlaced(zone, f.t, f.sq, "recuperado (ya estaba en el mapa)") end
  S.logAlways("WARN " .. zone .. ": el set ya estaba en el mapa (" .. #found .. " items del mod) pero el ModData no lo sabia (partida cerrada a mitad del guardado?): no se coloca de nuevo")
  return true
end

function W.placeBase()
  local key = "base.set"
  local w = W.data()
  if w.placements[key] then return end
  local res = W.scanBuilding("base")
  if not res or #res.all == 0 then return end
  if recoverPlaced("base", res) then return end
  w.placements[key] = true
  local T = "Sandevistan."
  -- Notas 1-12 (investigador): se reparten por el ala de investigación subterránea (plantas <= DeepMaxZ) para que se vayan encontrando al
  -- bajar: los diarios personales (1, 4, 7, 9, 10) en oficinas y los informes oficiales (2, 3, 5, 6, 8, 11) en laboratorios. La 12 (la nota
  -- cortada) va al fondo de todo, junto a las cajas criogénicas. Las del guardia (13-15), arriba.
  local deep = CFG.World.BaseDeepMaxZ
  local PERSONAL = { [1] = true, [4] = true, [7] = true, [9] = true, [10] = true }
  for n = 1, 11 do
    local nt = T .. string.format("SandevistanNote%02d", n)
    if PERSONAL[n] then place(res, { "office", "other" }, nt, nil, nil, nil, deep)
    else place(res, { "lab", "office", "other" }, nt, nil, nil, nil, deep) end
  end
  place(res, { "lab", "office", "other" }, T .. "SandevistanNote12", "low")
  for n = 13, 15 do place(res, { "office", "storage", "other" }, T .. string.format("SandevistanNote%02d", n), "high", nil, 0) end
  local boxes = math.max(1, math.min(2, CFG.World.MilitaryCryoBoxCount))
  for _ = 1, boxes do place(res, { "lab", "storage", "other" }, T .. "SandevistanCryoBox", "low") end
  for _ = 1, CFG.World.ClinicalCount do place(res, { "medical", "lab", "storage" }, T .. "ImmunosuppressantClinicalPack") end
  for _ = 1, CFG.World.KerenzikovMilitaryCount do place(res, { "medical", "lab", "storage" }, T .. "KerenzikovMilitary") end
  place(res, { "medical", "lab", "office" }, T .. "KerenzikovFormulationBook")
  -- v0.1.30 (43): microchips militares de la replica Mk. II (oficinas y laboratorios); solo si esta activada
  if CFG.Prototype07.Enabled then
    for _ = 1, CFG.World.MilChipCount do place(res, { "lab", "office", "other" }, T .. "MilSpecChip") end
  end
  -- v0.1.30 (87): chips de firmware ya programados: la Camara criogenica al fondo (junto a las cajas criogenicas) y unos pocos al azar entre los demas
  local fw = CFG.World.FwBaseChips
  if CFG.Firmware.Enabled ~= false then
    for _ = 1, CFG.World.FwBaseTerminals or 0 do place(res, { "lab", "office", "storage", "other" }, T .. "FwTerminal") end       -- (88) el terminal no se fabrica
  end
  if fw and CFG.Firmware.Enabled ~= false then          -- (un solo criterio para los dos bloques)
    for _, id in ipairs(fw.fixed or {}) do place(res, { "lab", "storage", "other" }, T .. "Fw" .. id, "low") end
    local pool = {}
    for _, id in ipairs(fw.random and fw.random.pool or {}) do pool[#pool + 1] = id end
    for _ = 1, math.min(fw.random and fw.random.count or 0, #pool) do
      local id = table.remove(pool, ZombRand(#pool) + 1)
      place(res, { "lab", "office", "storage", "other" }, T .. "Fw" .. id)
    end
  end
  S.log("set de la base colocado por habitaciones")
end

-- Casilla para el bolso de Leo: la más al norte de la planta más alta que se pueda pisar (sin objetos sólidos encima, como un tanque o
-- una máquina) y con espacio alrededor (al menos 3 vecinas libres, para no caer en un hueco entre objetos). v0.1.29: en Ekron el
-- bolso quedó dentro de un tanque de la azotea.
local function bagSquare(res)
  local top = res.top
  if not top then return nil end
  local tz = top:getZ()
  local cell = getCell()
  local function walkable(sq)
    local ok, free = pcall(function() return sq:isFree(false) and sq:isSolidFloor() end)
    return ok and free
  end
  local best = nil
  for _, sq in ipairs(res.all) do
    if sq:getZ() == tz and (best == nil or sq:getY() < best:getY()) and walkable(sq) then
      local free = 0
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local n = cell:getGridSquare(sq:getX() + d[1], sq:getY() + d[2], tz)
        if n and walkable(n) then free = free + 1 end
      end
      if free >= 3 then best = sq end
    end
  end
  return best or top
end

function W.placeCampus(zone)
  local key = zone .. ".set"
  local w = W.data()
  if w.placements[key] then return end
  local res = W.scanBuilding(zone)
  if not res or #res.all == 0 then return end
  if recoverPlaced(zone, res) then return end
  w.placements[key] = true
  local T = "Sandevistan."
  -- bolso de Leo junto al acceso a la azotea: la casilla más al norte de la planta más alta
  local bagSq = nil
  local zc = zoneCfg(zone)
  if zc and zc.bagAt then                      -- (94) casilla fija del campus (con piso firme); si no se puede usar, la regla de siempre
    local sq = getCell():getGridSquare(zc.bagAt.x, zc.bagAt.y, zc.bagAt.z)
    local okFloor = false
    if sq then pcall(function() okFloor = sq:isSolidFloor() end) end
    if sq and okFloor then bagSq = sq else S.logAlways("WARN " .. zone .. ": la casilla fija del bolso no sirve (" .. zc.bagAt.x .. "," .. zc.bagAt.y .. "," .. zc.bagAt.z .. "): se usa la planta mas alta") end
  end
  bagSq = bagSq or bagSquare(res) or res.top or res.all[1]
  -- (106) la ultima nota del estudiante (5/5) va en su bolso, con su implante: la historia cierra ahi. El bolso se llena ANTES de ponerlo en el suelo:
  -- asi viaja a los clientes entero (llenarlo despues no les avisa nada; en MP el otro jugador lo veia vacio).
  local contents = { T .. "SandevistanLab" }
  for _ = 1, CFG.World.LeoBagImmunoCount do contents[#contents + 1] = T .. "ImmunosuppressantCraftedPack" end
  contents[#contents + 1] = T .. "SandevistanNote20"
  local packed, inv = nil, nil
  if rawget(_G, "instanceItem") then
    S.try("bagPack", function()
      packed = instanceItem(CFG.Crafting.Items.LeoBag)
      inv = packed and packed:getInventory()
      if not inv then packed = nil; return end
      for _, ft in ipairs(contents) do
        local it = instanceItem(ft)
        if it then markPlaced(it); inv:AddItem(it) end
      end
    end)
  end
  local bag = dropItem(bagSq, packed or CFG.Crafting.Items.LeoBag, { SandevistanLeoBag = true, SandevistanPlaced = true })
  if bag then logPlaced(zone, CFG.Crafting.Items.LeoBag, bagSq, "suelo (acceso a la azotea)") end
  if bag and not packed then S.try("bagInventory", function() inv = bag:getInventory() end) end
  if not (bag and packed) then                             -- sin instanceItem o no se pudo armar: el bolso vacio y se llena (giveItem avisa) o todo al suelo
    if inv then
      for _, ft in ipairs(contents) do markPlaced(S.giveItem(inv, ft, { SandevistanPlaced = true })) end
    else
      for _, ft in ipairs(contents) do markPlaced(dropItem(bagSq, ft)) end
    end
  end
  for n = 16, 19 do place(res, { "lab", "office", "other" }, T .. string.format("SandevistanNote%02d", n)) end
  place(res, { "lab", "office", "other" }, T .. "ImmunoSynthesisBook")
  -- (161) T10: un First Aid vol. 1 y un Electricista vol. 1 en el laboratorio de los campus (además del botín aleatorio)
  place(res, { "lab", "storage", "office", "other" }, "Base.BookFirstAid1")
  place(res, { "lab", "storage", "office", "other" }, "Base.BookElectrician1")
  local c = CFG.World.SyntheticCompoundCount
  for _ = 1, ZombRand(c[1], c[2] + 1) do place(res, { "storage", "lab", "medical" }, T .. "SyntheticCompoundSample") end
  if CFG.Prototype04.Enabled then place(res, { "storage", "lab", "other" }, T .. "SandevistanLabP04Broken", "low") end
  if S.chance(CFG.ExSubjects.CampusContainerImplantChance) then
    place(res, { "lab", "storage", "office", "other" }, T .. "SandevistanLab", nil, { heatDegradationMultiplier = 1.2 })
  end
  S.log("set civil colocado por habitaciones en " .. zone)
end

---------------------------------------------------------------------------
-- Auditoría (Debug): cuenta los ítems del mod que hay realmente en el mapa alrededor del ancla, por tipo, lugar y habitación.
-- Sirve para comprobar en el juego que los sets se colocaron donde corresponde (solo ve casillas cargadas).
---------------------------------------------------------------------------
local function countItems(list, where, room, z, out, depth)
  if not list then return end
  for i = 0, list:size() - 1 do
    local it = list:get(i)
    local ft = nil
    pcall(function() ft = it:getFullType() end)
    if ft and string.find(ft, "^Sandevistan%.") then
      local k = ft .. " | " .. where .. " | " .. room .. " | z=" .. z
      out[k] = (out[k] or 0) + 1
    end
    if (depth or 0) < 2 then       -- bolsos y cajas anidados
      local inner = nil
      pcall(function() if it.getInventory then inner = it:getInventory() end end)
      if inner then countItems(inner:getItems(), where .. ">bolso", room, z, out, (depth or 0) + 1) end
    end
  end
end

function W.audit(zone)
  local a = W.anchor(zone)
  local lines = {}
  if not a then return { zone .. ": sin ancla" } end
  local zc = zoneCfg(zone)
  local r = zc.scanRadius or 40
  local bx0, bx1, by0, by1 = scanBox(zone)
  local cell = getCell()
  local out, squaresSeen, roomSquares = {}, 0, 0
  for z = zc.zMin or -3, zc.zMax or 3 do
    for dx = bx0, bx1 do
      for dy = by0, by1 do
        local sq = cell:getGridSquare(a.x + dx, a.y + dy, z)
        if sq then
          squaresSeen = squaresSeen + 1
          local room, cat = "-", "-"
          pcall(function()
            local rm = sq:getRoom()
            if rm then room = tostring(rm:getName()); cat = categorize(room); roomSquares = roomSquares + 1 end
          end)
          local label = room .. "(" .. cat .. ")"
          local objs = sq:getObjects()
          for i = 0, objs:size() - 1 do
            local c = nil
            pcall(function() c = objs:get(i):getContainer() end)
            if c then countItems(c:getItems(), "contenedor", label, z, out, 0) end
          end
          pcall(function()
            local wo = sq:getWorldObjects()
            for i = 0, wo:size() - 1 do
              local item = wo:get(i):getItem()
              if item then
                local one = { size = function() return 1 end, get = function() return item end }
                countItems(one, "suelo", label, z, out, 0)
              end
            end
          end)
        end
      end
    end
  end
  lines[#lines + 1] = string.format("%s: ancla %d,%d,%d radio %d | casillas cargadas %d, con habitación %d | activa=%s colocada=%s",
    zone, a.x, a.y, a.z, math.max(bx1 - bx0, by1 - by0) / 2, squaresSeen, roomSquares, tostring(W.isZoneActive(zone)), tostring(W.data().placements[zone .. ".set"] == true))
  local keys = {}
  for k in pairs(out) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do lines[#lines + 1] = "  " .. out[k] .. " x " .. k end
  if #keys == 0 then lines[#lines + 1] = "  (ningún ítem del mod en las casillas cargadas)" end
  local log = W.data().placedLog and W.data().placedLog[zone]
  if log and #log > 0 then
    lines[#lines + 1] = "  registro de colocaciones (" .. #log .. "):"
    for _, e in ipairs(log) do
      lines[#lines + 1] = string.format("    %s | %s | %d,%d,%d | hab=%s", e.t, e.how, e.x, e.y, e.z, e.room)
    end
  else
    lines[#lines + 1] = "  (sin registro de colocaciones: el set se colocó en una versión anterior o todavía no)"
  end
  local st = W.data().zones[zone]
  if st then
    lines[#lines + 1] = string.format("  ex-sujetos fijos: generados=%s (%s creados, %s intentos), extras=%s", tostring(st.fixedSpawned),
      tostring(st.fixedMade or 0), tostring(st.fixedTries or 0), tostring(st.extraCount))
  end
  local byState = {}
  for _, sub in pairs(W.data().subjects) do
    if sub.zone == zone then byState[sub.state] = (byState[sub.state] or 0) + 1 end
  end
  for state, n in pairs(byState) do lines[#lines + 1] = "  ex-sujetos registrados: " .. n .. " " .. tostring(state) end
  for _, l in ipairs(lines) do S.log("auditoría " .. l) end
  return lines
end

-- Habitaciones que ve el escaneo alrededor del ancla, por planta: nombre, categoría, casillas y contenedores. Sirve para ajustar
-- las palabras clave (Config.RoomKeywords), el radio o el ancla cuando algo no aparece donde se espera.
function W.scanReport(zone)
  local a = W.anchor(zone)
  if not a then return { zone .. ": sin ancla" } end
  local zc = zoneCfg(zone)
  local r = zc.scanRadius or 40
  local bx0, bx1, by0, by1 = scanBox(zone)
  local cell = getCell()
  local rooms, order = {}, {}
  local minX, maxX, minY, maxY, minZ, maxZ = nil, nil, nil, nil, nil, nil
  for z = zc.zMin or -3, zc.zMax or 3 do
    for dx = bx0, bx1 do
      for dy = by0, by1 do
        local sq = cell:getGridSquare(a.x + dx, a.y + dy, z)
        local room = sq and sq:getRoom()
        if room then
          local name = "?"
          pcall(function() name = tostring(room:getName()) end)
          local key = string.format("z=%d %s", z, name)
          local e = rooms[key]
          if not e then e = { z = z, name = name, cat = categorize(name), squares = 0, containers = 0 }; rooms[key] = e; order[#order + 1] = key end
          e.squares = e.squares + 1
          local objs = sq:getObjects()
          for i = 0, objs:size() - 1 do
            local c = nil
            pcall(function() c = objs:get(i):getContainer() end)
            if c then e.containers = e.containers + 1 end
          end
          if not minZ or z < minZ then minZ = z end
          if not maxZ or z > maxZ then maxZ = z end
          local x, y = sq:getX(), sq:getY()
          if not minX or x < minX then minX = x end
          if not maxX or x > maxX then maxX = x end
          if not minY or y < minY then minY = y end
          if not maxY or y > maxY then maxY = y end
        end
      end
    end
  end
  table.sort(order)
  local lines = { string.format("habitaciones alrededor de %s (%d,%d,%d) oeste %d este %d norte %d sur %d, plantas %d..%d:", zone, a.x, a.y, a.z, -bx0, bx1, -by0, by1, zc.zMin or -3, zc.zMax or 3) }
  for _, k in ipairs(order) do
    local e = rooms[k]
    lines[#lines + 1] = string.format("  z=%d | %s | categoria=%s | casillas=%d | contenedores=%d", e.z, e.name, e.cat, e.squares, e.containers)
  end
  if #order == 0 then lines[#lines + 1] = "  (ninguna habitación en las casillas cargadas)"
  else
    lines[#lines + 1] = string.format("  extensión con habitación: x %d..%d, y %d..%d (el escaneo cubre x %d..%d, y %d..%d)",
      minX, maxX, minY, maxY, a.x + bx0, a.x + bx1, a.y + by0, a.y + by1)
    local clipped = {}
    if minX <= a.x + bx0 then clipped[#clipped + 1] = "oeste (x mín)" end
    if maxX >= a.x + bx1 then clipped[#clipped + 1] = "este (x máx)" end
    if minY <= a.y + by0 then clipped[#clipped + 1] = "norte (y mín)" end
    if maxY >= a.y + by1 then clipped[#clipped + 1] = "sur (y máx)" end
    if minZ and minZ <= (zc.zMin or -3) then clipped[#clipped + 1] = "planta más baja (z=" .. minZ .. ")" end
    if maxZ and maxZ >= (zc.zMax or 3) then clipped[#clipped + 1] = "planta más alta (z=" .. maxZ .. ")" end
    if #clipped > 0 then
      lines[#lines + 1] = "  AVISO: hay habitaciones pegadas al límite del escaneo (" .. table.concat(clipped, ", ") .. "): el edificio sigue más allá; ampliar scanRadius/scanExtent/zMin/zMax o mover el ancla"
    end
  end
  return lines
end

-- Escribe la auditoría de las 3 zonas + el reporte de habitaciones en Zomboid/Lua/Sandevistan_audit.txt (para mandarlo como texto).
-- Auditoría + reporte de habitaciones de UNA zona (solo ve las casillas cargadas: hay que estar cerca).
function W.collectZone(zone)
  local out = {}
  local ok, res = pcall(W.audit, zone)
  for _, l in ipairs(ok and res or { zone .. ": ERROR en la auditoria: " .. tostring(res) }) do out[#out + 1] = l end
  local ok2, rep = pcall(W.scanReport, zone)
  for _, l in ipairs(ok2 and rep or { zone .. ": ERROR en el reporte: " .. tostring(rep) }) do out[#out + 1] = l end
  return out
end

-- sections (opcional): { zona = líneas } ya recogidas (por ejemplo, por el recorrido de Debug); las que falten se recogen ahora.
function W.exportAudit(sections)
  local lines = { "# Sandevistan " .. tostring(CFG.Version) .. ": auditoria de spawns (mundo, hora del juego " .. tostring(S.worldHours()) .. ")" }
  for _, zone in ipairs({ "base", "lsu", "ekron" }) do
    local sec = sections and sections[zone] or W.collectZone(zone)
    for _, l in ipairs(sec) do lines[#lines + 1] = l end
    lines[#lines + 1] = ""
  end
  local wrote = pcall(function()
    local w = getFileWriter("Sandevistan_audit.txt", true, false)
    if w then
      for _, l in ipairs(lines) do w:write(S.ascii(l) .. "\n") end
      w:close()
    else error("sin escritor") end
  end)
  S.log("auditoria exportada: " .. #lines .. " lineas, archivo " .. (wrote and "escrito en Zomboid/Lua/Sandevistan_audit.txt" or "NO se pudo escribir"))
  return lines, wrote
end

---------------------------------------------------------------------------
-- Ex-sujetos
---------------------------------------------------------------------------
local sessionTagged = {}   -- zombie -> subjectId (solo en memoria)
function W.tagged() return sessionTagged end

-- (94) Debug: la ultima posicion conocida de cada ex-sujeto vivo (al nacer y cada vez que se revisan los zombis cargados), para poder ir a buscarlo aunque su zona no este cargada.
local function rememberPositions()
  local w = W.data()
  for z, id in pairs(sessionTagged) do
    local sub = w.subjects[id]
    if sub and sub.state == "alive" then
      pcall(function()
        if not z:isDead() then sub.lx, sub.ly, sub.lz = z:getX(), z:getY(), z:getZ() end
      end)
    end
  end
end
W.rememberPositions = rememberPositions

-- Ex-sujetos vivos, con su posicion: la del zombi si esta cargado ahora, si no la ultima conocida (o sin posicion). { id, variant, zone, x, y, z, loaded }
function W.liveSubjects()
  local w = W.data()
  local byId = {}
  for z, id in pairs(sessionTagged) do
    local ok, dead = pcall(z.isDead, z)
    if ok and not dead then byId[id] = z end
  end
  local out = {}
  for id, s in pairs(w.subjects) do
    if s.state == "alive" then
      local e = { id = id, variant = s.variant, zone = s.zone }
      local z = byId[id]
      if z then pcall(function() e.x, e.y, e.z = z:getX(), z:getY(), z:getZ(); e.loaded = true end) end
      if not e.x and s.lx then e.x, e.y, e.z = s.lx, s.ly, s.lz end
      out[#out + 1] = e
    end
  end
  table.sort(out, function(a, b) return (tonumber(string.match(a.id, "%d+")) or 0) < (tonumber(string.match(b.id, "%d+")) or 0) end)
  return out
end

-- Debug: borra los ítems del mod de la zona (casillas cargadas) y vuelve a colocar el set. Útil si el ancla o el radio cambiaron.
-- Solo los que colocó el mod (marca SandevistanPlaced).
local function isModItem(it)
  local ft = nil
  pcall(function() ft = it:getFullType() end)
  if ft == nil or string.find(ft, "^Sandevistan%.") == nil then return false end
  local placed = false
  pcall(function() placed = it:getModData().SandevistanPlaced == true end)
  return placed
end

local function purgeContainer(c, depth)
  local n = 0
  local items = c:getItems()
  local doomed, bags = {}, {}
  for i = 0, items:size() - 1 do
    local it = items:get(i)
    if isModItem(it) then doomed[#doomed + 1] = it
    elseif depth < 2 then
      local inner = nil
      pcall(function() if it.getInventory then inner = it:getInventory() end end)
      if inner then bags[#bags + 1] = inner end
    end
  end
  for _, it in ipairs(doomed) do
    local ok = pcall(function() c:Remove(it) end)
    if ok then
      n = n + 1
      if isServer() and rawget(_G, "sendRemoveItemFromContainer") then pcall(sendRemoveItemFromContainer, c, it) end
    end
  end
  for _, inner in ipairs(bags) do n = n + purgeContainer(inner, depth + 1) end
  return n
end

-- Debug: borra los ítems colocados por el mod de los contenedores y del suelo de las casillas cargadas del área de escaneo.
function W.purge(zone)
  local a = W.anchor(zone)
  if not a then return 0 end
  local zc = zoneCfg(zone)
  local r = zc.scanRadius or 40
  local bx0, bx1, by0, by1 = scanBox(zone)
  local cell = getCell()
  local removed = 0
  for z = zc.zMin or -3, zc.zMax or 3 do
    for dx = bx0, bx1 do
      for dy = by0, by1 do
        local sq = cell:getGridSquare(a.x + dx, a.y + dy, z)
        if sq then
          local objs = sq:getObjects()
          for i = 0, objs:size() - 1 do
            local c = nil
            pcall(function() c = objs:get(i):getContainer() end)
            if c then removed = removed + purgeContainer(c, 0) end
          end
          local doomed = {}
          pcall(function()
            local wo = sq:getWorldObjects()
            for i = 0, wo:size() - 1 do
              local o = wo:get(i)
              local it = o and o:getItem()
              if it then
                local isLeoBag = false
                pcall(function() isLeoBag = it:getModData().SandevistanLeoBag == true end)
                if isModItem(it) or isLeoBag then doomed[#doomed + 1] = o
                else
                  -- bolsos en el suelo (también los que dejó una versión anterior sin marca): se vacía lo del mod que llevan
                  local inner = nil
                  pcall(function() if it.getInventory then inner = it:getInventory() end end)
                  if inner then removed = removed + purgeContainer(inner, 1) end
                end
              end
            end
          end)
          for _, o in ipairs(doomed) do
            local ok = pcall(function()
              if isServer() then sq:transmitRemoveItemFromSquare(o) end
              o:removeFromWorld(); o:removeFromSquare()
            end)
            if ok then removed = removed + 1 end
          end
        end
      end
    end
  end
  local w = W.data()
  if w.placedLog then w.placedLog[zone] = nil end
  S.log("purga de " .. zone .. " (solo lo colocado por el mod): " .. removed .. " ítems borrados")
  return removed
end

function W.replace(zone)
  local w = W.data()
  W.purge(zone)
  w.placements[zone .. ".set"] = nil
  W.resetScan(zone)
  W.processZone(zone, true)
  S.log("set de " .. zone .. " vuelto a colocar (debug)")
end

-- Debug: n-ésima colocación registrada de una zona (para teletransportarse a verla).
function W.placedAt(zone, n)
  local l = W.data().placedLog and W.data().placedLog[zone]
  if not l or #l == 0 then return nil, 0 end
  local i = ((n - 1) % #l) + 1
  return l[i], #l, i
end

-- Placa 3D de la espalda puesta en el ex-sujeto (para reconocerlo a simple vista). Una vez por objeto zombi; no rompe nada si falla.
local function applyExSubjectVisual(z, subjectId)
  local V = CFG.ExSubjects.Visual3D
  if not V or not V.Enabled then return end
  local sub = W.data().subjects[subjectId]
  local variant = sub and sub.variant or "lab"
  local fullType = "Sandevistan.SandevistanSpine" .. (variant == "military" and "Military" or "Lab") .. (V.Lit and "On" or "")
  local md = nil
  pcall(function() md = z:getModData() end)
  if md and md.SandevistanVisual == fullType then return end
  local ok, res = pcall(function()
    local iv = z:addBodyVisualFromItemType(fullType)
    if z.resetModelNextFrame then z:resetModelNextFrame() end
    return iv
  end)
  if md then md.SandevistanVisual = (ok and res ~= nil) and fullType or false end
  S.log("ex-sujeto " .. tostring(subjectId) .. ": placa 3D " .. fullType .. " -> " .. (ok and (res ~= nil and "aplicada" or "el motor no devolvió el visual") or ("ERROR " .. tostring(res))))
end

local function applyExSubjectTraits(z, subjectId)
  sessionTagged[z] = subjectId
  applyExSubjectVisual(z, subjectId)
  S.try("zModData", function() z:getModData().SandevistanSubject = subjectId end)
  -- (103) "Fast shambler": en 42.21 la velocidad de un zombi sale de la animacion de su marcha (variable zombieWalkType); speedMod ya no mueve nada (solo
  -- escalaba los cuadros de la animacion 2D vieja). La marcha "2" es la mas rapida que no es de corredor (animacion x1,04 contra x0,80 de la comun). Un
  -- corredor del mundo (sandbox de velocidad = corredores) se deja como esta: no se lo frena.
  if S.chance(CFG.ExSubjects.FastShamblerChance) then
    S.try("zFastShambler", function()
      if z:getSpeedType() ~= 1 then
        z:setWalkType(CFG.ExSubjects.FastShamblerWalkType)
        z:setSpeedTypeFromWalkType()
      end
    end)
  end
end

-- (106) Una casilla libre y cargada cerca de (x, y, z), en la misma planta; nil si no hay (sin caer al ancla como nearbySquare).
local function freeSquareNear(x, y, z, minR, maxR, tries)
  local cell = getCell()
  if not cell then return nil end
  for _ = 1, tries or 15 do
    local r = S.randRange(minR, maxR)
    local ang = ZombRandFloat(0, 6.2831)
    local sq = cell:getGridSquare(math.floor(x + math.cos(ang) * r), math.floor(y + math.sin(ang) * r), z)
    if sq and sq:isSolidFloor() and sq:isFree(false) then return sq end
  end
  return nil
end

-- (106) Los ex-sujetos aparecen al lado de lo que coloco el set (notas, implante, compuesto): antes salian en una casilla al azar de TODO el
-- edificio (LSU: 10.000 casillas en 7 plantas; la base baja 17 pisos) y no se los encontraba. placedLog guarda donde se coloco cada item.
function W.squareNearSet(zone)
  local log = W.data().placedLog and W.data().placedLog[zone]
  if not log or #log == 0 then return nil end
  for _ = 1, 12 do
    local e = log[ZombRand(#log) + 1]
    local sq = freeSquareNear(e.x, e.y, e.z, 1, 4, 12)
    if sq then return sq end
  end
  return nil
end

function W.spawnExSubject(zone, variant, farFromPlayers)
  local a = W.anchor(zone)
  if not a then return nil end
  local sq = W.squareNearSet(zone)
  local res = scanCache[zone]
  if not sq and res and #res.all > 0 then
    local cell = getCell()
    for _ = 1, 30 do
      local c = res.all[ZombRand(#res.all) + 1]
      -- (103) las casillas del escaneo viejo pueden haberse descargado (el jugador se fue y volvio): se toma la casilla de ahora, y si no esta cargada se prueba otra
      local cur = cell and cell:getGridSquare(c:getX(), c:getY(), c:getZ())
      if cur and cur:isFree(false) then sq = cur; break end
    end
  end
  sq = sq or nearbySquare(a.x, a.y, a.z, CFG.ExSubjects.SpawnOffsetMin, CFG.ExSubjects.SpawnOffsetMax, 30)
  if not sq then return nil end
  if farFromPlayers then
    for _, p in ipairs(allPlayers()) do
      if p:DistTo(sq:getX(), sq:getY()) < CFG.ExSubjects.SpawnMinDistFromPlayers then return nil end
    end
  end
  return W.spawnAt(sq, zone, variant)
end

function W.spawnAt(sq, zone, variant)
  local outfit = CFG.ExSubjects.Outfits[variant]
  local list = nil
  S.try("addZombiesInOutfit", function()
    list = addZombiesInOutfit(sq:getX(), sq:getY(), sq:getZ(), 1, outfit, 50)
  end)
  if not list or list:size() == 0 then return nil end
  local z = list:get(0)
  local w = W.data()
  local id = "ex" .. w.nextId
  w.nextId = w.nextId + 1
  local oid = nil
  S.try("zOutfitId", function() oid = tostring(z:getPersistentOutfitID()) end)
  w.subjects[id] = { variant = variant, zone = zone, state = "alive", outfitId = oid, degradation = 1.0 }
  pcall(function() w.subjects[id].lx, w.subjects[id].ly, w.subjects[id].lz = z:getX(), z:getY(), z:getZ() end)          -- (94) posicion de nacimiento
  if oid then w.aliveByOutfit[oid] = id end
  applyExSubjectTraits(z, id)
  S.log("ex-sujeto " .. id .. " (" .. variant .. ") en " .. zone)
  return id
end

local function variantForZone(zone) return zone == "base" and "military" or "lab" end

-- (107) cuantos ex-sujetos fijos tiene la zona. Cada campus tiene SIEMPRE uno; la tirada de CivilExSubjectChance (una por campus al crear el mundo,
-- guardada en civilExSubject) decide si hay un SEGUNDO.
function W.fixedWanted(zone)
  if zone == "base" then return CFG.ExSubjects.MilitaryCount end
  return 1 + (W.data().civilExSubject[zone] and 1 or 0)
end

function W.spawnFixed(zone)
  local st = W.zoneState(zone)
  local want = W.fixedWanted(zone)
  if st.fixedSpawned then return end
  -- si un spawn falla (outfit inexistente, casilla no cargada...) se reintenta cada minuto, hasta 5 veces
  for _ = 1, want - (st.fixedMade or 0) do
    if W.spawnExSubject(zone, variantForZone(zone), false) then st.fixedMade = (st.fixedMade or 0) + 1 end
  end
  st.fixedTries = (st.fixedTries or 0) + 1
  if (st.fixedMade or 0) >= want then
    st.fixedSpawned = true
  elseif st.fixedTries >= 5 then
    st.fixedSpawned = true
    S.logAlways("WARN ex-sujetos de " .. zone .. ": solo " .. (st.fixedMade or 0) .. " de " .. want .. " tras 5 intentos (revisar Config.ExSubjects.Outfits)")
  end
end

function W.respawnCheck(zone)
  if not CFG.ExSubjects.Respawn then return end
  local st = W.zoneState(zone)
  if not st.fixedSpawned then return end
  local now = S.worldHours()
  if CFG.ExSubjects.RespawnMax > 0 and st.extraCount >= CFG.ExSubjects.RespawnMax then return end
  if now - st.lastCheckHour < CFG.ExSubjects.RespawnCheckHours then return end
  st.lastCheckHour = now
  if S.chance(CFG.ExSubjects.RespawnChance) then
    if W.spawnExSubject(zone, variantForZone(zone), true) then st.extraCount = st.extraCount + 1 end
  end
end

-- (169) T16: ex-sujetos errantes. Alguien que se escapó de un campus y quedó vagando lejos: aparece muy de vez en cuando, cerca de un
-- jugador que esté lejos de todos los anclajes, y como mucho Max por mundo. Se registra con zone = "wander" (no tiene set ni ancla).
function W.playerDistToZones(player)
  local best = 1e9
  for _, z in ipairs({ "base", "lsu", "ekron" }) do
    local a = W.anchor(z)
    if a and player then best = math.min(best, player:DistTo(a.x, a.y)) end
  end
  return best
end

function W.farPlayer(minDist)
  for _, p in ipairs(allPlayers()) do
    if p and not p:isDead() and W.playerDistToZones(p) >= (minDist or 250) then return p end
  end
  return nil
end

-- Decisión pura (para las pruebas): ¿toca generar uno ahora? roll = tirada 0..1.
function W.wanderWanted(w, now, far, roll)
  local c = CFG.ExSubjects.Wander
  if not (c and c.Enabled and far) then return false end
  if (w.wanderCount or 0) >= (c.Max or 1) then return false end
  if now - (w.lastWanderHour or -1e9) < (c.CheckHours or 12) then return false end
  return (roll or 0) < (c.Chance or 0)
end

function W.wanderCheck()
  local c = CFG.ExSubjects.Wander
  if not (c and c.Enabled) then return end
  local w = W.data()
  local now = S.worldHours()
  local p = W.farPlayer(c.MinDistFromZone)
  if not p then return end
  if not W.wanderWanted(w, now, true, ZombRandFloat(0, 1)) then return end
  local sq = freeSquareNear(p:getX(), p:getY(), math.floor(p:getZ()), c.RadiusMin or 14, c.RadiusMax or 40, 25)
  if not sq then return end
  w.lastWanderHour = now
  local variant = S.chance(c.MilitaryChance or 0.2) and "military" or "lab"
  if W.spawnAt(sq, "wander", variant) then
    w.wanderCount = (w.wanderCount or 0) + 1
    S.log("ex-sujeto errante cerca de un jugador lejos de los campus")
  end
end

-- (169) Debug: uno ahora, al lado del jugador (sin tirada ni tope).
function W.debugWander(player)
  if not W.authority or not player then return nil end
  local c = CFG.ExSubjects.Wander or {}
  local sq = freeSquareNear(player:getX(), player:getY(), math.floor(player:getZ()), 6, 12, 30)
  if not sq then return nil end
  local variant = S.chance(c.MilitaryChance or 0.2) and "military" or "lab"
  local id = W.spawnAt(sq, "wander", variant)
  if id then
    local w = W.data()
    w.wanderCount = (w.wanderCount or 0) + 1
  end
  return id
end

local replaceCheck = {}   -- [zone] = hora de chequeo (una vez por sesión)
local replacedThisSession = {}

-- (103) ¿Esta cargado el chunk donde se vio por ultima vez al ex-sujeto? Si no lo esta, el zombi simplemente no esta cargado (se alejo mas que la ventana de chunks
-- del jugador): no se lo da por perdido ni se lo reemplaza, porque seguiria ahi y cada sesion cerca de la base sumaria otros ex-sujetos. Sin posicion conocida, o sin
-- forma de saberlo, se asume cargado (el comportamiento de antes).
function W.chunkLoadedAt(x, y, z)
  if not x or not y then return true end
  local ok, ch = pcall(function() return getCell():getChunkForGridSquare(math.floor(x), math.floor(y), math.floor(z or 0)) end)
  if not ok then return true end
  return ch ~= nil
end

function W.replaceUnidentified(zone)
  local w = W.data()
  local taggedIds = {}
  for _, id in pairs(sessionTagged) do taggedIds[id] = true end
  for id, sub in pairs(w.subjects) do
    if sub.zone == zone and sub.state == "alive" and not taggedIds[id] and W.chunkLoadedAt(sub.lx, sub.ly, sub.lz) then
      sub.state = "lost"
      if sub.outfitId then w.aliveByOutfit[sub.outfitId] = nil end
      local newId = W.spawnExSubject(zone, sub.variant, true)
      if newId then
        S.log("ex-sujeto " .. id .. " no reconocido tras cargar; reemplazado por " .. newId)
      else
        sub.state = "alive"   -- no hubo lugar lejos de los jugadores: se reintenta en la próxima carga
        if sub.outfitId then w.aliveByOutfit[sub.outfitId] = id end
      end
    end
  end
end

local sessionNear = {}

-- (103) El set se coloca al primer minuto en que un jugador esta cerca del ancla, y solo se ve lo que esta CARGADO: la ventana de chunks alrededor del
-- jugador depende de la pantalla (IsoChunkMap.CalcChunkWidth: 19 chunks de 8 casillas en 1920x1080, 13 en 1366x768, 9 en pantallas chicas). Con el complejo
-- militar (13346 casillas de salas, cargadas solo las que caen en la ventana) disparar a 30 casillas del ancla da 85 % del area de salas con 19 chunks,
-- pero 62 % con 13 y 28 % con 9 (segun desde donde se llegue): con una ventana chica hay que estar mas cerca. Sin dato (servidor, sin chunkmap) vale el valor de Config.
W.TRIGGER_COVER = 40          -- radio alrededor del ancla que tiene que quedar dentro de la ventana
W.TRIGGER_MIN = 8
function W.loadedHalfWidth()
  if isServer() then return nil end
  local half = nil
  pcall(function() half = getCell():getChunkMap(0):getWidthInTiles() / 2 end)
  if type(half) ~= "number" or half <= 0 then return nil end
  return half
end

function W.triggerDistance()
  local base = CFG.PlacementTriggerDistance
  local half = W.loadedHalfWidth()
  if not half then return base end
  return math.max(W.TRIGGER_MIN, math.min(base, half - W.TRIGGER_COVER))
end

local function playerNear(a, dist)
  for _, p in ipairs(allPlayers()) do
    if not p:isDead() and math.floor(p:getZ()) >= -32 and p:DistTo(a.x, a.y) <= dist then return true end
  end
  return false
end

-- Se procesa cuando un jugador está cerca del ancla, así el edificio está cargado.
function W.processZone(zone, force)
  if not W.isZoneActive(zone) then return end
  local a = W.anchor(zone)
  if not a then return end
  if not force and not playerNear(a, W.triggerDistance()) then return end
  if not sessionNear[zone] then
    sessionNear[zone] = true
    if CFG.ExSubjects.ReplaceUnidentifiedAfterLoad and not replacedThisSession[zone] then
      replaceCheck[zone] = S.worldHours() + 2 / 60
    end
  end
  if zone == "base" then W.placeBase() else W.placeCampus(zone) end
  if W.data().placements[zone .. ".set"] then
    W.spawnFixed(zone)
    W.respawnCheck(zone)
  end
end

function W.processAllZones()
  for _, zone in ipairs({ "base", "lsu", "ekron" }) do W.processZone(zone, false) end
  W.wanderCheck()
end

local function onZombieCreate(z)
  local w = W.data()
  local okO, rawOid = pcall(z.getPersistentOutfitID, z)            -- v0.1.30: sin funciones anónimas (corre por cada zombi)
  local oid = okO and rawOid ~= nil and tostring(rawOid) or nil
  local id = oid and w.aliveByOutfit[oid]
  if not id then
    local mdId = nil
    local okM, zmd = pcall(z.getModData, z)
    if okM and zmd then mdId = zmd.SandevistanSubject end
    if mdId and w.subjects[mdId] and w.subjects[mdId].state == "alive" then
      id = mdId
      if oid then w.aliveByOutfit[oid] = id; w.subjects[id].outfitId = oid end
    end
  end
  if id and w.subjects[id] and w.subjects[id].state == "alive" then
    if sessionTagged[z] ~= id then applyExSubjectTraits(z, id) end
  elseif sessionTagged[z] then
    sessionTagged[z] = nil   -- objeto zombi reciclado: ya no es el ex-sujeto
  end
end

-- Reemplazo de ex-sujetos sin identificar tras cargar (cada minuto in-game: es solo mirar una tabla chica).
function W.checkReplacements()
  local now = S.worldHours()
  for zone, h in pairs(replaceCheck) do
    if now >= h then
      replaceCheck[zone] = nil
      replacedThisSession[zone] = true
      W.replaceUnidentified(zone)
    end
  end
end

-- Respaldo: revisa los zombis cargados por si OnZombieCreate no disparó al cargar la partida. v0.1.30: cada 10 minutos in-game
-- (antes cada minuto: recorría cientos de zombis 2-3 veces por segundo real).
function W.scanLoadedZombies()
  W.checkReplacements()
  local w = W.data()
  if S.isEmpty(w.aliveByOutfit) then return end
  local cell = getCell()
  local zl = cell and cell:getZombieList()
  if not zl then return end
  local n = zl:size()
  for i = 0, n - 1 do
    local z = zl:get(i)
    if z then onZombieCreate(z) end
  end
  rememberPositions()
  S.perfCount("mundo.zombisRevisados", n)
end

---------------------------------------------------------------------------
-- Muerte → cadáver con implante
---------------------------------------------------------------------------
local pendingBodies = {}   -- { x, y, z, info, ms, outfit (ex-sujeto) | player, onlineID (jugador) }
W.pendingBodies = function() return pendingBodies end

local function subjectIdOf(z)
  if sessionTagged[z] then return sessionTagged[z] end
  local id = nil
  pcall(function() id = z:getModData().SandevistanSubject end)
  if id then return id end
  local w = W.data()
  local oid = nil
  pcall(function() oid = tostring(z:getPersistentOutfitID()) end)
  return oid and w.aliveByOutfit[oid] or nil
end

-- (99) Cadaveres que YA existen alrededor de (x, y, z): el de un ex-sujeto que acaba de morir todavia no existe (aparece unos segundos
-- despues), asi que ninguno de estos puede ser el suyo. Con el REPORTE de la (98) se vio que el implante se iba al instante, en el mismo cuadro
-- de la muerte, a un cadaver viejo de al lado que no trae outfit.
W.SNAPSHOT_RADIUS = 3
function W.bodiesAround(x, y, z)
  local seen = {}
  local cell = getCell()
  if not cell then return seen end
  local cx, cy, cz = math.floor(x), math.floor(y), math.floor(z)
  for dx = -W.SNAPSHOT_RADIUS, W.SNAPSHOT_RADIUS do
    for dy = -W.SNAPSHOT_RADIUS, W.SNAPSHOT_RADIUS do
      local sq = cell:getGridSquare(cx + dx, cy + dy, cz)
      local bodies = sq and sq:getDeadBodys()
      for i = 0, (bodies and bodies:size() or 0) - 1 do seen[bodies:get(i)] = true end
    end
  end
  return seen
end

local function onZombieDead(z)
  local id = subjectIdOf(z)
  if not id then return end
  local w = W.data()
  local sub = w.subjects[id]
  if not sub or sub.state ~= "alive" then return end
  if sub.outfitId then w.aliveByOutfit[sub.outfitId] = nil end
  sessionTagged[z] = nil
  sub.state = "dying"
  S.log(string.format("ex-sujeto %s (%s) murio en %.1f,%.1f,%d: se espera su cadaver", tostring(id), tostring(sub.variant), z:getX(), z:getY(), math.floor(z:getZ())))          -- (98) para seguir la extraccion en el log
  table.insert(pendingBodies, { x = z:getX(), y = z:getY(), z = z:getZ(), ms = S.realMs(), outfit = CFG.ExSubjects.Outfits[sub.variant],
    seen = W.bodiesAround(z:getX(), z:getY(), z:getZ()),
    info = { variant = sub.variant, subjectId = id, degradation = sub.degradation or 1.0 } })
end

-- Muerte de un jugador con implante: su cadáver lo lleva (y se puede extraer). En un jugador llega por OnPlayerDeath; en multijugador
-- el estado del implante vive en el cliente, que se lo manda al servidor (Net.lua, "implantDeath"): OnPlayerDeath es un evento del
-- cliente y en un servidor dedicado no dispara.
function W.registerPlayerDeath(info, x, y, z, onlineID)
  local w = W.data()
  local id = "pl" .. w.nextId
  w.nextId = w.nextId + 1
  w.subjects[id] = { variant = info.variant, zone = "player", state = "dying", degradation = info.degradation or 1.0 }
  table.insert(pendingBodies, { x = x, y = y, z = z, ms = S.realMs(), player = true, onlineID = onlineID,
    info = { variant = info.variant, subjectId = id, degradation = info.degradation or 1.0,
             degradationFloor = info.degradationFloor } })
  return id
end

-- (129) Muerte de un NPC de otro mod que llevaba el implante (Project A-Life, server/Sandevistan/ALife.lua). Por dentro es un zombi: como con un
-- ex-sujeto, el cadaver aparece despues y no puede ser ninguno de los que ya estan alrededor (seen). info.npcKey = la marca que lleva su ModData
-- (y por lo tanto su cadaver): en la ventana estricta solo vale ese cuerpo.
function W.registerNpcDeath(info, x, y, z, zone)
  local w = W.data()
  local id = "npc" .. w.nextId
  w.nextId = w.nextId + 1
  w.subjects[id] = { variant = info.variant, zone = zone or "npc", state = "dying", degradation = info.degradation or 1.0 }
  table.insert(pendingBodies, { x = x, y = y, z = z, ms = S.realMs(), seen = W.bodiesAround(x, y, z), npcKey = info.npcKey,
    info = { variant = info.variant, subjectId = id, degradation = info.degradation or 1.0 } })
  return id
end

local function onPlayerDeath(player)
  if isClient() or isServer() then return end        -- multijugador: lo avisa el propio cliente (Net.lua)
  local d = player:getModData().Sandevistan
  if type(d) ~= "table" or (d.variant ~= "lab" and d.variant ~= "military") then return end
  W.registerPlayerDeath({ variant = d.variant, degradation = d.degradation, degradationFloor = d.degradationFloor },
    player:getX(), player:getY(), player:getZ())
end

local function claimBody(body, p)
  body:getModData().Sandevistan = p.info
  -- multijugador: el ModData del cadáver no viaja solo; se transmite para que los clientes vean el implante y puedan extraerlo
  if isServer() then pcall(function() body:transmitModData() end) end
  S.log(string.format("cadaver de %s reclamado en %.1f,%.1f: lleva el implante (%s)", tostring(p.info.subjectId), body:getX(), body:getY(), tostring(p.info.variant)))
  local sub = W.data().subjects[p.info.subjectId]
  if sub then
    sub.state = "corpse"; sub.x = math.floor(body:getX()); sub.y = math.floor(body:getY()); sub.z = math.floor(body:getZ())
    sub.corpseHour = S.worldHours()
  end
end

-- ¿Puede ser este cuerpo el de la muerte pendiente p? Nunca uno que ya lleva un implante ni uno que ya estaba cuando murió. strict: además coincide el outfit del
-- ex-sujeto o el id del jugador (los primeros segundos; después alcanza con que sea de zombi o de jugador y esté ahí).
local function bodyFits(body, p, strict)
  local okM, md = pcall(body.getModData, body)
  if not okM or not md or type(md.Sandevistan) == "table" then return false end
  if p.player then
    local okP, isP = pcall(body.isPlayer, body)
    if okP and isP == false then return false end
    if strict and p.onlineID ~= nil then
      local okI, oid = pcall(body.getCharacterOnlineID, body)
      if okI and oid ~= nil and oid ~= p.onlineID then return false end
    end
    return true
  end
  if p.seen and p.seen[body] then return false end          -- (99) ya estaba ahi cuando murio el ex-sujeto: no es su cuerpo
  local okZ, isZ = pcall(body.isZombie, body)
  if okZ and isZ == false then return false end
  if strict and p.outfit then
    -- (99) en la ventana estricta el outfit tiene que COINCIDIR: los cuerpos de zombis comunes devuelven nil (el del ex-sujeto devuelve su outfit)
    local okO, outfit = pcall(body.getOutfitName, body)
    if not okO or outfit ~= p.outfit then return false end
  end
  -- (129) NPC de A-Life: el cadaver copia el ModData del zombi (IsoDeadBody -> LuaManager.copyTable), asi que trae la marca con su uid
  if strict and p.npcKey and md.SandevistanALifeKey ~= p.npcKey then return false end
  return true
end

-- (99) OnDeadBodySpawn dispara con CADA cuerpo que aparece, y el de un ex-sujeto aparece unos segundos despues de su muerte: antes se
-- quedaba con el primer cuerpo de zombi a menos de 2 casillas, sin mirar el outfit, y con una horda cerca el implante iba a otro cadaver.
-- Ahora, en los primeros segundos, pide el outfit del ex-sujeto (o el id del jugador) y que el cuerpo este practicamente donde murio;
-- si no, no reclama nada y lo resuelve la busqueda por casillas (W.claimPendingBodies), que elige el mas parecido y el mas cercano.
W.EVENT_MAX_DIST2 = 1.0           -- el cuerpo aparece donde murio el zombi (distancia al cuadrado, en casillas)
local function onDeadBodySpawn(body)
  if #pendingBodies == 0 then return end
  local bx, by, bz = body:getX(), body:getY(), body:getZ()
  local now = S.realMs()
  local bestI, bestD = nil, nil
  for i = #pendingBodies, 1, -1 do
    local p = pendingBodies[i]
    local ex, ey = p.x - bx, p.y - by
    local dd = ex * ex + ey * ey
    if dd <= W.EVENT_MAX_DIST2 and math.floor(p.z) == math.floor(bz) and bodyFits(body, p, now - p.ms < W.CLAIM_STRICT_MS)
       and (not bestD or dd < bestD) then
      bestI, bestD = i, dd
    end
  end
  if bestI then
    claimBody(body, pendingBodies[bestI])
    table.remove(pendingBodies, bestI)
  end
end

-- v0.1.30 (13): el cadáver también se busca en las casillas de alrededor (cada 0.5 s mientras haya muertes pendientes). OnDeadBodySpawn
-- es un evento del cliente: en un servidor dedicado no dispara y los ex-sujetos morían sin dejar el implante en el cuerpo.
W.CLAIM_EVERY_MS, W.CLAIM_STRICT_MS, W.CLAIM_GIVEUP_MS, W.CLAIM_RADIUS = 500, 10000, 60000, 2
local nextClaimMs = 0
function W.claimPendingBodies()
  if #pendingBodies == 0 then return end
  local now = S.realMs()
  if now < nextClaimMs then return end
  nextClaimMs = now + W.CLAIM_EVERY_MS
  local cell = getCell()
  if not cell then return end
  local w = W.data()
  for i = #pendingBodies, 1, -1 do
    local p = pendingBodies[i]
    local strict = now - p.ms < W.CLAIM_STRICT_MS
    local best, bestD, bestRank = nil, nil, nil
    local cx, cy, cz = math.floor(p.x), math.floor(p.y), math.floor(p.z)
    for dx = -W.CLAIM_RADIUS, W.CLAIM_RADIUS do
      for dy = -W.CLAIM_RADIUS, W.CLAIM_RADIUS do
        local sq = cell:getGridSquare(cx + dx, cy + dy, cz)
        local bodies = sq and sq:getDeadBodys()
        for j = 0, (bodies and bodies:size() or 0) - 1 do
          local b = bodies:get(j)
          -- (99) pasada la ventana estricta se acepta cualquier cuerpo que encaje, pero gana el que si coincide en outfit/id y despues el mas cercano
          local exact = bodyFits(b, p, true)
          if exact or (not strict and bodyFits(b, p, false)) then
            local ex, ey = b:getX() - p.x, b:getY() - p.y
            local dd = ex * ex + ey * ey
            local rank = exact and 0 or 1
            if not best or rank < bestRank or (rank == bestRank and dd < bestD) then best, bestD, bestRank = b, dd, rank end
          end
        end
      end
    end
    if best then
      claimBody(best, p)
      table.remove(pendingBodies, i)
    elseif now - p.ms > W.CLAIM_GIVEUP_MS then
      local sub = w.subjects[p.info.subjectId]
      if sub and sub.state == "dying" then sub.state = "lost" end
      table.remove(pendingBodies, i)
      S.log("muerte con implante sin cadaver encontrado: " .. tostring(p.info.subjectId))
    end
  end
end

-- (98) Debug / REPORTE: que hay en los cadaveres de alrededor (radio r, mismo piso) y que muertes esperan su cadaver. Una linea por cadaver: si lleva el implante y de quien.
function W.corpseDiagnosis(x, y, z, r)
  local out = {}
  local cell = getCell()
  r = r or 6
  out[#out + 1] = string.format("muertes que esperan cadaver = %d", #pendingBodies)
  for _, p in ipairs(pendingBodies) do
    out[#out + 1] = string.format("  esperando: %s en %.1f,%.1f,%d hace %.0f s (%s)", tostring(p.info.subjectId), p.x, p.y, math.floor(p.z), (S.realMs() - p.ms) / 1000, p.player and "jugador" or ("outfit " .. tostring(p.outfit)))
  end
  local n = 0
  for dx = -r, r do
    for dy = -r, r do
      local sq = cell and cell:getGridSquare(math.floor(x) + dx, math.floor(y) + dy, math.floor(z))
      local bodies = sq and sq:getDeadBodys()
      for i = 0, (bodies and bodies:size() or 0) - 1 do
        local b = bodies:get(i)
        n = n + 1
        local md = nil
        pcall(function() md = b:getModData().Sandevistan end)
        local outfit = nil
        pcall(function() outfit = b:getOutfitName() end)
        local isZ = nil
        pcall(function() isZ = b:isZombie() end)
        out[#out + 1] = string.format("  cadaver en %d,%d: %s | zombi=%s | outfit=%s | %s", sq:getX(), sq:getY(), "IsoDeadBody", tostring(isZ), tostring(outfit),
          type(md) == "table" and string.format("IMPLANTE %s de %s%s", tostring(md.variant), tostring(md.subjectId), md.extracted and " (YA EXTRAIDO)" or "") or "sin implante")
      end
    end
  end
  out[#out + 1] = string.format("cadaveres a %d casillas = %d", r, n)
  return out
end

function W.markSubject(id, state)
  if not id then return end
  local sub = W.data().subjects[id]
  if sub then sub.state = state end
end

---------------------------------------------------------------------------
-- Cadáver eliminado → implante suelto 1.5x (chequeo horario sobre cuadrados cargados)
---------------------------------------------------------------------------
local function corpseStillThere(sub, id)
  local cell = getCell()
  local r = CFG.ExSubjects.CorpseSearchRadius
  for dx = -r, r do
    for dy = -r, r do
      local sq = cell:getGridSquare(sub.x + dx, sub.y + dy, sub.z)
      if sq then
        local bodies = sq:getDeadBodys()
        if bodies then
          for i = 0, bodies:size() - 1 do
            local md = bodies:get(i):getModData().Sandevistan
            if type(md) == "table" and md.subjectId == id then return true end
          end
        end
      end
    end
  end
  return false
end

function W.checkCorpses()
  local w = W.data()
  local now = S.worldHours()
  local cell = getCell()
  if not cell then return end
  for id, sub in pairs(w.subjects) do
    if sub.state == "corpse" and sub.x and (now - (sub.corpseHour or now)) >= 1 then
      local sq = cell:getGridSquare(sub.x, sub.y, sub.z)
      if sq and not corpseStillThere(sub, id) then
        local t = sub.variant == "military" and "Sandevistan.SandevistanMilitary" or "Sandevistan.SandevistanLab"
        dropItem(sq, t, { heatDegradationMultiplier = CFG.Extraction.RemovedCorpseDegradation })
        sub.state = "dropped"
        S.log("cadáver de " .. id .. " no encontrado: implante suelto en el suelo")
      end
    end
  end
  -- limpieza de muertes que nunca generaron cadáver
  for i = #pendingBodies, 1, -1 do
    if S.realMs() - pendingBodies[i].ms > 60000 then
      local sub = w.subjects[pendingBodies[i].info.subjectId]
      if sub and sub.state == "dying" then sub.state = "lost" end
      table.remove(pendingBodies, i)
    end
  end
end

if W.authority then
  Events.OnInitGlobalModData.Add(S.safe("World.OnInitGlobalModData", function() W.init(); W.rebuildAnchorIndex() end))
  Events.OnZombieCreate.Add(S.safe("World.OnZombieCreate", onZombieCreate))
  Events.OnZombieDead.Add(S.safe("World.OnZombieDead", onZombieDead))
  Events.OnPlayerDeath.Add(S.safe("World.OnPlayerDeath", onPlayerDeath))
  Events.OnDeadBodySpawn.Add(S.safe("World.OnDeadBodySpawn", onDeadBodySpawn))
  Events.OnTick.Add(S.safe("World.ClaimBodies", W.claimPendingBodies))
  Events.EveryHours.Add(S.safe("World.EveryHours", W.checkCorpses))
  Events.EveryOneMinute.Add(S.safe("World.Replacements", W.checkReplacements))
  Events.EveryTenMinutes.Add(S.safe("World.ScanZombies", W.scanLoadedZombies))
  Events.EveryOneMinute.Add(S.safe("World.Zones", W.processAllZones))
end
return W
