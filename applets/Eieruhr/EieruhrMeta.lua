--[[
Eieruhr – Küchentimer mit Countdown und Signalton.
--]]

local tonumber      = tonumber

local string        = require("string")

local io            = require("io")
local os            = require("os")
local oo            = require("loop.simple")
local AppletMeta    = require("jive.AppletMeta")
local Icon          = require("jive.ui.Icon")
local Surface       = require("jive.ui.Surface")
local Timer         = require("jive.ui.Timer")

local appletManager = appletManager
local jiveMain      = jiveMain

module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end


function defaultSettings(self)
	return {}
end


function registerApplet(self)
	local item = self:menuItem('appletEieruhr', 'home', "EIERUHR_MENU", function(applet, ...) applet:menuShow(...) end, 16)
	-- eigenes Sanduhr-Bild; Rahmen/Abstände kommen vom Stil der Standard-Icons
	item.icon = Icon("hm_advancedSettings", Surface:loadImage("applets/Eieruhr/icon.png"))
	jiveMain:addItem(item)
	-- liefert Restsekunden + Bezeichnung, solange ein Timer läuft (für die Wetter-Uhr)
	self:registerService("eieruhrStatus")
	self:registerService("eieruhrShow")
end


-- Fernstart: Datei /tmp/eieruhr mit "<sekunden>" (z. B. per SSH), 0 = stoppen
local TRIGGER = "/tmp/eieruhr"

function configureApplet(self)
	self.remote = Timer(2000, function()
		local fh = io.open(TRIGGER, "r")
		if not fh then return end
		local line = fh:read("*l") or ""
		fh:close()
		os.remove(TRIGGER)
		local sec = string.match(line, "^%s*(%d+)")
		sec = tonumber(sec)
		if sec == 0 then
			appletManager:loadApplet("Eieruhr"):_cancel()
		elseif sec then
			appletManager:loadApplet("Eieruhr"):_start(sec)
		end
	end)
	self.remote:start()
end
