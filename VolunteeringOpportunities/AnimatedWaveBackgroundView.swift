import SwiftUI

struct AnimatedWaveBackgroundView: View {
    // Input: Event start and end times
    let startTime: Date
    let endTime: Date
    // Base color for waves AND solid background
    let baseColor: Color

    // Configuration
    // Adjust baseOpacity for the waves themselves if needed
    let waveBaseOpacity: Double = 0.25 // Slightly higher opacity for waves now maybe?
    let solidBackgroundOpacity: Double = 0.08 // Opacity for the solid base layer
    let minAmplitude: Double = 5.0
    let maxAmplitude: Double = 25.0
    let animationSpeed: Double = 0.015 // Horizontal phase speed

    // State for the animation phase
    @State private var phase: Double = 0.0

    // Timer to drive the phase animation
    @State private var timer: Timer? = nil

    // Calculate progress based on current time
    private var currentProgress: Double {
        let now = Date()
        guard endTime > startTime else { return 0.0 }
        let totalDuration = endTime.timeIntervalSince(startTime)
        // Ensure elapsedDuration doesn't go below zero if 'now' is before 'startTime'
        let elapsedDuration = max(0.0, now.timeIntervalSince(startTime))
        let progress = min(1.0, elapsedDuration / totalDuration)
        return progress
    }

    // Calculate dynamic amplitude based on progress
    private var currentAmplitude: Double {
        let amplitudeRange = maxAmplitude - minAmplitude
        return minAmplitude + (amplitudeRange * currentProgress)
    }

    var body: some View {
        // Use a TimelineView to drive updates for the progress calculation
        TimelineView(.animation(minimumInterval: 0.1, paused: false)) { timelineContext in
            ZStack {
                // --- ADDED: Solid Background Layer ---
                // Place this *first* in the ZStack so it's behind the waves
                baseColor.opacity(solidBackgroundOpacity)
                // --- END ADDED ---

                // --- Wave Layers ---
                // Draw waves on top of the solid color
                WaveShape(frequency: 1.5, amplitude: currentAmplitude * 0.6, phase: phase, progress: currentProgress)
                    .fill(baseColor.opacity(waveBaseOpacity * 0.6)) // Use waveBaseOpacity

                WaveShape(frequency: 1.2, amplitude: currentAmplitude * 1.0, phase: phase + 0.3, progress: currentProgress)
                    .fill(baseColor.opacity(waveBaseOpacity * 0.8)) // Use waveBaseOpacity

                WaveShape(frequency: 1.8, amplitude: currentAmplitude * 0.8, phase: phase + 0.6, progress: currentProgress)
                    .fill(baseColor.opacity(waveBaseOpacity * 1.0)) // Use waveBaseOpacity
                // --- End Wave Layers ---
            }
            .clipped() // Keep waves and background within the view bounds
        }
        // Start/Stop horizontal phase animation timer
        .onAppear(perform: startPhaseAnimation)
        .onDisappear(perform: stopPhaseAnimation)
        .drawingGroup() // Can help performance with complex drawing
    }

    // MARK: - Animation Control (for horizontal phase only)
    private func startPhaseAnimation() {
        stopPhaseAnimation() // Ensure no duplicate timers
        print("Starting Wave Phase Animation")
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            phase += animationSpeed // Only animate phase here
        }
    }

    private func stopPhaseAnimation() {
        print("Stopping Wave Phase Animation")
        timer?.invalidate()
        timer = nil
    }
}

