-- (157) Sandevistan / CraftBooksUI (cliente): en la ventana de crafteo, decir con qué se está fabricando una receta guiada.
-- El panel del juego no sabe de la guía con libros: muestra el tiempo de siempre y, si el OnTest rechaza los ítems, dice "faltan ítems".
-- Acá se engancha la cabecera de la receta (ISWidgetTitleHeader:updateLabels, que es la que dibuja el título, el tooltip y la línea roja de
-- "no se puede") y la barra de tiempo de abajo (ISWidgetHandCraftControl:prerender) para sumar:
--   * "Guía con libros: faltan N niveles; ×X de tiempo; Y % de fallo" debajo del tooltip;
--   * "Faltan libros: ..." en la misma línea roja de "no se puede", para que no quede como si faltaran materiales;
--   * el tiempo ya multiplicado en el icono del reloj y en la barra de abajo.
-- Solo interfaz y solo en el cliente: no toca el crafteo en sí.
require "Sandevistan/Core"
require "Sandevistan/BookGuide"

local CFG = SandevistanConfig
local S = Sandevistan
local BG = SandevistanBookGuide

SandevistanCraftBooksUI = SandevistanCraftBooksUI or {}
local UI = SandevistanCraftBooksUI

local function pct(v) return string.format("%d %s", math.floor((v or 0) * 100 + 0.5), "%") end
local function r2(v) return math.floor((v or 0) * 100 + 0.5) / 100 end

-- Nombre localizado de la skill (el mismo que usa el juego: "Primeros Auxilios", "Electricidad"…).
local function perkName(perk)
  local name = perk
  pcall(function() name = PerkFactory.getPerkName(Perks[perk]) or name end)
  return name
end

-- Estado de la guía para la receta y el jugador: nil si la receta no está guiada o el nivel alcanza; si no, guided o missing.
function UI.status(recipe, player)
  if not recipe or not player then return nil end
  local name = nil
  pcall(function() name = recipe:getName() end)
  local req = BG.recipeReq(name)
  if not req then return nil end
  local bg = BG.checkAll(player, req)
  if bg.ok and (bg.gap or 0) > 0 then
    local fail = BG.failChance(bg.gap)
    local RC, key = rawget(_G, "SandevistanRecipeCode"), nil
    if RC and RC.AssemblyRecipes then key = RC.AssemblyRecipes[name] or RC.AssemblyRecipes[(tostring(name):gsub("^.*%.", ""))] end
    if key then fail = 1 - RC.assemblyChance(player, CFG[key]) end             -- (196) el ensamblado tira su chance, no el fallo por nivel
    local guidedSkills = {}                                                    -- (199) que skill guian los libros: "Electricidad 3 (tenés 0)"
    for perk, required in pairs(req) do
      local r = bg.parts and bg.parts[perk]
      if r and (r.gap or 0) > 0 then guidedSkills[#guidedSkills + 1] = { perk = perk, required = required, cur = r.cur or 0 } end
    end
    table.sort(guidedSkills, function(a, b) return tostring(a.perk) < tostring(b.perk) end)
    return { guided = true, ok = true, gap = bg.gap, timeMult = BG.timeMult(bg.gap), fail = fail, skills = guidedSkills }
  elseif not bg.ok then
    local skills = {}
    for perk, required in pairs(req) do
      local r = bg.parts and bg.parts[perk]
      if not (r and r.ok) then skills[#skills + 1] = { perk = perk, required = required } end
    end
    table.sort(skills, function(a, b) return tostring(a.perk) < tostring(b.perk) end)
    return { missing = BG.missingNames(bg), off = (CFG.BookGuide.Enabled == false), skills = skills }
  end
  return nil
end

-- (200) Con el nivel no hay guía, pero el texto fijo de la receta habla de libros: decir igual qué skill pide. nil si la receta no es guiable
-- o falta el nivel (ahí van la línea de la guía o el error rojo).
function UI.reqLine(recipe, player)
  if not recipe or not player then return nil end
  local name = nil
  pcall(function() name = recipe:getName() end)
  local req = BG.recipeReq(name)
  if not req then return nil end
  local skills = {}
  for perk, required in pairs(req) do
    local cur = BG.level(player, perk)
    if cur < required then return nil end
    skills[#skills + 1] = { perk = perk, required = required, cur = cur }
  end
  table.sort(skills, function(a, b) return tostring(a.perk) < tostring(b.perk) end)
  local parts = {}
  for _, s in ipairs(skills) do parts[#parts + 1] = getText("IGUI_Sandevistan_BookGuideSkill", perkName(s.perk), s.required, s.cur) end
  return getText("IGUI_Sandevistan_BookReqLine") .. ": " .. table.concat(parts, ", ")
end

-- "Faltan libros: … (o subí Electricidad a 4)": los libros que faltan y, al lado, el nivel que también sirve.
function UI.missingText(st)
  local value = st.off and getText("IGUI_Sandevistan_BookOff") or table.concat(st.missing or {}, ", ")
  local hints = {}
  for _, s in ipairs(st.skills or {}) do
    hints[#hints + 1] = getText("IGUI_Sandevistan_BookMissingLevel", perkName(s.perk), s.required)
  end
  if #hints > 0 then value = value .. " (" .. table.concat(hints, "; ") .. ")" end
  return getText("IGUI_Sandevistan_BookMissing") .. ": " .. value
end

-- (199) dos renglones: la skill que guian los libros (con la que pide y la que tenés) y debajo la penalidad
function UI.line(st)
  local skills = {}
  for _, s in ipairs(st.skills or {}) do skills[#skills + 1] = getText("IGUI_Sandevistan_BookGuideSkill", perkName(s.perk), s.required, s.cur) end
  local head = getText("IGUI_Sandevistan_BookGuideLine")
  if #skills > 0 then head = head .. ": " .. table.concat(skills, ", ") end
  return head .. "\n" .. getText("IGUI_Sandevistan_BookGuideValue", st.gap, string.format("%.2f", st.timeMult), pct(st.fail))
end

-- Cabecera de la receta: el tooltip gana una línea y el error rojo explica que lo que falta son los libros.
local function hookTitleHeader()
  local C = rawget(_G, "ISWidgetTitleHeader")
  if type(C) ~= "table" or type(C.updateLabels) ~= "function" then return false end
  if C.sdvBooks then return true end
  C.sdvBooks = true
  local orig = C.updateLabels
  C.updateLabels = function(self, ...)
    local r = orig(self, ...)
    pcall(function()
      if not self.recipe or not self.player then return end
      local st = UI.status(self.recipe, self.player)
      -- tooltip: la línea de la guía aparece y se va sola cuando ya no hace falta
      if self.tooltipLabel then
        if self.sdvTooltipRef ~= self.tooltipLabel then
          self.sdvTooltipRef = self.tooltipLabel
          self.sdvBaseTooltip = self.tooltipLabel:getName()
        end
        local txt = self.sdvBaseTooltip or ""
        if st and st.guided then txt = txt .. "\n" .. UI.line(st)
        elseif not st then
          local rl = UI.reqLine(self.recipe, self.player)
          if rl then txt = txt .. "\n" .. rl end
        end
        if self.tooltipLabel:getName() ~= txt then
          self.tooltipLabel:setName(txt)
          pcall(function() self.tooltipLabel:setHeightToName(0) end)
        end
      end
      -- el reloj de la cabecera también muestra el tiempo con la penalidad
      if self.timeIcon then
        local base = 0
        pcall(function() base = self.recipe:getTime(self.player) / 10 end)
        local mult = (st and st.guided) and st.timeMult or 1
        self.timeIcon.mouseovertext = getText("IGUI_CraftingWindow_CraftTime") .. " " .. tostring(r2(base * mult)) .. " " .. getText("IGUI_CraftingWindow_Seconds")
      end
      -- línea roja de "no se puede": agregar qué libros faltan (sin pisar el texto del juego)
      if st and st.missing and self.errorLabel and self.errorLabel.errorText and self.errorLabel:isVisible() then
        local extra = UI.missingText(st)
        if not self.errorLabel.errorText:find(extra, 1, true) then
          local base = self.errorLabel.errorText
          local sep = base:match("[%.,;:!?]$") and " " or ". "      -- el texto del juego no siempre termina en punto
          self.errorLabel.errorText = base .. sep .. extra
        end
      end
    end)
    return r
  end
  return true
end

-- Barra de abajo ("Time Required"): muestra el tiempo con la penalidad de los libros.
local function hookTimeBar()
  local C = rawget(_G, "ISWidgetHandCraftControl")
  if type(C) ~= "table" or type(C.prerender) ~= "function" then return false end
  if C.sdvBooksTime then return true end
  C.sdvBooksTime = true
  local orig = C.prerender
  C.prerender = function(self, ...)
    -- (198) ISLabel:setName vuelve la etiqueta a su X de creacion (0) cada vez que cambia el texto, y calculateLayout la puso en la mitad
    -- con setX. El juego escribe su texto en cada cuadro y nosotros el nuestro: sin guardar la X quedaba encima de "Quantity".
    local lbl = self.durationLabel
    local x0 = lbl and lbl:getX()
    local r = orig(self, ...)
    pcall(function()
      if not lbl or not self.logic or not self.player then return end
      local recipe = self.logic:getRecipe()
      local st = UI.status(recipe, self.player)
      if not st or not st.guided then return end
      local seconds = math.floor(recipe:getTime(self.player) * st.timeMult + 0.5)
      local mm, ss = math.floor(seconds / 60), math.fmod(seconds, 60)
      lbl:setNameWithoutMoving(string.format(getText("IGUI_CraftingWindow_TimeRequired") .. " %02dm %02ds", mm, ss))
      if x0 and lbl:getX() ~= x0 then lbl:setX(x0) end
    end)
    return r
  end
  return true
end

function UI.install()
  local a = hookTitleHeader()
  local b = hookTimeBar()
  return a and b
end

if not UI.install() then
  Events.OnGameStart.Add(function() UI.install() end)
end

return UI
