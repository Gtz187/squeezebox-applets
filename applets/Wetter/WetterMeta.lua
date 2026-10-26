--[[
Wetter – Meta. Menüpunkt im Hauptmenü + Bildschirmschoner.
Daten: Open-Meteo (kostenlos, ohne API-Key).
--]]

local pcall         = pcall

local oo            = require("loop.simple")
local AppletMeta    = require("jive.AppletMeta")

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
	jiveMain:addItem(self:menuItem('appletWetter', 'home', "WETTER_MENU", function(applet, ...) applet:menuShow(...) end, 15))
end


function configureApplet(self)
	appletManager:callService("addScreenSaver",
		self:string("WETTER_SCREENSAVER"),
		"Wetter",
		"openScreensaver", _, _, 30
	)

	-- beim ersten Start (z. B. frisch über den Applet-Installer) einmalig
	-- als Bildschirmschoner für Stopp und Wiedergabe eintragen
	local settings = self:getSettings()
	if not settings.screensaverSet then
		local ok, err = pcall(function()
			local ss = appletManager:loadApplet("ScreenSavers")
			ss:setScreenSaver("whenStopped", "Wetter:openScreensaver")
			ss:setScreenSaver("whenPlaying", "Wetter:openScreensaver")
			ss:storeSettings()
		end)
		if ok then
			settings.screensaverSet = true
			self:storeSettings()
		end
	end
end
