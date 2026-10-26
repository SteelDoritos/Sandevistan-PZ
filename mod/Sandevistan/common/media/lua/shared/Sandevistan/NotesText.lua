-- Sandevistan / Textos de las notas de lore.
-- El texto vive en Translate/<idioma>/IG_UI.json (claves IGUI_Sandevistan_NoteTitle_NN / IGUI_Sandevistan_NoteText_NN, NN = 01..20):
-- los archivos .lua se leen sin UTF-8 (las tildes, "°" y "—" salían rotos), los JSON sí. SandevistanNotes[n] arma { title, text } al
-- pedirlo, así respeta el idioma activo. Para editar una nota: notas/<idioma>/*.txt del repo y tools/notas.py.
require "Sandevistan/Config"

SandevistanNotes = setmetatable({}, {
  __index = function(_, n)
    if type(n) ~= "number" or n < 1 or n > SandevistanConfig.Notes.Count or n ~= math.floor(n) then return nil end
    local key = string.format("%02d", n)
    return { title = getText("IGUI_Sandevistan_NoteTitle_" .. key), text = getText("IGUI_Sandevistan_NoteText_" .. key) }
  end,
})
return SandevistanNotes
