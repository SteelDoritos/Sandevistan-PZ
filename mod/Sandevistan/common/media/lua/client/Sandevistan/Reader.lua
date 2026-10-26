-- Sandevistan / Reader: ventana de lectura de notas, informes y expedientes.
-- v0.1.30 (23): antes se usaba ISModalRichText (modal: no se movia, no cambiaba de tamano y bloqueaba la pantalla). Ahora es una
-- ISCollapsableWindow: se arrastra, se cambia de tamano, se pliega, se cierra y puede haber varias abiertas para comparar notas. El fondo y la
-- tinta cambian segun quien la escribio (papel del investigador, informe militar, papelito del guardia, cuaderno del estudiante).
require "ISUI/ISCollapsableWindow"
require "ISUI/ISRichTextPanel"
require "Sandevistan/Core"

SandevistanReader = ISCollapsableWindow:derive("SandevistanReader")
local R = SandevistanReader

-- fondo (rgba de la ventana), tinta (rgb del texto en <RGB:...>), borde
R.STYLES = {
  dark     = { bg = { 0.05, 0.05, 0.06, 0.96 }, ink = { 0.92, 0.92, 0.92 }, border = { 0.4, 0.4, 0.45, 1 } },
  paper    = { bg = { 0.90, 0.87, 0.78, 0.98 }, ink = { 0.13, 0.11, 0.09 }, border = { 0.45, 0.40, 0.30, 1 } },
  military = { bg = { 0.17, 0.21, 0.15, 0.98 }, ink = { 0.86, 0.90, 0.80 }, border = { 0.42, 0.50, 0.34, 1 } },
  sticky   = { bg = { 0.93, 0.85, 0.50, 0.98 }, ink = { 0.22, 0.17, 0.10 }, border = { 0.60, 0.52, 0.25, 1 } },
  student  = { bg = { 0.86, 0.84, 0.93, 0.98 }, ink = { 0.10, 0.12, 0.30 }, border = { 0.42, 0.40, 0.60, 1 } },
}

-- Etiquetas <RGB> de la tinta de un estilo (y una version atenuada hacia el fondo, para lo que "falta"). Hay que repetirlas despues de cada <H2> y <TEXT>.
function R.inkTag(style)
  local st = R.STYLES[style] or R.STYLES.dark
  return string.format("<RGB:%.2f,%.2f,%.2f>", st.ink[1], st.ink[2], st.ink[3])
end
function R.dimTag(style)
  local st = R.STYLES[style] or R.STYLES.dark
  local m = 0.55                                     -- cuanto se acerca al fondo
  return string.format("<RGB:%.2f,%.2f,%.2f>", st.ink[1] + (st.bg[1] - st.ink[1]) * m, st.ink[2] + (st.bg[2] - st.ink[2]) * m, st.ink[3] + (st.bg[3] - st.ink[3]) * m)
end

R.open = {}      -- titulo -> ventana abierta (una sola por texto; una segunda lectura la trae al frente)

function R:createChildren()
  ISCollapsableWindow.createChildren(self)
  local th = self:titleBarHeight()
  local rh = self:resizeWidgetHeight()
  local st = R.STYLES[self.styleName] or R.STYLES.dark
  local pagerH = self.pages and 34 or 0          -- fila de botones Anterior / Siguiente (solo en las guias de varias paginas)
  self.text = ISRichTextPanel:new(0, th, self.width, self.height - th - rh - pagerH)
  self.text:initialise()
  self.text.autosetheight = false
  self.text.clip = true
  self.text.marginLeft, self.text.marginRight, self.text.marginTop, self.text.marginBottom = 14, 14, 10, 10
  self.text.textR, self.text.textG, self.text.textB = st.ink[1], st.ink[2], st.ink[3]      -- color por defecto del panel (las etiquetas <RGB> de abajo son el refuerzo)
  self.text.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
  self.text.borderColor = { r = 0, g = 0, b = 0, a = 0 }
  self:addChild(self.text)
  self.text:addScrollBars()
  self.text:setText(self.body or "")
  self.text:paginate()
  self.lastW, self.lastH = self.width, self.height
  if self.pages then self:createPager() end
end

-- Paginas (v0.1.30 (30)): self.pages = { { title =, text = }, ... }; botones Anterior / Siguiente y "Pagina n / N" abajo.
function R:pageBody(n)
  local st = R.STYLES[self.styleName] or R.STYLES.dark
  local ink = string.format("<RGB:%.2f,%.2f,%.2f>", st.ink[1], st.ink[2], st.ink[3])
  local pg = self.pages[n]
  return ink .. " <H2> " .. ink .. " " .. pg.title .. " <LINE> <LINE> <TEXT> " .. ink .. " " .. pg.text
end

function R:createPager()
  local rh = self:resizeWidgetHeight()
  local y = self.height - rh - 30
  self.btnPrev = ISButton:new(12, y, 110, 24, getText("IGUI_Sandevistan_Guide_Prev"), self, R.onPrev)
  self.btnPrev:initialise(); self.btnPrev:instantiate()
  self.btnNext = ISButton:new(self.width - 122, y, 110, 24, getText("IGUI_Sandevistan_Guide_Next"), self, R.onNext)
  self.btnNext:initialise(); self.btnNext:instantiate()
  self:addChild(self.btnPrev); self:addChild(self.btnNext)
  self.page = self.page or 1
end

function R:setPage(n)
  n = math.max(1, math.min(#self.pages, n))
  self.page = n
  self.text:setText(self:pageBody(n))
  self.text:paginate()
  pcall(function() self.text:setYScroll(0) end)
end
function R:onPrev() self:setPage((self.page or 1) - 1) end
function R:onNext() self:setPage((self.page or 1) + 1) end

function R:render()
  ISCollapsableWindow.render(self)
  if self.pages and self.btnPrev then
    -- botones pegados al borde inferior aunque se cambie el tamano; indicador de pagina en el medio
    local y = self.height - self:resizeWidgetHeight() - 30
    self.btnPrev:setY(y); self.btnNext:setY(y); self.btnNext:setX(self.width - 122)
    local st = R.STYLES[self.styleName] or R.STYLES.dark
    self:drawTextCentre(getText("IGUI_Sandevistan_Guide_Page", self.page or 1, #self.pages), self.width / 2, y + 4, st.ink[1], st.ink[2], st.ink[3], 1, UIFont.Small)
  end
end

-- Al cambiar el tamano el texto se vuelve a acomodar (un chequeo barato por cuadro).
function R:prerender()
  ISCollapsableWindow.prerender(self)
  if self.text and (self.width ~= self.lastW or self.height ~= self.lastH) then
    self.lastW, self.lastH = self.width, self.height
    local th = self:titleBarHeight()
    self.text:setWidth(self.width)
    self.text:setHeight(math.max(10, self.height - th - self:resizeWidgetHeight() - (self.pages and 34 or 0)))
    self.text:paginate()
  end
end

function R:close()
  if R.open[self.titleKey] == self then R.open[self.titleKey] = nil end
  self:setVisible(false)
  self:removeFromUIManager()
end

-- Abre la ventana. Si el mismo texto ya estaba abierto solo lo trae al frente. style: clave de R.STYLES.
function R.show(title, body, w, h, style)
  local prev = R.open[title]
  if prev then
    pcall(function() prev:setVisible(true); prev:bringToTop() end)
    return prev
  end
  w, h = w or 520, h or 460
  local core = getCore()
  local n = 0
  for _ in pairs(R.open) do n = n + 1 end
  local x = (core:getScreenWidth() - w) / 2 + (n % 6) * 28
  local y = (core:getScreenHeight() - h) / 2 + (n % 6) * 28
  local win = R:new(x, y, w, h)
  local st = R.STYLES[style] or R.STYLES.dark
  win.styleName = R.STYLES[style] and style or "dark"
  win.titleKey = title
  -- v0.1.30 (28): el color de la tinta hay que repetirlo despues de <H2> y de <TEXT> (cada uno lo vuelve a blanco): con solo uno al principio el
  -- texto salia casi blanco sobre el papel claro y no se leia
  local ink = string.format("<RGB:%.2f,%.2f,%.2f>", st.ink[1], st.ink[2], st.ink[3])
  win.body = ink .. " <H2> " .. ink .. " " .. title .. " <LINE> <LINE> <TEXT> " .. ink .. " " .. (body or "")
  win:setTitle(title)
  win:setResizable(true)
  win:initialise()
  win.backgroundColor = { r = st.bg[1], g = st.bg[2], b = st.bg[3], a = st.bg[4] }
  win.borderColor = { r = st.border[1], g = st.border[2], b = st.border[3], a = st.border[4] }
  win:addToUIManager()
  win:setVisible(true)
  R.open[title] = win
  return win
end

-- Ventana de varias paginas (la guia de campo). pages = { { title =, text = }, ... }.
function R.showPages(title, pages, w, h, style, startPage)
  local prev = R.open[title]
  if prev then
    pcall(function() prev:setVisible(true); prev:bringToTop() end)
    return prev
  end
  w, h = w or 600, h or 500
  local core = getCore()
  local win = R:new((core:getScreenWidth() - w) / 2, (core:getScreenHeight() - h) / 2, w, h)
  local st = R.STYLES[style] or R.STYLES.dark
  win.styleName = R.STYLES[style] and style or "dark"
  win.titleKey = title
  win.pages = pages
  win.page = startPage or 1
  win.body = win:pageBody(win.page)
  win:setTitle(title)
  win:setResizable(true)
  win:initialise()
  win.backgroundColor = { r = st.bg[1], g = st.bg[2], b = st.bg[3], a = st.bg[4] }
  win.borderColor = { r = st.border[1], g = st.border[2], b = st.border[3], a = st.border[4] }
  win:addToUIManager()
  win:setVisible(true)
  R.open[title] = win
  return win
end

return R
