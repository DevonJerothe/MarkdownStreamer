import Foundation
import SwiftUI
import Testing
@testable import MarkdownStreamer

@Test
@MainActor
func readerUpdatesFinalParagraphBlockWithChangingPartialID() async {
    let reader = MarkdownReader()

    let firstBlocks = await reader.append("Hel")
    let firstID = firstBlocks.first?.id
    let blocks = await reader.append("lo")

    #expect(blocks.count == 1)
    #expect(blocks.first?.id != firstID)
    #expect(blocks.first?.plainText == "Hello")
}

@Test
@MainActor
func readerBuildsStreamingCodeBlock() async {
    let reader = MarkdownReader()

    let blocks = await reader.append("```swift\nlet value = 1")

    #expect(blocks.count == 1)
    #expect(blocks.first?.codeBlock?.language == "swift")
    #expect(blocks.first?.codeBlock?.code == "let value = 1")
    #expect(blocks.first?.codeBlock?.isClosed == false)
}

@Test
@MainActor
func readerBuildsLanguageLessStreamingCodeBlock() async {
    let reader = MarkdownReader()

    let blocks = await reader.append("```\nTest()\n```")

    #expect(blocks.count == 1)
    #expect(blocks.first?.codeBlock?.language == nil)
    #expect(blocks.first?.codeBlock?.code == "Test()\n")
    #expect(blocks.first?.codeBlock?.isClosed == true)
}

@Test
@MainActor
func readerClosesCodeBlockWithoutFullDocumentParsing() async {
    let reader = MarkdownReader()

    let blocks = await reader.append("```swift\nlet value = 1\n```\nDone")

    #expect(blocks.count == 2)
    #expect(blocks[0].codeBlock?.code == "let value = 1\n")
    #expect(blocks[0].codeBlock?.isClosed == true)
    #expect(blocks[1].plainText == "Done")
}

@Test
func completedMarkdownUsesStableIDs() async {
    let markdown = "# Greeting\nThe assistant said"

    let first = await MarkdownReader.read(markdown)
    let second = await MarkdownReader.read(markdown)
    let sync = MarkdownReader.readSync(markdown)

    #expect(first.map(\.id) == second.map(\.id))
    #expect(first.map(\.id) == sync.map(\.id))
    #expect(first.map(\.plainText) == second.map(\.plainText))
    #expect(first.map(\.plainText) == sync.map(\.plainText))
}

@Test
@MainActor
func accumulatedReaderKeepsCompletedBlockIDsStable() async {
    let reader = MarkdownReader()

    let first = await reader.appendAccumulated("First\n\nSec")
    let completedID = first[0].id
    let partialID = first[1].id

    let second = await reader.appendAccumulated("First\n\nSecond")

    #expect(second[0].id == completedID)
    #expect(second[0].plainText == "First")
    #expect(second[1].id != partialID)
    #expect(second[1].plainText == "Second")
}

@Test
@MainActor
func accumulatedReaderSettlesPartialIDWhenBlockCompletes() async {
    let reader = MarkdownReader()

    let partial = await reader.appendAccumulated("First\n\nSecond")
    let partialID = partial[1].id

    let completed = await reader.appendAccumulated("First\n\nSecond\n\nThi")
    let settledID = completed[1].id

    let later = await reader.appendAccumulated("First\n\nSecond\n\nThird")

    #expect(settledID != partialID)
    #expect(completed[1].plainText == "Second")
    #expect(later[1].id == settledID)
    #expect(later[2].plainText == "Third")
}

@Test
func statelessReadsKeepExistingBlockIDsWhenMarkdownGrows() async {
    let shorter = "# Greeting\n\nThe assistant said"
    let longer = shorter + "\n\nDone"

    let asyncShorter = await MarkdownReader.read(shorter)
    let asyncLonger = await MarkdownReader.read(longer)
    let syncShorter = MarkdownReader.readSync(shorter)
    let syncLonger = MarkdownReader.readSync(longer)

    #expect(asyncLonger.prefix(asyncShorter.count).map(\.id) == asyncShorter.map(\.id))
    #expect(syncLonger.prefix(syncShorter.count).map(\.id) == syncShorter.map(\.id))
    #expect(asyncShorter.map(\.id) == syncShorter.map(\.id))
    #expect(asyncLonger.map(\.id) == syncLonger.map(\.id))
}

@Test
func readerCanReadCompleteMarkdownStatelessly() async {
    let markdown = """
    # Greeting
    The assistant said "Hello world"

    ```swift
    let value = 1
    ```
    ![Wave](https://example.com/wave.png)
    Done.
    """

    let blocks = await MarkdownReader.read(markdown)
    let syncBlocks = MarkdownReader.readSync(markdown)

    #expect(blocks.count == 5)
    #expect(syncBlocks.map(\.plainText) == blocks.map(\.plainText))
    #expect(blocks[0].headingLevel == 1)
    #expect(blocks[0].plainText == "Greeting")
    #expect(blocks[1].plainText == "The assistant said \"Hello world\"")
    #expect(blocks[2].codeBlock?.language == "swift")
    #expect(blocks[2].codeBlock?.code == "let value = 1\n")
    #expect(blocks[2].codeBlock?.isClosed == true)
    #expect(blocks[3].kind == .image(source: URL(string: "https://example.com/wave.png")!, alt: "Wave"))
    #expect(blocks[4].plainText == "Done.")
}

@Test
func statelessReadTreatsLanguageLessFenceAsCodeBlock() {
    let markdown = """
    ```
    Test()
    ```
    """

    let blocks = MarkdownReader.readSync(markdown)

    #expect(blocks.count == 1)
    #expect(blocks.first?.codeBlock?.language == nil)
    #expect(blocks.first?.codeBlock?.code == "Test()\n")
    #expect(blocks.first?.codeBlock?.isClosed == true)
}

@Test
@MainActor
func streamingFenceCanInterruptParagraphWithoutBlankLine() async {
    let reader = MarkdownReader()
    let markdown = """
    *A large crowed of people*
    ```
    Moral: Very Hight
    ```
    """

    let blocks = await reader.append(markdown)

    #expect(blocks.count == 2)
    #expect(blocks[0].plainText == "*A large crowed of people*")
    #expect(blocks[1].codeBlock?.language == nil)
    #expect(blocks[1].codeBlock?.code == "Moral: Very Hight\n")
    #expect(blocks[1].codeBlock?.isClosed == true)
}

@Test
func statelessFenceCanInterruptParagraphWithoutBlankLine() {
    let markdown = """
    *A large crowed of people*
    ```
    Moral: Very Hight
    ```
    """

    let blocks = MarkdownReader.readSync(markdown)

    #expect(blocks.count == 2)
    #expect(blocks[0].plainText == "*A large crowed of people*")
    #expect(blocks[1].codeBlock?.language == nil)
    #expect(blocks[1].codeBlock?.code == "Moral: Very Hight\n")
    #expect(blocks[1].codeBlock?.isClosed == true)
}

@Test
@MainActor
func languageLessFenceWithCRLFLineEndingsClosesCorrectly() async {
    let markdown = "*A great crowd has gathered around {{user}}'s dungeon, it is early morning.*\r\n\"Brothers, sisters, companions!\"\r\n\r\n*Everyone begins to march inside the dungeon...*\r\n\r\n```\r\nMorale: Very High\r\nWarriors: 1000\r\n```"
    let reader = MarkdownReader()

    let streamingBlocks = await reader.append(markdown)
    let syncBlocks = MarkdownReader.readSync(markdown)

    #expect(streamingBlocks.count == 3)
    #expect(syncBlocks.count == 3)
    #expect(streamingBlocks.last?.codeBlock?.language == nil)
    #expect(streamingBlocks.last?.codeBlock?.code == "Morale: Very High\nWarriors: 1000\n")
    #expect(streamingBlocks.last?.codeBlock?.isClosed == true)
    #expect(syncBlocks.last?.codeBlock?.language == nil)
    #expect(syncBlocks.last?.codeBlock?.code == "Morale: Very High\nWarriors: 1000\n")
    #expect(syncBlocks.last?.codeBlock?.isClosed == true)
}

@Test
func inlineCodeRemainsParagraphText() {
    let markdown = "`Test()`"

    let blocks = MarkdownReader.readSync(markdown)

    #expect(blocks.count == 1)
    #expect(blocks.first?.codeBlock == nil)
    #expect(blocks.first?.plainText == "Test()")
}

@Test
func quotedSpeechHighlightingIsDisabledByDefault() {
    let markdown = #"He said "hello" and “goodbye”."#

    let blocks = MarkdownReader.readSync(markdown)

    #expect(blocks.first?.foregroundColor(for: #""hello""#) != .blue)
    #expect(blocks.first?.foregroundColor(for: #"“goodbye”"#) != .blue)
}

@Test
func customThemeHighlightsStraightAndCurlyQuotedSpeech() {
    let markdown = #"He said "hello" and “goodbye”."#
    var theme = MarkdownTheme.default
    theme.regexHighlights = [.standardQuotedSpeech]

    let blocks = MarkdownReader.readSync(markdown, theme: theme)

    #expect(blocks.first?.foregroundColor(for: #""hello""#) == .blue)
    #expect(blocks.first?.foregroundColor(for: #"“goodbye”"#) == .blue)
}

@Test
func quotedSpeechHighlightUsesThemeQuoteSettings() {
    let markdown = #"He said "hello"."#
    var theme = MarkdownTheme.default
    theme.quoteHighlightFont = .title.bold()
    theme.quoteHighlightForeground = .green
    theme.regexHighlights = [.standardQuotedSpeech]

    let blocks = MarkdownReader.readSync(markdown, theme: theme)

    #expect(blocks.first?.font(for: #""hello""#) == theme.quoteHighlightFont)
    #expect(blocks.first?.foregroundColor(for: #""hello""#) == theme.quoteHighlightForeground)
}

@Test
func inlineCodeQuotesAreNotHighlightedAsSpeech() {
    let markdown = #"Run `"quotedCode"` before "speech"."#
    var theme = MarkdownTheme.default
    theme.regexHighlights = [.standardQuotedSpeech]

    let blocks = MarkdownReader.readSync(markdown, theme: theme)

    #expect(blocks.first?.foregroundColor(for: #""quotedCode""#) == theme.inlineCodeForeground)
    #expect(blocks.first?.foregroundColor(for: #""speech""#) == .blue)
}

@Test
@MainActor
func streamingQuotedSpeechHighlightsWhenClosingQuoteArrives() async {
    let reader = MarkdownReader(maximumFramesPerSecond: 120)
    var theme = MarkdownTheme.default
    theme.regexHighlights = [.standardQuotedSpeech]

    _ = await reader.append(#"He said "hello"#, theme: theme)
    let openQuoteBlocks = await reader.append(#"""#, theme: theme)

    #expect(openQuoteBlocks.first?.foregroundColor(for: #""hello""#) == .blue)
}

private extension ChatBlock {
    var plainText: String? {
        switch kind {
        case .paragraph(let text), .heading(_, let text):
            String(text.characters)
        case .code(let block):
            block.code
        case .image:
            nil
        }
    }

    var headingLevel: Int? {
        guard case .heading(let level, _) = kind else { return nil }
        return level
    }

    var codeBlock: CodeBlock? {
        guard case .code(let block) = kind else { return nil }
        return block
    }

    func foregroundColor(for substring: String) -> SwiftUI.Color? {
        let attributedText: AttributedString
        switch kind {
        case .paragraph(let text), .heading(_, let text):
            attributedText = text
        case .code, .image:
            return nil
        }

        for run in attributedText.runs {
            let runText = String(attributedText[run.range].characters)
            if runText.contains(substring) {
                return run.foregroundColor
            }
        }

        return nil
    }

    func font(for substring: String) -> SwiftUI.Font? {
        let attributedText: AttributedString
        switch kind {
        case .paragraph(let text), .heading(_, let text):
            attributedText = text
        case .code, .image:
            return nil
        }

        for run in attributedText.runs {
            let runText = String(attributedText[run.range].characters)
            if runText.contains(substring) {
                return run.font
            }
        }

        return nil
    }
}
