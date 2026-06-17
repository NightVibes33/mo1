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

        // Configure AVAudioSession for playback before any audio plugin
        // initialises so just_audio's AVAudioEngine starts in the right category.
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

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
