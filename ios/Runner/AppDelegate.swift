import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Warm up the shared AVAudioEngine so it's ready before the first
        // just_audio playback begins. This avoids a startup latency spike.
        AudioEngineManager.shared.warmUp()

        GeneratedPluginRegistrant.register(with: self)

        // Register the mo1/equalizer MethodChannel so Flutter can apply EQ
        // presets via AudioEngineManager.
        guard let controller = window?.rootViewController as? FlutterViewController
        else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }
        let equalizerChannel = FlutterMethodChannel(
            name: "mo1/equalizer",
            binaryMessenger: controller.binaryMessenger
        )
        equalizerChannel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            self.handleEqualizerCall(call, result: result)
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - EQ Method Channel

    private func handleEqualizerCall(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {
        case "wireEngine":
            AudioEngineManager.shared.warmUp()
            result(["wired": true])

        case "setPreset":
            guard
                let args = call.arguments as? [String: Any],
                let bandGains = args["bandGainsDb"] as? [Double]
            else {
                result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "setPreset requires bandGainsDb: [Double]",
                    details: nil
                ))
                return
            }
            let presetName = args["presetName"] as? String ?? "Custom"
            let applied = AudioEngineManager.shared.applyBandGains(bandGains)
            result([
                "isApplied": applied,
                "presetName": presetName,
                "backend": "avAudioEngine",
            ])

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
