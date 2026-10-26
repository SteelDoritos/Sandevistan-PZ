-- Sandevistan / SkillTooltip: detalle por nivel en el tooltip de la skill "Sandevistan: Adaptation" (pestana Skills del personaje). v0.1.30 (35).
-- Al pasar el mouse por un cuadradito de nivel, vanilla arma el texto en ISSkillProgressBar:updateTooltip(lvlSelected); aca se engancha esa funcion
-- y, SOLO para nuestra skill, se agregan al final de self.message las lineas de lo que hace ese nivel. Todos los numeros salen de SandevistanConfig (si se calibra el
-- balance, el tooltip sigue solo). Sin implante se muestran los dos (laboratorio y militar); con implante, solo el propio.
require "Sandevistan/Core"

local CFG = SandevistanConfig
local S = Sandevistan

SandevistanSkillTooltip = {}
local ST = SandevistanSkillTooltip
ST.installed = false
ST.calls = 0

local function t(key, ...) return getText("IGUI_Sandevistan_LvlTip_" .. key, ...) end
local function pct(x) return string.format("%d%%", math.floor(x * 100 + 0.5)) end
local function num(x) return string.format("%.1f", x) end
local function rgb(r, g, b) return string.format(" <RGB:%.2f,%.2f,%.2f> ", r, g, b) end
local WHITE, GREY, GOLD, GREEN = rgb(1, 1, 1), rgb(0.7, 0.7, 0.7), rgb(1, 0.8, 0.3), rgb(0.5, 1, 0.5)

-- tramo de dilatacion temporal que rige a ese nivel en esa variante (el mismo criterio que S.dilationTier)
function ST.tierAt(v, level)
  return S.tierFor(v, level)
end

-- valores numericos de un nivel para una variante (los usa el texto y la prueba)
function ST.stats(v, level)
  local tier, idx = ST.tierAt(v, level)
  local OD = CFG.Overdrive
  local frac = math.max(0, math.min(1, level / math.max(1, v.stableLevel or v.maxLevel or 1)))
  return {
    heat = v.baseHeat * (1 - level * v.heatReductionPerLevel), heatBase = v.baseHeat,
    cool = v.baseCool * (1 + level * v.coolBonusPerLevel), coolBase = v.baseCool,
    window = OD.WindowSeconds + (v.overdriveMax - OD.WindowSeconds) * level / math.max(1, v.maxLevel),
    tier = tier, tierIndex = idx, newTier = (idx > 1 and level == tier.minLevel),
    athletic = math.min(1, frac * ((CFG.Athletic and CFG.Athletic.GuardScale) or 1)),
    frac = frac, rejection = 1 - frac,                 -- rechazo basal: fraccion que queda
    stable = level >= (v.stableLevel or v.maxLevel),
    collapse = (OD.RejectionAdaptReduction or 0) * frac,
    ko = ((OD.Kerenzikov and OD.Kerenzikov.UnconsciousAdaptReduction) or 0) * frac,
    recovery = (OD.RecoveryAdaptReduction or 0) * frac,
    neuralUse = ((CFG.NeuralLoad and CFG.NeuralLoad.UseAdaptReduction) or 0) * frac,         -- (48) la carga neuronal por uso baja
    stamina = S.staminaDrainPerSecond(level, false),                                          -- (120) estamina por segundo encendido (baja con el nivel)
    staminaCut = 1 - S.staminaDrainPerSecond(level, false) / S.staminaDrainPerSecond(0, false),
  }
end

local function variantBlock(name, key, v, level)
  local st = ST.stats(v, level)
  local out = {}
  local function add(s) out[#out + 1] = s end
  add(GOLD .. name .. WHITE)
  add(t("Heat", pct(st.heat / st.heatBase - 1), "+" .. pct(st.cool / st.coolBase - 1)))
  add(t("Window", num(st.window)))
  add(t("Stamina", string.format("%.1f%%", st.stamina * 100), level > 0 and ("-" .. pct(st.staminaCut)) or "-0%"))
  local tr = st.tier
  add(t("Dilation", pct(tr.world), "+" .. pct(tr.playerBoost), "+" .. pct(tr.attackBoost)))
  if st.newTier then add(GREEN .. t("NewTier") .. WHITE) end
  if level > 0 then add(t("Athletic", pct(st.athletic))) end
  if st.stable then
    add(GREEN .. t("RejStop") .. WHITE)
  elseif level > 0 then
    add(t("Rej", pct(1 - st.rejection)))
  end
  if level > 0 and st.neuralUse > 0 then add(t("NeuralUse", pct(st.neuralUse))) end
  if level > 0 then add(t("Adapt", pct(st.collapse))) end          -- colapso, KO de Kerenzikov y recuperacion comparten el mismo % (la prueba lo vigila)
  return out
end

-- (123) Niveles 11..15: solo existen con Beyond Ten (que dibuja esos cuadraditos). Los bonos de maestria acumulados sobre el nivel 10 del implante militar.
function ST.masteryLines(rank, variants)
  local M = CFG.Mastery
  local e = nil
  for _, x in ipairs(variants) do if x[3].mastery then e = x end end
  if not M or not e then return { GREY .. t("Unreachable") .. WHITE } end
  local v = e[3]
  local st = ST.stats(v, v.maxLevel)
  local out = {}
  local function add(s) out[#out + 1] = s end
  add(GOLD .. e[1] .. " - " .. t("Mastery", rank, #M.Table) .. WHITE)
  add(t("MasteryHeat", "-" .. pct(M.HeatPerRank * rank), "+" .. pct(M.CoolPerRank * rank)))
  add(t("Window", num(st.window + M.WindowPerRank * rank)))
  add(t("MasteryStamina", "-" .. pct(M.StaminaPerRank * rank)))
  add(t("NeuralUse", pct(st.neuralUse + M.NeuralUsePerRank * rank)))
  add(t("MasteryRecovery", pct(st.recovery + M.RecoveryPerRank * rank)))
  if rank >= (M.AfterimageRank or 99) then
    add((rank == M.AfterimageRank and GREEN or "") .. t("MasteryTrails", string.format("x%d", (CFG.Afterimage.AdaptMaxMultiplier or 3) + (M.AfterimageExtra or 0))) .. WHITE)
  end
  local tier = S.tierFor(v, v.maxLevel + rank)
  if tier ~= st.tier then
    add(t("Dilation", pct(tier.world), "+" .. pct(tier.playerBoost), "+" .. pct(tier.attackBoost)))
    if rank == tier.minLevel - v.maxLevel then add(GREEN .. t("NewTier") .. WHITE) end
  end
  return out
end

-- Texto (rich text de ISToolTip) del nivel 0..10 (y 11..15 con Beyond Ten). variants = { {nombre, clave, cfg}, ... }
function ST.lines(level, variants)
  level = math.max(0, math.floor(level or 0))
  if level > 10 then
    local out = { " <LINE>" }
    for _, l in ipairs(ST.masteryLines(math.min(level - 10, (CFG.Mastery and #CFG.Mastery.Table) or 0), variants)) do out[#out + 1] = " <LINE> " .. l end
    return table.concat(out, "")
  end
  local out = { " <LINE>" }
  local shown, shownKey = 0, nil
  for _, e in ipairs(variants) do
    local v = e[3]
    if level <= v.maxLevel then
      shown = shown + 1; shownKey = e[2]
      for _, l in ipairs(variantBlock(e[1], e[2], v, level)) do out[#out + 1] = " <LINE> " .. l end
    end
  end
  if shown == 0 then
    out[#out + 1] = " <LINE> " .. GREY .. t("Unreachable") .. WHITE
  elseif shown == 1 and level > (CFG.Variants.lab.maxLevel or 0) and shownKey == "military" then
    out[#out + 1] = " <LINE> " .. GREY .. t("MilOnly", CFG.Variants.lab.maxLevel) .. WHITE
  end
  return table.concat(out, "")
end

-- variantes a mostrar para un jugador: la suya si tiene implante que funciona; si no, las dos
function ST.variantsFor(player)
  local lab = { t("Lab"), "lab", CFG.Variants.lab }
  local mil = { t("Military"), "military", CFG.Variants.military }
  local d = nil
  if player then pcall(function() d = S.data(player) end) end
  if d and S.hasWorkingImplant(d) then
    return { d.variant == "military" and mil or lab }
  end
  return { lab, mil }
end

local function isOurs(bar)
  local p = S.perk()
  if not p or not bar.perk then return false end
  if bar.perk == p then return true end
  local same = false
  pcall(function() same = tostring(bar.perk:getId()) == "SandevistanAdaptation" end)
  return same
end

-- Despues de la funcion de vanilla: vanilla arma el texto en self.message (lo reescribe entero en cada llamada) y ISSkillProgressBar:render lo copia a
-- tooltip.description; por eso se agrega a self.message (agregar a tooltip.description se pisa en el cuadro siguiente: era el fallo de (35)).
-- lvlSelected es el indice del cuadradito desde 0: el nivel que se muestra es lvlSelected + 1. Se recuerda el bloque que se escribio para no apilarlo
-- si alguna version no reescribe el mensaje o si otro mod agrega texto entre nuestros dos ganchos.
function ST.decorate(bar, lvlSelected)
  if lvlSelected == nil or not isOurs(bar) then return end
  local level = lvlSelected + 1
  local player = nil
  pcall(function() player = getSpecificPlayer(bar.playerNum or 0) end)
  local msg = type(bar.message) == "string" and bar.message or ""
  local block = ST.lines(level, ST.variantsFor(player))
  -- (127) se saca nuestro bloque si ya esta (el de la llamada anterior si vanilla no reescribe, o el del otro enganche nuestro) y se agrega al final una
  -- sola vez. Antes se comparaba con lo ultimo escrito: Beyond Ten, enganchado entre nuestros dos ganchos, le suma su linea ("Beyond Ten mastery") y el
  -- gancho de afuera tomaba eso por un texto nuevo de vanilla y repetia el bloque entero (tooltip de los niveles 11-15 duplicado).
  for _, old in ipairs({ bar._sandevBlock, block }) do
    local i = old and old ~= "" and string.find(msg, old, 1, true)
    if i then msg = string.sub(msg, 1, i - 1) .. string.sub(msg, i + #old) end
  end
  local out = msg .. block
  bar.message = out
  bar._sandevBlock = block
  ST.calls = ST.calls + 1
end

local function wrap()
  local orig = ISSkillProgressBar.updateTooltip
  ISSkillProgressBar.updateTooltip = function(self, lvlSelected)
    orig(self, lvlSelected)
    local ok, err = pcall(ST.decorate, self, lvlSelected)
    if not ok then S.log("tooltip de skill: " .. tostring(err)) end
  end
  ST.wraps = (ST.wraps or 0) + 1
end

function ST.install()
  if ST.installed or not ISSkillProgressBar or not ISSkillProgressBar.updateTooltip then return false end
  wrap()
  ST.installed = true
  return true
end

-- Segundo enganche al empezar la partida: si otro mod de tooltips de skills (que reconstruye self.message entero) se cargo despues que este, nuestro
-- texto quedaba adentro y se perdia; asi queda por fuera. ST.decorate no apila (recuerda la base), dos enganches dan el mismo texto.
function ST.installOuter()
  if not ST.installed then ST.install() end
  if ST.installed and (ST.wraps or 0) < 2 then wrap() end
end

ST.install()
Events.OnGameStart.Add(ST.installOuter)

return ST
