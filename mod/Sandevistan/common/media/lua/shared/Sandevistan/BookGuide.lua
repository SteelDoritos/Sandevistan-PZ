-- (155) Sandevistan / BookGuide (shared): guía con los libros vanilla (31 §3.1, T06).
-- Sin el nivel de una skill, llevar los libros de esa skill en el inventario deja hacer la acción: más lento y con chance de fallar. Hacen
-- falta los libros de los niveles que faltan: con FA 0 para algo de FA 4, los vol. 1 y 2; con FA 2, solo el vol. 2 (y la penalidad es menor).
-- El volumen N enseña los niveles 2N-1 y 2N (vanilla, XPSystem_SkillBook). Se busca por tipo, sin leer el libro. Solo usa Core y Config.
require "Sandevistan/Core"

local CFG = SandevistanConfig
local S = Sandevistan

SandevistanBookGuide = {}
local BG = SandevistanBookGuide

-- Caché por personaje y requisito: el panel de crafteo y los menús preguntan muchas veces por cuadro (T07 lo necesita con OnTest).
local cache = {}

local function nowMs()
  local ok, t = pcall(getTimestampMs)
  if ok and type(t) == "number" then return t end
  return 0
end

-- Nivel de la skill ("Doctor", "Electricity", "MetalWelding", "Tailoring"...). 0 si el personaje o el Perk no existen.
function BG.level(character, perk)
  local p = Perks and Perks[perk]
  if not character or not p then return 0 end
  local lvl = 0
  pcall(function() lvl = character:getPerkLevel(p) or 0 end)
  return lvl
end

-- Volumen del libro que enseña ese nivel (el N enseña 2N-1 y 2N).
function BG.volumeFor(level) return math.ceil(level / 2) end

-- Tiene el libro de ese volumen (mira también adentro de las bolsas: getFirstTypeRecurse).
function BG.hasBook(character, perk, volume)
  local base = CFG.BookGuide.Books[perk]
  if not character or not base or not volume then return false end
  local found = false
  local fullType = base .. volume
  pcall(function() found = character:getInventory():getFirstTypeRecurse(fullType) ~= nil end)
  return found
end

-- Libros que faltan para cubrir los niveles de "from" a "to" (sin repetir volumen). Devuelve la lista de tipos completos.
function BG.missingBooks(character, perk, from, to)
  local out, done = {}, {}
  for level = from, to do
    local vol = BG.volumeFor(level)
    if not done[vol] then
      done[vol] = true
      if not BG.hasBook(character, perk, vol) then out[#out + 1] = CFG.BookGuide.Books[perk] .. vol end
    end
  end
  return out
end

-- Nombre legible de cada libro (el que muestra el juego), para los avisos. Si el juego no lo sabe, el tipo completo.
function BG.missingNames(res)
  local names = {}
  for _, fullType in ipairs((res and res.missing) or {}) do
    local name = nil
    pcall(function() name = getItemNameFromFullType(fullType) end)
    names[#names + 1] = (name and name ~= "") and name or fullType
  end
  return names
end

-- ¿Puede el personaje con esa skill al nivel requerido? Devuelve { ok, gap, missing = { tipo... }, cur }.
-- ok = true con gap 0 si el nivel alcanza; ok = true con gap > 0 si los libros guían; ok = false con missing si falta algún libro.
-- Con BookGuide.Enabled = false, debajo del nivel siempre es ok = false.
function BG.check(character, perk, required)
  local res = { ok = false, gap = 0, cur = 0, missing = {} }
  if not character or not perk or not required then return res end
  local cur = BG.level(character, perk)
  res.cur = cur
  local gap = required - cur
  if gap <= 0 then res.ok = true return res end
  res.gap = gap
  if not CFG.BookGuide.Enabled then return res end

  local key = tostring(perk) .. "|" .. tostring(required)
  local now, c = nowMs(), cache[character]
  if c and c[key] and (now - c[key].t) < (CFG.BookGuide.CacheMs or 0) then return c[key].res end

  local missing = BG.missingBooks(character, perk, cur + 1, required)
  if #missing == 0 then res.ok = true else res.missing = missing end
  if CFG.BookGuide.CacheMs and CFG.BookGuide.CacheMs > 0 then
    c = c or {}
    cache[character] = c
    c[key] = { t = now, res = res }
  end
  return res
end

-- Varios requisitos a la vez: BG.checkAll(character, { Doctor = 4, Electricity = 3 }). ok si todos lo son; gap = suma de los gaps;
-- missing = todos los libros que faltan (ordenados, sin repetir).
function BG.checkAll(character, reqs)
  local out = { ok = true, gap = 0, missing = {}, parts = {} }
  if not character or type(reqs) ~= "table" then out.ok = false return out end
  local seen = {}
  for perk, required in pairs(reqs) do
    local r = BG.check(character, perk, required)
    out.parts[perk] = r
    if not r.ok then out.ok = false end
    out.gap = out.gap + (r.gap or 0)
    for _, fullType in ipairs(r.missing or {}) do
      if not seen[fullType] then seen[fullType] = true; out.missing[#out.missing + 1] = fullType end
    end
  end
  table.sort(out.missing)
  return out
end

-- Penalididades (con los números del nivel de sandbox elegido; los de Normal por defecto):
function BG.timeMult(gap) return 1 + (CFG.BookGuide.TimePerLevel or 0) * math.max(0, gap or 0) end
function BG.failChance(gap) return math.min(CFG.BookGuide.FailMax or 0, (CFG.BookGuide.FailPerLevel or 0) * math.max(0, gap or 0)) end
-- (195) floor = el piso propio de la accion (BookChanceFloor en su tabla de Config); sin el, el general del nivel de sandbox.
function BG.chanceBelow(chanceAtMin, gap, floor) return math.max(floor or CFG.BookGuide.ChanceFloor or 0, (chanceAtMin or 0) - (CFG.BookGuide.ChanceLossPerLevel or 0) * math.max(0, gap or 0)) end
-- T07: parte de cada material que vuelve al fallar un crafteo guiado.
function BG.refundShare() return CFG.BookGuide.RefundShare or 0 end

-- ¿El estado permite la herida leve de las cirugías guiadas por libros (125)?
function BG.sloppyWound() return CFG.BookGuide.SloppyWound ~= false end

-- (156) T07: requisito de una receta por su nombre (el juego puede darlo pelado o con el módulo delante).
function BG.recipeReq(name)
  if type(name) ~= "string" then return nil end
  local bare = name:match("([^%.]+)$") or name
  return CFG.BookGuide.Recipes[bare] or CFG.BookGuide.Recipes[name]
end

---------------------------------------------------------------------------
-- (156) T07: la duración del crafteo nativo sale de ISHandcraftAction.getDuration (craftRecipe:getTime * 5). Se envuelve UNA vez y solo se
-- multiplica cuando la receta está en BookGuide.Recipes y los libros guían. Corre donde se calcula la duración (cliente en SP, servidor en MP).
-- El gancho de Taller también envuelve getDuration: se multiplican y el orden no importa.
---------------------------------------------------------------------------
BG.durationHooked = false
function BG.hookDuration()
  if BG.durationHooked then return true end
  local A = rawget(_G, "ISHandcraftAction")
  if type(A) ~= "table" or type(A.getDuration) ~= "function" then return false end
  BG.durationHooked = true
  local orig = A.getDuration
  A.getDuration = function(self, ...)
    local t = orig(self, ...)
    pcall(function()
      local req = self.craftRecipe and BG.recipeReq(self.craftRecipe:getName())
      if req and self.character then
        local bg = BG.checkAll(self.character, req)
        if bg.ok and (bg.gap or 0) > 0 then t = t * BG.timeMult(bg.gap) end
      end
    end)
    return t
  end
  return true
end
if not BG.hookDuration() then
  Events.OnGameStart.Add(function() BG.hookDuration() end)
end

-- (157) Diagnóstico para el menú Debug (y para pegar en un reporte): estado de la configuración, del enganche de la duración, los niveles del
-- jugador, cada receta guiada con lo que le falta y una comprobación de la matemática. Devuelve una lista de líneas.
function BG.diagnostics(player)
  local out = {}
  local function add(l) out[#out + 1] = l end
  local B = CFG.BookGuide
  add("# Sandevistan " .. tostring(CFG.Version or "?") .. " (" .. tostring(CFG.Build or "?") .. "): guía con libros")
  add(string.format("Enabled=%s  tiempo/nivel=%.3f  fallo/nivel=%.3f tope=%.2f  pérdida de tirada/nivel=%.3f piso=%.2f  devolución=%.2f  caché=%s ms",
    tostring(B.Enabled), B.TimePerLevel or 0, B.FailPerLevel or 0, B.FailMax or 0, B.ChanceLossPerLevel or 0, B.ChanceFloor or 0,
    B.RefundShare or 0, tostring(B.CacheMs or 0)))
  add("enganche de la duración (ISHandcraftAction): " .. tostring(BG.durationHooked == true))
  add("")
  add("## niveles del jugador")
  for _, perk in ipairs({ "Doctor", "Electricity", "MetalWelding", "Tailoring" }) do
    add(string.format("  %s = %d", perk, BG.level(player, perk)))
  end
  add("")
  add("## recetas nativas")
  local names = {}
  for name in pairs(B.Recipes or {}) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local req = B.Recipes[name]
    local all = BG.checkAll(player, req)
    local parts = {}
    for perk, required in pairs(req) do
      local r = BG.check(player, perk, required)
      local st
      if r.ok then st = ((r.gap or 0) > 0) and ("libros, faltan " .. r.gap) or "con el nivel"
      else st = "sin nivel ni libros; faltan: " .. table.concat(BG.missingNames(r), ", ") end
      parts[#parts + 1] = string.format("%s %d (tiene %d) -> %s", perk, required, r.cur, st)
    end
    local tail = "NO se puede"
    if all.ok then
      local fail = BG.failChance(all.gap)
      local RC = rawget(_G, "SandevistanRecipeCode")
      local key = RC and RC.AssemblyRecipes and RC.AssemblyRecipes[name]
      if key then fail = 1 - RC.assemblyChance(player, CFG[key]) end      -- (196) el ensamblado tira su chance, no el fallo por nivel
      tail = ((all.gap or 0) > 0) and string.format("x%.2f de tiempo, %.0f%% de fallo", BG.timeMult(all.gap), fail * 100) or "sin penalidad"
    end
    add(string.format("%s: %s | %s", name, table.concat(parts, " / "), tail))
  end
  add("")
  -- (195) las tiradas que ya existían, con su piso (el propio BookChanceFloor o el general) y lo que queda con nivel 0 y los libros
  add("## tiradas por debajo del mínimo (nivel 0 con libros)")
  local function roll(label, c, minLvl)
    if not c or not c.chance or not minLvl then return end
    local atMin = S.thresholdValue(c.chance, minLvl) or 0
    add(string.format("  %s: mínimo %d (%.0f%%), piso %.0f%%%s, con 0 = %.0f%%", label, minLvl, atMin * 100,
      (c.BookChanceFloor or B.ChanceFloor or 0) * 100, c.BookChanceFloor and " (propio)" or "", BG.chanceBelow(atMin, minLvl, c.BookChanceFloor) * 100))
  end
  for _, key in ipairs({ "guided", "blind", "assistedHarness", "assistedNoHarness" }) do
    roll("Surgery." .. key, CFG.Surgery[key], CFG.Surgery[key] and CFG.Surgery[key].minFA)
  end
  roll("Explant", CFG.Explant, CFG.Explant.MinFA)
  roll("Explant (destruido)", CFG.Explant, CFG.Explant.MinFADestroyed)
  roll("Prototype04 (reparar, Electricidad)", CFG.Prototype04, CFG.Prototype04.MinElectrical)
  roll("Prototype06 (ensamblar)", CFG.Prototype06, CFG.Prototype06.MinFA)
  roll("Prototype07 (ensamblar)", CFG.Prototype07, CFG.Prototype07.MinFA)
  add("")
  add("## comprobación de la matemática (Normal)")
  add(string.format("  timeMult(4)=%.2f (esperado 2.00)   timeMult(1)=%.2f (esperado 1.25)", BG.timeMult(4), BG.timeMult(1)))
  add(string.format("  failChance(4)=%.2f (0.40)   failChance(10)=%.2f (0.60, tope)", BG.failChance(4), BG.failChance(10)))
  add(string.format("  chanceBelow(0.75,4)=%.2f (0.43)   chanceBelow(0.75,10)=%.2f (0.25, piso)", BG.chanceBelow(0.75, 4), BG.chanceBelow(0.75, 10)))
  add(string.format("  chanceBelow(0.75,10,0.40)=%.2f (0.40, piso propio)", BG.chanceBelow(0.75, 10, 0.40)))
  return out
end

-- Para las pruebas y el Debug: olvida la caché (también después de un cambio de sandbox).
function BG.clearCache() cache = {} end

Events.OnGameStart.Add(function() BG.clearCache() end)

return BG
