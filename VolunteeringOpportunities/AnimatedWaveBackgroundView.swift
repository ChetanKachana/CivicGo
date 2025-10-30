import SwiftUI

struct AnimatedWaveBackgroundView: View {
    let startTime: Date
    let endTime: Date
    let baseColor: Color

    let waveBaseOpacity: Double = 0.25
    let solidBackgroundOpacity: Double = 0.08
    let minAmplitude: Double = 5.0
    let maxAmplitude: Double = 25.0
    let animationSpeed: Double = 0.015

    @State private var phase: Double = 0.0

    @State private var timer: Timer? = nil

    private var currentProgress: Double {
        let now = Date()
        guard endTime > startTime else { return 0.0 }
        let totalDuration = endTime.timeIntervalSince(startTime)
        let elapsedDuration = max(0.0, now.timeIntervalSince(startTime))
        let progress = min(1.0, elapsedDuration / totalDuration)
        return progress
    }

    private var currentAmplitude: Double {
        let amplitudeRange = maxAmplitude - minAmplitude
        return minAmplitude + (amplitudeRange * currentProgress)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: false)) { timelineContext in
            ZStack {
                baseColor.opacity(solidBackgroundOpacity)

                WaveShape(frequency: 1.5, amplitude: currentAmplitude * 0.6, phase: phase, progress: currentProgress)
                    .fill(baseColor.opacity(waveBaseOpacity * 0.6))

                WaveShape(frequency: 1.2, amplitude: currentAmplitude * 1.0, phase: phase + 0.3, progress: currentProgress)
                    .fill(baseColor.opacity(waveBaseOpacity * 0.8))

                WaveShape(frequency: 1.8, amplitude: currentAmplitude * 0.8, phase: phase + 0.6, progress: currentProgress)
                    .fill(baseColor.opacity(waveBaseOpacity * 1.0))
            }
            .clipped()
        }
        .onAppear(perform: startPhaseAnimation)
        .onDisappear(perform: stopPhaseAnimation)
        .drawingGroup()
    }

    // MARK: - Animation Control (for horizontal phase only)
    private func startPhaseAnimation() {
        stopPhaseAnimation()
        print("Starting Wave Phase Animation")
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            phase += animationSpeed
        }
    }

    private func stopPhaseAnimation() {
        print("Stopping Wave Phase Animation")
        timer?.invalidate()
        timer = nil
    }
}
