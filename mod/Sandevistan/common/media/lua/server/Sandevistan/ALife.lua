-- Sandevistan / ALife (servidor; en SP corre en el mismo proceso). (129) Compatibilidad con Project A-Life [ALIFE NPCS].
-- Sus NPCs son zombis por dentro ("shells") y se visten con cualquier prenda desde su creador, tambien la espalda del Sandevistan
-- (SandevistanSpine*). Un NPC vestido asi deja el implante en su cadaver: se registra su muerte como la de un ex-sujeto
-- (World.registerNpcDeath) y la extraccion, la cirugia y el desgaste son los de siempre. Solo actua si A-Life esta cargado.
--
-- De A-Life se usa su API publica (ProjectALife.Interop: el hook "loot.corpse", isNpc, uidOf, actorOf) y una sola pieza interna,
-- ProjectALife.ProfileHydrator.plan(actor).clothing: al morir, A-Life tira un dado sobre la ropa y puede borrar la prenda antes de avisar,
-- asi que lo que llevaba puesto se lee del perfil. Si eso falla, se mira lo que todavia tiene encima.
-- Dos caminos llegan aca: el hook "loot.corpse" (despues del reparto de botin de A-Life) y nuestro OnZombieDead (por si el hook no existe
-- en otra version o A-Life no lo llama). Una marca en el ModData del cuerpo evita registrar dos implantes por el mismo NPC.
require "Sandevistan/Core"
require "Sandevistan/World"

local CFG = SandevistanConfig
local S = Sandevistan
local W = SandevistanWorld

SandevistanALife = { hooked = false, handled = 0, stripped = 0, errors = 0, lastError = nil }
local AL = SandevistanALife

local SPINE_PREFIX = "^Sandevistan%.SandevistanSpine"

function AL.interop()
  local PA = rawget(_G, "ProjectALife")
  return type(PA) == "table" and type(PA.Interop) == "table" and PA.Interop or nil
end

function AL.enabled()
  return W.authority and CFG.ALife and CFG.ALife.Enabled ~= false and AL.interop() ~= nil
end

-- Variante del implante por el tipo de la prenda (con o sin On/Red), o nil si no es la espalda del Sandevistan.
function AL.variantOf(fullType)
  if type(fullType) ~= "string" or not string.find(fullType, SPINE_PREFIX) then return nil end
  if string.find(fullType, "^Sandevistan%.SandevistanSpineMilitary") then return "military" end
  if string.find(fullType, "^Sandevistan%.SandevistanSpineLab") then return "lab" end
  return nil
end

-- Si lleva dos, gana la militar.
local function better(a, b)
  if a == "military" or b == "military" then return "military" end
  return a or b
end

-- Del perfil: el atuendo que A-Life eligio para ese NPC (las entradas son { itemType = "Modulo.Tipo", ... }).
function AL.variantFromProfile(actor)
  local PA = rawget(_G, "ProjectALife")
  local H = PA and PA.ProfileHydrator
  if type(actor) ~= "table" or type(H) ~= "table" or type(H.plan) ~= "function" then return nil end
  local ok, plan = pcall(H.plan, actor)
  if not ok or type(plan) ~= "table" or type(plan.clothing) ~= "table" then return nil end
  local found = nil
  for _, entry in pairs(plan.clothing) do
    local t = type(entry) == "table" and entry.itemType or entry
    found = better(found, AL.variantOf(t))
  end
  return found
end

-- Lo que todavia lleva encima (prendas puestas e inventario).
local function eachSpine(shell, fn)
  pcall(function()
    local worn = shell:getWornItems()
    for i = 0, worn:size() - 1 do
      local it = worn:get(i):getItem()
      if it and AL.variantOf(it:getFullType()) then fn(it) end
    end
  end)
  pcall(function()
    local items = shell:getInventory():getItems()
    for i = 0, items:size() - 1 do
      local it = items:get(i)
      if it and AL.variantOf(it:getFullType()) then fn(it) end
    end
  end)
end

function AL.variantFromBody(shell)
  local found = nil
  eachSpine(shell, function(it) found = better(found, AL.variantOf(it:getFullType())) end)
  return found
end

-- La prenda es solo el modelo (el implante de verdad queda en el cadaver): se le saca, para que nadie saquee un objeto que no sirve, y en su
-- lugar va la placa 3D como visual del cuerpo, igual que los ex-sujetos (el cadaver copia los visuales del cuerpo, no la ropa que se saco).
function AL.strip(shell, variant)
  local list = {}
  eachSpine(shell, function(it) list[#list + 1] = it end)
  for _, it in ipairs(list) do
    pcall(function() shell:getWornItems():remove(it) end)
    pcall(function() shell:getInventory():Remove(it) end)
    AL.stripped = AL.stripped + 1
  end
  if variant and CFG.ExSubjects.Visual3D and CFG.ExSubjects.Visual3D.Enabled then
    local md = nil
    pcall(function() md = shell:getModData() end)
    local fullType = "Sandevistan.SandevistanSpine" .. (variant == "military" and "Military" or "Lab")
    if not (md and md.SandevistanVisual == fullType) then
      local ok = pcall(function() shell:addBodyVisualFromItemType(fullType) end)
      if md and ok then md.SandevistanVisual = fullType end
    end
  end
  return #list
end

-- Clave del NPC (uid y generacion de A-Life) para no registrar dos veces el mismo.
-- Sin la copia del actor, la generacion sale del cuerpo como en Interop.onDead (ModData ProjectALifeGeneration o la variable ALifeGeneration).
local function keyOf(shell, actor)
  local I = AL.interop()
  local uid = type(actor) == "table" and actor.uid or nil
  if uid == nil and I and type(I.uidOf) == "function" then pcall(function() uid = I.uidOf(shell) end) end
  if uid == nil then return nil end
  local gen = type(actor) == "table" and tonumber(actor.generation) or nil
  if gen == nil then pcall(function() gen = tonumber(shell:getModData().ProjectALifeGeneration) end) end
  if gen == nil and I and type(I.variable) == "function" then pcall(function() gen = tonumber(I.variable(shell, "ALifeGeneration")) end) end
  return tostring(uid) .. ":" .. tostring(gen or "?")
end

-- Un NPC de A-Life murio: si llevaba la espalda del Sandevistan, su cadaver lleva el implante. Devuelve la variante registrada o nil.
function AL.onNpcDeath(shell, actor, via)
  if not shell or not AL.enabled() then return nil end
  local md = nil
  pcall(function() md = shell:getModData() end)
  if type(md) ~= "table" then return nil end
  -- la marca lleva el uid y la generacion del NPC: el motor recicla los objetos zombi y uno nuevo podria traer el ModData de otro
  local key = keyOf(shell, actor) or "?"
  if md.SandevistanALife and md.SandevistanALifeKey == key then
    AL.strip(shell, md.SandevistanALife ~= "none" and md.SandevistanALife or nil)     -- A-Life pudo devolver cosas al inventario entre los dos caminos
    return nil
  end
  local variant = better(AL.variantFromProfile(actor), AL.variantFromBody(shell))
  md.SandevistanALife, md.SandevistanALifeKey = variant or "none", key
  if not variant then return nil end
  AL.strip(shell, variant)
  local deg = CFG.ALife.Degradation and CFG.ALife.Degradation[variant] or 1.0
  local x, y, z = shell:getX(), shell:getY(), shell:getZ()
  local id = W.registerNpcDeath({ variant = variant, degradation = deg, npcKey = key }, x, y, z, "alife")
  AL.handled = AL.handled + 1
  S.log(string.format("NPC de A-Life %s con implante %s murio en %.1f,%.1f,%d (%s): se espera su cadaver como %s (desgaste %.2f)",
    tostring(keyOf(shell, actor)), variant, x, y, math.floor(z), tostring(via), tostring(id), deg))
  return variant
end

-- Hook "loot.corpse" de A-Life: (shell, copia del actor, plan de botin).
function AL.onLootCorpse(shell, actor)
  local ok, err = pcall(AL.onNpcDeath, shell, actor, "loot.corpse")
  if not ok then AL.errors = AL.errors + 1; AL.lastError = tostring(err); S.warnOnce("alifeLoot", "A-Life loot.corpse: " .. tostring(err)) end
end

-- Respaldo: cualquier zombi que muere; solo cuenta si A-Life dice que es uno de sus NPCs.
function AL.onZombieDead(z)
  local I = AL.interop()
  if not I or not AL.enabled() or type(I.isNpc) ~= "function" then return end
  local okN, npc = pcall(I.isNpc, z)
  if not okN or not npc then return end
  local actor = nil
  if type(I.uidOf) == "function" and type(I.actorOf) == "function" then
    pcall(function() actor = I.actorOf(I.uidOf(z)) end)
  end
  local ok, err = pcall(AL.onNpcDeath, z, actor, "OnZombieDead")
  if not ok then AL.errors = AL.errors + 1; AL.lastError = tostring(err); S.warnOnce("alifeDead", "A-Life OnZombieDead: " .. tostring(err)) end
end

-- Se engancha cuando A-Life ya esta cargado (puede cargar despues que este archivo): al cargar, al arrancar la partida y al arrancar el servidor.
function AL.install()
  if AL.hooked or not W.authority then return AL.hooked end
  local I = AL.interop()
  if not I or type(I.on) ~= "function" then return false end
  local ok, res = pcall(I.on, "loot.corpse", AL.onLootCorpse)
  AL.hooked = ok and res == true
  S.log("Project A-Life detectado: hook loot.corpse " .. (AL.hooked and "registrado" or ("NO registrado (" .. tostring(ok and res or res) .. "); queda el respaldo por OnZombieDead")))
  return AL.hooked
end

function AL.statusLine()
  if not AL.interop() then return "Project A-Life no cargado" end
  return string.format("Project A-Life: integracion %s, hook loot.corpse %s, NPCs con implante = %d, prendas sacadas = %d, errores = %d%s",
    AL.enabled() and "activa" or "apagada", AL.hooked and "si" or "no", AL.handled, AL.stripped, AL.errors,
    AL.lastError and (" (ultimo: " .. AL.lastError .. ")") or "")
end

if W.authority then
  AL.install()
  Events.OnGameStart.Add(S.safe("ALife.OnGameStart", AL.install))
  if Events.OnServerStarted then Events.OnServerStarted.Add(S.safe("ALife.OnServerStarted", AL.install)) end
  Events.OnZombieDead.Add(S.safe("ALife.OnZombieDead", AL.onZombieDead))
end

return AL
