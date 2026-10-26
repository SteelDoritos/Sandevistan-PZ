-- Sandevistan / Acción temporizada genérica.
-- Todas las acciones largas (cirugía, extracción, calibración, reparación, dosis, síntesis,
-- abrir caja) usan esta clase con callbacks. La tirada ocurre solo en perform():
-- cancelar (stop) nunca consume nada ni aplica castigos.
-- (190) C12: este archivo va en shared/ A PROPÓSITO. En multijugador el cliente manda la acción al servidor con NetTimedAction y
-- el servidor la reconstruye con LuaManager.get("SandevistanAction") + "SandevistanAction.new": si la clase no existe allá
-- (carpeta client/, que el servidor dedicado no carga), el parseo del paquete falla y el anti-cheat del juego expulsa al cliente
-- con «malformed packet or suspicious activity». En el servidor la acción solo tiene que existir y calcular la duración; los
-- callbacks (funciones) no viajan, así que perform/stop se saltean alla (abajo).
require "TimedActions/ISBaseTimedAction"

SandevistanAction = ISBaseTimedAction:derive("SandevistanAction")

-- params = { time, label, isValid = fn(action) -> bool, onPerform = fn(action), onStart / onStop = fn(action) (opcionales),
--            anim = "Loot" | "Craft" | "TakePills" | ..., target = objeto (para mirar), stopOnWalk / stopOnAim = false (opcionales) }
function SandevistanAction:new(character, params)
  params = params or {}
  local o = ISBaseTimedAction.new(self, character)
  o.params = params
  o.stopOnWalk = params.stopOnWalk ~= false
  o.stopOnRun = true
  if params.stopOnAim == false then o.stopOnAim = false end         -- (108) dosis: se puede apuntar y caminar mientras tanto
  o.maxTime = o:getDuration()
  return o
end

function SandevistanAction:getDuration()
  if self.character:isTimedActionInstant() then return 1 end
  return self.params.time or 100
end

-- (190) C12: la acción se sincroniza sola (el efecto real va por los comandos del mod). Así el cliente NO manda el NetTimedAction
-- con esta clase al servidor: en un servidor dedicado que no cargara client/ (o con otra versión del mod) ese paquete podía
-- tirar una excepción y el anti-cheat expulsaba por «malformed packet». Es el mismo modo que usan las acciones vanilla con
-- serverStart/serverStop propios. La clase igual vive en shared/ para que el servidor pueda parsearla si llega de otro cliente.
function SandevistanAction:create()
  self.maxTime = self:adjustMaxTime(self.maxTime)
  self.action = LuaTimedActionNew.new(self, self.character)
  if self.action and self.action.setCustomRemoteTimedActionSync then
    pcall(function() self.action:setCustomRemoteTimedActionSync(true) end)
  end
end

function SandevistanAction:isValid()
  if self.params.isValid then return self.params.isValid(self) end
  return true
end

function SandevistanAction:waitToStart()
  if self.params.faceObject then
    self.character:faceThisObject(self.params.faceObject)
    return self.character:shouldBeTurning()
  end
  return false
end

function SandevistanAction:update()
  if self.params.faceObject then self.character:faceThisObject(self.params.faceObject) end
  self.character:setMetabolicTarget(Metabolics.LightWork)
end

function SandevistanAction:start()
  if self.params.anim then
    pcall(function() self:setActionAnim(self.params.anim) end)
  end
  -- v0.1.30 (21): onStart corre al empezar la accion (los sonidos de uso suenan desde el principio, no al terminar)
  if self.params.onStart then
    local ok, err = pcall(self.params.onStart, self)
    if not ok then print("[Sandevistan] error en inicio de accion " .. tostring(self.params.label) .. ": " .. tostring(err)) end
  end
end

-- En un servidor dedicado (isServer sin isClient) la acción existe solo para que el paquete se pueda parsear: no hay
-- ISTimedActionQueue ni callbacks. En el anfitrión de una partida alojada isClient también es true y corre normal.
local function clientSide() return not (isServer() and not isClient()) end

function SandevistanAction:stop()
  if not clientSide() then return end
  if self.params.onStop then pcall(self.params.onStop, self) end
  ISBaseTimedAction.stop(self)
end

function SandevistanAction:perform()
  if not clientSide() then return end
  if self.params.onPerform then
    local ok, err = pcall(self.params.onPerform, self)
    if not ok then print("[Sandevistan] error en acción " .. tostring(self.params.label) .. ": " .. tostring(err)) end
  end
  ISBaseTimedAction.perform(self)
end

return SandevistanAction
