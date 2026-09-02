<div align="center">

# doPi

![doPi App Screenshots](screenshots/combined.jpg)

A retro click-wheel music player for iPhone built around personal libraries, Apple Music catalog playback, local audio imports, server libraries, metadata editing, lyrics, equalizer controls, widgets, and a classic iPod-style interface.

</div>

## What doPi Is

doPi is a Flutter music player inspired by classic iPod navigation. The app keeps the click-wheel, Cover Flow, split-screen browsing, and Now Playing flow, while adding modern library sources and editing tools.

The app is focused on user-owned or user-authorized music:

- Local audio imported into the app.
- Apple Music catalog/library references for users with Apple Music access.
- Self-hosted music through Navidrome and Jellyfin.
- Metadata, artwork, lyrics, explicit badges, playlists, equalizer controls, and widgets around those sources.

YouTube support was intentionally removed. doPi does not download audio from YouTube and does not ship a YouTube API key.

## Current Feature Status

### Music Sources

- [x] Local audio import for MP3 and other supported audio files.
- [x] Apple Music search and library-reference import.
- [x] Apple Music catalog playback through the native iOS music player bridge.
- [x] Navidrome connection, browsing, search, starred content, and playback.
- [x] Jellyfin connection, browsing, and playback support.
- [x] Mixed-source Songs list with MP3, Apple Music, Navidrome, and Jellyfin items.
- [x] Source badges in song rows.
- [ ] Spotify support. Not implemented because Spotify does not provide Apple-Music-style full library/playback integration for this use case.
- [ ] YouTube metadata or playback support. Not implemented to avoid API-key exposure, quota/rate-limit issues, and App Store risk.

### Playback

- [x] Classic Now Playing screen.
- [x] Background playback support.
- [x] Lock-screen/media notification controls through the audio service stack.
- [x] Next, previous, seek, play, and pause controls.
- [x] Long-press seek behavior for supported local playback controls.
- [x] Shuffle and repeat modes.
- [x] In-app volume control path.
- [x] Mixed-source queue coordination.
- [x] Apple Music manual-selection start-offset correction.
- [x] Apple Music queue next/previous bridge support.
- [x] Playback crash/debug breadcrumbs.
- [x] Song transition settings for supported local playback paths.
- [x] Local audio format support through the app audio stack, including MP3, M4A/AAC, WAV, FLAC, OGG, and OPUS where platform codecs allow.
- [ ] Apple Music Music Haptics API support. Not implemented because Apple does not expose a public third-party API to reuse Apple Music's built-in haptic tracks inside this app.

### Library Management

- [x] Songs, Albums, Artists, Genres, Playlists, Cover Flow, and Search sections.
- [x] Browse by artist, album, genre, playlist, and all songs.
- [x] Search songs, artists, albums, and playlists.
- [x] Swipe-to-delete individual songs from the Songs section.
- [x] Playlist creation and storage.
- [x] Song rating support.
- [x] Imported artwork caching for offline artwork.
- [x] Cached metadata for faster startup.
- [x] Apple Music artwork persistence across app updates.
- [x] Import progress/loading UI for large local imports.
- [x] Duplicate detection for local imports.
- [x] Date-added sorting across mixed sources.
- [ ] Advanced duplicate merge tools. Planned.
- [ ] Bulk library cleanup tools. Planned.
- [ ] Custom folder scanning outside app imports. Not implemented in the current iOS-focused doPi flow; imports are app-managed.

### Metadata, Artwork, and Lyrics

- [x] Read embedded local-file metadata.
- [x] Automatic MP3 metadata lookup with confidence checks.
- [x] Manual metadata matching.
- [x] Edit song title, artist, album, genre, year, track number, disc number, artwork, lyrics, and explicit status.
- [x] Explicit `E` badges in song rows and Apple Music search results.
- [x] Explicit metadata parsing from Apple Music, iTunes, Deezer-style fields, and lyric-result metadata when provided.
- [x] Manual lyrics search and exact lyrics lookup through LRCLIB.
- [x] Synced/plain lyric storage when found.
- [x] Custom artwork picker.
- [ ] Full embedded tag writing back into the original imported audio file. Not implemented; edits are stored in the app library database.
- [ ] Multi-result metadata merge review screen. Planned.

### Equalizer

- [x] Preset equalizer menu.
- [x] Custom equalizer editor.
- [x] Bass, mid, and treble band grouping in the custom editor.
- [x] Live custom EQ preview path for supported playback.
- [x] EQ support messaging in Settings.
- [x] Native EQ player path for supported local/remote playback attempts.
- [x] EQ debug logging and native-EQ failure fallback.
- [ ] Apple Music EQ processing. Not implemented because Apple Music catalog audio is played by the system music player, not by the app's local audio engine.
- [ ] Per-song EQ presets. Planned.

### UI and Navigation

- [x] Classic click-wheel interface.
- [x] Scrollable wheel rotation.
- [x] Touchscreen support.
- [x] Cover Flow with reflective artwork.
- [x] Split-screen iPod-style browsing.
- [x] Settings toggle for split-screen behavior.
- [x] Tutorial/onboarding flow.
- [x] Status bar with battery indicators and charging state.
- [x] Haptics and click-wheel sounds.
- [x] Responsive layout work for different iPhone/iPad screen sizes.
- [x] About/settings screens.
- [x] Multi-language/localization infrastructure.
- [x] Multiple visual refresh passes for the doPi-branded UI.
- [ ] Built-in iPod-style games. Planned, not implemented.
- [ ] Photo viewer. Planned, not implemented.
- [ ] Video viewer. Planned, not implemented.
- [ ] Xbox 360/Neon-style music visualizer. Planned as an original inspired visualizer only, not a copy of proprietary Xbox software.

### Widgets and System Integration

- [x] iOS widget extension project.
- [x] Widget sync service for current playback/library state.
- [x] Basic widget playback/library display data.
- [ ] Full app clone inside an iOS widget. Not possible under iOS widget limitations; widgets cannot run the entire app UI or full player engine.
- [ ] App Intents/Siri controls. Planned.
- [ ] Lock Screen/Live Activity playback companion. Planned.

### Diagnostics and Release Pipeline

- [x] Debug log export paths.
- [x] Crash/session breadcrumb logging.
- [x] GitHub Actions unsigned IPA builds.
- [x] GitHub Actions Android APK builds.
- [x] Optional TestFlight upload workflow.
- [x] App Store metadata automation scripts.
- [ ] Automated integration tests for every playback backend. Planned.
- [ ] Device-farm playback validation. Planned.

## Roadmap

### In Progress / Next

- [ ] Continue hardening mixed-source playback edge cases.
- [ ] Improve Navidrome and Jellyfin parity where server APIs expose richer data.
- [ ] Add more robust metadata review tools after auto-match.
- [ ] Add App Intents/Siri shortcuts for common playback actions.
- [ ] Improve widget actions within Apple's widget limits.
- [ ] Add per-source diagnostics in the in-app debug viewer.

### Planned

- [ ] Original music visualizer inspired by classic console/player visualizers.
- [ ] Built-in iPod-style games.
- [ ] Photo viewer.
- [ ] Video viewer for user-owned local videos if added later.
- [ ] Per-song or per-source EQ profiles.
- [ ] Better bulk import review and duplicate cleanup tools.
- [ ] Advanced artwork management for very large libraries.
- [ ] More tutorial depth for Apple Music, local imports, server connections, EQ, and widgets.
- [ ] More source-specific library quality indicators for Navidrome and Jellyfin.

### Not Planned Right Now

- [ ] YouTube audio import/download.
- [ ] YouTube API-key-backed metadata search in the client app.
- [ ] Spotify full-library playback integration.
- [ ] Full Apple Music feature parity with Apple's own Music app internals.
- [ ] Full app UI inside an iOS widget.

## Tech Stack

- [x] Flutter app architecture with Riverpod state management.
- [x] `just_audio` playback stack for local/remote app-controlled audio.
- [x] `audio_service` / background audio integration.
- [x] Native iOS Apple Music bridge for catalog/library playback.
- [x] Native iOS widget extension and widget sync service.
- [x] Hive-backed library/cache persistence.
- [x] `audio_metadata_reader` for embedded local-file metadata.
- [x] `file_picker` for user-selected imports.
- [x] `battery_plus` for status bar battery state.
- [x] `vibration` for click-wheel feedback where supported.
- [x] `permission_handler` for platform permissions.
- [x] GitHub Actions release/build automation.

## Build Notes

The primary release workflow is `.github/workflows/testflight.yml`.

It can build:

- Unsigned iOS IPA artifacts.
- Android APK artifacts.
- Signed TestFlight IPA uploads when the required App Store Connect secrets are configured.

The project is Flutter-based and includes iOS-native bridges for Apple Music playback, widgets, native EQ experiments, and platform-specific integrations.

## Privacy and Source Policy

- doPi is designed for music the user owns, imports, or is authorized to access.
- Apple Music features require user authorization and Apple Music availability on the device.
- Navidrome and Jellyfin features connect to servers configured by the user.
- YouTube support is not included.
- Metadata edits are stored in the app library database unless a feature explicitly says it writes tags back to files.

## Attribution

This project is based on the upstream open-source Classipod player by Aditya R and is distributed under the BSD-4-Clause license included in this repository.

## License

See [LICENSE](LICENSE).
