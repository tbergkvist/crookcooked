import SwiftUI
import CrookcookedCore

/// The brand mark, alive: it glances around and blinks.
///
/// Motion comes from short animations started at random intervals, not a frame
/// timer, so between glances the view costs nothing. Its mood follows the status:
/// drowsy while disarmed, wide awake while armed, startled when triggered.
struct WatchingBlob: View {
    let status: CrookcookedStatus
    var size: CGFloat = 78
    var color: Color

    @State private var gaze = CGSize.zero
    @State private var blinking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: size / 2, bottomLeading: size * 5 / 22, bottomTrailing: size / 2, topTrailing: size / 2),
                style: .continuous
            )
            .fill(color)
            .shadow(color: color.opacity(status == .disarmed ? 0.15 : 0.5), radius: size * 0.22)

            eye(centreX: 7.5 / 22)
            eye(centreX: 14.5 / 22)
        }
        .frame(width: size, height: size)
        // Matches the site's `rotate(-7deg)`.
        .rotationEffect(.degrees(-7))
        .animation(.easeInOut(duration: 0.3), value: status)
        .task(id: status) { await live() }
        .accessibilityHidden(true)
    }

    private func eye(centreX: CGFloat) -> some View {
        let diameter = size * 5 / 22 * (status == .triggered ? 1.25 : 1)
        return Circle()
            .fill(.white)
            .frame(width: diameter, height: diameter)
            .scaleEffect(x: 1, y: blinking ? 0.1 : openness)
            .offset(
                x: size * centreX - diameter / 2 + gaze.width,
                y: size * 9.5 / 22 - diameter / 2 + gaze.height
            )
    }

    private var openness: CGFloat {
        status == .disarmed ? 0.55 : 1
    }

    private func live() async {
        gaze = .zero
        guard !reduceMotion else { return }
        let reach = size * 0.07
        let pause: ClosedRange<Int> = switch status {
        case .triggered: 250...700
        case .armed, .arming: 900...2_600
        case .disarmed: 2_000...5_000
        }

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int.random(in: pause)))
            guard !Task.isCancelled else { return }

            if Double.random(in: 0..<1) < 0.3 {
                withAnimation(.easeIn(duration: 0.07)) { blinking = true }
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.easeOut(duration: 0.12)) { blinking = false }
            } else {
                // Mostly glance sideways, the way something watching a room does.
                let target = CGSize(
                    width: .random(in: -reach...reach),
                    height: .random(in: -reach * 0.5...reach * 0.5)
                )
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { gaze = target }
            }
        }
    }
}
