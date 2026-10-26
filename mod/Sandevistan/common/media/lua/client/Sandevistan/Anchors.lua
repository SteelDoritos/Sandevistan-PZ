-- Sandevistan / Anchors: anclas de humanidad (179; 29 §9.1). Cosas de la vida normal que bajan la PRESION y espacian un poco la
-- proxima crisis, cada una con su propia espera: dormir en una cama, leer un libro o una revista, comer algo bueno y, en multijugador,
-- estar cerca de otro jugador un rato. No tocan la CN ni curan la cyberpsicosis: compran aire.
--   La presion baja PressureCut durante Hours (P.pressureTick descuenta el valor) y la proxima antesala espera CrisisMult
--   (Crisis.tick) o se empuja PushMinutes si ya estaba agendada. Las esperas y el estado viven en st (no se guardan).
require "Sandevistan/Core"
require "Sandevistan/Effects"
require "Sandevistan/Psychosis"

SandevistanAnchors = { hooked = false }
local A = SandevistanAnchors
local CFG = SandevistanConfig
local S = Sandevistan
local E = SandevistanEffects
local P = SandevistanPsychosis

local function C() return CFG.Psychosis.Anchors end

function A.enabled()
  local c = C()
  return c ~= nil and c.Enabled and CFG.Psychosis.Pressure.Enabled
end

function A.active(st)
  local c = C()
  return st ~= nil and (st.anchorUntilHour or -1) > S.worldHours()
end

-- Puntos que se restan del valor de presion mientras el ancla esta activa.
function A.discount(st)
  if not A.active(st) or not A.enabled() then return 0 end
  return (C() and C().PressureCut) or 0.3
end

-- Multiplicador de espera de la proxima antesala mientras el ancla esta activa (>1 = mas lejos).
function A.crisisMult(st)
  if not A.active(st) or not A.enabled() then return 1 end
  return (C() and C().CrisisMult) or 1.5
end

-- Activa un ancla. forced (Debug) saltea la espera y la opcion apagada. Devuelve true si se aplico.
function A.activate(player, d, st, kind, forced)
  local c = C()
  if not (c and kind) then return false end
  if not forced and (not c.Enabled or not CFG.Psychosis.Pressure.Enabled or P.stage(d) < 1) then return false end
  local ac = c[kind] or {}
  if not forced and ac.Enabled == false then return false end
  local nowH = S.worldHours()
  st.anchorCd = st.anchorCd or {}
  if not forced and nowH - (st.anchorCd[kind] or -1000) < (ac.CooldownHours or 4) then return false end
  st.anchorCd[kind] = nowH
  st.anchorUntilHour = nowH + (c.Hours or 1)
  st.anchorKind = kind
  if st.nextCrisisMs then st.nextCrisisMs = st.nextCrisisMs + (c.PushMinutes or 10) * 60000 end
  E.halo(player, getText("IGUI_Sandevistan_Anchor_" .. kind), 120, 220, 255)
  S.log(string.format("ancla: %s (presion -%.2f por %.1f h)", kind, c.PressureCut or 0.3, c.Hours or 1))
  return true
end

-- Debug: un ancla ya, sin espera.
function A.force(player, kind)
  return A.activate(player, S.data(player), P.st(player), kind or "read", true)
end

function A.clear(st)
  if not st then return end
  st.anchorUntilHour, st.anchorKind, st.anchorCd = nil, nil, nil
  st.anchorSleepMin, st.anchorCompanySec = 0, 0
end

-- Desde Psychosis.minuteTick, una vez por minuto de juego.
function A.tick(player, d, st)
  if not st then return end
  local c = C()
  if not (c and c.Enabled) or not CFG.Psychosis.Pressure.Enabled then return end
  -- dormir en una cama: Minutes seguidos dormido y en cama
  local sl = c.Sleep or {}
  if sl.Enabled ~= false then
    local onBed = false
    if player:isAsleep() then pcall(function() onBed = player:isOnBed() or player:isbOnBed() end) end
    if onBed then
      st.anchorSleepMin = (st.anchorSleepMin or 0) + 1
      if st.anchorSleepMin >= (sl.Minutes or 60) then
        st.anchorSleepMin = 0
        A.activate(player, d, st, "sleep")
      end
    else
      st.anchorSleepMin = 0
    end
  end
  -- compania: otro jugador cerca un rato (solo multijugador)
  local co = c.Company or {}
  if co.Enabled ~= false and isClient and isClient() then
    local n = 0
    local ok, ps = pcall(getOnlinePlayers)
    if ok and ps then
      local r2 = (co.Radius or 8) ^ 2
      for i = 0, ps:size() - 1 do
        local o = ps:get(i)
        local other = true
        pcall(function() other = o ~= player and not o:isLocalPlayer() end)
        if other then
          local dd = nil
          pcall(function()
            if math.floor(o:getZ()) == math.floor(player:getZ()) then
              dd = (o:getX() - player:getX()) ^ 2 + (o:getY() - player:getY()) ^ 2
            end
          end)
          if dd and dd <= r2 then n = n + 1 end
        end
      end
    end
    if n > 0 then
      st.anchorCompanySec = (st.anchorCompanySec or 0) + 60
      if st.anchorCompanySec >= (co.Seconds or 120) then
        st.anchorCompanySec = 0
        A.activate(player, d, st, "company")
      end
    else
      st.anchorCompanySec = 0
    end
  end
end

function A.statusLine(st)
  if not A.active(st) then return "ancla: ninguna" end
  return string.format("ancla: %s (presion -%.2f, quedan %.1f h)", tostring(st.anchorKind), A.discount(st),
    math.max(0, st.anchorUntilHour - S.worldHours()))
end

-- Engancha las acciones del juego una sola vez. La clase puede no existir en un motor raro: se avisa y no rompe.
local function hook(cls, method, name, fn)
  local c = rawget(_G, cls)
  if type(c) ~= "table" or type(c[method]) ~= "function" then
    S.warnOnce("anchor_" .. cls, "ancla " .. name .. ": falta " .. cls .. "." .. method)
    return false
  end
  local orig = c[method]
  c[method] = function(self, ...)
    local res = orig(self, ...)
    pcall(fn, self)
    return res
  end
  return true
end

function A.hookActions()
  if A.hooked then return end
  A.hooked = true
  -- leer: al terminar la accion de lectura (libro, revista, etc.)
  hook("ISReadABook", "perform", "leer", function(self)
    local ch = self and self.character
    if ch then A.activate(ch, S.data(ch), P.st(ch), "read") end
  end)
  -- comer algo bueno: la accion termina de comer (complete llama a Eat) y el item baja la infelicidad
  hook("ISEatFoodAction", "complete", "comer", function(self)
    if not (self and self.character and self.item) then return end
    local u = nil
    pcall(function() u = tonumber(self.item:getUnhappyChange()) end)
    if u and u <= ((C().Eat or {}).UnhappyChange or -5) then
      A.activate(self.character, S.data(self.character), P.st(self.character), "eat")
    end
  end)
end

Events.OnGameStart.Add(S.safe("Anchors.hookActions", A.hookActions))

return A
