-- Sandevistan / BodyLocations: agrega la ubicación de cuerpo "sandevistan:spine" al grupo "Human".
-- 42.13+: el identificador se registra en media/registries.lua y aquí se crea la ubicación dentro del
-- grupo (BodyLocationGroup:getOrCreateLocation es idempotente, así que se puede repetir sin riesgo).
-- Todo va protegido con pcall: sin la ubicación el mod usa el dibujo 2D de Spine.lua o nada.
require "Sandevistan/Config"

SandevistanBodyLocations = { id = "sandevistan:spine", ok = false, lastError = nil }
local BL = SandevistanBodyLocations

function BL.ensure()
  local okAll, err = pcall(function()
    local loc = ItemBodyLocation.get(ResourceLocation.of(BL.id))
    if not loc then error("identificador no registrado (media/registries.lua)") end
    local group = BodyLocations.getGroup("Human")
    if not group then error("grupo Human inexistente") end
    local okObj = pcall(function() group:getOrCreateLocation(loc) end)
    if not okObj then group:getOrCreateLocation(BL.id) end          -- 42.13 restauró la variante con String
  end)
  BL.ok = okAll
  BL.lastError = (not okAll) and tostring(err) or nil
  return okAll
end

BL.ensure()
-- por si el grupo se reconstruye más tarde (cargar partida, reinicio de ubicaciones)
for _, ev in ipairs({ "OnGameBoot", "OnGameStart", "OnCreatePlayer" }) do
  if Events and Events[ev] then Events[ev].Add(function() BL.ensure() end) end
end

return BL
