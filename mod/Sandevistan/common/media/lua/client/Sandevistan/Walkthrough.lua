-- Sandevistan / Walkthrough: el RECORRIDO funcional semiautomatico (Debug -> "RECORRIDO funcional").
-- v0.1.30 (27). Complementa al autotest (FullTest, que prueba la LOGICA con funciones directas): esto recorre lo que el jugador toca de verdad,
-- con las herramientas del propio juego, y al final pregunta por lo que solo se juzga mirando.
--   Automatico: items (se crean, tienen icono/modelo/nombre), sonidos, textos de notas, recetas nativas (cargadas, nombres, salidas), rasgos,
--               dificultades del sandbox, menus de inventario REALES (opciones y "Leer" de las 20 notas abriendo la ventana), lectura REAL de
--               los libros con la accion del juego (ISReadABook) y crafteo con la logica de crafteo del juego (HandcraftLogic).
--   Manual:     preguntas si/no sobre lo visual: modelos en el piso, ventanas de lectura, pestana del menu de crafteo, sonidos.
-- Cada paso va en pcall: una API que el juego no tenga NO cierra el recorrido, queda como INFO ("no automatizable") o FALLA con el error.
-- Al terminar repone TODO (conocimiento de recetas, dificultad, ventanas, items de prueba) y escribe Zomboid/Lua/Sandevistan_walkthrough.txt;
-- el reporte (Debug -> REPORTE) incluye los resultados de la ultima corrida.
-- Personaje de prueba recomendado: el crafteo consume ingredientes iguales a los tuyos. Para probar el crafteo con habilidad, subi antes
-- Electrical 6, First Aid 3 y Soldadura 3 (menu debug del juego): si no llegas, ese paso queda como INFO.
require "Sandevistan/Core"
require "Sandevistan/Medical"
require "Sandevistan/Dossier"
require "Sandevistan/NotesText"
require "Sandevistan/ContextMenus"
require "Sandevistan/Reader"
require "Sandevistan/Dialog"

local CFG = SandevistanConfig
local S = Sandevistan
local M = SandevistanMedical
local DOS = SandevistanDossier
local V = CFG.Crafting.Items

SandevistanWalkthrough = { results = nil }
local W = SandevistanWalkthrough

-- Sonidos que define scripts/Sandevistan_sounds.txt (tools/tests/walkthrough.lua comprueba que esta lista y el script coinciden)
W.SOUNDS = { "SandevistanActivate", "SandevistanDeactivate", "SandevistanHeatWarn", "SandevistanOverdrive", "SandevistanCollapse", "SandevistanError",
             "SandevistanHeartbeat", "SandevistanTinnitus", "SandevistanDoseImmuno",
             -- (153) glitch en tres familias (Config.Psychosis.Audio.Roles)
             "SandevistanGlitch1", "SandevistanGlitch2", "SandevistanGlitch3", "SandevistanGlitch4", "SandevistanGlitch5", "SandevistanGlitch6",
             "SandevistanGlitch7", "SandevistanGlitchVanish1", "SandevistanGlitchVanish2", "SandevistanGlitchVanish3",
             "SandevistanGlitchSevere1", "SandevistanGlitchSevere2" }
W.TRAIT_KEYS = { special = "SandevistanSpecial", chrome = "SandevistanChrome", labkit = "SandevistanLabKit", ripperdoc = "SandevistanRipperdoc",
                 psycho = "SandevistanPsycho", edgerunner = "SandevistanEdgerunner", excorpo = "SandevistanExCorpo", unstable = "SandevistanUnstable" }
W.ANSWER_TIMEOUT_MS = 180000
W.ACTION_TIMEOUT_MS = 25000

local run = nil
function W.running() return run ~= nil end
function W.stepName() return run and run.stepName or "-" end

---------------------------------------------------------------------------
-- Resultados
---------------------------------------------------------------------------
local function rec(status, name, detail)
  local line = string.format("[%s] %s%s", status, name, detail and ("  (" .. tostring(detail) .. ")") or "")
  line = S.ascii and S.ascii(line) or line
  if run then
    run.lines[#run.lines + 1] = line
    run.counts[status] = (run.counts[status] or 0) + 1
  end
  print("[Sandevistan][WALK] " .. line)
end
local function check(name, cond, detail) rec(cond and "OK" or "FALLA", name, detail) end
local function info(name, detail) rec("INFO", name, detail) end
local function header(text)
  if run then run.lines[#run.lines + 1] = "-- " .. text end
  print("[Sandevistan][WALK] -- " .. text)
end

local function try(f, ...)
  local ok, v = pcall(f, ...)
  if ok then return v end
  return nil
end

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = deepcopy(v) end
  return c
end

-- Acciones instantaneas mientras dura el recorrido (se repone el valor que tenia).
local function instantOn(p)
  if run.prevInstant == nil then run.prevInstant = try(function() return p:isTimedActionInstantCheat() end) == true end
  pcall(function() p:setTimedActionInstantCheat(true) end)
end

-- Items de ese tipo que creo el recorrido (no los que ya tenia el jugador).
local function newItems(p, fullType)
  local out = {}
  local list = try(function() return p:getInventory():getAllTypeRecurse(fullType) end)
  if not list then return out end
  for i = 0, list:size() - 1 do
    local it = list:get(i)
    if not run.ids[it:getID()] then out[#out + 1] = it end
  end
  return out
end
local function purgeNew(p, fullType)
  for _, it in ipairs(newItems(p, fullType)) do p:getInventory():DoRemoveItem(it) end
end

local function giveItem(p, fullType)
  local it = S.giveItem(p:getInventory(), fullType)
  return it
end

---------------------------------------------------------------------------
-- Pasos automaticos
---------------------------------------------------------------------------
local function stepItems(p)
  header("Items del mod: se crean, nombre, icono y modelo")
  local SM = getScriptManager()
  local list = try(function() return SM:getAllItems() end)
  if not list then info("items", "getAllItems no disponible"); return end
  local total, bad = 0, {}
  for i = 0, list:size() - 1 do
    local full = try(function() return list:get(i):getFullName() end)
    if full and string.find(full, "^Sandevistan%.") then
      total = total + 1
      local probs = {}
      local scriptItem = list:get(i)
      local inst = try(function() return instanceItem(full) end)
      if not inst then
        probs[#probs + 1] = "no se puede crear"
      else
        local name = try(function() return inst:getDisplayName() end)
        if not name or name == "" or name == full or string.find(name, "ItemName_", 1, true) then probs[#probs + 1] = "sin nombre traducido (" .. tostring(name) .. ")" end
        local isClothing = string.find(full, "Spine", 1, true) ~= nil
        if not isClothing and not try(function() return inst:getTexture() end) then probs[#probs + 1] = "sin icono" end
      end
      local wm = try(function() return scriptItem:getWorldStaticModel() end)
      if wm and wm ~= "" then
        local ms = try(function() return SM:getModelScript(wm) end) or try(function() return SM:getModelScript("Sandevistan." .. wm) end)
        if not ms then probs[#probs + 1] = "modelo '" .. tostring(wm) .. "' no existe" end
      end
      if #probs > 0 then bad[#bad + 1] = full .. ": " .. table.concat(probs, ", ") end
    end
  end
  check("items del mod sin problemas", #bad == 0 and total > 0, total .. " items revisados")
  for i = 1, math.min(#bad, 12) do rec("FALLA", "item", bad[i]) end
end

local function stepSounds(p)
  header("Sonidos definidos")
  local SM = getScriptManager()
  local missing = {}
  for _, n in ipairs(W.SOUNDS) do
    if not try(function() return SM:getGameSound(n) end) then missing[#missing + 1] = n end
  end
  check("sonidos cargados", #missing == 0, #W.SOUNDS .. " revisados" .. (#missing > 0 and (", faltan: " .. table.concat(missing, ", ")) or ""))
end

local function stepTexts(p)
  header("Textos: notas, libros y rasgos")
  local bad = {}
  for n = 1, CFG.Notes.Count do
    local note = SandevistanNotes and SandevistanNotes[n]
    if not note or type(note.title) ~= "string" or note.title == "" or type(note.text) ~= "string" or #note.text < 40 then
      bad[#bad + 1] = "nota " .. n
    elseif string.find(note.text, "IGUI_", 1, true) == 1 then
      bad[#bad + 1] = "nota " .. n .. " sin traducir"
    end
  end
  check(CFG.Notes.Count .. " notas con titulo y texto", #bad == 0, table.concat(bad, ", "))
  for _, k in ipairs({ "IGUI_Sandevistan_NotebookText", "IGUI_Sandevistan_KereNotesText" }) do
    local t = getText(k)
    check("texto " .. k, t ~= k and #t > 40)
  end
  local T = rawget(_G, "SandevistanTraits")
  for key, tk in pairs(W.TRAIT_KEYS) do
    local id = T and T.Ids[key]
    local registered = id and try(function() return CharacterTrait.get(ResourceLocation.of(id)) end) ~= nil
    local name, desc = getText("UI_trait_" .. tk), getText("UI_trait_" .. tk .. "Desc")
    check("rasgo " .. key, registered and name ~= "UI_trait_" .. tk and desc ~= "UI_trait_" .. tk .. "Desc",
      (registered and "registrado" or "NO registrado") .. ", " .. tostring(name))
  end
end

local function stepRecipes(p)
  header("Recetas nativas: cargadas, nombre, categoria, entradas y salidas")
  local SM = getScriptManager()
  for _, key in ipairs(M.SyncOrder) do
    local full = CFG.Crafting.Recipes[key]
    local r = try(function() return SM:getCraftRecipe(full) end)
    if not r then
      rec("FALLA", "receta " .. key, "NO cargada: " .. tostring(full))
    else
      local name = try(function() return r:getTranslationName() end)
      local cat = try(function() return r:getCategory() end)
      local nIn = try(function() return r:getInputs():size() end)
      local nOut = try(function() return r:getOutputs():size() end)
      local bare = M.bareName(full)
      check("receta " .. key, name ~= nil and name ~= bare and cat == "Sandevistan" and (nIn or 0) > 0 and (nOut or 0) > 0,
        string.format("'%s', categoria %s, %s entradas, %s salidas", tostring(name), tostring(cat), tostring(nIn), tostring(nOut)))
    end
  end
  check("categoria de crafteo traducida", getText("IGUI_CraftingCategories_Sandevistan") ~= "IGUI_CraftingCategories_Sandevistan")
end

-- Campos del sandbox que tocan las dificultades (se repone tal cual al terminar). Cada uno es una ruta dentro de CFG.
local PRESET_PATHS = {
  { "XP", "Multiplier" }, { "Rejection", "RateMultiplier" }, { "Overdrive", "ChestWoundChance" }, { "Overdrive", "Cyberpsychosis", "DeathChance" },
  { "NeuralLoad", "Hallucinations" }, { "NeuralLoad", "Remission", "Enabled" }, { "Overdrive", "HeatCap", "Enabled" },
  { "Immunosuppressant", "CraftedRecipeKnown" }, { "Immunosuppressant", "DurationMultiplier" }, { "Loot", "PartsMultiplier" },
  { "ExSubjects", "RespawnChance" }, { "World", "MilitaryCryoBoxCount" }, { "HeatRateMultiplier" },
  { "Psychosis", "Audio", "Enabled" }, { "Psychosis", "ThreatVision", "Enabled" }, { "Psychosis", "TimeGlitch", "Enabled" },
  { "Psychosis", "Misfire", "Enabled" }, { "Psychosis", "Blackouts", "Enabled" }, { "Psychosis", "Berserk", "Enabled" },
  { "Psychosis", "Overload", "Enabled" }, { "Psychosis", "NightTerrors", "Enabled" }, { "Prototype07", "Enabled" },
  { "Firmware", "AllKnown" }, { "Firmware", "Enabled" },
}
local function pathGet(path)
  local t = CFG
  for _, k in ipairs(path) do if type(t) ~= "table" then return nil end; t = t[k] end
  return t
end
local function pathSet(path, v)
  local t = CFG
  for i = 1, #path - 1 do t = t[path[i]] end
  t[path[#path]] = v
end

local function stepPresets(p)
  header("Dificultades del sandbox (se repone todo al terminar)")
  if not CFG.Presets then info("dificultades", "sin Config.Presets"); return end
  local snap = {}
  for i, path in ipairs(PRESET_PATHS) do snap[i] = pathGet(path) end
  local hadSV = SandboxVars and SandboxVars.Sandevistan
  local prevPreset = hadSV and SandboxVars.Sandevistan.Preset
  if not hadSV then SandboxVars = SandboxVars or {}; SandboxVars.Sandevistan = {} end
  for idx, name in ipairs(CFG.PresetNames) do
    local preset = CFG.Presets[name]
    if preset then
      SandboxVars.Sandevistan.Preset = idx
      CFG.applySandbox()
      local okAll, why = true, nil
      local map = { XPMultiplier = { "XP", "Multiplier" }, RejectionRateMultiplier = { "Rejection", "RateMultiplier" },
                    CyberpsychosisRemission = { "NeuralLoad", "Remission", "Enabled" }, HeatRateMultiplier = { "HeatRateMultiplier" },
                    ImmunoDurationMultiplier = { "Immunosuppressant", "DurationMultiplier" }, PartsLootMultiplier = { "Loot", "PartsMultiplier" },
                    CatastrophicFailureChance = { "Overdrive", "ChestWoundChance" }, Prototype07Enabled = { "Prototype07", "Enabled" },
                    FirmwareAllKnown = { "Firmware", "AllKnown" } }
      for key, path in pairs(map) do
        if pathGet(path) ~= preset[key] then okAll = false; why = key .. "=" .. tostring(pathGet(path)) .. " (esperado " .. tostring(preset[key]) .. ")" end
      end
      check("dificultad " .. name, okAll and CFG.Preset == name, why)
    end
  end
  if hadSV then SandboxVars.Sandevistan.Preset = prevPreset else SandboxVars.Sandevistan = nil end
  for i, path in ipairs(PRESET_PATHS) do pathSet(path, snap[i]) end
  CFG.Preset = nil
  check("configuracion repuesta", pathGet({ "XP", "Multiplier" }) == snap[1])
end

---------------------------------------------------------------------------
-- Menus de inventario reales
---------------------------------------------------------------------------
local function openMenu(p, item)
  local MN = SandevistanMenus
  if not MN or not MN.fillInventory then return nil, "MN.fillInventory no existe" end
  -- v0.1.30 (28): un menu PROPIO que no se registra en la UI. La primera version usaba ISContextMenu.get(0,0,0) (el menu real del jugador) y despues del
  -- recorrido el clic derecho quedo bloqueado un rato.
  local ctx = try(function() return ISContextMenu:new(0, 0, 200, 20) end)
  if not ctx then return nil, "ISContextMenu:new fallo" end
  local ok, err = pcall(MN.fillInventory, p:getPlayerNum(), ctx, { item })
  if not ok then return nil, tostring(err) end
  return ctx
end
local function menuNames(ctx)
  local names = {}
  for i = 1, (ctx.numOptions or 0) do
    local o = ctx.options and ctx.options[i]
    if o and o.name then names[#names + 1] = o.name end
  end
  return names
end
local function closeMenu(ctx) pcall(function() ctx:clear() end) end

local function closeReaders()
  local R = SandevistanReader
  if R and R.open then
    local titles = {}
    for t in pairs(R.open) do titles[#titles + 1] = t end
    for _, t in ipairs(titles) do pcall(function() R.open[t]:close() end) end
  end
end

-- Clic en la opcion con ese nombre del menu (como lo hace el juego: onSelect(target, param1, param2...)).
local function clickOption(ctx, label)
  for i = 1, (ctx.numOptions or 0) do
    local o = ctx.options[i]
    if o and o.name == label and o.onSelect then
      o.onSelect(o.target, o.param1, o.param2, o.param3, o.param4, o.param5)
      return true
    end
  end
  return false
end

local function readerOpen(title)
  local win = SandevistanReader and SandevistanReader.open and SandevistanReader.open[title]
  if not win then return nil, "la ventana '" .. tostring(title) .. "' no se abrio" end
  local lines = win.text and win.text.lines and #win.text.lines or 0
  return win, lines
end

local function stepMenus(p)
  header("Menus de inventario reales: opciones por item y boton Leer de cada nota")
  local T = M.T
  local types = { T.Lab, T.Military, T.CryoBox, T.Clinical, T.Crafted, T.Herbal, T.KereMil, T.KereCrafted,
                  T.Compound, T.PartBoard, T.PartRegulator, T.PartCell, T.PartChassis, T.PartHarness }
  for _, t in ipairs(types) do
    local item = try(function() return instanceItem(t) end)
    if not item then
      rec("FALLA", "menu " .. t, "no se pudo crear el item")
    else
      local ctx, err = openMenu(p, item)
      if not ctx then
        info("menu " .. t, "no automatizable: " .. tostring(err))
      else
        local names = menuNames(ctx)
        -- el compuesto y las partes no tienen opciones propias; los demas si
        local wantsOptions = not (t == T.Compound or t == T.PartBoard or t == T.PartRegulator or t == T.PartCell or t == T.PartChassis or t == T.PartHarness)
        check("menu " .. t, (#names > 0) == wantsOptions, #names .. " opciones" .. (#names > 0 and (": " .. table.concat(names, " | ")) or ""))
        closeMenu(ctx)
      end
    end
  end
  -- notas: "Leer" abre la ventana con el texto paginado
  local readLabel = getText("IGUI_Sandevistan_Read")
  local failed, opened = {}, 0
  for n = 1, CFG.Notes.Count do
    local item = try(function() return instanceItem(DOS.noteType(n)) end)
    local note = SandevistanNotes and SandevistanNotes[n]
    local story, page, total = DOS.storyOfNote(n)
    if not (item and note and story) then
      failed[#failed + 1] = "nota " .. n .. " (datos)"
    else
      local ctx, err = openMenu(p, item)
      if not ctx then
        failed[#failed + 1] = "nota " .. n .. " (menu: " .. tostring(err) .. ")"
      else
        pcall(clickOption, ctx, readLabel)
        closeMenu(ctx)
        local title = string.format("%s (%d/%d)", note.title, page, total)
        local win, lines = readerOpen(title)
        if win and lines > 0 then opened = opened + 1
        else failed[#failed + 1] = "nota " .. n .. " (" .. tostring(win and "sin texto paginado" or lines) .. ")" end
        closeReaders()
      end
    end
  end
  check("Leer abre la ventana en las " .. CFG.Notes.Count .. " notas", #failed == 0, opened .. "/" .. CFG.Notes.Count .. (#failed > 0 and (": " .. table.concat(failed, "; ")) or ""))
end

---------------------------------------------------------------------------
-- Pasos con espera (la accion del juego tarda): devuelven { cond, timeoutMs, onDone(timedOut) }
---------------------------------------------------------------------------
local function notDoing(p) return function() return not ISTimedActionQueue.isPlayerDoingAction(p) end end

local function bookStep(book, recipeKeys, title)
  return function(p)
    header("Lectura REAL del libro " .. book)
    local d = S.data(p)
    if not rawget(_G, "ISReadABook") then info("libro " .. book, "ISReadABook no existe"); return end
    local knowKeys = M.BOOK_KNOWS[book]
    for _, k in ipairs(knowKeys) do d.knows[k] = nil end
    if book == M.T.NotebookBook then d.knows.compound = nil end
    M.syncRecipes(p, true)
    local already = {}
    for _, k in ipairs(recipeKeys) do already[k] = M.recipeKnown(p, CFG.Crafting.Recipes[k]) end
    local anyKnown = false
    for _, v in pairs(already) do if v then anyKnown = true end end
    if anyKnown then info("libro " .. book, "las recetas ya estaban aprendidas (sandbox CraftedRecipeKnown o rasgo): no se puede probar el aprendizaje"); return end
    local item = giveItem(p, book)
    if not item then rec("FALLA", "libro " .. book, "no se pudo crear"); return end
    instantOn(p)
    local ok, err = pcall(function() ISTimedActionQueue.add(ISReadABook:new(p, item)) end)
    if not ok then rec("FALLA", "libro " .. book, "no se pudo encolar la lectura: " .. tostring(err)); return end
    return { cond = notDoing(p), timeoutMs = W.ACTION_TIMEOUT_MS, onDone = function(timedOut)
      if timedOut then rec("FALLA", "libro " .. book, "la lectura no termino en " .. (W.ACTION_TIMEOUT_MS / 1000) .. " s") end
      local okAll = true
      for _, k in ipairs(recipeKeys) do
        local known = M.recipeKnown(p, CFG.Crafting.Recipes[k])
        if not known then okAll = false end
        check("libro " .. book .. ": aprende " .. k, known)
      end
      check("libro " .. book .. ": el mod lo anota", d.knows[knowKeys[1]] == true)
      local win, lines = readerOpen(title())
      check("libro " .. book .. ": muestra el texto", win ~= nil, win and (lines .. " lineas") or lines)
      closeReaders()
    end }
  end
end

local PART_QUALS = { 1.0, 1.4, 1.3, 1.1, 1.2 }        -- (68) una calidad por parte (PartOrder): el promedio es 1.20
-- Ingredientes de vanilla por receta (todo se crea de cero; el crafteo consume los primeros que encuentre: por eso se recomienda personaje de prueba)
local function alcohol(p) giveItem(p, V.Disinfectant) end
local PROVISION = {
  compound = function(p) giveItem(p, V.MortarCeramic or V.Mortar); giveItem(p, V.Painkillers); giveItem(p, V.Coldpack); alcohol(p) end,
  crafted = function(p) giveItem(p, V.Mortar); giveItem(p, V.Painkillers); giveItem(p, M.T.Compound); alcohol(p) end,
  herbal = function(p) giveItem(p, V.Mortar); for _ = 1, 2 do giveItem(p, V.WildGarlic); giveItem(p, V.BlackSage) end; alcohol(p) end,
  kerenzikov = function(p) giveItem(p, V.Painkillers); giveItem(p, V.Caffeine); alcohol(p) end,
  board = function(p) giveItem(p, V.Screwdriver); for _ = 1, 4 do giveItem(p, V.ElectronicsScrap) end; for _ = 1, 2 do giveItem(p, V.Wire) end end,
  regulator = function(p) giveItem(p, V.Screwdriver); for _ = 1, 2 do giveItem(p, V.SmallSheetMetal); giveItem(p, V.ElectronicsScrap) end; giveItem(p, V.Wire) end,
  cell = function(p) giveItem(p, V.Screwdriver); giveItem(p, V.Battery); giveItem(p, V.Wire); for _ = 1, 2 do giveItem(p, V.ElectronicsScrap) end end,
  -- v0.1.30 (68): chasis (sin habilidad desde la (122)) y arnes (Costura); la aguja es la unica pieza cuyo ID no esta verificado: si no se crea, el paso de crafteo lo dice
  chassis = function(p) giveItem(p, V.Screwdriver); for _ = 1, 6 do giveItem(p, V.Screws) end; for _ = 1, 4 do giveItem(p, V.SmallSheetMetal) end end,
  harness = function(p) giveItem(p, V.Needle); giveItem(p, V.Twine); for _ = 1, 2 do giveItem(p, V.LeatherStrips); giveItem(p, V.Wire) end end,
  -- v0.1.30 (43): Prototipo 07 (militar) y planos
  board07 = function(p) giveItem(p, V.Screwdriver); for _ = 1, 6 do giveItem(p, V.ElectronicsScrap) end; for _ = 1, 2 do giveItem(p, V.Wire) end; giveItem(p, M.T.MilChip) end,
  regulator07 = function(p) giveItem(p, V.Screwdriver); for _ = 1, 2 do giveItem(p, V.SmallSheetMetal); giveItem(p, V.ElectronicsScrap) end; giveItem(p, V.Wire); for _ = 1, 3 do giveItem(p, V.Coldpack) end end,
  chip07 = function(p) giveItem(p, V.Screwdriver); for _ = 1, 12 do giveItem(p, V.ElectronicsScrap) end; for _ = 1, 3 do giveItem(p, V.Wire) end end,
  cell07 = function(p) giveItem(p, V.Screwdriver); for _ = 1, 2 do giveItem(p, V.Battery); giveItem(p, V.Wire); giveItem(p, V.ElectronicsScrap) end end,
  chassis07 = function(p) giveItem(p, V.Screwdriver); for _ = 1, 8 do giveItem(p, V.Screws) end; for _ = 1, 5 do giveItem(p, V.SmallSheetMetal) end end,
  harness07 = function(p) giveItem(p, V.Needle); giveItem(p, V.Twine); for _ = 1, 3 do giveItem(p, V.LeatherStrips); giveItem(p, V.Wire) end; for _ = 1, 2 do giveItem(p, V.ElectronicsScrap) end end,
  proto07 = function(p)
    for _, key in ipairs(CFG.Prototype07.PartOrder) do purgeNew(p, CFG.Prototype07.Parts[key].item) end
    purgeNew(p, M.T.Military)
    giveItem(p, V.Screwdriver); for _ = 1, 2 do giveItem(p, V.ElectronicsScrap) end; giveItem(p, M.T.KereMil); giveItem(p, M.T.KereCrafted)
    local RC = SandevistanRecipeCode
    for i, key in ipairs(CFG.Prototype07.PartOrder) do RC.setPartQuality(giveItem(p, CFG.Prototype07.Parts[key].item), PART_QUALS[i]) end
  end,
  plan06 = function(p) giveItem(p, V.Pen); for _ = 1, 3 do giveItem(p, V.Paper) end end,
  plan07 = function(p) giveItem(p, V.Pen); for _ = 1, 5 do giveItem(p, V.Paper) end end,
  proto06 = function(p)
    for _, key in ipairs(CFG.Prototype06.PartOrder) do purgeNew(p, CFG.Prototype06.Parts[key].item) end       -- las partes de los pasos anteriores no cuentan
    purgeNew(p, M.T.Lab)
    giveItem(p, V.Screwdriver); for _ = 1, 2 do giveItem(p, V.ElectronicsScrap) end; giveItem(p, M.T.Compound)
    local RC = SandevistanRecipeCode
    for i, key in ipairs(CFG.Prototype06.PartOrder) do RC.setPartQuality(giveItem(p, CFG.Prototype06.Parts[key].item), PART_QUALS[i]) end
  end,
}
-- Que tiene que haber despues de craftear
local function onCreatePart(p, key, design)
  local RC = SandevistanRecipeCode
  local def = (design or CFG.Prototype06).Parts[key]
  local item = giveItem(p, def.item)
  if not item then return false, "no se pudo crear" end
  RC.onCreatePart({ getAllCreatedItems = function() return { size = function() return 1 end, get = function() return item end } end }, p)
  local q = tonumber(item:getModData().partQuality)
  local name = try(function() return item:getName() end)
  return q ~= nil and name ~= nil and string.find(name, "(", 1, true) ~= nil, "calidad " .. tostring(q) .. ", nombre '" .. tostring(name) .. "'"
end
-- OnCreate de cada receta que tiene uno (las demas no: el juego entrega el item y listo)
local function listOf(items) return { size = function() return #items end, get = function(_, i) return items[i + 1] end } end

local VERIFY_ONCREATE = {
  board = function(p) return onCreatePart(p, "board") end,
  regulator = function(p) return onCreatePart(p, "regulator") end,
  cell = function(p) return onCreatePart(p, "cell") end,
  chassis = function(p) return onCreatePart(p, "chassis") end,
  harness = function(p) return onCreatePart(p, "harness") end,
  board07 = function(p) return onCreatePart(p, "board", CFG.Prototype07) end,
  regulator07 = function(p) return onCreatePart(p, "regulator", CFG.Prototype07) end,
  cell07 = function(p) return onCreatePart(p, "cell", CFG.Prototype07) end,
  chassis07 = function(p) return onCreatePart(p, "chassis", CFG.Prototype07) end,
  harness07 = function(p) return onCreatePart(p, "harness", CFG.Prototype07) end,
  proto07 = function(p)
    local RC = SandevistanRecipeCode
    local parts = {}
    for i, key in ipairs(CFG.Prototype07.PartOrder) do
      local it = giveItem(p, CFG.Prototype07.Parts[key].item)
      if it then RC.setPartQuality(it, PART_QUALS[i]); parts[#parts + 1] = it end
    end
    local mil = giveItem(p, M.T.Military)
    if not mil then return false, "no se pudo crear el implante" end
    RC.forcedChance = 1
    RC.onCreateProto07({ getAllCreatedItems = function() return listOf({ mil }) end, getAllConsumedItems = function() return listOf(parts) end }, p)
    RC.forcedChance = nil
    local q = tonumber(mil:getModData().heatDegradationMultiplier)
    local lp = RC.lastProto07
    return mil:getModData().prototype == "07" and q ~= nil and math.abs(q - 1.20) < 0.011,
      "calidad " .. tostring(q) .. " (esperada 1.20), partes leidas " .. tostring(lp and lp.partsRead) .. "/5"
  end,
  proto06 = function(p)
    local RC = SandevistanRecipeCode
    local parts = {}
    for i, key in ipairs(CFG.Prototype06.PartOrder) do
      local it = giveItem(p, CFG.Prototype06.Parts[key].item)
      if it then RC.setPartQuality(it, PART_QUALS[i]); parts[#parts + 1] = it end
    end
    local lab = giveItem(p, M.T.Lab)
    if not lab then return false, "no se pudo crear el implante" end
    RC.forcedChance = 1
    RC.onCreateProto06({ getAllCreatedItems = function() return listOf({ lab }) end, getAllConsumedItems = function() return listOf(parts) end }, p)
    RC.forcedChance = nil
    local q = tonumber(lab:getModData().heatDegradationMultiplier)
    local lp = RC.lastProto06
    return lab:getModData().prototype == "06" and q ~= nil and math.abs(q - 1.20) < 0.011,
      "calidad " .. tostring(q) .. " (esperada 1.20), partes leidas " .. tostring(lp and lp.partsRead) .. "/5"
  end,
}

-- Crafteo en dos partes, sin la ventana de crafteo: (1) el juego tiene que dar por validos los ingredientes de la receta (CraftRecipeManager, sin estado) y
-- (2) lo que hace el mod al crear el resultado (OnCreate) se corre con items reales. v0.1.30 (28): la primera version intentaba craftear con HandcraftLogic
-- y daba "puede=false" en todas (esa logica depende de la ventana de crafteo para llenar su inventario) y dejo el juego raro un rato: se quito.
local function craftStep(key)
  return function(p)
    header("Crafteo de " .. key .. ": ingredientes validos para el juego y OnCreate con items reales")
    local full = CFG.Crafting.Recipes[key]
    local recipe = try(function() return getScriptManager():getCraftRecipe(full) end)
    if not recipe then rec("FALLA", "crafteo " .. key, "receta no cargada"); return end
    pcall(function() p:learnRecipe(M.bareName(full)) end)           -- se repone al final (syncRecipes estricto)
    PROVISION[key](p)
    -- (1) cada entrada de la receta tiene que aceptar al menos un item del inventario
    local inputs = try(function() return recipe:getInputs() end)
    if not inputs then info("crafteo " .. key, "no automatizable: recipe:getInputs() no disponible"); return end
    local CRM = rawget(_G, "CraftRecipeManager")
    if not CRM or not CRM.isItemValidForInputScript then info("crafteo " .. key, "no automatizable: CraftRecipeManager.isItemValidForInputScript no existe"); return end
    local inv = p:getInventory():getItems()
    local unsatisfied = {}
    for i = 0, inputs:size() - 1 do
      local inp = inputs:get(i)
      local found = false
      for j = 0, inv:size() - 1 do
        local ok, valid = pcall(CRM.isItemValidForInputScript, inp, inv:get(j), p)
        if ok and valid == true then found = true; break end
      end
      if not found then unsatisfied[#unsatisfied + 1] = tostring(try(function() return inp:getOriginalLine() end) or ("entrada " .. (i + 1))) end
    end
    check("crafteo " .. key .. ": los ingredientes son validos para el juego", #unsatisfied == 0, #unsatisfied > 0 and ("sin ingrediente para: " .. table.concat(unsatisfied, " | ")) or (inputs:size() .. " entradas"))
    -- el juego da la receta por valida para el personaje (conocida, habilidades): informativo, depende del nivel del personaje
    local valid = try(function() return CRM.isValidRecipeForCharacter(recipe, p, nil, nil) end)
    info("crafteo " .. key .. ": receta valida para el personaje", tostring(valid) .. (valid == false and " (probablemente falta nivel: subi las habilidades con el menu debug)" or ""))
    -- (2) OnCreate con items reales
    local out = VERIFY_ONCREATE[key]
    if out then
      local ok, detail = out(p)
      check("crafteo " .. key .. ": OnCreate deja lo esperado", ok == true, detail)
    end
  end
end

---------------------------------------------------------------------------
-- Pasos manuales (si / no)
---------------------------------------------------------------------------
local function ask(p, name, text)
  local answered = false
  local modal = SandevistanDialog.yesNo(p:getPlayerNum(), text, 520, 260, function(yes)
    answered = true
    rec(yes and "SI" or "NO", name)
  end)
  if not modal then info(name, "no se pudo mostrar la pregunta"); return end
  return { cond = function() return answered end, timeoutMs = W.ANSWER_TIMEOUT_MS, onDone = function(timedOut)
    if timedOut then
      rec("SIN RESPUESTA", name)
      pcall(function() modal:setVisible(false); modal:removeFromUIManager() end)
    end
  end }
end

local FLOOR_TYPES = function()
  local T = M.T
  return { T.Lab, T.Military, T.P04, T.CryoBox, T.Harness, T.Clinical, T.Crafted, T.Herbal, T.Compound, T.KereMil, T.KereCrafted, T.PartBoard,
           T.PartRegulator, T.PartCell, T.PartChassis, T.PartHarness, T.NotebookBook, T.KereBook, T.Blueprint06, T.Blueprint07, T.MilChip,
           CFG.Prototype07.Parts.board.item, CFG.Prototype07.Parts.regulator.item, CFG.Prototype07.Parts.cell.item, CFG.Prototype07.Parts.chassis.item, CFG.Prototype07.Parts.harness.item, DOS.noteType(1), DOS.noteType(2), DOS.noteType(11), DOS.noteType(13),
           "Sandevistan.SandevistanDossierResearcher", "Sandevistan.SandevistanDossierDepot", "Sandevistan.SandevistanDossierStudent",
           "Sandevistan.FwBlank", "Sandevistan.FwCompatibilidad", "Sandevistan.FwMartillo", "Sandevistan.FwCamaraCriogenica" }
end

local function stepFloor(p)
  header("Manual: modelos de los items en el piso")
  local cell = getCell()
  local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), p:getZ()
  local n = 0
  for i, t in ipairs(FLOOR_TYPES()) do
    local col, row = (i - 1) % 6, math.floor((i - 1) / 6)
    local sq = cell and cell:getGridSquare(px + 2 + col, py - 2 + row, pz)
    if sq then
      local it = try(function() return sq:AddWorldInventoryItem(t, 0.5, 0.5, 0) end)
      if it then n = n + 1; run.floor[#run.floor + 1] = it end
    end
  end
  info("items tirados en el piso", n .. " (6 por fila, a tu derecha)")
  return ask(p, "los modelos del piso se ven bien (ninguno gigante, invisible ni negro)", "Hay " .. n .. " items tirados en el piso a tu derecha, 6 por fila "
    .. "(implantes, cajas, inmunosupresores en forma de puff, partes, libros, notas, carpetas y los chips de firmware, que son EPROM chicas sin patas con una etiqueta de color: "
    .. "verde los de Sistema y violeta los de Habilidad; mira que no sean ni gigantes ni microscopicas, el nombre se lee en el inventario). <LINE> Mira si se ven bien: ninguno gigante, invisible o negro. <LINE> <LINE> Se ven bien?")
end

local function stepReaders(p)
  header("Manual: ventanas de lectura")
  local R = SandevistanReader
  if not R then info("ventanas de lectura", "sin SandevistanReader"); return end
  local MN = SandevistanMenus
  local samples = { { 1, "paper" }, { 2, "military" }, { 11, "sticky" }, { 13, "student" } }
  for _, s in ipairs(samples) do
    local note = SandevistanNotes and SandevistanNotes[s[1]]
    if note then MN.showText(p, note.title, note.text, nil, nil, s[2]) end
  end
  local guide = false
  if MN and MN.showGuide then guide = pcall(MN.showGuide, p) end            -- (45) la guia de campo de 7 paginas (Anterior / Siguiente)
  return ask(p, "las ventanas de lectura y la guia de campo se ven bien y se pueden arrastrar", "Se abrieron 4 ventanas de lectura (papel, militar, papelito amarillo, cuaderno lila)"
    .. (guide and " y la guia de campo de 7 paginas (con botones Anterior / Siguiente)" or "") .. ". <LINE> "
    .. "Arrastralas de la barra de titulo, cambiales el tamano desde la esquina y proba el scroll y los botones de la guia. <LINE> <LINE> Se ven legibles y se mueven bien?")
end

local function stepCraftTab(p)
  header("Manual: pestana del menu de crafteo")
  closeReaders()
  return ask(p, "el menu de crafteo tiene la pestana Sandevistan con las 20 recetas y sus nombres", "Abri el menu de crafteo del juego (con el menu de tu personaje o la tecla de crafteo). <LINE> "
    .. "Tiene que haber una pestana 'Sandevistan' con 20 recetas con nombre (no el ID interno): compuesto, inmunosupresores x2, Kerenzikov, las 5 partes y el Prototipo 06, las 5 partes militares, el microchip y el Mk. II, redactar planos (P06 y militar) y el chip de firmware virgen. <LINE> <LINE> Esta bien?")
end

local function stepSoundCheck(p)
  header("Manual: sonidos de uso")
  local E = SandevistanEffects
  pcall(function() E.sound(p, "SandevistanDoseImmuno") end)
  return ask(p, "se oyo el sonido del inmunosupresor", "Acabas de oir el sonido del inmunosupresor? <LINE> (Si no, revisa el volumen del juego y volve a correr el recorrido.)")
end

---------------------------------------------------------------------------
-- v0.1.30 (45): pasos que acumulan lo agregado desde el ultimo recorrido (Mk. II, planos, tooltip de la skill, XP por fuente, escenas, HUD, trepar)
---------------------------------------------------------------------------
local function stepMarkII(p)
  header("Mk. II (replica militar): etiquetas, textos, estudio y planos")
  local T = M.T
  check("etiqueta de pantalla Mk.II", S.protoLabel("07") == "Mk.II" and S.protoLabel("06") == "P06" and S.protoLabel("04") == "P04")
  local bad = {}
  for _, k in ipairs({ "IGUI_Sandevistan_ItemName_P07", "IGUI_Sandevistan_Info_P07", "IGUI_Sandevistan_StudyMil", "IGUI_Sandevistan_StudyMilWarning",
                       "IGUI_Sandevistan_StudyMilOK", "IGUI_Sandevistan_Req_Dossiers", "IGUI_Sandevistan_Proto07OK", "IGUI_Sandevistan_Proto07Fail",
                       "IGUI_Sandevistan_Proto06Fail", "IGUI_Sandevistan_Blueprint06Title", "IGUI_Sandevistan_Blueprint06Text", "IGUI_Sandevistan_Blueprint07Title",
                       "IGUI_Sandevistan_Blueprint07Text", "IGUI_Sandevistan_Scene_IdP07", "IGUI_Sandevistan_Guide_Page7_Text" }) do
    local t = getText(k)
    if t == k or #t < 8 then bad[#bad + 1] = k end
  end
  check("textos del Mk. II y de los planos traducidos", #bad == 0, table.concat(bad, ", "))
  -- el menu del militar trae el estudio del diseno militar (deshabilitado si faltan los expedientes)
  if not CFG.Prototype07.Enabled then
    info("menu de estudio militar", "el Mk. II esta apagado por sandbox")
  elseif M.knows(p, "proto07") then
    info("menu de estudio militar", "ya conoces el diseno: la opcion no aparece")
  else
    local item = try(function() return instanceItem(T.Military) end)
    local ctx, err = item and openMenu(p, item)
    if not ctx then
      info("menu de estudio militar", "no automatizable: " .. tostring(err))
    else
      local want, found = getText("IGUI_Sandevistan_StudyMil"), false
      for _, n in ipairs(menuNames(ctx)) do if n == want then found = true end end
      check("el militar ofrece 'Estudiar el diseno militar'", found, table.concat(menuNames(ctx), " | "))
      closeMenu(ctx)
    end
  end
  -- los planos y las partes militares existen, con nombre
  local P7 = CFG.Prototype07
  local types = { T.Blueprint06, T.Blueprint07, T.MilChip, P7.Parts.board.item, P7.Parts.regulator.item, P7.Parts.cell.item, P7.Parts.chassis.item, P7.Parts.harness.item }
  local probs = {}
  for _, t in ipairs(types) do
    local it = try(function() return instanceItem(t) end)
    local name = it and try(function() return it:getDisplayName() end)
    if not it then probs[#probs + 1] = t .. " (no se crea)" elseif not name or name == "" or string.find(name, "ItemName_", 1, true) then probs[#probs + 1] = t .. " (sin nombre)" end
  end
  check("planos, microchip y partes militares: se crean con nombre", #probs == 0, table.concat(probs, ", "))
  -- calibrar sigue valiendo para un implante ensamblado (sin piso de desgaste vuelve a 1.0)
  local mk = try(function() return instanceItem(T.Military) end)
  if mk then
    mk:getModData().heatDegradationMultiplier = 1.2; mk:getModData().prototype = "07"
    local deg, floor = M.itemDegradation(mk)
    check("un Mk. II degradado no tiene piso de desgaste (calibrable a 1.0)", deg > 1.0 and floor <= 1.0, tostring(deg) .. " / piso " .. tostring(floor))
  end
end

-- v0.1.30 (85): aprender y escribir programas. Textos, recetas nativas del chip virgen y del terminal, el menu real del terminal y, con un implante que funciona, escribir un programa
-- con la logica real (el chip virgen y la bateria se gastan, sale el chip). Los items que crea los borra el final del recorrido; lo aprendido se repone aca.
local function stepFirmwareWrite(p)
  local FW, FC = rawget(_G, "SandevistanFirmware"), rawget(_G, "SandevistanFirmwareClient")
  local W = CFG.Firmware.Write
  local keys = { "IGUI_Sandevistan_Fw_WritePC", "IGUI_Sandevistan_Fw_WriteTerminal", "IGUI_Sandevistan_Fw_WriteOption", "IGUI_Sandevistan_Fw_WriteTime", "IGUI_Sandevistan_Fw_Written",
    "IGUI_Sandevistan_Fw_Learned", "IGUI_Sandevistan_Fw_Req_Unknown", "IGUI_Sandevistan_Fw_Req_NoneKnown", "IGUI_Sandevistan_Fw_Req_BlankChip", "IGUI_Sandevistan_Fw_Req_MilChip",
    "IGUI_Sandevistan_Fw_Req_Power", "IGUI_Sandevistan_Fw_Req_Battery", "IGUI_Sandevistan_Fw_Req_Terminal", "IGUI_Sandevistan_Info_FwKnown", "IGUI_Sandevistan_Info_FwNext",
    "IGUI_Sandevistan_Guide_Page8_Title", "IGUI_Sandevistan_Guide_Page8_Text" }
  local bad = {}
  for _, k in ipairs(keys) do local t = getText(k); if t == k or #t < 3 then bad[#bad + 1] = k end end
  local termName = try(function() local it = instanceItem(W.Terminal); return it and it:getDisplayName() end)           -- los nombres de item no son claves de getText
  if not termName or termName == "" or string.find(termName, "ItemName_", 1, true) then bad[#bad + 1] = "nombre del item " .. W.Terminal end
  check("textos de escribir y aprender programas traducidos", #bad == 0, table.concat(bad, ", "))
  check("la guia de campo tiene la pagina del firmware", CFG.Guide.Pages == 8, tostring(CFG.Guide.Pages))
  local chipRecipe = M.nativeRecipe("fwchip")
  check("la receta nativa del chip virgen esta cargada", chipRecipe ~= nil, tostring(chipRecipe))
  local d = S.data(p)
  info("el personaje sabe fabricar el chip virgen (con un implante si)", tostring(M.knows(p, "firmware")) .. " | receta del juego: " .. tostring(M.recipeKnown(p, CFG.Crafting.Recipes.fwchip)))
  local missing = {}
  for _, ft in ipairs({ W.Terminal, FW.BLANK, W.MilitaryChip }) do
    local it = try(function() return instanceItem(ft) end)
    if not it then missing[#missing + 1] = ft end
  end
  check("existen el terminal, el chip virgen y el microchip militar", #missing == 0, table.concat(missing, ", "))
  -- el menu real del terminal (aunque no se conozca ningun programa, la opcion existe)
  local term = giveItem(p, W.Terminal)
  local ctx = term and openMenu(p, term)
  if ctx then
    local want, found = getText("IGUI_Sandevistan_Fw_WriteTerminal"), false
    for _, n in ipairs(menuNames(ctx)) do if n == want then found = true end end
    check("el terminal ofrece 'Escribir firmware con el terminal' en el menu real", found, table.concat(menuNames(ctx), " | "))
    closeMenu(ctx)
  else
    info("menu del terminal", "no automatizable")
  end
  if not S.hasWorkingImplant(d) then
    info("aprender y escribir con la logica real", "el personaje de prueba no tiene un implante que funcione (Debug > Estado > Implante y adaptacion > Instalar)")
    return
  end
  local keepKnown = deepcopy(d.fwKnown)
  d.fwKnown = {}
  local learned = FW.syncKnown(d)
  info("programas que se aprenden con el nivel actual (" .. tostring(S.level(d)) .. ")", #learned .. ": " .. table.concat(learned, ", "))
  d.fwKnown = {}; d.fwKnown.Martillo = true
  local blank, battery = giveItem(p, FW.BLANK), giveItem(p, W.Battery)
  local src = { kind = "terminal", item = term }
  local function cnt(t) return p:getInventory():getCountTypeRecurse(t) end
  local c0 = { chip = cnt(FW.itemType("Martillo")), blank = cnt(FW.BLANK), battery = cnt(W.Battery) }        -- por diferencia: el personaje puede llevar chips o baterias propios
  local reasons = term and blank and battery and FC.writeReasons(p, "Martillo", src) or { "faltan items de prueba" }
  check("con el chip virgen, la bateria y el terminal no falta nada para escribir Martillo", #reasons == 0, table.concat(reasons, " | "))
  if #reasons == 0 then
    local ok = FC.write(p, "Martillo", src)
    check("escribir gasta el chip virgen y la bateria y entrega el chip del programa", ok == true and cnt(FW.itemType("Martillo")) == c0.chip + 1
      and cnt(FW.BLANK) == c0.blank - 1 and cnt(W.Battery) == c0.battery - 1,
      string.format("%s | chips %d -> %d, virgenes %d -> %d, baterias %d -> %d", tostring(ok), c0.chip, cnt(FW.itemType("Martillo")), c0.blank, cnt(FW.BLANK), c0.battery, cnt(W.Battery)))
  end
  d.fwKnown = keepKnown or {}
end

-- v0.1.30 (86): Taller (modo trabajo). Textos y ganchos de las acciones mas rapidas: que clases de acciones del juego enganchamos (la duracion real de una accion se mide en el juego con el
-- modo trabajo encendido: Debug > Firmware > "Modo trabajo (Taller)") y que el estado del modo trabajo tiene sentido.
local function stepFirmwareWork(p)
  local FW, FC = rawget(_G, "SandevistanFirmware"), rawget(_G, "SandevistanFirmwareClient")
  local Wk = CFG.Firmware.Work
  local keys = { "IGUI_Sandevistan_Fw_WorkCN", "IGUI_Sandevistan_Fw_WorkRejection", "IGUI_Sandevistan_Fw_WorkStop_limit", "IGUI_Sandevistan_Fw_WorkStop_stamina",
    "IGUI_Sandevistan_Fw_WorkStop_threat", "IGUI_Sandevistan_Info_FwWork", "IGUI_Sandevistan_Info_FwWorkNow", "IGUI_Sandevistan_FwDesc_Taller" }
  local bad = {}
  for _, k in ipairs(keys) do local t = getText(k); if t == k or #t < 3 then bad[#bad + 1] = k end end
  check("textos del modo trabajo traducidos", #bad == 0, table.concat(bad, ", "))
  check("Taller esta terminado y es un chip de Habilidad que cambia el modo", CFG.Firmware.Programs.Taller.ready == true and FW.profile({ firmware = { habilidad = "Taller" }, variant = "lab" }).mode == "work")
  local hooked, missing, extra = {}, {}, {}
  for k in pairs(FC.work.classes) do hooked[#hooked + 1] = k end
  for k in pairs(FC.work.missing) do missing[#missing + 1] = k end
  table.sort(hooked); table.sort(missing)
  for _, n in ipairs(Wk.Actions) do if FC.work.classes[n] ~= true and FC.work.missing[n] ~= true then extra[#extra + 1] = n end end
  if Wk.ActionsEnabled then
    check("se engancho getDuration de al menos una clase de acciones del juego (fabricar)", FC.work.classes.ISHandcraftAction == true or FC.work.classes.ISCraftAction == true,
      "enganchadas: " .. table.concat(hooked, ", ") .. " | no existen: " .. table.concat(missing, ", "))
    info("clases de acciones enganchadas por el modo trabajo", #hooked .. ": " .. table.concat(hooked, ", ") .. " | no existen en esta version: " .. table.concat(missing, ", "))
    info("ISBaseTimedAction.adjustMaxTime enganchado (refuerzo)", tostring(FC.work.base))
  else
    info("acciones mas rapidas del modo trabajo", "apagadas por Work.ActionsEnabled")
  end
  info("acciones aceleradas hasta ahora", tostring(FC.work.scaled) .. (FC.work.last and (" (ultima: " .. tostring(FC.work.last) .. ")") or ""))
end

-- v0.1.30 (87): decompilar chips programados y los chips del mundo. Textos, el menu real del terminal y el de un chip programado con un terminal encima, y el botin (cuantas entradas hay
-- en las tablas y que tablas "Army*" existen en esta version). Lo aprendido se repone.
local function stepFirmwareDecompile(p)
  local FW, FC = rawget(_G, "SandevistanFirmware"), rawget(_G, "SandevistanFirmwareClient")
  local W = CFG.Firmware.Write
  local keys = { "IGUI_Sandevistan_Fw_DecompilePC", "IGUI_Sandevistan_Fw_DecompileTerminal", "IGUI_Sandevistan_Fw_DecompileThis", "IGUI_Sandevistan_Fw_DecompileTime", "IGUI_Sandevistan_Fw_Decompiled",
    "IGUI_Sandevistan_Fw_Req_AlreadyKnown", "IGUI_Sandevistan_Fw_Req_ChipMissing", "IGUI_Sandevistan_Fw_LearnedDossier", "IGUI_Sandevistan_Fw_DetailDossier", "IGUI_Sandevistan_Fw_DetailDecompile" }
  local bad = {}
  for _, k in ipairs(keys) do local t = getText(k); if t == k or #t < 3 then bad[#bad + 1] = k end end
  check("textos de decompilar traducidos", #bad == 0, table.concat(bad, ", "))
  local missing = {}
  for _, id in ipairs(CFG.Firmware.Order) do
    local it = try(function() return instanceItem(FW.itemType(id)) end)
    if not it then missing[#missing + 1] = id end
  end
  check("los " .. #CFG.Firmware.Order .. " chips programados se crean (los que se reparten en el mundo)", #missing == 0, table.concat(missing, ", "))
  local d = S.data(p)
  local keepKnown = deepcopy(d.fwKnown)
  d.fwKnown = {}
  local term, chip = giveItem(p, W.Terminal), giveItem(p, FW.itemType("Overclock"))
  local ctx = term and chip and openMenu(p, term)
  if ctx then
    local want, found = getText("IGUI_Sandevistan_Fw_DecompileTerminal"), false
    for _, n in ipairs(menuNames(ctx)) do if n == want then found = true end end
    check("el terminal con un chip programado encima ofrece 'Decompilar un chip con el terminal'", found, table.concat(menuNames(ctx), " | "))
    closeMenu(ctx)
  else
    info("menu del terminal con un chip programado", "no automatizable")
  end
  local ctx2 = chip and term and openMenu(p, chip)
  if ctx2 then
    local want, found = getText("IGUI_Sandevistan_Fw_DecompileThis"), false
    for _, n in ipairs(menuNames(ctx2)) do if n == want then found = true end end
    check("el chip programado ofrece 'Decompilar este chip con el terminal' si llevas el terminal y no sabes el programa", found, table.concat(menuNames(ctx2), " | "))
    closeMenu(ctx2)
  end
  -- el botin: cuantas entradas hay y que tablas "Army*" existen (los nombres de 42.21 no estan verificados)
  local PD = rawget(_G, "ProceduralDistributions")
  if PD and PD.list then
    local total, army = 0, {}
    for name, dist in pairs(PD.list) do
      if type(dist) == "table" and type(dist.items) == "table" then
        if string.find(name, "Army", 1, true) then army[#army + 1] = name end
        for i = 1, #dist.items, 2 do
          local t = dist.items[i]
          if type(t) == "string" and string.sub(t, 1, 14) == "Sandevistan.Fw" and t ~= FW.BLANK then total = total + 1 end
        end
      end
    end
    table.sort(army)
    if isClient() and total == 0 then info("botin con chips programados", "en multijugador lo reparte el servidor (el cliente no ve esas entradas)")
    else check("las tablas de botin traen chips programados", total > 0, total .. " entradas") end
    info("tablas 'Army*' que existen en esta version (" .. #army .. ")", #army > 0 and table.concat(army, ", ") or "ninguna: ajustar Config.Loot.FwProgrammedArmy y MilChip")
  else
    info("botin con chips programados", "sin ProceduralDistributions en este entorno")
  end
  d.fwKnown = keepKnown or {}
end

-- v0.1.30 (82): firmware. Textos, detalle de cada programa, menu real de un chip y, si el personaje tiene un implante que funciona, instalar y sacar un chip con la
-- logica real viendo cambiar el perfil y la pestana Implante (se repone todo).
local function stepFirmware(p)
  header("Firmware (chips): textos, menu del chip, instalar y sacar con el perfil")
  local FW, FC = rawget(_G, "SandevistanFirmware"), rawget(_G, "SandevistanFirmwareClient")
  if not (FW and FC) then info("firmware", "sin SandevistanFirmware o SandevistanFirmwareClient"); return end
  check("el firmware esta activo en esta partida", FW.enabled(), "opcion de sandbox FirmwareEnabled")
  if not FW.enabled() then return end
  local okWrite, errWrite = pcall(stepFirmwareWrite, p)                        -- (85) aprender y escribir
  if not okWrite then check("aprender y escribir programas", false, tostring(errWrite)) end
  local okWork, errWork = pcall(stepFirmwareWork, p)                           -- (86) Taller: modo trabajo
  if not okWork then check("modo trabajo (Taller)", false, tostring(errWork)) end
  local okDec, errDec = pcall(stepFirmwareDecompile, p)                         -- (87) decompilar y chips del mundo
  if not okDec then check("decompilar y chips del mundo", false, tostring(errDec)) end
  local F = CFG.Firmware
  local bad = {}
  for _, id in ipairs(F.Order) do
    local keys = { "IGUI_Sandevistan_Fw_Name_" .. id }
    if F.Programs[id].ready then keys[#keys + 1] = "IGUI_Sandevistan_FwDesc_" .. id end
    for _, k in ipairs(keys) do
      local t = getText(k)
      if t == k or #t < 3 then bad[#bad + 1] = k end
    end
  end
  check("nombres y descripciones de los programas traducidos", #bad == 0, table.concat(bad, ", "))
  local probs = {}
  for _, id in ipairs(F.Order) do
    local ok, title, body = pcall(FC.detail, p, id)
    if not ok or not title or not body or #body < 20 then probs[#probs + 1] = id end
  end
  check("el detalle de los " .. #F.Order .. " programas se arma", #probs == 0, table.concat(probs, ", "))
  -- el menu real de un chip ofrece instalarlo
  local item = try(function() return instanceItem(FW.itemType("Compatibilidad")) end)
  local ctx, err = item and openMenu(p, item)
  if not ctx then
    info("menu del chip", "no automatizable: " .. tostring(err))
  else
    local want, found = getText("IGUI_Sandevistan_Fw_Install", getText("IGUI_Sandevistan_Fw_Slot_sistema")), false
    for _, n in ipairs(menuNames(ctx)) do if n == want then found = true end end
    check("el chip ofrece 'Instalar firmware (Sistema)'", found, table.concat(menuNames(ctx), " | "))
    closeMenu(ctx)
  end
  -- instalar y sacar con la logica real (hace falta un implante que funcione y apagado)
  local d = S.data(p)
  if not S.hasWorkingImplant(d) then
    info("instalar y sacar un chip", "el personaje de prueba no tiene un implante que funcione (Debug > Estado > Implante y adaptacion > Instalar)")
    return
  end
  local snap = { rejection = d.rejection, recal = d.fwRecalUntil, fw = deepcopy(d.firmware) }
  d.firmware = {}; d.fwRecalUntil = nil
  local level = S.level(d)
  local plain = S.heatPerSecond(d, level)
  local chip = giveItem(p, FW.itemType("Compatibilidad"))
  local reasons = FC.flashReasons(p, "Compatibilidad")
  local okFlash = chip ~= nil and #reasons == 0 and FC.flash(p, chip) == true
  check("instalar el Compatibilidad lo deja en el slot de Sistema", okFlash and d.firmware.sistema == "Compatibilidad", #reasons > 0 and table.concat(reasons, " | ") or tostring(d.firmware.sistema))
  if okFlash then
    local changed = S.heatPerSecond(d, level)
    check("el Heat por segundo cambia con el chip (x1.1, mas el 10 % del recalibrado)", math.abs(changed - plain * 1.1 * F.Recalibrate.HeatMult) < 1e-6, string.format("%.2f -> %.2f", plain, changed))
    local IV = rawget(_G, "SandevistanInfoView")
    local R = rawget(_G, "SandevistanRuntime")
    if IV and R then
      local lines = try(function() return IV.buildLines(p, d, R.session(p), S.worldHours()) end) or {}
      local seen = false
      for _, ln in ipairs(lines) do if string.find(ln.text, getText("IGUI_Sandevistan_Fw_Name_Compatibilidad"), 1, true) then seen = true end end
      check("la pestana Implante lista el chip instalado", seen)
    end
    check("sacar el chip lo devuelve al inventario", FC.unflash(p, "sistema") == true and d.firmware.sistema == nil and #newItems(p, FW.itemType("Compatibilidad")) >= 1)
  end
  d.firmware = snap.fw; d.rejection = snap.rejection; d.fwRecalUntil = snap.recal           -- se repone
end

local function stepSkillTooltip(p)
  header("Tooltip de la skill Sandevistan: Adaptation (detalle por nivel)")
  local ST = rawget(_G, "SandevistanSkillTooltip")
  if not ST then info("tooltip de la skill", "sin SandevistanSkillTooltip"); return end
  check("enganchado a ISSkillProgressBar:updateTooltip", ST.installed == true)
  local variants = ST.variantsFor(p)
  for _, level in ipairs({ 1, 5, 8, 10 }) do
    local txt = ST.lines(level, variants)
    check("detalle del nivel " .. level .. " con textos traducidos", #txt > 30 and not string.find(txt, "IGUI_Sandevistan_" .. "LvlTip", 1, true), string.sub(txt, 1, 60))
  end
  local perk = S.perk()
  if not (perk and ISSkillProgressBar and ISSkillProgressBar.updateTooltip) then info("tooltip de la skill con la barra real", "ISSkillProgressBar no disponible"); return end
  -- una barra falsa con los campos que usa vanilla: el mensaje tiene que traer nuestro detalle
  local pf = try(function() return PerkFactory.getPerk(perk) end) or perk
  local fake = { perk = pf, level = 2, xp = 10, xpForLvl = 100, char = p, playerNum = p:getPlayerNum(), parent = {}, message = "" }
  local ok, err = pcall(ISSkillProgressBar.updateTooltip, fake, 2)
  if not ok then info("tooltip de la skill con la barra real", "no automatizable: " .. tostring(err)); return end
  local expected = ST.lines(3, variants)
  check("el mensaje de la barra trae el detalle del nivel 3", type(fake.message) == "string" and string.find(fake.message, expected, 1, true) ~= nil,
    "largo " .. tostring(fake.message and #fake.message))
end

local function stepXPSources(p)
  header("XP de adaptacion por fuente (uso, kills, pasiva)")
  local R = rawget(_G, "SandevistanRuntime")
  local d = S.data(p)
  if not R or not R.addPendingXP then info("XP por fuente", "sin Runtime"); return end
  if not S.hasWorkingImplant(d) then info("XP por fuente", "necesita un implante operativo instalado (si no, no hay adaptacion que sumar)"); return end
  local xp0, src0, pend0, by0 = d.adaptXP, deepcopy(d.xpSrc), nil, nil
  local s0 = R.session(p); pend0, by0 = s0.xpPending, deepcopy(s0.xpBy)
  s0.xpPending, s0.xpBy = 0, {}
  local t0, k0 = (d.xpSrc and d.xpSrc.time) or 0, (d.xpSrc and d.xpSrc.kill) or 0
  R.addPendingXP(p, 20, "time"); R.addPendingXP(p, 12, "kill"); R.flushXP(p, true)
  local xs = d.xpSrc or {}
  check("la XP se reparte por fuente", (xs.time or 0) > t0 and (xs.kill or 0) > k0, string.format("uso %.0f, kills %.0f", xs.time or 0, xs.kill or 0))
  check("y suma a la adaptacion", d.adaptXP > xp0 or d.adaptXP >= S.xpCap(d), string.format("%.0f -> %.0f", xp0, d.adaptXP))
  -- se repone todo como estaba
  d.adaptXP, d.xpSrc = xp0, src0
  s0.xpPending, s0.xpBy = pend0 or 0, by0 or {}
  pcall(S.syncPerk, p)
end

local function stepOverdriveWindow(p)
  header("Ventana de Overdrive por variante")
  local lab, mil = CFG.Variants.lab, CFG.Variants.military
  local dl, dm = { variant = "lab" }, { variant = "military" }
  check("laboratorio: 2,5 s en nivel 0 y 4 s en el nivel maximo", math.abs(S.overdriveWindow(dl, 0) - 2.5) < 1e-9 and math.abs(S.overdriveWindow(dl, lab.maxLevel) - lab.overdriveMax) < 1e-9,
    string.format("%.2f / %.2f", S.overdriveWindow(dl, 0), S.overdriveWindow(dl, lab.maxLevel)))
  check("militar: 7 s en el nivel 10", math.abs(S.overdriveWindow(dm, mil.maxLevel) - mil.overdriveMax) < 1e-9, string.format("%.2f", S.overdriveWindow(dm, mil.maxLevel)))
  local F = rawget(_G, "SandevistanFirearms")
  if F then
    local ok, mult = pcall(F.multiplier, p)
    check("armas de fuego: engancha recarga y cerrojo", F.installed == true or rawget(_G, "ISReloadWeaponAction") == nil, "enganchado = " .. tostring(F.installed))
    info("armas de fuego: multiplicador ahora", ok and string.format("%.2f (1.00 si el implante esta apagado)", mult) or tostring(mult))
  end
end

local function sceneStep(label, info_, hint)
  return function(p)
    header("Manual: " .. label)
    local IS = rawget(_G, "SandevistanInstallScene")
    if not IS then info(label, "sin SandevistanInstallScene"); return end
    IS.suppress = false
    local d = S.data(p)
    local started = IS.start(p, info_(d))
    if not started then IS.suppress = true; info(label, "no arranco (opcion del cliente apagada o ya hay una escena)"); return end
    return { cond = function() return IS.active == nil end, timeoutMs = 25000, onDone = function() IS.suppress = true end }
  end
end
local stepSceneInstall = sceneStep("escena de instalacion", function(d)
  return { ok = true, variant = d.variant or "lab", prototype = d.prototype, degradation = d.degradation or 1, rejection = d.rejection or 0, guide = false, debug = true } end)
local stepSceneExplant = sceneStep("escena de explantacion", function(d)
  return { kind = "explant", ok = true, variant = d.variant or "lab", keptPct = 50, remissionDays = 5 } end)

local function stepScenesAsk(p)
  header("Manual: preguntas de las escenas")
  return ask(p, "las escenas de instalacion y de desconexion se vieron y sonaron bien", "Acabas de ver la escena de INSTALACION (texto tipo terminal, latido al empezar y sonido de encendido al final) "
    .. "y la de DESCONEXION (modulos que se apagan, sonido de apagado al empezar y al cortarse el puente neural). <LINE> "
    .. "ENTER las salta pasados 2 s y aparece el aviso '[ENTER] SKIP'. Caminar no las corta. <LINE> <LINE> Se vieron y oyeron bien?")
end

local function stepHudAsk(p)
  header("Manual: HUD del implante")
  local d = S.data(p)
  if not S.hasAnyImplant(d) then info("HUD", "sin implante instalado: no hay panel que mirar"); return end
  return ask(p, "el panel del implante se ve bien (laboratorio con placa de circuito, militar de fibra de carbono o aluminio; compacto y avanzado)", "Mira el panel flotante del implante (si esta oculto, activalo desde la pestana Implante). <LINE> "
    .. "Con clic derecho alterna entre COMPACTO (solo Heat) y AVANZADO (con Rechazo y Neural). El de laboratorio es una placa de circuito con cinta rotulada a mano; el militar (XM-1) es de fibra de carbono con etiqueta de serie y el Mk. II de aluminio con chapa grabada. "
    .. "Los leds ACTIVE y OVERDRIVE se prenden segun el estado (amarillo = armado). <LINE> "
    .. "<LINE> Se ve bien, sin textos cortados ni solapados?")
end

local function stepClimbAsk(p)
  header("Manual: animaciones rapidas de trepar y saltar")
  local d = S.data(p)
  if not S.hasWorkingImplant(d) then info("trepar y saltar", "necesita un implante operativo instalado para activarlo"); return end
  return ask(p, "con el implante encendido saltar vallas, trepar y pasar ventanas se ve mas rapido y sin trabarse", "Encende el implante (tecla de activacion) y: salta una valla baja corriendo, trepa una valla alta, "
    .. "pasa por una ventana y, si podes, sube una pared con soga. <LINE> Las animaciones tienen que verse mas rapidas que sin implante, sin cortarse ni trabarse a mitad. <LINE> <LINE> Se ven bien?")
end

---------------------------------------------------------------------------
-- Orquestacion
---------------------------------------------------------------------------
local function buildSteps()
  local T = M.T
  local steps = {
    { "items", stepItems }, { "sonidos", stepSounds }, { "textos", stepTexts }, { "recetas", stepRecipes }, { "dificultades", stepPresets },
    { "menus", stepMenus },
    { "Mk. II", stepMarkII },
    { "libro sintesis", bookStep(T.NotebookBook, { "compound", "crafted", "herbal" }, function() return getText("IGUI_Sandevistan_NotebookTitle") end) },
    { "libro Kerenzikov", bookStep(T.KereBook, { "kerenzikov" }, function() return getText("IGUI_Sandevistan_KereNotesTitle") end) },
  }
  steps[#steps + 1] = { "planos P06", bookStep(T.Blueprint06, { "board", "regulator", "cell", "chassis", "harness", "proto06", "plan06" }, function() return getText("IGUI_Sandevistan_Blueprint06Title") end) }
  steps[#steps + 1] = { "planos militares", bookStep(T.Blueprint07, { "board07", "regulator07", "cell07", "chassis07", "harness07", "chip07", "proto07", "plan07" }, function() return getText("IGUI_Sandevistan_Blueprint07Title") end) }
  for _, key in ipairs({ "compound", "crafted", "herbal", "kerenzikov", "board", "regulator", "cell", "chassis", "harness", "proto06", "plan06", "board07", "regulator07", "cell07", "chassis07", "harness07", "chip07", "proto07", "plan07" }) do
    steps[#steps + 1] = { "crafteo " .. key, craftStep(key) }
  end
  steps[#steps + 1] = { "firmware", stepFirmware }
  steps[#steps + 1] = { "tooltip de la skill", stepSkillTooltip }
  steps[#steps + 1] = { "XP por fuente", stepXPSources }
  steps[#steps + 1] = { "ventana de Overdrive", stepOverdriveWindow }
  steps[#steps + 1] = { "piso", stepFloor }
  steps[#steps + 1] = { "ventanas", stepReaders }
  steps[#steps + 1] = { "crafteo menu", stepCraftTab }
  steps[#steps + 1] = { "sonido", stepSoundCheck }
  steps[#steps + 1] = { "escena de instalacion", stepSceneInstall }
  steps[#steps + 1] = { "escena de explantacion", stepSceneExplant }
  steps[#steps + 1] = { "escenas", stepScenesAsk }
  steps[#steps + 1] = { "HUD", stepHudAsk }
  steps[#steps + 1] = { "trepar y saltar", stepClimbAsk }
  return steps
end

local function say(p, text)
  S.log("recorrido: " .. text)
  pcall(function() p:Say(text) end)
end

function W.start(p, stepsOverride)
  if run then return false end
  local ids = {}
  local items = p:getInventory():getItems()
  for i = 0, items:size() - 1 do ids[items:get(i):getID()] = true end
  run = { p = p, steps = stepsOverride or buildSteps(), i = 1, lines = {}, counts = {}, startMs = S.realMs(), ids = ids, floor = {},
          knowsSnap = deepcopy(S.data(p).knows), stepName = "-" }
  if SandevistanInstallScene then SandevistanInstallScene.suppress = true end
  S.localItems = true                                     -- (114) los items de prueba se crean aca (se usan y se borran al terminar)
  say(p, "Recorrido funcional: va solo; al final te hace unas preguntas (si/no).")
  return true
end

function W.cancel(reason)
  if run then rec("INFO", "recorrido cancelado", reason); W.finish() end
end

function W.finish()
  if not run then return end
  local r, p = run, run.p
  S.localItems = nil
  pcall(function() closeReaders() end)
  pcall(function() p:setTimedActionInstantCheat(r.prevInstant == true) end)
  pcall(function() SandevistanRecipeCode.forcedChance = nil end)
  pcall(function() S.data(p).knows = r.knowsSnap end)
  pcall(function() M.syncRecipes(p, true) end)
  pcall(function() ISTimedActionQueue.clear(p) end)                    -- sin acciones colgadas de la lectura de libros
  for _, it in ipairs(r.floor) do
    pcall(function()
      local wo = it:getWorldItem()
      if wo then
        local sq = wo:getSquare()
        if sq then sq:transmitRemoveItemFromSquare(wo) end                 -- como hace el juego al levantar un item: tambien en un jugador, si no el objeto queda en el cuadrado
        wo:removeFromWorld(); wo:removeFromSquare()
        pcall(function() it:setWorldItem(nil) end)
      end
    end)
  end
  local inv = p:getInventory()
  local items = inv:getItems()
  local removed = 0
  for i = items:size() - 1, 0, -1 do
    local it = items:get(i)
    if not r.ids[it:getID()] then inv:DoRemoveItem(it); removed = removed + 1 end
  end
  run = nil
  if SandevistanInstallScene then SandevistanInstallScene.suppress = false end
  local c = r.counts
  local summary = string.format("OK %d | FALLA %d | INFO %d | SI %d | NO %d | sin respuesta %d", c.OK or 0, c.FALLA or 0, c.INFO or 0, c.SI or 0, c.NO or 0, c["SIN RESPUESTA"] or 0)
  r.lines[#r.lines + 1] = "items de prueba borrados: " .. removed
  r.lines[#r.lines + 1] = "=== resultado: " .. summary .. " ==="
  W.results = { lines = r.lines, counts = c, summary = summary, seconds = (S.realMs() - r.startMs) / 1000 }
  pcall(function()
    local w = getFileWriter("Sandevistan_walkthrough.txt", true, false)
    for _, l in ipairs(r.lines) do w:write(l .. "\n") end
    w:close()
  end)
  say(p, "Recorrido terminado: " .. summary)
  print("[Sandevistan][WALK] " .. summary)
end

function W.onTick()
  if not run then return end
  local now = S.realMs()
  if run.wait then
    local w = run.wait
    local done = false
    pcall(function() done = w.cond() == true end)
    if not done and now < w.untilMs then return end
    run.wait = nil
    if w.onDone then
      local ok, err = pcall(w.onDone, not done)
      if not ok then rec("FALLA", run.stepName .. " (error al verificar)", tostring(err)) end
    end
  end
  local st = run.steps[run.i]
  if not st then W.finish(); return end
  run.i = run.i + 1
  run.stepName = st[1]
  local ok, res = pcall(st[2], run.p)
  if not ok then
    rec("FALLA", st[1] .. " (error)", tostring(res))
  elseif type(res) == "table" and res.cond then
    res.untilMs = now + (res.timeoutMs or 20000)
    run.wait = res
  end
end

-- pasos sueltos (tools/tests/walkthrough.lua los corre con el juego simulado)
W.stepFns = { items = stepItems, sounds = stepSounds, texts = stepTexts, recipes = stepRecipes, presets = stepPresets, menus = stepMenus, ask = ask, craft = craftStep,
              markII = stepMarkII, tooltip = stepSkillTooltip, xp = stepXPSources, overdrive = stepOverdriveWindow, firmware = stepFirmware }

Events.OnTick.Add(S.safe("Walkthrough.OnTick", W.onTick))

return W
