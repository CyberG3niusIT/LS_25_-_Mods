# Changelog

## [1.0.0] — 2026-06-27

### Added
- Animated smartphone notification overlay (iPhone 16 Pro Max / Samsung Galaxy S26 Ultra)
- Event detection: harvest ready, harvest overdue, worker done, worker stuck, fuel low, silo full, rain, storm
- Scrollable notification inbox (N key)
- Camera navigation on notification click
- Cooldown system preventing notification spam
- Cooldown persistence across save/load
- Farm ownership filter in multiplayer (only your farm's events)
- Per-event notification sounds (generated WAV files)
- Optional phone-specific sound overrides (place your own MP3s in sounds/)
- Savegame persistence for notification history
- Atomic savegame write (temp file + rename)
- Dedicated server guard (UI/audio disabled, no crash)
- Full localization (DE / EN)
- Phone model selection and all settings persist per user profile

### Technical
- Stale field ID validation after savegame load
- Monotonic notification ID counter (no ID collisions)
- FillType nil-check in fuel unit detection
- g_fieldManager nil-guard in MapNavigator
- Settings write-deduplication (no redundant XML saves)
