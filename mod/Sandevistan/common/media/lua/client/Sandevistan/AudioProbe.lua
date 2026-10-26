-- Sandevistan / AudioProbe: sonda de Debug (Debug -> Interfaz y visual -> Dilatacion -> Sonda de audio) para decidir si la dilatacion puede tocar
-- el sonido de los zombis. Deja el resultado en Zomboid/Lua/Sandevistan_audioprobe.txt. Lo que se sabe por el jar (42.21):
--   - Las voces son eventos de FMOD (bancos). emitter:setPitch solo se aplica a los sonidos de archivo, asi que a una voz no deberia cambiarle nada.
--   - El volumen de un evento se recalcula en cada tick con GameSound:getUserVolume(), pero ese valor vale 1 salvo con
--     SystemDisabler.setEnableAdvancedSoundOptions(true) (en memoria; solo muestra ademas el boton "Avanzado" de las opciones de sonido).
--   - El handle de la voz esta en el campo publico IsoZombie.vocalEvent; por reflexion solo se lee con -debug ("Not in debug").
-- La sonda lee lo que puede y despues alterna fases de 4 s (normal / voces mas bajas / ...) para comparar de oido.
require "Sandevistan/Core"

local S = Sandevistan

SandevistanAudioProbe = {}
local P = SandevistanAudioProbe
P.FILE = "Sandevistan_audioprobe.txt"
P.RADIUS = 30
P.PHASE_MS = 4000
P.sections = {}
P.order = { "lectura", "voces" }
P.run = nil

local function try(fn, ...)
  local ok, v = pcall(fn, ...)
  if ok then return v end
  return "ERR"
end

local function str(v)
  if type(v) == "number" then return string.format("%.3f", v) end
  return tostring(v)
end

---------------------------------------------------------------------------
-- Archivo
---------------------------------------------------------------------------
function P.export(player)
  local lines = { "# Sandevistan " .. tostring(SandevistanConfig.Build) .. ": sonda de audio de los zombis (la ultima corrida de cada parte)" }
  for _, title in ipairs(P.order) do
    local sec = P.sections[title]
    lines[#lines + 1] = ""
    lines[#lines + 1] = "== " .. title
    if sec then for _, l in ipairs(sec) do lines[#lines + 1] = l end else lines[#lines + 1] = "(no se corrio en esta sesion)" end
  end
  local wrote = pcall(function()
    local w = getFileWriter(P.FILE, true, false)
    if not w then error("sin escritor") end
    for _, l in ipairs(lines) do w:write(S.ascii(l) .. "\n") end
    w:close()
  end)
  S.log("sonda de audio: " .. #lines .. " lineas, " .. (wrote and ("escrito en Zomboid/Lua/" .. P.FILE) or "NO se pudo escribir"))
  if player then pcall(function() player:Say(wrote and ("Sonda de audio: Zomboid/Lua/" .. P.FILE) or "No se pudo escribir la sonda") end) end
  return lines, wrote
end

---------------------------------------------------------------------------
-- Ayudas
---------------------------------------------------------------------------
-- Zombis vivos del piso del jugador dentro del radio, del mas cercano al mas lejano.
function P.nearZombies(player, radius)
  local out = {}
  local list = try(function() return getCell():getZombieList() end)
  if not list or list == "ERR" then return out end
  local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ())
  for i = 0, list:size() - 1 do
    local z = list:get(i)
    if z and not z:isDead() and math.floor(z:getZ()) == pz then
      local d2 = (z:getX() - px) ^ 2 + (z:getY() - py) ^ 2
      if d2 <= radius * radius then out[#out + 1] = { z = z, d = math.sqrt(d2) } end
    end
  end
  table.sort(out, function(a, b) return a.d < b.d end)
  return out
end

-- Campo IsoZombie.vocalEvent por reflexion (solo con -debug). Se busca una vez y se guarda el Field.
local vocalField = nil
local vocalFieldErr = nil
P.fieldDiag = nil          -- cuantos campos vio la reflexion y los primeros, para el archivo si no aparece vocalEvent
function P.vocalHandle(z)
  if vocalField == nil and vocalFieldErr == nil then
    local ok, err = pcall(function()
      local n = getNumClassFields(z)
      local sample = {}
      for i = 0, n - 1 do
        local f = getClassField(z, i)
        local name = tostring(f)
        local okName, short = pcall(function() return f:getName() end)
        if okName and short then name = name .. " [" .. tostring(short) .. "]" end
        if #sample < 6 or name:find("ocal", 1, true) then sample[#sample + 1] = name end
        if name:find("vocalEvent", 1, true) then vocalField = f; return end
      end
      P.fieldDiag = n .. " campos; " .. table.concat(sample, " ; ")
      error("no esta el campo")
    end)
    if not ok then vocalFieldErr = tostring(err) end
  end
  if not vocalField then return nil, vocalFieldErr end
  local ok, v = pcall(getClassFieldVal, z, vocalField)
  if not ok then return nil, tostring(v) end
  local n = tonumber(v) or tonumber(tostring(v))
  return n, nil
end

-- Sonidos de voz de zombi (categoria Zombie con "Voice" en el nombre), mas los que usan los zombis cercanos.
function P.voiceSounds(near)
  local names, seen = {}, {}
  local function add(n) if n and not seen[n] then seen[n] = true; names[#names + 1] = n end end
  pcall(function()
    local list = GameSounds.getSoundsInCategory("Zombie")
    for i = 0, list:size() - 1 do
      local gs = list:get(i)
      local n = gs:getName()
      if n:find("Voice") then add(n) end
    end
  end)
  for _, e in ipairs(near or {}) do add(try(function() return e.z:getVoiceSoundName() end)) end
  return names
end

local function gameSound(name)
  -- (no getScriptManager():getGameSound: eso es el script, GameSoundScript; el objeto de audio con setUserVolume es este)
  return try(function() return GameSounds.getSound(name) end)
end

local function advancedFlag()
  return try(function() return SystemDisabler.getEnableAdvancedSoundOptions() end)
end

---------------------------------------------------------------------------
-- 1. Lectura
---------------------------------------------------------------------------
function P.read(player)
  local out = {}
  local function add(l) out[#out + 1] = l end
  local near = P.nearZombies(player, P.RADIUS)
  add("modo: " .. (isClient() and "cliente MP" or (isServer() and "servidor" or "un jugador")) .. ", debug=" .. str(try(getDebug)) .. ", zombis a " .. P.RADIUS .. " casillas: " .. #near)
  add("SystemDisabler.getEnableAdvancedSoundOptions = " .. str(advancedFlag()))
  local voices = P.voiceSounds(near)
  add("sonidos de voz (" .. #voices .. "): nombre | userVolume efectivo | valor guardado (leido con la bandera prendida)")
  local flag0 = advancedFlag()
  for _, n in ipairs(voices) do
    local gs = gameSound(n)
    if gs and gs ~= "ERR" then
      local eff = try(function() return gs:getUserVolume() end)
      pcall(function() SystemDisabler.setEnableAdvancedSoundOptions(true) end)
      local raw = try(function() return gs:getUserVolume() end)
      if flag0 ~= "ERR" then pcall(function() SystemDisabler.setEnableAdvancedSoundOptions(flag0 == true) end) end
      add("  " .. n .. " | " .. str(eff) .. " | " .. str(raw))
    else
      add("  " .. n .. " | sin GameSound")
    end
  end
  add("zombis cercanos (hasta 8): distancia | voz | isPlaying(voz) | z.vocalEvent directo | vocalEvent por reflexion | isPlaying(handle)")
  for i = 1, math.min(8, #near) do
    local z, d = near[i].z, near[i].d
    local em = try(function() return z:getEmitter() end)
    local voice = try(function() return z:getVoiceSoundName() end)
    local playingName = (em and em ~= "ERR") and try(function() return em:isPlaying(voice) end) or "sin emisor"
    local direct = try(function() return z.vocalEvent end)
    local h, err = P.vocalHandle(z)
    local playingH = (h and em and em ~= "ERR") and try(function() return em:isPlaying(h) end) or "-"
    add(string.format("  %.1f | %s | %s | %s | %s | %s", d, str(voice), str(playingName), str(direct), h and string.format("%.0f", h) or ("nil (" .. tostring(err) .. ")"), str(playingH)))
  end
  if P.fieldDiag then add("reflexion sin vocalEvent: " .. P.fieldDiag) end
  if #near == 0 then add("  (no hay zombis cerca: acercate a unos 10-20 casillas de varios y volve a correrla)") end
  P.sections.lectura = out
  return out
end

---------------------------------------------------------------------------
-- 2. Voces de oido: fases de 4 s
---------------------------------------------------------------------------
-- kind: "normal" | "user" (GameSound:setUserVolume global) | "handle" (setVolume por zombi, -debug) | "pitch" (setPitch por zombi, -debug)
P.PHASES = {
  { kind = "normal", say = "NORMAL" },
  { kind = "user", value = 0.25, say = "VOCES AL 25% (global)" },
  { kind = "normal", say = "NORMAL" },
  { kind = "user", value = 0, say = "VOCES MUDAS (global)" },
  { kind = "normal", say = "NORMAL" },
  { kind = "handle", value = 0, say = "VOCES MUDAS (por zombi)" },
  { kind = "normal", say = "NORMAL" },
  { kind = "pitch", value = 0.5, say = "PITCH 0.5 (por zombi)" },
  { kind = "normal", say = "NORMAL" },
}

function P.startVoices(player)
  if P.run then return false end
  P.read(player)
  local near = P.nearZombies(player, P.RADIUS)
  local voices = P.voiceSounds(near)
  local saved = {}
  -- getUserVolume vale 1 con la bandera apagada: se lee con ella prendida para no pisar el valor propio del sonido (GameSounds.ini)
  local flag0 = advancedFlag()
  pcall(function() SystemDisabler.setEnableAdvancedSoundOptions(true) end)
  for _, n in ipairs(voices) do
    local gs = gameSound(n)
    if gs and gs ~= "ERR" then saved[n] = { gs = gs, uv = try(function() return gs:getUserVolume() end) } end
  end
  if flag0 ~= "ERR" then pcall(function() SystemDisabler.setEnableAdvancedSoundOptions(flag0 == true) end) end
  P.run = { player = player, t0 = S.realMs(), phase = 0, voices = voices, saved = saved, flag = flag0,
            touched = {}, stats = {}, errors = {} }
  pcall(function() player:Say("Sonda de audio: " .. (#P.PHASES * P.PHASE_MS / 1000) .. " s, escucha las voces") end)
  return true
end

local function noteError(r, key, err)
  if not r.errors[key] then r.errors[key] = tostring(err) end
end

local function setUserAll(r, v)
  if v ~= 1 then
    local ok, err = pcall(function() SystemDisabler.setEnableAdvancedSoundOptions(true) end)
    if not ok then noteError(r, "setEnableAdvancedSoundOptions", err) end
  end
  for n, s in pairs(r.saved) do
    local target = v
    if target == 1 then target = (type(s.uv) == "number") and s.uv or 1 end
    if not r.errors["setUserVolume " .. n] then         -- si fallo una vez no se reintenta: cada falla llena la consola
      local ok, err = pcall(function() s.gs:setUserVolume(target) end)
      if not ok then noteError(r, "setUserVolume " .. n, err) end
    end
  end
end

-- Devuelve todo como estaba: volumen de usuario, la bandera y volumen/pitch de cada handle tocado.
local function restore(r)
  setUserAll(r, 1)
  if r.flag ~= "ERR" then pcall(function() SystemDisabler.setEnableAdvancedSoundOptions(r.flag == true) end) end
  for h, em in pairs(r.touched) do
    pcall(function() em:setVolume(h, 1) end)
    pcall(function() em:setPitch(h, 1) end)
  end
  r.touched = {}
end

local function phaseStats(r, i)
  local st = r.stats[i]
  if not st then st = { samples = 0, zombies = 0, playing = 0, handles = 0, changes = 0 }; r.stats[i] = st end
  return st
end

local function tickVoices()
  local r = P.run
  if not r then return end
  local pl = r.player
  local now = S.realMs()
  local idx = math.floor((now - r.t0) / P.PHASE_MS) + 1
  if idx > #P.PHASES or not pl or pl:isDead() then
    restore(r)
    P.run = nil
    local out = {}
    local function add(l) out[#out + 1] = l end
    add("fases de " .. (P.PHASE_MS / 1000) .. " s; por fase: muestras | zombis en el radio (media) | con la voz sonando (media) | con handle leido (media) | cambios de handle")
    for i, ph in ipairs(P.PHASES) do
      local st = r.stats[i] or { samples = 0, zombies = 0, playing = 0, handles = 0, changes = 0 }
      local n = math.max(1, st.samples)
      add(string.format("%d. %s | %d | %.1f | %.1f | %.1f | %d", i, ph.say, st.samples, st.zombies / n, st.playing / n, st.handles / n, st.changes))
    end
    add("bandera de opciones avanzadas al empezar: " .. str(r.flag) .. "; al terminar: " .. str(advancedFlag()))
    local any = false
    for k, e in pairs(r.errors) do add("error: " .. k .. ": " .. e); any = true end
    if not any then add("sin errores en las llamadas") end
    add("ANOTA DE OIDO: en que fases bajaron las voces y si en la de PITCH cambio el tono (se espera que no)")
    P.sections.voces = out
    P.export(pl)
    return
  end
  local ph = P.PHASES[idx]
  if idx ~= r.phase then
    r.phase = idx
    setUserAll(r, ph.kind == "user" and ph.value or 1)
    for h, em in pairs(r.touched) do
      pcall(function() em:setVolume(h, 1) end)
      pcall(function() em:setPitch(h, 1) end)
    end
    pcall(function() pl:Say(ph.say) end)
  end
  -- Cada tick: el manager de voces puede reasignar el handle de un zombi, asi que se vuelve a aplicar.
  local st = phaseStats(r, idx)
  st.samples = st.samples + 1
  local near = P.nearZombies(pl, P.RADIUS)
  st.zombies = st.zombies + #near
  r.last = r.last or {}
  for _, e in ipairs(near) do
    local z = e.z
    local em = z:getEmitter()
    local voice = try(function() return z:getVoiceSoundName() end)
    if try(function() return em:isPlaying(voice) end) == true then st.playing = st.playing + 1 end
    local h = P.vocalHandle(z)
    if h and h ~= 0 then
      st.handles = st.handles + 1
      local prev = r.last[z]
      if prev and prev ~= h then st.changes = st.changes + 1 end
      r.last[z] = h
      if r.errors["setVolume(handle)"] or r.errors["setPitch(handle)"] then
        -- ya fallo: no se reintenta en cada tick
      elseif ph.kind == "handle" then
        local ok, err = pcall(function() em:setVolume(h, ph.value) end)
        if ok then r.touched[h] = em else noteError(r, "setVolume(handle)", err) end
      elseif ph.kind == "pitch" then
        local ok, err = pcall(function() em:setPitch(h, ph.value) end)
        if ok then r.touched[h] = em else noteError(r, "setPitch(handle)", err) end
      end
    end
  end
end

Events.OnTick.Add(S.safe("AudioProbe.OnTick", tickVoices))

return P
