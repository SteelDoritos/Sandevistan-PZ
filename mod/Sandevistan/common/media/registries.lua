-- Sandevistan / registries.lua (B42.13+): se carga antes que todos los scripts y archivos Lua.
-- Aquí se registran los identificadores propios del mod.
--   sandevistan:spine  ubicación de cuerpo del modelo 3D del implante en la espalda
--                      (la usan scripts/Sandevistan_spine.txt y lua/shared/Sandevistan/BodyLocations.lua)
local ok, err = pcall(function() ItemBodyLocation.register("sandevistan:spine") end)
if not ok then print("[Sandevistan] WARN registries.lua: no se pudo registrar sandevistan:spine: " .. tostring(err)) end

-- Rasgos de personaje (creación de personaje): ver lua/shared/Sandevistan/TraitDefs.lua y lua/client/Sandevistan/Traits.lua
for _, id in ipairs({ "sandevistan:special", "sandevistan:chromerejection", "sandevistan:labkit",
                      "sandevistan:ripperdoc", "sandevistan:cyberpsychoprone",
                      "sandevistan:edgerunner", "sandevistan:excorpo", "sandevistan:neurallyunstable",
                      "sandevistan:chromed" }) do
  local ok2, err2 = pcall(function() CharacterTrait.register(id) end)
  if not ok2 then print("[Sandevistan] WARN registries.lua: no se pudo registrar " .. id .. ": " .. tostring(err2)) end
end
