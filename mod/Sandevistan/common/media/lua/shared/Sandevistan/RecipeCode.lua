-- Sandevistan / RecipeCode (shared): funciones OnCreate de las recetas nativas (scripts/Sandevistan_recipes.txt) y dosis múltiples.
-- Las recetas son craftRecipe del juego (aparecen en el menú de crafteo). Lo que un script no puede expresar va acá:
--   * dosis de los inmunosupresores (items drenables del juego);
--   * los Prototipos 06 y 07 tienen tirada de éxito (por First Aid): si falla, se quita el implante creado y las partes vuelven algo gastadas.
-- El script llama por nombre: OnCreate = SandevistanRecipeCode.<función>(data, character) con data = CraftRecipeData.
-- Solo usa Core/Config (nada del cliente), así que también sirve en un servidor.
require "Sandevistan/Core"
require "Sandevistan/BookGuide"

local CFG = SandevistanConfig
local S = Sandevistan
local BG = SandevistanBookGuide

SandevistanRecipeCode = {}
local RC = SandevistanRecipeCode

---------------------------------------------------------------------------
-- (155) T07 paso 0: OnTest de las recetas nativas guiables. El juego llama CraftRecipe.OnTestItem(item, character) por cada ítem candidato
-- del panel de crafteo, sin decir de qué receta: por eso va una función por receta, generada desde CFG.BookGuide.Recipes. Sin el nivel y con
-- los libros de la skill, la receta queda disponible; sin nivel ni libros, no. La decisión final (y el fallo con pérdida de material) la toma
-- el OnCreate. Si no hay personaje (el servidor en algún camino), devuelve true: la valida el OnCreate.
---------------------------------------------------------------------------
function RC.guideOk(character, name)
  if not character then return true end
  local req = CFG.BookGuide.Recipes and CFG.BookGuide.Recipes[name]
  if not req then return true end
  local BG = rawget(_G, "SandevistanBookGuide")
  if not BG then return true end
  return BG.checkAll(character, req).ok
end

for name in pairs(CFG.BookGuide.Recipes or {}) do
  RC["guide_" .. name] = function(item, character) return RC.guideOk(character, name) end
end

---------------------------------------------------------------------------
-- Dosis múltiples (inmunosupresores)
--   Los items (…Pack) son DRENABLES del juego, 3 usos (UseDelta 0.3333): el juego muestra la barra y consume los usos.
---------------------------------------------------------------------------
local function isDrainable(item)
  local f = rawget(_G, "instanceof")
  return f ~= nil and item ~= nil and f(item, "DrainableComboItem") == true
end
RC.isDrainable = isDrainable

-- Dosis que le quedan a un item. Un item que no es drenable (no deberia haber ninguno) cuenta como una sola dosis.
function RC.dosesLeft(item)
  if not isDrainable(item) then return 1 end
  -- getCurrentUsesFloat() es la fraccion que queda del item (1.0 = lleno, lo midio la prueba completa); los usos son fraccion / UseDelta
  local n = nil
  local okF, f = pcall(item.getCurrentUsesFloat, item)
  local okD, ud = pcall(item.getUseDelta, item)
  if okF and okD and type(f) == "number" and type(ud) == "number" and ud > 0 then n = math.floor(f / ud + 0.05) end
  if n == nil then local okU, u = pcall(item.getCurrentUses, item); if okU then n = u end end
  return math.max(0, n or 0)
end

local function baseName(item)
  local md = item:getModData()
  if md.sandeBaseName then return md.sandeBaseName end
  local name = nil
  pcall(function() name = getItemNameFromFullType(item:getFullType()) end)
  if not name or name == "" or name == item:getFullType() then pcall(function() name = item:getName() end) end
  md.sandeBaseName = name
  return name
end

-- Gasta una dosis: devuelve las que quedan.
function RC.useDose(item)
  if not isDrainable(item) then return 0 end
  S.serverUse(nil, item, "use")                                               -- (115) MP: la dosis se gasta tambien en el servidor
  -- Use(bCrafting, bInContainer, bNeedSync). (122) En un cliente de MP va SIN sincronizar: con bNeedSync el cliente manda su propio SyncItemFields
  -- (verificado en el jar: InventoryItem.syncItemFields envia desde el cliente) y el servidor, que ademas recibe "consume", gastaba dos dosis.
  local sync = not S.isMPClient()
  if not pcall(item.Use, item, false, false, sync) then pcall(item.Use, item) end
  return RC.dosesLeft(item)
end

---------------------------------------------------------------------------
-- OnCreate de las recetas
---------------------------------------------------------------------------
local function eachCreated(data, fn)
  local list = nil
  pcall(function() list = data:getAllCreatedItems() end)
  if not list then return end
  for i = list:size() - 1, 0, -1 do
    local item = list:get(i)
    if item then fn(item, list) end
  end
end

local function give(character, fullType, n)
  local last = nil
  for _ = 1, n or 1 do last = S.giveItem(character:getInventory(), fullType) end
  return last
end

-- (122) Multijugador: el OnCreate de las recetas corre en el SERVIDOR, que no carga los textos IGUI_ (getText devolvia la clave: el P06 salia
-- llamado "IGUI_Sandevistan_ItemName_P06"). Alla no se ponen nombres ni avisos: se le manda al cliente que fabrico (comando "crafted") lo que
-- hace falta para ponerlos con su idioma; el cliente los pone y los devuelve al servidor (S.syncItem). En SP y en el cliente, como siempre.
local function onServer() return isServer() and not isClient() end
local function notify(character, args)
  if character and sendServerCommand then pcall(sendServerCommand, character, "Sandevistan", "crafted", args) end
end
local function itemId(item)
  local id = nil
  pcall(function() id = item:getID() end)
  return id
end

local function perk(character, name)
  local level = 0
  pcall(function() level = character:getPerkLevel(Perks[name]) end)
  return level
end

---------------------------------------------------------------------------
-- Partes de los prototipos (v0.1.30 (24), generalizado en (43)): placa neural, regulador termico y celda de energia. Cada una se fabrica con su receta
-- y guarda en el item la calidad (md.partQuality = degradacion que aporta; menor es mejor) segun el nivel de quien la armo. El implante sale con el
-- promedio. Hay dos juegos de partes: las del P06 (CFG.Prototype06, implante de laboratorio) y las del P07 (CFG.Prototype07, replica militar).
---------------------------------------------------------------------------
local DESIGNS = { "Prototype06", "Prototype07" }       -- nombres de las tablas de Config

-- Tabla de Config del diseno al que pertenece un item de parte (nil si no es una parte) y la clave de la parte (board | regulator | cell).
function RC.partDesign(fullType)
  for _, name in ipairs(DESIGNS) do
    local c = CFG[name]
    if c then
      for key, def in pairs(c.Parts) do
        if def.item == fullType then return c, key end
      end
    end
  end
  return nil
end

function RC.partKey(fullType)
  local _, key = RC.partDesign(fullType)
  return key
end

function RC.gradeOf(q)
  for _, g in ipairs(CFG.Prototype06.Grades) do
    if q <= g[1] then return g[2] end
  end
  return "Crude"
end

-- Calidad de una parte: la marca del item; sin marca (encontrada en el mundo) vale DefaultPartQuality.
function RC.partQuality(item)
  local md = item and item:getModData()
  local c = item and RC.partDesign(item:getFullType())
  return (md and tonumber(md.partQuality)) or (c and c.DefaultPartQuality) or CFG.Prototype06.DefaultPartQuality
end

-- Degradacion que aporta una parte de la clave `key` armada por `character`. c = tabla de Config del diseno (por defecto el P06).
function RC.partQualityFor(key, character, c)
  c = c or CFG.Prototype06
  local def = c.Parts[key]
  if def.fixed then return def.fixed end                                    -- (122) parte sin habilidad (el chasis)
  return S.thresholdValue(c.PartQuality, perk(character, def.perk) + (def.bonus or 0)) or c.DefaultPartQuality
end

-- Marca la calidad y la muestra en el nombre: "Neural Interface Board (Fine)".
function RC.setPartQuality(item, q, character)
  if not item then return end
  item:getModData().partQuality = q
  if onServer() then notify(character, { kind = "part", id = itemId(item), q = q }); return end     -- (122) el nombre lo pone el cliente
  local name = baseName(item)
  if not name then return end
  local grade = RC.gradeOf(q)
  pcall(function()
    item:setName(string.format("%s (%s)", name, getText("IGUI_Sandevistan_PartGrade_" .. grade)))
    item:setCustomName(true)
  end)
  S.syncItem(nil, item, { "partQuality" })                                 -- (115) MP: si lo cambio el cliente (desgaste al fallar), que lo sepa el servidor
end

-- Promedio de las partes (cinco desde la (68)) (una faltante = valor por defecto), en degradacion: nunca menos de 1.0. Sin piso de desgaste: con partes perfectas sale 1.0.
function RC.finalQuality(parts, c)
  c = c or CFG.Prototype06
  local sum = 0
  for _, key in ipairs(c.PartOrder) do sum = sum + (parts[key] or c.DefaultPartQuality) end
  return math.max(1.0, math.floor(sum / #c.PartOrder * 100 + 0.5) / 100)
end

---------------------------------------------------------------------------
-- (156) T07: fallo de un crafteo nativo guiado con libros. Los crafteos que antes no fallaban (partes, chips) ahora pueden salir mal por
-- debajo del nivel: se pierde el ítem creado y vuelve RefundShare de cada material consumido (sin drenables ni fluidos). El aviso lo pone el
-- cliente (notify "bookfail") o el halo en SP. La decisión la toma el OnCreate, que en MP corre en el servidor.
---------------------------------------------------------------------------
-- getFluidContainerFromSelfOrWorldItem: es la que existe en 42.21 (getFluidContainer no está en InventoryItem; verificado con javap)
local function isFluid(item)
  local ok, fc = pcall(function() return item:getFluidContainerFromSelfOrWorldItem() end)
  return ok and fc ~= nil
end

function RC.refundFailedCraft(data, character)
  eachCreated(data, function(item)
    local cont = item:getContainer()
    if cont then cont:DoRemoveItem(item) end
  end)
  local list, counts, order = nil, {}, {}
  pcall(function() list = data:getAllConsumedItems() end)
  if list then
    for i = 0, list:size() - 1 do
      local it = list:get(i)
      local ft = it and it:getFullType()
      if ft and not isDrainable(it) and not isFluid(it) then
        if not counts[ft] then counts[ft] = 0; order[#order + 1] = ft end
        counts[ft] = counts[ft] + 1
      end
    end
  end
  for _, ft in ipairs(order) do
    local n = math.floor(counts[ft] * BG.refundShare())
    if n > 0 then give(character, ft, n) end
  end
  if onServer() then notify(character, { kind = "bookfail" })
  elseif character then pcall(function() HaloTextHelper.addText(character, getText("IGUI_Sandevistan_BookFail"), "", 255, 120, 60) end) end
end

-- Tirada de fallo de una receta guiada. true = falló (ya se devolvió el material y se sacó el ítem creado).
function RC.craftFailed(data, character)
  if not character or not CFG.BookGuide.Enabled then return false end
  local name = nil
  pcall(function() name = data:getRecipe():getName() end)
  local req = BG.recipeReq(name)
  if not req then return false end
  local bg = BG.checkAll(character, req)
  if not bg.ok or (bg.gap or 0) <= 0 then return false end
  local fail = S.chance(BG.failChance(bg.gap))
  if RC.forcedBookFail ~= nil then fail = RC.forcedBookFail == true end        -- solo para el autotest
  if not fail then return false end
  RC.refundFailedCraft(data, character)
  return true
end

-- OnCreate de las recetas guiadas que no tenían uno (los chips): solo la tirada de fallo.
function RC.onCreateGuided(data, character)
  RC.craftFailed(data, character)
end

function RC.onCreatePart(data, character)
  if RC.craftFailed(data, character) then return end                       -- (156) T07: guiado con libros puede perder material
  eachCreated(data, function(item)
    local c, key = RC.partDesign(item:getFullType())
    if key then RC.setPartQuality(item, RC.partQualityFor(key, character, c), character) end
  end)
end

-- Calidad de las partes de este diseno que consumio la receta (clave -> degradacion). Si el juego no deja leerlas queda vacio y valen los valores por defecto.
local function consumedParts(data, c)
  local parts = {}
  local list = nil
  pcall(function() list = data:getAllConsumedItems() end)
  if list then
    for i = 0, list:size() - 1 do
      local it = list:get(i)
      local pc, key = RC.partDesign(it and it:getFullType() or "")
      if key and pc == c and parts[key] == nil then parts[key] = RC.partQuality(it) end
    end
  end
  return parts
end

-- Ensamblado (P06 y P07): la tirada es por FIRST AID (v0.1.30 (43); antes Electrical). Exito: implante marcado con la calidad PROMEDIO de las partes
-- (P06: lab "06"; P07: militar "07"). Falla: se pierde el implante creado y los conectores y el estabilizador (los items ya consumidos por la receta) y
-- las partes VUELVEN con FailWear de desgaste de mas (ya no se quema una al azar: podia ser de otro jugador).
-- (196) recetas nativas de ensamblado -> su tabla de Config: el panel de crafteo muestra esta tirada y no el fallo generico por nivel
RC.AssemblyRecipes = { BuildPrototype06 = "Prototype06", BuildPrototype07 = "Prototype07", BuildPrototype07Homemade = "Prototype07" }

function RC.assemblyChance(character, c)
  local chance = S.thresholdValue(c.chance, perk(character, "Doctor"))
  if not chance then                          -- (156) T07: por debajo del minimo, con los libros de First Aid
    local bg = BG.checkAll(character, { Doctor = c.MinFA })
    if bg.ok and (bg.gap or 0) > 0 then chance = BG.chanceBelow(S.thresholdValue(c.chance, c.MinFA) or 0, bg.gap, c.BookChanceFloor) end
  end
  chance = chance or 0
  if c.DossierChanceBonus and S.dossiersComplete(character, c.Dossiers) then chance = math.min(0.98, chance + c.DossierChanceBonus) end   -- (106) binder de estudiante
  return chance
end

local function assemble(data, character, c, label)
  local ok = S.chance(RC.assemblyChance(character, c))
  if RC.forcedChance ~= nil then ok = S.chance(RC.forcedChance) end                     -- solo para el autotest
  local parts = consumedParts(data, c)
  local nRead = 0
  for _ in pairs(parts) do nRead = nRead + 1 end
  eachCreated(data, function(item)
    if ok then
      local q = RC.finalQuality(parts, c)
      item:getModData().heatDegradationMultiplier = q
      item:getModData().prototype = c.Tag
      if onServer() then notify(character, { kind = "proto", id = itemId(item), proto = c.Tag, q = q })        -- (122) nombre y aviso en el cliente
      else pcall(function() item:setName(getText("IGUI_Sandevistan_ItemName_P" .. c.Tag)); item:setCustomName(true) end) end
      local rec = { ok = true, quality = q, partsRead = nRead, partsTotal = #c.PartOrder }
      RC["last" .. label] = rec
      if RC.forcedChance == nil then RC["real" .. label] = rec; S.log(string.format("ensamblado real %s: exito, calidad %.2f, partes leidas %d/%d", label, q, nRead, #c.PartOrder)) end   -- (54) del crafteo del juego, no de las pruebas
      if not onServer() then pcall(function() HaloTextHelper.addText(character, getText("IGUI_Sandevistan_Proto" .. c.Tag .. "OK", string.format("%.2f", q)), "", 80, 220, 255) end) end
    else
      local cont = item:getContainer()
      if cont then cont:DoRemoveItem(item) end
      for _, key in ipairs(c.PartOrder) do
        RC.setPartQuality(give(character, c.Parts[key].item), (parts[key] or c.DefaultPartQuality) + (c.FailWear or 0), character)
      end
      local rec = { ok = false, partsRead = nRead, partsTotal = #c.PartOrder, wear = c.FailWear }
      RC["last" .. label] = rec
      if RC.forcedChance == nil then RC["real" .. label] = rec; S.log(string.format("ensamblado real %s: fallo, partes leidas %d/%d", label, nRead, #c.PartOrder)) end
      if onServer() then notify(character, { kind = "fail", proto = c.Tag })
      else pcall(function() HaloTextHelper.addText(character, getText("IGUI_Sandevistan_Proto" .. c.Tag .. "Fail"), "", 255, 160, 60) end) end
    end
  end)
end

function RC.onCreateProto06(data, character) assemble(data, character, CFG.Prototype06, "Proto06") end
function RC.onCreateProto07(data, character) assemble(data, character, CFG.Prototype07, "Proto07") end

return RC
