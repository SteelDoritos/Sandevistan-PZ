-- Sandevistan / HUD: elemento de interfaz arrastrable. Construye el modelo del panel (HUDPanel.lua lo
-- dibuja) y dibuja además todo lo que va sobre el mundo: overlay de pantalla (tinte al activar, viñeta
-- de calor, glitches), estelas, implante en la espalda, cyberpsicosis (Psychosis.lua) y marcadores de ex-sujetos.
-- Desde v0.1.25 los moodles (Moodles.lua, vía Moodle Framework) son el indicador de estado y el panel flotante
-- queda oculto mientras funcionan; se muestra solo si los moodles no están disponibles o si el jugador lo
-- activa (pestaña "Implante" de la ventana de información, tecla opcional o menú Debug). El overlay de pantalla
-- se dibuja siempre, con o sin panel. Los estados tipo moodle se listan en el panel solo si MF no los muestra.
require "ISUI/ISUIElement"
require "Sandevistan/Core"
require "Sandevistan/Kerenzikov"
require "Sandevistan/Runtime"
require "Sandevistan/Afterimages"
require "Sandevistan/Viewport"
require "Sandevistan/Moodles"
require "Sandevistan/Psychosis"
require "Sandevistan/Spine"
require "Sandevistan/InstallScene"
require "Sandevistan/Firearms"
require "Sandevistan/SkillTooltip"
require "Sandevistan/HUDPanel"

local CFG = SandevistanConfig
local S = Sandevistan
local R = SandevistanRuntime

SandevistanHUD = ISUIElement:derive("SandevistanHUD")
local H = SandevistanHUD

local W0 = SandevistanHUDPanel.COMPACT_W

H.instance = nil
H.flashKind, H.flashUntil = nil, 0
H.glitchUntil, H.glitchLastMs = 0, 0
H.glitchStrips = {}

-- Glitch de pantalla/HUD por Carga Neuronal alta (v0.1.15). Devuelve true mientras dura.
function H.updateGlitch(d)
  if d.disconnected then return false end                                   -- (165) T12: el glitch es del implante
  local now = S.realMs()
  local dt = math.min(0.25, (now - (H.glitchLastMs or now)) / 1000)
  H.glitchLastMs = now
  if SandevistanInput and not SandevistanInput.getOption("screenGlitches", true) then return false end
  if now < H.glitchUntil then return true end
  local calm = S.lessFlashes()
  if calm and now - (H.glitchUntil or 0) < (CFG.LessFlashes.GlitchGapMs or 1000) then return false end   -- (170) C01: como mucho uno por segundo
  local rate = S.glitchRate(d)
  local PS = rawget(_G, "SandevistanPsychosis")
  if PS and PS.freqMult and PS.state[0] then                                -- (176) presión (jugador 0); (177) y la disociación
    rate = rate * (PS.state[0].pressureMult or 1)
    local CR = rawget(_G, "SandevistanCrisis")
    if CR then rate = rate * CR.mult(PS.state[0], "ScreenGlitch") end
  end
  if rate > 0 and dt > 0 and S.chance(rate * dt) then
    local g = CFG.NeuralLoad.Glitch
    H.glitchUntil = now + S.randRange(g.DurationMs[1], g.DurationMs[2]) * (calm and 2 or 1)
    H.glitchStrips = {}
    local n = calm and 0 or (3 + ZombRand(5))                                   -- (170) menos destellos: sin tiras
    for i = 1, n do
      H.glitchStrips[i] = { y = ZombRandFloat(0, 1), h = 2 + ZombRand(14), dx = ZombRand(81) - 40,
                            a = ZombRandFloat(0.12, 0.35), c = ZombRand(3) }
    end
    H.glitchDX = calm and 0 or (ZombRand(13) - 6)
    H.wiggleMoodles()
    return true
  end
  return false
end

-- (148/149) Moodles con el glitch (27 §12). Al empezar cada glitch:
--  * los moodles vanilla se rompen como el panel (separacion de color, temblor, desgarro) y se sacuden: eso lo hace el jar de SandevistanPsychosis
--    (MoodleGlitch), porque a los vanilla los dibuja Java y Moodles:wiggle no esta expuesto a Lua (la 148 lo llamaba y daba "tried to call nil"
--    en cada glitch). Sin el jar, los vanilla quedan como estan.
--  * los de Moodle Framework (los del mod y los de otros mods que lo usan) se sacuden con su propio doWiggle y, mientras dura el
--    glitch, se dibujan rotos como el panel (H.hookMoodleRender).
-- Nada de esto puede tirar errores: el depurador con "Break On Error" se detiene aunque haya pcall, asi que se pregunta antes de llamar.
function H.wiggleMoodles()
  H.hookMoodleRender()
  if S.lessFlashes() then return end                       -- (170) C01: sin sacudidas ni copias de color en los moodles
  local B = rawget(_G, "SandevistanPsyBridge")
  if B and B.moodleGlitch then B.moodleGlitch(1, math.max(0, H.glitchUntil - S.realMs())) end
  local mf = rawget(_G, "MF")
  local store = type(mf) == "table" and mf.MoodlesStorage or nil
  if type(store) ~= "table" then return end
  for idx = 0, getNumActivePlayers() - 1 do
    for _, byPlayer in pairs(store) do
      local m = type(byPlayer) == "table" and byPlayer[idx] or nil
      if type(m) == "table" and type(m.doWiggle) == "function" and type(m.getGoodBadNeutral) == "function" and m:getGoodBadNeutral() ~= 0 then
        m:doWiggle()
      end
    end
  end
end

-- Los moodles de Moodle Framework son elementos de Lua: su render() se envuelve una sola vez (a nivel de clase) para que, con el
-- glitch encendido, dibuje a traves de H.glitchUI. Si algo falla, el moodle se dibuja normal.
function H.hookMoodleRender()
  if H.mfHooked then return true end
  local mf = rawget(_G, "MF")
  local cls = mf and mf.ISMoodle
  if not (cls and type(cls.render) == "function") then return false end
  local orig = cls.render
  cls.render = function(self, ...)
    if not (H.glitching and pcall(orig, H.glitchUI(self), ...)) then orig(self, ...) end
    H.blackoutMoodle(self)
  end
  H.mfHooked = true
  return true
end

-- (182) El negro del apagon lo dibuja el HUD del mod, que queda encima de los moodles vanilla pero debajo de los de Moodle Framework: los
-- nuestros seguian viendose. Encima de cada uno va el mismo negro, con el mismo nivel. (183) Y el tunel (los anillos que oscurecen el borde),
-- recortado al moodle: en la 182 los vanilla se oscurecian con el tunel y los nuestros no.
function H.blackoutMoodle(m)
  local PS = rawget(_G, "SandevistanPsychosis")
  if not (PS and PS.drawBlackoutClip) then return end
  local player = getSpecificPlayer(tonumber(m.playerNum) or 0)
  if not player then return end
  local vig, black = PS.blackoutLevels(player)
  if vig <= 0 and black <= 0 then return end                 -- casi siempre: sin apagon no se arma nada
  PS.drawBlackoutClip(m, player, { m:getAbsoluteX(), m:getAbsoluteY(), m:getWidth(), m:getHeight() })
end

-- (142) Glitch del panel propio (27 §12): mientras dura el glitch de pantalla, los iconos y los numeros del panel se dibujan
-- corridos y con la separacion de color cian/magenta, como una imagen que se rompe. Solo afecta a lo que dibuja el mod (los iconos
-- de vanilla van por Java, 27 §12 aparte). Devuelve un "ui" de reemplazo: todo lo que no se toca se delega al original.
function H.glitchUI(ui)
  local calm = S.lessFlashes()                             -- (170) C01: menos destellos = separacion de color quieta, sin temblor ni desgarro
  local jx = calm and 0 or (ZombRand(5) - 2)
  local jy = calm and 0 or (ZombRand(3) - 1)
  -- (146) la separacion de color va siempre (antes solo si el temblor no daba 0) y con un ancho distinto en cada cuadro
  local sp = calm and 1 or (1 + ZombRand(3))
  local proxy = setmetatable({}, { __index = function(t, k)
    local v = ui[k]
    if type(v) == "function" then
      local f = function(_, ...) return v(ui, ...) end
      rawset(t, k, f)                                    -- (146) un envoltorio por metodo y por cuadro, no uno por llamada
      return f
    end
    return v
  end,
  -- (148) lo que el dibujo escribe en self (el temblor y la posicion de los moodles de MF) va al original, no se pierde con el proxy
  __newindex = function(_, k, v) ui[k] = v end })
  -- (146) desgarro: a veces el icono se dibuja en tres tiras horizontales corridas a los costados (DrawSubTextureRGBA: recorte de la
  -- textura en pixeles y destino relativo al panel, como el resto del dibujo). Si no se puede, el icono va entero.
  local function torn(tex, x, y, w, h, a, r, g, b)
    if calm or ZombRand(4) ~= 0 then return false end
    local ok = pcall(function()
      local tw, th = tex:getWidth(), tex:getHeight()
      local jo = ui.javaObject
      for i = 0, 2 do
        local dx = ZombRand(7) - 3
        jo:DrawSubTextureRGBA(tex, 0, th * i / 3, tw, th / 3, x + dx, y + h * i / 3, w, h / 3, r, g, b, a)
      end
    end)
    return ok
  end
  rawset(proxy, "drawTextureScaled", function(_, tex, x, y, w, h, a, r, g, b)
    ui:drawTextureScaled(tex, x + jx + sp, y + jy, w, h, a * 0.5, 0.2, 1, 1)
    ui:drawTextureScaled(tex, x + jx - sp, y + jy, w, h, a * 0.5, 1, 0.15, 0.85)
    if not (tex and torn(tex, x + jx, y + jy, w, h, a, r or 1, g or 1, b or 1)) then
      ui:drawTextureScaled(tex, x + jx, y + jy, w, h, a, r, g, b)
    end
  end)
  rawset(proxy, "drawText", function(_, text, x, y, r, g, b, a, font)
    ui:drawText(text, x + jx + sp, y + jy, 0.2, 1, 1, a * 0.45, font)
    ui:drawText(text, x + jx - sp, y + jy, 1, 0.15, 0.85, a * 0.45, font)
    ui:drawText(text, x + jx, y + jy, r, g, b, a, font)
  end)
  rawset(proxy, "drawTextRight", function(_, text, x, y, r, g, b, a, font)
    ui:drawTextRight(text, x + jx + sp, y + jy, 0.2, 1, 1, a * 0.45, font)
    ui:drawTextRight(text, x + jx - sp, y + jy, 1, 0.15, 0.85, a * 0.45, font)
    ui:drawTextRight(text, x + jx, y + jy, r, g, b, a, font)
  end)
  return proxy
end

-- Fuerza un glitch de pantalla de ms milisegundos (inestabilidad temporal de la cyberpsicosis).
function H.forceGlitch(ms)
  local now = S.realMs()
  local calm = S.lessFlashes()
  if calm and now >= (H.glitchUntil or 0) and now - (H.glitchUntil or 0) < (CFG.LessFlashes.GlitchGapMs or 1000) then return end   -- (170) C01
  H.glitchUntil = math.max(H.glitchUntil or 0, now + ms)
  H.glitchStrips = {}
  for i = 1, calm and 0 or (4 + ZombRand(5)) do
    H.glitchStrips[i] = { y = ZombRandFloat(0, 1), h = 2 + ZombRand(14), dx = ZombRand(81) - 40, a = ZombRandFloat(0.15, 0.4), c = ZombRand(3) }
  end
  H.glitchDX = calm and 0 or (ZombRand(13) - 6)
  H.wiggleMoodles()
end

function H.flash(kind)
  H.flashKind = kind
  H.flashUntil = S.realMs() + 400
end

-- Encendido del panel tras instalar el implante (v0.1.30 (80)): parpadeo de arranque y barrido de prueba de los indicadores (suben al tope y
-- vuelven a su valor real). Solo visual: no toca el estado. H.bootSweep es pura para poder probarla.
local BOOT_SECONDS = 1.9
function H.bootSweep(t)                                  -- t en segundos desde el encendido -> (opacidad, barrido 0..1) o nil si ya terminó
  if t < 0 or t >= BOOT_SECONDS then return nil end
  local a = 1
  if t < 0.4 then
    if S.lessFlashes() then a = 0.25 + 0.75 * t / 0.4                    -- (170) C01: sube de a poco en vez de parpadear
    else a = (math.floor(t * 1000 / 70) % 2 == 0) and 1 or 0.25 end
  end
  local u = math.max(0, math.min(1, (t - 0.4) / 1.4))
  return a, math.sin(math.pi * u)
end

function H.bootActive() return H.boot ~= nil and H.bootSweep((S.realMs() - H.boot.ms) / 1000) ~= nil end

-- Tras instalarse el implante por primera vez (o con force, desde Debug): muestra el panel flotante aunque los moodles de Moodle Framework lo
-- ocultarían (d.hudFloating pasa a true; la elección explícita del jugador, true o false, no se pisa) y lo enciende con el barrido de prueba.
-- Queda visible hasta que el jugador lo oculte (clic derecho > ocultar, pestaña Implante o la tecla). Una sola vez por personaje.
function H.powerOn(p, force)
  if not p then return false end
  pcall(function() if p.isLocalPlayer and not p:isLocalPlayer() then p = nil end end)
  if not p then return false end
  local d = S.data(p)
  if not S.hasWorkingImplant(d) or (d.hudInstallShown and not force) then return false end
  d.hudInstallShown = true
  if d.hudFloating == nil and not H.floatingVisible(d) then d.hudFloating = true end
  local now = S.realMs()
  H.boot = { ms = now, pn = p:getPlayerNum() }
  H.flashKind, H.flashUntil = "on", now + 400
  return true
end

local function palette(d)
  if d.cyberpsychosisActive then return 0.85, 0.1, 0.15 end
  local v = CFG.Variants[d.variant]
  if v then return v.color[1], v.color[2], v.color[3] end
  return 0.5, 0.5, 0.5
end

function H:new(x, y)
  local o = ISUIElement.new(self, x, y, W0, 10)
  o.moving = false
  return o
end

-- Posición guardada en la partida (ModData del jugador), dentro de la pantalla.
local function clampToScreen(x, y)
  local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
  return math.max(0, math.min(sw - 60, x)), math.max(0, math.min(sh - 40, y))
end

function H:loadPosition()
  local p = getSpecificPlayer(0)
  if not p then return end
  local d = S.data(p)
  if d.hudX and d.hudY then
    local x, y = clampToScreen(d.hudX, d.hudY)
    self:setX(x); self:setY(y)
  end
end

function H:savePosition()
  local p = getSpecificPlayer(0)
  if not p then return end
  local d = S.data(p)
  d.hudX, d.hudY = self:getX(), self:getY()
end

function H:onMouseDown(x, y) self.moving = true; self.dragX, self.dragY = x, y; return true end
function H:onMouseUp() if self.moving then self:savePosition() end; self.moving = false; return true end
function H:onMouseUpOutside() if self.moving then self:savePosition() end; self.moving = false end
function H:onMouseMove(dx, dy)
  if self.moving then self:setX(self:getX() + dx); self:setY(self:getY() + dy) end
end
function H:onMouseMoveOutside(dx, dy) self:onMouseMove(dx, dy) end

local function hudScale()
  local k = 1
  if SandevistanInput then k = tonumber(SandevistanInput.getOption("hudScale", 1)) or 1 end
  return math.max(1, math.min(1.6, k))
end

---------------------------------------------------------------------------
-- Modelo del panel (HUDPanel.lua lo dibuja)
---------------------------------------------------------------------------
local function stateOf(d, s)
  if d.variant == "destroyed" then return "destroyed", getText("IGUI_Sandevistan_HUD_Offline") end
  if not S.hasWorkingImplant(d) then return nil, nil end
  if s.fury then return "overdrive", getText("IGUI_Sandevistan_HUD_Fury") end
  if s.overdrive then return "overdrive", getText("IGUI_Sandevistan_HUD_Overdrive") end
  if s.armed then return "armed", getText("IGUI_Sandevistan_HUD_Armed") end
  if s.active then return "active", getText("IGUI_Sandevistan_HUD_Active") end
  if d.lockUntilCool and d.heat > 0 then return "cooling", getText("IGUI_Sandevistan_HUD_Cooling") end
  return "ready", getText("IGUI_Sandevistan_HUD_Ready")
end

-- Filas tipo moodle (solo si Moodle Framework no las muestra en la columna vanilla): salen de los mismos
-- estados que los moodles (Moodles.lua), solo los que no tienen barra o franja propia en el panel.
local function statusRows(p)
  local rows = {}
  local M = SandevistanMoodles
  if not M then return rows end
  for _, st in ipairs(M.states(p)) do
    if st.row then
      local r, g, b = 1, 0.6, 0.45
      if st.kind == "Good" then r, g, b = 0.5, 0.9, 0.65 end
      rows[#rows + 1] = { icon = st.hud, text = st.title, r = r, g = g, b = b }
    end
  end
  return rows
end

-- ¿Se dibuja el panel flotante? d.hudFloating: true = siempre, false = nunca, nil = automático (solo mientras
-- los moodles de Moodle Framework no estén activos).
function H.floatingVisible(d)
  if d.hudFloating ~= nil then return d.hudFloating and true or false end
  return not (SandevistanMoodles and SandevistanMoodles.ready)
end

function H.toggleFloating(p)
  p = p or getSpecificPlayer(0)
  if not p then return end
  local d = S.data(p)
  d.hudFloating = not H.floatingVisible(d)
  return d.hudFloating
end

-- ¿El implante está bloqueado (no se puede activar)? Bloqueo térmico (hay que enfriar hasta Heat 0), Heat al tope o rechazo alto.
-- Con eso la barra de Heat se dibuja toda roja. (La falta de estamina no cuenta: es momentánea y titilaría.)
function H.isLocked(d, s)
  if not S.hasWorkingImplant(d) or s.active or s.overdrive then return false end
  if d.lockUntilCool and (d.heat or 0) > 0 then return true end
  if (d.heat or 0) >= S.heatCap(d) then return true end
  if (d.rejection or 0) >= CFG.Rejection.BlockActivationAt then return true end
  return false
end

H.titleCache, H.levelCache = {}, {}      -- (58) textos que no cambian entre cuadros
function H.buildModel(p, d, s)
  local now = S.worldHours()
  local coverage = S.immunoHoursLeft(d, now)
  local r, g, b = palette(d)
  local working = S.hasWorkingImplant(d)
  local realMs = S.realMs()
  local m = {
    color = { r, g, b }, working = working,
    heat = d.heat or 0, heatCap = S.heatCap(d), heatPct = S.heatPct(d), rejection = d.rejection or 0, neural = d.neuralLoad or 0,
    coverageHours = coverage,
    locked = H.isLocked(d, s),
    disconnected = d.disconnected and true or false,     -- (165b) T12: la placa se rotula DESCONECTADO
    cyber = d.cyberpsychosisActive and true or false,
    idle = not s.active and d.heat <= 0,
    expanded = d.hudExpanded and true or false,
    style = d.variant,                                   -- "lab" = aspecto casero; "military" y el resto = diseno limpio
    alpha = H.fadeAlpha or 1,
    glitching = H.glitching and not S.lessFlashes(), glitchDX = H.glitchDX,     -- (170) C01: sin desgarro ni letras cambiantes en el panel
    timeMs = realMs,
    flash = math.max(0, math.min(1, (H.flashUntil - realMs) / 400)),
  }
  if H.boot and H.boot.pn == p:getPlayerNum() and working then
    local a, sweep = H.bootSweep((realMs - H.boot.ms) / 1000)
    if a then
      m.alpha = a
      m.heat, m.heatPct = math.max(m.heat, 100 * sweep), math.max(m.heatPct, 100 * sweep)
      m.rejection, m.neural = math.max(m.rejection, 100 * sweep), math.max(m.neural, 100 * sweep)
    else H.boot = nil end
  end
  m.stateKey, m.stateText = stateOf(d, s)
  local FWm = rawget(_G, "SandevistanFirmware")
  if FWm and working and FWm.enabled() then          -- (88) los dos leds de los slots de firmware del panel de placa
    m.fw = { FWm.slotProgram(d, "sistema") ~= nil, FWm.slotProgram(d, "habilidad") ~= nil }
  end
  if d.variant == "destroyed" then
    m.title = SandevistanHUDPanel.text("IGUI_Sandevistan_HUD_Destroyed")
  elseif d.disconnected then
    m.title = SandevistanHUDPanel.text("IGUI_Sandevistan_HUD_Disconnected")
  elseif d.variant then
    local tkey = d.variant .. "|" .. tostring(d.prototype) .. "|" .. tostring(d.plateName)
    m.title = H.titleCache[tkey]
    if not m.title then
      m.title = S.plateTitle(d)                               -- (69) nombre de la placa o titulo segun el diseno
      H.titleCache[tkey] = m.title
    end
    m.prototype, m.plate = d.prototype, d.plateName
  else
    m.title = SandevistanHUDPanel.text("IGUI_Sandevistan_HUD_Monitor")
  end
  if working then
    local lvl = S.displayLevel(d)                        -- (123) con la maestria de Beyond Ten, 11..15
    m.level = lvl                                        -- (70) el panel de laboratorio lo dibuja en 7 segmentos
    m.levelText = H.levelCache[lvl]
    if not m.levelText then m.levelText = getText("IGUI_Sandevistan_HUD_Level", lvl); H.levelCache[lvl] = m.levelText end
    local _, _, _, frac = S.levelProgress(d)
    if S.masteryEnabled(d) and S.level(d) >= S.maxLevel(d) then _, _, _, frac = S.masteryProgress(d) end
    m.xpFrac = frac
  end
  local hideRows = SandevistanMoodles and SandevistanMoodles.ready
                   and not (SandevistanInput and SandevistanInput.getOption("hudMoodles", false))
  m.statuses = hideRows and {} or statusRows(p)
  return m
end

-- Transparencia: con el Heat en 0 y el implante apagado el panel se desvanece despacio (y vuelve rápido al usarlo).
H.fadeAlpha, H.fadeMs = 1, nil
function H.updateFade(d, s, ui)
  local now = S.realMs()
  local dt = math.min(0.25, (now - (H.fadeMs or now)) / 1000)
  H.fadeMs = now
  local busy = s.active or s.armed or s.overdrive or (d.heat or 0) > 0 or (H.flashUntil or 0) > now or H.bootActive()
  -- el mouse encima del panel lo va opacando de a poco (para leer los demás valores); al sacarlo vuelve despacio
  local hover = false
  if ui then
    pcall(function()
      local mx, my = getMouseX(), getMouseY()
      local ax, ay = ui:getAbsoluteX(), ui:getAbsoluteY()
      hover = ui:getHeight() > 0 and mx >= ax and mx <= ax + ui:getWidth() and my >= ay and my <= ay + ui:getHeight()
    end)
  end
  H.hover = hover
  local target = (busy or hover) and 1 or CFG.HUD.IdleAlpha
  local speed = busy and CFG.HUD.FadeInPerSecond or (hover and CFG.HUD.HoverInPerSecond or CFG.HUD.FadeOutPerSecond)
  if H.fadeAlpha < target then H.fadeAlpha = math.min(target, H.fadeAlpha + speed * dt)
  else H.fadeAlpha = math.max(target, H.fadeAlpha - speed * dt) end
end

-- Clic derecho en el panel: compacto (solo Heat) / expandido (con Rechazo y Neural).
function H:onRightMouseUp(x, y)
  local p = getSpecificPlayer(0)
  if not p then return true end
  local d = S.data(p)
  local ok = pcall(function()
    local ctx = ISContextMenu.get(0, getMouseX(), getMouseY())
    ctx:addOption(getText(d.hudExpanded and "IGUI_Sandevistan_HUD_Compact" or "IGUI_Sandevistan_HUD_Expand"), self, function() d.hudExpanded = not d.hudExpanded end)
    ctx:addOption(getText("IGUI_Sandevistan_HUD_HidePanel"), self, function() d.hudFloating = false end)
  end)
  if not ok then d.hudExpanded = not d.hudExpanded end
  return true
end

-- v0.1.30: el dibujo va protegido (un error ya no se repite en cada frame sin aviso) y cuenta para el reporte de rendimiento.
local prerenderBody
function H:prerender()
  local t0 = S.clockMs()
  local ok, err = pcall(prerenderBody, self)
  S.perfAdd("HUD.prerender", S.clockMs() - t0)
  if not ok then
    H.renderErrors = (H.renderErrors or 0) + 1
    if H.renderErrors == 1 or H.renderErrors % 1000 == 0 then S.logAlways("ERROR en HUD.prerender (x" .. H.renderErrors .. "): " .. tostring(err)) end
  end
end

prerenderBody = function(self)
  local p = getSpecificPlayer(0)
  if not p or p:isDead() then self:setHeight(0); return end
  if H.benchPending then H.benchPending = false; local okb, errb = pcall(H.runBench, self, p); if not okb then S.logAlways("ERROR en el microbenchmark del HUD: " .. tostring(errb)) end end
  local clock, add = S.clockMs, S.perfAdd                  -- v0.1.30: tiempos por parte para el reporte de rendimiento
  local t = clock()
  self:drawExSubjectMarkers(p)
  local dFX = S.data(p)
  local t1 = clock(); add("HUD > marcadores ex-sujetos", t1 - t); t = t1
  SandevistanAfterimages.update(p, R.session(p), dFX)
  SandevistanAfterimages.updateRemotes(p, R.session(p))         -- v0.1.30 (31): estelas ajenas solo con ambos activos
  SandevistanAfterimages.draw(self, p, dFX)
  t1 = clock(); add("HUD > estelas", t1 - t); t = t1
  SandevistanSpine.update()
  t1 = clock(); add("HUD > espalda", t1 - t); t = t1
  SandevistanInstallScene.draw(self, p)                    -- v0.1.30 (30): escena de instalacion (antes de la salida "sin implante": tambien dibuja la del fallo)
  local d = dFX                                            -- (61) la misma tabla de datos (antes una segunda llamada a S.data por cuadro)
  if not S.hasAnyImplant(d) and not Kerenzikov.isActive(p) and d.herbalToxicity <= 0 and d.neuralLoad <= 0 then
    self:setHeight(0); return
  end
  local s = R.session(p)
  H.glitching = H.updateGlitch(d)
  self:drawOverlay(d, s)                                   -- el overlay de pantalla no depende del panel
  t1 = clock(); add("HUD > overlay (tinte, viñeta, glitch)", t1 - t); t = t1
  if not H.mfHooked then H.hookMoodleRender() end          -- (182) el negro del apagon tambien sobre los moodles de MF
  SandevistanPsychosis.draw(self, p, d)                    -- cyberpsicosis: visión de amenaza, apagones y monitor neural
  t1 = clock(); add("HUD > cyberpsicosis (monitor, peligro, apagones)", t1 - t); t = t1
  H.updateFade(d, s, self)
  if not H.floatingVisible(d) then self:setHeight(0); return end
  local model = H.buildModel(p, d, s)
  local uiDraw = H.glitching and H.glitchUI(self) or self      -- (142) glitch del panel propio
  local w, h = SandevistanHUDPanel.draw(uiDraw, model, hudScale())
  add("HUD > panel flotante", clock() - t)
  if self:getWidth() ~= w then self:setWidth(w) end
  self:setHeight(h)
end

---------------------------------------------------------------------------
-- Marcador de ex-sujetos: tira de LEDs sobre la espalda (sustituto de la espina 3D).
---------------------------------------------------------------------------
function H:drawExSubjectMarkers(p)
  if not SandevistanWorld or not SandevistanWorld.tagged then return end
  if SandevistanViewport.is3D() then return end                  -- (95) camara 3D de Project Viewport
  local subjects = SandevistanWorld.data().subjects
  local ax, ay = self:getAbsoluteX(), self:getAbsoluteY()
  local zoom = 1
  pcall(function() zoom = getCore():getZoom(0) end)
  local px, py = p:getX(), p:getY()
  local pulse = 0.6 + 0.4 * math.abs(math.sin(S.realMs() / 300))
  for z, id in pairs(SandevistanWorld.tagged()) do
    local ok = pcall(function()
      if z:isDead() then return end
      local dx, dy = z:getX() - px, z:getY() - py
      if dx * dx + dy * dy > 400 then return end
      local alpha = 1
      pcall(function() alpha = z:getAlpha(0) end)
      if alpha < 0.2 then return end
      local sub = subjects[id]
      local r, g, b = 1.0, 0.7, 0.15
      if sub and sub.variant == "lab" then r, g, b = 0.2, 0.9, 1.0 end
      local sx = isoToScreenX(0, z:getX(), z:getY(), z:getZ()) - ax
      local sy = isoToScreenY(0, z:getX(), z:getY(), z:getZ()) - ay - 70 / zoom
      local seg = math.max(2, math.floor(4 / zoom))
      for i = 0, 5 do
        self:drawRect(sx - seg, sy + i * seg * 2, seg * 2, seg, alpha * pulse, r, g, b)
      end
    end)
    if not ok then S.warnOnce("marker", "no se pudo dibujar el marcador de ex-sujeto") end
  end
end

---------------------------------------------------------------------------
-- Overlay de pantalla: se dibuja desde el propio HUD (coordenadas negativas),
-- sin un elemento de pantalla completa que capture el mouse.
---------------------------------------------------------------------------
local HTEX = {}
function H.tex(name)
  local t = HTEX[name]
  if t == nil then
    t = getTexture("media/ui/Sandevistan_HUD_" .. name .. ".png") or false
    HTEX[name] = t
  end
  return t or nil
end

function H:drawOverlay(d, s)
  local ox, oy = -self:getAbsoluteX(), -self:getAbsoluteY()
  local w, h = getCore():getScreenWidth(), getCore():getScreenHeight()
  local HC = CFG.HUD
  local in3D = (s.active or s.overdrive) and SandevistanViewport.is3D()
  if s.active then
    local r, g, b = palette(d)
    self:drawRect(ox, oy, w, h, in3D and HC.Tint3D or HC.Tint, r, g, b)
  end
  if S.hasWorkingImplant(d) and S.heatPct(d) >= 60 then
    -- viñeta de calor: degradé desde los bordes, sin borde duro. v0.1.30: 4 texturas escaladas (antes 80 rectángulos por frame);
    -- si faltan las texturas, los anillos de siempre.
    local peak = (S.heatPct(d) - 60) / 40 * 0.28
    local depth = math.floor(math.min(w, h) * 0.16)
    local vt, vb, vl, vr = H.tex("VigTop"), H.tex("VigBottom"), H.tex("VigLeft"), H.tex("VigRight")
    if vt and vb and vl and vr then
      self:drawTextureScaled(vt, ox, oy, w, depth, peak, 1, 0.1, 0.05)
      self:drawTextureScaled(vb, ox, oy + h - depth, w, depth, peak, 1, 0.1, 0.05)
      self:drawTextureScaled(vl, ox, oy, depth, h, peak, 1, 0.1, 0.05)
      self:drawTextureScaled(vr, ox + w - depth, oy, depth, h, peak, 1, 0.1, 0.05)
    else
    local rings = 20
    local bt = math.max(1, math.floor(depth / rings))
    for i = 0, rings - 1 do
      local f = 1 - i / rings
      local a = peak * f * f
      local o = i * bt
      self:drawRect(ox + o, oy + o, w - 2 * o, bt, a, 1, 0.1, 0.05)                    -- arriba
      self:drawRect(ox + o, oy + h - o - bt, w - 2 * o, bt, a, 1, 0.1, 0.05)          -- abajo
      self:drawRect(ox + o, oy + o + bt, bt, h - 2 * o - 2 * bt, a, 1, 0.1, 0.05)     -- izquierda
      self:drawRect(ox + w - o - bt, oy + o + bt, bt, h - 2 * o - 2 * bt, a, 1, 0.1, 0.05) -- derecha
    end
    end
  end
  if s.overdrive then self:drawRect(ox, oy, w, h, in3D and HC.OverdriveTint3D or HC.OverdriveTint, 1, 0, 0) end
  if H.glitching then
    -- franjas horizontales desplazadas (cian / magenta / color de la variante), algo más
    -- transparentes que en v0.1.18
    local vr, vg, vb = palette(d)
    local cols = { { 0.2, 1, 1 }, { 1, 0.1, 0.8 }, { vr, vg, vb } }
    for _, st in ipairs(H.glitchStrips) do
      local c = cols[st.c + 1]
      self:drawRect(ox + st.dx, oy + st.y * h, w, st.h, st.a * 0.7, c[1], c[2], c[3])
    end
    if #H.glitchStrips > 0 then self:drawRect(ox, oy, w, h, 0.03, 1, 1, 1) end     -- (170) con menos destellos no hay tiras ni velo
    -- (147) sin las rayas sobre las zonas de moodles/botones/hotbar (v0.1.26): eran rectangulos encima de la interfaz y se notaba el truco.
    -- Los moodles del mod se sacuden (H.wiggleMoodles) y el panel propio se rompe por dentro (H.glitchUI).
  end
end


---------------------------------------------------------------------------
-- (60) MICROBENCHMARK del panel (Debug -> "Costo del panel del HUD"): mide dentro del juego cuanto cuesta cada pieza del dibujo con muchas repeticiones en un solo
-- cuadro (el reloj es de 1 ms: una sola llamada de 0,01 ms no se puede medir, 2000 si). Escribe Zomboid/Lua/Sandevistan_hudbench.txt. Sirve para saber DONDE se
-- va el medio milisegundo del panel antes de optimizar a ciegas: la v0.1.30 (59) bajo las llamadas de dibujo de 110 a 48 y el tiempo del panel no cambio.
---------------------------------------------------------------------------
H.benchPending = false
function H.requestBench() H.benchPending = true end

local function benchLine(lines, label, n, ms, extra)
  lines[#lines + 1] = string.format("%-52s %6d x | %8.1f ms | %8.2f us por vez%s", label, n, ms, ms * 1000 / n, extra and ("  " .. extra) or "")
end

function H.runBench(ui, p)
  local clock = S.clockMs
  local lines = { "# Sandevistan " .. CFG.Build .. ": microbenchmark del panel del HUD", "(1 ms de resolucion: cada fila repite la operacion muchas veces)", "" }
  local function time(label, n, fn, extra)
    fn()                                       -- calentamiento
    local t0 = clock()
    for _ = 1, n do fn() end
    benchLine(lines, label, n, clock() - t0, extra)
  end
  local d = S.data(p)
  local s = R.session(p)
  local P = SandevistanHUDPanel
  local small = UIFont.Small
  local tex = getTexture("media/ui/Sandevistan_HUD_Heat.png")
  lines[#lines + 1] = "-- Lua puro y getters"
  time("S.data(player)", 3000, function() S.data(p) end)
  time("S.realMs()", 3000, function() S.realMs() end)
  time("S.worldHours()", 3000, function() S.worldHours() end)
  time("H.buildModel (el modelo del panel entero)", 1500, function() H.buildModel(p, d, s) end)
  time("H.updateFade (mouse, alfa)", 1500, function() H.updateFade(d, s, ui) end)
  time("SandevistanMoodles.states(player)", 1500, function() if SandevistanMoodles then SandevistanMoodles.states(p) end end)
  time("getText (sin cache)", 3000, function() getText("IGUI_Sandevistan_HUD_Heat") end)
  time("MeasureStringX (Java)", 3000, function() getTextManager():MeasureStringX(small, "Lv 4") end)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "-- Primitivas de dibujo (cada una dibuja de verdad en este cuadro)"
  time("drawRect", 3000, function() ui:drawRect(0, 0, 40, 4, 0.1, 1, 1, 1) end)
  time("drawRectBorder", 2000, function() ui:drawRectBorder(0, 0, 40, 12, 0.1, 1, 1, 1) end)
  time("drawText (Small)", 1500, function() ui:drawText("Heat", 0, 0, 1, 1, 1, 0.1, small) end)
  time("drawText (Medium)", 1000, function() ui:drawText("SANDEVISTAN", 0, 0, 1, 1, 1, 0.1, UIFont.Medium) end)
  time("drawTextRight (Small)", 1500, function() ui:drawTextRight("42", 40, 0, 1, 1, 1, 0.1, small) end)
  time("drawTextureScaled (icono 14 px)", 2000, function() if tex then ui:drawTextureScaled(tex, 0, 0, 14, 14, 0.1, 1, 1, 1) end end)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "-- El panel entero (dibujo)"
  local k = hudScale()
  for _, case in ipairs({ { "activo", true, 1.0 }, { "reposo", false, 0.3 } }) do
    local keepA, keepAct, keepHeat = H.fadeAlpha, s.active, d.heat
    s.active = case[2]; d.heat = case[2] and 40 or 0; H.fadeAlpha = case[3]
    local model = H.buildModel(p, d, s)
    S.perf.counts["hud.panel.liviano"] = 0
    local w, h = P.draw(ui, model, k)
    time("P.draw panel " .. case[1] .. " (modelo ya armado)", 300, function() P.draw(ui, model, k) end,
         "(" .. tostring(w) .. "x" .. tostring(h) .. ", liviano=" .. tostring((S.perf.counts["hud.panel.liviano"] or 0) > 0) .. ")")
    H.fadeAlpha, s.active, d.heat = keepA, keepAct, keepHeat
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "lectura: si 'P.draw panel' cuesta casi lo mismo activo que en reposo, el costo no esta en la cantidad de primitivas. Si 'H.buildModel' o 'H.updateFade' pesan, el costo esta en el modelo."
  pcall(function()
    local w = getFileWriter("Sandevistan_hudbench.txt", true, false)
    for _, l in ipairs(lines) do w:write(S.ascii(l) .. "\n") end
    w:close()
  end)
  for _, l in ipairs(lines) do print("[Sandevistan][HUDBENCH] " .. S.ascii(l)) end
  pcall(function() p:Say("Microbenchmark del panel listo: Zomboid/Lua/Sandevistan_hudbench.txt") end)
end

---------------------------------------------------------------------------
function H.create()
  if H.instance then return end
  local hud = H:new(80, 220)
  hud:initialise(); hud:addToUIManager()
  hud:loadPosition()
  H.instance = hud
end

function H.setVisible(v)
  if H.instance then H.instance:setVisible(v) end
end

Events.OnGameStart.Add(S.safe("HUD.OnGameStart", H.create))
return H
