-- Sandevistan / HUDPanel: dibujo del panel del implante (monitor estilo Edgerunners).
-- Solo dibuja a partir de un "modelo" (tabla con los datos ya calculados), sin tocar el estado del
-- juego: así se puede probar fuera del juego (tools/preview_hud.py). Sin texturas de 9 cortes ni
-- subtexturas: el marco son cuatro esquinas (PNG de 14x14) más rectángulos, para no depender de
-- llamadas de dibujo poco usadas.
--
-- Modelo (m):
--   color = {r,g,b}      color de la variante
--   title, levelText     "PROTOTYPE 05" / "Lv 2" (levelText nil si no hay implante operativo)
--   stateKey, stateText  overdrive | armed | active | cooling | ready | destroyed
--   style                "lab" (placa de circuito impreso, v0.1.30 (70)) | "military" (fibra de carbono / aluminio, v0.1.30 (71)): los dos los dibuja drawLab; el
--                        resto (monitor neural, implante destruido) conserva el diseno de siempre
--   prototype, plate     (lab) "04" | "06" | "07" | nil y el nombre de la placa que le puso el jugador (P06 / Mk. II; nil = el titulo por defecto)
--   expanded             false = panel comprimido (mas angosto y con menos aire); true = modo avanzado con Rechazo y Neural
--   idle                 true = panel atenuado
--   working              hay implante operativo (muestra Heat, Rechazo, Cobertura)
--   heat, rejection, neural (0..100), coverageHours (solo el número: sin barra)
--   cyber                cyberpsicosis activa
--   statuses             lista { icon, text, r, g, b } (filas tipo moodle; vacía si las muestra Moodle Framework)
--   flash (0..1), glitching, glitchDX, timeMs
require "Sandevistan/Core"

local CFG = SandevistanConfig
local S = Sandevistan

SandevistanHUDPanel = {}
local P = SandevistanHUDPanel

P.BASE_W = 256
P.COMPACT_W = 224
local CORNER = 14
local FILL = { 0.075, 0.09, 0.125 }          -- fondo (se tiñe con el color de la variante)
local FILL_A = 0.80

---------------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------------
local TEX = {}
local function tex(name)
  local t = TEX[name]
  if t == nil then
    t = getTexture("media/ui/Sandevistan_HUD_" .. name .. ".png") or false
    if not t then S.warnOnce("hudtex_" .. name, "no se encontró la textura del HUD " .. name) end
    TEX[name] = t
  end
  return t or nil
end

-- (58) Todo lo que no cambia entre cuadros se calcula una vez: ancho de un texto, alto de una fuente, texto traducido y numeros chicos como texto. Antes cada cuadro
-- hacia ~40 KB de basura (closures de pcall, getText, string.format) y el recolector se llevaba parte del 5 % de tiempo que costaba el HUD.
local MEASURE, MEASURE_N = {}, 0
local function measure(font, text)
  local byFont = MEASURE[font]
  local w = byFont and byFont[text]
  if w then return w end
  local ok, mw = pcall(function() return getTextManager():MeasureStringX(font, text) end)
  w = (ok and mw) or string.len(text) * 6
  if MEASURE_N >= 300 then MEASURE, MEASURE_N = {}, 0; byFont = nil end              -- tope por si el texto es cambiante (glitch)
  if not byFont then byFont = {}; MEASURE[font] = byFont end
  byFont[text] = w; MEASURE_N = MEASURE_N + 1
  return w
end

local FONT_H = {}
local function fontHeight(font)
  local h = FONT_H[font]
  if h then return h end
  local ok, fh = pcall(function() return getTextManager():getFontHeight(font) end)
  h = (ok and fh and fh > 0) and fh or 14
  FONT_H[font] = h
  return h
end

local TEXTS = {}
local function T(key)                      -- getText cacheado (el idioma no cambia con la partida en marcha)
  local t = TEXTS[key]
  if not t then t = getText(key); TEXTS[key] = t end
  return t
end
P.text = T

local INTS = {}
local function istr(n)                     -- "%d" de math.floor(n), cacheado para 0..100
  n = math.floor(n)
  if n < 0 or n > 100 then return string.format("%d", n) end
  local s = INTS[n]
  if not s then s = string.format("%d", n); INTS[n] = s end
  return s
end

local HOURS = {}
local function hstr(h)                     -- "%.0f h"
  local n = math.floor(h + 0.5)
  if n < 0 or n > 200 then return string.format("%.0f h", h) end
  local s = HOURS[n]
  if not s then s = string.format("%d h", n); HOURS[n] = s end
  return s
end

local GLITCH_CHARS = { "#", "%", "?", "/", "0", "1", "&" }
local function garble(n)
  local t = {}
  for i = 1, n do t[i] = GLITCH_CHARS[ZombRand(#GLITCH_CHARS) + 1] end
  return table.concat(t)
end

local function clamp01(v) return math.max(0, math.min(1, v)) end

---------------------------------------------------------------------------
-- Zonas de color de cada barra
---------------------------------------------------------------------------
-- cap (0..1): tope de Heat (cicatriz térmica). Sobre el tope, la barra queda en rojo bloqueado.
local HEAT_ZONES = {}
local function heatZones(color, cap)
  cap = cap or 1
  local key = color[1] .. "|" .. color[2] .. "|" .. color[3] .. "|" .. cap
  local z = HEAT_ZONES[key]
  if z then return z end
  z = { { upTo = 0.75 * cap, color[1], color[2], color[3] }, { upTo = cap, 1, 0.3, 0.1 } }
  if cap < 1 then z[#z + 1] = { upTo = 1.0, 1.0, 0.16, 0.12 } end
  local n = 0
  for _ in pairs(HEAT_ZONES) do n = n + 1 end
  if n >= 16 then HEAT_ZONES = {} end                                -- el tope de Heat baja de a 5: pocas combinaciones
  HEAT_ZONES[key] = z
  return z
end

-- Implante bloqueado: toda la barra de Heat en rojo (el Heat real queda más brillante).
local LOCKED_ZONES = { { upTo = 1.0, 1.0, 0.16, 0.12 } }

local REJECTION_ZONES = {
  { upTo = 0.25, 0.75, 0.85, 0.25 }, { upTo = 0.50, 0.95, 0.80, 0.20 },
  { upTo = 0.75, 1.00, 0.55, 0.15 }, { upTo = 1.00, 1.00, 0.20, 0.20 },
}

local REJ_TICKS = { 0.25, 0.5, 0.75 }
local NEURAL_TICKS_T = nil
local function NEURAL_TICKS()
  if not NEURAL_TICKS_T then local z = CFG.NeuralLoad.Zones; NEURAL_TICKS_T = { z.risk / 100, z.critical / 100, z.cyberpsychosis / 100 } end
  return NEURAL_TICKS_T
end
local NEURAL_ZONES = nil
local function neuralZones()
  if NEURAL_ZONES then return NEURAL_ZONES end
  local z = CFG.NeuralLoad.Zones
  NEURAL_ZONES = {
    { upTo = z.risk / 100, 0.30, 0.85, 0.40 }, { upTo = z.critical / 100, 0.95, 0.85, 0.20 },
    { upTo = z.cyberpsychosis / 100, 1.0, 0.50, 0.10 }, { upTo = 1.0, 0.95, 0.15, 0.25 },
  }
  return NEURAL_ZONES
end


---------------------------------------------------------------------------
-- Piezas
---------------------------------------------------------------------------
-- Marco: cuatro esquinas de 14x14 + bordes de 1 px + relleno. (El laboratorio ya no lo usa: dibuja su propia placa, ver drawLab.)
local function frame(ui, w, h, a, r, g, b, lite)
  local c = CORNER
  local fr, fg, fb, fa = FILL[1] * r, FILL[2] * g, FILL[3] * b, FILL_A * a
  if lite then                                                           -- (58) panel en reposo (muy atenuado): fondo, borde y tira de acento
    ui:drawRect(0, 0, w, h, fa, fr, fg, fb)
    ui:drawRectBorder(0, 0, w, h, 0.92 * a, r, g, b)
    ui:drawRect(1, c, 2, h - 2 * c, 0.85 * a, r, g, b)
    return
  end
  local tl, tr, bl, br = tex("CornerTL"), tex("CornerTR"), tex("CornerBL"), tex("CornerBR")
  -- relleno (sin las esquinas)
  ui:drawRect(c, 1, w - 2 * c, c - 1, fa, fr, fg, fb)
  ui:drawRect(1, c, w - 2, h - 2 * c, fa, fr, fg, fb)
  ui:drawRect(c, h - c, w - 2 * c, c - 1, fa, fr, fg, fb)
  -- línea interior tenue (a 3 px del borde)
  ui:drawRect(c, 3, w - 2 * c, 1, 0.16 * a, r, g, b)
  ui:drawRect(c, h - 4, w - 2 * c, 1, 0.16 * a, r, g, b)
  ui:drawRect(3, c, 1, h - 2 * c, 0.16 * a, r, g, b)
  ui:drawRect(w - 4, c, 1, h - 2 * c, 0.16 * a, r, g, b)
  -- bordes
  ui:drawRect(c, 0, w - 2 * c, 1, 0.92 * a, r, g, b)
  ui:drawRect(c, h - 1, w - 2 * c, 1, 0.92 * a, r, g, b)
  ui:drawRect(0, c, 1, h - 2 * c, 0.92 * a, r, g, b)
  ui:drawRect(w - 1, c, 1, h - 2 * c, 0.92 * a, r, g, b)
  -- esquinas
  if tl and tr and bl and br then
    ui:drawTextureScaled(tl, 0, 0, c, c, a, r, g, b)
    ui:drawTextureScaled(tr, w - c, 0, c, c, a, r, g, b)
    ui:drawTextureScaled(bl, 0, h - c, c, c, a, r, g, b)
    ui:drawTextureScaled(br, w - c, h - c, c, c, a, r, g, b)
  else
    ui:drawRectBorder(0, 0, w, h, 0.92 * a, r, g, b)
  end
  -- tira de acento a la izquierda
  ui:drawRect(1, c + 2, 2, h - 2 * c - 4, 0.85 * a, r, g, b)
end

-- Halo exterior (anillos concéntricos que se desvanecen hacia fuera).
local function halo(ui, w, h, a, r, g, b)
  if a <= 0.01 then return end
  for i = 1, 7 do
    local f = 1 - (i - 1) / 7
    ui:drawRectBorder(-i, -i, w + 2 * i, h + 2 * i, a * f * f * 0.55, r, g, b)
  end
end

-- Cápsula (rectángulo con las esquinas de 1 px recortadas).
local function pill(ui, x, y, w, h, a, r, g, b)
  ui:drawRect(x + 1, y, w - 2, h, a, r, g, b)
  ui:drawRect(x, y + 1, w, h - 2, a, r, g, b)
end

local function pillLine(ui, x, y, w, h, a, r, g, b)
  ui:drawRect(x + 1, y, w - 2, 1, a, r, g, b)
  ui:drawRect(x + 1, y + h - 1, w - 2, 1, a, r, g, b)
  ui:drawRect(x, y + 1, 1, h - 2, a, r, g, b)
  ui:drawRect(x + w - 1, y + 1, 1, h - 2, a, r, g, b)
end

local LITE = false            -- (58) lo fija P.draw por cuadro: panel en reposo sin sombras de texto ni segmentos sueltos
local function shadowText(ui, text, x, y, r, g, b, a, font)
  if not LITE then ui:drawText(text, x + 1, y + 1, 0, 0, 0, 0.65 * a, font) end
  ui:drawText(text, x, y, r, g, b, a, font)
end

local function shadowTextRight(ui, text, x, y, r, g, b, a, font)
  if not LITE then ui:drawTextRight(text, x + 1, y + 1, 0, 0, 0, 0.65 * a, font) end
  ui:drawTextRight(text, x, y, r, g, b, a, font)
end

local function icon(ui, name, x, y, size, a, r, g, b)
  local t = tex(name)
  if t then ui:drawTextureScaled(t, x, y, size, size, a, r, g, b) end
end

-- Barra de segmentos coloreada por zonas. Devuelve nada; dibuja en (x, y, w, h).
-- v0.1.30: cada segmento encendido es UN rectángulo (antes dos: mitad clara y mitad oscura) y el brillo va como una línea fina por tramo
-- de zona encima de todo lo encendido. Mismo aspecto a la vista con ~1/3 menos de llamadas de dibujo (el panel era lo más caro del mod).
P.FAST_BARS = true

-- (61) Geometria de una barra (posicion y ancho de cada segmento y su zona de color) calculada UNA vez por (zonas, ancho, segmentos). El microbenchmark de la (60) mostro que el
-- panel costaba ~200 us de Lua puro por encima de las primitivas de dibujo (que valen 1-3 us cada una): recalcular en cada cuadro los ~100 segmentos de las tres barras (floor, busqueda
-- de zona) era lo mas pesado, y en reposo se hacia igual aunque casi todos los segmentos estuvieran apagados.
local GEOM = setmetatable({}, { __mode = "k" })
local function geometry(zones, w, n)
  local byZones = GEOM[zones]
  if not byZones then byZones = {}; GEOM[zones] = byZones end
  local key = w * 1000 + n
  local g = byZones[key]
  if g then return g end
  g = { off = {}, sw = {}, zr = {}, zg = {}, zb = {}, zid = {} }
  local segW = w / n
  for i = 0, n - 1 do
    local o0 = math.floor(i * segW + 0.5)
    local o1 = math.floor((i + 1) * segW + 0.5) - 1
    g.off[i] = o0; g.sw[i] = math.max(1, o1 - o0)
    local f, zi = (i + 0.5) / n, #zones
    for jj, z in ipairs(zones) do if f <= z.upTo then zi = jj; break end end
    local z = zones[zi]
    g.zr[i], g.zg[i], g.zb[i], g.zid[i] = z[1], z[2], z[3], zi
  end
  byZones[key] = g
  return g
end

local OFF = { x0 = 0, x1 = 0, zi = 0, a = 0, r = 0, g = 0, b = 0 }     -- tramo apagado en curso (modo liviano); se reusa: sin tabla nueva por barra
local function segBar(ui, x, y, w, h, frac, zones, a, opts)
  opts = opts or {}
  frac = clamp01(frac)
  local n = math.max(10, math.floor(w / (opts.segPx or 5)))
  local G = geometry(zones, w, n)
  local goff, gsw, gzr, gzg, gzb, gzid = G.off, G.sw, G.zr, G.zg, G.zb, G.zid
  ui:drawRect(x - 1, y - 1, w + 2, h + 2, 0.92 * a, 0.02, 0.02, 0.03)
  local lit = opts.whole and math.floor(frac * n + 0.5) or frac * n     -- whole: solo segmentos enteros (nunca uno a medio iluminar)
  local pulse = opts.pulse and (0.75 + 0.25 * math.sin((opts.timeMs or 0) / 120)) or 1
  local runStart = nil
  local offOn = false
  local lite = LITE
  local glowH = math.max(1, math.floor(h * 0.3))
  local offA = ((opts.fullRed) and 0.55 or 0.16) * a
  local lockedFrom = opts.lockedFrom
  for i = 0, n - 1 do
    local x0 = x + goff[i]
    local sw = gsw[i]
    local zr, zg, zb, zi = gzr[i], gzg[i], gzb[i], gzid[i]
    local isLit = i + 1 <= lit + 1e-6
    if isLit then                                       -- segmento encendido: un rectangulo y el brillo por tramo de zona
      ui:drawRect(x0, y, sw, h, 0.94 * a * pulse, zr * 0.9, zg * 0.9, zb * 0.9)
      runStart = runStart or x0
      local nextLit = i + 2 <= lit + 1e-6 and i + 1 < n
      if not nextLit or gzid[i + 1] ~= zi then
        ui:drawRect(runStart, y, x0 + sw - runStart, glowH, 0.55 * a * pulse, math.min(1, zr * 1.3), math.min(1, zg * 1.3), math.min(1, zb * 1.3))
        runStart = nil
      end
    elseif i < lit then                                 -- segmento parcial
      local pw = math.max(1, math.floor(sw * (lit - i)))
      ui:drawRect(x0, y, sw, h, offA, zr, zg, zb)
      ui:drawRect(x0, y, pw, h, 0.9 * a * pulse, zr, zg, zb)
    else                                                -- apagado: se ve la zona (bloqueado: rojo tenue en toda la barra)
      local ga = offA
      if lockedFrom and (i + 0.5) / n > lockedFrom then ga = 0.55 * a end
      if lite then
        -- reposo: los segmentos apagados de la misma zona se dibujan como UN rectangulo (sin las rayitas entre segmentos, que a esta opacidad no se ven)
        if offOn and OFF.zi == zi and OFF.a == ga then
          OFF.x1 = x0 + sw
        else
          if offOn then ui:drawRect(OFF.x0, y, OFF.x1 - OFF.x0, h, OFF.a, OFF.r, OFF.g, OFF.b) end
          offOn = true
          OFF.x0, OFF.x1, OFF.zi, OFF.a, OFF.r, OFF.g, OFF.b = x0, x0 + sw, zi, ga, zr, zg, zb
        end
      else
        ui:drawRect(x0, y, sw, h, ga, zr, zg, zb)
      end
    end
    if offOn and (isLit or i < lit) then               -- llego un segmento encendido: se cierra el tramo apagado
      ui:drawRect(OFF.x0, y, OFF.x1 - OFF.x0, h, OFF.a, OFF.r, OFF.g, OFF.b); offOn = false
    end
  end
  if offOn then ui:drawRect(OFF.x0, y, OFF.x1 - OFF.x0, h, OFF.a, OFF.r, OFF.g, OFF.b) end
  -- marcas de zona
  if opts.ticks and not LITE then
    for _, f in ipairs(opts.ticks) do
      local tx = x + math.floor(f * w + 0.5)
      ui:drawRect(tx, y - 3, 1, 2, 0.55 * a, 1, 1, 1)
      ui:drawRect(tx, y + h + 1, 1, 2, 0.55 * a, 1, 1, 1)
    end
  end
  if opts.alert then                                  -- contorno parpadeante en zona crítica
    ui:drawRectBorder(x - 2, y - 2, w + 4, h + 4, 0.55 * a * pulse, 1, 0.25, 0.1)
  end
end

---------------------------------------------------------------------------
-- Diseño y dibujo
---------------------------------------------------------------------------
-- Escala de layout: U[n] = floor(n * k + 0.5), memoizado por k (el __index calcula la primera vez y guarda).
local UCACHE = {}
local function uTable(k)
  local U = UCACHE[k]
  if not U then
    U = setmetatable({}, { __index = function(t, n) local v = math.floor(n * k + 0.5); rawset(t, n, v); return v end })
    UCACHE[k] = U
  end
  return U
end

-- Dibuja sobre "ui" desplazado (ox, oy): para incrustar el panel en otra vista (pestaña Implante).
local function offsetUI(ui, ox, oy)
  return {
    drawRect = function(_, x, y, w, h, a, r, g, b) ui:drawRect(x + ox, y + oy, w, h, a, r, g, b) end,
    drawRectBorder = function(_, x, y, w, h, a, r, g, b) ui:drawRectBorder(x + ox, y + oy, w, h, a, r, g, b) end,
    drawText = function(_, text, x, y, r, g, b, a, font) ui:drawText(text, x + ox, y + oy, r, g, b, a, font) end,
    drawTextRight = function(_, text, x, y, r, g, b, a, font) ui:drawTextRight(text, x + ox, y + oy, r, g, b, a, font) end,
    drawTextureScaled = function(_, t, x, y, w, h, a, r, g, b) ui:drawTextureScaled(t, x + ox, y + oy, w, h, a, r, g, b) end,
  }
end

---------------------------------------------------------------------------
-- Laboratorio (v0.1.30 (70)): placa de circuito impreso con indicadores fijos, como un aparato de los 90. Todo lo estatico es una textura (la placa con sus chips y
-- su serigrafia, la cinta rotulada a mano, los tornillos); lo que cambia son leds, digitos de 7 segmentos (una textura por digito, teñidos) y las barras de siempre.
-- Las medidas (a escala 1) son las de tools/gen_hud_lab.py: ancho 256; titulo y nivel arriba, fila de estado, y una fila de LAB.RP por barra.
--   Comprimido: solo Heat (la cobertura va como lampara en la fila de estado). Expandido: Heat, Rechazo y Carga Neural.
-- La tipografia es una sola, monoespaciada (Code de vanilla si existe). Sin texto que cambie de estado: ACTIVE y OVERDRIVE son rotulos fijos con su led.
---------------------------------------------------------------------------
local LAB = { W = 256, ROW0 = 56, RP = 33, FOOT = 22 }
P.LAB = LAB
local EDGE = { 0.27, 0.47, 0.43 }                 -- borde de las ranuras (verde de la placa, mas claro)
local SLOT = { 0.02, 0.08, 0.09 }                 -- fondo de las ranuras
local SILK = { 0.89, 0.94, 0.91 }                 -- serigrafia
local LABEL = { 0.75, 0.84, 0.80 }                -- rotulos
local ICON_TEX = { heat = "LabIconHeat", rej = "LabIconRej", neural = "LabIconNeural" }

local CODE_S, CODE_M
-- (130) CodeSmall/CodeMedium de vanilla solo traen letras latinas (RU no las reemplaza): en idiomas con otro alfabeto se usan Small/Medium,
-- que el juego si cambia por la version del idioma (en RU, zomboidSmallCyrillic).
local NON_LATIN = { RU = true, UA = true, CH = true, CN = true, JP = true, KO = true, TH = true }
local function codeFonts()
  if not CODE_S then
    local lang
    pcall(function() lang = tostring(Translator.getLanguage()) end)
    if lang and NON_LATIN[lang] then
      CODE_S, CODE_M = UIFont.Small, UIFont.Medium
      return CODE_S, CODE_M
    end
    local ok, f = pcall(function() return UIFont.CodeSmall end)
    CODE_S = (ok and f) or UIFont.Small
    ok, f = pcall(function() return UIFont.CodeMedium end)
    CODE_M = (ok and f) or UIFont.Medium
  end
  return CODE_S, CODE_M
end

local SEGT, SEGTS = {}, {}                          -- digitos grandes (cajas de numeros) y chicos (nivel y horas), por caracter
local function segTex(ch, small)
  local cache = small and SEGTS or SEGT
  local t = cache[ch]
  if t == nil then t = tex((small and "LabSegS" or "LabSeg") .. ch) or false; cache[ch] = t end
  return t or nil
end

local NUMTXT = {}                                  -- "  0".." 99" de dos caracteres; 100 o mas = "Er" (caso teorico: error)
for n = 0, 99 do NUMTXT[n] = n < 10 and (" " .. n) or tostring(n) end
local function numText(v)
  v = math.floor(v)
  if v >= 100 then return "Er" end
  if v < 0 then v = 0 end
  return NUMTXT[v]
end
local FOOT_TXT = {}
local function footText(proto)
  local key = proto or "05"
  local t = FOOT_TXT[key]
  if not t then t = "SDV-" .. key .. "  REV.B"; FOOT_TXT[key] = t end
  return t
end

-- Dos digitos de 7 segmentos (lo apagado se ve tenue). x, y: esquina del primero.
local function sevenSeg(ui, x, y, dw, dh, gap, text, a, r, g, b, ghost, small)
  if ghost then
    local off = tex(small and "LabSegSOff2" or "LabSegOff2")
    if off then ui:drawTextureScaled(off, x, y, 2 * dw + gap, dh, 0.16 * a, r, g, b) end
  end
  local x1 = x
  for i = 1, 2 do
    local ch = string.sub(text, i, i)
    if ch ~= " " and ch ~= "" then
      local tx = segTex(ch, small)
      if tx then ui:drawTextureScaled(tx, x1, y, dw, dh, a, r, g, b) end
    end
    x1 = x1 + dw + gap
  end
end

-- Led: bisel, punto teñido (apagado = muy oscuro) y resplandor si esta encendido.
local function led(ui, U, cx, cy, r, g, b, lit, a, glow, small)
  local rs, ds = U[12], U[8]
  if small then rs, ds = U[9], U[6] end
  if lit and glow and CFG.HUD.LedGlow then
    local gl = tex("LabLedGlow")
    if gl then ui:drawTextureScaled(gl, cx - U[12], cy - U[12], U[24], U[24], 0.55 * a, r, g, b) end
  end
  local ring, dot = tex("LabLedRing"), tex("LabLedDot")
  if ring then ui:drawTextureScaled(ring, cx - math.floor(rs / 2), cy - math.floor(rs / 2), rs, rs, a, 1, 1, 1) end
  local f = lit and 1 or 0.18
  if dot then ui:drawTextureScaled(dot, cx - math.floor(ds / 2), cy - math.floor(ds / 2), ds, ds, a, r * f, g * f, b * f)
  else ui:drawRect(cx - 3, cy - 3, 6, 6, a, r * f, g * f, b * f) end
end

-- Cuadro hundido con un numero de dos digitos (la caja mide lo que los digitos mas el marco).
local function numBox(ui, U, x, y, text, a, r, g, b, ghost)
  local bw, bh = U[20], U[18]
  if not LITE then ui:drawRect(x - 1, y - 1, bw + 2, bh + 2, 0.95 * a, EDGE[1], EDGE[2], EDGE[3]) end            -- en reposo (muy atenuado) sin el borde: menos llamadas
  ui:drawRect(x, y, bw, bh, 0.97 * a, SLOT[1], SLOT[2], SLOT[3])
  local dw, dh, gap = U[7], U[13], U[2]
  sevenSeg(ui, x + math.floor((bw - (2 * dw + gap)) / 2), y + math.floor((bh - dh) / 2), dw, dh, gap, text, a, r, g, b, ghost)
end

local ROWOPT = {}                                  -- se reusa: sin tabla nueva por barra
-- Una barra con su rotulo arriba, el icono cuadrado a la izquierda y el numero en su caja a la derecha. ry = arriba de la fila.
local function labRow(ui, U, ry, iconKey, label, frac, zones, value, a, o, small, hS, t, glitch, ghost)
  local barX, barW, barH = U[28], U[196], U[14]
  local by = ry + U[15]
  local lab, txt, f = label, numText(value), frac
  if glitch then
    f = clamp01(f + ZombRandFloat(0, 0.5) - 0.25)
    txt = NUMTXT[ZombRand(100)]
    if ZombRand(3) == 0 then lab = garble(string.len(lab)) end
  end
  ui:drawText(lab, barX, ry + math.floor((U[14] - hS) / 2), LABEL[1], LABEL[2], LABEL[3], a, small)
  -- icono: marco cuadrado + simbolo teñido
  local ix, iy = U[8], by + math.floor((barH - U[14]) / 2)
  if LITE then
    ui:drawRect(ix, iy, U[14], U[14], 0.97 * a, SLOT[1], SLOT[2], SLOT[3])
  else
    ui:drawRect(ix, iy, U[14], U[14], 0.95 * a, EDGE[1], EDGE[2], EDGE[3])
    ui:drawRect(ix + 1, iy + 1, U[14] - 2, U[14] - 2, 0.97 * a, SLOT[1], SLOT[2], SLOT[3])
  end
  local it = tex(ICON_TEX[iconKey])
  if it then ui:drawTextureScaled(it, ix + U[2], iy + U[2], U[10], U[10], 0.95 * a, o.ir, o.ig, o.ib) end
  -- barra (marco verde alrededor del fondo oscuro que dibuja segBar)
  if not LITE then ui:drawRectBorder(barX - 2, by - 2, barW + 4, barH + 4, 0.9 * a, EDGE[1], EDGE[2], EDGE[3]) end
  segBar(ui, barX, by, barW, barH, f, zones, a, { ticks = o.ticks, alert = o.alert, pulse = o.pulse, timeMs = t, segPx = U[9], fullRed = o.fullRed, lockedFrom = o.lockedFrom, whole = true })
  -- numero
  if not o.hideNumber then numBox(ui, U, U[228], by + math.floor((barH - U[18]) / 2), txt, a, o.dr, o.dg, o.db, ghost) end
end

-- Nombre en la placa: cinta rotulada a mano (P05, P04) o serigrafia con el nombre real (P06 y Mk. II: el jugador puede cambiarlo).
local function namePlate(ui, U, m, a, small, med, hS, glitch)
  local x, y, w, h = U[22], U[8], U[178], U[22]
  if m.disconnected then                                     -- (165b) T12: la placa queda apagada y rotulada; no se dibuja la cinta del modelo
    local text = m.title or ""
    ui:drawRect(x, y, w, h, 0.88 * a, 0.10, 0.05, 0.04)
    ui:drawRectBorder(x, y, w, h, 0.95 * a, 0.85, 0.35, 0.20)
    ui:drawText(text, x + U[8], y + math.floor((h - hS) / 2) + U[1], 0.95, 0.55, 0.30, a, small)
    return
  end
  if m.style == "military" then
    if m.prototype ~= "07" then                             -- el militar original: etiqueta de serie (de fabrica, no se renombra)
      local lb = tex("MilLabel")
      if lb then ui:drawTextureScaled(lb, x - U[3], y - U[4], U[184], U[30], a, 1, 1, 1); return end
    else                                                     -- la replica (Mk. II): chapa anodizada con el nombre grabado, que el jugador puede cambiar
      local pl = tex("MilPlate")
      if pl then
        ui:drawTextureScaled(pl, x - U[3], y - U[4], U[184], U[30], a, 1, 1, 1)
        local text = m.title or ""
        if glitch and ZombRand(2) == 0 then text = garble(string.len(text)) end
        local tx, ty = x + U[22], y + math.floor((h - hS) / 2)
        ui:drawText(text, tx + 1, ty + 1, 0.03, 0.035, 0.04, a, small)         -- grabado: sombra y letra clara encima (letra chica, como el resto)
        ui:drawText(text, tx, ty, 0.84, 0.87, 0.91, a, small)
        return
      end
    end
  end
  local tapeName = (m.prototype == nil and "LabTape05") or (m.prototype == "04" and "LabTape04") or nil
  local tt = (tapeName and not m.plate) and tex(tapeName) or nil
  if tt then
    ui:drawTextureScaled(tt, x - U[3], y - U[3], U[184], U[28], a, 1, 1, 1)
    return
  end
  local text = m.title or ""
  if glitch and ZombRand(2) == 0 then text = garble(string.len(text)) end
  ui:drawRectBorder(x, y, w, h, 0.9 * a, SILK[1], SILK[2], SILK[3])
  local tab = tex("LabIdTab")                                        -- pestaña "ID" (textura: las letras son diminutas, como la serigrafia de un circuito)
  if tab then ui:drawTextureScaled(tab, x, y, U[14], U[8], 0.95 * a, 1, 1, 1)
  else ui:drawRect(x, y, U[14], U[8], 0.9 * a, SILK[1], SILK[2], SILK[3]) end
  ui:drawText(text, x + U[20], y + math.floor((h - hS) / 2) + U[1], SILK[1], SILK[2], SILK[3], a, small)       -- el nombre va con la letra chica (la grande se veia desproporcionada)
end

local function drawLab(ui, m, k, U)
  local W = U[LAB.W]
  local small, med = codeFonts()
  local hS = fontHeight(small)
  local a = m.alpha or (m.idle and 0.5 or 1.0)
  local r, g, b = m.color[1], m.color[2], m.color[3]
  local t = m.timeMs or 0
  local glitch = m.glitching
  local nRows = m.expanded and 3 or 1
  local statuses = m.statuses
  local chipH = math.max(hS + 2, U[16])
  local chipsH = (statuses and #statuses > 0) and (U[5] + #statuses * (chipH + U[2])) or 0
  local rowsEnd = U[LAB.ROW0] + nRows * U[LAB.RP]
  local H = rowsEnd + chipsH + U[LAB.FOOT]

  -- halo exterior segun el estado (igual que el resto de los paneles)
  local hr, hg, hb, ha = r, g, b, 0
  if m.stateKey == "overdrive" then hr, hg, hb, ha = 1, 0.15, 0.1, 0.55 + 0.25 * math.sin(t / 90)
  elseif m.stateKey == "armed" then hr, hg, hb, ha = 1, 0.6, 0.15, 0.42
  elseif m.working and (m.heatPct or m.heat) >= 75 then hr, hg, hb, ha = 1, 0.25, 0.1, 0.22 + ((math.floor(t / 250) % 2 == 0) and 0.2 or 0)
  elseif m.stateKey == "active" then ha = 0.30 end
  if (m.flash or 0) > 0 then ha = math.max(ha, 0.65 * m.flash); if m.stateKey == "ready" then hr, hg, hb = r, g, b end end
  halo(ui, W, H, ha * (m.idle and 0.5 or 1), hr, hg, hb)

  -- placa, tornillos y el agujero que se hizo por error junto al de abajo a la derecha
  local mil = m.style == "military"
  local replica = mil and m.prototype == "07"
  local bname = (not mil) and (m.expanded and "LabBoardFull" or "LabBoardCompact")
                or replica and (m.expanded and "MilAlumFull" or "MilAlumCompact")
                or (m.expanded and "MilCarbonFull" or "MilCarbonCompact")
  local board = tex(bname)
  if board then ui:drawTextureScaled(board, 0, 0, W, H, a, 1, 1, 1)
  else ui:drawRect(0, 0, W, H, 0.95 * a, 0.063, 0.227, 0.196); ui:drawRectBorder(0, 0, W, H, a, 0.12, 0.49, 0.44) end
  local ss = U[8]
  if replica then                                           -- el Mk. II no lleva tornillos: puntos de soldadura en las esquinas y un cordon abajo
    local wd, bd = tex("MilWeld"), tex("MilBead")
    if wd then
      ui:drawTextureScaled(wd, U[3], U[3], U[22], U[9], a, 1, 1, 1)
      ui:drawTextureScaled(wd, W - U[25], U[3], U[22], U[9], a, 1, 1, 1)
      ui:drawTextureScaled(wd, U[3], H - U[12], U[22], U[9], a, 1, 1, 1)
      ui:drawTextureScaled(wd, W - U[25], H - U[12], U[22], U[9], a, 1, 1, 1)
    end
    if bd then ui:drawTextureScaled(bd, U[33], H - U[8], U[190], U[4], 0.9 * a, 1, 1, 1) end
  else
    local sc = tex(mil and "MilBolt" or "LabScrew")         -- cuatro tornillos (hexagonales negros en el militar); solo el laboratorio lleva el agujero de mas
    if sc then
      ui:drawTextureScaled(sc, U[1], U[1], ss, ss, a, 1, 1, 1)
      ui:drawTextureScaled(sc, W - ss - U[1], U[1], ss, ss, a, 1, 1, 1)
      ui:drawTextureScaled(sc, U[1], H - ss - U[1], ss, ss, a, 1, 1, 1)
      ui:drawTextureScaled(sc, W - ss - U[1], H - ss - U[1], ss, ss, a, 1, 1, 1)
      local hl = (not mil) and tex("LabHole")
      if hl then ui:drawTextureScaled(hl, W - U[22], H - U[21], ss, ss, a, 1, 1, 1) end
    end
  end

  namePlate(ui, U, m, a, small, med, hS, glitch)

  -- nivel: "LV" suelto y un panelito de dos digitos (la mitad del alto del nombre), encima de la columna de numeros
  if m.levelText then
    local bw, bh = U[16], U[13]
    local bx, by = U[230], U[18]
    ui:drawRect(bx - 1, by - 1, bw + 2, bh + 2, 0.95 * a, EDGE[1], EDGE[2], EDGE[3])
    ui:drawRect(bx, by, bw, bh, 0.97 * a, SLOT[1], SLOT[2], SLOT[3])
    local lv = T("IGUI_Sandevistan_HUD_LvShort")
    ui:drawText(lv, bx - measure(small, lv) - U[3], by + math.floor((bh - hS) / 2), SILK[1], SILK[2], SILK[3], a, small)
    local dw, dh, gap = U[5], U[9], U[1]
    sevenSeg(ui, bx + math.floor((bw - (2 * dw + gap)) / 2), by + math.floor((bh - dh) / 2), dw, dh, gap, numText(m.level or 0), a, SILK[1], SILK[2], SILK[3], not LITE, true)
    if m.xpFrac and not LITE then                          -- progreso hacia el siguiente nivel: una raya bajo el panelito
      ui:drawRect(bx, by + bh + U[2], bw, 1, 0.25 * a, SILK[1], SILK[2], SILK[3])
      ui:drawRect(bx, by + bh + U[2], math.floor(bw * clamp01(m.xpFrac)), 1, 0.95 * a, SILK[1], SILK[2], SILK[3])
    end
  end

  -- fila de estado: rotulos fijos con su led a la derecha. ACTIVE se enciende activo, armado y en overdrive; OVERDRIVE en overdrive (rojo) y armado (amarillo, fijo).
  -- La cobertura (inmunosupresor) va a la derecha: texto, lampara y las horas en 7 segmentos; se calcula primero para que el resto no la pise.
  local sy = U[36]
  local ty = sy + math.floor((U[15] - hS) / 2)
  local sk = m.stateKey
  local onActive = sk == "active" or sk == "armed" or sk == "overdrive"
  local cov = (m.coverageHours or 0) > 0
  local covTxt = T("IGUI_Sandevistan_HUD_CovShort")
  local mh = measure(small, "h")
  local dgW = 2 * U[5] + U[2]                                       -- ancho de las dos cifras de las horas
  local dgX = W - U[8] - mh - U[3] - dgW
  local lx = dgX - U[4] - U[6]
  local covX = lx - U[6] - U[4] - measure(small, covTxt)
  local x = U[24]
  -- (130) rotulos propios de la placa: el ancho es fijo y en ruso "АКТИВЕН ОВЕРДРАЙВ" no entraba (el led pisaba el texto)
  local txtA, txtO = T("IGUI_Sandevistan_HUD_PlateActive"), T("IGUI_Sandevistan_HUD_PlateOverdrive")
  ui:drawText(txtA, x, ty, LABEL[1], LABEL[2], LABEL[3], a, small)
  x = x + measure(small, txtA) + U[9]
  led(ui, U, math.min(x, covX - U[16]), sy + U[7], r, g, b, onActive, a, not LITE)
  x = x + U[13]
  ui:drawText(txtO, x, ty, LABEL[1], LABEL[2], LABEL[3], a, small)
  x = x + measure(small, txtO) + U[9]
  local overLit, or_, og, ob = sk == "overdrive", 1, 0.25, 0.2
  if sk == "armed" then overLit, or_, og, ob = true, 1, 0.85, 0.1 end                  -- armado: luz AMARILLA fija (antes titilaba y en el juego no se notaba)
  led(ui, U, math.min(x, covX - U[10]), sy + U[7], or_, og, ob, overLit, a, not LITE)
  ui:drawText("h", W - U[8] - mh, ty, LABEL[1], LABEL[2], LABEL[3], a, small)
  local hours = cov and math.min(99, math.floor(m.coverageHours + 0.5)) or nil
  sevenSeg(ui, dgX, sy + math.floor((U[15] - U[9]) / 2), U[5], U[9], U[2], hours and numText(hours) or "", a, 1, 0.67, 0.16, false, true)
  led(ui, U, lx, sy + U[7], 1, 0.67, 0.16, cov, a, not LITE)
  ui:drawText(covTxt, covX, ty, LABEL[1], LABEL[2], LABEL[3], a, small)

  -- barras
  local capF = (m.heatCap or 100) / 100
  local hot = (m.heatPct or m.heat) >= 75
  local locked = m.locked and true or false
  local ry = U[LAB.ROW0]
  local o = ROWOPT
  o.ticks, o.alert, o.pulse, o.fullRed, o.lockedFrom, o.hideNumber = { 0.75 * capF }, hot or locked, hot and (math.floor(t / 250) % 2 == 0), locked, capF < 1 and capF or nil, false
  o.ir, o.ig, o.ib = 1, 0.85, 0.5
  if hot or locked then o.ir, o.ig, o.ib = 1, 0.45, 0.3 else o.ir, o.ig, o.ib = r, g, b end
  o.dr, o.dg, o.db = r, g, b
  if hot or locked or m.heat >= 100 then o.dr, o.dg, o.db = 1, 0.35, 0.3 end
  if sk == "cooling" and (math.floor(t / 350) % 2 == 1) then o.hideNumber = true end          -- bloqueado: el numero de Heat parpadea mientras baja
  labRow(ui, U, ry, "heat", T("IGUI_Sandevistan_HUD_Heat"), m.heat / 100, locked and LOCKED_ZONES or heatZones(m.color, capF), m.heat, a, o, small, hS, t, glitch, not LITE)
  if m.expanded then
    ry = ry + U[LAB.RP]
    o.ticks, o.alert, o.pulse, o.fullRed, o.lockedFrom, o.hideNumber = REJ_TICKS, m.rejection >= 75, false, false, nil, false
    o.ir, o.ig, o.ib = 0.95, 0.8, 0.2
    o.dr, o.dg, o.db = 0.95, 0.8, 0.2
    if m.rejection >= 75 then o.dr, o.dg, o.db = 1, 0.45, 0.2 end
    labRow(ui, U, ry, "rej", T("IGUI_Sandevistan_HUD_Rejection"), m.rejection / 100, REJECTION_ZONES, m.rejection, a, o, small, hS, t, glitch, not LITE)
    ry = ry + U[LAB.RP]
    o.ticks, o.alert, o.pulse = NEURAL_TICKS(), m.cyber, false
    o.ir, o.ig, o.ib = 1, 0.5, 0.7
    o.dr, o.dg, o.db = 1, 0.5, 0.7
    if m.cyber or m.neural >= 100 then o.dr, o.dg, o.db = 1, 0.3, 0.3 end
    labRow(ui, U, ry, "neural", T("IGUI_Sandevistan_HUD_CN"), m.neural / 100, neuralZones(), m.neural, a, o, small, hS, t, glitch, not LITE)
  end

  -- estados (filas tipo moodle) debajo de las barras
  if chipsH > 0 then
    local y = rowsEnd + U[5]
    for _, st in ipairs(statuses) do
      local text = st.text
      if glitch and ZombRand(4) == 0 then text = garble(string.len(text)) end
      ui:drawRect(U[8], y, W - 2 * U[8], chipH, 0.8 * a, st.r * 0.2, st.g * 0.2, st.b * 0.2)
      ui:drawRect(U[8], y, 2, chipH, 0.95 * a, st.r, st.g, st.b)
      icon(ui, st.icon, U[8] + U[6], y + math.floor((chipH - U[12]) / 2), U[12], a, st.r, st.g, st.b)
      ui:drawText(text, U[8] + U[23], y + math.floor((chipH - hS) / 2), st.r, st.g, st.b, a, small)
      y = y + chipH + U[2]
    end
  end

  -- serigrafia del pie con el diseno ("SDV-06 REV.B"); no se dibuja en reposo
  if not LITE and not mil then ui:drawText(footText(m.prototype), U[84], H - hS - U[2], 0.75, 0.84, 0.8, 0.55 * a, small) end

  -- (88) dos leds chicos abajo a la izquierda: los slots de firmware (verde = Sistema, violeta = Habilidad); encendido = hay un chip instalado
  if m.fw and not LITE then
    local ly = H - U[12]
    led(ui, U, U[36], ly, 0.24, 1.0, 0.55, m.fw[1], a, false, true)
    led(ui, U, U[48], ly, 0.71, 0.38, 1.0, m.fw[2], a, false, true)
  end

  -- desgarro por glitch
  if glitch then
    for _ = 1, 3 do
      local gy = ZombRand(math.max(1, H - 6))
      ui:drawRect(m.glitchDX or 0, gy, W, 2 + ZombRand(5), 0.5, r, g, b)
    end
  end
  return W, H
end

-- k: escala (>= 1); ox, oy: desplazamiento opcional. Devuelve ancho y alto totales tras dibujar.
function P.draw(ui, m, k, ox, oy)
  k = k or 1
  if (ox and ox ~= 0) or (oy and oy ~= 0) then ui = offsetUI(ui, ox or 0, oy or 0) end
  local U = uTable(k)                                  -- (61) U[n] como lectura de tabla (una llamada de funcion menos por cada uno de los ~35 usos por cuadro)
  -- (58) panel en reposo muy atenuado = version liviana. Se desactiva con glitch o destello (los efectos se ven completos); con cyberpsicosis o implante bloqueado sigue
  -- liviano (las alertas parpadeantes de las barras se dibujan igual). Los contadores del reporte dicen por que no se uso.
  local why = (not m.idle) and "hud.panel.completo.activo" or ((m.alpha or 0.5) > 0.45) and "hud.panel.completo.opaco"
              or m.glitching and "hud.panel.completo.glitch" or ((m.flash or 0) > 0) and "hud.panel.completo.destello" or nil
  LITE = why == nil
  S.perfCount(LITE and "hud.panel.liviano" or why)
  if m.style == "lab" or m.style == "military" then return drawLab(ui, m, k, U) end       -- (70) laboratorio y (71) militar: panel de placa con indicadores fijos
  -- v0.1.30 (38): el panel comprimido (sin el modo avanzado) es mas angosto y con menos aire
  local compact = not m.expanded
  local W = U[compact and P.COMPACT_W or P.BASE_W]
  local small = UIFont.Small
  local titleFont = (k >= 1.35) and UIFont.Large or UIFont.Medium
  local hS, hT = fontHeight(small), fontHeight(titleFont)
  local rowH = math.max(hS + (compact and 2 or 4), U[compact and 15 or 17])
  local pad = U[compact and 9 or 11]
  local a = m.alpha or (m.idle and 0.5 or 1.0)      -- alpha: transición suave del HUD (HUD.lua)
  local r, g, b = m.color[1], m.color[2], m.color[3]
  local t = m.timeMs or 0
  local glitch = m.glitching

  -- ---- filas (se calculan antes para conocer la altura) ----
  local rows = {}
  local function add(h, fn) rows[#rows + 1] = { h = h, fn = fn } end

  local labelX = pad + U[18]
  local LW = U[compact and 66 or 76]
  local VW = U[compact and 30 or 34]
  local barX = labelX + LW
  local barW = W - pad - VW - barX - U[4]
  local barH = U[8]

  local function barRow(iconName, label, frac, zones, valueText, ticks, opts)
    opts = opts or {}
    add(rowH, function(y)
      local f = frac
      local lab, val = label, valueText
      if glitch then
        f = clamp01(f + ZombRandFloat(0, 0.5) - 0.25)
        if val then val = garble(string.len(val)) end
        if ZombRand(3) == 0 then lab = garble(string.len(lab)) end
      end
      local cy = y + math.floor((rowH - U[14]) / 2)
      icon(ui, iconName, pad, cy, U[14], 0.95 * a, opts.iconR or 0.85, opts.iconG or 0.9, opts.iconB or 1)
      shadowText(ui, lab, labelX, y + math.floor((rowH - hS) / 2), 0.86, 0.9, 0.95, a, small)
      segBar(ui, barX, y + math.floor((rowH - barH) / 2), barW, barH, f, zones, (opts.alpha or 1) * a,
             { ticks = ticks, alert = opts.alert, pulse = opts.pulse, timeMs = t, segPx = U[8], fullRed = opts.fullRed })
      if val then
        local vr, vg, vb = 1, 1, 1
        if opts.alert then vr, vg, vb = 1, 0.55, 0.45 end
        shadowTextRight(ui, val, W - pad, y + math.floor((rowH - hS) / 2), vr, vg, vb, a, small)
      end
    end)
  end

  -- fila solo de texto (ícono, nombre y valor a la derecha): la cobertura muestra las horas, sin barra
  local function textRow(iconName, label, valueText, opts)
    opts = opts or {}
    add(rowH, function(y)
      local lab, val = label, valueText
      if glitch then
        if val then val = garble(string.len(val)) end
        if ZombRand(3) == 0 then lab = garble(string.len(lab)) end
      end
      local cy = y + math.floor((rowH - U[14]) / 2)
      local al = (opts.alpha or 1) * a
      icon(ui, iconName, pad, cy, U[14], 0.95 * al, opts.iconR or 0.85, opts.iconG or 0.9, opts.iconB or 1)
      shadowText(ui, lab, labelX, y + math.floor((rowH - hS) / 2), 0.86, 0.9, 0.95, al, small)
      if val then
        shadowTextRight(ui, val, W - pad, y + math.floor((rowH - hS) / 2), 1, 1, 1, al, small)
      end
    end)
  end

  if m.working then
    local capF = (m.heatCap or 100) / 100
    local hot = (m.heatPct or m.heat) >= 75
    local blink = hot and (math.floor(t / 250) % 2 == 0)
    local locked = m.locked and true or false
    barRow("Heat", T("IGUI_Sandevistan_HUD_Heat"), m.heat / 100, locked and LOCKED_ZONES or heatZones(m.color, capF),
           istr(m.heat), { 0.75 * capF },
           { alert = hot or locked, pulse = blink, fullRed = locked, lockedFrom = capF < 1 and capF or nil,
             iconR = (hot or locked) and 1 or 0.85, iconG = (hot or locked) and 0.45 or 0.9, iconB = (hot or locked) and 0.3 or 1 })
    if m.expanded then       -- el Impulso ya no tiene barra (solo el moodle); Rechazo y Neural solo en el modo expandido
      barRow("Rejection", T("IGUI_Sandevistan_HUD_Rejection"), m.rejection / 100, REJECTION_ZONES,
             istr(m.rejection), REJ_TICKS, { alert = m.rejection >= 75 })
    end
    local cov = (m.coverageHours or 0) > 0
    textRow("Pill", T("IGUI_Sandevistan_HUD_Coverage"), cov and hstr(m.coverageHours) or "-",
            { iconR = 0.55, iconG = 0.8, iconB = 1, alpha = cov and 1 or 0.6 })
  end
  local z = CFG.NeuralLoad.Zones
  if m.expanded or not m.working then
    barRow("Neural", T("IGUI_Sandevistan_HUD_CN"), m.neural / 100, neuralZones(),
           istr(m.neural),
           NEURAL_TICKS(),
           { alert = m.cyber, iconR = 1, iconG = 0.6, iconB = 0.8 })
  end

  -- estados (filas tipo moodle)
  if m.statuses and #m.statuses > 0 then
    add(U[5], function(y) end)
    local chipH = math.max(hS + 2, U[16])
    for _, st in ipairs(m.statuses) do
      add(chipH + U[2], function(y)
        local text = st.text
        if glitch and ZombRand(4) == 0 then text = garble(string.len(text)) end
        ui:drawRect(pad, y, W - 2 * pad, chipH, 0.34 * a, st.r * 0.25, st.g * 0.25, st.b * 0.25)
        ui:drawRect(pad, y, 2, chipH, 0.95 * a, st.r, st.g, st.b)
        icon(ui, st.icon, pad + U[6], y + math.floor((chipH - U[12]) / 2), U[12], a, st.r, st.g, st.b)
        ui:drawText(text, pad + U[23], y + math.floor((chipH - hS) / 2), st.r, st.g, st.b, a, small)
      end)
    end
  end

  -- ---- alturas ----
  local headerH = hT + U[compact and 6 or 9]
  local stripH = m.stateText and (hS + U[compact and 3 or 5]) or 0
  local gapAfterHeader = U[compact and 3 or 5] + (stripH > 0 and (stripH + U[compact and 3 or 5]) or 0)
  local total = headerH + U[3] + gapAfterHeader
  for _, row in ipairs(rows) do total = total + row.h end
  total = total + U[compact and 6 or 9]
  local H = total

  -- ---- dibujo ----
  -- halo según el estado
  local hr, hg, hb, ha = r, g, b, 0
  if m.stateKey == "overdrive" then hr, hg, hb, ha = 1, 0.15, 0.1, 0.55 + 0.25 * math.sin(t / 90)
  elseif m.stateKey == "armed" then hr, hg, hb, ha = 1, 0.6, 0.15, 0.42
  elseif m.working and (m.heatPct or m.heat) >= 75 then hr, hg, hb, ha = 1, 0.25, 0.1, 0.22 + ((math.floor(t / 250) % 2 == 0) and 0.2 or 0)
  elseif m.stateKey == "active" then ha = 0.30 end
  if (m.flash or 0) > 0 then ha = math.max(ha, 0.65 * m.flash); if m.stateKey == "ready" then hr, hg, hb = r, g, b end end
  halo(ui, W, H, ha * (m.idle and 0.5 or 1), hr, hg, hb)

  frame(ui, W, H, a, r, g, b, LITE)

  -- cabecera: título a la izquierda, nivel (con su progreso de XP) a la derecha
  local y0 = U[compact and 4 or 5]
  local title = m.title or ""
  if glitch and ZombRand(2) == 0 then title = garble(string.len(title)) end
  shadowText(ui, title, pad + U[3], y0, r, g, b, a, titleFont)
  if m.levelText then
    local lw = measure(small, m.levelText) + U[12]
    local bh = hS + U[3]
    local lx = W - pad - lw
    local ly = y0 + math.floor((hT - bh) / 2)
    pill(ui, lx, ly, lw, bh, 0.26 * a, r, g, b)
    if not LITE then pillLine(ui, lx, ly, lw, bh, 0.8 * a, r, g, b) end
    ui:drawText(m.levelText, lx + U[6], ly + math.floor((bh - hS) / 2), r, g, b, a, small)
    if m.xpFrac then                                     -- progreso hacia el siguiente nivel
      ui:drawRect(lx + 2, ly + bh - 2, lw - 4, 1, 0.25 * a, r, g, b)
      ui:drawRect(lx + 2, ly + bh - 2, math.floor((lw - 4) * clamp01(m.xpFrac)), 1, 0.95 * a, r, g, b)
    end
  end
  -- divisor
  local dv = tex("Divider")
  if dv then ui:drawTextureScaled(dv, pad, headerH, W - 2 * pad, 2, 0.85 * a, r, g, b)
  else ui:drawRect(pad, headerH, W - 2 * pad, 1, 0.5 * a, r, g, b) end

  -- franja de estado
  if m.stateText then
    local sr, sg, sb = r, g, b
    local blinkA = 1
    if m.stateKey == "overdrive" then sr, sg, sb = 1, 0.25, 0.2; blinkA = 0.7 + 0.3 * math.sin(t / 90)
    elseif m.stateKey == "armed" then sr, sg, sb = 1, 0.65, 0.2; blinkA = 0.75 + 0.25 * math.sin(t / 200)
    elseif m.stateKey == "cooling" then sr, sg, sb = 0.55, 0.75, 1
    elseif m.stateKey == "ready" then sr, sg, sb = 0.45, 0.95, 0.6
    elseif m.stateKey == "destroyed" then sr, sg, sb = 0.9, 0.2, 0.2 end
    local sy = headerH + U[3] + U[compact and 3 or 5]
    ui:drawRect(pad, sy, W - 2 * pad, stripH, 0.20 * a, sr * 0.6, sg * 0.6, sb * 0.6)
    ui:drawRect(pad, sy, 2, stripH, 0.95 * a, sr, sg, sb)
    local dotY = sy + math.floor(stripH / 2) - 1
    ui:drawRect(pad + U[7], dotY, 3, 3, blinkA * a, sr, sg, sb)                       -- punto de estado
    shadowText(ui, m.stateText, pad + U[15], sy + math.floor((stripH - hS) / 2), sr, sg, sb, a, small)
  end

  local y = headerH + U[3] + gapAfterHeader
  for _, row in ipairs(rows) do
    row.fn(y)
    y = y + row.h
  end

  -- desgarro del panel por glitch
  if glitch then
    for _ = 1, 3 do
      local gy = ZombRand(math.max(1, H - 6))
      ui:drawRect(m.glitchDX or 0, gy, W, 2 + ZombRand(5), 0.5, r, g, b)
    end
  end
  return W, H
end

return P
