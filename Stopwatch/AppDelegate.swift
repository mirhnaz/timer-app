import AppKit
import SwiftUI
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Models live here for the app's lifetime; SwiftUI popover content holds references.
    let stopwatch = StopwatchModel()
    let timer = TimerModel()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var defaultsObserver: NSObjectProtocol?

    // Coalesce many model changes per runloop pass into a single re-render.
    private var renderPending = false
    private var lastIconName = ""
    private var lastTitle = ""

    // Render every needed glyph once and reuse — the timer ticks at 30 Hz, so we
    // don't want to allocate NSImages on every tick.
    private lazy var iconCache: [String: NSImage] = [
        "stopwatch":                Self.paddedIcon("stopwatch"),
        "stopwatch.fill":           Self.paddedIcon("stopwatch.fill"),
        "hourglass":                Self.paddedIcon("hourglass"),
        "hourglass.tophalf.filled": Self.paddedIcon("hourglass.tophalf.filled"),
    ]

    override init() {
        super.init()
        // Apply saved appearance before any window draws, so first paint is correct.
        let raw = UserDefaults.standard.string(forKey: "appearance") ?? AppearanceMode.system.rawValue
        (AppearanceMode(rawValue: raw) ?? .system).apply()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

            // NSPopover's built-in tracking is unreliable when the menu bar rearranges
            // other items mid-frame. Reposition manually whenever our button's frame
            // shifts (origin changes when neighbours grow/shrink, size changes when our
            // own title length changes).
            button.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: button,
                queue: .main
            ) { [weak self] _ in
                // Tracking the popover reliably across menu bar rearrangements is
                // unreliable, so dismiss it on any layout change. The user re-clicks
                // the icon to get a popover correctly anchored to the new position.
                MainActor.assumeIsolated { [self] in
                    guard let self, self.popover.isShown else { return }
                    self.popover.close()
                }
            }
        }

        let host = NSHostingController(rootView: PopoverRoot(stopwatch: stopwatch, timer: timer))
        host.sizingOptions = [.preferredContentSize]

        popover = NSPopover()
        popover.behavior = .transient        // closes on click outside; auto-tracks status button position
        popover.animates = true
        popover.contentViewController = host

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue: .main guarantees main-thread delivery; type system doesn't know that.
            MainActor.assumeIsolated {
                self?.scheduleRender()
            }
        }

        renderNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Status button rendering

    private func scheduleRender() {
        guard !renderPending else { return }
        renderPending = true
        DispatchQueue.main.async { [weak self] in
            self?.renderPending = false
            self?.renderNow()
        }
    }

    private func renderNow() {
        // withObservationTracking re-arms after each fire; the closure schedules the next render.
        // onChange is @Sendable, so hop back to the main actor before touching self.
        withObservationTracking {
            applyStatusButton()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleRender()
            }
        }
    }

    private func applyStatusButton() {
        guard let button = statusItem.button else { return }

        // mode is stored in UserDefaults via @AppStorage in the popover. UserDefaults
        // changes route through observeDefaults() above.
        let modeRaw = UserDefaults.standard.string(forKey: "mode") ?? AppMode.stopwatch.rawValue
        let mode = AppMode(rawValue: modeRaw) ?? .stopwatch

        let (iconName, title): (String, String) = {
            switch barState(mode: mode) {
            case .finished:
                return ("hourglass.tophalf.filled", " Done")
            case .time(let symbol, let value):
                return (symbol, " " + TimeFormat.menuBar(value))
            case .idle(let symbol):
                return (symbol, "")
            }
        }()

        if iconName != lastIconName {
            button.image = iconCache[iconName]
            lastIconName = iconName
        }
        if title != lastTitle {
            button.title = title
            lastTitle = title
        }
    }

    private enum BarState {
        case finished
        case time(symbol: String, value: TimeInterval)
        case idle(symbol: String)
    }

    // Priority: finished timer > running timer > running stopwatch > selected mode's snapshot.
    private func barState(mode: AppMode) -> BarState {
        if timer.isFinished { return .finished }
        if timer.isRunning { return .time(symbol: "hourglass", value: timer.remaining) }
        if stopwatch.isRunning { return .time(symbol: "stopwatch.fill", value: stopwatch.elapsed) }
        switch mode {
        case .timer:
            return timer.hasDuration
                ? .time(symbol: "hourglass", value: timer.remaining)
                : .idle(symbol: "hourglass")
        case .stopwatch:
            return stopwatch.hasActivity
                ? .time(symbol: "stopwatch", value: stopwatch.elapsed)
                : .idle(symbol: "stopwatch")
        }
    }

    // MARK: - Icon rendering

    private static let canvasSize = NSSize(width: 16, height: 16)

    private static func paddedIcon(_ name: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        let image = NSImage(size: canvasSize, flipped: false) { rect in
            guard let symbol else { return false }
            let s = symbol.size
            let origin = NSPoint(
                x: (rect.width  - s.width)  / 2,
                y: (rect.height - s.height) / 2
            )
            symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        return image
    }
}

// SwiftUI root for the popover. Re-applies preferredColorScheme so SwiftUI's environment
// matches NSApp.appearance even though we're outside MenuBarExtra now.
private struct PopoverRoot: View {
    let stopwatch: StopwatchModel
    let timer: TimerModel
    @AppStorage("appearance") private var appearance: AppearanceMode = .system

    var body: some View {
        StopwatchView(stopwatch: stopwatch, timer: timer)
            .id(appearance)
            .preferredColorScheme(appearance.colorScheme)
    }
}
