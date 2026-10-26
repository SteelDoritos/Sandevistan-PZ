-- SandevistanPsychosis / Bridge (mod opcional, 0.7 (152)): conecta la cyberpsicosis del Sandevistan con el jar de este mod (ZombieBuddy lo carga y
-- lo expone a Lua como SandevistanPsy). Todo es local: lo ve solo este cliente y nada viaja por la red.
--  * (138) titeres: dibuja los zombis falsos (Sandevistan/FakeZombies.lua decide todo; aca solo se pasa al jar).
--  * (148) el clon: titere con la visual del jugador (Sandevistan/Doppelganger.lua decide todo).
--  * (138) texto corrupto: cambia letras por simbolos en todo el texto del juego cuando Psychosis.lua lo pide.
--  * (149) glitch de los moodles vanilla (lo pide HUD.wiggleMoodles).
--  * (147) disfraz (22 §6.2.1): este cliente ve a un zombi con piel de persona o a un jugador con piel de zombi, por un rato.
--  * (174) disfraz nivel B: un jugador visto como un zombi entero (no se dibuja y va un titere zombi en su lugar). Sandevistan/Disguise.lua decide.
--  * (181) C13.3 sacudida de camara y C13.5 efectos de pantalla de los episodios (Sandevistan/ScreenFX.lua decide; las figuras fantasma de C13.2
--    usan los titeres de siempre, por FZ.backend).
-- Hasta la 151 todo esto estaba en SandevistanFX (SandevistanFXBridge); se mudo a su mod (27 §11.3) con las mismas funciones.
-- Sin el jar (ZombieBuddy no lo aprobo) no pasa nada: la cyberpsicosis sigue con sus efectos de Lua.
require "Sandevistan/Core"
require "Sandevistan/FakeZombies"
require "Sandevistan/Doppelganger"
require "Sandevistan/Disguise"
require "Sandevistan/Psychosis"
require "Sandevistan/ScreenFX"

local S = Sandevistan

SandevistanPsyBridge = { disguised = {} }
local B = SandevistanPsyBridge

-- El juego publica la clase del jar como global SandevistanPsy y tambien con la ruta del paquete (sandevistan.psychosis.SandevistanPsy).
local function jar()
  local j = rawget(_G, "SandevistanPsy")
  if j then return j end
  local pkg = rawget(_G, "sandevistan")
  return type(pkg) == "table" and type(pkg.psychosis) == "table" and pkg.psychosis.SandevistanPsy or nil
end
B.jar = jar

-- (147) Disfraz: mode 1 persona, 2..4 zombi (podredumbre 1..3), 0 lo saca. Dura ms (por defecto 60 s) y se saca solo en B.tick.
function B.disguise(chr, mode, ms)
  local j = jar()
  if not (j and j.disguise and chr) then return false end
  local ok, r = pcall(j.disguise, chr, mode)
  if not (ok and r == true) then return false end
  B.disguised[chr] = mode > 0 and (S.realMs() + (ms or 60000)) or nil
  return true
end

function B.disguiseClear()
  local DSm = rawget(_G, "SandevistanDisguise")                -- (174) tambien los episodios de disfraz en curso
  if DSm then DSm.eps = {} end
  local j = jar()
  if j and j.disguiseClear then pcall(j.disguiseClear) end
  B.disguised = {}
end

-- (149) Glitch de los moodles vanilla (lo pide HUD.wiggleMoodles al empezar cada glitch de pantalla).
function B.moodleGlitch(amount, ms)
  local j = jar()
  if j and j.moodleGlitch then j.moodleGlitch(amount, ms) end
end

function B.tick()
  if S.isEmpty(B.disguised) then return end
  local j = jar()
  if not j then return end
  local now = S.realMs()
  for chr, untilMs in pairs(B.disguised) do
    if now >= untilMs then
      pcall(j.disguise, chr, 0)
      B.disguised[chr] = nil
    end
  end
end

function B.status()
  local j = jar()
  if not j then return "el jar no esta cargado (ZombieBuddy no lo aprobo o no esta activo)" end
  local ok, s = pcall(function()
    return tostring(j.status()) .. " | " .. tostring(j.puppetStats()) .. " | " .. tostring(j.disguiseStats()) .. " | " .. tostring(j.moodleGlitchStats())
      .. (j.fxStats and (" | " .. tostring(j.fxStats())) or "")
  end)
  return ok and s or ("error: " .. tostring(s))
end

-- (138) Titeres: el motor de dibujo de Sandevistan/FakeZombies.lua (zombis falsos) y de Doppelganger.lua (el clon). Una tabla con las funciones
-- del jar; se pone siempre (aunque el jar falte: ready() da false y no nacen zombis falsos ni clones).
B.puppets = {
  ready = function() local j = jar(); return j ~= nil and j.puppetsAvailable ~= nil and j.puppetsAvailable() == true end,
  spawn = function(id, outfit, female, x, y, z, pn) return jar().puppetSpawn(id, outfit, female, x, y, z, pn) == true end,
  move = function(id, x, y, z, vx, vy, fx, fy) jar().puppetMove(id, x, y, z, vx, vy, fx, fy) end,
  var = function(id, name, value) jar().puppetVar(id, name, value) end,
  look = function(id, a, r, g, b) jar().puppetLook(id, a, r, g, b) end,
  speed = function(id) return tonumber(jar().puppetSpeed(id)) or -1 end,              -- (138e) paso de la animacion
  outline = function(id, on) jar().puppetOutline(id, on and true or false) end,       -- (141) borde rojo
  glitch = function(id, v) jar().puppetGlitch(id, v) end,                              -- (142) separacion de color
  state = function(id, s) jar().puppetSetState(id, s) end,                             -- (148) estado (el clon)
  remove = function(id) local j = jar(); if j then j.puppetRemove(id) end end,
  clear = function() local j = jar(); if j then j.puppetClear() end end,
  stats = function() local j = jar(); return j and tostring(j.puppetStats()) or "sin el jar de SandevistanPsychosis" end,
  canClone = function() return jar() ~= nil end,                                       -- (148) el clon (Doppelganger.lua)
  spawnClone = function(id, chr, x, y, z, pn) return jar().puppetSpawnClone(id, chr, x, y, z, pn) == true end,
}
local FZ = rawget(_G, "SandevistanFakeZombies")
if FZ then FZ.backend = B.puppets end

-- (174) Disfraz como episodio (Sandevistan/Disguise.lua): nivel A (B.disguise, con su vencimiento) y nivel B (titere en lugar del jugador).
local DS = rawget(_G, "SandevistanDisguise")
if DS then
  DS.backend = {
    ready = function() local j = jar(); return j ~= nil and j.disguise ~= nil end,
    canHide = function() local j = jar(); return j ~= nil and j.disguiseHide ~= nil and j.puppetsAvailable() == true end,
    disguise = B.disguise,
    hide = function(chr, id, pn, rot) return jar().disguiseHide(chr, id, pn, rot) == true end,
    unhide = function(chr) local j = jar(); if j then j.disguiseUnhide(chr) end end,
    hidden = function(chr) return jar().disguiseHidden(chr) == true end,
    -- (188) jar 5: mirar al que lo ve y soltarse (un jar viejo no los tiene: el disfraz sigue, sin girar ni soltarse)
    face = function(id, on, x, y, deg) local j = jar(); if j and j.puppetFace then j.puppetFace(id, on and true or false, x, y, deg) end end,
    canDetach = function() local j = jar(); return j ~= nil and j.disguiseDetach ~= nil end,
    detach = function(chr, ms) return tonumber(jar().disguiseDetach(chr, ms)) or -1 end,
  }
end

-- (181) C13.3 / C13.5: sacudida de camara y efectos de pantalla (Sandevistan/ScreenFX.lua). Un jar viejo (sin shake) cuenta como ausente.
local SFX = rawget(_G, "SandevistanScreenFX")
if SFX then
  SFX.backend = {
    ready = function() local j = jar(); return j ~= nil and j.shake ~= nil and j.screenFx ~= nil end,
    shake = function(view, px, ms) jar().shake(view, px, ms) end,
    screen = function(view, d, w, b, s, t, ms) jar().screenFx(view, d, w, b, s, t, ms) end,
    screenStop = function(view) local j = jar(); if j and j.screenFxStop then j.screenFxStop(view) end end,
    stats = function() local j = jar(); return j and j.fxStats and tostring(j.fxStats()) or "sin el jar 3 de SandevistanPsychosis" end,
  }
end

-- (138) Texto corrupto (Psychosis.textGlitch): amount 0..1 de las letras, durante ms.
local PSY = rawget(_G, "SandevistanPsychosis")
if PSY then
  PSY.textBackend = function(amount, ms, messages)
    local j = jar()
    if not j then error("sin el jar de SandevistanPsychosis") end
    if messages then j.textGlitch(amount, ms, messages) else j.textGlitch(amount, ms) end
  end
end

Events.OnTick.Add(S.safe("SandevistanPsychosis.OnTick", B.tick))

S.log("SandevistanPsychosis: puente cargado (" .. (jar() and "jar presente" or "jar ausente") .. ")")

return B
