//
//  HorizontalSplitView.swift
//  TablePro
//

import AppKit
import SwiftUI

struct HorizontalSplitView<Leading: View, Trailing: View>: NSViewRepresentable {
    var isTrailingCollapsed: Bool
    @Binding var trailingWidth: CGFloat
    var minTrailingWidth: CGFloat
    var maxTrailingWidth: CGFloat
    var autosaveName: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    func makeCoordinator() -> Coordinator {
        Coordinator(trailingWidth: $trailingWidth)
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = autosaveName
        splitView.delegate = context.coordinator

        let leadingHosting = NSHostingView(rootView: leading)
        leadingHosting.sizingOptions = [.minSize]

        let trailingHosting = NSHostingView(rootView: trailing)
        trailingHosting.sizingOptions = [.minSize]

        splitView.addArrangedSubview(leadingHosting)
        splitView.addArrangedSubview(trailingHosting)

        context.coordinator.leadingHosting = leadingHosting
        context.coordinator.trailingHosting = trailingHosting
        context.coordinator.lastCollapsedState = isTrailingCollapsed
        context.coordinator.minWidth = minTrailingWidth
        context.coordinator.maxWidth = maxTrailingWidth

        if isTrailingCollapsed {
            trailingHosting.isHidden = true
        }

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.leadingHosting?.rootView = leading
        context.coordinator.trailingHosting?.rootView = trailing
        context.coordinator.trailingWidth = $trailingWidth
        context.coordinator.minWidth = minTrailingWidth
        context.coordinator.maxWidth = maxTrailingWidth

        guard let trailingView = context.coordinator.trailingHosting else { return }
        let wasCollapsed = context.coordinator.lastCollapsedState

        if isTrailingCollapsed != wasCollapsed {
            context.coordinator.lastCollapsedState = isTrailingCollapsed
            if isTrailingCollapsed {
                if splitView.subviews.count >= 2 {
                    context.coordinator.savedDividerPosition = splitView.subviews[1].frame.width
                }
                splitView.setPosition(splitView.bounds.width, ofDividerAt: 0)
                trailingView.isHidden = true
            } else {
                trailingView.isHidden = false
                let targetWidth = context.coordinator.savedDividerPosition ?? trailingWidth
                splitView.adjustSubviews()
                splitView.setPosition(splitView.bounds.width - targetWidth, ofDividerAt: 0)
            }
        }
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var leadingHosting: NSHostingView<Leading>?
        var trailingHosting: NSHostingView<Trailing>?
        var lastCollapsedState = false
        var savedDividerPosition: CGFloat?
        var minWidth: CGFloat = 0
        var maxWidth: CGFloat = 0
        var trailingWidth: Binding<CGFloat>

        init(trailingWidth: Binding<CGFloat>) {
            self.trailingWidth = trailingWidth
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            splitView.bounds.width - maxWidth
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            splitView.bounds.width - minWidth
        }

        func splitView(
            _ splitView: NSSplitView,
            canCollapseSubview subview: NSView
        ) -> Bool {
            subview == trailingHosting
        }

        func splitView(
            _ splitView: NSSplitView,
            effectiveRect proposedEffectiveRect: NSRect,
            forDrawnRect drawnRect: NSRect,
            ofDividerAt dividerIndex: Int
        ) -> NSRect {
            if trailingHosting?.isHidden == true {
                return .zero
            }
            return proposedEffectiveRect
        }

        func splitView(
            _ splitView: NSSplitView,
            shouldHideDividerAt dividerIndex: Int
        ) -> Bool {
            trailingHosting?.isHidden == true
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? NSSplitView,
                  splitView.subviews.count >= 2,
                  trailingHosting?.isHidden != true
            else { return }
            let width = splitView.subviews[1].frame.width
            guard width > 0, abs(width - trailingWidth.wrappedValue) > 0.5 else { return }
            trailingWidth.wrappedValue = width
        }
    }
}
