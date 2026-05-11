import Foundation
import CryptoKit
import Splash
import SwiftUI

enum MarkdownSyncParser {
    static func read(_ markdown: String, theme: MarkdownTheme) -> [ChatBlock] {
        var parser = Parser(markdown: markdown, theme: theme)
        return parser.parse()
    }

    private struct Parser {
        var markdown: String
        var theme: MarkdownTheme
        var blocks: [ChatBlock] = []
        var paragraphLines: [String] = []
        var nextBlockIndex = 0

        mutating func parse() -> [ChatBlock] {
            var iterator = markdown.normalizedLineEndings
                .split(separator: "\n", omittingEmptySubsequences: false)
                .makeIterator()

            while let rawLine = iterator.next() {
                let line = String(rawLine)

                if isOpeningFence(line) {
                    flushParagraph()
                    parseCodeBlock(openingFence: line, iterator: &iterator)
                    continue
                }

                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    flushParagraph()
                    continue
                }

                if let image = parseImage(line) {
                    flushParagraph()
                    blocks.append(.init(id: makeID(), kind: .image(source: image.source, alt: image.alt)))
                    continue
                }

                if let heading = parseHeading(line) {
                    flushParagraph()
                    blocks.append(.init(
                        id: makeID(),
                        kind: .heading(
                            level: heading.level,
                            text: renderInline(
                                heading.text,
                                font: theme.headingFonts[heading.level] ?? .headline,
                                color: theme.headingColor
                            )
                        )
                    ))
                    continue
                }

                paragraphLines.append(line)
            }

            flushParagraph()
            return blocks
        }

        private mutating func parseCodeBlock(
            openingFence: String,
            iterator: inout IndexingIterator<[Substring]>
        ) {
            let language = parseFenceLanguage(openingFence)
            var code = ""
            var isClosed = false

            while let rawLine = iterator.next() {
                let line = String(rawLine)
                if isClosingFence(line) {
                    isClosed = true
                    break
                }

                code += line + "\n"
            }

            blocks.append(.init(
                id: makeID(),
                kind: .code(.init(
                    language: language,
                    code: code,
                    highlightedCode: highlightCode(code: code, isClosed: isClosed),
                    isClosed: isClosed
                ))
            ))
        }

        private mutating func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let text = paragraphLines.joined(separator: "\n")
            paragraphLines.removeAll(keepingCapacity: true)

            blocks.append(.init(
                id: makeID(),
                kind: .paragraph(renderInline(text, font: theme.bodyFont, color: theme.bodyColor))
            ))
        }

        private mutating func makeID() -> UUID {
            defer { nextBlockIndex += 1 }

            let digest = SHA256.hash(data: Data("MarkdownStreamer.Block#\(nextBlockIndex)".utf8))
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

        private func renderInline(_ source: String, font: SwiftUI.Font, color: SwiftUI.Color) -> AttributedString {
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
