-- Sandevistan / ScreenFX (cliente, 0.7 (181)): lo que queda de la lista Java (C13, 31 §10.2), del lado de Lua. Aca se decide CUANDO; lo hacen dos mods
-- opcionales y sin ellos no pasa nada:
--  * C13.3 sacudida de camara (apagon, furia, sobrecarga, susto y contacto de un zombi falso) y C13.5 efectos de pantalla de los episodios
--    (desaturacion, ondulacion, separacion de color y desgarro del mundo): el jar de SandevistanPsychosis (SF.backend, lo llena su Bridge.lua).
--    (185) Tambien con la camara 3D de Viewpoint si Config.Psychosis.ScreenFX.In3D: Viewpoint dibuja el mundo el, pero deja la imagen en la
--    textura del mundo del juego y el juego la pasa a la pantalla igual que en isometrico (ahi estan los enganches del jar).
--  * C13.4 tono de los sonidos reales cercanos durante el episodio (un poco desafinados): el pedido de tono generico de SandevistanFX
--    (SandevistanFXBridge.pitchRequest), que no sabe de la cyberpsicosis.
-- Todo es local de este cliente y respeta «menos destellos» (C01): sin copias de color ni tiras, ondulacion y sacudida mas suaves.
-- Config.Psychosis.ScreenFX.
require "Sandevistan/Core"
require "Sandevistan/Viewport"

local CFG = SandevistanConfig
local S = Sandevistan

SandevistanScreenFX = { backend = nil, base = {}, hits = {}, sent = {}, shakes = 0, screens = 0, bursts = 0, pitches = 0, errors = 0 }
local SF = SandevistanScreenFX

local function C() return CFG.Psychosis.ScreenFX end
local function is3D() return SandevistanViewport ~= nil and SandevistanViewport.is3D ~= nil and SandevistanViewport.is3D() == true end
-- (185) Si con la camara de ahora van los efectos (en 3D, solo con In3D).
local function allowed()
  if not is3D() then return true end
  local c = C()
  return c ~= nil and c.In3D == true
end
SF.allowed = allowed
local PITCH_KEY = "psychosisEpisode"

function SF.ready()
  local b = SF.backend
  if not b then return false end
  return S.cached("SF.ready", 1000, function()          -- (194) una vez por segundo, no en cada tick
    local ok, r = pcall(b.ready)
    return ok and r == true
  end, b)
end

-- Sacudida de un evento (kind = clave de Config.Psychosis.ScreenFX.Shake). px/ms fuerzan otros valores (Debug).
function SF.shake(player, kind, px, ms)
  local c = C()
  if not (c and c.Enabled and c.Shake and c.Shake.Enabled) and not px then return false end
  local v = (c and c.Shake and c.Shake[kind]) or nil
  px, ms = px or (v and v[1]), ms or (v and v[2])
  if not (px and ms) or not SF.ready() or not allowed() then return false end
  if S.lessFlashes() then px = px * (CFG.LessFlashes.ShakeMult or 0.5) end
  if is3D() then px = px * ((c and c.Shake3DMult) or 0.5) end          -- (185) en primera persona marea mas
  local ok, err = pcall(SF.backend.shake, player:getPlayerNum(), px, ms)
  if not ok then SF.errors = SF.errors + 1; S.warnOnce("sfShake", "sacudida: " .. tostring(err)); return false end
  SF.shakes = SF.shakes + 1
  return true
end

-- Valores de pantalla de un tipo (Config.Psychosis.ScreenFX.Screen[kind]), con «menos destellos» aplicado.
local function values(kind)
  local sc = C().Screen
  local v = sc and sc[kind]
  if not v then return nil end
  local calm = S.lessFlashes()
  return { d = v.Desat or 0, w = (v.Wobble or 0) * (calm and (CFG.LessFlashes.WobbleMult or 0.5) or 1), b = v.Blur or 0,
           s = calm and 0 or (v.Split or 0), t = calm and 0 or (v.Tear or 0) }
end

-- Empieza el efecto de un episodio (Paranoia / Dissociation) para seconds segundos, y su tono desafinado.
function SF.episode(player, kind, seconds)
  local c = C()
  if not (c and c.Enabled) then return end
  local idx = player:getPlayerNum()
  local now = S.realMs()
  if c.Screen and c.Screen.Enabled then
    local v = values(kind)
    if v then SF.base[idx] = { v = v, untilMs = now + seconds * 1000, kind = kind }; SF.screens = SF.screens + 1 end
  end
  SF.pitch(kind, seconds * 1000)
end

-- Termina el episodio (CR.stop): la pantalla sale con su fundido y el tono vuelve en el proximo refresco de FX.
function SF.episodeEnd(player)
  SF.base[player:getPlayerNum()] = nil
  SF.pitch(nil, 0)
end

-- Golpe corto (tartamudeo de la disociacion, tartamudeo del tiempo): Screen.Burst encima de lo que haya.
function SF.burst(player, ms)
  local c = C()
  if not (c and c.Enabled and c.Screen and c.Screen.Enabled) then return end
  local v = values("Burst")
  if not v then return end
  SF.hits[player:getPlayerNum()] = { v = v, untilMs = S.realMs() + (ms or 500) }
  SF.bursts = SF.bursts + 1
end

-- C13.4: tono de los sonidos reales cercanos (Config.Psychosis.ScreenFX.Pitch[kind] = { tono, oscilacion }); kind nil lo suelta.
function SF.pitch(kind, ms)
  local FXB = rawget(_G, "SandevistanFXBridge")
  if not (FXB and FXB.pitchRequest) then return false end
  local p = C().Pitch
  local v = kind and p and p.Enabled and p[kind] or nil
  if not v then FXB.pitchRequest(PITCH_KEY, 1, 0); return false end
  FXB.pitchRequest(PITCH_KEY, v[1], ms, v[2] or 0, p.Hz or 0.3)
  SF.pitches = SF.pitches + 1
  return true
end

-- Lo que hay que mostrar ahora: lo mas fuerte de cada valor entre el episodio y el golpe, y hasta cuando.
-- (184) Antes era ipairs({ base, golpe }): sin episodio, base es nil, ipairs corta ahi y el golpe solo nunca se mandaba (182 y 183).
function SF.effective(idx, now)
  local out, untilMs = nil, 0
  for i = 1, 2 do
    local e = (i == 1) and SF.base[idx] or SF.hits[idx]
    if e and now < e.untilMs then
      out = out or { d = 0, w = 0, b = 0, s = 0, t = 0 }
      for k, x in pairs(e.v) do if x > out[k] then out[k] = x end end
      if e.untilMs > untilMs then untilMs = e.untilMs end
    end
  end
  return out, untilMs
end

local function same(a, b)
  if not a or not b then return a == b end
  for _, k in ipairs({ "d", "w", "b", "s", "t" }) do if math.abs(a[k] - b[k]) > 1e-3 then return false end end
  return true
end

-- Desde Psychosis.tick: manda al jar solo cuando cambia (o una vez por segundo, por si el jar se reinicio).
function SF.tick(player, now)
  local idx = player:getPlayerNum()
  if SF.base[idx] and now >= SF.base[idx].untilMs then SF.base[idx] = nil end
  if SF.hits[idx] and now >= SF.hits[idx].untilMs then SF.hits[idx] = nil end
  local want, untilMs = SF.effective(idx, now)
  if not allowed() then want = nil end
  local sent = SF.sent[idx]
  if not want then
    if sent then
      SF.sent[idx] = nil
      if SF.backend then pcall(SF.backend.screenStop, idx) end
    end
    return
  end
  if not SF.ready() then return end
  if sent and same(sent.v, want) and sent.untilMs == untilMs and now < sent.refreshMs then return end
  local ok, err = pcall(SF.backend.screen, idx, want.d, want.w, want.b, want.s, want.t, math.max(1, untilMs - now))
  if not ok then SF.errors = SF.errors + 1; S.warnOnce("sfScreen", "pantalla: " .. tostring(err)); return end
  SF.sent[idx] = { v = want, untilMs = untilMs, refreshMs = now + 1000 }
end

function SF.clear(idx)
  SF.base[idx], SF.hits[idx] = nil, nil
  if SF.sent[idx] and SF.backend then pcall(SF.backend.screenStop, idx) end
  SF.sent[idx] = nil
  SF.pitch(nil, 0)
end

-- (Debug) Un tipo de pantalla (Paranoia / Dissociation) y su tono por seconds, aunque no haya episodio.
function SF.test(player, kind, seconds)
  SF.episode(player, kind, seconds or 15)
end

function SF.statusLine()
  local b = SF.backend
  local js = b and b.stats and select(2, pcall(b.stats)) or "sin el jar de SandevistanPsychosis"
  return string.format("sacudida y pantalla: %d sacudidas, %d episodios en pantalla, %d golpes, %d pedidos de tono, errores %d%s | %s",
    SF.shakes, SF.screens, SF.bursts, SF.pitches, SF.errors, (not is3D()) and "" or (allowed() and " (camara 3D)" or " (camara 3D: sin efectos)"), tostring(js))
end

Events.OnPlayerDeath.Add(S.safe("ScreenFX.OnPlayerDeath", function(player) SF.clear(player:getPlayerNum()) end))

return SF
