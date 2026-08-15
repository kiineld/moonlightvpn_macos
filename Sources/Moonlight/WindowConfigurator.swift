import SwiftUI
import AppKit

/// Forces the window to draw its content under the title bar.
///
/// `.windowStyle(.hiddenTitleBar)` hides the title and makes the bar
/// transparent, but SwiftUI still lays the content out *below* the reserved
/// title bar area. The result is the app's own title strip sitting under the
/// traffic lights rather than around them — the wordmark ends up on its own row,
/// which is exactly what it looked like.
///
/// `.fullSizeContentView` is what moves the content origin to the top of the
/// window, so the 28pt strip in `RootView` overlaps the title bar and its text
/// lands on the same line as the buttons.
/// It also reports where AppKit actually put the traffic lights. Their inset is
/// not a documented constant and differs with the style mask, so the strip is
/// sized from the measured button centre rather than from an assumed titlebar
/// height — that is what guarantees the wordmark shares their line instead of
/// landing a few points below it.
struct WindowConfigurator: NSViewRepresentable {
    /// Distance from the top of the window to the centre of the close button.
    @Binding var buttonCentre: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The view has no window yet during make; configure once it is attached.
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: view.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // With no title bar to grab, the strip itself has to be the drag handle.
        window.isMovableByWindowBackground = true

        guard let button = window.standardWindowButton(.closeButton),
              let content = window.contentView else { return }
        // AppKit's coordinates run from the bottom, the layout's from the top.
        let inWindow = button.convert(button.bounds, to: content)
        let centre = content.bounds.height - inWindow.midY
        if abs(centre - buttonCentre) > 0.5, centre > 0, centre < 60 {
            buttonCentre = centre
        }
    }
}
