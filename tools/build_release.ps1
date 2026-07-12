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
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

$stagingDirectory = Join-Path $outputDirectory (".farmnotify-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $stagingDirectory | Out-Null

try {
    foreach ($relativePath in $runtimeFiles) {
        $source = Join-Path $projectRoot $relativePath
        $target = Join-Path $stagingDirectory $relativePath
        $targetDirectory = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
    }

    Compress-Archive -Path (Join-Path $stagingDirectory "*") -DestinationPath $zipPath -CompressionLevel Optimal
} finally {
    if (Test-Path -LiteralPath $stagingDirectory) {
        Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
    }
}

Write-Output $zipPath
