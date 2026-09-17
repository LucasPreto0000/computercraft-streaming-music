local api_base_url = "https://ipod-2to6magyna-uc.a.run.app/"
local version = "3.2"
local media_backend = settings.get("music.media_backend", "")
local revision = 0
local audio_error = nil
local search_notice = nil
local elapsed_samples = 0
local excluded = settings.get("music.exclude_speakers", {})

local width, height = term.getSize()
local tab = 1

local waiting_for_input = false
local last_search = nil
local last_search_url = nil
local last_spotify_url = nil
local last_spotify_embed_url = nil
local spotify_fallback_title = nil
local search_results = nil
local search_error = false

local playing = false
local queue = {}
local now_playing = nil
local looping = 0
-- CC:Tweaked accepts values from 0.0 to 3.0. Start at the real maximum.
local volume = 3.0

local playing_id = nil
local cancelledDownloads = {}
local downloadSerial = 0
local is_loading = false
local is_error = false;


-- Do not collect peripheral.find's multiple return values here. Enumerating the
-- peripheral names has no practical vararg limit and also lets us refresh the
-- list when wired speakers are attached or removed while the program is open.
local speakers = {}

local function refreshSpeakers()
	local found, seen = {}, {}
	for _, name in ipairs(peripheral.getNames()) do
		if not seen[name] and not excluded[name] and peripheral.hasType(name, "speaker") then
			seen[name] = true
			local device = peripheral.wrap(name)
			if device then found[#found + 1] = {name = name, device = device} end
		end
	end
	table.sort(found, function(a, b) return a.name < b.name end)
	speakers = found
	return #speakers
end

local function stopDevices()
	for _, speaker in ipairs(speakers) do pcall(speaker.device.stop) end
end

local function stopAllSpeakers()
	revision = revision + 1
	stopDevices()
	os.queueEvent("audio_update")
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

local function isSpotifyUrl(value)
	if not value then return false end
	return value:match("^https?://open%.spotify%.com/") ~= nil
		or value:match("^https?://spotify%.link/") ~= nil
end

local function spotifyOEmbedUrl(value)
	local base = value:match("^https?://spotify%.link/") and "https://spotify.link" or "https://open.spotify.com"
	return base .. "/oembed?url=" .. textutils.urlEncode(value)
end

local function requestMusicSearch(query)
	search_notice = nil
	if query:match("^https?://") and not query:match("^https?://[%w.]*youtube%.com/") and not query:match("^https?://youtu%.be/") then
		last_search_url = nil
		local path = query:match("^[^?#]+") or query
		if path:lower():match("%.dfpwm$") then
			search_results = {{id = query, direct_url = query, name = "Audio DFPWM", artist = query}}
			return true
		elseif media_backend ~= "" then
			search_results = {{id = query, media_url = query, name = "Video externo", artist = query}}
			return true
		else
			search_error = true
			search_notice = "Outros sites: configure music.media_backend"
			return false
		end
	end
	last_search_url = api_base_url .. "?v=" .. version .. "&search=" .. textutils.urlEncode(query)
	local requested = http.request(last_search_url)
	if not requested then
		last_search_url = nil
		search_error = true
	end
	return requested
end


refreshSpeakers()

local scroll = {0, 0, 0}
local buttons = {}
local selected = nil
local query_text = ""

local function clip(value, maximum)
	value = tostring(value or ""):gsub("[\r\n\t]", " ")
	if maximum < 1 then return "" end
	if #value <= maximum then return value end
	if maximum == 1 then return "~" end
	return value:sub(1, maximum - 1) .. "~"
end

local function text(x, y, value, foreground, background, maximum)
	if y < 1 or y > height or x < 1 or x > width then return end
	term.setCursorPos(x, y)
	term.setTextColor(foreground or colors.white)
	term.setBackgroundColor(background or colors.black)
	term.write(clip(value, math.min(maximum or width, width - x + 1)))
end

local function fill(x1, y1, x2, y2, color)
	x1, y1 = math.max(1, x1), math.max(1, y1)
	x2, y2 = math.min(width, x2), math.min(height, y2)
	if x1 > x2 or y1 > y2 then return end
	local spaces = string.rep(" ", x2 - x1 + 1)
	for y = y1, y2 do text(x1, y, spaces, colors.white, color) end
end

local function centeredText(x, y, boxWidth, value, foreground, background)
	value = clip(value, boxWidth)
	local left = x + math.max(0, math.floor((boxWidth - #value) / 2))
	text(left, y, value, foreground, background, boxWidth)
end

local function button(x, y, boxWidth, label, action, active, enabled)
	boxWidth = math.max(1, math.min(boxWidth, width - x + 1))
	local background = active and colors.cyan or (enabled == false and colors.gray or colors.blue)
	local foreground = active and colors.black or (enabled == false and colors.lightGray or colors.white)
	fill(x, y, x + boxWidth - 1, y, background)
	centeredText(x, y, boxWidth, label, foreground, background)
	buttons[#buttons + 1] = {x=x, y=y, w=boxWidth, h=1, action=action, enabled=enabled ~= false}
end

local function submitSearch(input)
	input = input:match("^%s*(.-)%s*$")
	scroll[2], selected = 0, nil
	last_search, search_results, search_notice = input, nil, nil
	last_search_url, last_spotify_url, last_spotify_embed_url = nil, nil, nil
	spotify_fallback_title, search_error = nil, false
	if input == "" then return end
	if isSpotifyUrl(input) then
		last_spotify_url = spotifyOEmbedUrl(input)
		if not http.request(last_spotify_url) then
			last_spotify_url, search_error = nil, true
		end
	else
		local direct_id = extractYouTubeVideoId(input)
		if direct_id then
			search_results = {{id=direct_id, name="Video YouTube", artist="Link pronto para tocar"}}
		end
		requestMusicSearch(input)
	end
end

local function playTrack(item)
	stopAllSpeakers()
	if item.type == "playlist" then
		queue = {}
		for _, track in ipairs(item.playlist_items or {}) do queue[#queue + 1] = track end
		now_playing = table.remove(queue, 1)
	else
		now_playing = item
	end
	playing, is_error, audio_error = now_playing ~= nil, false, nil
	selected, tab = nil, 1
	os.queueEvent("audio_update")
end

local function skipTrack()
	stopAllSpeakers()
	if looping == 1 and now_playing then queue[#queue + 1] = now_playing end
	now_playing = table.remove(queue, 1)
	playing, is_error = now_playing ~= nil, false
	os.queueEvent("audio_update")
end

local function queueItem(item, nextUp)
	local items = item.type == "playlist" and (item.playlist_items or {}) or {item}
	if nextUp then
		for i = #items, 1, -1 do table.insert(queue, 1, items[i]) end
	else
		for _, track in ipairs(items) do queue[#queue + 1] = track end
	end
	selected = nil
end

local function drawHeader()
	fill(1, 1, width, 1, colors.blue)
	text(2, 1, "MUSIC PLAYER", colors.white, colors.blue)
	local info = "v" .. version .. "  " .. #speakers .. " SPK"
	text(math.max(14, width - #info), 1, info, colors.cyan, colors.blue)

	local first = math.floor(width / 3)
	local second = math.floor(width / 3)
	local third = width - first - second
	button(1, 2, first, "PLAYER", function() tab=1; selected=nil; waiting_for_input=false end, tab==1)
	button(first + 1, 2, second, "BUSCA", function() tab=2; selected=nil end, tab==2)
	button(first + second + 1, 2, third, "SAIDAS", function() tab=3; selected=nil; waiting_for_input=false end, tab==3)
	fill(1, 3, width, 3, colors.gray)
end

local function drawFooter()
	fill(1, height, width, height, colors.blue)
	text(2, height, "RODA: rolar", colors.lightGray, colors.blue)
	local exit = "CTRL+T: sair"
	text(math.max(15, width - #exit), height, exit, colors.lightGray, colors.blue)
end

local function drawSelection()
	text(2, 4, "ITEM SELECIONADO", colors.lightBlue)
	text(2, 5, selected.name, colors.cyan, colors.black, width - 3)
	text(2, 6, selected.artist, colors.lightGray, colors.black, width - 3)
	button(2, 8, math.min(15, width - 3), "TOCAR AGORA", function() playTrack(selected) end, true)
	button(2, 10, math.min(15, width - 3), "TOCAR DEPOIS", function() queueItem(selected, true) end)
	button(2, 12, math.min(20, width - 3), "ADICIONAR A FILA", function() queueItem(selected, false) end)
	button(2, 14, math.min(10, width - 3), "VOLTAR", function() selected=nil end)
end

local function drawPlayer()
	local state = is_error and "ERRO" or is_loading and "CARREGANDO" or playing and "TOCANDO" or "PARADO"
	local stateColor = is_error and colors.red or is_loading and colors.orange or playing and colors.lime or colors.lightGray
	text(2, 4, "AGORA TOCANDO", colors.lightBlue)
	text(math.max(20, width - #state - 1), 4, state, stateColor)
	text(2, 5, now_playing and now_playing.name or "Nenhuma musica selecionada", now_playing and colors.cyan or colors.white, colors.black, width - 3)
	text(2, 6, now_playing and now_playing.artist or "Abra BUSCA para escolher uma musica.", colors.lightGray, colors.black, width - 3)
	if is_error then
		text(2, 7, audio_error or "Falha no audio", colors.red, colors.black, width - 3)
	else
		text(2, 7, string.format("TEMPO ENVIADO  %02d:%02d", math.floor(elapsed_samples / 2880000), math.floor(elapsed_samples / 48000) % 60), colors.gray)
	end

	local canPlay = now_playing ~= nil or #queue > 0
	button(2, 9, 10, playing and "PARAR" or "TOCAR", function()
		if playing then
			playing=false
			stopAllSpeakers()
		elseif now_playing then
			playTrack(now_playing)
		elseif #queue > 0 then
			playTrack(table.remove(queue, 1))
		end
	end, playing, canPlay)
	button(13, 9, 9, "PULAR", skipTrack, false, now_playing ~= nil or #queue > 0)
	local loopLabel = ({"LOOP OFF", "LOOP FILA", "LOOP 1"})[looping + 1]
	button(23, 9, math.min(13, width - 24), loopLabel, function() looping=(looping+1)%3 end, looping > 0)

	local percent = math.floor(volume / 3 * 100 + 0.5)
	text(2, 11, "VOLUME", colors.lightBlue)
	local percentage = percent .. "%"
	text(math.max(10, width - #percentage - 1), 11, percentage, colors.cyan)
	local barWidth = math.max(4, width - 3)
	local filled = math.floor(barWidth * volume / 3 + 0.5)
	fill(2, 12, 1 + barWidth, 12, colors.gray)
	if filled > 0 then fill(2, 12, 1 + filled, 12, colors.cyan) end

	text(2, 14, "FILA", colors.lightBlue)
	text(8, 14, tostring(#queue) .. " faixa" .. (#queue == 1 and "" or "s"), colors.lightGray)
	local visible = math.max(0, height - 15)
	if #queue == 0 then
		text(2, 16, "A fila esta vazia.", colors.gray)
	else
		for row = 0, visible - 1 do
			local index = scroll[1] + row + 1
			local item = queue[index]
			if item then
				text(2, 15 + row, tostring(index), colors.gray)
				text(5, 15 + row, item.name, colors.white, colors.black, width - 6)
			end
		end
	end
end

local function drawSearch()
	text(2, 4, "BUSCAR MUSICA OU VIDEO", colors.lightBlue)
	fill(2, 5, width - 1, 5, waiting_for_input and colors.white or colors.lightGray)
	local prompt = query_text ~= "" and query_text or "Cole um link ou digite uma musica"
	text(3, 5, prompt, query_text ~= "" and colors.black or colors.gray, waiting_for_input and colors.white or colors.lightGray, width - 4)
	text(2, 6, waiting_for_input and "Digite e pressione ENTER" or "Clique no campo para editar", colors.gray)
	if waiting_for_input then
		term.setCursorPos(math.min(width - 1, 3 + #query_text), 5)
		term.setCursorBlink(true)
	end

	if search_notice then
		text(2, 8, search_notice, colors.orange, colors.black, width - 3)
	elseif search_error then
		text(2, 8, "Nao foi possivel completar a busca.", colors.red)
	elseif last_spotify_url or last_spotify_embed_url then
		text(2, 8, "Consultando o Spotify...", colors.lime)
	elseif not search_results and last_search_url then
		text(2, 8, "Buscando...", colors.orange)
	elseif not search_results then
		text(2, 8, "YouTube, Spotify ou backend configurado", colors.lightGray)
	end

	local visible = math.max(0, math.floor((height - 10) / 2))
	for row = 0, visible - 1 do
		local index = scroll[2] + row + 1
		local item = search_results and search_results[index]
		if item then
			local y = 8 + row * 2
			text(2, y, tostring(index) .. ".", colors.gray)
			text(5, y, item.name, colors.cyan, colors.black, width - 6)
			text(5, y + 1, item.artist, colors.lightGray, colors.black, width - 6)
			buttons[#buttons + 1] = {x=1, y=y, w=width, h=2, enabled=true, action=function()
				selected=item
				waiting_for_input=false
			end}
		end
	end
end

local function drawOutputs()
	text(2, 4, "SPEAKERS CONECTADOS", colors.lightBlue)
	local summary = tostring(#speakers) .. " detectado" .. (#speakers == 1 and "" or "s")
	text(math.max(22, width - #summary - 1), 4, summary, colors.cyan)
	text(2, 5, "O grupo fica fixo durante cada faixa.", colors.lightGray, colors.black, width - 3)
	text(2, 6, "Novos speakers entram ao reiniciar.", colors.gray, colors.black, width - 3)
	button(2, 8, math.min(18, width - 3), "REINICIAR GRUPO", function()
		refreshSpeakers()
		if now_playing then playTrack(now_playing) end
	end, false, now_playing ~= nil)

	local visible = math.max(0, height - 10)
	for row = 0, visible - 1 do
		local item = speakers[scroll[3] + row + 1]
		if item then
			local y = 10 + row
			text(2, y, "+", colors.lime)
			text(5, y, item.name, colors.white, colors.black, width - 6)
		end
	end
end

function redrawScreen()
	width, height = term.getSize()
	buttons = {}
	term.setCursorBlink(false)
	term.setBackgroundColor(colors.black)
	term.clear()
	drawHeader()
	drawFooter()
	if selected then drawSelection()
	elseif tab == 1 then drawPlayer()
	elseif tab == 2 then drawSearch()
	else drawOutputs() end
end

local function visibleRows()
	if tab == 1 then return math.max(1, height - 15) end
	if tab == 2 then return math.max(1, math.floor((height - 10) / 2)) end
	return math.max(1, height - 10)
end

function uiLoop()
	while true do
		redrawScreen()
		local event, a, b, c = os.pullEvent()
		if event == "mouse_click" then
			if tab == 2 and not selected and c == 5 then
				waiting_for_input = true
			else
				for _, hit in ipairs(buttons) do
					if hit.enabled and b >= hit.x and b < hit.x + hit.w and c >= hit.y and c < hit.y + hit.h then
						hit.action()
						break
					end
				end
			end
		end
		if (event == "mouse_click" or event == "mouse_drag") and a == 1 and tab == 1 and not selected and c == 12 then
			local barWidth = math.max(4, width - 3)
			volume = math.max(0, math.min(3, (b - 2) / math.max(1, barWidth - 1) * 3))
		elseif event == "mouse_scroll" then
			local total = tab == 1 and #queue or tab == 2 and #(search_results or {}) or #speakers
			local maximum = math.max(0, total - visibleRows())
			scroll[tab] = math.max(0, math.min(maximum, scroll[tab] + a))
		elseif tab == 2 and not selected then
			if event == "paste" or event == "char" then
				query_text = query_text .. a
				waiting_for_input = true
			elseif event == "key" and a == keys.backspace then
				query_text = query_text:sub(1, -2)
			elseif event == "key" and a == keys.enter then
				waiting_for_input = false
				submitSearch(query_text)
			end
		end
		if event == "peripheral" or event == "peripheral_detach" then refreshSpeakers() end
	end
end

-- Build a binary tree of CC:Tweaked's native parallel scheduler. Each leaf is
-- one speaker, but every waitForAll call receives only two functions. This
-- avoids table.unpack's argument ceiling while leaving task_complete and
-- speaker_audio_empty event routing to the scheduler bundled with CraftOS.
local function runWorkers(workers)
	local function runRange(first, last)
		if first > last then return end
		if first == last then return workers[first]() end
		local middle = math.floor((first + last) / 2)
		parallel.waitForAll(
			function() runRange(first, middle) end,
			function() runRange(middle + 1, last) end
		)
	end
	runRange(1, #workers)
end

local function playBufferOnAllSpeakers(audio, group)
	if #group == 0 then error("Nenhum speaker conectado", 0) end
	local workers = {}
	for i, entry in ipairs(group) do
		local speaker = entry
		workers[i] = function()
			local timer = os.startTimer(8)
			while true do
				if not peripheral.isPresent(speaker.name) then
					error("Speaker removido: " .. speaker.name, 0)
				end
				local ok, accepted = pcall(speaker.device.playAudio, audio, volume)
				if not ok then error("Falha no speaker: " .. speaker.name, 0) end
				if accepted then break end
				while true do
					local event, name = os.pullEvent()
					if event == "timer" and name == timer then
						error("Speaker ocupado: " .. speaker.name, 0)
					elseif event == "peripheral_detach" and name == speaker.name then
						error("Speaker removido: " .. speaker.name, 0)
					elseif event == "speaker_audio_empty" and name == speaker.name then
						break
					end
				end
			end
			-- Barrier: no speaker receives chunk N+1 until every speaker is ready.
			while true do
				local event, name = os.pullEvent()
				if event == "speaker_audio_empty" and name == speaker.name then
					os.cancelTimer(timer)
					return
				elseif event == "timer" and name == timer then
					error("Speaker sem resposta: " .. speaker.name, 0)
				elseif event == "peripheral_detach" and name == speaker.name then
					error("Speaker removido: " .. speaker.name, 0)
				end
			end
		end
	end
	runWorkers(workers)
end

local function audioUrl(track)
	if track.direct_url then return track.direct_url end
	if track.media_url then
		return media_backend:gsub("/+$", "") .. "/audio?url=" .. textutils.urlEncode(track.media_url)
	end
	return api_base_url .. "?v=2.4&id=" .. textutils.urlEncode(track.id)
end

function audioLoop()
	while true do
		if not playing or not now_playing then
			os.pullEvent("audio_update")
		else
			local track, token = now_playing, revision
			local handle, finished = nil, false
			downloadSerial = downloadSerial + 1
			local requestUrl = audioUrl(track)
			if not track.direct_url then
				requestUrl = requestUrl .. "&request=" .. os.epoch("utc") .. "-" .. downloadSerial
			end
			refreshSpeakers()
			local group = speakers -- Fixed for this track; newcomers join the next.
			stopDevices()
			playing_id = track.id
			is_loading, is_error, audio_error = true, false, nil
			elapsed_samples = 0
			os.queueEvent("redraw_screen")
			local ok, err = pcall(function()
				parallel.waitForAny(
					function()
						if #group == 0 then error("Conecte um speaker e tente novamente", 0) end
						local reason
						local headers = nil
						if track.media_url then
							headers = {Authorization = "Bearer " .. settings.get("music.media_token", "")}
						end
						handle, reason = http.get(requestUrl, headers, true)
						if not handle then error("Falha no download: " .. tostring(reason), 0) end
						local decode = require("cc.audio.dfpwm").make_decoder()
						is_loading = false
						os.queueEvent("redraw_screen")
						local final_duration = 0
						while true do
							local chunk = handle.read(16 * 1024)
							if not chunk or #chunk == 0 then break end
							local samples = decode(chunk)
							playBufferOnAllSpeakers(samples, group)
							final_duration = #samples / 48000
							elapsed_samples = elapsed_samples + #samples
							os.queueEvent("redraw_screen")
						end
						-- The readiness event allows more buffering; it is not an
						-- audible-end event. Let the last chunk finish before stopping.
						if final_duration > 0 then sleep(final_duration) end
						finished = true
					end,
					function()
						repeat os.pullEvent("audio_update")
						until revision ~= token or not playing or now_playing ~= track
					end
				)
			end)
			if handle then pcall(handle.close) else cancelledDownloads[requestUrl] = true end
			for _, speaker in ipairs(group) do pcall(speaker.device.stop) end
			is_loading = false
			if not ok then
				if tostring(err):find("Terminated", 1, true) then error(err, 0) end
				is_error, audio_error, playing = true, tostring(err), false
			elseif finished and token == revision and now_playing == track then
				if looping == 2 then
					-- Repeat current track with a fresh decoder.
				elseif looping == 1 then
					queue[#queue + 1] = track
					now_playing = table.remove(queue, 1)
				elseif #queue > 0 then
					now_playing = table.remove(queue, 1)
				else
					now_playing, playing = nil, false
				end
			end
			playing_id = nil
			os.queueEvent("redraw_screen")
		end
	end
end

function httpLoop()
	while true do
		parallel.waitForAny(
			function()
				local event, url, handle = os.pullEvent("http_success")

				if url == last_spotify_url then
					local body = handle.readAll()
					handle.close()
					last_spotify_url = nil
					local ok, metadata = pcall(textutils.unserialiseJSON, body)
					if ok and type(metadata) == "table" and type(metadata.title) == "string" then
						spotify_fallback_title = metadata.title
						local embed_url = metadata.iframe_url
							or (type(metadata.html) == "string" and metadata.html:match('src="([^"]+)"'))
						if embed_url then embed_url = embed_url:gsub("&amp;", "&") end
						last_spotify_embed_url = embed_url
						local requested = embed_url and http.request(embed_url)
						if not requested then
							last_spotify_embed_url = nil
							requestMusicSearch(spotify_fallback_title .. " official audio")
							spotify_fallback_title = nil
						end
					else
						search_error = true
					end
					os.queueEvent("redraw_screen")
				elseif url == last_spotify_embed_url then
					local body = handle.readAll()
					handle.close()
					last_spotify_embed_url = nil
					local json = body:match('<script[^>]-id="__NEXT_DATA__"[^>]*>(.-)</script>')
					local ok, page = pcall(textutils.unserialiseJSON, json or "")
					local entity = ok and page and page.props and page.props.pageProps
						and page.props.pageProps.state and page.props.pageProps.state.data
						and page.props.pageProps.state.data.entity
					local title = entity and (entity.title or entity.name) or spotify_fallback_title
					local artist_names = {}
					if entity and type(entity.artists) == "table" then
						for _, artist in ipairs(entity.artists) do
							if type(artist) == "table" and type(artist.name) == "string" then
								artist_names[#artist_names + 1] = artist.name
							end
						end
					end
					spotify_fallback_title = nil
					if title then
						local query = title
						if #artist_names > 0 then query = query .. " " .. table.concat(artist_names, " ") end
						requestMusicSearch(query .. " official audio")
					else
						search_error = true
					end
					os.queueEvent("redraw_screen")
				elseif url == last_search_url then
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
				elseif cancelledDownloads[url] then
					handle.close()
					cancelledDownloads[url] = nil
				end
			end,
			function()
				local event, url = os.pullEvent("http_failure")	

				if url == last_spotify_url then
					last_spotify_url = nil
					search_error = true
					os.queueEvent("redraw_screen")
				elseif url == last_spotify_embed_url then
					last_spotify_embed_url = nil
					if spotify_fallback_title then
						requestMusicSearch(spotify_fallback_title .. " official audio")
						spotify_fallback_title = nil
					else
						search_error = true
					end
					os.queueEvent("redraw_screen")
				elseif url == last_search_url then
					search_error = true
					os.queueEvent("redraw_screen")
				end
				cancelledDownloads[url] = nil
			end
		)
	end
end

local ok, err = pcall(parallel.waitForAny, uiLoop, audioLoop, httpLoop)
stopDevices()
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok and not tostring(err):find("Terminated", 1, true) then printError(err) end
