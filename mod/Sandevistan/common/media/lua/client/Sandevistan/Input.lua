-- Sandevistan / Input: máquina de estados de la tecla (01 §3, 03 §8).
-- Tap activa/desactiva. Hold ≥ 0.3 s arma el override. Con cyberpsicosis:
-- doble toque + hold para armar, y el tap de desactivar tiene 0.4 s de retraso.
require "Sandevistan/Core"
require "Sandevistan/Runtime"

local CFG = SandevistanConfig
local S = Sandevistan
local R = SandevistanRuntime
local FW = SandevistanFirmware

SandevistanInput = {}
local I = SandevistanInput

-- Opciones de mod (PZAPI.ModOptions, B42)
I.options = nil
local function setupOptions()
  if I.options or not PZAPI or not PZAPI.ModOptions then return end
  local ok, opts = pcall(function() return PZAPI.ModOptions:create("Sandevistan", "Sandevistan") end)
  if not ok or not opts then S.warnOnce("modoptions", "PZAPI.ModOptions no disponible"); return end
  opts:addKeyBind("activate", getText("UI_Sandevistan_Opt_Key"), CFG.Input.DefaultKey)
  pcall(function() opts:addKeyBind("togglePanel", getText("UI_Sandevistan_Opt_TogglePanel"), 0) end)   -- sin asignar
  opts:addSlider("hudScale", getText("UI_Sandevistan_Opt_HudScale"), 1.0, 1.6, 0.1, 1.0)
  opts:addTickBox("screenGlitches", getText("UI_Sandevistan_Opt_Glitches"), true)
  -- (170) C01: menos destellos (fotosensibilidad, 29 §7.1). Lo lee S.lessFlashes().
  opts:addTickBox("lessFlashes", getText("UI_Sandevistan_Opt_LessFlashes"), false, getText("UI_Sandevistan_Opt_LessFlashes_tooltip"))
  opts:addTickBox("hudMoodles", getText("UI_Sandevistan_Opt_HudMoodles"), false)
  opts:addTickBox("installScene", getText("UI_Sandevistan_Opt_InstallScene"), true)
  opts:addTickBox("neuralMonitor", getText("UI_Sandevistan_Opt_NeuralMonitor"), true)
  opts:addTickBox("threatVision", getText("UI_Sandevistan_Opt_ThreatVision"), true)
  opts:addTickBox("spineModel3D", getText("UI_Sandevistan_Opt_SpineModel"), true)
  opts:addTickBox("afterimages", getText("UI_Sandevistan_Opt_Afterimages"), true)
  opts:addTickBox("afterimagesRainbow", getText("UI_Sandevistan_Opt_AfterimagesRainbow"), false)
  opts:addTickBox("slowZombieVoices", getText("UI_Sandevistan_Opt_SlowZombieVoices"), true)     -- (126) SlowAudio.lua
  opts:addTickBox("viewportAuto", getText("UI_Sandevistan_Opt_ViewportAuto"), true)
  opts:addTickBox("debugMenu", getText("UI_Sandevistan_Opt_Debug"), false)
  -- (189) C12: la consola publicada solo muestra avisos y errores; el resto queda detrás de esta opción (o de -debug).
  opts:addTickBox("verboseLog", getText("UI_Sandevistan_Opt_VerboseLog"), false, getText("UI_Sandevistan_Opt_VerboseLog_tooltip"))
  -- (189) C12: las pruebas internas del menú de debug (rendimiento, recorridos, sondas) detrás de esta opción.
  opts:addTickBox("debugFull", getText("UI_Sandevistan_Opt_DebugFull"), false, getText("UI_Sandevistan_Opt_DebugFull_tooltip"))
  I.options = opts
end
setupOptions()

function I.getOption(id, default)
  if not I.options then return default end
  local ok, v = pcall(function() return I.options:getOption(id):getValue() end)
  if ok and v ~= nil then return v end
  return default
end

function I.key() return I.getOption("activate", CFG.Input.DefaultKey) end

-- Estado del input (solo jugador 0 con teclado en v0.1)
I.state = "IDLE"
I.pressStartMs = 0
I.pendingSinceMs = 0
I.held = false          -- la tecla está físicamente abajo (flanco de subida ya procesado)
I.lastKeepMs = -1000    -- último OnKeyKeepPressed (respaldo si isKeyDown no responde)

local function player0() return getSpecificPlayer(0) end

local function resetIfInactive(p)
  -- (163) FORCING y PENDING_FORCE viven con el implante apagado: no se resetean
  if not R.isActive(p) and I.state ~= "IDLE" and I.state ~= "FORCING" and I.state ~= "PENDING_FORCE" then I.state = "IDLE" end
end

-- (163) T11: aviso de "mantené para forzar" (rojo) y enganche al HUD.
local function forceNotice(p, flags)
  local E = rawget(_G, "SandevistanEffects")
  local key = (flags and flags.heat) and "IGUI_Sandevistan_ForceHoldHeat" or "IGUI_Sandevistan_ForceHoldAir"
  if E then E.halo(p, getText(key), 255, 120, 60) end
  if SandevistanHUD then SandevistanHUD.flash("forcing") end
end

-- Estado físico de la tecla. Se consulta isKeyDown y no el evento OnKeyPressed: en B42 ese
-- evento no marca de forma fiable cuándo se suelta la tecla, y un tap se leía como "mantener".
-- Si isKeyDown no responde, se usa el latido de OnKeyKeepPressed.
local function keyIsDown()
  local ok, v = pcall(isKeyDown, I.key())
  if ok and v then return true end
  -- respaldo (~2 frames): OnKeyKeepPressed se dispara cada frame mientras la tecla está abajo
  return S.realMs() - I.lastKeepMs < 40
end

-- Reglas (v0.1.6):
--   Inactivo + pulsar: activa. Si se mantiene 0.3 s, además arma el override.
--   Activo + tap: corte manual.  Activo + mantener 0.3 s: arma el override.
--   El armado queda enganchado: se puede soltar la tecla y moverse con normalidad.
--   Armado + pulsar: corte manual (o, en Overdrive, termina y colapsa).
--   Con el Heat en 100 y armado, el Overdrive dura su ventana y colapsa solo.
--   Cyberpsicosis: para armar, doble toque + mantener; el tap simple corta con 0.4 s de retraso.
local function handlePress(p)
  local d = S.data(p)
  if not S.hasAnyImplant(d) then return end
  resetIfInactive(p)
  local now = S.realMs()
  local s = R.session(p)
  if s.fury then return end                          -- furia total (sobrecarga neural): el implante está trabado
  I.pressStartMs = now
  if I.state == "IDLE" then
    -- (163) T11: si lo que frena es el aire o el calor, mantener fuerza; si no, el encendido de siempre (con su aviso de error)
    local fok, flags, freason = false, nil, nil
    if R.canForce then fok, flags, freason = R.canForce(p) end
    if not fok and freason and (freason == "IGUI_Sandevistan_Err_ForceAir" or freason == "IGUI_Sandevistan_Err_ForceHeat") then
      -- (163) bloqueado para forzar: el motivo del bloqueo es más útil que el error genérico de la resistencia
      local E = rawget(_G, "SandevistanEffects")
      if E then E.halo(p, getText(freason), 255, 120, 60) end
    elseif fok then
      if d.cyberpsychosisActive then          -- con cyberpsicosis: doble toque y mantener, como para armar
        I.state = "PENDING_FORCE"
        I.pendingSinceMs = now
        I.pendingFlags = flags
      else
        I.state = "FORCING"
        I.forceFlags = flags
        forceNotice(p, flags)
      end
    elseif R.activate(p) then
      I.state = "ACTIVATING"
    end
  elseif I.state == "PENDING_FORCE" then
    if now - I.pendingSinceMs <= CFG.Input.DoubleTapWindowSeconds * 1000 then
      I.state = "FORCING"
      I.forceFlags = I.pendingFlags
      I.pendingFlags = nil
      forceNotice(p, I.forceFlags)
    end
  elseif I.state == "ARMED" then
    if s.overdrive then R.collapse(p) else R.deactivate(p, "manual") end
    I.state = "IDLE"
  elseif I.state == "ACTIVE" then
    if d.cyberpsychosisActive then
      I.state = "PENDING_TAP"
      I.pendingSinceMs = now
    else
      I.state = "ARMING"
    end
  elseif I.state == "PENDING_TAP" then
    if now - I.pendingSinceMs <= CFG.Input.DoubleTapWindowSeconds * 1000 then
      I.state = "ARMING"
    end
  end
end

-- Solo arma si la tecla sigue abajo desde hace HoldToArmSeconds.
local function checkArm(p)
  if I.held and (I.state == "ARMING" or I.state == "ACTIVATING")
     and S.realMs() - I.pressStartMs >= CFG.Input.HoldToArmSeconds * 1000 then
    if FW.profile(S.data(p)).noOverdrive then              -- (83) Overclock y Taller: el firmware no deja armar el Overdrive; sigue encendido normal
      I.state = "ACTIVE"
      local E = rawget(_G, "SandevistanEffects")
      if E then E.halo(p, getText("IGUI_Sandevistan_Fw_NoOverdrive"), 255, 200, 80) end
      return
    end
    R.session(p).armed = true
    I.state = "ARMED"
    if SandevistanHUD then SandevistanHUD.flash("armed") end
  end
end

local function handleRelease(p)
  if I.state == "ACTIVATING" then
    I.state = "ACTIVE"
  elseif I.state == "FORCING" then
    I.state = "IDLE"                    -- (163) soltaste antes de tiempo: no pasa nada
    I.forceFlags = nil
  elseif I.state == "ARMING" then
    local d = S.data(p)
    if d.cyberpsychosisActive then
      I.state = "ACTIVE"             -- doble toque sin mantener: no hace nada
    else
      R.deactivate(p, "manual"); I.state = "IDLE"
    end
  end
end

local function press(key)
  if key ~= I.key() then return end
  if I.held then return end          -- el mismo pulso ya se procesó (evento repetido)
  local p = player0()
  if not p or p:isDead() then return end
  if p:getVehicle() then return end -- en el coche la Z es cambiar de asiento y el implante no se usa: sin aviso
  I.held = true
  handlePress(p)
end

local function onHold(key)
  if key ~= I.key() then return end
  I.lastKeepMs = S.realMs()
  local p = player0()
  if p and I.held then checkArm(p) end
end

-- Cada tick: detecta el flanco de bajada (soltar), el flanco de subida perdido y resuelve
-- el tap simple en cyberpsicosis (corte con 0.4 s de retraso).
local function onTick()
  local p = player0()
  if not p then return end
  resetIfInactive(p)
  local down = keyIsDown()
  -- 60 ms de gracia tras pulsar: la tecla tarda un frame en reportarse abajo
  if not down and I.held and S.realMs() - I.pressStartMs > 60 then
    I.held = false
    handleRelease(p)
  end
  checkArm(p)
  if I.state == "PENDING_TAP" and S.realMs() - I.pendingSinceMs > CFG.Input.DoubleTapWindowSeconds * 1000 then
    R.deactivate(p, "manual")
    I.state = "IDLE"
  end
  -- (163) T11: mantener 0.8 s fuerza el implante y entra en Overdrive
  if I.state == "FORCING" then
    if not I.held then
      I.state = "IDLE"; I.forceFlags = nil
    elseif S.realMs() - I.pressStartMs >= (CFG.Force and CFG.Force.HoldSeconds or 0.8) * 1000 then
      local fok, flags, freason = false, nil, nil
      if R.canForce then fok, flags, freason = R.canForce(p) end
      if fok and R.force(p, flags) then
        I.state = "ARMED"
      else
        I.state = "IDLE"
        if freason and (freason == "IGUI_Sandevistan_Err_ForceAir" or freason == "IGUI_Sandevistan_Err_ForceHeat") then
          local E = rawget(_G, "SandevistanEffects")
          if E then E.halo(p, getText(freason), 255, 120, 60) end
        end
      end
      I.forceFlags = nil
    end
  elseif I.state == "PENDING_FORCE" and S.realMs() - I.pendingSinceMs > CFG.Input.DoubleTapWindowSeconds * 1000 then
    I.state = "IDLE"; I.pendingFlags = nil
  end
end

-- Tecla opcional (sin asignar por defecto) para mostrar u ocultar el panel flotante.
local function pressTogglePanel(key)
  local tk = I.getOption("togglePanel", 0)
  if not tk or tk == 0 or key ~= tk then return end
  if SandevistanHUD and SandevistanHUD.toggleFloating then SandevistanHUD.toggleFloating(player0()) end
end

Events.OnKeyStartPressed.Add(S.safe("Input.OnKeyStartPressed", press))
Events.OnKeyStartPressed.Add(S.safe("Input.TogglePanel", pressTogglePanel))
Events.OnKeyKeepPressed.Add(S.safe("Input.OnKeyKeepPressed", onHold))
Events.OnTick.Add(S.safe("Input.OnTick", onTick))
return I
