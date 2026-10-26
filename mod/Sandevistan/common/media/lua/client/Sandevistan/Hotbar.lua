-- Sandevistan / Hotbar (127): el Black Lace (autoinyector militar y casero) va en el cinturon y su tecla lo inyecta.
-- 1. Los items tienen AttachmentType = BlackLace (scripts/Sandevistan_items.txt). Aca se suma ese tipo a los slots de cinturon de vanilla
--    (ISHotbarAttachDefinition: SmallBeltLeft / SmallBeltRight), en los puntos de enganche del walkie ("Walkie Belt Left/Right" de AttachedLocations.lua):
--    no se toca el archivo vanilla ni el modelo del cuerpo, asi no choca con otros mods del cinturon. El modelo colgado es el StaticModel del item.
-- 2. La tecla del slot (ISHotbar:activateSlot) en vanilla pone el item en la mano; con un Black Lace arranca la accion de inyectarse del menu
--    (SandevistanMenus.injectKerenzikov: sonido, duracion y, en multijugador, la dosis la gasta el servidor). Con la ultima dosis el item se va y el
--    cinturon lo suelta solo.
-- Todo es del cliente: el enganche al cinturon (ISAttachItemHotbar) no lo valida el servidor contra estas definiciones y vanilla sincroniza lo colgado.
require "Hotbar/ISHotbarAttachDefinition"
require "Hotbar/ISHotbar"
require "Sandevistan/Core"

SandevistanHotbar = SandevistanHotbar or {}
local HB = SandevistanHotbar

HB.TYPE = "BlackLace"
HB.ITEMS = { ["Sandevistan.KerenzikovMilitary"] = true, ["Sandevistan.KerenzikovCrafted"] = true }
HB.SLOTS = { SmallBeltLeft = "Walkie Belt Left", SmallBeltRight = "Walkie Belt Right" }

-- Suma el tipo a los slots de cinturon. Idempotente; devuelve cuantos slots lo aceptan.
function HB.installSlots()
  local n = 0
  for _, def in ipairs(ISHotbarAttachDefinition or {}) do
    local loc = def.type and HB.SLOTS[def.type]
    if loc and type(def.attachments) == "table" then
      if def.attachments[HB.TYPE] == nil then def.attachments[HB.TYPE] = loc end
      n = n + 1
    end
  end
  HB.slots = n
  return n
end

function HB.isBlackLace(item)
  local ok, ft = pcall(function() return item:getFullType() end)
  return ok and HB.ITEMS[ft] == true
end

function HB.installActivate()
  if not ISHotbar or type(ISHotbar.activateSlot) ~= "function" or rawget(ISHotbar, "_sandeBlackLace") then return false end
  local orig = ISHotbar.activateSlot
  ISHotbar.activateSlot = function(self, slotIndex, ...)
    local item = self.attachedItems and self.attachedItems[slotIndex]
    local MN = rawget(_G, "SandevistanMenus")
    if item and self.chr and MN and MN.injectKerenzikov and HB.isBlackLace(item) then
      local ok, err = pcall(MN.injectKerenzikov, self.chr, item)
      if ok then return end
      Sandevistan.log("cinturon: no se pudo inyectar el Black Lace: " .. tostring(err))
    end
    return orig(self, slotIndex, ...)
  end
  rawset(ISHotbar, "_sandeBlackLace", true)
  return true
end

-- Ajuste en vivo del modelo colgado (Debug -> Interfaz y visual -> "Black Lace en el cinturon"). Cambia el `attachment walkie_belt_*` de los dos modelos
-- (militar y casero) en memoria; los valores buenos se copian a scripts/Sandevistan_models.txt (HB.describe los escribe en la consola).
HB.MODELS = { "Sandevistan.SandevistanBeltKerenzikovMilitary", "Sandevistan.SandevistanBeltKerenzikovCrafted" }
HB.ATTACH = { left = "walkie_belt_left", right = "walkie_belt_right" }

function HB.attachments(side)
  local out = {}
  for _, name in ipairs(HB.MODELS) do
    local ms, a = nil, nil
    pcall(function() ms = getScriptManager():getModelScript(name) end)
    if not ms then pcall(function() ms = getScriptManager():getModelScript(string.match(name, "%.(.+)$")) end) end
    if ms then pcall(function() a = ms:getAttachmentById(HB.ATTACH[side]) end) end
    if a then out[#out + 1] = a end
  end
  return out
end

-- kind = "offset" | "rotate", axis = 1..3 (x, y, z). Devuelve cuantos modelos cambio.
function HB.nudge(player, side, kind, axis, delta)
  local n = 0
  for _, a in ipairs(HB.attachments(side)) do
    local ok = pcall(function()
      local v = kind == "offset" and a:getOffset() or a:getRotate()
      local x, y, z = v:x(), v:y(), v:z()
      if axis == 1 then x = x + delta elseif axis == 2 then y = y + delta else z = z + delta end
      v:set(x, y, z)
    end)
    if ok then n = n + 1 end
  end
  if player then pcall(function() player:resetModelNextFrame() end) end
  return n
end

function HB.describe(side)
  local a = HB.attachments(side)[1]
  if not a then return "sin enganche " .. tostring(HB.ATTACH[side]) end
  local o, r = a:getOffset(), a:getRotate()
  return string.format("attachment %s { offset = %.4f %.4f %.4f, rotate = %.1f %.1f %.1f, }", HB.ATTACH[side], o:x(), o:y(), o:z(), r:x(), r:y(), r:z())
end

HB.installSlots()
HB.installActivate()
-- por si otro mod rearma las definiciones del cinturon despues de cargar
Events.OnGameStart.Add(function() HB.installSlots() end)

return HB
