-- Sandevistan / Psychosis: cyberpsicosis por etapas (v0.1.28). Reemplaza a los zombis fantasma 2D.
--   Etapa 1 (CN >= Stage1CN): tics: susurros y pasos lejanos, terrores nocturnos, avisos del monitor neural.
--   Etapa 2 (cyberpsicosis activa): inestabilidad temporal, sentido de peligro (zombis reales que no ves, y de a ratos una marca fantasma a tu espalda), audio completo.
--   Etapa 3 (CN >= Stage3CN): reflejo descontrolado, apagones/visión de túnel, furia cibernética (recompensa).
-- Todo es local del jugador (sin efecto en el mundo salvo el reflejo descontrolado y la furia, que tocan al propio jugador) y cada
-- sistema se apaga con Config.Psychosis.<Sistema>.Enabled (opciones de sandbox). Los sonidos NO llaman a addSound: no atraen zombis.
-- Todo lo que toca API dudosa se comprueba antes de llamar (el depurador con "Break On Error" se detiene aun con pcall).
require "Sandevistan/Core"
require "Sandevistan/Viewport"
require "Sandevistan/Effects"
require "Sandevistan/Runtime"
require "Sandevistan/Slowdown"

local CFG = SandevistanConfig
local S = Sandevistan
local E = SandevistanEffects
local R = SandevistanRuntime
local SD = SandevistanSlowdown
local FW = SandevistanFirmware

SandevistanPsychosis = { state = {}, toasts = {}, threats = {}, phantoms = {}, lastRefreshMs = 0, soundCache = {}, lastPlayed = {} }
local P = SandevistanPsychosis

local function PC() return CFG.Psychosis end

local function has(obj, name)
  if obj == nil then return false end
  local ok, f = pcall(function() return obj[name] end)
  return ok and f ~= nil
end

local function lerp(a, b, t) return a + (b - a) * t end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function rnd(a, b) return lerp(a, b, ZombRandFloat(0, 1)) end

local function option(id, default)
  if SandevistanInput and SandevistanInput.getOption then return SandevistanInput.getOption(id, default) end
  return default
end

---------------------------------------------------------------------------
-- Etapas e intensidad
---------------------------------------------------------------------------
-- 0 = nada, 1 = tics, 2 = cyberpsicosis activa, 3 = crítica.
function P.stage(d)
  local cn = d.neuralLoad or 0
  local c = PC()
  local off = S.scarOffset(d)                                            -- (178) C05: la cicatriz neural acumulativa baja los umbrales
  local stage1, stage3 = c.Stage1CN - off, c.Stage3CN - off
  if cn >= stage3 then return 3 end
  if d.cyberpsychosisActive and cn >= stage1 then return 2 end       -- en remisión (CN < 60) los síntomas de etapa 2 se apagan
  if cn >= stage1 then return 1 end
  return 0
end

-- 0..1 entre Stage1CN (con la cicatriz restada) y 100.
function P.intensity(d)
  local c = PC()
  local stage1 = c.Stage1CN - S.scarOffset(d)
  return clamp(((d.neuralLoad or 0) - stage1) / math.max(1, 100 - stage1), 0, 1)
end

---------------------------------------------------------------------------
-- (176) C05: presion psicotica (26 §3 con 27 §4.1; Config.Psychosis.Pressure). Sale del contexto (cansancio, zombis cerca, dolor), no de la
-- CN, y multiplica la frecuencia de las alucinaciones. Vive en st (no se guarda: al cargar se recalcula).
---------------------------------------------------------------------------
-- Zombis vivos a menos de radius casillas (los titeres de las alucinaciones no estan en la lista del juego; los jugadores no cuentan).
function P.zombiesNear(player, radius, cap)
  local n = 0
  pcall(function()
    local cell = getCell()
    local zl = cell and cell:getZombieList()
    if not zl then return end
    local r2 = radius * radius
    local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ())
    for i = 0, zl:size() - 1 do
      local z = zl:get(i)
      if z and not z:isDead() and math.abs(math.floor(z:getZ()) - pz) <= 1 then
        local dx, dy = z:getX() - px, z:getY() - py
        if dx * dx + dy * dy <= r2 then
          n = n + 1
          if cap and n >= cap then return end
        end
      end
    end
  end)
  return n
end

-- Los factores, cada uno 0..1.
function P.pressureFactors(player, d)
  local c = PC().Pressure
  local f = {}
  f.fatigue = clamp(E.getStat(player, "FATIGUE") or 0, 0, 1)
  f.pain = clamp((E.getStat(player, "PAIN") or 0) / 100, 0, 1)
  f.crowd = clamp(P.zombiesNear(player, c.CrowdRadius or 10, c.CrowdMax or 12) / math.max(1, c.CrowdMax or 12), 0, 1)
  -- (180) C06: el Heat suma desde el 70 % del tope y crece en linea recta hasta el tope (el tope ya incluye la cicatriz termica)
  local cap = S.heatCap(d) or 100
  f.heat = clamp(((d.heat or 0) / math.max(1, cap) - 0.7) / 0.3, 0, 1)
  return f
end

-- Promedio pesado de los factores (los pesos se renormalizan: con todo al tope da 1).
function P.pressureValue(f)
  local w = PC().Pressure.Weights
  local sum, total = 0, 0
  for k, key in pairs({ fatigue = "Fatigue", crowd = "Crowd", pain = "Pain", heat = "Heat" }) do
    local wk = w[key] or 0
    if wk > 0 then sum = sum + wk * (f[k] or 0); total = total + wk end
  end
  if total <= 0 then return 0 end
  return clamp(sum / total, 0, 1)
end

-- Cada RefreshMs: recalcula, suaviza hacia el valor nuevo y avisa al pasar a alta. Sin la etapa 1 (o apagada) queda en 0.
function P.pressureTick(player, d, st, now)
  local c = PC().Pressure
  if now < (st.pressureNextMs or 0) then return end
  local last = st.pressureAtMs or now
  st.pressureNextMs, st.pressureAtMs = now + (c.RefreshMs or 1000), now
  local target, f = 0, nil
  if c.Enabled and P.stage(d) >= 1 then
    f = P.pressureFactors(player, d)
    target = P.pressureValue(f)
    local AN = rawget(_G, "SandevistanAnchors")                  -- (179) un ancla de humanidad baja la presion un rato
    if AN and AN.discount then target = math.max(0, target - AN.discount(st)) end
  end
  if st.pressureForced and now < st.pressureForced.untilMs then target = st.pressureForced.value
  else st.pressureForced = nil end
  local v = st.pressure or 0
  local k = clamp((now - last) / 1000 / math.max(0.1, c.SmoothSeconds or 6), 0, 1)
  if st.pressure == nil then k = 1 end
  v = v + (target - v) * k
  if math.abs(v - target) < 0.005 then v = target end              -- sin colas eternas del suavizado
  st.pressure, st.pressureFactors = v, f
  st.pressureMult = (c.Enabled and v > 0) and (1 + v * (c.Strength or 0.5)) or 1
  local lvl = P.pressureLevel(st)
  if lvl == "high" and st.pressureLastLevel ~= "high" and now >= (st.pressureToastMs or 0) then
    st.pressureToastMs = now + (c.ToastCooldownSeconds or 300) * 1000
    P.toast(getText("IGUI_Sandevistan_Mon_PressureHigh"), "warn")
  end
  st.pressureLastLevel = lvl
end

-- "low" / "mid" / "high" (nil sin presion calculada).
function P.pressureLevel(st)
  if not st or st.pressure == nil then return nil end
  local c = PC().Pressure
  if st.pressure >= (c.High or 0.66) then return "high" end
  if st.pressure >= (c.Mid or 0.33) then return "mid" end
  return "low"
end

-- Multiplicador de frecuencia de las alucinaciones: el de siempre (antidepresivos, firmware, desconexion, intensidad) por la presion.
-- st = P.st(player); sin st, el del jugador 0 (el HUD). (177) kind = la clase del sistema ("Audio", "FakeZombies", ...): el episodio de
-- crisis en curso la multiplica (Crisis.lua, Config.Psychosis.Crisis.Types[...].Mult).
function P.freqMult(d, st, kind)
  st = st or P.state[0]
  local m = S.symptomMultiplier(d) * ((st and st.pressureMult) or 1)
  local CR = rawget(_G, "SandevistanCrisis")
  if kind and CR and st then m = m * CR.mult(st, kind) end
  return m
end

-- (Debug) Fuerza la presion a value por seconds segundos (nil = vuelve a la real).
function P.forcePressure(player, value, seconds)
  local st = P.st(player)
  st.pressureForced = value and { value = value, untilMs = S.realMs() + (seconds or 60) * 1000 } or nil
  st.pressureNextMs, st.pressure = 0, value or st.pressure
end

function P.pressureStatus(player)
  local st = P.st(player)
  local f = st.pressureFactors or {}
  return string.format("presion: %.2f (%s) x%.2f | cansancio %.2f, zombis %.2f, dolor %.2f, heat %.2f%s", st.pressure or 0, tostring(P.pressureLevel(st)),
    st.pressureMult or 1, f.fatigue or 0, f.crowd or 0, f.pain or 0, f.heat or 0, st.pressureForced and " [forzada]" or "")
end

function P.st(player)
  local idx = player:getPlayerNum()
  local st = P.state[idx]
  if not st then
    local now = S.realMs()
    st = { stage = 0, nextAudioMs = now + 15000, nextToastMs = now + 30000, glitchCooldownMs = 0, misfireCooldownMs = 0,
           nextThreatCheckMs = 0, nextPhantomMs = now + 20000, nextBlackoutMs = now + 60000, queue = {}, lastBerserkMs = 0, sleepSince = nil }
    P.state[idx] = st
  end
  return st
end

function P.reset(idx) P.state[idx] = nil end

---------------------------------------------------------------------------
-- Sonidos: roles -> nombre de sonido (vanilla si existe, propio si no)
---------------------------------------------------------------------------
local function soundKnown(name)
  local known = nil
  pcall(function()
    local sm = getScriptManager and getScriptManager()
    if sm and has(sm, "getGameSound") then known = sm:getGameSound(name) ~= nil end
  end)
  return known
end

P.soundKnown = soundKnown                      -- (172) lo usa la voz de los zombis falsos (la mordida de la misma voz)

-- (140) Genero de una voz vanilla: "MaleZombieVoiceA" -> false, "FemaleZombieBiteB" -> true, nil si no es una voz (pasos, mordida foley).
local function voiceGender(name)
  if string.sub(name, 1, 6) == "Female" then return true end
  if string.sub(name, 1, 4) == "Male" then return false end
  return nil
end

-- Elige el sonido de un rol: candidatos vanilla que existan (al azar) y, si no hay, el propio. (140) female filtra las voces del mismo sexo
-- que el zombi falso (los sonidos sin sexo valen para los dos); si el rol no tiene voces de ese sexo, quedan todas.
function P.resolve(role, female)
  local def = PC().Audio.Roles[role]
  if not def then return nil end
  local key = role .. (female == nil and "" or (female and "|f" or "|m"))
  local cache = P.soundCache[key]
  if cache == nil then
    cache = { vanilla = {}, own = {} }
    for _, n in ipairs(def.candidates or {}) do
      if soundKnown(n) and (female == nil or voiceGender(n) == nil or voiceGender(n) == female) then
        cache.vanilla[#cache.vanilla + 1] = n
      end
    end
    if female ~= nil and #cache.vanilla == 0 then                 -- no hay voces de ese sexo en el rol: valen todas
      for _, n in ipairs(def.candidates or {}) do if soundKnown(n) then cache.vanilla[#cache.vanilla + 1] = n end end
    end
    local own = def.fallback
    if type(own) == "string" then own = { own } end
    for _, n in ipairs(own or {}) do if soundKnown(n) ~= false then cache.own[#cache.own + 1] = n end end
    P.soundCache[key] = cache
  end
  local list = (#cache.vanilla > 0) and cache.vanilla or cache.own
  if #list == 0 then return nil end
  local i = ZombRand(#list) + 1
  if #list > 1 and list[i] == cache.last then                     -- (153) no repetir el ultimo: se sortea entre los demas
    i = ZombRand(#list - 1) + 1
    if list[i] == cache.last then i = #list end
  end
  cache.last = list[i]
  return list[i]
end

-- (187) Solo lo oye este cliente (E.privateAt): hasta la 186 iba con playSound y en multijugador lo oian los que estaban cerca.
function P.playAt(name, x, y, z, vol)
  if not name then return nil end
  local id, em = E.privateAt(name, x, y, z, vol)
  if em then P.lastEmitter = em end
  return id
end

-- Reproduce un rol en una posición del mundo (o sin posición, en el oído del jugador). female (140) elige la voz del mismo sexo.
function P.play(player, role, x, y, z, vol, female)
  if CFG.Sound and CFG.Sound.Enabled == false then return nil end
  local name = P.resolve(role, female)
  if not name then return nil end
  P.lastPlayed[role] = name
  local def = PC().Audio.Roles[role]
  vol = (vol or 1) * (PC().Audio.Volume or 1)
  if def.VolumeJitter then vol = vol * (1 - rnd(0, def.VolumeJitter)) end      -- (153) cada toque un poco distinto
  local id = nil
  P.lastEmitter = nil
  if x then id = P.playAt(name, x, y, z or player:getZ(), vol) end
  if id == nil then id = E.sound(player, name, vol, true); P.lastEmitter = E.lastEmitter end          -- (187) solo este cliente
  -- setPitch solo vale en sonidos de archivo (los glitch lo son) y con un id del emisor. (153b) Con el personaje invisible (modo admin/debug) el emisor
  -- no suena y E.sound devuelve el FMODAudio del respaldo, que no tiene tono: pasarselo a setPitch daba "expected argument of type long".
  if def.Pitch and type(id) == "number" and id ~= 0 and P.lastEmitter then
    local pitch = rnd(1 - def.Pitch, 1 + def.Pitch)
    pcall(function() P.lastEmitter:setPitch(id, pitch) end)
  end
  return id
end

-- (140) Audio de la cyberpsicosis habilitado: la opcion de sandbox PsychosisAudio y el interruptor del mod. Lo consultan los zombis falsos
-- antes de sonar (asi apagar las alucinaciones de audio tambien deja mudos a los titeres).
function P.audioOn()
  local A = PC().Audio
  if A and A.Enabled == false then return false end
  return not (CFG.Sound and CFG.Sound.Enabled == false)
end

-- (171) C02: parametros de FMOD del ultimo sonido de P.play (FootstepMaterial, CharacterMovementSpeed, PlayerDistance). Verificado en 42.21:
-- BaseSoundEmitter.setParameterValueByName(long, String, float), el mismo que usa vanilla para CharacterVoicePitch. Si el evento no usa el
-- parametro no pasa nada (la descripcion da null y vuelve), y si el evento todavia no arranco el emisor guarda el valor para cuando arranque.
function P.setParams(id, params)
  local em = P.lastEmitter
  if not (em and params and type(id) == "number" and id ~= 0) then return end
  for name, v in pairs(params) do pcall(function() em:setParameterValueByName(id, name, v) end) end
end

-- (171) C02: el piso de una casilla como lo calcula el juego para los pasos (ParameterFootstepMaterial.getMaterial, 42.21): nieve; si no, la
-- propiedad FootstepMaterial del ultimo objeto de la casilla que la tenga (sin contar los items tirados); si no hay, madera en una escalera y
-- concreto en lo demas. Los numeros son los del enum del juego (los mismos del panel de FMOD de Debug).
P.FOOTSTEP = { Upstairs = 0, BrokenGlass = 1, Concrete = 2, Grass = 3, Gravel = 4, Puddle = 5, Snow = 6, Wood = 7, Carpet = 8, Dirt = 9,
               Sand = 10, Ceramic = 11, Metal = 12 }
function P.footstepMaterial(x, y, z)
  local M = P.FOOTSTEP
  local mat = M.Concrete
  pcall(function()
    local cell = getCell()
    local ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    local sq = cell and cell:getGridSquare(ix, iy, iz)
    if not sq then return end
    if cell:gridSquareIsSnow(ix, iy, iz) then mat = M.Snow; return end
    local objs = sq:getObjects()
    local found, stairs = nil, false
    for i = 0, objs:size() - 1 do
      local o = objs:get(i)
      if o and not instanceof(o, "IsoWorldInventoryObject") then
        local pr = o:getProperties()
        if pr then
          if o:isStairsObject() then stairs = true end
          if pr:has("FootstepMaterial") then found = pr end
        end
      end
    end
    local name = found and found:get("FootstepMaterial")
    if name and M[name] then mat = M[name] elseif stairs then mat = M.Wood end
  end)
  return mat
end

-- Posición al azar entre minR y maxR tiles; prefiere casillas cargadas que el jugador no ve. behind = dirección opuesta al rumbo
-- (con un giro al azar de hasta ~40 grados; sin atan2: se rota el vector).
function P.pickPos(player, minR, maxR, behind)
  local px, py, pz = player:getX(), player:getY(), player:getZ()
  local vx, vy = nil, nil
  if behind then
    pcall(function()
      if has(player, "getForwardDirectionX") then
        local fx, fy = player:getForwardDirectionX(), player:getForwardDirectionY()
        if fx and fy and (fx ~= 0 or fy ~= 0) then
          local len = math.sqrt(fx * fx + fy * fy)
          vx, vy = -fx / len, -fy / len
        end
      end
    end)
  end
  local bx, by = px, py
  for _ = 1, 8 do
    local dx, dy
    if vx then
      local th = ZombRandFloat(-0.7, 0.7)
      local c, sn = math.cos(th), math.sin(th)
      dx, dy = vx * c - vy * sn, vx * sn + vy * c
    else
      local ang = ZombRandFloat(0, 6.2831)
      dx, dy = math.cos(ang), math.sin(ang)
    end
    local r = rnd(minR, maxR)
    bx, by = px + dx * r, py + dy * r
    local ok, unseen = pcall(function()
      local cell = getCell()
      local sq = cell and cell:getGridSquare(math.floor(bx), math.floor(by), math.floor(pz))
      if not sq then return false end
      if has(sq, "isCouldSee") then return sq:isCouldSee(player:getPlayerNum()) ~= true end
      return true
    end)
    if ok and unseen then return bx, by, pz end
  end
  return bx, by, pz
end

---------------------------------------------------------------------------
-- (138) Texto corrupto: lo hace el mod opcional SandevistanPsychosis (Java: cambia letras por simbolos en todo el texto que dibuja el juego).
-- P.textBackend = function(amount 0..1, ms) lo pone SandevistanPsychosis/Bridge.lua; sin ese mod, nada. Necesita tambien "Alucinaciones".
---------------------------------------------------------------------------
P.textBackend = nil
P.textEpisodes = 0

function P.textGlitchOn()
  local c = PC().TextGlitch
  return c ~= nil and c.Enabled and P.textBackend ~= nil and CFG.NeuralLoad.Hallucinations ~= false
end

function P.textGlitch(amount, ms, messages)
  if not P.textGlitchOn() or not amount or amount <= 0 then return false end
  local ok = pcall(P.textBackend, amount, ms, messages)
  if not ok and messages then ok = pcall(P.textBackend, amount, ms) end     -- jar viejo: sin frases
  if ok then P.textEpisodes = P.textEpisodes + 1 end
  return ok
end

---------------------------------------------------------------------------
-- (192) Mensajes alucinados: la frase se incrusta en un texto que ya se esta corrompiendo
-- (etiqueta, tooltip, chat...). No hay una capa aparte: el jar reemplaza una ventana del texto.
---------------------------------------------------------------------------
function P.messageKey(i) return "IGUI_Sandevistan_PsyMessage" .. tostring(i) end

function P.messageList(force)
  local c = PC().Messages
  if not c or (not force and not c.Enabled) then return nil end
  local count = math.max(1, math.floor(c.Count or 8))
  local list = {}
  for i = 1, count do list[#list + 1] = getText(P.messageKey(i)) end
  return table.concat(list, "\n")
end

function P.messageFor(d, st, now)
  local c = PC().Messages
  if not c or not c.Enabled or not P.textGlitchOn() then return nil end
  if P.stage(d) < (c.MinStage or 2) then return nil end
  if not st.nextMessageMs then st.nextMessageMs = now + (c.FirstDelaySeconds or 120) * 1000 end
  if now < st.nextMessageMs then return nil end
  if ZombRandFloat(0, 1) >= (c.Chance or 0.04) then return nil end
  st.nextMessageMs = now + (c.CooldownSeconds or 600) * 1000
  return P.messageList()
end

-- Debug: fuerza un episodio de texto con frases. Solo se ve si hay un texto elegible en pantalla
-- (inventario, tooltip, chat, guia); no dibuja nada por su cuenta.
function P.forceMessage(player, ms)
  local list = P.messageList(true)
  if not list then return false end
  return P.textGlitch(0.45, ms or 3000, list)
end

function P.textTick(player, d, st, now)
  local c = PC().TextGlitch
  if not P.textGlitchOn() or not d.cyberpsychosisActive or P.stage(d) < (c.MinStage or 2) or player:isAsleep() then return end
  if not st.nextTextMs then st.nextTextMs = now + c.FirstDelaySeconds * 1000 end
  if now < st.nextTextMs then return end
  local every = lerp(c.EverySeconds[2], c.EverySeconds[1], P.intensity(d)) / math.max(0.2, P.freqMult(d, st, "TextGlitch")) / S.halluMultiplier(d)          -- (180) Filtro
  st.nextTextMs = now + every * 1000 * rnd(0.6, 1.4)
  local messages = P.messageFor(d, st, now)
  local seconds = rnd(c.Seconds[1], c.Seconds[2])
  if messages then seconds = math.max(seconds, (PC().Messages.Seconds or 2.2)) end          -- (193) la frase se lee: el episodio dura al menos 2,2 s
  P.textGlitch(lerp(c.Amount[1], c.Amount[2], P.intensity(d)), seconds * 1000, messages)
end

-- (181) C13.3 Sacudida de camara de un evento (ScreenFX.lua; la hace el jar de SandevistanPsychosis, solo en isometrico).
function P.shake(player, kind)
  local SFX = rawget(_G, "SandevistanScreenFX")
  if SFX then pcall(SFX.shake, player, kind) end
end

local function schedule(st, delayMs, fn) st.queue[#st.queue + 1] = { at = S.realMs() + delayMs, fn = fn } end

-- Eventos de audio ---------------------------------------------------------------------------------------------------
local AUDIO = {}

function AUDIO.footsteps(player, st)      -- pasos que se acercan por detrás
  local n = 4 + ZombRand(4)
  local x0, y0, z0 = P.pickPos(player, 6, 9, true)
  for i = 1, n do
    schedule(st, (i - 1) * rnd(380, 520), function()
      local f = (i - 1) / math.max(1, n - 1)
      local px, py = player:getX(), player:getY()
      P.play(player, "footstep", lerp(x0, px + (x0 - px) * 0.25, f), lerp(y0, py + (y0 - py) * 0.25, f), z0, 0.9)
    end)
  end
end

function AUDIO.footstepFar(player, st)
  local x, y, z = P.pickPos(player, 9, 14, false)
  P.play(player, "footstep", x, y, z, 0.6)
  schedule(st, 480, function() P.play(player, "footstep", x, y, z, 0.6) end)
end

function AUDIO.groan(player) local x, y, z = P.pickPos(player, 9, 15, false); P.play(player, "groan", x, y, z, 0.9) end
function AUDIO.bang(player) local x, y, z = P.pickPos(player, 6, 12, false); P.play(player, "bang", x, y, z, 1.0) end
function AUDIO.glass(player) local x, y, z = P.pickPos(player, 8, 14, false); P.play(player, "glass", x, y, z, 1.0) end
function AUDIO.whisper(player)
  local a = ZombRandFloat(0, 6.2831)
  P.play(player, "whisper", player:getX() + math.cos(a) * 1.2, player:getY() + math.sin(a) * 1.2, player:getZ(), 0.55)
end
function AUDIO.heartbeat(player, st)
  for i = 0, 2 do schedule(st, i * 850, function() P.play(player, "heartbeat", nil, nil, nil, 0.9) end) end
end
-- El tinnitus es un tono agudo: el clip ya suena a 0.5 en el script (Sandevistan_sounds.txt); acá solo aplica el volumen general.
function AUDIO.tinnitus(player) P.play(player, "tinnitus", nil, nil, nil, 1.0) end

local WEIGHTS = {
  [1] = { { "whisper", 5 }, { "footstepFar", 2 }, { "tinnitus", 1 } },
  [2] = { { "footsteps", 4 }, { "groan", 3 }, { "bang", 2 }, { "glass", 1 }, { "whisper", 3 }, { "footstepFar", 1 } },
  [3] = { { "footsteps", 4 }, { "groan", 3 }, { "bang", 2 }, { "glass", 1 }, { "whisper", 4 }, { "heartbeat", 2 }, { "tinnitus", 2 } },
}

local function pickEvent(stage)
  local list = WEIGHTS[stage]
  if not list then return nil end
  local total = 0
  for _, e in ipairs(list) do total = total + e[2] end
  local r = ZombRand(total * 100) / 100
  for _, e in ipairs(list) do
    r = r - e[2]
    if r < 0 then return e[1] end
  end
  return list[1][1]
end

function P.audioTick(player, d, st, now)
  local c = PC().Audio
  if not c.Enabled or player:isAsleep() or st.stage < 1 or now < st.nextAudioMs then return end
  local intensity = P.intensity(d)
  local every = lerp(c.EverySeconds[1], c.EverySeconds[2], intensity)
  if st.stage >= 2 then every = every * 0.6 end
  every = every / math.max(0.2, P.freqMult(d, st, "Audio"))                 -- antidepresivos: más espaciado; (176) presión: más seguido
  st.nextAudioMs = now + every * 1000 * rnd(0.6, 1.4)
  local ev = pickEvent(st.stage)
  if ev and AUDIO[ev] then
    st.lastAudio = ev
    local ok, err = pcall(AUDIO[ev], player, st)
    if not ok then S.warnOnce("psyAudio_" .. tostring(ev), "audio de cyberpsicosis '" .. tostring(ev) .. "' falló: " .. tostring(err)) end
  end
end

---------------------------------------------------------------------------
-- Monitor neural (avisos estilo HUD)
---------------------------------------------------------------------------
function P.toast(text, kind)
  local m = PC().Monitor
  if not m.Enabled or not option("neuralMonitor", true) or not text then return end
  local now = S.realMs()
  P.toasts[#P.toasts + 1] = { text = text, kind = kind or "warn", bornMs = now, seed = ZombRand(1000) }
  while #P.toasts > (m.MaxToasts or 3) do table.remove(P.toasts, 1) end
end

local STAGE_TEXT = { [1] = "IGUI_Sandevistan_Mon_Unstable", [2] = "IGUI_Sandevistan_Mon_Cyberpsychosis", [3] = "IGUI_Sandevistan_Mon_Critical" }

function P.monitorTick(player, d, st, now)
  if d.disconnected then return end                          -- (165) T12: el monitor es el implante
  local m = PC().Monitor
  if st.stage ~= st.lastStage then
    if st.stage > (st.lastStage or 0) then
      P.toast(getText(STAGE_TEXT[st.stage]), st.stage >= 2 and "crit" or "warn")
    elseif st.stage == 0 and (st.lastStage or 0) > 0 then
      P.toast(getText("IGUI_Sandevistan_Mon_Recovered"), "ok")
    end
    st.lastStage = st.stage
  end
  if st.stage >= 1 and now >= st.nextToastMs then
    st.nextToastMs = now + rnd(m.RandomEverySeconds[1], m.RandomEverySeconds[2]) * 1000
    local human = math.max(0, math.min(99, math.floor(100 - (d.neuralLoad or 0))))
    P.toast(getText("IGUI_Sandevistan_Mon_Humanity", human), st.stage >= 2 and "crit" or "warn")
  end
end

---------------------------------------------------------------------------
-- Inestabilidad temporal
---------------------------------------------------------------------------
function P.glitchTick(player, s, d, st, now, dt)
  local c = PC().TimeGlitch
  if not c.Enabled or not s.active or not d.cyberpsychosisActive or now < st.glitchCooldownMs then return end
  local intensity = P.intensity(d)
  if intensity <= 0 then return end
  local chance = lerp(c.ChancePerSecond.min, c.ChancePerSecond.max, intensity)
  if not S.chance(chance * dt) then return end
  local dur = rnd(c.DurationMs[1], c.DurationMs[2])
  SD.glitchUntil = SD.glitchUntil or {}
  SD.glitchUntil[player:getPlayerNum()] = now + dur
  st.glitchCooldownMs = now + dur + c.CooldownSeconds * 1000
  if SandevistanHUD and SandevistanHUD.forceGlitch then SandevistanHUD.forceGlitch(dur) end
  P.textGlitch(PC().TextGlitch.OnTimeGlitch, dur)                 -- (138)
  local SFX = rawget(_G, "SandevistanScreenFX")                   -- (181) C13.5: el mundo tambien falla un instante
  if SFX then SFX.burst(player, dur) end
  P.play(player, "glitch", nil, nil, nil, 0.8)
  if now - (st.lastGlitchToastMs or -100000) > 15000 then
    st.lastGlitchToastMs = now
    P.toast(getText("IGUI_Sandevistan_Mon_TimeGlitch"), "crit")
  end
end

---------------------------------------------------------------------------
-- Reflejo descontrolado
---------------------------------------------------------------------------
local function zombieAttacking(player, radius)
  local found = false
  pcall(function()
    local cell = getCell()
    local zl = cell and cell:getZombieList()
    if not zl then return end
    local r2 = radius * radius
    local px, py = player:getX(), player:getY()
    for i = 0, zl:size() - 1 do
      local z = zl:get(i)
      if z and not z:isDead() then
        local dx, dy = z:getX() - px, z:getY() - py
        if dx * dx + dy * dy <= r2 then
          local attacking = false
          if has(z, "isAttacking") then attacking = z:isAttacking() == true end
          if not attacking and has(z, "getTarget") then attacking = z:getTarget() == player end
          if attacking then found = true; return end
        end
      end
    end
  end)
  return found
end
P.zombieAttacking = zombieAttacking

function P.misfireTick(player, s, d, st, now)
  local c = PC().Misfire
  -- fin del disparo involuntario
  if s.active and s.misfireUntilMs and now >= s.misfireUntilMs then
    s.misfireUntilMs = nil
    if not s.armed and not s.overdrive then
      R.deactivate(player, "manual")
      if SandevistanInput then SandevistanInput.state = "IDLE" end
    end
  end
  if not c.Enabled or st.stage < 3 or s.active or not S.hasWorkingImplant(d) then return end
  if now < st.misfireCooldownMs or now < st.nextThreatCheckMs then return end
  st.nextThreatCheckMs = now + 200
  if not zombieAttacking(player, c.RadiusTiles) then return end
  if not S.chance(c.ChancePerSecond * 0.2) then return end
  local ok = R.canActivate(player)
  if not ok then return end
  if R.activate(player) then
    s.misfireUntilMs = now + rnd(c.Seconds[1], c.Seconds[2]) * 1000
    st.misfireCooldownMs = now + c.CooldownSeconds * 1000
    d.rejection = math.min(100, (d.rejection or 0) + c.RejectionCost)
    if SandevistanInput then SandevistanInput.state = "ACTIVE" end
    P.toast(getText("IGUI_Sandevistan_Mon_Misfire"), "crit")
  end
end

---------------------------------------------------------------------------
-- Apagones y visión de túnel
---------------------------------------------------------------------------
-- fases: "tunnel" -> ("black" ->) fin. st.bo = { phase, t0, dur, blackDur }
function P.blackoutTick(player, s, d, st, now)
  local c = PC().Blackouts
  local bo = st.bo
  if bo then
    local t = (now - bo.t0) / 1000
    if bo.phase == "tunnel" then
      if now >= (bo.nextBeat or 0) then bo.nextBeat = now + 850; P.play(player, "heartbeat", nil, nil, nil, 0.95) end
      if t >= c.TunnelSeconds then
        if bo.blackDur then
          bo.phase = "black"; bo.t0 = now; P.toast(getText("IGUI_Sandevistan_Mon_Blackout"), "crit")
          P.shake(player, "Blackout")                                                     -- (181) C13.3
          P.textGlitch(PC().TextGlitch.OnBlackout, bo.blackDur * 1000 + 600)          -- (138) al volver la vista, el texto todavia no se lee
          S.addIncident(player, d, { kind = "blackout", stage = P.stage(d), pressure = P.pressureLevel(st), secs = bo.blackDur })   -- (178) solo el apagon con negro
        else st.bo = nil end
      end
    elseif bo.phase == "black" then
      if t >= bo.blackDur + 0.5 then st.bo = nil end
    end
    return
  end
  if not c.Enabled or st.stage < 3 or now < st.nextBlackoutMs or player:isAsleep() then return end
  local cool = rnd(c.CooldownSeconds[1], c.CooldownSeconds[2]) / math.max(0.2, P.freqMult(d, st, "Blackouts"))
  st.nextBlackoutMs = now + cool * 1000
  st.bo = { phase = "tunnel", t0 = now, nextBeat = now,
            blackDur = S.chance(c.BlackoutChance) and rnd(c.BlackoutSeconds[1], c.BlackoutSeconds[2]) or nil }
end

-- Devuelve (viñeta 0..1, negro 0..1) para dibujar.
function P.blackoutLevels(player)
  local vig, black = P.blackoutLevelsRaw(player)
  local CR = rawget(_G, "SandevistanCrisis")                   -- (177) tunel suave de la antesala, la cascada y la disociacion
  if CR then vig = math.max(vig, CR.tunnel(player)) end
  return vig, black
end
function P.blackoutLevelsRaw(player)
  local st = P.state[player:getPlayerNum()]
  local bo = st and st.bo
  if not bo then return 0, 0 end
  local c = PC().Blackouts
  local t = (S.realMs() - bo.t0) / 1000
  if bo.phase == "tunnel" then
    local up = clamp(t / (c.TunnelSeconds * 0.6), 0, 1)
    local down = bo.blackDur and 1 or clamp((c.TunnelSeconds - t) / (c.TunnelSeconds * 0.3), 0, 1)
    return up * down, 0
  end
  local fadeIn, fadeOut = 0.15, 0.5
  if S.lessFlashes() then fadeIn = CFG.LessFlashes.BlackFadeIn or 0.5 end         -- (170) C01: el negro entra despacio, no de golpe
  local a = math.min(1, t / fadeIn)
  if t > bo.blackDur then a = clamp(1 - (t - bo.blackDur) / fadeOut, 0, 1) end
  return (t > bo.blackDur) and a or 1, a
end

---------------------------------------------------------------------------
-- Furia cibernética
---------------------------------------------------------------------------
function P.berserkTick(player, s, d, st, now)
  local c = PC().Berserk
  local forced = st.forceBerserkUntilMs and now < st.forceBerserkUntilMs        -- Debug: furia de prueba (desgaste del arma)
  local want = c.Enabled and s.active and (d.cyberpsychosisActive or forced) and not FW.profile(d).noBerserk and true or false          -- (83) Supresor: sin furia cibernetica
  if want ~= (s.berserk and true or false) then
    s.berserk = want
    if R.refreshTier then R.refreshTier(player, s) end
  end
  if want and now - st.lastBerserkMs >= 500 then
    st.lastBerserkMs = now
    if c.NoPanic and E.getStat(player, "PANIC") > 0 then E.setStat(player, "PANIC", 0) end
    local pain = E.getStat(player, "PAIN")
    if pain > 0 then E.setStat(player, "PAIN", pain * (1 - 0.1 * (1 - c.PainScale))) end
  end
end

---------------------------------------------------------------------------
-- Sobrecarga neural (CN al tope) y furia total
---------------------------------------------------------------------------
-- Furia total: el implante queda trabado encendido Seconds; al terminar, bajón.
function P.startFury(player, s, d, now)
  local F = PC().Overload.Fury
  if not s.active then
    d.lockUntilCool = false
    local cap = S.heatCap(d)
    if (d.heat or 0) >= cap then d.heat = cap * 0.9 end
    if not R.activate(player) then return false end            -- no se puede encender (rechazo alto, estamina...): cae al KO
  end
  s.armed, s.overdrive = false, false
  s.fury = { untilMs = now + F.Seconds * 1000 }
  if R.refreshTier then R.refreshTier(player, s) end
  E.halo(player, getText("IGUI_Sandevistan_Fury"), 255, 40, 40)
  P.toast(getText("IGUI_Sandevistan_Mon_Fury"), "crit")
  P.shake(player, "Fury")                                              -- (181) C13.3
  E.sound(player, "SandevistanOverdrive")
  return true
end

function P.endFury(player, s, d)
  local F = PC().Overload.Fury
  s.fury = nil
  if s.active then R.deactivate(player, "forced") end
  if R.refreshTier then R.refreshTier(player, s) end
  E.setEndurance(player, 0)
  if R.clearDebt then R.clearDebt(player) end           -- (139) fin de la furia: el cuerpo queda seco, la deuda se borra
  E.knockOut(player, F.CrashSeconds)
  P.st(player).wakePending = true                       -- (178) C05: el bajon de la furia tambien despierta alucinado
  local oldCap = S.heatCap(d)
  local cap = S.scarHeatCap(d, CFG.Overdrive.HeatCap.PerFury)
  d.heat, d.lockUntilCool, d.cooldownMult = cap, true, CFG.Overdrive.CoolingMultiplier
  local V = PC().Vulnerable
  if V and V.Enabled then d.vulnUntilHour = S.worldHours() + (V.Hours or 0.4) end     -- (180) C06: ventana vulnerable
  if cap < oldCap then E.halo(player, getText("IGUI_Sandevistan_HeatScar", math.floor(cap)), 255, 140, 60) end
  E.halo(player, getText("IGUI_Sandevistan_FuryEnd"), 255, 120, 80)
  P.toast(getText("IGUI_Sandevistan_Mon_FuryEnd"), "warn")
end

-- Mientras dura: el implante no se corta solo (Heat y estamina con piso) y termina si algo lo apaga a la fuerza.
function P.furyTick(player, s, d, now)
  local F = PC().Overload.Fury
  if not s.active then s.fury = nil; if R.refreshTier then R.refreshTier(player, s) end; return end
  if now >= s.fury.untilMs then P.endFury(player, s, d); return end
  local top = S.heatCap(d) * 0.95
  if (d.heat or 0) > top then d.heat = top end
  if E.getEndurance(player) < F.EnduranceFloor then E.setEndurance(player, F.EnduranceFloor) end
end

-- Convulsión: apagado forzado, KO, sangrado, dolor y un grito que atrae zombis.
function P.convulse(player, s, d)
  local c = PC().Overload
  if s.active then R.deactivate(player, "forced") end
  local sec = rnd(c.KOSeconds[1], c.KOSeconds[2]) * (S.antidepActive(d) and c.AntidepKOMultiplier or 1)
  E.knockOut(player, sec)
  E.startNosebleed(player, d)
  E.addPain(player, "Torso_Upper", c.Pain)
  E.scream(player, d)
  E.halo(player, getText("IGUI_Sandevistan_Overload"), 255, 40, 40)
  P.toast(getText("IGUI_Sandevistan_Mon_Overload"), "crit")
  P.shake(player, "Overload")                                          -- (181) C13.3
  E.sound(player, "SandevistanCollapse")
  P.st(player).wakePending = true                                      -- (178) C05: al volver del KO, pico alucinado
  return sec
end

-- La sobrecarga en sí: baja la CN a DropTo, suma la cicatriz, elige furia (chance) o KO y lo anota en la caja negra.
-- noFury = Debug: fuerza el KO (para probar el despertar alucinado sin esperar la furia).
function P.applyOverload(player, s, d, now, noFury)
  local c = PC().Overload
  local cnAt = d.neuralLoad or CFG.NeuralLoad.Max
  d.lastOverloadHour = S.worldHours()
  d.neuralLoad = c.DropTo
  local NS = CFG.NeuralLoad.NeuralScar
  S.addNeuralScar(player, d, (NS and NS.PerOverload) or 2)            -- (178) C05: cada sobrecarga deja cicatriz
  local st = P.st(player)
  if not noFury and d.cyberpsychosisActive and S.hasWorkingImplant(d) and S.chance(c.FuryChance) and P.startFury(player, s, d, now) then
    S.addIncident(player, d, { kind = "overload", cn = math.floor(cnAt + 0.5), stage = P.stage(d), pressure = P.pressureLevel(st),
                               secs = c.Fury.Seconds, fury = true })   -- (178) C05: caja negra
    S.log(string.format("sobrecarga (CN %.0f): furia total, cicatriz %d", cnAt, d.neuralScar or 0))
    R.checkThresholds(player)                                        -- la cicatriz puede adelantar la cyberpsicosis ya mismo
    return "fury"
  end
  local sec = P.convulse(player, s, d)
  S.addIncident(player, d, { kind = "overload", cn = math.floor(cnAt + 0.5), stage = P.stage(d), pressure = P.pressureLevel(st),
                             secs = sec })                             -- (178) C05: caja negra
  S.log(string.format("sobrecarga (CN %.0f): KO %d s, cicatriz %d", cnAt, math.floor((sec or 0) + 0.5), d.neuralScar or 0))
  R.checkThresholds(player)
  return "ko"
end

-- Debug: la sobrecarga ya, sin cascada y sin pausa. noFury = KO seguro (para ver el despertar alucinado).
function P.forceOverload(player, noFury)
  local d = S.data(player)
  local s = R.session(player)
  P.st(player).cascade = nil
  d.neuralLoad = CFG.NeuralLoad.Max
  d.lastOverloadHour = -1000
  P.applyOverload(player, s, d, S.realMs(), noFury == true)
end

-- Se dispara al tocar el tope: baja la CN a DropTo y elige convulsión o (con cyberpsicosis) una chance de furia total.
function P.overloadTick(player, s, d, now)
  local c = PC().Overload
  if not c.Enabled then return end
  if s.fury then P.furyTick(player, s, d, now); return end
  local CR = rawget(_G, "SandevistanCrisis")                   -- (177) antesala de la sobrecarga: apagar el implante a tiempo la evita
  if CR and CR.cascadeGate(player, s, d, P.st(player), now) then return end
  if (d.neuralLoad or 0) < CFG.NeuralLoad.Max - 1e-6 then return end
  local hours = S.worldHours()
  if hours - (d.lastOverloadHour or -1000) < c.CooldownHours then return end
  P.applyOverload(player, s, d, now)
end

---------------------------------------------------------------------------
-- (178) C05: despertar alucinado (29 §5.2.2)
---------------------------------------------------------------------------
-- El pico: un episodio de paranoia forzado (los multiplicadores de Crisis.lua) y, una vez al empezar, el clon, los zombis falsos, el
-- disfraz de los zombis cercanos y texto corrupto fuerte. forced = Debug: sin pedir cyberpsicosis activa.
function P.startWake(player, d, st, now, forced)
  local W = PC().Wake
  if not W or (not W.Enabled and not forced) then return false end
  local c = PC()
  if not forced and (not c.Crisis.Enabled or not d.cyberpsychosisActive or d.disconnected or player:isAsleep()) then return false end
  now = now or S.realMs()
  local secs = rnd(W.Seconds[1], W.Seconds[2])
  local CR = rawget(_G, "SandevistanCrisis")
  if CR and CR.forceEpisode then CR.forceEpisode(player, d, st, now, "Paranoia", secs) end
  P.toast(getText("IGUI_Sandevistan_Mon_Wake"), "crit")
  P.textGlitch(W.TextGlitch or 0.8, W.TextGlitchMs or 6000)
  P.play(player, "heartbeat", nil, nil, nil, 0.95)
  pcall(function() P.play(player, "whisper", player:getX(), player:getY(), player:getZ(), 0.7) end)
  local hallu = CFG.NeuralLoad.Hallucinations ~= false          -- (178) las figuras respetan la opcion de alucinaciones
  local inCar = false
  pcall(function() inCar = player:getVehicle() ~= nil end)
  if not inCar and W.Clone and hallu and c.Doppelganger.Enabled then
    pcall(function()
      local DG = rawget(_G, "SandevistanDoppelganger")
      if DG and DG.ready() then DG.spawn(player, "watch", true) end
    end)
  end
  if not inCar and hallu and c.FakeZombies.Enabled then
    for _ = 1, (W.FakeZombies or 0) do
      pcall(function()
        local FZ = rawget(_G, "SandevistanFakeZombies")
        if FZ and FZ.ready() then FZ.spawn(player, false) end
      end)
    end
  end
  if not inCar and W.Disguise and hallu and c.Disguise.Enabled then
    pcall(function()
      local DS = rawget(_G, "SandevistanDisguise")
      if DS and DS.ready() then DS.start(player, "zombies", true) end
    end)
  end
  P.wakes = (P.wakes or 0) + 1
  S.log(string.format("despertar alucinado (%.0f s)", secs))
  return true
end

-- Se marca wakePending al quedar inconsciente; cuando E.isUnconscious pasa a falso, arranca el pico (reloj de juego).
function P.wakeTick(player, d, st, now)
  if not st.wakePending or E.isUnconscious(player) then return end
  st.wakePending = nil
  P.startWake(player, d, st, now)
end

-- (179) C09: cierre narrativo de la remission (29 §9.2). El monitor dice HUMANIDAD RESTAURADA y el clon aparece a lo lejos, saluda y se
-- deshace sin glitch. Con el jar de SandevistanPsychosis; sin el, queda el aviso. Si recae, el clon vuelve en la etapa 3 como siempre.
function P.remissionDone(player, d)
  P.toast(getText("IGUI_Sandevistan_Mon_HumanityRestored"), "ok")
  E.halo(player, getText("IGUI_Sandevistan_HumanityRestored"), 120, 255, 180)
  local DG = rawget(_G, "SandevistanDoppelganger")
  if DG and DG.spawnRemission then pcall(DG.spawnRemission, player) end
  S.log("cyberpsicosis en remision: HUMANIDAD RESTAURADA")
end

-- Debug: el pico ya, sin esperar al KO.
function P.forceWake(player)
  local d = S.data(player)
  local st = P.st(player)
  st.wakePending = nil
  return P.startWake(player, d, st, S.realMs(), true)
end

---------------------------------------------------------------------------
-- (178) C05: caja negra (texto para el REPORTE y el volcado del Debug)
---------------------------------------------------------------------------
function P.incidentText(e)
  if not e then return "nada" end
  local secs = math.floor((e.secs or 0) + 0.5)
  if e.kind == "overload" then
    return string.format("sobrecarga: %s (%d s)", e.fury and "furia total" or "KO", secs)
  elseif e.kind == "episode" then
    return string.format("episodio de %s (%d s)", tostring(e.why), secs)
  elseif e.kind == "crisisAborted" then
    return "antesala cortada (" .. tostring(e.why) .. ")"
  elseif e.kind == "cascadeAvoided" then return "cascada evitada"
  elseif e.kind == "blackout" then return string.format("apagon (%d s)", secs)
  elseif e.kind == "nightTerror" then return "terror nocturno" end
  return tostring(e.kind)
end

function P.blackBoxStatus(d)
  local list = (type(d.incidents) == "table") and d.incidents or {}
  if #list == 0 then return "caja negra: sin incidentes" end
  local last = S.lastIncident(d)
  return string.format("caja negra: %d en total, %d en 24 h, ultimo: %s (hace %.1f h, CN %d)",
    #list, S.incidentCount(d, 24), P.incidentText(last), math.max(0, S.worldHours() - (last.t or 0)), last.cn or 0)
end

function P.dumpIncidents(player, d)
  d = d or S.data(player)
  local list = (type(d.incidents) == "table") and d.incidents or {}
  S.log(string.format("caja negra: %d incidentes", #list))
  for i = #list, 1, -1 do
    local e = list[i] or {}
    S.log(string.format("  INC-%04d  dia %d %.1f h  CN %d  etapa %s  presion %s  %s", i,
      math.floor((e.t or 0) / 24) + 1, (e.t or 0) % 24, e.cn or 0, tostring(e.stage), tostring(e.pressure), P.incidentText(e)))
  end
end

---------------------------------------------------------------------------
-- Tick principal (lo llama Runtime.onTick por jugador local)
---------------------------------------------------------------------------
-- (194) Detalle de rendimiento por subsistema (solo con S.perfDetail, que prende la prueba de rendimiento): suma el tramo y devuelve el reloj.
local function mark(name, t0)
  local t1 = S.clockMs()
  S.perfAdd(name, t1 - t0)
  return t1
end

function P.tick(player, s, d, dt)
  local st = P.st(player)
  local now = S.realMs()
  st.stage = P.stage(d)
  P.berserkTick(player, s, d, st, now)
  if dt <= 0 then return end
  local detail = S.perfDetail == true
  local t = detail and S.clockMs() or 0
  P.pressureTick(player, d, st, now)                           -- (176) antes que todo lo que la usa
  P.wakeTick(player, d, st, now)                               -- (178) al volver del KO, pico alucinado
  local CR = rawget(_G, "SandevistanCrisis")                   -- (177) antesala, episodio de paranoia/disociacion (Crisis.lua)
  if CR then CR.tick(player, s, d, st, now) end
  P.overloadTick(player, s, d, now)
  if detail then t = mark("Psychosis > presion, crisis, sobrecarga", t) end
  P.monitorTick(player, d, st, now)
  P.audioTick(player, d, st, now)
  P.glitchTick(player, s, d, st, now, dt)
  P.misfireTick(player, s, d, st, now)
  P.blackoutTick(player, s, d, st, now)
  if detail then t = mark("Psychosis > monitor, audio, glitch, apagon", t) end
  P.threatTick(player, d, st, now, dt)
  P.phantomTick(player, d, st, now)
  if detail then t = mark("Psychosis > peligro y marcas fantasma", t) end
  local PF = rawget(_G, "SandevistanPhantomFigures")           -- (181) C13.2 figuras fantasma (PhantomFigures.lua, titeres de SandevistanPsychosis)
  if PF then PF.tick(player, d, st, now, dt) end
  if detail then t = mark("Psychosis > figuras fantasma", t) end
  local FZ = rawget(_G, "SandevistanFakeZombies")              -- (138) zombis falsos (FakeZombies.lua, dibujados por SandevistanPsychosis)
  if FZ then FZ.tick(player, d, st, now, dt) end
  if detail then t = mark("Psychosis > zombis falsos", t) end
  local DG = rawget(_G, "SandevistanDoppelganger")             -- (148) el clon (Doppelganger.lua, dibujado por SandevistanPsychosis)
  if DG then DG.tick(player, d, st, now, dt) end
  if detail then t = mark("Psychosis > clon", t) end
  local DS = rawget(_G, "SandevistanDisguise")                 -- (174) el disfraz (Disguise.lua, dibujado por SandevistanPsychosis)
  if DS then DS.tick(player, d, st, now, dt) end
  if detail then t = mark("Psychosis > disfraz", t) end
  local SE = rawget(_G, "SandevistanSelfEcho")                 -- (175) eco de tus propios ruidos (SelfEcho.lua)
  if SE then SE.tick(player, d, st, now, dt) end
  if detail then t = mark("Psychosis > eco propio", t) end
  local EC = rawget(_G, "SandevistanEchoes")                   -- (138) ecos de los zombis (Echoes.lua, motor de estelas)
  if EC then EC.tick(player, d, st, now) end
  P.textTick(player, d, st, now)                               -- (138) texto corrupto (SandevistanPsychosis)
  if detail then t = mark("Psychosis > ecos y texto", t) end
  local SFX = rawget(_G, "SandevistanScreenFX")                -- (181) C13.5 pantalla de los episodios (ScreenFX.lua)
  if SFX then SFX.tick(player, now) end
  if detail then t = mark("Psychosis > pantalla", t) end
  -- cola de eventos con retraso
  for i = #st.queue, 1, -1 do
    local q = st.queue[i]
    if now >= q.at then
      table.remove(st.queue, i)
      pcall(q.fn)
    end
  end
end

-- Terrores nocturnos (cada minuto in-game, desde Periodic.minuteTick).
function P.minuteTick(player, d)
  local c = PC().NightTerrors
  local st = P.st(player)
  if not c.Enabled then return end
  local now = S.worldHours()
  if not player:isAsleep() then st.sleepSince = nil; return end
  if S.stopgapNoNightTerrors(d, now) then return end                              -- (162) T09: el somnífero los evita esa noche
  if not st.sleepSince then st.sleepSince = now; return end
  if (d.neuralLoad or 0) < S.neuralThreshold(d, PC().Stage1CN) or now - st.sleepSince < c.MinSleepHours then return end
  local chance = lerp(c.ChancePerMinute.min, c.ChancePerMinute.max, P.intensity(d)) * S.symptomMultiplier(d) * S.stopgapTerrorMult(d, now)
  if not S.chance(chance) then return end
  st.sleepSince = nil
  S.try("forceAwake", function() player:forceAwake() end)
  E.addStat(player, "PANIC", c.Panic)
  E.addStat(player, "STRESS", c.Stress)
  E.halo(player, getText("IGUI_Sandevistan_NightTerror"), 200, 60, 80)
  P.toast(getText("IGUI_Sandevistan_Mon_NightTerror"), "crit")
  S.addIncident(player, d, { kind = "nightTerror", stage = P.stage(d), pressure = P.pressureLevel(st) })   -- (178) caja negra
  P.play(player, "heartbeat", nil, nil, nil, 0.9)
  local a = ZombRandFloat(0, 6.2831)
  P.play(player, "whisper", player:getX() + math.cos(a), player:getY() + math.sin(a), player:getZ(), 0.6)
end

---------------------------------------------------------------------------
-- Sentido de peligro (antes "visión de amenaza")
-- El implante es espinal, no visual: no "ve", pero los reflejos aceleran la percepción. Por eso solo se marcan los zombis cercanos
-- del MISMO piso que el jugador NO está viendo (detrás de una pared o una esquina) y sin datos numéricos. Sin marcas falsas: una marca
-- siempre tiene un zombi real detrás (v0.1.29), salvo las marcas fantasma (80): ver abajo.
---------------------------------------------------------------------------
function P.threatActive(d)
  return PC().ThreatVision.Enabled and d.cyberpsychosisActive and P.stage(d) >= 2 and option("threatVision", true)
    and not S.senseOff(d)                                  -- (180) Filtro: sin marcas reales ni fantasma
end

-- ¿El zombi sigue en el mundo y en el mismo piso? (la lista se refresca cada RefreshMs; el dibujo lo revalida en cada cuadro)
local function threatValid(z, pz)
  if z == nil or z:isDead() or z:getCurrentSquare() == nil then return false end
  return math.floor(z:getZ()) == pz
end

-- Refresca la lista de zombis cercanos que el jugador no ve (cada RefreshMs).
function P.threatTick(player, d, st, now, dt)
  if d.disconnected then                                          -- (165) T12: sin marcas (ni reales ni fantasma) con el implante inerte
    if #P.threats > 0 then P.threats = {} end
    return
  end
  if not P.threatActive(d) then
    if #P.threats > 0 then P.threats = {} end
    return
  end
  local c = PC().ThreatVision
  if now - P.lastRefreshMs < c.RefreshMs then return end
  P.lastRefreshMs = now
  local list = {}
  pcall(function()
    local cell = getCell()
    local zl = cell and cell:getZombieList()
    if not zl then return end
    local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ())
    local pn = player:getPlayerNum()
    local r2 = c.Range * c.Range
    for i = 0, zl:size() - 1 do
      local z = zl:get(i)
      if threatValid(z, pz) then
        local dx, dy = z:getX() - px, z:getY() - py
        local d2 = dx * dx + dy * dy
        if d2 <= r2 and z:getCurrentSquare():isCouldSee(pn) ~= true then list[#list + 1] = { z = z, d2 = d2 } end
      end
    end
  end)
  table.sort(list, function(a, b) return a.d2 < b.d2 end)
  while #list > c.Max do table.remove(list) end
  P.threats = list
end

-- Marcas fantasma (v0.1.30 (80)): con el sentido de peligro activo, de a ratos aparece un marco sobre alguien que no está, casi siempre a tu espalda.
-- Es la cabeza jugándote una mala pasada: dura un par de segundos, parpadea y se disuelve de golpe en cuanto esa casilla pasa a verse (mirás hacia
-- ahí). Se posiciona en el mundo (no sigue al jugador). Más seguido con más CN; los antidepresivos las espacian. A veces van con unos pasos lejanos.
function P.spawnPhantom(player, st)
  local c = PC().ThreatVision.Phantoms
  local behind = ZombRandFloat(0, 1) < (c.BehindChance or 0.7)
  local x, y, z = P.pickPos(player, c.Radius[1], c.Radius[2], behind)
  P.phantoms[#P.phantoms + 1] = { x = x, y = y, z = math.floor(z or player:getZ()), bornMs = S.realMs(),
                                  lifeMs = rnd(c.LifeSeconds[1], c.LifeSeconds[2]) * 1000, seed = ZombRand(1000) }
  if st and ZombRandFloat(0, 1) < (c.SoundChance or 0) then pcall(AUDIO.footstepFar, player, st) end
end

function P.phantomTick(player, d, st, now)
  if d.disconnected then                                          -- (165) T12
    if #P.phantoms > 0 then P.phantoms = {} end
    return
  end
  local c = PC().ThreatVision.Phantoms
  if not (c and c.Enabled and P.threatActive(d)) or player:isAsleep() then
    if #P.phantoms > 0 then P.phantoms = {} end
    return
  end
  local pz, pn = math.floor(player:getZ()), player:getPlayerNum()
  for i = #P.phantoms, 1, -1 do
    local e = P.phantoms[i]
    local age = now - e.bornMs
    if e.z ~= pz or age > e.lifeMs then
      table.remove(P.phantoms, i)
    elseif not e.fading and age > 400 then
      local seen = false
      pcall(function()
        local cell = getCell()
        local sq = cell and cell:getGridSquare(math.floor(e.x), math.floor(e.y), e.z)
        seen = sq ~= nil and sq:isCouldSee(pn) == true
      end)
      if seen then e.fading = true; e.lifeMs = age + 180; S.markSeen(player, "phantom") end   -- (179) la miraste: se disuelve
    end
  end
  if now < st.nextPhantomMs or #P.phantoms >= (c.Max or 2) then return end
  local every = lerp(c.EverySeconds[2], c.EverySeconds[1], P.intensity(d)) / math.max(0.2, P.freqMult(d, st, "Phantoms")) / S.halluMultiplier(d)            -- (180) Filtro
  st.nextPhantomMs = now + every * 1000 * rnd(0.6, 1.4)
  P.spawnPhantom(player, st)
end

local function bracket(ui, x, y, w, h, cl, th, a, r, g, b)
  ui:drawRect(x, y, cl, th, a, r, g, b);                 ui:drawRect(x, y, th, cl, a, r, g, b)
  ui:drawRect(x + w - cl, y, cl, th, a, r, g, b);         ui:drawRect(x + w - th, y, th, cl, a, r, g, b)
  ui:drawRect(x, y + h - th, cl, th, a, r, g, b);         ui:drawRect(x, y + h - cl, th, cl, a, r, g, b)
  ui:drawRect(x + w - cl, y + h - th, cl, th, a, r, g, b); ui:drawRect(x + w - th, y + h - cl, th, cl, a, r, g, b)
end

local function drawMark(ui, sx, sy, zoom, a)
  local w, h = 34 / zoom, 62 / zoom
  local cl, th = 8 / zoom, math.max(1, math.floor(1.6 / zoom + 0.5))
  bracket(ui, sx - w / 2, sy - h, w, h, cl, th, a, 1.0, 0.16, 0.14)
end

function P.drawThreats(ui, player, d)
  if not P.threatActive(d) or (#P.threats == 0 and #P.phantoms == 0) then return end
  if SandevistanViewport.is3D() then return end                  -- (95) camara 3D de Project Viewport
  local ax, ay = ui:getAbsoluteX(), ui:getAbsoluteY()
  local zoom = 1
  pcall(function() zoom = getCore():getZoom(0) end)
  local now = S.realMs()
  local intensity = P.intensity(d)
  local pz = math.floor(player:getZ())
  local calm = S.lessFlashes()                     -- (170) C01: las marcas no titilan (solo aparecen y se van con fundido)
  pcall(function()
    for _, e in ipairs(P.threats) do
      local z = e.z
      if threatValid(z, pz) then
        -- con CN alta los marcos parpadean (a veces desaparecen un instante)
        local flick = (not calm and intensity > 0.6 and math.sin(now / 47 + e.d2) > 0.85) and 0.25 or 1
        local a = clamp(1.05 - math.sqrt(e.d2) / (PC().ThreatVision.Range * 1.15), 0.3, 0.85) * flick
        local x, y, zz = z:getX(), z:getY(), z:getZ()
        drawMark(ui, isoToScreenX(0, x, y, zz) - ax, isoToScreenY(0, x, y, zz) - ay, zoom, a)
      end
    end
    for _, e in ipairs(P.phantoms) do                  -- marcas fantasma: mismo marco que las reales, con su propio parpadeo
      if e.z == pz then
        local age = now - e.bornMs
        local env = clamp(math.min(age / 150, (e.lifeMs - age) / 250), 0, 1)
        local flick = (not calm and math.sin(now / 53 + e.seed) > 0.8) and 0.3 or 1
        drawMark(ui, isoToScreenX(0, e.x, e.y, e.z) - ax, isoToScreenY(0, e.x, e.y, e.z) - ay, zoom, 0.8 * env * flick)
      end
    end
  end)
end

---------------------------------------------------------------------------
-- Dibujo del monitor y del apagón
---------------------------------------------------------------------------
function P.drawToasts(ui, player)
  if #P.toasts == 0 then return end
  local m = PC().Monitor
  local w = getCore():getScreenWidth()
  local ox, oy = -ui:getAbsoluteX(), -ui:getAbsoluteY()
  local now = S.realMs()
  local life = m.ToastSeconds * 1000
  local y = 96
  for i = #P.toasts, 1, -1 do
    local t = P.toasts[i]
    local age = now - t.bornMs
    if age > life then table.remove(P.toasts, i)
    else
      local a = clamp(math.min(age / 200, (life - age) / 600), 0, 1)
      local r, g, b = 1, 0.25, 0.2
      if t.kind == "ok" then r, g, b = 0.4, 1, 0.8 elseif t.kind == "warn" then r, g, b = 1, 0.75, 0.2 end
      local glitchy = (math.floor(now / 130) + t.seed) % 7 == 0 and not S.lessFlashes()     -- (170) C01
      local jx = glitchy and (ZombRand(9) - 4) or 0
      pcall(function()
        if glitchy then
          ui:drawTextCentre(t.text, ox + w / 2 + jx + 3, oy + y, 0.2, 1, 1, a * 0.6, UIFont.Medium)
          ui:drawTextCentre(t.text, ox + w / 2 + jx - 3, oy + y, 1, 0.1, 0.8, a * 0.6, UIFont.Medium)
        end
        ui:drawTextCentre(t.text, ox + w / 2 + jx, oy + y, r, g, b, a, UIFont.Medium)
      end)
      y = y + 26
    end
  end
end

function P.drawBlackout(ui, player)
  P.drawBlackoutClip(ui, player)
end

-- (183) El tunel y el negro del apagon; con clip = { x, y, w, h } (en pantalla) solo lo que cae adentro de ese rectangulo. Lo usan los moodles
-- de Moodle Framework, que se dibujan despues del HUD (HUD.blackoutMoodle): en la 182 solo les llegaba el negro, no el tunel.
function P.drawBlackoutClip(ui, player, clip)
  local vig, black = P.blackoutLevels(player)
  if vig <= 0 and black <= 0 then return end
  local ax, ay = ui:getAbsoluteX(), ui:getAbsoluteY()
  local w, h = getCore():getScreenWidth(), getCore():getScreenHeight()
  local cx, cy, cw, ch = 0, 0, w, h
  if clip then cx, cy, cw, ch = clip[1], clip[2], clip[3], clip[4] end
  local function rect(x, y, rw, rh, a)
    local x0, y0 = math.max(x, cx), math.max(y, cy)
    local x1, y1 = math.min(x + rw, cx + cw), math.min(y + rh, cy + ch)
    if x1 > x0 and y1 > y0 then ui:drawRect(x0 - ax, y0 - ay, x1 - x0, y1 - y0, a, 0, 0, 0) end
  end
  if vig > 0 then
    local depth = math.floor(math.min(w, h) * (0.18 + 0.34 * vig))
    local rings = 24
    local bt = math.max(1, math.floor(depth / rings))
    for i = 0, rings - 1 do
      local f = 1 - i / rings
      local a = clamp(vig * f * f * 1.05, 0, 1)
      local o = i * bt
      rect(o, o, w - 2 * o, bt, a)
      rect(o, h - o - bt, w - 2 * o, bt, a)
      rect(o, o + bt, bt, h - 2 * o - 2 * bt, a)
      rect(w - o - bt, o + bt, bt, h - 2 * o - 2 * bt, a)
    end
  end
  if black > 0 then rect(0, 0, w, h, black) end
end

-- Todo lo que dibuja el sistema (lo llama el HUD en cada frame).
function P.draw(ui, player, d)
  local ok, err = pcall(function()
    P.drawThreats(ui, player, d)
    local EC = rawget(_G, "SandevistanEchoes")                 -- (138) los ecos se muestran en cada cuadro (el motor los suelta a los 300 ms)
    if EC then EC.draw(player) end
    P.drawBlackout(ui, player)
    P.drawToasts(ui, player)
  end)
  if not ok then S.warnOnce("psyDraw", "no se pudo dibujar la cyberpsicosis: " .. tostring(err)) end
end

Events.OnPlayerDeath.Add(S.safe("Psychosis.OnPlayerDeath", function(player) P.reset(player:getPlayerNum()); P.threats = {}; P.phantoms = {}; P.toasts = {} end))
Events.OnCreatePlayer.Add(S.safe("Psychosis.OnCreatePlayer", function(idx) if idx ~= nil then P.reset(idx) end end))

return P
