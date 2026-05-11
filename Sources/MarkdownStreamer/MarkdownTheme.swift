import SwiftUI

public struct MarkdownTheme: Equatable, Sendable {
    public var bodyFont: Font
    public var bodyColor: Color
    public var headingFonts: [Int: Font]
    public var headingColor: Color
    public var boldFont: Font
    public var inlineCodeFont: Font
    public var inlineCodeForeground: Color
    public var inlineCodeBackground: Color
    public var quoteHighlightFont: Font
    public var quoteHighlightForeground: Color
    public var codeBlockBackground: Color
    public var regexHighlights: [RegexHighlight]

    public init(
        bodyFont: Font = .body,
        bodyColor: Color = .primary,
        headingFonts: [Int: Font] = [
            1: .largeTitle.bold(),
            2: .title.bold(),
            3: .title2.bold(),
        ],
        headingColor: Color = .primary,
        boldFont: Font = .body.bold(),
        inlineCodeFont: Font = .system(.body, design: .monospaced),
        inlineCodeForeground: Color = .pink,
        inlineCodeBackground: Color = Color.secondary.opacity(0.14),
        quoteHighlightFont: Font = .body.italic(),
        quoteHighlightForeground: Color = .blue,
        codeBlockBackground: Color = Color.secondary.opacity(0.12),
        regexHighlights: [RegexHighlight] = []
    ) {
        self.bodyFont = bodyFont
        self.bodyColor = bodyColor
        self.headingFonts = headingFonts
        self.headingColor = headingColor
        self.boldFont = boldFont
        self.inlineCodeFont = inlineCodeFont
        self.inlineCodeForeground = inlineCodeForeground
        self.inlineCodeBackground = inlineCodeBackground
        self.quoteHighlightFont = quoteHighlightFont
        self.quoteHighlightForeground = quoteHighlightForeground
        self.codeBlockBackground = codeBlockBackground
        self.regexHighlights = regexHighlights
    }

    public static let `default` = MarkdownTheme()
}

public struct RegexHighlight: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case explicit
        case quotedSpeech
    }

    public var pattern: String
    public var font: Font
    public var foreground: Color
    var style: Style

    public init(pattern: String, font: Font, foreground: Color) {
        self.pattern = pattern
        self.font = font
        self.foreground = foreground
        self.style = .explicit
    }

    init(pattern: String, font: Font, foreground: Color, style: Style) {
        self.pattern = pattern
        self.font = font
        self.foreground = foreground
        self.style = style
    }

    public static let standardQuotedSpeech = RegexHighlight(
        pattern: #"(?:"[^"]+"|“[^”]+”)"#,
        font: .body.italic(),
        foreground: .blue,
        style: .quotedSpeech
    )
}

private struct MarkdownThemeKey: EnvironmentKey {
    static let defaultValue = MarkdownTheme.default
}

public extension EnvironmentValues {
    var markdownTheme: MarkdownTheme {
        get { self[MarkdownThemeKey.self] }
        set { self[MarkdownThemeKey.self] = newValue }
    }
}

public extension View {
    func markdownTheme(_ theme: MarkdownTheme) -> some View {
        environment(\.markdownTheme, theme)
    }
}
