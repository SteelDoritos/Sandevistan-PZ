-- Sandevistan / TraitDefs (shared): definiciones de los rasgos de creación de personaje.
-- Se hacen por Lua (como DoTraits de vanilla) y no por script para que un error acá NO impida cargar el juego.
-- Los ids se registran en media/registries.lua. Textos: UI_trait_* en Translate/*/UI.json.
-- (154) Costos de las decisiones del 22/10 (D2, D3, D4): Instalador de callejón 10 (antes 15), Aprendiz de ripperdoc 7 (antes 6) y
-- Neuralmente inestable -4 (antes -3).
local DEFS = {
  { id = "sandevistan:special", cost = 7, name = "UI_trait_SandevistanSpecial", desc = "UI_trait_SandevistanSpecialDesc",
    xp = { { "SandevistanAdaptation", 1 } } },
  { id = "sandevistan:chromerejection", cost = -6, name = "UI_trait_SandevistanChrome", desc = "UI_trait_SandevistanChromeDesc" },
  { id = "sandevistan:labkit", cost = 10, name = "UI_trait_SandevistanLabKit", desc = "UI_trait_SandevistanLabKitDesc" },
  { id = "sandevistan:ripperdoc", cost = 7, name = "UI_trait_SandevistanRipperdoc", desc = "UI_trait_SandevistanRipperdocDesc",
    xp = { { "Doctor", 1 }, { "Electricity", 1 } } },
  { id = "sandevistan:cyberpsychoprone", cost = -5, name = "UI_trait_SandevistanPsycho", desc = "UI_trait_SandevistanPsychoDesc" },
  -- v0.1.30 (15). cost > 0: el rasgo CUESTA puntos; cost < 0: DA puntos.
  { id = "sandevistan:edgerunner", cost = 4, name = "UI_trait_SandevistanEdgerunner", desc = "UI_trait_SandevistanEdgerunnerDesc" },
  { id = "sandevistan:excorpo", cost = 4, name = "UI_trait_SandevistanExCorpo", desc = "UI_trait_SandevistanExCorpoDesc" },
  { id = "sandevistan:neurallyunstable", cost = -4, name = "UI_trait_SandevistanUnstable", desc = "UI_trait_SandevistanUnstableDesc" },
  -- (161) T08: arranca con el implante ya instalado. Cuesta 12 y no se puede combinar con el Instalador de callejón.
  { id = "sandevistan:chromed", cost = 12, name = "UI_trait_SandevistanChromed", desc = "UI_trait_SandevistanChromedDesc" },
}

SandevistanTraitDefs = { done = false, added = 0, errors = {} }
local TD = SandevistanTraitDefs

-- (137) Ids y subidas de skill de cada rasgo: el servidor los usa para reponer los rasgos del mod a un personaje nuevo (server/Sandevistan/Net.lua).
-- (154) TD.cost expone el costo de cada rasgo para las pruebas y el reporte (no lo usa el juego: lo pone addCharacterTraitDefinition).
TD.ids, TD.xp, TD.cost = {}, {}, {}
for _, def in ipairs(DEFS) do TD.ids[#TD.ids + 1] = def.id; TD.xp[def.id] = def.xp; TD.cost[def.id] = def.cost end

function TD.add()
  if TD.done then return end
  TD.done = true
  for _, def in ipairs(DEFS) do
    local ok, err = pcall(function()
      local trait = CharacterTrait.get(ResourceLocation.of(def.id))
      if not trait then error("rasgo no registrado (registries.lua): " .. def.id) end
      local d = CharacterTraitDefinition.addCharacterTraitDefinition(trait, getText(def.name), def.cost, getText(def.desc), false)
      for _, xp in ipairs(def.xp or {}) do
        if Perks and Perks[xp[1]] then d:addXPBoost(Perks[xp[1]], xp[2]) end
      end
    end)
    if ok then TD.added = TD.added + 1 else table.insert(TD.errors, tostring(err)); print("[Sandevistan] WARN rasgo " .. def.id .. ": " .. tostring(err)) end
  end
  -- (161) T08: *Cromado* excluye al *Instalador de callejón*: son dos arranques distintos (implante puesto o en la mochila).
  pcall(function()
    local a = CharacterTrait.get(ResourceLocation.of("sandevistan:chromed"))
    local b = CharacterTrait.get(ResourceLocation.of("sandevistan:labkit"))
    if a and b then CharacterTraitDefinition.setMutualExclusive(a, b) end
  end)
end

Events.OnGameBoot.Add(TD.add)
