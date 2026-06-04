# mo1

mo1 is a real iOS local-MP3 player with a futuristic iPod-style interface. It imports downloaded audio files from the iOS Files app, copies them into local app storage, and plays them through `react-native-track-player` with background-audio configuration.

## Current features

- Import MP3/audio files from iOS Files
- Persist an in-app local music library
- Play, pause, seek, previous, and next controls
- Background audio mode and remote-control event handling
- Glass iPod-style main player UI
- Floating animated album cards
- Expandable Now Playing sheet
- Animated waveform-style visualizer
- Unsigned real-device IPA workflow for SideStore/AltStore-style signing

## Local development

```sh
npm install
npm run typecheck
npx expo prebuild --platform ios
```

This project is intended for a real iOS build, not Expo Go, because it uses native audio playback modules.

## GitHub Actions IPA

Run the `Build unsigned iOS IPA` workflow from the Actions tab. It uses the `macos-26-intel` GitHub-hosted runner, selects Xcode 26, builds with code signing disabled, packages the `.app` into `Payload/mo1.app`, zips it as `mo1-unsigned.ipa`, and uploads it as an artifact.

That IPA is unsigned. SideStore/AltStore still needs to sign it during install.
