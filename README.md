# ComputerCraft Streaming Music — Enhanced Fork

An improved music player for Minecraft computers running CC: Tweaked.

**Version:** 2.3

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

- Redesigned responsive UI with clearer playback state, queue, volume, and the
  live number of detected speakers.
- Direct YouTube links appear immediately and can be played while metadata is
  still loading in the background.
- Starts at CC: Tweaked's maximum supported speaker volume (`3.0`).
- Uses every connected speaker found on the wired peripheral network.
- Keeps large speaker arrays synchronized without creating one coroutine per
  speaker or silently dropping chunks when one speaker is busy.
- Detects speakers again during playback, supporting network changes.

## Connecting multiple speakers

Speakers directly touching any of the computer's six faces are detected:
`top`, `bottom`, `left`, `right`, `front`, and `back`.

A speaker touching another speaker is **not** automatically connected. For
speakers farther away, use a Wired Modem on the computer, Networking Cable, and
a Wired Modem attached to every remote speaker. Right-click each modem so its
peripheral appears on the wired network. The player will then detect and use
all of them automatically.

## How to use

1. Install the [CC: Tweaked](https://tweaked.cc/) mod to your world/server. Make sure you're using version 1.100.0 of the mod (released December 2021) or newer, or it won't work.
2. Craft an Advanced Computer and connect it to a speaker, or craft an Advanced Noisy Pocket Computer.
3. Run the installation command above.
4. Run the `music` command and enjoy your music.

## Troubleshooting
- "No speakers attached" when using an Advanced Noisy Pocket Computer: Restart your Minecraft game. If that doesn't work, restart the server.
- "Module 'cc.audio.dfpwm' not found" error: Make sure you're using version 1.100.0 or newer of the CC: Tweaked mod (December 2021 or later). New audio features were added in this version, so it won't work in 1.99.X or below.

## How to self-host

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
