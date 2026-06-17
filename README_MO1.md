# døPe

This branch is the døPe-branded fork: a real retro click-wheel local music player built with Flutter.

It keeps the native classic click wheel, local library, metadata, Cover Flow, now playing screen, background playback, and local file/audio support from the upstream project. The iOS bundle display name is `døPe` and the bundle identifier remains `app.mo1.player` for update compatibility.

## iOS 26 Visual Refresh

The døPe fork adds an iOS 26-inspired visual pass while preserving the working local MP3/audio stack:

- Liquid Glass-style translucent device body, screen chrome, status bar, and selected-row focus.
- Animated aurora lighting, reflection layers, and depth shadows around the player body.
- Polished click wheel with glass highlights, glow, and center-button press animation.
- Smoother eased wheel scrolling, split-screen motion, Cover Flow movement, and Now Playing page changes.
- Now Playing waveform/heat visualizer driven by playback state.
- Xcode 26 GitHub Actions build path with iOS deployment target aligned to 15.0 for broader real-device install support.

Flutter cannot call SwiftUI-only Liquid Glass APIs directly, so this uses Flutter blur, gradients, reflection passes, and custom painters to get the visual language in the existing cross-platform app.

## Unsigned IPA

The `Build unsigned iOS IPA` GitHub Actions workflow installs Flutter 3.35.7 on `macos-26-intel`, runs `flutter pub get`, builds iOS with signing disabled, packages `Runner.app` into `Payload/døPe.app`, and uploads `døPe-classic-unsigned.ipa`.

The artifact is unsigned. SideStore or AltStore signs it during install.

## Attribution

Based on the upstream open-source player by Aditya R, licensed under the BSD-4-Clause license included in this repository.
