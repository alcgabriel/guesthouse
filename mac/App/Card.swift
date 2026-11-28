import SwiftUI

/// The rounded panel the overview and sharing tabs are made of: the system's own control
/// background with a hairline, so it follows light and dark and the user's accent colour.
struct CardStyle: ViewModifier {
    /// A card that asks for the person's attention has the accent colour as its edge.
    var highlighted = false
    var padding: CGFloat = 14
    /// Fill the height the row gives, content at the top, so cards in a row are as tall as each other.
    var fillsHeight = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(highlighted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.1)),
                                  lineWidth: highlighted ? 1.5 : 1)
            }
    }
}

extension View {
    func card(highlighted: Bool = false, padding: CGFloat = 14, fillsHeight: Bool = false) -> some View {
        modifier(CardStyle(highlighted: highlighted, padding: padding, fillsHeight: fillsHeight))
    }
}

/// The small grey heading at the top of a card.
struct CardTitle: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// A coloured dot for a state, hidden from VoiceOver since the words beside it say the same.
struct StateDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
