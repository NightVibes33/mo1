# mo1 Classic

This branch is a mo1-branded fork of ClassiPod, a real iPod Classic-style local music player built with Flutter.

It keeps the native iPod-style click wheel, local library, metadata, Cover Flow, now playing screen, background playback, and local file/audio support from the upstream project. The iOS bundle display name is `mo1` and the bundle identifier is `app.mo1.player`.

## Unsigned IPA

The `Build unsigned iOS IPA` GitHub Actions workflow installs Flutter 3.35.7 on `macos-26-intel`, runs `flutter pub get`, builds iOS with signing disabled, packages `Runner.app` into `Payload/mo1.app`, and uploads `mo1-classic-unsigned.ipa`.

The artifact is unsigned. SideStore or AltStore signs it during install.

## Attribution

Based on ClassiPod by Aditya R, licensed under the BSD-4-Clause license included in this repository.
