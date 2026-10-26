-- Sandevistan / Debug: submenú de mundo para probar sin coordenadas de mapa ni esperar horas.
-- Visible con -debug o con la opción de mod "Menú de debug".
require "Sandevistan/Core"
require "Sandevistan/Medical"
require "Sandevistan/Runtime"
require "Sandevistan/Periodic"
require "Sandevistan/Slowdown"
require "Sandevistan/Effects"
require "Sandevistan/Afterimages"
require "Sandevistan/Moodles"
require "Sandevistan/Report"
require "Sandevistan/TestSuite"
require "Sandevistan/PerfTest"
require "Sandevistan/Walkthrough"
require "Sandevistan/FirmwareClient"
require "Sandevistan/FirmwareProbe"
require "Sandevistan/AudioProbe"
require "Sandevistan/HitBench"
require "Sandevistan/Viewport"

local CFG = SandevistanConfig
local S = Sandevistan
local M = SandevistanMedical
local R = SandevistanRuntime
local P = SandevistanPeriodic
local SD = SandevistanSlowdown
local E = SandevistanEffects
local V = CFG.Crafting.Items

SandevistanDebug = {}
local D = SandevistanDebug

function D.enabled()
  if S.debugOn() then return true end
  return SandevistanInput and SandevistanInput.getOption("debugMenu", false) or false
end

-- (189) C12: el menú para jugadores o admins (REPORTE, probar un efecto, montar el estado) va siempre; las pruebas internas
-- (rendimiento, recorridos de auditoría, sondas de firmware, volcados del mundo) solo con la opción o con -debug.
function D.full()
  if S.debugOn() then return true end
  return SandevistanInput and SandevistanInput.getOption("debugFull", false) or false
end

-- (127) Textos del menu en el idioma del juego: IGUI_Sandevistan_Dbg_<clave> en Translate/AR (fuente), ES (generado) y EN
local function L(key, ...) return getText("IGUI_Sandevistan_Dbg_" .. key, ...) end

-- Opcion con la etiqueta corta y el detalle (que hace, que da, a que txt escribe) en el tooltip: las etiquetas largas ocupaban toda la pantalla
local function tip(menu, name, detail, target, fn, ...)
  local o = menu:addOption(name, target, fn, ...)
  if detail and type(o) == "table" and ISToolTip then
    local t = ISToolTip:new(); t:initialise(); t:setVisible(false)
    t.description = detail
    o.toolTip = t
  end
  return o
end

local function sub(context, parent, name)
  local o = parent:addOption(name, nil, nil)
  local m = ISContextMenu:getNew(parent)
  parent:addSubMenu(o, m)
  return m
end

-- (122) MP: los crea el servidor (S.grantItem). Creados aca existian solo en esta pantalla: un libro asi no se podia leer (el servidor no lo encontraba).
local function give(player, list)
  for _, t in ipairs(list) do S.grantItem(player, t) end
end

-- (94) teletransporte de Debug (anclas y ex-sujetos): la casilla de destino y la anterior, para que el motor no interpole el salto
function D.teleport(player, x, y, z)
  S.try("teleport", function()
    player:setX(x + 0.5); player:setY(y + 0.5); player:setZ(z or 0)
    player:setLastX(x + 0.5); player:setLastY(y + 0.5); player:setLastZ(z or 0)
  end)
end

-- (91) "PROBAR TODOS LOS CHIPS" (FullTest.runChips): una sola definicion para sus dos lugares del menu (Pruebas e informes y Firmware)
function D.addChipsTest(menu, player)
  local FT = rawget(_G, "SandevistanFullTest")
  if FT and FT.runChips then
    tip(menu, L("ChipsTest"), L("ChipsTest_Tip"), player, function() FT.runChips(player) end)
  end
end

function D.fillWorldMenu(player, context, worldObjects)
  local root = sub(context, context, "Sandevistan [DEBUG]")
  local d = S.data(player)
  local TS = SandevistanTestSuite
  local PTs = SandevistanPerfTest
  local WT = SandevistanWalkthrough
  local full = D.full()

  -- Pruebas e informes (cada una escribe su txt en Zomboid/Lua/). (189) C12: el REPORTE queda siempre (lo usa el jugador para
  -- reportar un problema); las pruebas internas van detrás de la opción «Menú de debug completo».
  local ts = sub(context, root, L("Tests"))
  tip(ts, L("Report"), L("Report_Tip"), player, function()
    if SandevistanReport then S.try("report", function() SandevistanReport.export(player) end) end end)
  if full then
    if TS and TS.running() then
      ts:addOption(L("FullTestRun", TS.phaseName()), player, function() TS.cancel("cancelada") end)
    else
      tip(ts, L("FullTest"), L("FullTest_Tip"), player, function()
        if TS then TS.start(player) end end)
    end
    D.addChipsTest(ts, player)
    if WT and WT.running() then
      ts:addOption(L("WalkthroughRun", WT.stepName()), player, function() WT.cancel("cancelado") end)
    elseif WT then
      tip(ts, L("Walkthrough"), L("Walkthrough_Tip"), player, function()
        WT.start(player) end)
    end
    if PTs and PTs.running() then
      ts:addOption(L("PerfRun", PTs.stageName()), player, function() PTs.cancel("cancelada") end)
    elseif PTs then
      tip(ts, L("PerfNormal"), L("PerfNormal_Tip"), player, function() PTs.start(player, "normal") end)
      ts:addOption(L("PerfHeavy"), player, function() PTs.start(player, "heavy") end)
      tip(ts, L("PerfLod"), L("PerfLod_Tip"), player, function()
        PTs.start(player, "lod") end)
      tip(ts, L("PerfHud"), L("PerfHud_Tip"), player, function()
        if SandevistanHUD and SandevistanHUD.requestBench then SandevistanHUD.requestBench() end end)
      tip(ts, L("PerfSweep"), L("PerfSweep_Tip"), player, function()
        local n = PTs.sweep(); pcall(function() player:Say(L("PerfSwept", tostring(n))) end) end)
    end
    local CB = SandevistanCombat
    if CB and CB.startFuryTest then
      tip(ts, L("RageWear"), L("RageWear_Tip"), player, function()
        CB.startFuryTest(player) end)
    end
    local HB = SandevistanHitBench
    if HB and HB.running() then
      ts:addOption(L("HitBenchRun", HB.phaseName()), player, function() HB.cancel("cancelado") end)
    elseif HB then
      tip(ts, L("HitBench"), L("HitBench_Tip", HB.FILE), player, function() HB.start(player) end)
    end
    tip(ts, L("BookGuideDiag"), L("BookGuideDiag_Tip"), player, function()          -- (157) estado de la guía con libros
      local BGx = rawget(_G, "SandevistanBookGuide")
      if not BGx then return end
      local okDiag, lines = pcall(BGx.diagnostics, player)
      if not okDiag or type(lines) ~= "table" then S.log("guia con libros: no se pudo diagnosticar: " .. tostring(lines)) return end
      local wrote = pcall(function()
        local w = getFileWriter("Sandevistan_bookguide.txt", true, false)
        if not w then error("sin escritor") end
        for _, l in ipairs(lines) do w:write(S.ascii(l) .. "\n") end
        w:close()
      end)
      for i = 1, math.min(#lines, 24) do S.log("guia con libros: " .. lines[i]) end
      pcall(function() player:Say(wrote and "Guía con libros: Zomboid/Lua/Sandevistan_bookguide.txt" or "No se pudo escribir el txt") end)
    end)
  end

  -- Escenas y guia (sin operarte). (189) C12: la guía queda; las escenas son pruebas internas.
  local sc = sub(context, root, L("Scenes"))
  if full then
    tip(sc, L("SceneInstall"), L("SceneInstall_Tip"), player, function()
      local IS = SandevistanInstallScene
      if IS then
        local d2 = S.data(player)
        IS.suppress = false
        IS.start(player, { ok = true, variant = d2.variant or "lab", prototype = d2.prototype, degradation = d2.degradation or 1, rejection = d2.rejection or 0, debug = true })
      end end)
    sc:addOption(L("SceneExplant"), player, function()
      local IS = SandevistanInstallScene
      if IS then
        IS.suppress = false
        IS.start(player, { kind = "explant", ok = true, variant = S.data(player).variant or "lab", keptPct = 50, remissionDays = 5 })
      end end)
    tip(sc, L("SceneExplantPsy"), L("SceneExplantPsy_Tip"), player, function()
      local IS = SandevistanInstallScene
      if IS then
        IS.suppress = false
        IS.start(player, { kind = "explant", ok = true, variant = S.data(player).variant or "lab", keptPct = 50, remissionDays = 5, cyber = true, cn = S.data(player).neuralLoad or 85 })
      end end)
    sc:addOption(L("SceneFail"), player, function()
      if SandevistanInstallScene then SandevistanInstallScene.start(player, { ok = false }) end end)
  end
  sc:addOption(L("Guide"), player, function()
    if SandevistanMenus and SandevistanMenus.showGuide then SandevistanMenus.showGuide(player) end end)

  -- Ítems (189) C12: kits y volcados para probar; son internos.
  if full then
  local items = sub(context, root, L("Items"))
  items:addOption(L("ItemMilitary"), player, function() give(player, { M.T.CryoBox }) end)
  items:addOption(L("ItemLab"), player, function() give(player, { M.T.Lab }) end)
  items:addOption(L("ItemP04"), player, function() give(player, { M.T.P04 }) end)
  items:addOption(L("ItemImmuno"), player, function()
    give(player, { M.T.Clinical, M.T.Clinical, M.T.Crafted, M.T.Crafted, M.T.Herbal, M.T.Herbal }) end)
  items:addOption(L("ItemKerenzikov"), player, function() give(player, { M.T.KereMil, M.T.KereCrafted }) end)
  tip(items, L("KitSurgery"), L("KitSurgery_Tip"), player, function()
    give(player, { V.Suture, V.Suture, V.Disinfectant, V.Scalpel, V.Mirror, V.Painkillers }) end)
  tip(items, L("KitSurgeryThread"), L("KitSurgeryThread_Tip"), player, function()       -- (194) la sutura alternativa de vanilla
    give(player, { V.Needle, V.Thread, V.Disinfectant, V.Scalpel, V.Mirror, V.Painkillers }) end)
  tip(items, L("KitWorkshop"), L("KitWorkshop_Tip"), player, function()
    give(player, { V.Screwdriver, V.ElectronicsScrap, V.ElectronicsScrap, V.ElectronicsScrap, V.ElectronicsScrap }) end)
  tip(items, L("KitSynth"), L("KitSynth_Tip"), player, function()
    give(player, { V.Painkillers, V.Painkillers, V.Painkillers, V.Disinfectant, V.Coldpack, V.Mortar, M.T.Compound }) end)
  items:addOption(L("ItemHerbs"), player, function()
    give(player, { V.WildGarlic, V.WildGarlic, V.BlackSage, V.BlackSage, V.Whiskey }) end)
  tip(items, L("KitBooks"), L("KitBooks_Tip"), player, function()      -- (155) T06: los libros de guía, vol. 1 a 3 de las cuatro skills
    local t = {}
    for _, base in ipairs({ "Base.BookFirstAid", "Base.BookElectrician", "Base.BookMetalWelding", "Base.BookTailoring" }) do
      for v = 1, 3 do t[#t + 1] = base .. v end
    end
    give(player, t) end)
  tip(items, L("ItemBuilt"), L("ItemBuilt_Tip"), player, function()
    local lab = M.addItem(player, M.T.Lab)
    if lab then lab:getModData().heatDegradationMultiplier = 1.0; M.tagPrototype(lab, "06") end
    local mil = M.addItem(player, M.T.Military)
    if mil then mil:getModData().heatDegradationMultiplier = 1.0; M.tagPrototype(mil, "07") end
    give(player, { V.Pen })
  end)
  tip(items, L("KitP06"), L("KitP06_Tip"), player, function()
    local t = { V.Screwdriver, M.T.Compound }
    for _, key in ipairs(CFG.Prototype06.PartOrder) do table.insert(t, CFG.Prototype06.Parts[key].item) end
    for _ = 1, CFG.Prototype06.ScrapRequired do table.insert(t, V.ElectronicsScrap) end
    give(player, t) end)
  tip(items, L("MatP06"), L("MatP06_Tip"), player, function()
    local t = { V.Screwdriver, V.Battery, V.Needle, V.Twine }
    for _ = 1, 8 do table.insert(t, V.ElectronicsScrap) end
    for _ = 1, 6 do table.insert(t, V.Wire) end
    for _ = 1, 4 do table.insert(t, V.SmallSheetMetal) end
    for _ = 1, 3 do table.insert(t, V.Screws) end
    for _ = 1, 2 do table.insert(t, V.LeatherStrips) end
    give(player, t) end)
  -- v0.1.30 (43): Prototipo 07 (replica militar) y planos
  tip(items, L("KitMk2"), L("KitMk2_Tip"), player, function()
    local t = { V.Screwdriver, M.T.KereMil, M.T.KereCrafted }
    for _, key in ipairs(CFG.Prototype07.PartOrder) do table.insert(t, CFG.Prototype07.Parts[key].item) end
    for _ = 1, CFG.Prototype07.ScrapRequired do table.insert(t, V.ElectronicsScrap) end
    give(player, t) end)
  tip(items, L("MatMk2"), L("MatMk2_Tip"), player, function()
    local t = { V.Screwdriver, M.T.MilChip, V.Coldpack, V.Coldpack, V.Coldpack, V.Needle, V.Twine }
    for _ = 1, 14 do table.insert(t, V.ElectronicsScrap) end
    for _ = 1, 8 do table.insert(t, V.Wire) end
    for _ = 1, 5 do table.insert(t, V.SmallSheetMetal) end
    for _ = 1, 4 do table.insert(t, V.Screws) end
    for _ = 1, 3 do table.insert(t, V.LeatherStrips) end
    for _ = 1, 2 do table.insert(t, V.Battery) end
    give(player, t) end)
  tip(items, L("Blueprints"), L("Blueprints_Tip"), player, function()
    give(player, { M.T.Blueprint06, M.T.Blueprint07, V.Pen, V.Paper, V.Paper, V.Paper, V.Paper, V.Paper, V.Paper, V.Paper, V.Paper }) end)
  tip(items, L("DossiersFull"), L("DossiersFull_Tip"), player, function()
    local D = rawget(_G, "SandevistanDossier")
    if not D then return end
    for _, st in ipairs(CFG.Notes.Stories) do
      if st.id == "researcher" or st.id == "depot" then
        for _, n in ipairs(st.notes) do give(player, { D.noteType(n) }) end
        if S.isMPClient() then D.requestFile(player, st, st.notes)       -- (122) MP: las notas las crea el servidor y todavia no llegaron; el pedido va despues
        else D.fileNotes(player, st, D.looseNotes(player, st, D.find(player, st))) end
      end
    end end)
  items:addOption(L("ItemAntidep"), player, function() give(player, { V.AntiDep }) end)
  -- (168) T13: los mapas anotados, sin esperar a que salgan en el botín
  tip(items, L("StashMaps"), L("StashMaps_Tip"), player, function()
    local AM = rawget(_G, "SandevistanAnnotatedMaps")
    local n = 0
    if AM and AM.giveMap then for _, key in ipairs(AM.order) do if AM.giveMap(player, key) then n = n + 1 end end end
    E.halo(player, getText(n > 0 and "IGUI_Sandevistan_Dbg_StashMapsGiven" or "IGUI_Sandevistan_Dbg_StashMapsNone", n), 150, 200, 255)
  end)
  -- (168b) diagnóstico: qué ve el sistema de escondites del juego (para cuando los mapas no salen)
  tip(items, L("StashDiag"), L("StashDiag_Tip"), player, function()
    local AM = rawget(_G, "SandevistanAnnotatedMaps")
    local SS = rawget(_G, "StashSystem")
    local lines = { "StashSystem=" .. tostring(SS ~= nil) .. " AM=" .. tostring(AM ~= nil), "AMbuilt=" .. tostring(AM and AM.built) }
    local function add(f) local ok, v = pcall(f); lines[#lines + 1] = tostring(v) .. (ok and "" or " (err)") end
    if SS then
      add(function() return "all=" .. SS.getAllStashes():size() end)
      add(function() return "possible=" .. SS.getPossibleStashes():size() end)
    end
    if AM and CFG.AnnotatedMaps then
      for _, key in ipairs(AM.order) do
        local c = CFG.AnnotatedMaps[key]
        add(function() return c.stash .. "=" .. tostring(SS and SS.getStash(c.stash) ~= nil) end)
      end
    end
    local text = table.concat(lines, "; ")
    player:Say(text)
    S.log("mapas: " .. text)
    for _, l in ipairs(lines) do print("[Sandevistan] mapas: " .. l) end
  end)
  tip(items, L("DossiersEmpty"), L("DossiersEmpty_Tip"), player, function()
    give(player, { "Sandevistan.SandevistanDossierResearcher", "Sandevistan.SandevistanDossierDepot", "Sandevistan.SandevistanDossierStudent" }) end)
  tip(items, L("Notes"), L("Notes_Tip"), player, function()
    give(player, { M.T.NotebookBook, M.T.KereBook })
    M.grantGuideItem(player, false)
    for n = 1, CFG.Notes.Count do give(player, { "Sandevistan." .. string.format("SandevistanNote%02d", n) }) end
  end)
  end

  -- Estado (por grupos)
  local st = sub(context, root, L("State"))
  local si = sub(context, st, L("Implant"))
  si:addOption(L("InstallMilitary"), player, function()
    d.variant = "military"; d.degradation = 1.0; d.adaptXP = 0; d.rejection = 0; d.heat = 0
    d.lastRejectionTickHour = S.worldHours(); d.lastCNTickHour = S.worldHours(); d.noImplantSinceHour = nil end)
  si:addOption(L("InstallLab"), player, function()
    d.variant = "lab"; d.degradation = 1.0; d.adaptXP = 0; d.rejection = 0; d.heat = 0
    d.lastRejectionTickHour = S.worldHours(); d.lastCNTickHour = S.worldHours(); d.noImplantSinceHour = nil end)
  -- (69) para ver cada placa del HUD sin fabricar nada: el implante instalado cambia de diseno y de nombre
  local sp = sub(context, si, L("Plate"))
  local function plate(variant, proto, name)
    return function()
      d.variant = variant; d.prototype = proto; d.plateName = name
      d.degradation = d.degradation or 1.0; d.heat = d.heat or 0; d.noImplantSinceHour = nil
    end
  end
  sp:addOption(L("PlateP05"), player, plate("lab", nil, nil))
  sp:addOption(L("PlateP04"), player, plate("lab", "04", nil))
  sp:addOption(L("PlateP06"), player, plate("lab", "06", nil))
  sp:addOption(L("PlateP06Named"), player, plate("lab", "06", "EL RELAMPAGO"))
  sp:addOption(L("PlateMk2Named"), player, plate("military", "07", "ARCO 7"))
  sp:addOption(L("PlateMilitary"), player, plate("military", nil, nil))
  tip(sp, L("Armed"), L("Armed_Tip"), player, function()
    local ss = R.session(player)
    ss.armed = not ss.armed
  end)
  si:addOption(L("RemoveImplant"), player, function()
    R.deactivate(player, "forced"); player:getModData().Sandevistan = nil; player:getModData().Kerenzikov = nil end)
  si:addOption(L("AdaptUp"), player, function()
    if S.level(d) >= S.maxLevel(d) and S.masteryEnabled(d) then             -- (123) maestria con Beyond Ten: al umbral del nivel siguiente (11..15)
      local rank, into, need = S.masteryProgress(d)
      if need > 0 then d.adaptXP = math.min(S.xpCap(d), d.adaptXP - into + need) end
      return
    end
    d.adaptXP = math.max(d.adaptXP, math.min(S.xpCap(d), S.xpForLevel(S.level(d) + 1))) end)          -- (124) nunca baja la XP guardada por encima del techo
  for _, lv in ipairs({ 5, 8, 10 }) do
    si:addOption(L("AdaptSet", lv), player, function() d.adaptXP = S.xpForLevel(lv) end)
  end
  si:addOption(L("LearnP06"), player, function() d.knows.proto06 = true; SandevistanMedical.syncRecipes(player) end)
  si:addOption(L("LearnMk2"), player, function() d.knows.proto07 = true; SandevistanMedical.syncRecipes(player) end)
  si:addOption(L("LearnRecipes"), player, function() d.knows.crafted = true; d.knows.kerenzikov = true end)

  -- (164) Pruebas rápidas de la fase 1 y 2: montar la situación a mano (resistencia, Heat, bloqueos, pastillas) lleva tiempo, y así se
  -- prueba en un par de clics.
  local sf = sub(context, st, L("Quick"))
  local function forceNow(flags)
    d.forceLock = nil
    if flags.heat then
      d.heat = S.heatCap(d); d.lockUntilCool = true
    else
      E.setEndurance(player, math.max(0, CFG.Stamina.MinToActivate - 0.05))
    end
    local ok, fl = false, nil
    if R.canForce then ok, fl = R.canForce(player) end
    if ok and R.force(player, fl or flags) then
      local ss = R.session(player)
      ss.overdriveUntilMs = S.gameMs() - 1            -- colapsa en el próximo tick: se ve la cuenta completa
    else
      E.halo(player, L("ForceNo"), 255, 120, 60)
    end
  end
  tip(sf, L("ForceAir"), L("ForceAir_Tip"), player, function() forceNow({ stamina = true }) end)
  tip(sf, L("ForceHeat"), L("ForceHeat_Tip"), player, function() forceNow({ heat = true }) end)
  tip(sf, L("ForceAirLock"), nil, player, function() d.forceLock = d.forceLock or {}; d.forceLock.stamina = true end)
  tip(sf, L("ForceHeatLock"), nil, player, function() d.forceLock = d.forceLock or {}; d.forceLock.heat = true end)
  tip(sf, L("ForceLocksClear"), nil, player, function() d.forceLock = nil end)
  tip(sf, L("StopgapsGive"), nil, player, function()
    give(player, { CFG.Stopgaps.Painkiller.Item, CFG.Stopgaps.Sleeping.Item, CFG.Stopgaps.Beta.Item }) end)
  tip(sf, L("StopgapPainkiller"), nil, player, function() M.applyStopgap(player, "painkiller") end)
  tip(sf, L("StopgapSleeping"), nil, player, function() M.applyStopgap(player, "sleeping") end)
  tip(sf, L("StopgapBeta"), nil, player, function() M.applyStopgap(player, "beta") end)
  tip(sf, L("StopgapsClear"), nil, player, function() d.stopgap = {} end)
  tip(sf, L("Disconnect"), L("Disconnect_Tip"), player, function()
    if #M.disconnectReq(player) == 0 then M.performDisconnect(player) else d.disconnected = true; d.disconnectedAtHour = S.worldHours() end end)
  tip(sf, L("Reconnect"), L("Reconnect_Tip"), player, function()
    if d.disconnected then M.performReconnect(player) end end)
  tip(sf, L("RemissionInfo"), L("RemissionInfo_Tip"), player, function()
    local left = S.remissionHoursLeft(d, S.worldHours())
    player:Say(string.format("remision: acumuladas %.1f h, quedan %s, desconectado %s", d.remissionHours or 0,
      left and string.format("%.1f h", left) or "-", tostring(d.disconnected)))
    S.log(string.format("remision: remissionHours=%.2f left=%s disconnected=%s noImplantSinceHour=%s",
      d.remissionHours or 0, tostring(left), tostring(d.disconnected), tostring(d.noImplantSinceHour))) end)
  tip(sf, L("Chromed"), L("Chromed_Tip"), player, function()
    M.applyStartingImplant(player); M.giveGuide(player)
    give(player, CFG.Traits.ChromedKit) end)

  local sh = sub(context, st, L("Heat"))
  sh:addOption("Heat 0", player, function() d.heat = 0; d.cooldownMult = 1 end)
  sh:addOption("Heat 90", player, function() d.heat = 90 end)
  tip(sh, L("ScarDown"), L("ScarDown_Tip"), player, function()
    S.scarHeatCap(d, CFG.Overdrive.HeatCap.PerCollapse) end)
  tip(sh, L("ScarReset"), nil, player, function() d.heatCap = 100 end)

  local sn = sub(context, st, L("Neural"))
  sn:addOption(L("Nl", 0), player, function() d.neuralLoad = 0; d.cyberpsychosisActive = false end)
  sn:addOption(L("Nl", 59), player, function() d.neuralLoad = 59 end)
  sn:addOption(L("Nl70"), player, function() d.neuralLoad = 70 end)
  sn:addOption(L("Nl85"), player, function() d.neuralLoad = 85; R.checkThresholds(player) end)
  sn:addOption(L("Nl100"), player, function() d.neuralLoad = 100; R.checkThresholds(player) end)
  tip(sn, L("RemissionDone"), L("RemissionDone_Tip"), player, function()
    d.remissionHours = CFG.NeuralLoad.Remission.HoursWithoutImplant end)
  tip(sn, L("RemissionStart"), L("RemissionStart_Tip"), player, function()
    d.cyberpsychosisActive = true; d.remissionHours = 0 end)
  tip(sn, L("RemissionHalf"), L("RemissionHalf_Tip"), player, function()
    d.cyberpsychosisActive = true; d.remissionHours = CFG.NeuralLoad.Remission.HoursWithoutImplant / 2 end)

  local sr = sub(context, st, L("Rejection"))
  sr:addOption(L("Rej0"), player, function() d.rejection = 0 end)
  sr:addOption(L("Rej30"), player, function() d.rejection = 30 end)
  sr:addOption(L("Rej55"), player, function() d.rejection = 55 end)
  sr:addOption(L("Rej74"), player, function() d.rejection = 74 end)
  sr:addOption(L("Rej95"), player, function() d.rejection = 95 end)
  sr:addOption(L("RejClear"), player, function()
    d.immuno = {}; d.herbalToxicity = 0; d.immunodep = 0; d.immunoPeak = 0; d.immunoDoses = {}; d.immunoReboundUntil = -1 end)   -- (135) y la inmunodepresion
  -- (135) inmunodepresion: fijarla y hacerse un rasguño para ver la infeccion y la curacion (solo en este cliente)
  for _, v in ipairs({ 0, 60, 100 }) do sr:addOption(L("Immunodep", v), player, function() d.immunodep = v end) end
  local FT = rawget(_G, "SandevistanFullTest")
  if FT and FT.runImmuno then tip(sr, L("ImmunoTest"), L("ImmunoTest_Tip"), player, function() FT.runImmuno(player) end) end
  tip(sr, L("ImmunoScratch"), L("ImmunoScratch_Tip"), player, function()
    pcall(function() player:getBodyDamage():getBodyPart(BodyPartType.Hand_L):setScratched(true, true) end) end)
  sr:addOption(L("RejSim"), player, function()
    d.lastRejectionTickHour = S.worldHours() - 24; P.rejectionTick(player, d) end)

  local sy = sub(context, st, L("Symptoms"))
  sy:addOption(L("Nosebleed"), player, function() E.startNosebleed(player, d) end)
  sy:addOption(L("Scream"), player, function() E.scream(player, d) end)
  sy:addOption(L("Antidep"), player, function() M.applyAntidepressant(player) end)

  -- Firmware (82): chips, perfil vigente y sondas para verificar en el juego lo que el plan (15) deja abierto
  local FC, FP = rawget(_G, "SandevistanFirmwareClient"), rawget(_G, "SandevistanFirmwareProbe")
  if FC and full then
    local fm = sub(context, root, "Firmware")
    D.addChipsTest(fm, player)
    tip(fm, L("FwGiveAll"), nil, player, function() FC.debugGiveAll(player) end)
    tip(fm, L("FwGiveWriter"), L("FwGiveWriter_Tip"), player, function() FC.debugGiveWriter(player) end)
    tip(fm, L("FwGiveDecompile"), L("FwGiveDecompile_Tip"), player, function() FC.debugGiveDecompile(player) end)
    tip(fm, L("WorkOn"), L("WorkOn_Tip"), player, function() FC.debugWork(player) end)
    tip(fm, L("WorkOff"), L("WorkOff_Tip"), player, function() FC.debugWork(player, true) end)
    tip(fm, L("FwLearnAll"), L("FwLearnAll_Tip"), player, function() FC.debugLearnAll(player) end)
    tip(fm, L("FwForgetAll"), L("FwForgetAll_Tip"), player, function() FC.debugForgetAll(player) end)
    local fi = sub(context, fm, L("FwInstall"))
    for _, id in ipairs(CFG.Firmware.Order) do
      local pr = CFG.Firmware.Programs[id]
      fi:addOption(id .. " (" .. pr.slot .. (pr.only and (", " .. L("FwOnly", pr.only)) or "") .. ")" .. (pr.ready and "" or (" [" .. L("FwInDev") .. "]")), player, function() FC.debugSet(player, id) end)
    end
    tip(fm, L("FwClear"), L("FwClear_Tip"), player, function() FC.debugClear(player) end)
    tip(fm, L("FwProfile"), L("FwProfile_Tip"), player, function()
      local lines = FC.profileLines(player)
      for _, l in ipairs(lines) do S.log("firmware, perfil: " .. l) end
      pcall(function() player:Say(#lines > 0 and table.concat(lines, "; ") or L("FwNeutral")) end) end)
    fm:addOption(L("FwRecal"), player, function() d.fwRecalUntil = nil end)
    if FP then
      local fp = sub(context, fm, L("Probes"))
      tip(fp, L("ProbeObjects"), L("ProbeObjects_Tip"), player, function()
        FP.scanObjects(player, 7); FP.export(player) end)
      tip(fp, FP.act.on and L("ProbeActOff") or L("ProbeActOn"), FP.act.on and L("ProbeActOff_Tip") or L("ProbeActOn_Tip"), player, function()
        FP.toggleActions(player) end)
      tip(fp, L("ProbeMove"), L("ProbeMove_Tip"), player, function()
        FP.startMovement(player) end)
    end
  end

  -- Mundo (189) C12: teleportes, spawns, recorridos y volcados son pruebas internas.
  if full then
  local wm = sub(context, root, L("World"))
  local sq = player:getCurrentSquare()
  -- v0.1.30 (13): en un cliente de multijugador el mundo no corre (lo maneja el servidor): lo que spawnea o coloca desde acá sería
  -- una copia local. Solo queda el teletransporte a las anclas.
  local worldHere = SandevistanWorld and SandevistanWorld.authority
  if not worldHere then
    local info = tip(wm, L("WorldMp"), L("WorldMp_Tip"), nil, nil)
    if type(info) == "table" then info.notAvailable = true end
  end
  -- Verificar los spawns en el juego: teletransporte al ancla (SP / admin) y auditoría de los ítems del mod que hay en el mapa
  for _, zone in ipairs({ "base", "lsu", "ekron" }) do
    wm:addOption(L("GoAnchor", zone), player, function()
      local a = SandevistanWorld and SandevistanWorld.anchor(zone)
      if not a then return end
      D.teleport(player, a.x, a.y, a.z)
    end)
  end
  -- (169) T16: un ex-sujeto errante al lado del jugador, sin tirada ni tope (para probarlo sin caminar horas)
  if worldHere then
    tip(wm, L("Wander"), L("Wander_Tip"), player, function()
      local id = SandevistanWorld.debugWander(player)
      if id then E.halo(player, getText("IGUI_Sandevistan_Dbg_WanderDone", id), 150, 220, 255)
      else E.halo(player, getText("IGUI_Sandevistan_Dbg_WanderNone"), 255, 120, 60) end
    end)
  end
  -- (94) ir a un ex-sujeto (zombi con Sandevistan): a donde esta ahora si esta cargado, si no a la ultima posicion conocida, si no al ancla de su zona
  if SandevistanWorld and SandevistanWorld.liveSubjects then
    local sm = sub(context, wm, L("GoSubject"))
    local list = SandevistanWorld.liveSubjects()
    if #list == 0 then
      local o = sm:addOption(L("NoSubjects"), nil, nil)
      if type(o) == "table" then o.notAvailable = true end
    end
    for _, e in ipairs(list) do
      local where = e.loaded and L("SubjLoaded") or (e.x and L("SubjLast") or L("SubjNone"))
      sm:addOption(L("SubjectEntry", e.id, tostring(e.variant), tostring(e.zone), where), player, function()
        if e.x then D.teleport(player, e.x, e.y, e.z)
        else
          local a = SandevistanWorld.anchor(e.zone)
          if a then D.teleport(player, a.x, a.y, a.z) end
        end
      end)
    end
  end
  if worldHere then
    for _, zone in ipairs({ "base", "lsu", "ekron" }) do
      wm:addOption(L("SetAnchor", zone), player, function()
        if SandevistanWorld then SandevistanWorld.setAnchor(zone, sq) end end)
    end
    wm:addOption(L("SpawnMilitary"), player, function()
      local t = getCell():getGridSquare(sq:getX() + 4, sq:getY(), sq:getZ())
      if t and SandevistanWorld then SandevistanWorld.spawnAt(t, "debug", "military") end end)
    wm:addOption(L("SpawnLab"), player, function()
      local t = getCell():getGridSquare(sq:getX() + 4, sq:getY(), sq:getZ())
      if t and SandevistanWorld then SandevistanWorld.spawnAt(t, "debug", "lab") end end)
    tip(wm, L("BackupRoll"), L("BackupRoll_Tip"), player, function()
      if not SandevistanWorld then return end
      local keep = CFG.ExSubjects.RespawnChance
      CFG.ExSubjects.RespawnChance = 1
      for _, zone in ipairs({ "base", "lsu", "ekron" }) do
        SandevistanWorld.zoneState(zone).lastCheckHour = -1000
        SandevistanWorld.respawnCheck(zone)
      end
      CFG.ExSubjects.RespawnChance = keep
    end)
    tip(wm, L("Corpses"), L("Corpses_Tip"), player, function()
      local sq0 = player:getCurrentSquare()
      if not sq0 then return end
      local lines = SandevistanWorld.corpseDiagnosis(player:getX(), player:getY(), player:getZ(), 6)
      for _, l in ipairs(lines) do S.log("cadaveres: " .. l) end
      pcall(function() player:Say(lines[#lines] .. " | " .. lines[1]) end)
    end)
    wm:addOption(L("CorpseCheck"), player, function()
      for id, s in pairs(SandevistanWorld.data().subjects) do if s.corpseHour then s.corpseHour = -1000 end end
      SandevistanWorld.checkCorpses()
    end)
    for _, zone in ipairs({ "base", "lsu", "ekron" }) do
      tip(wm, L("ReplaceSet", zone), L("ReplaceSet_Tip"), player, function()
        if SandevistanWorld then SandevistanWorld.replace(zone) end end)
    end
    if D.tour then
      tip(wm, L("TourCancel"), L("TourCancel_Tip"), player, function() D.cancelTour("cancelado") end)
    else
      tip(wm, L("Tour"), L("Tour_Tip"), player, function() D.startTour(player, false) end)
      tip(wm, L("TourReplace"), L("TourReplace_Tip"), player, function() D.startTour(player, true) end)
    end
    tip(wm, L("Audit"), L("Audit_Tip"), player, function()
      if SandevistanWorld then S.try("exportAudit", function() SandevistanWorld.exportAudit() end) end end)
    for _, zone in ipairs({ "base", "lsu", "ekron" }) do
      wm:addOption(L("NextPlacement", zone), player, function()
        if not SandevistanWorld then return end
        D.placeIdx = D.placeIdx or {}
        D.placeIdx[zone] = (D.placeIdx[zone] or 0) + 1
        local e, total, i = SandevistanWorld.placedAt(zone, D.placeIdx[zone])
        if not e then S.log("sin colocaciones registradas en " .. zone); return end
        S.log(string.format("colocacion %d/%d de %s: %s | %s | %d,%d,%d | hab=%s", i, total, zone, e.t, e.how, e.x, e.y, e.z, e.room))
        S.try("teleport", function()
          player:setX(e.x + 0.5); player:setY(e.y + 0.5); player:setZ(e.z)
          player:setLastX(e.x + 0.5); player:setLastY(e.y + 0.5); player:setLastZ(e.z)
        end)
      end)
    end
  end
  end
  -- Cyberpsicosis por etapas (Psychosis.lua)
  local PS = SandevistanPsychosis
  local psy = sub(context, root, L("Psy"))
  psy:addOption(L("PsyStage3"), player, function() d.neuralLoad = 96; d.cyberpsychosisActive = true end)
  psy:addOption(L("PsyStage2"), player, function() d.neuralLoad = 85; d.cyberpsychosisActive = true end)
  psy:addOption(L("PsyStage1"), player, function() d.neuralLoad = 65 end)
  psy:addOption(L("PsyGlitch"), player, function()
    SD.glitchUntil = SD.glitchUntil or {}
    SD.glitchUntil[player:getPlayerNum()] = S.realMs() + 700
    if SandevistanHUD then SandevistanHUD.forceGlitch(700) end
    if PS then PS.play(player, "glitch", nil, nil, nil, 0.8) end
  end)
  -- (153) las otras dos familias de glitch, para escucharlas (cada clic sortea otro)
  psy:addOption(L("PsyGlitchVanish"), player, function() if PS then PS.play(player, "glitchVanish", nil, nil, nil, 0.8) end end)
  psy:addOption(L("PsyGlitchSevere"), player, function() if PS then PS.play(player, "glitchSevere") end end)
  psy:addOption(L("PsyBlackout"), player, function()
    if PS then PS.st(player).bo = { phase = "tunnel", t0 = S.realMs(), nextBeat = 0, blackDur = 1.0 } end end)
  psy:addOption(L("PsyMonitor"), player, function()
    if PS then PS.toast(getText("IGUI_Sandevistan_Mon_Humanity", math.floor(100 - d.neuralLoad)), "crit") end end)
  tip(psy, L("PsyOverload"), L("PsyOverload_Tip"), player, function()
    d.lastOverloadHour = nil; d.neuralLoad = CFG.NeuralLoad.Max end)
  -- (178) la sobrecarga de verdad, sin cascada y forzando KO: sirve para ver la cicatriz y el despertar alucinado
  tip(psy, L("PsyOverloadNow"), L("PsyOverloadNow_Tip"), player, function()
    if not S.data(player).cyberpsychosisActive then
      S.log("sobrecarga forzada: sin cyberpsicosis activa no habrá despertar alucinado (el KO y la cicatriz sí)")
    end
    PS.forceOverload(player, true)
  end)
  tip(psy, L("PsyRage"), L("PsyRage_Tip"), player, function()
    if PS then
      d.lastOverloadHour = S.worldHours(); d.cyberpsychosisActive = true
      if not PS.startFury(player, R.session(player), d, S.realMs()) then S.log("furia total: no se pudo encender el implante") end
    end end)
  tip(psy, L("PsyGhost"), L("PsyGhost_Tip"), player, function()
    if PS then
      if not PS.threatActive(d) then S.log("marca fantasma: el sentido de peligro no esta activo (etapa 2+ con cyberpsicosis)") end
      PS.spawnPhantom(player, PS.st(player))
    end end)
  tip(psy, L("PsyFakeZombie"), L("PsyFakeZombie_Tip"), player, function()          -- (138) zombi falso (titere de SandevistanPsychosis)
    local FZ = rawget(_G, "SandevistanFakeZombies")
    if not FZ then return end
    if not FZ.ready() then S.log("zombi falso: " .. tostring(FZ.notReadyReason())); return end          -- (171) C13.1
    if not FZ.spawn(player, false) then S.log("zombi falso: no hubo lugar con camino recto hasta vos (proba en un lugar abierto)") end
  end)
  tip(psy, L("PsyFakeZombieScare"), L("PsyFakeZombieScare_Tip"), player, function()   -- (146) el susto: corredor callado que grita de cerca
    local FZ = rawget(_G, "SandevistanFakeZombies")
    if not FZ then return end
    if not FZ.ready() then S.log("zombi falso: " .. tostring(FZ.notReadyReason())); return end          -- (171) C13.1
    if not FZ.spawn(player, true) then S.log("zombi falso: no hubo lugar con camino recto hasta vos (proba en un lugar abierto)") end
  end)
  -- (181) C13.2 figura fantasma (PhantomFigures.lua): al costado de lo que ves, quieta o caminando; mirala de frente o acercate
  tip(psy, L("PsyFigure"), L("PsyFigure_Tip"), player, function()
    local PF = rawget(_G, "SandevistanPhantomFigures")
    if not PF then return end
    local FZ = rawget(_G, "SandevistanFakeZombies")
    if not PF.ready() then S.log("figura fantasma: " .. tostring(FZ and FZ.notReadyReason and FZ.notReadyReason() or "falta el mod SandevistanPsychosis")); return end
    if not PF.spawn(player, true) then S.log("figura fantasma: no hubo una casilla libre a la vista al costado (proba en un lugar abierto, de dia)") end
  end)
  -- (181) C13.3 / C13.4 / C13.5: sacudida, pantalla de cada episodio (15 s, con su tono) y el golpe corto
  local function sfx(fn)
    local SFX = rawget(_G, "SandevistanScreenFX")
    if not SFX then return end
    if not SFX.allowed() then S.log("sacudida y pantalla: con la camara 3D estan apagadas (Config.Psychosis.ScreenFX.In3D)"); return end
    if not SFX.ready() then S.log("sacudida y pantalla: falta el jar 3 de SandevistanPsychosis (ZombieBuddy tiene que aprobarlo): "
      .. tostring(rawget(_G, "SandevistanPsyBridge") and SandevistanPsyBridge.status())) end
    fn(SFX)
  end
  tip(psy, L("PsyShake"), L("PsyShake_Tip"), player, function()
    sfx(function(SFX) SFX.shake(player, "Overload") end)
  end)
  local function screen(kind)
    sfx(function(SFX)
      SFX.test(player, kind, 15)
      local FXB = rawget(_G, "SandevistanFXBridge")
      if not FXB then S.log("pantalla: sin SandevistanFX no hay tono desafinado (la imagen si)") end
    end)
  end
  tip(psy, L("PsyScreenParanoia"), L("PsyScreenParanoia_Tip"), player, function() screen("Paranoia") end)
  tip(psy, L("PsyScreenDissociation"), L("PsyScreenDissociation_Tip"), player, function() screen("Dissociation") end)
  tip(psy, L("PsyScreenBurst"), L("PsyScreenBurst_Tip"), player, function() sfx(function(SFX) SFX.burst(player, 900) end) end)
  tip(psy, L("PsyScreenStop"), L("PsyScreenStop_Tip"), player, function()
    local SFX = rawget(_G, "SandevistanScreenFX")
    if SFX then SFX.clear(player:getPlayerNum()) end
  end)
  tip(psy, L("PsyC13Sequence"), L("PsyC13Sequence_Tip"), player, function() D.c13Start(player) end)     -- (182) todo en orden
  -- (148) el clon (Doppelganger.lua): quieto mirandote o copiando tus pasos con un segundo de atraso
  local function clone(mode)
    local DG = rawget(_G, "SandevistanDoppelganger")
    if not DG then return end
    if not DG.ready() then
      local FZ = rawget(_G, "SandevistanFakeZombies")
      S.log("clon: " .. tostring(FZ and FZ.notReadyReason and FZ.notReadyReason() or "falta el mod SandevistanPsychosis")); return
    end
    if not DG.spawn(player, mode, true) then S.log("clon: no hubo lugar libre a tu espalda (proba en un lugar abierto)") end
  end
  tip(psy, L("PsyClone"), L("PsyClone_Tip"), player, function() clone("watch") end)
  tip(psy, L("PsyCloneMirror"), L("PsyCloneMirror_Tip"), player, function() clone("mirror") end)
  tip(psy, L("PsyCloneWave"), L("PsyCloneWave_Tip"), player, function() clone("wave") end)
  -- (147) Prueba del disfraz (22 §6.2.1): la piel del otro bando por 60 s, solo en este cliente. Sin el mod SandevistanPsychosis no hace nada.
  local function disguise(chr, mode, what)
    local B = rawget(_G, "SandevistanPsyBridge")
    if not (B and B.disguise) then S.log("disfraz: falta el mod SandevistanPsychosis"); return end
    if B.disguise(chr, mode, 60000) then S.log("disfraz: " .. what .. " por 60 s")
    else S.log("disfraz: el jar no lo hizo (apagado): " .. tostring(B.status())) end
  end
  tip(psy, L("PsyDisguiseZombie"), L("PsyDisguiseZombie_Tip"), player, function()
    local best, bestD
    local zl = getCell() and getCell():getZombieList()
    for i = 0, (zl and zl:size() or 0) - 1 do
      local z = zl:get(i)
      local dd = z and not z:isDead() and z:DistToSquared(player) or nil
      if dd and dd < 400 and (not bestD or dd < bestD) then best, bestD = z, dd end
    end
    if not best then S.log("disfraz: no hay zombis a menos de 20 casillas"); return end
    disguise(best, 1, string.format("zombi a %.1f casillas visto como persona", math.sqrt(bestD)))
  end)
  tip(psy, L("PsyDisguiseSelf"), L("PsyDisguiseSelf_Tip"), player, function()
    disguise(player, 3, "vos, visto como zombi (podredumbre 2)")
  end)
  -- (174) C03: nivel B sobre uno mismo (para probarlo sin otro jugador) y el disfraz como episodio, ahora
  tip(psy, L("PsyDisguiseSelfB"), L("PsyDisguiseSelfB_Tip"), player, function()
    local DS = rawget(_G, "SandevistanDisguise")
    if not (DS and DS.backend) then S.log("disfraz: falta el mod SandevistanPsychosis"); return end
    if DS.testSelf(player, 30000) then S.log("disfraz nivel B: vos como zombi entero por 30 s")
    else S.log("disfraz nivel B: no disponible (" .. (SandevistanViewport.is3D() and "camara 3D sin LevelB3D" or tostring(rawget(_G, "SandevistanPsyBridge") and SandevistanPsyBridge.status())) .. ")") end
  end)
  -- (188) el titere con tu ropa se suelta y viene hacia vos como zombi falso (lo que hace el disfrazado de otro jugador, a veces, de cerca)
  tip(psy, L("PsyDisguiseDetach"), L("PsyDisguiseDetach_Tip"), player, function()
    local DS = rawget(_G, "SandevistanDisguise")
    if not (DS and DS.testDetach) then return end
    local ok, why = DS.testDetach(player)
    S.log(ok and "disfraz: el zombi con tu ropa viene hacia vos" or ("disfraz: no se pudo soltar: " .. tostring(why)))
  end)
  local function disguiseEp(kind)
    local DS = rawget(_G, "SandevistanDisguise")
    if not (DS and DS.ready()) then S.log("disfraz: falta el mod SandevistanPsychosis (o ZombieBuddy no aprobo su jar)"); return end
    if not DS.start(player, kind, true) then
      S.log(kind == "players" and "disfraz: no hay otros jugadores a la vista a menos de " .. CFG.Psychosis.Disguise.Range .. " casillas"
        or "disfraz: no hay zombis a la vista entre " .. CFG.Psychosis.Disguise.MinDist .. " y " .. CFG.Psychosis.Disguise.Range .. " casillas")
    end
  end
  tip(psy, L("PsySelfEcho"), L("PsySelfEcho_Tip"), player, function()           -- (175): eco de tu ultimo ruido
    local SE = rawget(_G, "SandevistanSelfEcho")
    if not SE then return end
    if not SE.echoNow(player) then S.log("eco: todavia no hiciste ningun ruido que se pueda repetir (golpe, disparo, puerta o corrida)") end
  end)
  -- (187) Los sonidos de la cyberpsicosis solo los oye este cliente: susurro al lado y un latido, y en la consola como salieron
  tip(psy, L("PsyPrivateSound"), L("PsyPrivateSound_Tip"), player, function()
    local P, E = rawget(_G, "SandevistanPsychosis"), rawget(_G, "SandevistanEffects")
    if not (P and P.play) then return end
    local a = ZombRandFloat(0, 6.283)
    local id1 = P.play(player, "whisper", player:getX() + math.cos(a) * 1.5, player:getY() + math.sin(a) * 1.5, player:getZ(), 0.8)
    local id2 = P.play(player, "heartbeat", nil, nil, nil, 0.9)
    local log = {}
    for name, r in pairs(E and E.soundLog or {}) do if tostring(r):find("^privado") then log[#log + 1] = name .. " " .. tostring(r) end end
    S.log("sonido privado: susurro id=" .. tostring(id1) .. ", latido id=" .. tostring(id2) .. " | " .. table.concat(log, ", "))
  end)
  -- (176) C05: presion psicotica forzada 60 s (alta = todo mas seguido; baja = sin presion) y el estado en la consola y en un globo
  local function pressure(v)
    PS.forcePressure(player, v, 60)
    PS.pressureTick(player, S.data(player), PS.st(player), S.realMs())
    local line = PS.pressureStatus(player)
    S.log(line); player:Say(line)
  end
  tip(psy, L("PsyPressureHigh"), L("PsyPressureHigh_Tip"), player, function() pressure(1) end)
  tip(psy, L("PsyPressureLow"), L("PsyPressureLow_Tip"), player, function() pressure(0) end)
  -- (177) C05: antesala de crisis de cada tipo, cortarla, y la antesala de la sobrecarga (CN 97 con el implante encendido)
  local function crisis(kind)
    local CR = rawget(_G, "SandevistanCrisis")
    local d = S.data(player)
    if not (CR and d.cyberpsychosisActive and PS.stage(d) >= 2) then S.log("crisis: hace falta cyberpsicosis activa con CN 60 o mas"); return end
    CR.start(player, d, PS.st(player), S.realMs(), kind)
  end
  tip(psy, L("PsyCrisisParanoia"), L("PsyCrisisParanoia_Tip"), player, function() crisis("Paranoia") end)
  tip(psy, L("PsyCrisisDissociation"), L("PsyCrisisDissociation_Tip"), player, function() crisis("Dissociation") end)
  tip(psy, L("PsyCrisisStop"), L("PsyCrisisStop_Tip"), player, function()
    local CR = rawget(_G, "SandevistanCrisis")
    local st = PS.st(player)
    if CR then CR.stop(player, st, S.realMs()); st.cascade = nil; st.nextCrisisMs = nil end
  end)
  tip(psy, L("PsyCascade"), L("PsyCascade_Tip"), player, function()
    local d = S.data(player)
    local s = SandevistanRuntime.session(player)
    if not (s and s.active) then S.log("cascada: encende el implante primero"); return end
    d.neuralLoad = math.max(d.neuralLoad or 0, CFG.Psychosis.Overload.Cascade.FromCN)
    d.lastOverloadHour = -1000
  end)
  -- (178) C05: despertar alucinado, cicatriz neural acumulativa y caja negra
  tip(psy, L("PsyWake"), L("PsyWake_Tip"), player, function()
    local d = S.data(player)
    if not d.cyberpsychosisActive then S.log("despertar alucinado: hace falta cyberpsicosis activa"); return end
    if PS.forceWake(player) then S.log("despertar alucinado: empezado") else S.log("despertar alucinado: no se pudo (opcion apagada)") end
  end)
  tip(psy, L("PsyScar"), L("PsyScar_Tip"), player, function()
    local d = S.data(player)
    local v = S.addNeuralScar(player, d, CFG.NeuralLoad.NeuralScar.PerOverload)
    S.log(string.format("cicatriz neural: %d puntos (umbrales -%d)", v, S.scarOffset(d)))
  end)
  tip(psy, L("PsyScarClear"), L("PsyScarClear_Tip"), player, function()
    local d = S.data(player)
    d.neuralScar, d.neuralScarHours = 0, 0
    local N = rawget(_G, "SandevistanNet"); if N and N.saveState then pcall(N.saveState, player) end
    S.log("cicatriz neural: 0 puntos")
  end)
  tip(psy, L("PsyIncidents"), L("PsyIncidents_Tip"), player, function() PS.dumpIncidents(player) end)
  -- (179) anclas de humanidad: probar el descuento de presion y el empujon de la proxima crisis sin esperar a dormir o leer
  tip(psy, L("PsyAnchor"), L("PsyAnchor_Tip"), player, function()
    local AN = rawget(_G, "SandevistanAnchors")
    if AN and AN.force(player, "read") then S.log("ancla: activada (leer)") else S.log("ancla: no se pudo activar") end
  end)
  tip(psy, L("PsyAnchorClear"), L("PsyAnchorClear_Tip"), player, function()
    local AN = rawget(_G, "SandevistanAnchors")
    if AN then AN.clear(PS.st(player)) end
    S.log("ancla: limpia")
  end)
  tip(psy, L("PsyDisguiseEpZombies"), L("PsyDisguiseEpZombies_Tip"), player, function() disguiseEp("zombies") end)
  tip(psy, L("PsyDisguiseEpPlayers"), L("PsyDisguiseEpPlayers_Tip"), player, function() disguiseEp("players") end)
  psy:addOption(L("PsyDisguiseClear"), player, function()
    local B = rawget(_G, "SandevistanPsyBridge")
    local DS = rawget(_G, "SandevistanDisguise")
    if DS then DS.clear() end
    if B and B.disguiseClear then B.disguiseClear() end
  end)
  tip(psy, L("PsyEchoes"), L("PsyEchoes_Tip"), player, function()                -- (138) ecos (motor de estelas de SandevistanViewpoint)
    local EC = rawget(_G, "SandevistanEchoes")
    if not EC then return end
    if not EC.engine() then S.log("ecos: falta el mod de estelas SandevistanViewpoint (o ZombieBuddy no aprobo su jar)"); return end
    if not EC.start(player, PS.st(player), S.realMs()) then S.log("ecos: no hay zombis a la vista a menos de " .. CFG.Psychosis.Echoes.Range .. " casillas") end
  end)
  tip(psy, L("PsyTextGlitch"), L("PsyTextGlitch_Tip"), player, function()        -- (138) texto corrupto (SandevistanPsychosis)
    if PS and not PS.textGlitch(0.45, 3000) then S.log("texto corrupto: falta el mod SandevistanPsychosis o la opcion esta apagada") end
  end)
  tip(psy, L("PsyMessage"), L("PsyMessage_Tip"), player, function()              -- (192) frase incrustada en un texto corrupto
    if not PS or not PS.forceMessage(player) then
      S.log("mensaje alucinado: falta el mod SandevistanPsychosis o la opcion de texto corrupto")
    else
      S.log("mensaje alucinado: si no se ve, abri el inventario o un tooltip (la frase va dentro de un texto)")
    end
  end)
  psy:addOption(L("PsyAudio"), player, function()
    if PS then PS.st(player).nextAudioMs = 0; PS.st(player).stage = math.max(1, PS.stage(d)) end end)
  -- (170) C01: rotar la intensidad de la cyberpsicosis en este cliente (Apagada -> Leve -> Normal -> Brutal), sin rehacer la partida
  local names = CFG.PsychosisIntensityNames
  local cur = CFG.Psychosis.Intensity or "Normal"
  local nextIdx = 1
  for i, n in ipairs(names) do if n == cur then nextIdx = i % #names + 1 end end
  tip(psy, L("PsyIntensity", L("PsyIntensity_" .. cur), L("PsyIntensity_" .. names[nextIdx])), L("PsyIntensity_Tip"), player, function()
    CFG.applyPsychosisIntensity(nextIdx, CFG.effectiveSandbox())
    S.log("intensidad de la cyberpsicosis: " .. tostring(CFG.Psychosis.Intensity) .. " (solo en este cliente)")
  end)

  -- Modelo 3D de la espalda
  local SPN = SandevistanSpine
  local ui = sub(context, root, L("Ui"))
  local m3 = sub(context, ui, L("Model"))
  m3:addOption(L("ModelRetry"), player, function()
    if SPN then SPN.modelFailures = 0; SPN.lastSync = {}; SPN.syncWorn(player, true) end end)
  m3:addOption(L("ModelRemove"), player, function()
    if SPN then
      local cur = SPN.wornSpine(player)
      if cur then player:removeWornItem(cur); player:getInventory():Remove(cur); player:resetModelNextFrame() end
    end end)

  -- (127) Black Lace colgado del cinturon: girar y mover el modelo en vivo (los dos, militar y casero) y escribir los valores para el script
  local HBK = rawget(_G, "SandevistanHotbar")
  if HBK then
    local bl = sub(context, ui, L("Belt"))
    for _, side in ipairs({ "left", "right" }) do
      local sd = sub(context, bl, side == "left" and L("BeltLeft") or L("BeltRight"))
      for axis, an in ipairs({ "X", "Y", "Z" }) do
        for _, step in ipairs({ { "rotate", 15, L("BeltRotate", an, "+15") }, { "rotate", -15, L("BeltRotate", an, "-15") },
                                { "offset", 0.01, L("BeltMove", an, "+1") }, { "offset", -0.01, L("BeltMove", an, "-1") } }) do
          sd:addOption(step[3], player, function()
            HBK.nudge(player, side, step[1], axis, step[2])
            E.halo(player, HBK.describe(side), 255, 220, 120)
          end)
        end
      end
    end
    bl:addOption(L("BeltLog"), player, function()
      for _, side in ipairs({ "left", "right" }) do S.log("Black Lace cinturon: " .. HBK.describe(side)) end
      E.halo(player, L("BeltLogged"), 255, 220, 120)
    end)
  end

  -- Moodles (Moodle Framework)
  local MO = SandevistanMoodles
  local mo = sub(context, ui, L("Moodles"))
  tip(mo, L("MoodleTest"), L("MoodleTest_Tip"), player, function()
    if MO and MO.ready then MO.startTest() end end)

  -- Panel flotante (d.hudFloating: nil = automatico, true = siempre, false = nunca)
  local HD = SandevistanHUD
  local pn = sub(context, ui, L("Panel"))
  local mode = d.hudFloating == nil and L("PanelAuto") or (d.hudFloating and L("PanelAlways") or L("PanelNever"))
  tip(pn, L("PanelMode", mode), L("PanelMode_Tip"), player, function()
    if HD then HD.toggleFloating(player) end end)
  pn:addOption(L("PanelReset"), player, function() d.hudFloating = nil end)

  -- Dilatación
  local dl = sub(context, ui, L("Dilation"))
  tip(dl, L("SlowAnim", CFG.SlowAnimations.Enabled and "ON" or "OFF"), L("Toggle_Tip"), player, function()
    SD.restoreAll(); CFG.SlowAnimations.Enabled = not CFG.SlowAnimations.Enabled end)
  tip(dl, L("FastAnim", CFG.FastAnimations.Enabled and "ON" or "OFF"), L("Toggle_Tip"), player, function()
    CFG.FastAnimations.Enabled = not CFG.FastAnimations.Enabled end)
  local SAU = rawget(_G, "SandevistanSlowAudio")
  if SAU then
    tip(dl, L("SlowAudio", CFG.SlowAudio.Enabled and "ON" or "OFF"), L("Toggle_Tip"), player, function()
      SAU.restore(); CFG.SlowAudio.Enabled = not CFG.SlowAudio.Enabled end)
  end
  local AP = rawget(_G, "SandevistanAudioProbe")
  if AP and full then
    local ap = sub(context, dl, L("AudioProbe"))
    tip(ap, L("AudioRead"), L("AudioRead_Tip"), player, function() AP.read(player); AP.export(player) end)
    tip(ap, AP.run and L("AudioVoicesRun") or L("AudioVoices"), L("AudioVoices_Tip"), player, function()
      AP.startVoices(player) end)
  end
end

---------------------------------------------------------------------------
-- Recorrido de auditoría: las 3 zonas están a miles de casillas y solo se ve lo cargado, así que se teletransporta al jugador a cada
-- ancla, espera a que cargue el mapa, coloca (o reemplaza) el set, recoge el reporte y al final vuelve y escribe UN txt.
-- Solo un jugador local (SP / anfitrión). Modo invulnerable mientras dura. No se puede usar en un servidor dedicado.
---------------------------------------------------------------------------
local TOUR_ZONES = { "base", "lsu", "ekron" }
local TOUR_MIN_WAIT_MS, TOUR_MAX_WAIT_MS, TOUR_SETTLE_MS = 8000, 40000, 2500
D.tour = nil

local function tourTeleport(player, x, y, z, exact)
  local off = exact and 0 or 0.5           -- a las anclas se entra al centro de la casilla; al origen, a la posición exacta
  S.try("tourTeleport", function()
    player:setX(x + off); player:setY(y + off); player:setZ(z)
    player:setLastX(x + off); player:setLastY(y + off); player:setLastZ(z)
  end)
end

function D.startTour(player, replace)
  if D.tour then S.log("recorrido de auditoria: ya hay uno en curso"); return end
  if not SandevistanWorld then return end
  local god = false
  pcall(function() god = player:isGodMod() == true end)
  D.tour = { player = player, replace = replace and true or false, i = 0, phase = "next", sections = {}, god = god,
             origin = { x = player:getX(), y = player:getY(), z = player:getZ() } }
  pcall(function() player:setGodMod(true) end)
  S.log("recorrido de auditoria iniciado" .. (replace and " (con reemplazo del set)" or "") .. ": no toques nada hasta que termine")
  pcall(function() player:Say(L("TourStart")) end)
end

function D.cancelTour(reason)
  local t = D.tour
  if not t then return end
  D.tour = nil
  pcall(function() t.player:setGodMod(t.god) end)
  tourTeleport(t.player, t.origin.x, t.origin.y, t.origin.z, true)
  S.log("recorrido de auditoria terminado: " .. tostring(reason))
end

local function tourTick()
  local t = D.tour
  if not t then return end
  local ok, err = pcall(function()
    local now = S.realMs()
    local W = SandevistanWorld
    if t.phase == "next" then
      t.i = t.i + 1
      local zone = TOUR_ZONES[t.i]
      if not zone then
        local _, wrote = W.exportAudit(t.sections)
        D.cancelTour("archivo " .. (wrote and "escrito en Zomboid/Lua/Sandevistan_audit.txt" or "NO escrito"))
        pcall(function() t.player:Say(wrote and L("TourDone") or L("TourFail")) end)
        return
      end
      local a = W.anchor(zone)
      if not a then t.sections[zone] = { zone .. ": sin ancla" }; return end
      tourTeleport(t.player, a.x, a.y, a.z)
      t.zone, t.phase, t.since, t.reTp = zone, "wait", now, false
      S.log("recorrido: " .. zone .. " -> " .. a.x .. "," .. a.y .. "," .. a.z .. " (esperando que cargue el mapa)")
    elseif t.phase == "wait" then
      local a = W.anchor(t.zone)
      local age = now - t.since
      local loaded = false
      local sq = getCell() and getCell():getGridSquare(a.x, a.y, a.z)
      loaded = sq ~= nil and sq:getRoom() ~= nil
      if age < TOUR_MIN_WAIT_MS or (not loaded and age < TOUR_MAX_WAIT_MS) then
        if age > 3000 and not t.reTp then t.reTp = true; tourTeleport(t.player, a.x, a.y, a.z) end   -- una vez más, por si el motor lo movió
        return
      end
      if not loaded then S.log("recorrido: " .. t.zone .. ": el ancla sigue sin habitacion cargada tras " .. math.floor(age / 1000) .. " s (se audita igual)") end
      t.phase, t.since = "work", now
    elseif t.phase == "work" then
      if t.replace then W.replace(t.zone) else W.processZone(t.zone, true) end
      t.phase, t.since = "settle", now
    elseif t.phase == "settle" then
      if now - t.since < TOUR_SETTLE_MS then return end
      t.sections[t.zone] = W.collectZone(t.zone)
      t.phase = "next"
    end
  end)
  if not ok then
    S.logAlways("recorrido de auditoria: ERROR " .. tostring(err))
    D.cancelTour("error")
  end
end
Events.OnTick.Add(tourTick)


-- (182) Prueba en orden de C13 (sacudida, pantalla, golpe, corte y figura), para probar todo de una. Cada paso avisa arriba del personaje y
-- escribe en la consola el estado del jar ANTES de correr (asi el paso siguiente muestra lo que hizo el anterior). (183) Un solo modo de
-- sacudida (la imagen del mundo) y el golpe solo con una duracion de las reales (600 ms).
local C13_STEPS = {
  { at = 0, say = "1/8 sacudida", run = function(pl, SFX) SFX.shake(pl, "Overload", 14, 1500) end },
  { at = 2500, say = "2/8 pantalla: paranoia (5 s)", run = function(pl, SFX) SFX.test(pl, "Paranoia", 5) end },
  { at = 8000, say = "3/8 pantalla: disociacion (5 s)", run = function(pl, SFX) SFX.test(pl, "Dissociation", 5) end },
  { at = 10000, say = "4/8 golpe corto encima", run = function(pl, SFX) SFX.burst(pl, 900) end },
  { at = 14000, say = "5/8 golpe corto solo", run = function(pl, SFX) SFX.burst(pl, 600) end },
  { at = 16000, say = "6/8 disociacion 10 s (se corta a los 3 s)", run = function(pl, SFX) SFX.test(pl, "Dissociation", 10) end },
  { at = 19000, say = "7/8 corte", run = function(pl, SFX) SFX.clear(pl:getPlayerNum()) end },
  { at = 21500, say = "8/8 figura fantasma (al costado)", run = function(pl)
      local PF = rawget(_G, "SandevistanPhantomFigures")
      if not (PF and PF.ready() and PF.spawn(pl, true)) then S.log("[prueba C13] la figura no nacio (sin el jar o sin lugar a la vista)") end
    end },
  { at = 24500, say = "fin", run = function() end },
}

function D.c13Start(player)
  local SFX = rawget(_G, "SandevistanScreenFX")
  if not SFX then return end
  if not SFX.allowed() then S.log("[prueba C13] con la camara 3D los efectos estan apagados (Config.Psychosis.ScreenFX.In3D)"); return end
  if not SFX.ready() then
    S.log("[prueba C13] falta el jar 4 de SandevistanPsychosis: " .. tostring(rawget(_G, "SandevistanPsyBridge") and SandevistanPsyBridge.status()))
    return
  end
  D.c13 = { player = player, t0 = S.realMs(), i = 1 }
  S.log(string.format("[prueba C13] empieza (menos destellos: %s, camara %s)", tostring(S.lessFlashes()), SandevistanViewport.is3D() and "3D" or "isometrica"))
end

function D.c13Tick()
  local q = D.c13
  if not q then return end
  local SFX = rawget(_G, "SandevistanScreenFX")
  local step = C13_STEPS[q.i]
  if not (SFX and step) then D.c13 = nil; return end
  if S.realMs() - q.t0 < step.at then return end
  q.i = q.i + 1
  S.log("[prueba C13] " .. step.say .. " | " .. tostring(SFX.statusLine()))
  E.halo(q.player, "C13 " .. step.say, 255, 120, 220)
  local ok, err = pcall(step.run, q.player, SFX)
  if not ok then S.log("[prueba C13] error en el paso: " .. tostring(err)) end
  if q.i > #C13_STEPS then D.c13 = nil end
end

Events.OnTick.Add(S.safe("Debug.c13Tick", D.c13Tick))

return D
