import AppKit
import SwiftUI

// Custom NSPanel hosting the popover content. Replaces NSPopover so we can
// position the panel manually and keep it anchored to the status item button
// when the menu bar rearranges or the button's title width changes — neither
// of which NSPopover tracks correctly.
@MainActor
final class PopoverPanel: NSPanel {

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
        let old = self.frame
        guard fitting != old.size else { return }
        // Anchor the TOP edge: NSWindow origin is bottom-left, so growing
        // height while keeping origin.y would push the top up into the menu
        // bar. Shift origin.y down by the delta to keep the top anchored.
        // X is left untouched — the menu bar may shift the icon left/right
        // beneath us, but the panel itself stays put.
        let heightDelta = fitting.height - old.size.height
        var newFrame = old
        newFrame.size = fitting
        newFrame.origin.y -= heightDelta
        // Animate the frame change so growth/shrink slides instead of snapping.
        // NSWindow's built-in animator picks a sensible duration based on the
        // size of the change.
        animator().setFrame(newFrame, display: true, animate: true)
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
