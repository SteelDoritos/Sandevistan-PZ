-- Sandevistan / Report: reporte de diagnóstico en un solo txt (Debug → Pruebas e informes → REPORTE rapido; la PRUEBA COMPLETA también lo escribe). Junta lo que hace falta para
-- revisar un problema a distancia: versión e idioma, opciones de sandbox, estado del implante y del jugador, inventario del mod,
-- chequeo de traducciones (nombres de ítems, notas y codificación), estado de moodles/skill/trepado/mundo y las últimas líneas del log.
-- Escribe Zomboid/Lua/Sandevistan_report.txt. Todo va envuelto: una parte que falla deja una línea "ERROR" y el resto sigue.
require "Sandevistan/Core"

local CFG = SandevistanConfig
local S = Sandevistan

SandevistanReport = {}
local RP = SandevistanReport
RP.FILE = "Sandevistan_report.txt"

local function str(v)
  if type(v) == "number" then
    if v == math.floor(v) then return tostring(v) end
    return string.format("%.3f", v)
  end
  return tostring(v)
end

-- tabla -> líneas "prefijo.clave = valor", ordenadas (con límite de profundidad)
local function dump(out, t, prefix, depth)
  if type(t) ~= "table" then out[#out + 1] = prefix .. " = " .. str(t); return end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local v, name = t[k], prefix .. "." .. tostring(k)
    if type(v) == "table" and depth > 0 then dump(out, v, name, depth - 1)
    elseif type(v) ~= "function" then out[#out + 1] = name .. " = " .. str(v) end
  end
end

-- bytes de un texto (para ver si "°" y "—" llegan en UTF-8)
local function bytes(text, maxN)
  local b = {}
  for i = 1, math.min(string.len(text), maxN or 12) do b[#b + 1] = string.format("%02X", string.byte(text, i)) end
  return table.concat(b, " ")
end

function RP.sections(player)
  local L = {}
  local function add(line) L[#L + 1] = line end
  local function section(title, fn)
    add(""); add("== " .. title)
    local ok, err = pcall(fn)
    if not ok then add("ERROR en la seccion: " .. tostring(err)) end
  end
  local d = S.data(player)

  section("version y entorno", function()
    add("mod = " .. tostring(CFG.Version) .. ", entrega = " .. tostring(CFG.Build))
    pcall(function()
      local mi = getModInfoByID("Sandevistan")
      if mi then add("carpeta cargada = " .. tostring(mi:getDir()) .. " | common = " .. tostring(mi:getCommonDir())) end
    end)
    local gv = nil
    pcall(function() gv = getCore():getVersion() end)
    add("juego = " .. tostring(gv))
    local lang = nil
    pcall(function() lang = tostring(Translator.getLanguage()) end)
    add("idioma = " .. tostring(lang))
    add("isClient = " .. tostring(isClient()) .. ", isServer = " .. tostring(isServer()) .. ", debug = " .. tostring(S.debugOn()))
    add("horas de juego = " .. str(S.worldHours()) .. ", velocidad = " .. tostring(getGameSpeed and getGameSpeed() or "?"))
    local user = "?"
    pcall(function() user = tostring(player:getUsername()) end)
    add("jugador = " .. user .. " idx " .. tostring(player:getPlayerNum()))
  end)

  local TSr = rawget(_G, "SandevistanTestSuite") and SandevistanTestSuite.results
  if TSr then
    section("prueba completa", function()
      add(string.format("duracion = %.0f s%s", TSr.seconds or 0, TSr.cancelled and (", CANCELADA: " .. tostring(TSr.cancelled)) or ""))
      local F = rawget(_G, "SandevistanFullTest")
      if F and F.last then add(string.format("autotest: %d OK, %d FALLA (detalle mas abajo)", F.last.passed, F.last.failed)) end
      if TSr.fulltest then add("autotest: " .. tostring(TSr.fulltest)) end
    end)
    section("multijugador", function()
      if not TSr.mpClient then add("partida local (SP): sin servidor que consultar") end
      if TSr.mpClient then add("respuesta del servidor = " .. tostring(TSr.mpReply) .. (TSr.mpReply and "" or " (no llego en 6 s: el servidor no tiene el mod, tiene una version vieja o no responde)")) end
      for _, l in ipairs(TSr.mpLines or {}) do add(l) end
    end)
    section("dilatacion medida (5 s apagado + 25 s encendido)", function()
      if TSr.dilation then add(TSr.dilation); return end
      local m = TSr.dil
      if not m then add("sin datos"); return end
      local function v(x) return (x and x.speed) and string.format("%.2f", x.speed) or "-" end
      add(string.format("radio = %s tiles; velocidad esperada del tramo = x%s; ventanas de %d ms (una ventana de menos de 0.1 tiles/s cuenta como quieto)",
        tostring(m.radius), tostring(m.expected), m.windowMs or 500))
      add(string.format("categoria | zombis | ventanas | en movimiento | tiles/s | imposibles (>%d tiles/s) | saltos en 1 tick", m.fast or 6))
      local NAMES = { { "base.own", "apagado, los simula este cliente" }, { "base.rem", "apagado, llegan por la red" },
                      { "slow.own", "frenados, este cliente" }, { "slow.rem", "frenados, red" },
                      { "released", "recien soltados (< 2 s fuera del radio)" },
                      { "free.own", "sin frenar (fuera del radio), este cliente" }, { "free.rem", "sin frenar, red" } }
      for _, e in ipairs(NAMES) do
        local c = m.cats and m.cats[e[1]]
        if c then add(string.format("%s | %d | %d | %d | %s | %d | %d", e[2], c.zombies, c.windows, c.moving, v(c), c.fast, c.snaps)) end
      end
      local function r(x) return x and string.format("x%.2f", x) or "-" end
      add("relacion frenados / apagado = " .. r(m.ratio) .. " (todos); este cliente " .. r(m.ratioOwn) .. "; red " .. r(m.ratioRem))
      add("zombis que recibieron la animacion lenta = " .. tostring(m.animMarked))
      -- lectura automática
      local exp = tonumber(m.expected)
      if not m.ratio then
        add("lectura: faltan datos (hacen falta zombis moviendose cerca con el implante apagado y encendido)")
      elseif exp and math.abs(m.ratio - exp) <= 0.12 then
        add("lectura: el frenado da lo esperado")
      elseif m.ratio > 0.8 then
        add("lectura: los zombis NO se frenaron")
      else
        add("lectura: frenado distinto del esperado (x" .. string.format("%.2f", m.ratio) .. " contra x" .. tostring(exp) .. ")")
      end
      if m.ratioRem and m.ratioRem > 0.7 then
        add("lectura: los zombis que llegan por la red NO se frenan (este cliente solo atrasa su dibujo; siguen a velocidad normal)")
      end
      local rel = m.cats and m.cats.released
      if rel and rel.fast > 0 then
        add("lectura: " .. rel.fast .. " ventanas imposibles al salir del radio: se ponian al dia con la posicion del servidor")
      end
    end)
    if TSr.server or TSr.mpClient then
      section("dilatacion vista por el servidor (multijugador)", function()
        local srv = TSr.server
        if not srv or (not srv.base and not srv.on) then
          add(srv and srv.asked and "sin respuesta del servidor (servidor con una version vieja del mod?)" or "no se pidio (partida local o sin implante)")
          return
        end
        local WHO = { { "own", "los simula este cliente" }, { "server", "los simula el servidor" }, { "other", "los simula otro jugador" } }
        local function line(tag, a)
          if not a then add(tag .. ": sin respuesta"); return end
          if a.err then add(tag .. ": ERROR en el servidor: " .. tostring(a.err)) end
          add(string.format("%s: %.1f s, %d ticks del servidor (%.0f por segundo)", tag, (a.ms or 0) / 1000, a.ticks or 0,
            (a.ticks or 0) / math.max(0.001, (a.ms or 0) / 1000)))
          for _, w in ipairs(WHO) do
            local n = a[w[1] .. "_n"]
            if n then
              local sp = a[w[1] .. "_v"]
              add(string.format("  %s: %d zombis, %d ventanas, %s tiles/s, %d imposibles", w[2], n, a[w[1] .. "_win"] or 0,
                sp and string.format("%.2f", sp) or "-", a[w[1] .. "_fast"] or 0))
            end
          end
        end
        line("apagado", srv.base)
        line("encendido", srv.on)
        local function all(a)
          if not a then return nil end
          local dist, time = 0, 0
          for _, w in ipairs(WHO) do
            local sp, mov = a[w[1] .. "_v"], a[w[1] .. "_mov"]
            if sp and mov and mov > 0 then dist = dist + sp * mov; time = time + mov end
          end
          return time > 0 and dist / time or nil
        end
        local b, o = all(srv.base), all(srv.on)
        if b and o and b > 0 then
          local ratio = o / b
          add(string.format("relacion encendido / apagado vista por el servidor = x%.2f", ratio))
          if ratio <= 0.6 then add("lectura: el servidor ve a los zombis frenados: los demas jugadores tambien los ven lentos")
          else add("lectura: el servidor los mueve a velocidad normal: el frenado es solo visual en este cliente") end
        end
      end)
    end
  end

  section("sandbox (SandboxVars.Sandevistan y EasyClimbing)", function()
    local sv = SandboxVars and SandboxVars.Sandevistan
    if sv then dump(L, sv, "Sandevistan", 1) else add("sin SandboxVars.Sandevistan") end
    add("EasyClimbing (mundo) = " .. tostring(SandboxVars and SandboxVars.EasyClimbing))
    -- v0.1.30 (25): dificultad elegida y lo que quedo aplicado (con un preset distinto de Custom pisa a las opciones sueltas de arriba)
    add(string.format("dificultad = %s | Heat x%.2f | duracion de inmunosupresores x%.2f | partes del P06 en el loot x%.2f | rechazo x%.2f | XP x%.2f | remision = %s",
      tostring(CFG.Preset or SandevistanConfig.presetName()), CFG.HeatRateMultiplier or 1, CFG.Immunosuppressant.DurationMultiplier or 1, CFG.Loot.PartsMultiplier or 1,
      CFG.Rejection.RateMultiplier or 1, CFG.XP.Multiplier or 1, tostring(CFG.NeuralLoad.Remission.Enabled)))
    -- (170) C01: intensidad de la cyberpsicosis (sandbox) y "menos destellos" (opcion del mod, de este cliente)
    add(string.format("cyberpsicosis: intensidad = %s (sintomas x%.2f) | menos destellos = %s",
      tostring(CFG.Psychosis.Intensity or "Normal"), CFG.Psychosis.FreqMult or 1, tostring(S.lessFlashes())))
  end)

  -- v0.1.30 (27): resultados de la ultima corrida del RECORRIDO funcional de esta sesion (Debug -> RECORRIDO funcional)
  local WTr = rawget(_G, "SandevistanWalkthrough") and SandevistanWalkthrough.results
  if WTr then
    section("recorrido funcional (ultima corrida)", function()
      add(string.format("duracion = %.0f s | %s", WTr.seconds or 0, tostring(WTr.summary)))
      for _, l in ipairs(WTr.lines) do add(l) end
    end)
  end

  section("firmware (chips)", function()
    local FW = rawget(_G, "SandevistanFirmware")
    local FC = rawget(_G, "SandevistanFirmwareClient")
    if not FW then add("SandevistanFirmware no esta cargado"); return end
    local F = CFG.Firmware
    local ready = 0
    for _, id in ipairs(F.Order) do if F.Programs[id].ready then ready = ready + 1 end end
    add(string.format("activo = %s | todos conocidos = %s | programas terminados = %d de %d | recalibrando = %.2f h", tostring(F.Enabled), tostring(F.AllKnown), ready, #F.Order, FW.recalLeft(d)))
    for _, slot in ipairs(F.Slots) do
      local id = FW.slotProgram(d, slot)
      add(slot .. " = " .. tostring(id or "vacio") .. (id and string.format(" | terminado = %s | hardware = %s | funcionando = %s", tostring(F.Programs[id].ready), tostring(FW.supported(d, id)), tostring(FW.active(d, id))) or ""))
    end
    local lines = FC and FC.profileLines(player) or {}
    add("perfil (solo lo que se aparta de lo neutro): " .. (#lines > 0 and table.concat(lines, "; ") or "neutro"))
    -- (86) Taller: estado del modo trabajo y de las acciones aceleradas
    do
      local prof = FW.profile(d)
      local R = rawget(_G, "SandevistanRuntime")
      local sess = R and R.session(player)
      local Wk = F.Work
      add(string.format("modo trabajo (Taller): puesto = %s | encendido = %s | flujo = %.0f s de %d | trabajando ahora = %s | acciones activadas = %s",
        tostring(prof.mode == "work"), tostring(sess and sess.active and sess.work or false), sess and sess.workFlow or 0, Wk.FlowSeconds, tostring(sess and sess.workNow or false),
        tostring(Wk.ActionsEnabled)))
      if FC and FC.work then
        local cls, miss = {}, {}
        for k in pairs(FC.work.classes) do cls[#cls + 1] = k end
        for k in pairs(FC.work.missing) do miss[#miss + 1] = k end
        table.sort(cls); table.sort(miss)
        add(string.format("acciones aceleradas por el modo trabajo: %d (ultima: %s) | enganchadas: %s | ISBaseTimedAction.adjustMaxTime enganchado = %s | clases de la lista que no existen en esta version: %s",
          FC.work.scaled, tostring(FC.work.last), table.concat(cls, ", "), tostring(FC.work.base), #miss > 0 and table.concat(miss, ", ") or "ninguna"))
      end
    end
    -- (85) programas conocidos, escritura y recetas
    add("conocidos (" .. #FW.knownList(d) .. "): " .. (#FW.knownList(d) > 0 and table.concat(FW.knownList(d), ", ") or "ninguno") .. string.format(" | segundos para escribir uno = %.1f | aprendio el chip virgen y el terminal = %s", FW.writeSeconds(d), tostring(d.knows and d.knows.firmware == true)))
    local W = F.Write
    local inv = player:getInventory()
    local function n(t) local c = 0; pcall(function() c = inv:getCountTypeRecurse(t) end); return c end
    add(string.format("en el inventario: chips virgenes = %d | terminales = %d | baterias = %d | microchips militares = %d", n(FW.BLANK), n(W.Terminal), n(W.Battery), n(W.MilitaryChip)))
    local M = rawget(_G, "SandevistanMedical")
    if M then
      add("receta nativa del chip virgen = " .. tostring(M.nativeRecipe("fwchip") ~= nil) .. " | la sabe el jugador = " .. tostring(M.recipeKnown(player, CFG.Crafting.Recipes.fwchip)) .. " (el terminal no se fabrica: se encuentra en lugares militares)")
      -- (87) expedientes militares (ensenan la Camara criogenica) y chips programados que lleva
      local okD, comp = pcall(M.militaryDossiersComplete, player)
      local list = FC and FC.programmedChips(player) or {}
      local ids = {}
      for _, e in ipairs(list) do ids[#ids + 1] = e.id end
      add(string.format("expedientes militares completos encima = %s | chips programados que lleva (%d): %s | segundos para decompilar uno = %.1f", okD and tostring(comp) or "error", #ids, #ids > 0 and table.concat(ids, ", ") or "ninguno", FW.decompileSeconds(d)))
    end
    -- (87) chips programados en el botin: cuantas entradas hay y en que tablas (los nombres "Army*" de 42.21 no estan verificados: lista las que existen). En multijugador el cliente no ve lo que agrega el servidor.
    local PD = rawget(_G, "ProceduralDistributions")
    if PD and PD.list then
      local armyTables, with, total = {}, {}, 0
      for name, dist in pairs(PD.list) do
        if type(dist) == "table" and type(dist.items) == "table" then
          if string.find(name, "Army", 1, true) then armyTables[#armyTables + 1] = name end
          local c = 0
          for i = 1, #dist.items, 2 do
            local t = dist.items[i]
            if type(t) == "string" and string.sub(t, 1, 14) == "Sandevistan.Fw" and t ~= FW.BLANK then c = c + 1 end
          end
          if c > 0 then with[#with + 1] = name .. "=" .. c; total = total + c end
        end
      end
      table.sort(armyTables); table.sort(with)
      add(string.format("botin con chips programados: %d entradas en %d tablas%s | tablas 'Army*' que existen (%d): %s", total, #with, #with > 0 and (" (" .. table.concat(with, ", ") .. ")") or "", #armyTables,
        #armyTables > 0 and table.concat(armyTables, ", ") or "ninguna"))
      if isClient() and total == 0 then add("(multijugador: el servidor reparte el botin; el cliente no ve esas entradas)") end
    end
    local Wd = rawget(_G, "SandevistanWorld")
    local plog = Wd and Wd.authority and Wd.data and Wd.data().placedLog and Wd.data().placedLog.base
    if plog then
      local c = {}
      for _, e in ipairs(plog) do if type(e.t) == "string" and string.sub(e.t, 1, 14) == "Sandevistan.Fw" then c[#c + 1] = string.sub(e.t, 15) end end
      table.sort(c)
      add(string.format("chips programados colocados en la base militar: %d (%s) | esperados en una partida nueva: %d", #c, #c > 0 and table.concat(c, ", ") or "ninguno", #CFG.World.FwBaseChips.fixed + CFG.World.FwBaseChips.random.count + (CFG.World.FwBaseTerminals or 0)))          -- (96) incluye el terminal (la lista de arriba lo cuenta: "Fw" + Terminal)
    end
  end)

  section("estado del implante (modData)", function()
    dump(L, d, "d", 2)
    local k = S.kdata(player)
    dump(L, k, "kerenzikov", 1)
  end)

  section("derivados", function()
    local now = S.worldHours()
    add("nivel = " .. str(S.level(d)) .. ", adaptFraction = " .. str(S.adaptFraction(d)))
    local xs = d.xpSrc or {}
    add(string.format("XP de adaptacion por fuente (ya con multiplicadores): uso = %.0f (%.0f s encendido), kills = %.0f (%d kills), pasiva = %.0f, otro = %.0f | adoptada de la skill = %.0f | activaciones = %d | total = %.0f",
      xs.time or 0, xs.activeSeconds or 0, xs.kill or 0, xs.nKills or 0, xs.pasiva or 0, xs.otro or 0, xs.adoptada or 0, xs.nActivations or 0, d.adaptXP or 0))
    local sum = (xs.time or 0) + (xs.kill or 0) + (xs.pasiva or 0) + (xs.otro or 0) + (xs.adoptada or 0)
    add(string.format("XP sin registrar (total - fuentes) = %.0f: la que ya tenia la partida antes de la version (41)%s", (d.adaptXP or 0) - sum,
      ((d.adaptXP or 0) - sum) > 1 and "; si sigue creciendo en una partida nueva, hay una via que suma sin pasar por S.addAdaptXP" or ""))
    add("heatCap = " .. str(S.heatCap(d)) .. ", heatPct = " .. str(S.heatPct(d)))
    add("zonaCN = " .. tostring(S.cnZone(d)) .. ", moodleRechazo = " .. str(S.rejectionMoodle(d.rejection or 0)))
    add("remision (h que faltan) = " .. tostring(S.remissionHoursLeft(d, now)))
    add("inmuno (h de cobertura) = " .. str(S.immunoHoursLeft(d, now)) .. ", tier = " .. tostring(S.immunoActiveTier(d, now)))
    -- (135) inmunodepresion y sus efectos (contadores desde que se cargo la partida)
    local IMD, EF = rawget(_G, "SandevistanImmunodep"), rawget(_G, "SandevistanEffects")
    add(string.format("inmunodepresion = %.1f (nivel %d, sandbox x%.1f), pico de la tanda = %.1f, dosis en 24 h = %d, rebote (h) = %.1f, enfermo = %s",
      d.immunodep or 0, S.immunoMoodle(d.immunodep), CFG.Immunosuppressant.Immunodepression.Level or 0, d.immunoPeak or 0, S.immunoDoseCount(d, now),
      math.max(0, (d.immunoReboundUntil or -1) - now), tostring(EF and EF.sickReason(player) or nil)))
    if IMD then
      local st = IMD.stats
      add(string.format("efectos de la inmunodepresion: %d tiradas de infeccion extra (%d infectaron), %d subidas de infeccion, %d frenos de curacion, %d de resfrio, %d de malestar",
        st.rolls, st.infected, st.grown, st.held, st.cold, st.sick))
    end
    local R = rawget(_G, "SandevistanRuntime")
    if R then
      local ok, reason = R.canActivate(player)
      add("canActivate = " .. tostring(ok) .. " (" .. tostring(reason) .. ")")
      local s = R.session(player)
      for _, key in ipairs({ "active", "armed", "overdrive", "berserk", "momentum", "level", "reuseAtMs" }) do
        add("sesion." .. key .. " = " .. str(s[key]))
      end
      add("sesion.fury = " .. tostring(s.fury ~= nil))
    end
    local K = rawget(_G, "Kerenzikov")
    if K then add("kerenzikov activo = " .. tostring(K.isActive(player))) end
  end)

  section("jugador", function()
    local E = rawget(_G, "SandevistanEffects")
    if E then
      for _, st in ipairs({ "ENDURANCE", "PANIC", "PAIN", "STRESS", "FATIGUE", "TEMPERATURE" }) do
        local v = nil
        pcall(function() v = E.getStat(player, st) end)
        add(st .. " = " .. str(v))
      end
      add("inconsciente = " .. tostring(E.isUnconscious(player)))
    end
    add("salud = " .. str(player:getHealth()) .. ", dormido = " .. tostring(player:isAsleep()))
    local sq = player:getCurrentSquare()
    if sq then add("posicion = " .. sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()) end
  end)

  section("inventario (items del mod y cuchillos)", function()
    local items = player:getInventory():getItems()
    for i = 0, items:size() - 1 do
      local it = items:get(i)
      local ft = it:getFullType()
      if string.find(ft, "^Sandevistan%.") then
        local md = {}
        dump(md, it:getModData(), "md", 0)
        add(ft .. " | " .. tostring(it:getName()) .. " | " .. table.concat(md, "; "))
      end
    end
    local M = rawget(_G, "SandevistanMedical")
    if M and M.crudeTool then
      local tool = M.crudeTool(player)
      add("cuchillo reconocido para la extraccion tosca = " .. (tool and tool:getFullType() or "NINGUNO"))
    end
  end)

  section("traducciones (nombres de items, notas, codificacion)", function()
    for _, t in ipairs({ "SandevistanLab", "ImmunosuppressantCraftedPack", "SandevistanNote02", "SandevistanDossierStudent" }) do
      local full = "Sandevistan." .. t
      local shown = nil
      pcall(function() shown = getItemNameFromFullType(full) end)
      local script = nil
      pcall(function() script = getScriptManager():getItem(full):getDisplayName() end)
      add(full .. ": nombre del juego = '" .. tostring(shown) .. "', DisplayName del script = '" .. tostring(script)
        .. "', ItemName_ = '" .. tostring(getTextOrNull("ItemName_" .. full)) .. "', clave completa = '" .. tostring(getTextOrNull(full)) .. "'")
    end
    local title = getText("IGUI_Sandevistan_NoteTitle_02")
    local text = getText("IGUI_Sandevistan_NoteText_02")
    add("nota 2 titulo = " .. title)
    local deg = string.find(text, "39", 1, true) or string.find(text, "103", 1, true)
    if deg then add("nota 2 alrededor de la temperatura = '" .. string.sub(text, deg, deg + 10) .. "' bytes " .. bytes(string.sub(text, deg, deg + 10), 12)) end
    add("nota 2 inicio bytes = " .. bytes(string.sub(text, 1, 40), 40))
  end)

  section("moodles, skill, trepado", function()
    local MO = rawget(_G, "SandevistanMoodles")
    if MO then add("moodles: ready = " .. tostring(MO.ready) .. ", failed = " .. tostring(MO.failed)) end
    add("skill registrada = " .. tostring(S.perk() ~= nil))
    local perk = S.perk()
    if perk then
      -- ¿la pestaña de skills muestra lo mismo que el mod? (nivel y avance dentro del nivel, en la escala del juego)
      local pl = nil
      pcall(function() pl = player:getPerkLevel(perk) end)
      local have = S.perkXP(player, perk)
      local lvl, into, need, frac = S.levelProgress(d)
      local cap = S.hasWorkingImplant(d) and S.maxLevel(d) or 0
      local want = S.perkXPFor(perk, lvl, lvl < cap and math.min(0.999, frac) or 0)
      add(string.format("skill del juego: nivel %s, XP %s (la que corresponde: %.0f) | mod: nivel %d, %.0f / %.0f del tramo",
        tostring(pl), have and string.format("%.0f", have) or "?", want, lvl, into, need))
      add("suma de XP a la skill: via " .. tostring(S.perkAdd.via) .. string.format(", escala %.2f", S.perkAdd.scale)
        .. (S.perkAdd.broken and ", NO SUMA en este proceso (la barra no avanza)" or ""))
      -- (123) maestria con Beyond Ten: la del mod y la que guarda Beyond Ten (en un cliente de multijugador, su copia del servidor)
      local BT = S.beyondTen()
      if BT then
        local rank, mInto, mNeed = S.masteryProgress(d)
        local stored, eff = nil, nil
        pcall(function() stored = BT.GetStoredXP(player, perk); eff = BT.GetEffectiveLevel(player, perk) end)
        add(string.format("Beyond Ten activo: maestria del mod %d (%.0f / %.0f) | Beyond Ten: nivel %s, XP guardada %s", rank, mInto, mNeed,
          tostring(eff), stored and string.format("%.0f", stored) or "?"))
      end
    end
    local A = rawget(_G, "SandevistanAthletic")
    if A then
      add("trepado: ultimo = " .. tostring(A.lastReport))
      dump(L, A.easy, "trepado.easy", 0)
    end
  end)

  section("diagnostico de moodles (Moodle Framework)", function()
    local MO = rawget(_G, "SandevistanMoodles")
    if not (MO and MO.diagnose) then add("SandevistanMoodles.diagnose no disponible"); return end
    for _, line in ipairs(MO.diagnose(true)) do add(line) end
  end)

  section("diagnostico del modelo 3D de la espalda", function()
    local SP = rawget(_G, "SandevistanSpine")
    if not (SP and SP.diagnose) then add("SandevistanSpine.diagnose no disponible"); return end
    for _, line in ipairs(SP.diagnose(player, true)) do add(line) end
  end)

  section("camara 3D de Project Viewport (deteccion)", function()
    local VP = rawget(_G, "SandevistanViewport")
    if not (VP and VP.reportLines) then add("SandevistanViewport no disponible"); return end
    for _, line in ipairs(VP.reportLines()) do add(line) end
  end)

  section("mundo (sets y ex-sujetos)", function()
    local CVis = rawget(_G, "SandevistanCorpseVisual")       -- (137) placa 3D puesta por este cliente en los cadaveres con implante (tambien en MP)
    if CVis then add(CVis.statusLine()) end
    local Tr = rawget(_G, "SandevistanTraits")               -- (137) rasgos del mod repuestos por el servidor en MP
    if Tr and Tr.statusLine then add(Tr.statusLine()) end
    local W = rawget(_G, "SandevistanWorld")
    if not W then add("SandevistanWorld no disponible en este cliente (multijugador)"); return end
    if not W.authority then add("cliente de multijugador: el mundo lo maneja el servidor (ver 'multijugador': sets y ex-sujetos del servidor)"); return end
    local w = W.data()
    dump(L, w.placements or {}, "colocado", 0)
    add("campus activos = " .. table.concat(w.activeCampuses or {}, ", "))
    local n, states = 0, {}
    for _, sub in pairs(w.subjects or {}) do n = n + 1; states[#states + 1] = tostring(sub.variant) .. ":" .. tostring(sub.state) .. "@" .. tostring(sub.zone) end
    add("ex-sujetos = " .. n .. " (" .. table.concat(states, ", ") .. ")")
    local AL = rawget(_G, "SandevistanALife")               -- (129) Project A-Life: los NPCs con implante aparecen arriba como npcN@alife
    add(AL and AL.statusLine() or "Project A-Life: sin el modulo")
    -- (98) la extraccion depende de que el cadaver lleve el implante: lo que esperan y los cadaveres de alrededor
    if W.corpseDiagnosis and player then
      local okC, lines = pcall(W.corpseDiagnosis, player:getX(), player:getY(), player:getZ(), 6)
      for _, l in ipairs(okC and lines or { "diagnostico de cadaveres: error " .. tostring(lines) }) do add(l) end
    end
  end)

  section("rendimiento", function()
    local now = S.clockMs()
    local since = S.perf.since or now
    local secs = math.max(0.001, (now - since) / 1000)
    add(string.format("medido durante %.1f s reales (con la PRUEBA COMPLETA: el tramo de 25 s con el implante encendido)", secs))
    local rt = S.perf.spans["Runtime.OnTick"]
    if rt then add(string.format("ticks del juego por segundo (aprox. FPS) = %.1f", rt.calls / secs)) end
    local names = {}
    for name in pairs(S.perf.spans) do names[#names + 1] = name end
    table.sort(names, function(a, b) return S.perf.spans[a].total > S.perf.spans[b].total end)
    local modTotal, testTotal, hasTest = 0, 0, false
    add("handler | llamadas | ms promedio | ms max | ms total | % del tiempo")
    for _, name in ipairs(names) do
      local sp = S.perf.spans[name]
      if string.find(name, "^TestSuite") or string.find(name, "^FullTest") then testTotal = testTotal + sp.total; hasTest = true   -- la prueba misma
      elseif not string.find(name, " > ", 1, true) then modTotal = modTotal + sp.total end
      add(string.format("%s | %d | %.3f | %d | %d | %.2f%%", name, sp.calls, sp.total / math.max(1, sp.calls), sp.max, sp.total,
        100 * sp.total / (secs * 1000)))
    end
    add(string.format("TOTAL del mod (sin sub-secciones ' > ' ni la propia prueba) = %d ms = %.2f%% del tiempo real", modTotal, 100 * modTotal / (secs * 1000)))
    if hasTest then add(string.format("la prueba misma (medir zombis cada tick; no existe al jugar) = %d ms = %.2f%%", testTotal, 100 * testTotal / (secs * 1000))) end
    local cnames = {}
    for name in pairs(S.perf.counts) do cnames[#cnames + 1] = name end
    table.sort(cnames)
    for _, name in ipairs(cnames) do
      local v = S.perf.counts[name]
      add(string.format("contador %s = %d (%.1f por segundo)", name, v, v / secs))
    end
    local zl = nil
    pcall(function() zl = getCell():getZombieList() end)
    add("zombis cargados ahora = " .. tostring(zl and zl:size() or "?"))
    local SD = rawget(_G, "SandevistanSlowdown")
    if SD then
      local n = 0
      for _ in pairs(SD.slowed) do n = n + 1 end
      add("dilatacion: estrategia = " .. tostring(SD.strategy()) .. ", metodo = " .. tostring(CFG.SlowMethod) .. ", frenados ahora = " .. n
        .. ", candidatos = " .. #(SD.cand or {}) .. ", animacion lenta = " .. tostring(CFG.SlowAnimations.Enabled))
      local L = CFG.SlowLOD
      if L then
        add("dilatacion LOD: " .. (L.Enabled and "activado" or "apagado (camino de antes)") .. ", eleccion cada " .. tostring(L.SelectMs) .. " ms, cercanos = hasta "
          .. tostring(L.NearTiles) .. " casillas, lejanos cada " .. tostring(L.FarMs) .. " ms (0 = todos los ticks), guarda de velocidad (salto maximo) = " .. tostring(L.FarMaxJump)
          .. " casillas (0 = sin guarda); ahora: cercanos " .. tostring(SD.lod and SD.lod.near or 0) .. ", lejanos " .. tostring(SD.lod and SD.lod.far or 0)
          .. ", rapidos tratados como cercanos " .. tostring(SD.lod and SD.lod.fast or 0))
      end
      -- el zombi frenado más cercano: ¿tiene la variable puesta? (si sí y no se ve lento, los nodos del mod no se están cargando)
      for z, info in pairs(SD.slowed) do
        local v = nil
        pcall(function() v = z:getVariableBoolean(CFG.SlowAnimations.Variable) end)
        add("zombi frenado de muestra: variable " .. CFG.SlowAnimations.Variable .. " = " .. tostring(v) .. " (marcada por el mod: " .. tostring(info.animSlow) .. ")")
        break
      end
    end
  end)

  section("voces de zombis con la dilatacion", function()          -- (126)
    local SAU = rawget(_G, "SandevistanSlowAudio")
    if not SAU then add("SlowAudio.lua no cargado"); return end
    for _, l in ipairs(SAU.reportLines()) do add(l) end
  end)

  section("mods opcionales con Java (tono, lluvia congelada, estelas con pose real, cyberpsicosis)", function()          -- (134); (136) las estelas tambien en isometrico
    local FXB, VPB = rawget(_G, "SandevistanFXBridge"), rawget(_G, "SandevistanViewpointBridge")
    add("SandevistanFX: " .. (FXB and tostring(FXB.status()) or "no activo"))
    add("SandevistanViewpoint: " .. (VPB and tostring(VPB.status()) or "no activo"))
    local PSB = rawget(_G, "SandevistanPsyBridge")             -- (152) la cyberpsicosis en Java, en su propio mod
    add("SandevistanPsychosis: " .. (PSB and tostring(PSB.status()) or "no activo"))
    local SDl = rawget(_G, "SandevistanSlowdown")
    if SDl and SDl.precipFactor then add("lluvia ahora: factor " .. tostring(SDl.precipFactor()) .. " (Config.FX.Precip)") end
    local FZ = rawget(_G, "SandevistanFakeZombies")          -- (138) zombis falsos de la cyberpsicosis (titeres del jar de SandevistanPsychosis)
    if FZ then add(FZ.statusLine()) end
    local PFg = rawget(_G, "SandevistanPhantomFigures")      -- (181) C13.2 figuras fantasma
    if PFg then add(PFg.statusLine()) end
    local SFX = rawget(_G, "SandevistanScreenFX")           -- (181) C13.3 / C13.4 / C13.5 sacudida, pantalla y tono
    if SFX then add(SFX.statusLine()) end
    local EC = rawget(_G, "SandevistanEchoes")               -- (138) ecos (motor de estelas de SandevistanViewpoint)
    if EC then add(EC.statusLine()) end
    local DS = rawget(_G, "SandevistanDisguise")             -- (174) el disfraz como episodio
    if DS then add(DS.statusLine()) end
    local SE = rawget(_G, "SandevistanSelfEcho")             -- (175) eco de tus ruidos
    if SE then add(SE.statusLine()) end
    local PSY = rawget(_G, "SandevistanPsychosis")
    if PSY and PSY.pressureStatus then add(PSY.pressureStatus(player)) end          -- (176) presion psicotica
    local CRs = rawget(_G, "SandevistanCrisis")             -- (177) antesala, episodios y cascada
    if CRs then add(CRs.statusLine(player)) end
    if PSY and PSY.blackBoxStatus then add(PSY.blackBoxStatus(d)) end     -- (178) caja negra: cantidad y ultimo
    local AN = rawget(_G, "SandevistanAnchors")                          -- (179) ancla de humanidad activa
    if AN and PSY and PSY.st then add(AN.statusLine(PSY.st(player))) end
    if PSY then add("texto corrupto: " .. (PSY.textGlitchOn() and "listo" or "no disponible") .. ", episodios pedidos = " .. tostring(PSY.textEpisodes)) end
  end)

  section("animacion lenta de zombis", function()
    add("activada = " .. tostring(CFG.SlowAnimations.Enabled) .. ", variable = " .. CFG.SlowAnimations.Variable
      .. ", opcion de sandbox = " .. tostring(SandboxVars and SandboxVars.Sandevistan and SandboxVars.Sandevistan.SlowZombieAnimations))
    -- ¿están los archivos de nodos lentos en la copia del mod que carga el juego?
    local found, tried = 0, 0
    for _, rel in ipairs({ "walktoward/Sandevistan_walktoward1.xml", "walktoward/Sandevistan_sprint1.xml", "lunge/Sandevistan_lunge1.xml",
                           "pathfind/Sandevistan_pathfind1.xml", "attack/Sandevistan_success.xml" }) do
      tried = tried + 1
      local r = nil
      pcall(function() r = getModFileReader("Sandevistan", "media/AnimSets/zombie/" .. rel, false) end)
      if r then found = found + 1; pcall(function() r:close() end) end
    end
    add(string.format("archivos de nodos lentos encontrados en la carpeta del mod = %d de %d", found, tried))
    add("zombis marcados con la variable (en la medicion) = " .. tostring(S.perf.counts["dilatacion.animacionLenta"] or 0))
    local SD = rawget(_G, "SandevistanSlowdown")
    local smp = SD and SD.lastSample
    if smp then
      add(string.format("ultima muestra (hace %.0f s): variable = %s, marcada por el mod = %s, estado = %s, zombieWalkType = %s",
        (S.clockMs() - smp.atMs) / 1000, tostring(smp.var), tostring(smp.marked), tostring(smp.state), tostring(smp.walkType)))
    else
      add("sin muestra: todavia no se freno ningun zombi en esta sesion")
    end
  end)

  section("recetas nativas (menu de crafteo)", function()
    local M = rawget(_G, "SandevistanMedical")
    local SM = getScriptManager and getScriptManager()
    if not M or not SM then add("sin Medical o ScriptManager"); return end
    add("recetas cargadas por el juego = " .. tostring(M.nativeRecipesLoaded()) .. " (si es false, el respaldo por menu contextual esta activo)")
    for _, key in ipairs(M.SyncOrder) do
      local name = CFG.Crafting.Recipes[key]
      local r = nil
      pcall(function() r = SM:getCraftRecipe(name) end)
      if not r then
        add(key .. " (" .. name .. "): NO CARGADA por el juego (¿error de sintaxis en scripts/Sandevistan_recipes.txt?)")
      else
        local function try(f) local ok, v = pcall(f); return ok and v or "?" end
        add(string.format("%s (%s): cargada | nombre mostrado = '%s' | categoria = %s | tiempo = %s | entradas = %s | salidas = %s | habilidades = %s",
          key, name, tostring(try(function() return r:getTranslationName() end)), tostring(try(function() return r:getCategory() end)),
          tostring(try(function() return r:getTime() end)), tostring(try(function() return r:getInputCount() end)),
          tostring(try(function() return r:getOutputCount() end)), tostring(try(function() return r:getRequiredSkillCount() end))))
        pcall(function()
          local inputs = r:getInputs()
          for i = 0, inputs:size() - 1 do
            local inp = inputs:get(i)
            local possible = try(function() return inp:getPossibleInputItems():size() end)
            add(string.format("    entrada %d: '%s' | items aceptados = %s | cantidad = %s", i + 1,
              tostring(try(function() return inp:getOriginalLine() end)), tostring(possible), tostring(try(function() return inp:getAmount() end))))
          end
        end)
        local known, knownMod = false, M.knows(player, M.Recipes[key].knowledge)
        local knownFull = false
        pcall(function() known = player:isRecipeActuallyKnown(M.bareName(name)) == true end)
        pcall(function() knownFull = player:isRecipeActuallyKnown(name) == true end)
        add(string.format("    aprendida (nombre pelado '%s') = %s, con el nombre completo = %s", M.bareName(name), tostring(known), tostring(knownFull)))
        add(string.format("    aprendida por el jugador = %s | segun el mod deberia saberla = %s | resultado de aprender = %s",
          tostring(known), tostring(knownMod), tostring(M.learnResult and M.learnResult[key])))
        if knownMod and not known then add("    ATENCION: el mod la considera conocida pero el juego no (learnRecipe no funciono con este nombre)") end
      end
    end
    -- los items de vanilla que usan las recetas: ¿existen con ese ID?
    local checked = {}
    for _, id in pairs(CFG.Crafting.Items) do
      if not checked[id] then
        checked[id] = true
        local it = nil
        pcall(function() it = SM:getItem(id) end)
        local ty = nil
        if it then pcall(function() ty = tostring(it:getItemType()) end) end
        add(string.format("item %s: %s%s", id, it and "existe" or "NO EXISTE", ty and (" (" .. ty .. ")") or ""))
      end
    end
    for _, id in ipairs({ "Sandevistan.ImmunosuppressantCraftedPack", "Sandevistan.SyntheticCompoundSample", "Sandevistan.KerenzikovCrafted", "Sandevistan.SandevistanLab",
                          "Sandevistan.NeuralInterfaceBoard", "Sandevistan.ThermalRegulator", "Sandevistan.PowerCell", "Sandevistan.ImplantChassis", "Sandevistan.NeuralLinkHarness",
                          "Sandevistan.MilChassis", "Sandevistan.MilLinkHarness", "Base.Screws", "Base.LeatherStrips", "Base.Twine", "Base.Needle",
                          "Base.Wire", "Base.ElectricWire", "Base.SmallSheetMetal", "Base.UnusableMetal", "Base.AluminumScrap", "Base.Battery" }) do
      local it = nil
      pcall(function() it = SM:getItem(id) end)
      add(string.format("item %s: %s", id, it and "existe" or "NO EXISTE"))
    end
    add("dosis por unidad = " .. tostring(CFG.Immunosuppressant.Uses))
    local RCm = rawget(_G, "SandevistanRecipeCode")
    -- (54) "real" = lo que hizo la receta del juego al craftear de verdad (la unica forma de saber si el juego le pasa al OnCreate las partes que consumio:
    -- "partes leidas 5/5"; con 0/5 la calidad del implante saldria siempre con el valor por defecto); "pruebas" = las que forzo el autotest o el recorrido.
    local function describe(lp)
      if not lp then return nil end
      return lp.ok and string.format("exito, calidad %.2f, partes leidas %d/%d", lp.quality or 0, lp.partsRead or 0, lp.partsTotal or 3)
        or string.format("fallo, las partes vuelven con +%s de desgaste, partes leidas %d/%d", tostring(lp.wear), lp.partsRead or 0, lp.partsTotal or 3)
    end
    for _, pr in ipairs({ { "06", "Proto06" }, { "07", "Proto07" } }) do
      add("ensamblado Prototipo " .. pr[1] .. " con la receta REAL del juego = " .. (describe(RCm and RCm["real" .. pr[2]]) or "ninguno en esta sesion (crafteá uno desde el menu de crafteo)"))
      add("ensamblado Prototipo " .. pr[1] .. " de las pruebas = " .. (describe(RCm and RCm["last" .. pr[2]]) or "ninguno en esta sesion"))
    end
    -- nombres traducidos de las recetas: el juego mostro el nombre del script (sin traducir). Se prueban claves candidatas y una receta de vanilla
    -- de referencia para ver como arma el juego la clave.
    local function tn(full) local r = nil; pcall(function() r = SM:getCraftRecipe(full):getTranslationName() end); return tostring(r) end
    add("nombre de referencia (vanilla): Base.MakeSplint -> '" .. tn("Base.MakeSplint") .. "' | Base.DisinfectRag -> '" .. tn("Base.DisinfectRag") .. "'")
    for _, k in ipairs({ "MakeSplint", "MakeSyntheticCompound", "Recipe_MakeSplint", "IGUI_CraftingCategories_Sandevistan" }) do
      add("clave " .. k .. " = '" .. tostring(getTextOrNull(k)) .. "'")
    end
    local rn = nil
    pcall(function() rn = Translator.getRecipeName("MakeSyntheticCompound") end)
    add("Translator.getRecipeName('MakeSyntheticCompound') = '" .. tostring(rn) .. "'")
  end)

  section("combate (velocidad del golpe y golpes sin cuadro de impacto)", function()
    local CB = rawget(_G, "SandevistanCombat")
    add("tope de velocidad del golpe (Combat.MaxCombatSpeed) = " .. tostring(CFG.Combat.MaxCombatSpeed) .. " | el motor deja la base entre 0.8 y 1.6")
    if not CB or not CB.hitStats then add("modulo no cargado"); return end
    local H = CB.hitStats
    add(string.format("golpes cerrados = %d | con cuadro de impacto = %d | sin cuadro de impacto = %d (acelerados por el implante: %d) | mayor velocidad que si registro = %.2f",
      H.swings, H.hit, H.lost, H.lostBoosted, H.maxHitSpeed))
    local OV = CFG.Combat.SpeedOverflowDamage                                                  -- (134e)
    add(string.format("velocidad por encima del tope convertida en daño (Combat.SpeedOverflowDamage %s, eficiencia %s, hasta x%s): %d golpes, x%.2f de media",
      tostring(OV and OV.Enabled), tostring(OV and OV.Efficiency), tostring(OV and OV.Max), H.overflowHits or 0,
      (H.overflowHits or 0) > 0 and H.overflowSum / H.overflowHits or 1))
    if H.lastLost then add(string.format("ultimo golpe acelerado sin impacto: velocidad %.2f (base %.2f) %s", H.lastLost.speed or 0, H.lastLost.base or 0, tostring(H.lastLost.why))) end
    add("(un golpe sin cuadro de impacto tambien pasa si cancelas el ataque a medias; si salen muchos acelerados y todos con la misma velocidad alta, bajar Config.Combat.MaxCombatSpeed)")
    local Cb = rawget(_G, "SandevistanCombat")
    if Cb then add("multijugador: golpes frenados por el limite del anti-cheat del servidor = " .. tostring(Cb.rateBrakes or 0) .. " (MPHitRateGuard = " .. tostring(CFG.Combat.MPHitRateGuard) .. ")") end
    local HBn = rawget(_G, "SandevistanHitBench")                                              -- (134)
    if HBn and HBn.last then
      add("banco de golpes (ultima corrida, detalle en " .. HBn.FILE .. "):" .. (HBn.last.cancelled and (" CANCELADO " .. tostring(HBn.last.cancelled)) or ""))
      local ok, lines = pcall(HBn.buildLines, HBn.last)
      if ok then
        local on = false
        for _, l in ipairs(lines) do
          if l:find("^== velocidad maxima") then on = true elseif l == "" and on then break elseif on then add("  " .. l) end
        end
      end
    end
  end)

  section("animacion rapida del jugador", function()
    local F = CFG.FastAnimations
    add("activada = " .. tostring(F.Enabled) .. ", bandera = " .. F.Flag .. ", opcion de sandbox = "
      .. tostring(SandboxVars and SandboxVars.Sandevistan and SandboxVars.Sandevistan.FastPlayerAnimations))
    local found, tried = 0, 0
    for _, rel in ipairs({ "movement/SandevistanFast_defaultWalk.xml", "run/SandevistanFast_defaultRun.xml", "run/SandevistanFast_run2hands.xml",
                           "sprint/SandevistanFast_defaultSprint.xml", "sprint/SandevistanFast_sprint2handed.xml" }) do
      tried = tried + 1
      local r = nil
      pcall(function() r = getModFileReader("Sandevistan", "media/AnimSets/player/" .. rel, false) end)
      if r then found = found + 1; pcall(function() r:close() end) end
    end
    add(string.format("archivos de nodos rapidos encontrados en la carpeta del mod = %d de %d", found, tried))
    local flag = nil
    pcall(function() flag = player:getVariableBoolean(F.Flag) end)
    add("bandera en el jugador ahora = " .. tostring(flag) .. " (true solo con el implante encendido)")
    for _, base in ipairs(F.Bases) do
      local name = F.VarPrefix .. string.format("%03d", math.floor(base * 100 + 0.5))
      local v = nil
      pcall(function() v = player:getVariableFloat(name, -1) end)
      add(name .. " = " .. tostring(v) .. " (base " .. base .. "; encendido deberia valer base x (1 + aumento del tramo))")
    end
    local SDm = rawget(_G, "SandevistanSlowdown")
    local b = SDm and SDm.boost[player:getPlayerNum()]
    add("multiplicador aplicado ahora = " .. tostring(b and b.animMult))
    local FW = rawget(_G, "SandevistanFirearms")
    add("armas de fuego: recarga/cerrojo mas rapidos con el implante = " .. tostring(CFG.Firearms and CFG.Firearms.Enabled) .. ", enganchado = " .. tostring(FW and FW.installed)
      .. ", multiplicador ahora = " .. (FW and string.format("%.2f", FW.multiplier(player)) or "?"))
    add("contador jugador.animacionRapida (veces que se puso la bandera) = " .. tostring(S.perf.counts["jugador.animacionRapida"] or 0))
  end)

  section("autotest completo (ultima corrida)", function()
    local F = rawget(_G, "SandevistanFullTest")
    local last = F and F.last
    if not last then add("no se corrio en esta sesion (Debug -> 'PRUEBA COMPLETA')"); return end
    add(string.format("resultado: %d OK, %d FALLA", last.passed, last.failed))
    for _, l in ipairs(last.lines) do add(l) end
  end)

  section("avisos (WARN una vez)", function()
    local keys = {}
    for k in pairs(S.warned or {}) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    add(#keys > 0 and table.concat(keys, ", ") or "ninguno")
  end)

  section("ultimas lineas del log", function()
    for _, l in ipairs(S.logBuffer or {}) do add(l) end
  end)
  return L
end

function RP.export(player)
  local lines = { "# Sandevistan " .. tostring(CFG.Version) .. ": reporte de diagnostico" }
  for _, l in ipairs(RP.sections(player)) do lines[#lines + 1] = l end
  local wrote = pcall(function()
    local w = getFileWriter(RP.FILE, true, false)
    if not w then error("sin escritor") end
    for _, l in ipairs(lines) do w:write(S.ascii(l) .. "\n") end
    w:close()
  end)
  S.log("reporte de diagnostico: " .. #lines .. " lineas, " .. (wrote and ("escrito en Zomboid/Lua/" .. RP.FILE) or "NO se pudo escribir"))
  pcall(function() player:Say(wrote and ("Reporte: Zomboid/Lua/" .. RP.FILE) or "No se pudo escribir el reporte") end)
  return lines, wrote
end

return RP
