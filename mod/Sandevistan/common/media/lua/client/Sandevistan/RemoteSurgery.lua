-- Sandevistan / RemoteSurgery: cirugía de implante sobre otro jugador en multijugador.
-- Flujo (todo pasa por el servidor, ver server/Sandevistan/Net.lua):
--   1. Cirujano elige "Operar a <jugador>" -> surgeryRequest.
--   2. El paciente ve un aviso: si acepta y puede recibir el implante -> surgeryAnswer(ok).
--   3. Cirujano hace la acción temporizada; al terminar tira el resultado -> surgeryApply.
--   4. El cliente del paciente aplica el implante (o el corte) sobre su propio estado y
--      responde surgeryDone(ok). Solo entonces el cirujano pierde el implante.
-- El paciente nunca recibe un implante sin haber aceptado esa operación (ventana de 2 min).
require "Sandevistan/Core"
require "Sandevistan/Medical"
require "Sandevistan/Net"
require "Sandevistan/Dialog"
require "Sandevistan/TimedActions/SandevistanAction"

local CFG = SandevistanConfig
local S = Sandevistan
local M = SandevistanMedical
local E = SandevistanEffects
local N = SandevistanNet

SandevistanRemoteSurgery = {}
local RS = SandevistanRemoteSurgery

local MODULE = "Sandevistan"
local CONSENT_MS = 120000
local ANSWER_TIMEOUT_MS = 30000

RS.asking = nil       -- cirujano: { patientId, implant, option, sinceMs }
RS.applying = nil     -- cirujano: { patientId, implant, ok, sinceMs } esperando surgeryDone
RS.consent = {}       -- paciente: [cirujanoId] = vence (ms)

local function say(player, key, ...) E.halo(player, getText(key, ...), 255, 220, 120) end

local function send(player, command, args) sendClientCommand(player, MODULE, command, args) end

local function onlineId(p)
  local id = nil
  pcall(function() id = p:getOnlineID() end)
  return id
end

---------------------------------------------------------------------------
-- Cirujano
---------------------------------------------------------------------------
-- Pide permiso al paciente. onAccepted() arranca la operación cuando acepta.
function RS.request(surgeon, patient, implant, option, onAccepted)
  RS.asking = { patientId = onlineId(patient), implant = implant, option = option,
                sinceMs = S.realMs(), onAccepted = onAccepted, surgeon = surgeon, name = patient:getUsername() }
  send(surgeon, "surgeryRequest", { target = RS.asking.patientId })
  say(surgeon, "IGUI_Sandevistan_RemoteWait", RS.asking.name)
end

-- Al terminar la acción temporizada del cirujano.
function RS.perform(surgeon, patientId, implant, option)
  local variant = M.implantVariant(implant)
  if not variant then return end
  M.consumeSuture(surgeon)                                         -- (194) aguja de sutura o aguja e hilo
  M.consumeFirstOf(surgeon, M.DISINFECT, 1)
  local ok = S.chance(option.chance)
  local deg, floor = M.itemDegradation(implant)
  send(surgeon, "surgeryApply", { target = patientId, ok = ok, variant = variant, deg = deg, floor = floor,
                                  proto = M.itemPrototype(implant), plate = M.itemPlate(implant), sloppy = option.sloppy and true or nil })
  RS.applying = { patientId = patientId, implant = implant, ok = ok, sinceMs = S.realMs(), surgeon = surgeon }
end

local function onAnswered(args)
  local a = RS.asking
  if not a or args.from ~= a.patientId then return end
  RS.asking = nil
  if args.ok then
    a.onAccepted()
  else
    say(a.surgeon, "IGUI_Sandevistan_RemoteDenied", a.name)
  end
end

local function onDone(args)
  local a = RS.applying
  if not a or args.from ~= a.patientId then return end
  RS.applying = nil
  if not args.ok then
    say(a.surgeon, "IGUI_Sandevistan_RemoteBlocked")
    return
  end
  if a.ok then
    local c = a.implant:getContainer()
    if c then
      c:DoRemoveItem(a.implant)                          -- ya está en el paciente
      if isClient() then pcall(sendRemoveItemFromContainer, c, a.implant) end   -- (115) MP: si no, el servidor lo seguia teniendo (duplicado al reconectar)
    end
    E.halo(a.surgeon, getText("IGUI_Sandevistan_SurgeryOK"), 80, 220, 255)
  else
    M.degradeAfterFailure(a.implant)
    E.halo(a.surgeon, getText("IGUI_Sandevistan_SurgeryFail"), 255, 120, 60)
  end
end

---------------------------------------------------------------------------
-- Paciente
---------------------------------------------------------------------------
local function localPlayer() return getSpecificPlayer(0) end

local function onAsk(args)
  local me = localPlayer()
  if not me or me:isDead() then return end
  local from = args.from
  if not M.canReceiveImplant(me) then
    send(me, "surgeryAnswer", { target = from, ok = false })
    return
  end
  local text = getText("IGUI_Sandevistan_RemoteAsk", tostring(args.name)) .. " <LINE> <LINE> "
    .. getText("IGUI_Sandevistan_SurgeryWarning")
  local w, h = 480, 240
  local x = (getCore():getScreenWidth() - w) / 2
  local y = (getCore():getScreenHeight() - h) / 2
  SandevistanDialog.yesNo(me:getPlayerNum(), text, w, h, function(yes)
    if yes then RS.consent[from] = S.realMs() + CONSENT_MS end
    send(me, "surgeryAnswer", { target = from, ok = yes })
  end)
end

local function onApply(args)
  local me = localPlayer()
  if not me or me:isDead() then return end
  local from = args.from
  local until_ = RS.consent[from]
  RS.consent[from] = nil
  local allowed = until_ and until_ > S.realMs() and M.canReceiveImplant(me)
    and (args.variant == "lab" or args.variant == "military")
  if not allowed then
    send(me, "surgeryDone", { target = from, ok = false })
    return
  end
  if args.ok then
    M.applyImplant(me, args.variant, tonumber(args.deg) or 1, tonumber(args.floor) or 1, args.proto, args.plate)
    if args.sloppy then M.applySloppyWound(me) end
  else
    M.applyFailedCut(me)
  end
  local N = rawget(_G, "SandevistanNet")          -- (190) MP: que el servidor guarde el implante del paciente ya
  if N and N.saveState then pcall(N.saveState, me) end
  send(me, "surgeryDone", { target = from, ok = true })
end

---------------------------------------------------------------------------
-- v0.1.26: explantar / calibrar el implante instalado de otro jugador (mismo esquema: consentimiento -> acción del
-- cirujano -> el cliente del paciente aplica su parte y responde; el implante retirado pasa al cirujano).
---------------------------------------------------------------------------
RS.opAsking = nil        -- cirujano: { patientId, op, onAccepted, sinceMs, surgeon, name }
RS.opApplying = nil      -- cirujano: { patientId, op, sinceMs, surgeon }
RS.opConsent = {}        -- paciente: [cirujanoId .. op] = vence (ms)
RS.calibWear = {}        -- (122) cirujano: [pacienteId] = desgaste que informo el paciente al aceptar una calibracion

function RS.requestOp(surgeon, patient, op, onAccepted)
  RS.opAsking = { patientId = onlineId(patient), op = op, onAccepted = onAccepted, sinceMs = S.realMs(),
                  surgeon = surgeon, name = patient:getUsername() }
  send(surgeon, "opRequest", { target = RS.opAsking.patientId, op = op })
  say(surgeon, "IGUI_Sandevistan_RemoteWait", RS.opAsking.name)
end

-- Al terminar la acción temporizada del cirujano. "chance" solo importa en la explantación; "sloppy" (155) = guiada con libros.
function RS.performOp(surgeon, patientId, op, chance, sloppy)
  M.consumeFirstOf(surgeon, M.DISINFECT, 1)
  local success = true
  if op == "explant" then
    success = S.chance(chance or 0)                                -- (194) el explante ya no gasta aguja de sutura
  else
    M.consume(surgeon, CFG.Crafting.Items.ElectronicsScrap, M.calibrationScrap(RS.calibWear[patientId]))   -- (122) segun el desgaste del paciente
    RS.calibWear[patientId] = nil
    -- (155) T06: guiada con libros puede fallar (la chatarra ya se gastó; el desgaste del paciente queda igual)
    local bg = M.installedCalibrationGuide(surgeon)
    success = not (bg.ok and bg.gap > 0 and S.chance(SandevistanBookGuide.failChance(bg.gap)))
  end
  send(surgeon, "opApply", { target = patientId, op = op, success = success, sloppy = sloppy and true or nil })
  RS.opApplying = { patientId = patientId, op = op, sinceMs = S.realMs(), surgeon = surgeon }
end

local function onOpAnswered(args)
  local a = RS.opAsking
  if not a or args.from ~= a.patientId or args.op ~= a.op then return end
  RS.opAsking = nil
  if not args.ok then say(a.surgeon, "IGUI_Sandevistan_RemoteDenied", a.name) return end
  if a.op == "calibrate" then                                                  -- (122) la chatarra depende del desgaste del paciente
    local need = M.calibrationScrap(args.wear)
    if M.count(a.surgeon, CFG.Crafting.Items.ElectronicsScrap) < need then
      E.halo(a.surgeon, getText("IGUI_Sandevistan_Req_Scrap", need), 255, 160, 60)
      return
    end
    RS.calibWear[a.patientId] = tonumber(args.wear) or 0
  end
  a.onAccepted()
end

local function onOpDone(args)
  local a = RS.opApplying
  if not a or args.from ~= a.patientId or args.op ~= a.op then return end
  RS.opApplying = nil
  if not args.ok then say(a.surgeon, "IGUI_Sandevistan_RemoteBlocked") return end
  if a.op == "explant" then
    if args.done and args.variant then
      M.explantGive(a.surgeon, { variant = args.variant, deg = tonumber(args.deg) or 1, floor = tonumber(args.floor) or 1, proto = args.proto, plate = S.cleanPlate(args.plate) })
      E.halo(a.surgeon, getText("IGUI_Sandevistan_ExplantOK"), 80, 220, 255)
    else
      E.halo(a.surgeon, getText("IGUI_Sandevistan_ExplantFail"), 255, 120, 60)
    end
  elseif args.done then
    E.halo(a.surgeon, getText("IGUI_Sandevistan_Calibrated"), 80, 220, 255)
  else
    E.halo(a.surgeon, getText("IGUI_Sandevistan_CalibFailBook"), 255, 120, 60)
  end
end

local function onOpAsk(args)
  local me = localPlayer()
  if not me or me:isDead() then return end
  local from, op = args.from, args.op
  local d = S.data(me)
  local valid = (op == "explant" and S.hasAnyImplant(d)) or (op == "calibrate" and S.hasWorkingImplant(d))
  if not valid then send(me, "opAnswer", { target = from, op = op, ok = false }) return end
  local text = getText(op == "explant" and "IGUI_Sandevistan_RemoteAskExplant" or "IGUI_Sandevistan_RemoteAskCalibrate", tostring(args.name))
  local w, h = 480, 200
  local x = (getCore():getScreenWidth() - w) / 2
  local y = (getCore():getScreenHeight() - h) / 2
  SandevistanDialog.yesNo(me:getPlayerNum(), text, w, h, function(yes)
    if yes then RS.opConsent[from .. op] = S.realMs() + CONSENT_MS end
    send(me, "opAnswer", { target = from, op = op, ok = yes, wear = op == "calibrate" and M.installedWear(d) or nil })
  end)
end

local function onOpApply(args)
  local me = localPlayer()
  if not me or me:isDead() then return end
  local from, op = args.from, args.op
  local key = tostring(from) .. tostring(op)
  local until_ = RS.opConsent[key]
  RS.opConsent[key] = nil
  local d = S.data(me)
  local allowed = until_ and until_ > S.realMs()
    and ((op == "explant" and S.hasAnyImplant(d)) or (op == "calibrate" and S.hasWorkingImplant(d)))
  if not allowed then send(me, "opDone", { target = from, op = op, ok = false }) return end
  if op == "explant" then
    M.explantWound(me)
    if args.success then
      if args.sloppy then M.applySloppyWound(me) end        -- (155) T06: la herida leve viaja con la operación remota
      local snap = M.explantPatientPart(me)
      send(me, "opDone", { target = from, op = op, ok = true, done = true, variant = snap.variant, deg = snap.deg,
                           floor = snap.floor, proto = snap.proto, plate = snap.plate })
    else
      M.explantScene(me, { kind = "explant", ok = false })
      send(me, "opDone", { target = from, op = op, ok = true, done = false })
    end
  else
    M.installedCalibrationResult(me, args.success)             -- (155) T06: con libros puede fallar
    send(me, "opDone", { target = from, op = op, ok = true, done = args.success and true or false })
  end
end

---------------------------------------------------------------------------
if N then
  N.handlers.opAnswered = S.safe("RS.onOpAnswered", onOpAnswered)
  N.handlers.opDoneIn = S.safe("RS.onOpDone", onOpDone)
  N.handlers.opAsk = S.safe("RS.onOpAsk", onOpAsk)
  N.handlers.opApplyIn = S.safe("RS.onOpApply", onOpApply)
end
if N then
  N.handlers.surgeryAnswered = S.safe("RS.onAnswered", onAnswered)
  N.handlers.surgeryDoneIn = S.safe("RS.onDone", onDone)
  N.handlers.surgeryAsk = S.safe("RS.onAsk", onAsk)
  N.handlers.surgeryApplyIn = S.safe("RS.onApply", onApply)
end

-- Caducidad de la petición sin respuesta
Events.OnTick.Add(S.safe("RS.OnTick", function()
  local a = RS.asking
  if a and S.realMs() - a.sinceMs > ANSWER_TIMEOUT_MS then
    RS.asking = nil
    say(a.surgeon, "IGUI_Sandevistan_RemoteTimeout", a.name)
  end
  local b = RS.applying
  if b and S.realMs() - b.sinceMs > ANSWER_TIMEOUT_MS then RS.applying = nil end
  local oa = RS.opAsking
  if oa and S.realMs() - oa.sinceMs > ANSWER_TIMEOUT_MS then RS.opAsking = nil; say(oa.surgeon, "IGUI_Sandevistan_RemoteTimeout", oa.name) end
  local ob = RS.opApplying
  if ob and S.realMs() - ob.sinceMs > ANSWER_TIMEOUT_MS then RS.opApplying = nil end
end))

return RS
