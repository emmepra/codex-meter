import AppKit
#if !METER_TESTS
import Sparkle
#endif

/// Sparkle verifies signed metadata and archives before installing executable code.
/// Quiet availability polling remains in ReleaseChecker; installation requires a click.
@MainActor
final class SparkleInstaller {
    static let shared = SparkleInstaller()
    #if !METER_TESTS
    private let controller = SPUStandardUpdaterController(startingUpdater: false,
        updaterDelegate: nil, userDriverDelegate: nil)
    private var started = false
    #endif

    func check() {
        #if !METER_TESTS
        if !started {
            controller.startUpdater()
            started = true
        }
        guard controller.updater.canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
        #endif
    }
}
