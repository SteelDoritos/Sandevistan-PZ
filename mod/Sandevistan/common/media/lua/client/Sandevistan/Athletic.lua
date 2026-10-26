-- Sandevistan / Athletic: con el implante activo, las "pruebas atléticas" del motor no fallan (a la adaptación estable de la
-- variante: lab 5, militar 8; lineal desde 0). Cubre vallas (ClimbOverFenceState), ventanas (ClimbThroughWindowState),
-- paredes/vallas altas (ClimbOverWallState) y tropiezos/caídas por choque ("bump").
--
-- Qué se sabe del motor (B42.21, con los registros del usuario):
--  * El resultado se decide AL ENTRAR al estado y queda en los parámetros del estado (State.Param). Desde Lua ese mapa no se puede leer
--    ni escribir (player:getStateMachineParams devuelve un objeto que Lua no puede indexar: cada consulta lanzaba un error).
--  * Cambiar la variable de animación (ClimbFenceOutcome) o las banderas del jugador (isClimbOverWallSuccess) DESPUÉS de entrar no
--    cambia el resultado: la valla baja siguió cayendo ("fall") y la pared siguió en struggle=true success=false.
--  * Pared: el motor escribe "ClimbWall struggle? true / success? false" con probabilidad 1 en 0 cuando el personaje lleva demasiado peso.
--  * Valla baja: al correr/esprintar el salto puede terminar en tropiezo; pesa la carga, la fatiga y Nimble.
--
-- v0.1.29 (10): dos palancas que sí actúan ANTES o DESPUÉS de la decisión del motor:
--  1) Opción de sandbox "EasyClimbing" (el motor la lee al decidir): mientras el implante está activo y la tirada de este trepado sale
--     bien se activa con getSandboxOptions():set(...) y se restaura al apagar el implante, al morir y al cargar la partida (por si se
--     cerró con el implante encendido). Con ella el motor no deja fallar paredes ni sogas de sábanas.
--  2) "Escudo": si el trepado tenía la tirada superada y aun así el motor lo hizo caer, las heridas NUEVAS que aparezcan durante el
--     trepado (y unos segundos después) se curan. Nunca toca partes que ya estaban heridas ni mordidas.
-- Se tira UNA vez por trepado, ANTES de entrar (la de "el próximo trepado"); cada trepado deja una línea "trepado (...)" en la consola.
-- Todo se comprueba antes de llamar (el depurador con "Break On Error" se detiene aun con pcall).
require "Sandevistan/Core"

local CFG = SandevistanConfig
local S = Sandevistan

SandevistanAthletic = {}
local A = SandevistanAthletic

A.lastReport = nil      -- último evento (texto), para el diagnóstico
A.easy = { on = false, orig = nil }     -- palanca de EasyClimbing: on = la tenemos activada nosotros; orig = valor del mundo

local function has(obj, name)
  if obj == nil then return false end
  local ok, f = pcall(function() return obj[name] end)
  return ok and f ~= nil
end

local function call(obj, name, ...)
  if not has(obj, name) then return nil end
  local ok, r = pcall(obj[name], obj, ...)
  if ok then return r end
  return nil
end

local function cfg() return CFG.Athletic or {} end

-- Nombre del estado actual ("ClimbOverFenceState"...), "" si no se puede leer.
local function stateName(player)
  local n = call(player, "getCurrentStateName")
  return n ~= nil and tostring(n) or ""
end

-- variables de animación candidatas (solo se leen las que existen: getVariableString devuelve "" si no existe)
local function varString(player, name)
  local v = call(player, "getVariableString", name)
  return v ~= nil and tostring(v) or ""
end

local function setVar(player, name, value)
  if has(player, "setVariable") then pcall(function() player:setVariable(name, value) end) end
end

local function passRoll(d)
  return S.chance(S.adaptFraction(d) * (cfg().GuardScale or 1))
end

local function report(text)
  A.lastReport = text
  S.log("prueba atlética: " .. text)
end

---------------------------------------------------------------------------
-- Palanca EasyClimbing (sandbox)
---------------------------------------------------------------------------
local function store()
  local md = nil
  pcall(function() md = ModData.getOrCreate("SandevistanAthletic") end)
  return md
end

local function sandboxSet(value)
  return (pcall(function() getSandboxOptions():set("EasyClimbing", value) end))
end

-- on = true: activa EasyClimbing (si el mundo no la tenía); on = false: restaura el valor del mundo.
function A.setEasy(on)
  on = on and true or false
  local e = A.easy
  if on == e.on then return end
  if on then
    if e.disabled then return end
    if isClient() and not cfg().EasyClimbingInMP then return end   -- multijugador: no se toca la sandbox del servidor (sin probar)
    if e.orig == nil then e.orig = (SandboxVars ~= nil and SandboxVars.EasyClimbing == true) end
    if e.orig then return end                                   -- el mundo ya la tiene activa: no hay nada que tocar
    if not sandboxSet(true) then         -- una sola vez: si la API falla no se reintenta en cada tick
      e.disabled = true
      S.warnOnce("athlEasy", "no se pudo activar EasyClimbing (getSandboxOptions():set); la palanca queda desactivada")
      return
    end
    e.on = true
    local md = store()
    if md then md.easyOn = true; md.easyOrig = false end          -- por si se cierra el juego con el implante encendido
    if not e.logged then e.logged = true; report("EasyClimbing activado mientras el implante esté encendido (se restaura al apagarlo)") end
  else
    sandboxSet(e.orig == true)
    e.on = false
    local md = store()
    if md then md.easyOn = false end
  end
end

-- Al apagar el implante / colapsar / morir: se devuelve todo a como estaba.
-- Pantalla dividida: si otro jugador local sigue con el implante activo, EasyClimbing queda puesta hasta que él también lo apague.
function A.release(sess)
  if sess then sess.athl = nil end
  local R = rawget(_G, "SandevistanRuntime")
  if R and R.sessions then
    for _, other in pairs(R.sessions) do
      if other ~= sess and other.active then return end
    end
  end
  A.setEasy(false)
end

local function restoreOnStart()
  local md = store()
  if md and md.easyOn then
    sandboxSet(md.easyOrig == true)
    md.easyOn = false
    S.log("EasyClimbing restaurado al cargar (la partida se había cerrado con el implante encendido)")
  end
  A.easy.on = false
end
Events.OnGameStart.Add(S.safe("Athletic.OnGameStart", restoreOnStart))
Events.OnPlayerDeath.Add(S.safe("Athletic.OnPlayerDeath", function() A.setEasy(false) end))

---------------------------------------------------------------------------
-- Escudo de heridas
---------------------------------------------------------------------------
local function bodyParts(player)
  local parts = nil
  pcall(function() parts = player:getBodyDamage():getBodyParts() end)
  return parts
end

-- índice de parte -> ¿ya estaba herida? (nil si no se puede leer)
local function injurySnapshot(player)
  local parts = bodyParts(player)
  if not parts then return nil end
  local snap = {}
  pcall(function()
    for i = 0, parts:size() - 1 do snap[i] = parts:get(i):HasInjury() and true or false end
  end)
  return snap
end

-- Cura las partes que NO tenían heridas y ahora sí (salvo mordidas, que nunca se tocan). Devuelve cuántas.
local function healNew(player, snap)
  local parts = bodyParts(player)
  if not parts or not snap then return 0 end
  local n, healed = 0, {}
  pcall(function()
    for i = 0, parts:size() - 1 do
      local bp = parts:get(i)
      if snap[i] == false and bp:HasInjury() and not bp:bitten() then
        bp:RestoreToFullHealth()
        n = n + 1
        healed[#healed + 1] = i
      end
    end
  end)
  -- (115) MP: el servidor lleva las heridas; sin esto la herida del golpe volvia con su reenvio
  local EF = rawget(_G, "SandevistanEffects")
  if n > 0 and EF and EF.bodyNet then EF.bodyNet(player, { op = "heal", parts = table.concat(healed, ",") }) end
  return n
end

---------------------------------------------------------------------------
-- Guardias por tipo de trepado
---------------------------------------------------------------------------
-- Estados con resultado en una variable de animación (texto).
local OUTCOME_STATES = {
  { key = "fence", frag = "ClimbOverFence", var = "ClimbFenceOutcome", label = "valla" },
  { key = "window", frag = "ClimbThroughWindow", var = "ClimbWindowOutcome", label = "ventana" },
}

local function boolText(v) if v == nil then return "?" end return v and "si" or "no" end

-- La tirada de ESTE trepado (la que se hizo antes de entrar; si no hay, se tira ahora).
local function climbPass(sess, d)
  local at = sess.athl
  if at.pass == nil then at.pass = passRoll(d) end
  return at.pass
end

-- Una línea por trepado (al entrar al estado): qué ve el motor. Sirve para saber si el resultado se puede leer y si el implante alcanza.
local function logClimb(player, sess, label, current, d, g)
  sess.athl = sess.athl or {}
  if sess.athl["seen_" .. label] then return end
  sess.athl["seen_" .. label] = true
  report(string.format("trepado (%s): estado=%s variable=%s prob.caída=%s sprint=%s carrera=%s nivel=%s tirada=%s easyClimbing=%s",
    label, current, g and (varString(player, g.var) ~= "" and varString(player, g.var) or "(vacía)") or "-",
    tostring(call(player, "getClimbingFailChanceInt")), boolText(call(player, "isSprinting")), boolText(call(player, "isRunning")),
    tostring(S.level(d)), boolText(sess.athl.pass), boolText(A.easy.on)))
end

local function guardOutcome(player, sess, d, g, current)
  sess.athl = sess.athl or {}
  local inState = string.find(current, g.frag, 1, true) ~= nil
  local outcome = varString(player, g.var)
  -- fuera del estado esperado solo se actúa si la variable de animación dice "fall" (por si el nombre del estado cambia)
  if not inState and outcome ~= "fall" then sess.athl[g.key] = nil; sess.athl["seen_" .. g.label] = nil; return false end
  if inState then
    if not sess.athl["seen_" .. g.label] then sess.athl[g.key] = nil end      -- trepado nuevo: tirada nueva
    logClimb(player, sess, g.label, current, d, g)
  end
  local st = sess.athl[g.key]
  if st == nil and outcome == "fall" then
    st = { pass = climbPass(sess, d) }
    sess.athl[g.key] = st
    report(string.format("%s: el motor decidió \"fall\" (estado=%s, variable=%s) -> %s", g.label, current, outcome, st.pass and "SUPERADA" or "falla"))
  end
  if st and st.pass then
    setVar(player, g.var, "success")
    if not st.logged then st.logged = true; report(g.label .. ": forzado a success (variable " .. g.var .. ")") end
    return true
  end
  return false
end

-- Paredes / vallas altas: STRUGGLE (forcejeo) y SUCCESS (false = cae).
local WALL_VARS = { "ClimbWallStruggle", "ClimbWallSuccess", "ClimbOverWallStruggle", "ClimbOverWallSuccess" }

local function guardWall(player, sess, d, current)
  sess.athl = sess.athl or {}
  if not string.find(current, "ClimbOverWall", 1, true) then sess.athl.wall = nil; sess.athl.seen_pared = nil; return false end
  logClimb(player, sess, "pared", current, d, nil)
  local struggle, success = call(player, "isClimbOverWallStruggle"), call(player, "isClimbOverWallSuccess")
  local st = sess.athl.wall
  if st == nil and (struggle == true or success == false) then
    st = { pass = climbPass(sess, d) }
    sess.athl.wall = st
    local seen = {}
    for _, v in ipairs(WALL_VARS) do local s = varString(player, v); if s ~= "" then seen[#seen + 1] = v .. "=" .. s end end
    report(string.format("pared: el motor decidió struggle=%s success=%s (estado=%s, variables: %s) -> %s",
      tostring(struggle), tostring(success), current, table.concat(seen, ", "), st.pass and "SUPERADA" or "falla"))
  end
  if st and st.pass then
    call(player, "setClimbOverWallStruggle", false)
    call(player, "setClimbOverWallSuccess", true)
    for _, v in ipairs(WALL_VARS) do
      if varString(player, v) ~= "" then setVar(player, v, string.find(v, "Struggle", 1, true) and "false" or "true") end
    end
    if not st.logged then st.logged = true; report("pared: forzado struggle=false success=true") end
    return true
  end
  return false
end

-- Tropiezos / caídas por choque: se cancelan con la misma probabilidad (una tirada por evento).
local function guardBump(player, sess, d)
  local bumped = call(player, "isBumpFall") == true or call(player, "isBumpStaggered") == true or call(player, "isKnockedDown") == true
  if not bumped then sess.bumpRolled = false; return false end
  if sess.bumpRolled then return false end
  sess.bumpRolled = true
  if not passRoll(d) then return false end
  call(player, "setBumpFall", false); call(player, "setBumpStaggered", false); call(player, "setKnockedDown", false)
  call(player, "setBumpDone", true)
  report("choque/tropiezo cancelado")
  return true
end

-- Inicio y fin de cada trepado: pasa la tirada "del próximo trepado" a "de este trepado" (y se vuelve a tirar al terminar), y se
-- maneja la palanca de EasyClimbing (ANTES de que el motor decida) y el escudo de heridas.
local function trackClimb(player, sess, d, current)
  local at = sess.athl
  local climbing = string.find(current, "Climb", 1, true) ~= nil
  local now = S.realMs()
  if climbing and not at.inClimb then
    at.inClimb = true
    at.pass = at.nextPass                                 -- la tirada con la que se armó EasyClimbing antes de entrar
    if at.pass == nil then at.pass = passRoll(d) end      -- (si el trepado empezó sin tirada previa)
    at.nextPass = nil
    at.healed = 0
    at.snap = (cfg().InjuryShield ~= false and at.pass) and injurySnapshot(player) or nil
  elseif not climbing and at.inClimb then
    at.inClimb = false
    at.pass = nil
    at.shieldUntil = now + (cfg().ShieldGraceMs or 2500)
    if (at.healed or 0) > 0 then report("heridas nuevas del trepado curadas: " .. at.healed .. " parte(s)") end
  end
  if not climbing then
    if at.nextPass == nil then at.nextPass = passRoll(d) end
    if cfg().EasyClimbing ~= false then A.setEasy(at.nextPass) end
  end
  -- escudo: durante el trepado y unos segundos después
  if at.snap then
    if climbing or now < (at.shieldUntil or 0) then
      local n = healNew(player, at.snap)
      if n > 0 then at.healed = (at.healed or 0) + n end
    else
      at.snap = nil
    end
  end
  return climbing
end

-- Devuelve true si anuló o está forzando algún resultado en este tick.
function A.guard(player, sess, d)
  sess.athl = sess.athl or {}
  local current = stateName(player)
  trackClimb(player, sess, d, current)
  local acted = false
  for _, g in ipairs(OUTCOME_STATES) do
    if guardOutcome(player, sess, d, g, current) then acted = true end
  end
  if guardWall(player, sess, d, current) then acted = true end
  if guardBump(player, sess, d) then acted = true end
  return acted
end

return A
