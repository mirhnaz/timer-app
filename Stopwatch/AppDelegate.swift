import AppKit
import SwiftUI
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Models live here for the app's lifetime; SwiftUI panel content holds references.
    let stopwatch = StopwatchModel()
    let timer = TimerModel()

    private var statusItem: NSStatusItem!
    private var panel: PopoverPanel!
    private var defaultsObserver: NSObjectProtocol?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    // KVO on the status item's window frame. The status item lives in its own
    // NSWindow whose frame moves both when neighbours rearrange (origin shifts)
    // and when our button resizes due to title changes (size changes). One
    // observer handles both — re-anchors the panel underneath the button.
    private var statusWindowObservation: NSKeyValueObservation?

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
            button.action = #selector(togglePanel(_:))
            button.target = self
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }

        panel = PopoverPanel(rootView: PopoverRoot(stopwatch: stopwatch, timer: timer))
        panel.onContentResize = { [weak self] in
            self?.repositionPanelIfShown()
        }

        // Observe the status item window's frame to keep the panel anchored
        // when (a) other menu bar items rearrange — our window's origin shifts,
        // and (b) our button's title appears/disappears — our window resizes.
        if let win = statusItem.button?.window {
            statusWindowObservation = win.observe(\.frame, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.repositionPanelIfShown() }
            }
        }

        installOutsideClickMonitors()

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

    func applicationWillTerminate(_ notification: Notification) {
        removeOutsideClickMonitors()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    // MARK: - Panel show/hide/reposition

    @objc private func togglePanel(_ sender: Any?) {
        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        repositionPanel()
        statusItem.button?.isHighlighted = true
        panel.makeKeyAndOrderFront(nil)
    }

    private func closePanel() {
        statusItem.button?.isHighlighted = false
        panel.orderOut(nil)
    }

    private func repositionPanelIfShown() {
        guard panel?.isVisible == true else { return }
        repositionPanel()
    }

    private func repositionPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let rectInWindow = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(rectInWindow)

        var origin = NSPoint(
            x: screenRect.midX - panel.frame.width / 2,
            y: screenRect.minY - panel.frame.height - 4
        )

        if let screen = buttonWindow.screen {
            // Clamp to the screen the button is on so a wide panel doesn't
            // spill off-screen on either side.
            let minX = screen.frame.minX + 4
            let maxX = screen.frame.maxX - panel.frame.width - 4
            origin.x = max(minX, min(origin.x, maxX))
        }

        panel.setFrameOrigin(origin)
    }

    // MARK: - Outside click dismissal

    private func installOutsideClickMonitors() {
        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleLocalClick(event)
            }
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isVisible else { return }
                self.closePanel()
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func handleLocalClick(_ event: NSEvent) {
        guard panel.isVisible else { return }
        guard !isClickInsidePanel(event), !isClickOnStatusItemButton(event) else { return }
        closePanel()
    }

    private func isClickInsidePanel(_ event: NSEvent) -> Bool {
        event.window === panel
    }

    private func isClickOnStatusItemButton(_ event: NSEvent) -> Bool {
        guard
            let button = statusItem.button,
            let buttonWindow = button.window,
            event.window === buttonWindow
        else {
            return false
        }

        let pointInButton = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(pointInButton)
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
        // changes route through the defaultsObserver above.
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

// SwiftUI root for the panel. Re-applies preferredColorScheme so SwiftUI's environment
// matches NSApp.appearance even though we're outside MenuBarExtra.
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
