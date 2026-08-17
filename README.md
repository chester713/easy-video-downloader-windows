# Easy Video Downloader for Windows

An interactive Windows command-line app for `yt-dlp` and FFmpeg. Users paste a video URL and choose from a readable list of available resolutions, containers, video codecs, audio codecs, frame rates, and estimated file sizes. They never need to write a `yt-dlp` or FFmpeg command.

## Start the app

1. Download or copy this project folder to the Windows computer.
2. Double-click **Start Easy Video Downloader.cmd**.
3. On the first run, choose either:
   - **Use existing tools** and paste the folder containing `yt-dlp.exe` and `ffmpeg.exe`; or
   - **Install automatically** and choose where the app should install the latest stable versions.
4. Choose a download folder.
5. Paste a video URL, wait for the available formats to appear, and enter a format number.

The app remembers the selected tools and download folder in `%LOCALAPPDATA%\EasyVideoDownloader\settings.json`. Enter `S` at the URL prompt whenever you want to change them.

## Format choices

- **Best video + best audio** downloads separate high-quality streams when available and asks FFmpeg to merge them.
- **Best single file** chooses a source that already contains video and audio.
- Selecting a **video-only** source automatically adds the best available audio and merges it.
- Selecting an **audio-only** or **video+audio** source downloads that exact format.

Formats are specific to each website and video. A `?` in the Size column means the website did not report a reliable size before download.

## Automatic installation

The installer downloads:

- the latest stable Windows `yt-dlp.exe` from the official yt-dlp GitHub release;
- the latest stable FFmpeg release essentials ZIP from the Windows builds linked by the FFmpeg project.

Both downloads are checked against their published SHA-256 checksums before installation. The app keeps `yt-dlp.exe`, `ffmpeg.exe`, and `ffprobe.exe` together in the chosen installation folder and does not change the system `PATH`.

Automatic FFmpeg installation uses a 64-bit Windows build. The current builds target Windows 10 or newer.

## Troubleshooting

- If a site rejects a URL, confirm the URL opens normally in a browser and try again. Some protected, paid, or login-only videos require authentication that this first version does not collect.
- If formats stop appearing for sites that previously worked, enter `S` and run automatic setup again to refresh the tools.
- Downloads are intentionally limited to one video rather than an entire playlist.
- Only download media when you have permission and doing so complies with the website's terms and applicable law.

## Developer check

Run the built-in checks without opening the interactive app:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\EasyVideoDownloader.ps1 -SelfTest
```
