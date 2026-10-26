-- Sandevistan / InstallScene: la escena de instalacion ("instalar algo nuevo en tu cuerpo"). v0.1.30 (30).
-- Se dispara desde Medical.applyImplant / applyFailedCut, que corren SOLO en la maquina del paciente (RemoteSurgery: el cliente del paciente aplica el
-- implante), asi que el cirujano no ve nada. Es puro overlay local (texto estilo terminal, tinte, destello y sonidos propios): no toca el mundo ni a otros
-- jugadores, no bloquea el control y se salta con ENTER pasados SkipAfter segundos (v0.1.30 (38): antes era cualquier tecla y caminar la cortaba). Tiempos REALES (no dependen de la velocidad del juego ni del Sandevistan).
-- (v0.1.30 (39): tambien la escena INVERSA al explantar, info.kind = "explant": desconexion, modulos que se apagan, adaptacion archivada y ventana de remision.)
-- Secuencia completa (~11 s): handshake (lineas que se tipean) -> modulos que se completan con el estado real del implante -> primer pulso
-- (destello + "SANDEVISTAN ONLINE") -> salida. Fallo de cirugia: pantalla roja corta. Modo "corto": solo el primer pulso.
require "Sandevistan/Core"
require "Sandevistan/Effects"

local CFG = SandevistanConfig
local S = Sandevistan
local E = SandevistanEffects

SandevistanInstallScene = {}
local IS = SandevistanInstallScene
IS.active = nil
IS.suppress = false        -- las pruebas (autotest, recorrido) lo prenden para que no salte la escena en cada cirugia simulada

local function option()
  local I = rawget(_G, "SandevistanInput")
  if I and I.getOption then return I.getOption("installScene", true) end
  return true
end

local function text(key, ...) return getText("IGUI_Sandevistan_Scene_" .. key, ...) end

-- (153) un sonido de la familia de falla grave (sin repetir el ultimo); sin el modulo de cyberpsicosis, el primero de la lista
local function severeGlitch()
  local P = SandevistanPsychosis
  return (P and P.resolve and P.resolve("glitchSevere")) or CFG.Psychosis.Audio.Roles.glitchSevere.fallback[1]
end

local function playerName(player)
  local name = nil
  pcall(function() name = player:getDescriptor():getForename() end)
  if not name or name == "" then pcall(function() name = player:getUsername() end) end
  return string.upper(tostring(name or "HOST"))
end

local COLORS = { lab = { 0.4, 1, 1 }, military = { 1, 0.75, 0.25 }, p06 = { 1, 0.4, 0.9 }, fail = { 1, 0.25, 0.2 }, off = { 0.62, 0.68, 0.8 } }

-- Guion: lista de eventos con su tiempo (segundos desde el inicio).
--   line   = { t, text }            linea que se tipea
--   module = { t, dur, label, status } "LABEL .... 100 PCT" que avanza durante dur y termina en status
--   flash  = { t }                  destello
--   title  = { t, text, sub }       texto grande centrado
function IS.buildScript(info, name)
  local ev, C = {}, CFG.InstallScene
  local function line(t, txt, col) ev[#ev + 1] = { kind = "line", t = t, text = txt, col = col } end
  if info.kind == "explant" then
    if info.ok == false then
      line(0.4, text("ExFailA"), "fail"); line(1.3, text("FailB"), "fail"); line(2.1, text("FailC"), "fail")
      return ev, C.FailSeconds, "fail"
    end
    if IS.mode == "short" then
      ev[#ev + 1] = { kind = "flash", t = 0.2 }
      ev[#ev + 1] = { kind = "title", t = 0.2, text = text("ExTitle"), sub = text(info.cyber and "CySub" or "ExSub") }
      return ev, C.ShortSeconds, info.cyber and "fail" or "off"
    end
    if info.cyber then return IS.buildCyberExplant(info, name, ev, line) end
    line(0.6, text("Header")); line(1.6, text("ExDisc")); line(2.6, text("Bio", name))
    local t = 3.4
    if info.keptPct then line(t, text("ExArchive", info.keptPct)); t = t + 0.8 end
    ev[#ev + 1] = { kind = "module", t = t, dur = 0.6, label = text("ModReflex"), status = text("StOffline") }
    ev[#ev + 1] = { kind = "module", t = t + 0.8, dur = 0.6, label = text("ModThermal"), status = text("StOffline") }
    ev[#ev + 1] = { kind = "module", t = t + 1.6, dur = 0.8, label = text("ModBridge"), status = text("StSevered") }
    t = t + 2.6
    line(t, text("ExTrauma"), "fail"); t = t + 0.8
    if info.remissionDays then line(t, text("ExRemission", info.remissionDays)); t = t + 0.8 end
    ev[#ev + 1] = { kind = "flash", t = t + 0.2, sound = "SandevistanDeactivate" }
    ev[#ev + 1] = { kind = "title", t = t + 0.2, text = text("ExTitle"), sub = text("ExSub") }
    return ev, C.ExplantSeconds, "off"
  end
  if info.ok == false then
    line(0.4, text("FailA"), "fail"); line(1.3, text("FailB"), "fail"); line(2.1, text("FailC"), "fail")
    return ev, C.FailSeconds, "fail"
  end
  local key = info.prototype == "06" and "p06" or (info.variant == "military" and "military" or "lab")
  local replica07 = info.prototype == "07"
  if IS.mode == "short" then
    ev[#ev + 1] = { kind = "flash", t = 0.2 }
    ev[#ev + 1] = { kind = "title", t = 0.2, text = text("Title"), sub = text("Adapt") }
    return ev, C.ShortSeconds, key
  end
  line(0.6, text("Header")); line(1.6, text("Detect")); line(2.6, text("Bio", name)); line(3.4, text("Handshake"))
  ev[#ev + 1] = { kind = "module", t = 4.4, dur = 1.0, label = text("ModBridge"), status = "100 PCT" }
  ev[#ev + 1] = { kind = "module", t = 5.6, dur = 0.5, label = text("ModThermal"), status = text(info.variant == "military" and "StMil" or "StOnline") }
  ev[#ev + 1] = { kind = "module", t = 6.4, dur = 0.5, label = text("ModReflex"), status = text("StSync") }
  line(7.2, text(replica07 and "IdP07" or key == "p06" and "IdP06" or key == "military" and "IdMil" or "IdLab"), key)
  local extra = 8.0
  if (info.degradation or 1) > 1.3 then line(extra, text("Wear", math.floor(((info.degradation or 1) - 1) * 100 + 0.5)), "fail"); extra = extra + 0.6 end
  if (info.rejection or 0) > 0 and extra < 8.6 then line(extra, text("Reject"), "military") end
  ev[#ev + 1] = { kind = "flash", t = 8.8 }
  ev[#ev + 1] = { kind = "title", t = 8.8, text = text("Title"), sub = text("Adapt") }
  return ev, C.Seconds, key
end

-- (66) Explantacion con cyberpsicosis activa (info.cyber): el huesped se resiste. Mas larga y en rojo, con mas glitch, un destello de falla a mitad y la
-- abstinencia anunciada; sin reponer nada del lore (solo lo que el jugador ya vio en los moodles).
function IS.buildCyberExplant(info, name, ev, line)
  local C = CFG.InstallScene
  local WD = CFG.NeuralLoad.Remission.Withdrawal
  line(0.6, text("Header"), "fail"); line(1.6, text("ExDisc"), "fail"); line(2.5, text("CyHost"), "fail")
  line(3.4, text("CyLoad", math.floor(info.cn or 0)), "fail")
  line(4.3, text("CyForce"), "fail")
  local t = 5.1
  if info.keptPct then line(t, text("ExArchive", info.keptPct)); t = t + 0.8 end
  ev[#ev + 1] = { kind = "module", t = t, dur = 0.9, label = text("ModReflex"), status = text("StFault") }
  ev[#ev + 1] = { kind = "module", t = t + 0.9, dur = 0.9, label = text("ModThermal"), status = text("StFault") }
  ev[#ev + 1] = { kind = "flash", t = t + 1.8, sound = severeGlitch() }
  ev[#ev + 1] = { kind = "module", t = t + 2.0, dur = 1.1, label = text("ModBridge"), status = text("StSevered") }
  t = t + 3.3
  line(t, text("ExTrauma"), "fail"); t = t + 0.8
  if WD and WD.Hours then line(t, text("CyWithdrawal", WD.Hours), "fail"); t = t + 0.8 end
  if info.remissionDays then line(t, text("ExRemission", info.remissionDays), "fail"); t = t + 0.8 end
  ev[#ev + 1] = { kind = "flash", t = t + 0.2, sound = "SandevistanDeactivate" }
  ev[#ev + 1] = { kind = "title", t = t + 0.2, text = text("ExTitle"), sub = text("CySub") }
  return ev, (C.ExplantSeconds or 10) + 3, "fail"
end

-- info = { ok = true|false, variant, prototype, degradation, rejection, guide = true si se le dio la guia }
function IS.start(player, info)
  local C = CFG.InstallScene
  if IS.suppress or not C or not C.Enabled or IS.active then return false end
  local isLocal = true
  pcall(function() if player.isLocalPlayer then isLocal = player:isLocalPlayer() end end)
  if not isLocal then return false end
  local mode = option()
  if mode == false then return false end
  IS.mode = (mode == "short") and "short" or "full"
  local ev, seconds, colorKey = IS.buildScript(info, playerName(player))
  IS.active = { player = player, startMs = S.realMs(), events = ev, seconds = seconds, color = colorKey, info = info, played = {} }
  -- solo lo oye quien recibe el implante. Instalar: latido y luego el encendido; explantar (contraste): el sonido de apagado desde el primer momento y de nuevo al
  -- cortarse el puente neural; fallo: error
  local startSound = info.ok == false and "SandevistanError" or (info.kind == "explant" and (info.cyber and severeGlitch() or "SandevistanDeactivate") or "SandevistanHeartbeat")
  E.sound(player, startSound, nil, true)
  S.log("escena de " .. (info.kind == "explant" and "explantacion: " or "instalacion: ") .. (info.ok == false and "fallo" or "inicio"))
  return true
end

function IS.finish()
  local a = IS.active
  if not a then return end
  IS.active = nil
  if a.info.guide then E.halo(a.player, text("Guide"), 120, 220, 255) end
  -- instalación lograda: el panel del HUD se enciende (una vez; desde Debug siempre)
  if a.info.ok ~= false and a.info.kind ~= "explant" then
    local HD = rawget(_G, "SandevistanHUD")
    if HD and HD.powerOn then S.try("hud.powerOn", function() HD.powerOn(a.player, a.info.debug) end) end
  end
end

function IS.skip()
  local a = IS.active
  if a and S.realMs() - a.startMs >= (CFG.InstallScene.SkipAfter or 2) * 1000 then IS.finish() end
end

local function font(name, fallback) return (UIFont and (UIFont[name] or UIFont[fallback])) or fallback end

-- Dibujo: lo llama HUD.prerender (antes de la salida anticipada "sin implante", para que tambien se vea la pantalla de fallo).
function IS.draw(ui, player)
  local a = IS.active
  if not a or a.player ~= player then return end
  local now = S.realMs()
  local t = (now - a.startMs) / 1000
  if t >= a.seconds then IS.finish(); return end
  local core = getCore()
  local w, h = core:getScreenWidth(), core:getScreenHeight()
  local ox, oy = -ui:getAbsoluteX(), -ui:getAbsoluteY()
  local col = COLORS[a.color] or COLORS.lab
  local fadeIn = math.min(1, t / 0.5)
  local fadeOut = math.min(1, math.max(0, (a.seconds - t) / 0.7))
  local k = math.min(fadeIn, fadeOut)
  -- tinte oscuro de fondo (mas fuerte al centro de la escena)
  ui:drawRect(ox, oy, w, h, 0.55 * k, 0, 0, 0)
  local f = font("Code", "Medium")
  if t >= (CFG.InstallScene.SkipAfter or 2) and t < a.seconds - 1 then
    ui:drawTextRight(text("SkipHint"), ox + w - 24, oy + h - 40, 0.8, 0.8, 0.8, 0.6 * k, font("Small", "Small"))
  end
  local x0, y0, lh = w / 2 - 230, h * 0.28, 22
  local row = 0
  local cps = CFG.InstallScene.TypeCharsPerSecond or 45
  local cy = a.info and a.info.cyber and a.info.kind == "explant"
  local glitchy = (math.floor(now / 130)) % (cy and 4 or 9) == 0                    -- (66) con cyberpsicosis tiembla el doble de seguido
  local jx = glitchy and ((cy and (ZombRand(13) - 6)) or (ZombRand(7) - 3)) or 0
  for _, ev in ipairs(a.events) do
    if ev.kind == "line" and t >= ev.t then
      local chars = math.min(#ev.text, math.floor((t - ev.t) * cps) + 1)
      local shown = string.sub(ev.text, 1, chars)
      if chars < #ev.text and math.floor(now / 250) % 2 == 0 then shown = shown .. "_" end
      local c = COLORS[ev.col or a.color] or col
      if ev.col == "fail" then c = COLORS.fail end
      if glitchy then ui:drawText(shown, ox + x0 + jx + 2, oy + y0 + row * lh, 1, 0.1, 0.8, 0.5 * k, f) end
      ui:drawText(shown, ox + x0 + jx, oy + y0 + row * lh, c[1], c[2], c[3], k, f)
      row = row + 1
    elseif ev.kind == "module" and t >= ev.t then
      local p = math.min(1, (t - ev.t) / ev.dur)
      local dots = string.rep(".", 20 - math.min(18, #ev.label))
      local status = p >= 1 and ev.status or (math.floor(p * 100) .. " PCT")
      ui:drawText(ev.label .. " " .. dots .. " " .. status, ox + x0 + jx, oy + y0 + row * lh, col[1], col[2], col[3], k, f)
      row = row + 1
    elseif ev.kind == "flash" and t >= ev.t then
      if not a.played.flash then a.played.flash = true; E.sound(a.player, ev.sound or "SandevistanActivate", nil, true) end      -- aunque un cuadro lento se salte la ventana del destello
      if t < ev.t + 0.3 then ui:drawRect(ox, oy, w, h, 0.55 * (1 - (t - ev.t) / 0.3), col[1], col[2], col[3]) end
    elseif ev.kind == "title" and t >= ev.t + 0.05 then
      local ty = h * 0.62
      local tk = math.min(1, (t - ev.t) / 0.4) * k
      ui:drawTextCentre(ev.text, ox + w / 2 + jx, oy + ty, col[1], col[2], col[3], tk, font("Large", "Medium"))
      ui:drawTextCentre(ev.sub, ox + w / 2, oy + ty + 34, 0.85, 0.95, 1, tk * 0.85, font("Medium", "Small"))
    end
  end
end

-- Solo ENTER (o ENTER del teclado numerico) salta la escena: las teclas de movimiento no la cortan
local function isSkipKey(key)
  local K = rawget(_G, "Keyboard")
  local enter = (K and K.KEY_RETURN) or 28
  local numEnter = (K and K.KEY_NUMPADENTER) or 156
  return key == enter or key == numEnter
end
IS.isSkipKey = isSkipKey

Events.OnKeyPressed.Add(function(key) if IS.active and isSkipKey(key) then pcall(IS.skip) end end)
Events.OnPlayerDeath.Add(function(p) if IS.active and IS.active.player == p then IS.active = nil end end)

return IS
