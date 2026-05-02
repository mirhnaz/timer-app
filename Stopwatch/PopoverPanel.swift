import AppKit
import SwiftUI

// Custom NSPanel hosting the popover content. Replaces NSPopover so we can
// position the panel manually and keep it anchored to the status item button
// when the menu bar rearranges or the button's title width changes — neither
// of which NSPopover tracks correctly.
@MainActor
final class PopoverPanel: NSPanel {

    /// Called after the panel resizes to match new SwiftUI content height
    /// (mode switch, lap list growing). The owner should reposition.
    var onContentResize: (() -> Void)?

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.auxiliary, .moveToActiveSpace, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false

        // Transparent window so the rounded content view shows through the
        // square frame and the shadow follows the rounded shape.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        // NSHostingView with autoresizing avoids the constraint update loop
        // that NSHostingController's .preferredContentSize can trigger on
        // borderless panels. The subclass below tells us when SwiftUI's
        // fittingSize changes so we can resize the panel.
        let hosting = SizingHostingView(rootView: rootView.background(.background))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        hosting.onIntrinsicContentSizeChange = { [weak self] in
            self?.sizeToFitContent()
            self?.onContentResize?()
        }
        contentView = hosting

        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 12
        hosting.layer?.masksToBounds = true

        sizeToFitContent()
    }

    private func sizeToFitContent() {
        guard let view = contentView else { return }
        let fitting = view.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { return }
        guard fitting != frame.size else { return }
        var frame = self.frame
        frame.size = fitting
        setFrame(frame, display: false)
        invalidateShadow()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// NSHostingView's intrinsic size tracks the SwiftUI fitting size. When SwiftUI
// content reflows (mode switch, lap added) it calls invalidateIntrinsicContentSize.
// We hook that to drive a panel resize.
private final class SizingHostingView<Content: View>: NSHostingView<Content> {

    var onIntrinsicContentSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        // Defer so we don't reentrantly resize during a layout pass.
        DispatchQueue.main.async { [weak self] in
            self?.onIntrinsicContentSizeChange?()
        }
    }
}
