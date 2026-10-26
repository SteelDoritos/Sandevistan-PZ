-- Sandevistan / ContextMenus: opciones de inventario y de mundo. Solo muestran opciones
-- (con motivo si no están disponibles) y encolan SandevistanAction con la lógica de Medical.
require "Sandevistan/Core"
require "Sandevistan/Medical"
require "Sandevistan/NotesText"
require "Sandevistan/Dossier"
require "Sandevistan/Reader"
require "Sandevistan/Dialog"
require "Sandevistan/TimedActions/SandevistanAction"
require "Sandevistan/Runtime"
require "Sandevistan/RemoteSurgery"
require "Sandevistan/FirmwareClient"

local CFG = SandevistanConfig
local S = Sandevistan
local getText = S.text     -- requisitos con el nombre vanilla del ítem
local M = SandevistanMedical
local T = M.T
local DOS = SandevistanDossier
local E = SandevistanEffects
local FW = SandevistanFirmware
local FC = SandevistanFirmwareClient

SandevistanMenus = {}
local MN = SandevistanMenus

---------------------------------------------------------------------------
-- Helpers de UI
---------------------------------------------------------------------------
local function tooltip(option, lines)
  if not option or not lines or #lines == 0 then return end
  local tt = ISInventoryPaneContextMenu.addToolTip()
  tt.description = table.concat(lines, " <LINE> ")
  option.toolTip = tt
end

local function disabled(option, reasons)
  option.notAvailable = true
  tooltip(option, reasons)
end

-- (155) T06: motivos de siempre + la línea de la guía con libros (IGUI_Sandevistan_BookGuided). La opción queda deshabilitada solo con motivos:
-- con los libros el motivo desaparece y queda el aviso de lo que cuesta (más tiempo y chance de que salga mal).
local function tips(option, reasons, books)
  local lines = {}
  for _, r in ipairs(reasons or {}) do lines[#lines + 1] = r end
  if books then
    lines[#lines + 1] = getText("IGUI_Sandevistan_BookGuided", books.gap, string.format("%.2f", books.timeMult),
      string.format("%d %s", math.floor((books.fail or 0) * 100 + 0.5), "%"))
  end
  if #lines > 0 then tooltip(option, lines) end
  if reasons and #reasons > 0 then option.notAvailable = true end
end

-- style: clave de SandevistanReader.STYLES (papel, militar, papelito, estudiante). v0.1.30 (23): ventana movible en vez del modal.
local function showText(player, title, body, w, h, style)
  w, h = w or 560, h or 480
  if SandevistanReader and SandevistanReader.show and pcall(SandevistanReader.show, title, body, w, h, style) then return end
  local x = (getCore():getScreenWidth() - w) / 2
  local y = (getCore():getScreenHeight() - h) / 2
  local modal = ISModalRichText:new(x, y, w, h, " <H2> " .. title .. " <LINE> <LINE> <TEXT> " .. body, false)
  modal:initialise()
  modal:addToUIManager()
end

MN.showText = showText

-- Estilo de la ventana de lectura segun quien escribio: los informes oficiales del programa son militares, el resto del investigador va en papel,
-- el guardia en un papelito amarillo y el estudiante en su cuaderno.
local OFFICIAL_NOTES = { [2] = true, [3] = true, [5] = true, [6] = true, [8] = true, [11] = true, [12] = true }
function MN.storyStyle(id) return id == "depot" and "sticky" or id == "student" and "student" or "military" end
function MN.noteStyle(n)
  if OFFICIAL_NOTES[n] then return "military" end
  local story = DOS.storyOfNote(n)
  return story and story.id == "researcher" and "paper" or MN.storyStyle(story and story.id)
end

local function confirm(player, text, onYes)
  SandevistanDialog.yesNo(player:getPlayerNum(), text, 460, 240, function(yes) if yes then onYes() end end)
end

local function ensureInInventory(player, item)
  if item and item:getContainer() ~= player:getInventory() then
    pcall(function() ISInventoryPaneContextMenu.transferIfNeeded(player, item) end)
  end
end

local function queue(player, params)
  ISTimedActionQueue.add(SandevistanAction:new(player, params))
end

local function stillHas(player, item)
  return function() return item:getContainer() ~= nil and player:getInventory():contains(item, true) end
end

-- Inyectarse Black Lace (militar o casero): la del menu del item y (127) la tecla del cinturon (Hotbar.lua)
function MN.injectKerenzikov(player, item)
  local crafted = item:getFullType() == M.T.KereCrafted
  ensureInInventory(player, item)
  queue(player, { label = "kerenzikov", time = 40, anim = "TakePills", stopOnWalk = false, stopOnAim = false,      -- (108) se toma caminando (TakePills mueve solo el torso; Loot frenaba al personaje)
    isValid = stillHas(player, item),
    onStart = function(a) a.soundId = M.playKerenzikovSound(player, crafted) end,
    onStop = function(a) M.stopDoseSound(player, a.soundId) end,
    onPerform = function() M.takeKerenzikov(player, item, crafted, true) end })
end

---------------------------------------------------------------------------
-- Cirugía
---------------------------------------------------------------------------
function MN.startSurgery(surgeon, patient, implant, option)
  local text = getText("IGUI_Sandevistan_SurgeryWarning")
  if not M.hasAnyImmuno(patient) then text = text .. " <LINE> <LINE> " .. getText("IGUI_Sandevistan_SurgeryNoImmuno") end
  text = text .. " <LINE> <LINE> " .. getText("IGUI_Sandevistan_SurgeryChance", math.floor(option.chance * 100 + 0.5))
  if option.books then                                                                    -- (155) T06: guiada con libros
    text = text .. " <LINE> <LINE> " .. getText("IGUI_Sandevistan_BookGuided", option.books.gap, string.format("%.2f", option.books.timeMult),
      string.format("%d %s", math.floor((option.books.fail or 0) * 100 + 0.5), "%"))
  end
  if option.sloppy then text = text .. " <LINE> <LINE> " .. getText("IGUI_Sandevistan_SurgerySloppyWarn") end
  confirm(surgeon, text, function()
    ensureInInventory(surgeon, implant)
    queue(surgeon, {
      label = "surgery", time = option.time, anim = "Loot",
      faceObject = surgeon ~= patient and patient or nil,
      isValid = function()
        if not M.canReceiveImplant(patient) then return false end
        if surgeon ~= patient and surgeon:DistTo(patient) > 1.8 then return false end
        return stillHas(surgeon, implant)()
      end,
      onPerform = function() M.performSurgery(surgeon, patient, implant, option) end,
    })
  end)
end

local function addSurgeryMenu(context, surgeon, patient, implant, titleKey)
  local root = context:addOption(getText(titleKey), nil, nil)
  local sub = ISContextMenu:getNew(context)
  context:addSubMenu(root, sub)
  if not M.canReceiveImplant(patient) then
    disabled(root, { getText("IGUI_Sandevistan_Req_AlreadyImplanted") })
    return
  end
  for _, opt in ipairs(M.surgeryOptions(surgeon, patient, implant)) do
    local label = getText("IGUI_Sandevistan_Surgery_" .. opt.key) .. string.format(" (%d%%)", math.floor(opt.chance * 100 + 0.5))
      .. (opt.dossier and (" - " .. getText("IGUI_Sandevistan_Surgery_Dossier")) or "")
    local o = sub:addOption(label, surgeon, function() MN.startSurgery(surgeon, patient, implant, opt) end)
    tips(o, opt.reasons, opt.books)
  end
end

-- Cirugía sobre un jugador remoto (multijugador): pide permiso al paciente y, si acepta,
-- opera con una acción temporizada. La aplicación del implante la hace el cliente del paciente.
local function addRemoteSurgeryMenu(context, surgeon, patient, implant)
  local root = context:addOption(getText("IGUI_Sandevistan_OperateOn") .. ": " .. tostring(patient:getUsername()), nil, nil)
  local sub = ISContextMenu:getNew(context)
  context:addSubMenu(root, sub)
  local RS = SandevistanRemoteSurgery
  local id = patient:getOnlineID()
  for _, opt in ipairs(M.surgeryOptions(surgeon, patient, implant)) do
    local label = getText("IGUI_Sandevistan_Surgery_" .. opt.key) .. string.format(" (%d%%)", math.floor(opt.chance * 100 + 0.5))
      .. (opt.dossier and (" - " .. getText("IGUI_Sandevistan_Surgery_Dossier")) or "")
    local o = sub:addOption(label, surgeon, function()
      local text = getText("IGUI_Sandevistan_SurgeryWarning") .. " <LINE> <LINE> "
        .. getText("IGUI_Sandevistan_SurgeryChance", math.floor(opt.chance * 100 + 0.5))
        .. (opt.books and (" <LINE> <LINE> " .. getText("IGUI_Sandevistan_BookGuided", opt.books.gap,
             string.format("%.2f", opt.books.timeMult), string.format("%d %s", math.floor((opt.books.fail or 0) * 100 + 0.5), "%"))) or "")
        .. (opt.sloppy and (" <LINE> <LINE> " .. getText("IGUI_Sandevistan_SurgerySloppyWarn")) or "")
      confirm(surgeon, text, function()
        ensureInInventory(surgeon, implant)
        RS.request(surgeon, patient, implant, opt, function()
          queue(surgeon, {
            label = "surgeryRemote", time = opt.time, anim = "Loot", faceObject = patient,
            isValid = function()
              return not patient:isDead() and surgeon:DistTo(patient) <= 1.8 and stillHas(surgeon, implant)()
            end,
            onPerform = function() RS.perform(surgeon, id, implant, opt) end,
          })
        end)
      end)
    end)
    tips(o, opt.reasons, opt.books)
  end
end

---------------------------------------------------------------------------
-- Inventario
---------------------------------------------------------------------------
local function unwrap(items)
  local out = {}
  for _, v in ipairs(items) do
    if instanceof(v, "InventoryItem") then table.insert(out, v)
    elseif v.items and v.items[1] then table.insert(out, v.items[1]) end
  end
  return out
end

local function addCraftMenu(context, player)
  local root = context:addOption(getText("IGUI_Sandevistan_CraftMenu"), nil, nil)
  local sub = ISContextMenu:getNew(context)
  context:addSubMenu(root, sub)
  local any = false
  for _, key in ipairs(M.RecipeOrder) do
    local rc = M.Recipes[key]
    if M.knows(player, rc.knowledge) then
      any = true
      local reasons = {}
      for _, req in ipairs(rc.check(player)) do if not req[1] then table.insert(reasons, req.raw and req[2] or getText(req[2])) end end
      -- (155) T06: el ensamblado del P06 por menú también acepta los libros (chance y tiempo); las demás recetas son nativas (T07).
      local books = (key == "proto06") and M.bookInfo(M.proto06Guide(player), 1 - (rc.chance and rc.chance(player) or 0)) or nil
      local label = getText(rc.label)
      if rc.chance then label = label .. string.format(" (%d%%)", math.floor(rc.chance(player) * 100 + 0.5)) end
      local o = sub:addOption(label, player, function()
        queue(player, { label = key, time = (rc.time or CFG.Crafting.Time) * (books and books.timeMult or 1), anim = "Craft",
          isValid = function()
            for _, req in ipairs(rc.check(player)) do if not req[1] then return false end end
            return true
          end,
          onPerform = function() rc.perform(player) end })
      end)
      tips(o, reasons, books)
    end
  end
  if not any then disabled(root, { getText("IGUI_Sandevistan_CraftNoneKnown") }) end
end

local function describeImplant(item)
  local deg, floor = M.itemDegradation(item)
  local lines = {
    getText(M.implantVariant(item) == "military" and "IGUI_Sandevistan_HUD_Military" or "IGUI_Sandevistan_HUD_Lab"),
    getText("IGUI_Sandevistan_Info_Degradation", string.format("%.1f", deg)),
  }
  if floor > 1.0 then table.insert(lines, getText("IGUI_Sandevistan_Info_Floor", string.format("%.1f", floor))) end
  local proto = item:getModData().prototype
  if proto == "04" then table.insert(lines, getText("IGUI_Sandevistan_Info_P04")) end
  if proto == "06" then table.insert(lines, getText("IGUI_Sandevistan_Info_P06")) end
  if proto == "07" then table.insert(lines, getText("IGUI_Sandevistan_Info_P07")) end
  local plate = M.itemPlate(item)
  if plate then table.insert(lines, getText("IGUI_Sandevistan_Info_Plate", plate)) end
  return lines
end

-- (69) Nombre de la placa (P06 / Mk. II): pide una lapicera; el cuadro de texto es el de vanilla (ISTextBox). Texto vacio = vuelve al nombre original.
function MN.onPlateEntered(target, button, player, item)
  if not button or button.internal ~= "OK" then return end
  if #M.plateReq(player, item) > 0 or not stillHas(player, item)() then return end
  local text = button.parent and button.parent.entry and button.parent.entry:getText() or ""
  local plate = M.setPlate(item, text)
  E.halo(player, plate and getText("IGUI_Sandevistan_PlateDone", plate) or getText("IGUI_Sandevistan_PlateCleared"), 80, 220, 255)
end

function MN.askPlate(player, item)
  local w, h = 320, 170
  local x, y = (getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2
  local modal = ISTextBox:new(x, y, w, h, getText("IGUI_Sandevistan_PlatePrompt", CFG.Plate.MaxLength), M.itemPlate(item) or "", nil,
                              MN.onPlateEntered, player:getPlayerNum(), player, item)
  modal:initialise()
  modal:addToUIManager()
end

function MN.addPlateOption(context, player, item)
  if not M.plateAllowed(item) then return end
  local reasons = M.plateReq(player, item)
  local o = context:addOption(getText("IGUI_Sandevistan_PlateName"), player, function() MN.askPlate(player, item) end)
  if #reasons > 0 then disabled(o, reasons) end
end

-- Ingeniería inversa (Prototipo 06): solo mientras no se conozca el diseño.
function MN.addStudyOption(context, player, item)
  if not CFG.Prototype06.Enabled or S.data(player).knows.proto06 then return end
  local reasons = M.studyReq(player, item)
  local books = M.bookInfo(M.studyGuide(player))
  local o = context:addOption(getText("IGUI_Sandevistan_Study"), player, function()
    local text = getText(item:getFullType() == T.P04 and "IGUI_Sandevistan_StudyWarningP04" or "IGUI_Sandevistan_StudyWarning")
    confirm(player, text, function()
      ensureInInventory(player, item)
      queue(player, { label = "study", time = CFG.Prototype06.Study.Time * (books and books.timeMult or 1), anim = "Craft",
        isValid = function() return #M.studyReq(player, item) == 0 and stillHas(player, item)() end,
        onPerform = function() M.performStudy(player, item) end })
    end)
  end)
  tips(o, reasons, books)
end

-- Ingenieria inversa del implante MILITAR (Prototipo 07, v0.1.30 (43)): pide llevar los dos expedientes militares completos.
function MN.addStudyMilOption(context, player, item)
  if item:getFullType() ~= T.Military or not CFG.Prototype07.Enabled or S.data(player).knows.proto07 then return end
  local reasons = M.studyMilReq(player, item)
  local books = M.bookInfo(M.studyMilGuide(player))
  local o = context:addOption(getText("IGUI_Sandevistan_StudyMil"), player, function()
    confirm(player, getText("IGUI_Sandevistan_StudyMilWarning"), function()
      ensureInInventory(player, item)
      queue(player, { label = "studyMil", time = CFG.Prototype07.Study.Time * (books and books.timeMult or 1), anim = "Craft",
        isValid = function() return #M.studyMilReq(player, item) == 0 and stillHas(player, item)() end,
        onPerform = function() M.performStudyMil(player, item) end })
    end)
  end)
  tips(o, reasons, books)
end

---------------------------------------------------------------------------
-- Firmware (82): opciones del chip en el inventario y submenu de los chips instalados (menu de mundo)
---------------------------------------------------------------------------
-- Ventana de detalle de un programa (id = nil: el chip base).
function MN.showChip(player, id)
  local title, body = FC.detail(player, id)
  showText(player, title, body, 520, 420, "military")
end

-- Instalar el chip: accion de ~10 s (sin PC ni cirugia). Los motivos que faltan salen en el tooltip de la opcion.
function MN.startFlash(player, item, id)
  ensureInInventory(player, item)
  queue(player, { label = "flash", time = FC.ticks(CFG.Firmware.FlashSeconds), anim = "Craft",
    isValid = function() return #FC.flashReasons(player, id) == 0 and stillHas(player, item)() end,
    onPerform = function() FC.flash(player, item) end })
end

function MN.startUnflash(player, slot)
  queue(player, { label = "unflash", time = FC.ticks(CFG.Firmware.FlashSeconds), anim = "Craft",
    isValid = function() return #FC.removeReasons(player, slot) == 0 end,
    onPerform = function() FC.unflash(player, slot) end })
end

function MN.addChipOptions(context, player, item, ft)
  local id = FW.idOfItem(ft)
  if id then
    local p = FW.program(id)
    local reasons = FC.flashReasons(player, id)
    local o = context:addOption(getText("IGUI_Sandevistan_Fw_Install", FC.slotLabel(p.slot)), player, function() MN.startFlash(player, item, id) end)
    if #reasons > 0 then disabled(o, reasons) end
  end
  context:addOption(getText("IGUI_Sandevistan_Fw_Detail"), player, function() MN.showChip(player, id) end)
  if id and FW.enabled() and not FW.known(S.data(player), id) then               -- (87) decompilar este chip con el terminal, si lo llevas
    local term = M.find(player, CFG.Firmware.Write.Terminal)
    if term then
      local src = { kind = "terminal", item = term }
      local reasons = FC.decompileReasons(player, id, src)
      local o = context:addOption(getText("IGUI_Sandevistan_Fw_DecompileThis"), player, function() MN.startDecompile(player, id, src) end)
      if #reasons > 0 then disabled(o, reasons) end
    end
  end
end

-- Submenu "Firmware" con los chips instalados (solo si hay alguno): ver el programa y sacar el chip.
function MN.addFirmwareMenu(context, player, always)
  local d = S.data(player)
  if not (FW.enabled() and S.hasWorkingImplant(d)) then return end
  if always and not (FW.slotProgram(d, "sistema") or FW.slotProgram(d, "habilidad")) then
    local o = context:addOption(getText("IGUI_Sandevistan_Fw_Menu"), nil, nil)
    disabled(o, { getText("IGUI_Sandevistan_Fw_NoneInstalled") })
    return
  end
  local sub = nil
  for _, slot in ipairs(CFG.Firmware.Slots) do
    local id = FW.slotProgram(d, slot)
    if id then
      if not sub then
        local root = context:addOption(getText("IGUI_Sandevistan_Fw_Menu"), nil, nil)
        sub = ISContextMenu:getNew(context)
        context:addSubMenu(root, sub)
      end
      if not always then sub:addOption(getText("IGUI_Sandevistan_Fw_DetailOf", FC.slotLabel(slot), FC.name(id)), player, function() MN.showChip(player, id) end) end          -- (91) en el implante equipado solo se saca; ver el programa va en el chip y en el menu del piso
      local reasons = FC.removeReasons(player, slot)
      local o = sub:addOption(getText("IGUI_Sandevistan_Fw_Remove", FC.slotLabel(slot), FC.name(id)), player, function() MN.startUnflash(player, slot) end)
      if #reasons > 0 then disabled(o, reasons) end
    end
  end
end

-- Escribir firmware (85): submenu con los programas que conoces, en una computadora con corriente o con el terminal portatil. Cada programa muestra en el tooltip lo que
-- cambia y lo que tarda; si falta algo (chip virgen, microchip militar, corriente, bateria) la opcion sale deshabilitada con el motivo.
-- src = { kind = "pc", square = casilla, obj = objeto } | { kind = "terminal", item = item }
function MN.startWrite(player, id, src)
  if src.kind == "terminal" then
    ensureInInventory(player, src.item)
  elseif src.square and luautils and luautils.walkAdj then
    pcall(function() luautils.walkAdj(player, src.square) end)
  end
  queue(player, { label = "fwWrite", time = FC.writeTicks(player), anim = "Craft", faceObject = src.kind == "pc" and src.obj or nil,
    isValid = function() return #FC.writeReasons(player, id, src) == 0 end,
    onPerform = function() FC.write(player, id, src) end })
end

function MN.addWriteMenu(context, player, src)
  if not FW.enabled() then return end
  local d = S.data(player)
  local root = context:addOption(getText(src.kind == "pc" and "IGUI_Sandevistan_Fw_WritePC" or "IGUI_Sandevistan_Fw_WriteTerminal"), nil, nil)
  local list = FW.knownList(d)
  if #list == 0 then
    disabled(root, { getText("IGUI_Sandevistan_Fw_Req_NoneKnown") })
    return
  end
  local sub = ISContextMenu:getNew(context)
  context:addSubMenu(root, sub)
  local secs = math.floor(FC.writeSeconds(player) + 0.5)
  for _, id in ipairs(list) do
    local p = FW.program(id)
    local reasons = FC.writeReasons(player, id, src)
    local o = sub:addOption(getText("IGUI_Sandevistan_Fw_WriteOption", FC.name(id), p.code, FC.slotLabel(p.slot)), player, function() MN.startWrite(player, id, src) end)
    local lines = {}
    for _, r in ipairs(reasons) do lines[#lines + 1] = r end
    for _, l in ipairs(FW.fieldLines(id)) do lines[#lines + 1] = l end
    lines[#lines + 1] = getText("IGUI_Sandevistan_Fw_WriteTime", secs)
    tooltip(o, lines)
    if #reasons > 0 then o.notAvailable = true end
  end
end

-- Decompilar firmware (87): un chip programado que encontraste, en una computadora con corriente o con el terminal. Se aprende su programa y el chip queda en blanco; el submenu
-- lista los chips programados que llevas (los de programas que ya sabes salen deshabilitados). Sin chips programados la opcion no aparece.
function MN.startDecompile(player, id, src)
  if src.kind == "terminal" then
    ensureInInventory(player, src.item)
  elseif src.square and luautils and luautils.walkAdj then
    pcall(function() luautils.walkAdj(player, src.square) end)
  end
  queue(player, { label = "fwDecompile", time = FC.decompileTicks(player), anim = "Craft", faceObject = src.kind == "pc" and src.obj or nil,
    isValid = function() return #FC.decompileReasons(player, id, src) == 0 end,
    onPerform = function() FC.decompile(player, id, src) end })
end

function MN.addDecompileMenu(context, player, src)
  if not FW.enabled() then return end
  local chips = FC.programmedChips(player)
  if #chips == 0 then return end
  local root = context:addOption(getText(src.kind == "pc" and "IGUI_Sandevistan_Fw_DecompilePC" or "IGUI_Sandevistan_Fw_DecompileTerminal"), nil, nil)
  local sub = ISContextMenu:getNew(context)
  context:addSubMenu(root, sub)
  local secs = math.floor(FC.decompileSeconds(player) + 0.5)
  for _, e in ipairs(chips) do
    local p = FW.program(e.id)
    local reasons = FC.decompileReasons(player, e.id, src)
    local o = sub:addOption(getText("IGUI_Sandevistan_Fw_WriteOption", FC.name(e.id), p.code, FC.slotLabel(p.slot)), player, function() MN.startDecompile(player, e.id, src) end)
    local lines = {}
    for _, r in ipairs(reasons) do lines[#lines + 1] = r end
    lines[#lines + 1] = getText("IGUI_Sandevistan_Fw_DecompileTime", secs)
    tooltip(o, lines)
    if #reasons > 0 then o.notAvailable = true end
  end
end

local function onFillInventory(playerIndex, context, items)
  local player = getSpecificPlayer(playerIndex)
  if not player then return end
  local list = unwrap(items)
  local item = list[1]
  if not item then return end
  local ft = item:getFullType()

  if ft == T.Military or ft == T.Lab then
    local info = context:addOption(getText("IGUI_Sandevistan_Examine"), nil, nil)
    tooltip(info, describeImplant(item))
    addSurgeryMenu(context, player, player, item, "IGUI_Sandevistan_SelfInstall")
    -- cirugía asistida sobre otro jugador local (pantalla dividida) o remoto (multijugador)
    for i = 0, getNumActivePlayers() - 1 do
      local other = getSpecificPlayer(i)
      if other and other ~= player and not other:isDead() and player:DistTo(other) <= 2 then
        addSurgeryMenu(context, player, other, item, "IGUI_Sandevistan_OperateOn")
      end
    end
    -- multijugador: jugadores de otros clientes a menos de 2 tiles
    if isClient() then
      local online = getOnlinePlayers()
      for i = 0, (online and online:size() or 0) - 1 do
        local other = online:get(i)
        if other and not other:isLocalPlayer() and not other:isDead() and player:DistTo(other) <= 2 then
          addRemoteSurgeryMenu(context, player, other, item)
        end
      end
    end
    local reasons = M.calibrationReq(player, item)
    local booksCal = M.bookInfo(M.calibrationGuide(player))
    local o = context:addOption(getText("IGUI_Sandevistan_Calibrate"), player, function()
      ensureInInventory(player, item)
      queue(player, { label = "calibrate", time = CFG.Calibration.Time * (booksCal and booksCal.timeMult or 1), anim = "Craft",
        isValid = function() return #M.calibrationReq(player, item) == 0 and stillHas(player, item)() end,
        onPerform = function() M.performCalibration(player, item) end })
    end)
    tips(o, reasons, booksCal)
    MN.addPlateOption(context, player, item)
    MN.addStudyOption(context, player, item)
    MN.addStudyMilOption(context, player, item)

  elseif ft == T.P04 then
    local reasons = M.repairReq(player)
    local chance = M.repairChance(player)                       -- (155) T06: con libros, la chance del mínimo menos la pérdida por nivel
    local booksRep = M.bookInfo(M.repairGuide(player), 1 - chance)
    local o = context:addOption(getText("IGUI_Sandevistan_RepairP04") .. string.format(" (%d%%)", math.floor(chance * 100 + 0.5)), player, function()
      ensureInInventory(player, item)
      queue(player, { label = "repairP04", time = CFG.Prototype04.Time * (booksRep and booksRep.timeMult or 1), anim = "Craft",
        isValid = function() return #M.repairReq(player) == 0 and stillHas(player, item)() end,
        onPerform = function() M.performRepair(player, item) end })
    end)
    tips(o, reasons, booksRep)
    MN.addStudyOption(context, player, item)

  elseif ft == T.CryoBox then
    context:addOption(getText("IGUI_Sandevistan_OpenCryo"), player, function()
      ensureInInventory(player, item)
      queue(player, { label = "openCryo", time = 300, anim = "Loot",
        isValid = stillHas(player, item), onPerform = function() M.openCryoBox(player, item) end })
    end)

  elseif ft == CFG.Firmware.Write.Terminal then
    MN.addWriteMenu(context, player, { kind = "terminal", item = item })          -- (85)
    MN.addDecompileMenu(context, player, { kind = "terminal", item = item })      -- (87)

  elseif M.immunoTier(ft) then
    local tier = M.immunoTier(ft)
    local before, after, hours, idBefore, idAfter = M.immunoPreview(player, tier)       -- (49) el menu muestra el efecto: asi se ve cuanto se aprovecha
    local label = getText("IGUI_Sandevistan_TakeDoseInfo", math.floor(before + 0.5), math.floor(after + 0.5), math.floor(hours + 0.5))
    if S.immunodepOn() then                                                               -- (135) y cuanto sube la inmunodepresion
      label = label .. getText("IGUI_Sandevistan_TakeDoseImmunodep", math.floor(idBefore + 0.5), math.floor(idAfter + 0.5))
    end
    context:addOption(label, player, function()
      ensureInInventory(player, item)
      queue(player, { label = "dose", time = M.DOSE_TIME, anim = "TakePills", stopOnWalk = false, stopOnAim = false,      -- (108) se toma caminando (TakePills mueve solo el torso; Loot frenaba al personaje)
        isValid = stillHas(player, item),
        onStart = function(a) a.soundId = M.playDoseSound(player, tier) end,       -- el sonido arranca con la accion
        onStop = function(a) M.stopDoseSound(player, a.soundId) end,
        onPerform = function() M.takeImmuno(player, item, tier, true) end })
    end)

  elseif ft == CFG.Crafting.Items.AntiDep and not M.antidepHooked then
    -- solo si no se pudo enganchar la acción vanilla de tomar pastillas
    context:addOption(getText("IGUI_Sandevistan_TakeAntidep"), player, function()
      ensureInInventory(player, item)
      queue(player, { label = "antidep", time = 60, anim = "TakePills", stopOnWalk = false, stopOnAim = false,      -- (108) se toma caminando (TakePills mueve solo el torso; Loot frenaba al personaje)
        isValid = stillHas(player, item),
        onPerform = function()
          S.serverUse(player, item, "use")                                    -- (115) MP
          local okUse = pcall(function() item:Use() end)
          if not okUse then local c = item:getContainer(); if c then c:DoRemoveItem(item); if isClient() then pcall(sendRemoveItemFromContainer, c, item) end end end
          M.applyAntidepressant(player)
        end })
    end)

  elseif ft == T.KereMil or ft == T.KereCrafted then
    context:addOption(getText("IGUI_Sandevistan_Inject"), player, function() MN.injectKerenzikov(player, item) end)

  elseif FW.isChip(ft) then
    MN.addChipOptions(context, player, item, ft)

  elseif ft == CFG.Guide.Item then
    context:addOption(getText("IGUI_Sandevistan_Read"), player, function() MN.showGuide(player) end)

  elseif string.find(ft, "^Sandevistan%.SandevistanNote%d%d$") then
    local n = tonumber(string.sub(ft, -2))
    local note = SandevistanNotes and SandevistanNotes[n]
    local story, page, total = DOS.storyOfNote(n)
    if note and story then
      local title = string.format("%s (%d/%d)", note.title, page, total)
      context:addOption(getText("IGUI_Sandevistan_Read"), player, function() showText(player, title, note.text, nil, nil, MN.noteStyle(n)) end)
      -- archivar en el expediente de su historia (lo crea con la primera página)
      local dossier = DOS.find(player, story)
      local o = context:addOption(getText(dossier and "IGUI_Sandevistan_DossierFile" or "IGUI_Sandevistan_DossierStart"), player, function()
        ensureInInventory(player, item)
        queue(player, { label = "fileNote", time = CFG.Notes.FileTime, anim = "Loot", stopOnWalk = false,
          isValid = stillHas(player, item),
          onPerform = function() DOS.fileNotes(player, story, { { n = n, item = item } }) end })
      end)
      if dossier and DOS.filed(dossier)[n] then disabled(o, { getText("IGUI_Sandevistan_DossierAlready") }) end
    end

  elseif DOS.storyOfDossier(ft) then
    local story = DOS.storyOfDossier(ft)
    context:addOption(getText("IGUI_Sandevistan_DossierRead"), player, function()
      local title, body = DOS.readText(item, story, MN.storyStyle(story.id))
      showText(player, title, body, 640, 560, MN.storyStyle(story.id))
    end)
    local loose = DOS.looseNotes(player, story, item)
    if #loose > 0 then
      context:addOption(getText("IGUI_Sandevistan_DossierFileAll", #loose), player, function()
        ensureInInventory(player, item)
        queue(player, { label = "fileNotes", time = CFG.Notes.FileTime, anim = "Loot", stopOnWalk = false,
          isValid = stillHas(player, item),
          onPerform = function() DOS.fileNotes(player, story, DOS.looseNotes(player, story, item)) end })
      end)
    end
  
  elseif string.sub(ft, 1, 28) == "Sandevistan.SandevistanSpine" then          -- (89) el Sandevistan equipado en la espalda: ver y sacar los chips instalados
    MN.addFirmwareMenu(context, player, true)
  end

  -- v0.1.30 (15): las recetas estan en el menu de crafteo del juego; este submenu es solo el respaldo si no se cargaron
  if not M.nativeRecipesLoaded() then
    local known = M.CraftTriggersIfKnown[ft]
    if M.CraftTriggers[ft] or (known and M.knows(player, known)) then addCraftMenu(context, player) end
  end
end

---------------------------------------------------------------------------
-- Mundo: extracción sobre cadáveres
---------------------------------------------------------------------------
local function findBodies(worldObjects, context)
  local seenSq, seenBody, out = {}, {}, {}
  local function add(b) if b and not seenBody[b] then seenBody[b] = true; table.insert(out, b) end end
  -- (99) el cadaver bajo el cursor: el menu del juego lo busca igual (IsoObjectPicker:PickCorpse) porque no siempre viene en worldObjects
  local picker = rawget(_G, "IsoObjectPicker")
  if picker and picker.Instance and context and context.requestX then
    pcall(function() add(picker.Instance:PickCorpse(context.requestX, context.requestY)) end)
  end
  for _, obj in ipairs(worldObjects) do
    local sq = obj.getSquare and obj:getSquare()
    if sq and not seenSq[sq] then
      seenSq[sq] = true
      local bodies = sq:getDeadBodys()
      if bodies then
        for i = 0, bodies:size() - 1 do add(bodies:get(i)) end
      end
    end
  end
  return out
end

local function onFillWorld(playerIndex, context, worldObjects, test)
  if test then return end
  local player = getSpecificPlayer(playerIndex)
  if not player then return end
  -- síntesis / P06 desde el mundo (ej.: parado frente a una mesa), una vez aprendida la receta
  -- v0.1.30 (29): ya estan en el menu de crafteo del juego; este submenu queda solo de respaldo si las recetas nativas no cargaron
  if M.knows(player, "proto06") and not M.nativeRecipesLoaded() then addCraftMenu(context, player) end
  for _, body in ipairs(findBodies(worldObjects, context)) do
    local info = M.corpseImplant(body)
    if info then
      -- (101) UNA sola opcion: con bisturi sale limpia; sin bisturi pero con un cuchillo afilado, tosca (mas desgaste, tarda mas, riesgo de corte);
      -- sin ninguno de los dos, la misma opcion en gris con el motivo. El modo se decide al hacer clic y la accion lo revalida.
      local mode = M.extractionMode(player)
      local crudeLabel = mode == "crude"
      local o = context:addOption(getText(crudeLabel and "IGUI_Sandevistan_ExtractCrude" or "IGUI_Sandevistan_Extract"), player, function()
        local tool = mode == "clean" and M.find(player, CFG.Crafting.Items.Scalpel) or M.crudeTool(player)
        if not tool then return end
        ensureInInventory(player, tool)
        if luautils and luautils.walkAdj then pcall(function() luautils.walkAdj(player, body:getSquare()) end) end
        local crude = mode == "crude"
        queue(player, { label = crude and "extractCrude" or "extract", time = CFG.Extraction.Time * (crude and CFG.Extraction.Crude.TimeMult or 1), anim = "Loot", faceObject = body,
          isValid = function() return M.corpseImplant(body) ~= nil and #(crude and M.crudeExtractionReq(player) or M.extractionReq(player)) == 0 end,
          onPerform = function() M.performExtraction(player, body, crude) end })
      end)
      if not mode then disabled(o, M.extractionAnyReq(player)) end
      break
    end
  end
  -- calibración del implante instalado (propio o de otro jugador local cercano)
  local function addInstalledCalib(patient, key)
    local d = S.data(patient)
    if not S.hasWorkingImplant(d) or (d.degradation or 1) <= math.max(1.0, d.degradationFloor or 1) then return end
    local reasons = M.installedCalibrationReq(player, patient)
    local books = M.bookInfo(M.installedCalibrationGuide(player))
    local o = context:addOption(getText(key), player, function()
      queue(player, { label = "calibrateInstalled", time = CFG.Calibration.Time * 1.5 * (books and books.timeMult or 1), anim = "Loot",
        faceObject = patient ~= player and patient or nil,
        isValid = function() return #M.installedCalibrationReq(player, patient) == 0 end,
        onPerform = function() M.performInstalledCalibration(player, patient) end })
    end)
    tips(o, reasons, books)
  end
  addInstalledCalib(player, "IGUI_Sandevistan_CalibrateInstalled")

  -- explantación (propia con espejo, u otro jugador local)
  local function addExplant(patient, key)
    local d = S.data(patient)
    if not S.hasAnyImplant(d) then return end
    local reasons = M.explantReq(player, patient)
    local destroyed = d.variant == "destroyed"
    local chance = M.explantChance(player, destroyed)
    local books = M.explantBooks(player, destroyed)          -- (155) T06: con libros, herida leve si sale bien
    local label = getText(key) .. string.format(" (%d%%)", math.floor(chance * 100 + 0.5))
    local o = context:addOption(label, player, function()
      local text = getText(destroyed and "IGUI_Sandevistan_ExplantWarningDestroyed" or "IGUI_Sandevistan_ExplantWarning")
      confirm(player, text, function()
        queue(player, { label = "explant", time = CFG.Explant.Time * (books and books.timeMult or 1), anim = "Loot",
          faceObject = patient ~= player and patient or nil,
          isValid = function() return #M.explantReq(player, patient) == 0 end,
          onPerform = function() M.performExplant(player, patient, nil, books and true or nil) end })
      end)
    end)
    tips(o, reasons, books)
  end
  addExplant(player, "IGUI_Sandevistan_ExplantSelf")

  -- (165) T12: desconectar / reconectar el implante (solo el propio; con el implante apagado)
  local self_d = S.data(player)
  if self_d.disconnected then
    context:addOption(getText("IGUI_Sandevistan_Reconnect"), player, function() M.performReconnect(player) end)
  elseif S.hasWorkingImplant(self_d) then
    local reasons = M.disconnectReq(player)
    local o = context:addOption(getText("IGUI_Sandevistan_Disconnect"), player, function()
      confirm(player, getText("IGUI_Sandevistan_DisconnectWarn"), function()
        queue(player, { label = "disconnect", time = (CFG.Disconnect.ActionSeconds or 6) * 100, anim = "Loot",
          isValid = function() return #M.disconnectReq(player) == 0 end,
          onPerform = function() M.performDisconnect(player) end })
      end)
    end)
    tips(o, reasons, nil)
  end
  for i = 0, getNumActivePlayers() - 1 do
    local other = getSpecificPlayer(i)
    if other and other ~= player and not other:isDead() and player:DistTo(other) <= 2 then
      addExplant(other, "IGUI_Sandevistan_ExplantOther")
    end
  end
  for i = 0, getNumActivePlayers() - 1 do
    local other = getSpecificPlayer(i)
    if other and other ~= player and not other:isDead() and player:DistTo(other) <= 2 then
      addInstalledCalib(other, "IGUI_Sandevistan_CalibrateOther")
    end
  end

  -- multijugador: explantar y calibrar el implante instalado de jugadores de otros clientes (a menos de 2 tiles)
  if isClient() then
    local RS = SandevistanRemoteSurgery
    local online = getOnlinePlayers()
    for i = 0, (online and online:size() or 0) - 1 do
      local other = online:get(i)
      if other and not other:isLocalPlayer() and not other:isDead() and player:DistTo(other) <= 2 then
        local pid = other:getOnlineID()
        local chance = M.explantChance(player)
        local books = M.explantBooks(player)
        local reasons = M.explantReq(player, nil)
        local o = context:addOption(getText("IGUI_Sandevistan_ExplantOther") .. ": " .. tostring(other:getUsername())
                                    .. string.format(" (%d%%)", math.floor(chance * 100 + 0.5)), player, function()
          confirm(player, getText("IGUI_Sandevistan_ExplantWarning"), function()
            RS.requestOp(player, other, "explant", function()
              queue(player, { label = "explantRemote", time = CFG.Explant.Time * (books and books.timeMult or 1), anim = "Loot", faceObject = other,
                isValid = function() return not other:isDead() and player:DistTo(other) <= 1.8 and #M.explantReq(player, nil) == 0 end,
                onPerform = function() RS.performOp(player, pid, "explant", chance, books and true or nil) end })
            end)
          end)
        end)
        tips(o, reasons, books)
        local reasons2 = M.installedCalibrationReq(player, nil)
        local books2 = M.bookInfo(M.installedCalibrationGuide(player))
        local o2 = context:addOption(getText("IGUI_Sandevistan_CalibrateOther") .. ": " .. tostring(other:getUsername()), player, function()
          RS.requestOp(player, other, "calibrate", function()
            queue(player, { label = "calibrateRemote", time = CFG.Calibration.Time * 1.5 * (books2 and books2.timeMult or 1), anim = "Loot", faceObject = other,
              isValid = function() return not other:isDead() and player:DistTo(other) <= 1.8 and #M.installedCalibrationReq(player, nil) == 0 end,
              onPerform = function() RS.performOp(player, pid, "calibrate") end })
          end)
        end)
        tips(o2, reasons2, books2)
      end
    end
  end

  MN.addFirmwareMenu(context, player)                  -- (82) chips de firmware instalados
  local pcs = FC.computersIn(worldObjects)             -- (85) escribir un programa en una computadora (con corriente)
  if #pcs > 0 then
    MN.addWriteMenu(context, player, { kind = "pc", square = pcs[1].square, obj = pcs[1].obj })
    MN.addDecompileMenu(context, player, { kind = "pc", square = pcs[1].square, obj = pcs[1].obj })          -- (87)
  end

  if SandevistanDebug and SandevistanDebug.enabled() then SandevistanDebug.fillWorldMenu(player, context, worldObjects) end
end

-- Guia de campo: 7 paginas en una ventana (desde el item, desde el boton de la pestana Implante y desde Debug)
function MN.showGuide(player)
  local pages = {}
  for i = 1, CFG.Guide.Pages do
    pages[i] = { title = getText("IGUI_Sandevistan_Guide_Page" .. i .. "_Title"), text = getText("IGUI_Sandevistan_Guide_Page" .. i .. "_Text") }
  end
  local R = SandevistanReader
  if R and R.showPages and pcall(R.showPages, getText("IGUI_Sandevistan_Guide_Title"), pages, 600, 500, "military") then return end
  showText(player, pages[1].title, pages[1].text, nil, nil, "military")
end

MN.fillInventory = onFillInventory          -- v0.1.30 (27): el recorrido funcional arma el menu real de un item sin simular el clic derecho
Events.OnFillInventoryObjectContextMenu.Add(S.safe("ContextMenus.OnFillInventoryObjectContextMenu", onFillInventory))
Events.OnFillWorldObjectContextMenu.Add(S.safe("ContextMenus.OnFillWorldObjectContextMenu", onFillWorld))
return MN
