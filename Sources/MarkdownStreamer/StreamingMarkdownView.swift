import SwiftUI

public struct StreamingMarkdownView<CodeView: View, ImageView: View>: View {
    private let blocks: [ChatBlock]
    private let codeView: (CodeBlock) -> CodeView
    private let imageView: (MarkdownImage) -> ImageView

    public init(
        blocks: [ChatBlock],
        @ViewBuilder codeView: @escaping (CodeBlock) -> CodeView,
        @ViewBuilder imageView: @escaping (MarkdownImage) -> ImageView
    ) {
        self.blocks = blocks
        self.codeView = codeView
        self.imageView = imageView
    }

    public init(
        markdown: String,
        theme: MarkdownTheme = .default,
        @ViewBuilder codeView: @escaping (CodeBlock) -> CodeView,
        @ViewBuilder imageView: @escaping (MarkdownImage) -> ImageView
    ) {
        self.blocks = MarkdownReader.readSync(markdown, theme: theme)
        self.codeView = codeView
        self.imageView = imageView
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks.indices, id: \.self) { index in
                blockView(for: blocks[index])
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: ChatBlock) -> some View {
        switch block.kind {
        case .paragraph(let text):
            AnimatedAttributedText(text)
                .textSelection(.enabled)

        case .heading(_, let text):
            AnimatedAttributedText(text)
                .textSelection(.enabled)

        case .code(let block):
            codeView(block)

        case .image(let source, let alt):
            imageView(.init(source: source, alt: alt))
        }
    }
}

public extension StreamingMarkdownView where CodeView == SplashCodeBlockView, ImageView == DefaultMarkdownImageView {
    init(blocks: [ChatBlock]) {
        self.init(
            blocks: blocks,
            codeView: { SplashCodeBlockView(block: $0) },
            imageView: { DefaultMarkdownImageView(image: $0) }
        )
    }

    init(markdown: String, theme: MarkdownTheme = .default) {
        self.init(
            markdown: markdown,
            theme: theme,
            codeView: { SplashCodeBlockView(block: $0) },
            imageView: { DefaultMarkdownImageView(image: $0) }
        )
    }
}

public extension StreamingMarkdownView where ImageView == DefaultMarkdownImageView {
    init(
        blocks: [ChatBlock],
        @ViewBuilder codeView: @escaping (CodeBlock) -> CodeView
    ) {
        self.init(
            blocks: blocks,
            codeView: codeView,
            imageView: { DefaultMarkdownImageView(image: $0) }
        )
    }

    init(
        markdown: String,
        theme: MarkdownTheme = .default,
        @ViewBuilder codeView: @escaping (CodeBlock) -> CodeView
    ) {
        self.init(
            markdown: markdown,
            theme: theme,
            codeView: codeView,
            imageView: { DefaultMarkdownImageView(image: $0) }
        )
    }
}

public extension StreamingMarkdownView where CodeView == SplashCodeBlockView {
    init(
        blocks: [ChatBlock],
        @ViewBuilder imageView: @escaping (MarkdownImage) -> ImageView
    ) {
        self.init(
            blocks: blocks,
            codeView: { SplashCodeBlockView(block: $0) },
            imageView: imageView
        )
    }

    init(
        markdown: String,
        theme: MarkdownTheme = .default,
        @ViewBuilder imageView: @escaping (MarkdownImage) -> ImageView
    ) {
        self.init(
            markdown: markdown,
            theme: theme,
            codeView: { SplashCodeBlockView(block: $0) },
            imageView: imageView
        )
    }
}

public struct DefaultMarkdownImageView: View {
    public let image: MarkdownImage

    public init(image: MarkdownImage) {
        self.image = image
    }

    public var body: some View {
        AsyncImage(url: image.source) { phase in
            switch phase {
            case .empty:
                ProgressView()
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                Image(systemName: "photo")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            @unknown default:
                EmptyView()
            }
        }
        .accessibilityLabel(image.alt ?? "")
    }
}
