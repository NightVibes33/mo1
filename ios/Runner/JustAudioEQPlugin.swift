// JustAudioEQPlugin.swift
// This file is intentionally kept as a no-op stub.
//
// The previous MethodChannel-interception approach was removed because:
//   1. just_audio sends "init" on per-player channels, not the top-level
//      channel, so setupPlayerChannel() was never called and all load/play
//      calls fell through to AVQueuePlayer, bypassing the EQ graph.
//   2. Returning FlutterMethodNotImplemented from a registered plugin
//      silently drops the call rather than forwarding to the next plugin,
//      which broke non-local playback entirely.
//   3. No EventChannel state updates were ever sent to Dart, so
//      just_audio's load() future never completed on the Flutter side.
//
// EQ is now applied via an AVAudioEngine output-node tap in
// AudioEngineManager, which affects ALL audio routed through the
// AVAudioSession regardless of which backend (just_audio, MusicKit,
// MPMusicPlayerController) is playing. No MethodChannel interception
// or per-player wiring is required.
//
// AppDelegate no longer registers this class. It is retained only so
// any external references compile without change.

import Flutter

@objc public class JustAudioEQPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        // No-op: EQ is handled by AudioEngineManager output tap.
    }
}
