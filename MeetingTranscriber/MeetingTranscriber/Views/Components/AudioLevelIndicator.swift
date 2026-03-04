import SwiftUI

struct AudioLevelIndicator: View {
    let level: Float
    let barCount: Int

    init(level: Float, barCount: Int = 5) {
        self.level = level
        self.barCount = barCount
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .frame(height: 24)
        .animation(.easeInOut(duration: 0.1), value: level)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let threshold = Float(index) / Float(barCount)
        let active = level > threshold
        return active ? CGFloat(8 + index * 4) : 4
    }

    private func barColor(for index: Int) -> Color {
        let threshold = Float(index) / Float(barCount)
        if level > threshold {
            if index < barCount / 2 {
                return .green
            } else if index < barCount * 3 / 4 {
                return .yellow
            } else {
                return .red
            }
        }
        return .gray.opacity(0.3)
    }
}
