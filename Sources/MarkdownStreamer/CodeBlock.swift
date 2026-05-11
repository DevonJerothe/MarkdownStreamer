import Foundation

public struct CodeBlock: Equatable, Sendable {
    public var language: String?
    public var code: String
    public var highlightedCode: AttributedString
    public var isClosed: Bool

    public init(
        language: String?,
        code: String,
        highlightedCode: AttributedString,
        isClosed: Bool
    ) {
        self.language = language
        self.code = code
        self.highlightedCode = highlightedCode
        self.isClosed = isClosed
    }

    public var codeWithPhantomClosure: String {
        isClosed ? code : code + "\n```"
    }

    public static func == (lhs: CodeBlock, rhs: CodeBlock) -> Bool {
        lhs.language == rhs.language
            && lhs.code == rhs.code
            && lhs.isClosed == rhs.isClosed
    }
}
