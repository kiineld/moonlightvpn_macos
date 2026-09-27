import SwiftUI
import AppKit
import MoonlightCore

/// Forces the window to draw its content under the title bar.
///
/// `.windowStyle(.hiddenTitleBar)` hides the title and makes the bar
/// transparent, but SwiftUI still lays the content out *below* the reserved
/// title bar area, which leaves a dead band across the whole window.
///
/// `.fullSizeContentView` is what moves the content origin to the top of the
/// window, so the page can run up beside the traffic lights while the floating
/// sidebar starts just under them.
/// It also reports where AppKit actually put the traffic lights. Their inset is
/// not a documented constant and differs with the style mask, so `RootView`
/// sizes its top inset from the measured button centre rather than from an
/// assumed titlebar height.
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

        // A login launch starts tucked away rather than in the user's face.
        if LoginLaunch.hideFirstWindow {
            LoginLaunch.hideFirstWindow = false
            LoginLaunch.tuck(window, menuBarIcon: Preferences.shared.menuBarIcon)
        }

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
