# ComputerCraft Streaming Music — Enhanced Fork

An improved music player for Minecraft computers running CC: Tweaked.

**Version:** 3.1

## Install or update

Run this command in your CC: Tweaked computer:

```lua
wget run https://raw.githubusercontent.com/LucasPreto0000/computercraft-streaming-music/main/install.lua
```

Then start the player with:

```lua
music
```

The installer downloads this fork directly from GitHub. When updating, it
keeps the previous version as `music.bak`.

## Improvements in this fork

- Accepts public Spotify links. It reads the public title with Spotify oEmbed
  and searches for the matching playable audio source.
- Fresh DFPWM decoder for every track. No additional lossy smoothing in the
  client. The optional self-hosted backend converts audio to mono 48 kHz DFPWM.
- Redesigned responsive UI with clearer playback state, queue, volume, and the
  live number of detected speakers.
- Direct YouTube links appear immediately and can be played while metadata is
  still loading in the background.
- Starts at CC: Tweaked's maximum supported speaker volume (`3.0`).
- Uses every connected speaker found on the wired peripheral network.
- Dispatches speaker calls concurrently with a table-based coroutine scheduler.
  Every speaker must report readiness before the next chunk is sent.
- No hardcoded speaker-count limit. Tested with up to 1,000 simulated speakers;
  actual capacity and audible synchronization depend on Minecraft, CC and lag.
- Fixed group per track: newly attached speakers join on the next track or via
  SAIDAS > REINICIAR GRUPO. Removal/timeouts stop the group with a named error.
- Redesigned Portuguese interface on a consistent 51x19 grid: full-width tabs,
  aligned controls, separate status/title rows, labeled volume, queue, editable
  search, output list and group restart. Other terminal sizes remain responsive.

## Other video sites

Direct raw mono 48 kHz `.dfpwm` URLs work without an additional backend.
Other HTTP(S) video URLs require the new [yt-dlp backend](backend/README.md).
Its source and setup instructions are included, but it is **not deployed**.
The default upstream server cannot gain new capabilities from this fork.
Without configuration, the player explains the missing backend instead of
searching YouTube for the entire external URL.

No tool supports every site: the extractor, login requirements, DRM, regional
restrictions and availability determine whether a video can be played.

## Spotify links

Paste a public `open.spotify.com` or `spotify.link` URL into Search. Spotify
audio is not downloaded or bypassed: the player obtains the public item title
through Spotify's oEmbed endpoint, then searches for a corresponding playable
source. Track links provide the most precise matches. Album and playlist links
currently search by their collection title rather than importing every track.

## Connecting multiple speakers

Speakers directly touching any of the computer's six faces are detected:
`top`, `bottom`, `left`, `right`, `front`, and `back`.

A speaker touching another speaker is **not** automatically connected. For
speakers farther away, use a Wired Modem on the computer, Networking Cable, and
a Wired Modem attached to every remote speaker. Right-click each modem so its
peripheral appears on the wired network. The player will then detect and use
all of them automatically.

Use one connection per physical speaker. A speaker exposed both directly and
through a wired modem may have two names: CC does not provide a universal
physical identity to merge aliases. Remove the duplicate connection or exclude
its name in the Lua shell:

```lua
settings.set("music.exclude_speakers", {left = true})
settings.save()
```

Restart music after changing this setting. Use only one player/computer per
speaker group: other running players can interfere with its audio buffers.

## How to use

1. Install the [CC: Tweaked](https://tweaked.cc/) mod to your world/server. Make sure you're using version 1.100.0 of the mod (released December 2021) or newer, or it won't work.
2. Craft an Advanced Computer and connect it to a speaker, or craft an Advanced Noisy Pocket Computer.
3. Run the installation command above.
4. Run the `music` command and enjoy your music.

## Troubleshooting
- No speakers listed: check direct connections or activate each wired modem.
- Speaker removed/busy/unresponsive: the group stops; check the named peripheral
  and use SAIDAS > REINICIAR GRUPO. This restarts the current song.
- "Module 'cc.audio.dfpwm' not found" error: Make sure you're using version 1.100.0 or newer of the CC: Tweaked mod (December 2021 or later). New audio features were added in this version, so it won't work in 1.99.X or below.

## Tests

```sh
python -m pip install lupa yt-dlp
python -m unittest discover -s tests -v
```

FFmpeg is also required. Tests exercise concurrent dispatch, buffer barriers,
busy speakers, timeouts, detach, UI rendering and an actual local media-to-DFPWM
conversion. No Minecraft playback or audible synchronization test was performed.

## How to self-host the original YouTube backend

> [!IMPORTANT]  
> Self-hosting is not required to use this program. You can use the GitHub
> installation command above.

The ComputerCraft program connects to a web server to download the music files. This server is hosted with Firebase Cloud Functions. The server uses two unofficial APIs on RapidAPI: one for searching YouTube and one for downloading the audio.

1. Download this repository to your computer into a folder.
2. Create an account for RapidAPI and sign up for the free tier of both of these APIs:
   - "YT-API" (used for search): [https://rapidapi.com/ytjar/api/yt-api](https://rapidapi.com/ytjar/api/yt-api)
   - "YouTube MP3" (used for downloading): [https://rapidapi.com/ytjar/api/youtube-mp36](https://rapidapi.com/ytjar/api/youtube-mp36)
3. If you sign up for both APIs on the same account, you will have a single RapidAPI key. Copy and paste it into the file `functions/index.js` where it says "YOUR API KEY HERE". Leave the quotes.
4. Paste your RapidAPI username into `functions/index.js` where it says "YOUR RAPIDAPI USERNAME HERE". Leave the quotes.
5. Sign up for Firebase and make a new project at [https://firebase.google.com/](https://firebase.google.com/). A billing account is required even for the free plan. The limits of the free plan should be plenty for most people.
6. Install Node.js version 20 from [https://nodejs.org/en/download/](https://nodejs.org/en/download/).
7. In your terminal, run `npm install -g firebase-tools` to install Firebase.
8. In your terminal, navigate inside the project folder. Run `firebase login` and follow the steps.
9. Run `firebase init functions` and follow the steps. Choose JavaScript. Don't choose to overwrite the `functions/index.js` or `functions/package.json` files when it asks you. Install the dependencies when prompted.
10. Run `cd functions` to go inside the `functions` directory and then run `npm install` to install more dependencies.
11. Run `cd ..` to go back and then run `firebase deploy` to deploy your new Cloud Function.
12. After the deployment is complete it will give you the Function URL. Copy that URL into the first line of `music.lua`.
