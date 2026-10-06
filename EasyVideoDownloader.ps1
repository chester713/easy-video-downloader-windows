[CmdletBinding()]
param(
    [switch]$SelfTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AppName = 'Easy Video Downloader'
$script:ConfigDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'EasyVideoDownloader'
$script:ConfigPath = Join-Path $script:ConfigDirectory 'settings.json'
$script:YtDlpDownloadUrl = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
$script:YtDlpChecksumsUrl = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS'
$script:FfmpegDownloadUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
$script:FfmpegChecksumUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip.sha256'

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch {
    # The app remains usable if the host does not permit changing its encoding.
}

function Write-Title {
    param([string]$Text)

    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
    Write-Host ('  ' + $Text) -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
}

function Write-Status {
    param(
        [string]$Text,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Kind = 'Info'
    )

    $color = switch ($Kind) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'Gray' }
    }

    Write-Host $Text -ForegroundColor $color
}

function Read-RequiredInput {
    param([string]$Prompt)

    while ($true) {
        $value = (Read-Host $Prompt).Trim()
        if ($value) {
            return $value
        }
        Write-Status 'Please enter a value.' 'Warning'
    }
}

function ConvertTo-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $cleanPath = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"').Trim("'"))
    return (Remove-TrailingSeparator ([IO.Path]::GetFullPath($cleanPath)))
}

function Remove-TrailingSeparator {
    param([Parameter(Mandatory = $true)][string]$Path)

    # Windows PowerShell 5.1 passes a quoted argument such as "C:\My Videos\"
    # to native programs with the final \" read as an escaped quote, which
    # corrupts every argument after it. Drive roots such as D:\ keep their
    # separator because they never contain spaces and need it to stay valid.
    $root = [IO.Path]::GetPathRoot($Path)
    if ($root -and ($Path.Length -le $root.Length)) {
        return $Path
    }
    return $Path.TrimEnd([char[]]@('\', '/'))
}

function Find-Executable {
    param(
        [Parameter(Mandatory = $true)][string]$StartPath,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    try {
        $normalized = ConvertTo-NormalizedPath $StartPath
    } catch {
        return $null
    }

    if (Test-Path -LiteralPath $normalized -PathType Leaf) {
        if ([IO.Path]::GetFileName($normalized) -ieq $FileName) {
            return $normalized
        }
        return $null
    }

    if (-not (Test-Path -LiteralPath $normalized -PathType Container)) {
        return $null
    }

    $directCandidates = @(
        (Join-Path $normalized $FileName),
        (Join-Path (Join-Path $normalized 'bin') $FileName)
    )

    foreach ($candidate in $directCandidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }

    $match = Get-ChildItem -LiteralPath $normalized -Filter $FileName -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($match) {
        return $match.FullName
    }

    return $null
}

function Test-Executable {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Arguments = @('--version')
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $null = & $Path @Arguments 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    } finally {
        $ErrorActionPreference = $oldPreference
    }
}

function Test-ToolConfiguration {
    param($Configuration)

    if (-not $Configuration) {
        return $false
    }

    $properties = @($Configuration.PSObject.Properties.Name)
    if (($properties -notcontains 'YtDlpPath') -or ($properties -notcontains 'FfmpegPath')) {
        return $false
    }
    if (-not $Configuration.YtDlpPath -or -not $Configuration.FfmpegPath) {
        return $false
    }

    return ((Test-Executable $Configuration.YtDlpPath) -and
            (Test-Executable $Configuration.FfmpegPath -Arguments @('-version')))
}

function Get-SavedConfiguration {
    if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json)
    } catch {
        Write-Status 'The saved settings could not be read. Setup will run again.' 'Warning'
        return $null
    }
}

function Save-Configuration {
    param(
        [Parameter(Mandatory = $true)][string]$YtDlpPath,
        [Parameter(Mandatory = $true)][string]$FfmpegPath,
        [Parameter(Mandatory = $true)][string]$DownloadDirectory
    )

    if (-not (Test-Path -LiteralPath $script:ConfigDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $script:ConfigDirectory -Force
    }

    [pscustomobject]@{
        YtDlpPath       = [IO.Path]::GetFullPath($YtDlpPath)
        FfmpegPath      = [IO.Path]::GetFullPath($FfmpegPath)
        DownloadDirectory = Remove-TrailingSeparator ([IO.Path]::GetFullPath($DownloadDirectory))
    } | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
}

function Get-DownloadDirectory {
    param([string]$SavedDirectory)

    $defaultDirectory = if ($SavedDirectory) {
        $SavedDirectory
    } else {
        Join-Path $env:USERPROFILE 'Downloads'
    }

    # Keep asking until a usable folder is chosen, so a typo or a declined
    # prompt never closes the app or forces the tools to be set up again.
    while ($true) {
        Write-Host ''
        Write-Host "Download folder (press Enter to use: $defaultDirectory)"
        $entered = (Read-Host 'Folder').Trim()

        try {
            $selected = if ($entered) {
                ConvertTo-NormalizedPath $entered
            } else {
                ConvertTo-NormalizedPath $defaultDirectory
            }
        } catch {
            Write-Status 'That is not a valid folder path. Please try again.' 'Warning'
            continue
        }

        if (-not (Test-Path -LiteralPath $selected -PathType Container)) {
            if (Test-Path -LiteralPath $selected) {
                Write-Status 'That path is a file, not a folder. Please choose a folder.' 'Warning'
                continue
            }
            $answer = (Read-Host 'That folder does not exist. Create it? [Y/n]').Trim()
            if (($answer -ne '') -and ($answer -notmatch '^(?i)y(es)?$')) {
                Write-Status 'Choose another download folder.' 'Warning'
                continue
            }
            try {
                $null = [IO.Directory]::CreateDirectory($selected)
            } catch {
                Write-Status "The folder could not be created: $($_.Exception.Message)" 'Warning'
                continue
            }
        }

        return $selected
    }
}

function Get-ExistingTools {
    Write-Host ''
    Write-Host 'Paste the folder that contains yt-dlp.exe and ffmpeg.exe.'
    Write-Host 'They may be inside subfolders such as bin.' -ForegroundColor DarkGray
    $directory = Read-RequiredInput 'Tools folder'

    Write-Status 'Looking for the programs...' 'Info'
    $ytDlpPath = Find-Executable -StartPath $directory -FileName 'yt-dlp.exe'
    $ffmpegPath = Find-Executable -StartPath $directory -FileName 'ffmpeg.exe'

    if (-not $ytDlpPath) {
        Write-Status 'yt-dlp.exe was not found there.' 'Warning'
        $ytDirectory = Read-RequiredInput 'Paste the folder or full path for yt-dlp.exe'
        $ytDlpPath = Find-Executable -StartPath $ytDirectory -FileName 'yt-dlp.exe'
    }

    if (-not $ffmpegPath) {
        Write-Status 'ffmpeg.exe was not found there.' 'Warning'
        $ffmpegDirectory = Read-RequiredInput 'Paste the folder or full path for ffmpeg.exe'
        $ffmpegPath = Find-Executable -StartPath $ffmpegDirectory -FileName 'ffmpeg.exe'
    }

    if (-not $ytDlpPath) {
        throw 'yt-dlp.exe could not be found.'
    }
    if (-not $ffmpegPath) {
        throw 'ffmpeg.exe could not be found.'
    }
    if (-not (Test-Executable $ytDlpPath)) {
        throw "yt-dlp could not run: $ytDlpPath"
    }
    if (-not (Test-Executable $ffmpegPath -Arguments @('-version'))) {
        throw "FFmpeg could not run: $ffmpegPath"
    }

    return [pscustomobject]@{
        YtDlpPath  = $ytDlpPath
        FfmpegPath = $ffmpegPath
    }
}

function Test-DownloadedFileHash {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$ExpectedHash
    )

    $actualHash = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash
    if ($actualHash -ine $ExpectedHash) {
        throw "Checksum check failed for $([IO.Path]::GetFileName($FilePath)). The download may be incomplete or corrupted, so it was not installed. Please try again."
    }
}

function Remove-AppTempDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $resolvedTarget = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $expectedPrefix = Join-Path $resolvedTemp 'EasyVideoDownloader-'

    if (($resolvedTarget -notlike ($expectedPrefix + '*')) -or
        ([IO.Path]::GetFileName($resolvedTarget) -notmatch '^EasyVideoDownloader-[0-9a-f-]{36}$')) {
        throw "Refusing to remove an unexpected temporary path: $resolvedTarget"
    }

    if (Test-Path -LiteralPath $resolvedTarget -PathType Container) {
        Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
    }
}

function Install-Tools {
    $defaultDirectory = Join-Path $script:ConfigDirectory 'tools'
    Write-Host ''
    Write-Host "Installation folder (press Enter to use: $defaultDirectory)"
    $entered = (Read-Host 'Folder').Trim()
    $installDirectory = if ($entered) { ConvertTo-NormalizedPath $entered } else { $defaultDirectory }

    if (-not (Test-Path -LiteralPath $installDirectory -PathType Container)) {
        $null = [IO.Directory]::CreateDirectory($installDirectory)
    }

    $tempDirectory = Join-Path ([IO.Path]::GetTempPath()) ('EasyVideoDownloader-' + [guid]::NewGuid().ToString())
    $null = New-Item -ItemType Directory -Path $tempDirectory
    $ytDlpDownload = Join-Path $tempDirectory 'yt-dlp.exe'
    $ytDlpChecksums = Join-Path $tempDirectory 'SHA2-256SUMS'
    $ffmpegArchive = Join-Path $tempDirectory 'ffmpeg-release-essentials.zip'
    $ffmpegChecksum = Join-Path $tempDirectory 'ffmpeg-release-essentials.zip.sha256'
    $ffmpegExtracted = Join-Path $tempDirectory 'ffmpeg'

    $oldProgressPreference = $ProgressPreference
    try {
        # Add TLS 1.2 for Windows PowerShell 5.1 without disabling any newer
        # protocol the system already allows.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'

        Write-Status 'Downloading the latest stable yt-dlp release...' 'Info'
        Invoke-WebRequest -UseBasicParsing -Uri $script:YtDlpDownloadUrl -OutFile $ytDlpDownload
        Invoke-WebRequest -UseBasicParsing -Uri $script:YtDlpChecksumsUrl -OutFile $ytDlpChecksums
        $ytChecksumText = Get-Content -LiteralPath $ytDlpChecksums -Raw
        $ytMatch = [regex]::Match($ytChecksumText, '(?im)^([0-9a-f]{64})\s+\*?yt-dlp\.exe\s*$')
        if (-not $ytMatch.Success) {
            throw 'The official yt-dlp checksum could not be read.'
        }
        Test-DownloadedFileHash -FilePath $ytDlpDownload -ExpectedHash $ytMatch.Groups[1].Value

        Write-Status 'Downloading the latest stable FFmpeg essentials release...' 'Info'
        Write-Host 'This download is approximately 100 MB.' -ForegroundColor DarkGray
        Invoke-WebRequest -UseBasicParsing -Uri $script:FfmpegDownloadUrl -OutFile $ffmpegArchive
        Invoke-WebRequest -UseBasicParsing -Uri $script:FfmpegChecksumUrl -OutFile $ffmpegChecksum
        $ffmpegChecksumText = Get-Content -LiteralPath $ffmpegChecksum -Raw
        $ffmpegMatch = [regex]::Match($ffmpegChecksumText, '(?i)([0-9a-f]{64})')
        if (-not $ffmpegMatch.Success) {
            throw 'The FFmpeg checksum could not be read.'
        }
        Test-DownloadedFileHash -FilePath $ffmpegArchive -ExpectedHash $ffmpegMatch.Groups[1].Value

        Write-Status 'Installing the verified downloads...' 'Info'
        Expand-Archive -LiteralPath $ffmpegArchive -DestinationPath $ffmpegExtracted -Force
        $downloadedFfmpeg = Get-ChildItem -LiteralPath $ffmpegExtracted -Filter 'ffmpeg.exe' -File -Recurse |
            Select-Object -First 1
        $downloadedFfprobe = Get-ChildItem -LiteralPath $ffmpegExtracted -Filter 'ffprobe.exe' -File -Recurse |
            Select-Object -First 1
        if (-not $downloadedFfmpeg) {
            throw 'ffmpeg.exe was not present in the downloaded archive.'
        }

        $ytDlpPath = Join-Path $installDirectory 'yt-dlp.exe'
        $ffmpegPath = Join-Path $installDirectory 'ffmpeg.exe'
        Copy-Item -LiteralPath $ytDlpDownload -Destination $ytDlpPath -Force
        Copy-Item -LiteralPath $downloadedFfmpeg.FullName -Destination $ffmpegPath -Force
        if ($downloadedFfprobe) {
            Copy-Item -LiteralPath $downloadedFfprobe.FullName -Destination (Join-Path $installDirectory 'ffprobe.exe') -Force
        }

        if (-not (Test-Executable $ytDlpPath)) {
            throw 'The installed yt-dlp program did not start correctly.'
        }
        if (-not (Test-Executable $ffmpegPath -Arguments @('-version'))) {
            throw 'The installed FFmpeg program did not start correctly.'
        }

        Write-Status "Installation complete: $installDirectory" 'Success'
        return [pscustomobject]@{
            YtDlpPath  = $ytDlpPath
            FfmpegPath = $ffmpegPath
        }
    } finally {
        $ProgressPreference = $oldProgressPreference
        # Antivirus software often keeps a lock on a freshly downloaded .exe for
        # a few seconds. Cleanup is best-effort so it never hides the real
        # result of the installation.
        try {
            Remove-AppTempDirectory $tempDirectory
        } catch {
            Write-Status "Temporary files could not be removed and can be deleted later: $tempDirectory" 'Warning'
        }
    }
}

function Initialize-Application {
    param([switch]$ForceSetup)

    Write-Title "$script:AppName - Setup"
    $saved = if ($ForceSetup) { $null } else { Get-SavedConfiguration }
    if ($saved -and (Test-ToolConfiguration $saved)) {
        Write-Status 'Saved yt-dlp and FFmpeg installation found.' 'Success'
        $savedDownloadDirectory = $null
        if (@($saved.PSObject.Properties.Name) -contains 'DownloadDirectory') {
            $savedDownloadDirectory = $saved.DownloadDirectory
        }
        return (Complete-Configuration -YtDlpPath $saved.YtDlpPath -FfmpegPath $saved.FfmpegPath -SavedDownloadDirectory $savedDownloadDirectory)
    }

    if ($saved) {
        Write-Status 'The saved tools are missing or cannot run. Please set them up again.' 'Warning'
    }

    $tools = $null
    while (-not $tools) {
        Write-Host ''
        Write-Host '[1] Use yt-dlp and FFmpeg already installed on this computer'
        Write-Host '[2] Automatically download and install the latest stable versions'
        Write-Host '[Q] Quit'
        $choice = (Read-Host 'Choose an option').Trim()

        # An if/elseif chain is used instead of switch: inside a switch,
        # "continue" and "break" act on the switch, not on this loop.
        try {
            if ($choice -eq '1') {
                $tools = Get-ExistingTools
            } elseif ($choice -eq '2') {
                $tools = Install-Tools
            } elseif ($choice -match '^(?i)q$') {
                return $null
            } else {
                Write-Status 'Choose 1, 2, or Q.' 'Warning'
            }
        } catch {
            $tools = $null
            Write-Status $_.Exception.Message 'Error'
            Write-Host 'You can try again or choose another setup method.' -ForegroundColor DarkGray
        }
    }

    # The download folder is chosen after the tools are ready, outside the
    # retry loop above, so a folder problem never repeats the tool setup.
    return (Complete-Configuration -YtDlpPath $tools.YtDlpPath -FfmpegPath $tools.FfmpegPath -SavedDownloadDirectory $null)
}

function Complete-Configuration {
    param(
        [Parameter(Mandatory = $true)][string]$YtDlpPath,
        [Parameter(Mandatory = $true)][string]$FfmpegPath,
        [string]$SavedDownloadDirectory
    )

    $downloadDirectory = Get-DownloadDirectory $SavedDownloadDirectory
    try {
        Save-Configuration -YtDlpPath $YtDlpPath -FfmpegPath $FfmpegPath -DownloadDirectory $downloadDirectory
    } catch {
        Write-Status "Settings could not be saved, so setup will run again next time: $($_.Exception.Message)" 'Warning'
    }

    return [pscustomobject]@{
        YtDlpPath         = $YtDlpPath
        FfmpegPath        = $FfmpegPath
        DownloadDirectory = $downloadDirectory
    }
}

function Test-VideoUrl {
    param([string]$Url)

    $parsed = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$parsed)) {
        return $false
    }
    return (($parsed.Scheme -eq 'http') -or ($parsed.Scheme -eq 'https'))
}

function Get-VideoInformation {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)][string]$Url
    )

    Write-Status 'Checking the video and detecting available formats...' 'Info'
    $ffmpegDirectory = Remove-TrailingSeparator (Split-Path -Parent $Configuration.FfmpegPath)
    $arguments = @(
        '--dump-single-json',
        '--skip-download',
        '--no-warnings',
        '--no-playlist',
        '--encoding', 'utf-8',
        '--ffmpeg-location', $ffmpegDirectory,
        '--', $Url
    )

    $oldPreference = $ErrorActionPreference
    try {
        # Windows PowerShell can treat text written by native programs to stderr
        # as a PowerShell error even when the program handles it correctly.
        $ErrorActionPreference = 'Continue'
        $jsonLines = & $Configuration.YtDlpPath @arguments
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($exitCode -ne 0) {
        throw 'yt-dlp could not read this URL. Check the address, your connection, and whether the site is supported.'
    }

    $json = ($jsonLines -join [Environment]::NewLine)
    if (-not $json) {
        throw 'No video information was returned.'
    }
    return ($json | ConvertFrom-Json)
}

function Format-ByteSize {
    param($Bytes)

    if (($null -eq $Bytes) -or ([double]$Bytes -le 0)) {
        return '?'
    }

    $size = [double]$Bytes
    if ($size -ge 1GB) { return ('{0:N1} GB' -f ($size / 1GB)) }
    if ($size -ge 1MB) { return ('{0:N1} MB' -f ($size / 1MB)) }
    if ($size -ge 1KB) { return ('{0:N1} KB' -f ($size / 1KB)) }
    return ('{0:N0} B' -f $size)
}

function Limit-Text {
    param(
        $Text,
        [int]$MaximumLength
    )

    $value = if ($null -eq $Text) { '-' } else { [string]$Text }
    if (-not $value) { $value = '-' }
    if ($value.Length -le $MaximumLength) { return $value }
    if ($MaximumLength -le 1) { return $value.Substring(0, $MaximumLength) }
    return ($value.Substring(0, $MaximumLength - 1) + [char]0x2026)
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }
    return $null
}

function Get-CodecState {
    param($Codec)

    if (($null -eq $Codec) -or ([string]$Codec -eq '')) { return 'unknown' }
    if ([string]$Codec -eq 'none') { return 'none' }
    return 'known'
}

function Format-Codec {
    param(
        [string]$State,
        $Codec
    )

    switch ($State) {
        'known'   { return [string]$Codec }
        'unknown' { return '?' }
        default   { return '-' }
    }
}

function Get-FormatChoices {
    param([Parameter(Mandatory = $true)]$VideoInformation)

    $choices = New-Object System.Collections.ArrayList
    $null = $choices.Add([pscustomobject]@{
        Number     = 1
        Id         = 'auto'
        Type       = 'Recommended'
        Resolution = 'Best'
        Fps        = '-'
        Container  = 'auto'
        VideoCodec = 'best'
        AudioCodec = 'best'
        Size       = '?'
        Note       = 'Best video + best audio; automatically merged'
        Selector   = 'bestvideo+bestaudio/best'
    })
    $null = $choices.Add([pscustomobject]@{
        Number     = 2
        Id         = 'best'
        Type       = 'Single file'
        Resolution = 'Best'
        Fps        = '-'
        Container  = 'auto'
        VideoCodec = 'best'
        AudioCodec = 'best'
        Size       = '?'
        Note       = 'Best source that already contains video and audio'
        Selector   = 'best'
    })

    $nextNumber = 3
    $formats = Get-PropertyValue $VideoInformation 'formats'
    if ($null -eq $formats) { $formats = @() }
    foreach ($format in @($formats)) {
        if ($null -eq $format) { continue }
        $formatId = Get-PropertyValue $format 'format_id'
        $protocol = Get-PropertyValue $format 'protocol'
        $extension = Get-PropertyValue $format 'ext'
        $videoCodec = Get-PropertyValue $format 'vcodec'
        $audioCodec = Get-PropertyValue $format 'acodec'
        if (-not $formatId) { continue }
        if (($protocol -eq 'mhtml') -or ($extension -eq 'mhtml')) { continue }

        # yt-dlp reports a codec as 'none' when the stream is absent and as
        # null when the site simply did not say. Unknown is not the same as
        # absent, so those formats are kept rather than hidden.
        $videoState = Get-CodecState $videoCodec
        $audioState = Get-CodecState $audioCodec
        if (($videoState -eq 'none') -and ($audioState -eq 'none')) { continue }
        $hasVideo = $videoState -ne 'none'
        $hasAudio = $audioState -ne 'none'
        $codecsUnknown = ($videoState -eq 'unknown') -or ($audioState -eq 'unknown')

        $type = if ($hasVideo -and -not $hasAudio) {
            'Video only'
        } elseif ($hasAudio -and -not $hasVideo) {
            'Audio only'
        } elseif ($codecsUnknown) {
            'Unknown'
        } else {
            'Video+Audio'
        }

        $resolution = '-'
        if ($hasVideo) {
            $width = Get-PropertyValue $format 'width'
            $height = Get-PropertyValue $format 'height'
            $reportedResolution = Get-PropertyValue $format 'resolution'
            if ($width -and $height) {
                $resolution = "${width}x${height}"
            } elseif ($reportedResolution) {
                $resolution = [string]$reportedResolution
            } elseif ($height) {
                $resolution = "${height}p"
            }
        }

        $fileSize = Get-PropertyValue $format 'filesize'
        $approximateFileSize = Get-PropertyValue $format 'filesize_approx'
        $sizeValue = if ($fileSize) { $fileSize } else { $approximateFileSize }
        $noteParts = New-Object System.Collections.ArrayList
        $formatNote = Get-PropertyValue $format 'format_note'
        $dynamicRange = Get-PropertyValue $format 'dynamic_range'
        $language = Get-PropertyValue $format 'language'
        $framesPerSecond = Get-PropertyValue $format 'fps'
        if ($formatNote) { $null = $noteParts.Add([string]$formatNote) }
        if ($dynamicRange -and ($dynamicRange -ne 'SDR')) { $null = $noteParts.Add([string]$dynamicRange) }
        if ($language) { $null = $noteParts.Add([string]$language) }
        if ($hasVideo -and -not $hasAudio) { $null = $noteParts.Add('adds best audio') }
        if ($type -eq 'Unknown') { $null = $noteParts.Add('site did not report codecs') }

        $selector = if ($hasVideo -and -not $hasAudio) {
            "${formatId}+bestaudio/${formatId}"
        } else {
            [string]$formatId
        }

        $null = $choices.Add([pscustomobject]@{
            Number     = $nextNumber
            Id         = [string]$formatId
            Type       = $type
            Resolution = $resolution
            Fps        = if ($framesPerSecond) { [string]$framesPerSecond } else { '-' }
            Container  = if ($extension) { [string]$extension } else { '-' }
            VideoCodec = Format-Codec $videoState $videoCodec
            AudioCodec = Format-Codec $audioState $audioCodec
            Size       = Format-ByteSize $sizeValue
            Note       = ($noteParts -join ', ')
            Selector   = $selector
        })
        $nextNumber++
    }

    return @($choices)
}

function Show-FormatChoices {
    param([Parameter(Mandatory = $true)][array]$Choices)

    Write-Host ''
    Write-Host ('{0,3}  {1,-10} {2,-13} {3,-11} {4,-5} {5,-5} {6,-12} {7,-12} {8,10}  {9}' -f
        '#', 'ID', 'Type', 'Resolution', 'FPS', 'Ext', 'Video codec', 'Audio codec', 'Size', 'Notes') -ForegroundColor Cyan
    Write-Host ('-' * 116) -ForegroundColor DarkGray

    foreach ($choice in $Choices) {
        Write-Host ('{0,3}  {1,-10} {2,-13} {3,-11} {4,-5} {5,-5} {6,-12} {7,-12} {8,10}  {9}' -f
            $choice.Number,
            (Limit-Text $choice.Id 10),
            (Limit-Text $choice.Type 13),
            (Limit-Text $choice.Resolution 11),
            (Limit-Text $choice.Fps 5),
            (Limit-Text $choice.Container 5),
            (Limit-Text $choice.VideoCodec 12),
            (Limit-Text $choice.AudioCodec 12),
            (Limit-Text $choice.Size 10),
            $choice.Note)
    }
}

function Select-FormatChoice {
    param([Parameter(Mandatory = $true)][array]$Choices)

    while ($true) {
        $entered = (Read-Host 'Choose a format number (or C to cancel)').Trim()
        if ($entered -match '^(?i)c$') {
            return $null
        }

        $number = 0
        if ([int]::TryParse($entered, [ref]$number)) {
            $match = @($Choices | Where-Object { $_.Number -eq $number })
            if ($match.Count -eq 1) {
                return $match[0]
            }
        }
        Write-Status 'Enter one of the format numbers shown above.' 'Warning'
    }
}

function Get-FormatDescription {
    param([Parameter(Mandatory = $true)]$FormatChoice)

    # The two convenience choices are described fully by their note.
    if (@('auto', 'best') -contains $FormatChoice.Id) {
        return $FormatChoice.Note
    }

    $parts = New-Object System.Collections.ArrayList
    $null = $parts.Add("#$($FormatChoice.Number) $($FormatChoice.Type)")
    if ($FormatChoice.Resolution -and ($FormatChoice.Resolution -ne '-')) { $null = $parts.Add($FormatChoice.Resolution) }
    if ($FormatChoice.Container -and ($FormatChoice.Container -ne '-')) { $null = $parts.Add($FormatChoice.Container) }
    $null = $parts.Add("ID $($FormatChoice.Id)")
    $description = $parts -join ', '
    if ($FormatChoice.Note) { $description += " ($($FormatChoice.Note))" }
    return $description
}

function Start-VideoDownload {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)]$FormatChoice
    )

    $ffmpegDirectory = Remove-TrailingSeparator (Split-Path -Parent $Configuration.FfmpegPath)
    # Settings saved by older versions may still end with a backslash.
    $downloadDirectory = Remove-TrailingSeparator $Configuration.DownloadDirectory
    $outputTemplate = '%(title).180B [%(id)s].%(ext)s'
    $arguments = @(
        '--no-playlist',
        '--newline',
        '--windows-filenames',
        '--ffmpeg-location', $ffmpegDirectory,
        '--paths', $downloadDirectory,
        '--output', $outputTemplate,
        '--format', $FormatChoice.Selector,
        '--', $Url
    )

    Write-Title 'Downloading'
    Write-Host "Format: $(Get-FormatDescription $FormatChoice)"
    Write-Host "Saving to: $downloadDirectory"
    Write-Host ''
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Configuration.YtDlpPath @arguments
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($exitCode -ne 0) {
        throw "The download did not finish successfully (yt-dlp exit code $exitCode)."
    }
    Write-Status 'Download complete.' 'Success'
}

function Invoke-SelfTest {
    $fakeInformation = [pscustomobject]@{
        formats = @(
            [pscustomobject]@{ format_id = '137'; ext = 'mp4'; width = 1920; height = 1080; fps = 30; vcodec = 'avc1.640028'; acodec = 'none'; filesize = 10485760; protocol = 'https'; format_note = '1080p'; dynamic_range = 'SDR'; language = $null },
            [pscustomobject]@{ format_id = '140'; ext = 'm4a'; width = $null; height = $null; fps = $null; vcodec = 'none'; acodec = 'mp4a.40.2'; filesize_approx = 1048576; protocol = 'https'; format_note = 'medium'; dynamic_range = $null; language = 'en' },
            [pscustomobject]@{ format_id = 'sb0'; ext = 'mhtml'; width = 160; height = 90; fps = $null; vcodec = 'none'; acodec = 'none'; filesize = $null; protocol = 'mhtml'; format_note = 'storyboard'; dynamic_range = $null; language = $null }
        )
    }

    $choices = @(Get-FormatChoices $fakeInformation)
    if ($choices.Count -ne 4) { throw "Self-test failed: expected 4 choices, got $($choices.Count)." }
    if ($choices[2].Selector -ne '137+bestaudio/137') { throw 'Self-test failed: video-only format did not add audio.' }
    if ((Format-ByteSize 1048576) -ne '1.0 MB') { throw 'Self-test failed: file size formatting is incorrect.' }
    if (-not (Test-VideoUrl 'https://example.com/watch?v=1')) { throw 'Self-test failed: valid URL rejected.' }
    if (Test-VideoUrl 'not a URL') { throw 'Self-test failed: invalid URL accepted.' }

    # Formats whose codecs the site did not report must still be offered.
    $unknownInformation = [pscustomobject]@{
        formats = @(
            [pscustomobject]@{ format_id = 'hls-1080p'; ext = 'mp4'; width = 1920; height = 1080; vcodec = $null; acodec = $null },
            [pscustomobject]@{ format_id = 'dash-720'; ext = 'mp4'; width = 1280; height = 720; vcodec = $null; acodec = 'none' },
            $null
        )
    }
    $unknownChoices = @(Get-FormatChoices $unknownInformation)
    if ($unknownChoices.Count -ne 4) { throw "Self-test failed: formats with unknown codecs were dropped (got $($unknownChoices.Count) choices)." }
    if ($unknownChoices[2].Type -ne 'Unknown' -or $unknownChoices[2].Selector -ne 'hls-1080p') { throw 'Self-test failed: unknown-codec format was not offered as-is.' }
    if ($unknownChoices[3].Selector -ne 'dash-720+bestaudio/dash-720') { throw 'Self-test failed: video with unknown codec did not add audio.' }

    # Missing format lists must not crash.
    if (@(Get-FormatChoices ([pscustomobject]@{ title = 'x' })).Count -ne 2) { throw 'Self-test failed: missing format list was not handled.' }

    # Trailing separators break native argument passing in Windows PowerShell 5.1.
    $sep = [IO.Path]::DirectorySeparatorChar
    $tempRoot = Remove-TrailingSeparator ([IO.Path]::GetTempPath())
    if ((Remove-TrailingSeparator ($tempRoot + $sep)) -ne $tempRoot) { throw 'Self-test failed: trailing separator was not removed.' }
    $driveRoot = [IO.Path]::GetPathRoot($tempRoot)
    if ((Remove-TrailingSeparator $driveRoot) -ne $driveRoot) { throw 'Self-test failed: a drive root was changed.' }

    # Interactive prompts are exercised with scripted answers. Functions defined
    # inside this script block shadow Read-Host, Write-Host and Write-Status for
    # the code it calls, and disappear when the block ends.
    & {
        $answers = New-Object System.Collections.Queue
        $statuses = New-Object System.Collections.ArrayList
        function Read-Host {
            param([string]$Prompt)
            if ($answers.Count -eq 0) { throw "Self-test failed: unexpected prompt '$Prompt'." }
            return $answers.Dequeue()
        }
        function Write-Host { }
        function Write-Status {
            param([string]$Text, [string]$Kind = 'Info')
            $null = $statuses.Add([pscustomobject]@{ Text = $Text; Kind = $Kind })
        }

        # An invalid setup choice warns once and asks again, with no error.
        foreach ($answer in @('x', 'q')) { $answers.Enqueue($answer) }
        $result = Initialize-Application -ForceSetup
        if ($null -ne $result) { throw 'Self-test failed: quitting setup did not return nothing.' }
        if (@($statuses | Where-Object { $_.Kind -eq 'Error' }).Count -ne 0) {
            throw "Self-test failed: invalid setup choice produced an error: $(@($statuses | Where-Object { $_.Kind -eq 'Error' })[0].Text)"
        }
        if (@($statuses | Where-Object { $_.Text -eq 'Choose 1, 2, or Q.' }).Count -ne 1) { throw 'Self-test failed: invalid setup choice was not reported.' }

        # Declining to create a folder asks again instead of failing, and the
        # chosen folder is returned without a trailing separator.
        $statuses.Clear()
        $missingFolder = Join-Path $tempRoot ('EasyVideoDownloader-selftest-' + [guid]::NewGuid().ToString())
        foreach ($answer in @($missingFolder, 'n', ($tempRoot + $sep))) { $answers.Enqueue($answer) }
        $folder = Get-DownloadDirectory $tempRoot
        if ($folder -ne $tempRoot) { throw "Self-test failed: unexpected download folder '$folder'." }
        if (Test-Path -LiteralPath $missingFolder) { throw 'Self-test failed: a declined folder was created.' }
        if ($answers.Count -ne 0) { throw 'Self-test failed: not every scripted answer was used.' }
    }

    Write-Status 'All self-tests passed.' 'Success'
}

function Start-Application {
    Clear-Host
    Write-Title $script:AppName
    Write-Host 'Download videos through guided choices - no commands required.'
    Write-Host 'Only download media you have permission to save.' -ForegroundColor DarkGray

    $configuration = Initialize-Application
    if (-not $configuration) { return }

    while ($true) {
        Write-Title 'New Download'
        Write-Host 'Paste a video URL, or enter S for setup and Q to quit.'
        $url = (Read-Host 'Video URL').Trim()

        if ($url -match '^(?i)q$') { return }
        if ($url -match '^(?i)s$') {
            $updatedConfiguration = Initialize-Application -ForceSetup
            if ($updatedConfiguration) { $configuration = $updatedConfiguration }
            continue
        }
        if (-not (Test-VideoUrl $url)) {
            Write-Status 'Enter a complete http:// or https:// video address.' 'Warning'
            continue
        }

        try {
            $videoInformation = Get-VideoInformation -Configuration $configuration -Url $url
            Write-Host ''
            $videoTitle = Get-PropertyValue $videoInformation 'title'
            $videoUploader = Get-PropertyValue $videoInformation 'uploader'
            Write-Host ('Title: ' + (Limit-Text $videoTitle 100)) -ForegroundColor Green
            if ($videoUploader) {
                Write-Host ('Creator: ' + $videoUploader)
            }

            $choices = @(Get-FormatChoices $videoInformation)
            Show-FormatChoices $choices
            $selected = Select-FormatChoice $choices
            if (-not $selected) { continue }

            Start-VideoDownload -Configuration $configuration -Url $url -FormatChoice $selected
        } catch {
            Write-Status $_.Exception.Message 'Error'
        }

        Write-Host ''
        $again = (Read-Host 'Download another video? [Y/n]').Trim()
        if (($again -ne '') -and ($again -notmatch '^(?i)y(es)?$')) {
            return
        }
    }
}

if ($SelfTest) {
    Invoke-SelfTest
} else {
    Start-Application
}
