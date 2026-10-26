-- Sandevistan / Medical: requisitos y resultados de todas las acciones sobre ítems.
-- Los menús (ContextMenus.lua) solo muestran opciones y encolan SandevistanAction con estas funciones.
require "Sandevistan/Core"
require "Sandevistan/RecipeCode"
require "Sandevistan/Kerenzikov"
require "Sandevistan/Effects"
require "Sandevistan/Runtime"
require "Sandevistan/Net"
require "Sandevistan/BookGuide"

local CFG = SandevistanConfig
local S = Sandevistan
local getText = S.text     -- requisitos con el nombre vanilla del ítem
local E = SandevistanEffects
local R = SandevistanRuntime
local V = CFG.Crafting.Items
local BG = SandevistanBookGuide

SandevistanMedical = {}
local M = SandevistanMedical

-- (190) Multijugador: el estado del jugador (implante, rechazo, XP...) lo guarda el servidor y solo se entera con transmitModData.
-- Al instalar, explantar o calibrar conviene mandarlo ya: el guardado periódico tarda hasta SaveEveryMs (15 s) y una desconexión
-- antes de eso dejaba el cambio sin guardar.
local function persist(player)
  local N = rawget(_G, "SandevistanNet")
  if N and N.saveState then pcall(N.saveState, player) end
end

---------------------------------------------------------------------------
-- (155) T06: guía con libros (shared/Sandevistan/BookGuide.lua). Cada acción que pedía un nivel de skill ahora acepta los libros vanilla de
-- esa skill: sin el nivel y con los libros sigue disponible (más lenta y con chance de fallar); sin el nivel ni los libros, el motivo pasa a
-- «Requiere X N (o con los libros: ...)». El tiempo y la tirada salen de BG, no de números sueltos.
---------------------------------------------------------------------------
local function bookReason(reqKey, required, bg)
  return getText("IGUI_Sandevistan_Req_OrBooks", getText(reqKey, required), table.concat(BG.missingNames(bg), ", "))
end

-- Motivo de una skill: nil si el nivel alcanza o si los libros guían. Devuelve también el resultado de BG.
local function skillReason(character, perk, required, reqKey)
  local bg = BG.check(character, perk, required)
  if bg.ok then return nil, bg end
  return bookReason(reqKey, required, bg), bg
end

-- Info para el menú: { gap, timeMult, fail = chance de que salga mal (0..1) } cuando los libros guían; nil con el nivel.
function M.bookInfo(bg, failChance)
  if not bg or not bg.ok or (bg.gap or 0) <= 0 then return nil end
  return { gap = bg.gap, timeMult = BG.timeMult(bg.gap), fail = failChance or BG.failChance(bg.gap) }
end

M.T = {
  Military = "Sandevistan.SandevistanMilitary",
  Lab = "Sandevistan.SandevistanLab",
  P04 = "Sandevistan.SandevistanLabP04Broken",
  CryoBox = "Sandevistan.SandevistanCryoBox",
  Harness = "Sandevistan.SandevistanCryoBoxEmpty",
  Clinical = "Sandevistan.ImmunosuppressantClinicalPack",          -- v0.1.30 (17): drenables de 3 dosis
  Crafted = "Sandevistan.ImmunosuppressantCraftedPack",
  Herbal = "Sandevistan.ImmunosuppressantHerbalPack",
  Compound = "Sandevistan.SyntheticCompoundSample",
  KereMil = "Sandevistan.KerenzikovMilitary",
  KereCrafted = "Sandevistan.KerenzikovCrafted",
  NotebookBook = "Sandevistan.ImmunoSynthesisBook",                -- v0.1.30 (22): literatura nativa que ensena las recetas (LearnedRecipes)
  KereBook = "Sandevistan.KerenzikovFormulationBook",
  PartBoard = "Sandevistan.NeuralInterfaceBoard",                  -- v0.1.30 (24): partes del Prototipo 06
  PartRegulator = "Sandevistan.ThermalRegulator",
  PartCell = "Sandevistan.PowerCell",
  PartChassis = "Sandevistan.ImplantChassis",                      -- v0.1.30 (68): chasis y arnes (Costura)
  PartHarness = "Sandevistan.NeuralLinkHarness",
  Blueprint06 = "Sandevistan.SandevistanBlueprint06",              -- v0.1.30 (43): planos (literatura nativa: ensenan las recetas del diseno)
  Blueprint07 = "Sandevistan.SandevistanBlueprint07",
  MilChip = "Sandevistan.MilSpecChip",
}

function M.implantVariant(item)
  local t = item:getFullType()
  if t == M.T.Military then return "military" end
  if t == M.T.Lab then return "lab" end
  return nil
end

-- Marca un implante como prototipo alternativo ("04" | "06" en laboratorio, "07" en militar) y le pone nombre propio.
function M.prototypeName(proto) return getText("IGUI_Sandevistan_ItemName_P" .. proto) end

function M.tagPrototype(item, proto)
  if not item or not proto then return end
  item:getModData().prototype = proto
  S.try("setName", function()
    item:setName(M.prototypeName(proto))
    item:setCustomName(true)
  end)
end

function M.itemPrototype(item) return item and item:getModData().prototype or nil end

---------------------------------------------------------------------------
-- Nombre de la placa (v0.1.30 (69)): los implantes que arma el jugador (P06 y Mk. II) se pueden renombrar desde el menu del item, con una lapicera.
---------------------------------------------------------------------------
local PENS = { V.Pen, V.BluePen, V.RedPen, V.Pencil }

function M.itemPlate(item) return item and S.cleanPlate(item:getModData().plateName) or nil end

-- El item es un implante cuyo diseno permite ponerle nombre (P06 / Mk. II).
function M.plateAllowed(item)
  if not (CFG.Plate and CFG.Plate.Enabled) or not item then return false end
  local t = item:getFullType()
  if t ~= M.T.Lab and t ~= M.T.Military then return false end
  local proto = item:getModData().prototype
  return proto ~= nil and CFG.Plate.Prototypes[proto] == true
end

function M.plateReq(player, item)
  local reasons = {}
  if not M.findAny(player, PENS) then table.insert(reasons, getText("IGUI_Sandevistan_Req_Pen")) end
  return reasons
end

-- Nombre del item segun su diseno y su nombre de placa: "Sandevistan (Prototipo 06) \"EL RELAMPAGO\"".
local function plateItemName(item, plate)
  local proto = item:getModData().prototype
  local base = proto and M.prototypeName(proto) or item:getName()
  if plate then return base .. ' "' .. plate .. '"' end
  return base
end

-- Mismo nombre, para un implante que todavia no existe (se crea con el nombre puesto: S.grantItem).
function M.plateName(proto, plate)
  local base = M.prototypeName(proto)
  if plate then return base .. ' "' .. plate .. '"' end
  return base
end

-- Pone (o saca, con texto vacio) el nombre de la placa. Devuelve el nombre limpio o nil.
function M.setPlate(item, text)
  if not item then return nil end
  local plate = S.cleanPlate(text)
  local md = item:getModData()
  md.plateName = plate
  if md.prototype then
    S.try("setName", function() item:setName(plateItemName(item, plate)); item:setCustomName(true) end)
  end
  S.try("syncItemFields", function() item:syncItemFields() end)        -- multijugador: que el servidor vea el cambio del item
  S.syncItem(nil, item, { "plateName" })                              -- (115) y el ModData (syncItemFields lleva el nombre, no el ModData)
  return plate
end

function M.itemDegradation(item)
  local md = item:getModData()
  return md.heatDegradationMultiplier or 1.0, md.degradationFloor or 1.0
end

---------------------------------------------------------------------------
-- Inventario
---------------------------------------------------------------------------
function M.find(player, fullType)
  return player:getInventory():getFirstTypeRecurse(fullType)
end

---------------------------------------------------------------------------
-- (157) Espejo para operarte solo: el item del inventario o un espejo del mundo al lado. Es la misma detección que usa el juego para maquillarse
-- (ISInventoryPaneContextMenu.doMakeUpMenu, vanilla): objetos o sprites pegados con la propiedad IsMirror, sin pared de por medio, en el área
-- de 3x4 casillas alrededor del jugador.
---------------------------------------------------------------------------
local function worldMirror(player)
  local sq0 = nil
  pcall(function() sq0 = player:getCurrentSquare() end)
  if not sq0 then return false end
  local cell = getCell()
  for x = sq0:getX() - 1, sq0:getX() + 2 do
    for y = sq0:getY() - 1, sq0:getY() + 2 do
      local sq = cell:getGridSquare(x, y, sq0:getZ())
      if sq then
        local objects = sq:getObjects()
        for i = 0, objects:size() - 1 do
          local object = objects:get(i)
          local sprite = object:getSprite()
          if sprite and not sq:isWallTo(sq0) and sprite:getProperties():has("IsMirror") then return true end
          local anim = object:getAttachedAnimSprite()
          if anim then
            for j = 0, anim:size() - 1 do
              local s2 = anim:get(j):getParentSprite()
              if s2 and not sq:isWallTo(sq0) and s2:getProperties():has("IsMirror") then return true end
            end
          end
        end
      end
    end
  end
  return false
end

function M.mirrorInReach(player)
  if not player then return false end
  if M.find(player, V.Mirror) then return true end
  local ok, found = pcall(worldMirror, player)
  return ok and found == true
end

function M.findAny(player, types)
  for _, t in ipairs(types) do
    local it = M.find(player, t)
    if it then return it end
  end
  return nil
end

-- Destornillador: el de siempre o cualquier item con la etiqueta SCREWDRIVER (v0.1.30 (23): la receta nativa ya aceptaba las 5 variantes de
-- vanilla pero los requisitos propios miraban solo Base.Screwdriver). Los rotos (condicion 0) no cuentan, igual que NoBrokenItems.
function M.findScrewdriver(player)
  local inv = player:getInventory()
  local it = inv:getFirstTypeRecurse(V.Screwdriver)
  if it then return it end
  local ItemTag = rawget(_G, "ItemTag")
  local tag = ItemTag and ItemTag.SCREWDRIVER
  if not tag then return nil end
  local found
  pcall(function()
    local list = inv:getAllEvalRecurse(function(x) return x:hasTag(tag) and not x:isBroken() end)
    if list and list:size() > 0 then found = list:get(0) end
  end)
  return found
end

function M.count(player, fullType)
  return player:getInventory():getCountTypeRecurse(fullType)
end

local function uses(item)
  if instanceof(item, "DrainableComboItem") then
    local ok, n = pcall(function() return item:getCurrentUses() end)
    return (ok and n) or 0
  end
  local fc = nil
  pcall(function() fc = item:getFluidContainer() end)
  if fc then
    local amt = 0
    pcall(function() amt = fc:getAmount() end)
    return amt > 0 and 99 or 0
  end
  return 1
end

-- (194) Items con una etiqueta vanilla (ItemTag.<tagKey>), sin los rotos. nil si la etiqueta no existe en esta version.
local function tagged(player, tagKey)
  local ItemTag = rawget(_G, "ItemTag")
  local tag = ItemTag and ItemTag[tagKey]
  if not tag then return nil end
  local list = nil
  pcall(function() list = player:getInventory():getAllEvalRecurse(function(x) return x:hasTag(tag) and not x:isBroken() end) end)
  return list
end

-- Usos disponibles de un tipo (drainables cuentan sus usos; fluidos cuentan como muchos).
function M.totalUses(player, fullType)
  local items = player:getInventory():getAllTypeRecurse(fullType)
  local total = 0
  for i = 0, items:size() - 1 do total = total + uses(items:get(i)) end
  return total
end

-- (194) Sutura de las cirugias (CFG.Surgery.ThreadUses): la aguja de sutura o una aguja de coser con hilo, como en vanilla
-- (ISHealthPanel.HStitch: Base.Needle o etiqueta SEWING_NEEDLE + Base.Thread o etiqueta THREAD). La aguja de sutura va primero, como alla.
function M.threadUses(player)
  local list = tagged(player, "THREAD")
  local n = 0
  for i = 0, (list and list:size() or 0) - 1 do n = n + uses(list:get(i)) end
  return n
end

function M.hasSuture(player)
  if M.find(player, V.Suture) then return true end
  local needles = tagged(player, "SEWING_NEEDLE")
  return needles ~= nil and needles:size() > 0 and M.threadUses(player) >= (CFG.Surgery.ThreadUses or 3)
end

-- Texto del requisito: "falta aguja de sutura (o aguja e hilo, N usos)".
function M.sutureReason()
  return getText("IGUI_Sandevistan_Req_SutureOrThread", CFG.Surgery.ThreadUses or 3)
end

local function removeItem(item)
  local c = item:getContainer()
  if c then
    c:DoRemoveItem(item)
    if isClient() and rawget(_G, "sendRemoveItemFromContainer") then pcall(sendRemoveItemFromContainer, c, item) end   -- (114) MP: que el servidor tambien lo saque
  end
end

-- Consume "n" usos de un tipo: drainables con Use(), fluidos con removeFluid, el resto se borra.
function M.consume(player, fullType, n)
  n = n or 1
  local guard = 0
  while n > 0 and guard < 50 do
    guard = guard + 1
    local item = M.find(player, fullType)
    if not item then return false end
    local fc = nil
    pcall(function() fc = item:getFluidContainer() end)
    if fc then
      S.serverUse(player, item, "fluid", 0.1)                                  -- (115) MP: que el servidor tambien lo gaste
      S.try("removeFluid", function() fc:removeFluid(0.1) end)
      n = n - 1
    elseif instanceof(item, "DrainableComboItem") then
      S.serverUse(player, item, "use")                                        -- (115) MP: que el servidor tambien lo gaste
      local okUse = pcall(function() item:Use() end)
      if not okUse then removeItem(item) end
      n = n - 1
    else
      removeItem(item)
      n = n - 1
    end
  end
  return true
end

-- (194) Gasta la sutura de una cirugia: la aguja de sutura entera o ThreadUses usos de hilo (la aguja de coser queda).
function M.consumeSuture(player)
  if M.find(player, V.Suture) then return M.consume(player, V.Suture, 1) end
  local left = CFG.Surgery.ThreadUses or 3
  local list = tagged(player, "THREAD")
  for i = 0, (list and list:size() or 0) - 1 do
    local it = list:get(i)
    local guard = 0
    while left > 0 and uses(it) > 0 and guard < 50 do
      guard = guard + 1
      S.serverUse(player, it, "use")                                        -- (115) MP: que el servidor tambien lo gaste
      if not pcall(function() it:Use() end) then removeItem(it); left = left - 1; break end
      left = left - 1
    end
    if left <= 0 then break end
  end
  return left <= 0
end

function M.consumeFirstOf(player, types, n)
  for _, t in ipairs(types) do
    if M.totalUses(player, t) >= (n or 1) then return M.consume(player, t, n) end
  end
  return false
end

function M.hasUsesOfAny(player, types, n)
  for _, t in ipairs(types) do
    if M.totalUses(player, t) >= (n or 1) then return true end
  end
  return false
end

-- (114) S.grantItem: en multijugador lo crea el servidor y devuelve true (no el item): el ModData y el nombre van en md y name.
function M.addItem(player, fullType, md, name)
  return S.grantItem(player, fullType, md, name)
end

local function fa(p) return p:getPerkLevel(Perks.Doctor) end
local function elec(p) return p:getPerkLevel(Perks.Electricity) end

local DISINFECT = { V.Disinfectant, V.AlcoholWipes }
M.DISINFECT = DISINFECT
local ALCOHOL = { V.Whiskey, V.Disinfectant }

---------------------------------------------------------------------------
-- Cirugía
---------------------------------------------------------------------------
-- Devuelve lista de { key, available, reasons = {textKeys}, chance, time }
-- (125) ¿El expediente del estudiante le baja el requisito al cirujano para este implante? (CFG.Surgery.StudentDossier)
function M.dossierGuided(surgeon, implant)
  local sd = CFG.Surgery.StudentDossier
  if not sd or not implant then return false end
  local variant = M.implantVariant(implant)
  return variant ~= nil and sd.Variants[variant] == true and S.dossierComplete(surgeon, sd.Dossier)
end

function M.surgeryOptions(surgeon, patient, implant)
  local self = surgeon == patient
  local skill = fa(surgeon)
  local guidedByDossier = M.dossierGuided(surgeon, implant)
  local hasHarness = M.find(surgeon, M.T.Harness) ~= nil
  local hasSuture = M.hasSuture(surgeon)                -- (194) o aguja de coser e hilo
  local hasDisinf = M.hasUsesOfAny(surgeon, DISINFECT, 1)
  local hasScalpel = M.find(surgeon, V.Scalpel) ~= nil
  local hasMirror = M.mirrorInReach(surgeon)
  local hasPills = M.totalUses(surgeon, V.Painkillers) >= 1
  local list = {}
  local function add(key, needs)
    local c = CFG.Surgery[key]
    local reasons = {}
    local sd = CFG.Surgery.StudentDossier
    local minFA = guidedByDossier and math.min(c.minFA, sd.MinFA) or c.minFA
    -- (155) T06: el camino de los libros usa el mínimo real del método; se toma el mejor de los dos caminos (expediente o libros), sin sumarlos.
    local bg = BG.check(surgeon, "Doctor", c.minFA)
    local booksPath = bg.ok and bg.gap > 0
    if skill < minFA and not booksPath then
      if #bg.missing > 0 then table.insert(reasons, bookReason("IGUI_Sandevistan_Req_FA", minFA, bg))
      else table.insert(reasons, getText("IGUI_Sandevistan_Req_FA", minFA)) end
    end
    for _, n in ipairs(needs) do if not n[1] then table.insert(reasons, n[3] or getText(n[2])) end end
    local chance = S.thresholdValue(c.chance, skill) or 0
    local sloppy, gap = nil, nil
    if skill < c.minFA then
      local atMin = S.thresholdValue(c.chance, c.minFA) or 0
      local dossierChance = nil
      if guidedByDossier and skill >= sd.MinFA then        -- (125) por debajo del minimo de siempre: menos probabilidad y herida segura
        local lo = sd.ChanceAtMinFA[key] or 0
        local t = (c.minFA > sd.MinFA) and (skill - sd.MinFA) / (c.minFA - sd.MinFA) or 1
        dossierChance = lo + (atMin - lo) * math.max(0, t)
      end
      local booksChance = booksPath and BG.chanceBelow(atMin, bg.gap, c.BookChanceFloor) or nil
      if dossierChance and (not booksChance or dossierChance >= booksChance) then
        chance, sloppy = dossierChance, true
      elseif booksChance then
        chance, sloppy, gap = booksChance, true, bg.gap
      end
    end
    table.insert(list, { key = key, available = #reasons == 0, reasons = reasons, dossier = guidedByDossier or nil, sloppy = sloppy,
                         chance = chance, time = c.time * (gap and BG.timeMult(gap) or 1),
                         books = gap and { gap = gap, timeMult = BG.timeMult(gap), fail = math.max(0, 1 - chance) } or nil })
  end
  local common = { { hasSuture, "IGUI_Sandevistan_Req_Suture", M.sutureReason() }, { hasDisinf, "IGUI_Sandevistan_Req_Disinfectant" } }
  if self then
    add("guided", { { hasHarness, "IGUI_Sandevistan_Req_Harness" }, common[1], common[2] })
    add("blind", { { hasMirror, "IGUI_Sandevistan_Req_MirrorPlace" }, { hasScalpel, "IGUI_Sandevistan_Req_Scalpel" },
                   { hasPills, "IGUI_Sandevistan_Req_Painkillers" }, common[1], common[2] })
  else
    add("assistedHarness", { { hasHarness, "IGUI_Sandevistan_Req_Harness" }, common[1], common[2] })
    add("assistedNoHarness", { { hasScalpel, "IGUI_Sandevistan_Req_Scalpel" }, common[1], common[2] })
  end
  return list
end

function M.canReceiveImplant(patient)
  local d = S.data(patient)
  return d.variant == nil
end

-- Tipo de inmunosupresor de un item ("clinical" | "crafted" | "herbal") o nil.
M.IMMUNO_TIER = { [M.T.Clinical] = "clinical", [M.T.Crafted] = "crafted", [M.T.Herbal] = "herbal" }
function M.immunoTier(fullType) return M.IMMUNO_TIER[fullType] end

function M.hasAnyImmuno(player)
  for t in pairs(M.IMMUNO_TIER) do
    local it = M.find(player, t)
    if it then return it end
  end
  return nil
end

-- Aplica el implante a "patient" (solo toca el estado del paciente; en multijugador lo llama
-- el propio cliente del paciente al recibir el resultado de la operación).
function M.applyImplant(patient, variant, deg, floor, proto, plate)
  local d = S.data(patient)
  d.variant = variant
  d.degradation = deg
  d.degradationFloor = floor
  d.prototype = proto                                              -- (43) tambien el militar puede ser una replica (P07)
  d.plateName = (proto and CFG.Plate and CFG.Plate.Prototypes[proto]) and S.cleanPlate(plate) or nil     -- (69)
  -- tras una explantación: conserva la adaptación y arranca con rechazo. (124) Sin recortar al techo de la variante: la XP de mas queda guardada (como la de
  -- Sin limitador) y vuelve si despues se pone otra vez un implante que la alcanza (militar -> laboratorio -> militar ya no pierde nada)
  d.adaptXP = d.keptXP or 0
  d.keptXP = nil
  d.heat, d.rejection, d.cooldownMult = 0, d.pendingRejection or 0, 1
  d.pendingRejection = nil
  d.remissionHours, d.noImplantSinceHour = 0, nil                  -- (165) con implante, la remisión se reinicia
  d.lastRejectionTickHour = S.worldHours()
  d.lastCNTickHour = S.worldHours()
  E.addPain(patient, "Torso_Lower", CFG.Surgery.PostOpPain)
  E.halo(patient, getText("IGUI_Sandevistan_SurgeryOK"), 80, 220, 255)
  -- v0.1.30 (30): guia de campo (una vez) y escena de instalacion. Esto corre SOLO en la maquina del paciente (RemoteSurgery: el cliente del paciente aplica el
  -- implante), asi que el cirujano no ve nada de la escena.
  local gave = M.giveGuide(patient)
  local IS = rawget(_G, "SandevistanInstallScene")
  local started = IS and IS.start(patient, { ok = true, variant = variant, prototype = d.prototype, degradation = deg, rejection = d.rejection, guide = gave })
  if not started then                                              -- sin escena (desactivada o no local): el panel se enciende igual
    local HD = rawget(_G, "SandevistanHUD")
    if HD and HD.powerOn then S.try("hud.powerOn", function() HD.powerOn(patient) end) end
  end
end

-- Crea la guia en el inventario del jugador. En multijugador la crea el SERVIDOR (comando "grant"): un item creado por el cliente no siempre es valido para el
-- servidor y no se deja tirar ni pasar a contenedores (paso con la primera version). `unique`: no si ya lleva una.
function M.grantGuideItem(player, unique)
  if isClient() then
    sendClientCommand(player, "Sandevistan", "grant", { type = CFG.Guide.Item, unique = unique and true or nil })
    return true
  end
  local has = false
  pcall(function() has = unique and M.find(player, CFG.Guide.Item) ~= nil end)
  if has then return false end
  return S.giveItem(player:getInventory(), CFG.Guide.Item) ~= nil
end

-- Entrega UNA vez la guia de campo al paciente (nunca al cirujano): la crea el cliente de quien la va a tener, asi que en multijugador no hay duplicado.
function M.giveGuide(player)
  local d = S.data(player)
  if CFG.FieldGuideOnInstall == false then return false end
  local T = rawget(_G, "SandevistanTraits")
  if T and not T.serverKnows(player) then return false end          -- en MP el item se crea cuando el servidor ya conoce al jugador (se reintenta cada minuto)
  if d.guideGiven then return false end
  local has = false
  pcall(function() has = M.find(player, CFG.Guide.Item) ~= nil end)
  if has then d.guideGiven = true; return false end     -- ya la lleva (por si el estado se perdio): no se duplica
  if not M.grantGuideItem(player, true) then return false end
  d.guideGiven = true
  S.log("guia de campo entregada")
  return true
end

-- Fallo: corte en la espalda del paciente (el implante no se pierde; lo degrada el cirujano).
function M.applyFailedCut(patient)
  E.hemorrhage(patient, "Torso_Lower", "severe")
  local IS = rawget(_G, "SandevistanInstallScene")
  if IS then IS.start(patient, { ok = false }) end
end

-- (125) Instalacion que salio bien con el binder pero por debajo del First Aid de siempre: herida profunda leve en la espalda (CFG.Surgery.StudentDossier.SloppyWound).
function M.applySloppyWound(patient)
  local w = CFG.Surgery.StudentDossier.SloppyWound
  E.hemorrhage(patient, w.part, "light")
  E.halo(patient, getText("IGUI_Sandevistan_SurgerySloppy"), 255, 190, 80)
end

function M.degradeAfterFailure(implant)
  local deg = M.itemDegradation(implant)
  implant:getModData().heatDegradationMultiplier = math.min(CFG.Extraction.MaxDegradation, deg + CFG.Surgery.FailDegradationExtra)
  S.syncItem(nil, implant, { "heatDegradationMultiplier" })           -- (115) MP: el servidor no se enteraba del desgaste
end

function M.performSurgery(surgeon, patient, implant, option)
  local variant = M.implantVariant(implant)
  if not variant or not M.canReceiveImplant(patient) then return end
  M.consumeSuture(surgeon)                                         -- (194) aguja de sutura o aguja e hilo
  M.consumeFirstOf(surgeon, DISINFECT, 1)
  if option.key == "blind" then
    M.consume(surgeon, V.Painkillers, 1)
    E.addPain(patient, "Torso_Lower", 70)
  end
  if S.chance(option.chance) then
    local deg, floor = M.itemDegradation(implant)
    local proto = M.itemPrototype(implant)
    local plate = M.itemPlate(implant)
    removeItem(implant)
    M.applyImplant(patient, variant, deg, floor, proto, plate)
    if option.sloppy then M.applySloppyWound(patient) end
    persist(patient)                                                   -- (190) que el servidor lo guarde ya
  else
    M.applyFailedCut(patient)
    if variant ~= "military" then M.degradeAfterFailure(implant) end      -- v0.1.26: el militar no sufre nada si falla
    E.halo(surgeon, getText("IGUI_Sandevistan_SurgeryFail"), 255, 120, 60)
  end
end

---------------------------------------------------------------------------
-- Caja criogénica
---------------------------------------------------------------------------
function M.openCryoBox(player, box)
  removeItem(box)
  M.addItem(player, M.T.Military)
  M.addItem(player, M.T.Harness)
end

---------------------------------------------------------------------------
-- Extracción (sobre cadáver con ModData.Sandevistan)
---------------------------------------------------------------------------
function M.corpseImplant(body)
  if not body then return nil end
  local md = body:getModData()
  local info = md and md.Sandevistan
  if type(info) ~= "table" then return nil end
  if info.extracted then return nil end
  if info.variant ~= "lab" and info.variant ~= "military" then return nil end
  return info
end

-- (49) Desgaste (multiplicador de Heat) del implante extraido segun el First Aid: lineal de DegradationAtFA0 (FA 0) a 1.0 (FA PerfectFA o mas); sin azar.
function M.extractionDegradation(skill)
  local X = CFG.Extraction
  local f = math.max(0, math.min(1, (skill or 0) / math.max(1, X.PerfectFA)))
  return 1 + (X.DegradationAtFA0 - 1) * (1 - f)
end

-- Extracción limpia: con bisturí (sin nivel minimo; cuanto mas First Aid, menos desgaste).
function M.extractionReq(player)
  local reasons = {}
  if not M.find(player, V.Scalpel) then table.insert(reasons, getText("IGUI_Sandevistan_Req_Scalpel")) end
  return reasons
end

-- Extracción tosca: cualquier cuchillo afilado.
-- ¿El nombre del tipo ("SteakKnife") parece un cuchillo? (Words sin ExcludeWords, sin distinguir mayúsculas)
function M.isBladeName(typeName)
  local n = string.lower(tostring(typeName or ""))
  local C = CFG.Extraction.Crude
  for _, w in ipairs(C.ExcludeWords) do if string.find(n, w, 1, true) then return false end end
  for _, w in ipairs(C.Words) do if string.find(n, w, 1, true) then return true end end
  return false
end

function M.crudeTool(player)
  local known = M.findAny(player, CFG.Extraction.Crude.Tools)
  if known then return known end
  local inv = player:getInventory()
  local ItemTag = rawget(_G, "ItemTag")
  for _, tagName in ipairs(CFG.Extraction.Crude.Tags) do        -- por etiqueta del juego
    local tag = ItemTag and ItemTag[tagName]
    if tag then
      local ok, it = pcall(function() return inv:getFirstTagRecurse(tag) end)
      if ok and it then return it end
    end
  end
  local found                                                   -- por nombre del tipo
  pcall(function()
    local list = inv:getAllEvalRecurse(function(it) return M.isBladeName(it:getType()) end)
    if list and list:size() > 0 then found = list:get(0) end
  end)
  return found
end

function M.crudeExtractionReq(player)
  local reasons = {}
  if not M.crudeTool(player) then table.insert(reasons, getText("IGUI_Sandevistan_Req_Knife")) end
  return reasons
end

-- (101) Una sola opcion de extraccion en el menu: "clean" con bisturi, "crude" con un cuchillo afilado si no hay bisturi, nil si no hay ninguno.
function M.extractionMode(player)
  if #M.extractionReq(player) == 0 then return "clean" end
  if #M.crudeExtractionReq(player) == 0 then return "crude" end
  return nil
end

function M.extractionAnyReq(player)
  if M.extractionMode(player) then return {} end
  return { getText("IGUI_Sandevistan_Req_ScalpelOrKnife") }
end

function M.performExtraction(player, body, crude)
  local info = M.corpseImplant(body)
  if not info then return end
  info.extracted = true
  if isClient() then pcall(function() body:transmitModData() end) end   -- MP: que nadie más extraiga el mismo implante
  local skill = fa(player)
  if SandevistanWorld and SandevistanWorld.authority and SandevistanWorld.markSubject then
    SandevistanWorld.markSubject(info.subjectId, "extracted")
  elseif isClient() and info.subjectId ~= nil then
    -- v0.1.30 (13): el registro de ex-sujetos es del servidor; si no se entera, al desaparecer el cuerpo deja otro implante en el suelo
    pcall(sendClientCommand, player, "Sandevistan", "subjectExtracted", { id = info.subjectId })
  end
  local X = CFG.Extraction
  local deg = M.extractionDegradation(skill)
  if crude then
    deg = deg + X.Crude.DegradationExtra
    if S.chance(X.Crude.CutChance) then
      E.cutPart(player, "Hand_R")
      E.halo(player, getText("IGUI_Sandevistan_ExtractCut"), 255, 120, 80)
    end
  end
  deg = math.min(X.MaxDegradation, math.max(info.degradation or 1.0, deg))
  M.addItem(player, info.variant == "military" and M.T.Military or M.T.Lab,
    { heatDegradationMultiplier = deg, degradationFloor = info.degradationFloor })
  E.halo(player, getText(crude and "IGUI_Sandevistan_ExtractCrudeDone" or "IGUI_Sandevistan_ExtractOK",
    string.format("%.1f", deg)), 80, 220, 255)
end

---------------------------------------------------------------------------
-- Calibración y reparación del Prototipo 04
---------------------------------------------------------------------------
-- (122) Chatarra de una calibracion que saca `wear` de desgaste (degradacion menos su piso).
function M.calibrationScrap(wear)
  local c = CFG.Calibration
  local n = math.ceil((tonumber(wear) or 0) / (c.WearPerScrap or 0.1) - 1e-6)
  return math.max(c.ScrapRequired or 1, n)
end

function M.itemWear(implant)
  local deg, floor = M.itemDegradation(implant)
  return math.max(0, deg - math.max(1.0, floor))
end

function M.installedWear(d)
  return math.max(0, (d.degradation or 1) - math.max(1.0, d.degradationFloor or 1))
end

function M.calibrationReq(player, implant)
  local reasons = {}
  local deg, floor = M.itemDegradation(implant)
  local scrap = M.calibrationScrap(M.itemWear(implant))
  if deg <= math.max(1.0, floor) then table.insert(reasons, getText("IGUI_Sandevistan_Req_NotDegraded")) end
  local reasonFA = skillReason(player, "Doctor", CFG.Calibration.MinFA, "IGUI_Sandevistan_Req_FA")
  local reasonEl = skillReason(player, "Electricity", CFG.Calibration.MinElectrical, "IGUI_Sandevistan_Req_Elec")
  if reasonFA then table.insert(reasons, reasonFA) end
  if reasonEl then table.insert(reasons, reasonEl) end
  if not M.findScrewdriver(player) then table.insert(reasons, getText("IGUI_Sandevistan_Req_Screwdriver")) end
  if M.count(player, V.ElectronicsScrap) < scrap then
    table.insert(reasons, getText("IGUI_Sandevistan_Req_Scrap", scrap))
  end
  return reasons
end

-- (155) T06: guía de la calibración suelta (First Aid + Electricidad).
function M.calibrationGuide(player)
  return BG.checkAll(player, { Doctor = CFG.Calibration.MinFA, Electricity = CFG.Calibration.MinElectrical })
end

-- (155) un solo lugar para la tirada de los crafteos que hoy no fallaban: forcedFall para las pruebas.
local function bookFailRoll(bg, forcedFall)
  if forcedFall ~= nil then return forcedFall == true end
  return bg.ok and bg.gap > 0 and S.chance(BG.failChance(bg.gap))
end

function M.performCalibration(player, implant, forcedFall)
  local _, floor = M.itemDegradation(implant)
  M.consume(player, V.ElectronicsScrap, M.calibrationScrap(M.itemWear(implant)))
  if bookFailRoll(M.calibrationGuide(player), forcedFall) then          -- (155) T06: se gastó la chatarra y el desgaste queda igual
    E.halo(player, getText("IGUI_Sandevistan_CalibFailBook"), 255, 120, 60)
    return
  end
  implant:getModData().heatDegradationMultiplier = math.max(1.0, floor)
  S.syncItem(player, implant, { "heatDegradationMultiplier" })        -- (115) MP
  E.halo(player, getText("IGUI_Sandevistan_Calibrated"), 80, 220, 255)
end

---------------------------------------------------------------------------
-- Explantación
---------------------------------------------------------------------------
-- patient = nil: paciente remoto (multijugador); su estado lo comprueba su propio cliente al aplicar la operación.
function M.explantReq(surgeon, patient)
  local d = patient and S.data(patient) or nil
  local c = CFG.Explant
  local reasons = {}
  if d and not S.hasAnyImplant(d) then table.insert(reasons, getText("IGUI_Sandevistan_Req_NoImplant")) return reasons end
  local minFA = (d and d.variant == "destroyed") and c.MinFADestroyed or c.MinFA
  local reasonFA = skillReason(surgeon, "Doctor", minFA, "IGUI_Sandevistan_Req_FA")
  if reasonFA then table.insert(reasons, reasonFA) end
  if not M.find(surgeon, V.Scalpel) then table.insert(reasons, getText("IGUI_Sandevistan_Req_Scalpel")) end
  if not M.hasUsesOfAny(surgeon, DISINFECT, 1) then table.insert(reasons, getText("IGUI_Sandevistan_Req_Disinfectant")) end
  if surgeon == patient and not M.mirrorInReach(surgeon) then table.insert(reasons, getText("IGUI_Sandevistan_Req_MirrorPlace")) end
  return reasons
end

-- (155) T06: chance del explante con los libros. destroyed = el paciente tiene el implante quemado (pide FA 7).
function M.explantChance(surgeon, destroyed)
  local c = CFG.Explant
  local minFA = destroyed and c.MinFADestroyed or c.MinFA
  if fa(surgeon) >= minFA then return S.thresholdValue(c.chance, fa(surgeon)) or 0 end
  local bg = BG.check(surgeon, "Doctor", minFA)
  if bg.ok and bg.gap > 0 then return BG.chanceBelow(S.thresholdValue(c.chance, minFA) or 0, bg.gap, c.BookChanceFloor) end   -- (194) piso propio
  return 0
end

-- (155) T06: info de los libros para el menú del explante (nil con el nivel).
function M.explantBooks(surgeon, destroyed)
  local minFA = destroyed and CFG.Explant.MinFADestroyed or CFG.Explant.MinFA
  return M.bookInfo(BG.check(surgeon, "Doctor", minFA), 1 - M.explantChance(surgeon, destroyed))
end

-- Escena de desconexion (v0.1.30 (39)): SOLO en la maquina del paciente, igual que la de instalacion.
function M.explantScene(patient, info)
  local IS = rawget(_G, "SandevistanInstallScene")
  if IS then IS.start(patient, info) end
end

-- Corte y dolor de la explantación (siempre, salga bien o mal). Lo aplica el propio paciente.
function M.explantWound(patient)
  R.deactivate(patient, "forced")
  E.hemorrhage(patient, "Torso_Lower", "severe")
  E.addPain(patient, "Torso_Lower", 60)
end

-- Ítem que recibe el cirujano (snap = { variant, deg, floor, proto, plate } del implante retirado).
function M.explantGive(surgeon, snap)
  local c = CFG.Explant
  if snap.variant == "lab" or snap.variant == "military" then
    -- (69) el nombre de la placa vuelve con el implante
    local plate = snap.plate and S.cleanPlate(snap.plate) or nil
    M.addItem(surgeon, snap.variant == "military" and M.T.Military or M.T.Lab, {
        heatDegradationMultiplier = math.min(CFG.Extraction.MaxDegradation, (snap.deg or 1) + c.DegradationExtra),
        degradationFloor = (snap.floor or 1) > 1 and snap.floor or nil,
        prototype = snap.proto, plateName = plate },
      snap.proto and M.plateName(snap.proto, plate) or nil)
  else
    M.addItem(surgeon, V.ElectronicsScrap)   -- el implante quemado solo deja chatarra
  end
end

function M.performExplant(surgeon, patient, forcedChance, sloppy)
  local d = S.data(patient)
  if not S.hasAnyImplant(d) then return end
  M.consumeFirstOf(surgeon, DISINFECT, 1)                         -- (194) sin aguja de sutura: la incision queda abierta (explantWound)
  M.explantWound(patient)
  local chance = forcedChance or M.explantChance(surgeon, d.variant == "destroyed")
  if not S.chance(chance) then
    E.halo(surgeon, getText("IGUI_Sandevistan_ExplantFail"), 255, 120, 60)
    M.explantScene(patient, { kind = "explant", ok = false })
    return
  end
  if sloppy then M.applySloppyWound(patient) end          -- (155) T06: guiada con libros, salió bien igual con herida leve
  M.explantGive(surgeon, M.explantPatientPart(patient))
end

---------------------------------------------------------------------------
-- (165) T12: desconectar / reconectar el implante (29 §4.5, D13-D15). Solo con el implante apagado (y sin furia). Desconectado queda
-- inerte: no se puede encender, el firmware no corre, la CN baja a la mitad, los síntomas del daño cerebral siguen a la mitad (lo que
-- hace el implante no) y la remisión avanza a la mitad. Reconectar cuesta +CN, 20 s sin poder encender, estrés y un glitch; si
-- reconectás antes de 10 minutos, la CN se duplica.
---------------------------------------------------------------------------
function M.disconnectReq(player)
  local d = S.data(player)
  local reasons = {}
  if not S.hasAnyImplant(d) then table.insert(reasons, getText("IGUI_Sandevistan_Req_NoImplant")); return reasons end
  if d.variant == "destroyed" then table.insert(reasons, getText("IGUI_Sandevistan_Req_Destroyed")) return reasons end
  if R.isActive(player) then table.insert(reasons, getText("IGUI_Sandevistan_Req_TurnOff")) return reasons end
  if R.session(player).fury then table.insert(reasons, getText("IGUI_Sandevistan_Req_Fury")) end
  return reasons
end

function M.performDisconnect(player)
  local d = S.data(player)
  if R.isActive(player) or R.session(player).fury or not S.hasWorkingImplant(d) then return false end
  d.disconnected = true
  d.disconnectedAtHour = S.worldHours()
  E.halo(player, getText("IGUI_Sandevistan_Disconnected"), 255, 170, 80)
  if SandevistanHUD then SandevistanHUD.flash("disconnect") end
  local N = rawget(_G, "SandevistanNet")
  if N and N.saveState then pcall(N.saveState, player) end
  S.log("implante desconectado")
  return true
end

function M.performReconnect(player)
  local d = S.data(player)
  if not d.disconnected then return false end
  local c = CFG.Disconnect
  local rc = c.Reconnect
  local quick = d.disconnectedAtHour ~= nil and (S.worldHours() - d.disconnectedAtHour) < ((rc.QuickMinutes or 10) / 60)
  local cn = (rc.CN or 8) * (quick and (rc.QuickMult or 2) or 1)
  d.disconnected = false
  d.disconnectedAtHour = nil
  d.remissionHours = 0                                             -- reconectar reinicia la remisión
  d.neuralLoad = math.min(CFG.NeuralLoad.Max, (d.neuralLoad or 0) + cn)
  R.session(player).reuseAtMs = S.gameMs() + (rc.LockSeconds or 20) * 1000
  E.addStat(player, "STRESS", math.floor((rc.Stress or 0.15) * 100))
  E.halo(player, getText("IGUI_Sandevistan_Reconnected", math.floor(cn + 0.5), rc.LockSeconds or 20), 150, 200, 255)
  if SandevistanHUD and SandevistanHUD.forceGlitch then SandevistanHUD.forceGlitch(300) end
  local N = rawget(_G, "SandevistanNet")
  if N and N.saveState then pcall(N.saveState, player) end
  S.log("implante reconectado: +" .. math.floor(cn + 0.5) .. " de CN")
  return true
end

-- (161) T08: implante del rasgo *Cromado* ya puesto desde el arranque. Hace lo de applyImplant sin dolor, halo ni escena de instalación:
-- desgaste 1.1x, adaptación 0, rechazo 15, 24 h de cobertura casera ya corriendo (la dosis fue antes del brote: no suma inmunodepresión).
function M.applyStartingImplant(player)
  local d = S.data(player)
  local now = S.worldHours()
  d.variant = "lab"
  d.degradation, d.degradationFloor = 1.1, 1.0
  d.adaptXP, d.keptXP = 0, nil
  d.prototype, d.plateName = nil, nil
  d.heat, d.rejection, d.cooldownMult = 0, 15, 1
  d.pendingRejection = nil
  d.remissionHours, d.noImplantSinceHour = 0, nil             -- (165) con implante, la remisión se reinicia
  d.lastRejectionTickHour, d.lastCNTickHour = now, now
  d.immuno = d.immuno or {}
  d.immuno.craftedUntil = M.immunoUntil(d, "crafted", now)    -- 24 h a dificultad Normal (respeta duración y factor de inmunosupresores)
  d.immunoReboundUntil = -1
  S.log("implante inicial del rasgo Cromado aplicado (lab 1.1x, rechazo 15)")
  persist(player)                                                     -- (190) que el servidor lo guarde ya
  return true
end

-- (124) Fraccion de la adaptacion que se conserva al explantar: toda con un implante sano y la mitad si esta destruido.
function M.explantKeepFraction(d)
  local c = CFG.Explant
  if d.variant == "destroyed" then return c.KeepXPFractionDestroyed or c.KeepXPFraction or 1 end
  return c.KeepXPFraction or 1
end

-- Parte del paciente de una explantación exitosa: quita el implante conservando XP, CN y cobertura. Devuelve el snapshot.
function M.explantPatientPart(patient)
  local d = S.data(patient)
  local c = CFG.Explant
  local snap = { variant = d.variant, deg = d.degradation or 1, floor = d.degradationFloor or 1, proto = d.prototype, plate = d.plateName }
  local sceneInfo = { kind = "explant", ok = true, variant = d.variant, cyber = d.cyberpsychosisActive and true or nil, cn = d.neuralLoad,
                      keptPct = math.floor(M.explantKeepFraction(d) * 100 + 0.5),
                      remissionDays = (CFG.NeuralLoad.Remission and CFG.NeuralLoad.Remission.Enabled) and math.floor(CFG.NeuralLoad.Remission.HoursWithoutImplant / 24 + 0.5) or nil }
  d.keptXP = (d.adaptXP or 0) * M.explantKeepFraction(d)
  d.pendingRejection = c.RejectionSpike
  -- (82) los chips de firmware vuelven al inventario de quien tenia el implante (corre en su propia maquina: en multijugador son items validos)
  local FWC = rawget(_G, "SandevistanFirmwareClient")
  if FWC then FWC.returnChips(patient) end
  d.variant = nil
  d.adaptXP = 0
  d.heat, d.rejection, d.cooldownMult, d.lockUntilCool = 0, 0, 1, false
  d.degradation, d.degradationFloor = 1.0, 1.0
  d.prototype = nil
  d.plateName = nil
  -- la Carga Neuronal, la cyberpsicosis y la cobertura de inmunos se conservan; sin implante empieza a contar la remisión
  d.remissionHours = 0
  d.noImplantSinceHour = nil
  E.halo(patient, getText("IGUI_Sandevistan_ExplantOK"), 80, 220, 255)
  M.explantScene(patient, sceneInfo)
  persist(patient)                                                     -- (190) que el servidor lo guarde ya
  return snap
end

-- Calibración del implante instalado: auto (con espejo) o por otro jugador. Nunca lo pierde.
function M.installedCalibrationReq(surgeon, patient)      -- patient = nil: paciente remoto (lo comprueba su cliente)
  local d = patient and S.data(patient) or nil
  local reasons = {}
  if d and not S.hasWorkingImplant(d) then table.insert(reasons, getText("IGUI_Sandevistan_Req_NoImplant")) return reasons end
  if d and (d.degradation or 1) <= math.max(1.0, d.degradationFloor or 1) then table.insert(reasons, getText("IGUI_Sandevistan_Req_NotDegraded")) end
  local reasonFA = skillReason(surgeon, "Doctor", CFG.Calibration.MinFA, "IGUI_Sandevistan_Req_FA")
  local reasonEl = skillReason(surgeon, "Electricity", CFG.Calibration.MinElectrical, "IGUI_Sandevistan_Req_Elec")
  if reasonFA then table.insert(reasons, reasonFA) end
  if reasonEl then table.insert(reasons, reasonEl) end
  if not M.findScrewdriver(surgeon) then table.insert(reasons, getText("IGUI_Sandevistan_Req_Screwdriver")) end
  local scrap = d and M.calibrationScrap(M.installedWear(d)) or CFG.Calibration.ScrapRequired     -- remoto: el minimo; el resto se mira cuando el paciente acepta
  if M.count(surgeon, V.ElectronicsScrap) < scrap then
    table.insert(reasons, getText("IGUI_Sandevistan_Req_Scrap", scrap))
  end
  if surgeon == patient and not M.mirrorInReach(surgeon) then table.insert(reasons, getText("IGUI_Sandevistan_Req_MirrorPlace")) end
  if not M.hasUsesOfAny(surgeon, DISINFECT, 1) then table.insert(reasons, getText("IGUI_Sandevistan_Req_Disinfectant")) end
  return reasons
end

-- Parte del paciente de la calibración del implante instalado.
function M.calibratePatientPart(patient)
  local d = S.data(patient)
  d.degradation = math.max(1.0, d.degradationFloor or 1.0)
  E.addPain(patient, "Torso_Lower", 30)
  E.halo(patient, getText("IGUI_Sandevistan_Calibrated"), 80, 220, 255)
  persist(patient)                                                     -- (190) que el servidor lo guarde ya
end

-- (155) T06: guía de la calibración del implante instalado (First Aid + Electricidad).
function M.installedCalibrationGuide(surgeon)
  return BG.checkAll(surgeon, { Doctor = CFG.Calibration.MinFA, Electricity = CFG.Calibration.MinElectrical })
end

function M.performInstalledCalibration(surgeon, patient, forcedFall)
  M.consume(surgeon, V.ElectronicsScrap, M.calibrationScrap(M.installedWear(S.data(patient))))
  M.consumeFirstOf(surgeon, DISINFECT, 1)
  if bookFailRoll(M.installedCalibrationGuide(surgeon), forcedFall) then    -- (155) T06: chatarra gastada, el desgaste queda igual
    E.halo(surgeon, getText("IGUI_Sandevistan_CalibFailBook"), 255, 120, 60)
    return
  end
  M.calibratePatientPart(patient)
end

-- (155) T06: resultado de una calibración remota ya resuelta por el cirujano (success false = tirada fallida de los libros).
function M.installedCalibrationResult(patient, success)
  if success then M.calibratePatientPart(patient)
  else
    E.addPain(patient, "Torso_Lower", 10)
    E.halo(patient, getText("IGUI_Sandevistan_CalibFailBook"), 255, 120, 60)
  end
end

function M.repairReq(player)
  local c = CFG.Prototype04
  local reasons = {}
  local reasonEl = skillReason(player, "Electricity", c.MinElectrical, "IGUI_Sandevistan_Req_Elec")
  local reasonFA = skillReason(player, "Doctor", c.MinFA, "IGUI_Sandevistan_Req_FA")
  if reasonEl then table.insert(reasons, reasonEl) end
  if reasonFA then table.insert(reasons, reasonFA) end
  if not M.findScrewdriver(player) then table.insert(reasons, getText("IGUI_Sandevistan_Req_Screwdriver")) end
  if M.count(player, V.ElectronicsScrap) < c.ScrapRequired then
    table.insert(reasons, getText("IGUI_Sandevistan_Req_Scrap", c.ScrapRequired))
  end
  -- (95) piezas a reemplazar y estabilizador
  local P6 = CFG.Prototype06
  local REQ = { board = "IGUI_Sandevistan_Req_Board", regulator = "IGUI_Sandevistan_Req_Regulator", cell = "IGUI_Sandevistan_Req_Cell",
                chassis = "IGUI_Sandevistan_Req_Chassis", harness = "IGUI_Sandevistan_Req_LinkHarness" }
  for _, key in ipairs(c.Repair.Parts) do
    if not M.find(player, P6.Parts[key].item) then table.insert(reasons, getText(REQ[key])) end
  end
  if M.count(player, M.T.Compound) < c.Repair.CompoundRequired then table.insert(reasons, getText("IGUI_Sandevistan_Req_Compound")) end
  return reasons
end

-- (155) T06: guía de la reparación del P04 (Electricidad + First Aid).
function M.repairGuide(player)
  return BG.checkAll(player, { Electricity = CFG.Prototype04.MinElectrical, Doctor = CFG.Prototype04.MinFA })
end

-- (155) T06: chance de la reparación con los libros (la tirada de siempre es por Electricidad).
function M.repairChance(player)
  local c = CFG.Prototype04
  local base = S.thresholdValue(c.chance, elec(player))
  if base then return base end                     -- con la tabla de siempre manda el nivel (y las pruebas que la reemplazan)
  local bg = M.repairGuide(player)
  if bg.ok and bg.gap > 0 then return BG.chanceBelow(S.thresholdValue(c.chance, c.MinElectrical) or 0, bg.gap, c.BookChanceFloor) end
  return 0
end

-- (95) Reparar el P04: gasta la chatarra y el compuesto; si sale bien las piezas quemadas se gastan; si falla vuelven con FailWear de desgaste de mas.
function M.performRepair(player, broken, forcedChance)
  local c = CFG.Prototype04
  local P6, RC = CFG.Prototype06, SandevistanRecipeCode
  local parts = {}
  for _, key in ipairs(c.Repair.Parts) do parts[#parts + 1] = M.find(player, P6.Parts[key].item) end
  M.consume(player, V.ElectronicsScrap, c.ScrapRequired)
  M.consume(player, M.T.Compound, c.Repair.CompoundRequired)
  local chance = forcedChance or M.repairChance(player)
  if S.chance(chance) then
    for _, it in ipairs(parts) do removeItem(it) end
    removeItem(broken)
    M.addItem(player, M.T.Lab, { heatDegradationMultiplier = c.RepairedDegradation, degradationFloor = c.DegradationFloor, prototype = "04" },
      M.prototypeName("04"))
    E.halo(player, getText("IGUI_Sandevistan_RepairOK"), 80, 220, 255)
  else
    for _, it in ipairs(parts) do if RC and RC.setPartQuality then RC.setPartQuality(it, RC.partQuality(it) + (c.Repair.FailWear or 0)) end end
    E.halo(player, getText("IGUI_Sandevistan_RepairFail"), 255, 160, 60)
  end
end

---------------------------------------------------------------------------
-- Prototipo 06: ingeniería inversa (estudiar un implante suelto) y fabricación
---------------------------------------------------------------------------
function M.studyReq(player, item)
  local c = CFG.Prototype06
  local reasons = {}
  if not c.Enabled then table.insert(reasons, getText("IGUI_Sandevistan_Req_Disabled")) return reasons end
  if S.data(player).knows.proto06 then table.insert(reasons, getText("IGUI_Sandevistan_Req_AlreadyKnown")) end
  local reasonEl = skillReason(player, "Electricity", c.Study.MinElectrical, "IGUI_Sandevistan_Req_Elec")
  if reasonEl then table.insert(reasons, reasonEl) end
  if not M.findScrewdriver(player) then table.insert(reasons, getText("IGUI_Sandevistan_Req_Screwdriver")) end
  if c.Dossiers and not M.dossiersComplete(player, c.Dossiers) then table.insert(reasons, getText("IGUI_Sandevistan_Req_DossierStudent")) end   -- (106)
  return reasons
end

-- (155) T06: guía del estudio del P06 (Electricidad).
function M.studyGuide(player)
  return BG.check(player, "Electricity", CFG.Prototype06.Study.MinElectrical)
end

-- Desarmar y volver a armar un implante que funciona lo deja un poco peor (+0.1x, tope 1.8x).
-- (155) T06: guiado con libros puede fallar: no aprende el diseño y el implante se desarma igual (suma su DegradationExtra).
function M.performStudy(player, item, forcedFall)
  local c = CFG.Prototype06
  local bg = M.studyGuide(player)
  local fail = forcedFall
  if fail == nil then fail = bg.ok and bg.gap > 0 and S.chance(BG.failChance(bg.gap)) end
  if item:getFullType() ~= M.T.P04 then
    local deg = M.itemDegradation(item)
    item:getModData().heatDegradationMultiplier = math.min(CFG.Extraction.MaxDegradation, deg + c.Study.DegradationExtra)
    S.syncItem(player, item, { "heatDegradationMultiplier" })         -- (115) MP
  end
  if fail then
    E.halo(player, getText("IGUI_Sandevistan_StudyFailBook"), 255, 120, 60)
    return
  end
  S.data(player).knows.proto06 = true
  M.syncRecipes(player)
  persist(player)                                                     -- (190) MP: el conocimiento nuevo, guardado ya
  E.halo(player, getText("IGUI_Sandevistan_StudyOK"), 80, 220, 255)
end

---------------------------------------------------------------------------
-- Prototipo 07 (v0.1.30 (43)): replica del implante militar. Se aprende estudiando un militar funcional con los dos expedientes militares completos
-- encima (los planos); los dos expedientes no se consumen.
---------------------------------------------------------------------------
-- Cuantas paginas tiene archivadas el expediente de esa historia que lleva el jugador (nil si no lo lleva) y cuantas hacen falta.
function M.dossierProgress(player, storyId)
  local D = rawget(_G, "SandevistanDossier")
  if not D then return nil end
  for _, st in ipairs(CFG.Notes.Stories) do
    if st.id == storyId then
      local item = D.find(player, st)
      return item and D.count(item, st) or 0, D.total(st)
    end
  end
  return nil
end

-- expedientes completos encima (por Dossier.lua, el mismo conteo que muestra el nombre del expediente)
function M.dossiersComplete(player, ids)
  for _, id in ipairs(ids or {}) do
    local have, total = M.dossierProgress(player, id)
    if not have or not total or have < total then return false end
  end
  return true
end

function M.militaryDossiersComplete(player) return M.dossiersComplete(player, CFG.Prototype07.Dossiers) end

function M.studyMilReq(player, item)
  local c = CFG.Prototype07
  local reasons = {}
  if not c.Enabled then table.insert(reasons, getText("IGUI_Sandevistan_Req_Disabled")) return reasons end
  if S.data(player).knows.proto07 then table.insert(reasons, getText("IGUI_Sandevistan_Req_AlreadyKnown")) end
  local reasonEl = skillReason(player, "Electricity", c.Study.MinElectrical, "IGUI_Sandevistan_Req_Elec")
  if reasonEl then table.insert(reasons, reasonEl) end
  if not M.findScrewdriver(player) then table.insert(reasons, getText("IGUI_Sandevistan_Req_Screwdriver")) end
  if not M.militaryDossiersComplete(player) then table.insert(reasons, getText("IGUI_Sandevistan_Req_Dossiers")) end
  return reasons
end

-- (155) T06: guía del estudio del Mk. II (Electricidad).
function M.studyMilGuide(player)
  return BG.check(player, "Electricity", CFG.Prototype07.Study.MinElectrical)
end

-- (155) T06: guiado con libros puede fallar (no aprende el diseño; el implante se desarma igual).
function M.performStudyMil(player, item, forcedFall)
  local c = CFG.Prototype07
  local bg = M.studyMilGuide(player)
  local fail = forcedFall
  if fail == nil then fail = bg.ok and bg.gap > 0 and S.chance(BG.failChance(bg.gap)) end
  local deg = M.itemDegradation(item)
  item:getModData().heatDegradationMultiplier = math.min(CFG.Extraction.MaxDegradation, deg + c.Study.DegradationExtra)
  S.syncItem(player, item, { "heatDegradationMultiplier" })           -- (115) MP
  if fail then
    E.halo(player, getText("IGUI_Sandevistan_StudyFailBook"), 255, 120, 60)
    return
  end
  S.data(player).knows.proto07 = true
  M.syncRecipes(player)
  persist(player)                                                     -- (190) MP: el conocimiento nuevo, guardado ya
  E.halo(player, getText("IGUI_Sandevistan_StudyMilOK"), 80, 220, 255)
end

-- (155) T06: chance del ensamblado del P06 con libros (misma regla que el resto: la del mínimo, menos la pérdida por nivel).
function M.proto06Chance(player)
  local c = CFG.Prototype06
  local chance
  if fa(player) >= c.MinFA then
    chance = S.thresholdValue(c.chance, fa(player)) or 0
  else
    local bg = M.proto06Guide(player)
    chance = (bg.ok and bg.gap > 0) and BG.chanceBelow(S.thresholdValue(c.chance, c.MinFA) or 0, bg.gap, c.BookChanceFloor) or 0
  end
  if c.DossierChanceBonus and M.dossiersComplete(player, c.Dossiers) then chance = math.min(0.98, chance + c.DossierChanceBonus) end   -- (106)
  return chance
end
function M.proto07Chance(player) return S.thresholdValue(CFG.Prototype07.chance, fa(player)) or 0 end

-- Partes de un diseno (c = CFG.Prototype06 | CFG.Prototype07) que el jugador lleva: clave -> item (la primera de cada tipo). v0.1.30 (24).
function M.partItems(player, c)
  c = c or CFG.Prototype06
  local out = {}
  for _, key in ipairs(c.PartOrder) do out[key] = M.find(player, c.Parts[key].item) end
  return out
end

local PART_REQ = { board = "IGUI_Sandevistan_Req_Board", regulator = "IGUI_Sandevistan_Req_Regulator", cell = "IGUI_Sandevistan_Req_Cell",
                  chassis = "IGUI_Sandevistan_Req_Chassis", harness = "IGUI_Sandevistan_Req_LinkHarness" }

-- (155) T06: guía del ensamblado del P06 (First Aid).
function M.proto06Guide(player)
  return BG.check(player, "Doctor", CFG.Prototype06.MinFA)
end

function M.proto06Check(p)
  local c = CFG.Prototype06
  local bgFA = M.proto06Guide(p)
  local faOk = fa(p) >= c.MinFA or (bgFA.ok and bgFA.gap > 0)
  local list = {
    { faOk, faOk and getText("IGUI_Sandevistan_Req_FA", c.MinFA) or bookReason("IGUI_Sandevistan_Req_FA", c.MinFA, bgFA), raw = true },  -- (155) T06
    { M.findScrewdriver(p) ~= nil, "IGUI_Sandevistan_Req_Screwdriver" },
  }
  for _, key in ipairs(c.PartOrder) do
    list[#list + 1] = { M.find(p, c.Parts[key].item) ~= nil, PART_REQ[key] }
  end
  list[#list + 1] = { M.count(p, V.ElectronicsScrap) >= c.ScrapRequired, getText("IGUI_Sandevistan_Req_Scrap", c.ScrapRequired), raw = true }
  list[#list + 1] = { M.count(p, M.T.Compound) >= c.CompoundRequired, "IGUI_Sandevistan_Req_Compound" }
  return list
end

-- Respaldo por menu contextual (si las recetas nativas no cargaron; las partes solo se pueden encontrar). Con la misma regla que la receta:
-- exito = implante con la calidad PROMEDIO de las tres partes; fallo (v0.1.30 (43)) = se pierden el compuesto y los conectores y las tres partes vuelven
-- con FailWear de desgaste de mas. forcedChance solo para el autotest.
function M.performProto06(p, forcedChance)
  local c = CFG.Prototype06
  local RC = SandevistanRecipeCode
  local parts = M.partItems(p, c)
  local chance = forcedChance or M.proto06Chance(p)
  M.consume(p, V.ElectronicsScrap, c.ScrapRequired)
  M.consume(p, M.T.Compound, c.CompoundRequired)
  if not S.chance(chance) then
    for _, item in pairs(parts) do RC.setPartQuality(item, RC.partQuality(item) + (c.FailWear or 0)) end
    E.halo(p, getText("IGUI_Sandevistan_Proto06Fail"), 255, 160, 60)
    return nil
  end
  local q = {}
  for key, item in pairs(parts) do q[key] = RC.partQuality(item); removeItem(item) end
  local quality = RC.finalQuality(q, c)
  local item = M.addItem(p, M.T.Lab, { heatDegradationMultiplier = quality, prototype = "06" }, M.prototypeName("06"))
  E.halo(p, getText("IGUI_Sandevistan_Proto06OK", string.format("%.2f", quality)), 80, 220, 255)
  return item
end

---------------------------------------------------------------------------
-- Antidepresivos vanilla (PillsAntiDep) como tratamiento de la CN
---------------------------------------------------------------------------
function M.applyAntidepressant(player)
  local d = S.data(player)
  local c = CFG.Antidepressant
  local now = S.worldHours()
  d.antidepUntil = math.min(now + c.CapHours, math.max(d.antidepUntil or -1, now) + c.DurationHours)
  if S.hasAnyImplant(d) or d.neuralLoad > 0 then
    E.halo(player, getText("IGUI_Sandevistan_AntidepTaken"), 150, 180, 255)
  end
  persist(player)                                                      -- (190) MP: que el servidor lo guarde ya
end

-- (162) T09: paliativos. Los activa SOLO tomarlos (ISTakePillAction). Las recetas y la cirugía a ciegas también gastan analgésicos:
-- eso no cuenta como paliativo.
function M.applyStopgap(player, id)
  local G = CFG.Stopgaps or {}
  if not G.Enabled then return end
  local d = S.data(player)
  local now = S.worldHours()
  local st = S.stopgap(d)
  if id == "painkiller" then
    local pk = G.Painkiller
    st.painkillerUntil = math.max(st.painkillerUntil or -1, now) + pk.Hours
    st.painkillerDoses = st.painkillerDoses or {}
    table.insert(st.painkillerDoses, now)
    for i = #st.painkillerDoses, 1, -1 do if now - st.painkillerDoses[i] >= 24 then table.remove(st.painkillerDoses, i) end end
    E.halo(player, getText("IGUI_Sandevistan_Stopgap_Painkiller", pk.Hours, math.floor((1 - S.stopgapPainkillerMult(d, now)) * 100 + 0.5)), 150, 200, 255)
  elseif id == "sleeping" then
    local sl = G.Sleeping
    st.sleepingUntil = math.max(st.sleepingUntil or -1, now) + (sl.Hours or 12)
    E.halo(player, getText("IGUI_Sandevistan_Stopgap_Sleeping", (sl.Hours or 12)), 150, 200, 255)
  elseif id == "beta" then
    local be = G.Beta
    st.betaUntil = math.max(st.betaUntil or -1, now) + be.Hours
    E.halo(player, getText("IGUI_Sandevistan_Stopgap_Beta", be.Hours), 150, 200, 255)
  end
  local N = rawget(_G, "SandevistanNet")
  if N and N.saveState then pcall(N.saveState, player) end
end

-- Qué pastilla es este ítem: "antidep" | "painkiller" | "sleeping" | "beta" | nil.
function M.pillKind(item)
  if not item then return nil end
  local ft = nil
  pcall(function() ft = item:getFullType() end)
  if ft == V.AntiDep then return "antidep" end
  local G = CFG.Stopgaps or {}
  if G.Enabled then
    if ft == (G.Painkiller or {}).Item then return "painkiller" end
    if ft == (G.Sleeping or {}).Item then return "sleeping" end
    if ft == (G.Beta or {}).Item then return "beta" end
  end
  return nil
end

-- Se engancha a la acción vanilla de tomar pastillas (ISTakePillAction.perform/complete: verificado en 42.21).
M.antidepHooked = false
function M.hookAntidep()
  if M.antidepHooked then return end
  local A = rawget(_G, "ISTakePillAction")
  if type(A) ~= "table" then
    S.warnOnce("antidepHook", "ISTakePillAction no existe: se usa la opción propia del menú")
    return
  end
  local function wrap(name)
    local orig = A[name]
    if type(orig) ~= "function" then return false end
    A[name] = function(self, ...)
      local res = orig(self, ...)
      pcall(function()
        if not self._sandePill and self.item and self.character then
          local kind = M.pillKind(self.item)
          if kind then
            self._sandePill = true   -- en SP corren perform y complete: aplicar una vez
            if kind == "antidep" then M.applyAntidepressant(self.character) else M.applyStopgap(self.character, kind) end
          end
        end
      end)
      return res
    end
    return true
  end
  local a = wrap("perform")
  local b = wrap("complete")
  M.antidepHooked = a or b
end
Events.OnGameStart.Add(S.safe("Medical.hookAntidep", M.hookAntidep))

---------------------------------------------------------------------------
-- Dosis
---------------------------------------------------------------------------
M.DOSE_SOUND = { clinical = "SandevistanDoseImmuno", crafted = "SandevistanDoseImmuno", herbal = "SandevistanDoseImmuno" }   -- un solo sonido real para los tres

M.DOSE_TIME = 100        -- v0.1.30 (21): dura lo que el sonido (~2.7 s) para que suene entero mientras se usa

function M.playDoseSound(player, tier) return E.sound(player, M.DOSE_SOUND[tier] or "SandevistanDoseImmuno") end
-- El Black Lace suena igual que los inmunosupresores (es el mismo puff: de ahi salio la prueba del Sandevistan); crafted queda por compatibilidad.
function M.playKerenzikovSound(player, crafted) return E.sound(player, "SandevistanDoseImmuno") end
-- Si se cancela la accion, el sonido se corta (id nil o 0 = no hay nada que cortar). (135) El id es un numero del emisor del personaje o, si el
-- emisor no sono (devuelve 0 con el personaje invisible: modo admin/debug), el FMODAudio del respaldo de E.sound, que se corta con su stop().
function M.stopDoseSound(player, id)
  if not id or id == 0 then return end
  if type(id) == "number" then
    pcall(function() player:getEmitter():stopSound(id) end)
  else
    pcall(function() id:stop() end)
  end
end

-- Hora en que terminaria la cobertura del tier con una dosis mas. (135) Tolerancia: cada dosis que ya hay en la ventana resta duracion.
function M.immunoUntil(d, tier, now)
  local IS = CFG.Immunosuppressant
  local hours = IS[tier].durationHours * (IS.DurationMultiplier or 1) * S.immunoDurationFactor(d, now)
  return math.min(now + IS.CapHours, math.max((d.immuno or {})[tier .. "Until"] or 0, now) + hours)
end

-- (49) Vista previa de una dosis para el menu: { antes, despues, horas de cobertura que quedan, (135) ID antes, ID despues }. Misma cuenta que takeImmuno
-- (sin tirar el dado de la falla casera).
function M.immunoPreview(player, tier)
  local d = S.data(player)
  local t = CFG.Immunosuppressant[tier]
  local now = S.worldHours()
  local before = d.rejection or 0
  local after = tier == "clinical" and 0 or before * (1 - t.instantReduction)
  local idAfter = S.immunodepOn() and S.immunoAfterDose(d, tier, now) or (d.immunodep or 0)
  return before, after, M.immunoUntil(d, tier, now) - now, d.immunodep or 0, idAfter
end

-- (135) La dosis sube la inmunodepresion (antes de registrarla y de extender la cobertura: el piso nuevo lo pone el tier) y el pico de la tanda.
function M.addImmunodep(d, tier, now)
  if not S.immunodepOn() then return end
  if not S.immunoActiveTier(d, now) then d.immunoPeak = 0 end           -- tanda nueva
  d.immunodep = S.immunoAfterDose(d, tier, now)
  d.immunoPeak = math.max(d.immunoPeak or 0, d.immunodep)
  d.immunoWasCovered = true                                             -- el final de esta cobertura lo ve Periodic.immunoTick aunque no haya pasado un tick
end

-- soundPlayed = true cuando la accion ya lo hizo sonar al empezar (el menu); las pruebas lo llaman sin el y suena aca.
function M.takeImmuno(player, item, tier, soundPlayed)
  local d = S.data(player)
  local t = CFG.Immunosuppressant[tier]
  local now = S.worldHours()
  -- v0.1.30 (15): cada unidad trae varias dosis; se gasta una y la unidad se va con la ultima
  if SandevistanRecipeCode.useDose(item) <= 0 then removeItem(item) end
  if not soundPlayed then M.playDoseSound(player, tier) end
  if tier == "crafted" then
    E.addStat(player, "FOOD_SICKNESS", t.Nausea)
    local IM = rawget(_G, "SandevistanImmunodep"); if IM then IM.resnap(player) end    -- (135) la nausea de la dosis no se amplifica
    if S.chance(t.FailChance) then
      d.rejection = d.rejection * (1 - t.instantReduction)
      E.halo(player, getText("IGUI_Sandevistan_DoseFailed"), 255, 160, 60)
      return
    end
  end
  if tier == "clinical" then d.rejection = 0
  else d.rejection = d.rejection * (1 - t.instantReduction) end
  M.addImmunodep(d, tier, now)                                           -- (135)
  d.immuno[tier .. "Until"] = M.immunoUntil(d, tier, now)                -- (135) con la tolerancia de las dosis anteriores
  S.immunoLogDose(d, now)
  d.immunoReboundUntil = -1                                              -- (135) una dosis nueva corta el rebote (vuelve la cobertura)
  if tier == "herbal" then d.herbalToxicity = math.min(100, d.herbalToxicity + t.toxicityPerDose) end
  E.halo(player, getText("IGUI_Sandevistan_DoseTaken"), 120, 200, 255)
  if SandevistanNet then SandevistanNet.saveState(player) end     -- (135) MP: la cobertura y la inmunodepresion nuevas, guardadas ya
end

function M.takeKerenzikov(player, item, crafted, soundPlayed)
  -- (119) tres dosis por unidad, como los inmunosupresores: se gasta una y la unidad se va con la ultima
  if SandevistanRecipeCode.useDose(item) <= 0 then removeItem(item) end
  if not soundPlayed then M.playKerenzikovSound(player, crafted) end     -- autoinyector militar / dosis casera
  local dur = Kerenzikov.take(player, crafted)
  E.addStat(player, "ENDURANCE", CFG.Kerenzikov.StaminaBoost)      -- v0.1.26: buff de resistencia para escapar
  E.halo(player, getText("IGUI_Sandevistan_KereTaken", math.floor(dur + 0.5)), 255, 200, 80)
  if SandevistanNet then SandevistanNet.saveState(player) end     -- (114) MP: que el servidor guarde la dosis ya (si no, se perdia al reiniciar)
end

---------------------------------------------------------------------------
-- Conocimiento y síntesis (acciones Lua en v0.1; ver 06)
---------------------------------------------------------------------------
function M.knows(player, recipe)
  local d = S.data(player)
  if recipe == "crafted" and CFG.Immunosuppressant.CraftedRecipeKnown then return true end
  if recipe == "proto06" and not CFG.Prototype06.Enabled then return false end
  if recipe == "proto07" and not CFG.Prototype07.Enabled then return false end
  if recipe == "firmware" then                       -- (85) el chip virgen y el terminal los sabe quien tiene (o tuvo) un implante; con FirmwareAllKnown, todos
    return CFG.Firmware.Enabled ~= false and (d.knows.firmware == true or CFG.Firmware.AllKnown == true or S.hasAnyImplant(d))
  end
  if recipe == "herbal" then
    local herbalist = false
    pcall(function() herbalist = player:hasTrait(CharacterTrait.HERBALIST) end)
    return herbalist or d.knows.herbal == true or player:getPerkLevel(Perks.PlantScavenging) >= CFG.Crafting.HerbalMinForaging     -- (30): tambien la ensena el cuaderno
  end
  if recipe == "compound" then return d.knows.compound == true or d.knows.crafted == true or CFG.Immunosuppressant.CraftedRecipeKnown == true end   -- (25): con la opcion de sandbox tambien se sabe el compuesto (el casero lo pide)   -- (21): el rasgo Aprendiz de ripperdoc solo sabia el compuesto; el cuaderno da los dos
  return d.knows[recipe] == true
end

local MORTARS = { V.Mortar, V.MortarCeramic }

-- Cada receta: requisitos (lista de { check, textKey }) y resultado.
M.Recipes = {
  crafted = {
    label = "IGUI_Sandevistan_Craft_Crafted", knowledge = "crafted",
    check = function(p) return {
      { M.totalUses(p, V.Painkillers) >= CFG.Crafting.Cost.CraftedPills, "IGUI_Sandevistan_Req_Painkillers2" },
      { M.hasUsesOfAny(p, DISINFECT, 1), "IGUI_Sandevistan_Req_Disinfectant" },
      { M.find(p, M.T.Compound) ~= nil, "IGUI_Sandevistan_Req_Compound" } } end,
    perform = function(p)
      M.consume(p, V.Painkillers, CFG.Crafting.Cost.CraftedPills); M.consumeFirstOf(p, DISINFECT, 1); M.consume(p, M.T.Compound, 1)
      M.addItem(p, M.T.Crafted) end,
  },
  compound = {
    label = "IGUI_Sandevistan_Craft_Compound", knowledge = "compound",
    check = function(p) return {
      { M.totalUses(p, V.Painkillers) >= CFG.Crafting.Cost.CompoundPills, "IGUI_Sandevistan_Req_Painkillers5" },
      { M.hasUsesOfAny(p, DISINFECT, 1), "IGUI_Sandevistan_Req_Disinfectant" },
      { M.hasUsesOfAny(p, { V.Coldpack, V.BakingSoda }, 1), "IGUI_Sandevistan_Req_ColdOrSoda" },
      { M.findAny(p, MORTARS) ~= nil, "IGUI_Sandevistan_Req_Mortar" } } end,
    perform = function(p)
      M.consume(p, V.Painkillers, CFG.Crafting.Cost.CompoundPills); M.consumeFirstOf(p, DISINFECT, 1)
      M.consumeFirstOf(p, { V.Coldpack, V.BakingSoda }, 1)
      M.addItem(p, M.T.Compound) end,
  },
  herbal = {
    label = "IGUI_Sandevistan_Craft_Herbal", knowledge = "herbal",
    check = function(p) return {
      { M.count(p, V.WildGarlic) >= 2, "IGUI_Sandevistan_Req_Garlic" },
      { M.count(p, V.BlackSage) >= 2 or M.count(p, V.Comfrey) >= 2, "IGUI_Sandevistan_Req_SageComfrey" },
      { M.hasUsesOfAny(p, ALCOHOL, 1), "IGUI_Sandevistan_Req_Alcohol" },
      { M.findAny(p, MORTARS) ~= nil, "IGUI_Sandevistan_Req_Mortar" } } end,
    perform = function(p)
      M.consume(p, V.WildGarlic, 2)
      if M.count(p, V.BlackSage) >= 2 then M.consume(p, V.BlackSage, 2) else M.consume(p, V.Comfrey, 2) end
      M.consumeFirstOf(p, ALCOHOL, 1)
      M.addItem(p, M.T.Herbal) end,
  },
  kerenzikov = {
    label = "IGUI_Sandevistan_Craft_Kerenzikov", knowledge = "kerenzikov",
    check = function(p) return {
      { M.totalUses(p, V.Painkillers) >= 1, "IGUI_Sandevistan_Req_Painkillers" },
      { M.totalUses(p, V.Caffeine) >= 1, "IGUI_Sandevistan_Req_Caffeine" },
      { M.hasUsesOfAny(p, ALCOHOL, 1), "IGUI_Sandevistan_Req_Alcohol" } } end,
    perform = function(p)
      M.consume(p, V.Painkillers, 1); M.consume(p, V.Caffeine, 1); M.consumeFirstOf(p, ALCOHOL, 1)
      M.addItem(p, M.T.KereCrafted) end,
  },
}
M.Recipes.proto06 = {
  label = "IGUI_Sandevistan_Craft_Proto06", knowledge = "proto06", time = CFG.Prototype06.Time,
  chance = function(p) return M.proto06Chance(p) end,
  check = function(p) return M.proto06Check(p) end,
  perform = function(p) M.performProto06(p) end,
}
M.RecipeOrder = { "compound", "crafted", "herbal", "kerenzikov", "proto06" }
-- v0.1.30 (24): las tres partes del P06 son recetas nativas que ensena el mismo conocimiento (el diseno estudiado): no tienen respaldo por menu
-- (solo la ensenanza y el reporte las miran).
for _, key in ipairs(CFG.Prototype06.PartOrder) do M.Recipes[key] = { knowledge = "proto06" } end
-- v0.1.30 (43): Prototipo 07 (partes, ensamblado) y redaccion de planos: solo la ensenanza (las recetas son nativas, sin respaldo por menu)
for _, key in ipairs(CFG.Prototype07.PartOrder) do M.Recipes[key .. "07"] = { knowledge = "proto07" } end
M.Recipes.proto07 = { knowledge = "proto07" }
M.Recipes.proto07h = { knowledge = "proto07" }                -- (122) el mismo ensamblado con un Black Lace casero entero
M.Recipes.chip07 = { knowledge = "proto07" }
M.Recipes.plan06 = { knowledge = "proto06" }
M.Recipes.plan07 = { knowledge = "proto07" }
M.Recipes.fwchip = { knowledge = "firmware" }          -- (85) chip de firmware virgen: solo la ensenanza (receta nativa, sin respaldo por menu)
M.SyncOrder = { "compound", "crafted", "herbal", "kerenzikov", "proto06", "board", "regulator", "cell", "chassis", "harness", "plan06",
                "proto07", "proto07h", "board07", "regulator07", "cell07", "chassis07", "harness07", "chip07", "plan07", "fwchip" }

---------------------------------------------------------------------------
-- Recetas nativas (v0.1.30 (15)): scripts/Sandevistan_recipes.txt. Estan en el menu de crafteo del juego; el menu contextual
-- de arriba (M.Recipes) queda solo como respaldo si el juego no las cargo.
---------------------------------------------------------------------------
function M.nativeRecipe(key)
  local r = nil
  pcall(function() r = getScriptManager():getCraftRecipe(CFG.Crafting.Recipes[key]) end)
  return r
end

function M.nativeRecipesLoaded()
  if M._nativeOk == nil or M._nativeAt ~= S.worldHours() then
    M._nativeOk = M.nativeRecipe("compound") ~= nil
    M._nativeAt = S.worldHours()
  end
  return M._nativeOk
end

-- Nombre pelado de una receta ("Sandevistan.MakeSyntheticCompound" -> "MakeSyntheticCompound"). v0.1.30 (22): el juego lleva la lista de recetas
-- conocidas por el nombre pelado (es lo que ponen los libros en LearnedRecipes y lo que traduce Recipes.json); con el nombre completo la
-- receta figuraba "no aprendida" en el menu de crafteo aunque el mod la diera por sabida.
function M.bareName(full) return (tostring(full):match("([^%.]+)$")) end

-- Olvida una receta nativa (la lista de recetas conocidas del jugador es una List<String> de Java). Saca el nombre pelado y el completo.
function M.forgetRecipe(player, name)
  local ok = pcall(function()
    local list = player:getKnownRecipes()
    list:remove(M.bareName(name)); list:remove(name)
  end)
  if S.isMPClient() then sendClientCommand(player, "Sandevistan", "recipes", { forget = M.bareName(name) }) end   -- (115)
  if M.serverKnew then M.serverKnew[name] = nil end
  return ok
end

function M.recipeKnown(player, name)
  local known = false
  pcall(function() known = player:isRecipeActuallyKnown(M.bareName(name)) == true end)
  return known
end

-- Deja las recetas nativas del jugador iguales a lo que sabe el mod (cuaderno, informe, manual, rasgos, sandbox) y al reves: si el juego ya la
-- sabe (la ensenio un libro nativo) el mod la da por conocida. NeedToBeLearn las oculta hasta entonces. Solo se OLVIDA lo que el mod no da por
-- sabido Y se pide `strict` (la autoprueba, al terminar, repone `d.knows` y tiene que quitar lo que ensenio); sin `strict` lo que el juego ya sabe
-- (libros nativos, otro mod) se adopta en `d.knows`. Devuelve la lista de las que aprendio en esta llamada.
function M.syncRecipes(player, strict)
  local learned = {}
  -- (115) MP: la lista de recetas conocidas la guarda el servidor y el crafteo nativo se valida alla; learnRecipe en el cliente no le llega
  -- (SyncPlayerFields va solo del servidor al cliente). Se le pide que aprenda las que el mod da por sabidas.
  local T = rawget(_G, "SandevistanTraits")
  local toServer = (S.isMPClient() and (not T or not T.serverKnows or T.serverKnows(player))) and {} or nil   -- recien cuando el servidor conoce al jugador
  local d = S.data(player)
  for _, key in ipairs(M.SyncOrder) do
    local rc = M.Recipes[key]
    local name = CFG.Crafting.Recipes[key]
    if name then
      local known = M.recipeKnown(player, name)
      if M.knows(player, rc.knowledge) then
        if toServer and not (M.serverKnew and M.serverKnew[name]) then toServer[#toServer + 1] = M.bareName(name) end
        if not known then
          pcall(function() player:learnRecipe(M.bareName(name)) end)
          pcall(function() player:learnRecipe(name) end)                 -- por si el juego busca el nombre completo
          known = M.recipeKnown(player, name)
          if known then learned[#learned + 1] = key end
          M.learnResult = M.learnResult or {}
          M.learnResult[key] = known
        end
      elseif known and strict then
        M.forgetRecipe(player, name)
        M.learnResult = M.learnResult or {}
        M.learnResult[key] = "olvidada"
      elseif known then
        d.knows[rc.knowledge] = true                                      -- la ensenio un libro nativo
      end
    end
  end
  if toServer and #toServer > 0 then
    sendClientCommand(player, "Sandevistan", "recipes", { learn = table.concat(toServer, ",") })
    M.serverKnew = M.serverKnew or {}
    for _, key in ipairs(M.SyncOrder) do local n = CFG.Crafting.Recipes[key]; if n and M.knows(player, M.Recipes[key].knowledge) then M.serverKnew[n] = true end end
    persist(player)                                                   -- (190) MP: las recetas aprendidas, guardadas ya
  end
  return learned
end

-- Libros nativos: al terminar la lectura el mod anota lo aprendido, muestra el texto de la nota y sincroniza.
M.BOOK_KNOWS = { [M.T.NotebookBook] = { "crafted", "herbal" }, [M.T.KereBook] = { "kerenzikov" },
                 [M.T.Blueprint06] = { "proto06" }, [M.T.Blueprint07] = { "proto07" } }        -- (43): los planos ensenan el diseno       -- (30): el cuaderno tambien ensena la tintura herbolaria
M.bookHooked = false
function M.hookBooks()
  if M.bookHooked then return end
  local A = rawget(_G, "ISReadABook")
  if type(A) ~= "table" or type(A.perform) ~= "function" then
    S.warnOnce("bookHook", "ISReadABook no existe: los libros nuevos solo ensenan por LearnedRecipes")
    return
  end
  local orig = A.perform
  A.perform = function(self, ...)
    local res = orig(self, ...)
    pcall(function()
      local ft = self.item and self.item:getFullType()
      local key = ft and M.BOOK_KNOWS[ft]
      if key and self.character and not self._sandeBook then
        self._sandeBook = true
        for _, k in ipairs(key) do S.data(self.character).knows[k] = true end
        M.syncRecipes(self.character)
        local MN = rawget(_G, "SandevistanMenus")
        if MN and MN.showText then
          if ft == M.T.NotebookBook then MN.showText(self.character, getText("IGUI_Sandevistan_NotebookTitle"), getText("IGUI_Sandevistan_NotebookText"), nil, nil, "paper")
          elseif ft == M.T.Blueprint06 then MN.showText(self.character, getText("IGUI_Sandevistan_Blueprint06Title"), getText("IGUI_Sandevistan_Blueprint06Text"), nil, nil, "student")
          elseif ft == M.T.Blueprint07 then MN.showText(self.character, getText("IGUI_Sandevistan_Blueprint07Title"), getText("IGUI_Sandevistan_Blueprint07Text"), nil, nil, "military")
          else MN.showText(self.character, getText("IGUI_Sandevistan_KereNotesTitle"), getText("IGUI_Sandevistan_KereNotesText"), nil, nil, "military") end
        end
      end
    end)
    return res
  end
  M.bookHooked = true
end
Events.OnGameStart.Add(S.safe("Medical.hookBooks", M.hookBooks))

Events.OnGameStart.Add(S.safe("Medical.syncRecipesStart", function()
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p then M.syncRecipes(p) end
  end
end))
Events.EveryOneMinute.Add(S.safe("Medical.syncRecipes", function()
  for idx = 0, getNumActivePlayers() - 1 do
    local p = getSpecificPlayer(idx)
    if p and not p:isDead() then
      M.syncRecipes(p)
      if S.hasAnyImplant(S.data(p)) then M.giveGuide(p) end          -- reintento por minuto: en MP la guia se crea cuando el servidor ya conoce al jugador
    end
  end
end))

-- Tipos que muestran el submenú de síntesis al hacer clic derecho.
M.CraftTriggers = {
  [M.T.Compound] = true, [V.Mortar] = true, [V.MortarCeramic] = true, [V.Painkillers] = true,
  [V.Caffeine] = true, [V.WildGarlic] = true, [V.BlackSage] = true, [V.Comfrey] = true,
  [M.T.NotebookBook] = true, [M.T.KereBook] = true,
}
-- Solo abren el submenú si el jugador ya conoce la receta (evita ruido en ítems vanilla comunes).
M.CraftTriggersIfKnown = {
  [V.ElectronicsScrap] = "proto06", [V.Screwdriver] = "proto06",
  [M.T.Lab] = "proto06", [M.T.P04] = "proto06",
}

---------------------------------------------------------------------------
-- (122) Crafteo en multijugador: el servidor arma el implante o la parte pero no tiene los textos IGUI_; manda "crafted" y aca se ponen el nombre
-- (en el idioma de quien fabrico), la marca del diseno y el aviso, y se le devuelven al servidor (S.syncItem). El item puede llegar un poco despues
-- que el comando: se reintenta unos segundos.
---------------------------------------------------------------------------
M.craftedQueue = {}

local function applyCrafted(player, args)
  if args.kind == "bookfail" then                                    -- (156) T07: crafteo guiado con libros que salió mal
    E.halo(player, getText("IGUI_Sandevistan_BookFail"), 255, 120, 60)
    return true
  end
  if args.kind == "fail" then
    E.halo(player, getText("IGUI_Sandevistan_Proto" .. tostring(args.proto) .. "Fail"), 255, 160, 60)
    return true
  end
  local id = tonumber(args.id)
  if not id then return true end
  local item = nil
  pcall(function() item = player:getInventory():getItemWithIDRecursiv(id) end)
  if not item then return false end
  local q = tonumber(args.q)
  if args.kind == "part" then
    if q then SandevistanRecipeCode.setPartQuality(item, q) end     -- pone el nombre con la calidad y lo sincroniza
  elseif args.kind == "proto" and type(args.proto) == "string" then
    local md = item:getModData()
    md.prototype = args.proto
    if q then md.heatDegradationMultiplier = q end
    S.try("setName", function() item:setName(M.prototypeName(args.proto)); item:setCustomName(true) end)
    S.syncItem(player, item, { "prototype", "heatDegradationMultiplier" })
    if q then E.halo(player, getText("IGUI_Sandevistan_Proto" .. args.proto .. "OK", string.format("%.2f", q)), 80, 220, 255) end
  end
  return true
end

local function craftedTick()
  local player = getSpecificPlayer(0)
  if not player or #M.craftedQueue == 0 then return end
  local now = S.realMs()
  for i = #M.craftedQueue, 1, -1 do
    local e = M.craftedQueue[i]
    if now >= e.next then
      if applyCrafted(player, e.args) or now > e.untilMs then table.remove(M.craftedQueue, i)
      else e.next = now + 250 end
    end
  end
end

SandevistanNet.handlers.crafted = function(args)
  if type(args) ~= "table" then return end
  local player = getSpecificPlayer(0)
  if player and applyCrafted(player, args) then return end
  M.craftedQueue[#M.craftedQueue + 1] = { args = args, next = S.realMs() + 250, untilMs = S.realMs() + 5000 }
end
Events.OnTick.Add(S.safe("Medical.craftedTick", craftedTick))

return M
