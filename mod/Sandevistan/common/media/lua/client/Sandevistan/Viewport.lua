-- Sandevistan / Viewport: detecta si el mundo se esta dibujando con la camara 3D del mod "Project Viewport" (primera / tercera persona; tecla O por defecto) para apagar lo que se dibuja
-- en 2D sobre el mundo con la proyeccion isometrica (las estelas, las marcas de amenaza de la cyberpsicosis y los marcadores de ex-sujetos): con esa camara quedan en cualquier parte.
-- v0.1.30 (95).
--
-- Como se detecta (Viewport no expone si esta encendido): cuando esta encendido reemplaza el dibujo isometrico del mundo (parchea IsoCell.render y lo saltea), asi que los eventos que
-- el juego dispara DENTRO de ese dibujo (OnPostFloorLayerDraw y RenderOpaqueObjectsInWorld) dejan de llegar mientras el resto del dibujo (la interfaz) sigue. Entonces: modo 3D = Viewport
-- instalado + ya se vio al menos un dibujo isometrico en esta partida (prueba de que esos eventos llegan en este juego) + hace mas de StaleMs que no llega ninguno.
-- Sin Viewport no se hace nada (ni siquiera se escuchan los eventos). La opcion de mod "viewportAuto" lo apaga todo.
require "Sandevistan/Core"

local S = Sandevistan

SandevistanViewport = { StaleMs = 2500 }
local V = SandevistanViewport
V.lastIsoMs = nil          -- ultimo dibujo isometrico visto
V.events = 0               -- cuantos eventos de dibujo isometrico llegaron (para el reporte)

function V.installed()
  return type(rawget(_G, "Viewpoint")) == "table"
end

local function isoDrawn()
  V.lastIsoMs = getTimestampMs()
  V.events = V.events + 1
end
-- Los eventos se escuchan SOLO si Viewport esta instalado (llegan varias veces por cuadro, una por piso dibujado): sin Viewport el mod no paga nada. Se intenta al cargar y de
-- nuevo al empezar la partida, por si la clase de Viewport se expone despues de cargar este archivo.
local listening = false
function V.listen()
  if listening or not V.installed() or not Events then return false end
  listening = true
  if Events.OnPostFloorLayerDraw then Events.OnPostFloorLayerDraw.Add(isoDrawn) end
  if Events.RenderOpaqueObjectsInWorld then Events.RenderOpaqueObjectsInWorld.Add(isoDrawn) end
  return true
end
V.listen()
if Events and Events.OnGameStart then Events.OnGameStart.Add(V.listen) end

function V.auto()
  return not SandevistanInput or SandevistanInput.getOption("viewportAuto", true)
end

-- (131) El mod opcional SandevistanViewpoint pone aca una funcion que lee el dato exacto de Viewpoint (true/false; nil = no sabe).
V.probe = nil

-- ¿Se esta usando la camara 3D de Viewport ahora mismo?
function V.is3D()
  if not V.installed() or not V.auto() then return false end
  if V.probe then
    local ok, r = pcall(V.probe)
    if ok and r ~= nil then return r == true end
  end
  if not V.lastIsoMs then return false end           -- sin prueba de que los eventos llegan: se trata como isometrico
  return getTimestampMs() - V.lastIsoMs > V.StaleMs
end

-- Lineas para el REPORTE: sirven para comprobar la deteccion encendiendo y apagando la camara 3D.
function V.reportLines()
  local out = {}
  out[#out + 1] = "Project Viewport instalado = " .. tostring(V.installed()) .. " | deteccion automatica = " .. tostring(V.auto())
  out[#out + 1] = "eventos de dibujo isometrico vistos = " .. V.events .. " | ultimo hace = "
    .. (V.lastIsoMs and string.format("%.1f s", (getTimestampMs() - V.lastIsoMs) / 1000) or "nunca") .. " | modo 3D detectado = " .. tostring(V.is3D())
  local A = rawget(_G, "SandevistanAfterimages")
  local b = A and A.backend
  if b and b.status then                             -- (131) estelas con pose real del mod opcional SandevistanViewpoint; (136) tambien en isometrico
    local ok, st = pcall(b.status)
    out[#out + 1] = "estelas con pose real (SandevistanViewpoint): " .. (ok and tostring(st) or ("error: " .. tostring(st)))
  end
  return out
end

return V
