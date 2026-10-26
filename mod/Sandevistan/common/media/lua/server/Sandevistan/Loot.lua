-- Sandevistan / Loot (servidor; en SP corre en el mismo proceso).
-- Suma los ítems del mod a las tablas de distribución de vanilla (loot aleatorio de contenedores).
-- Las tablas se eligen por coincidencia de nombre para no depender de que exista una en concreto.
require "Sandevistan/Config"
require "Items/ProceduralDistributions"

local CFG = SandevistanConfig
local T = "Sandevistan."

local function matches(name, patterns)
  for _, p in ipairs(patterns) do
    if string.find(name, p, 1, true) then return true end
  end
  return false
end

local function addTo(list, patterns, fullType, weight)
  local added = 0
  for name, dist in pairs(list) do
    if type(dist) == "table" and type(dist.items) == "table" and matches(name, patterns) then
      table.insert(dist.items, fullType)
      table.insert(dist.items, weight)
      added = added + 1
    end
  end
  return added
end

function SandevistanRegisterLoot()
  pcall(SandevistanConfig.applySandbox)          -- v0.1.30 (25): dificultad / multiplicadores del sandbox (si SandboxVars todavia no existe no cambia nada)
  local L = CFG.Loot
  if not L or not L.Enabled or not ProceduralDistributions or not ProceduralDistributions.list then return 0 end
  local list, total = ProceduralDistributions.list, 0
  local function add(key, item)
    if not L[key] then return end
    local w = L[key].weight * (key == "Parts" and (L.PartsMultiplier or 1) or 1)
    if key == "Parts" and not CFG.Prototype06.Enabled then w = 0 end         -- sin Prototipo 06 las partes no sirven para nada
    if key == "MilChip" and not CFG.Prototype07.Enabled then w = 0 end       -- (43) ni el microchip sin la replica militar
    if (key == "FwBlank" or key == "FwTerminal" or string.sub(key, 1, 12) == "FwProgrammed") and CFG.Firmware.Enabled == false then w = 0 end     -- (85) ni el chip virgen ni los programados sin firmware
    if w > 0 then total = total + addTo(list, L[key].match, T .. item, w) end
  end
  add("KerenzikovMilitary", "KerenzikovMilitary")
  add("KerenzikovCrafted", "KerenzikovCrafted")
  add("KerenzikovHouse", "KerenzikovCrafted")
  add("Implant", "SandevistanLab")
  add("ImplantSchool", "SandevistanLab")
  add("Compound", "SyntheticCompoundSample")
  add("Parts", "NeuralInterfaceBoard")
  add("Parts", "ThermalRegulator")
  add("Parts", "PowerCell")
  add("Parts", "ImplantChassis")                                                    -- (68) chasis y arnes
  add("Parts", "NeuralLinkHarness")
  add("MilChip", "MilSpecChip")                                                     -- (43) materiales del Prototipo 07
  add("FwTerminal", "FwTerminal")                                                   -- (88) terminal de grabacion: solo tablas militares
  add("FwBlank", "FwBlank")                                                         -- (85) chip de firmware virgen (poco)
  -- (161) T10: libros de guía con el tipo completo (no llevan el prefijo Sandevistan.)
  local B = L.Books
  if B and type(B.items) == "table" and (tonumber(B.weight) or 0) > 0 then
    for _, fullType in ipairs(B.items) do total = total + addTo(list, B.match, fullType, B.weight) end
  end
  for _, id in ipairs(CFG.Firmware.Order) do                                        -- (87) chips ya programados: cada programa terminado donde su hardware lo admite
    local p = CFG.Firmware.Programs[id]
    if p.ready then
      if p.only ~= "military" and p.origin ~= "military" then add("FwProgrammedCivil", "Fw" .. id) end          -- (111) un diseno militar solo sale en el ejercito
      if p.only ~= "lab" then add("FwProgrammedArmy", "Fw" .. id) end
    end
  end
  add("Notebook", "ImmunoSynthesisBook")
  add("KerenzikovNotes", "KerenzikovFormulationBook")
  for n = 1, CFG.Notes.Count do
    add(n <= 15 and "MilitaryNotes" or "Notes", string.format("SandevistanNote%02d", n))
  end
  return total
end

local ok, n = pcall(SandevistanRegisterLoot)
-- (189) C12: el arranque no ensucia la consola publicada (queda en el REPORTE).
if ok then
  local S = rawget(_G, "Sandevistan")
  if S and S.log then S.log("loot: " .. tostring(n) .. " entradas en distribuciones")
  elseif CFG.Debug or (isDebugEnabled and isDebugEnabled()) then print("[Sandevistan] loot: " .. tostring(n) .. " entradas en distribuciones") end
end
