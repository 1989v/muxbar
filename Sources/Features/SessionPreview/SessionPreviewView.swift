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
        // 수동 NSScrollView + NSTextView 조합은 autoresizing 미설정으로 텍스트뷰가 0x0 프레임에 고정됨.
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.backgroundColor = .textBackgroundColor
            textView.textContainerInset = NSSize(width: 4, height: 4)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        tv.textStorage?.setAttributedString(content)
        tv.scrollToEndOfDocument(nil)
    }
}
