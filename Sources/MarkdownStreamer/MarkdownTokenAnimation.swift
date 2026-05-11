import SwiftUI

public struct MarkdownTokenAnimation: Sendable {
    public var isEnabled: Bool
    public var animation: Animation
    public var initialOpacity: Double
    public var minimumUpdateInterval: TimeInterval

    public init(
        isEnabled: Bool = true,
        animation: Animation = .easeOut(duration: 0.18),
        initialOpacity: Double = 0,
        minimumUpdateInterval: TimeInterval = 0.18
    ) {
        self.isEnabled = isEnabled
        self.animation = animation
        self.initialOpacity = initialOpacity
        self.minimumUpdateInterval = minimumUpdateInterval
    }

    public static let fade = MarkdownTokenAnimation()
    public static let none = MarkdownTokenAnimation(isEnabled: false, minimumUpdateInterval: 0)
}

private struct MarkdownTokenAnimationKey: EnvironmentKey {
    static let defaultValue = MarkdownTokenAnimation.none
}

public extension EnvironmentValues {
    var markdownTokenAnimation: MarkdownTokenAnimation {
        get { self[MarkdownTokenAnimationKey.self] }
        set { self[MarkdownTokenAnimationKey.self] = newValue }
    }
}

public extension View {
    func markdownTokenAnimation(_ animation: MarkdownTokenAnimation) -> some View {
        environment(\.markdownTokenAnimation, animation)
    }
}
