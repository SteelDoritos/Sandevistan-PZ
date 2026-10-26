-- Sandevistan / Spine: el implante se ve en la espalda con un modelo 3D: una prenda skineada a la columna
-- (models_X/skinned/clothes/SandevistanSpine*.X) que el mod equipa por Lua al tener el implante. Se replica sola en
-- multijugador. Este archivo la mantiene puesta (SP.update), publica el aspecto del jugador en la red y bloquea sacarla.
require "Sandevistan/Core"
require "Sandevistan/Runtime"
require "Sandevistan/Net"
require "Sandevistan/BodyLocations"

local CFG = SandevistanConfig
local S = Sandevistan
local N = SandevistanNet

SandevistanSpine = {}
local SP = SandevistanSpine

---------------------------------------------------------------------------
-- Modelo 3D (prenda skineada): el mod la equipa al tener implante y la quita al no tenerlo. Si algo
-- falla (ítem inexistente, ubicación de cuerpo no registrada) se desactiva sola.
---------------------------------------------------------------------------
SP.modelFailures = 0
SP.lastSync = {}

function SP.modelEnabled()
  return SP.modelFailures < 3 and (not SandevistanInput or SandevistanInput.getOption("spineModel3D", true))
end

-- Prenda de implante que lleva puesta un jugador (local o remoto), o nil.
function SP.wornSpine(p)
  local found = nil
  pcall(function()
    local worn = p:getWornItems()
    for i = 0, worn:size() - 1 do
      local it = worn:get(i):getItem()
      if it and string.find(it:getFullType(), "^Sandevistan%.SandevistanSpine") then found = it end
    end
  end)
  return found
end

-- Crea la prenda en el inventario del jugador. 42.21 no expone InventoryItemFactory: ItemContainer:AddItem(String)
-- crea la instancia y la agrega; instanceItem(String) crea una suelta (alternativa).
-- (190) C12: en un cliente de multijugador la crea el SERVIDOR (comando "give"); sendAddItemToContainer no hace nada desde un
-- cliente y el ítem quedaría solo en su pantalla. Mientras llega se devuelve "pending" y se reintenta, sin contar como fallo.
SP.pending = {}
local function createItem(p, want)
  if S.isMPClient() and not S.localItems then
    local idx = p:getPlayerNum()
    SP.pending[idx] = SP.pending[idx] or {}
    local now = S.realMs()
    if not SP.pending[idx][want] or now - SP.pending[idx][want] > 2000 then
      SP.pending[idx][want] = now
      S.grantItem(p, want)
    end
    return nil, true
  end
  local inv = p:getInventory()
  local item = nil
  item = S.giveItem(inv, want)
  if type(item) == "boolean" then item = nil end          -- otras sobrecargas de AddItem devuelven boolean
  if item == nil then
    pcall(function()
      local it = instanceItem(want)
      if it then inv:AddItem(it); item = it end
    end)
  end
  return item, false
end

-- (190) En un cliente de MP la prenda la puso el cliente con setWornItem, que no avisa a nadie: el servidor tiene que saber que
-- está puesta para que los demás la vean (y para sacarla bien). El comando lleva solo el id y on/off; el servidor valida el tipo.
local function syncWornNet(p, item, on)
  if not S.isMPClient() or not item then return end
  local id = nil
  pcall(function() id = item:getID() end)
  if id then sendClientCommand(p, "Sandevistan", "spineWorn", { id = id, on = on and true or false }) end
end

-- (190) Quita una prenda que puso el mod. Si la creó el servidor hay que avisarle: `Inventory:Remove` solo la saca del cliente y
-- en el próximo sync volvería (o quedaría duplicada). `sendRemoveItemFromContainer` sí funciona desde un cliente (verificado).
local function takeOff(p, item)
  syncWornNet(p, item, false)
  local ok = pcall(function() p:removeWornItem(item) end)
  local c = nil
  pcall(function() c = item:getContainer() end)
  if c then
    local okRemove = pcall(function() c:DoRemoveItem(item) end)
    if not okRemove then pcall(function() c:Remove(item) end) end      -- respaldo para contenedores que no exponen DoRemoveItem
    if isClient() and rawget(_G, "sendRemoveItemFromContainer") then pcall(sendRemoveItemFromContainer, c, item) end
  else
    pcall(function() p:getInventory():Remove(item) end)
  end
  return ok
end

-- Equipa / quita la prenda según el implante. Devuelve true si todo salió bien (para el diagnóstico).
local function applyWorn(p, want, cur)
  if want and (not cur or cur:getFullType() ~= want) then
    if SandevistanBodyLocations then SandevistanBodyLocations.ensure() end
    if cur then
      local oldLoc = cur:getBodyLocation()
      takeOff(p, cur)
      if isClient() then pcall(function() sendClothing(p, oldLoc, nil) end) end
    end
    -- si el jugador se la sacó, se vuelve a poner la misma (sin fabricar copias)
    local item = nil
    pcall(function() item = p:getInventory():getFirstTypeRecurse(want) end)
    local pending = false
    if not item then item, pending = createItem(p, want) end
    if not item then
      if pending then return "pending" end
      error("no se pudo crear el ítem " .. want .. " (¿se cargó el script? revisar la consola)")
    end
    local loc = item:getBodyLocation()
    if not loc then error("el ítem " .. want .. " no tiene BodyLocation") end
    p:setWornItem(loc, item)
    syncWornNet(p, item, true)
    if isClient() then pcall(function() sendClothing(p, loc, item) end) end
    p:resetModelNextFrame()
    triggerEvent("OnClothingUpdated", p)
  elseif not want and cur then
    local loc = cur:getBodyLocation()
    takeOff(p, cur)
    if isClient() then pcall(function() sendClothing(p, loc, nil) end) end
    p:resetModelNextFrame()
    triggerEvent("OnClothingUpdated", p)
  end
  return true
end

-- ¿lleva una chaqueta/capa que tape la espalda? (por la ubicación de cuerpo de lo que tiene puesto)
function SP.coveredBack(p)
  local covered = false
  pcall(function()
    local worn = p:getWornItems()
    for i = 0, worn:size() - 1 do
      local it = worn:get(i):getItem()
      if it and not string.find(it:getFullType(), "^Sandevistan%.") then
        local loc = string.lower(tostring(it:getBodyLocation()))
        for _, key in ipairs(CFG.Spine.HiddenUnder) do
          if string.find(loc, key, 1, true) then covered = true end
        end
      end
    end
  end)
  return covered
end

-- Ítem que corresponde al estado actual: apagado / encendido / rojo, o ninguno (sin implante o tapado por ropa).
function SP.wantedItem(p, d)
  local base = CFG.Spine.Model[d.variant or ""]
  if not base or SP.coveredBack(p) then return nil end
  local Rt = rawget(_G, "SandevistanRuntime")
  local s = Rt and Rt.session(p) or {}
  local want
  if d.variant == "destroyed" or not s.active then want = base
  elseif s.overdrive or d.cyberpsychosisActive then want = CFG.Spine.ModelRed[d.variant] or CFG.Spine.ModelRed.lab
  else want = CFG.Spine.ModelOn[d.variant] or base end
  return want                                   -- (107) sin "lado B": los modelos hechos a mano ya van en la espalda
end

---------------------------------------------------------------------------
-- (56) La prenda es parte del cuerpo: no se puede sacar ni tirar. Antes el inventario dejaba tirar al suelo (o pasar a otro contenedor) todas las copias que
-- uno quisiera y cada cambio de estado del implante fabricaba una nueva. Se bloquean las acciones de transferir y de sacarse la prenda para esos items, y
-- las copias sueltas que haya en el inventario se borran al sincronizar.
---------------------------------------------------------------------------
function SP.isSpineItem(item)
  local ok, ft = pcall(function() return item:getFullType() end)
  return ok and type(ft) == "string" and string.find(ft, "^Sandevistan%.SandevistanSpine") ~= nil
end

SP.lockNotifiedMs = 0
local function notifyLocked(character)
  local now = S.realMs()
  if now - SP.lockNotifiedMs < 2500 then return end              -- isValid se evalua cada cuadro: un solo aviso cada tanto
  SP.lockNotifiedMs = now
  pcall(function() HaloTextHelper.addText(character, getText("IGUI_Sandevistan_SpineLocked"), "", 255, 160, 60) end)
end

-- (128) ¿la prenda la lleva puesta este personaje? El bloqueo es solo para la propia: antes frenaba cualquier prenda del implante, tambien la de un
-- cadaver o un NPC de otro mod (Project A-Life deja vestir a sus NPCs con ella) y avisaba «es parte de tu cuerpo».
function SP.wornBy(character, item)
  local id = nil
  pcall(function() id = item:getID() end)
  local found = false
  pcall(function()
    local worn = character:getWornItems()
    for i = 0, worn:size() - 1 do
      local it = worn:get(i):getItem()
      if it == item or (id ~= nil and it and it:getID() == id) then found = true end
    end
  end)
  return found
end

SP.lockWraps = 0
function SP.installLock()
  if SP.lockWraps >= 2 then return end
  local n = 0
  for _, className in ipairs({ "ISInventoryTransferAction", "ISUnequipAction" }) do
    local cls = rawget(_G, className)
    if type(cls) == "table" and type(cls.isValid) == "function" then
      local orig = cls.isValid
      cls.isValid = function(self, ...)
        if self and self.item and self.character and SP.isSpineItem(self.item) and SP.wornBy(self.character, self.item)
            and SP.manages(self.character) then
          notifyLocked(self.character); return false
        end
        return orig(self, ...)
      end
      n = n + 1
    end
  end
  if n > 0 then SP.lockWraps = SP.lockWraps + 1 end
end

-- Copias sueltas de la prenda (todas menos la puesta) en el inventario.
function SP.purgeStray(p)
  local inv = p:getInventory()
  local worn = SP.wornSpine(p)
  local wornId = nil
  if worn then pcall(function() wornId = worn:getID() end) end
  local list = nil
  pcall(function() list = inv:getAllEvalRecurse(function(it) return SP.isSpineItem(it) end) end)
  if not list then return 0 end
  local removed = 0
  for i = list:size() - 1, 0, -1 do
    local it = list:get(i)
    local id = nil
    pcall(function() id = it:getID() end)
    if it and (wornId == nil or id ~= wornId) then
      local ok = pcall(function()
        local c = it:getContainer() or inv
        local okRemove = pcall(function() c:DoRemoveItem(it) end)
        if not okRemove then pcall(function() c:Remove(it) end) end
        if isClient() and rawget(_G, "sendRemoveItemFromContainer") then pcall(sendRemoveItemFromContainer, c, it) end
      end)
      if ok then removed = removed + 1 end
    end
  end
  return removed
end

-- (137) ¿el mod maneja la espalda de este personaje? Si tiene implante (también destruido) o si la prenda puesta la puso el mod.
function SP.manages(p, d)
  d = d or S.data(p)
  return d.variant ~= nil or d.spineWorn == true
end

SP.lastWant = {}
function SP.syncWorn(p, force)
  if not SP.modelEnabled() and not force then return end
  local idx = p:getPlayerNum()
  local now = S.realMs()
  local d = S.data(p)
  local want = SP.wantedItem(p, d)
  local changed = SP.lastWant[idx] ~= (want or false)       -- un cambio de estado se aplica al instante
  if not force and not changed and SP.lastSync[idx] and now - SP.lastSync[idx] < CFG.Spine.SyncSeconds * 1000 then return end
  SP.lastSync[idx] = now
  SP.lastWant[idx] = want or false
  local cur = SP.wornSpine(p)
  -- (137) Sin implante y sin una prenda que haya puesto el mod, no se toca nada: una espalda dada por un admin (o para vestir a un NPC de
  -- A-Life) se puede tener, ponerse y tirar. d.spineWorn recuerda que la puso el mod, para sacarla al explantar aunque el estado cambie al recargar.
  if not SP.manages(p, d) then return true end
  local ok, err = pcall(applyWorn, p, want, cur)
  if ok and err == "pending" then return true end          -- (190) el servidor todavía no creó la prenda: se reintenta al próximo tick
  if ok then
    pcall(SP.purgeStray, p)
    if want then d.spineWorn = true elseif not d.variant then d.spineWorn = nil end
  end
  if not ok then
    SP.modelFailures = SP.modelFailures + 1
    SP.lastError = tostring(err)
    S.warnOnce("spineModel", "modelo 3D del implante no disponible: " .. tostring(err))
  else
    SP.modelFailures = 0
    SP.lastError = nil
  end
  return ok, (not ok) and err or nil
end

-- Diagnóstico paso a paso del modelo 3D: lo incluye el REPORTE (sección 'diagnostico del modelo 3D'); sin quiet también escribe en consola con el prefijo [Sandevistan].
-- No debe lanzar errores (el depurador con "Break On Error" se detiene aunque haya pcall): cada método
-- se comprueba antes de llamarlo y los resultados se devuelven como texto.
local function has(obj, name)
  if obj == nil then return false end
  local ok, f = pcall(function() return obj[name] end)
  return ok and f ~= nil
end

local function call(obj, name)
  if not has(obj, name) then return "(sin método " .. name .. ")" end
  local ok, r = pcall(function() return obj[name](obj) end)
  if not ok then return "ERROR " .. tostring(r) end
  if r == nil then return "nil" end
  return tostring(r)
end

function SP.diagnose(p, quiet)
  local out = {}
  local function add(t) out[#out + 1] = t; if not quiet then S.log("modelo 3D: " .. t) end end
  local id = SandevistanBodyLocations and SandevistanBodyLocations.id or "sandevistan:spine"

  -- 1. ubicación de cuerpo
  if rawget(_G, "Registries") and rawget(_G, "ResourceLocation") then
    local ok, r = pcall(function() return Registries.ITEM_BODY_LOCATION:contains(ResourceLocation.of(id)) end)
    add("ubicación " .. id .. " registrada (Registries, media/registries.lua) -> " .. (ok and tostring(r) or ("ERROR " .. tostring(r))))
  else
    add("Registries/ResourceLocation no existen en esta versión del juego")
  end
  if SandevistanBodyLocations then
    local ok = SandevistanBodyLocations.ensure()
    add("BodyLocations.ensure() -> " .. tostring(ok) .. (SandevistanBodyLocations.lastError and (" (" .. SandevistanBodyLocations.lastError .. ")") or ""))
  end

  -- 2. scripts, clothingItem y modelos de cada ítem
  local sm = getScriptManager()
  for _, want in ipairs({ CFG.Spine.Model.lab, CFG.Spine.Model.military }) do
    local it = sm and sm:getItem(want) or nil
    if not it then
      add("script " .. want .. " -> NO EXISTE (revisar Sandevistan_spine.txt y errores de scripts en la consola)")
    else
      add("script " .. want .. " -> ok, tipo=" .. call(it, "getItemType") .. " ubicación=" .. call(it, "getBodyLocation")
          .. " clothingItem=" .. call(it, "getClothingItem"))
      local ci = has(it, "getClothingItemAsset") and it:getClothingItemAsset() or nil
      if not ci then
        add("  clothingItem (XML) NO cargado: revisar GUID en fileGuidTable.xml y la ruta del XML")
      else
        add("  clothingItem cargado: hasModel=" .. call(ci, "hasModel") .. " macho=" .. call(ci, "getMaleModel")
            .. " hembra=" .. call(ci, "getFemaleModel") .. " texturas=" .. call(ci, "getTextureChoices"))
      end
    end
    local inst = nil
    if rawget(_G, "instanceItem") then pcall(function() inst = instanceItem(want) end) end
    add("  instanceItem(" .. want .. ") -> " .. (inst and ("ok, fullType=" .. call(inst, "getFullType") .. " ubicación=" .. call(inst, "getBodyLocation")) or "nil"))
  end

  -- 3. el jugador
  if p then
    local d = S.data(p)
    local w = SP.wornSpine(p)
    add("variante del jugador = " .. tostring(d.variant) .. "; prenda puesta = " .. tostring(w and w:getFullType()))
    local okSync, e = SP.syncWorn(p, true)
    add("syncWorn(forzado) -> " .. tostring(okSync) .. (e and (" " .. tostring(e)) or ""))
    w = SP.wornSpine(p)
    add("prenda puesta ahora = " .. tostring(w and w:getFullType()) .. (w and (" en " .. call(w, "getBodyLocation")) or ""))
    local list = {}
    pcall(function()
      local worn = p:getWornItems()
      for i = 0, worn:size() - 1 do
        local wi = worn:get(i)
        list[#list + 1] = tostring(wi:getItem() and wi:getItem():getFullType()) .. "@" .. tostring(wi:getLocation())
      end
    end)
    add("prendas puestas (" .. #list .. "): " .. table.concat(list, ", "))
  end
  add("fallos acumulados = " .. SP.modelFailures .. "; último error = " .. tostring(SP.lastError))
  return out
end

-- Cada cuadro (lo llama el HUD): mantiene puesta la prenda 3D y publica mi aspecto en multijugador.
function SP.update()
  for i = 0, getNumActivePlayers() - 1 do
    local lp = getSpecificPlayer(i)
    if lp and not lp:isDead() then
      SP.syncWorn(lp)
      local d = S.data(lp)
      N.sendLook(lp, d.variant, d.prototype)
    end
  end
end

SP.installLock()
Events.OnGameStart.Add(SP.installLock)          -- segundo enganche por si las acciones del juego se cargaron despues que este archivo

return SP
