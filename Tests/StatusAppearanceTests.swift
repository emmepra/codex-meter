import AppKit

/// Runs against a real native status item in the logged-in desktop session.
/// No account data, network requests, or system appearance preferences are used.
@MainActor
private final class AppearanceTestDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    #if LEGACY_APPEARANCE_OBSERVER
    private var observer: NSKeyValueObservation?
    #else
    private var observer: StatusAppearanceObserver?
    #endif
    private var renderCount = 0
    private var renderedAppearance: NSAppearance.Name?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.appearance = NSAppearance(named: .aqua)
        Task { await runChecks() }
    }

    private func finish(_ status: Int32, _ message: String) -> Never {
        observer = nil
        NSStatusBar.system.removeStatusItem(item)
        print(message)
        exit(status)
    }

    private func require(_ condition: Bool, _ message: String) {
        if !condition { finish(1, "FAIL: \(message)") }
    }

    private func settle() async {
        // Let both the AppKit snapshot pass and its deferred KVO callbacks run.
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private func render() {
        renderCount += 1
        // Legacy mode reproduces the feedback loop without leaving it running.
        require(renderCount <= 100, "appearance redraw feedback exceeded 100 renders")
        let button = item.button!
        let appearance = button.effectiveAppearance
        renderedAppearance = appearance.name
        button.image = StatusIndicator.image(used: 37, uncertain: false,
            showPercentage: true, refreshing: false, resetCount: nil,
            appearance: appearance)
    }

    private func imageLuminance() -> Double {
        guard let data = item.button?.image?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data) else {
            finish(1, "FAIL: status image must render to pixels")
        }
        var sum = 0.0
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.7 else { continue }
                sum += Double(color.redComponent + color.greenComponent + color.blueComponent) / 3
                count += 1
            }
        }
        require(count > 0, "status image must contain visible ring/text pixels")
        return sum / Double(count)
    }

    private func expectStableChange(to name: NSAppearance.Name) async -> Double {
        let before = renderCount
        guard let target = NSAppearance(named: name) else {
            finish(1, "FAIL: AppKit could not create \(name.rawValue)")
        }
        // AppKit may resolve a requested high-contrast appearance to its normal
        // counterpart when system Increase Contrast is off. Test the actual
        // resolved appearance without changing the user's accessibility settings.
        let targetName = target.name
        let expectedRedraws = renderedAppearance == targetName ? 0 : 1
        item.button?.appearance = target
        await settle()
        require(renderCount == before + expectedRedraws,
                "persistent \(name.rawValue) must redraw \(expectedRedraws) times; got \(renderCount - before)")
        require(renderedAppearance == targetName,
                "render must use resolved \(targetName.rawValue), got \(renderedAppearance?.rawValue ?? "nil")")
        let luminance = imageLuminance()
        await settle()
        require(renderCount == before + expectedRedraws, "drawing \(name.rawValue) must settle without more renders")
        print("PASS: \(name.rawValue) resolves to \(targetName.rawValue), redraws \(expectedRedraws) times and settles")
        return luminance
    }

    private func runChecks() async {
        for _ in 0..<100 {
            if item.button?.window.map({ $0.isVisible && $0.screen != nil }) == true { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        require(item.button?.window.map({ $0.isVisible && $0.screen != nil }) == true,
                "requires a logged-in native macOS desktop")
        let button = item.button!
        #if LEGACY_APPEARANCE_OBSERVER
        observer = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.render() }
        }
        #else
        observer = StatusAppearanceObserver(button: button) { [weak self] in self?.render() }
        #endif

        render()
        await settle()
        require(renderCount == 1, "initial render must settle; got \(renderCount) renders")
        let light = imageLuminance()
        await settle()
        require(renderCount == 1, "rasterizing the initial image must not trigger another render")
        print("PASS: initial native status item is quiescent")

        // NSStatusItem itself performs temporary appearance swaps to draw its
        // replicas. Model several such swaps within one synchronous transaction.
        let saved = button.appearance
        let transientNames: [NSAppearance.Name] = [.darkAqua, .accessibilityHighContrastDarkAqua, .aqua]
        for name in transientNames {
            button.appearance = NSAppearance(named: name)
        }
        button.appearance = saved
        await settle()
        require(renderCount == 1, "restored transient appearances must cause zero redraws")
        require(renderedAppearance == .aqua, "transient appearance must not replace the stable render")
        print("PASS: transient appearances restored synchronously cause zero redraws")

        let dark = await expectStableChange(to: .darkAqua)
        require(dark > light + 0.3, "dark-mode ring/text must be brighter than light-mode pixels")
        _ = await expectStableChange(to: .accessibilityHighContrastDarkAqua)
        _ = await expectStableChange(to: .accessibilityHighContrastAqua)
        let lightAgain = await expectStableChange(to: .aqua)
        require(abs(lightAgain - light) < 0.05, "returning to light mode must restore its drawing colors")
        finish(0, "Status appearance integration tests passed (\(renderCount) renders)")
    }
}

@main
struct StatusAppearanceTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppearanceTestDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
