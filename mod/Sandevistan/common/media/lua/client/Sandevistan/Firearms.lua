-- Sandevistan / Firearms: sinergia con las armas de fuego (v0.1.30 (33)). Con el implante activo, recargar, montar el cerrojo y cargar/sacar cargadores corren MAS
-- RAPIDO con el mismo factor que tu velocidad (1 + playerBoost del tramo, con Momentum, Overdrive y Edgerunner). No toca el dano ni la punteria: el ruido de los disparos
-- sigue atrayendo a los zombis de fuera de la burbuja. Solo cliente (la velocidad de las acciones es local). Sandbox: FirearmActionSpeed.
-- (v0.1.30 (38): se quitaron la punteria acelerada y el Heat por disparo; el juego ya es permisivo con la punteria.)
-- Se engancha a DOS funciones vanilla de ISReloadWeaponAction: getReloadTime(character, baseTime) (duracion de la accion) y setReloadSpeed(character, rack) (la
-- variable de animacion ReloadSpeed que usan los nodos de recarga, m_SpeedScale = ReloadSpeed).
require "Sandevistan/Core"
require "Sandevistan/Runtime"

local CFG = SandevistanConfig
local S = Sandevistan
local R = SandevistanRuntime
local FW = SandevistanFirmware

SandevistanFirearms = {}
local F = SandevistanFirearms
F.installed = false
F.state = {}        -- [playerNum] = { base, out }: para no multiplicar dos veces lo que ya multiplicamos

-- Multiplicador de velocidad de las acciones de armas ahora mismo (1 = sin efecto).
function F.multiplier(player)
  local C = CFG.Firearms
  if not C or not C.Enabled then return 1 end
  local s = R.session(player)
  if not (s and s.active and s.eff) then return 1 end
  local m = math.min(CFG.FastAnimations.MaxMultiplier or 2.2, 1 + (s.eff.playerBoost or 0))
  return 1 + (m - 1) * (C.Factor or 1)
end

function F.install()
  if F.installed then return true end
  local A = rawget(_G, "ISReloadWeaponAction")
  if type(A) ~= "table" or type(A.getReloadTime) ~= "function" or type(A.setReloadSpeed) ~= "function" then return false end
  local origTime, origSpeed = A.getReloadTime, A.setReloadSpeed
  A.getReloadTime = function(character, baseTime, ...)
    local t = origTime(character, baseTime, ...)
    local ok, m = pcall(F.multiplier, character)
    if ok and m and m > 1 and type(t) == "number" then return t / m end
    return t
  end
  A.setReloadSpeed = function(character, rack, ...)
    local r = origSpeed(character, rack, ...)
    pcall(function()
      local m = F.multiplier(character)
      if m <= 1 then return end
      local v = character:getVariableFloat("ReloadSpeed", 1.0)
      local st = F.state[character:getPlayerNum()]
      local base = v
      if st and math.abs(v - st.out) < 1e-4 then base = st.base end       -- es lo que dejamos nosotros: se parte de la base, no se compone
      local out = base * m
      character:setVariable("ReloadSpeed", out)
      F.state[character:getPlayerNum()] = { base = base, out = out }
    end)
    return r
  end
  F.installed = true
  return true
end

F.install()
Events.OnGameStart.Add(S.safe("Firearms.install", F.install))

return F
