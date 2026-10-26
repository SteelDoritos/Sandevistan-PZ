-- Sandevistan / Traits (cliente): rasgos de creación de personaje (lua/shared/Sandevistan/TraitDefs.lua).
-- Los efectos leen d.traits (ModData del jugador); acá se refresca desde el motor y se entrega el kit inicial.
require "Sandevistan/Core"
require "Sandevistan/Net"

local CFG = SandevistanConfig
local S = Sandevistan

SandevistanTraits = {}
local T = SandevistanTraits

T.Ids = {
  special = "sandevistan:special", chrome = "sandevistan:chromerejection", labkit = "sandevistan:labkit",
  ripperdoc = "sandevistan:ripperdoc", psycho = "sandevistan:cyberpsychoprone",
  edgerunner = "sandevistan:edgerunner", excorpo = "sandevistan:excorpo", unstable = "sandevistan:neurallyunstable",
  chromed = "sandevistan:chromed",                                  -- (161) T08: arranca con el implante puesto
}

function T.has(player, id)
  local has = false
  pcall(function()
    local trait = CharacterTrait.get(ResourceLocation.of(id))
    if trait then has = player:hasTrait(trait) == true end
  end)
  return has
end

function T.serverKnows(player)
  if not isClient() then return true end
  local id = nil
  pcall(function() id = player:getOnlineID() end)
  return id ~= nil and id >= 0
end

---------------------------------------------------------------------------
-- (137) Multijugador: rasgos del mod elegidos al crear el personaje. Se reportó que en una partida alojada desaparecían al aparecer (y no llegaba
-- el kit): el servidor arma al personaje con CreatePlayerPacket -> applyTraits, que saltea sin avisar un rasgo que no encuentra, y después le manda
-- su lista al cliente. Acá el cliente lee lo que eligió (getWorld():getLuaTraits(), la lista que manda el juego) y, una vez y solo con un
-- personaje nuevo, se la pide al servidor ("traits"), que repone los que falten. La respuesta ("traitsAck") queda en la consola y en el REPORTE:
-- dice si el servidor tuvo que registrar el rasgo (no lo conocía) o solo agregarlo.
---------------------------------------------------------------------------
T.restore = { sent = false, ack = nil }

-- Ids de los rasgos del mod en la lista de la creación de personaje.
function T.chosenModTraits()
  local out, known, objs = {}, {}, {}
  for _, id in pairs(T.Ids) do
    known[id] = true
    pcall(function() local t = CharacterTrait.get(ResourceLocation.of(id)); if t then objs[#objs + 1] = { t, id } end end)
  end
  pcall(function()
    local list = getWorld():getLuaTraits()
    for i = 0, list:size() - 1 do
      local t = list:get(i)
      local id = tostring(t)                         -- CharacterTrait.toString() = su ResourceLocation ("sandevistan:labkit")
      if not known[id] then
        id = nil
        for _, o in ipairs(objs) do if o[1] == t then id = o[2] end end
      end
      if id then out[#out + 1] = id end
    end
  end)
  table.sort(out)
  return out
end

function T.isNewCharacter(player)
  local h = nil
  pcall(function() h = player:getHoursSurvived() end)
  return h ~= nil and h < (CFG.Traits.ServerRestoreMaxHours or 1)
end

function T.restoreOnServer(player)
  if not isClient() or T.restore.sent or not T.serverKnows(player) then return false end
  local d = S.data(player)
  if d.traitsRestoreSent or not T.isNewCharacter(player) then T.restore.sent = true; return false end
  local ids = T.chosenModTraits()
  T.restore.sent = true
  if #ids == 0 then return false end
  d.traitsRestoreSent = true
  T.restore.ids = table.concat(ids, ",")
  sendClientCommand(player, "Sandevistan", "traits", { ids = T.restore.ids })
  S.log("rasgos del mod elegidos al crear el personaje, pedidos al servidor: " .. T.restore.ids)
  return true
end

function T.onAck(args)
  T.restore.ack = string.format("agregados=%s, ya estaban=%s, registrados por el servidor=%s, rechazo=%s",
    tostring(args.added or 0), tostring(args.had or 0), tostring(args.registered or 0), tostring(args.refused or "-"))
  S.log("rasgos repuestos por el servidor: " .. T.restore.ack)
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p then pcall(T.refresh, p) end
  end
end

function T.statusLine()
  if not isClient() then return "rasgos del mod: un jugador (sin reponer en el servidor)" end
  return "rasgos del mod en MP: pedidos=" .. tostring(T.restore.ids or "ninguno") .. " | respuesta del servidor: " .. tostring(T.restore.ack or "sin respuesta")
end

-- (190) MP: los kits y las banderas de "ya entregado" tienen que quedar guardados en el servidor ya; si no, una desconexión antes
-- del guardado periódico (15 s) los volvía a entregar al reconectar.
local function persist(player)
  local N = rawget(_G, "SandevistanNet")
  if N and N.saveState then pcall(N.saveState, player) end
end

-- Copia los rasgos a d.traits; entrega una vez el kit del "Instalador de callejón" y el del "Aprendiz de ripperdoc", y enseña las recetas del
-- ripperdoc (las tres civiles: compuesto sintético, inmunosupresor casero y tintura herbal).
function T.refresh(player)
  local d = S.data(player)
  for key, id in pairs(T.Ids) do d.traits[key] = T.has(player, id) or nil end
  if d.traits.ripperdoc then d.knows.compound = true; d.knows.crafted = true; d.knows.herbal = true end   -- (154) T01: las tres civiles
  if d.traits.excorpo then d.knows.kerenzikov = true end                  -- v0.1.30 (15): la receta de Kerenzikov desde el primer dia
  -- En multijugador el kit se entrega cuando el servidor ya conoce al jugador (id en línea válido); si no, los ítems se
  -- crearían solo en el cliente y no se podrían tirar ni mover. Se reintenta cada minuto (EveryOneMinute).
  if d.traits.labkit and not d.kitGiven and T.serverKnows(player) then
    d.kitGiven = true
    for _, fullType in ipairs(CFG.Traits.Kit) do S.grantItem(player, fullType) end
    persist(player)
    S.log("kit inicial de rasgo entregado")
  end
  -- (154) T01: los dos libros de guía del Aprendiz (First Aid y Electricista, vol. 1), con su propia bandera para no repetirlos.
  if d.traits.ripperdoc and not d.ripperdocKitGiven and T.serverKnows(player) then
    d.ripperdocKitGiven = true
    for _, fullType in ipairs(CFG.Traits.RipperdocKit or {}) do S.grantItem(player, fullType) end
    persist(player)
    S.log("kit del aprendiz de ripperdoc entregado")
  end
  if d.traits.excorpo and not d.excorpoKitGiven and T.serverKnows(player) then
    d.excorpoKitGiven = true
    for _, fullType in ipairs(CFG.Traits.ExCorpoKit) do S.grantItem(player, fullType) end
    persist(player)
    S.log("kit de ex-corpo entregado")
  end
  -- (161) T08: *Cromado* empieza con el implante puesto. Solo un personaje nuevo (el estado de un personaje viejo no se toca) y una sola vez.
  if d.traits.chromed and not d.chromedApplied and T.serverKnows(player) and T.isNewCharacter(player) then
    local Med = rawget(_G, "SandevistanMedical")
    if Med and Med.applyStartingImplant then
      d.chromedApplied = true
      Med.applyStartingImplant(player)
      Med.giveGuide(player)
      for _, fullType in ipairs(CFG.Traits.ChromedKit or {}) do S.grantItem(player, fullType) end
      persist(player)
      S.log("rasgo Cromado aplicado: implante puesto y kit entregados")
    end
  end
  return d.traits
end

Events.OnCreatePlayer.Add(S.safe("Traits.OnCreatePlayer", function(idx)
  local p = idx and getSpecificPlayer(idx)
  if p then T.refresh(p) end
end))
Events.EveryOneMinute.Add(S.safe("Traits.EveryOneMinute", function()
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p and not p:isDead() then
      if idx == 0 then T.restoreOnServer(p) end
      T.refresh(p)
    end
  end
end))
do
  local NetC = rawget(_G, "SandevistanNet")
  if NetC and type(NetC.handlers) == "table" then NetC.handlers.traitsAck = T.onAck end
end
Events.OnGameStart.Add(S.safe("Traits.OnGameStart", function()
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p then T.refresh(p) end
  end
end))

---------------------------------------------------------------------------
-- (128) Opcion de sandbox Sandevistan.CharacterTraits: apagada, los rasgos del mod no aparecen en la creacion de personaje. Solo los oculta: un
-- personaje que ya tiene uno lo conserva y sigue funcionando (T.refresh no cambia). Se lee con getSandboxOptions() y no con SandboxVars, como
-- NegativeTraitsPenalty en vanilla: en el menu la partida todavia no existe. En multijugador el servidor manda sus opciones en la respuesta del
-- login (ConnectionDetails.write -> writeSandboxOptions en 42.21), antes de crear el personaje.
-- La pantalla (CharacterCreationProfession) se crea una sola vez al abrir el juego y solo rearma las listas al agregar o sacar un rasgo: por eso
-- ademas del filtro (isTraitEnabled, el mismo que usa vanilla para Insomne en MP) se rearman al mostrarla. El boton aleatorio y las builds
-- guardadas toman los rasgos de esas listas, asi que tampoco pueden meter uno oculto.
---------------------------------------------------------------------------
function T.creationEnabled()
  local on = true
  pcall(function()
    local opt = getSandboxOptions():getOptionByName("Sandevistan.CharacterTraits")
    if opt then on = opt:getValue() ~= false end
  end)
  return on
end

local modTraits = nil
function T.isModTrait(traitDef)
  if not modTraits or #modTraits == 0 then
    modTraits = {}
    for _, id in pairs(T.Ids) do
      pcall(function()
        local t = CharacterTrait.get(ResourceLocation.of(id))
        if t then modTraits[#modTraits + 1] = t end
      end)
    end
  end
  local ok, ty = pcall(function() return traitDef:getType() end)
  if not ok or ty == nil then return false end
  for _, t in ipairs(modTraits) do
    if t == ty then return true end
  end
  return false
end

-- Al mostrar la pantalla: con la opcion apagada saca los rasgos del mod que hayan quedado elegidos (devuelve los puntos) y rearma las listas.
function T.refreshCreation(screen)
  if not screen.listboxTraitSelected or not screen.listboxTrait or not screen.removeTraitBtn then return end
  if not T.creationEnabled() then
    local items = screen.listboxTraitSelected.items
    for i = #items, 1, -1 do
      if items[i] and T.isModTrait(items[i].item) then screen:removeTrait(i) end
    end
  end
  screen:repopulateTraitLists()
end

function T.installCreationFilter()
  local C = rawget(_G, "CharacterCreationProfession")
  if type(C) ~= "table" or type(C.isTraitEnabled) ~= "function" or type(C.setVisible) ~= "function" then return false end
  if C.sandevistanTraitFilter then return true end
  C.sandevistanTraitFilter = true
  local origEnabled = C.isTraitEnabled
  C.isTraitEnabled = function(self, trait, ...)
    if T.isModTrait(trait) and not T.creationEnabled() then return false end
    return origEnabled(self, trait, ...)
  end
  local origVisible = C.setVisible
  C.setVisible = function(self, visible, ...)
    local r = origVisible(self, visible, ...)
    if visible then
      local ok, err = pcall(T.refreshCreation, self)
      if not ok then print("[Sandevistan] WARN rasgos en la creacion de personaje: " .. tostring(err)) end
    end
    return r
  end
  return true
end

T.installCreationFilter()
if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function() T.installCreationFilter() end) end

return T
