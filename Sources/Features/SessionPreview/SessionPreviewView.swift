import SwiftUI
import AppKit
import Core

public struct SessionPreviewView: View {
    @ObservedObject public var controller: PreviewController

    public init(controller: PreviewController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            AttributedTextView(content: controller.attributedContent)
                .frame(minWidth: 480, minHeight: 240)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
            if controller.isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }
}

struct AttributedTextView: NSViewRepresentable {
    let content: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 4)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        tv.textStorage?.setAttributedString(content)
        tv.scrollToEndOfDocument(nil)
    }
}
