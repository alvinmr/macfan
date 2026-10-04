import AppKit
import SwiftUI

extension View {
    /// Runs `action` while this view's window is actually on screen, and cancels it when the
    /// window closes, is hidden behind others, minimized, or (for the menu bar panel) dismissed.
    ///
    /// For work that only matters while someone can see it. `.task` alone isn't enough:
    /// a window left open behind other apps never disappears, and the menu bar panel's
    /// content isn't reliably torn down when it closes.
    func whileVisible(_ action: @escaping () async -> Void) -> some View {
        modifier(WhileVisibleModifier(action: action))
    }
}

private struct WhileVisibleModifier: ViewModifier {
    let action: () async -> Void
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .background(WindowVisibilityReader(isVisible: $isVisible))
            .task(id: isVisible) {
                if isVisible { await action() }
            }
    }
}

private struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = { isVisible = $0 }
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.onChange = { isVisible = $0 }
    }
}

private final class VisibilityView: NSView {
    var onChange: ((Bool) -> Void)?
    private var lastReported: Bool?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        // Selector-based observers are removed automatically when the view is deallocated.
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
        if let newWindow {
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: newWindow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        report()
    }

    @objc private func occlusionChanged(_ notification: Notification) {
        report()
    }

    private func report() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        guard visible != lastReported else { return }
        lastReported = visible
        // Not during a SwiftUI update pass, which these AppKit callbacks can fall inside.
        DispatchQueue.main.async { [onChange] in onChange?(visible) }
    }
}
