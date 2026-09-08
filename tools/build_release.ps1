param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\dist")
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$zipPath = Join-Path $outputDirectory "FS25_FarmNotify.zip"

$runtimeFiles = @(
    "modDesc.xml",
    "lang\lang_de.xml",
    "lang\lang_en.xml",
    "scripts\EventDetector.lua",
    "scripts\FarmNotify.lua",
    "scripts\FarmNotifySettings.lua",
    "scripts\MapNavigator.lua",
    "scripts\NotificationManager.lua",
    "scripts\PhoneAnimator.lua",
    "scripts\PhoneModel.lua",
    "scripts\PhoneUI.lua",
    "scripts\SoundController.lua",
    "sounds\notify_alert.wav",
    "sounds\notify_default.wav",
    "sounds\notify_done.wav",
    "sounds\notify_harvest.wav",
    "sounds\notify_info.wav",
    "sounds\notify_urgent.wav",
    "sounds\notify_weather.wav",
    "sounds\custom\iphone_message.wav",
    "sounds\custom\iphone_ringtone.wav",
    "sounds\custom\samsung_message.wav",
    "sounds\custom\samsung_ringtone.wav",
    "sounds\custom\LICENSE.txt",
    "textures\icons\icon_farmnotify.dds",
    "textures\phones\iphone16promax_frame.png",
    "textures\phones\phone_wallpaper.png",
    "textures\phones\samsung_s26ultra_frame.png"
)

foreach ($relativePath in $runtimeFiles) {
    $absolutePath = Join-Path $projectRoot $relativePath
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        throw "Required release file is missing: $relativePath"
    }
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$temporaryZip = Join-Path $outputDirectory (".farmnotify-" + [guid]::NewGuid().ToString("N") + ".zip")
Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
    $archive = [IO.Compression.ZipFile]::Open($temporaryZip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($relativePath in $runtimeFiles) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, (Join-Path $projectRoot $relativePath), $relativePath.Replace('\', '/'),
                [IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    } finally {
        $archive.Dispose()
    }
    Move-Item -LiteralPath $temporaryZip -Destination $zipPath -Force
} finally {
    if (Test-Path -LiteralPath $temporaryZip) {
        Remove-Item -LiteralPath $temporaryZip -Force
    }
}

Write-Output $zipPath
