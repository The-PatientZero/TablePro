//
//  WindowAccessor.swift
//  TablePro
//
//  Captures the hosting NSWindow from SwiftUI via an invisible NSView.
//  Uses viewDidMoveToWindow to capture once, avoiding repeated async
//  dispatches that can race with window deallocation.
//

import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> WindowAccessorView {
        let view = WindowAccessorView()
        view.onWindowChange = { [self] newWindow in
            self.window = newWindow
        }
        return view
    }

    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.onWindowChange = { [self] newWindow in
            self.window = newWindow
        }
    }
}

final class WindowAccessorView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
