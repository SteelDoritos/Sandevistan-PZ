-- Sandevistan / ActionSpeed (servidor, 0.7 build 118): en multijugador la duracion de una accion temporizada la calcula el SERVIDOR. Crea su copia de la
-- accion y llama a getDuration / adjustMaxTime alla (NetTimedAction), y el cliente toma esa duracion (LuaTimedActionNew.update ->
-- ActionManager.getDuration), verificado en el jar de 42.21. Los ganchos del cliente (FirmwareClient.hookActions para Taller, Firearms.install para la
-- recarga) no corren en el servidor, asi que en MP esas acciones duraban lo normal. Aca estan los mismos ganchos, con el estado que manda cada cliente
-- (comando "speed": modo trabajo y multiplicador de recarga, acotados a lo que el mod puede dar). Sin efecto en SP (alla actuan los ganchos del cliente).
require "Sandevistan/Core"

local CFG = SandevistanConfig

SandevistanActionSpeed = SandevistanActionSpeed or {}
local A = SandevistanActionSpeed
A.state = A.state or setmetatable({}, { __mode = "k" })     -- [jugador del servidor] = { work = bool, reload = numero }
A.scaled = A.scaled or 0

local function num(v, lo, hi)
  v = tonumber(v)
  if not v or v ~= v then return nil end
  if v < lo then v = lo elseif v > hi then v = hi end
  return v
end

-- Estado que manda el cliente. work: el modo trabajo de Taller esta encendido; reload: el multiplicador de la recarga (>= 1).
function A.set(player, args)
  if not player then return end
  local maxReload = (CFG.FastAnimations and CFG.FastAnimations.MaxMultiplier) or 2.2
  A.state[player] = { work = args and args.work == true or false, reload = num(args and args.reload, 1, maxReload) or 1 }
end

local function stateOf(character)
  if not isServer() or not character then return nil end
  return A.state[character]
end

local function listed(typeName)
  for _, n in ipairs(CFG.Firmware.Work.Actions) do if n == typeName then return true end end
  return false
end

-- Factor de Taller para una accion (se fija una vez por accion, como en el cliente).
function A.workFactor(action)
  local f = action._sandeSrvF
  if f ~= nil then return f end
  f = 1
  local st = stateOf(action.character)
  if st and st.work and CFG.Firmware.Work.ActionsEnabled then f = CFG.Firmware.Work.ActionMult end
  action._sandeSrvF = f
  return f
end

function A.reloadFactor(character)
  local st = stateOf(character)
  if not st or not (CFG.Firearms and CFG.Firearms.Enabled) then return 1 end
  return st.reload or 1
end

function A.install()
  local Wk = CFG.Firmware.Work
  local n = 0
  for _, name in ipairs(Wk.Actions) do
    local cls = rawget(_G, name)
    if type(cls) == "table" and type(cls.getDuration) == "function" and not rawget(cls, "_sandeSrv") then
      local orig = cls.getDuration
      cls.getDuration = function(self, ...)
        local t = orig(self, ...)
        if type(t) == "number" and t > 0 then
          local f = A.workFactor(self)
          if f ~= 1 then A.scaled = A.scaled + 1; return t * f end
        end
        return t
      end
      cls._sandeSrv = true
      n = n + 1
    end
  end
  local B = rawget(_G, "ISBaseTimedAction")
  if type(B) == "table" and type(B.adjustMaxTime) == "function" and not rawget(B, "_sandeSrv") then
    local orig = B.adjustMaxTime
    B.adjustMaxTime = function(self, maxTime)
      local t = orig(self, maxTime)
      if type(t) == "number" and t > 0 and self._sandeSrvF == nil and listed(self.Type) then
        local f = A.workFactor(self)
        if f ~= 1 then A.scaled = A.scaled + 1; return t * f end
      end
      return t
    end
    B._sandeSrv = true
    n = n + 1
  end
  local R = rawget(_G, "ISReloadWeaponAction")
  if type(R) == "table" and type(R.getReloadTime) == "function" and not rawget(R, "_sandeSrv") then
    local orig = R.getReloadTime
    R.getReloadTime = function(character, baseTime, ...)
      local t = orig(character, baseTime, ...)
      local m = A.reloadFactor(character)
      if m > 1 and type(t) == "number" then A.scaled = A.scaled + 1; return t / m end
      return t
    end
    R._sandeSrv = true
    n = n + 1
  end
  return n
end

if isServer() then
  A.install()
  Events.OnGameBoot.Add(function() A.install() end)
  if Events.OnServerStarted then Events.OnServerStarted.Add(function() A.install() end) end
end

return A
