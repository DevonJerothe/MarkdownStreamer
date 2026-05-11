import SwiftUI

struct AnimatedAttributedText: View {
    let text: AttributedString

    @Environment(\.markdownTokenAnimation) private var tokenAnimation
    @State private var displayedText: AttributedString?
    @State private var pendingText: AttributedString?
    @State private var displayTask: Task<Void, Never>?
    @State private var previousPlainText: String?
    @State private var animatedRange: Range<Int>?
    @State private var animatedOpacity = 1.0

    init(_ text: AttributedString) {
        self.text = text
    }

    var body: some View {
        renderedText
            .onAppear {
                displayedText = text
                previousPlainText = displayedPlainText
            }
            .onChange(of: text) { _, _ in
                handleSourceTextChange()
            }
            .onChange(of: displayedPlainText) { _, newValue in
                guard tokenAnimation.isEnabled else {
                    previousPlainText = newValue
                    animatedRange = nil
                    animatedOpacity = 1
                    return
                }

                guard
                    let previousValue = previousPlainText,
                    newValue.hasPrefix(previousValue),
                    newValue.count > previousValue.count
                else {
                    previousPlainText = newValue
                    animatedRange = nil
                    animatedOpacity = 1
                    return
                }

                let range = previousValue.count..<newValue.count
                let animation = tokenAnimation.animation
                animatedRange = range

                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    animatedOpacity = tokenAnimation.initialOpacity
                }

                Task { @MainActor in
                    await Task.yield()
                    guard animatedRange == range else { return }
                    withAnimation(animation) {
                        animatedOpacity = 1
                    }
                }

                previousPlainText = newValue
            }
            .onDisappear {
                displayTask?.cancel()
                displayTask = nil
                pendingText = nil
            }
    }

    private var renderedText: Text {
        let text = visibleText

        guard
            tokenAnimation.isEnabled,
            let range = activeAnimatedRange,
            let slices = text.slices(forCharacterRange: range)
        else {
            return Text(text)
        }

        return Text(slices.before)
            + Text(slices.animated.applyingForegroundOpacity(activeAnimatedOpacity))
            + Text(slices.after)
    }

    private func handleSourceTextChange() {
        guard tokenAnimation.isEnabled else {
            displayTask?.cancel()
            displayTask = nil
            pendingText = nil
            displayedText = text
            return
        }

        pendingText = text
        schedulePendingTextDisplay()
    }

    private func schedulePendingTextDisplay() {
        guard displayTask == nil else { return }

        let interval = max(tokenAnimation.minimumUpdateInterval, 0)
        guard interval > 0 else {
            flushPendingText()
            return
        }

        displayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            flushPendingText()
        }
    }

    private func flushPendingText() {
        guard let pendingText else {
            displayTask = nil
            return
        }

        self.pendingText = nil
        displayedText = pendingText
        displayTask = nil
    }

    private var activeAnimatedRange: Range<Int>? {
        if let animatedRange {
            return animatedRange
        }

        guard
            tokenAnimation.isEnabled,
            let previousPlainText,
            displayedPlainText.hasPrefix(previousPlainText),
            displayedPlainText.count > previousPlainText.count
        else {
            return nil
        }

        return previousPlainText.count..<displayedPlainText.count
    }

    private var activeAnimatedOpacity: Double {
        if animatedRange == nil, activeAnimatedRange != nil {
            return tokenAnimation.initialOpacity
        }

        return animatedOpacity
    }

    private var visibleText: AttributedString {
        displayedText ?? text
    }

    private var displayedPlainText: String {
        String(visibleText.characters)
    }
}

private extension AttributedString {
    func slices(forCharacterRange range: Range<Int>) -> (
        before: AttributedString,
        animated: AttributedString,
        after: AttributedString
    )? {
        guard
            range.lowerBound >= 0,
            range.upperBound <= characters.count,
            range.lowerBound < range.upperBound
        else {
            return nil
        }

        let lower = characters.index(startIndex, offsetBy: range.lowerBound)
        let upper = characters.index(startIndex, offsetBy: range.upperBound)

        return (
            AttributedString(self[startIndex..<lower]),
            AttributedString(self[lower..<upper]),
            AttributedString(self[upper..<endIndex])
        )
    }

    func applyingForegroundOpacity(_ opacity: Double) -> AttributedString {
        var result = self

        for run in result.runs {
            if let color = run.foregroundColor {
                result[run.range].foregroundColor = color.opacity(opacity)
            } else {
                result[run.range].foregroundColor = Color.primary.opacity(opacity)
            }
        }

        return result
    }
}
