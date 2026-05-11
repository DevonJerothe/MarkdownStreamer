import Foundation
import CryptoKit
import Splash
import SwiftUI

public actor StreamProcessor {
    private enum OpenBlock {
        case paragraph(id: UUID, text: String)
        case heading(id: UUID, level: Int, text: String)
        case code(id: UUID, language: String?, committedCode: String)
    }

    private struct RawBlock: Equatable {
        var id: UUID
        var kind: RawBlockKind
    }

    private enum RawBlockKind: Equatable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case code(language: String?, code: String, isClosed: Bool)
        case image(source: URL, alt: String?)

        var identitySeed: String {
            switch self {
            case .paragraph(let text):
                "paragraph#\(text)"
            case .heading(let level, let text):
                "heading#\(level)#\(text)"
            case .code(let language, let code, let isClosed):
                "code#\(language ?? "")#\(isClosed)#\(code)"
            case .image(let source, let alt):
                "image#\(source.absoluteString)#\(alt ?? "")"
            }
        }
    }

    private var rawBlocks: [RawBlock] = []
    private var processedBlocks: [ChatBlock] = []
    private var openBlock: OpenBlock?
    private var lineBuffer = ""
    private var accumulatedText = ""
    private var lastTheme: MarkdownTheme?
    private var idSeed: String?
    private var nextBlockIndex = 0

    public init(idSeed: String? = nil) {
        self.idSeed = idSeed
    }

    public func process(token: String, theme: MarkdownTheme = .default) async -> [ChatBlock] {
        accumulatedText += token
        processCharacters(token, theme: theme)
        return processedBlocks
    }

    public func processAccumulated(_ text: String, theme: MarkdownTheme = .default) async -> [ChatBlock] {
        guard text.hasPrefix(accumulatedText) else {
            reset()
            accumulatedText = text
            processCharacters(text, theme: theme)
            return processedBlocks
        }

        let suffix = text.dropFirst(accumulatedText.count)
        guard !suffix.isEmpty else { return processedBlocks }

        accumulatedText = text
        processCharacters(String(suffix), theme: theme)
        return processedBlocks
    }

    public func finish(theme: MarkdownTheme = .default) async -> [ChatBlock] {
        ensureTheme(theme)

        if !lineBuffer.isEmpty {
            consumeLine(lineBuffer, theme: theme)
            lineBuffer.removeAll(keepingCapacity: true)
        }

        finalizeOpenBlock(theme: theme)
        return processedBlocks
    }

    public func reset() {
        rawBlocks.removeAll(keepingCapacity: true)
        processedBlocks.removeAll(keepingCapacity: true)
        openBlock = nil
        lineBuffer.removeAll(keepingCapacity: true)
        accumulatedText.removeAll(keepingCapacity: true)
        lastTheme = nil
        nextBlockIndex = 0
    }

    public static func read(_ markdown: String, theme: MarkdownTheme = .default) async -> [ChatBlock] {
        let processor = StreamProcessor(idSeed: "MarkdownStreamer.Block")
        _ = await processor.process(token: markdown, theme: theme)
        return await processor.finish(theme: theme)
    }

    private func processCharacters(_ token: String, theme: MarkdownTheme) {
        ensureTheme(theme)

        for character in token.normalizedLineEndings {
            if character == "\n" {
                consumeLine(lineBuffer, theme: theme)
                lineBuffer.removeAll(keepingCapacity: true)
            } else {
                lineBuffer.append(character)
                refreshStreamingBlock(theme: theme)
            }
        }
    }

    private func ensureTheme(_ theme: MarkdownTheme) {
        guard lastTheme != theme else { return }
        lastTheme = theme
        processedBlocks = rawBlocks.map { render($0, theme: theme) }
    }

    private func consumeLine(_ line: String, theme: MarkdownTheme) {
        switch openBlock {
        case .code(let id, let language, let committedCode):
            if isClosingFence(line) {
                openBlock = nil
                replaceBlock(id: id, with: .code(language: language, code: committedCode, isClosed: true), theme: theme)
            } else {
                let nextCode = committedCode + line + "\n"
                replaceBlock(id: id, with: .code(language: language, code: nextCode, isClosed: false), theme: theme)
                openBlock = .code(id: id, language: language, committedCode: nextCode)
            }

        case .paragraph(let id, let text):
            if isOpeningFence(line) {
                openBlock = nil
                replaceBlock(id: id, with: .paragraph(text.trimmingCharacters(in: .newlines)), theme: theme)
                let language = parseFenceLanguage(line)
                let codeID = makeID()
                appendBlock(.init(id: codeID, kind: .code(language: language, code: "", isClosed: false)), theme: theme)
                openBlock = .code(id: codeID, language: language, committedCode: "")
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                openBlock = nil
                replaceBlock(id: id, with: .paragraph(text.trimmingCharacters(in: .newlines)), theme: theme)
            } else {
                let nextText = text.isEmpty ? line : text + "\n" + line
                replaceBlock(id: id, with: .paragraph(nextText), theme: theme)
                openBlock = .paragraph(id: id, text: nextText)
            }

        case .heading(let id, let level, _):
            openBlock = nil
            replaceBlock(id: id, with: .heading(level: level, text: line.headingText(level: level)), theme: theme)

        case nil:
            consumeLineWithoutOpenBlock(line, theme: theme)
        }
    }

    private func consumeLineWithoutOpenBlock(_ line: String, theme: MarkdownTheme) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return
        }

        if isOpeningFence(line) {
            let language = parseFenceLanguage(line)
            let id = makeID()
            appendBlock(.init(id: id, kind: .code(language: language, code: "", isClosed: false)), theme: theme)
            openBlock = .code(id: id, language: language, committedCode: "")
            return
        }

        if let image = parseImage(line) {
            appendBlock(.init(id: makeID(), kind: .image(source: image.source, alt: image.alt)), theme: theme)
            return
        }

        if let heading = parseHeading(line) {
            let id = makeID()
            appendBlock(.init(id: id, kind: .heading(level: heading.level, text: heading.text)), theme: theme)
            openBlock = .heading(id: id, level: heading.level, text: heading.text)
            return
        }

        let id = makeID()
        appendBlock(.init(id: id, kind: .paragraph(line)), theme: theme)
        openBlock = .paragraph(id: id, text: line)
    }

    private func refreshStreamingBlock(theme: MarkdownTheme) {
        switch openBlock {
        case .code(let id, let language, let committedCode):
            if isClosingFence(lineBuffer) {
                openBlock = nil
                lineBuffer.removeAll(keepingCapacity: true)
                replaceBlock(id: id, with: .code(language: language, code: committedCode, isClosed: true), theme: theme)
                return
            }

            replaceBlock(id: id, with: .code(language: language, code: committedCode + lineBuffer, isClosed: false), theme: theme)

        case .paragraph(let id, let text):
            if lineBuffer.allSatisfy({ $0 == "`" }) || lineBuffer.hasPrefix("```") {
                replaceBlock(id: id, with: .paragraph(text.trimmingCharacters(in: .newlines)), theme: theme)
                return
            }

            let nextText = if text.isEmpty {
                lineBuffer
            } else if lineBuffer.isEmpty {
                text
            } else {
                text + "\n" + lineBuffer
            }
            replaceBlock(id: id, with: .paragraph(nextText), theme: theme)

        case .heading(let id, let level, _):
            replaceBlock(id: id, with: .heading(level: level, text: lineBuffer.headingText(level: level)), theme: theme)

        case nil:
            refreshProvisionalBlockFromLineBuffer(theme: theme)
        }
    }

    private func refreshProvisionalBlockFromLineBuffer(theme: MarkdownTheme) {
        guard !lineBuffer.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        if lineBuffer.allSatisfy({ $0 == "`" }) || lineBuffer.hasPrefix("```") {
            return
        }

        if isPotentialHeadingPrefix(lineBuffer) {
            return
        }

        if isPotentialImagePrefix(lineBuffer) {
            return
        }

        if let image = parseImage(lineBuffer) {
            appendBlock(.init(id: makeID(), kind: .image(source: image.source, alt: image.alt)), theme: theme)
            lineBuffer.removeAll(keepingCapacity: true)
            return
        }

        if let heading = parseHeading(lineBuffer) {
            let id = makeID()
            appendBlock(.init(id: id, kind: .heading(level: heading.level, text: heading.text)), theme: theme)
            openBlock = .heading(id: id, level: heading.level, text: heading.text)
            return
        }

        let id = makeID()
        appendBlock(.init(id: id, kind: .paragraph(lineBuffer)), theme: theme)
        openBlock = .paragraph(id: id, text: "")
    }

    private func appendBlock(_ block: RawBlock, theme: MarkdownTheme) {
        rawBlocks.append(block)
        processedBlocks.append(render(block, theme: theme))
    }

    private func makeID() -> UUID {
        defer { nextBlockIndex += 1 }

        guard let idSeed else {
            return UUID()
        }

        return Self.uuid(from: "\(idSeed)#\(nextBlockIndex)")
    }

    private static func uuid(from seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func replaceBlock(id: UUID, with kind: RawBlockKind, theme: MarkdownTheme) {
        guard let index = rawBlocks.firstIndex(where: { $0.id == id }) else { return }
        rawBlocks[index].kind = kind
        processedBlocks[index] = render(rawBlocks[index], theme: theme)
    }

    private func finalizeOpenBlock(theme: MarkdownTheme) {
        guard let openBlock else { return }

        let id = switch openBlock {
        case .paragraph(let id, _), .heading(let id, _, _), .code(let id, _, _):
            id
        }

        self.openBlock = nil
        guard let index = rawBlocks.firstIndex(where: { $0.id == id }) else { return }
        processedBlocks[index] = render(rawBlocks[index], theme: theme)
    }

    private func render(_ block: RawBlock, theme: MarkdownTheme) -> ChatBlock {
        let renderedID = renderedID(for: block)

        switch block.kind {
        case .paragraph(let text):
            return ChatBlock(id: renderedID, kind: .paragraph(renderInline(text, font: theme.bodyFont, color: theme.bodyColor, theme: theme)))

        case .heading(let level, let text):
            let font = theme.headingFonts[level] ?? .headline
            return ChatBlock(id: renderedID, kind: .heading(
                level: level,
                text: renderInline(text, font: font, color: theme.headingColor, theme: theme)
            ))

        case .code(let language, let code, let isClosed):
            let codeBlock = CodeBlock(
                language: language,
                code: code,
                highlightedCode: highlightCode(code: code, isClosed: isClosed),
                isClosed: isClosed
            )
            return ChatBlock(id: renderedID, kind: .code(codeBlock))

        case .image(let source, let alt):
            return ChatBlock(id: renderedID, kind: .image(source: source, alt: alt))
        }
    }

    private func renderedID(for block: RawBlock) -> UUID {
        guard isOpenBlock(id: block.id) else { return block.id }
        return Self.uuid(from: "\(block.id.uuidString)#partial#\(block.kind.identitySeed)")
    }

    private func isOpenBlock(id: UUID) -> Bool {
        switch openBlock {
        case .paragraph(let openID, _),
             .heading(let openID, _, _),
             .code(let openID, _, _):
            openID == id
        case nil:
            false
        }
    }

    private func renderInline(_ source: String, font: SwiftUI.Font, color: SwiftUI.Color, theme: MarkdownTheme) -> AttributedString {
        InlineAttributedRenderer(theme: theme, baseFont: font, baseColor: color).render(source)
    }

    private func highlightCode(code: String, isClosed: Bool) -> AttributedString {
        let codeForHighlighting = isClosed ? code : code + "\n```"
        let highlighter = SyntaxHighlighter(
            format: AttributedStringOutputFormat(theme: .wwdc17(withFont: Splash.Font(size: 14)))
        )
        return AttributedString(highlighter.highlight(codeForHighlighting))
    }

    private func isOpeningFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("```")
    }

    private func isClosingFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 && trimmed.allSatisfy { $0 == "`" }
    }

    private func parseFenceLanguage(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return nil }
        let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return language.isEmpty ? nil : String(language)
    }

    private func parseImage(_ line: String) -> MarkdownImage? {
        guard line.hasPrefix("!["), let altEnd = line.firstIndex(of: "]") else { return nil }
        let parenStart = line.index(after: altEnd)
        guard parenStart < line.endIndex, line[parenStart] == "(" else { return nil }
        guard line.last == ")" else { return nil }

        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<altEnd])
        let sourceStart = line.index(after: parenStart)
        let sourceEnd = line.index(before: line.endIndex)
        let source = String(line[sourceStart..<sourceEnd])

        guard let url = URL(string: source), !source.isEmpty else { return nil }
        return MarkdownImage(source: url, alt: alt.isEmpty ? nil : alt)
    }

    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let markerEnd = line.index(line.startIndex, offsetBy: hashes)
        guard markerEnd < line.endIndex, line[markerEnd] == " " else { return nil }
        return (hashes, line.headingText(level: hashes))
    }

    private func isPotentialHeadingPrefix(_ line: String) -> Bool {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return false }
        return line.count == hashes
    }

    private func isPotentialImagePrefix(_ line: String) -> Bool {
        line == "!" || line.hasPrefix("![")
    }
}

struct InlineAttributedRenderer {
    var theme: MarkdownTheme
    var baseFont: SwiftUI.Font
    var baseColor: SwiftUI.Color

    func render(_ source: String) -> AttributedString {
        let segments = applyRegexHighlights(to: parseEmphasisAndCode(source))
        return segments.reduce(into: AttributedString()) { result, segment in
            result += segment.attributedString
        }
    }

    private func parseEmphasisAndCode(_ source: String) -> [InlineAttributedSegment] {
        var segments: [InlineAttributedSegment] = []
        var index = source.startIndex
        var plain = ""

        func flushPlain() {
            guard !plain.isEmpty else { return }
            segments.append(.init(value: plain, font: baseFont, foreground: baseColor))
            plain.removeAll(keepingCapacity: true)
        }

        while index < source.endIndex {
            if source[index] == "`", let end = source[source.index(after: index)...].firstIndex(of: "`") {
                flushPlain()
                let contentStart = source.index(after: index)
                segments.append(.init(
                    value: String(source[contentStart..<end]),
                    font: theme.inlineCodeFont,
                    foreground: theme.inlineCodeForeground,
                    allowsRegexHighlights: false
                ))
                index = source.index(after: end)
                continue
            }

            if source[index...].hasPrefix("**") {
                let contentStart = source.index(index, offsetBy: 2)
                if let range = source[contentStart...].range(of: "**") {
                    flushPlain()
                    segments.append(.init(
                        value: String(source[contentStart..<range.lowerBound]),
                        font: theme.boldFont,
                        foreground: baseColor
                    ))
                    index = range.upperBound
                    continue
                }
            }

            plain.append(source[index])
            index = source.index(after: index)
        }

        flushPlain()
        return segments
    }

    private func applyRegexHighlights(to segments: [InlineAttributedSegment]) -> [InlineAttributedSegment] {
        theme.regexHighlights.reduce(segments) { currentSegments, highlight in
            guard let regex = try? NSRegularExpression(pattern: highlight.pattern) else { return currentSegments }
            return currentSegments.flatMap { segment in
                guard segment.allowsRegexHighlights else { return [segment] }
                return highlightedSegments(for: segment, regex: regex, highlight: highlight)
            }
        }
    }

    private func highlightedSegments(
        for segment: InlineAttributedSegment,
        regex: NSRegularExpression,
        highlight: RegexHighlight
    ) -> [InlineAttributedSegment] {
        let nsRange = NSRange(segment.value.startIndex..<segment.value.endIndex, in: segment.value)
        let matches = regex.matches(in: segment.value, range: nsRange)
        guard !matches.isEmpty else { return [segment] }

        var result: [InlineAttributedSegment] = []
        var cursor = segment.value.startIndex

        for match in matches {
            guard let range = Range(match.range, in: segment.value) else { continue }

            if cursor < range.lowerBound {
                result.append(.init(
                    value: String(segment.value[cursor..<range.lowerBound]),
                    font: segment.font,
                    foreground: segment.foreground
                ))
            }

            result.append(.init(
                value: String(segment.value[range]),
                font: resolvedFont(for: highlight),
                foreground: resolvedForeground(for: highlight)
            ))

            cursor = range.upperBound
        }

        if cursor < segment.value.endIndex {
            result.append(.init(
                value: String(segment.value[cursor...]),
                font: segment.font,
                foreground: segment.foreground
            ))
        }

        return result
    }

    private func resolvedFont(for highlight: RegexHighlight) -> SwiftUI.Font {
        switch highlight.style {
        case .explicit:
            highlight.font
        case .quotedSpeech:
            theme.quoteHighlightFont
        }
    }

    private func resolvedForeground(for highlight: RegexHighlight) -> SwiftUI.Color {
        switch highlight.style {
        case .explicit:
            highlight.foreground
        case .quotedSpeech:
            theme.quoteHighlightForeground
        }
    }
}

private struct InlineAttributedSegment {
    var value: String
    var font: SwiftUI.Font
    var foreground: SwiftUI.Color
    var allowsRegexHighlights = true

    var attributedString: AttributedString {
        var result = AttributedString(value)
        result.font = font
        result.foregroundColor = foreground
        return result
    }
}

private extension String {
    var normalizedLineEndings: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    func headingText(level: Int) -> String {
        let marker = String(repeating: "#", count: level) + " "
        guard hasPrefix(marker) else { return self }
        return String(dropFirst(marker.count))
    }
}
