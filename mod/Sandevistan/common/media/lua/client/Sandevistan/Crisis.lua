-- Sandevistan / Crisis (cliente, 0.7 (177)): la crisis se anuncia (C05; 26 §4 y §5 con 27 §4.2; 29 §5.2.1).
--   Antesala: con cyberpsicosis en etapa 2+, de a ratos, 20 a 40 s de aviso que crece (tinnitus, latidos al final, vision de tunel suave, texto
--   que falla y el monitor: «CRISIS INMINENTE: PARANOIA/DISOCIACION»). El tipo se elige al empezar, asi el jugador sabe que viene. Se corta
--   tomando un antidepresivo o quedandose sentado (o dormido) sin zombis cerca unos segundos: un poco menos de estres y nada mas. Si no, el
--   episodio arranca.
--   Episodio: paranoia (mas zombis falsos, marcas fantasma, audio y ecos: no sabes que es real) o disociacion (el tiempo tartamudea, la pantalla
--   y el texto fallan). Es un multiplicador por sistema (CR.mult, entra en P.freqMult con su clase) y trae cerca los proximos eventos. No hace
--   dano real por si mismo (22 §2.1). Los antidepresivos cortan la antesala, no el episodio.
--   Cascada: la antesala de la sobrecarga. Desde CN FromCN con el implante encendido (o al llegar a 100 encendido), Seconds de aviso; la CN no
--   pasa de HoldCN mientras dura. Apagar el implante la evita (la CN queda en AvoidCN como mucho, sin KO). Si no, la sobrecarga de siempre.
-- Todo es local (st de Psychosis, no se guarda: al cargar no queda una crisis colgada).
require "Sandevistan/Core"
require "Sandevistan/Effects"
require "Sandevistan/Psychosis"

local CFG = SandevistanConfig
local S = Sandevistan
local E = SandevistanEffects
local P = SandevistanPsychosis

SandevistanCrisis = { started = 0, aborted = 0, fired = 0, cascades = 0, avoided = 0, cascadeFired = 0, lastAbort = nil }
local CR = SandevistanCrisis

local function C() return CFG.Psychosis.Crisis end
local function lerp(a, b, t) return a + (b - a) * t end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function rnd(a, b) return lerp(a, b, ZombRandFloat(0, 1)) end
local function log(msg) S.log("crisis: " .. msg) end

-- Los proximos eventos que el episodio trae cerca (campo de st por clase de P.freqMult).
CR.TIMERS = { FakeZombies = "nextFakeMs", Phantoms = "nextPhantomMs", Audio = "nextAudioMs", Echoes = "nextEchoMs", TextGlitch = "nextTextMs",
              Doppelganger = "nextCloneMs", Disguise = "nextDisguiseMs", PhantomFigures = "nextFigureMs" }          -- (181) figuras fantasma

-- Multiplicador de frecuencia del episodio en curso para una clase (1 sin episodio).
function CR.mult(st, kind)
  local ep = st and st.episode
  if not (ep and kind) then return 1 end
  local t = C().Types[ep.type]
  return (t and t.Mult and t.Mult[kind]) or 1
end

-- Algo grande ya esta pasando: no se empieza una antesala encima.
function CR.busy(player, s, st)
  if st.bo or st.cascade or player:isAsleep() then return true end
  if s and s.fury then return true end
  return E.isUnconscious and E.isUnconscious(player) or false
end

function CR.pickType(d)
  local c = C()
  local total, list = 0, {}
  for _, name in ipairs(c.Order) do
    local t = c.Types[name]
    if t and t.Enabled and P.stage(d) >= (t.MinStage or 2) and (t.Weight or 0) > 0 then
      total = total + t.Weight
      list[#list + 1] = { name = name, w = t.Weight }
    end
  end
  if total <= 0 then return nil end
  local r = ZombRandFloat(0, total)
  for _, e in ipairs(list) do
    r = r - e.w
    if r <= 0 then return e.name end
  end
  return list[#list].name
end

function CR.start(player, d, st, now, kind)
  local c = C()
  kind = kind or CR.pickType(d)
  if not kind or not c.Types[kind] then return false end
  st.crisis = { type = kind, t0 = now, untilMs = now + rnd(c.WarnSeconds[1], c.WarnSeconds[2]) * 1000, antidep0 = d.antidepUntil or -1,
                restMs = 0, lastMs = now, nextTinnitusMs = now, nextTextMs = now + 2000, nextToastMs = now + c.ToastEverySeconds * 1000,
                nextBeatMs = 0 }
  st.episode = nil
  CR.started = CR.started + 1
  P.toast(getText("IGUI_Sandevistan_Mon_Crisis_" .. kind), "crit")
  log(string.format("antesala de %s (%.0f s)", kind, (st.crisis.untilMs - now) / 1000))
  return true
end

function CR.abort(player, st, now, why)
  local c = C()
  st.crisis = nil
  CR.aborted = CR.aborted + 1
  CR.lastAbort = why
  st.nextCrisisMs = now + (c.AfterAbortSeconds or 600) * 1000
  P.toast(getText("IGUI_Sandevistan_Mon_CrisisAborted"), "ok")
  if (c.ReliefStress or 0) > 0 then E.addStat(player, "STRESS", -c.ReliefStress) end
  local d = S.data(player)
  S.addIncident(player, d, { kind = "crisisAborted", stage = P.stage(d), pressure = P.pressureLevel(P.st(player)), why = why })   -- (178)
  log("antesala cortada (" .. tostring(why) .. ")")
end

-- Empieza un episodio con su duracion. quiet = sin el aviso generico del monitor (el despertar alucinado pone el suyo); record = caja
-- negra (178): el despertar alucinado ya quedo registrado como sobrecarga y no se anota dos veces.
local function beginEpisode(player, d, st, now, kind, seconds, quiet, record)
  local t = C().Types[kind]
  if not t then return false end
  st.crisis = nil
  st.episode = { type = kind, t0 = now, untilMs = now + seconds * 1000, nextStutterMs = now + 1500 }
  if not quiet then P.toast(getText("IGUI_Sandevistan_Mon_Episode_" .. kind), "crit") end
  for k, m in pairs(t.Mult or {}) do                                -- lo que el episodio multiplica empieza pronto
    local field = CR.TIMERS[k]
    if field and m > 1 then
      local soon = now + rnd(1.5, 6) * 1000
      st[field] = st[field] and math.min(st[field], soon) or soon
    end
  end
  local SFX = rawget(_G, "SandevistanScreenFX")                     -- (181) C13.4 / C13.5: la pantalla y el tono del episodio
  if SFX then pcall(SFX.episode, player, kind, seconds) end
  if record then
    S.addIncident(player, d, { kind = "episode", stage = P.stage(d), pressure = P.pressureLevel(st), secs = seconds, why = kind })
  end
  log(string.format("episodio de %s (%.0f s)", kind, seconds))
  return true
end

function CR.fire(player, d, st, now, kind)
  local t = C().Types[kind]
  if not t then return end
  if beginEpisode(player, d, st, now, kind, rnd(t.Seconds[1], t.Seconds[2]), false, true) then CR.fired = CR.fired + 1 end
end

-- (178) El pico del despertar alucinado: episodio de paranoia forzado, sin aviso propio ni doble registro.
function CR.forceEpisode(player, d, st, now, kind, seconds)
  return beginEpisode(player, d, st, now, kind, seconds, true, false)
end

function CR.stop(player, st, now, quiet)
  local had = st.crisis or st.episode
  if st.episode then                                                 -- (181) la pantalla sale con su fundido y el tono vuelve
    local SFX = rawget(_G, "SandevistanScreenFX")
    if SFX then pcall(SFX.episodeEnd, player) end
  end
  st.crisis, st.episode = nil, nil
  if had and not quiet then P.toast(getText("IGUI_Sandevistan_Mon_EpisodeEnd"), "ok") end
  return had ~= nil
end

local function sitting(player)
  local yes = false
  pcall(function() yes = player:isSitOnGround() or player:isSittingOnFurniture() end)
  return yes
end

-- Sintomas de una antesala (o de la cascada): crecen con p (0..1).
local function warnSymptoms(player, w, now, p, beatFrom)
  if now >= w.nextTinnitusMs then
    w.nextTinnitusMs = now + lerp(9, 3, p) * 1000
    P.play(player, "tinnitus", nil, nil, nil, lerp(0.4, 1.0, p))
  end
  if p >= (beatFrom or 0.6) and now >= w.nextBeatMs then
    w.nextBeatMs = now + 850
    P.play(player, "heartbeat", nil, nil, nil, 0.85)
  end
  if now >= w.nextTextMs then
    w.nextTextMs = now + 3000
    P.textGlitch(lerp(0.05, 0.35, p), 1400)
  end
end

function CR.crisisTick(player, s, d, st, now)
  local c = C()
  local cr = st.crisis
  local dtMs = now - (cr.lastMs or now)
  cr.lastMs = now
  if c.AbortOnAntidep and (d.antidepUntil or -1) > cr.antidep0 + 1e-6 then CR.abort(player, st, now, "antidepresivo"); return end
  if player:isAsleep() or (sitting(player) and P.zombiesNear(player, c.AbortZombieRadius or 10, 1) == 0) then
    cr.restMs = cr.restMs + dtMs
    if cr.restMs >= (c.AbortRestSeconds or 8) * 1000 then CR.abort(player, st, now, "descanso"); return end
  else
    cr.restMs = 0
  end
  if now >= cr.untilMs then CR.fire(player, d, st, now, cr.type); return end
  local p = clamp((now - cr.t0) / math.max(1, cr.untilMs - cr.t0), 0, 1)
  warnSymptoms(player, cr, now, p)
  if now >= cr.nextToastMs then
    cr.nextToastMs = now + c.ToastEverySeconds * 1000
    P.toast(getText("IGUI_Sandevistan_Mon_Crisis_" .. cr.type), "crit")
  end
end

function CR.episodeTick(player, s, d, st, now)
  local ep = st.episode
  local c = C()
  if now >= ep.untilMs then
    CR.stop(player, st, now)
    st.nextCrisisMs = nil                                          -- la proxima con la espera normal (abajo)
    return
  end
  local t = c.Types[ep.type]
  if ep.type == "Dissociation" and now >= ep.nextStutterMs then    -- el tiempo tartamudea: glitch de pantalla y de texto, y un tiron del Sandi
    ep.nextStutterMs = now + rnd(t.StutterEverySeconds[1], t.StutterEverySeconds[2]) * 1000
    local dur = rnd(t.StutterMs[1], t.StutterMs[2])
    local SD = rawget(_G, "SandevistanSlowdown")
    if SD and s and s.active then
      SD.glitchUntil = SD.glitchUntil or {}
      SD.glitchUntil[player:getPlayerNum()] = now + dur
    end
    if SandevistanHUD and SandevistanHUD.forceGlitch then SandevistanHUD.forceGlitch(dur) end
    local SFX = rawget(_G, "SandevistanScreenFX")                 -- (181) C13.5: el mundo se rompe con el tartamudeo
    if SFX then SFX.burst(player, dur) end
    P.textGlitch(t.StutterText or 0.3, dur + 300)
    P.play(player, "glitch", nil, nil, nil, 0.5)
  end
end

-- Antesala de la sobrecarga (29 §5.2.1). Desde P.overloadTick: true = la sobrecarga espera.
function CR.cascadeGate(player, s, d, st, now)
  local cc = CFG.Psychosis.Overload.Cascade
  if not (cc and cc.Enabled) then return false end
  local cn = d.neuralLoad or 0
  local ca = st.cascade
  if ca then
    if not s.active then                                           -- apagaste el implante a tiempo
      st.cascade = nil
      d.neuralLoad = math.min(cn, cc.AvoidCN)
      CR.avoided = CR.avoided + 1
      S.addIncident(player, d, { kind = "cascadeAvoided", stage = P.stage(d), pressure = P.pressureLevel(st) })   -- (178) caja negra
      P.toast(getText("IGUI_Sandevistan_Mon_CascadeAvoided"), "ok")
      log(string.format("cascada evitada (CN %.1f)", d.neuralLoad))
      return true
    end
    if now >= ca.untilMs then                                      -- no hiciste nada: la sobrecarga de siempre
      st.cascade = nil
      d.neuralLoad = CFG.NeuralLoad.Max
      CR.cascadeFired = CR.cascadeFired + 1
      log("cascada: sobrecarga")
      return false
    end
    if cn > cc.HoldCN then d.neuralLoad = cc.HoldCN end           -- la ventana no se acorta
    local p = clamp((now - ca.t0) / math.max(1, ca.untilMs - ca.t0), 0, 1)
    warnSymptoms(player, ca, now, p, 0.4)
    if now >= ca.nextToastMs then
      ca.nextToastMs = now + 6000
      P.toast(getText("IGUI_Sandevistan_Mon_Cascade"), "crit")
    end
    return true
  end
  if S.worldHours() - (d.lastOverloadHour or -1000) < CFG.Psychosis.Overload.CooldownHours then return false end
  if s.active and not s.fury and cn >= cc.FromCN then
    st.cascade = { t0 = now, untilMs = now + rnd(cc.Seconds[1], cc.Seconds[2]) * 1000, nextTinnitusMs = now, nextTextMs = now,
                   nextToastMs = now + 6000, nextBeatMs = 0 }
    st.crisis = nil                                                -- la cascada pisa una antesala comun
    if cn > cc.HoldCN then d.neuralLoad = cc.HoldCN end
    CR.cascades = CR.cascades + 1
    P.toast(getText("IGUI_Sandevistan_Mon_Cascade"), "crit")
    log(string.format("cascada neural (CN %.1f, %.0f s)", cn, (st.cascade.untilMs - now) / 1000))
    return true
  end
  return false
end

-- Vision de tunel suave de la antesala y la cascada (0..1), para P.blackoutLevels.
function CR.tunnel(player)
  local st = P.state[player:getPlayerNum()]
  if not st then return 0 end
  local now = S.realMs()
  local w = st.cascade or st.crisis
  if w then
    local p = clamp((now - w.t0) / math.max(1, w.untilMs - w.t0), 0, 1)
    return p * (st.cascade and (C().CascadeTunnel or 0.6) or (C().WarnTunnel or 0.4))
  end
  if st.episode and st.episode.type == "Dissociation" then return C().Types.Dissociation.Tunnel or 0 end
  return 0
end

-- Desde Psychosis.tick, despues de la presion.
function CR.tick(player, s, d, st, now)
  local c = C()
  if not c.Enabled or not d.cyberpsychosisActive or P.stage(d) < (c.MinStage or 2) or d.disconnected then
    if st.crisis or st.episode then CR.stop(player, st, now, true) end
    return
  end
  if st.crisis then CR.crisisTick(player, s, d, st, now); return end
  if st.episode then CR.episodeTick(player, s, d, st, now); return end
  if not st.nextCrisisMs then
    local every = lerp(c.EverySeconds[2], c.EverySeconds[1], P.intensity(d)) / math.max(0.2, P.freqMult(d, st))
    local V = CFG.Psychosis.Vulnerable                                       -- (180) C06: despues de un colapso o una furia, antesala mas cerca
    if V and V.Enabled and P.stage(d) >= (V.MinStage or 2) and (d.vulnUntilHour or -1) > S.worldHours() then
      every = every * (V.CrisisWaitMult or 0.5)
    end
    local AN = rawget(_G, "SandevistanAnchors")                    -- (179) un ancla espacia la proxima antesala
    if AN and AN.crisisMult then every = every * AN.crisisMult(st) end
    st.nextCrisisMs = now + (st.crisisFirstDone and every or c.FirstDelaySeconds) * 1000 * rnd(0.7, 1.3)
    st.crisisFirstDone = true
    return
  end
  if now < st.nextCrisisMs then return end
  if CR.busy(player, s, st) then st.nextCrisisMs = now + 20000; return end
  st.nextCrisisMs = nil
  CR.start(player, d, st, now)
end

-- (179) Para el estado mental legible: que tan cerca esta la proxima antesala. "now" (crisis, episodio o cascada en curso),
-- "imminent" (<3 min), "near" (3 a 10) o "far" (>10); nil si no hay una agendada.
function CR.nextHint(st)
  if not st then return nil end
  if st.cascade or st.crisis or st.episode then return "now" end
  if not st.nextCrisisMs then return nil end
  local min = (st.nextCrisisMs - S.realMs()) / 60000
  if min <= 3 then return "imminent" elseif min <= 10 then return "near" end
  return "far"
end

-- Para la pestana Implante: "crisis" / "episode" y el tipo, o nil.
function CR.state(player)
  local st = P.state[player:getPlayerNum()]
  if not st then return nil end
  if st.cascade then return "cascade", nil end
  if st.crisis then return "crisis", st.crisis.type end
  if st.episode then return "episode", st.episode.type end
  return nil
end

function CR.statusLine(player)
  local st = player and P.state[player:getPlayerNum()]
  local now = S.realMs()
  local cur = "nada"
  if st and st.cascade then cur = string.format("cascada (%.0f s)", (st.cascade.untilMs - now) / 1000)
  elseif st and st.crisis then cur = string.format("antesala de %s (%.0f s)", st.crisis.type, (st.crisis.untilMs - now) / 1000)
  elseif st and st.episode then cur = string.format("episodio de %s (%.0f s)", st.episode.type, (st.episode.untilMs - now) / 1000)
  elseif st and st.nextCrisisMs then cur = string.format("proxima antesala en %.0f s", (st.nextCrisisMs - now) / 1000) end
  return string.format("crisis: %s | %d antesalas, %d cortadas (ultima: %s), %d episodios | cascadas: %d, %d evitadas, %d sobrecargas",
    cur, CR.started, CR.aborted, tostring(CR.lastAbort), CR.fired, CR.cascades, CR.avoided, CR.cascadeFired)
end

return CR
