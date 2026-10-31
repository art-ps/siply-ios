import SwiftUI

/// Живой mesh-фон плеера: точки дрейфуют, амплитуда и подсветка растут с громкостью.
struct PlayerBackground: View {
    let colors: [Color]
    let level: () -> Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var smoother = Smoother()
    @State private var start = Date()

    init(colors: [Color], level: @escaping () -> Float) {
        self.colors = colors
        self.level = level
    }

    /// Сглаживание уровня; класс, чтобы менять из body без записи в @State.
    final class Smoother {
        var value: Float = 0
        func push(_ level: Float) -> Float {
            value = value * 0.85 + level * 0.15
            return value
        }
    }

    var body: some View {
        // 30 fps хватает: дрейф 8–14 с, пульс сглажен; на 120 Гц жгло бы батарею.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 0 : ctx.date.timeIntervalSince(start)
            let s = reduceMotion ? 0 : smoother.push(level())
            MeshGradient(width: 3, height: 3,
                         points: Self.points(at: t, amplitude: 0.08 + 0.06 * s),
                         colors: colors)
                .overlay(Color.white.opacity(Double(0.12 * s)))
                .ignoresSafeArea()
        }
    }

    /// 9 точек сетки 3x3 построчно. Углы неподвижны, рёбра скользят вдоль своего края, центр — в обе стороны.
    nonisolated static func points(at t: Double, amplitude: Float) -> [SIMD2<Float>] {
        func d(_ period: Float, _ phase: Float) -> Float {
            amplitude * sin(Float(t) * 2 * .pi / period + phase)
        }
        func unit(_ v: Float) -> Float { min(max(v, 0), 1) }
        return [
            [0, 0], [unit(0.5 + d(8, 0)), 0], [1, 0],
            [0, unit(0.5 + d(10, 1.3))], [unit(0.5 + d(11, 5.2)), unit(0.5 + d(13, 0.7))], [1, unit(0.5 + d(12, 2.6))],
            [0, 1], [unit(0.5 + d(14, 3.9)), 1], [1, 1],
        ]
    }
}
