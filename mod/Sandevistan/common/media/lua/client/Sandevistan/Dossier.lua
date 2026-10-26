-- Sandevistan / Dossier: expedientes de notas de lore (v0.1.29). Hay uno por historia (CFG.Notes.Stories: investigador 1-12,
-- guardia del depósito 13-15, estudiante 16-20). Las notas sueltas se archivan en su carpeta (la nota se consume, la carpeta guarda
-- la lista en su modData) y la carpeta se lee entera, en el orden de la historia, con las páginas que faltan marcadas.
require "Sandevistan/Core"
require "Sandevistan/Effects"
require "Sandevistan/NotesText"
require "Sandevistan/Net"

local CFG = SandevistanConfig
local S = Sandevistan
local E = SandevistanEffects
local getText = S.text

SandevistanDossier = {}
local D = SandevistanDossier
local PREFIX = "Sandevistan."

function D.noteType(n) return string.format("%sSandevistanNote%02d", PREFIX, n) end

function D.noteNumber(fullType)
  local n = string.match(fullType or "", "^Sandevistan%.SandevistanNote(%d%d)$")
  return n and tonumber(n) or nil
end

-- historia, página y total de una nota
function D.storyOfNote(n)
  for _, st in ipairs(CFG.Notes.Stories) do
    if st.page[n] then return st, st.page[n], st.total end
  end
  return nil
end

function D.storyOfDossier(fullType)
  for _, st in ipairs(CFG.Notes.Stories) do
    if fullType == PREFIX .. st.dossier then return st end
  end
  return nil
end

function D.total(story) return story.total end

-- páginas archivadas: "1,3,4" en el modData del ítem -> { [1]=true, ... }
function D.filed(item)
  local set = {}
  local ok, raw = pcall(function() return item:getModData().SandevistanFiled end)
  if ok and type(raw) == "string" then
    for n in string.gmatch(raw, "%d+") do set[tonumber(n)] = true end
  end
  return set
end

function D.count(item, story)
  local c = 0
  for n in pairs(D.filed(item)) do
    if story.page[n] then c = c + 1 end
  end
  return c
end

local function save(item, set)
  local list = {}
  for n in pairs(set) do list[#list + 1] = n end
  table.sort(list)
  item:getModData().SandevistanFiled = table.concat(list, ",")
end

-- nombre con el avance ("Researcher Dossier (4/10)"); customName para que el guardado lo conserve
function D.refreshName(item, story)
  S.try("dossierName", function()
    item:setName(string.format("%s (%d/%d)", getText("IGUI_Sandevistan_Dossier_" .. story.id), D.count(item, story), D.total(story)))
    item:setCustomName(true)
  end)
end

function D.find(player, story)
  return player:getInventory():getFirstTypeRecurse(PREFIX .. story.dossier)
end

-- notas sueltas de la historia en el inventario que todavía no están en "dossier" (si hay)
function D.looseNotes(player, story, dossier)
  local set = dossier and D.filed(dossier) or {}
  local out, inv = {}, player:getInventory()
  for _, n in ipairs(story.notes) do
    local it = (not set[n]) and inv:getFirstTypeRecurse(D.noteType(n)) or nil
    if it then out[#out + 1] = { n = n, item = it } end
  end
  return out
end

-- Avisos al archivar (y el beneficio del expediente completo).
local function filedFeedback(player, story, added, have, total)
  E.halo(player, getText(have >= total and "IGUI_Sandevistan_DossierComplete" or "IGUI_Sandevistan_DossierFiled", added, have, total))
  if have >= total then
    pcall(function() S.data(player).knows["dossier_" .. story.id] = true end)   -- (106) queda aprendido (beneficios permanentes)
    local key = "IGUI_Sandevistan_DossierBenefit_" .. story.id
    if getText(key) ~= key then E.halo(player, getText(key), 120, 220, 255) end
  end
end

-- (114) Multijugador: archiva el SERVIDOR (server/Net.lua, "fileNotes"): saca las notas y crea o actualiza la carpeta (si la creara el
-- cliente, para el servidor no existiria: no se podria tirar ni pasar a otro jugador).
function D.requestFile(player, story, numbers)
  sendClientCommand(player, "Sandevistan", "fileNotes", { story = story.id, notes = table.concat(numbers, ","),
    title = getText("IGUI_Sandevistan_Dossier_" .. story.id) })
end

-- Respuesta del servidor: los avisos.
function D.onFiled(args)
  local story = S.storyById and S.storyById(args.story)
  local player = getSpecificPlayer(0)
  if not story or not player then return end
  local added, have, total = tonumber(args.added) or 0, tonumber(args.have) or 0, tonumber(args.total) or D.total(story)
  if added > 0 then filedFeedback(player, story, added, have, total) end
  if added == 0 and (tonumber(args.missing) or 0) > 0 then E.halo(player, getText("IGUI_Sandevistan_DossierNotOnServer"), 255, 160, 60) end   -- (122)
end

-- Archiva las notas { {n=, item=}, ... } en el expediente de la historia (lo crea si el jugador no tiene uno). Devuelve cuántas
-- (en multijugador, cuantas se pidieron: los avisos llegan con la respuesta del servidor).
function D.fileNotes(player, story, notes)
  if isClient() and not isServer() then
    local numbers = {}
    for _, e in ipairs(notes) do numbers[#numbers + 1] = e.n end
    if #numbers > 0 then D.requestFile(player, story, numbers) end
    return #numbers
  end
  local dossier = D.find(player, story)
  local created = false
  if not dossier then
    dossier = S.giveItem(player:getInventory(), PREFIX .. story.dossier)
    created = true
  end
  if not dossier then return 0 end
  local set, added = D.filed(dossier), 0
  for _, e in ipairs(notes) do
    local c = e.item and e.item:getContainer()
    if c and not set[e.n] then
      set[e.n] = true; added = added + 1
      c:DoRemoveItem(e.item)
      if isClient() and rawget(_G, "sendRemoveItemFromContainer") then pcall(sendRemoveItemFromContainer, c, e.item) end
    end
  end
  if added > 0 or created then
    save(dossier, set)
    D.refreshName(dossier, story)
    if rawget(_G, "syncItemFields") then pcall(syncItemFields, player, dossier) end
    local have = D.count(dossier, story)
    if have >= D.total(story) then S.dossierComplete(player, story.id) end          -- (106) queda aprendido (beneficios permanentes)
    filedFeedback(player, story, added, have, D.total(story))
  end
  return added
end

SandevistanNet.handlers.dossierFiled = function(args) D.onFiled(args) end

-- Texto de lectura del expediente: título y cuerpo (formato del panel de texto enriquecido)
-- style (opcional): estilo del lector (Reader.STYLES) en que se va a mostrar. Cada <H2> y cada <TEXT> vuelve el color a blanco, asi que la tinta del estilo se repite despues de
-- cada uno (v0.1.30 (94): en el expediente de estudiante, claro, los titulos y el texto salian casi blancos sobre el fondo lila y no se leian).
function D.readText(item, story, style)
  local set, have, total = D.filed(item), 0, D.total(story)
  local R = rawget(_G, "SandevistanReader")
  local ink = (style and R and R.inkTag) and (" " .. R.inkTag(style) .. " ") or " "
  local dim = (style and R and R.dimTag) and R.dimTag(style) or "<RGB:0.55,0.55,0.55>"
  local body = { ink, getText("IGUI_Sandevistan_DossierCover_" .. story.id), " <LINE> <LINE> " }
  for page, n in ipairs(story.notes) do
    local note = SandevistanNotes and SandevistanNotes[n]
    if set[n] and note then
      have = have + 1
      body[#body + 1] = string.format(" <H2>%s%s (%d/%d) <LINE> <TEXT>%s%s <LINE> <LINE> ", ink, note.title, page, total, ink, note.text)
    else
      body[#body + 1] = " " .. dim .. " " .. getText("IGUI_Sandevistan_DossierMissing", page) .. " <LINE> <LINE>" .. ink
    end
  end
  return string.format("%s (%d/%d)", getText("IGUI_Sandevistan_Dossier_" .. story.id), have, total), table.concat(body)
end

return D
