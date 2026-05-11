import Foundation

actor MarkdownBlockCache {
    static let shared = MarkdownBlockCache()

    private static let lock = NSLock()
    nonisolated(unsafe) private static var syncStorage: [String: [ChatBlock]] = [:]

    private var storage: [String: [ChatBlock]] = [:]

    func blocks(for markdown: String, theme: MarkdownTheme) async -> [ChatBlock] {
        let key = cacheKey(markdown: markdown, theme: theme)

        if let cached = Self.cachedBlocks(for: key) {
            return cached
        }

        if let cached = storage[key] {
            return cached
        }

        let blocks = await StreamProcessor.read(markdown, theme: theme)
        storage[key] = blocks
        Self.store(blocks, for: key)
        return blocks
    }

    nonisolated func blocksSync(for markdown: String, theme: MarkdownTheme) -> [ChatBlock] {
        let key = cacheKey(markdown: markdown, theme: theme)

        if let cached = Self.cachedBlocks(for: key) {
            return cached
        }

        let blocks = MarkdownSyncParser.read(markdown, theme: theme)
        Self.store(blocks, for: key)
        return blocks
    }

    nonisolated private func cacheKey(markdown: String, theme: MarkdownTheme) -> String {
        markdown + "\u{1F}" + String(describing: theme)
    }

    private static func cachedBlocks(for key: String) -> [ChatBlock]? {
        lock.lock()
        defer { lock.unlock() }
        return syncStorage[key]
    }

    private static func store(_ blocks: [ChatBlock], for key: String) {
        lock.lock()
        defer { lock.unlock() }
        syncStorage[key] = blocks
    }
}
