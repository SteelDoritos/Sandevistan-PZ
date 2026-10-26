-- Sandevistan / SlowAudio (0.7 (126)): con la dilatacion de un jugador local, las voces de los zombis bajan (Config.SlowAudio).
-- Las voces son eventos de FMOD y el volumen de cada evento se recalcula en cada tick con GameSound:getUserVolume(), asi que bajar ese valor las apaga en
-- vivo. getUserVolume vale 1 salvo con SystemDisabler.setEnableAdvancedSoundOptions(true) (en memoria; ademas muestra el boton "Avanzado" de las
-- opciones de sonido): se prende al bajar y se devuelve al terminar, con el volumen propio de cada sonido (GameSounds.ini) tal como estaba.
-- Es global por nombre de sonido (no hay forma de tocar la voz de un zombi solo; ver AudioProbe.lua). Solo audio local: nada viaja por la red.
require "Sandevistan/Core"
require "Sandevistan/Slowdown"

local CFG = SandevistanConfig
local S = Sandevistan

SandevistanSlowAudio = {}
local SA = SandevistanSlowAudio

SA.level = 1         -- volumen aplicado ahora (1 = sin tocar)
SA.saved = nil       -- mientras esta bajado: { flag = bandera original, sounds = { [nombre] = { gs, uv } } }
SA.lastMs = nil
SA.failed = nil      -- motivo si no se pudo (no se reintenta)

local function enabled()
  local A = CFG.SlowAudio
  if not (A and A.Enabled) then return false end
  local I = rawget(_G, "SandevistanInput")
  return not I or I.getOption("slowZombieVoices", true) ~= false
end

-- Volumen buscado: el del jugador local mas dilatado que no este en un glitch temporal (ahi los zombis vuelven a velocidad normal).
function SA.target()
  if not enabled() then return 1 end
  local A = CFG.SlowAudio
  local SD = SandevistanSlowdown
  local best = 1
  -- (134b) con el mod opcional SandevistanFX bajando el tono de cada zombi, el volumen baja mucho menos: grave y al 25 % casi no se oian
  local vol = A.Volume
  local FXB = rawget(_G, "SandevistanFXBridge")
  if FXB and FXB.pitchOk and CFG.FX and CFG.FX.Pitch and CFG.FX.Pitch.Enabled then vol = math.max(vol, CFG.FX.Pitch.Volume or vol) end
  for idx, tier in pairs(SD.active) do
    if not SD.isGlitching(idx) then
      local zs = tonumber(tier and tier.zombieSpeed) or 1
      local depth = math.max(0, math.min(1, (1 - zs) / math.max(0.01, 1 - A.FullAt)))
      best = math.min(best, 1 - (1 - vol) * depth)
    end
  end
  return best
end

local function voiceSounds()
  local A = CFG.SlowAudio
  local out = {}
  local list = GameSounds.getSoundsInCategory(A.Category)
  for i = 0, list:size() - 1 do
    local gs = list:get(i)
    if gs and tostring(gs:getName()):find(A.VoiceTag, 1, true) then out[#out + 1] = gs end
  end
  return out
end

-- Guarda la bandera y el volumen propio de cada voz (leido con la bandera prendida: apagada, getUserVolume vale 1) y deja la bandera prendida.
local function engage()
  local sounds = {}
  SA.saved = { flag = SystemDisabler.getEnableAdvancedSoundOptions(), sounds = sounds }      -- antes de tocar nada: si algo falla, SA.restore lo devuelve
  SystemDisabler.setEnableAdvancedSoundOptions(true)
  for _, gs in ipairs(voiceSounds()) do sounds[gs:getName()] = { gs = gs, uv = gs:getUserVolume() } end
end

local function apply(level)
  for _, s in pairs(SA.saved.sounds) do s.gs:setUserVolume(s.uv * level) end
end

-- Todo como estaba.
function SA.restore()
  local sv = SA.saved
  SA.saved = nil
  SA.level = 1
  if not sv then return end
  for _, s in pairs(sv.sounds) do pcall(function() s.gs:setUserVolume(s.uv) end) end
  pcall(function() SystemDisabler.setEnableAdvancedSoundOptions(sv.flag == true) end)
end

function SA.tick()
  local now = S.realMs()
  local dt = SA.lastMs and math.min(200, now - SA.lastMs) or 0
  SA.lastMs = now
  if SA.failed then return end
  if SA.level >= 1 and not SA.saved and S.isEmpty(SandevistanSlowdown.active) then return end      -- lo normal: implante apagado, nada que hacer
  local target = SA.target()
  if target >= 1 and SA.level >= 1 then
    if SA.saved then SA.restore() end
    return
  end
  local A = CFG.SlowAudio
  local level = SA.level
  if target < level then level = math.max(target, level - dt / math.max(1, A.FadeInMs))
  else level = math.min(target, level + dt / math.max(1, A.FadeOutMs)) end
  if level == SA.level and SA.saved then return end
  local ok, err = pcall(function()
    if not SA.saved then engage() end
    apply(level)
  end)
  if not ok then
    SA.failed = tostring(err)
    S.warnOnce("slowAudio", "voces lentas: no se pudo bajar el volumen (" .. SA.failed .. "); queda apagado")
    SA.restore()
    return
  end
  SA.level = level
  if level >= 1 then SA.restore() end
end

-- Lineas para el reporte.
function SA.reportLines()
  local A = CFG.SlowAudio
  local lines = {}
  lines[#lines + 1] = "activada = " .. tostring(A.Enabled) .. ", opcion de mod = " .. tostring(enabled()) .. ", volumen pleno = " .. A.Volume
    .. ", desde factor " .. A.FullAt .. ", rampas " .. A.FadeInMs .. "/" .. A.FadeOutMs .. " ms"
  lines[#lines + 1] = "ahora: nivel = " .. string.format("%.2f", SA.level) .. ", objetivo = " .. string.format("%.2f", SA.target())
    .. ", bajado = " .. tostring(SA.saved ~= nil) .. (SA.failed and (", FALLO: " .. SA.failed) or "")
  local n = 0
  pcall(function() n = #voiceSounds() end)
  lines[#lines + 1] = "voces de zombi encontradas: " .. n
  return lines
end

Events.OnPlayerDeath.Add(S.safe("SlowAudio.OnPlayerDeath", function()
  if S.isEmpty(SandevistanSlowdown.active) then SA.restore() end
end))

return SA
