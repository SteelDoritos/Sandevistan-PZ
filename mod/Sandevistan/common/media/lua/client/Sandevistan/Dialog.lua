-- Sandevistan / Dialog: pregunta si/no MOVIBLE con texto con etiquetas (<LINE>). v0.1.30 (28), movible en la (29).
-- ISModalDialog NO interpreta las etiquetas (mostraba "<LINE> <LINE>" escrito en pantalla: confirmaciones de cirugia y recorrido) y ninguno de los dos modales
-- del juego se puede arrastrar. Esta ventana es una ISCollapsableWindow (la misma base que el lector de notas, que si se arrastra) con el texto en un
-- ISRichTextPanel y dos botones. Cerrarla con la X cuenta como "No". Si la UI del juego no tiene esas clases, cae a ISModalRichText / ISModalDialog.
SandevistanDialog = {}
local D = SandevistanDialog

-- La clase se arma la primera vez que se usa (asi este archivo carga aunque la UI todavia no exista, p. ej. en las pruebas fuera del juego).
local function windowClass()
  if D.Window then return D.Window end
  local Base = rawget(_G, "ISCollapsableWindow")
  if not (Base and rawget(_G, "ISRichTextPanel") and rawget(_G, "ISButton")) then return nil end
  local W = Base:derive("SandevistanDialogWindow")
  D.Window = W

  function W:createChildren()
    Base.createChildren(self)
    local th = self:titleBarHeight()
    local btnW, btnH, pad = 110, 26, 10
    self.text = ISRichTextPanel:new(0, th, self.width, self.height - th - btnH - pad * 2)
    self.text:initialise()
    self.text.autosetheight = false
    self.text.clip = true
    self.text.marginLeft, self.text.marginRight, self.text.marginTop, self.text.marginBottom = 14, 14, 10, 6
    self.text.textR, self.text.textG, self.text.textB = 1, 1, 1
    self.text.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.text.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self:addChild(self.text)
    self.text:addScrollBars()
    self.text:setText(" <RGB:1,1,1> " .. (self.body or ""))
    self.text:paginate()
    local by = self.height - btnH - pad
    self.yes = ISButton:new(self.width / 2 - btnW - 8, by, btnW, btnH, getText("IGUI_Sandevistan_Yes"), self, W.onClick)
    self.yes.internal = "YES"
    self.yes:initialise(); self.yes:instantiate()
    self.yes.borderColor = { r = 0.4, g = 1, b = 0.4, a = 0.8 }
    self:addChild(self.yes)
    self.no = ISButton:new(self.width / 2 + 8, by, btnW, btnH, getText("IGUI_Sandevistan_No"), self, W.onClick)
    self.no.internal = "NO"
    self.no:initialise(); self.no:instantiate()
    self.no.borderColor = { r = 1, g = 0.4, b = 0.4, a = 0.8 }
    self:addChild(self.no)
  end

  function W:onClick(button) self:answer(button.internal == "YES") end

  -- Responde una sola vez y cierra.
  function W:answer(yes)
    if self.answered then return end
    self.answered = true
    pcall(function() self:setVisible(false); self:removeFromUIManager() end)
    if self.onAnswer then self.onAnswer(yes) end
  end

  function W:close() self:answer(false) end          -- la X = "No"
  return W
end

-- onAnswer(yes) se llama una sola vez con true/false. Devuelve la ventana (con :setVisible / :removeFromUIManager) o nil.
function D.yesNo(playerNum, text, w, h, onAnswer, title)
  w, h = w or 460, h or 220
  local x = (getCore():getScreenWidth() - w) / 2
  local y = (getCore():getScreenHeight() - h) / 2
  local W = windowClass()
  if W then
    local ok, win = pcall(function()
      local win = W:new(x, y, w, h)
      win.body = text
      win.onAnswer = onAnswer
      win:setTitle(title or "Sandevistan")
      win:setResizable(false)
      win:initialise()
      win.backgroundColor = { r = 0.04, g = 0.04, b = 0.05, a = 0.97 }
      win:addToUIManager()
      win:setVisible(true)
      return win
    end)
    if ok and win then return win end
  end
  -- respaldo: los modales del juego (no se arrastran)
  local Rich, Plain = rawget(_G, "ISModalRichText"), rawget(_G, "ISModalDialog")
  local Class = Rich or Plain
  if not Class then return nil end
  local shown = text
  if not Rich then shown = string.gsub(string.gsub(text, " ?<LINE> ?", " "), "<[^>]*>", "") end
  local modal
  modal = Class:new(x, y, w, h, shown, true, nil, function(_, button)
    pcall(function() modal:setVisible(false); modal:removeFromUIManager() end)      -- que no quede una ventana invisible tomando clics
    onAnswer(button.internal == "YES")
  end, playerNum)
  modal:initialise()
  modal:addToUIManager()
  return modal
end

return D
