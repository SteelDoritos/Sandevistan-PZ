-- (167) T13: mapas anotados (D8). Con el sistema de escondites vanilla: el ítem lo reparte el juego (AnnotatedMapChance) y, al leerlo,
-- el mapa muestra la zona marcada con círculo, cruz y texto a mano; el botón vanilla la pasa al mapa del mundo.
-- Se arma la tabla `StashDescriptions` (la lee StashSystem) y, en el cliente, la vista del mapa (`LootMaps.Init[<stash>]`).
require "Sandevistan/Config"

SandevistanAnnotatedMaps = {}
local AM = SandevistanAnnotatedMaps
local CFG = SandevistanConfig

AM.order = { "lsu", "ekron", "base" }

-- Crea los tres escondites una sola vez (lo puede llamar la carga de StashDescriptions o Core; el guard evita duplicados).
function AM.build()
  if AM.built then return end
  AM.built = true
  local C = CFG.AnnotatedMaps
  if not (C and C.Enabled) then return end
  local ok, err = pcall(require, "StashDescriptions/StashUtil")
  local StashUtil = rawget(_G, "StashUtil")                 -- (168c) el archivo vanilla define el global y no devuelve la tabla
  if not ok or type(StashUtil) ~= "table" or not StashUtil.newStash then
    print("[Sandevistan] WARN no se pudo cargar StashUtil: sin mapas anotados (" .. tostring(err) .. ")")
    return
  end
  local n = 0
  for _, key in ipairs(AM.order) do
    local c = C[key]
    if c and c.stash and c.item and c.building then
      local m = StashUtil.newStash(c.stash, "Map", c.item, "Stash_AnnotedMap")
      m.buildingX, m.buildingY = c.building.x, c.building.y
      local r, g, b = c.color[1], c.color[2], c.color[3]
      m:addStamp("Circle", nil, c.building.x, c.building.y, r, g, b)
      m:addStamp("Cross", nil, c.building.x + 24, c.building.y - 20, r, g, b)
      for _, t in ipairs(c.texts or {}) do m:addStamp(nil, t[1], t[2], t[3], r, g, b) end
      AM[key] = m
      n = n + 1
    end
  end
  local S = rawget(_G, "Sandevistan")
  if S and S.log then S.log("mapas anotados: " .. n .. " escondites registrados")
  elseif CFG.Debug or (isDebugEnabled and isDebugEnabled()) then print("[Sandevistan] mapas anotados: " .. n .. " escondites registrados") end
end

-- (168b) StashSystem cachea la lista de escondites: después de agregar los nuestros hay que pedirle que la relea (vanilla lo hace en el
-- botón REINIT de su Debug). Se llama al cargar y otra vez al empezar la partida, y se reintenta si un escondite no aparece.
function AM.reinit()
  local SS = rawget(_G, "StashSystem")
  if SS and SS.reinit then pcall(SS.reinit) end
end

-- ¿El sistema de escondites ya está inicializado? Ojo: getStash con allStashes en nil tira una excepción de Java (el depurador del
-- jugador frena aunque esté dentro de un pcall). init() es idempotente: si ya está inicializado no hace nada; si no, lee la tabla
-- StashDescriptions (ya con nuestros escondites). Se llama con pcall y, si anduvo, el sistema quedó listo.
function AM.ensureSystem()
  local SS = rawget(_G, "StashSystem")
  if not (SS and SS.init) then return false end
  return (pcall(SS.init))
end

-- ¿El sistema ya vio los nuestros? Si no, se le pide que relea la tabla (reinit). Ojo: reinit también vacía la lista de mapas ya leídos,
-- así que solo se llama cuando falta alguno.
function AM.ensureRegistered()
  if not AM.ensureSystem() then return false end
  local SS = rawget(_G, "StashSystem")
  if not (SS and SS.getStash and SS.reinit) then return false end
  local first = (CFG.AnnotatedMaps and CFG.AnnotatedMaps.lsu and CFG.AnnotatedMaps.lsu.stash) or "SandevistanStashLSU"
  local ok, found = pcall(SS.getStash, first)
  if ok and found then return true end
  AM.reinit()
  return true
end

-- Registra la vista del mapa en el cliente (la usa ISMap e ISWorldMap). Se puede llamar varias veces.
function AM.installMaps()
  if AM.mapsInstalled then return true end
  local LM, MU = rawget(_G, "LootMaps"), rawget(_G, "MapUtils")
  if not (LM and LM.Init and MU) then return false end
  AM.mapsInstalled = true
  local C = CFG.AnnotatedMaps
  if not (C and C.Enabled) then return end
  for _, key in ipairs(AM.order) do
    local c = C[key]
    if c and c.stash and c.bounds then
      LM.Init[c.stash] = function(mapUI)
        local api = mapUI.javaObject:getAPIv1()
        MU.initDirectoryMapData(mapUI, "media/maps/Muldraugh, KY")
        MU.initDefaultStyleV3(mapUI)
        api:setBoundsInSquares(c.bounds[1], c.bounds[2], c.bounds[3], c.bounds[4])
        MU.overlayPaper(mapUI)
      end
    end
  end
  return true
end

-- (168) Prueba desde Debug: crea el mapa anotado de esa zona y lo da. En multijugador lo crea el servidor (comando stashMap): un ítem
-- creado en el cliente no existe para el servidor.
function AM.giveMap(player, key)
  local C = CFG.AnnotatedMaps
  local c = C and C[key]
  if not c or not c.stash then return false end
  local S = rawget(_G, "Sandevistan")
  if S and S.isMPClient and S.isMPClient() then
    sendClientCommand(player, "Sandevistan", "stashMap", { stash = c.stash })
    return true
  end
  local SS = rawget(_G, "StashSystem")
  if not (SS and SS.getStash and SS.doStashItem) then
    print("[Sandevistan] WARN mapa anotado: StashSystem no disponible")
    return false
  end
  AM.ensureRegistered()                          -- (168c) si el sistema no arrancó o no nos vio, se lo inicializa/relée antes de pedir el escondite
  local stash = SS.getStash(c.stash)
  if not stash then
    AM.reinit()                                  -- (168b) la lista pudo quedar cacheada antes de que existieran los nuestros
    stash = SS.getStash(c.stash)
  end
  if not stash then
    print("[Sandevistan] WARN mapa anotado: no existe el escondite " .. tostring(c.stash))
    return false
  end
  local ok, item = pcall(function()
    local it = instanceItem(stash:getItem())
    SS.doStashItem(stash, it)
    return it
  end)
  if not ok or not item then return false end
  player:getInventory():AddItem(item)
  return true
end

AM.build()
if not AM.installMaps() and Events and Events.OnGameBoot then
  Events.OnGameBoot.Add(function() AM.installMaps() end)      -- el cliente arma la vista cuando ya cargaron los mapas vanilla
end
local function lateInit() pcall(AM.ensureRegistered) end
if Events and Events.OnGameBoot then Events.OnGameBoot.Add(lateInit) end
if Events and Events.OnGameStart then Events.OnGameStart.Add(lateInit) end
return AM
