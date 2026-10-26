--[[
Eieruhr – Küchentimer. Zeit mit dem Rad einstellen, Rad drücken startet.
Läuft im Hintergrund weiter, piept am Ende und zeigt „Fertig!“ bis eine
Taste gedrückt wird.
--]]

local math             = require("math")
local os               = require("os")
local string           = require("string")

local oo               = require("loop.simple")

local Applet           = require("jive.Applet")
local Font             = require("jive.ui.Font")
local Framework        = require("jive.ui.Framework")
local Icon             = require("jive.ui.Icon")
local Surface          = require("jive.ui.Surface")
local Timer            = require("jive.ui.Timer")
local Window           = require("jive.ui.Window")
local System           = require("jive.System")

local log              = require("jive.utils.log").logger("applet.Eieruhr")

local appletManager    = appletManager

module(..., Framework.constants)
oo.class(_M, Applet)


local MIN_TIME     = 5             -- Sekunden
local MAX_TIME     = 3 * 3600
local ALARM_LENGTH = 3 * 60        -- so lange piept es höchstens (Sekunden)

local WHITE  = 0xFFFFFFFF
local GREY   = 0x9A9A9AFF
local ORANGE = 0xFFB347FF


local function mmss(sec)
	sec = math.max(0, sec)
	if sec >= 3600 then
		return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
	end
	return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

-- Schrittweite fürs Rad: fein bei kurzen Zeiten, grob bei langen
local function step(sec)
	if sec < 5 * 60 then return 5 end
	if sec < 15 * 60 then return 15 end
	if sec < 60 * 60 then return 60 end
	return 5 * 60
end

-- schnelles Drehen beschleunigt: nach einigen flotten Rastungen zählt jede dreifach
local lastTurn, fastTurns = 0, 0

local function turn(sec, scroll)
	local now = Framework:getTicks()
	if now - lastTurn < 80 then
		fastTurns = fastTurns + 1
	else
		fastTurns = 0
	end
	lastTurn = now
	local dir = scroll > 0 and 1 or -1
	local n = math.abs(scroll) * (fastTurns >= 6 and 3 or 1)
	for _ = 1, n do
		if dir > 0 then
			local s = step(sec)
			sec = math.floor(sec / s) * s + s
		else
			local s = step(sec - 1)
			sec = math.ceil(sec / s) * s - s
		end
	end
	return math.min(MAX_TIME, math.max(MIN_TIME, sec))
end

local function text(dst, font, color, s, x, y)
	local t = Surface:drawText(font, color, s)
	t:blit(dst, math.floor(x - font:width(s) / 2), y)
	t:release()
end


function free(self)
	-- im Speicher bleiben, solange ein Timer läuft oder es piept
	return not (self.endTime or self.alarmWindow)
end


function eieruhrStatus(self)
	if self.endTime then
		return self.endTime - os.time()
	end
	if self.alarmWindow then
		return 0
	end
	return nil
end


-- öffnet Countdown bzw. Einstellung (z. B. aus dem Wettermenü)
function eieruhrShow(self)
	return self:menuShow()
end


function _fonts(self)
	if not self.fonts then
		self.fonts = {
			huge  = Font:load("fonts/FreeSansBold.ttf", 96),
			big   = Font:load("fonts/FreeSansBold.ttf", 64),
			label = Font:load("fonts/FreeSans.ttf", 24),
			hint  = Font:load("fonts/FreeSans.ttf", 15),
		}
	end
	return self.fonts
end


function _image(self, main, label, hint, color)
	local W, H = Framework:getScreenSize()
	local f = self:_fonts()
	local img = Surface:newRGBA(W, H)
	img:filledRectangle(0, 0, W, H, 0x000000FF)
	local font = f.huge:width(main) > W - 10 and f.big or f.huge
	text(img, f.label, GREY, label, W / 2, 24)
	text(img, font, color, main, W / 2, (H - font:height()) / 2 + 6)
	text(img, f.hint, GREY, hint, W / 2, H - 28)
	return img
end

-- Vollbildfenster mit einem Bild, das per update() neu gezeichnet wird
function _screen(self, draw)
	local window = Window("window")
	local icon = Icon("icon", draw())
	window:addWidget(icon)
	window:setShowFrameworkWidgets(false)
	window.update = function()
		-- alte Surface sofort freigeben, der Lua-GC sieht den C-Speicher nicht
		local old = icon:getImage()
		icon:setValue(draw())
		if old then old:release() end
	end
	return window
end


----------------------------------------------------------------------
-- Einstellen

function menuShow(self, menuItem)
	if self.endTime then
		return self:_showCountdown()
	end
	return self:_showSetter()
end

function _showSetter(self)
	local seconds = self:getSettings().last or 5 * 60

	local window = self:_screen(function()
		return self:_image(mmss(seconds), "Eieruhr", "Rad drehen = Zeit  ·  Rad drücken = Start", WHITE)
	end)
	window:addListener(EVENT_SCROLL, function(event)
		seconds = turn(seconds, event:getScroll())
		window.update()
		return EVENT_CONSUME
	end)
	window:addActionListener("go", self, function()
		self:getSettings().last = seconds
		self:storeSettings()
		window:hide(Window.transitionNone)
		self:_start(seconds)
		return EVENT_CONSUME
	end)
	window:addActionListener("back", self, function()
		window:hide()
		return EVENT_CONSUME
	end)
	self:tieAndShowWindow(window)
	return window
end


----------------------------------------------------------------------
-- Timer

function _start(self, seconds)
	self:_stopAlarm()
	self.endTime = os.time() + seconds
	if not self.ticker then
		self.ticker = Timer(1000, function() self:_tick() end)
	end
	self.ticker:start()
	self:_showCountdown()
end

function _cancel(self)
	self:_stopAlarm()
	self.endTime = nil
	if self.ticker then self.ticker:stop() end
	if self.countdownWindow then self.countdownWindow:hide() end
end

function _tick(self)
	if not self.endTime then return end
	if self.endTime - os.time() <= 0 then
		self.endTime = nil
		self.ticker:stop()
		-- erst Alarm, dann Countdown schließen: sonst ist kurz kein Fenster
		-- mehr da, free() sagt ja und das Applet wird mitten im Ablauf entladen
		self:_alarm()
		if self.countdownWindow then self.countdownWindow:hide() end
	elseif self.countdownWindow then
		self.countdownWindow.update()
	end
end

function _showCountdown(self)
	if not self.endTime then return end
	if self.countdownWindow then
		self.countdownWindow:hide()
	end
	local window = self:_screen(function()
		return self:_image(mmss(self.endTime and self.endTime - os.time() or 0), "Eieruhr läuft",
			"Rad drehen = ändern  ·  drücken = Stopp", WHITE)
	end)
	-- Rad verstellt die laufende Zeit
	window:addListener(EVENT_SCROLL, function(event)
		if self.endTime then
			self.endTime = os.time() + turn(self.endTime - os.time(), event:getScroll())
			window.update()
		end
		return EVENT_CONSUME
	end)
	window:addActionListener("go", self, function()
		self:_cancel()
		return EVENT_CONSUME
	end)
	window:addActionListener("back", self, function()
		window:hide()
		return EVENT_CONSUME
	end)
	window:addListener(EVENT_WINDOW_POP, function()
		if self.countdownWindow == window then
			self.countdownWindow = nil
		end
	end)
	self.countdownWindow = window
	self:tieAndShowWindow(window)
	return window
end


----------------------------------------------------------------------
-- Alarm

function _alarm(self)
	if not self.soundLoaded then
		Framework:loadSound("EIERUHR", System:findFile("applets/Eieruhr/beep.wav"), 1)
		self.soundLoaded = true
	end
	-- unabhängig von den Klick-Ton-Einstellungen immer hörbar
	Framework:enableSound("EIERUHR", true)
	appletManager:callService("setBrightness", "on")

	local window = self:_screen(function()
		return self:_image("Fertig!", "Eieruhr", "Taste drücken zum Beenden", ORANGE)
	end)
	window:setAlwaysOnTop(true)
	window:setAllowScreensaver(false)
	window:addListener(EVENT_KEY_PRESS | EVENT_SCROLL | EVENT_MOUSE_PRESS, function()
		self:_stopAlarm()
		return EVENT_CONSUME
	end)
	self.alarmWindow = window

	local started = os.time()
	self.beeper = Timer(1500, function()
		if os.time() - started > ALARM_LENGTH then
			self:_stopAlarm()
		else
			Framework:playSound("EIERUHR")
		end
	end)
	Framework:playSound("EIERUHR")
	self.beeper:start()
	self:tieAndShowWindow(window)
end

function _stopAlarm(self)
	if self.beeper then
		self.beeper:stop()
		self.beeper = nil
	end
	if self.alarmWindow then
		local w = self.alarmWindow
		self.alarmWindow = nil
		w:hide()
	end
end
