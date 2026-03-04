import SwiftUI

struct SpeakerBadge: View {
    let label: String
    let color: Color

    init(label: String, color: Color? = nil) {
        self.label = label
        self.color = color ?? Self.colorForSpeaker(label)
    }

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    static func colorForSpeaker(_ label: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .teal, .pink, .indigo]
        guard let number = label.split(separator: " ").last.flatMap({ Int($0) }) else {
            return .blue
        }
        return colors[(number - 1) % colors.count]
    }
}
