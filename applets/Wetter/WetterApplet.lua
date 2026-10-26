--[[
Wetter – zeigt Außentemperatur und Vorhersage von Open-Meteo für einen
einstellbaren Ort (Menü „Ort ändern“, Suche über die Open-Meteo-Geocoding-API).
--]]

local tonumber, tostring, type, pcall, ipairs = tonumber, tostring, type, pcall, ipairs

local math             = require("math")
local os               = require("os")
local string           = require("string")
local table            = require("table")
local json             = require("json")

local oo               = require("loop.simple")

local Applet           = require("jive.Applet")
local Font             = require("jive.ui.Font")
local Group            = require("jive.ui.Group")
local Keyboard         = require("jive.ui.Keyboard")
local Textinput        = require("jive.ui.Textinput")
local Framework        = require("jive.ui.Framework")
local Icon             = require("jive.ui.Icon")
local Player           = require("jive.slim.Player")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Surface          = require("jive.ui.Surface")
local Window           = require("jive.ui.Window")
local SocketHttp       = require("jive.net.SocketHttp")
local RequestHttp      = require("jive.net.RequestHttp")
local URL              = require("socket.url")

local log              = require("jive.utils.log").logger("applet.Wetter")

local appletManager    = appletManager
local jnt              = jnt

module(..., Framework.constants)
oo.class(_M, Applet)


local HOST = "api.open-meteo.com"
local GEO_HOST = "geocoding-api.open-meteo.com"
local QUERY = "&current=is_day,temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"
	.. "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum"
	.. "&timezone=auto&forecast_days=7"

-- Ort ohne Einstellung (so war es vor der Ortswahl fest eingebaut)
local DEFAULT_PLACE = { name = "Glauchau", lat = 50.8197, lon = 12.5446 }

local REFRESH = 15 * 60       -- Sekunden

local WHITE  = 0xFFFFFFFF
local GREY   = 0x9A9A9AFF
local BLUE   = 0x6CB4FFFF
local ORANGE = 0xFFB347FF

local WOCHENTAG = { "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" }
local MONAT = { "Jan", "Feb", "März", "Apr", "Mai", "Juni", "Juli", "Aug", "Sep", "Okt", "Nov", "Dez" }

local WMO = {
	[0] = "Klar", [1] = "Überwiegend klar", [2] = "Teils bewölkt", [3] = "Bedeckt",
	[45] = "Nebel", [48] = "Reifnebel",
	[51] = "Leichter Niesel", [53] = "Niesel", [55] = "Starker Niesel",
	[56] = "Gefrierender Niesel", [57] = "Gefrierender Niesel",
	[61] = "Leichter Regen", [63] = "Regen", [65] = "Starker Regen",
	[66] = "Gefrierender Regen", [67] = "Gefrierender Regen",
	[71] = "Leichter Schnee", [73] = "Schnee", [75] = "Starker Schnee", [77] = "Schneegriesel",
	[80] = "Regenschauer", [81] = "Kräftige Schauer", [82] = "Heftige Schauer",
	[85] = "Schneeschauer", [86] = "Starke Schneeschauer",
	[95] = "Gewitter", [96] = "Gewitter, Hagel", [99] = "Gewitter, Hagel",
}

-- von Menü und Bildschirmschoner gemeinsam genutzt
local cache = { data = nil, fetched = 0, loading = false, listeners = {} }
local place = DEFAULT_PLACE


-- WMO-Code -> Symbolname (applets/Wetter/icons/<name>_<größe>.png)
local function iconName(code, isDay)
	code = tonumber(code) or -1
	local day = isDay ~= 0
	if code <= 1 then return day and "clear_day" or "clear_night" end
	if code == 2 then return day and "partly_day" or "partly_night" end
	if code == 3 then return "cloudy" end
	if code == 45 or code == 48 then return "fog" end
	if code >= 51 and code <= 55 then return "drizzle" end
	if code == 56 or code == 57 or code == 66 or code == 67 then return "sleet" end
	if code >= 61 and code <= 65 then return "rain" end
	if code >= 80 and code <= 82 then return day and "showers_day" or "rain" end
	if (code >= 71 and code <= 77) or code == 85 or code == 86 then return "snow" end
	if code >= 95 then return "thunder" end
	return "cloudy"
end

local icons = {}
local function icon(code, isDay, size)
	local key = iconName(code, isDay) .. "_" .. size
	if icons[key] == nil then
		icons[key] = Surface:loadImage("applets/Wetter/icons/" .. key .. ".png") or false
	end
	return icons[key] or nil
end

local function wmo(code)
	return WMO[tonumber(code) or -1] or "?"
end

local function grad(v, decimals)
	if type(v) ~= "number" then return "–" end
	if decimals then
		return (string.gsub(string.format("%.1f", v), "%.", ",")) .. "°"
	end
	return string.format("%d", math.floor(v + 0.5)) .. "°"
end

-- "2026-10-24" -> os.time am Mittag
local function dayTime(s)
	local y, m, d = string.match(s or "", "(%d+)-(%d+)-(%d+)")
	if not y then return nil end
	return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

local function dayName(s, i)
	if i == 1 then return "Heute" end
	if i == 2 then return "Morgen" end
	local t = dayTime(s)
	return t and WOCHENTAG[tonumber(os.date("%w", t)) + 1] or "?"
end


-- Daten holen; callback(data) für alle Wartenden
local fetch
fetch = function(force)
	if cache.loading then return end
	if not force and cache.data and os.time() - cache.fetched < REFRESH then return end

	cache.loading = true
	local p = place
	local path = string.format("/v1/forecast?latitude=%.4f&longitude=%.4f", p.lat, p.lon) .. QUERY
	local http = SocketHttp(jnt, HOST, 80, "Wetter")
	local req = RequestHttp(function(chunk, err)
		if err then
			log:warn("Wetter: ", err)
			cache.loading = false
		elseif chunk then
			local ok, obj = pcall(json.decode, chunk)
			-- Antwort für einen inzwischen gewechselten Ort verwerfen
			if p ~= place then
				cache.loading = false
				fetch(true)
			elseif ok and type(obj) == "table" and obj.current then
				cache.data = obj
				cache.fetched = os.time()
				for _, f in ipairs(cache.listeners) do pcall(f, obj) end
			else
				log:warn("Wetter: ungültige Antwort")
			end
			cache.loading = false
		end
	end, 'GET', "http://" .. HOST .. path)
	http:fetch(req)
end

local function listen(f)
	cache.listeners[#cache.listeners + 1] = f
end

local function unlisten(f)
	for i, g in ipairs(cache.listeners) do
		if g == f then
			table.remove(cache.listeners, i)
			return
		end
	end
end


-- Ort aus den Einstellungen übernehmen
function _loadPlace(self)
	local sp = self:getSettings().place
	if type(sp) == "table" and type(sp.lat) == "number" and type(sp.lon) == "number" then
		if sp.lat ~= place.lat or sp.lon ~= place.lon then
			place = sp
			cache.data = nil
		end
	end
end

function _setPlace(self, p)
	local settings = self:getSettings()
	settings.place = p
	self:storeSettings()
	place = p
	cache.data = nil
	cache.fetched = 0
	for _, f in ipairs(cache.listeners) do pcall(f, nil) end
	fetch(true)
end


----------------------------------------------------------------------
-- Ortswahl

-- "Glauchau (Sachsen, Deutschland)"
local function placeLabel(r)
	local extra = {}
	if type(r.admin1) == "string" and r.admin1 ~= r.name then extra[#extra + 1] = r.admin1 end
	if type(r.country) == "string" then extra[#extra + 1] = r.country end
	if #extra == 0 then return r.name end
	return r.name .. " (" .. table.concat(extra, ", ") .. ")"
end

function placeSearch(self)
	local window = Window("text_list", "Ort suchen")
	local input = Textinput("textinput", "", function(_, value)
		if #value < 2 then
			return false
		end
		self:_placeResults(value, window)
		return true
	end)
	local keyboard  = Keyboard("keyboard", "qwerty", input)
	local backspace = Keyboard.backspace()
	local group     = Group('keyboard_textinput', { textinput = input, backspace = backspace })
	window:addWidget(group)
	window:addWidget(keyboard)
	window:focusWidget(group)
	self:tieAndShowWindow(window)
	return window
end

function _placeResults(self, query, inputWindow)
	local window = Window("text_list", query)
	local menu = SimpleMenu("menu")
	menu:setItems({ { text = "Suche …", style = 'item_info' } })
	window:addWidget(menu)

	local http = SocketHttp(jnt, GEO_HOST, 80, "WetterOrt")
	local req = RequestHttp(function(chunk, err)
		if err then
			log:warn("Ortssuche: ", err)
			menu:setItems({ { text = "Keine Verbindung", style = 'item_info' } })
		elseif chunk then
			local ok, obj = pcall(json.decode, chunk)
			local items = {}
			if ok and type(obj) == "table" and type(obj.results) == "table" then
				for _, r in ipairs(obj.results) do
					if type(r.name) == "string" and type(r.latitude) == "number" and type(r.longitude) == "number" then
						items[#items + 1] = {
							text = placeLabel(r),
							callback = function()
								self:_setPlace({ name = r.name, lat = r.latitude, lon = r.longitude })
								window:playSound("WINDOWSHOW")
								-- zurück ins Wettermenü: Tastatur und Ergebnisliste schließen
								inputWindow:hideToTop(Window.transitionPushLeft)
								return EVENT_CONSUME
							end,
						}
					end
				end
			end
			if #items == 0 then
				items[1] = { text = "Nichts gefunden", style = 'item_info' }
			end
			menu:setItems(items)
		end
	end, 'GET', "http://" .. GEO_HOST .. "/v1/search?count=10&language=de&format=json&name=" .. URL.escape(query))
	http:fetch(req)

	self:tieAndShowWindow(window)
	return window
end


----------------------------------------------------------------------
-- Menü

local function timeLeft(sec)
	if sec >= 3600 then
		return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
	end
	return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

function _menuItems(self, menu, d)
	local items = {}
	local left = appletManager:callService("eieruhrStatus")
	if left then
		items[1] = {
			text = "Eieruhr  " .. (left > 0 and timeLeft(left) or "Fertig!"),
			callback = function()
				appletManager:callService("eieruhrShow")
				return EVENT_CONSUME
			end,
		}
	end
	if not d then
		items[1] = { text = "Wetter wird geladen …", style = 'item_info' }
	else
		local c = d.current
		items[#items + 1] = { text = "Jetzt " .. grad(c.temperature_2m, true) .. "C  " .. wmo(c.weather_code), style = 'item_info' }
		items[#items + 1] = { text = "Gefühlt " .. grad(c.apparent_temperature, true)
			.. "  Wind " .. string.format("%d", math.floor((c.wind_speed_10m or 0) + 0.5)) .. " km/h"
			.. "  Feuchte " .. tostring(c.relative_humidity_2m or "–") .. " %", style = 'item_info' }

		local dd = d.daily
		for i = 1, #(dd.time or {}) do
			local rain = dd.precipitation_probability_max[i]
			items[#items + 1] = {
				text = dayName(dd.time[i], i) .. ":  " .. grad(dd.temperature_2m_min[i]) .. " / " .. grad(dd.temperature_2m_max[i])
					.. "  " .. wmo(dd.weather_code[i])
					.. (rain and ("  " .. rain .. " %") or ""),
				style = 'item_info',
			}
		end
		items[#items + 1] = { text = "Stand " .. os.date("%H:%M", cache.fetched) .. " · Open-Meteo", style = 'item_info' }
	end
	items[#items + 1] = {
		text = "Aktualisieren",
		callback = function()
			fetch(true)
			return EVENT_CONSUME
		end,
	}
	items[#items + 1] = {
		text = "Ort ändern (" .. place.name .. ")",
		callback = function()
			self:placeSearch()
			return EVENT_CONSUME
		end,
	}
	menu:setItems(items)
end

function menuShow(self, menuItem)
	self:_loadPlace()
	local window = Window("text_list", "Wetter " .. place.name)
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	self:_menuItems(menu, cache.data)
	local listener = function(d)
		window:setTitle("Wetter " .. place.name)
		self:_menuItems(menu, d)
	end
	listen(listener)

	window:addListener(EVENT_WINDOW_POP, function()
		unlisten(listener)
	end)
	-- Eieruhr-Zeile mitzählen lassen
	local ticking = false
	window:addTimer(1000, function()
		local running = appletManager:callService("eieruhrStatus") ~= nil
		if running or ticking then
			self:_menuItems(menu, cache.data)
		end
		ticking = running
	end)

	fetch(false)
	self:tieAndShowWindow(window)
	return window
end


----------------------------------------------------------------------
-- Bildschirmschoner

local function fit(font, s, maxw)
	while font:width(s) > maxw and #s > 1 do
		s = string.gsub(s, "[%z\1-\127\194-\244][\128-\191]*$", "")
	end
	return s
end

local function text(dst, font, color, s, x, y, align)
	local w = font:width(s)
	if align == "right" then
		x = x - w
	elseif align == "center" then
		x = x - w / 2
	end
	local t = Surface:drawText(font, color, s)
	t:blit(dst, math.floor(x), y)
	t:release()
end

-- kleine orange Sanduhr vor der Eieruhr-Restzeit
local hourglass = Surface:loadImage("applets/Wetter/icons/hourglass_24.png")

-- Sender und Titel, solange der Player spielt; sonst nil
local function nowPlaying()
	local p = Player:getLocalPlayer()
	local st = p and p:getPlayerStatus()
	if not st or st.mode ~= "play" then
		return nil
	end
	local meta = type(st.remoteMeta) == "table" and st.remoteMeta or {}
	local item = type(st.item_loop) == "table" and st.item_loop[1] or {}
	local station = type(meta.remote_title) == "string" and meta.remote_title
		or type(item.text) == "string" and (string.match(item.text, "^[^\n]*"))
		or "Radio"
	-- "Absolut Germany (München, Deutschland / Pop)" -> "Absolut Germany"
	station = string.gsub(station, "%s*%b()%s*$", "")
	local song = ""
	if type(meta.title) == "string" and meta.title ~= station then
		song = meta.title
		if type(meta.artist) == "string" and meta.artist ~= "" then
			song = meta.artist .. " – " .. song
		end
	end
	return station, song
end

local function playKey()
	local station, song = nowPlaying()
	return station and (station .. song)
end


function _render(self)
	local W, H = self.sw, self.sh
	local f = self.fonts
	local img = Surface:newRGBA(W, H)
	img:filledRectangle(0, 0, W, H, 0x000000FF)

	local now = os.date("*t")
	local clock = os.date("%H:%M")
	text(img, f.time, WHITE, clock, 10, 6)
	text(img, f.mid, GREY, WOCHENTAG[now.wday] .. ", " .. now.day .. ". " .. MONAT[now.month], 12, 66)

	-- läuft die Eieruhr, steht hier groß die Restzeit statt der Details
	local left = appletManager:callService("eieruhrStatus")
	if left then
		local t = left > 0 and timeLeft(left) or "Fertig!"
		local w = 24 + 8 + f.timer:width(t)
		local x = math.floor((W - w) / 2)
		if hourglass then
			hourglass:blit(img, x, 91)
		end
		text(img, f.timer, ORANGE, t, x + 32, 86)
	end

	local d = cache.data
	if not d then
		text(img, f.mid, GREY, "Wetter wird geladen …", W / 2, 150, "center")
		return img
	end

	local c = d.current
	local temp = grad(c.temperature_2m)
	text(img, f.big, ORANGE, temp, W - 10, 2, "right")
	local sym = icon(c.weather_code, c.is_day, 64)
	if sym then
		local x = math.max(14 + f.time:width(clock), W - 14 - f.big:width(temp) - 64)
		sym:blit(img, x, 0)
	end
	text(img, f.mid, WHITE, fit(f.mid, wmo(c.weather_code), 150), W - 12, 66, "right")
	if not left then
		text(img, f.small, GREY, "Gefühlt " .. grad(c.apparent_temperature)
			.. "  ·  Wind " .. string.format("%d", math.floor((c.wind_speed_10m or 0) + 0.5)) .. " km/h"
			.. "  ·  " .. tostring(c.relative_humidity_2m or "–") .. " %", W / 2, 96, "center")
	end

	img:filledRectangle(10, 120, W - 10, 120, 0x444444FF)

	-- spielt Musik, weicht der dritte Vorhersagetag der Senderzeile
	local station, song = nowPlaying()
	self.playing = station and (station .. song)
	local dd = d.daily
	for i = 1, station and 2 or 3 do
		if dd.time and dd.time[i] then
			local y = 128 + (i - 1) * 36
			-- "Morgen" ist zu breit, ab Tag 2 Wochentag
			text(img, f.rowBold, WHITE, i == 1 and "Heute" or dayName(dd.time[i], 3), 10, y)
			local small = icon(dd.weather_code[i], 1, 30)
			if small then
				small:blit(img, 72, y - 3)
			end
			text(img, f.row, GREY, fit(f.row, (string.gsub(wmo(dd.weather_code[i]), "^Leichter ", "")), 90), 108, y + 3)
			local rain = dd.precipitation_probability_max[i]
			if rain then
				text(img, f.row, BLUE, rain .. "%", 234, y + 3, "right")
			end
			text(img, f.rowBold, ORANGE, grad(dd.temperature_2m_max[i]), W - 46, y, "right")
			text(img, f.row, GREY, grad(dd.temperature_2m_min[i]), W - 10, y + 3, "right")
		end
	end

	if station then
		img:filledRectangle(10, 198, W - 10, 198, 0x444444FF)
		text(img, f.rowBold, ORANGE, fit(f.rowBold, station, W - 20), 10, 202)
		if song ~= "" then
			text(img, f.small, GREY, fit(f.small, song, W - 20), 10, 221)
		end
	end

	return img
end

function _refreshScreen(self)
	if self.icon then
		-- alte Surface sofort freigeben, der Lua-GC sieht den C-Speicher nicht
		local old = self.icon:getImage()
		self.icon:setValue(self:_render())
		if old then old:release() end
	end
end

function openScreensaver(self, menuItem)
	self:_loadPlace()
	self.sw, self.sh = Framework:getScreenSize()
	self.fonts = {
		time    = Font:load("fonts/FreeSansBold.ttf", 50),
		big     = Font:load("fonts/FreeSansBold.ttf", 56),
		mid     = Font:load("fonts/FreeSans.ttf", 20),
		small   = Font:load("fonts/FreeSans.ttf", 15),
		row     = Font:load("fonts/FreeSans.ttf", 16),
		rowBold = Font:load("fonts/FreeSansBold.ttf", 20),
		timer   = Font:load("fonts/FreeSansBold.ttf", 28),
	}

	local window = Window("window")
	self.icon = Icon("icon", self:_render())
	window:addWidget(self.icon)
	window:setShowFrameworkWidgets(false)

	local lastMin = os.date("%H:%M")
	local ticking = false
	window:addTimer(1000, function()
		local m = os.date("%H:%M")
		-- auch einmal nach dem Ende der Eieruhr, damit die Restzeit verschwindet
		local running = appletManager:callService("eieruhrStatus") ~= nil
		local wasTicking = ticking
		ticking = running
		if m ~= lastMin then
			lastMin = m
			fetch(false)
			self:_refreshScreen()
		elseif running or wasTicking then
			self:_refreshScreen()
		elseif self.playing ~= playKey() then
			self:_refreshScreen()
		end
	end)

	local listener = function() self:_refreshScreen() end
	listen(listener)
	window:addListener(EVENT_WINDOW_POP, function()
		unlisten(listener)
		self.icon = nil
	end)

	fetch(false)

	local manager = appletManager:getAppletInstance("ScreenSavers")
	manager:screensaverWindow(window, _, _, _, 'Wetter')
	window:show(Window.transitionFadeIn)
	self.window = window
end
