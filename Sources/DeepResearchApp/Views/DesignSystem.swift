import SwiftUI

// MARK: - Color Palette

extension Color {
    // Primary gradient colors - Minimalistic pastels
    static let dsIndigo = Color(red: 0.722, green: 0.710, blue: 1.0)       // #B8B5FF - Soft pastel indigo
    static let dsVibrantPurple = Color(red: 0.831, green: 0.773, blue: 0.976) // #D4C5F9 - Soft lavender

    // Accent colors - Soft pastels
    static let dsTeal = Color(red: 0.706, green: 0.894, blue: 0.933)        // #B4E4EE - Soft sky blue
    static let dsAmber = Color(red: 1.0, green: 0.894, blue: 0.710)         // #FFE4B5 - Soft peach
    static let dsEmerald = Color(red: 0.757, green: 0.941, blue: 0.835)     // #C1F0D5 - Soft mint green

    // Backgrounds - Enterprise polish
    static let dsBackground = Color(red: 0.980, green: 0.984, blue: 0.988)  // #FAFBFC - Near-white
    static let dsCardBackground = Color(NSColor.controlBackgroundColor)

    // Text colors - Refined for pastels
    static let dsNavy = Color(red: 0.176, green: 0.216, blue: 0.282)        // #2D3748 - Softer dark gray
    static let dsSlate = Color(red: 0.443, green: 0.502, blue: 0.588)       // #718096 - Softer medium gray
    static let dsLightSlate = Color(red: 0.627, green: 0.682, blue: 0.753)  // #A0AEC0 - Softer light gray

    // Surface colors - Subtle backgrounds
    static let dsSurface = Color(red: 0.969, green: 0.980, blue: 0.988)     // #F7FAFC - Very light gray
    static let dsBorder = Color(red: 0.910, green: 0.925, blue: 0.941)      // #E8ECF0 - Softer border

    // Status colors - Soft pastels
    static let dsSuccess = Color(red: 0.757, green: 0.941, blue: 0.835)     // #C1F0D5 - Soft mint green
    static let dsError = Color(red: 1.0, green: 0.831, blue: 0.831)         // #FFD4D4 - Soft coral pink
    static let dsWarning = Color(red: 1.0, green: 0.894, blue: 0.710)       // #FFE4B5 - Soft peach
}

// MARK: - ShapeStyle Accessors
// Required so `.foregroundStyle(.dsNavy)` resolves in generic ShapeStyle contexts.

extension ShapeStyle where Self == Color {
    static var dsIndigo: Color { Color.dsIndigo }
    static var dsVibrantPurple: Color { Color.dsVibrantPurple }
    static var dsTeal: Color { Color.dsTeal }
    static var dsAmber: Color { Color.dsAmber }
    static var dsEmerald: Color { Color.dsEmerald }
    static var dsBackground: Color { Color.dsBackground }
    static var dsCardBackground: Color { Color.dsCardBackground }
    static var dsNavy: Color { Color.dsNavy }
    static var dsSlate: Color { Color.dsSlate }
    static var dsLightSlate: Color { Color.dsLightSlate }
    static var dsSurface: Color { Color.dsSurface }
    static var dsBorder: Color { Color.dsBorder }
    static var dsSuccess: Color { Color.dsSuccess }
    static var dsError: Color { Color.dsError }
    static var dsWarning: Color { Color.dsWarning }
}

// MARK: - Gradients

extension LinearGradient {
    static let dsPrimary = LinearGradient(
        colors: [.dsIndigo, .dsVibrantPurple],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let dsPrimaryVertical = LinearGradient(
        colors: [.dsIndigo, .dsVibrantPurple],
        startPoint: .top,
        endPoint: .bottom
    )

    static let dsTealAccent = LinearGradient(
        colors: [.dsTeal, .dsIndigo],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let dsShimmer = LinearGradient(
        colors: [
            .dsSlate.opacity(0.05),
            .dsSlate.opacity(0.15),
            .dsSlate.opacity(0.05)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    // ChatGPT-style text shimmer gradient
    static let dsTextShimmer = LinearGradient(
        colors: [
            .dsSlate,
            .dsIndigo,
            .dsTeal,
            .dsIndigo,
            .dsSlate
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let dsProgressBar = LinearGradient(
        colors: [.dsIndigo, .dsTeal, .dsEmerald],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Shadow System

enum DSShadow {
    static let level1: [(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)] = [
        (color: Color.black.opacity(0.02), radius: 2.0, x: 0.0, y: 1.0)
    ]
    static let level2: [(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)] = [
        (color: Color.black.opacity(0.03), radius: 8.0, x: 0.0, y: 2.0),
        (color: Color.black.opacity(0.015), radius: 1.0, x: 0.0, y: 0.5)
    ]
    static let level3: [(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)] = [
        (color: Color.black.opacity(0.04), radius: 12.0, x: 0.0, y: 4.0),
        (color: Color.black.opacity(0.02), radius: 2.0, x: 0.0, y: 1.0)
    ]
    static let level4: [(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)] = [
        (color: Color.black.opacity(0.06), radius: 24.0, x: 0.0, y: 8.0),
        (color: Color.black.opacity(0.03), radius: 4.0, x: 0.0, y: 2.0)
    ]
}

// MARK: - Card Modifier

struct DSCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.dsCardBackground)
            .clipShape(.rect(cornerRadius: 16))
            .modifier(ApplyShadows(shadows: DSShadow.level2))
    }
}

struct ApplyShadows: ViewModifier {
    let shadows: [(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)]

    func body(content: Content) -> some View {
        shadows.reduce(AnyView(content)) { view, shadow in
            AnyView(view.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y))
        }
    }
}

extension View {
    func dsCard(padding: CGFloat = 16) -> some View {
        modifier(DSCardModifier(padding: padding))
    }
}

// MARK: - Glass Card Modifier

struct DSGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 16))
            .modifier(ApplyShadows(shadows: DSShadow.level1))
    }
}

extension View {
    func dsGlassCard() -> some View {
        modifier(DSGlassCardModifier())
    }
}

// MARK: - Inter Font System

extension Font {
    /// Creates an Inter font with the specified size and weight
    /// Falls back to system font if Inter is not available
    static func inter(_ size: CGFloat, weight: Weight = .regular) -> Font {
        return .custom("Inter", size: size).weight(weight)
    }

    // Semantic font scale using Inter
    static let dsLargeTitle = Font.inter(34, weight: .bold)
    static let dsTitle = Font.inter(28, weight: .bold)
    static let dsTitle2 = Font.inter(22, weight: .bold)
    static let dsTitle3 = Font.inter(20, weight: .semibold)
    static let dsHeadline = Font.inter(17, weight: .semibold)
    static let dsBody = Font.inter(17, weight: .regular)
    static let dsBodyMedium = Font.inter(17, weight: .medium)
    static let dsBodyBold = Font.inter(17, weight: .bold)
    static let dsSubheadline = Font.inter(15, weight: .medium)
    static let dsCallout = Font.inter(16, weight: .regular)
    static let dsCaption = Font.inter(12, weight: .regular)
    static let dsCaption2 = Font.inter(11, weight: .regular)
}

// MARK: - Button Styles

struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsBodyBold)
            .foregroundStyle(.dsNavy)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.dsIndigo)
            .clipShape(.rect(cornerRadius: 12))
            .modifier(ApplyShadows(shadows: DSShadow.level1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1.0) : 0.5)
            .saturation(isEnabled ? 1.0 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct DSSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsBodyBold)
            .foregroundStyle(isEnabled ? .dsNavy : .dsLightSlate)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.dsCardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.dsBorder, lineWidth: 1.5)
            }
            .modifier(ApplyShadows(shadows: DSShadow.level1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1.0) : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct DSDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsBodyBold)
            .foregroundStyle(isEnabled ? .dsError : .dsLightSlate)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.dsCardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEnabled ? Color.dsError.opacity(0.3) : Color.dsBorder, lineWidth: 1.5)
            }
            .modifier(ApplyShadows(shadows: DSShadow.level1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1.0) : 0.6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { DSPrimaryButtonStyle() }
}

extension ButtonStyle where Self == DSSecondaryButtonStyle {
    static var dsSecondary: DSSecondaryButtonStyle { DSSecondaryButtonStyle() }
}

extension ButtonStyle where Self == DSDestructiveButtonStyle {
    static var dsDestructive: DSDestructiveButtonStyle { DSDestructiveButtonStyle() }
}

// MARK: - Animation Constants

enum DSAnimation {
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let quick = Animation.easeOut(duration: 0.2)
    static let smooth = Animation.easeInOut(duration: 0.3)
    static let shimmer = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: false)
    static let textShimmer = Animation.linear(duration: 2.0).repeatForever(autoreverses: false)
    static let pulse = Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
    static let cursorBlink = Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
    static let streamingDots = Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: false)
    static let progressShimmer = Animation.linear(duration: 2).repeatForever(autoreverses: false)
}

// MARK: - Shimmer Effect

struct DSShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.4),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .onAppear {
                    withAnimation(DSAnimation.shimmer) {
                        phase = 200
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 8))
    }
}

extension View {
    func dsShimmer() -> some View {
        modifier(DSShimmerModifier())
    }
}

// MARK: - ChatGPT-Style Text Shimmer

struct DSTextShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        if isActive {
            content
                .overlay {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.8),
                                Color.white.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 2)
                        .offset(x: geometry.size.width * phase)
                        .onAppear {
                            withAnimation(DSAnimation.textShimmer) {
                                phase = 1.0
                            }
                        }
                    }
                }
                .mask(content)
        } else {
            content
        }
    }
}

extension View {
    func dsTextShimmer(isActive: Bool) -> some View {
        modifier(DSTextShimmerModifier(isActive: isActive))
    }
}

// MARK: - Pulse Effect

struct DSPulseModifier: ViewModifier {
    let isActive: Bool
    @State private var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? opacity : 1.0)
            .onAppear {
                if isActive {
                    withAnimation(DSAnimation.pulse) {
                        opacity = 0.6
                    }
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    withAnimation(DSAnimation.pulse) {
                        opacity = 0.6
                    }
                } else {
                    opacity = 1.0
                }
            }
    }
}

extension View {
    func dsPulse(isActive: Bool) -> some View {
        modifier(DSPulseModifier(isActive: isActive))
    }
}

// MARK: - Streaming Cursor

struct StreamingCursor: View {
    @State private var opacity: Double = 1.0

    var body: some View {
        Rectangle()
            .fill(Color.dsIndigo)
            .frame(width: 2, height: 16)
            .opacity(opacity)
            .onAppear {
                withAnimation(DSAnimation.cursorBlink) {
                    opacity = 0.2
                }
            }
    }
}

// MARK: - Status Badge

struct DSStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.dsCaption)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(.capsule)
    }
}

// MARK: - Section Header

struct DSSectionHeader: View {
    let title: String
    let icon: String?

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.dsSubheadline)
                    .foregroundStyle(.dsIndigo)
            }
            Text(title)
                .font(.dsTitle3)
                .foregroundStyle(.dsNavy)
        }
    }
}
