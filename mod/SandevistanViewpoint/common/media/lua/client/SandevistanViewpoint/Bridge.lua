-- SandevistanViewpoint / Bridge (mod opcional, 0.7 (131); 136: poses reales tambien en isometrico): conecta las estelas del Sandevistan con
-- el jar de este mod, que las dibuja como poses reales (el esqueleto del momento, no una silueta): en la camara isometrica normal con el
-- mismo pipeline del juego, y dentro de la camara 3D de Viewpoint si esta instalado (Viewpoint es opcional desde la 136). ZombieBuddy carga
-- el jar y lo expone a Lua como SandevistanVP. La logica de las estelas (cuando nace cada una, cuanto dura, su color) sigue en
-- Sandevistan/Afterimages.lua; aca solo se pasa al jar. Sin el jar (ZombieBuddy no lo aprobo, o el juego cambio algo que el jar usa) no pasa
-- nada: quedan las siluetas 2D de siempre.
require "Sandevistan/Core"
require "Sandevistan/Viewport"
require "Sandevistan/Afterimages"
require "Sandevistan/Slowdown"

local S = Sandevistan
local A, V = SandevistanAfterimages, SandevistanViewport

SandevistanViewpointBridge = {
  AlphaScale = 1.0,     -- opacidad que se le pasa al motor respecto de la de las siluetas 2D (el motor dibuja con mezcla real)
  Tint = 1.5,           -- color de la estela x esto (el color de la ropa queda debajo, teñido)
  Glow = 1.0,           -- luz minima: la estela se ve aunque este a oscuras
  MaxDraws = 700,       -- tope de piezas agregadas por cuadro (cada estela es el personaje entero: 15 a 30 piezas)
}
local B = SandevistanViewpointBridge

-- El juego publica la clase del jar como global SandevistanVP y tambien con la ruta del paquete (sandevistan.viewpoint.SandevistanVP).
local function vp()
  local j = rawget(_G, "SandevistanVP")
  if j then return j end
  local pkg = rawget(_G, "sandevistan")
  return type(pkg) == "table" and type(pkg.viewpoint) == "table" and pkg.viewpoint.SandevistanVP or nil
end

local configured = false
function B.ready()
  local j = vp()
  if not j or not j.available() then return false end
  if not configured then
    configured = true
    j.look(B.Tint, B.Glow, B.MaxDraws)
  end
  return true
end

-- (138h) stamp lleva la posicion donde nacio la estela: si el jar la captura un cuadro despues, la estela no se corre del lugar.
function B.stamp(player, uid, x, y, z)
  local j = vp()
  if not j then return end
  if x and y and z then j.stamp(player, uid, x, y, z) else j.stamp(player, uid) end
end
function B.show(uid, r, g, b, a) local j = vp(); if j then j.show(uid, r, g, b, a * B.AlphaScale) end end
function B.drop(uid) local j = vp(); if j then j.drop(uid) end end
function B.clear() local j = vp(); if j then j.clear() end end

function B.status()
  local j = vp()
  if not j then return "el jar no esta cargado (ZombieBuddy no lo aprobo)" end
  local s = tostring(j.status()) .. " | " .. tostring(j.stats())
  if j.perf then s = s .. " | medidor: " .. tostring(j.perf()) end   -- (132) jar 3 en adelante
  return s
end

-- (132) Medicion de rendimiento desde la consola de Lua: SandevistanViewpointBridge.perf() y .reset() (pico y FPS desde cero).
-- Para comparar en la misma escena con el Sandevistan activo: AlphaScale = 0 apaga solo el dibujo de las estelas 3D.
function B.perf() local j = vp(); return j and j.perf and tostring(j.perf()) or "sin medidor (jar ausente o anterior a la 132)" end
function B.reset() local j = vp(); if j and j.resetStats then j.resetStats() end end

-- (134) Lluvia congelada en 3D: la velocidad de la lluvia y la nieve de Viewpoint sigue a SD.precipFactor (Config.FX.Precip); solo se manda al cambiar.
B.precip = 1
function B.tickPrecip()
  local j = vp()
  if not (j and j.precip) then return end
  local SDl = rawget(_G, "SandevistanSlowdown")
  local f = SDl and SDl.precipFactor and SDl.precipFactor() or 1
  if f == B.precip then return end
  B.precip = f
  local P = SandevistanConfig.FX.Precip
  S.try("vpPrecip", function() j.precip(f, P.RampMs, P.Streak) end)
end
Events.OnTick.Add(S.safe("SandevistanViewpoint.precip", B.tickPrecip))

A.backend = B
-- (131) deteccion exacta de la camara 3D (el heuristico de Viewport.lua tarda 2,5 s y queda de respaldo); nil si el jar no puede
-- dibujar en el modo de camara actual (por ejemplo 3D con las estelas 3D apagadas por un error), y ahi manda el heuristico.
V.probe = function()
  local j = vp()
  if j and j.available() then return j.is3D() == true end
  return nil
end

S.log("SandevistanViewpoint: puente de estelas con pose real cargado (" .. (vp() and "jar presente" or "jar ausente") .. ")")

return B
