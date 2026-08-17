# Easy Video Downloader for Windows

Easy Video Downloader is an interactive command-line interface for [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [FFmpeg](https://ffmpeg.org/). It helps Windows users download online videos without having to learn or type yt-dlp and FFmpeg commands.

Paste a video URL, review the formats offered by the website, and choose an option by number. The app handles the download and, when necessary, uses FFmpeg to combine separate video and audio streams.

> Only download media that you have permission to save. You are responsible for following the website's terms and applicable law.

## Features

- Guided first-run setup
- Uses an existing yt-dlp and FFmpeg installation, or installs both automatically
- Downloads the latest stable Windows releases during automatic setup
- Verifies downloaded tools with their published SHA-256 checksums
- Detects the formats available for each video
- Shows format ID, resolution, frame rate, container, video codec, audio codec, and estimated size
- Includes **Best video + best audio** and **Best single file** choices
- Automatically adds the best audio when a video-only format is selected
- Uses FFmpeg to merge separate streams
- Remembers tool locations and the preferred download folder
- Requires no Python installation and does not modify the Windows `PATH`

## Requirements

- Windows 10 or Windows 11, 64-bit
- Windows PowerShell 5.1 or newer
- An internet connection
- Permission to download the selected media

If you use automatic setup, keep at least 500 MB of disk space free during installation. The exact download and installed sizes vary between releases.

## Installation

The app is portable: there is no traditional Windows installer and no system-wide configuration is required.

### Option 1: Download the project as a ZIP

1. Open the [project repository](https://github.com/chester713/easy-video-downloader-windows).
2. Select **Code**, then **Download ZIP**.
3. Extract the ZIP to a permanent folder, such as `C:\Tools\EasyVideoDownloader`.
4. Open the extracted folder.
5. Double-click **Start Easy Video Downloader.cmd**.

Do not run the launcher from inside the ZIP preview. Extract all files first so the launcher can find `EasyVideoDownloader.ps1` beside it.

### Option 2: Clone with Git

```powershell
git clone https://github.com/chester713/easy-video-downloader-windows.git
cd easy-video-downloader-windows
```

Then double-click **Start Easy Video Downloader.cmd**, or start it from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\EasyVideoDownloader.ps1
```

## First-run setup

The app offers two setup methods the first time it starts.

### Use tools that are already installed

Choose option `1`, then paste the directory containing `yt-dlp.exe` and `ffmpeg.exe`. The app checks the selected directory and its subdirectories, including common `bin` folders.

If the two programs are stored in different locations, the app asks for the missing program separately. Both executables are tested before their locations are saved.

### Install the tools automatically

Choose option `2`, then press Enter to accept the suggested installation directory or paste another directory.

The app downloads:

- the latest stable `yt-dlp.exe` from the official yt-dlp GitHub release;
- the latest stable FFmpeg essentials build for Windows from Gyan's builds, which are linked from the FFmpeg website.

The published SHA-256 checksum for each download is checked before anything is installed. `yt-dlp.exe`, `ffmpeg.exe`, and `ffprobe.exe` are placed together in the selected directory. Temporary installation files are removed afterward.

Finally, select where completed videos should be saved. Press Enter to use the normal Windows `Downloads` folder.

## How to use the app

1. Start **Start Easy Video Downloader.cmd**.
2. Paste the complete `http://` or `https://` address of a video.
3. Wait while yt-dlp reads the video information and available formats.
4. Review the displayed format table.
5. Enter the number of the desired format.
6. Wait for the download and any required FFmpeg merge to finish.
7. Choose whether to download another video.

The downloaded filename follows this pattern:

```text
Video title [video-id].extension
```

The title is shortened when necessary to remain safe for Windows filenames.

### Format choices

The first two choices are always convenience options:

| Choice | Behaviour |
| --- | --- |
| Best video + best audio | Downloads the best video-only and audio-only streams and merges them. If separate streams are unavailable, it falls back to the best combined format. |
| Best single file | Downloads the best source that already contains both video and audio. This can be more convenient but may offer a lower maximum resolution. |

The remaining rows represent formats reported by the website:

- **Video+Audio** downloads that exact combined format.
- **Video only** downloads the selected video format, adds the best available audio, and merges them.
- **Audio only** downloads that exact audio format.

A `?` in the Size column means that the website did not provide a reliable size in advance. The actual download can therefore be larger or smaller.

### Controls

| Input | Location | Action |
| --- | --- | --- |
| `S` | Video URL prompt | Run setup again to change or refresh the tool installation and download folder |
| `Q` | Video URL prompt | Close the app |
| `C` | Format selection prompt | Cancel the current video and return to the URL prompt |

## Saved settings

The selected paths are stored in:

```text
%LOCALAPPDATA%\EasyVideoDownloader\settings.json
```

The file contains only local program and download-directory paths. It does not contain passwords, browser cookies, or website credentials.

If a saved executable is moved or removed, the app detects the problem and starts setup again.

## Updating

### Update yt-dlp and FFmpeg

Enter `S` at the video URL prompt, choose automatic setup, and select the existing tools directory. The downloaded files are checksum-verified before replacing the older copies.

### Update this project

If the project was cloned with Git, run:

```powershell
git pull
```

If it was downloaded as a ZIP, download and extract the newest ZIP from GitHub. Keep the existing `%LOCALAPPDATA%\EasyVideoDownloader\settings.json` file if you want the app to continue using the saved paths.

## Troubleshooting

### The window closes immediately

Start the app from PowerShell so the full error remains visible:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\EasyVideoDownloader.ps1
```

### A URL cannot be read

- Confirm that the complete URL opens in a normal browser.
- Confirm that the computer is connected to the internet.
- Enter `S` and use automatic setup to refresh yt-dlp.
- The current app does not collect browser cookies or account credentials, so login-only, paid, age-restricted, or otherwise protected media may not work.
- Website changes can temporarily break yt-dlp support until yt-dlp is updated.

### A selected format has no sound

Rows marked **Video only** are automatically paired with the best audio stream. If merging fails, confirm that FFmpeg still exists at the saved location, then enter `S` to repair or refresh the installation.

### Antivirus or Windows blocks a downloaded tool

Automatic setup retrieves the executables over HTTPS from the sources listed above and validates their SHA-256 checksums. Do not bypass a security warning you do not understand. Review the source URLs and scan the files according to your organisation's security policy.

## Current limitations

- The app downloads one video at a time and deliberately disables playlist downloads.
- There is no graphical desktop interface; interaction happens in a guided terminal window.
- Browser-cookie and account-login workflows are not currently included.
- Available formats, codecs, and estimated sizes depend entirely on information supplied by the source website.
- DRM-protected media is not supported.

## Project files

| File | Purpose |
| --- | --- |
| `EasyVideoDownloader.ps1` | Main PowerShell application, setup workflow, format browser, and downloader |
| `Start Easy Video Downloader.cmd` | Double-clickable Windows launcher |
| `README.md` | Installation and usage documentation |

## Developer check

Run the built-in tests without opening the interactive workflow:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\EasyVideoDownloader.ps1 -SelfTest
```

The checks cover URL validation, format conversion, video-only audio pairing, size formatting, and filtering of unsupported storyboard entries.

## Third-party software

This project is a wrapper around independently maintained software:

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [FFmpeg](https://ffmpeg.org/)
- [Gyan FFmpeg builds for Windows](https://www.gyan.dev/ffmpeg/builds/)

Those projects and downloaded binaries are governed by their respective licenses.
