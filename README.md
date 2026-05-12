# MarkdownStreamer

`MarkdownStreamer` renders streaming LLM Markdown in SwiftUI with block-level incremental processing.

The current pipeline avoids doing Markdown parsing or Splash highlighting inside SwiftUI `body`. Tokens are processed by a background `StreamProcessor` actor, then `MarkdownReader` publishes updates to the UI block by block.

## Streaming Usage

Keep one `MarkdownReader` for the message that is actively streaming:

```swift
import SwiftUI
import MarkdownStreamer

struct MessageView: View {
    @StateObject private var reader = MarkdownReader()
    @Environment(\.markdownTheme) private var theme

    var body: some View {
        ScrollView {
            StreamingMarkdownView(blocks: reader.blocks)
                .padding()
        }
        .task {
            for await token in streamLLMResponse() {
                await reader.append(token, theme: theme)
            }

            await reader.finish(theme: theme)
        }
    }
}
```

`MarkdownReader` throttles `@Published` updates to at most 30 FPS by default:

```swift
let reader = MarkdownReader(maximumFramesPerSecond: 30)
```

## Completed Messages

For completed chat messages, use the stateless string initializer:

```swift
StreamingMarkdownView(markdown: message.text)
```

Completed strings are parsed synchronously in the view initializer through a shared cache and use deterministic block IDs. This avoids the empty-first-layout flash that can make parent scroll views jump.

You can also precompute blocks yourself:

```swift
let blocks = MarkdownReader.readSync(message.text, theme: theme)
```

The async cached reader remains available for non-UI precomputation:

```swift
let blocks = await MarkdownReader.read(message.text, theme: theme)
```

## Accumulated Text Streams

Full accumulated message updates are supported through the `appendAccumulated(_:theme:)` method:

```swift
await reader.appendAccumulated("# Gre", theme: theme)
await reader.appendAccumulated("# Greetings\nThe", theme: theme)
await reader.appendAccumulated("# Greetings\nThe assistant said", theme: theme)
```

Only the new suffix is processed.

## Custom Code and Image Views

Custom code and image views are passed through the `StreamingMarkdownView` initializer:

```swift
StreamingMarkdownView(
    blocks: reader.blocks,
    codeView: { block in
        MyCodeBlockView(
            language: block.language,
            code: block.code,
            highlightedCode: block.highlightedCode
        )
    },
    imageView: { image in
        MyRemoteImageView(url: image.source, alt: image.alt)
    }
)
```

The default image provider supports caching and remote image loading.

`CodeBlock.highlightedCode` is precomputed by `StreamProcessor`; custom code views do not need to run Splash on the main thread.

## Theming

Create a `MarkdownTheme` to control typography and colors for rendered Markdown:

```swift
let chatTheme = MarkdownTheme(
    bodyFont: .body,
    bodyColor: .primary,
    headingFonts: [
        1: .title.bold(),
        2: .title2.bold(),
        3: .headline
    ],
    headingColor: .primary,
    boldFont: .body.bold(),
    inlineCodeFont: .system(.body, design: .monospaced),
    inlineCodeForeground: .pink,
    inlineCodeBackground: .secondary.opacity(0.14),
    quoteHighlightFont: .body.italic(),
    quoteHighlightForeground: .blue,
    codeBlockBackground: .black.opacity(0.88),
    regexHighlights: [
        .standardQuotedSpeech
    ]
)
```

`quoteHighlightFont` and `quoteHighlightForeground` control the style of quoted speech highlights. This is only applied if `regexHighlights` includes `.standardQuotedSpeech`.
`.standardQuotedSpeech` is a built-in regex highlight that highlights text wrapped in straight double quotes or smart curly double quotes. Commonly used in conversational AI.

Pass the same theme to the reader while streaming:

```swift
await reader.append(token, theme: chatTheme)
await reader.appendAccumulated(message.text, theme: chatTheme)
```

to apply the theme after stremaing use the `markdownTheme(_:)` modifier:

```swift
StreamingMarkdownView(blocks: reader.blocks)
    .markdownTheme(chatTheme)
```

For synchronous completed-string rendering, pass the theme at init time:

```swift
StreamingMarkdownView(markdown: message.text, theme: chatTheme)
```

The theme is used by `StreamProcessor` for headings, bold text, inline code, code block containers, and regex highlights.

### Regex Highlights

Regex highlights let you style custom inline patterns during parsing. They are disabled by default; enable quoted speech by adding `.standardQuotedSpeech` to a custom theme. It highlights text wrapped in straight double quotes or smart curly double quotes:

```swift
var theme = MarkdownTheme.default
theme.regexHighlights = [
    .standardQuotedSpeech
]
```

You can add additional app-specific highlights:

```swift
let commandTheme = MarkdownTheme(
    regexHighlights: [
        RegexHighlight(
            pattern: #"@[A-Za-z0-9_]+"#,
            font: .body.bold(),
            foreground: .purple
        ),
        .standardQuotedSpeech
    ]
)
```

Because completed markdown is parsed synchronously at init time, pass custom themes directly to `StreamingMarkdownView(markdown:theme:)`. For streaming messages, pass the same theme into `MarkdownReader.append(_:theme:)` and `finish(theme:)`.

## Token Animations

Animations are opt-in:

```swift
StreamingMarkdownView(blocks: reader.blocks)
    .markdownTokenAnimation(.fade)
```

Custom policy:

```swift
StreamingMarkdownView(blocks: reader.blocks)
    .markdownTokenAnimation(
        MarkdownTokenAnimation(
            animation: .spring(response: 0.24, dampingFraction: 0.9),
            initialOpacity: 0.15,
            minimumUpdateInterval: 0.24
        )
    )
```

`minimumUpdateInterval` limits how often text updates are presented while token animations are enabled. Fast streams are buffered to the latest received text so the active animation can complete smoothly instead of being restarted for every incoming token.

## Supported Blocks

- Paragraphs
- Headings using `#` through `######`
- Fenced code blocks
- Images in the form `![alt](url)`
