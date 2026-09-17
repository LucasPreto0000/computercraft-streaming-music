local api_base_url = "https://ipod-2to6magyna-uc.a.run.app/"
local version = "3.0"
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
	return #value > maximum and (value:sub(1, math.max(0, maximum - 1)) .. "~") or value
end
local function text(x, y, value, fg, bg, count)
	if y < 1 or y > height or x < 1 or x > width then return end
	term.setCursorPos(x, y)
	term.setTextColor(fg or colors.white)
	term.setBackgroundColor(bg or colors.black)
	term.write(clip(value, math.min(count or width, width - x + 1)))
end
local function bar(y, color)
	term.setCursorPos(1, y)
	term.setBackgroundColor(color)
	term.clearLine()
end
local function button(x, y, label, action, active)
	local value = " " .. label .. " "
	text(x, y, value, active and colors.black or colors.white, active and colors.cyan or colors.gray)
	buttons[#buttons + 1] = {x=x, y=y, w=#value, action=action}
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
		for _, track in ipairs(item.playlist_items or {}) do queue[#queue+1] = track end
		now_playing = table.remove(queue, 1)
	else now_playing = item end
	playing, is_error = now_playing ~= nil, false
	selected, tab = nil, 1
	os.queueEvent("audio_update")
end
local function skipTrack()
	stopAllSpeakers()
	if looping == 1 and now_playing then queue[#queue+1] = now_playing end
	now_playing = table.remove(queue, 1)
	playing, is_error = now_playing ~= nil, false
	os.queueEvent("audio_update")
end
local function queueItem(item, nextUp)
	local items = item.type == "playlist" and (item.playlist_items or {}) or {item}
	if nextUp then
		for i=#items,1,-1 do table.insert(queue, 1, items[i]) end
	else for _, track in ipairs(items) do queue[#queue+1] = track end end
	selected = nil
end

function redrawScreen()
	width, height = term.getSize()
	buttons = {}
	term.setCursorBlink(false)
	term.setBackgroundColor(colors.black)
	term.clear()
	bar(1, colors.blue)
	text(2,1,"MUSIC / 3.0",colors.white,colors.blue)
	local count = tostring(#speakers) .. " SPK"
	text(math.max(16,width-#count),1,count,colors.cyan,colors.blue)
	button(2,2,"PLAYER",function() tab=1; selected=nil end,tab==1)
	button(11,2,"BUSCA",function() tab=2; selected=nil end,tab==2)
	button(19,2,"SAIDAS",function() tab=3; selected=nil end,tab==3)
	bar(height, colors.gray)
	text(2,height,"Roda: rolar | Ctrl+T: sair",colors.lightGray,colors.gray)
	if selected then
		text(2,4,selected.name,colors.cyan)
		text(2,5,selected.artist,colors.lightGray)
		button(2,7,"TOCAR AGORA",function() playTrack(selected) end,true)
		button(2,9,"PROXIMA",function() queueItem(selected,true) end)
		button(2,11,"ADICIONAR A FILA",function() queueItem(selected,false) end)
		button(2,13,"VOLTAR",function() selected=nil end)
	elseif tab == 1 then
		text(2,4,now_playing and now_playing.name or "Sua proxima musica comeca aqui",colors.cyan)
		text(2,5,now_playing and now_playing.artist or "Abra BUSCA e cole um link.",colors.lightGray)
		local state = is_error and "ERRO" or is_loading and "CARREGANDO" or playing and "TOCANDO" or "PARADO"
		text(2,6,state .. "  /  " .. math.floor(elapsed_samples/48000) .. "s enviados",is_error and colors.red or colors.lime)
		button(2,8,playing and "PARAR" or "TOCAR",function()
			if playing then playing=false; stopAllSpeakers()
			elseif now_playing then playTrack(now_playing)
			elseif #queue>0 then playTrack(table.remove(queue,1)) end
		end,playing)
		button(11,8,"PULAR",skipTrack)
		button(20,8,({"LOOP -","LOOP FILA","LOOP 1"})[looping+1],function() looping=(looping+1)%3 end,looping>0)
		local w = math.max(2,width-13)
		local n = math.floor(w*volume/3+0.5)
		text(2,10,string.rep(" ",n),colors.black,colors.cyan)
		text(2+n,10,string.rep(" ",w-n),colors.white,colors.gray)
		text(w+3,10,math.floor(volume/3*100+0.5).."%",colors.cyan)
		text(2,12,"FILA / "..#queue,colors.lightBlue)
		if is_error then text(2,13,audio_error or "Falha no audio",colors.red)
		else
			for row=0,math.max(-1,height-15) do
				local index=scroll[1]+row+1
				if queue[index] then text(2,14+row,index..". "..queue[index].name) end
			end
		end
	elseif tab == 2 then
		bar(4,colors.gray)
		text(2,4,(waiting_for_input and "> " or "Buscar: ")..query_text,colors.white,colors.gray,width-2)
		text(2,5,"Cole o link, depois pressione Enter",colors.lightGray)
		if waiting_for_input then
			term.setCursorPos(math.min(width,4+#query_text),4)
			term.setCursorBlink(true)
		end
		if search_notice then text(2,7,search_notice,colors.orange)
		elseif search_error then text(2,7,"Falha na busca. Tente novamente.",colors.red)
		elseif last_spotify_url or last_spotify_embed_url then text(2,7,"Consultando Spotify...",colors.lime)
		elseif not search_results and last_search_url then text(2,7,"Buscando...",colors.orange) end
		for row=0,math.floor((height-9)/2) do
			local index=scroll[2]+row+1
			local item=search_results and search_results[index]
			if item then
				local y=8+row*2
				text(2,y,index..". "..item.name,colors.cyan)
				text(4,y+1,item.artist,colors.lightGray)
				buttons[#buttons+1]={x=1,y=y,w=width,h=2,action=function() selected=item; waiting_for_input=false end}
			end
		end
	elseif tab == 3 then
		text(2,4,"SAIDAS CONECTADAS / "..#speakers,colors.cyan)
		text(2,5,"Novas saidas entram na proxima faixa.",colors.lightGray)
		text(2,6,"Use 1 conexao por speaker; evite aliases.",colors.orange)
		button(2,7,"REINICIAR GRUPO",function()
			refreshSpeakers()
			if now_playing then playTrack(now_playing) end
		end)
		for row=0,height-10 do
			local item=speakers[scroll[3]+row+1]
			if item then text(2,8+row,"+ "..item.name,colors.lime) end
		end
	end
end

function uiLoop()
	while true do
		redrawScreen()
		local event,a,b,c = os.pullEvent()
		if event=="mouse_click" then
			if tab==2 and not selected and c==4 then
				waiting_for_input=true
			else
				for _, hit in ipairs(buttons) do
					if b>=hit.x and b<hit.x+hit.w and c>=hit.y and c<hit.y+(hit.h or 1) then hit.action(); break end
				end
			end
		end
		if (event=="mouse_click" or event=="mouse_drag") and a==1 and tab==1 and not selected and c==10 then
			volume=math.max(0,math.min(3,(b-2)/math.max(1,width-14)*3))
		elseif event=="mouse_scroll" then
			local total=tab==1 and #queue or tab==2 and #(search_results or {}) or #speakers
			scroll[tab]=math.max(0,math.min(math.max(0,total-1),scroll[tab]+a))
		elseif tab==2 and not selected then
			if event=="paste" or event=="char" then query_text=query_text..a; waiting_for_input=true
			elseif event=="key" and a==keys.backspace then query_text=query_text:sub(1,-2)
			elseif event=="key" and a==keys.enter then waiting_for_input=false; submitSearch(query_text) end
		end
		if event=="peripheral" or event=="peripheral_detach" then refreshSpeakers() end
	end
end

-- Table-based scheduler: each peripheral call starts before waiting for the
-- others. No unpack/function-argument ceiling, and event filters are preserved.
local function runWorkers(workers)
	local tasks = {}
	for i, fn in ipairs(workers) do tasks[i] = {co = coroutine.create(fn)} end
	local event = {n = 0}
	while true do
		local alive = false
		for _, task in ipairs(tasks) do
			if coroutine.status(task.co) ~= "dead" then
				if not task.filter or task.filter == event[1] or event[1] == "terminate" then
					local ok, filter = coroutine.resume(task.co, table.unpack(event, 1, event.n))
					if not ok then error(filter, 0) end
					task.filter = filter
				end
				if coroutine.status(task.co) ~= "dead" then alive = true end
			end
		end
		if not alive then return end
		event = table.pack(os.pullEventRaw())
	end
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
