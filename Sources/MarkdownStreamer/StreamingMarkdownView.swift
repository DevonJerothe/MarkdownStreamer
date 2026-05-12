import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
    @State private var phase: DefaultMarkdownImagePhase = .empty

    public init(image: MarkdownImage) {
        self.image = image
    }

    public var body: some View {
        Group {
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
            }
        }
        .task(id: image.source) {
            phase = .empty
            phase = await DefaultMarkdownImageLoader.shared.image(from: image.source)
        }
        .accessibilityLabel(image.alt ?? "")
    }
}

private enum DefaultMarkdownImagePhase {
    case empty
    case success(Image)
    case failure
}

private actor DefaultMarkdownImageLoader {
    static let shared = DefaultMarkdownImageLoader()

    private var cachedData: [URL: Data] = [:]
    private var inFlightRequests: [URL: Task<Data, Error>] = [:]

    func image(from url: URL) async -> DefaultMarkdownImagePhase {
        do {
            let data = try await data(from: url)

            guard let image = await Image.cachedMarkdownImage(from: data) else {
                return .failure
            }

            return .success(image)
        } catch {
            return .failure
        }
    }

    private func data(from url: URL) async throws -> Data {
        if let data = cachedData[url] {
            return data
        }

        if let request = inFlightRequests[url] {
            return try await request.value
        }

        let request = Task<Data, Error> {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                return data
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            return data
        }

        inFlightRequests[url] = request

        do {
            let data = try await request.value
            cachedData[url] = data
            inFlightRequests[url] = nil
            return data
        } catch {
            inFlightRequests[url] = nil
            throw error
        }
    }
}

private extension Image {
    @MainActor
    static func cachedMarkdownImage(from data: Data) -> Image? {
        #if os(macOS)
        guard let image = NSImage(data: data) else {
            return nil
        }

        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: data) else {
            return nil
        }

        return Image(uiImage: image)
        #endif
    }
}
