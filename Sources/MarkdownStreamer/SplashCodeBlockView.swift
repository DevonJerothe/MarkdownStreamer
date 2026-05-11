import SwiftUI
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct SplashCodeBlockView: View {
    public let block: CodeBlock

    @Environment(\.markdownTheme) private var theme
    @State private var didCopy = false

    public init(block: CodeBlock) {
        self.block = block
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .overlay(.white.opacity(0.08))

            ScrollView(.horizontal) {
                highlightedText
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .background(codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(languageLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)

            Spacer(minLength: 12)

            Button {
                copyCode()
            } label: {
                Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "check" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.72))
            .accessibilityLabel(didCopy ? "Copied code" : "Copy code")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(headerBackground)
    }

    private var highlightedText: Text {
        Text(block.highlightedCode)
    }

    private var languageLabel: String {
        guard let language = block.language, !language.isEmpty else {
            return "Code"
        }

        return language
    }

    private var codeBackground: Color {
        Color(red: 0.055, green: 0.059, blue: 0.071)
    }

    private var headerBackground: Color {
        Color.white.opacity(0.045)
    }

    private func copyCode() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        UIPasteboard.general.string = block.code
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block.code, forType: .string)
        #endif

        didCopy = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            didCopy = false
        }
    }
}
