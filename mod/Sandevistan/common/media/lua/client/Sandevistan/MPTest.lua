-- Sandevistan / MPTest: diagnóstico de multijugador (paso 2 de Debug → Pruebas e informes → PRUEBA COMPLETA). Escribe en consola
-- ([Sandevistan][MP]) y en Zomboid/Lua/Sandevistan_mp.txt para pasarlo. Conviene correrlo en el host y en el cliente
-- con otro jugador cerca (a menos de 2 tiles para probar también la cirugía remota).
require "Sandevistan/Core"
require "Sandevistan/Net"
require "Sandevistan/Spine"

local S = Sandevistan
local N = SandevistanNet

SandevistanMPTest = { lines = {} }
local T = SandevistanMPTest

local function out(line)
  line = S.ascii(line)
  table.insert(T.lines, line)
  print("[Sandevistan][MP] " .. line)
end

local function flush()
  pcall(function()
    local w = getFileWriter("Sandevistan_mp.txt", true, false)
    for _, l in ipairs(T.lines) do w:write(l .. "\r\n") end
    w:close()
  end)
end

function T.onServerReply(args)
  T.gotReply = true
  T.replyMs = T.sentMs and (S.realMs() - T.sentMs) or nil
  out("SERVIDOR: version=" .. tostring(args.version) .. (args.version ~= SandevistanConfig.Build and "  <-- DISTINTA de la de este cliente" or "")
      .. " isServer=" .. tostring(args.isServer) .. " mundo a cargo=" .. tostring(args.authority)
      .. " respuesta en " .. tostring(T.replyMs) .. " ms")
  out("SERVIDOR: jugadores vistos=" .. tostring(args.players) .. " campus activos=" .. tostring(args.campuses)
      .. " sets colocados=" .. tostring(args.placements) .. " (" .. tostring(args.placed) .. ") ItemSpawner=" .. tostring(args.spawner))
  out("SERVIDOR: ex-sujetos=" .. tostring(args.subjects) .. " (" .. tostring(args.subjectList) .. ")")
  if args.alife then out("SERVIDOR: " .. tostring(args.alife)) end
  if args.err then out("SERVIDOR: ERROR leyendo el mundo: " .. tostring(args.err)) end
  flush()
end

function T.run(player)
  T.lines = {}
  T.gotReply = false
  out("=== Diagnostico multijugador " .. SandevistanConfig.Version .. " ===")
  out("isClient=" .. tostring(isClient()) .. " isServer=" .. tostring(isServer()) .. " Net.enabled=" .. tostring(N.enabled()))
  out("ItemSpawner=" .. tostring(rawget(_G, "ItemSpawner") ~= nil) .. " sendClothing=" .. tostring(rawget(_G, "sendClothing") ~= nil)
      .. " addXpNoMultiplier=" .. tostring(rawget(_G, "addXpNoMultiplier") ~= nil))
  local d = S.data(player)
  out("yo: id=" .. tostring(pcall(function() return player:getOnlineID() end) and player:getOnlineID()) .. " variante=" .. tostring(d.variant)
      .. " nivel=" .. S.level(d) .. " prenda 3D=" .. tostring(SandevistanSpine.wornSpine(player) and SandevistanSpine.wornSpine(player):getFullType()))
  -- otros jugadores: distancia, prenda 3D que se les ve y lo que llegó por la red
  pcall(function()
    local online = getOnlinePlayers()
    for i = 0, (online and online:size() or 0) - 1 do
      local o = online:get(i)
      if o and o ~= player then
        local id = o:getOnlineID()
        local worn = SandevistanSpine.wornSpine(o)
        local look = N.look[id]
        out("otro jugador " .. tostring(o:getUsername()) .. " id=" .. tostring(id) .. " dist=" .. string.format("%.1f", player:DistTo(o))
            .. " prenda 3D vista=" .. tostring(worn and worn:getFullType()) .. " look recibido=" .. tostring(look and look.variant)
            .. " activo remoto=" .. tostring(N.remote[id] ~= nil))
      end
    end
  end)
  out("giveItem usa: " .. tostring(S.lastGiveVia or "(todavia ninguno)"))
  -- XP de la skill: la que ve el juego vs la propia
  pcall(function()
    local perk = S.perk()
    if perk then out("skill: nivel del juego=" .. player:getPerkLevel(perk) .. " nivel propio=" .. S.level(d) .. " XP propia=" .. string.format("%.0f", d.adaptXP)) end
  end)
  if isClient() then
    -- v0.1.30 (13): con una tabla vacía el servidor recibe nil y no respondía nunca; además se registra el manejador acá por si
    -- el orden de carga lo dejó afuera
    if N and N.handlers then N.handlers.mpDiagReply = T.reply end
    T.sentMs = S.realMs()
    pcall(function() sendClientCommand(player, "Sandevistan", "mpDiag", { v = SandevistanConfig.Build }) end)
    out("consultando al servidor... (la respuesta se agrega abajo y se guarda en Lua/Sandevistan_mp.txt)")
  end
  flush()
end

T.reply = S.safe("MPTest.reply", T.onServerReply)
if N and N.handlers then N.handlers.mpDiagReply = T.reply end
return T
