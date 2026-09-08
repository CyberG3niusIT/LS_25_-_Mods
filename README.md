# FarmNotify

Real smartphone notification system for Farming Simulator 25.

A rendered iPhone 16 Pro Max or Samsung Galaxy S26 Ultra slides in from the bottom-right of your screen whenever something important happens on your farm. Tap notifications to navigate directly to the affected field.

## Features

- **Harvest ready** — notified when crops reach peak growth
- **Harvest overdue** — alert when crops have withered
- **Worker done / stuck** — know when AI helpers finish or need attention
- **Fuel low** — warning when any vehicle drops below 15% tank
- **Silo full** — alert when storage reaches 99.9% capacity
- **Rain started** — detects the transition to rain; no forecast or storm detection
- **Scrollable inbox** — full notification history, press N to open
- **Phone model selector** — choose iPhone or Samsung in settings
- **Cooldown protection** — no notification spam, timers persist across saves

## Installation

1. Download the mod ZIP
2. Place in your FS25 mods folder
3. Activate in the in-game mod manager

## Controls

| Key | Action |
|-----|--------|
| N | Toggle notification inbox |
| ESC | Close inbox |
| Left-click field notification | Open the map at the field |

## Multiplayer

- Notifications are filtered per farm — you only see your own farm's events
- Detection runs locally on host/client; dedicated servers skip UI/audio and detection
- Live multiplayer and LS25 1.23 testing is still required for this release
- History is stored when a local savegame directory is available. Remote clients do not write the server's savegame

## Build and verification

Run `powershell -File tools/build_release.ps1` to create `dist/FS25_FarmNotify.zip`.
Use that filename unchanged; do not install the source ZIP or an extra enclosing folder.
For automated checks install `lupa` (`python -m pip install lupa`) and run the scripts in `tests/`.

History uses two alternating snapshots, `farmnotify.xml` and `farmnotify.backup.xml`,
with generation numbers. The latest complete snapshot is loaded; a failed write
leaves the previous snapshot available. History saves on the mission save hook and
map exit. This is recoverable dual-file storage, not an atomic filesystem rename.
Pre-1.1.1 history lacks farm ownership and may be discarded to avoid showing another farm's events.

Before live testing: activate this mod alone, test N/ESC and settings, then trigger
two silo warnings, a fuel threshold recrossing, field readiness and AI completion.
Save, exit, reload, then test farm switching and simultaneous use with SmartWorker.
Inspect `log.txt` after each test. Automated mocks do not replace a GIANTS runtime test.

## Requirements

- Farming Simulator 25
- No additional mods required

## Credits

- Mod: CyberG3nius
- Phone frames and wallpaper: programmatically generated (no third-party assets)
- Notification sounds: generated WAV files
