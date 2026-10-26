-- Sandevistan / Net (servidor): retransmite mensajes entre clientes en multijugador. Sin efecto en SP.
--   active         estado "activo" de un jugador -> todos (ralentización alrededor de remotos)
--   look           variante del implante de un jugador -> todos (se dibuja en su espalda)
--   scream         grito de cyberpsicosis -> todos (texto sobre el jugador) + ruido en el mundo
--   surgery*       cirugía sobre otro jugador (cirujano <-> paciente): solo entre jugadores cercanos
--   implantDeath   (v0.1.30 (13)) el cliente avisa con qué implante murió: el cadáver lo lleva (OnPlayerDeath no dispara acá)
--   subjectExtracted  (v0.1.30 (13)) se extrajo el implante de un cadáver registrado: el servidor no deja otro en el suelo
--   mpDiag / mpMeasure  PRUEBA COMPLETA: diagnóstico del servidor y velocidad de los zombis vista por el servidor
--   stats          (114) cambios de stats que hizo el mod en el cliente: el servidor manda en los stats y, sin esto, los pisaba
--   give / fileNotes  (114) ítems que crea el mod: los crea el SERVIDOR (uno creado en el cliente no existe para el servidor: no se tira ni se pasa)
--   traits         (137) rasgos del mod elegidos al crear el personaje: el servidor repone los que perdio (partida alojada)
--   speed          (118) modo trabajo (Taller) y multiplicador de recarga: los usa server/ActionSpeed.lua para la duracion de las acciones
--   body / itemMd / consume / perk / recipes  (115) heridas y salud, ModData de ítems del mod, consumo de dosis y fluidos, la skill de adaptación y
--                  las recetas nativas: el servidor manda en todo eso (verificado en el jar) y sin esto lo que hacía el cliente se deshacía o no se guardaba
-- El servidor valida y sanea los argumentos; la lógica del implante sigue siendo del cliente.
require "Sandevistan/Core"
require "Sandevistan/SpeedMeter"

local S = Sandevistan
local CFG = SandevistanConfig
local SM = SandevistanSpeedMeter

SandevistanNet = SandevistanNet or {}
local N = SandevistanNet
N.measures = N.measures or {}       -- [jugador] = medición en curso (mpMeasure)
N.lastDeath = N.lastDeath or {}     -- [usuario] = ms del último implantDeath aceptado

local MODULE = "Sandevistan"
local MAX_DIST = 6

-- (69) nombre de la placa: el servidor lo vuelve a limpiar (mismas reglas que el cliente) antes de retransmitirlo
local function plateOf(v) return S.cleanPlate(v) end

local function num(v, lo, hi)
  v = tonumber(v)
  if not v or v ~= v then return nil end
  if v < lo then v = lo elseif v > hi then v = hi end
  return v
end

-- Velocidad de zombi (y de jugadores cercanos) más baja que puede tener un tramo legítimo: tramo más lento x Overdrive.
-- Un cliente modificado que mande algo menor no puede congelar a los demás.
local function minLegitZs()
  local lo = 1
  for _, t in ipairs(CFG.DilationTiers) do if t.zombieSpeed < lo then lo = t.zombieSpeed end end
  return lo * (CFG.Overdrive.Bonus.ZombieSpeedMult or 1)
end

local function target(sender, args)
  local id = tonumber(args and args.target)
  if not id then return nil end
  local p = getPlayerByOnlineID(id)
  if not p or p == sender or p:isDead() then return nil end
  if sender:DistTo(p) > MAX_DIST then return nil end
  return p
end

-- Comandos entre dos jugadores: cliente -> (servidor valida) -> cliente destino.
local RELAY = {
  surgeryRequest = "surgeryAsk",          -- cirujano -> paciente
  surgeryAnswer  = "surgeryAnswered",     -- paciente -> cirujano
  surgeryApply   = "surgeryApplyIn",      -- cirujano -> paciente
  surgeryDone    = "surgeryDoneIn",       -- paciente -> cirujano
  -- v0.1.26: explantar y calibrar el implante instalado de otro jugador
  opRequest      = "opAsk",
  opAnswer       = "opAnswered",
  opApply        = "opApplyIn",
  opDone         = "opDoneIn",
}
local OPS = { explant = true, calibrate = true }

-- Diagnóstico para la PRUEBA COMPLETA: versión del mod en el servidor, jugadores y estado del mundo (que en multijugador es del servidor).
function N.diag(args)
  local W = rawget(_G, "SandevistanWorld")
  local out = { isServer = isServer(), version = tostring(CFG.Build or CFG.Version), clientVersion = tostring(args and args.v or "?"),
                players = "?", campuses = "?", placements = 0, subjects = 0, placed = "", subjectList = "",
                spawner = rawget(_G, "ItemSpawner") ~= nil, authority = W ~= nil and W.authority == true }
  local ok, err = pcall(function()
    out.players = #W.allPlayers()
    local w = W.data()
    local placed, subs = {}, {}
    for k in pairs(w.placements) do out.placements = out.placements + 1; placed[#placed + 1] = tostring(k) end
    for id, sub in pairs(w.subjects) do
      out.subjects = out.subjects + 1
      subs[#subs + 1] = tostring(id) .. ":" .. tostring(sub.variant) .. ":" .. tostring(sub.state) .. "@" .. tostring(sub.zone)
    end
    table.sort(placed); table.sort(subs)
    out.placed = table.concat(placed, ",")
    out.subjectList = string.sub(table.concat(subs, ", "), 1, 400)
    out.campuses = table.concat(w.activeCampuses or {}, ",")
  end)
  local AL = rawget(_G, "SandevistanALife")                 -- (129) Project A-Life
  out.alife = AL and AL.statusLine() or "sin el modulo de A-Life"
  if not ok then out.err = tostring(err) end
  return out
end

-- Medición de la PRUEBA COMPLETA del lado del servidor: zombis a menos de "range" tiles del jugador, en ventanas de 0.5 s, separados por
-- quién los simula (el cliente del probador, el servidor u otro cliente). Si el servidor los ve a velocidad normal mientras el
-- probador los ve frenados, el frenado es solo visual en ese cliente.
local MEASURE_CATS = { "own", "server", "other" }

local function measureReply(player, m, now, err)
  local out = { phase = m.phase, ticks = m.ticks, ms = now - m.t0, range = m.range, err = err }
  for _, c in ipairs(MEASURE_CATS) do
    local r = SM.result(m.meter, c)
    if r then
      out[c .. "_n"], out[c .. "_win"], out[c .. "_mov"], out[c .. "_fast"], out[c .. "_snaps"] = r.zombies, r.windows, r.moving, r.fast, r.snaps
      out[c .. "_v"] = r.speed
    end
  end
  pcall(sendServerCommand, player, MODULE, "mpMeasureReply", out)
end

function N.measureTick()
  if S.isEmpty(N.measures) then return end
  local now = getTimestampMs()
  local zl = nil
  pcall(function() zl = getCell():getZombieList() end)
  local done = {}
  for player, m in pairs(N.measures) do
    local ok, err = pcall(function()
      local px, py = player:getX(), player:getY()
      local r2 = m.range * m.range
      m.ticks = m.ticks + 1
      for i = 0, (zl and zl:size() or 0) - 1 do
        local z = zl:get(i)
        if z and not z:isDead() then
          local x, y = z:getX(), z:getY()
          local dx, dy = x - px, y - py
          if dx * dx + dy * dy <= r2 then
            local okO, owner = pcall(z.getOwnerPlayer, z)
            local c = "server"
            if okO and owner ~= nil then c = (owner == player) and "own" or "other" end
            SM.sample(m.meter, z, x, y, c, now)
          end
        end
      end
      SM.sweep(m.meter, now)
    end)
    if not ok or now >= m.untilMs then done[#done + 1] = { player, m, not ok and tostring(err) or nil } end
  end
  for _, e in ipairs(done) do
    N.measures[e[1]] = nil
    measureReply(e[1], e[2], now, e[3])
  end
end

-- (114) Stats que cambio el mod en el cliente (client/Net.lua, N.queueStat). El servidor es quien manda en los stats del jugador y se los reenvia
-- al cliente: sin esto el Black Lace, el bajon, el gasto del implante, etc. se deshacian solos en multijugador. d = diferencias (resistencia y fatiga),
-- s = valores finales. Solo los stats que toca el mod, acotados por paso.
local STAT_DELTA = { ENDURANCE = true, FATIGUE = true }
local STAT_SET = { PANIC = true, STRESS = true, PAIN = true, FOOD_SICKNESS = true, SICKNESS = true, TEMPERATURE = true }      -- (135) SICKNESS: malestar por cadaveres con la inmunodepresion

function N.applyStats(player, args)
  if not CharacterStat then return 0 end
  local stats = player:getStats()
  local n = 0
  local function apply(name, value, delta)
    local stat = CharacterStat[name]
    if not stat then return end
    pcall(function()
      local v = delta and (stats:get(stat) + value) or value
      stats:set(stat, stat:clamp(v))
      n = n + 1
    end)
  end
  if type(args.d) == "table" then
    for name, v in pairs(args.d) do
      if STAT_DELTA[name] then local x = num(v, -1, 1); if x then apply(name, x, true) end end
    end
  end
  if type(args.s) == "table" then
    for name, v in pairs(args.s) do
      if STAT_SET[name] then local x = num(v, -1000, 1000); if x then apply(name, x, false) end end
    end
  end
  return n
end

-- (114) Ítems que el mod le da al jugador (S.grantItem). Solo del módulo Sandevistan o los vanilla que entrega el mod; ModData solo con valores simples.
-- El ModData y el nombre se ponen ANTES de avisar a los clientes (puestos despues no les llegan).
-- (154) T01/T02: los kits de los rasgos entregan vanilla (libros de guía, agujas de sutura y toallitas con alcohol) y el servidor solo deja
-- entregar estos tipos.
local GIVE_BASE = { ["Base.ElectronicsScrap"] = true, ["Base.Battery"] = true,
                    ["Base.BookFirstAid1"] = true, ["Base.BookElectrician1"] = true,
                    ["Base.SutureNeedle"] = true, ["Base.AlcoholWipes"] = true }
N.giveLog = N.giveLog or {}   -- [jugador] = { t0, n }: tope de GiveMaxPerSecond por segundo

-- (122) Un admin (capacidad AddItem, la del panel de items del juego) puede pedir cualquier item: los kits del menu Debug traen vanilla.
local function canAddAny(player)
  local ok, yes = pcall(function() return player:getRole():hasCapability(Capability.AddItem) end)
  return ok and yes == true
end

local function giveAllowed(fullType, player)
  if type(fullType) ~= "string" then return false end
  if string.sub(fullType, 1, 12) ~= "Sandevistan." and not GIVE_BASE[fullType] and not (player and canAddAny(player)) then return false end
  local ok, found = pcall(function() return getScriptManager():FindItem(fullType) ~= nil end)
  return ok and found
end

-- (168) T13: crea el mapa anotado de uno de los escondites del mod y se lo da al jugador. El nombre viene del cliente: se valida
-- contra Config.AnnotatedMaps (no se acepta cualquier escondite).
function N.stashMap(player, args)
  local AM = rawget(_G, "SandevistanAnnotatedMaps")
  local C = CFG.AnnotatedMaps
  local name = args and args.stash
  if not (AM and AM.order and C and type(name) == "string") then return end
  local c = nil
  for _, key in ipairs(AM.order) do if C[key] and C[key].stash == name then c = C[key]; break end end
  if not c then return end
  local SS = rawget(_G, "StashSystem")
  if not (SS and SS.getStash and SS.doStashItem) then return end
  if AM.ensureRegistered then AM.ensureRegistered() end
  local stash = SS.getStash(c.stash)
  if not stash then
    AM.reinit()
    stash = SS.getStash(c.stash)
  end
  if not stash then return end
  local inv = player:getInventory()
  local item = nil
  pcall(function()
    item = inv:AddItem(stash:getItem())
    if item then SS.doStashItem(stash, item) end
  end)
  if item and sendAddItemToContainer then pcall(sendAddItemToContainer, inv, item) end
end

function N.give(player, fullType, md, name)
  if not giveAllowed(fullType, player) then return nil end
  local now, g = getTimestampMs(), N.giveLog[player]
  if not g or now - g.t0 > 1000 then g = { t0 = now, n = 0 }; N.giveLog[player] = g end
  g.n = g.n + 1
  if g.n > 30 and not canAddAny(player) then return nil end
  local inv = player:getInventory()
  local item = inv:AddItem(fullType)
  if not item then return nil end
  if type(md) == "table" then
    local c = 0
    for k, v in pairs(md) do
      local tv = type(v)
      if type(k) == "string" and (tv == "string" or tv == "number" or tv == "boolean") and c < 16 then item:getModData()[k] = v; c = c + 1 end
    end
  end
  if type(name) == "string" and name ~= "" then pcall(function() item:setName(string.sub(name, 1, 80)); item:setCustomName(true) end) end
  if sendAddItemToContainer then pcall(sendAddItemToContainer, inv, item) end
  return item
end

-- (114) Archivar notas en su carpeta, en el servidor: saca las notas del inventario del jugador y crea o actualiza la carpeta (antes lo hacia el cliente y
-- la carpeta no existia para el servidor). Responde "dossierFiled" con el avance para los avisos y el beneficio del expediente completo.
function N.fileNotes(player, args)
  local st = S.storyById and S.storyById(args.story)
  if not st or type(args.notes) ~= "string" then return end
  local inv = player:getInventory()
  local dtype = "Sandevistan." .. st.dossier
  local dossier = inv:getFirstTypeRecurse(dtype)
  local set = {}
  if dossier then
    local raw = dossier:getModData().SandevistanFiled
    if type(raw) == "string" then for n in string.gmatch(raw, "%d+") do set[tonumber(n)] = true end end
  end
  local added, missing = 0, 0
  for n in string.gmatch(args.notes, "%d+") do
    n = tonumber(n)
    if st.page[n] and not set[n] then
      local note = inv:getFirstTypeRecurse(string.format("Sandevistan.SandevistanNote%02d", n))
      local c = note and note:getContainer()
      if c then
        c:DoRemoveItem(note)
        if sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, c, note) end
        set[n] = true; added = added + 1
      else
        missing = missing + 1                                   -- (122) la nota existe solo en la pantalla del cliente (p. ej. creada alla): se avisa
      end
    end
  end
  local list, have = {}, 0
  for n in pairs(set) do list[#list + 1] = n; if st.page[n] then have = have + 1 end end
  table.sort(list)
  local total = st.total
  local filed = table.concat(list, ",")
  local name = type(args.title) == "string" and string.format("%s (%d/%d)", string.sub(args.title, 1, 60), have, total) or nil
  if not dossier then
    if added == 0 then
      if missing > 0 then sendServerCommand(player, MODULE, "dossierFiled", { story = st.id, added = 0, missing = missing }) end
      return
    end
    dossier = N.give(player, dtype, { SandevistanFiled = filed }, name)
    if not dossier then return end
  elseif added > 0 then
    dossier:getModData().SandevistanFiled = filed
    if name then pcall(function() dossier:setName(name); dossier:setCustomName(true) end) end
    if syncItemModData then pcall(syncItemModData, player, dossier) end
    if syncItemFields then pcall(syncItemFields, player, dossier) end
  end
  -- id: la carpeta que vale; el cliente borra de su inventario las que tenga con otro id (las que solo existian en su pantalla)
  sendServerCommand(player, MODULE, "dossierFiled", { story = st.id, added = added, have = have, total = total, id = dossier:getID(), missing = missing })
end

-- (115) Cuerpo: el servidor lleva heridas, dolor y salud y se los reenvia al cliente (PlayerDamage/PlayerHealth van solo del servidor al cliente).
-- Mismas operaciones que client/Effects.lua; las partes por nombre de BodyPartType, cantidades acotadas.
function N.body(player, args)
  local bd = player:getBodyDamage()
  if not bd then return false end
  local function part(name)
    if type(name) ~= "string" or not BodyPartType or not BodyPartType[name] then return nil end
    local bp = nil
    pcall(function() bp = bd:getBodyPart(BodyPartType[name]) end)
    return bp
  end
  local op, amount = args.op, num(args.amount, 0, 100) or 0
  local ok = pcall(function()
    if op == "pain" then local bp = part(args.part); if bp then bp:setAdditionalPain(math.min(100, bp:getAdditionalPain() + amount)) end
    elseif op == "minPain" then local bp = part(args.part); if bp and bp:getAdditionalPain() < amount then bp:setAdditionalPain(amount) end
    elseif op == "damage" then local bp = part(args.part); if bp then bp:AddDamage(amount) end
    elseif op == "hemorrhage" then
      local bp = part(args.part)
      if bp then
        local sw = CFG.Surgery.StudentDossier.SloppyWound                            -- (125) "light": la herida de la instalacion con el binder
        bp:generateDeepWound()
        bp:setBleedingTime(args.massive and 60 or (args.light and sw.bleeding) or 30)
        bp:AddDamage(args.massive and 60 or (args.light and sw.damage) or 35)
      end
    elseif op == "cut" then local bp = part(args.part); if bp then bp:setCut(true) end
    elseif op == "burn" then local bp = part(args.part); if bp then bp:setBurned() end                 -- (163) T11: quemadura por forzar
    elseif op == "health" then
      local floor = num(args.floor, 0, 1)
      if floor then
        local h = bd:getOverallBodyHealth()
        if h - amount < floor * 100 then amount = math.max(0, h - floor * 100) end
      end
      if amount > 0 then bd:ReduceGeneralHealth(amount) end
    elseif op == "kill" then bd:ReduceGeneralHealth(1000)
    elseif op == "heal" and type(args.parts) == "string" then
      local parts = bd:getBodyParts()
      for i in string.gmatch(args.parts, "%d+") do
        i = tonumber(i)
        local bp = i < parts:size() and parts:get(i) or nil
        if bp and not bp:bitten() then bp:RestoreToFullHealth() end           -- las mordidas nunca se curan
      end
    elseif op == "blood" then player:addBlood(BloodBodyPartType.Head, false, false, false)
    elseif op == "immuno" then N.immunoBody(player, bd, args)                  -- (135) inmunodepresion
    end
  end)
  return ok
end

-- (190) La prenda 3D de la espalda que el cliente se pone o se saca (client/Spine.lua). El cliente la crea pidiendo "give"; el
-- servidor tiene que saber tambien que esta PUESTA para que el resto la vea (setWornItem + sendClothing). Solo items del mod y
-- solo el cuerpo del propio jugador: no toca a nadie mas.
function N.spineWorn(player, args)
  local id = tonumber(args.id)
  if not id then return false end
  local item = nil
  pcall(function() item = player:getInventory():getItemWithIDRecursiv(id) end)
  if not item or not string.find(item:getFullType(), "^Sandevistan%.SandevistanSpine") then return false end
  local loc = nil
  pcall(function() loc = item:getBodyLocation() end)
  if not loc then return false end
  local on = args.on == true
  if on then
    pcall(function() player:setWornItem(loc, item) end)
  else
    pcall(function() player:removeWornItem(item) end)
  end
  if sendClothing then pcall(sendClothing, player, loc, on and item or nil) end
  return true
end

-- (135) Efectos de la inmunodepresion que midio el cliente (client/Immunodep.lua): una parte del cuerpo por indice o el resfrio. Solo suma, con los topes
-- por minuto de Config (Immunodepression.Net); infect solo marca una herida abierta como infectada (nunca la infeccion zombi).
function N.immunoBody(player, bd, args)
  local L = CFG.Immunosuppressant.Immunodepression.Net
  local md = player:getModData().Sandevistan
  if type(md) ~= "table" or (tonumber(md.immunodep) or 0) <= 0 then return end     -- solo con inmunodepresion (la que guardo el cliente)
  local i = tonumber(args.part)
  if i then
    local parts = bd:getBodyParts()
    local bp = (i >= 0 and i < parts:size()) and parts:get(i) or nil
    if not bp then return end
    if args.infect == true and (bp:getScratchTime() > 0 or bp:getCutTime() > 0 or bp:getDeepWoundTime() > 0 or bp:getStitchTime() > 0) then bp:setInfectedWound(true) end
    local lvl = num(args.lvl, 0, L.InfLevel)
    if lvl and bp:isInfectedWound() then bp:setWoundInfectionLevel(math.min(10, bp:getWoundInfectionLevel() + lvl)) end
    local function hold(key, get, set)
      local v = num(args[key], 0, L.Timer)
      if v and bp[get](bp) > 0 then bp[set](bp, bp[get](bp) + v) end
    end
    hold("scr", "getScratchTime", "setScratchTime"); hold("cut", "getCutTime", "setCutTime")
    hold("deep", "getDeepWoundTime", "setDeepWoundTime"); hold("burn", "getBurnTime", "setBurnTime")
  end
  local catch = num(args.catch, 0, L.Cold)
  if catch then bd:setCatchACold(math.min(100, bd:getCatchACold() + catch)) end
  local cold = num(args.cold, 0, L.Cold)
  if cold and bd:isHasACold() then bd:setColdStrength(math.min(100, bd:getColdStrength() + cold)) end
end

-- (115) ModData (y nombre) de un ítem del mod que cambio el cliente (S.syncItem): SyncItemModData va solo del servidor al cliente.
function N.itemMd(player, args)
  local id = tonumber(args.id)
  if not id then return nil end
  local item = nil
  pcall(function() item = player:getInventory():getItemWithIDRecursiv(id) end)
  if not item or string.sub(item:getFullType(), 1, 12) ~= "Sandevistan." then return nil end
  local md, c = item:getModData(), 0
  if type(args.md) == "table" then
    for k, v in pairs(args.md) do
      local tv = type(v)
      if type(k) == "string" and (tv == "string" or tv == "number" or tv == "boolean") and c < 16 then md[k] = v; c = c + 1 end
    end
  end
  if type(args.clear) == "string" then for k in string.gmatch(args.clear, "[^,]+") do md[k] = nil end end
  if type(args.name) == "string" and args.name ~= "" then pcall(function() item:setName(string.sub(args.name, 1, 80)); item:setCustomName(true) end) end
  if syncItemModData then pcall(syncItemModData, player, item) end
  if syncItemFields then pcall(syncItemFields, player, item) end
  return item
end

-- (115) Consumo hecho en el cliente (S.serverUse): una dosis de un drenable o un poco de fluido del inventario del jugador. Corriendo aca el juego
-- sincroniza solo (Use con needSync, sendSyncEntity).
function N.consume(player, args)
  local id = tonumber(args.id)
  if not id then return false end
  local item = nil
  pcall(function() item = player:getInventory():getItemWithIDRecursiv(id) end)
  if not item then return false end
  local c = item:getContainer()
  if args.op == "use" then
    if not pcall(item.Use, item, false, false, true) then pcall(item.Use, item) end
    if c and item:getContainer() == nil and sendRemoveItemFromContainer then pcall(sendRemoveItemFromContainer, c, item) end
    return true
  elseif args.op == "fluid" then
    local amount = num(args.amount, 0, 1)
    local fc = nil
    pcall(function() fc = item:getFluidContainer() end)
    if not fc or not amount then return false end
    pcall(function() fc:removeFluid(amount) end)
    pcall(function() item:sendSyncEntity(nil) end)
    return true
  end
  return false
end

-- (115, 119) Skill de adaptacion: el servidor reenvia su XP (syncXp) y SyncXp desde el cliente pide permisos de admin. El cliente manda el nivel y la
-- fraccion dentro del nivel (S.syncPerk) y el servidor arma la XP con SU escala (S.perkXPFor + S.addPerkXP, que se calibra leyendo de vuelta). Solo esa skill.
-- (123) Con Beyond Ten el nivel llega hasta 15 (maestria del implante militar): el servidor deja la skill en 10 y escribe la maestria en el almacen de
-- Beyond Ten (S.writeMastery), que es el suyo y el autoritativo; nunca le suma XP a la skill por AddXP (Beyond Ten la tomaria por maestria).
-- Pasar de 10 pide Beyond Ten y que la copia del servidor del jugador tenga un implante con maestria.
local function masteryAllowed(player)
  if not (S.beyondTen and S.beyondTen()) then return false end
  local d = nil
  pcall(function() d = player:getModData().Sandevistan end)
  local v = type(d) == "table" and CFG.Variants[d.variant] or nil
  return v ~= nil and v.mastery == true
end

function N.perk(player, args)
  local perk = S.perk and S.perk()
  local level = num(args.level, 0, 10 + ((CFG.Mastery and #CFG.Mastery.Table) or 0))
  if not perk or not level then return false end
  level = math.floor(level)
  local frac = num(args.frac, 0, 0.999) or 0
  if level >= 10 and not masteryAllowed(player) then level, frac = 10, 0 end
  if S.writeMastery and S.writeMastery(player, perk, level, frac) then return true end
  local want = S.perkXPFor(perk, level, frac)
  local pl, have = nil, nil
  pcall(function() pl = player:getPerkLevel(perk) end)
  have = S.perkXP(player, perk)
  if pl ~= level or (have and have > want + 0.5) then
    pcall(function() player:setPerkLevelDebug(perk, level); player:getXp():setXPToLevel(perk, level) end)
    have = S.perkXP(player, perk)
  end
  if have and want - have >= 1 then S.addPerkXP(player, perk, want - have) end
  return true
end

-- (115) Recetas nativas del mod que el cliente da por sabidas (Medical.syncRecipes): la lista la guarda el servidor y el crafteo se valida alla.
-- Solo las de Config.Crafting.Recipes, por el nombre pelado; avisa al cliente con sendSyncPlayerFields (0x1 = recetas, como ISResearchRecipe).
local function modRecipe(bare)
  for _, full in pairs(CFG.Crafting.Recipes) do if string.match(full, "([^%.]+)$") == bare then return true end end
  return false
end

function N.recipes(player, args)
  local n = 0
  if type(args.learn) == "string" then
    for bare in string.gmatch(args.learn, "[^,]+") do
      if modRecipe(bare) then pcall(function() player:learnRecipe(bare) end); n = n + 1 end
    end
  end
  if type(args.forget) == "string" then
    for bare in string.gmatch(args.forget, "[^,]+") do
      if modRecipe(bare) then pcall(function() player:getKnownRecipes():remove(bare) end); n = n + 1 end
    end
  end
  if n > 0 and sendSyncPlayerFields then pcall(sendSyncPlayerFields, player, 1) end
  return n
end

-- (137) Rasgos del mod que el cliente eligio al crear el personaje (client/Sandevistan/Traits.lua): en una partida alojada el servidor los perdia al
-- crear al jugador (applyTraits saltea un rasgo que no encuentra). Solo ids del mod, solo con la opcion de rasgos encendida, solo a un personaje
-- nuevo (menos de Traits.ServerRestoreMaxHours de vida) y una sola vez. Si el servidor no conoce el rasgo lo registra (y lo cuenta: eso dice la
-- causa). Agrega los que falten con sus subidas de skill (como applyTraits), manda la lista al cliente (sendSyncPlayerFields 2 = rasgos) y responde.
function N.traits(player, args)
  local TD = rawget(_G, "SandevistanTraitDefs")
  local res = { added = 0, had = 0, registered = 0 }
  local md = player:getModData()
  local hours = nil
  pcall(function() hours = player:getHoursSurvived() end)
  local on = not (SandboxVars and SandboxVars.Sandevistan and SandboxVars.Sandevistan.CharacterTraits == false)
  if not TD or type(TD.ids) ~= "table" then res.refused = "sin TraitDefs"
  elseif md.SandevistanTraitsRestored then res.refused = "ya repuestos"
  elseif not on then res.refused = "rasgos del mod apagados"
  elseif hours == nil or hours >= (CFG.Traits.ServerRestoreMaxHours or 1) then res.refused = "personaje no nuevo"
  elseif type(args.ids) ~= "string" then res.refused = "sin ids" end
  if not res.refused then
    md.SandevistanTraitsRestored = true
    local allowed = {}
    for _, id in ipairs(TD.ids) do allowed[id] = true end
    for id in string.gmatch(args.ids, "[^,]+") do
      if allowed[id] then
        allowed[id] = nil                                   -- cada id una sola vez
        local trait = nil
        pcall(function() trait = CharacterTrait.get(ResourceLocation.of(id)) end)
        if not trait then
          pcall(function() CharacterTrait.register(id) end)
          pcall(function() trait = CharacterTrait.get(ResourceLocation.of(id)) end)
          if trait then res.registered = res.registered + 1 end
        end
        if trait and player:hasTrait(trait) then
          res.had = res.had + 1
        elseif trait then
          player:getCharacterTraits():add(trait)
          pcall(function() player:modifyTraitXPBoost(trait, false) end)
          for _, xp in ipairs((TD.xp and TD.xp[id]) or {}) do
            local perk = Perks and Perks[xp[1]]
            if perk then
              pcall(function()
                local level = math.min(10, player:getPerkLevel(perk) + xp[2])
                player:setPerkLevelDebug(perk, level); player:getXp():setXPToLevel(perk, level)
              end)
            end
          end
          res.added = res.added + 1
        end
      end
    end
    if res.added > 0 and sendSyncPlayerFields then pcall(sendSyncPlayerFields, player, 2) end
  end
  S.log(string.format("rasgos del mod para %s (%s): agregados=%d, ya estaban=%d, registrados=%d%s", tostring(player:getUsername()),
    tostring(args.ids), res.added, res.had, res.registered, res.refused and (", rechazo: " .. res.refused) or ""))
  sendServerCommand(player, MODULE, "traitsAck", res)
  return res
end

local function onClientCommand(module, command, player, args)
  if module ~= MODULE or not player then return end
  -- v0.1.30 (13): una tabla vacía llega como nil (por eso el diagnóstico del servidor nunca respondía): se trata como vacía
  if type(args) ~= "table" then args = {} end

  if command == "active" then
    local zs = tonumber(args.zs)
    if args.on and (not zs or zs <= 0 or zs > 1) then return end   -- descarta valores inválidos
    if zs and zs < minLegitZs() then zs = minLegitZs() end          -- y acota los que ningún tramo real produce
    sendServerCommand(MODULE, "remoteActive", {
      id = player:getOnlineID(), on = args.on and true or false, zs = args.on and zs or nil,
    })

  elseif command == "look" then
    local v = args.variant
    if v ~= "lab" and v ~= "military" and v ~= "destroyed" and v ~= "none" then return end
    sendServerCommand(MODULE, "remoteLook", { id = player:getOnlineID(), variant = v,
                                              proto = (args.proto == "04" or args.proto == "06" or args.proto == "07") and args.proto or nil })

  elseif command == "grant" then
    -- v0.1.30 (32): entrega de la guia de campo creada POR EL SERVIDOR (un item que crea el cliente puede no ser valido para el servidor y no se deja tirar ni mover).
    -- Solo esa guia, y una sola si el jugador ya la lleva.
    if args.type ~= "Sandevistan.SandevistanFieldGuide" then return end
    local inv = player:getInventory()
    if args.unique and inv:getFirstTypeRecurse(args.type) then return end
    local item = inv:AddItem(args.type)
    if item and sendAddItemToContainer then pcall(sendAddItemToContainer, inv, item) end

  elseif command == "stats" then
    N.applyStats(player, args)

  elseif command == "body" then
    N.body(player, args)

  elseif command == "itemMd" then
    N.itemMd(player, args)

  elseif command == "spineWorn" then
    N.spineWorn(player, args)

  elseif command == "consume" then
    N.consume(player, args)

  elseif command == "perk" then
    N.perk(player, args)

  elseif command == "recipes" then
    N.recipes(player, args)

  elseif command == "speed" then                              -- (118) Taller y recarga rapida: la duracion de las acciones la calcula el servidor
    local AS = rawget(_G, "SandevistanActionSpeed")
    if AS then AS.set(player, args) end

  elseif command == "give" then
    N.give(player, args.type, args.md, args.name)

  elseif command == "stashMap" then                            -- (168) T13: mapa anotado para probar (lo crea el servidor)
    N.stashMap(player, args)

  elseif command == "traits" then                             -- (137) rasgos del mod de un personaje nuevo
    N.traits(player, args)

  elseif command == "fileNotes" then
    N.fileNotes(player, args)

  elseif command == "scream" then
    local n = num(args.n, 1, 3)
    if not n then return end
    n = math.floor(n)
    sendServerCommand(MODULE, "remoteScream", { id = player:getOnlineID(), n = n })
    local radius = num(args.radius, 1, 40) or 25
    pcall(function() addSound(player, player:getX(), player:getY(), player:getZ(), radius, radius) end)

  elseif command == "mpDiag" then
    sendServerCommand(player, MODULE, "mpDiagReply", N.diag(args))

  elseif command == "mpMeasure" then
    local ms, range = num(args.ms, 1000, 40000), num(args.range, 4, 30)
    if not ms or not range then return end
    local now = getTimestampMs()
    N.measures[player] = { phase = (args.phase == "base" or args.phase == "on") and args.phase or "?", range = range,
                           t0 = now, untilMs = now + ms, ticks = 0, meter = SM.new() }

  elseif command == "implantDeath" then
    local W = rawget(_G, "SandevistanWorld")
    local v = args.variant
    if not W or not W.registerPlayerDeath or (v ~= "lab" and v ~= "military") then return end
    local x, y, z = num(args.x, -1e7, 1e7), num(args.y, -1e7, 1e7), num(args.z, -64, 64)
    if not x or not y or not z then return end
    -- el cadáver tiene que quedar donde el servidor ve al jugador, y una sola muerte por minuto
    if math.abs(player:getX() - x) > 6 or math.abs(player:getY() - y) > 6 then return end
    local key = tostring(player:getUsername() or player:getOnlineID())
    local now = getTimestampMs()
    if N.lastDeath[key] and now - N.lastDeath[key] < 60000 then return end
    N.lastDeath[key] = now
    W.registerPlayerDeath({ variant = v, degradation = num(args.deg, 1, 3) or 1, degradationFloor = num(args.floor, 1, 3) or 1 },
      x, y, z, player:getOnlineID())

  elseif command == "subjectExtracted" then
    local W = rawget(_G, "SandevistanWorld")
    local id = args.id
    if not W or (type(id) ~= "string" and type(id) ~= "number") then return end
    local sub = W.data().subjects[id]
    if sub and sub.state == "corpse" and sub.x and math.abs(player:getX() - sub.x) <= 8 and math.abs(player:getY() - sub.y) <= 8 then
      W.markSubject(id, "extracted")
    end

  elseif RELAY[command] then
    local dest = target(player, args)
    if not dest then return end
    local out = { from = player:getOnlineID(), name = player:getUsername(), ok = args.ok and true or false }
    if command == "surgeryApply" then
      local variant = args.variant
      if variant ~= "lab" and variant ~= "military" then return end
      out.variant = variant
      out.deg = num(args.deg, 1, 3) or 1
      out.floor = num(args.floor, 1, 3) or 1
      out.proto = (args.proto == "04" or args.proto == "06" or args.proto == "07") and args.proto or nil
      out.plate = plateOf(args.plate)
      out.sloppy = args.sloppy and true or nil                                       -- (125) herida de la instalacion con el binder
    end
    if command:sub(1, 2) == "op" then
      if not OPS[args.op] then return end
      out.op = args.op
      if command == "opDone" then
        out.done = args.done and true or false
        if args.variant == "lab" or args.variant == "military" or args.variant == "destroyed" then
          out.variant = args.variant
          out.deg = num(args.deg, 1, 3) or 1
          out.floor = num(args.floor, 1, 3) or 1
          out.proto = (args.proto == "04" or args.proto == "06" or args.proto == "07") and args.proto or nil
          out.plate = plateOf(args.plate)
        end
      elseif command == "opApply" then
        out.success = args.success and true or false
      elseif command == "opAnswer" and args.op == "calibrate" then
        out.wear = num(args.wear, 0, 3)                                         -- (122) para el costo de la calibracion
      end
    end
    sendServerCommand(dest, MODULE, RELAY[command], out)
  end
end

if isServer() then
  Events.OnClientCommand.Add(S.safe("Net.OnClientCommand", onClientCommand))
  Events.OnTick.Add(S.safe("Net.MeasureTick", N.measureTick))
end

return N
