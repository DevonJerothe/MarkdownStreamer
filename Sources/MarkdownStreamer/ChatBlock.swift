import Foundation
import SwiftUI

public struct ChatBlock: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: ChatBlockKind

    public init(id: UUID = UUID(), kind: ChatBlockKind) {
        self.id = id
        self.kind = kind
    }

    public static func == (lhs: ChatBlock, rhs: ChatBlock) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind
    }
}

public enum ChatBlockKind: Equatable, Sendable {
    case paragraph(AttributedString)
    case heading(level: Int, text: AttributedString)
    case code(CodeBlock)
    case image(source: URL, alt: String?)

    public static func == (lhs: ChatBlockKind, rhs: ChatBlockKind) -> Bool {
        switch (lhs, rhs) {
        case (.paragraph(let lhs), .paragraph(let rhs)):
            lhs == rhs
        case (.heading(let lhsLevel, let lhsText), .heading(let rhsLevel, let rhsText)):
            lhsLevel == rhsLevel && lhsText == rhsText
        case (.code(let lhs), .code(let rhs)):
            lhs == rhs
        case (.image(let lhsSource, let lhsAlt), .image(let rhsSource, let rhsAlt)):
            lhsSource == rhsSource && lhsAlt == rhsAlt
        default:
            false
        }
    }
}

public struct MarkdownImage: Equatable, Sendable {
    public var source: URL
    public var alt: String?

    public init(source: URL, alt: String? = nil) {
        self.source = source
        self.alt = alt
    }
}
