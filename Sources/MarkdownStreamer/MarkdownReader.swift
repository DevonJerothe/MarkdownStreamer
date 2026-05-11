import Combine
import Foundation

@MainActor
public final class MarkdownReader: ObservableObject {
    @Published public private(set) var blocks: [ChatBlock] = []

    private let processor: StreamProcessor
    private let frameIntervalNanoseconds: UInt64
    private var pendingBlocks: [ChatBlock]?
    private var publishTask: Task<Void, Never>?

    public init(
        processor: StreamProcessor = StreamProcessor(),
        maximumFramesPerSecond: Double = 30
    ) {
        self.processor = processor
        self.frameIntervalNanoseconds = UInt64(1_000_000_000 / max(maximumFramesPerSecond, 1))
    }

    public static func read(_ markdown: String, theme: MarkdownTheme = .default) async -> [ChatBlock] {
        await MarkdownBlockCache.shared.blocks(for: markdown, theme: theme)
    }

    nonisolated public static func readSync(_ markdown: String, theme: MarkdownTheme = .default) -> [ChatBlock] {
        MarkdownBlockCache.shared.blocksSync(for: markdown, theme: theme)
    }

    @discardableResult
    public func append(_ token: String, theme: MarkdownTheme = .default) async -> [ChatBlock] {
        let processedBlocks = await processor.process(token: token, theme: theme)
        schedulePublish(processedBlocks)
        return processedBlocks
    }

    @discardableResult
    public func appendAccumulated(_ text: String, theme: MarkdownTheme = .default) async -> [ChatBlock] {
        let processedBlocks = await processor.processAccumulated(text, theme: theme)
        schedulePublish(processedBlocks)
        return processedBlocks
    }

    @discardableResult
    public func finish(theme: MarkdownTheme = .default) async -> [ChatBlock] {
        let processedBlocks = await processor.finish(theme: theme)
        publishImmediately(processedBlocks)
        return processedBlocks
    }

    public func reset() async {
        publishTask?.cancel()
        publishTask = nil
        pendingBlocks = nil
        blocks.removeAll(keepingCapacity: true)
        await processor.reset()
    }

    private func schedulePublish(_ processedBlocks: [ChatBlock]) {
        pendingBlocks = processedBlocks

        guard publishTask == nil else { return }

        publishTask = Task { [frameIntervalNanoseconds] in
            try? await Task.sleep(nanoseconds: frameIntervalNanoseconds)
            await MainActor.run {
                self.flushPendingBlocks()
            }
        }
    }

    private func flushPendingBlocks() {
        guard let pendingBlocks else {
            publishTask = nil
            return
        }

        self.pendingBlocks = nil
        blocks = pendingBlocks
        publishTask = nil
    }

    private func publishImmediately(_ processedBlocks: [ChatBlock]) {
        publishTask?.cancel()
        publishTask = nil
        pendingBlocks = nil
        blocks = processedBlocks
    }
}
