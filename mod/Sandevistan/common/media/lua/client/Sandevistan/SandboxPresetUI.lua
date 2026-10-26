-- Sandevistan / SandboxPresetUI: al elegir la DIFICULTAD (Sandevistan.Preset) en la pantalla de opciones de sandbox, el menu completa las demas
-- opciones del mod con los valores de ese preset (como los presets de vanilla). v0.1.30 (25).
-- v0.1.30 (29): la primera version escribia control por control y no hizo nada en el juego; ahora usa el ciclo settingsFromUI/settingsToUI de la propia pantalla.
-- Es solo un espejo visual: lo que vale en el juego lo decide SandevistanConfig.applySandbox (con un preset distinto de Custom, el preset pisa a
-- las opciones sueltas), asi que si esta pantalla cambia en una version del juego y el espejo falla, la dificultad se aplica igual; solo que el menu
-- no muestra los numeros. Todo va con pcall y el resultado queda en consola ("[Sandevistan] dificultad ...").
-- 0.7 (133): tambien en las otras dos pantallas donde se edita el sandbox: la del host (ServerSettingsScreen, pagina de edicion) y la del admin
-- dentro de la partida (ISServerSandboxOptionsUI). Antes solo se cubria la de partida nueva y en el host el menu no cambiaba.
require "Sandevistan/Config"

local CFG = SandevistanConfig

SandevistanPresetUI = {}
local PU = SandevistanPresetUI
-- (189) C12: esto es diagnóstico (queda en el REPORTE) y no ensucia la consola publicada.
local function info(msg)
  local S = rawget(_G, "Sandevistan")
  if S and S.log then S.log(msg) else print("[Sandevistan] " .. msg) end
end
PU.installed = false
PU.lastResult = nil          -- { name, ok, total } de la ultima vez que se eligio un preset

-- Pone un valor en un control del menu (tickbox o entrada de texto). Devuelve true si lo pudo poner.
local function setControl(ctl, value)
  if ctl == nil then return false end
  if type(value) == "boolean" then
    if ctl.setSelected then ctl:setSelected(1, value); return true end        -- ISTickBox
    return false
  end
  if ctl.setText then ctl:setText(tostring(value)); return true end           -- ISTextEntryBox (numeros)
  return false
end

-- Camino 1 (el bueno): el ciclo del propio juego. settingsFromUI(opciones) pasa a un objeto SandboxOptions lo que hay en pantalla, ahi se ponen los valores del
-- preset con options:set y settingsToUI(opciones) vuelve a dibujar TODOS los controles (asi no hay que conocer como esta armado cada control).
local function viaOptions(screen, preset)
  if type(screen.settingsFromUI) ~= "function" or type(screen.settingsToUI) ~= "function" then return nil, "la pantalla no tiene settingsFromUI/settingsToUI" end
  local getOpts = rawget(_G, "getSandboxOptions")
  local options = getOpts and getOpts()
  if not options then return nil, "getSandboxOptions() no devolvio opciones" end
  screen:settingsFromUI(options)
  local n = 0
  for key, value in pairs(preset) do
    local name = "Sandevistan." .. key
    local ok = pcall(options.set, options, name, value)
    if not ok then ok = pcall(options.set, options, name, tostring(value)) end
    if ok then n = n + 1 end
  end
  screen:settingsToUI(options)
  return n
end

-- Camino 2 (respaldo): escribir en los controles segun su tipo (tickbox o campo de texto).
local function viaControls(screen, preset)
  if not screen.controls then return nil, "la pantalla no tiene .controls" end
  local ok, total = 0, 0
  for key, value in pairs(preset) do
    total = total + 1
    local ctl = screen.controls["Sandevistan." .. key] or screen.controls[key]
    local done = false
    pcall(function() done = setControl(ctl, value) end)
    if done then ok = ok + 1 end
  end
  return ok
end

-- Pone los valores del preset en un objeto SandboxOptions con las mismas llamadas que usa el juego en sus pantallas (setValue / parse).
local function setAll(options, preset)
  local n = 0
  for key, value in pairs(preset) do
    local ok = pcall(function()
      local o = options:getOptionByName("Sandevistan." .. key)
      if not o then error("sin opcion") end
      if type(value) == "boolean" then o:setValue(value) else o:parse(tostring(value)) end
    end)
    if ok then n = n + 1 end
  end
  return n
end

-- Pantalla del host (pagina de edicion de ServerSettingsScreen): controles en controls.Sandbox y opciones del perfil en settings:getSandboxOptions(),
-- igual que su boton de presets de vanilla (SandboxPresetPanel:onButtonApplyPreset).
local function viaHostPage(page, preset)
  if not (page.settings and page.settingsFromUIAux and page.settingsToUIAux) then return nil, "la pagina del host no tiene settings/settingsFromUIAux" end
  local options = page.settings:getSandboxOptions()
  page:settingsFromUIAux("Sandbox", options)
  local n = setAll(options, preset)
  page:settingsToUIAux("Sandbox", options)
  return n
end

-- Panel de admin dentro de la partida: controles planos y sus propias opciones (self.options); se escriben solo cuando el admin acepta.
local function viaAdminPanel(ui, preset)
  if not (ui.settingsFromUI and ui.settingsToUI) then return nil, "el panel de admin no tiene settingsFromUI/settingsToUI" end
  local options = ui.options
  if not options then
    local SO = rawget(_G, "SandboxOptions")
    options = SO and SO.new and SO.new()
  end
  if not options then return nil, "el panel de admin no tiene opciones" end
  ui:settingsFromUI(options)
  local n = setAll(options, preset)
  ui:settingsToUI(options)
  return n
end

-- Completa las opciones de la pantalla `screen` con los valores del preset `idx` (indice del enum; 1 = Custom no hace nada).
-- kind: nil = partida nueva (SandboxOptionsScreen), "host" o "admin".
function PU.apply(screen, idx, kind)
  local name = CFG.PresetNames[idx]
  local preset = name and CFG.Presets[name]
  if not preset or not screen or PU.busy then return 0, 0 end
  PU.busy = true                                        -- settingsToUI puede volver a disparar los callbacks de los combos
  local total = 0
  for _ in pairs(preset) do total = total + 1 end
  local how, n, err = kind or "opciones", nil, nil
  local okCall, r1, r2 = pcall(kind == "host" and viaHostPage or kind == "admin" and viaAdminPanel or viaOptions, screen, preset)
  if okCall and r1 then n = r1 else err = okCall and r2 or r1 end
  if not n and kind == nil then
    how = "controles"
    local ok2, c1, c2 = pcall(viaControls, screen, preset)
    if ok2 and c1 then n = c1 else err = tostring(err) .. " / " .. tostring(ok2 and c2 or c1); n = 0 end
    -- para saber como esta armada la pantalla si ninguno de los dos caminos anduvo
    if n == 0 and type(screen.controls) == "table" then
      local shown = 0
      for k, v in pairs(screen.controls) do
        if string.find(tostring(k), "Sandevistan", 1, true) and shown < 4 then
          shown = shown + 1
          info("dificultad: control '" .. tostring(k) .. "' tipo " .. tostring(type(v) == "table" and v.Type or type(v)))
        end
      end
    end
  end
  n = n or 0
  PU.busy = false
  PU.lastResult = { name = name, ok = n, total = total, how = how, err = err }
  info(string.format("dificultad '%s': %d de %d opciones actualizadas en el menu (camino: %s)%s", name, n, total, how, err and (" | " .. tostring(err)) or ""))
  return n, total
end

local logged = 0
function PU.onCombo(screen, combo, optionName, kind)
  local n = tostring(optionName or "")
  if n ~= "Sandevistan.Preset" and not string.find(n, "Preset$") then
    if string.find(n, "Sandevistan", 1, true) and logged < 3 then logged = logged + 1; info("dificultad: combo '" .. n .. "' (no es el selector)") end
    return
  end
  local idx = combo and tonumber(combo.selected)
  if idx then PU.apply(screen, idx, kind) else info("dificultad: no pude leer el indice del combo (" .. n .. ")") end
end

-- Pantalla del host: su clase de pagina es local en ServerSettingsScreen.lua y cada combo guarda la funcion al crearse, asi que se envuelve
-- el onChange del combo de la dificultad en la pagina ya creada (una sola vez por combo).
function PU.hookHost(screen)
  local page = screen and screen.pageEdit
  local controls = page and type(page.controls) == "table" and page.controls.Sandbox
  local combo = type(controls) == "table" and controls["Sandevistan.Preset"]
  if not combo or combo.sandevistanPreset or type(combo.onChange) ~= "function" then return combo ~= nil and combo.sandevistanPreset == true end
  local orig = combo.onChange
  combo.onChange = function(target, cb, ...)
    local r = orig(target, cb, ...)
    pcall(PU.onCombo, page, cb, "Sandevistan.Preset", "host")
    return r
  end
  combo.sandevistanPreset = true
  return true
end

local function wrapMethod(C, method, after)
  local orig = C[method]
  C[method] = function(self, ...)
    local r = orig(self, ...)
    pcall(after, self, ...)
    return r
  end
end

-- Envuelve las tres pantallas (las define el juego; se reintenta al entrar al menu principal).
function PU.install()
  local C = rawget(_G, "SandboxOptionsScreen")
  if not PU.installed and type(C) == "table" and type(C.onComboBoxSelected) == "function" then
    wrapMethod(C, "onComboBoxSelected", function(self, combo, optionName) PU.onCombo(self, combo, optionName) end)
    PU.installed = true
  end
  local H = rawget(_G, "ServerSettingsScreen")
  if not PU.hostInstalled and type(H) == "table" and type(H.create) == "function" and type(H.aboutToShow) == "function" then
    wrapMethod(H, "create", PU.hookHost)
    wrapMethod(H, "aboutToShow", PU.hookHost)
    PU.hostInstalled = true
  end
  if H and H.instance then pcall(PU.hookHost, H.instance) end
  local U = rawget(_G, "ISServerSandboxOptionsUI")
  if not PU.adminInstalled and type(U) == "table" and type(U.onComboBoxSelected) == "function" then
    wrapMethod(U, "onComboBoxSelected", function(self, combo, optionName) PU.onCombo(self, combo, optionName, "admin") end)
    PU.adminInstalled = true
  end
  return PU.installed
end

PU.install()
if Events and Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function() PU.install() end) end
if Events and Events.OnGameStart then Events.OnGameStart.Add(function() PU.install() end) end

return PU
