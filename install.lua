local owner = "LucasPreto0000"
local repository = "computercraft-streaming-music"
local branch = "main"
local target = "music"

local url = ("https://raw.githubusercontent.com/%s/%s/%s/music.lua?ts=%d")
	:format(owner, repository, branch, os.epoch("utc"))

term.setTextColor(colors.cyan)
print("ComputerCraft Streaming Music")
term.setTextColor(colors.white)
print("Downloading the latest version...")

local response, request_error = http.get(url, {
	["Cache-Control"] = "no-cache",
	["User-Agent"] = "CC-Tweaked-Music-Installer"
})

if not response then
	error("Download failed: " .. tostring(request_error), 0)
end

local code = response.readAll()
response.close()

if not code or #code < 1000 then
	error("The downloaded file is invalid. Nothing was changed.", 0)
end

local temporary = target .. ".new"
local backup = target .. ".bak"

if fs.exists(temporary) then fs.delete(temporary) end
local file = fs.open(temporary, "w")
file.write(code)
file.close()

if fs.exists(backup) then fs.delete(backup) end
if fs.exists(target) then fs.move(target, backup) end
fs.move(temporary, target)

term.setTextColor(colors.lime)
print("Installed successfully as '" .. target .. "'.")
term.setTextColor(colors.lightGray)
if fs.exists(backup) then
	print("Your previous version is saved as '" .. backup .. "'.")
end
term.setTextColor(colors.white)
print("Run it with: " .. target)
