//
//  WindowAccessor.swift
//  TablePro
//
//  Captures the hosting NSWindow from SwiftUI via an invisible NSView.
//  Avoids brittle title-matching or NSApp.keyWindow heuristics.
//

import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { self.window = nsView.window }
    }
}
