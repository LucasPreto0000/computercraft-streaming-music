local api_base_url = "https://ipod-2to6magyna-uc.a.run.app/"
local version = "2.2"

local width, height = term.getSize()
local tab = 1

local waiting_for_input = false
local last_search = nil
local last_search_url = nil
local search_results = nil
local search_error = false
local in_search_result = false
local clicked_result = nil

local playing = false
local queue = {}
local now_playing = nil
local looping = 0
-- CC:Tweaked accepts values from 0.0 to 3.0. Start at the real maximum.
local volume = 3.0

local playing_id = nil
local last_download_url = nil
local playing_status = 0
local is_loading = false
local is_error = false;

local player_handle = nil
local start = nil
local pcm = nil
local size = nil
local decoder = require "cc.audio.dfpwm".make_decoder()
local needs_next_chunk = 0
local buffer

-- Do not collect peripheral.find's multiple return values here. Enumerating the
-- peripheral names has no practical vararg limit and also lets us refresh the
-- list when wired speakers are attached or removed while the program is open.
local speakers = {}

local function refreshSpeakers()
	local found = {}
	for _, name in ipairs(peripheral.getNames()) do
		if peripheral.hasType(name, "speaker") then
			found[#found + 1] = {
				name = name,
				device = peripheral.wrap(name)
			}
		end
	end
	speakers = found
	return #speakers
end

local function stopAllSpeakers()
	for _, speaker in ipairs(speakers) do
		pcall(speaker.device.stop)
	end
	os.queueEvent("playback_stopped")
end

local function extractYouTubeVideoId(value)
	if not value then return nil end
	value = value:gsub("&amp;", "&")
	local id = value:match("[?&]v=([%w_-]+)")
		or value:match("youtu%.be/([%w_-]+)")
		or value:match("youtube%.com/shorts/([%w_-]+)")
		or value:match("youtube%.com/embed/([%w_-]+)")
	if id and #id == 11 then return id end
	return nil
end

refreshSpeakers()
if #speakers == 0 then
	error("No speakers attached. You need to connect a speaker to this computer. If this is an Advanced Noisy Pocket Computer, then this is a bug, and you should try restarting your Minecraft game.", 0)
end

function redrawScreen()
	if waiting_for_input then
		return
	end

	term.setCursorBlink(false)  -- Make sure cursor is off when redrawing
	-- Clear the screen
	term.setBackgroundColor(colors.black)
	term.clear()

	--Draw the three top tabs
	term.setCursorPos(1,1)
	term.setBackgroundColor(colors.gray)
	term.clearLine()
	
	tabs = {" Now Playing ", " Search "}
	
	for i=1,#tabs,1 do
		if tab == i then
			term.setTextColor(colors.black)
			term.setBackgroundColor(colors.white)
		else
			term.setTextColor(colors.white)
			term.setBackgroundColor(colors.gray)
		end
		
		term.setCursorPos((math.floor((width/#tabs)*(i-0.5)))-math.ceil(#tabs[i]/2)+1, 1)
		term.write(tabs[i])
	end

	if tab == 1 then
		drawNowPlaying()
	elseif tab == 2 then
		drawSearch()
	end
end

function drawNowPlaying()
	if now_playing ~= nil then
		term.setBackgroundColor(colors.black)
		term.setTextColor(colors.white)
		term.setCursorPos(2,3)
		term.write(now_playing.name)
		term.setTextColor(colors.lightGray)
		term.setCursorPos(2,4)
		term.write(now_playing.artist)
	else
		term.setBackgroundColor(colors.black)
		term.setTextColor(colors.lightGray)
		term.setCursorPos(2,3)
		term.write("Not playing")
	end

	if is_loading == true then
		term.setTextColor(colors.gray)
		term.setBackgroundColor(colors.black)
		term.setCursorPos(2,5)
		term.write("Loading...")
	elseif is_error == true then
		term.setTextColor(colors.red)
		term.setBackgroundColor(colors.black)
		term.setCursorPos(2,5)
		term.write("Network error")
	end

	term.setTextColor(colors.white)
	term.setBackgroundColor(colors.gray)

	if playing then
		term.setCursorPos(2, 6)
		term.write(" Stop ")
	else
		if now_playing ~= nil or #queue > 0 then
			term.setTextColor(colors.white)
			term.setBackgroundColor(colors.gray)
		else
			term.setTextColor(colors.lightGray)
			term.setBackgroundColor(colors.gray)
		end
		term.setCursorPos(2, 6)
		term.write(" Play ")
	end

	if now_playing ~= nil or #queue > 0 then
		term.setTextColor(colors.white)
		term.setBackgroundColor(colors.gray)
	else
		term.setTextColor(colors.lightGray)
		term.setBackgroundColor(colors.gray)
	end
	term.setCursorPos(2 + 7, 6)
	term.write(" Skip ")

	if looping ~= 0 then
		term.setTextColor(colors.black)
		term.setBackgroundColor(colors.white)
	else
		term.setTextColor(colors.white)
		term.setBackgroundColor(colors.gray)
	end
	term.setCursorPos(2 + 7 + 7, 6)
	if looping == 0 then
		term.write(" Loop Off ")
	elseif looping == 1 then
		term.write(" Loop Queue ")
	else
		term.write(" Loop Song ")
	end

	term.setCursorPos(2,8)
	paintutils.drawBox(2,8,25,8,colors.gray)
	local width = math.floor(24 * (volume / 3) + 0.5)-1
	if not (width == -1) then
		paintutils.drawBox(2,8,2+width,8,colors.white)
	end
	if volume < 0.6 then
		term.setCursorPos(2+width+2,8)
		term.setBackgroundColor(colors.gray)
		term.setTextColor(colors.white)
	else
		term.setCursorPos(2+width-3-(volume == 3 and 1 or 0),8)
		term.setBackgroundColor(colors.white)
		term.setTextColor(colors.black)
	end
	term.write(math.floor(100 * (volume / 3) + 0.5) .. "%")

	if #queue > 0 then
		term.setBackgroundColor(colors.black)
		for i=1,#queue do
			term.setTextColor(colors.white)
			term.setCursorPos(2,10 + (i-1)*2)
			term.write(queue[i].name)
			term.setTextColor(colors.lightGray)
			term.setCursorPos(2,11 + (i-1)*2)
			term.write(queue[i].artist)
		end
	end
end

function drawSearch()
	-- Search bar
	paintutils.drawFilledBox(2,3,width-1,5,colors.lightGray)
	term.setBackgroundColor(colors.lightGray)
	term.setCursorPos(3,4)
	term.setTextColor(colors.black)
	term.write(last_search or "Search...")

	--Search results
	if search_results ~= nil then
		term.setBackgroundColor(colors.black)
		for i=1,#search_results do
			term.setTextColor(colors.white)
			term.setCursorPos(2,7 + (i-1)*2)
			term.write(search_results[i].name)
			term.setTextColor(colors.lightGray)
			term.setCursorPos(2,8 + (i-1)*2)
			term.write(search_results[i].artist)
		end
	else
		term.setCursorPos(2,7)
		term.setBackgroundColor(colors.black)
		if search_error == true then
			term.setTextColor(colors.red)
			term.write("Network error")
		elseif last_search_url ~= nil then
			term.setTextColor(colors.lightGray)
			term.write("Searching...")
		else
			term.setCursorPos(1,7)
			term.setTextColor(colors.lightGray)
			print("Tip: You can paste YouTube video or playlist links.")
		end
	end

	--fullscreen song options
	if in_search_result == true then
		term.setBackgroundColor(colors.black)
		term.clear()
		term.setCursorPos(2,2)
		term.setTextColor(colors.white)
		term.write(search_results[clicked_result].name)
		term.setCursorPos(2,3)
		term.setTextColor(colors.lightGray)
		term.write(search_results[clicked_result].artist)

		term.setBackgroundColor(colors.gray)
		term.setTextColor(colors.white)

		term.setCursorPos(2,6)
		term.clearLine()
		term.write("Play now")

		term.setCursorPos(2,8)
		term.clearLine()
		term.write("Play next")

		term.setCursorPos(2,10)
		term.clearLine()
		term.write("Add to queue")

		term.setCursorPos(2,13)
		term.clearLine()
		term.write("Cancel")
	end
end

function uiLoop()
	redrawScreen()

	while true do
		if waiting_for_input then
			parallel.waitForAny(
				function()
					term.setCursorPos(3,4)
					term.setBackgroundColor(colors.white)
					term.setTextColor(colors.black)
					local input = read()

					if string.len(input) > 0 then
						last_search = input
						last_search_url = api_base_url .. "?v=" .. version .. "&search=" .. textutils.urlEncode(input)
						local direct_id = extractYouTubeVideoId(input)
						if direct_id then
							-- Show a usable result immediately. The metadata request below
							-- replaces this placeholder when it finishes.
							search_results = {{
								id = direct_id,
								name = "YouTube video",
								artist = "Direct link - ready to play"
							}}
						else
							search_results = nil
						end
						search_error = false
						http.request(last_search_url)
					else
						last_search = nil
						last_search_url = nil
						search_results = nil
						search_error = false
					end

					waiting_for_input = false
					os.queueEvent("redraw_screen")
				end,
				function()
					while waiting_for_input do
						local event, button, x, y = os.pullEvent("mouse_click")
						if y < 3 or y > 5 or x < 2 or x > width-1 then
							waiting_for_input = false
							os.queueEvent("redraw_screen")
							break
						end
					end
				end
			)
		else
			parallel.waitForAny(
				function()
					local event, button, x, y = os.pullEvent("mouse_click")

					if button == 1 then
						-- Tabs
						if in_search_result == false then
							if y == 1 then
								if x < width/2 then
									tab = 1
								else
									tab = 2
								end
								redrawScreen()
							end
						end
						
						if tab == 2 and in_search_result == false then
							-- Search box click
							if y >= 3 and y <= 5 and x >= 1 and x <= width-1 then
								paintutils.drawFilledBox(2,3,width-1,5,colors.white)
								term.setBackgroundColor(colors.white)
								waiting_for_input = true
							end
		
							-- Search result click
							if search_results then
								for i=1,#search_results do
									if y == 7 + (i-1)*2 or y == 8 + (i-1)*2 then
										term.setBackgroundColor(colors.white)
										term.setTextColor(colors.black)
										term.setCursorPos(2,7 + (i-1)*2)
										term.clearLine()
										term.write(search_results[i].name)
										term.setTextColor(colors.gray)
										term.setCursorPos(2,8 + (i-1)*2)
										term.clearLine()
										term.write(search_results[i].artist)
										sleep(0.2)
										in_search_result = true
										clicked_result = i
										redrawScreen()
									end
								end
							end
						elseif tab == 2 and in_search_result == true then
							-- Search result menu clicks
		
							term.setBackgroundColor(colors.white)
							term.setTextColor(colors.black)
		
							if y == 6 then
								term.setCursorPos(2,6)
								term.clearLine()
								term.write("Play now")
								sleep(0.2)
								in_search_result = false
								stopAllSpeakers()
								playing = true
								is_error = false
								playing_id = nil
								if search_results[clicked_result].type == "playlist" then
									now_playing = search_results[clicked_result].playlist_items[1]
									queue = {}
									if #search_results[clicked_result].playlist_items > 1 then
										for i=2, #search_results[clicked_result].playlist_items do
											table.insert(queue, search_results[clicked_result].playlist_items[i])
										end
									end
								else
									now_playing = search_results[clicked_result]
								end
								os.queueEvent("audio_update")
							end
		
							if y == 8 then
								term.setCursorPos(2,8)
								term.clearLine()
								term.write("Play next")
								sleep(0.2)
								in_search_result = false
								if search_results[clicked_result].type == "playlist" then
									for i = #search_results[clicked_result].playlist_items, 1, -1 do
										table.insert(queue, 1, search_results[clicked_result].playlist_items[i])
									end
								else
									table.insert(queue, 1, search_results[clicked_result])
								end
								os.queueEvent("audio_update")
							end
		
							if y == 10 then
								term.setCursorPos(2,10)
								term.clearLine()
								term.write("Add to queue")
								sleep(0.2)
								in_search_result = false
								if search_results[clicked_result].type == "playlist" then
									for i = 1, #search_results[clicked_result].playlist_items do
										table.insert(queue, search_results[clicked_result].playlist_items[i])
									end
								else
									table.insert(queue, search_results[clicked_result])
								end
								os.queueEvent("audio_update")
							end
		
							if y == 13 then
								term.setCursorPos(2,13)
								term.clearLine()
								term.write("Cancel")
								sleep(0.2)
								in_search_result = false
							end
		
							redrawScreen()
						elseif tab == 1 and in_search_result == false then
							-- Now playing tab clicks
		
							if y == 6 then
								-- Play/stop button
								if x >= 2 and x < 2 + 6 then
									if playing or now_playing ~= nil or #queue > 0 then
										term.setBackgroundColor(colors.white)
										term.setTextColor(colors.black)
										term.setCursorPos(2, 6)
										if playing then
											term.write(" Stop ")
										else 
											term.write(" Play ")
										end
										sleep(0.2)
									end
									if playing then
										playing = false
										stopAllSpeakers()
										playing_id = nil
										is_loading = false
										is_error = false
										os.queueEvent("audio_update")
									elseif now_playing ~= nil then
										playing_id = nil
										playing = true
										is_error = false
										os.queueEvent("audio_update")
									elseif #queue > 0 then
										now_playing = queue[1]
										table.remove(queue, 1)
										playing_id = nil
										playing = true
										is_error = false
										os.queueEvent("audio_update")
									end
								end
		
								-- Skip button
								if x >= 2 + 7 and x < 2 + 7 + 6 then
									if now_playing ~= nil or #queue > 0 then
										term.setBackgroundColor(colors.white)
										term.setTextColor(colors.black)
										term.setCursorPos(2 + 7, 6)
										term.write(" Skip ")
										sleep(0.2)
		
										is_error = false
										if playing then
											stopAllSpeakers()
										end
										if #queue > 0 then
											if looping == 1 then
												table.insert(queue, now_playing)
											end
											now_playing = queue[1]
											table.remove(queue, 1)
											playing_id = nil
										else
											now_playing = nil
											playing = false
											is_loading = false
											is_error = false
											playing_id = nil
										end
										os.queueEvent("audio_update")
									end
								end
		
								-- Loop button
								if x >= 2 + 7 + 7 and x < 2 + 7 + 7 + 12 then
									if looping == 0 then
										looping = 1
									elseif looping == 1 then
										looping = 2
									else
										looping = 0
									end
								end
							end

							if y == 8 then
								-- Volume slider
								if x >= 1 and x < 2 + 24 then
									volume = (x - 1) / 24 * 3

									-- for _, speaker in ipairs(speakers) do
									-- 	speaker.stop()
									-- 	os.queueEvent("playback_stopped")
									-- end
									-- playing_id = nil
									-- os.queueEvent("audio_update")
								end
							end

							redrawScreen()
						end
					end
				end,
				function()
					local event, button, x, y = os.pullEvent("mouse_drag")

					if button == 1 then

						if tab == 1 and in_search_result == false then

							if y >= 7 and y <= 9 then
								-- Volume slider
								if x >= 1 and x < 2 + 24 then
									volume = (x - 1) / 24 * 3

									-- for _, speaker in ipairs(speakers) do
									-- 	speaker.stop()
									-- 	os.queueEvent("playback_stopped")
									-- end
									-- playing_id = nil
									-- os.queueEvent("audio_update")
								end
							end

							redrawScreen()
						end
					end
				end,
				function()
					local event = os.pullEvent("redraw_screen")

					redrawScreen()
				end
			)
		end
	end
end

local function playBufferOnAllSpeakers(audio, expected_id)
	refreshSpeakers()
	if #speakers == 0 then
		return false, "No speakers attached"
	end

	-- Keep retrying only the speakers which have not accepted this chunk yet.
	-- This prevents a busy speaker from silently losing chunks and avoids one
	-- coroutine per speaker, so large wired networks remain cheap and in sync.
	local pending = {}
	for _, speaker in ipairs(speakers) do
		pending[speaker.name] = speaker.device
	end

	while next(pending) do
		for name, device in pairs(pending) do
			local ok, accepted = pcall(device.playAudio, audio, volume)
			if not ok then
				-- It was probably detached. Do not block every other speaker.
				pending[name] = nil
			elseif accepted then
				pending[name] = nil
			end
		end

		if next(pending) then
			local event = os.pullEventRaw()
			if event == "terminate" then
				error("Terminated", 0)
			elseif event == "playback_stopped" then
				return false
			end
		end

		if not playing or playing_id ~= expected_id then
			return false
		end
	end

	return true
end

function audioLoop()
	while true do

		-- AUDIO
		if playing and now_playing then
			local thisnowplayingid = now_playing.id
			if playing_id ~= thisnowplayingid then
				playing_id = thisnowplayingid
				last_download_url = api_base_url .. "?v=" .. version .. "&id=" .. textutils.urlEncode(playing_id)
				playing_status = 0
				needs_next_chunk = 1

				http.request({url = last_download_url, binary = true})
				is_loading = true

				os.queueEvent("redraw_screen")
				os.queueEvent("audio_update")
			elseif playing_status == 1 and needs_next_chunk == 1 then

				while true do
					local chunk = player_handle.read(size)
					if not chunk then
						if looping == 2 or (looping == 1 and #queue == 0) then
							playing_id = nil
						elseif looping == 1 and #queue > 0 then
							table.insert(queue, now_playing)
							now_playing = queue[1]
							table.remove(queue, 1)
							playing_id = nil
						else
							if #queue > 0 then
								now_playing = queue[1]
								table.remove(queue, 1)
								playing_id = nil
							else
								now_playing = nil
								playing = false
								playing_id = nil
								is_loading = false
								is_error = false
							end
						end

						os.queueEvent("redraw_screen")

						player_handle.close()
						needs_next_chunk = 0
						break
					else
						if start then
							chunk, start = start .. chunk, nil
							size = size + 4
						end
				
						buffer = decoder(chunk)
						
						local ok, accepted, err = pcall(playBufferOnAllSpeakers, buffer, thisnowplayingid)
						if not ok or (not accepted and err) then
							needs_next_chunk = 2
							is_error = true
							break
						end
						
						-- If we're not playing anymore, exit the chunk processing loop
						if not playing or playing_id ~= thisnowplayingid then
							break
						end
					end
				end
				os.queueEvent("audio_update")
			end
		end

		os.pullEvent("audio_update")
	end
end

function httpLoop()
	while true do
		parallel.waitForAny(
			function()
				local event, url, handle = os.pullEvent("http_success")

				if url == last_search_url then
					local body = handle.readAll()
					handle.close()
					local ok, results = pcall(textutils.unserialiseJSON, body)
					if ok and type(results) == "table" then
						-- Keep an instant direct-link placeholder if metadata lookup
						-- returned nothing. The audio can still be requested by ID.
						if #results > 0 or not search_results then
							search_results = results
						end
					else
						search_error = true
					end
					os.queueEvent("redraw_screen")
				elseif url == last_download_url then
					is_loading = false
					player_handle = handle
					start = handle.read(4)
					size = 16 * 1024 - 4
					playing_status = 1
					os.queueEvent("redraw_screen")
					os.queueEvent("audio_update")
				else
					handle.close()
				end
			end,
			function()
				local event, url = os.pullEvent("http_failure")	

				if url == last_search_url then
					search_error = true
					os.queueEvent("redraw_screen")
				end
				if url == last_download_url then
					is_loading = false
					is_error = true
					playing = false
					playing_id = nil
					os.queueEvent("redraw_screen")
					os.queueEvent("audio_update")
				end
			end
		)
	end
end

parallel.waitForAny(uiLoop, audioLoop, httpLoop)
