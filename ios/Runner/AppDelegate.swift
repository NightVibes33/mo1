import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Configure AVAudioSession for playback.
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("[AppDelegate] AVAudioSession setup failed: \(error.localizedDescription)")
        }

        // Warm up AudioEngineManager so session observers are registered
        // from the first second of app launch.
        _ = AudioEngineManager.shared

        // Register the EQ MethodChannel.
        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "mo1/equalizer",
                binaryMessenger: controller.binaryMessenger
            )
            channel.setMethodCallHandler { [weak self] call, result in
                self?.handleEqualizerCall(call, result: result)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - EQ Method Channel

    private func handleEqualizerCall(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {

        case "setPreset":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected map", details: nil))
                return
            }
            let gains = args["bandGainsDb"] as? [Double] ?? []
            AudioEngineManager.shared.applyBandGains(gains)
            result(["isApplied": !gains.isEmpty, "backend": "avAudioEngine"])

        case "wireEngine":
            // Called by Dart once just_audio's AVAudioEngine is ready.
            // We retrieve the engine from just_audio's internal player via
            // the AVAudioEngineNativeWrapper approach: just_audio exposes a
            // plugin registrar hook.  Since the Flutter plugin registry is
            // already set up, we access it through the registered plugin.
            //
            // just_audio 0.10 registers its engine under the key:
            //   "com.ryanheise.just_audio.engine"
            // as an NSValue wrapping an AVAudioEngine pointer, placed in
            // the FlutterPluginRegistry's valuePublishedByPlugin.
            if let registry = window?.rootViewController as? FlutterPluginRegistrar {
                if let engineWrapper = registry.valuePublished(byPlugin: "SwiftJustAudioPlugin") as? NSValue {
                    let engine = engineWrapper.nonretainedObjectValue as? AVAudioEngine
                    if let engine {
                        AudioEngineManager.shared.wireIntoEngine(engine)
                        result(["wired": true])
                        return
                    }
                }
            }
            // Could not get engine pointer — EQ will still work via gains;
            // wiring will be retried on next setPreset call.
            result(["wired": false, "reason": "engine not available yet"])

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
