-- SandevistanFX / Bridge (mod opcional, 0.7 (134)): conecta la dilatacion del Sandevistan con el jar de este mod (ZombieBuddy lo carga y lo expone a Lua
-- como SandevistanFX). Dos efectos, solo locales (nada viaja por la red):
--  * tono: cada zombi frenado (Slowdown: SD.slowed, y los que se sueltan de a poco) suena mas grave, Min + (1 - Min) x su factor (Config.FX.Pitch). Los
--    que mueren en camara lenta (SD.zHolds) siguen graves hasta caer. Se apaga con la opcion "voces de zombis" del mod, igual que el volumen de SlowAudio.
--  * lluvia y nieve isometricas: caen a Config.FX.Precip.Factor de su velocidad con un jugador local dilatado (SD.precipFactor).
--  * (134b) ambiente del mundo: el evento de FMOD que trae la lluvia (y el viento) baja a Config.FX.Ambience.Pitch (SD.ambiencePitch).
--  * (152) la cyberpsicosis en Java (titeres, clon, texto corrupto, disfraz, moodles) se mudo al mod SandevistanPsychosis (SandevistanPsyBridge).
--  * (181) C13.4 pedido de tono generico (B.pitchRequest): otro sistema pide que los sonidos reales cercanos suenen con otro tono un rato.
-- Sin el jar (ZombieBuddy no lo aprobo) no pasa nada: el Sandevistan sigue igual.
require "Sandevistan/Core"
require "Sandevistan/Slowdown"

local CFG = SandevistanConfig
local S = Sandevistan
local SD = SandevistanSlowdown

SandevistanFXBridge = { pitched = {}, lastMs = 0, precip = 1, ambience = 1, pitchOk = nil, requests = {}, reqMult = 1 }
local B = SandevistanFXBridge

-- El juego publica la clase del jar como global SandevistanFX y tambien con la ruta del paquete (sandevistan.fx.SandevistanFX).
local function fx()
  local j = rawget(_G, "SandevistanFX")
  if j then return j end
  local pkg = rawget(_G, "sandevistan")
  return type(pkg) == "table" and type(pkg.fx) == "table" and pkg.fx.SandevistanFX or nil
end
B.jar = fx

local function voicesOn()
  local I = rawget(_G, "SandevistanInput")
  return not I or I.getOption("slowZombieVoices", true) ~= false
end

-- (181) C13.4 Pedido de tono generico: key = quien lo pide (cada uno pisa el suyo), mult = tono (1 = normal, lo suelta), ms = cuanto dura,
-- wobble/hz = una oscilacion lenta encima (desafinado). Este mod no sabe para que es (lo usa la cyberpsicosis, Sandevistan/ScreenFX.lua). Se
-- multiplica con el de la dilatacion y con los demas pedidos, y llega a los zombis a Config.FX.Request.Radius casillas, a los jugadores y al
-- ambiente. Al vencer (o con mult 1) todo vuelve a 1 en el proximo refresco.
function B.pitchRequest(key, mult, ms, wobble, hz)
  if key == nil then return end
  if not mult or math.abs(mult - 1) < 0.001 or (ms or 0) <= 0 then B.requests[key] = nil; return end
  local now = S.realMs()
  B.requests[key] = { mult = mult, untilMs = now + ms, wobble = wobble or 0, hz = hz or 0.3, t0 = now }
end

-- Producto de los pedidos vigentes en ese instante (1 sin pedidos). Los vencidos se borran.
function B.requestMult(now)
  local m, gone = 1, nil
  for k, r in pairs(B.requests) do
    if now >= r.untilMs then gone = gone or {}; gone[#gone + 1] = k
    else m = m * (r.mult + r.wobble * math.sin((now - r.t0) / 1000 * 2 * math.pi * r.hz)) end
  end
  for _, k in ipairs(gone or {}) do B.requests[k] = nil end
  return m
end

-- Los personajes que oye un pedido: zombis a Radius casillas de un jugador local (hasta Max) y todos los jugadores (locales y, en MP, los demas).
function B.nearby()
  local R = CFG.FX.Request or {}
  local out, n = {}, 0
  local locals = {}
  for i = 0, 3 do
    local p = getSpecificPlayer(i)
    if p then locals[#locals + 1] = p; out[#out + 1] = p end
  end
  pcall(function()
    local list = getOnlinePlayers and getOnlinePlayers()
    for i = 0, (list and list:size() or 0) - 1 do
      local p = list:get(i)
      if p and not p:isLocalPlayer() then out[#out + 1] = p end
    end
  end)
  pcall(function()
    local zl = getCell() and getCell():getZombieList()
    local r2 = (R.Radius or 18) ^ 2
    for i = 0, (zl and zl:size() or 0) - 1 do
      local z = zl:get(i)
      if z and not z:isDead() then
        for _, p in ipairs(locals) do
          local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
          if dx * dx + dy * dy <= r2 then
            out[#out + 1] = z
            n = n + 1
            break
          end
        end
        if n >= (R.Max or 40) then return end
      end
    end
  end)
  return out
end

-- Tono buscado por zombi. Los que se sueltan van de su factor a 1 en SlowRelease.Ms, como su velocidad.
-- (181) Encima, el pedido generico (B.reqMult, calculado en el refresco): multiplica a los frenados y llega a los demas cercanos.
function B.wanted(now)
  local want = {}
  local m = B.reqMult or 1
  if math.abs(m - 1) > 0.001 then
    for _, chr in ipairs(B.nearby()) do want[chr] = m end
  end
  if not voicesOn() then return want end
  for z, info in pairs(SD.slowed) do
    local p = SD.pitchFor(info.factor)
    if p < 0.999 then want[z] = p * m end
  end
  local ms = (CFG.SlowRelease and CFG.SlowRelease.Ms) or 500
  for z, info in pairs(SD.releasing or {}) do
    if not want[z] and info.factor then
      local t = info.relAt and math.max(0, math.min(1, (now - info.relAt) / ms)) or 1
      local p = SD.pitchFor(info.factor + (1 - info.factor) * t)
      if p < 0.999 then want[z] = p * m end
    end
  end
  for z in pairs(SD.zHolds or {}) do
    if not want[z] and B.pitched[z] then want[z] = B.pitched[z] end
  end
  return want
end

function B.tick()
  local j = fx()
  if not j then return end
  local now = S.realMs()
  local P = CFG.FX
  local f = SD.precipFactor()
  if f ~= B.precip then
    B.precip = f
    S.try("fxPrecip", function() j.precip(f, P.Precip.RampMs) end)
  end
  local a = SD.ambiencePitch() * (B.reqMult or 1)            -- (181) el pedido generico tambien al ambiente
  if a ~= B.ambience and j.ambience then
    B.ambience = a
    S.try("fxAmbience", function() j.ambience(a, P.Precip.RampMs) end)
  end
  if now - B.lastMs < (P.Pitch.RefreshMs or 100) then return end
  B.lastMs = now
  B.reqMult = B.requestMult(now)                            -- (181) una vez por refresco (el ambiente lo toma en el proximo tick)
  if B.pitchOk == nil then
    local ok, v = pcall(j.pitchAvailable)
    B.pitchOk = ok and v == true
    if not B.pitchOk then S.log("SandevistanFX: sin cambio de tono (" .. tostring(B.status()) .. ")") end
  end
  if not B.pitchOk then return end
  if j.ambienceTick then pcall(j.ambienceTick) end          -- (134b) rampa del tono del ambiente (lluvia, viento)
  local want = B.wanted(now)
  for z, p in pairs(want) do pcall(j.pitch, z, p) end
  for z in pairs(B.pitched) do
    if not want[z] then pcall(j.pitch, z, 1) end
  end
  B.pitched = want
end

function B.status()
  local j = fx()
  if not j then return "el jar no esta cargado (ZombieBuddy no lo aprobo o no esta activo)" end
  local ok, s = pcall(function() return tostring(j.status()) .. " | " .. tostring(j.stats()) end)
  return ok and s or ("error: " .. tostring(s))
end

-- Sonda desde la consola de Lua: SandevistanFXBridge.probe(zombi) lista los eventos de FMOD del zombi con su tono actual.
function B.probe(z) local j = fx(); return j and tostring(j.probe(z)) or "sin jar" end

Events.OnTick.Add(S.safe("SandevistanFX.OnTick", B.tick))

S.log("SandevistanFX: puente cargado (" .. (fx() and "jar presente" or "jar ausente") .. ")")

return B
